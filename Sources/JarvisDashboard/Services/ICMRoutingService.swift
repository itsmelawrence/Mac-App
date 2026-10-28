import Foundation

struct ICMRoute: Codable, Equatable, Sendable {
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
    case missingProjectHub(String)
    case vaultToolsMissing(String)
    case vaultTools(String)

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
        case let .missingProjectHub(path):
            "The PARA project note is missing: \(path)."
        case let .vaultToolsMissing(path):
            "JARVIS needs the vault tools to find projects: \(path) is missing."
        case let .vaultTools(message):
            message
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

    /// `.tools/icm.py` beside the vault owns discovery and routing (one implementation, shared with
    /// the vault tools and the assistant's MCP server). JARVIS runs it and reads its JSON reply.
    static func icmScriptURL(vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent(".tools/icm.py")
    }

    /// Runs one `icm.py` command and decodes the JSON on the last line of its output. Blocks; call off the main actor.
    static func runICM<Reply: Decodable>(_ command: String, vaultURL: URL, input: String? = nil,
                                         as type: Reply.Type) throws -> Reply {
        let script = icmScriptURL(vaultURL: vaultURL)
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw ICMRoutingError.vaultToolsMissing(script.path)
        }
        let result = try VaultMaintenanceService.run(
            script: script, arguments: [command, "--vault", vaultURL.path], timeout: 60, input: input.map { Data($0.utf8) })
        let lastLine = result.output.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard result.status == 0, let lastLine,
              let reply = try? JSONDecoder().decode(Reply.self, from: Data(lastLine.utf8)) else {
            throw ICMRoutingError.vaultTools("Vault routing failed: \(result.output.suffix(300))")
        }
        return reply
    }

    private struct RouteReply: Decodable {
        let status: String
        let message: String?
        let candidates: [String]?
        let route: ICMRoute?
        let projectRoot: String?
        let context: String?
        let graphNotes: [String]?
        let handoff: String?
    }

    /// The project a work request names, with its agent handoff; nil when no route matches.
    static func prepare(prompt: String, vaultURL: URL) throws -> ICMPreparedRoute? {
        let reply = try runICM("route", vaultURL: vaultURL, input: prompt, as: RouteReply.self)
        switch reply.status {
        case "unmatched":
            return nil
        case "ambiguous":
            throw ICMRoutingError.ambiguous(reply.candidates ?? [])
        case "routed":
            guard let route = reply.route, let root = reply.projectRoot, let context = reply.context,
                  let handoff = reply.handoff else { throw ICMRoutingError.vaultTools("Vault routing returned an incomplete route.") }
            return ICMPreparedRoute(route: route, projectURL: URL(fileURLWithPath: root, isDirectory: true),
                                    contextURL: URL(fileURLWithPath: context),
                                    graphURLs: (reply.graphNotes ?? []).map { URL(fileURLWithPath: $0) }, handoff: handoff)
        default:
            throw ICMRoutingError.vaultTools(reply.message ?? "Vault routing failed.")
        }
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

    @discardableResult
    static func recordActivity(
        prompt: String,
        route: ICMRoute,
        rawPromptURL: URL,
        vaultURL: URL,
        now: Date = .now
    ) throws -> URL {
        let projectNotesPath = "Notes/Projects/" + route.projectPath
        let hub = try safeURL(projectNotesPath + "/PROJECT.md", under: vaultURL)
        guard FileManager.default.fileExists(atPath: hub.path) else {
            throw ICMRoutingError.missingProjectHub(hub.path)
        }
        let activityFolder = try safeURL(projectNotesPath + "/Activities", under: vaultURL)
        try FileManager.default.createDirectory(at: activityFolder, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: now)
        let filename = timestamp.replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8) + ".md"
        let note = activityFolder.appendingPathComponent(filename)
        let hubLink = "Notes/Projects/" + route.projectPath + "/PROJECT"
        let rawRelative = rawPromptURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        let rawLink = String(rawRelative.dropLast(rawRelative.hasSuffix(".md") ? 3 : 0))
        var fence = "```"
        while prompt.contains(fence) { fence += "`" }
        let body = """
        ---
        type: project-activity
        para: Projects
        status: requested
        source: jarvis-command-console
        project: \(String(data: try JSONEncoder().encode(route.projectPath), encoding: .utf8) ?? "\"\"")
        created_at: \(timestamp)
        ---

        # Activity · \(timestamp)

        Project: [[\(hubLink)|\(route.name)]]
        Raw prompt: [[\(rawLink)|Captured prompt]]

        ## Request

        \(fence)text
        \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        \(fence)

        ## Work performed

        Pending agent work.

        ## Files and connections

        Pending verification.

        ## Verification and outcome

        Pending verification.
        """
        guard FileManager.default.createFile(atPath: note.path, contents: Data(body.utf8)) else {
            throw ICMRoutingError.captureFailed
        }
        return note
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

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
