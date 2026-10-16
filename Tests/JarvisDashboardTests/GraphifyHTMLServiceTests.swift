import Foundation
import Testing
@testable import JarvisDashboard

struct GraphifyHTMLServiceTests {
    @Test func localisesOnlyGraphifysPinnedViewerDependency() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.html")
        let library = root.appendingPathComponent("vis-network.min.js")
        let original = "<script src=\"\(GraphifyHTMLService.remoteLibrary)\"></script>const RAW_NODES = []; new vis.Network()"
        try original.write(to: source, atomically: true, encoding: .utf8)
        try "viewer".write(to: library, atomically: true, encoding: .utf8)

        let viewer = try GraphifyHTMLService.prepare(sourceURL: source, libraryURL: library,
                                                      cacheRoot: root.appendingPathComponent("cache"))
        let result = try String(contentsOf: viewer, encoding: .utf8)
        #expect(result == original.replacingOccurrences(of: GraphifyHTMLService.remoteLibrary,
                                                         with: GraphifyHTMLService.localLibrary))
        #expect(try String(contentsOf: source, encoding: .utf8) == original)
        #expect(FileManager.default.fileExists(atPath: viewer.deletingLastPathComponent()
            .appendingPathComponent("vis-network.min.js").path))
    }
}
