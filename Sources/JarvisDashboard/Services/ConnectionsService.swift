import Darwin
import Foundation

struct ConnectionProject: Identifiable, Hashable {
    let route: ICMRoute
    let rootURL: URL
    let contextURL: URL
    let graphURL: URL

    var id: String { route.id }
    var name: String { route.name }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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

    static func projects(in vaultURL: URL) throws -> [ConnectionProject] {
        let manifestURL = vaultURL.appendingPathComponent("ICM/routes.json")
        guard FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("CONTEXT.md").path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ICMManifest.self, from: data),
              manifest.version == 1 else { throw ICMRoutingError.invalidVault }

        return try manifest.routes.map { route in
            let root = try containedURL(route.projectPath, under: vaultURL)
            let context = try containedURL(route.contextPath, under: vaultURL)
            let graph = try containedURL(route.graphPath, under: vaultURL)
            guard isDirectory(root) else { throw ICMRoutingError.missingProject(route.projectPath) }
            return ConnectionProject(route: route, rootURL: root, contextURL: context, graphURL: graph)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard isContained(url, under: root) else { throw ICMRoutingError.invalidPath(path) }
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
