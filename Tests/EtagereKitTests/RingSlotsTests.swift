import CoreGraphics
import EtagereKit
import Testing

@Suite("Rest windows, render slots, floor math and the seam (behavior §1.3, §1.5, §1.6)")
struct RingSlotsTests {
    // MARK: T1

    @Test("T1 the rest window never repeats a card and respects the anchor side", arguments: RingCase.all)
    func restWindowRules(ringCase: RingCase) {
        let geometry = ringCase.geometry
        let rest = geometry.restWindow(count: ringCase.itemCount)
        #expect(rest.count <= ringCase.itemCount)
        #expect(rest.contains(0))
        switch ringCase.anchor {
        case .leading:
            #expect(rest.lowerBound == 0)
            #expect(rest.upperBound == min(ringCase.itemCount - 1, geometry.slotsFittingAfter))
        case .trailing:
            #expect(rest.upperBound == 0)
            #expect(-rest.lowerBound == min(ringCase.itemCount - 1, geometry.slotsFittingBefore))
        case .center:
            // Symmetric insets: the "next" side gets the extra card, never the "previous" side.
            #expect(rest.upperBound + rest.lowerBound >= 0)
            #expect(rest.upperBound + rest.lowerBound <= 1)
        }
        // Every slot shown at rest is at least partly on screen.
        for slot in rest {
            #expect(geometry.leadingEdge(at: Double(slot)) < ringCase.width)
            #expect(geometry.trailingEdge(at: Double(slot)) > 0)
        }
    }

    @Test("T1 known windows", arguments: [
        (RingAnchor.leading, 3, 0...2), (.leading, 40, 0...5), (.center, 4, -1...2), (.center, 3, -1...1),
        (.trailing, 3, -2...0), (.center, 2, 0...1), (.center, 1, 0...0), (.leading, 1, 0...0)
    ])
    func knownWindows(anchor: RingAnchor, count: Int, expected: ClosedRange<Int>) {
        #expect(Fixture.referenceGeometry(anchor: anchor).restWindow(count: count) == expected)
    }

    @Test("T1 an inactive shelf's window is computed with idle widths")
    func inactiveWindow() {
        let active = Fixture.referenceGeometry()
        let inactive = active.withActivity(0)
        #expect(inactive.slotsFittingAfter >= active.slotsFittingAfter)
        #expect(inactive.restWindow(count: 3) == 0...2)
    }

    // MARK: T7

    @Test("T7 a backward wrap renders the last card twice, on laps -1 and 0")
    func ghostCopyDuringBackwardWrap() {
        let slots = RingMath.renderSlots(ids: ["A", "B", "C"], rotation: -1, settledRotation: 0, rest: 0...2)
        let lapsOfC = slots.filter { $0.id.itemID == "C" }.map(\.lap)
        #expect(lapsOfC == [-1, 0])
        // The lap -1 copy is the one arriving at the anchor.
        let arriving = slots.first { $0.virtualIndex == -1 }
        #expect(arriving?.id == RingSlotKey(itemID: "C", lap: -1))
        #expect(Set(slots.map(\.id)).count == slots.count)
    }

    @Test("T7 the render count does not depend on the ring's length", arguments: RingAnchor.allCases)
    func renderCountIndependentOfLength(anchor: RingAnchor) {
        let geometry = Fixture.referenceGeometry(anchor: anchor)
        var askedFor = 0
        var counts: [Int] = []
        for size in [12, 10_000] {
            let rest = geometry.restWindow(count: size)
            let slots = RingMath.renderSlots(itemCount: size, rotation: 9_997, settledRotation: 9_995, rest: rest) {
                askedFor += 1
                return $0
            }
            counts.append(slots.count)
        }
        #expect(counts[0] == counts[1])
        #expect(askedFor == counts[0] + counts[1])

        let state = ShelfState(Shelf(id: "big", title: "Big", cards: Fixture.cards(10_000)))
        state.rotate(by: -3)
        #expect(state.renderSlots(rest: geometry.restWindow(count: 10_000)).count == counts[1] + 1)
    }

    // MARK: T8

    @Test("T8 the render range covers every slot in flight", arguments: RingCase.all.filter { $0.itemCount > 1 })
    func renderRangeCoversFlight(ringCase: RingCase) {
        let geometry = ringCase.geometry
        let rest = geometry.restWindow(count: ringCase.itemCount)
        for (settled, rotation) in [(0, 5), (5, 0), (-3, 2)] {
            let range = RingMath.renderRange(rotation: rotation, settledRotation: settled, rest: rest)
            let flight = slots(from: Double(min(settled, rotation)), through: Double(max(settled, rotation)), by: 0.05)
            for phase in flight {
                for virtualIndex in (range.lowerBound - 10)...(range.upperBound + 10) {
                    let visible = geometry.opacity(at: Double(virtualIndex) - phase, rest: rest) > 0
                    #expect(!visible || range.contains(virtualIndex), "v \(virtualIndex) at phase \(phase)")
                }
            }
            // The extra slot at each end is transparent at both ends of the flight, so views come and go unseen.
            for phase in [Double(settled), Double(rotation)] {
                #expect(geometry.opacity(at: Double(range.lowerBound) - phase, rest: rest) == 0)
                #expect(geometry.opacity(at: Double(range.upperBound) - phase, rest: rest) == 0)
            }
        }
    }

