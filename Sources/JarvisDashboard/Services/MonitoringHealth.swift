import Foundation
import SwiftUI

struct MonitoringHealth: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case healthy
        case needsAttention
        case critical
        case down
        case maintenance
        case stale
        case awaitingChecks
        case notConnected
    }

    struct Deduction: Equatable, Identifiable, Sendable {
        let id: String
        let points: Int
        let reason: String
    }

    let score: Int?
    let state: State
    let deductions: [Deduction]
    let lastObservedAt: Date?

    var label: String {
        switch state {
        case .healthy: "Healthy"
        case .needsAttention: "Needs attention"
        case .critical: "Critical"
        case .down: "Down"
        case .maintenance: "Maintenance"
        case .stale: "Stale"
        case .awaitingChecks: "Awaiting checks"
        case .notConnected: "Not connected"
        }
    }

    var colour: Color {
        switch state {
        case .healthy: Color(red: 0.24, green: 0.81, blue: 0.56)
        case .needsAttention, .maintenance: Color(red: 0.96, green: 0.65, blue: 0.14)
        case .critical, .down: Color(red: 0.94, green: 0.33, blue: 0.31)
        case .stale, .awaitingChecks, .notConnected: .secondary
        }
    }

    var sortRank: Int {
        switch state {
        case .down: 0
        case .critical: 1
        case .needsAttention: 2
        case .stale: 3
        case .awaitingChecks: 4
        case .maintenance: 5
        case .healthy: 6
        case .notConnected: 7
        }
    }

    var needsAttention: Bool {
        switch state {
        case .healthy, .maintenance, .notConnected: false
        default: true
        }
    }

    static func evaluate(site: MonitoringSite?, connected: Bool = false, now: Date = .now) -> MonitoringHealth {
        guard let site else {
            return MonitoringHealth(
                score: nil,
                state: connected ? .awaitingChecks : .notConnected,
                deductions: [],
                lastObservedAt: nil
            )
        }

        let observedAt = [site.lastCheckAt, site.lastHeartbeatAt, site.lastReportedAt, site.latestSnapshot?.checkedAt]
            .compactMap { $0 }
            .max()

        if let observedAt, now.timeIntervalSince(observedAt) > 48 * 60 * 60 {
            return MonitoringHealth(score: nil, state: .stale, deductions: [], lastObservedAt: observedAt)
        }
        if site.status == .maintenance {
            return MonitoringHealth(score: nil, state: .maintenance, deductions: [], lastObservedAt: observedAt)
        }
        if site.status == .down {
            return MonitoringHealth(score: 0, state: .down, deductions: [
                Deduction(id: "down", points: 100, reason: "Confirmed unreachable")
            ], lastObservedAt: observedAt)
        }

        var deductions: [Deduction] = []
        let openFindings = site.findings.filter { $0.status == "open" }
        for finding in openFindings {
            let points: Int
            switch finding.severity.lowercased() {
            case "critical": points = 40
            case "high": points = 20
            case "medium": points = 8
            default: points = 0
            }
            if points > 0 {
                deductions.append(Deduction(
                    id: "finding:\(finding.id)",
                    points: points,
                    reason: "\(finding.severity.capitalized): \(finding.title)"
                ))
            }
        }

        if let snapshot = site.latestSnapshot {
            let outdated = max(
                snapshot.pendingUpdateCount,
                snapshot.components.filter { $0.updateAvailable == true }.count
            )
            if outdated > 0 {
                deductions.append(Deduction(
                    id: "updates",
                    points: min(outdated * 2, 20),
                    reason: "\(outdated) component update\(outdated == 1 ? "" : "s") available"
                ))
            }
            if snapshot.phpSupported == false {
                deductions.append(Deduction(id: "php", points: 15, reason: "PHP version is end-of-life"))
            }
            let failedHealthChecks = snapshot.siteHealth.filter {
                ["critical", "fail", "failed", "error"].contains($0.status.lowercased())
            }
            if !failedHealthChecks.isEmpty {
                deductions.append(Deduction(
                    id: "site-health",
                    points: min(failedHealthChecks.count * 10, 20),
                    reason: "\(failedHealthChecks.count) critical application health check\(failedHealthChecks.count == 1 ? "" : "s")"
                ))
            }
        }

        if let expiry = site.sslExpiresAt {
            if expiry <= now {
                // Browsers already reject the site, so weigh it like a critical finding.
                deductions.append(Deduction(id: "ssl", points: 40, reason: "SSL certificate has expired"))
            } else if expiry.timeIntervalSince(now) <= 14 * 24 * 60 * 60 {
                deductions.append(Deduction(id: "ssl", points: 15, reason: "SSL certificate expires within 14 days"))
            }
        }

        if [.up, .degraded].contains(site.status),
           let heartbeat = site.lastHeartbeatAt,
           now.timeIntervalSince(heartbeat) > 15 * 60 {
            deductions.append(Deduction(id: "heartbeat", points: 15, reason: "Reporter heartbeat is missing"))
        }

        // The list response can expose a count before detailed findings are loaded. Do not
        // silently call them safe; reserve a medium deduction until their severities arrive.
        let unexpandedFindings = max(site.openFindingsCount - openFindings.count, 0)
        if unexpandedFindings > 0 {
            deductions.append(Deduction(
                id: "unexpanded-findings",
                points: min(unexpandedFindings * 8, 40),
                reason: "\(unexpandedFindings) open finding\(unexpandedFindings == 1 ? "" : "s") awaiting detail"
            ))
        }

        let score = max(0, 100 - deductions.reduce(0) { $0 + $1.points })
        let hasCriticalFinding = openFindings.contains { $0.severity.lowercased() == "critical" }
        let state: State
        if hasCriticalFinding {
            state = .critical
        } else if site.status == .unknown || site.lastCheckAt == nil {
            state = .awaitingChecks
        } else if score < 50 {
            state = .critical
        } else if score < 80 || site.status == .degraded {
            state = .needsAttention
        } else {
            state = .healthy
        }

        return MonitoringHealth(
            score: state == .awaitingChecks ? nil : score,
            state: state,
            deductions: deductions,
            lastObservedAt: observedAt
        )
    }
}
