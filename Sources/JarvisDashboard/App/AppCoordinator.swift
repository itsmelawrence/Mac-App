import Combine
import Foundation
import SwiftData

/// App-lifetime work that must not depend on a window: JARVIS keeps running from the
/// menu bar with its dashboard closed, and a second dashboard window must not double it.
@MainActor
final class AppCoordinator {
    private let appState: AppState
    private let wakeMonitor: WakeMonitor
    private let backupCoordinator: BackupCoordinator
    private let container: ModelContainer
    private let presentBriefing: @MainActor (AppState.BriefingReason, String?) -> Void
    private var briefingSubscription: AnyCancellable?
    private var tasks: [Task<Void, Never>] = []

    init(
        appState: AppState,
        wakeMonitor: WakeMonitor,
        backupCoordinator: BackupCoordinator,
        container: ModelContainer,
        presentBriefing: @escaping @MainActor (AppState.BriefingReason, String?) -> Void = { reason, message in
            BriefingPanelController.shared.show(reason: reason, message: message)
        }
    ) {
        self.appState = appState
        self.wakeMonitor = wakeMonitor
        self.backupCoordinator = backupCoordinator
        self.container = container
        self.presentBriefing = presentBriefing
    }

    /// Idempotent; called once at launch.
    func start(runBackgroundJobs: Bool = true) {
        guard briefingSubscription == nil else { return }

        // One subscriber for the whole app, so each request is presented exactly once.
        briefingSubscription = appState.$briefingRequest
            .compactMap { $0 }
            // @Published emits in willSet; deliver after the value is stored so consume can clear it.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                guard let self else { return }
                presentBriefing(request.reason, request.message)
                appState.consumeBriefingRequest(request)
            }

        wakeMonitor.start { [weak self] sleepDuration in
            SiteMonitor.shared.checkAfterWake()
            LeadMonitor.shared.syncAfterWake()
            IntelligenceFeed.shared.refreshAfterWake()
            guard let self,
                  appState.showWakeBriefing,
                  sleepDuration >= appState.minimumSleepForBriefing else { return }
            appState.requestBriefing(reason: .wake)
        }

        guard runBackgroundJobs else { return }
        let context = container.mainContext
        let backups = backupCoordinator
        tasks.append(Task { await backups.runAutomaticBackups(context: context) })
        tasks.append(Task.detached(priority: .background) { await VaultMaintenanceService.runWhileAppIsOpen() })
        tasks.append(Task.detached(priority: .utility) { await PromptCaptureService.runWhileAppIsOpen() })

        // Website up/down checks, every 5 minutes with the window closed too.
        SiteMonitor.shared.attach(context)
        tasks.append(Task { await SiteMonitor.shared.run() })

        // Weather, earthquakes, and news every 30 minutes, so alerts and state.json stay current with the window closed.
        IntelligenceFeed.shared.attach(context)
        tasks.append(Task { await IntelligenceFeed.shared.run() })

        // Contact-form leads from the portfolio sites, hourly with the window closed too.
        tasks.append(Task { await LeadMonitor.shared.run() })

        // The morning review (roadmap 4.1): once a day after 7:00; its proposals wait in Activity.
        tasks.append(Task { await DailyReviewService.shared.run() })

        // The action gate's approvals and log, watched for the app's lifetime so approvals reach you
        // (notification and menu bar) with the window closed.
        ActionCenter.shared.attach(context)
        tasks.append(Task { await ActionCenter.shared.run() })

        // The assistant's state.json: tasks and projects on launch, on every save, and each minute
        // (so overdue and due-today flags stay current). SiteMonitor adds sites; IntelligenceFeed adds weather, quakes, and news.
        let snapshots = StateSnapshotService.shared
        snapshots.refreshStore(context: context)
        tasks.append(Task {
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                snapshots.refreshStore(context: context)
            }
        })
        tasks.append(Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                snapshots.refreshStore(context: context)
            }
        })
    }
}
