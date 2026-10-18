import CoreGraphics
import EtagereKit
import Testing

@Suite("RingGeometry: anchor, slot functions and fade (behavior §1.2, §1.4)")
struct RingGeometryTests {
    private static let tolerance: CGFloat = 1e-6

    // MARK: T2

    @Test("T2 anchorCenter per alignment", arguments: ViewportCase.all)
    func anchorCenterPerAlignment(viewport: ViewportCase) {
        var geometry = viewport.geometry
        geometry.leadingInset = 40
        geometry.trailingInset = 100
        let width = geometry.activeLength
        let expected: CGFloat = switch viewport.anchor {
        case .leading: 40 + width / 2
        case .center: (40 + viewport.width - 100) / 2
        case .trailing: viewport.width - 100 - width / 2
        }
        #expect(abs(geometry.anchorCenter - expected) < Self.tolerance)
        #expect(geometry.center(at: 0) == geometry.anchorCenter)
        #expect(geometry.length(at: 0) == width)
    }

    @Test("T2 reference values: the anchored card starts at the inset")
    func anchorReferenceValues() {
        let leading = Fixture.referenceGeometry(anchor: .leading)
        #expect(leading.anchorCenter == 275)
        #expect(leading.leadingEdge(at: 0) == 80)
        let trailing = Fixture.referenceGeometry(anchor: .trailing)
        let trailingEnd: CGFloat = 1920 - 80
        #expect(trailing.trailingEdge(at: 0) == trailingEnd)
        let center = Fixture.referenceGeometry(anchor: .center)
        #expect(center.anchorCenter == 960)
    }

    // MARK: T3

    @Test("T3 the gap between neighbours is always p", arguments: ViewportCase.all)
    func constantGap(viewport: ViewportCase) {
        for activity in [1.0, 0.5, 0] {
            let geometry = viewport.geometry.withActivity(activity)
            for slot in slots(from: -3, through: 6, by: 0.05) {
                let gap = geometry.leadingEdge(at: slot + 1) - geometry.trailingEdge(at: slot)
                #expect(abs(gap - geometry.spacing) < Self.tolerance, "slot \(slot), activity \(activity)")
            }
        }
    }

    @Test("T3 neighbour centres: anchorHop next to the anchor, step beyond")
    func hopAndStep() {
        let geometry = Fixture.referenceGeometry()
        #expect(geometry.step == 332)
        #expect(geometry.anchorHop == 377)
        #expect(geometry.center(at: 1) - geometry.center(at: 0) == geometry.anchorHop)
        #expect(geometry.center(at: 0) - geometry.center(at: -1) == geometry.anchorHop)
        #expect(geometry.center(at: 3) - geometry.center(at: 2) == geometry.step)
        #expect(geometry.center(at: -2) - geometry.center(at: -3) == geometry.step)
    }

    // MARK: T4

