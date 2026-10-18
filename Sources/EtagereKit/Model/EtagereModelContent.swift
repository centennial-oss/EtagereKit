extension EtagereModel {
    // MARK: Content changes (D8)

    /// Replaces the shelves and keeps the selection. Shelves whose ID is still present keep their `ShelfState`
    /// (its observers, its rotation and so its anchored card) and take the new title, placeholder text and cards
    /// through `ShelfState.replaceCards`. The Active Shelf stays active, on the same lap in mode 1; when it is gone,
    /// the shelf now at the old active index (clamped) becomes active. Empty shelves are kept (Q7). Later
    /// duplicate shelf IDs are dropped.
    ///
    /// When the list of shelf IDs changes, the shelves jump (behavior §1.8): they settle at once and
    /// `shelfJumpGeneration` is bumped so the view crossfades them, even when the Active Shelf stays.
    public func replaceShelves(_ newShelves: [Shelf<Card>]) {
        let unique = newShelves.uniquedByID()
        let existing = Dictionary(shelves.map { ($0.id, $0) }) { first, _ in first }
        let states = unique.map { shelf in
            guard let state = existing[shelf.id] else { return ShelfState(shelf) }
            state.apply(shelf)
            return state
        }
        guard !states.lazy.map(\.id).elementsEqual(shelves.lazy.map(\.id)) else { return }
        let activeID = activeShelf?.id
        let newIndex = activeID.flatMap { active in states.firstIndex { $0.id == active } }
        let newRotation = RingMath.rebasedRotation(
            shelfRotation, oldCount: shelves.count, newIndexOfAnchored: newIndex, newCount: states.count
        )
        shelves = states
        setShelfRotation(newRotation, isJump: true)
    }

    // MARK: Position (Q8)

    /// The Active Shelf and every non-empty shelf's anchored card, for the host to save between launches.
    public var position: EtagerePosition<Card.ID> {
        var anchored: [String: Card.ID] = [:]
        for shelf in shelves {
            if let card = shelf.anchoredCard { anchored[shelf.id] = card.id }
        }
        return EtagerePosition(activeShelfID: activeShelf?.id, anchoredCardIDs: anchored)
    }

    /// Restores a saved position without animating. Shelves and cards that no longer exist are skipped: their
    /// shelves keep their current anchored card, and a missing active shelf leaves the current one active.
    public func restore(_ position: EtagerePosition<Card.ID>) {
        for shelf in shelves {
            if let cardID = position.anchoredCardIDs[shelf.id] {
                shelf.jump(toCard: cardID)
            }
        }
        guard let activeID = position.activeShelfID,
              let target = shelves.firstIndex(where: { $0.id == activeID }),
              let current = activeShelfIndex, target != current else { return }
        let newRotation = switch configuration.verticalMode {
        case .ring: RingMath.floorDiv(shelfRotation, shelves.count) * shelves.count + target
        case .cursor: target
        }
        setShelfRotation(newRotation, isJump: true)
    }
}
