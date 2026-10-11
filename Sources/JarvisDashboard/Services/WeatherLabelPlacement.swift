import Foundation

enum WeatherLabelSide: String, CaseIterable, Equatable {
    case right, left, above, below

    func rect(around point: CGPoint, labelSize: CGSize, beaconSize: CGFloat = 44) -> CGRect {
        let distance = beaconSize / 2 + 5
        let centre: CGPoint
        switch self {
        case .right: centre = CGPoint(x: point.x + distance + labelSize.width / 2, y: point.y)
        case .left: centre = CGPoint(x: point.x - distance - labelSize.width / 2, y: point.y)
        case .above: centre = CGPoint(x: point.x, y: point.y - distance - labelSize.height / 2)
        case .below: centre = CGPoint(x: point.x, y: point.y + distance + labelSize.height / 2)
        }
        return CGRect(x: centre.x - labelSize.width / 2, y: centre.y - labelSize.height / 2,
                      width: labelSize.width, height: labelSize.height)
    }
}

struct WeatherLabelPoint {
    let id: String
    let position: CGPoint?
    let labelSize: CGSize
    let priority: Int
    let isFocused: Bool
}

enum WeatherLabelPlacer {
    static func place(
        points: [WeatherLabelPoint],
        viewSize: CGSize,
        maxLabels: Int,
        previous: [String: WeatherLabelSide]
    ) -> [String: WeatherLabelSide] {
        let bounds = CGRect(origin: .zero, size: viewSize).insetBy(dx: 5, dy: 5)
        let beacons = points.compactMap { point -> (String, CGRect)? in
            guard let position = point.position, bounds.contains(position) else { return nil }
            return (point.id, CGRect(x: position.x - 25, y: position.y - 25, width: 50, height: 50))
        }
        let ordered = points.sorted {
            if $0.isFocused != $1.isFocused { return $0.isFocused }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }
        var chosen: [String: WeatherLabelSide] = [:]
        var labelRects: [CGRect] = []
        for point in ordered {
            guard let position = point.position, bounds.contains(position) else { continue }
            if chosen.count >= maxLabels && !point.isFocused { continue }
            var sides = WeatherLabelSide.allCases
            if let old = previous[point.id] {
                sides.removeAll { $0 == old }
                sides.insert(old, at: 0)
            }
            let candidates = sides.map { ($0, $0.rect(around: position, labelSize: point.labelSize)) }
            let inside = candidates.filter { bounds.contains($0.1) }
            let clear = inside.first { _, rect in
                !labelRects.contains(where: { $0.intersects(rect) }) &&
                !beacons.contains(where: { $0.0 != point.id && $0.1.intersects(rect) })
            }
            // A focused point keeps a label if space is tight, but never at a fabricated origin.
            guard let selected = clear ?? (point.isFocused ? inside.first : nil) else { continue }
            chosen[point.id] = selected.0
            labelRects.append(selected.1)
        }
        return chosen
    }
}
