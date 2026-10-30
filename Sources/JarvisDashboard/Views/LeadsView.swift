import AppKit
import SwiftData
import SwiftUI

/// Contact-form leads from each portfolio site, one tab per site.
struct LeadsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var monitor = LeadMonitor.shared
    @AppStorage("leads.selectedSource") private var selectedSourceRaw = ""
    @AppStorage("settings.tab") private var settingsTab = SettingsTab.general.rawValue
    @State private var selectedLeadID: Lead.ID?
    @State private var notice: String?

    private var selectedSource: LeadSource? {
        monitor.sources.first { $0.id.uuidString == selectedSourceRaw } ?? monitor.sources.first
    }
    private var leads: [Lead] { selectedSource.map { monitor.leads(for: $0.id) } ?? [] }
    private var selectedLead: Lead? { leads.first { $0.id == selectedLeadID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Leads").font(.title2.bold())
                Text("Contact-form submissions from your sites, checked every 10 minutes while JARVIS is open.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let source = selectedSource {
                if monitor.sources.count > 1 { sourcePicker }
                statusLine(for: source)
                HStack(alignment: .top, spacing: 0) {
                    leadList.frame(width: 340)
                    Divider()
                    detail(source: source).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ContentUnavailableView {
                    Label("No sites connected", systemImage: "tray.and.arrow.down")
                } description: {
                    Text("Add each site's leads feed address and token in Settings → Connections.")
                } actions: {
                    Button("Open Settings") {
                        settingsTab = SettingsTab.connections.rawValue
                        appState.selection = .settings
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: selectedLeadID) { _, id in
            notice = nil
            if let lead = leads.first(where: { $0.id == id }) { monitor.setRead(lead, true) }
        }
        .onChange(of: selectedSourceRaw) { selectedLeadID = nil }
    }

    private var sourcePicker: some View {
        Picker("Site", selection: Binding(
            get: { selectedSource?.id.uuidString ?? "" },
            set: { selectedSourceRaw = $0 }
        )) {
            ForEach(monitor.sources) { source in
                let unread = monitor.unreadCount(for: source.id)
                Text(unread > 0 ? "\(source.name) · \(unread)" : source.name).tag(source.id.uuidString)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 460)
    }

    private func statusLine(for source: LeadSource) -> some View {
        let isSyncing = monitor.syncingIDs.contains(source.id)
        return HStack(spacing: 10) {
            if isSyncing {
                ProgressView().controlSize(.small)
                Text("Checking for leads…")
            } else if let error = monitor.errors[source.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if let syncedAt = monitor.lastSyncAt[source.id] {
                Text("Checked \(syncedAt, style: .relative) ago")
            } else {
                Text("Not checked yet")
            }
            Spacer()
            if monitor.unreadCount(for: source.id) > 0 {
                Button("Mark all read") { monitor.markAllRead(in: source.id) }
            }
            Button {
                Task { await monitor.sync(source.id) }
            } label: {
                Label("Check now", systemImage: "arrow.clockwise")
            }
            .disabled(isSyncing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var leadList: some View {
        List(leads, selection: $selectedLeadID) { lead in
            LeadRow(lead: lead).tag(lead.id)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if leads.isEmpty {
                Text("No leads yet.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func detail(source: LeadSource) -> some View {
        if let lead = selectedLead {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lead.name.isEmpty ? "No name given" : lead.name).font(.title3.bold())
                        Text(lead.email).textSelection(.enabled)
                        Text(lead.submittedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button {
                            reply(to: lead, from: source)
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(lead.email.isEmpty)
                        Button("Copy email") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(lead.email, forType: .string)
                            notice = "Email copied."
                        }
                        .disabled(lead.email.isEmpty)
                        Button("Create follow-up task") { createTask(for: lead, from: source) }
                        Button("Mark unread") { monitor.setRead(lead, false) }
                            .disabled(lead.isUnread)
                    }

                    if let notice {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                    }

                    let facts = Self.facts(for: lead)
                    if !facts.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                            ForEach(facts, id: \.label) { fact in
                                GridRow {
                                    Text(fact.label).foregroundStyle(.secondary)
                                    Text(fact.value).textSelection(.enabled)
                                }
                            }
                        }
                        .font(.callout)
                    }

                    Divider()
                    Text(lead.message.isEmpty ? "No message." : lead.message)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView("Select a lead", systemImage: "tray",
                                   description: Text("Its message and contact details appear here."))
        }
    }

    /// The optional fields a site sent, in reading order.
    static func facts(for lead: Lead) -> [(label: String, value: String)] {
        let attribution = [lead.utmSource, lead.utmMedium, lead.utmCampaign]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / ")
        let candidates: [(String, String?)] = [
            ("Subject", lead.subject),
            ("Company", lead.company),
            ("Service", lead.service),
            ("Status", lead.status?.capitalized),
            ("Campaign", attribution),
            ("Referrer", lead.referrer),
            ("Landing page", lead.landingPage)
        ]
        return candidates.compactMap { label, value in
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (label, value)
        }
    }

    private func reply(to lead: Lead, from source: LeadSource) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = lead.email
        let subject = lead.subject.flatMap { $0.isEmpty ? nil : "Re: \($0)" } ?? "Re: your enquiry via \(source.name)"
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func createTask(for lead: Lead, from source: LeadSource) {
        let name = lead.name.isEmpty ? lead.email : lead.name
        let task = TaskItem(
            title: "Reply to \(name) (\(source.name))",
            notes: [lead.email, lead.headline, lead.message].filter { !$0.isEmpty }.joined(separator: "\n\n"),
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            priority: .high
        )
        TaskStore.add(task, to: modelContext)
        notice = "Added a follow-up task, due tomorrow."
    }
}

private struct LeadRow: View {
    let lead: Lead

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.cyan)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
                .opacity(lead.isUnread ? 1 : 0)
                .accessibilityLabel(lead.isUnread ? "Unread" : "")
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(lead.name.isEmpty ? lead.email : lead.name)
                        .fontWeight(lead.isUnread ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    Text(lead.submittedAt, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(lead.headline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

/// The Settings → Connections rows that add, edit, and remove lead sources.
struct LeadSourceSettings: View {
    @ObservedObject private var monitor = LeadMonitor.shared
    @AppStorage(LeadMonitor.notificationsKey) private var notifyOnNewLead = true
    @State private var editingID: UUID?
    @State private var isAdding = false
    @State private var name = ""
    @State private var website = ""
    @State private var token = ""
    @State private var status: String?
    @State private var pendingRemoval: LeadSource?

    var body: some View {
        Section {
            ForEach(monitor.sources) { source in
                if editingID == source.id { editor(for: source) } else { row(for: source) }
            }
            if isAdding {
                editor(for: nil)
            } else if editingID == nil {
                Button("Add site…") { begin(nil) }
            }
            Toggle("Notify me about each new lead", isOn: $notifyOnNewLead)
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Leads")
        } footer: {
            Text("JARVIS reads each site's /api/jarvis/leads feed every 10 minutes while it is open. The token must match JARVIS_LEADS_TOKEN in the site's environment and is stored in macOS Keychain. Leads are kept on this Mac and included in backups; tokens are not.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "this site")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { source in
            Button("Remove", role: .destructive) { remove(source) }
        } message: { _ in
            Text("Its token and the leads JARVIS has saved from it are deleted from this Mac. The site keeps its own copy.")
        }
    }

    private func row(for source: LeadSource) -> some View {
        LabeledContent(source.name) {
            HStack(spacing: 10) {
                Text(URL(string: source.websiteURL)?.host() ?? source.websiteURL)
                    .foregroundStyle(.secondary)
                if monitor.hasToken(for: source.id) {
                    Label("Token saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Token needed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button("Edit…") { begin(source) }
                Button("Remove", role: .destructive) { pendingRemoval = source }
            }
        }
    }

    private func editor(for source: LeadSource?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $name, prompt: Text("Lawrence's portfolio"))
            TextField("Website", text: $website, prompt: Text("https://example.com"))
            SecureField("Feed token", text: $token, prompt: Text(source == nil
                ? "The site's JARVIS_LEADS_TOKEN"
                : "Leave blank to keep the saved token"))
                .textContentType(.password)
            HStack {
                Spacer()
                Button("Cancel") { finish() }
                Button(source == nil ? "Add" : "Save") { commit(source) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(website.trimmingCharacters(in: .whitespaces).isEmpty
                              || (source == nil && token.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
    }

    private func begin(_ source: LeadSource?) {
        name = source?.name ?? ""
        website = source?.websiteURL ?? ""
        token = ""
        status = nil
        editingID = source?.id
        isAdding = source == nil
    }

    private func finish() {
        editingID = nil
        isAdding = false
        name = ""
        website = ""
        token = ""
    }

    private func commit(_ source: LeadSource?) {
        do {
            if let source {
                try monitor.updateSource(source.id, name: name, websiteURL: website, token: token)
                status = "Saved. Checking \(name.isEmpty ? "the site" : name) now."
            } else {
                let added = try monitor.addSource(name: name, websiteURL: website, token: token)
                status = "Added \(added.name). Its existing leads are imported as read."
            }
            finish()
        } catch {
            status = error.localizedDescription
        }
    }

    private func remove(_ source: LeadSource) {
        do {
            try monitor.removeSource(source.id)
            status = "Removed \(source.name)."
        } catch {
            status = error.localizedDescription
        }
        pendingRemoval = nil
    }
}
