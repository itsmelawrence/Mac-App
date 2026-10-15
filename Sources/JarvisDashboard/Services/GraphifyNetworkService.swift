import Foundation

struct GraphifyNetwork {
    struct Node: Identifiable {
        let id: String
        let title: String
        let community: String
        let url: URL
        let x: Double
        let y: Double
    }

    struct Edge {
        let source: Int
        let target: Int
    }

    let nodes: [Node]
    let edges: [Edge]
    let communities: [(name: String, count: Int)]

    init(nodes: [Node], edges: [Edge]) {
        self.nodes = nodes
        self.edges = edges
        self.communities = Dictionary(grouping: nodes, by: \.community)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}

enum GraphifyNetworkError: LocalizedError {
    case missing

    var errorDescription: String? {
        "No Graphify notes were found for this project. Refresh its export and try again."
    }
}

enum GraphifyNetworkService {
    static func load(from directory: URL) throws -> GraphifyNetwork {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("_COMMUNITY_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { throw GraphifyNetworkError.missing }

        struct Draft {
            let url: URL
            let title: String
            let community: String
            let targets: [String]
        }
        let drafts: [Draft] = urls.compactMap { url in
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lines = contents.components(separatedBy: .newlines)
            let community = lines.first { $0.hasPrefix("community:") }?
                .dropFirst("community:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? "Ungrouped"
            let title = url.deletingPathExtension().lastPathComponent
            var targets: [String] = []
            var inConnections = false
            for line in lines {
                if line == "## Connections" { inConnections = true; continue }
                if inConnections && line.hasPrefix("## ") { break }
                guard inConnections, let open = line.range(of: "[["),
                      let close = line.range(of: "]]", range: open.upperBound..<line.endIndex) else { continue }
                let link = String(line[open.upperBound..<close.lowerBound])
                let path = String(link.split(separator: "|", maxSplits: 1).first ?? "")
                if let target = path.split(separator: "/").last {
                    targets.append(String(target))
                }
            }
            return Draft(url: url, title: title, community: community.isEmpty ? "Ungrouped" : community,
                         targets: targets)
        }
        let names = Dictionary(uniqueKeysWithValues: drafts.enumerated().map { ($0.element.title, $0.offset) })
        let counts = Dictionary(grouping: drafts, by: \.community).mapValues(\.count)
        let communities = counts.keys.sorted { (counts[$0] ?? 0) == (counts[$1] ?? 0) ? $0 < $1 : (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        var positions: [String: Int] = [:]
        let nodes = drafts.map { draft -> GraphifyNetwork.Node in
            let index = communities.firstIndex(of: draft.community) ?? 0
            let member = positions[draft.community, default: 0]
            positions[draft.community] = member + 1
            let groupAngle = Double(index) * 2.399963229728653
            let groupRadius = 34 * sqrt(Double(index))
            let memberAngle = Double(member) * 2.399963229728653 + Double(index) * 0.61
            let memberRadius = 4.6 * sqrt(Double(member))
            return GraphifyNetwork.Node(
                id: draft.title, title: draft.title, community: draft.community, url: draft.url,
                x: cos(groupAngle) * groupRadius + cos(memberAngle) * memberRadius,
                y: sin(groupAngle) * groupRadius + sin(memberAngle) * memberRadius
            )
        }
        var seen = Set<String>()
        var edges: [GraphifyNetwork.Edge] = []
        for (source, draft) in drafts.enumerated() {
            for targetName in draft.targets {
                guard let target = names[targetName], source != target else { continue }
                let pair = source < target ? "\(source):\(target)" : "\(target):\(source)"
                if seen.insert(pair).inserted { edges.append(.init(source: source, target: target)) }
            }
        }
        return GraphifyNetwork(nodes: nodes, edges: edges)
    }
}
