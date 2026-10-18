import CoreGraphics

/// Drag and fling math shared by touch drags (iOS) and trackpad scrubs (macOS), behavior §1.8. Pure, so it is unit
/// tested. Translations are physical (UIKit and AppKit report them left to right whatever the layout direction);
/// right-to-left layouts mirror them here, as they mirror the arrow keys in `EtagereKeyMap`.
nonisolated enum RingDragMath {
    /// The most slots one release may turn a long ring.
    static let maximumReleaseSlots = 30
    /// UIScrollView's normal deceleration rate, per millisecond, used to project a fling.
    static let decelerationRate = 0.998

    /// Slots of drag for a translation along the ring's axis. Moving the content toward the leading (or top) edge
    /// brings the next item in, so it is a positive drag.
    static func slots(forTranslation translation: CGFloat, step: CGFloat, isRightToLeft: Bool) -> Double {
        guard step > 0, translation.isFinite else { return 0 }
        let towardLeading = isRightToLeft ? translation : -translation
        return Double(towardLeading / step)
    }

    /// Slots a fling travels after release, projected from the release velocity in points per second with
    /// UIScrollView's deceleration (`distance = v / 1000 * r / (1 - r)`).
    static func projectedSlots(forVelocity velocity: CGFloat, step: CGFloat, isRightToLeft: Bool) -> Double {
        guard velocity.isFinite else { return 0 }
        let distance = velocity / 1000 * decelerationRate / (1 - decelerationRate)
        return slots(forTranslation: distance, step: step, isRightToLeft: isRightToLeft)
    }

    /// The largest rotation one drag or release may make: `min(N, 30)`, or 0 when the ring cannot turn.
    static func releaseLimit(itemCount: Int) -> Int {
        itemCount > 1 ? min(itemCount, maximumReleaseSlots) : 0
    }

    /// The drag shown while the finger is down, clamped to the release limit so the ring never runs further than
    /// a release could take it.
    static func liveSlots(_ slots: Double, itemCount: Int) -> Double {
        let limit = Double(releaseLimit(itemCount: itemCount))
        guard slots.isFinite else { return 0 }
        return min(max(slots, -limit), limit)
    }

    /// The rotation on release: `round(dragSlots + predictedSlots)`, clamped to `±min(N, 30)`.
    static func releaseDelta(dragSlots: Double, predictedSlots: Double, itemCount: Int) -> Int {
        let limit = releaseLimit(itemCount: itemCount)
        let total = dragSlots + predictedSlots
        guard limit > 0, total.isFinite else { return 0 }
        return min(max(Int(total.rounded()), -limit), limit)
    }
}

/// Mouse-wheel and trackpad scrolling over a shelf (macOS, behavior §3.3). Pure.
nonisolated enum ScrollScrub {
    /// Card steps for one notch of a wheel without precise deltas: one card per notch, from a horizontal wheel, or
    /// from a vertical wheel while Shift is held. Content moving toward the leading edge (or up) is "next" (+1);
    /// horizontal deltas are physical, so right-to-left layouts mirror them. 0 when the notch is not for the ring.
    static func notchStep(deltaX: CGFloat, deltaY: CGFloat, isShiftDown: Bool, isRightToLeft: Bool) -> Int {
        if deltaX != 0, abs(deltaX) >= abs(deltaY) {
            let towardLeading = isRightToLeft ? deltaX > 0 : deltaX < 0
            return towardLeading ? 1 : -1
        }
        if isShiftDown, deltaY != 0 {
            return deltaY < 0 ? 1 : -1
        }
        return 0
    }

    /// True when a trackpad gesture's first movement is mostly horizontal, so the shelf takes it as a scrub and
    /// leaves vertical scrolling to the page.
    static func isHorizontal(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        deltaX != 0 && abs(deltaX) > abs(deltaY)
    }

    /// Velocity in points per second over recent samples of (time, delta); 0 without enough time between them.
    static func velocity(samples: [(time: Double, delta: CGFloat)]) -> CGFloat {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        let distance = samples.dropFirst().reduce(0) { $0 + $1.delta }
        return distance / CGFloat(last.time - first.time)
    }
}

/// Game-controller direction and repeat timing (behavior §3.3). Pure.
nonisolated enum ControllerStick {
    /// How far a stick or d-pad must move before it counts as a press.
    static let threshold: Float = 0.5
    static let initialRepeatDelay = 0.4
    static let repeatInterval = 0.11

    /// The arrow a d-pad or stick position presses: the dominant axis past the threshold, nil inside the dead
    /// zone. GameController reports y positive upward.
    static func key(xValue: Float, yValue: Float, threshold: Float = ControllerStick.threshold) -> EtagereKey? {
        let horizontal = abs(xValue)
        let vertical = abs(yValue)
        guard max(horizontal, vertical) >= threshold else { return nil }
        if horizontal >= vertical {
            return xValue > 0 ? .rightArrow : .leftArrow
        }
        return yValue > 0 ? .upArrow : .downArrow
    }

    /// The wait before the `index`th repeat of a held direction: 400 ms before the first, 110 ms after that.
    static func delay(beforeRepeat index: Int) -> Double {
        index == 0 ? initialRepeatDelay : repeatInterval
    }
}

