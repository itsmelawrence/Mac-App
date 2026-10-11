import Foundation
import Testing
@testable import JarvisDashboard

@Suite struct WeatherLabelPlacementTests {
    private let canvas = CGSize(width: 500, height: 400)
    private let label = CGSize(width: 90, height: 28)

    private func point(_ id: String, _ x: CGFloat?, _ y: CGFloat?, priority: Int = 0, focused: Bool = false) -> WeatherLabelPoint {
        WeatherLabelPoint(id: id, position: x.flatMap { px in y.map { CGPoint(x: px, y: $0) } },
                          labelSize: label, priority: priority, isFocused: focused)
    }

    @Test func placedLabelsAvoidEachOtherAndOtherBeacons() {
        let points = [point("a", 120, 100), point("b", 220, 100), point("c", 320, 100)]
        let sides = WeatherLabelPlacer.place(points: points, viewSize: canvas, maxLabels: 3, previous: [:])
        let rects = points.compactMap { item -> CGRect? in
            guard let side = sides[item.id], let position = item.position else { return nil }
            return side.rect(around: position, labelSize: label)
        }
        for first in rects.indices {
            for second in rects.indices where second > first {
                #expect(!rects[first].intersects(rects[second]))
            }
        }
        for item in points {
            guard let position = item.position else { continue }
            let beacon = CGRect(x: position.x - 25, y: position.y - 25, width: 50, height: 50)
            for other in points where other.id != item.id {
                guard let side = sides[other.id], let otherPosition = other.position else { continue }
                #expect(!side.rect(around: otherPosition, labelSize: label).intersects(beacon))
            }
        }
    }

    @Test func focusIsLabelledEvenWhenAutomaticCapIsReached() {
        let points = [point("selected", 100, 120, focused: true), point("hovered", 300, 120, focused: true),
                      point("other", 200, 300)]
        let sides = WeatherLabelPlacer.place(points: points, viewSize: canvas, maxLabels: 1, previous: [:])
        #expect(sides["selected"] != nil)
        #expect(sides["hovered"] != nil)
        #expect(sides["other"] == nil)
    }

    @Test func missingAndOffscreenPointsNeverReceiveLabels() {
        let points = [point("missing", nil, nil, focused: true), point("outside", -30, 100, focused: true)]
        let sides = WeatherLabelPlacer.place(points: points, viewSize: canvas, maxLabels: 6, previous: [:])
        #expect(sides.isEmpty)
    }

    @Test func previousSidePersistsUntilItCollides() {
        let alone = [point("a", 160, 120)]
        let prior: [String: WeatherLabelSide] = ["a": .left]
        #expect(WeatherLabelPlacer.place(points: alone, viewSize: canvas, maxLabels: 6, previous: prior)["a"] == .left)
        let blocked = [point("a", 160, 120), point("blocker", 80, 120, priority: -1)]
        #expect(WeatherLabelPlacer.place(points: blocked, viewSize: canvas, maxLabels: 6, previous: prior)["a"] != .left)
    }

    @Test func capAndMoreLabelsAreRespected() {
        let points = (0..<4).map { point("\($0)", 80 + CGFloat($0) * 110, 200) }
        #expect(WeatherLabelPlacer.place(points: points, viewSize: canvas, maxLabels: 2, previous: [:]).count == 2)
        #expect(WeatherLabelPlacer.place(points: points, viewSize: canvas, maxLabels: 4, previous: [:]).count == 4)
    }
}
