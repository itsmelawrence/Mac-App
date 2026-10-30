import Foundation
import Testing
@testable import JarvisDashboard

@Suite struct WeatherLabelPlacementTests {
    private let canvas = CGSize(width: 500, height: 400)
    private let full = CGSize(width: 110, height: WeatherChipLayout.chipHeight)
    private let compact = CGSize(width: 60, height: WeatherChipLayout.chipHeight)

    private func point(_ id: String, _ x: CGFloat?, _ y: CGFloat?, priority: Int = 0, focused: Bool = false) -> WeatherChipCandidate {
        WeatherChipCandidate(id: id, position: x.flatMap { px in y.map { CGPoint(x: px, y: $0) } },
                             fullSize: full, compactSize: compact, priority: priority, isFocused: focused)
    }

    private func rect(_ candidate: WeatherChipCandidate, _ placement: WeatherChipPlacement) -> CGRect? {
        guard placement.style != .dot, let position = candidate.position else { return nil }
        return WeatherChipLayout.rect(size: placement.style == .full ? full : compact, edge: placement.edge, at: position)
    }

    @Test func chipsNeverOverlapEachOtherOrAnotherCitysDot() {
        // A tight cluster, like Manila, Calapan and Lucena at country zoom.
        let points = [point("a", 200, 200), point("b", 230, 210), point("c", 215, 240),
                      point("d", 260, 190), point("e", 400, 100)]
        let placements = WeatherChipLayout.place(points, viewSize: canvas, showNames: true)
        let chips = points.compactMap { candidate in placements[candidate.id].flatMap { rect(candidate, $0) } }
        for first in chips.indices {
            for second in chips.indices where second > first {
                #expect(!chips[first].intersects(chips[second]))
            }
        }
        for candidate in points {
            guard let placement = placements[candidate.id], let chip = rect(candidate, placement) else { continue }
            for other in points where other.id != candidate.id {
                let dot = CGRect(x: other.position!.x - 4, y: other.position!.y - 4, width: 8, height: 8)
                #expect(!chip.intersects(dot))
            }
        }
    }

    @Test func crowdedCitiesShrinkInsteadOfDisappearing() {
        let points = (0..<6).map { point("\($0)", 200 + CGFloat($0) * 12, 200, priority: -$0) }
        let placements = WeatherChipLayout.place(points, viewSize: canvas, showNames: true)
        // Every visible city keeps a marker; the highest priority keeps the most room.
        #expect(placements.count == 6)
        #expect(placements["0"]?.style == .full)
        #expect(placements.values.contains { $0.style == .dot })
    }

    @Test func namesAppearOnlyWhenAskedOrFocused() {
        let points = [point("plain", 100, 200), point("focused", 350, 200, focused: true)]
        let placements = WeatherChipLayout.place(points, viewSize: canvas, showNames: false)
        #expect(placements["plain"]?.style == .compact)
        #expect(placements["focused"]?.style == .full)
    }

    @Test func chipsFlipBelowAtTheTopEdgeAndKeepTheirSide() {
        let top = [point("north", 250, 20)]
        #expect(WeatherChipLayout.place(top, viewSize: canvas, showNames: true)["north"]?.edge == .below)

        let open = [point("a", 250, 200)]
        let previous = ["a": WeatherChipPlacement(style: .full, edge: .below)]
        #expect(WeatherChipLayout.place(open, viewSize: canvas, showNames: true, previous: previous)["a"]?.edge == .below)
    }

    @Test func missingAndOffscreenPointsAreLeftOut() {
        let points = [point("missing", nil, nil, focused: true), point("outside", -30, 100, focused: true)]
        #expect(WeatherChipLayout.place(points, viewSize: canvas, showNames: true).isEmpty)
    }
}
