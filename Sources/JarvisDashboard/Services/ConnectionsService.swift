import Darwin
import Foundation

struct ConnectionProject: Identifiable, Hashable, Sendable {
    let route: ICMRoute
    let rootURL: URL
    let contextURL: URL
    let graphURL: URL
    let isRegistered: Bool

    var id: String { route.id }
    var name: String { route.name }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ConnectionsWorkspace: Sendable {
    let projects: [ConnectionProject]
    /// Registered routes that could not be opened, described for display.
    let routeIssues: [String]
}

/// The report written by the vault's `.tools/vault_doctor.py` to `ICM/health.json`.
struct VaultHealth: Decodable, Sendable {
    struct Issue: Decodable, Hashable, Sendable {
        let level: String
        let check: String
        let message: String
        let path: String
    }

    let checkedAt: Date
    let errors: Int
    let warnings: Int
    let issues: [Issue]

    static let reportPath = "Notes/Resources/Vault health.md"
}

struct ConnectionFile: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let isDirectory: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct ConnectionNote: Identifiable, Hashable {
    let title: String
    let url: URL
    let relation: String

    var id: String { url.path }
}

enum ConnectionsService {
    // Build artefacts and dependency folders obscure the project structure and can
    // contain hundreds of thousands of files. They are excluded from browsing.
    static let excludedDirectories: Set<String> = [
        ".git", ".build", ".next", ".cache", ".obsidian", "node_modules",
        "vendor", "dist", "build", "coverage", "DerivedData", "__pycache__"
    ]
    static func projects(in vaultURL: URL) throws -> [ConnectionProject] {
        try workspace(in: vaultURL).projects
    }

    private struct WorkspaceReply: Decodable {
        struct Entry: Decodable {
            let route: ICMRoute
            let registered: Bool

            private enum CodingKeys: String, CodingKey { case registered }

            init(from decoder: Decoder) throws {
                route = try ICMRoute(from: decoder)
                registered = try decoder.container(keyedBy: CodingKeys.self).decode(Bool.self, forKey: .registered)
            }
        }

        let status: String
        let message: String?
        let projects: [Entry]?
        let routeIssues: [String]?
    }

    /// Every vault project from `.tools/icm.py`, which owns discovery: valid routes plus marked folders.
    /// A stale or unsafe route is reported there and skipped, so it cannot hide the rest of the vault.
    /// Blocks while the script runs; call off the main actor.
    static func workspace(in vaultURL: URL) throws -> ConnectionsWorkspace {
        let reply = try ICMRoutingService.runICM("workspace", vaultURL: vaultURL, as: WorkspaceReply.self)
        guard reply.status == "ok", let entries = reply.projects else {
            throw ICMRoutingError.vaultTools(reply.message ?? "Vault discovery failed.")
        }
        let projects = entries.compactMap { entry -> ConnectionProject? in
            guard let root = try? containedURL(entry.route.projectPath, under: vaultURL),
                  let context = try? containedURL(entry.route.contextPath, under: vaultURL),
                  let graph = try? containedURL(entry.route.graphPath, under: vaultURL) else { return nil }
            return ConnectionProject(route: entry.route, rootURL: root, contextURL: context,
                                     graphURL: graph, isRegistered: entry.registered)
        }
        return ConnectionsWorkspace(projects: projects, routeIssues: reply.routeIssues ?? [])
    }

    /// Missing or unreadable reports return nil; the doctor is optional.
    static func health(in vaultURL: URL) -> VaultHealth? {
        guard let data = try? Data(contentsOf: vaultURL.appendingPathComponent("ICM/health.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VaultHealth.self, from: data)
    }

    static func children(of directory: URL, in project: ConnectionProject) -> [ConnectionFile] {
        guard isDirectory(directory), isContained(directory, under: project.rootURL) else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else { return [] }
        return urls.compactMap { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  isContained(url, under: project.rootURL),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true else { return nil }
            let directory = values.isDirectory == true
            if directory && excludedDirectories.contains(url.lastPathComponent) { return nil }
            let relative = String(canonicalPath(url).dropFirst(canonicalPath(project.rootURL).count + 1))
            return ConnectionFile(url: url, relativePath: relative, isDirectory: directory)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func search(_ query: String, in project: ConnectionProject, limit: Int = 100) -> [ConnectionFile] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var results: [ConnectionFile] = []
        var pending = [project.rootURL]
        while let folder = pending.popLast(), results.count < limit {
            for item in children(of: folder, in: project) {
                if item.relativePath.localizedStandardContains(query) { results.append(item) }
                if item.isDirectory { pending.append(item.url) }
                if results.count >= limit { break }
            }
        }
        return results
    }

    static func notes(for file: ConnectionFile?, in project: ConnectionProject, vaultURL: URL) -> [ConnectionNote] {
        var notes: [ConnectionNote] = []
        if FileManager.default.fileExists(atPath: project.contextURL.path) {
            notes.append(ConnectionNote(title: "Project context", url: project.contextURL, relation: "describes project"))
        }
        guard let file, !file.isDirectory, isDirectory(project.graphURL) else { return notes }

        let candidate = project.graphURL.appendingPathComponent(file.name + ".md")
        guard let content = try? String(contentsOf: candidate, encoding: .utf8),
              content.contains("source_file: \"\(file.relativePath)\"") else { return notes }
        notes.append(ConnectionNote(title: "Graphify: \(file.name)", url: candidate, relation: "maps source"))
        guard let connections = content.components(separatedBy: "## Connections").dropFirst().first else { return notes }
        for line in connections.components(separatedBy: .newlines) where line.hasPrefix("- [[") {
            guard let start = line.range(of: "[["),
                  let end = line.range(of: "]]", range: start.upperBound..<line.endIndex) else { continue }
            let link = String(line[start.upperBound..<end.lowerBound]).components(separatedBy: "|")[0]
            guard let linkedURL = try? containedURL(link + ".md", under: vaultURL),
                  FileManager.default.fileExists(atPath: linkedURL.path) else { continue }
            let relation = line.components(separatedBy: "`").dropFirst().first ?? "connected"
            notes.append(ConnectionNote(title: linkedURL.deletingPathExtension().lastPathComponent,
                                        url: linkedURL, relation: relation))
            if notes.count >= 20 { break }
        }
        return notes
    }

    private static func containedURL(_ path: String, under root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ICMRoutingError.invalidPath(path)
        }
        let canonicalRoot = URL(fileURLWithPath: canonicalPath(root), isDirectory: true)
        let url = canonicalRoot.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard isContained(url, under: canonicalRoot) else { throw ICMRoutingError.invalidPath(path) }
        return url
    }

    private static func isContained(_ url: URL, under root: URL) -> Bool {
        let base = canonicalPath(root)
        let path = canonicalPath(url)
        return path == base || path.hasPrefix(base + "/")
    }

    private static func canonicalPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else {
            return url.standardizedFileURL.resolvingSymlinksInPath().path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }
}
