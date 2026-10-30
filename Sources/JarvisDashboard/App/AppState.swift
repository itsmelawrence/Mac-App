import Foundation

@MainActor
final class AppState: ObservableObject {
    enum BriefingReason: String {
        case manual
        case launch
        case wake
    }

    struct BriefingRequest: Identifiable, Equatable {
        let id = UUID()
        let reason: BriefingReason
        let message: String?
    }

    @Published var selection: SidebarDestination? = .today
    @Published private(set) var requestedProjectID: UUID?
    @Published private(set) var briefingRequest: BriefingRequest?

    @Published var showWakeBriefing: Bool {
        didSet { UserDefaults.standard.set(showWakeBriefing, forKey: Keys.showWakeBriefing) }
    }

    @Published var minimumSleepForBriefing: TimeInterval {
        didSet { UserDefaults.standard.set(minimumSleepForBriefing, forKey: Keys.minimumSleep) }
    }

    init() {
        let defaults = UserDefaults.standard
        showWakeBriefing = defaults.object(forKey: Keys.showWakeBriefing) as? Bool ?? true
        minimumSleepForBriefing = defaults.object(forKey: Keys.minimumSleep) as? TimeInterval ?? 15 * 60
    }

    func requestBriefing(reason: BriefingReason = .manual, message: String? = nil) {
        briefingRequest = BriefingRequest(reason: reason, message: message)
    }

    func consumeBriefingRequest(_ request: BriefingRequest) {
        guard briefingRequest?.id == request.id else { return }
        briefingRequest = nil
    }

    func openProject(_ projectID: UUID) {
        requestedProjectID = projectID
        selection = .projects
    }

    func consumeProjectRequest(_ projectID: UUID) {
        guard requestedProjectID == projectID else { return }
        requestedProjectID = nil
    }

    private enum Keys {
        static let showWakeBriefing = "showWakeBriefing"
        static let minimumSleep = "minimumSleepForBriefing"
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case today
    case tasks
    case projects
    case leads
    case connections
    case neuralMap
    case intelligence
    case activity
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .tasks: "Tasks"
        case .projects: "Projects"
        case .leads: "Leads"
        case .connections: "Cortex"
        case .neuralMap: "Neural Map"
        case .intelligence: "Intelligence"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sparkles"
        case .tasks: "checklist"
        case .projects: "square.stack.3d.up"
        case .leads: "tray.and.arrow.down"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .neuralMap: "brain"
        case .intelligence: "globe.asia.australia"
        case .activity: "checkmark.shield"
        case .settings: "gearshape"
        }
    }
}
