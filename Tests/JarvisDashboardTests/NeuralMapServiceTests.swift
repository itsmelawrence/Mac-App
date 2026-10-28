import Foundation
import Testing
@testable import JarvisDashboard

struct NeuralMapServiceTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func fillsTheTemplateAndKeepsFileNamesFromEndingTheScript() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = root.appendingPathComponent("neural-map.html")
        let data = root.appendingPathComponent("neural-map.json")
        try "<script>const DATA = __DATA__;</script>".write(to: template, atomically: true, encoding: .utf8)
        try #"{"generated":"abc1234","nodes":[{"id":"a</script>.swift"}],"links":[]}"#
            .write(to: data, atomically: true, encoding: .utf8)

        let page = try NeuralMapService.prepare(templateURL: template, dataURL: data,
                                                cacheRoot: root.appendingPathComponent("cache"), name: "JARVIS")
        let html = try String(contentsOf: page, encoding: .utf8)
        #expect(page.path.hasSuffix("cache/NeuralMap/JARVIS/index.html"))
        #expect(html.contains(#"const DATA = {"generated":"abc1234""#))
        #expect(html.contains(#"a<\/script>.swift"#))
        #expect(html.components(separatedBy: "</script>").count == 2)
        #expect(!html.contains(NeuralMapService.placeholder))
    }

    @Test func reportsMissingOrMalformedData() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = root.appendingPathComponent("neural-map.html")
        let data = root.appendingPathComponent("neural-map.json")
        try "const DATA = __DATA__;".write(to: template, atomically: true, encoding: .utf8)
        let cache = root.appendingPathComponent("cache")

        #expect(throws: NeuralMapError.self) {
            try NeuralMapService.prepare(templateURL: template, dataURL: data, cacheRoot: cache, name: "JARVIS")
        }
        for broken in ["not json", #"{"nodes":[],"links":[]}"#, #"{"nodes":[{"id":"a"}]}"#] {
            try broken.write(to: data, atomically: true, encoding: .utf8)
            #expect(throws: NeuralMapError.self) {
                try NeuralMapService.prepare(templateURL: template, dataURL: data, cacheRoot: cache, name: "JARVIS")
            }
        }
    }

    @Test func bundledTemplateHasExactlyOnePlaceholder() throws {
        let template = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Supporting/NeuralMap/neural-map.html")
        let html = try String(contentsOf: template, encoding: .utf8)
        #expect(html.components(separatedBy: NeuralMapService.placeholder).count == 2)
    }

    @Test func dataSitsBesideGraphifysExport() {
        let vault = URL(fileURLWithPath: "/Users/me/Documents/Main/Projects")
        #expect(NeuralMapService.dataURL(export: "JARVIS", vaultURL: vault).path
                == "/Users/me/Documents/Main/.tools/graphify-data/JARVIS/graphify-out/neural-map.json")
        #expect(NeuralMapService.scriptURL(vaultURL: vault).path == "/Users/me/Documents/Main/.tools/graphify_neural_map.py")
    }
}
