import CoreGraphics
import Observation

/// One shelf's live state. Each shelf is its own observable, so rotating one shelf invalidates only that shelf's
/// views (D4).
///
/// `rotation` is unbounded: the anchored index is `floorMod(rotation, count)` and a rendered copy's lap is
/// `floorDiv(virtualIndex, count)`. It never wraps, so each on-screen copy keeps its `(cardID, lap)` identity while
/// the ring turns. While animations run, `rotationsInFlight` keeps every card in flight rendered, and it shrinks
/// behind them as the oldest animations end, so a held key never grows the render window (behavior §1.5, D3, D4).
@Observable
public final class ShelfState<Card: ShelfCardContent>: Identifiable {
    /// The token returned when a call changes nothing. `settle(_:)` ignores it.
    public static var noOpToken: Int { -1 }

    public let id: String
    public private(set) var title: String
    public private(set) var cards: [Card]
    public private(set) var emptyMessage: String?
    /// True while the host is refreshing this shelf's cards; the title shows a quiet "Updating" next to it.
    public private(set) var isUpdating: Bool
    public private(set) var rotation = 0
    /// Where the oldest animation still running began (behind a run of moves in one direction, the far end of the
    /// render window). Equal to `rotation` at rest.
    public private(set) var settledRotation = 0
    /// The rotations the render window covers (behavior §1.5): `rotation` at rest; during animations, every
    /// rotation since the oldest animation still running began, at most `RingFlights.maximumLag` slots from
    /// `rotation`, so its size never depends on the number of cards (D4).
    public private(set) var rotationsInFlight: ClosedRange<Int> = 0...0
    /// Bumped when the ring jumps without animating (a restore, or a reload that changes the list of card IDs); the
    /// view crossfades the ring when it changes (behavior §1.8).
    public private(set) var jumpGeneration = 0
    @ObservationIgnored private var flights = RingFlights()

    public init(_ shelf: Shelf<Card>) {
        id = shelf.id
        title = shelf.title
        cards = shelf.cards.uniquedByID()
        emptyMessage = shelf.emptyMessage
        isUpdating = shelf.isUpdating
    }

    /// True when the shelf shows its placeholder card (Q7).
    public var isEmpty: Bool { cards.isEmpty }

    public var anchoredIndex: Int? {
        cards.isEmpty ? nil : RingMath.floorMod(rotation, cards.count)
    }

    /// The card at the Anchor Spot; nil only when the shelf is empty.
    public var anchoredCard: Card? { anchoredIndex.map { cards[$0] } }

    /// True when no animation is moving the ring.
    public var isSettled: Bool { rotationsInFlight == rotation...rotation }

    // MARK: Rotation

    /// Moves the target rotation by `delta` slots at once (input is never locked, D3) and returns the token to pass
    /// to `settle(_:)` when the animation finishes. A no-op for rings of fewer than two cards (R11).
    @discardableResult
    public func rotate(by delta: Int) -> Int {
        guard cards.count > 1, delta != 0 else { return Self.noOpToken }
        let token = flights.takeOff(from: rotation, to: rotation + delta)
        rotation += delta
        syncFlights()
        return token
    }

    /// Rotates the shortest way so `cardID` becomes anchored; ties go forward (a tap or click on a visible card,
    /// behavior §1.8). A no-op when the card is missing or already anchored.
    @discardableResult
    public func rotate(toCard cardID: Card.ID) -> Int {
        guard let target = cards.firstIndex(where: { $0.id == cardID }), let current = anchoredIndex else {
            return Self.noOpToken
        }
        return rotate(by: RingMath.shortestDelta(from: current, to: target, itemCount: cards.count))
    }

    /// Records that the animation started by the call that returned `token` has finished (T13). The latest token
    /// settles the ring. An older one shrinks the render window only up to the oldest animation still running, so
    /// cards in flight stay rendered under rapid input while a held key keeps the window small. Tokens from before
    /// a jump, and the no-op token, change nothing.
    public func settle(_ token: Int) {
        guard flights.land(token) else { return }
        syncFlights()
    }

