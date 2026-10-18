import SwiftUI

/// Model operations that only the view layer needs: pointer, drag, scrub and VoiceOver input, which turn any shelf
/// and move to a particular rendered copy rather than by one step (behavior §1.8, §4).
extension EtagereModel {
    /// True when `move` would change the selection now. The model consumes some moves without moving (one card,
    /// one shelf, an empty shelf in mode 1, R27); the view gives those a small bump instead.
    func wouldMove(_ move: EtagereMove) -> Bool {
        if move.isHorizontal {
            return (activeShelf?.cards.count ?? 0) > 1
        }
        switch configuration.verticalMode {
        case .ring:
            return shelves.count > 1
        case .cursor:
            let target = shelfRotation + move.delta
            return target >= 0 && target < shelves.count
        }
    }

    /// Turns `shelf` by `delta` slots under `animation` (nil: at once) and settles it when the animation is removed.
    /// Any shelf may turn, active or not (a drag or a scrub on the shelf under the pointer). `alongside` runs in the
    /// same transaction, so a drag offset returns to zero exactly as the rotation takes over.
    func rotate(
        _ shelf: ShelfState<Card>, by delta: Int, animation: Animation?, alongside: () -> Void = {}
    ) {
        perform(animation) {
            alongside()
            return shelf.rotate(by: delta)
        } settle: { token in
            shelf.settle(token)
        }
    }

    /// Makes the shelf copy at `virtualIndex` the Active Shelf. In mode 1 the ShelvesRing turns to that copy, so the
    /// copy the user tapped (or VoiceOver focused) is the one that slides to the anchor and keeps its identity; in
    /// mode 2 the cursor moves to that row.
    func activateShelfCopy(virtualIndex: Int, animation: Animation?) {
        guard !shelves.isEmpty, virtualIndex != shelfRotation else { return }
        if configuration.verticalMode == .cursor, !(0..<shelves.count).contains(virtualIndex) { return }
        animateShelfRotation(to: virtualIndex, animation: animation)
    }

    /// The animation for a shelf change made by pointer, VoiceOver or a host: `shelfStepAnimation` in mode 1,
    /// `highlightAnimation` in mode 2, nil under Reduce Motion.
    func shelfChangeAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return configuration.verticalMode == .ring
            ? configuration.shelfStepAnimation : configuration.highlightAnimation
    }
}
