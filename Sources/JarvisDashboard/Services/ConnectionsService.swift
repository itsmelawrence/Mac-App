import Darwin
import Foundation

struct ConnectionProject: Identifiable, Hashable {
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

struct ConnectionsWorkspace {
    let projects: [ConnectionProject]
    /// Registered routes that could not be opened, described for display.
    let routeIssues: [String]
}

/// The report written by the vault's `.tools/vault_doctor.py` to `ICM/health.json`.
struct VaultHealth: Decodable {
    struct Issue: Decodable, Hashable {
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

struct ConnectionFile: Identifiable, Hashable {
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
    /// Discovery rules shared with the vault's `.tools/project_hubs.py` through `ICM/discovery.json`.
    struct DiscoveryRules: Decodable, Equatable {
        let version: Int
        let roots: [String]
        let markers: Set<String>
        let excludedDirectories: Set<String>
        let maxDepth: Int

        static let defaults = DiscoveryRules(
            version: 1, roots: ["Work", "Personal"],
            markers: [
                ".git", "Package.swift", "package.json", "composer.json", "Cargo.toml",
                "go.mod", "pyproject.toml", "Gemfile", "artisan", "project.yml", "PROJECT.md",
                "wp-config.php", "public_html", "index.php", "index.html"
            ],
            excludedDirectories: ConnectionsService.excludedDirectories.union([
                ".vscode", "Media", "JPC Assets", "output", "tmp", "uploads"
            ]),
            maxDepth: 6
        )
    }

    /// Falls back to the built-in rules when the file is missing, malformed, or a newer version.
    static func discoveryRules(in vaultURL: URL) -> DiscoveryRules {
        guard let data = try? Data(contentsOf: vaultURL.appendingPathComponent("ICM/discovery.json")),
              let rules = try? JSONDecoder().decode(DiscoveryRules.self, from: data),
              rules.version == 1, !rules.markers.isEmpty, rules.maxDepth > 0 else { return .defaults }
        return rules
    }

    /// Records the scan for the vault doctor's parity check; writes only when the list changes.
    static func recordScan(_ projects: [ConnectionProject], in vaultURL: URL) {
        struct Scan: Codable, Equatable { let version: Int; let paths: [String] }
        let url = vaultURL.appendingPathComponent("ICM/cortex-projects.json")
        let scan = Scan(version: 1, paths: projects.map(\.route.projectPath).sorted())
        if let data = try? Data(contentsOf: url), (try? JSONDecoder().decode(Scan.self, from: data)) == scan { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(scan).write(to: url, options: .atomic)
    }

    static func projects(in vaultURL: URL) throws -> [ConnectionProject] {
        try workspace(in: vaultURL).projects
    }

    /// A stale or unsafe route is reported and skipped so it cannot hide the rest of the vault.
    static func workspace(in vaultURL: URL) throws -> ConnectionsWorkspace {
        let manifestURL = vaultURL.appendingPathComponent("ICM/routes.json")
        guard FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("CONTEXT.md").path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ICMManifest.self, from: data),
              manifest.version == 1 else { throw ICMRoutingError.invalidVault }

        var registered: [ConnectionProject] = []
        var routeIssues: [String] = []
        for route in manifest.routes {
            do {
                let root = try containedURL(route.projectPath, under: vaultURL)
                let context = try containedURL(route.contextPath, under: vaultURL)
                let graph = try containedURL(route.graphPath, under: vaultURL)
                guard isDirectory(root) else { throw ICMRoutingError.missingProject(route.projectPath) }
                registered.append(ConnectionProject(route: route, rootURL: root, contextURL: context,
                                                    graphURL: graph, isRegistered: true))
            } catch {
                routeIssues.append("\(route.name): \(error.localizedDescription)")
            }
        }
        let registeredPaths = Set(registered.map(\.route.projectPath))
        let projects = (registered + discoveredProjects(in: vaultURL, excluding: registeredPaths))
            .sorted {
                let byName = $0.name.localizedStandardCompare($1.name)
                return byName == .orderedSame
                    ? $0.route.projectPath < $1.route.projectPath
                    : byName == .orderedAscending
            }
        return ConnectionsWorkspace(projects: projects, routeIssues: routeIssues)
    }

    /// Missing or unreadable reports return nil; the doctor is optional.
    static func health(in vaultURL: URL) -> VaultHealth? {
        guard let data = try? Data(contentsOf: vaultURL.appendingPathComponent("ICM/health.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VaultHealth.self, from: data)
    }

    private static func discoveredProjects(in vaultURL: URL, excluding registeredPaths: Set<String>) -> [ConnectionProject] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let vaultPath = canonicalPath(vaultURL)
        let rules = discoveryRules(in: vaultURL)
        var pending = rules.roots.compactMap { try? containedURL($0, under: vaultURL) }
        var candidates: [(path: String, hasGit: Bool)] = []

        while let directory = pending.popLast() {
            guard isDirectory(directory), isContained(directory, under: vaultURL),
                  let entries = try? manager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]
                  ) else { continue }
            let names = Set(entries.map(\.lastPathComponent))
            let relativePath = String(canonicalPath(directory).dropFirst(vaultPath.count + 1))
            if !names.isDisjoint(with: rules.markers) {
                candidates.append((relativePath, names.contains(".git")))
            }
            let depth = relativePath.split(separator: "/").count
            guard depth < rules.maxDepth else { continue }
            for entry in entries {
                guard !entry.lastPathComponent.hasPrefix("."),
                      !rules.excludedDirectories.contains(entry.lastPathComponent),
                      let values = try? entry.resourceValues(forKeys: keys),
                      values.isDirectory == true, values.isSymbolicLink != true,
                      isContained(entry, under: vaultURL) else { continue }
                pending.append(entry)
            }
        }

        let candidatePaths = Set(candidates.map(\.path)).union(registeredPaths)
        return candidates.compactMap { candidate in
            let path = candidate.path
            guard !registeredPaths.contains(path),
                  (candidate.hasGit || !hasCandidateAncestor(path, in: candidatePaths)) else { return nil }
            let route = ICMRoute(
                id: "discovered:\(path)", name: URL(fileURLWithPath: path).lastPathComponent,
                aliases: [], projectPath: path,
                contextPath: "Notes/Projects/\(path)/PROJECT.md",
                graphPath: "Graphify/_discovered/\(path.replacingOccurrences(of: "/", with: "__"))",
                entrypoints: [], graphNotes: []
            )
            guard let root = try? containedURL(route.projectPath, under: vaultURL),
                  let context = try? containedURL(route.contextPath, under: vaultURL),
                  let graph = try? containedURL(route.graphPath, under: vaultURL) else { return nil }
            return ConnectionProject(route: route, rootURL: root, contextURL: context,
                                     graphURL: graph, isRegistered: false)
        }
    }

    private static func hasCandidateAncestor(_ path: String, in paths: Set<String>) -> Bool {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return false }
        return (1..<parts.count).contains { paths.contains(parts.prefix($0).joined(separator: "/")) }
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
