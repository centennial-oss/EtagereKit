import CoreGraphics
import Observation
import SwiftUI

/// The Etagere's state: its shelves, each with its own observable ring, and the single selection across them (R9).
///
/// `shelfRotation` places the Active Shelf. In ring mode (mode 1) it is unbounded like a card ring's rotation, so a
/// wrapping shelf keeps its `(shelfID, lap)` identity; in cursor mode (mode 2) it stays in `0..<shelves.count`.
@Observable
public final class EtagereModel<Card: ShelfCardContent> {
    public internal(set) var shelves: [ShelfState<Card>]
    public internal(set) var shelfRotation = 0
    /// Where the oldest shelf animation still running began; equal to `shelfRotation` at rest.
    public internal(set) var settledShelfRotation = 0
    /// The shelf rotations mode 1's render window covers (behavior §1.5, §2.1), as `ShelfState.rotationsInFlight`.
    public internal(set) var shelfRotationsInFlight: ClosedRange<Int> = 0...0
    /// Bumped when the shelves jump without animating: a restore, a vertical mode change, or a reload that changes
    /// the list of shelf IDs. The view crossfades the shelves when it changes (behavior §1.8).
    public internal(set) var shelfJumpGeneration = 0
    private var storedConfiguration: EtagereConfiguration
    @ObservationIgnored private var shelfFlights = RingFlights()
    /// Runs every animated change; SwiftUI's `withAnimation(_:completionCriteria: .removed)` unless a test holds
    /// the completions to look at the cards in flight (D3).
    @ObservationIgnored var animationRunner: EtagereAnimationRunner = runWithSwiftUIAnimation

    /// Shelf IDs must be unique; later duplicates are dropped.
    public init(shelves: [Shelf<Card>], configuration: EtagereConfiguration = EtagereConfiguration()) {
        self.shelves = shelves.uniquedByID().map { ShelfState($0) }
        storedConfiguration = configuration
    }

    public var configuration: EtagereConfiguration {
        get { storedConfiguration }
        set {
            let modeChanged = newValue.verticalMode != storedConfiguration.verticalMode
            storedConfiguration = newValue
            if modeChanged, !shelves.isEmpty {
                // Cursor mode keeps the rotation inside the shelf indices; the active shelf does not change.
                let normalized = RingMath.floorMod(shelfRotation, shelves.count)
                setShelfRotation(normalized, isJump: normalized != shelfRotation)
            }
        }
    }

    // MARK: The selection

    public var activeShelfIndex: Int? {
        shelves.isEmpty ? nil : RingMath.floorMod(shelfRotation, shelves.count)
    }

    public var activeShelf: ShelfState<Card>? { activeShelfIndex.map { shelves[$0] } }

    /// The Active ShelfCard: the one selection in the Etagere (R9). It is the target of any move in flight, so "go"
    /// during an animation plays the card that is arriving (D3). Nil when the Active Shelf is empty (Q7).
    public var activeCard: Card? { activeShelf?.anchoredCard }

    /// What "go" acts on: the Active ShelfCard, or the placeholder of an empty Active Shelf (Q7).
    public var activation: EtagereActivation<Card>? {
        guard let shelf = activeShelf else { return nil }
        return shelf.anchoredCard.map { .card($0) } ?? .emptyShelf(shelfID: shelf.id)
    }

    public func shelf(id: String) -> ShelfState<Card>? {
        shelves.first { $0.id == id }
    }

    /// True for the rendered copy of a shelf that holds the selection: the copy at `shelfRotation` (in mode 1 the
    /// copy nearest the anchor; in mode 2 shelf `virtualIndex` itself).
    public func isShelfActive(virtualIndex: Int) -> Bool {
        !shelves.isEmpty && virtualIndex == shelfRotation
    }

    /// The context for a card copy at `cardVirtualIndex` on the shelf copy at `shelfVirtualIndex`. Exactly one
    /// rendered card gets `isActive` (T15). Nil when there are no shelves or that shelf is empty.
    public func cardContext(shelfVirtualIndex: Int, cardVirtualIndex: Int, faceSize: CGSize) -> ShelfCardContext? {
        guard !shelves.isEmpty else { return nil }
        let shelf = shelves[RingMath.floorMod(shelfVirtualIndex, shelves.count)]
        return shelf.cardContext(
            virtualIndex: cardVirtualIndex, isShelfActive: isShelfActive(virtualIndex: shelfVirtualIndex),
            faceSize: faceSize
        )
    }

    /// The shelf copies to render in mode 1 for a rest window of the vertical ring.
    public func shelfRenderSlots(rest: ClosedRange<Int>) -> [RingSlot<String>] {
        RingMath.renderSlots(itemCount: shelves.count, covering: shelfRotationsInFlight, rest: rest) { shelves[$0].id }
    }

    // MARK: Moves

