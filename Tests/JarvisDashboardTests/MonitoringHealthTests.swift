import Foundation
import Testing
@testable import JarvisDashboard

struct MonitoringHealthTests {
    @Test func criticalFindingForcesCriticalState() {
        let site = makeSite(
            findings: [MonitoringFinding(
                id: "finding-1",
                componentType: "plugin",
                slug: "example",
                title: "Critical advisory",
                severity: "critical",
                fixedIn: "2.0",
                status: "open",
                referenceURL: nil
            )]
        )

        let health = MonitoringHealth.evaluate(site: site, now: referenceDate)

        #expect(health.state == .critical)
        #expect(health.score == 60)
    }

    @Test func oneOutdatedComponentScoresNinetyEight() {
        let site = makeSite(snapshot: MonitoringSnapshot(
            checkedAt: referenceDate,
            phpVersion: "8.4",
            phpSupported: true,
            pendingUpdateCount: 1,
            components: [],
            notCovered: [],
            siteHealth: [],
            applicationName: nil,
            applicationVersion: nil,
            environment: nil
        ))

        let health = MonitoringHealth.evaluate(site: site, now: referenceDate)

        #expect(health.state == .healthy)
        #expect(health.score == 98)
    }

    @Test func staleDataNeverAppearsHealthy() {
        let staleDate = referenceDate.addingTimeInterval(-49 * 60 * 60)
        let site = MonitoringSite(
            id: "site-1",
            name: "Site",
            url: "https://example.com",
            platform: .custom,
            status: .up,
            lastCheckAt: staleDate,
            lastHeartbeatAt: staleDate
        )

        let health = MonitoringHealth.evaluate(site: site, now: referenceDate)

        #expect(health.state == .stale)
        #expect(health.score == nil)
    }

    @Test func missingOutsideCheckRemainsUnscored() {
        let site = MonitoringSite(
            id: "site-1",
            name: "Site",
            url: "https://example.com",
            platform: .laravel,
            status: .unknown,
            lastHeartbeatAt: referenceDate,
            latestSnapshot: MonitoringSnapshot(
                checkedAt: referenceDate,
                phpVersion: "8.4",
                phpSupported: nil,
                pendingUpdateCount: 0,
                components: [],
                notCovered: [],
                siteHealth: [],
                applicationName: nil,
                applicationVersion: nil,
                environment: nil
            )
        )

        let health = MonitoringHealth.evaluate(site: site, now: referenceDate)

        #expect(health.state == .awaitingChecks)
        #expect(health.score == nil)
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func makeSite(
        snapshot: MonitoringSnapshot? = MonitoringSnapshot(
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000),
            phpVersion: "8.4",
            phpSupported: true,
            pendingUpdateCount: 0,
            components: [],
            notCovered: [],
            siteHealth: [],
            applicationName: nil,
            applicationVersion: nil,
            environment: nil
        ),
        findings: [MonitoringFinding] = []
    ) -> MonitoringSite {
        MonitoringSite(
            id: "site-1",
            name: "Site",
            url: "https://example.com",
            platform: .custom,
            status: .up,
            lastCheckAt: referenceDate,
            lastHeartbeatAt: referenceDate,
            openFindingsCount: findings.count,
            latestSnapshot: snapshot,
            findings: findings
        )
    }
}
