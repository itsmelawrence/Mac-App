import Foundation
import SwiftData
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

/// An app action (tasks) the gate has allowed, queued for JARVIS to perform.
struct AppJob: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let action: String
    let args: [String: String?]
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
    private let clearNotifications: ([String]) -> Void
    private let reminders: TaskReminderScheduling
    private var lastStamp = ""
    private var lastRefresh = Date.distantPast
    private var announced: Set<String> = []
    private var context: ModelContext?
    private var isRunningJobs = false

    init(
        vaultURL: @escaping () -> URL = {
            ICMRoutingService.vaultURL(configuredPath: UserDefaults.standard.string(forKey: "icm.vaultPath") ?? "")
        },
        stateURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JARVIS Dashboard"),
        notify: @escaping (PendingAction) -> Void = ActionCenter.postNotification,
        clearNotifications: @escaping ([String]) -> Void = {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: $0)
        },
        reminders: TaskReminderScheduling = NotificationService()
    ) {
        self.vaultURL = vaultURL
        self.stateURL = stateURL
        self.notify = notify
        self.clearNotifications = clearNotifications
        self.reminders = reminders
    }

    /// App actions (tasks) are performed in this context; without one they wait in the queue.
    func attach(_ context: ModelContext) {
        self.context = context
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
        struct State: Decodable { let pending: [PendingAction]; let jobs: [AppJob]; let recent: [ActionRecord] }
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
            if !state.jobs.isEmpty { await runJobs(state.jobs) }
            let open = Set(state.pending.map(\.id))
            let decided = announced.subtracting(open)
            if !decided.isEmpty {
                clearNotifications(decided.map { "action-\($0)" })
            }
        case let .failure(error):
            message = error.localizedDescription
        }
    }

    func approve(_ id: String) async { await decide("approve", id) }
    func deny(_ id: String) async { await decide("deny", id) }
    func undo(_ id: String) async { await decide("undo", id) }

    private struct Reply: Decodable {
        let status: String
        let reason: String?
        let action: String?
        let args: [String: String?]?
        let result: [String: String]?
    }

    private func gate(_ arguments: [String], input: String? = nil) async -> Result<Reply, Error> {
        let script = Self.scriptURL(vaultURL: vaultURL())
        let vault = vaultURL()
        return await Task.detached(priority: .userInitiated) {
            Result { try VaultMaintenanceService.runJSON(script: script, arguments: arguments + ["--vault", vault.path],
                                                         input: input, as: Reply.self) }
        }.value
    }

    private func decide(_ command: String, _ id: String) async {
        busy.insert(id)
        defer { busy.remove(id) }
        switch await gate([command, id]) {
        case let .success(reply) where reply.status == "run_in_app" && command == "undo":
            message = await reverseInApp(id, reply)
        case let .success(reply):
            message = Self.describe(command: command, reply.status, reply.reason)
        case let .failure(error):
            message = error.localizedDescription
        }
        await refresh()
    }

    /// Claims each queued app job from the gate, performs it on JARVIS's data, and reports the outcome.
    private func runJobs(_ jobs: [AppJob]) async {
        guard let context, !isRunningJobs else { return }
        isRunningJobs = true
        defer { isRunningJobs = false }
        for job in jobs {
            guard case let .success(claim) = await gate(["start", job.id]), claim.status == "run_in_app",
                  let action = claim.action, let args = claim.args else { continue }
            let (outcome, detail): (String, [String: String])
            switch AppActionExecutor.perform(action, args: args, context: context, reminders: reminders) {
            case let .success(result): (outcome, detail) = ("done", result)
            case let .failure(failure): (outcome, detail) = ("failed", ["reason": failure.reason])
            }
            let input = String(data: (try? JSONEncoder().encode(detail)) ?? Data("{}".utf8), encoding: .utf8)
            _ = await gate(["finish", job.id, outcome], input: input)
        }
    }

    private func reverseInApp(_ id: String, _ reply: Reply) async -> String {
        guard let context, let action = reply.action else { return "Not done: JARVIS's data isn't open yet." }
        switch AppActionExecutor.reverse(action, result: reply.result ?? [:], context: context, reminders: reminders) {
        case .success:
            _ = await gate(["finish", id, "undone"], input: "{}")
            return "Undone."
        case let .failure(failure):
            return "Not done: \(failure.reason)"
        }
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
