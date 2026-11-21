import CoreGraphics

/// Card widths on a ShelfRing whose cards differ in shape (behavior §1.12, D9): each card's idle width as a
/// multiple of the shelf's idle width (`RingGeometry.idleLength`), for a window of virtual indices. A ring whose
/// cards all have the shelf's shape is uniform: it stores nothing and uses the uniform slot functions.
nonisolated struct RingWidths: Sendable, Equatable {
    /// The card shapes (width / height) a card may ask for; others are clamped into it.
    static let aspectRatioRange: ClosedRange<CGFloat> = 0.5...2.5
    static let uniform = RingWidths(firstVirtualIndex: 0, ratios: [])

    var firstVirtualIndex: Int
    /// Width ratios for the virtual indices from `firstVirtualIndex`.
    var ratios: [CGFloat]

    var isUniform: Bool { ratios.isEmpty }

    /// The width ratio of a virtual index; 1 (the shelf's width) outside the window.
    func ratio(at virtualIndex: Int) -> CGFloat {
        let offset = virtualIndex - firstVirtualIndex
        return ratios.indices.contains(offset) ? ratios[offset] : 1
    }

    /// A card's aspect ratio clamped to `aspectRatioRange`; nil when it has none or it is not a positive number.
    static func clampedAspectRatio(_ ratio: CGFloat?) -> CGFloat? {
        guard let ratio, ratio.isFinite, ratio > 0 else { return nil }
        return min(max(ratio, aspectRatioRange.lowerBound), aspectRatioRange.upperBound)
    }

    /// A card's idle width over the shelf's: the shelf's card height times the card's clamped ratio. Within 1e-9
    /// of 1 counts as 1, so a card that asks for the shelf's own shape keeps the ring uniform.
    static func widthRatio(cardAspectRatio: CGFloat?, cardSize: CGSize) -> CGFloat {
        guard let ratio = clampedAspectRatio(cardAspectRatio), cardSize.width > 0 else { return 1 }
        let widthRatio = cardSize.height * ratio / cardSize.width
        return abs(widthRatio - 1) < 1e-9 ? 1 : widthRatio
    }

    /// The widths for `range`; uniform when every card there has the shelf's width.
    static func window(_ range: ClosedRange<Int>, ratio: (Int) -> CGFloat) -> RingWidths {
        let ratios = range.map(ratio)
        guard ratios.contains(where: { $0 != 1 }) else { return .uniform }
        return RingWidths(firstVirtualIndex: range.lowerBound, ratios: ratios)
    }
}

/// A ring's rest window at each rotation of a range (behavior §1.12). With cards of different widths the window
/// depends on which card is anchored.
nonisolated struct RestWindows: Sendable, Equatable {
    var firstRotation: Int
    /// Never empty.
    var windows: [ClosedRange<Int>]

    init(firstRotation: Int, windows: [ClosedRange<Int>]) {
        self.firstRotation = firstRotation
        self.windows = windows.isEmpty ? [0...0] : windows
    }

    /// One window for every rotation: a uniform ring.
    init(single window: ClosedRange<Int>) {
        self.init(firstRotation: 0, windows: [window])
    }

    /// The window at `rotation`; the nearest one outside the range.
    func window(at rotation: Int) -> ClosedRange<Int> {
        windows[min(max(rotation - firstRotation, 0), windows.count - 1)]
    }

    /// Every window's slots together.
    var union: ClosedRange<Int> {
        windows.dropFirst().reduce(windows[0], RingPhase.union)
    }
}

// MARK: - Slot functions for cards of different widths

