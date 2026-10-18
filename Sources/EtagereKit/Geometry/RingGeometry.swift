import CoreGraphics

/// Where the anchored item rests on its ring's main axis. The public alignments map onto it: leading, center
/// and trailing on a ShelfRing; top, center and bottom on the vertical ShelvesRing. Layout direction never changes
/// it; right-to-left only mirrors the drawing (behavior §1.11).
public nonisolated enum RingAnchor: String, Sendable, Hashable, CaseIterable, Codable {
    case leading, center, trailing
}

/// Pure geometry for one ring (behavior §1.2-§1.6): a horizontal ShelfRing of cards or the vertical ShelvesRing of
/// shelves. Coordinates run from the leading (or top) edge of the viewport. Slot 0 is the Anchor Spot, positive
/// slots follow it ("next"), negative slots precede it. Slots are continuous, so the same functions place items at
/// rest and on every animation frame.
public nonisolated struct RingGeometry: Sendable, Equatable {
    /// The allowed fade lengths in slots (Q1): values above 1 would leave the fade slot partly visible at rest.
    public static let fadeLengthRange: ClosedRange<Double> = 0.25...1

    /// `V`: the viewport length on the main axis.
    public var viewportLength: CGFloat
    /// `Lin`: the inset before the anchor when it is leading.
    public var leadingInset: CGFloat
    /// `Tin`: the inset after the anchor when it is trailing.
    public var trailingInset: CGFloat
    /// `w`: the main-axis length of an item away from the anchor.
    public var idleLength: CGFloat
    /// `W`: the main-axis length of the anchored item; equal to `idleLength` on an inactive ring.
    public var activeLength: CGFloat
    /// `p`: the gap between neighbouring items. Never stretched to fill the ring (R16).
    public var spacing: CGFloat
    public var anchor: RingAnchor
    private var storedFadeLength: Double

    public init(
        viewportLength: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        idleLength: CGFloat,
        activeLength: CGFloat,
        spacing: CGFloat,
        anchor: RingAnchor,
        fadeLength: Double = 1
    ) {
        self.viewportLength = viewportLength
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.idleLength = idleLength
        self.activeLength = activeLength
        self.spacing = spacing
        self.anchor = anchor
        storedFadeLength = Self.clampedFadeLength(fadeLength)
    }

    /// Slots of travel past the rest edge over which an item fades to 0 (R17, Q1), clamped to `fadeLengthRange`.
    public var fadeLength: Double {
        get { storedFadeLength }
        set { storedFadeLength = Self.clampedFadeLength(newValue) }
    }

    /// Clamps a fade length to `fadeLengthRange`; a value that is not a number becomes the default of 1.
    public static func clampedFadeLength(_ value: Double) -> Double {
        guard !value.isNaN else { return fadeLengthRange.upperBound }
        return min(max(value, fadeLengthRange.lowerBound), fadeLengthRange.upperBound)
    }

    /// The same ring with the anchored item's enlargement scaled by `activity` (1 on the Active Shelf, 0 on the
    /// others). Animating `activity` shrinks the anchored card and closes up its neighbours (behavior §1.9).
    public func withActivity(_ activity: Double) -> RingGeometry {
        var copy = self
        copy.activeLength = idleLength + (activeLength - idleLength) * CGFloat(activity)
        return copy
    }

    // MARK: Slot functions (behavior §1.2)

    /// Center distance between two neighbouring items away from the anchor: `w + p`.
    public var step: CGFloat { idleLength + spacing }

    /// Center distance between the anchored item and either neighbour: `(W + w) / 2 + p`.
    public var anchorHop: CGFloat { (activeLength + idleLength) / 2 + spacing }

    /// Main-axis center of the Anchor Spot.
    public var anchorCenter: CGFloat {
        switch anchor {
        case .leading: leadingInset + activeLength / 2
        case .center: (leadingInset + viewportLength - trailingInset) / 2
        case .trailing: viewportLength - trailingInset - activeLength / 2
        }
    }

    /// 1 at the anchor, falling linearly to 0 one slot away.
    public func emphasis(at slot: Double) -> CGFloat {
        CGFloat(max(0, 1 - abs(slot)))
    }

    /// Main-axis length of an item at `slot`: `W` at the anchor, `w` one slot away and beyond.
    public func length(at slot: Double) -> CGFloat {
        idleLength + (activeLength - idleLength) * emphasis(at: slot)
    }

    /// Main-axis center of an item at `slot`. Piecewise linear, so the gap between neighbours stays exactly
    /// `spacing` on every animation frame (R12, R18).
    public func center(at slot: Double) -> CGFloat {
        let magnitude = CGFloat(abs(slot))
        let travel = min(magnitude, 1) * anchorHop + max(magnitude - 1, 0) * step
        return anchorCenter + (slot < 0 ? -travel : travel)
    }

    /// The item's edge nearer the leading end of the viewport.
    public func leadingEdge(at slot: Double) -> CGFloat {
        center(at: slot) - length(at: slot) / 2
    }

    /// The item's edge nearer the trailing end of the viewport.
    public func trailingEdge(at slot: Double) -> CGFloat {
        center(at: slot) + length(at: slot) / 2
    }

    /// Slots after the anchor that are at least partly inside the viewport.
    public var slotsFittingAfter: Int {
        let firstNearEdge = anchorCenter + anchorHop - idleLength / 2
        return Self.slotCount(covering: viewportLength - firstNearEdge, step: step)
    }

    /// Slots before the anchor that are at least partly inside the viewport.
    public var slotsFittingBefore: Int {
        let firstNearEdge = anchorCenter - anchorHop + idleLength / 2
        return Self.slotCount(covering: firstNearEdge, step: step)
    }

    private static func slotCount(covering room: CGFloat, step: CGFloat) -> Int {
        guard room > 0, step > 0, room.isFinite else { return 0 }
        return Int(min(room / step, 1_000_000).rounded(.up))
    }

    // MARK: Rest window and fade (behavior §1.3, §1.4)

    /// The slots shown at full opacity at rest. It never holds more than `count` slots, so a short ring never shows
    /// an item twice (R19). A leading anchor shows nothing before the anchor (that side is the exit side), a
    /// trailing anchor nothing after it, and a center anchor gives the extra item to the "next" side.
    public func restWindow(count: Int) -> ClosedRange<Int> {
        let others = max(count - 1, 0)
        switch anchor {
        case .leading:
            return 0...min(others, slotsFittingAfter)
        case .trailing:
            return -min(others, slotsFittingBefore)...0
        case .center:
            var after = min(slotsFittingAfter, (others + 1) / 2)
            let before = min(slotsFittingBefore, others - after)
            after = min(slotsFittingAfter, others - before)
            return -before...after
        }
    }

    /// 1 inside the rest window, falling linearly to 0 after `fadeLength` slots of travel past either rest edge.
    /// With the default fade of one slot, a leaving item is transparent once it has swept `2w + p` (R13, R15, R17).
    public func opacity(at slot: Double, rest: ClosedRange<Int>) -> Double {
        let upper = Double(rest.upperBound)
        let lower = Double(rest.lowerBound)
        if slot > upper { return max(0, 1 - (slot - upper) / fadeLength) }
        if slot < lower { return max(0, 1 - (lower - slot) / fadeLength) }
        return 1
    }

    // MARK: Seam and mirroring (behavior §1.6, §1.11)

    /// Main-axis center of the seam bar that follows the item at `slot`: the middle of the gap after it. Only the
    /// ring's last item owns a seam (`RingSlot.isSeamOwner`); the bar uses that item's opacity.
    public func seamCenter(afterSlot slot: Double) -> CGFloat {
        trailingEdge(at: slot) + spacing / 2
    }

    /// Converts a leading-based position to the physical axis: `V - x` in right-to-left layouts.
    public func physicalPosition(_ position: CGFloat, isRightToLeft: Bool) -> CGFloat {
        isRightToLeft ? viewportLength - position : position
    }
}

