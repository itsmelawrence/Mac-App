import AppKit
import SwiftUI

/// What the assistant has done, and what is waiting for your approval (SAFETY.md in the vault).
struct ActivityView: View {
    @ObservedObject private var center = ActionCenter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity").font(.title2.bold())
                    Text("Changes the assistant asks to make wait here for you. Everything it does is logged and can be undone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = center.message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                if !center.jobs.isEmpty {
                    Text("Running now").font(.headline)
                    ForEach(center.jobs) { JobCard(job: $0) }
                }

                if !center.pending.isEmpty {
                    Text("Waiting for you").font(.headline)
                    ForEach(center.pending) { action in
                        ApprovalCard(action: action, isBusy: center.busy.contains(action.id),
                                     approve: { Task { await center.approve(action.id) } },
                                     deny: { Task { await center.deny(action.id) } })
                    }
                }

                Text("Recent actions").font(.headline)
                if center.recent.isEmpty {
                    Text("Nothing yet. When the assistant adds or changes something, it appears here.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(center.recent) { record in
                            ActionRow(record: record, isBusy: center.busy.contains(record.id)) {
                                Task { await center.undo(record.id) }
                            }
                            Divider().opacity(0.4)
                        }
                    }
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .task {
            center.refreshJobs()
            await center.refresh()
        }
    }
}

private struct JobCard: View {
    let job: BackgroundJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(job.title).font(.body.weight(.semibold))
                Spacer()
                Text(statusLabel).font(.caption.weight(.semibold)).foregroundStyle(tint)
            }
            if let fraction = job.fraction {
                ProgressView(value: fraction).tint(tint)
            }
            HStack {
                if let total = job.total { Text("\(job.done) of \(total)") }
                Text(job.isRunning ? "started \(job.startedAt, style: .relative) ago" : "ended \(job.updatedAt, style: .relative) ago")
                Spacer()
                if let log = job.log, FileManager.default.fileExists(atPath: log) {
                    Button("Open log") { NSWorkspace.shared.open(URL(fileURLWithPath: log)) }
                        .buttonStyle(.link).font(.caption)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let detail = job.detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(14)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusLabel: String {
        if job.isStopped { return "Stopped" }
        switch job.status {
        case "running": return "Running"
        case "done": return "Done"
        case "failed": return "Failed"
        default: return job.status.capitalized
        }
    }

    private var symbol: String {
        if job.isStopped { return "stop.circle" }
        switch job.status {
        case "running": return "gearshape.2"
        case "done": return "checkmark.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        if job.isStopped { return .secondary }
        switch job.status {
        case "running": return .cyan
        case "done": return .green
        default: return .red
        }
    }
}

private struct ApprovalCard: View {
    let action: PendingAction
    let isBusy: Bool
    let approve: () -> Void
    let deny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(tierLabel(action.tier))
                    .font(.caption2.weight(.bold)).tracking(0.6)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                Text(action.summary).font(.body.weight(.semibold))
                Spacer()
                Text("expires \(action.expiresAt, style: .relative)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Requested by \(action.client ?? "the assistant") \(action.requestedAt, style: .relative) ago")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(action.preview.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(String(line)).foregroundStyle(colour(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
            }
            .frame(maxHeight: 240)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
                Button("Deny", role: .cancel, action: deny).disabled(isBusy)
                Button("Approve", action: approve)
                    .buttonStyle(.borderedProminent).tint(.green).disabled(isBusy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.35)))
    }

    private func colour(for line: Substring) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return .cyan }
        return .primary
    }
}

private struct ActionRow: View {
    let record: ActionRecord
    let isBusy: Bool
    let undo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.summary ?? record.action ?? record.id).font(.callout.weight(.medium))
                Text([statusLabel, record.tier.map(tierLabel), record.client].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if let reason = record.reason, record.status == "refused" || record.status == "failed" {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(record.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
            if record.canUndo {
                Button("Undo", action: undo).disabled(isBusy)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var statusLabel: String {
        switch record.status {
        case "done": record.approvedBy == nil ? "Done" : "Approved and done"
        case "awaiting_approval": "Waiting for approval"
        case "queued": "Queued for JARVIS"
        case "running": "Running"
        case "failed": "Failed"
        case "denied": "Denied"
        case "expired": "Expired"
        case "refused": "Refused"
        case "undone": "Undone"
        default: record.status
        }
    }

    private var symbol: String {
        switch record.status {
        case "done": "checkmark.circle.fill"
        case "awaiting_approval", "queued", "running": "hourglass"
        case "failed": "exclamationmark.triangle.fill"
        case "refused": "hand.raised.fill"
        case "undone": "arrow.uturn.backward.circle"
        default: "xmark.circle"
        }
    }

    private var tint: Color {
        switch record.status {
        case "done": .green
        case "awaiting_approval", "queued", "running": .orange
        case "refused", "failed": .red
        default: .secondary
        }
    }
}

private func tierLabel(_ tier: Int) -> String {
    switch tier {
    case 1: "TIER 1 · ADD"
    case 2: "TIER 2 · CHANGE"
    case 3: "TIER 3 · OUTWARD"
    default: "TIER \(tier)"
    }
}
