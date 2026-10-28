import Foundation

enum NeuralMapError: LocalizedError {
    case missingTemplate
    case missingData
    case malformedData

    var errorDescription: String? {
        switch self {
        case .missingTemplate: "The neural map page is missing from JARVIS."
        case .missingData: "No neural map data yet. Choose Rebuild to roll Graphify's graph up to files."
        case .malformedData: "The neural map data could not be read. Choose Rebuild to regenerate it."
        }
    }
}

/// The neural map is the bundled page template plus a project's `neural-map.json`, which
/// `.tools/graphify_neural_map.py` rolls up from Graphify's graph (Python owns Graphify logic).
enum NeuralMapService {
    static let placeholder = "__DATA__"

    static func scriptURL(vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent(".tools/graphify_neural_map.py")
    }

    /// Beside Graphify's graph.json for the route's export, e.g. `graphify-data/JARVIS/graphify-out/`.
    static func dataURL(export: String, vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent()
            .appendingPathComponent(".tools/graphify-data")
            .appendingPathComponent(export)
            .appendingPathComponent("graphify-out/neural-map.json")
    }

    /// Writes the filled page into the cache, so WebKit never needs read access to the vault.
    static func prepare(templateURL: URL, dataURL: URL, cacheRoot: URL, name: String) throws -> URL {
        guard let template = try? String(contentsOf: templateURL, encoding: .utf8),
              template.components(separatedBy: placeholder).count == 2 else { throw NeuralMapError.missingTemplate }
        guard FileManager.default.fileExists(atPath: dataURL.path) else { throw NeuralMapError.missingData }
        guard let data = try? Data(contentsOf: dataURL), data.count <= 20_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = object["nodes"] as? [Any], !nodes.isEmpty, object["links"] is [Any],
              let json = String(data: data, encoding: .utf8) else { throw NeuralMapError.malformedData }
        // "</" only occurs inside JSON strings, where "<\/" means the same; a file named
        // "</script>" then cannot end the page's script early.
        let html = template.replacingOccurrences(of: placeholder, with: json.replacingOccurrences(of: "</", with: "<\\/"))
        let directory = cacheRoot.appendingPathComponent("NeuralMap/\(name)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pageURL = directory.appendingPathComponent("index.html")
        try html.write(to: pageURL, atomically: true, encoding: .utf8)
        return pageURL
    }
}
