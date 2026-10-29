import Foundation
import UserNotifications

/// An assistant action waiting for your decision (Tier 2 or 3; see the vault's SAFETY.md).
struct PendingAction: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let action: String
    let tier: Int
    let client: String?
    let summary: String
    let preview: String
    let requestedAt: Date
    let expiresAt: Date
}

/// One assistant action from the append-only action log, folded to its latest state.
struct ActionRecord: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let action: String?
    let tier: Int?
    let client: String?
    let summary: String?
    let status: String
    let reason: String?
    let path: String?
    let undo: Bool?
    let approvedBy: String?
    let requestedAt: Date
    let updatedAt: Date

    var canUndo: Bool { status == "done" && undo == true }
}

/// Watches the vault tools' action gate (`.tools/actions.py`) and carries out your decisions.
///
/// The gate holds the rules; JARVIS only shows what is pending and calls `approve`, `deny`, or `undo`.
/// Approving runs the action from JARVIS itself, so it happens even if the chat has moved on.
@MainActor
final class ActionCenter: ObservableObject {
    static let shared = ActionCenter()

    @Published private(set) var pending: [PendingAction] = []
    @Published private(set) var recent: [ActionRecord] = []
    @Published private(set) var message: String?
    @Published private(set) var busy: Set<String> = []

    private let vaultURL: () -> URL
    private let stateURL: URL
    private let notify: (PendingAction) -> Void
    private var lastStamp = ""
    private var lastRefresh = Date.distantPast
    private var announced: Set<String> = []

    init(
        vaultURL: @escaping () -> URL = {
            ICMRoutingService.vaultURL(configuredPath: UserDefaults.standard.string(forKey: "icm.vaultPath") ?? "")
        },
        stateURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JARVIS Dashboard"),
        notify: @escaping (PendingAction) -> Void = ActionCenter.postNotification
    ) {
        self.vaultURL = vaultURL
        self.stateURL = stateURL
        self.notify = notify
    }

    static func scriptURL(vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent(".tools/actions.py")
    }

    /// Checks for changes every 2 seconds for the app's lifetime (the coordinator starts it).
    func run() async {
        while !Task.isCancelled {
            await refreshIfChanged()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Reads the gate's state when the log or the approvals folder changed, and at least every 30 seconds
    /// so expiries show up. Cheap otherwise: two stats.
    func refreshIfChanged() async {
        let stamp = Self.stamp(stateURL)
        guard stamp != lastStamp || Date.now.timeIntervalSince(lastRefresh) > 30 else { return }
        lastStamp = stamp
        await refresh()
    }

    func refresh() async {
        struct State: Decodable { let pending: [PendingAction]; let recent: [ActionRecord] }
        lastRefresh = .now
        let script = Self.scriptURL(vaultURL: vaultURL())
        guard FileManager.default.fileExists(atPath: script.path) else { return }
        let vault = vaultURL()
        let result = await Task.detached(priority: .utility) {
            Result { try VaultMaintenanceService.runJSON(script: script, arguments: ["state", "--vault", vault.path, "--limit", "100"],
                                                         decoder: Self.decoder, as: State.self) }
        }.value
        switch result {
        case let .success(state):
            pending = state.pending
            recent = state.recent
            for action in state.pending where !announced.contains(action.id) {
                announced.insert(action.id)
                notify(action)
            }
            let open = Set(state.pending.map(\.id))
            let decided = announced.subtracting(open)
            if !decided.isEmpty {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: decided.map { "action-\($0)" })
            }
        case let .failure(error):
            message = error.localizedDescription
        }
    }

    func approve(_ id: String) async { await decide("approve", id) }
    func deny(_ id: String) async { await decide("deny", id) }
    func undo(_ id: String) async { await decide("undo", id) }

    private func decide(_ command: String, _ id: String) async {
        struct Reply: Decodable { let status: String; let reason: String? }
        busy.insert(id)
        defer { busy.remove(id) }
        let script = Self.scriptURL(vaultURL: vaultURL())
        let vault = vaultURL()
        let result = await Task.detached(priority: .userInitiated) {
            Result { try VaultMaintenanceService.runJSON(script: script, arguments: [command, id, "--vault", vault.path], as: Reply.self) }
        }.value
        switch result {
        case let .success(reply):
            message = Self.describe(command: command, reply.status, reply.reason)
        case let .failure(error):
            message = error.localizedDescription
        }
        await refresh()
    }

    static func describe(command: String, _ status: String, _ reason: String?) -> String {
        switch (command, status) {
        case ("approve", "done"): "Approved and applied."
        case ("deny", "denied"): "Denied. Nothing changed."
        case ("undo", "undone"): "Undone."
        case (_, "expired"): "That request had expired. Nothing changed."
        default: reason.map { "Not done: \($0)" } ?? "Not done (\(status))."
        }
    }

    nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private nonisolated static func stamp(_ root: URL) -> String {
        let manager = FileManager.default
        let log = (try? manager.attributesOfItem(atPath: root.appendingPathComponent("actions.jsonl").path))?[.modificationDate] as? Date
        let approvals = (try? manager.contentsOfDirectory(atPath: root.appendingPathComponent("approvals").path)) ?? []
        return "\(log?.timeIntervalSince1970 ?? 0)|\(approvals.sorted().joined(separator: ","))"
    }

    nonisolated static func postNotification(_ action: PendingAction) {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = "JARVIS needs your approval"
            content.body = "\(action.summary). Review it in Activity or the menu bar."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "action-\(action.id)", content: content, trigger: nil))
        }
    }
}
