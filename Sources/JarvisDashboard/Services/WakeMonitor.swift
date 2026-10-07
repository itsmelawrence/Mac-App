import AppKit
import Foundation

@MainActor
final class WakeMonitor: ObservableObject {
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lastSleepDate: Date?
    private var onWake: ((TimeInterval) -> Void)?

    func start(onWake: @escaping (TimeInterval) -> Void) {
        guard sleepObserver == nil, wakeObserver == nil else { return }
        self.onWake = onWake

        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lastSleepDate = .now }
        }

        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let duration = self.lastSleepDate.map { Date.now.timeIntervalSince($0) } ?? 0
                self.onWake?(duration)
                self.lastSleepDate = nil
            }
        }
    }

    deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
