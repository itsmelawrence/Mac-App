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
    /// A run longer than `timeout` is terminated, so a hung script (e.g. a stalled network
    /// folder) cannot block the caller's loop forever. `input` is sent on standard input, which
    /// keeps text such as prompts out of the process list.
    static func run(
        script: URL, arguments: [String] = [], timeout: TimeInterval = 600, input: Data? = nil,
        python: URL = URL(fileURLWithPath: "/usr/bin/python3")
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = python
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PYTHONDONTWRITEBYTECODE": "1"
        ]) { _, enforcedValue in enforcedValue }
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = input == nil ? FileHandle.nullDevice : inputPipe
        try process.run()
        if let input {
            // Written from another thread: a reply larger than the pipe buffer must not deadlock the write.
            DispatchQueue.global().async {
                try? inputPipe.fileHandleForWriting.write(contentsOf: input)
                try? inputPipe.fileHandleForWriting.close()
            }
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Runs a vault script that prints a JSON reply on its last line, and decodes it. Blocks; call off the main actor.
    static func runJSON<Reply: Decodable>(
        script: URL, arguments: [String], input: String? = nil, timeout: TimeInterval = 60,
        decoder: JSONDecoder = JSONDecoder(), as type: Reply.Type
    ) throws -> Reply {
        let result = try run(script: script, arguments: arguments, timeout: timeout, input: input.map { Data($0.utf8) })
        let lastLine = result.output.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard result.status == 0, let lastLine, let reply = try? decoder.decode(Reply.self, from: Data(lastLine.utf8)) else {
            throw VaultScriptError(script: script.lastPathComponent, output: String(result.output.suffix(300)))
        }
        return reply
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

struct VaultScriptError: LocalizedError {
    let script: String
    let output: String
    var errorDescription: String? { "\(script) failed: \(output)" }
}
