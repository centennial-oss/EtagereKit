import Foundation
import Observation
import SwiftUI

/// A small nudge for a move that is consumed but cannot move: one card, one shelf, or the end of mode 2 with
/// nowhere for focus to go (behavior §1.10, Q2). The view animates it as an 8 pt rubber-band bump.
nonisolated struct EtagereBump: Equatable, Sendable {
    static let distance: CGFloat = 8

    var count = 0
    /// +1 toward the next item, -1 toward the previous one.
    var direction = 0
    /// The shelf whose ring bumps; nil for the shelves themselves.
    var shelfID: String?

    mutating func trigger(towardNext: Bool, shelfID: String? = nil) {
        count += 1
        direction = towardNext ? 1 : -1
        self.shelfID = shelfID
    }

    /// The trigger one ring watches: the latest card bump when it was for that ring's shelf, otherwise a value that
    /// stays the same, so a ring never replays an old bump when the selection moves to or from it.
    func trigger(forShelf shelfID: String) -> EtagereBump {
        self.shelfID == shelfID ? self : EtagereBump()
    }

    /// The nudge along the ring's axis in leading-based (or top-based) coordinates: a "next" move pushes the
    /// content toward the leading or top edge, the way the next item would arrive.
    var offset: CGFloat { -CGFloat(direction) * Self.distance }
}

/// View-only state shared by the Etagere's subviews. Each property is observed separately, so a bump re-renders
/// only the rings that read it.
@Observable
final class EtagereViewState {
    /// True while the Etagere has keyboard (or remote) focus: the Active ShelfCard then shows the focus ring.
    var hasKeyboardFocus = false
    /// The active ring's bump.
    var cardBump = EtagereBump()
    /// The shelves' bump: mode 1 with one shelf, or mode 2 at an edge.
    var shelfBump = EtagereBump()
    /// The shelf under the pointer (macOS hover).
    var hoveredShelfID: String?
}

/// Turns input into model changes and host callbacks: one place for every platform's keys, commands, pointer,
/// drags, scrubs, controllers and VoiceOver (behavior §3.1).
final class EtagereController<Card: ShelfCardContent> {
    /// A drag or fling release (behavior §1.8).
    static var releaseAnimation: Animation { .smooth(duration: 0.45) }
    /// A tap farther away than this many slots jumps and crossfades instead of animating (behavior §1.8).
    static var maximumAnimatedTapSlots: Int { 6 }
    /// A second pointer activation sooner than this is ignored, so a double-click on the anchored card plays once.
    static var pointerActivationGuard: Double { 0.4 }

    /// tvOS mode 2: an edge command this soon after focus arrived on a row belongs to the move that brought it.
    static var edgeFocusGuard: Double { 0.1 }

    static var now: Double { ProcessInfo.processInfo.systemUptime }

    private(set) var model: EtagereModel<Card>
    let viewState = EtagereViewState()
    private(set) var handlers = EtagereHandlers<Card>()
    private(set) var reduceMotion = false
    private var repeatDetector = RepeatDetector()
    private var scrubDetector = RepeatDetector()
    private var lastPointerActivation = -Double.infinity
    private var lastRowFocusChange = -Double.infinity

    init(model: EtagereModel<Card>) {
        self.model = model
    }

    /// Takes the host's latest model, callbacks and accessibility setting. Called while the Etagere evaluates its
    /// body; it touches nothing that a view observes.
    func update(model newModel: EtagereModel<Card>, handlers newHandlers: EtagereHandlers<Card>, reduceMotion: Bool) {
        if newModel !== model {
            model = newModel
            repeatDetector.reset()
        }
        handlers = newHandlers
        self.reduceMotion = reduceMotion
    }

    var configuration: EtagereConfiguration { model.configuration }

    // MARK: Intents