    @Test("T4 length is W at the anchor, w one slot away, monotonic between", arguments: ViewportCase.all)
    func lengthAroundAnchor(viewport: ViewportCase) {
        let geometry = viewport.geometry
        let idle = geometry.idleLength
        #expect(geometry.length(at: 0) == geometry.activeLength)
        #expect(geometry.length(at: 1) == idle)
        #expect(geometry.length(at: -1) == idle)
        #expect(geometry.length(at: 2.5) == idle)
        #expect(geometry.length(at: -4) == idle)
        let forward = slots(from: 0, through: 1, by: 0.05).map { geometry.length(at: $0) }
        #expect(zip(forward, forward.dropFirst()).allSatisfy { $0 > $1 })
        let backward = slots(from: -1, through: 0, by: 0.05).map { geometry.length(at: $0) }
        #expect(zip(backward, backward.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("T4 an inactive shelf does not enlarge its anchored card", arguments: ViewportCase.all)
    func inactiveLength(viewport: ViewportCase) {
        let geometry = viewport.geometry
        let inactive = geometry.withActivity(0)
        #expect(inactive.length(at: 0) == geometry.idleLength)
        #expect(inactive.activeLength == inactive.idleLength)
        let half = geometry.withActivity(0.5)
        #expect(abs(half.length(at: 0) - (geometry.idleLength + geometry.activeLength) / 2) < Self.tolerance)
    }

    @Test("T4 emphasis is 1 at the anchor and 0 one slot away")
    func emphasis() {
        let geometry = Fixture.referenceGeometry()
        #expect(geometry.emphasis(at: 0) == 1)
        #expect(geometry.emphasis(at: 0.5) == 0.5)
        #expect(geometry.emphasis(at: -0.25) == 0.75)
        #expect(geometry.emphasis(at: 1) == 0)
        #expect(geometry.emphasis(at: -3) == 0)
    }

    // MARK: T5

    @Test("T5 opacity: 1 inside the window, fading over fadeLength slots", arguments: [0.25, 0.5, 1.0])
    func opacityRule(fade: Double) {
        let geometry = RingGeometry(
            viewportLength: 1920, leadingInset: 80, trailingInset: 80, idleLength: 300, activeLength: 390,
            spacing: 32, anchor: .center, fadeLength: fade
        )
        let rest = -2...3
        for slot in slots(from: -2, through: 3, by: 0.25) {
            #expect(geometry.opacity(at: slot, rest: rest) == 1)
        }
        #expect(geometry.opacity(at: 3 + fade / 2, rest: rest) == 0.5)
        #expect(geometry.opacity(at: -2 - fade / 2, rest: rest) == 0.5)
        #expect(geometry.opacity(at: 3 + fade, rest: rest) == 0)
        #expect(geometry.opacity(at: -2 - fade, rest: rest) == 0)
        #expect(geometry.opacity(at: 3 + fade + 0.5, rest: rest) == 0)
        #expect(geometry.opacity(at: -10, rest: rest) == 0)
    }

    @Test("T5 the default fade reaches 0.5 half a slot past the edge", arguments: RingCase.all)
    func defaultFade(ringCase: RingCase) {
        let geometry = ringCase.geometry
        let rest = geometry.restWindow(count: ringCase.itemCount)
        #expect(geometry.fadeLength == 1)
        #expect(geometry.opacity(at: Double(rest.upperBound) + 0.5, rest: rest) == 0.5)
        #expect(geometry.opacity(at: Double(rest.upperBound) + 1, rest: rest) == 0)
        #expect(geometry.opacity(at: Double(rest.lowerBound) - 1, rest: rest) == 0)
    }

    @Test("T5 fadeLengthInSlots is clamped to 0.25...1")
    func fadeClamp() {
        #expect(RingGeometry.clampedFadeLength(0.1) == 0.25)
        #expect(RingGeometry.clampedFadeLength(0.6) == 0.6)
        #expect(RingGeometry.clampedFadeLength(3) == 1)
        #expect(RingGeometry.clampedFadeLength(-1) == 0.25)
        #expect(RingGeometry.clampedFadeLength(.nan) == 1)
        #expect(RingGeometry.clampedFadeLength(.infinity) == 1)

        var geometry = Fixture.referenceGeometry()
        geometry.fadeLength = 2
        #expect(geometry.fadeLength == 1)
        geometry.fadeLength = 0
        #expect(geometry.fadeLength == 0.25)

        var configuration = EtagereConfiguration()
        #expect(configuration.fadeLengthInSlots == 1)
        configuration.fadeLengthInSlots = 0.1
        #expect(configuration.fadeLengthInSlots == 0.25)
        configuration.fadeLengthInSlots = 1.5
        #expect(configuration.fadeLengthInSlots == 1)
        configuration.fadeLengthInSlots = .nan
        #expect(configuration.fadeLengthInSlots == 1)
    }

    // MARK: T6

    /// The ground a leaving card covers while it fades: from fully opaque at the rest edge to transparent
    /// `fadeLength` slots further on, in points along the ring.
    private func fadeDistance(_ geometry: RingGeometry, from edge: Int, outward direction: Double) -> CGFloat {
        let start = Double(edge)
        let end = start + direction * geometry.fadeLength
        #expect(geometry.opacity(at: end, rest: edge...edge) == 0)
        return abs(geometry.center(at: end) - geometry.center(at: start))
    }

    @Test("T6 the far-end fade covers one step at the screen edge and mid-shelf", arguments: RingAnchor.allCases)
    func fadeDistanceIndependentOfEdge(anchor: RingAnchor) {
        let atScreenEdge = Fixture.referenceGeometry(anchor: anchor, viewport: 1920)
        let midShelf = Fixture.referenceGeometry(anchor: anchor, viewport: 3000)
        let longRest = atScreenEdge.restWindow(count: 40)
        let shortRest = midShelf.restWindow(count: 3)
        // The long ring runs off the 1920 pt screen; the short one ends more than a card inside the 3000 pt shelf.
        if anchor != .trailing {
            #expect(atScreenEdge.trailingEdge(at: Double(longRest.upperBound)) > 1920)
            #expect(midShelf.trailingEdge(at: Double(shortRest.upperBound)) < CGFloat(3000 - 300))
        }
        if anchor != .leading {
            #expect(atScreenEdge.leadingEdge(at: Double(longRest.lowerBound)) < 0)
            #expect(midShelf.leadingEdge(at: Double(shortRest.lowerBound)) > 300)
        }
        for (geometry, rest) in [(atScreenEdge, longRest), (midShelf, shortRest)] {
            if anchor != .leading {
                #expect(fadeDistance(geometry, from: rest.lowerBound, outward: -1) == geometry.step)
            }
            if anchor != .trailing {
                #expect(fadeDistance(geometry, from: rest.upperBound, outward: 1) == geometry.step)
            }
        }
    }

    @Test("T6 one slot of travel sweeps 2w + p, and a shorter fade scales with it")
    func sweepIsTwoWidthsPlusPadding() {
        var geometry = Fixture.referenceGeometry()
        let rest = geometry.restWindow(count: 3)
        let edge = Double(rest.upperBound)
        let swept = geometry.trailingEdge(at: edge + 1) - geometry.leadingEdge(at: edge)
        #expect(swept == 2 * geometry.idleLength + geometry.spacing)
        geometry.fadeLength = 0.5
        #expect(fadeDistance(geometry, from: rest.upperBound, outward: 1) == geometry.step / 2)
    }

    // MARK: Mirroring and factories

    @Test("RTL mirrors positions across the viewport (behavior §1.11)")
    func mirroring() {
        let geometry = Fixture.referenceGeometry()
        #expect(geometry.physicalPosition(275, isRightToLeft: false) == 275)
        let mirrored: CGFloat = 1920 - 275
        #expect(geometry.physicalPosition(275, isRightToLeft: true) == mirrored)
        let mirroredAnchor = geometry.physicalPosition(geometry.anchorCenter, isRightToLeft: true)
        let trailing = Fixture.referenceGeometry(anchor: .trailing)
        #expect(mirroredAnchor == trailing.anchorCenter)
    }

    @Test("A shelf ring built from resolved metrics uses w, W, p and the alignment")
    func shelfRingFactory() {
        let metrics = EtagereResolvedMetrics.starting(.television, containerWidth: 1920)
        let geometry = RingGeometry(
            shelfMetrics: metrics, viewportWidth: 1920, leadingInset: 90, trailingInset: 90,
            alignment: .trailing, fadeLength: 0.5
        )
        #expect(geometry.idleLength == 360)
        #expect(geometry.activeLength == 450)
        #expect(geometry.spacing == 40)
        #expect(geometry.anchor == .trailing)
        #expect(geometry.fadeLength == 0.5)
        #expect(EtagereHorizontalAlignment.allCases.map(\.ringAnchor) == RingAnchor.allCases)
    }

    @Test("Degenerate viewports fit no slots instead of trapping")
    func degenerateViewports() {
        var geometry = Fixture.referenceGeometry()
        geometry.viewportLength = 0
        #expect(geometry.slotsFittingAfter == 0)
        #expect(geometry.restWindow(count: 40) == 0...0)
        geometry.viewportLength = .nan
        #expect(geometry.slotsFittingAfter == 0)
        geometry = Fixture.referenceGeometry()
        geometry.idleLength = 0
        geometry.spacing = 0
        #expect(geometry.slotsFittingAfter == 0)
        #expect(geometry.restWindow(count: 0) == 0...0)
    }
}
