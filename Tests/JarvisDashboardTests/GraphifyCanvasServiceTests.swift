import Foundation
import Testing
@testable import JarvisDashboard

struct GraphifyCanvasServiceTests {
    @Test func loadsExportedDiagramAndLocatesFocusedNote() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("graphify-canvas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let canvas = """
        {"nodes":[
          {"id":"g0","type":"group","label":"Community 0","x":0,"y":0,"width":400,"height":200,"color":"1"},
          {"id":"n1","type":"file","file":"TodayView.swift.md","x":20,"y":80,"width":180,"height":60},
          {"id":"n2","type":"file","file":"CommandPanel.md","x":220,"y":80,"width":180,"height":60}
        ],"edges":[{"id":"e1","fromNode":"n1","toNode":"n2","label":"contains [EXTRACTED]"}]}
        """
        try canvas.write(to: folder.appendingPathComponent("graph.canvas"), atomically: true, encoding: .utf8)
        let note = folder.appendingPathComponent("TodayView.swift.md")
        try "# TodayView".write(to: note, atomically: true, encoding: .utf8)
        let document = try GraphifyCanvasService.load(from: folder)
        #expect(document.nodes.count == 3)
        #expect(document.edges.count == 1)
        #expect(document.bounds.width == 400)
        let focused = try #require(document.node(forGraphNote: note))
        #expect(focused.id == "n1")
        #expect(GraphifyCanvasService.noteURL(for: focused, in: folder)?.lastPathComponent == "TodayView.swift.md")
    }

    @Test func malformedAndEscapingNodesAreRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("graphify-canvas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "{}".write(to: folder.appendingPathComponent("graph.canvas"), atomically: true, encoding: .utf8)
        #expect(throws: GraphifyCanvasError.self) { _ = try GraphifyCanvasService.load(from: folder) }
        let node = GraphifyCanvasDocument.Node(id: "n", type: "file", file: "../secret.md", label: nil,
                                                x: 0, y: 0, width: 180, height: 60, color: nil)
        #expect(GraphifyCanvasService.noteURL(for: node, in: folder) == nil)
    }
}
