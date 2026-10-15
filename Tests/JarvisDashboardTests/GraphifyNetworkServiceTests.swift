import Foundation
import Testing
@testable import JarvisDashboard

struct GraphifyNetworkServiceTests {
    @Test func readsCommunitiesAndConnectionsFromGraphifyNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        ---
        community: "Core"
        ---
        # Alpha
        ## Connections
        - [[Graphify/Demo/Beta|Beta]] - `calls`
        """.write(to: directory.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        try """
        ---
        community: "Services"
        ---
        # Beta
        ## Connections
        - [[Graphify/Demo/Alpha|Alpha]] - `called by`
        """.write(to: directory.appendingPathComponent("Beta.md"), atomically: true, encoding: .utf8)
        let network = try GraphifyNetworkService.load(from: directory)
        #expect(network.nodes.count == 2)
        #expect(network.edges.count == 1)
        #expect(Set(network.communities.map(\.name)) == Set(["Core", "Services"]))
        #expect(network.nodes.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
}