nonisolated extension RingGeometry {
    /// `W / w`: how much the anchored item grows.
    var growth: CGFloat { idleLength > 0 ? activeLength / idleLength : 1 }

    /// The idle length of the item at a virtual index.
    func idleLength(of virtualIndex: Int, widths: RingWidths) -> CGFloat {
        idleLength * widths.ratio(at: virtualIndex)
    }

    /// The length of the item at a virtual index at a rendering phase: grown by its emphasis.
    func length(of virtualIndex: Int, phase: Double, widths: RingWidths) -> CGFloat {
        let emphasis = emphasis(at: Double(virtualIndex) - phase)
        return idleLength(of: virtualIndex, widths: widths) * (1 + (growth - 1) * emphasis)
    }

    /// The Anchor Spot's center while the item at `virtualIndex` rests there.
    func anchorCenter(anchoring virtualIndex: Int, widths: RingWidths) -> CGFloat {
        let active = idleLength(of: virtualIndex, widths: widths) * growth
        switch anchor {
        case .leading: return leadingInset + active / 2
        case .center: return (leadingInset + viewportLength - trailingInset) / 2
        case .trailing: return viewportLength - trailingInset - active / 2
        }
    }

    /// The center of the item at a virtual index at a rendering phase (behavior §1.12). Between rotations `r` and
    /// `r + 1`, at fraction `t`, the anchor point moves from `r`'s anchor center to `r + 1`'s and sits `t` of the
    /// way from `r`'s center to `r + 1`'s; every other item follows with exactly `spacing` between neighbours.
    /// With equal widths this is `center(at:)`.
    func center(of virtualIndex: Int, phase: Double, widths: RingWidths) -> CGFloat {
        let bounded = phase.isFinite ? min(max(phase, -1e15), 1e15) : 0
        let base = Int(bounded.rounded(.down))
        let fraction = CGFloat(bounded - Double(base))
        func length(_ index: Int) -> CGFloat { self.length(of: index, phase: bounded, widths: widths) }
        let pin = anchorCenter(anchoring: base, widths: widths) * (1 - fraction)
            + anchorCenter(anchoring: base + 1, widths: widths) * fraction
        var center = pin - fraction * ((length(base) + length(base + 1)) / 2 + spacing)
        var index = base
        while index < virtualIndex {
            center += (length(index) + length(index + 1)) / 2 + spacing
            index += 1
        }
        while index > virtualIndex {
            center -= (length(index) + length(index - 1)) / 2 + spacing
            index -= 1
        }
        return center
    }

    /// Points per slot for drags and scrubs while `rotation` is anchored: the mean idle length of the anchored item
    /// and the next one, plus the spacing (`step` on a uniform ring).
    func dragStep(at rotation: Int, widths: RingWidths) -> CGFloat {
        (idleLength(of: rotation, widths: widths) + idleLength(of: rotation + 1, widths: widths)) / 2 + spacing
    }

    /// The rest window while the item at `rotation` is anchored (behavior §1.12): the same rule as
    /// `restWindow(count:)`, counting the items that are at least partly inside the viewport at their own widths.
    func restWindow(count: Int, rotation: Int, widths: RingWidths) -> ClosedRange<Int> {
        guard !widths.isUniform else { return restWindow(count: count) }
        let others = max(count - 1, 0)
        let after = fittingCount(from: rotation, direction: 1, limit: others, widths: widths)
        let before = fittingCount(from: rotation, direction: -1, limit: others, widths: widths)
        return Self.restWindow(others: others, fittingAfter: after, fittingBefore: before, anchor: anchor)
    }

    /// The items after (`direction` 1) or before (-1) the anchored one, at rest, whose near edge is inside the
    /// viewport, up to `limit`.
    private func fittingCount(from rotation: Int, direction: Int, limit: Int, widths: RingWidths) -> Int {
        let anchored = idleLength(of: rotation, widths: widths) * growth
        var edge = anchorCenter(anchoring: rotation, widths: widths) + CGFloat(direction) * anchored / 2
        var count = 0
        while count < min(limit, 10_000) {
            let nearEdge = edge + CGFloat(direction) * spacing
            guard direction > 0 ? nearEdge < viewportLength : nearEdge > 0 else { break }
            count += 1
            edge = nearEdge + CGFloat(direction) * idleLength(of: rotation + direction * count, widths: widths)
        }
        return count
    }

    /// The opacity of the item at a virtual index at a rendering phase, for rest windows that may differ per
    /// rotation (behavior §1.12). Between rotations `r` and `r + 1` an item in both windows stays opaque, one
    /// leaving `r`'s fades out and one entering `r + 1`'s fades in, each over `fadeLength` slots of travel. With
    /// one window for every rotation this is `opacity(at:rest:)`.
    func opacity(of virtualIndex: Int, phase: Double, rests: RestWindows) -> Double {
        let bounded = phase.isFinite ? min(max(phase, -1e15), 1e15) : 0
        let base = Int(bounded.rounded(.down))
        let fraction = bounded - Double(base)
        let inBase = rests.window(at: base).contains(virtualIndex - base)
        let inNext = rests.window(at: base + 1).contains(virtualIndex - base - 1)
        switch (inBase, inNext) {
        case (true, true): return 1
        case (true, false): return max(0, 1 - fraction / fadeLength)
        case (false, true): return max(0, 1 - (1 - fraction) / fadeLength)
        case (false, false): return 0
        }
    }
}

// MARK: - The strip a ring's effects share

