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
        let original = """
        <script src="\(GraphifyHTMLService.remoteLibrary)" integrity="sha384-Ux6phic9PEHJ38YtrijhkzyJ8yQlH8i/+buBR8s3mAZOJrP1gwyvAcIYl3GWtpX1" crossorigin="anonymous"></script>
        const RAW_NODES = []; new vis.Network()
        """
        try original.write(to: source, atomically: true, encoding: .utf8)
        try "viewer".write(to: library, atomically: true, encoding: .utf8)

        let viewer = try GraphifyHTMLService.prepare(sourceURL: source, libraryURL: library,
                                                      cacheRoot: root.appendingPathComponent("cache"))
        let result = try String(contentsOf: viewer, encoding: .utf8)
        #expect(result.contains("<script>\nviewer\n</script>"))
        #expect(!result.contains(GraphifyHTMLService.remoteLibrary))
        #expect(!result.contains("crossorigin="))
        #expect(!result.contains("integrity="))
        #expect(try String(contentsOf: source, encoding: .utf8) == original)
    }
}