    // MARK: T9

    @Test("T9 floorDiv and floorMod round toward negative infinity", arguments: [
        (7, 3, 2, 1), (-1, 3, -1, 2), (-3, 3, -1, 0), (-4, 3, -2, 2), (0, 5, 0, 0), (-7, 1, -7, 0), (9, 4, 2, 1)
    ])
    func floorMath(dividend: Int, divisor: Int, quotient: Int, remainder: Int) {
        #expect(RingMath.floorDiv(dividend, divisor) == quotient)
        #expect(RingMath.floorMod(dividend, divisor) == remainder)
    }

    @Test("T9 floorDiv * n + floorMod reconstructs the value")
    func floorIdentity() {
        for divisor in 1...7 {
            for dividend in -50...50 {
                let remainder = RingMath.floorMod(dividend, divisor)
                #expect((0..<divisor).contains(remainder))
                #expect(RingMath.floorDiv(dividend, divisor) * divisor + remainder == dividend)
            }
        }
    }

    @Test("Shortest delta: never more than half way round; ties go forward")
    func shortestDelta() {
        #expect(RingMath.shortestDelta(from: 0, to: 2, itemCount: 4) == 2)
        #expect(RingMath.shortestDelta(from: 2, to: 0, itemCount: 4) == 2)
        #expect(RingMath.shortestDelta(from: 0, to: 3, itemCount: 4) == -1)
        #expect(RingMath.shortestDelta(from: 0, to: 2, itemCount: 5) == 2)
        #expect(RingMath.shortestDelta(from: 0, to: 3, itemCount: 5) == -2)
        #expect(RingMath.shortestDelta(from: 0, to: 0, itemCount: 1) == 0)
    }

    @Test("Re-basing keeps the lap, or falls back to the old index clamped")
    func rebase() {
        // Lap 2, index 1 of 4 -> the same card at index 2 of 4.
        #expect(RingMath.rebasedRotation(9, oldCount: 4, newIndexOfAnchored: 2, newCount: 4) == 10)
        // Lap -1, index 1 of 4 -> index 0 of 6 keeps lap -1.
        #expect(RingMath.rebasedRotation(-3, oldCount: 4, newIndexOfAnchored: 0, newCount: 6) == -6)
        // Gone: index 3 clamps to the new last index 1.
        #expect(RingMath.rebasedRotation(3, oldCount: 4, newIndexOfAnchored: nil, newCount: 2) == 1)
        #expect(RingMath.rebasedRotation(5, oldCount: 4, newIndexOfAnchored: nil, newCount: 0) == 0)
        #expect(RingMath.rebasedRotation(0, oldCount: 0, newIndexOfAnchored: nil, newCount: 3) == 0)
    }

    // MARK: T10

    @Test("T10 only copies of the last card own a seam, and none when N = 1", arguments: Fixture.ringSizes)
    func seamOwners(size: Int) {
        let ids = Fixture.cardIDs(size)
        let slots = RingMath.renderSlots(ids: ids, rotation: -size - 1, settledRotation: 2, rest: -2...5)
        let owners = slots.filter(\.isSeamOwner)
        if size == 1 {
            #expect(owners.isEmpty)
        } else {
            #expect(!owners.isEmpty)
            #expect(owners.allSatisfy { $0.ringIndex == size - 1 && $0.id.itemID == ids[size - 1] })
            #expect(slots.filter { $0.ringIndex == size - 1 }.count == owners.count)
        }
    }

    @Test("T10 the seam bar sits in the middle of the gap after the last card", arguments: ViewportCase.all)
    func seamPosition(viewport: ViewportCase) {
        for activity in [1.0, 0] {
            let geometry = viewport.geometry.withActivity(activity)
            for slot in slots(from: -3, through: 5, by: 0.25) {
                let middle = (geometry.trailingEdge(at: slot) + geometry.leadingEdge(at: slot + 1)) / 2
                #expect(abs(geometry.seamCenter(afterSlot: slot) - middle) < 1e-6)
            }
        }
    }

    @Test("T10 the seam shows after the last card wherever the anchor is")
    func seamAtRest() {
        // Leading A B C |, center D | [A] B C, trailing B C | [A]: the bar follows the last card's slot.
        let cases: [RingAnchor: (size: Int, lastCardSlot: Int)] = [
            .leading: (3, 2), .center: (4, -1), .trailing: (3, -1)
        ]
        for (anchor, expected) in cases {
            let (size, lastCardSlot) = expected
            let geometry = Fixture.referenceGeometry(anchor: anchor)
            let rest = geometry.restWindow(count: size)
            let slots = RingMath.renderSlots(ids: Fixture.cardIDs(size), rotation: 0, settledRotation: 0, rest: rest)
            let visibleOwners = slots.filter { $0.isSeamOwner && rest.contains($0.virtualIndex) }
            #expect(visibleOwners.map(\.virtualIndex) == [lastCardSlot], "\(anchor)")
        }
    }
}
