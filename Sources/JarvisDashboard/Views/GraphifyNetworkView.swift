import AppKit
import SwiftUI

/// A community-coloured network built from Graphify's exported notes and links.
struct GraphifyNetworkView: View {
    let graphDirectory: URL
    let focusNoteURL: URL?

    @State private var network: GraphifyNetwork?
    @State private var errorMessage: String?
    @State private var visibleCommunities = Set<String>()
    @State private var selectedNodeID: String?
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let network {
                    Text("Graphify network · \(network.nodes.count) nodes · \(network.edges.count) links")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Graphify network").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { zoom = 1; offset = .zero }
                Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom = max(0.45, zoom * 0.75) }
                Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(5, zoom * 1.35) }
                Button("Open Graphify notes", systemImage: "arrow.up.right.square") {
                    NSWorkspace.shared.open(graphDirectory)
                }
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let network {
                HStack(spacing: 0) {
                    GeometryReader { geometry in
                        TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
                            Canvas { context, size in
                                draw(network, in: &context, size: size,
                                     time: timeline.date.timeIntervalSinceReferenceDate)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 3)
                            .updating($dragOffset) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                offset.width += value.translation.width
                                offset.height += value.translation.height
                            })
                        .simultaneousGesture(SpatialTapGesture().onEnded { value in
                            selectNode(at: value.location, in: geometry.size, network: network)
                        })
                    }
                    .background(Color(red: 0.035, green: 0.04, blue: 0.09))
                    .clipped()
                    communitiesPanel(network)
                        .frame(width: 235)
                        .background(Color(red: 0.085, green: 0.09, blue: 0.16))
                }
                if let selected = network.nodes.first(where: { $0.id == selectedNodeID }) {
                    HStack {
                        Circle().fill(color(for: selected.community, in: network)).frame(width: 8, height: 8)
                        Text(selected.title).font(.caption).lineLimit(1)
                        Text(selected.community).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Graphify note") { NSWorkspace.shared.open(selected.url) }
                            .font(.caption)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
            } else {
                ContentUnavailableView("Graphify network unavailable", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text(errorMessage ?? "No network loaded."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.cyan.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: graphDirectory.path) {
            do {
                let loaded = try GraphifyNetworkService.load(from: graphDirectory)
                network = loaded
                visibleCommunities = Set(loaded.communities.map(\.name))
                selectedNodeID = loaded.nodes.first(where: { $0.url == focusNoteURL })?.id
                errorMessage = nil
                zoom = 1; offset = .zero
            } catch {
                network = nil
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: focusNoteURL?.path) { _, path in
            selectedNodeID = network?.nodes.first(where: { $0.url.path == path })?.id
        }
    }

    private func communitiesPanel(_ network: GraphifyNetwork) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("COMMUNITIES")
                .font(.caption.bold()).tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            Button {
                visibleCommunities = visibleCommunities.count == network.communities.count
                    ? [] : Set(network.communities.map(\.name))
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: visibleCommunities.count == network.communities.count
                          ? "checkmark.square.fill" : "square")
                        .foregroundStyle(.blue)
                    Text("Select All")
                    Spacer()
                }
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(network.communities, id: \.name) { community in
                        Button {
                            if visibleCommunities.contains(community.name) {
                                visibleCommunities.remove(community.name)
                            } else {
                                visibleCommunities.insert(community.name)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: visibleCommunities.contains(community.name)
                                      ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(.blue)
                                Circle().fill(color(for: community.name, in: network))
                                    .frame(width: 10, height: 10)
                                Text(community.name).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(community.count)").foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("\(visibleCommunities.count) of \(network.communities.count) communities")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(12)
        }
    }

    private func color(for community: String, in network: GraphifyNetwork) -> Color {
        let index = network.communities.firstIndex(where: { $0.name == community }) ?? 0
        return Color(hue: (Double(index) * 0.61803398875).truncatingRemainder(dividingBy: 1),
                     saturation: 0.57, brightness: 0.9)
    }

    private func point(_ node: GraphifyNetwork.Node, in size: CGSize) -> CGPoint {
        let scale = min(size.width / 800, size.height / 630) * zoom
        return CGPoint(x: size.width / 2 + CGFloat(node.x) * scale + offset.width + dragOffset.width,
                       y: size.height / 2 + CGFloat(node.y) * scale + offset.height + dragOffset.height)
    }

    private func draw(_ network: GraphifyNetwork, in context: inout GraphicsContext,
                      size: CGSize, time: TimeInterval) {
        let points = network.nodes.map { point($0, in: size) }
        let palette = Dictionary(uniqueKeysWithValues: network.communities.map { ($0.name, color(for: $0.name, in: network)) })
        for edge in network.edges {
            let source = network.nodes[edge.source], target = network.nodes[edge.target]
            guard visibleCommunities.contains(source.community), visibleCommunities.contains(target.community) else { continue }
            var path = Path()
            path.move(to: points[edge.source]); path.addLine(to: points[edge.target])
            context.stroke(path, with: .color((palette[source.community] ?? .cyan).opacity(0.20)), lineWidth: 0.7)
        }
        for (index, node) in network.nodes.enumerated() where visibleCommunities.contains(node.community) {
            let position = points[index]
            let isSelected = node.id == selectedNodeID
            let radius: CGFloat = isSelected ? 5 : 2.2
            context.fill(Path(ellipseIn: CGRect(x: position.x-radius, y: position.y-radius,
                                                width: radius*2, height: radius*2)),
                         with: .color(isSelected ? .white : (palette[node.community] ?? .cyan)))
        }
        // Sparse travelling impulses keep the map alive without obscuring the real links.
        if !network.edges.isEmpty {
            let pulseCount = min(24, network.edges.count)
            for pulse in 0..<pulseCount {
                let edgeIndex = (pulse * 97 + Int(time / 4) * 53) % network.edges.count
                let edge = network.edges[edgeIndex]
                let source = network.nodes[edge.source], target = network.nodes[edge.target]
                guard visibleCommunities.contains(source.community), visibleCommunities.contains(target.community) else { continue }
                let progress = CGFloat((time * 0.46 + Double(pulse) * 0.173).truncatingRemainder(dividingBy: 1))
                let a = points[edge.source], b = points[edge.target]
                let x = a.x + (b.x - a.x) * progress
                let y = a.y + (b.y - a.y) * progress
                context.fill(Path(ellipseIn: CGRect(x: x-2.5, y: y-2.5, width: 5, height: 5)),
                             with: .color(.white.opacity(0.9)))
            }
        }
    }

    private func selectNode(at location: CGPoint, in size: CGSize, network: GraphifyNetwork) {
        selectedNodeID = network.nodes
            .filter { visibleCommunities.contains($0.community) }
            .min { first, second in
                let a = point(first, in: size), b = point(second, in: size)
                return hypot(a.x-location.x, a.y-location.y) < hypot(b.x-location.x, b.y-location.y)
            }
            .flatMap { node in
                let p = point(node, in: size)
                return hypot(p.x-location.x, p.y-location.y) <= 9 ? node.id : nil
            }
    }
}
