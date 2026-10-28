import Foundation
import Testing
@testable import JarvisDashboard

struct VaultMaintenanceServiceTests {
    @Test func scriptLivesInToolsFolderBesideTheVault() {
        let vault = URL(fileURLWithPath: "/Users/me/Documents/Main/Projects")
        #expect(VaultMaintenanceService.scriptURL(vaultURL: vault).path == "/Users/me/Documents/Main/.tools/vault_maintenance.py")
    }

    @Test func runsWhenNeverRunOldOrClockMovedBack() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(VaultMaintenanceService.isDue(lastRun: nil, now: now))
        #expect(!VaultMaintenanceService.isDue(lastRun: now.addingTimeInterval(-60), now: now))
        #expect(VaultMaintenanceService.isDue(lastRun: now.addingTimeInterval(-VaultMaintenanceService.interval), now: now))
        #expect(VaultMaintenanceService.isDue(lastRun: now.addingTimeInterval(3_600), now: now))
    }

    @Test func runReportsExitStatusAndCombinedOutput() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("maint-\(UUID().uuidString).py")
        defer { try? FileManager.default.removeItem(at: script) }
        try "import sys\nprint('hubs ok')\nprint('doctor failed', file=sys.stderr)\nsys.exit(3)\n"
            .write(to: script, atomically: true, encoding: .utf8)
        let result = try VaultMaintenanceService.run(script: script)
        #expect(result.status == 3)
        #expect(result.output.contains("hubs ok") && result.output.contains("doctor failed"))
    }
}
