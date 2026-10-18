import CoreGraphics
@testable import EtagereKit
import SwiftUI
import Testing

@Suite("Input math: drags, flings, scrubs, controllers and repeat (behavior §1.8, §3.3)")
struct InputMathTests {
    // MARK: Drags and flings

    @Test("A drag toward the leading edge is a positive drag; right-to-left layouts mirror the physical axis")
    func dragSlots() {
        #expect(RingDragMath.slots(forTranslation: -300, step: 150, isRightToLeft: false) == 2)
        #expect(RingDragMath.slots(forTranslation: 75, step: 150, isRightToLeft: false) == -0.5)
        #expect(RingDragMath.slots(forTranslation: 300, step: 150, isRightToLeft: true) == 2)
        #expect(RingDragMath.slots(forTranslation: 100, step: 0, isRightToLeft: false) == 0)
        #expect(RingDragMath.slots(forTranslation: .infinity, step: 100, isRightToLeft: false) == 0)
    }

    @Test("A fling projects with UIScrollView's deceleration: v / 1000 * 0.998 / 0.002")
    func projectedSlots() {
        let projected = RingDragMath.projectedSlots(forVelocity: -1000, step: 499, isRightToLeft: false)
        #expect(abs(projected - 1) < 1e-9)
        #expect(RingDragMath.projectedSlots(forVelocity: 0, step: 100, isRightToLeft: false) == 0)
        #expect(RingDragMath.projectedSlots(forVelocity: .nan, step: 100, isRightToLeft: false) == 0)
        #expect(RingDragMath.projectedSlots(forVelocity: 1000, step: 499, isRightToLeft: true) > 0.99)
    }

    @Test("Release turns by round(drag + predicted), clamped to ±min(N, 30); rings under two cards never turn",
          arguments: [
            (0.4, 0.0, 8, 0), (0.6, 0.0, 8, 1), (-1.4, -0.2, 8, -2), (2.0, 40.0, 8, 8), (-5.0, -90.0, 100, -30),
            (3.0, 3.0, 1, 0), (3.0, 3.0, 0, 0), (0.5, 0.0, 4, 1), (-0.5, 0.0, 4, -1), (.nan, 0.0, 4, 0)
          ])
    func releaseDelta(drag: Double, predicted: Double, itemCount: Int, expected: Int) {
        #expect(RingDragMath.releaseDelta(dragSlots: drag, predictedSlots: predicted, itemCount: itemCount) == expected)
    }

    @Test("A live drag is clamped to the release limit")
    func liveSlots() {
        #expect(RingDragMath.liveSlots(12.5, itemCount: 8) == 8)
        #expect(RingDragMath.liveSlots(-0.75, itemCount: 8) == -0.75)
        #expect(RingDragMath.liveSlots(0.75, itemCount: 1) == 0)
        #expect(RingDragMath.liveSlots(-100, itemCount: 1000) == -30)
        #expect(RingDragMath.releaseLimit(itemCount: 3) == 3)
    }

    // MARK: Wheel and trackpad

