import SwiftUI

/// Native rendering of the supplied 64×64 SVG weather-icon motion designs.
/// Canvas animates the weather itself (drops, rays, mist, lightning), not the whole icon.
struct AnimatedWeatherGlyph: View {
    let condition: WeatherPointCondition
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if condition == .unknown {
                Image(systemName: condition.systemImage)
                    .font(.system(size: size * 0.65))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
                    Canvas(opaque: false) { graphics, canvasSize in
                        var graphics = graphics
                        graphics.scaleBy(x: canvasSize.width / 64, y: canvasSize.height / 64)
                        WeatherIconDrawing.draw(condition, in: &graphics,
                                                time: timeline.date.timeIntervalSinceReferenceDate,
                                                reducedMotion: reduceMotion)
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .accessibilityLabel(condition.title)
        .accessibilityHidden(false)
    }
}

enum WeatherIconMotion {
    static func fraction(time: Double, period: Double, delay: Double = 0) -> Double {
        let value = (time + delay) / period
        return value - floor(value)
    }

    static func thunderFlash(time: Double) -> Double {
        let phase = fraction(time: time, period: 3.2)
        let first = max(0, 1 - abs(phase - 0.55) / 0.035)
        let second = max(0, 1 - abs(phase - 0.63) / 0.045)
        return max(first, second)
    }
}

private enum WeatherIconDrawing {
    private static let white = Color(red: 0.99, green: 0.995, blue: 1)
    private static let cloudBase = Color(red: 0.73, green: 0.82, blue: 0.89)
    private static let cloudDark = Color(red: 0.38, green: 0.45, blue: 0.53)
    private static let rain = Color(red: 0.37, green: 0.83, blue: 1)
    private static let lightRain = Color(red: 0.50, green: 0.86, blue: 1)
    private static let heavyRain = Color(red: 0.25, green: 0.76, blue: 1)
    private static let sun = Color(red: 1, green: 0.69, blue: 0.13)
    private static let bolt = Color(red: 1, green: 0.82, blue: 0.25)

