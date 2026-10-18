/// Identity of one rendered copy of a ring item (behavior §1.5). The same item can be on screen twice during a wrap,
/// leaving one end while it enters the other (R14); `lap` keeps those copies distinct.
public nonisolated struct RingSlotKey<ItemID: Hashable & Sendable>: Hashable, Sendable {
    public let itemID: ItemID
    public let lap: Int

    public init(itemID: ItemID, lap: Int) {
        self.itemID = itemID
        self.lap = lap
    }
}

/// One rendered copy of a ring item: a card on a ShelfRing, or a shelf on the vertical ShelvesRing.
public nonisolated struct RingSlot<ItemID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public let id: RingSlotKey<ItemID>
    /// Unbounded position in the infinite unrolled ring.
    public let virtualIndex: Int
    /// Index into the item array: `floorMod(virtualIndex, count)`.
    public let ringIndex: Int
    /// True for every copy of the ring's last item when the ring has two or more items: the seam bar follows it (R20).
    public let isSeamOwner: Bool

    public init(id: RingSlotKey<ItemID>, virtualIndex: Int, ringIndex: Int, isSeamOwner: Bool) {
        self.id = id
        self.virtualIndex = virtualIndex
        self.ringIndex = ringIndex
        self.isSeamOwner = isSeamOwner
    }

    public var lap: Int { id.lap }

    /// The continuous slot of this copy (`v - phase`) for a rendering phase: `Double(rotation)` at rest, or the
    /// fractional phase of a drag or a snapshot.
    public func slot(atPhase phase: Double) -> Double {
        Double(virtualIndex) - phase
    }
}

/// Floor arithmetic and the render window shared by both ring axes.
public nonisolated enum RingMath {
    /// Division rounded toward negative infinity. `divisor` must be positive.
    public static func floorDiv(_ dividend: Int, _ divisor: Int) -> Int {
        precondition(divisor > 0, "RingMath.floorDiv needs a positive divisor")
        let quotient = dividend / divisor
        return (dividend % divisor != 0 && dividend < 0) ? quotient - 1 : quotient
    }

    /// The remainder that pairs with `floorDiv`, always in `0..<divisor`. `divisor` must be positive.
    public static func floorMod(_ dividend: Int, _ divisor: Int) -> Int {
        precondition(divisor > 0, "RingMath.floorMod needs a positive divisor")
        let remainder = dividend % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }

    /// The shortest signed rotation from ring index `from` to ring index `target` in a ring of `itemCount` items.
    /// Ties (exactly half way round an even ring) go forward. Returns 0 for rings of fewer than two items.
    public static func shortestDelta(from origin: Int, to target: Int, itemCount: Int) -> Int {
        guard itemCount > 1 else { return 0 }
        let forward = floorMod(target - origin, itemCount)
        return forward > itemCount / 2 ? forward - itemCount : forward
    }

    /// The rotation after a ring's items change (behavior §1.10). The anchored item stays anchored on the same lap
    /// when it is still present (`newIndexOfAnchored`); when it is gone, the item now at the old anchored index
    /// (clamped to the new last item) is anchored on the same lap. Empty rings rest at rotation 0.
    public static func rebasedRotation(_ rotation: Int, oldCount: Int, newIndexOfAnchored: Int?, newCount: Int) -> Int {
        guard newCount > 0 else { return 0 }
        guard oldCount > 0 else { return min(max(newIndexOfAnchored ?? 0, 0), newCount - 1) }
        let lap = floorDiv(rotation, oldCount)
        let index = newIndexOfAnchored ?? min(floorMod(rotation, oldCount), newCount - 1)
        return lap * newCount + index
    }

    /// The virtual indices to render (behavior §1.5): the rest window around both the target and the settled
    /// rotation, plus one always-transparent slot on each side, so views are inserted and removed only while
    /// invisible. Its size depends on the window and the rotation in flight, never on the ring's length (D4).
    public static func renderRange(rotation: Int, settledRotation: Int, rest: ClosedRange<Int>) -> ClosedRange<Int> {
        renderRange(covering: min(rotation, settledRotation)...max(rotation, settledRotation), rest: rest)
    }

    /// The virtual indices to render around every rotation in `rotations` (a ring's `rotationsInFlight`).
    public static func renderRange(covering rotations: ClosedRange<Int>, rest: ClosedRange<Int>) -> ClosedRange<Int> {
        (rotations.lowerBound + rest.lowerBound - 1)...(rotations.upperBound + rest.upperBound + 1)
    }

    /// The rendered copies for a ring of `itemCount` items. `itemID` is asked only for the ring indices in the
    /// render range, so the cost does not grow with the ring (a 10,000-card ring renders as many as a 12-card one).
    public static func renderSlots<ItemID>(
        itemCount: Int,
        rotation: Int,
        settledRotation: Int,
        rest: ClosedRange<Int>,
        itemID: (Int) -> ItemID
    ) -> [RingSlot<ItemID>] {
        guard itemCount > 0 else { return [] }
        let range = renderRange(rotation: rotation, settledRotation: settledRotation, rest: rest)
        return range.map { virtualIndex in
            let ringIndex = floorMod(virtualIndex, itemCount)
            return RingSlot(
                id: RingSlotKey(itemID: itemID(ringIndex), lap: floorDiv(virtualIndex, itemCount)),
                virtualIndex: virtualIndex,
                ringIndex: ringIndex,
                isSeamOwner: itemCount > 1 && ringIndex == itemCount - 1
            )
        }
    }

    /// The rendered copies around every rotation in `rotations` (a ring's `rotationsInFlight`).
    public static func renderSlots<ItemID>(
        itemCount: Int, covering rotations: ClosedRange<Int>, rest: ClosedRange<Int>, itemID: (Int) -> ItemID
    ) -> [RingSlot<ItemID>] {
        renderSlots(
            itemCount: itemCount, rotation: rotations.upperBound, settledRotation: rotations.lowerBound, rest: rest,
            itemID: itemID
        )
    }

    /// `renderSlots` for an array of item IDs.
    public static func renderSlots<ItemID>(
        ids: [ItemID], rotation: Int, settledRotation: Int, rest: ClosedRange<Int>
    ) -> [RingSlot<ItemID>] {
        renderSlots(itemCount: ids.count, rotation: rotation, settledRotation: settledRotation, rest: rest) { ids[$0] }
    }
}