    @Test("One card per wheel notch: horizontal wheels and Shift with a vertical wheel", arguments: [
        (CGFloat(-1), CGFloat(0), false, false, 1), (1, 0, false, false, -1), (-1, 0, false, true, -1),
        (1, 0, false, true, 1), (0, -1, true, false, 1), (0, 1, true, false, -1), (0, -1, false, false, 0),
        (0, 0, true, false, 0), (-3, 1, false, false, 1)
    ])
    func notchStep(deltaX: CGFloat, deltaY: CGFloat, shift: Bool, rightToLeft: Bool, expected: Int) {
        #expect(ScrollScrub.notchStep(
            deltaX: deltaX, deltaY: deltaY, isShiftDown: shift, isRightToLeft: rightToLeft
        ) == expected)
    }

    @Test("A horizontal trackpad gesture drags, then releases with its velocity; its momentum is swallowed")
    func trackpadScrub() {
        var tracker = ScrubTracker()
        #expect(tracker.handle(.init(phase: .began, time: 0), isRightToLeft: false) == .pass)
        let first = tracker.handle(.init(phase: .changed, deltaX: -30, deltaY: 4, time: 0.01), isRightToLeft: false)
        #expect(first == .init(action: .drag(translation: -30), consumes: true))
        let second = tracker.handle(.init(phase: .changed, deltaX: -20, deltaY: 9, time: 0.02), isRightToLeft: false)
        #expect(second == .init(action: .drag(translation: -50), consumes: true), "later events stay with the scrub")
        #expect(tracker.isTracking)
        let ended = tracker.handle(.init(phase: .ended, time: 0.03), isRightToLeft: false)
        guard case .release(let translation, let velocity)? = ended.action else {
            Issue.record("expected a release, got \(ended)")
            return
        }
        #expect(translation == -50)
        #expect(abs(velocity - -2500) < 1e-6, "50 pt over the 20 ms since the gesture began")
        #expect(!ended.consumes, "the page's scroll view still sees the gesture end")
        #expect(tracker.handle(.init(phase: .momentum(isLast: false), deltaX: -8, time: 0.05), isRightToLeft: false)
            == .init(action: nil, consumes: true))
        #expect(tracker.handle(.init(phase: .momentum(isLast: true), time: 0.3), isRightToLeft: false).consumes)
        #expect(tracker.handle(.init(phase: .momentum(isLast: false), time: 0.4), isRightToLeft: false) == .pass)
    }

    @Test("A vertical trackpad gesture belongs to the page from start to finish")
    func verticalGesturePasses() {
        var tracker = ScrubTracker()
        _ = tracker.handle(.init(phase: .began, time: 0), isRightToLeft: false)
        #expect(tracker.handle(.init(phase: .changed, deltaX: 2, deltaY: -12, time: 0.01), isRightToLeft: false)
            == .pass)
        #expect(tracker.handle(.init(phase: .changed, deltaX: -40, deltaY: 0, time: 0.02), isRightToLeft: false)
            == .pass, "the gesture's direction is decided once")
        #expect(tracker.handle(.init(phase: .ended, time: 0.03), isRightToLeft: false) == .pass)
        #expect(tracker.handle(.init(phase: .momentum(isLast: false), time: 0.04), isRightToLeft: false) == .pass)
        #expect(!tracker.isTracking)
    }

    @Test("A cancelled scrub releases without a fling; a mouse wheel steps")
    func cancelledAndWheel() {
        var tracker = ScrubTracker()
        _ = tracker.handle(.init(phase: .began, time: 0), isRightToLeft: true)
        _ = tracker.handle(.init(phase: .changed, deltaX: 90, time: 0.01), isRightToLeft: true)
        let cancelled = tracker.handle(.init(phase: .cancelled, time: 0.02), isRightToLeft: true)
        #expect(cancelled.action == .release(translation: 90, velocity: 0))
        let wheel = tracker.handle(.init(phase: .wheel, deltaY: -1, isShiftDown: true), isRightToLeft: true)
        #expect(wheel == .init(action: .step(1), consumes: true))
        #expect(tracker.handle(.init(phase: .wheel, deltaY: -1), isRightToLeft: true) == .pass)
    }

    @Test("Velocity over samples of (time, delta)")
    func velocity() {
        #expect(ScrollScrub.velocity(samples: []) == 0)
        #expect(ScrollScrub.velocity(samples: [(0, 5)]) == 0)
        #expect(ScrollScrub.velocity(samples: [(0, 0), (0.1, 10), (0.2, 10)]) == 100)
    }

    // MARK: Controllers and repeat

    @Test("A stick or d-pad presses the dominant axis past half way", arguments: [
        (Float(0.6), Float(0.1), EtagereKey?.some(.rightArrow)), (-0.9, 0.5, .leftArrow), (0.2, 0.7, .upArrow),
        (0.3, -0.51, .downArrow), (0.49, 0.2, nil), (0, 0, nil), (0.5, -0.5, .rightArrow)
    ])
    func stickKey(xValue: Float, yValue: Float, expected: EtagereKey?) {
        #expect(ControllerStick.key(xValue: xValue, yValue: yValue) == expected)
    }

    @Test("A held direction repeats after 400 ms, then every 110 ms")
    func controllerRepeatTiming() {
        #expect(ControllerStick.delay(beforeRepeat: 0) == 0.4)
        #expect(ControllerStick.delay(beforeRepeat: 1) == 0.11)
        #expect(ControllerStick.delay(beforeRepeat: 7) == 0.11)
    }

    @Test("A reported key phase wins over the detector; without one (the Siri Remote) the detector decides")
    func repeatResolution() {
        let quick = RepeatSample(isRepeat: true, interval: 0.09)
        let slow = RepeatSample(isRepeat: false, interval: 0.5)
        let first = RepeatSample(isRepeat: false, interval: nil)
        let held = RepeatSample(isRepeat: true, interval: 0.5)
        #expect(EtagereRepeat.resolve(reportedRepeat: true, sample: slow) == held)
        #expect(EtagereRepeat.resolve(reportedRepeat: false, sample: quick) == first)
        #expect(EtagereRepeat.resolve(reportedRepeat: nil, sample: quick) == quick)
        #expect(EtagereRepeat.resolve(reportedRepeat: nil, sample: slow) == first)
    }

    @Test("Key repeat retimes the repeat animation to the measured interval through the controller")
    @MainActor
    func repeatRetiming() {
        let model = Fixture.model(cardCounts: [8])
        let held = HeldAnimations(model)
        let controller = EtagereController(model: model)
        // Binary-exact times, so the measured intervals are exactly 0.125, 0.0625 and 0.0078125 s.
        controller.perform(key: .rightArrow, isRightToLeft: false, reportedRepeat: false, at: 0)
        controller.perform(key: .rightArrow, isRightToLeft: false, reportedRepeat: true, at: 0.125)
        controller.perform(key: .rightArrow, isRightToLeft: false, reportedRepeat: true, at: 0.1875)
        controller.perform(key: .rightArrow, isRightToLeft: false, reportedRepeat: true, at: 0.1953125)
        let configuration = model.configuration
        let reference = RepeatDetector.referenceInterval
        #expect(held.animations == [
            configuration.stepAnimation, configuration.repeatAnimation.speed(reference / 0.125),
            configuration.repeatAnimation.speed(reference / 0.0625),
            configuration.repeatAnimation.speed(reference / RepeatDetector.animationIntervalRange.lowerBound)
        ])
        #expect(model.activeCard?.id == "s0-E")
    }
}
