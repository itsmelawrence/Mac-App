import AppKit
import SwiftUI

/// Renders Graphify's exported Obsidian canvas using its node positions and edges.
struct GraphifyCanvasView: View {
    let graphDirectory: URL
    let focusNoteURL: URL?

    @State private var document: GraphifyCanvasDocument?
    @State private var errorMessage: String?
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var selectedNodeID: String?
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if let document {
                        Text("Graphify canvas · \(document.nodes.count) nodes · \(document.edges.count) edges")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Graphify canvas").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                        fit(in: canvasSize(for: geometry.size))
                    }
                    Button("Zoom out", systemImage: "minus.magnifyingglass") {
                        changeZoom(by: 0.7, in: canvasSize(for: geometry.size))
                    }
                    Button("Zoom in", systemImage: "plus.magnifyingglass") {
                        changeZoom(by: 1.4, in: canvasSize(for: geometry.size))
                    }
                    Button("Open canvas", systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.open(graphDirectory.appendingPathComponent("graph.canvas"))
                    }
                    .disabled(document == nil)
                }
                .labelStyle(.iconOnly)
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                if let document {
                    Canvas { context, size in
                        draw(document, in: &context, size: size,
                             zoom: zoom * magnification,
                             offset: CGSize(width: offset.width + dragOffset.width,
                                            height: offset.height + dragOffset.height))
                    }
                    .background(Color(red: 0.035, green: 0.065, blue: 0.11))
                    .clipped()
                    .gesture(DragGesture(minimumDistance: 3)
                        .updating($dragOffset) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                        })
                    .simultaneousGesture(MagnificationGesture()
                        .updating($magnification) { value, state, _ in state = value }
                        .onEnded { value in
                            changeZoom(by: value, in: canvasSize(for: geometry.size))
                        })
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in
                        selectNode(at: value.location, in: canvasSize(for: geometry.size))
                    })
                    .accessibilityLabel("Graphify diagram. Use Fit and Zoom controls; drag to pan.")
                } else {
                    ContentUnavailableView("Graphify diagram unavailable", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text(errorMessage ?? "No canvas loaded."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let selectedNode = document?.nodes.first(where: { $0.id == selectedNodeID }) {
                    HStack {
                        Text(selectedNode.title).font(.caption).lineLimit(1)
                        Spacer()
                        if let url = GraphifyCanvasService.noteURL(for: selectedNode, in: graphDirectory) {
                            Button("Open note") { NSWorkspace.shared.open(url) }
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                }
            }
            .background(Color.cyan.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .task(id: graphDirectory.path) {
                do {
                    document = try GraphifyCanvasService.load(from: graphDirectory)
                    errorMessage = nil
                    if let focusNoteURL {
                        focus(on: focusNoteURL, in: canvasSize(for: geometry.size))
                    } else {
                        fit(in: canvasSize(for: geometry.size))
                    }
                } catch {
                    document = nil
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: focusNoteURL?.path) { _, _ in
                if let focusNoteURL {
                    focus(on: focusNoteURL, in: canvasSize(for: geometry.size))
                } else {
                    fit(in: canvasSize(for: geometry.size))
                }
            }
        }
    }

    private func canvasSize(for total: CGSize) -> CGSize {
        CGSize(width: total.width, height: max(100, total.height - 45))
    }

    private func fit(in size: CGSize) {
        guard let bounds = document?.bounds, !bounds.isNull,
              bounds.width > 0, bounds.height > 0 else { return }
        zoom = min(max(0.9 * min(size.width / bounds.width, size.height / bounds.height), 0.01), 2)
        offset = CGSize(width: size.width / 2 - bounds.midX * zoom,
                        height: size.height / 2 - bounds.midY * zoom)
        selectedNodeID = nil
    }

    private func focus(on note: URL, in size: CGSize) {
        guard let node = document?.node(forGraphNote: note) else { fit(in: size); return }
        zoom = 0.75
        offset = CGSize(width: size.width / 2 - node.rect.midX * zoom,
                        height: size.height / 2 - node.rect.midY * zoom)
        selectedNodeID = node.id
    }

    private func changeZoom(by factor: CGFloat, in size: CGSize) {
        let newZoom = min(max(zoom * factor, 0.01), 3)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let worldX = (center.x - offset.width) / zoom
        let worldY = (center.y - offset.height) / zoom
        zoom = newZoom
        offset = CGSize(width: center.x - worldX * newZoom,
                        height: center.y - worldY * newZoom)
    }

    private func selectNode(at point: CGPoint, in size: CGSize) {
        guard let document else { return }
        let match = document.nodes.reversed().first { node in
            node.type == "file" && screenRect(node.rect, zoom: zoom, offset: offset).insetBy(dx: -3, dy: -3).contains(point)
        }
        selectedNodeID = match?.id
    }

    private func draw(_ document: GraphifyCanvasDocument, in context: inout GraphicsContext,
                      size: CGSize, zoom: CGFloat, offset: CGSize) {
        let viewport = CGRect(origin: .zero, size: size)
        let nodesByID = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        for node in document.nodes where node.type == "group" {
            let rect = screenRect(node.rect, zoom: zoom, offset: offset)
            guard rect.intersects(viewport) else { continue }
            let shape = Path(roundedRect: rect, cornerRadius: 8)
            context.fill(shape, with: .color(.cyan.opacity(0.045)))
            context.stroke(shape, with: .color(.cyan.opacity(0.17)), lineWidth: 1)
            if rect.width > 95 && rect.height > 25, let label = node.label {
                let text = context.resolve(Text(label).font(.system(size: 10)).foregroundColor(.cyan.opacity(0.7)))
                context.draw(text, at: CGPoint(x: rect.minX + 8, y: rect.minY + 10), anchor: .leading)
            }
        }
        for edge in document.edges {
            guard let from = nodesByID[edge.fromNode], let to = nodesByID[edge.toNode] else { continue }
            let start = screenPoint(from.rect.midX, from.rect.midY, zoom: zoom, offset: offset)
            let end = screenPoint(to.rect.midX, to.rect.midY, zoom: zoom, offset: offset)
            guard viewport.intersects(CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                            width: max(1, abs(start.x - end.x)),
                                            height: max(1, abs(start.y - end.y)))) else { continue }
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(.cyan.opacity(0.28)), lineWidth: 1)
        }
        for node in document.nodes where node.type == "file" {
            let rect = screenRect(node.rect, zoom: zoom, offset: offset)
            guard rect.intersects(viewport) else { continue }
            let selected = node.id == selectedNodeID
            let shape = Path(roundedRect: rect, cornerRadius: min(6, rect.height / 3))
            context.fill(shape, with: .color(selected ? .cyan : Color(red: 0.14, green: 0.28, blue: 0.39)))
            if selected { context.stroke(shape, with: .color(.white), lineWidth: 2) }
            if rect.width >= 65 && rect.height >= 22 {
                let text = context.resolve(Text(node.title).font(.system(size: 9)).foregroundColor(selected ? .black : .white))
                context.draw(text, in: rect.insetBy(dx: 4, dy: 2))
            }
        }
    }

    private func screenRect(_ rect: CGRect, zoom: CGFloat, offset: CGSize) -> CGRect {
        CGRect(x: rect.minX * zoom + offset.width,
               y: rect.minY * zoom + offset.height,
               width: rect.width * zoom, height: rect.height * zoom)
    }

    private func screenPoint(_ x: CGFloat, _ y: CGFloat, zoom: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: x * zoom + offset.width, y: y * zoom + offset.height)
    }
}