/// Everything a ShelfRing's effects need to place a card (behavior §1.12): the active ring's geometry, the card
/// widths around the rotations in flight, and the rest windows of the active and the inactive ring at each of
/// those rotations. A uniform ring holds one rest window of each and uses the uniform slot functions, so it
/// places cards exactly as a ring without per-card shapes. Its cost follows the viewport and the rotations in
/// flight, never the ring's length (D4).
nonisolated struct RingStrip: Sendable, Equatable {
    var geometry: RingGeometry
    var widths: RingWidths
    var activeRests: RestWindows
    var inactiveRests: RestWindows

    init(geometry: RingGeometry, widths: RingWidths, activeRests: RestWindows, inactiveRests: RestWindows) {
        self.geometry = geometry
        self.widths = widths
        self.activeRests = activeRests
        self.inactiveRests = inactiveRests
    }

    /// The strip of a ring of `itemCount` cards rendered around `rotations`.
    /// - Parameters:
    ///   - cardSize: The shelf's idle card size.
    ///   - cardAspectRatio: The `ShelfCardContent.cardAspectRatio` of the card at a ring index.
    init(
        geometry: RingGeometry, cardSize: CGSize, itemCount: Int, covering rotations: ClosedRange<Int>,
        cardAspectRatio: (Int) -> CGFloat?
    ) {
        let inactive = geometry.withActivity(0)
        guard itemCount > 0 else {
            self.init(geometry: geometry, widths: .uniform, activeRests: RestWindows(single: 0...0),
                      inactiveRests: RestWindows(single: 0...0))
            return
        }
        // The narrowest card any shape allows bounds how many cards can show on one side of the anchor.
        let narrowest = min(1, RingWidths.widthRatio(
            cardAspectRatio: RingWidths.aspectRatioRange.lowerBound, cardSize: cardSize
        ))
        let perCard = max(geometry.idleLength * narrowest + geometry.spacing, 1)
        let fitting = Double(geometry.viewportLength / perCard).rounded(.up)
        let reach = min(itemCount, Int(min(max(fitting, 0), 10_000)) + 1)
        let window = (rotations.lowerBound - reach - 2)...(rotations.upperBound + reach + 2)
        let widths = RingWidths.window(window) { virtualIndex in
            RingWidths.widthRatio(
                cardAspectRatio: cardAspectRatio(RingMath.floorMod(virtualIndex, itemCount)), cardSize: cardSize
            )
        }
        guard !widths.isUniform else {
            self.init(
                geometry: geometry, widths: widths,
                activeRests: RestWindows(single: geometry.restWindow(count: itemCount)),
                inactiveRests: RestWindows(single: inactive.restWindow(count: itemCount))
            )
            return
        }
        let restRotations = (rotations.lowerBound - 1)...(rotations.upperBound + 1)
        self.init(
            geometry: geometry, widths: widths,
            activeRests: RestWindows(firstRotation: restRotations.lowerBound, windows: restRotations.map {
                geometry.restWindow(count: itemCount, rotation: $0, widths: widths)
            }),
            inactiveRests: RestWindows(firstRotation: restRotations.lowerBound, windows: restRotations.map {
                inactive.restWindow(count: itemCount, rotation: $0, widths: widths)
            })
        )
    }

    /// The strip of an empty shelf's one placeholder card.
    static func placeholder(geometry: RingGeometry) -> RingStrip {
        RingStrip(geometry: geometry, widths: .uniform, activeRests: RestWindows(single: 0...0),
                  inactiveRests: RestWindows(single: 0...0))
    }

    /// The slots to render around the rotations in flight: every rest window of the active and inactive ring.
    var renderRest: ClosedRange<Int> { RingPhase.union(activeRests.union, inactiveRests.union) }

    /// The rest window at a rotation, of the active ring or of an inactive one.
    func restWindow(at rotation: Int, isActive: Bool) -> ClosedRange<Int> {
        (isActive ? activeRests : inactiveRests).window(at: rotation)
    }

    /// The idle width of the card at a virtual index.
    func idleWidth(of virtualIndex: Int) -> CGFloat {
        geometry.idleLength(of: virtualIndex, widths: widths)
    }

    /// Points per slot for drags and scrubs while `rotation` is anchored: the mean width of the anchored card and
    /// the next one, plus the spacing (`step` on a uniform ring).
    func step(at rotation: Int) -> CGFloat {
        geometry.dragStep(at: rotation, widths: widths)
    }

    /// The x offset of the idle-size card at a virtual index, at continuous `slot` (`virtualIndex - phase`).
    func offset(of virtualIndex: Int, slot: Double, activity: Double) -> CGFloat {
        let ring = geometry.withActivity(activity)
        guard !widths.isUniform else { return ring.center(at: slot) - ring.idleLength / 2 }
        let phase = Double(virtualIndex) - slot
        return ring.center(of: virtualIndex, phase: phase, widths: widths) - idleWidth(of: virtualIndex) / 2
    }

    /// The card's opacity, blended between the active and inactive rest windows by `activity` (behavior §1.4).
    func opacity(of virtualIndex: Int, slot: Double, activity: Double) -> Double {
        let active: Double
        let inactive: Double
        if widths.isUniform {
            active = geometry.opacity(at: slot, rest: activeRests.window(at: 0))
            inactive = geometry.opacity(at: slot, rest: inactiveRests.window(at: 0))
        } else {
            let phase = Double(virtualIndex) - slot
            active = geometry.opacity(of: virtualIndex, phase: phase, rests: activeRests)
            inactive = geometry.opacity(of: virtualIndex, phase: phase, rests: inactiveRests)
        }
        return inactive + (active - inactive) * activity
    }

    /// The center of the seam bar after the card at a virtual index: the middle of the gap after it (R20).
    func seamCenter(after virtualIndex: Int, slot: Double, activity: Double) -> CGFloat {
        let ring = geometry.withActivity(activity)
        guard !widths.isUniform else { return ring.seamCenter(afterSlot: slot) }
        let phase = Double(virtualIndex) - slot
        return ring.center(of: virtualIndex, phase: phase, widths: widths)
            + ring.length(of: virtualIndex, phase: phase, widths: widths) / 2 + ring.spacing / 2
    }
}
