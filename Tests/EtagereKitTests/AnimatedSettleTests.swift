@testable import EtagereKit
import SwiftUI
import Testing

/// Stands in for SwiftUI's animation runner. It applies each change at once, as `withAnimation` does, and holds the
/// completion until the test says that animation was removed. Outside a view hierarchy SwiftUI calls completions at
/// once, so without this every animated move would settle before a test could look at the cards in flight.
final class HeldAnimations {
    private(set) var animations: [Animation] = []
    private var completions: [(() -> Void)?] = []

    init<Card>(_ model: EtagereModel<Card>) {
        model.animationRunner = { [self] animation, change, completion in
            animations.append(animation)
            change()
            completions.append(completion)
        }
    }

    /// Ends the animation of the `index`th animated change (0-based). Each completion runs at most once.
    func finish(_ index: Int) {
        let completion = completions[index]
        completions[index] = nil
        completion?()
    }

    func finishAll() {
        completions.indices.forEach(finish)
    }
}

@Suite("Animated moves settle only once their animation is removed (behavior §1.5, §1.8, D3)")
struct AnimatedSettleTests {
    private static let cursorAnimation: Animation = .linear(duration: 1)
    private static let ringAnimation: Animation = .easeIn(duration: 0.5)

    @Test("T13 card moves keep every card in flight rendered until its animation ends, in any order",
          arguments: [[0, 1, 2], [2, 1, 0], [1, 2, 0]])
    func cardMovesDeferSettling(finishOrder: [Int]) {
        let model = Fixture.model(cardCounts: [8])
        let held = HeldAnimations(model)
        let shelf = model.shelves[0]
        for _ in 0..<3 { model.move(.nextCard, isRepeat: false, reduceMotion: false) }
        #expect(shelf.rotation == 3)
        #expect(model.activeCard?.id == "s0-D", "input is never locked: the arriving card is the selection")
        #expect(shelf.settledRotation == 0)
        #expect(shelf.renderSlots(rest: 0...2).map(\.virtualIndex) == Array(-1...6), "T8: the whole flight")
        #expect(held.animations == Array(repeating: model.configuration.stepAnimation, count: 3))
        var ended = Set<Int>()
        for index in finishOrder {
            held.finish(index)
            ended.insert(index)
            // Animation i moves from rotation i to i + 1. The window keeps everything since the oldest one still
            // running, and the latest one ending settles the ring.
            let oldestRunning = ended.contains(2) ? 3 : (0..<3).first { !ended.contains($0) } ?? 3
            #expect(shelf.settledRotation == oldestRunning, "after animation \(index) ended")
            #expect(shelf.rotationsInFlight == oldestRunning...3)
        }
        #expect(shelf.renderSlots(rest: 0...2).map(\.virtualIndex) == Array(2...6))
    }

    @Test("Shelf moves defer settling and use shelfStepAnimation in mode 1, highlightAnimation in mode 2",
          arguments: EtagereVerticalMode.allCases)
    func shelfMovesDeferSettling(mode: EtagereVerticalMode) {
        var configuration = EtagereConfiguration(verticalMode: mode)
        configuration.shelfStepAnimation = Self.ringAnimation
        configuration.highlightAnimation = Self.cursorAnimation
        let model = Fixture.model(cardCounts: [2, 2, 2, 2], configuration: configuration)
        let held = HeldAnimations(model)
        model.move(.nextShelf, isRepeat: false, reduceMotion: false)
        model.move(.nextShelf, isRepeat: false, reduceMotion: false)
        #expect(model.shelfRotation == 2)
        #expect(model.activeShelf?.id == "s2")
        #expect(model.settledShelfRotation == 0)
        if mode == .ring {
            #expect(model.shelfRenderSlots(rest: 0...1).map(\.virtualIndex) == Array(-1...4))
        }
        held.finish(0)
        #expect(model.settledShelfRotation == 1, "the first step is over; the second one stays rendered")
        #expect(model.shelfRotationsInFlight == 1...2)
        held.finish(1)
        #expect(model.settledShelfRotation == 2)

        let step = mode == .ring ? Self.ringAnimation : Self.cursorAnimation
        #expect(model.activateShelf(id: "s0", animation: step))
        #expect(model.settledShelfRotation == 2, "activateShelf animates too")
        held.finish(2)
        #expect(model.settledShelfRotation == model.shelfRotation)
        #expect(held.animations == [step, step, step])
    }

