import Foundation

struct GraphifyCanvasDocument: Decodable {
    struct Node: Decodable, Identifiable {
        let id: String
        let type: String
        let file: String?
        let label: String?
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let color: String?

        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
        var title: String { label ?? file?.replacingOccurrences(of: ".md", with: "") ?? id }
    }

    struct Edge: Decodable, Identifiable {
        let id: String
        let fromNode: String
        let toNode: String
        let label: String?
    }

    let nodes: [Node]
    let edges: [Edge]

    var bounds: CGRect {
        nodes.reduce(CGRect.null) { $0.union($1.rect) }
    }

    func node(forGraphNote note: URL) -> Node? {
        nodes.first { $0.file == note.lastPathComponent }
    }
}

enum GraphifyCanvasError: LocalizedError {
    case missing
    case malformed

    var errorDescription: String? {
        switch self {
        case .missing: "This project has no Graphify graph.canvas export yet."
        case .malformed: "The Graphify canvas could not be read. Refresh its export and try again."
        }
    }
}

enum GraphifyCanvasService {
    static func load(from graphDirectory: URL) throws -> GraphifyCanvasDocument {
        let url = graphDirectory.appendingPathComponent("graph.canvas")
        guard FileManager.default.fileExists(atPath: url.path) else { throw GraphifyCanvasError.missing }
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(GraphifyCanvasDocument.self, from: data),
              !document.nodes.isEmpty, document.nodes.count <= 20_000,
              document.edges.count <= 50_000,
              document.nodes.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite && $0.width.isFinite && $0.height.isFinite &&
                  $0.width > 0 && $0.height > 0
              }) else { throw GraphifyCanvasError.malformed }
        return document
    }

    static func noteURL(for node: GraphifyCanvasDocument.Node, in graphDirectory: URL) -> URL? {
        guard let file = node.file, !file.hasPrefix("/"),
              !file.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }) else { return nil }
        let root = graphDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(file).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }
}
