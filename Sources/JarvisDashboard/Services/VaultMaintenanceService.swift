import Foundation

/// Runs the vault's `.tools/vault_maintenance.py` (hub refresh, then the vault doctor) on a schedule.
///
/// It runs from JARVIS rather than a LaunchAgent because macOS will not let launchd jobs
/// list folders in ~/Documents. A child process shares JARVIS's access to the vault.
enum VaultMaintenanceService {
    static let interval: TimeInterval = 3 * 60 * 60
    static let lastRunKey = "vaultMaintenance.lastRunAt"

    /// The tools folder sits beside the Projects vault: `<vault>/../.tools`.
    static func scriptURL(vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent(".tools/vault_maintenance.py")
    }

    static func isDue(lastRun: Date?, now: Date = .now) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= interval || lastRun > now
    }

    /// Runs the script and returns its exit status and combined output. Blocks; call off the main actor.
    static func run(script: URL, arguments: [String] = [], python: URL = URL(fileURLWithPath: "/usr/bin/python3")) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = python
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PYTHONDONTWRITEBYTECODE": "1"
        ]) { _, enforcedValue in enforcedValue }
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Checks every 15 minutes and runs when the last run is older than `interval`.
    static func runWhileAppIsOpen(defaults: UserDefaults = .standard) async {
        while !Task.isCancelled {
            if isDue(lastRun: defaults.object(forKey: lastRunKey) as? Date) {
                let vault = ICMRoutingService.vaultURL(configuredPath: defaults.string(forKey: "icm.vaultPath") ?? "")
                let script = scriptURL(vaultURL: vault)
                if FileManager.default.fileExists(atPath: script.path) {
                    let result = await Task.detached(priority: .background) { try? run(script: script, arguments: ["--vault", vault.path]) }.value
                    log(result.map { "exit \($0.status)\n\($0.output)" } ?? "could not start /usr/bin/python3\n")
                    defaults.set(Date.now, forKey: lastRunKey)
                }
            }
            try? await Task.sleep(for: .seconds(15 * 60))
        }
    }

    private static func log(_ text: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/vault-maintenance.log")
        let entry = "--- \(Date.now.formatted(.iso8601)) JARVIS\n\(text)"
        guard let data = entry.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
