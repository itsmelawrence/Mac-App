import Foundation

enum GraphifyHTMLError: LocalizedError {
    case missing
    case malformed
    case missingViewerLibrary

    var errorDescription: String? {
        switch self {
        case .missing: "Graphify's graph.html is not available for this project. Generate it with Graphify first."
        case .malformed: "Graphify's graph.html could not be read. Regenerate it with Graphify."
        case .missingViewerLibrary: "The local Graphify viewer library is missing from JARVIS."
        }
    }
}

enum GraphifyHTMLService {
    static let remoteLibrary = "https://unpkg.com/vis-network@9.1.6/standalone/umd/vis-network.min.js"
    static let localLibrary = "vis-network.min.js"

    /// Graphify's original HTML lives beside graph.json, outside the Obsidian notes export.
    static func htmlURL(for project: ConnectionProject, vaultURL: URL) -> URL {
        let inProject = project.rootURL.appendingPathComponent("graphify-out/graph.html")
        if FileManager.default.fileExists(atPath: inProject.path) { return inProject }
        return vaultURL.deletingLastPathComponent()
            .appendingPathComponent(".tools/graphify-data")
            .appendingPathComponent(project.graphURL.lastPathComponent)
            .appendingPathComponent("graphify-out/graph.html")
    }

    /// Keep Graphify's generated viewer intact. Only localise its exact pinned JS dependency.
    static func prepare(sourceURL: URL, libraryURL: URL, cacheRoot: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw GraphifyHTMLError.missing }
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { throw GraphifyHTMLError.missingViewerLibrary }
        guard let data = try? Data(contentsOf: sourceURL), data.count <= 30_000_000,
              let html = String(data: data, encoding: .utf8),
              html.contains("const RAW_NODES ="), html.contains("new vis.Network"),
              html.contains(remoteLibrary) else { throw GraphifyHTMLError.malformed }

        // A stable, path-specific cache avoids handing WebKit read access to the source vault.
        let hash = sourceURL.standardizedFileURL.path.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        let directory = cacheRoot.appendingPathComponent("GraphifyViewer/\(String(hash, radix: 16))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let viewerURL = directory.appendingPathComponent("graph.html")
        let scriptURL = directory.appendingPathComponent(localLibrary)
        let localHTML = html.replacingOccurrences(of: remoteLibrary, with: localLibrary)
        try localHTML.write(to: viewerURL, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: scriptURL.path) {
            try FileManager.default.removeItem(at: scriptURL)
        }
        try FileManager.default.copyItem(at: libraryURL, to: scriptURL)
        return viewerURL
    }
}
