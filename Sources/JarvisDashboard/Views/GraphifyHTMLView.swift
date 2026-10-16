import AppKit
import SwiftUI
import WebKit

/// Hosts Graphify's own generated graph.html, including its search and community controls.
struct GraphifyHTMLView: View {
    let htmlURL: URL
    let focusSourcePath: String?

    @State private var viewerURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Graphify diagram")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open original", systemImage: "arrow.up.right.square") {
                    NSWorkspace.shared.open(htmlURL)
                }
                .disabled(!FileManager.default.fileExists(atPath: htmlURL.path))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let viewerURL {
                GraphifyWebView(fileURL: viewerURL, focusSourcePath: focusSourcePath) { error in
                    errorMessage = error
                }
            } else {
                ContentUnavailableView("Graphify diagram unavailable", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text(errorMessage ?? "Loading Graphify's diagram."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.cyan.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: htmlURL.path) {
            do {
                guard let library = Bundle.main.url(forResource: "vis-network.min", withExtension: "js",
                                                     subdirectory: "GraphifyViewer") else {
                    throw GraphifyHTMLError.missingViewerLibrary
                }
                viewerURL = try GraphifyHTMLService.prepare(
                    sourceURL: htmlURL, libraryURL: library,
                    cacheRoot: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("JARVIS Dashboard"))
                errorMessage = nil
            } catch {
                viewerURL = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct GraphifyWebView: NSViewRepresentable {
    let fileURL: URL
    let focusSourcePath: String?
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onError = onError
        context.coordinator.focusSourcePath = focusSourcePath
        if context.coordinator.loadedURL != fileURL {
            context.coordinator.loadedURL = fileURL
            context.coordinator.didLoad = false
            context.coordinator.lastFocusedPath = nil
            view.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else if context.coordinator.didLoad {
            context.coordinator.focus(in: view)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onError: (String) -> Void
        var loadedURL: URL?
        var focusSourcePath: String?
        var lastFocusedPath: String?
        var didLoad = false

        init(onError: @escaping (String) -> Void) { self.onError = onError }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoad = true
            webView.evaluateJavaScript(Self.pulseScript) { [weak self] result, error in
                if error != nil || (result as? Bool) != true {
                    self?.onError("Graphify's viewer could not start. Check the local graph.html export.")
                }
            }
            focus(in: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            onError(error.localizedDescription)
        }

        func focus(in webView: WKWebView) {
            guard focusSourcePath != lastFocusedPath else { return }
            lastFocusedPath = focusSourcePath
            guard let focusSourcePath,
                  let data = try? JSONEncoder().encode(focusSourcePath),
                  let quoted = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("""
                (function () {
                  if (typeof RAW_NODES === 'undefined' || typeof focusNode !== 'function') return;
                  const matches = RAW_NODES.filter(n => n.source_file === \(quoted));
                  if (matches.length) {
                    matches.sort((a, b) => (b.degree || 0) - (a.degree || 0));
                    focusNode(matches[0].id);
                  }
                })();
                """)
        }

        private static let pulseScript = """
            (function () {
              if (typeof network === 'undefined' || typeof RAW_EDGES === 'undefined') return false;
              if (window.__jarvisGraphifyPulses) return true;
              window.__jarvisGraphifyPulses = true;
              const pulseEdges = RAW_EDGES.filter(e => e.from && e.to);
              network.on('afterDrawing', function (ctx) {
                if (!pulseEdges.length) return;
                const now = performance.now() / 1000;
                const count = Math.min(24, pulseEdges.length);
                for (let i = 0; i < count; i++) {
                  const edge = pulseEdges[(i * 97 + Math.floor(now / 4) * 53) % pulseEdges.length];
                  const positions = network.getPositions([edge.from, edge.to]);
                  const a = positions[edge.from], b = positions[edge.to];
                  if (!a || !b) continue;
                  const t = (now * 0.46 + i * 0.173) % 1;
                  ctx.beginPath();
                  ctx.arc(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, 2.6, 0, 2 * Math.PI);
                  ctx.fillStyle = 'rgba(255,255,255,0.88)';
                  ctx.fill();
                }
              });
              window.setInterval(() => network.redraw(), 80);
              return true;
            })();
            """
    }
}
