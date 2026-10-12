import SwiftUI
import WebKit

struct MapTilerPoint: Encodable {
    let id: String
    let latitude: Double
    let longitude: Double
}

/// A vector basemap only. Forecast glyphs stay in SwiftUI so their animation and
/// accessibility do not depend on the web renderer.
struct MapTilerWeatherBasemap: NSViewRepresentable {
    let key: String
    let points: [MapTilerPoint]
    let resetCounter: Int
    let onPositions: ([String: CGPoint]) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "jarvisMap")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = NSColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1)
        webView.customUserAgent = "JARVIS-Dashboard-macOS/0.2.8"
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastResetCounter = resetCounter
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://api.maptiler.com/"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastResetCounter != resetCounter {
            context.coordinator.lastResetCounter = resetCounter
            webView.evaluateJavaScript("window.jarvisResetMap && window.jarvisResetMap()", completionHandler: nil)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "jarvisMap")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MapTilerWeatherBasemap
        var lastResetCounter = 0

        init(_ parent: MapTilerWeatherBasemap) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let encodedKey = Self.jsonString(parent.key),
                  let encodedPoints = Self.jsonData(parent.points) else {
                parent.onError("Could not prepare the MapTiler preview.")
                return
            }
            webView.evaluateJavaScript("window.jarvisStartMap(\(encodedKey), \(encodedPoints))") { [weak self] _, error in
                if error != nil { self?.parent.onError("The MapTiler preview could not start.") }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onError("MapTiler could not load. Check your internet connection.")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
            if kind == "error" {
                parent.onError("MapTiler could not load the landscape map. Check the API key and plan limits.")
            } else if kind == "positions", let items = body["items"] as? [[String: Any]] {
                var positions: [String: CGPoint] = [:]
                for item in items {
                    guard let id = item["id"] as? String,
                          let x = item["x"] as? Double,
                          let y = item["y"] as? Double,
                          x.isFinite, y.isFinite else { continue }
                    positions[id] = CGPoint(x: x, y: y)
                }
                parent.onPositions(positions)
            }
        }

        private static func jsonString(_ value: String) -> String? { jsonData(value) }

        private static func jsonData<T: Encodable>(_ value: T) -> String? {
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    private static let html = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="https://cdn.maptiler.com/maptiler-sdk-js/v4.2.0/maptiler-sdk.css" rel="stylesheet">
    <style>html,body,#map{width:100%;height:100%;margin:0;background:#071522;overflow:hidden}
    .maptiler-ctrl-attrib{font-size:10px!important}</style>
    <script src="https://cdn.maptiler.com/maptiler-sdk-js/v4.2.0/maptiler-sdk.umd.min.js"></script>
    </head><body><div id="map"></div><script>
    let jarvisMap = null;
    let jarvisPoints = [];
    let pendingFrame = 0;
    const report = (kind, items) => window.webkit.messageHandlers.jarvisMap.postMessage({kind, items});
    const reportPositions = () => {
      if (!jarvisMap || !jarvisMap.loaded()) return;
      if (pendingFrame) return;
      pendingFrame = requestAnimationFrame(() => {
        pendingFrame = 0;
        report('positions', jarvisPoints.map(p => {
          const xy = jarvisMap.project([p.longitude, p.latitude]);
          return {id:p.id, x:xy.x, y:xy.y};
        }));
      });
    };
    window.jarvisResetMap = () => {
      if (jarvisMap) jarvisMap.fitBounds([[118.0,5.2],[126.3,18.8]], {padding:55, duration:350});
    };
    window.jarvisStartMap = (key, points) => {
      if (typeof maptilersdk === 'undefined') { report('error'); return; }
      jarvisPoints = points;
      maptilersdk.config.apiKey = key;
      jarvisMap = new maptilersdk.Map({
        container:'map',
        style:'https://api.maptiler.com/maps/landscape-v4/style.json?key=' + encodeURIComponent(key),
        center:[122.1,12.0], zoom:5.1, minZoom:4, maxZoom:12,
        attributionControl:true
      });
      jarvisMap.on('load', () => { window.jarvisResetMap(); reportPositions(); });
      jarvisMap.on('move', reportPositions);
      jarvisMap.on('resize', reportPositions);
      jarvisMap.on('error', () => report('error'));
      new ResizeObserver(() => { jarvisMap.resize(); reportPositions(); }).observe(document.getElementById('map'));
    };
    </script></body></html>
    """#
}