// MARK: - Shelf and shelves rings

nonisolated extension RingGeometry {
    /// The geometry of one ShelfRing: card widths and spacing from the resolved metrics, the anchor from the
    /// horizontal alignment. It describes the active ring; use `withActivity(0)` for an inactive shelf.
    public init(
        shelfMetrics metrics: EtagereResolvedMetrics,
        viewportWidth: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        alignment: EtagereHorizontalAlignment,
        fadeLength: Double = 1
    ) {
        self.init(
            viewportLength: viewportWidth, leadingInset: leadingInset, trailingInset: trailingInset,
            idleLength: metrics.cardWidth, activeLength: metrics.activeCardWidth, spacing: metrics.cardSpacing,
            anchor: alignment.ringAnchor, fadeLength: fadeLength
        )
    }

    /// The geometry of the vertical ShelvesRing (mode 1, behavior §2.1): the same math on the y axis. Shelves do
    /// not grow at the anchor, so `activeLength == idleLength == shelfHeight` (the title plus the reserved ring
    /// height). The leading inset is the top inset and the trailing inset the bottom one.
    public init(
        shelvesViewportHeight viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        shelfHeight: CGFloat,
        shelfSpacing: CGFloat,
        alignment: EtagereVerticalAlignment,
        fadeLength: Double = 1
    ) {
        self.init(
            viewportLength: viewportHeight, leadingInset: topInset, trailingInset: bottomInset,
            idleLength: shelfHeight, activeLength: shelfHeight, spacing: shelfSpacing,
            anchor: alignment.ringAnchor, fadeLength: fadeLength
        )
    }
}
