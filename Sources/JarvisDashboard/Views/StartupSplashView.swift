import AppKit
import SwiftUI
import WebKit

struct StartupSplashView: NSViewRepresentable {
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.messageHandlerName)
        controller.addUserScript(
            WKUserScript(
                source: Self.completionBridge,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let webView = SplashWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        if let splashURL = Bundle.main.url(forResource: "jarvis-startup", withExtension: "html") {
            webView.splashURL = splashURL
        } else {
            context.coordinator.finishOnce()
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageHandlerName)
        nsView.stopLoading()
    }

    private static let completionBridge = """
    (() => {
      window.__TAURI__ = true;
      var sent = false;
      const finish = () => {
        if (sent) return;
        sent = true;
        window.webkit.messageHandlers.jarvisSplash.postMessage({ type: 'jarvis-splash-done' });
      };
      window.addEventListener('splash:done', finish, { once: true });
      window.addEventListener('message', event => {
        if (event.data && event.data.type === 'jarvis-splash-done') finish();
      });
    })();
    """

    final class SplashWebView: WKWebView {
        var splashURL: URL?
        private var hasStartedLoading = false

        override func layout() {
            super.layout()

            guard !hasStartedLoading,
                  bounds.width > 0,
                  bounds.height > 0,
                  let splashURL
            else { return }

            hasStartedLoading = true
            loadFileURL(splashURL, allowingReadAccessTo: splashURL.deletingLastPathComponent())
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageHandlerName = "jarvisSplash"

        private let onFinished: () -> Void
        private var hasFinished = false

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageHandlerName else { return }
            finishOnce()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finishOnce()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finishOnce()
        }

        func finishOnce() {
            guard !hasFinished else { return }
            hasFinished = true
            Task { @MainActor in onFinished() }
        }
    }
}

struct WindowFirstPaintConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowObserverView {
        WindowObserverView()
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {}

    final class WindowObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.backgroundColor = NSColor(
                calibratedRed: 2 / 255,
                green: 6 / 255,
                blue: 12 / 255,
                alpha: 1
            )
            window.isOpaque = true
        }
    }
}
