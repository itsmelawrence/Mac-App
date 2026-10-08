import Foundation
import Testing
@testable import JarvisDashboard

struct GitRepositoryServiceTests {
    @Test func parsesRepositoryStatusAndActivity() {
        let snapshot = GitRepositoryService.parseSnapshot(
            statusOutput: """
            ## main...origin/main [ahead 2, behind 1]
             M Sources/App.swift
            ?? Notes.md
            """,
            logOutput: "a1b2c3d\u{1f}Improve dashboard\u{1f}2026-10-05T09:30:00+08:00",
            countOutput: "12\n"
        )

        #expect(snapshot.branch == "main")
        #expect(snapshot.dirtyFileCount == 2)
        #expect(snapshot.lastCommitHash == "a1b2c3d")
        #expect(snapshot.lastCommitMessage == "Improve dashboard")
        #expect(snapshot.lastCommitDate != nil)
        #expect(snapshot.commitsInLast30Days == 12)
        #expect(snapshot.aheadCount == 2)
        #expect(snapshot.behindCount == 1)
    }

    @Test func evaluatesOngoingProjectHealthFromActivity() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = RepositorySnapshot(
            branch: "main",
            dirtyFileCount: 0,
            lastCommitHash: "abc123",
            lastCommitMessage: "Update",
            lastCommitDate: calendar.date(byAdding: .day, value: -3, to: now),
            commitsInLast30Days: 4,
            aheadCount: 0,
            behindCount: 0
        )
        let stale = RepositorySnapshot(
            branch: "main",
            dirtyFileCount: 0,
            lastCommitHash: "def456",
            lastCommitMessage: "Older update",
            lastCommitDate: calendar.date(byAdding: .day, value: -20, to: now),
            commitsInLast30Days: 0,
            aheadCount: 0,
            behindCount: 0
        )

        #expect(RepositoryHealth.evaluate(status: .active, dueDate: nil, snapshot: recent, now: now, calendar: calendar) == .healthy)
        #expect(RepositoryHealth.evaluate(status: .active, dueDate: nil, snapshot: stale, now: now, calendar: calendar) == .attention)
        #expect(RepositoryHealth.evaluate(status: .onHold, dueDate: nil, snapshot: recent, now: now, calendar: calendar) == .blocked)
        #expect(RepositoryHealth.evaluate(status: .active, dueDate: nil, snapshot: nil, now: now, calendar: calendar) == .setupNeeded)
    }
}