/// Combines a platform's own repeat report with `RepeatDetector` (behavior §1.8). Pure.
nonisolated enum EtagereRepeat {
    /// `reportedRepeat` is the key phase on macOS and iPad keyboards, or nil where the platform reports none (the
    /// Siri Remote). A reported phase wins; the detector then only supplies the interval that retimes the repeat
    /// animation. Without a report, the detector decides. A first press never carries an interval.
    static func resolve(reportedRepeat: Bool?, sample: RepeatSample) -> RepeatSample {
        let isRepeat = reportedRepeat ?? sample.isRepeat
        return RepeatSample(isRepeat: isRepeat, interval: isRepeat ? sample.interval : nil)
    }
}

/// Follows one trackpad or wheel gesture over a shelf (macOS, behavior §3.3) and says what to do with each scroll
/// event. Pure, so the gesture logic is unit tested without AppKit. Only the movement of a gesture that starts out
/// mostly horizontal is consumed; its `began` and `ended` events pass through, so the page's scroll view always
/// sees whole gestures, and any vertical gesture belongs to the page.
nonisolated struct ScrubTracker {
    enum Phase: Sendable {
        /// A notched wheel, without precise deltas.
        case wheel
        case began, changed, ended, cancelled
        /// Momentum after the fingers lift; `isLast` on its final event.
        case momentum(isLast: Bool)
    }

    enum Action: Equatable, Sendable {
        /// One card per wheel notch.
        case step(Int)
        /// The content's translation so far, in points.
        case drag(translation: CGFloat)
        /// The gesture ended: its translation and release velocity in points per second.
        case release(translation: CGFloat, velocity: CGFloat)
    }

    /// One scroll event.
    struct Event: Sendable {
        var phase: Phase
        var deltaX: CGFloat = 0
        var deltaY: CGFloat = 0
        /// Seconds, monotonic.
        var time: Double = 0
        var isShiftDown = false
    }

    struct Output: Equatable, Sendable {
        var action: Action?
        /// True when the event is used up here and must not reach the page.
        var consumes: Bool

        static let pass = Output(action: nil, consumes: false)
    }

    private enum State {
        case idle, pending, tracking, ignoring, coasting
    }

    /// How much recent movement measures the release velocity.
    static let velocityWindow = 0.1

    private var state = State.idle
    private var translation: CGFloat = 0
    private var samples: [(time: Double, delta: CGFloat)] = []

    var isTracking: Bool { state == .tracking }

    mutating func handle(_ event: Event, isRightToLeft: Bool) -> Output {
        switch event.phase {
        case .wheel:
            let step = ScrollScrub.notchStep(
                deltaX: event.deltaX, deltaY: event.deltaY, isShiftDown: event.isShiftDown,
                isRightToLeft: isRightToLeft
            )
            return step == 0 ? .pass : Output(action: .step(step), consumes: true)
        case .began:
            state = .pending
            translation = 0
            samples = [(event.time, 0)]
            return .pass
        case .changed:
            return changed(deltaX: event.deltaX, deltaY: event.deltaY, time: event.time)
        case .ended, .cancelled:
            guard state == .tracking else {
                state = .idle
                return .pass
            }
            state = .coasting
            let isCancelled = if case .cancelled = event.phase { true } else { false }
            let velocity = isCancelled ? 0 : ScrollScrub.velocity(samples: samples)
            return Output(action: .release(translation: translation, velocity: velocity), consumes: false)
        case .momentum(let isLast):
            guard state == .coasting else { return .pass }
            if isLast { state = .idle }
            return Output(action: nil, consumes: true)
        }
    }

    private mutating func changed(deltaX: CGFloat, deltaY: CGFloat, time: Double) -> Output {
        switch state {
        case .idle, .pending, .coasting:
            guard deltaX != 0 || deltaY != 0 else { return .pass }
            guard ScrollScrub.isHorizontal(deltaX: deltaX, deltaY: deltaY) else {
                state = .ignoring
                return .pass
            }
            if state != .pending {
                translation = 0
                samples = [(time, 0)]
            }
            state = .tracking
            return track(deltaX: deltaX, time: time)
        case .tracking:
            return track(deltaX: deltaX, time: time)
        case .ignoring:
            return .pass
        }
    }

    private mutating func track(deltaX: CGFloat, time: Double) -> Output {
        translation += deltaX
        samples.append((time, deltaX))
        samples.removeAll { time - $0.time > Self.velocityWindow }
        return Output(action: .drag(translation: translation), consumes: true)
    }
}