    @Test("Key repeat retimes repeatAnimation to the clamped measured interval")
    func repeatsAreRetimed() {
        let model = Fixture.model(cardCounts: [8, 8], configuration: EtagereConfiguration(verticalMode: .cursor))
        let held = HeldAnimations(model)
        model.move(.nextCard, isRepeat: true, repeatInterval: 0.08, reduceMotion: false)
        model.move(.nextCard, isRepeat: true, repeatInterval: 0.01, reduceMotion: false)
        model.move(.nextShelf, isRepeat: true, repeatInterval: 0.5, reduceMotion: false)
        model.move(.previousShelf, isRepeat: true, reduceMotion: false)
        let repeatAnimation = model.configuration.repeatAnimation
        #expect(held.animations == [
            repeatAnimation.speed(RepeatDetector.referenceInterval / 0.08), repeatAnimation.speed(2),
            repeatAnimation.speed(RepeatDetector.referenceInterval / 0.2), repeatAnimation
        ])
    }

    @Test("T19 Reduce Motion never animates, settles at once, and a stale animation never settles a newer one",
          arguments: EtagereVerticalMode.allCases)
    func reduceMotionBetweenAnimatedMoves(mode: EtagereVerticalMode) {
        let model = Fixture.model(cardCounts: [8, 8, 8, 8], configuration: EtagereConfiguration(verticalMode: mode))
        let held = HeldAnimations(model)
        model.move(.nextCard, isRepeat: false, reduceMotion: false)
        model.move(.nextShelf, isRepeat: false, reduceMotion: false)
        model.move(.previousShelf, isRepeat: false, reduceMotion: true)
        model.move(.nextCard, isRepeat: false, reduceMotion: true)
        let shelf = model.shelves[0]
        #expect(shelf.rotation == 2)
        #expect(shelf.isSettled)
        #expect(model.settledShelfRotation == model.shelfRotation)

        model.move(.nextCard, isRepeat: false, reduceMotion: false)
        model.move(.nextShelf, isRepeat: false, reduceMotion: false)
        held.finish(0)
        held.finish(1)
        #expect(shelf.settledRotation == 2, "a stale animation leaves the newer flight rendered")
        #expect(model.settledShelfRotation == 0)
        held.finish(2)
        held.finish(3)
        #expect(shelf.settledRotation == 3)
        #expect(model.settledShelfRotation == 1)
        #expect(held.animations.count == 4, "the Reduce Motion moves never reached the runner")
    }

    @Test("A reload during a move settles at once, crossfades, and outlasts the old animations (behavior §1.8)")
    func reloadDuringMoves() {
        let model = Fixture.model(cardCounts: [4, 4])
        let held = HeldAnimations(model)
        let first = model.shelves[0]
        model.move(.nextCard, isRepeat: false, reduceMotion: false)
        model.move(.nextShelf, isRepeat: false, reduceMotion: false)
        #expect(!first.isSettled)
        #expect(model.settledShelfRotation == 0)

        model.replaceShelves([
            Fixture.shelf("s1", cardCount: 4),
            Shelf(id: "s0", title: "S0", cards: ["s0-D", "s0-C", "s0-B", "s0-A"].map { PlainCard($0) })
        ])
        #expect(model.shelves[1] === first)
        #expect(model.activeShelf?.id == "s1")
        #expect(model.shelfRotation == 0)
        #expect(model.settledShelfRotation == 0)
        #expect(model.shelfJumpGeneration == 1)
        #expect(first.anchoredCard?.id == "s0-B")
        #expect(first.rotation == 2)
        #expect(first.isSettled)
        #expect(first.jumpGeneration == 1)

        held.finishAll()
        #expect(first.rotation == 2 && first.settledRotation == 2)
        #expect(model.shelfRotation == 0 && model.settledShelfRotation == 0)
    }
}