    static func draw(_ condition: WeatherPointCondition, in graphics: inout GraphicsContext,
                     time: Double, reducedMotion: Bool) {
        switch condition {
        case .clear:
            drawSun(in: &graphics, x: 32, y: 32, scale: 1, time: time, reducedMotion: reducedMotion)
        case .partlyCloudy:
            drawSun(in: &graphics, x: 24, y: 24, scale: 0.78, time: time, reducedMotion: reducedMotion)
            drawCloud(in: &graphics, x: 8 + drift(time, period: 7, range: 2, reducedMotion: reducedMotion),
                      y: 12, scale: 0.88, top: white, bottom: cloudBase)
        case .cloudy:
            drawCloud(in: &graphics, x: 18 + drift(time, period: 9, range: -2.5, reducedMotion: reducedMotion),
                      y: 2, scale: 0.70, top: cloudBase, bottom: cloudDark)
            drawCloud(in: &graphics, x: -1 + drift(time, period: 7, range: 2, reducedMotion: reducedMotion),
                      y: 8, scale: 0.95, top: white, bottom: cloudBase)
        case .fog:
            drawCloud(in: &graphics, x: 6 + drift(time, period: 7, range: 2, reducedMotion: reducedMotion),
                      y: -1, scale: 0.80, top: white, bottom: cloudBase)
            for (index, y) in [43.0, 50.0, 57.0].enumerated() {
                let phase = time * 2 * .pi / 4.5 + Double(index) * 2.1
                let offset = reducedMotion ? 0 : sin(phase) * 3
                let opacity = reducedMotion ? 0.8 : 0.72 + 0.28 * sin(phase)
                var mist = Path()
                mist.move(to: CGPoint(x: (index == 1 ? 12 : index == 2 ? 18 : 15) + offset, y: y))
                mist.addLine(to: CGPoint(x: (index == 1 ? 44 : index == 2 ? 52 : 49) + offset, y: y))
                graphics.stroke(mist, with: .color(cloudBase.opacity(opacity)),
                                style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
            }
        case .showers:
            drawRain(in: &graphics, count: 3, startX: 24, spacing: 8, startY: 38,
                     length: 4, travel: 12, slant: 2, width: 2.4, period: 2.6,
                     color: lightRain, time: time, reducedMotion: reducedMotion)
            drawCloud(in: &graphics, x: 3 + drift(time, period: 7, range: 2, reducedMotion: reducedMotion),
                      y: -3, scale: 0.90, top: white, bottom: cloudBase)
        case .rain:
            drawRain(in: &graphics, count: 4, startX: 20, spacing: 8, startY: 38,
                     length: 6, travel: 15, slant: 4, width: 2.8, period: 1.2,
                     color: rain, time: time, reducedMotion: reducedMotion)
            drawCloud(in: &graphics, x: 3 + drift(time, period: 7, range: 2, reducedMotion: reducedMotion),
                      y: -3, scale: 0.90, top: white, bottom: cloudBase)
        case .heavyRain:
            drawRain(in: &graphics, count: 6, startX: 16, spacing: 6, startY: 36,
                     length: 7, travel: 18, slant: 6, width: 3, period: 0.7,
                     color: heavyRain, time: time, reducedMotion: reducedMotion)
            drawCloud(in: &graphics, x: 3, y: -3 + rumble(time, reducedMotion: reducedMotion),
                      scale: 0.90, top: cloudBase, bottom: cloudDark)
        case .thunderstorm:
            drawRain(in: &graphics, count: 2, startX: 17, spacing: 31, startY: 36,
                     length: 6, travel: 18, slant: 6, width: 2.8, period: 0.7,
                     color: heavyRain, time: time, reducedMotion: reducedMotion)
            let cloudY = -5 + rumble(time, reducedMotion: reducedMotion)
            drawCloud(in: &graphics, x: 3, y: cloudY, scale: 0.90,
                      top: cloudDark, bottom: Color(red: 0.22, green: 0.27, blue: 0.33))
            let flash = reducedMotion ? 1 : WeatherIconMotion.thunderFlash(time: time)
            if flash > 0 {
                drawCloud(in: &graphics, x: 3, y: cloudY, scale: 0.90,
                          top: white.opacity(flash * 0.38), bottom: white.opacity(flash * 0.15))
            }
            var lightning = Path()
            lightning.move(to: CGPoint(x: 36, y: 32))
            for point in [CGPoint(x: 27, y: 46), CGPoint(x: 33, y: 46), CGPoint(x: 30, y: 58),
                          CGPoint(x: 42, y: 41), CGPoint(x: 35, y: 41), CGPoint(x: 40, y: 32)] {
                lightning.addLine(to: point)
            }
            lightning.closeSubpath()
            graphics.fill(lightning, with: .color(bolt.opacity(flash)))
            graphics.stroke(lightning, with: .color(white.opacity(flash)), lineWidth: 0.8)
        case .unknown:
            break
        }
    }

    private static func drawSun(in graphics: inout GraphicsContext, x: Double, y: Double,
                                scale: Double, time: Double, reducedMotion: Bool) {
        let pulse = reducedMotion ? 0 : sin(time * 2 * .pi / 3.4)
        let haloRadius = (19 + 2.2 * pulse) * scale
        graphics.fill(Path(ellipseIn: CGRect(x: x - haloRadius, y: y - haloRadius,
                                            width: haloRadius * 2, height: haloRadius * 2)),
                      with: .color(sun.opacity(0.24 + 0.10 * pulse)))
        let rotation = reducedMotion ? 0 : time * 2 * .pi / 28
        for index in 0..<8 {
            let angle = rotation + Double(index) * .pi / 4
            let start = CGPoint(x: x + cos(angle) * 18 * scale, y: y + sin(angle) * 18 * scale)
            let end = CGPoint(x: x + cos(angle) * 24 * scale, y: y + sin(angle) * 24 * scale)
            var ray = Path()
            ray.move(to: start)
            ray.addLine(to: end)
            graphics.stroke(ray, with: .color(sun),
                            style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round))
        }
        let radius = 12 * scale
        graphics.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                            width: radius * 2, height: radius * 2)),
                      with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.71), sun]),
                                            center: CGPoint(x: x - radius * 0.2, y: y - radius * 0.2),
                                            startRadius: 1, endRadius: radius * 1.8))
    }

    private static func drawCloud(in graphics: inout GraphicsContext, x: Double, y: Double,
                                  scale: Double, top: Color, bottom: Color) {
        let path = cloudPath.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y))
        graphics.fill(path, with: .linearGradient(Gradient(colors: [top, bottom]),
                                                 startPoint: CGPoint(x: 32, y: y + 17 * scale),
                                                 endPoint: CGPoint(x: 32, y: y + 47 * scale)))
    }

    private static let cloudPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 20, y: 46))
        path.addCurve(to: CGPoint(x: 19, y: 28), control1: CGPoint(x: 8, y: 46),
                      control2: CGPoint(x: 9, y: 30))
        path.addCurve(to: CGPoint(x: 44, y: 25), control1: CGPoint(x: 18, y: 14),
                      control2: CGPoint(x: 37, y: 10))
        path.addCurve(to: CGPoint(x: 47, y: 46), control1: CGPoint(x: 55, y: 20),
                      control2: CGPoint(x: 59, y: 43))
        path.closeSubpath()
        return path
    }()

    private static func drawRain(in graphics: inout GraphicsContext, count: Int,
                                 startX: Double, spacing: Double, startY: Double,
                                 length: Double, travel: Double, slant: Double,
                                 width: Double, period: Double, color: Color,
                                 time: Double, reducedMotion: Bool) {
        for index in 0..<count {
            let progress = reducedMotion
                ? 0.36 + Double(index % 3) * 0.14
                : WeatherIconMotion.fraction(time: time, period: period,
                                             delay: Double(index) * period / Double(count))
            let opacity = reducedMotion ? 0.9 : min(1, min(progress / 0.14, (1 - progress) / 0.24))
            let start = CGPoint(x: startX + Double(index) * spacing - slant * progress,
                                y: startY + travel * progress)
            var streak = Path()
            streak.move(to: start)
            streak.addLine(to: CGPoint(x: start.x - length * 0.28, y: start.y + length))
            graphics.stroke(streak, with: .color(color.opacity(max(0, opacity))),
                            style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    private static func drift(_ time: Double, period: Double, range: Double,
                              reducedMotion: Bool) -> Double {
        reducedMotion ? 0 : sin(time * 2 * .pi / period) * range
    }

    private static func rumble(_ time: Double, reducedMotion: Bool) -> Double {
        reducedMotion ? 0 : sin(time * 2 * .pi / 0.45) * 0.8
    }
}