    /// Performs an intent and returns whether it was consumed. `reportedRepeat` is the platform's key phase, or nil
    /// where there is none (the Siri Remote); `time` is a monotonic timestamp in seconds.
    @discardableResult
    func perform(_ intent: EtagereIntent, reportedRepeat: Bool? = nil, at time: Double = now) -> Bool {
        switch intent {
        case .move(let move):
            return perform(move, reportedRepeat: reportedRepeat, at: time)
        case .activate:
            activate()
            return true
        case .contextMenu:
            // The platform's context menu presents the actions; there is nothing to do here.
            return false
        case .exit:
            repeatDetector.reset()
            handlers.onExit()
            return true
        }
    }

    /// A physical key through `EtagereKeyMap`.
    @discardableResult
    func perform(key: EtagereKey, isRightToLeft: Bool, reportedRepeat: Bool? = nil, at time: Double = now) -> Bool {
        perform(EtagereKeyMap.intent(for: key, isRightToLeft: isRightToLeft), reportedRepeat: reportedRepeat, at: time)
    }

    private func perform(_ move: EtagereMove, reportedRepeat: Bool?, at time: Double) -> Bool {
        let sample = EtagereRepeat.resolve(
            reportedRepeat: reportedRepeat, sample: repeatDetector.register(move, at: time)
        )
        let moves = model.wouldMove(move)
        let consumed = model.move(
            move, isRepeat: sample.isRepeat, repeatInterval: sample.interval, reduceMotion: reduceMotion
        )
        if consumed {
            if !moves { bump(move) }
            return true
        }
        // Mode 2 without shelves lets left and right leave; the top and bottom ask the host (Q2).
        guard !move.isHorizontal else { return false }
        if let onEdge = handlers.onEdge, onEdge(move == .previousShelf ? .top : .bottom) {
            repeatDetector.reset()
            return true
        }
        bump(move)
        return true
    }

    /// tvOS mode 2 (behavior §2.2, Q2): up on the top row or down on the bottom row, where the focus engine found
    /// nowhere to go. The host's edge handler may move focus out; otherwise the cursor bumps. Up and down between
    /// rows stay native focus moves. A command right after focus arrived on the row is ignored: it is the move
    /// that brought focus there.
    func reachEdge(_ edge: VerticalEdge, at time: Double = now) {
        guard time - lastRowFocusChange >= Self.edgeFocusGuard else { return }
        perform(.move(edge == .top ? .previousShelf : .nextShelf), at: time)
    }

    /// tvOS mode 2: focus moved to another shelf row (or left the rows).
    func rowFocusChanged(at time: Double = now) {
        lastRowFocusChange = time
    }

    /// "Go" (R8): the Active ShelfCard, or the host's action for an empty Active Shelf (Q7).
    func activate() {
        switch model.activation {
        case .card(let card): handlers.onActivate(card)
        case .emptyShelf(let shelfID): handlers.onActivateEmptyShelf(shelfID)
        case nil: break
        }
    }

    /// Play/Pause on the Siri Remote (behavior §3.2): the host's handler first, which returns true when it used the
    /// press (dismissing a mini player, say); otherwise "go", as Select does.
    func playPause() {
        if let onPlayPause = handlers.onPlayPause, onPlayPause() { return }
        activate()
    }

    /// Forgets key-repeat history, for example when the Etagere loses focus.
    func resetRepeat() {
        repeatDetector.reset()
        scrubDetector.reset()
    }

    private func bump(_ move: EtagereMove) {
        guard !reduceMotion else { return }
        let towardNext = move.delta > 0
        if move.isHorizontal {
            viewState.cardBump.trigger(towardNext: towardNext, shelfID: model.activeShelf?.id)
        } else {
            viewState.shelfBump.trigger(towardNext: towardNext)
        }
    }

    // MARK: Pointer, touch and VoiceOver

    /// Makes the shelf copy at `shelfVirtualIndex` active (a tap on its row, VoiceOver focus).
    func selectShelf(virtualIndex: Int) {
        guard !model.isShelfActive(virtualIndex: virtualIndex) else { return }
        model.activateShelfCopy(
            virtualIndex: virtualIndex, animation: model.shelfChangeAnimation(reduceMotion: reduceMotion)
        )
    }

