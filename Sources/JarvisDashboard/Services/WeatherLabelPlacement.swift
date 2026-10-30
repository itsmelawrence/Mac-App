import Foundation
import SwiftUI

/// How much of a city's weather chip fits on the map. A crowded city shrinks instead of disappearing,
/// so every forecast point keeps a marker at its exact coordinate.
enum WeatherChipStyle: Equatable {
    /// Weather symbol, city name, and value.
    case full
    /// Weather symbol and value.
    case compact
    /// Only the coloured dot at the coordinate.
    case dot
}

/// Which side of the coordinate the chip sits on; a short stem joins the two.
enum WeatherChipEdge: Equatable {
    case above, below
}

struct WeatherChipPlacement: Equatable {
    let style: WeatherChipStyle
    let edge: WeatherChipEdge
}

struct WeatherChipCandidate {
    let id: String
    /// Screen position of the coordinate; nil when the map cannot convert it yet.
    let position: CGPoint?
    let fullSize: CGSize
    let compactSize: CGSize
    let priority: Int
    let isFocused: Bool
}

enum WeatherChipLayout {
    static let chipHeight: CGFloat = 26
    /// The stem between the dot's frame and the chip.
    static let stemLength: CGFloat = 8
    static let dotSize: CGFloat = 8
    /// The dot's hit and selection-ring area, centred on the coordinate.
    static let dotFrame: CGFloat = 14

    /// The chip's frame for a coordinate at `point`.
    static func rect(size: CGSize, edge: WeatherChipEdge, at point: CGPoint) -> CGRect {
        let gap = dotFrame / 2 + stemLength
        let y = edge == .above ? point.y - gap - size.height : point.y + gap
        return CGRect(x: point.x - size.width / 2, y: y, width: size.width, height: size.height)
    }

    /// Where the coordinate falls in a marker's frame, as a unit point for map annotation anchors.
    static func anchor(for placement: WeatherChipPlacement) -> UnitPoint {
        guard placement.style != .dot else { return .center }
        let height = chipHeight + stemLength + dotFrame
        let y = placement.edge == .above ? (height - dotFrame / 2) / height : (dotFrame / 2) / height
        return UnitPoint(x: 0.5, y: y)
    }

    /// Focused points first, then by priority. Each takes the largest chip that fits without covering another
    /// chip or another city's dot, keeping its previous edge while that still fits; otherwise it becomes a dot.
    /// Points off screen are left out.
    static func place(
        _ candidates: [WeatherChipCandidate],
        viewSize: CGSize,
        showNames: Bool,
        previous: [String: WeatherChipPlacement] = [:]
    ) -> [String: WeatherChipPlacement] {
        let bounds = CGRect(origin: .zero, size: viewSize).insetBy(dx: 4, dy: 4)
        let visible = candidates.filter { $0.position.map(bounds.contains) ?? false }
        let dots = visible.map { candidate -> (String, CGRect) in
            let point = candidate.position!
            // Slightly larger than the drawn dot, so a chip never sits right on another city's marker.
            let side = dotSize + 6
            return (candidate.id, CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
        }
        let ordered = visible.sorted {
            if $0.isFocused != $1.isFocused { return $0.isFocused }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }

        var result: [String: WeatherChipPlacement] = [:]
        var taken: [CGRect] = []
        for candidate in ordered {
            let point = candidate.position!
            let styles: [WeatherChipStyle] = showNames || candidate.isFocused ? [.full, .compact] : [.compact]
            var edges: [WeatherChipEdge] = [.above, .below]
            if let old = previous[candidate.id]?.edge, old == .below { edges = [.below, .above] }

            var chosen: (WeatherChipPlacement, CGRect)?
            search: for style in styles {
                let size = style == .full ? candidate.fullSize : candidate.compactSize
                for edge in edges {
                    let rect = rect(size: size, edge: edge, at: point)
                    guard bounds.contains(rect),
                          !taken.contains(where: { $0.intersects(rect) }),
                          !dots.contains(where: { $0.0 != candidate.id && $0.1.intersects(rect) }) else { continue }
                    chosen = (WeatherChipPlacement(style: style, edge: edge), rect)
                    break search
                }
            }
            if let chosen {
                result[candidate.id] = chosen.0
                taken.append(chosen.1)
            } else {
                result[candidate.id] = WeatherChipPlacement(style: .dot, edge: previous[candidate.id]?.edge ?? .above)
            }
        }
        return result
    }
}
