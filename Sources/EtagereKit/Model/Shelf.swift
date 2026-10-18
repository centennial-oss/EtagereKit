/// One titled row of cards, as the host describes it. Generic over a single card type, so shelves are homogeneous
/// by construction (R5).
public nonisolated struct Shelf<Card: ShelfCardContent>: Identifiable, Sendable, Equatable {
    /// Unique within the Etagere; it keys the active shelf and the saved position.
    public let id: String
    public var title: String
    /// Card IDs must be unique within the shelf. Later duplicates are dropped when the shelf is loaded.
    public var cards: [Card]
    /// The text of the one placeholder card an empty shelf shows (Q7). Empty shelves stay in the Etagere and can
    /// become the Active Shelf; "go" on one runs the host's empty-shelf action.
    public var emptyMessage: String?
    /// True while the host is refreshing this shelf (a source is still loading, say). The Etagere shows a quiet
    /// "Updating" next to the title, and VoiceOver reads it with the shelf's value. Changing it never moves a card.
    public var isUpdating: Bool

    public init(id: String, title: String, cards: [Card], emptyMessage: String? = nil, isUpdating: Bool = false) {
        self.id = id
        self.title = title
        self.cards = cards
        self.emptyMessage = emptyMessage
        self.isUpdating = isUpdating
    }
}

/// What "go" (R8) acts on.
public nonisolated enum EtagereActivation<Card: ShelfCardContent>: Sendable, Equatable {
    /// The Active ShelfCard.
    case card(Card)
    /// The placeholder of an empty Active Shelf (Q7); the host runs its action for that shelf.
    case emptyShelf(shelfID: String)
}

/// The position to remember between launches (Q8): the Active Shelf and each shelf's anchored card.
/// `EtagereModel.restore(_:)` skips shelves and cards that no longer exist.
public nonisolated struct EtagerePosition<CardID: Hashable & Sendable>: Sendable, Hashable {
    public var activeShelfID: String?
    /// Anchored card IDs by shelf ID. Empty shelves have no entry.
    public var anchoredCardIDs: [String: CardID]

    public init(activeShelfID: String? = nil, anchoredCardIDs: [String: CardID] = [:]) {
        self.activeShelfID = activeShelfID
        self.anchoredCardIDs = anchoredCardIDs
    }
}

nonisolated extension EtagerePosition: Codable where CardID: Codable {}

nonisolated extension Array where Element: Identifiable {
    /// The elements with the first occurrence of each ID kept and later duplicates dropped.
    func uniquedByID() -> [Element] {
        var seen = Set<Element.ID>()
        seen.reserveCapacity(count)
        return filter { seen.insert($0.id).inserted }
    }
}
