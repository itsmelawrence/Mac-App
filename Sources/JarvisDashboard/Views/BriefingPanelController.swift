import AppKit
import SwiftUI

@MainActor
final class BriefingPanelController {
    static let shared = BriefingPanelController()

    private var panel: NSPanel?

    func show(reason: AppState.BriefingReason, message: String? = nil) {
        panel?.close()
        SpeechService.shared.stop()

        let displayMessage = Self.message(for: reason, suppliedMessage: message)
        let content = BriefingOverlayView(message: displayMessage, speechService: .shared) { [weak self] in
            SpeechService.shared.stop()
            self?.panel?.close()
        }
        let hostingView = NSHostingView(rootView: content)
        let size = NSSize(width: 640, height: 360)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 520, height: 300)
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.panel = panel

        if reason == .wake {
            SpeechService.shared.speakWakeBriefing(displayMessage)
        }
    }

    private static func message(for reason: AppState.BriefingReason, suppliedMessage: String?) -> String {
        if let suppliedMessage, !suppliedMessage.isEmpty {
            return suppliedMessage
        }
        return switch reason {
        case .launch:
            "Systems are online and your command centre is ready."
        case .wake:
            "Welcome back, Sir. Your dashboard has refreshed its live intelligence."
        case .manual:
            "All systems are standing by. Open the command centre for your complete briefing."
        }
    }
}

private struct BriefingOverlayView: View {
    let message: String
    @ObservedObject var speechService: SpeechService
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("JARVIS").font(.title2.bold())
                    Text(Date.now.formatted(date: .complete, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollView(.vertical) {
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                if speechService.isSpeaking {
                    Button("Stop", systemImage: "stop.fill") { speechService.stop() }
                } else {
                    Button("Speak", systemImage: "speaker.wave.2.fill") {
                        speechService.speak(message)
                    }
                    .disabled(!speechService.isEnabled)
                }
                Button("Dismiss", action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .background(.ultraThinMaterial)
    }
}
