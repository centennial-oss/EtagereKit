import EtagereKit
import SwiftUI
import Testing

@Suite("Animation choice and Reduce Motion (behavior §1.8, §4)")
struct AnimationChoiceTests {
    @Test("T19 with Reduce Motion the chosen animation is nil",
          arguments: EtagereMove.allCases, EtagereVerticalMode.allCases)
    func reduceMotionChoosesNoAnimation(move: EtagereMove, mode: EtagereVerticalMode) {
        for isRepeat in [false, true] {
            let choice = EtagereAnimationChoice.choose(
                for: move, verticalMode: mode, isRepeat: isRepeat, repeatInterval: 0.09, reduceMotion: true
            )
            #expect(choice == .immediate)
            #expect(EtagereConfiguration(verticalMode: mode).animation(for: choice) == nil)
        }
    }

    @Test("T19 without Reduce Motion: a step per axis and mode, repeats retimed",
          arguments: EtagereMove.allCases, EtagereVerticalMode.allCases)
    func animatedChoices(move: EtagereMove, mode: EtagereVerticalMode) {
        func choose(isRepeat: Bool, interval: Double? = nil) -> EtagereAnimationChoice {
            EtagereAnimationChoice.choose(
                for: move, verticalMode: mode, isRepeat: isRepeat, repeatInterval: interval, reduceMotion: false
            )
        }
        let verticalStep: EtagereAnimationChoice = mode == .ring ? .shelfStep : .highlightStep
        #expect(choose(isRepeat: false) == (move.isHorizontal ? .cardStep : verticalStep))
        #expect(choose(isRepeat: false, interval: 0.09) == choose(isRepeat: false), "only repeats are retimed")
        #expect(choose(isRepeat: true) == .repeating(interval: nil))
        #expect(choose(isRepeat: true, interval: 0.09) == .repeating(interval: 0.09))
        #expect(choose(isRepeat: true, interval: 0.01) == .repeating(interval: 0.06))
        #expect(choose(isRepeat: true, interval: 0.5) == .repeating(interval: 0.2))
    }

    @Test("T19 a shelf step turns the ring in mode 1 and slides the highlight in mode 2 (behavior §2.2, R25)")
    func shelfStepPerMode() {
        var configuration = EtagereConfiguration(verticalMode: .cursor)
        configuration.shelfStepAnimation = .easeIn(duration: 0.5)
        configuration.highlightAnimation = .linear(duration: 1)
        let cursorStep = EtagereAnimationChoice.choose(
            for: .nextShelf, verticalMode: configuration.verticalMode, isRepeat: false, reduceMotion: false
        )
        #expect(configuration.animation(for: cursorStep) == .linear(duration: 1))
        configuration.verticalMode = .ring
        let ringStep = EtagereAnimationChoice.choose(
            for: .previousShelf, verticalMode: configuration.verticalMode, isRepeat: false, reduceMotion: false
        )
        #expect(configuration.animation(for: ringStep) == .easeIn(duration: 0.5))
    }

    @Test("T19 the configuration resolves each choice to its animation")
    func resolvedAnimations() {
        let configuration = EtagereConfiguration()
        #expect(configuration.animation(for: .cardStep) == configuration.stepAnimation)
        #expect(configuration.animation(for: .shelfStep) == configuration.shelfStepAnimation)
        #expect(configuration.animation(for: .highlightStep) == configuration.highlightAnimation)
        #expect(configuration.animation(for: .repeating(interval: nil)) == configuration.repeatAnimation)
        #expect(configuration.animation(for: .repeating(interval: RepeatDetector.referenceInterval))
            == configuration.repeatAnimation.speed(1))
        #expect(configuration.animation(for: .repeating(interval: 0.06)) == configuration.repeatAnimation.speed(2))
    }

    @Test("T19 a repeat interval is clamped to 60-200 ms even when passed straight to the configuration",
          arguments: [
            (0.0, 0.06), (-0.1, 0.06), (0.01, 0.06), (0.09, 0.09), (0.5, 0.2), (Double.infinity, 0.2),
            (-Double.infinity, 0.06), (Double.nan, RepeatDetector.referenceInterval)
          ])
    func repeatIntervalIsClamped(measured: Double, clamped: Double) {
        let configuration = EtagereConfiguration()
        let speed = RepeatDetector.referenceInterval / clamped
        #expect(speed.isFinite && speed > 0)
        let retimed = configuration.animation(for: .repeating(interval: measured))
        #expect(retimed == configuration.repeatAnimation.speed(speed))
    }

    @Test("T19 the model ends in the same state with and without Reduce Motion",
          arguments: EtagereVerticalMode.allCases)
    func reduceMotionMatchesAnimatedPath(mode: EtagereVerticalMode) {
        let configuration = EtagereConfiguration(verticalMode: mode)
        let animated = Fixture.model(cardCounts: [3, 1, 8, 0, 40], configuration: configuration)
        let reduced = Fixture.model(cardCounts: [3, 1, 8, 0, 40], configuration: configuration)
        let moves: [(EtagereMove, Bool)] = [
            (.nextCard, false), (.nextCard, true), (.nextCard, true), (.nextShelf, false), (.previousCard, false),
            (.nextShelf, false), (.nextCard, true), (.nextShelf, true), (.previousShelf, false),
            (.previousShelf, false), (.previousShelf, false), (.previousShelf, true), (.previousCard, false)
        ]
        for (move, isRepeat) in moves {
            let animatedResult = animated.move(move, isRepeat: isRepeat, repeatInterval: 0.08, reduceMotion: false)
            let reducedResult = reduced.move(move, isRepeat: isRepeat, repeatInterval: 0.08, reduceMotion: true)
            #expect(animatedResult == reducedResult)
            #expect(animated.shelfRotation == reduced.shelfRotation)
            #expect(animated.shelves.map(\.rotation) == reduced.shelves.map(\.rotation))
            #expect(animated.activeCard == reduced.activeCard)
            #expect(animated.position == reduced.position)
            // Reduce Motion never leaves anything in flight.
            #expect(reduced.shelves.allSatisfy { $0.isSettled })
            #expect(reduced.settledShelfRotation == reduced.shelfRotation)
        }
    }
}
