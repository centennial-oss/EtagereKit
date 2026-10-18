import CoreGraphics
import EtagereKit
import Testing

/// One vertical ShelvesRing case: an alignment, a shelf count and a viewport height.
nonisolated struct ShelvesCase: Sendable, CustomTestStringConvertible {
    let alignment: EtagereVerticalAlignment
    let shelfCount: Int
    let height: CGFloat

    var testDescription: String { "\(alignment) shelves=\(shelfCount) H=\(Int(height))" }

    /// Home's 3-5 shelves, each a title plus a reserved 16:9 ring at the regular metrics for 1280 pt.
    var geometry: RingGeometry {
        let metrics = EtagereResolvedMetrics.starting(.regular, containerWidth: 1280)
        let shelfHeight = 34 + metrics.reservedRingHeight(aspectRatio: 16.0 / 9.0)
        return RingGeometry(
            shelvesViewportHeight: height, topInset: 40, bottomInset: 40, shelfHeight: shelfHeight,
            shelfSpacing: metrics.shelfSpacing, alignment: alignment
        )
    }

    static let all: [ShelvesCase] = EtagereVerticalAlignment.allCases.flatMap { alignment in
        [3, 4, 5].flatMap { count in
            [400, 800, 1080, 1440].map { ShelvesCase(alignment: alignment, shelfCount: count, height: $0) }
        }
    }
}

@Suite("The vertical ShelvesRing of mode 1 (behavior §2.1)")
struct VerticalRingTests {
    @Test("T17 shelves do not grow at the anchor", arguments: ShelvesCase.all)
    func shelvesKeepTheirHeight(shelves: ShelvesCase) {
        let geometry = shelves.geometry
        #expect(geometry.activeLength == geometry.idleLength)
        #expect(geometry.anchorHop == geometry.step)
        for slot in slots(from: -2, through: 2, by: 0.25) {
            #expect(geometry.length(at: slot) == geometry.idleLength)
        }
    }

    @Test("T17 Home's 3-5 shelves never repeat at rest", arguments: ShelvesCase.all)
    func noRepeatedShelves(shelves: ShelvesCase) {
        let rest = shelves.geometry.restWindow(count: shelves.shelfCount)
        #expect(rest.count <= shelves.shelfCount)
        let ids = (0..<shelves.shelfCount).map { "s\($0)" }
        let atRest = RingMath.renderSlots(ids: ids, rotation: 7, settledRotation: 7, rest: rest)
            .filter { rest.contains($0.virtualIndex - 7) }
        #expect(Set(atRest.map(\.id.itemID)).count == atRest.count)
    }

    @Test("T17 top, center and bottom anchor the Active Shelf", arguments: EtagereVerticalAlignment.allCases)
    func verticalAnchors(alignment: EtagereVerticalAlignment) {
        let geometry = RingGeometry(
            shelvesViewportHeight: 1080, topInset: 60, bottomInset: 20, shelfHeight: 300, shelfSpacing: 36,
            alignment: alignment
        )
        let expected: CGFloat = switch alignment {
        case .top: 60 + 150
        case .center: (60 + 1080 - 20) / 2
        case .bottom: 1080 - 20 - 150
        }
        #expect(geometry.anchorCenter == expected)
        #expect(geometry.anchor == alignment.ringAnchor)
        let rest = geometry.restWindow(count: 4)
        switch alignment {
        case .top: #expect(rest.lowerBound == 0)
        case .center: #expect(rest.contains(-1) && rest.contains(1))
        case .bottom: #expect(rest.upperBound == 0)
        }
    }

    @Test("T17 a wrapping shelf is rendered twice with different laps, and the shelf seam follows the last shelf")
    func wrappingShelf() {
        let model = Fixture.model(cardCounts: [3, 8, 2])
        let geometry = ShelvesCase(alignment: .top, shelfCount: 3, height: 1080).geometry
        let rest = geometry.restWindow(count: 3)
        model.move(.previousShelf, isRepeat: false, reduceMotion: false)
        #expect(model.shelfRotation == -1)
        #expect(model.activeShelf?.id == "s2")
        let slots = model.shelfRenderSlots(rest: rest)
        // The copy arriving at the anchor (lap -1) and the copy leaving the far end (lap 0).
        #expect(slots.filter { $0.id.itemID == "s2" }.map(\.lap) == [-1, 0])
        #expect(slots.filter(\.isSeamOwner).allSatisfy { $0.id.itemID == "s2" })
        // Only the copy at the anchor is the Active Shelf.
        let active = slots.filter { model.isShelfActive(virtualIndex: $0.virtualIndex) }
        #expect(active.map(\.id) == [RingSlotKey(itemID: "s2", lap: -1)])
    }
}
