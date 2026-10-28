import SwiftUI
import WebKit

struct MapTilerPoint: Encodable {
    let id: String
    let latitude: Double
    let longitude: Double
}

enum MapTilerBasemapStyle: String {
    case landscape
    case satellite
}

/// A basemap only. Forecast glyphs stay in SwiftUI so their animation and
/// accessibility do not depend on the web renderer.
struct MapTilerWeatherBasemap: NSViewRepresentable {
    let key: String
    let style: MapTilerBasemapStyle
    let points: [MapTilerPoint]
    let resetCounter: Int
    let cloudRefreshCounter: Int
    let onPositions: ([String: CGPoint]) -> Void
    let onStatus: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "jarvisMap")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = NSColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1)
        webView.customUserAgent = "JARVIS-Dashboard-macOS/0.2.12"
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastResetCounter = resetCounter
        context.coordinator.lastCloudRefreshCounter = cloudRefreshCounter
        context.coordinator.lastStyle = style
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://api.maptiler.com/"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastStyle != style {
            context.coordinator.lastStyle = style
            webView.evaluateJavaScript("window.jarvisSetStyle && window.jarvisSetStyle('\(style.rawValue)')", completionHandler: nil)
        }
        if context.coordinator.lastResetCounter != resetCounter {
            context.coordinator.lastResetCounter = resetCounter
            webView.evaluateJavaScript("window.jarvisResetMap && window.jarvisResetMap()", completionHandler: nil)
        }
        if context.coordinator.lastCloudRefreshCounter != cloudRefreshCounter {
            context.coordinator.lastCloudRefreshCounter = cloudRefreshCounter
            webView.evaluateJavaScript("window.jarvisRefreshClouds && window.jarvisRefreshClouds()", completionHandler: nil)
        }
        // Forecast points often arrive after the page has loaded; push changes once the map has started.
        if context.coordinator.didStartMap, let encoded = Coordinator.jsonData(points),
           encoded != context.coordinator.lastSentPoints {
            context.coordinator.lastSentPoints = encoded
            webView.evaluateJavaScript("window.jarvisSetPoints && window.jarvisSetPoints(\(encoded))", completionHandler: nil)
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
        var lastCloudRefreshCounter = 0
        var lastStyle: MapTilerBasemapStyle = .landscape
        var didStartMap = false
        var lastSentPoints: String?

        init(_ parent: MapTilerWeatherBasemap) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let encodedKey = Self.jsonString(parent.key),
                  let encodedPoints = Self.jsonData(parent.points) else {
                parent.onStatus("Could not prepare the MapTiler preview.")
                return
            }
            didStartMap = true
            lastSentPoints = encodedPoints
            webView.evaluateJavaScript("window.jarvisStartMap(\(encodedKey), \(encodedPoints), '\(parent.style.rawValue)')") { [weak self] _, error in
                if error != nil { self?.parent.onStatus("The MapTiler preview could not start.") }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onStatus("MapTiler could not load. Check your internet connection.")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
            if kind == "error" {
                parent.onStatus("MapTiler could not load the map. Check the API key and plan limits.")
            } else if kind == "cloudError" {
                parent.onStatus("NOAA cloud imagery is unavailable right now; the satellite basemap is still usable.")
            } else if kind == "ready" {
                parent.onStatus(nil)
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

        fileprivate static func jsonData<T: Encodable>(_ value: T) -> String? {
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
    const cloudSourceID = 'jarvis-noaa-clouds';
    const cloudLayerID = 'jarvis-noaa-clouds-layer';
    const cloudTiles = 'https://gis.nnvl.noaa.gov/arcgis/rest/services/GOES/GOES_current/ImageServer/tile/{z}/{y}/{x}';
    let jarvisCurrentStyle = 'landscape';
    let baseStyleReady = false;
    const addCloudLayer = () => {
      if (!jarvisMap || jarvisMap.getSource(cloudSourceID)) return;
      jarvisMap.addSource(cloudSourceID, {
        type:'raster', tiles:[cloudTiles + '?v=' + Math.floor(Date.now() / 600000)],
        tileSize:256, minzoom:0, maxzoom:8,
        attribution:'Cloud imagery: NOAA/NESDIS'
      });
      jarvisMap.addLayer({
        id:cloudLayerID, type:'raster', source:cloudSourceID,
        paint:{'raster-opacity':0.58, 'raster-contrast':0.22, 'raster-fade-duration':0}
      });
    };
    let jarvisStyle = (key, style) => style === 'satellite'
      ? maptilersdk.MapStyle.SATELLITE
      : 'https://api.maptiler.com/maps/landscape-v4/style.json?key=' + encodeURIComponent(key);
    const report = (kind, items) => window.webkit.messageHandlers.jarvisMap.postMessage({kind, items});
    const reportPositions = () => {
      if (!jarvisMap) return;
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
    window.jarvisSetStyle = (style) => {
      jarvisCurrentStyle = style;
      baseStyleReady = false;
      if (jarvisMap) jarvisMap.setStyle(jarvisStyle(maptilersdk.config.apiKey, style));
    };
    window.jarvisRefreshClouds = () => {
      if (!jarvisMap || jarvisCurrentStyle !== 'satellite') return;
      if (jarvisMap.getLayer(cloudLayerID)) jarvisMap.removeLayer(cloudLayerID);
      if (jarvisMap.getSource(cloudSourceID)) jarvisMap.removeSource(cloudSourceID);
      addCloudLayer();
    };
    window.jarvisSetPoints = (points) => {
      jarvisPoints = points;
      if (jarvisMap) reportPositions();
    };
    window.jarvisStartMap = (key, points, style) => {
      if (typeof maptilersdk === 'undefined') { report('error'); return; }
      jarvisPoints = points;
      jarvisCurrentStyle = style;
      maptilersdk.config.apiKey = key;
      jarvisMap = new maptilersdk.Map({
        container:'map',
        style:jarvisStyle(key, style),
        center:[122.1,12.0], zoom:5.1, minZoom:4, maxZoom:12,
        attributionControl:true, geolocateControl:false
      });
      jarvisMap.on('load', () => { window.jarvisResetMap(); reportPositions(); report('ready'); });
      jarvisMap.on('style.load', () => {
        baseStyleReady = true;
        if (jarvisCurrentStyle === 'satellite') addCloudLayer();
        reportPositions(); report('ready');
      });
      jarvisMap.on('move', reportPositions);
      jarvisMap.on('resize', reportPositions);
      // Individual tile/auxiliary requests can fail even while the basemap renders.
      // Only surface a map-loading error before the main style becomes available.
      jarvisMap.on('error', event => {
        if (event.sourceId === cloudSourceID) report('cloudError');
        else if (!baseStyleReady) report('error');
      });
      new ResizeObserver(() => { jarvisMap.resize(); reportPositions(); }).observe(document.getElementById('map'));
    };
    </script></body></html>
    """#
}