    /// Anchors `cardID` without animating (type-ahead, a far tap, a restore), on the current lap, and bumps
    /// `jumpGeneration`. Returns false when the card is not on the shelf.
    @discardableResult
    public func jump(toCard cardID: Card.ID) -> Bool {
        guard let target = cards.firstIndex(where: { $0.id == cardID }) else { return false }
        let newRotation = RingMath.floorDiv(rotation, cards.count) * cards.count + target
        guard newRotation != rotation || !isSettled else { return true }
        flights.removeAll()
        rotation = newRotation
        syncFlights()
        jumpGeneration += 1
        return true
    }

    // MARK: Content changes (behavior §1.10, D8)

    /// Replaces the cards and keeps the anchored card where it is. When the list of IDs is unchanged (a lineup
    /// refresh usually is), the rotation is untouched; changed card contents are still taken. Otherwise the
    /// rotation is re-based so the same card stays anchored on the same lap or, when that card is gone, the card
    /// now at the old anchored index (clamped) is. Later duplicate IDs are dropped.
    ///
    /// A re-base is a jump (behavior §1.8): the ring settles at once and `jumpGeneration` is bumped so the view
    /// crossfades it, even when the anchored card stays. Neighbours change slots, new cards appear inside the rest
    /// window and cards in flight drop out of the render window, none of which may simply pop.
    public func replaceCards(_ newCards: [Card]) {
        let unique = newCards.uniquedByID()
        guard unique != cards else { return }
        guard !unique.lazy.map(\.id).elementsEqual(cards.lazy.map(\.id)) else {
            cards = unique
            return
        }
        let anchoredID = anchoredCard?.id
        let newIndex = anchoredID.flatMap { anchored in unique.firstIndex { $0.id == anchored } }
        let newRotation = RingMath.rebasedRotation(
            rotation, oldCount: cards.count, newIndexOfAnchored: newIndex, newCount: unique.count
        )
        cards = unique
        flights.removeAll()
        rotation = newRotation
        syncFlights()
        jumpGeneration += 1
    }

    /// Takes a new title, placeholder text, status and cards for this shelf ID (`EtagereModel.replaceShelves`).
    func apply(_ shelf: Shelf<Card>) {
        if title != shelf.title { title = shelf.title }
        if emptyMessage != shelf.emptyMessage { emptyMessage = shelf.emptyMessage }
        if isUpdating != shelf.isUpdating { isUpdating = shelf.isUpdating }
        replaceCards(shelf.cards)
    }

    /// Publishes the flights' settled rotation and covered rotations, touching only what changed.
    private func syncFlights() {
        let settled = flights.settledRotation(at: rotation)
        if settledRotation != settled { settledRotation = settled }
        let covered = flights.coveredRotations(at: rotation)
        if rotationsInFlight != covered { rotationsInFlight = covered }
    }

    // MARK: Rendering helpers

    /// The copies to render for a rest window (behavior §1.5), including ghost copies during a wrap. The cost
    /// follows the window and the rotations in flight, not the number of cards.
    public func renderSlots(rest: ClosedRange<Int>) -> [RingSlot<Card.ID>] {
        RingMath.renderSlots(itemCount: cards.count, covering: rotationsInFlight, rest: rest) { cards[$0].id }
    }

    /// The context for the copy of a card at `virtualIndex`, on a copy of this shelf that is (or is not) the
    /// Active Shelf. Only the copy at `rotation` is anchored, so a ghost copy never is. Nil for an empty shelf.
    public func cardContext(virtualIndex: Int, isShelfActive: Bool, faceSize: CGSize) -> ShelfCardContext? {
        guard !cards.isEmpty else { return nil }
        let isAnchored = virtualIndex == rotation
        return ShelfCardContext(
            isActive: isAnchored && isShelfActive,
            isAnchored: isAnchored,
            isShelfActive: isShelfActive,
            ringIndex: RingMath.floorMod(virtualIndex, cards.count),
            ringCount: cards.count,
            faceSize: faceSize
        )
    }
}