    /// The Shelves rotor: makes a shelf active the shortest way.
    func selectShelf(id: String) {
        model.activateShelf(id: id, animation: model.shelfChangeAnimation(reduceMotion: reduceMotion))
    }

    /// A tap or click on a rendered card (behavior §1.8). On an inactive shelf it makes that shelf active. On the
    /// Active Shelf, the anchored card plays and any other card rotates to the anchor the shortest way, or jumps
    /// when it is more than six slots away.
    func tapCard(on shelf: ShelfState<Card>, shelfVirtualIndex: Int, cardVirtualIndex: Int, at time: Double = now) {
        let wasActive = model.isShelfActive(virtualIndex: shelfVirtualIndex)
        selectShelf(virtualIndex: shelfVirtualIndex)
        guard let anchored = shelf.anchoredIndex else { return }
        let ringIndex = RingMath.floorMod(cardVirtualIndex, shelf.cards.count)
        guard ringIndex != anchored else {
            if wasActive { activateFromPointer(at: time) }
            return
        }
        let delta = RingMath.shortestDelta(from: anchored, to: ringIndex, itemCount: shelf.cards.count)
        if abs(delta) > Self.maximumAnimatedTapSlots {
            shelf.jump(toCard: shelf.cards[ringIndex].id)
        } else {
            model.rotate(shelf, by: delta, animation: reduceMotion ? nil : configuration.stepAnimation)
        }
    }

    /// A tap or click on an empty shelf's placeholder card (Q7).
    func tapPlaceholder(shelfVirtualIndex: Int, at time: Double = now) {
        let wasActive = model.isShelfActive(virtualIndex: shelfVirtualIndex)
        selectShelf(virtualIndex: shelfVirtualIndex)
        if wasActive { activateFromPointer(at: time) }
    }

    private func activateFromPointer(at time: Double) {
        guard time - lastPointerActivation >= Self.pointerActivationGuard else { return }
        lastPointerActivation = time
        activate()
    }

    /// Ends a drag or trackpad scrub on `shelf`: turns it by `delta` with the release animation while `alongside`
    /// returns the drag offset to zero in the same transaction.
    func releaseDrag(on shelf: ShelfState<Card>, delta: Int, alongside: () -> Void) {
        model.rotate(shelf, by: delta, animation: reduceMotion ? nil : Self.releaseAnimation, alongside: alongside)
    }

    /// Ends a vertical drag of the ShelvesRing (mode 1 on touch screens).
    func releaseShelvesDrag(delta: Int, alongside: () -> Void) {
        let animation = reduceMotion ? nil : Self.releaseAnimation
        withAnimation(animation, alongside)
        if delta != 0 {
            model.activateShelfCopy(virtualIndex: model.shelfRotation + delta, animation: animation)
        }
    }

    /// One notch of a mouse wheel over `shelf`: one card, retimed like key repeat when notches come quickly.
    func scrubStep(on shelf: ShelfState<Card>, step: Int, at time: Double = now) {
        guard step != 0 else { return }
        let move: EtagereMove = step > 0 ? .nextCard : .previousCard
        let sample = scrubDetector.register(move, at: time)
        let choice = EtagereAnimationChoice.choose(
            for: move, verticalMode: configuration.verticalMode, isRepeat: sample.isRepeat,
            repeatInterval: sample.interval, reduceMotion: reduceMotion
        )
        model.rotate(shelf, by: step, animation: configuration.animation(for: choice))
    }

    /// VoiceOver's increment and decrement on a shelf: the shelf becomes active and turns one card.
    func adjust(_ shelf: ShelfState<Card>, shelfVirtualIndex: Int, by delta: Int) {
        selectShelf(virtualIndex: shelfVirtualIndex)
        model.rotate(shelf, by: delta, animation: reduceMotion ? nil : configuration.stepAnimation)
    }

    /// VoiceOver's default action on a shelf: it becomes active and its anchored card (or placeholder) plays.
    func activate(shelfVirtualIndex: Int) {
        selectShelf(virtualIndex: shelfVirtualIndex)
        activate()
    }
}
