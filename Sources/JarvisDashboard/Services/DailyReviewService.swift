import AppKit
import Foundation
import UserNotifications

/// One morning's review, as `.tools/daily_review.py` writes it to `daily-review.json` (roadmap 4.1).
struct DailyReview: Decodable, Equatable, Sendable {
    struct Counts: Decodable, Equatable, Sendable {
        let overdue: Int
        let dueToday: Int
        let sitesDown: Int
        let alerts: Int
        let unfinished: Int
        let proposals: Int
    }

    struct Proposal: Decodable, Equatable, Sendable {
        let id: String?
        let status: String?
        let summary: String
    }

    let date: String
    let generatedAt: Date
    let note: String
    let summary: [String]
    let summarySource: String
    let model: String?
    let fallbackReason: String?
    let counts: Counts
    let proposals: [Proposal]

    var sourceLine: String {
        if summarySource == "model", let model { return "Written by \(model) from today's facts" }
        return "Facts only" + (fallbackReason.map { ": \($0)" } ?? "")
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Runs the daily review once a day, the first time JARVIS is awake after 7:00, and keeps the latest for Today.
///
/// The script collects facts, asks the local model for a short summary (falling back to facts only), and
/// proposes actions through the gate. Proposals wait in Activity; this posts one notification for the lot.
@MainActor
final class DailyReviewService: ObservableObject {
    static let shared = DailyReviewService()
    nonisolated static let client = "daily-review"
    nonisolated static let hour = 7
    nonisolated static let lastRunKey = "dailyReview.lastRunDay"

    @Published private(set) var review: DailyReview?
    @Published private(set) var isRunning = false
    @Published private(set) var message: String?

    private let defaults: UserDefaults
    private let stateURL: URL
    private let vaultURL: () -> URL
    private let notify: (DailyReview) -> Void

    init(
        defaults: UserDefaults = .standard,
        stateURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JARVIS Dashboard"),
        vaultURL: @escaping () -> URL = {
            ICMRoutingService.vaultURL(configuredPath: UserDefaults.standard.string(forKey: "icm.vaultPath") ?? "")
        },
        notify: @escaping (DailyReview) -> Void = DailyReviewService.postNotification
    ) {
        self.defaults = defaults
        self.stateURL = stateURL
        self.vaultURL = vaultURL
        self.notify = notify
    }

    static func scriptURL(vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent(".tools/daily_review.py")
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Due from 7:00 on any day it hasn't run yet.
    static func isDue(lastRunDay: String?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: now) >= hour && lastRunDay != day(now, calendar: calendar)
    }

    /// Checks every 5 minutes for the app's lifetime, so a Mac that wakes after 7:00 catches up within minutes.
    func run() async {
        load()
        while !Task.isCancelled {
            if Self.isDue(lastRunDay: defaults.string(forKey: Self.lastRunKey)) {
                await runNow(announce: true)
            }
            try? await Task.sleep(for: .seconds(5 * 60))
        }
    }

    /// The latest review on disk, so Today shows it after a relaunch.
    func load() {
        guard let data = try? Data(contentsOf: stateURL.appendingPathComponent("daily-review.json")),
              let latest = try? DailyReview.decoder.decode(DailyReview.self, from: data) else { return }
        review = latest
    }

    func runNow(announce: Bool = false) async {
        guard !isRunning else { return }
        let vault = vaultURL()
        let script = Self.scriptURL(vaultURL: vault)
        guard FileManager.default.fileExists(atPath: script.path) else {
            message = "daily_review.py is missing from the vault's .tools folder"
            return
        }
        isRunning = true
        defer { isRunning = false }
        // Recorded before running, so a failing script is retried tomorrow (or by hand), not every 5 minutes.
        defaults.set(Self.day(.now), forKey: Self.lastRunKey)
        // The model can take a few minutes on this Mac; the script gives it up after 4.
        let result = await Task.detached(priority: .utility) {
            Result { try VaultMaintenanceService.runJSON(script: script, arguments: ["--vault", vault.path], timeout: 600,
                                                         decoder: DailyReview.decoder, as: DailyReview.self) }
        }.value
        switch result {
        case let .success(latest):
            review = latest
            message = nil
            if announce { notify(latest) }
        case let .failure(error):
            message = error.localizedDescription
        }
    }

    func openNote() {
        guard let review else { return }
        let file = vaultURL().appendingPathComponent(review.note)
        var components = URLComponents(string: "obsidian://open")
        components?.queryItems = [URLQueryItem(name: "path", value: file.path)]
        if let url = components?.url, NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    nonisolated static func postNotification(_ review: DailyReview) {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = "Daily review"
            let waiting = review.counts.proposals
            content.body = (review.summary.first ?? "Your daily review is ready.")
                + (waiting > 0 ? " \(waiting) suggestion\(waiting == 1 ? "" : "s") wait for your approval in Activity." : "")
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "daily-review-\(review.date)", content: content, trigger: nil))
        }
    }
}
