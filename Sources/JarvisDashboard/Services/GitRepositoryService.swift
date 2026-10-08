import Foundation

struct RepositorySnapshot: Equatable, Sendable {
    let branch: String
    let dirtyFileCount: Int
    let lastCommitHash: String
    let lastCommitMessage: String
    let lastCommitDate: Date?
    let commitsInLast30Days: Int
    let aheadCount: Int
    let behindCount: Int
}

struct RepositoryInspection: Sendable {
    let snapshot: RepositorySnapshot
    let refreshedBookmarkData: Data?
}

enum RepositoryHealth: String, Equatable, Sendable {
    case healthy
    case quiet
    case attention
    case blocked
    case setupNeeded

    var title: String {
        switch self {
        case .healthy: "Healthy"
        case .quiet: "Quiet"
        case .attention: "Needs Attention"
        case .blocked: "Blocked"
        case .setupNeeded: "Setup Needed"
        }
    }

    static func evaluate(
        status: ProjectStatus,
        dueDate: Date?,
        snapshot: RepositorySnapshot?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RepositoryHealth {
        if status == .onHold { return .blocked }

        if let dueDate,
           calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now),
           status != .completed,
           status != .archived {
            return .attention
        }

        guard let snapshot, let lastCommitDate = snapshot.lastCommitDate else {
            return .setupNeeded
        }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastCommitDate),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        if days <= 7 { return .healthy }
        if days <= 14 { return .quiet }
        return .attention
    }
}

enum GitRepositoryService {
    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func inspect(bookmarkData: Data) async throws -> RepositoryInspection {
        try await Task.detached(priority: .utility) {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            let refreshedBookmark = isStale ? try bookmark(for: url) : nil
            let statusOutput = try runGit(["status", "--porcelain=v1", "--branch"], at: url)
            let logOutput = try runGit(["log", "-1", "--format=%h%x1f%s%x1f%cI"], at: url)
            let countOutput = try runGit(["rev-list", "--count", "--since=30.days", "HEAD"], at: url)

            return RepositoryInspection(
                snapshot: parseSnapshot(
                    statusOutput: statusOutput,
                    logOutput: logOutput,
                    countOutput: countOutput
                ),
                refreshedBookmarkData: refreshedBookmark
            )
        }.value
    }

    static func parseSnapshot(
        statusOutput: String,
        logOutput: String,
        countOutput: String
    ) -> RepositorySnapshot {
        let statusLines = statusOutput.split(whereSeparator: \Character.isNewline).map(String.init)
        let header = statusLines.first(where: { $0.hasPrefix("## ") }) ?? "## HEAD"
        let tracking = String(header.dropFirst(3))
        let branch: String
        if let range = tracking.range(of: "...") {
            branch = String(tracking[..<range.lowerBound])
        } else if let range = tracking.range(of: " [") {
            branch = String(tracking[..<range.lowerBound])
        } else {
            branch = tracking
        }

        let logParts = logOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map(String.init)

        let dateString = logParts.count > 2 ? logParts[2] : ""
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lastCommitDate = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)

        return RepositorySnapshot(
            branch: branch,
            dirtyFileCount: statusLines.filter { !$0.hasPrefix("## ") }.count,
            lastCommitHash: logParts.first ?? "",
            lastCommitMessage: logParts.count > 1 ? logParts[1] : "No commits yet",
            lastCommitDate: lastCommitDate,
            commitsInLast30Days: Int(countOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            aheadCount: trackingCount(named: "ahead", in: header),
            behindCount: trackingCount(named: "behind", in: header)
        )
    }

    private static func trackingCount(named name: String, in header: String) -> Int {
        let pattern = "\\b\(name) ([0-9]+)"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: header,
                range: NSRange(header.startIndex..., in: header)
              ),
              let range = Range(match.range(at: 1), in: header)
        else { return 0 }
        return Int(header[range]) ?? 0
    }

    private static func runGit(_ arguments: [String], at url: URL) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-C", url.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0"
        ]) { _, enforcedValue in enforcedValue }
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw GitRepositoryError.gitUnavailable
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitRepositoryError.commandFailed(message ?? "The selected folder is not a readable Git repository.")
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

enum GitRepositoryError: LocalizedError {
    case gitUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "The local Git command is unavailable. Install Xcode Command Line Tools and try again."
        case let .commandFailed(message):
            message.isEmpty ? "The selected folder is not a readable Git repository." : message
        }
    }
}