    /// Applies a logical move at once (input is never locked, D3), animated as `EtagereAnimationChoice.choose`
    /// decides: a card step, a shelf step (`shelfStepAnimation` in mode 1, `highlightAnimation` in mode 2), a repeat
    /// retimed to `repeatInterval`, or nothing under Reduce Motion.
    ///
    /// Returns whether the move was consumed (T16). Mode 1 consumes every move, even where nothing can move (one
    /// card, one shelf, an empty shelf), so directional input never leaves the Etagere (R27); the view gives a small
    /// bump instead. Mode 2 returns false for a shelf move at the top or bottom, so the host can move focus to
    /// controls above or below (R28, Q2); it never wraps.
    @discardableResult
    public func move(
        _ move: EtagereMove, isRepeat: Bool, repeatInterval: Double? = nil, reduceMotion: Bool
    ) -> Bool {
        let choice = EtagereAnimationChoice.choose(
            for: move, verticalMode: configuration.verticalMode, isRepeat: isRepeat, repeatInterval: repeatInterval,
            reduceMotion: reduceMotion
        )
        let animation = configuration.animation(for: choice)
        return move.isHorizontal
            ? moveCard(by: move.delta, animation: animation)
            : moveShelf(by: move.delta, animation: animation)
    }

    /// Makes the shelf with `id` the Active Shelf (mode 2 focus, VoiceOver focus, a tap on a shelf). Mode 1 rotates
    /// the ShelvesRing the shortest way; mode 2 moves the cursor. Pass `shelfStepAnimation` in mode 1 or
    /// `highlightAnimation` in mode 2, or nil under Reduce Motion. Returns false when there is no such shelf.
    @discardableResult
    public func activateShelf(id: String, animation: Animation? = nil) -> Bool {
        guard let target = shelves.firstIndex(where: { $0.id == id }), let current = activeShelfIndex else {
            return false
        }
        guard target != current else { return true }
        let newRotation = switch configuration.verticalMode {
        case .ring: shelfRotation + RingMath.shortestDelta(from: current, to: target, itemCount: shelves.count)
        case .cursor: target
        }
        animateShelfRotation(to: newRotation, animation: animation)
        return true
    }

    private func moveCard(by delta: Int, animation: Animation?) -> Bool {
        guard let shelf = activeShelf else { return configuration.verticalMode == .ring }
        guard shelf.cards.count > 1 else { return true }
        perform(animation) {
            shelf.rotate(by: delta)
        } settle: { token in
            shelf.settle(token)
        }
        return true
    }

    private func moveShelf(by delta: Int, animation: Animation?) -> Bool {
        switch configuration.verticalMode {
        case .ring:
            if shelves.count > 1 {
                animateShelfRotation(to: shelfRotation + delta, animation: animation)
            }
            return true
        case .cursor:
            let target = shelfRotation + delta
            guard !shelves.isEmpty, target >= 0, target < shelves.count else { return false }
            animateShelfRotation(to: target, animation: animation)
            return true
        }
    }

    // MARK: Shelf rotation

    func animateShelfRotation(to newRotation: Int, animation: Animation?) {
        perform(animation) { [self] in
            guard newRotation != shelfRotation else { return ShelfState<Card>.noOpToken }
            let token = shelfFlights.takeOff(from: shelfRotation, to: newRotation)
            shelfRotation = newRotation
            syncShelfFlights()
            return token
        } settle: { [weak self] token in
            self?.settleShelves(token)
        }
    }

    /// Records that the shelf animation that returned `token` has finished, as `ShelfState.settle(_:)` does.
    func settleShelves(_ token: Int) {
        guard shelfFlights.land(token) else { return }
        syncShelfFlights()
    }

    /// Moves the shelves without animating and settles them at once; animations still running are forgotten.
    /// `isJump` bumps `shelfJumpGeneration`, even when the rotation keeps its value but a different shelf now sits
    /// there.
    func setShelfRotation(_ newRotation: Int, isJump: Bool) {
        shelfFlights.removeAll()
        if newRotation != shelfRotation { shelfRotation = newRotation }
        syncShelfFlights()
        if isJump { shelfJumpGeneration += 1 }
    }

    /// Publishes the shelf flights' settled rotation and covered rotations, touching only what changed.
    private func syncShelfFlights() {
        let settled = shelfFlights.settledRotation(at: shelfRotation)
        if settledShelfRotation != settled { settledShelfRotation = settled }
        let covered = shelfFlights.coveredRotations(at: shelfRotation)
        if shelfRotationsInFlight != covered { shelfRotationsInFlight = covered }
    }

    /// Applies `change` under `animation` and hands its settle token to `settle` once the animation is removed, so
    /// the render window shrinks only behind cards that are no longer in flight (behavior §1.5).
    ///
    /// Without an animation (Reduce Motion) the change is applied in a transaction with a nil animation, as in the
    /// prototype, and settled at once. It does not set `disablesAnimations`: that would also stop the views' own
    /// `.animation(_:value:)` modifiers, and Reduce Motion still crossfades the emphasis of the old and new active
    /// cards, the vertical ring and the mode 2 highlight (behavior §4).
    func perform(_ animation: Animation?, change: () -> Int, settle: @escaping (Int) -> Void) {
        guard let animation else {
            settle(withAnimation(nil, change))
            return
        }
        var token = ShelfState<Card>.noOpToken
        animationRunner(animation, { token = change() }, { settle(token) })
    }
}

/// Applies a change under an animation and calls `completion` once that animation has been removed, so the model
/// can settle its render windows only when nothing is in flight any more (behavior §1.5, D3).
typealias EtagereAnimationRunner = @MainActor (
    _ animation: Animation, _ change: () -> Void, _ completion: @escaping () -> Void
) -> Void

/// The runner every model uses outside tests.
func runWithSwiftUIAnimation(
    _ animation: Animation, change: () -> Void, completion: @escaping () -> Void
) {
    withAnimation(animation, completionCriteria: .removed, change, completion: completion)
}
