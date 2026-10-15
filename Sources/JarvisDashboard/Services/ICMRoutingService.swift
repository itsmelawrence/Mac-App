import Foundation

struct ICMRoute: Codable, Equatable {
    let id: String
    let name: String
    let aliases: [String]
    let projectPath: String
    let contextPath: String
    let graphPath: String
    let entrypoints: [String]
    let graphNotes: [String]
}

struct ICMManifest: Codable {
    let version: Int
    let routes: [ICMRoute]
}

struct ICMPreparedRoute {
    let route: ICMRoute
    let projectURL: URL
    let contextURL: URL
    let graphURLs: [URL]
    let handoff: String
}

enum ICMRoutingError: LocalizedError {
    case invalidVault
    case unsupportedManifest
    case invalidPath(String)
    case missingProject(String)
    case missingContext(String)
    case ambiguous([String])
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .invalidVault:
            "The selected vault needs CONTEXT.md and ICM/routes.json. Choose the Projects vault in Settings."
        case .unsupportedManifest:
            "This ICM routes file uses an unsupported version."
        case let .invalidPath(path):
            "The ICM routes file contains an unsafe path: \(path)."
        case let .missingProject(path):
            "The routed project folder is missing: \(path)."
        case let .missingContext(path):
            "The project context note is missing: \(path)."
        case let .ambiguous(names):
            "More than one project matches: \(names.joined(separator: ", ")). Name the intended project."
        case .captureFailed:
            "JARVIS could not save this prompt in the Obsidian vault."
        }
    }
}

enum ICMRoutingService {
    static var defaultVaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Main/Projects", isDirectory: true)
    }

    static func vaultURL(configuredPath: String) -> URL {
        let path = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? defaultVaultURL : URL(fileURLWithPath: path, isDirectory: true)
    }

    static func isWorkRequest(_ prompt: String) -> Bool {
        let actionWords: Set<String> = [
            "add", "build", "change", "create", "debug", "design", "fix", "implement",
            "improve", "refactor", "remove", "redesign", "review", "route", "update"
        ]
        return !Set(words(in: prompt)).isDisjoint(with: actionWords)
    }

    static func prepare(prompt: String, vaultURL: URL) throws -> ICMPreparedRoute? {
        let manifest = try loadManifest(vaultURL: vaultURL)
        let promptWords = words(in: prompt)
        let matches = manifest.routes.filter { route in
            ([route.name] + route.aliases).contains { alias in
                let aliasWords = words(in: alias)
                return !aliasWords.isEmpty && promptWords.windows(of: aliasWords).contains(aliasWords)
            }
        }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, let route = matches.first else {
            throw ICMRoutingError.ambiguous(matches.map(\.name).sorted())
        }

        let projectURL = try safeURL(route.projectPath, under: vaultURL)
        let contextURL = try safeURL(route.contextPath, under: vaultURL)
        guard isDirectory(projectURL) else { throw ICMRoutingError.missingProject(route.projectPath) }
        guard FileManager.default.fileExists(atPath: contextURL.path) else {
            throw ICMRoutingError.missingContext(route.contextPath)
        }
        let graphDirectory = try safeURL(route.graphPath, under: vaultURL)
        let graphURLs = try suggestedGraphNotes(route: route, directory: graphDirectory, prompt: prompt)
        let sourceURLs = try route.entrypoints.map { try safeURL($0, under: projectURL) }
        let graphLines = graphURLs.map { "- \($0.path)" }.joined(separator: "\n")
        let sourceLines = sourceURLs.map { "- \($0.path)" }.joined(separator: "\n")
        let handoff = """
        Task: \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))

        ICM route: \(route.name)
        Project root: \(projectURL.path)
        Read the vault router: \(vaultURL.appendingPathComponent("CONTEXT.md").path)
        Read the project context: \(contextURL.path)
        Start with these source files when relevant:
        \(sourceLines)
        Graphify navigation hints:
        \(graphLines.isEmpty ? "- No graph notes available yet." : graphLines)

        Read only the context needed for this task. Check current source and local project instructions before editing. Treat Graphify edges as leads, then verify them in code. Record durable decisions in the vault after the work.
        """
        return ICMPreparedRoute(route: route, projectURL: projectURL, contextURL: contextURL,
                                graphURLs: graphURLs, handoff: handoff)
    }

    @discardableResult
    static func capture(prompt: String, route: ICMRoute?, vaultURL: URL, now: Date = .now) throws -> URL {
        guard FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("CONTEXT.md").path) else {
            throw ICMRoutingError.invalidVault
        }
        let folder = try safeURL("Memory/01_intake/" + (route?.projectPath ?? "_unrouted"), under: vaultURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let file = folder.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8)).md")
        let body = """
        ---
        source: jarvis-command-console
        captured_at: \(ISO8601DateFormatter().string(from: now))
        route_id: \(route?.id ?? "unrouted")
        ---

        # Prompt

        \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        guard FileManager.default.createFile(atPath: file.path, contents: Data(body.utf8)) else {
            throw ICMRoutingError.captureFailed
        }
        return file
    }

    private static func loadManifest(vaultURL: URL) throws -> ICMManifest {
        guard FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("CONTEXT.md").path) else {
            throw ICMRoutingError.invalidVault
        }
        let path = vaultURL.appendingPathComponent("ICM/routes.json")
        guard let data = try? Data(contentsOf: path),
              let manifest = try? JSONDecoder().decode(ICMManifest.self, from: data) else {
            throw ICMRoutingError.invalidVault
        }
        guard manifest.version == 1 else { throw ICMRoutingError.unsupportedManifest }
        return manifest
    }

    private static func safeURL(_ relativePath: String, under root: URL) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.hasPrefix("/"), !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ICMRoutingError.invalidPath(relativePath)
        }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let result = canonicalRoot.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard result.path.hasPrefix(canonicalRoot.path + "/") else {
            throw ICMRoutingError.invalidPath(relativePath)
        }
        return result
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func suggestedGraphNotes(route: ICMRoute, directory: URL, prompt: String) throws -> [URL] {
        guard isDirectory(directory) else { return [] }
        let seedNames = route.graphNotes
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let promptTokens: Set<String> = Set(words(in: prompt).filter { $0.count >= 4 })
        var scored: [(url: URL, score: Int)] = []
        for url in files where url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_COMMUNITY") {
            let filename = url.deletingPathExtension().lastPathComponent
            let filenameTokens: Set<String> = Set(words(in: filename))
            let score: Int = filenameTokens.intersection(promptTokens).count
            if score > 0 { scored.append((url: url, score: score)) }
        }
        scored.sort {
            if $0.score == $1.score { return $0.url.lastPathComponent < $1.url.lastPathComponent }
            return $0.score > $1.score
        }
        let ranked = Array(scored.prefix(3)).map(\.url)
        let seeded = try seedNames.map { try safeURL($0, under: directory) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return Array((ranked + seeded).uniqued().prefix(4))
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

private extension Array where Element == String {
    func windows(of pattern: [String]) -> [[String]] {
        guard count >= pattern.count else { return [] }
        return (0...(count - pattern.count)).map { Array(self[$0..<($0 + pattern.count)]) }
    }
}

private extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seen: Set<String> = []
        return filter { seen.insert($0.path).inserted }
    }
}
