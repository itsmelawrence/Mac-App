import SwiftUI

/// The terminal palette shared by the Ask JARVIS button and the console.
enum ConsoleTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.085)
    static let chrome = Color(red: 0.07, green: 0.10, blue: 0.15)
    static let text = Color(white: 0.86)
    static let dim = Color(white: 0.52)
    static let accent = Color.cyan
    static let font = Font.system(size: 13, design: .monospaced)
    static let smallFont = Font.system(size: 11, design: .monospaced)
}

/// The Ask JARVIS button: braces around a blinking cursor in a small terminal tile, with no title.
///
/// Hovering spreads the braces and lights the tile; pressing presses it in. The cursor blinks while idle.
/// With Reduce Motion on, the cursor stays lit and hover changes only the colour.
struct ConsoleGlyphButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var cursorLit = true

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ConsoleTheme.chrome)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ConsoleTheme.accent.opacity(hovering ? 0.95 : 0.45), lineWidth: 1.5)
                HStack(spacing: hovering && !reduceMotion ? 6 : 1) {
                    Text("{")
                    Text("_").opacity(cursorLit ? 1 : 0.12).offset(y: -2)
                    Text("}")
                }
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(ConsoleTheme.accent)
            }
            .frame(width: 54, height: 34)
            .shadow(color: ConsoleTheme.accent.opacity(hovering ? 0.5 : 0), radius: 8)
        }
        .buttonStyle(ConsoleGlyphPressStyle(reduceMotion: reduceMotion))
        .onHover { isHovering in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.55)) {
                hovering = isHovering
            }
        }
        .task(id: reduceMotion) {
            cursorLit = true
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                withAnimation(.easeInOut(duration: 0.12)) { cursorLit.toggle() }
            }
        }
        .help("Ask JARVIS (⌘K)")
        .accessibilityLabel("Ask JARVIS")
    }
}

private struct ConsoleGlyphPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A braille spinner for "thinking"; a static ellipsis with Reduce Motion on.
struct ConsoleSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        if reduceMotion {
            Text("…")
        } else {
            TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
                let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 0.08)
                Text(Self.frames[tick % Self.frames.count])
            }
        }
    }
}
