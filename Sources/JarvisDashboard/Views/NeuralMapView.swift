import AppKit
import SwiftUI
import WebKit

/// JARVIS's own source as a 3D neural map: files are neurons, calls and references are fibres.
struct NeuralMapView: View {
    /// The ICM route and Graphify export this map shows. Every Cortex project can follow later.
    static let route = "JARVIS"

    @AppStorage("icm.vaultPath") private var vaultPath = ""
    @State private var pageURL: URL?
    @State private var errorMessage: String?
    @State private var isRebuilding = false
    @State private var reloadCount = 0

    private var vaultURL: URL { ICMRoutingService.vaultURL(configuredPath: vaultPath) }
    private var dataURL: URL { NeuralMapService.dataURL(export: Self.route, vaultURL: vaultURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Neural Map").font(.title2.bold())
                    Text("JARVIS's own source as a living brain, from its Graphify graph.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isRebuilding { ProgressView().controlSize(.small) }
                Button("Rebuild", systemImage: "arrow.clockwise", action: rebuild)
                    .disabled(isRebuilding)
                    .help("Roll the current Graphify graph up to files again")
                Button("Open in browser", systemImage: "arrow.up.right.square") {
                    if let pageURL { NSWorkspace.shared.open(pageURL) }
                }
                .disabled(pageURL == nil)
            }
            .padding(16)
            Divider()
            if let pageURL {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                NeuralMapWebView(fileURL: pageURL, reloadCount: reloadCount)
            } else {
                ContentUnavailableView("Neural map unavailable", systemImage: "brain",
                                       description: Text(errorMessage ?? "Loading the neural map."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(red: 3 / 255, green: 9 / 255, blue: 21 / 255))
        .task(id: "\(dataURL.path)|\(reloadCount)") { await load() }
    }

    private func load() async {
        let data = dataURL
        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
            guard let template = Bundle.main.url(forResource: "neural-map", withExtension: "html",
                                                  subdirectory: "NeuralMap") else {
                return .failure(NeuralMapError.missingTemplate)
            }
            return Result {
                try NeuralMapService.prepare(
                    templateURL: template, dataURL: data,
                    cacheRoot: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("JARVIS Dashboard"),
                    name: Self.route)
            }
        }.value
        switch result {
        case let .success(url):
            pageURL = url
            errorMessage = nil
        case let .failure(error):
            pageURL = nil
            errorMessage = error.localizedDescription
        }
    }

    private func rebuild() {
        let script = NeuralMapService.scriptURL(vaultURL: vaultURL)
        let vault = vaultURL
        isRebuilding = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                try? VaultMaintenanceService.run(script: script, arguments: [Self.route, "--vault", vault.path], timeout: 120)
            }.value
            isRebuilding = false
            if let result, result.status == 0 {
                reloadCount += 1
            } else {
                errorMessage = result.map { "Rebuild failed: \($0.output.suffix(400))" }
                    ?? "Rebuild could not start \(script.path)."
            }
        }
    }
}

private struct NeuralMapWebView: NSViewRepresentable {
    let fileURL: URL
    let reloadCount: Int

    final class Coordinator { var loaded: (URL, Int)? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")  // no white flash before the dark page paints
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded?.0 != fileURL || context.coordinator.loaded?.1 != reloadCount else { return }
        context.coordinator.loaded = (fileURL, reloadCount)
        view.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }
}
