/// One registered move, as `RepeatDetector` sees it.
public nonisolated struct RepeatSample: Sendable, Hashable {
    /// True when the move repeats the previous one: the same direction, less than the threshold after it.
    public var isRepeat: Bool
    /// Seconds since the previous move in the same direction, or nil when the direction changed, this is the first
    /// move, or time went backwards.
    public var interval: Double?

    public init(isRepeat: Bool, interval: Double?) {
        self.isRepeat = isRepeat
        self.interval = interval
    }
}

/// Detects key and button repeat from move timestamps and measures the repeat rate (behavior §1.8). Pure: the host
/// passes monotonic times in seconds (for example a key event's timestamp or `ProcessInfo.systemUptime`).
///
/// tvOS reports no repeat phase, so move commands in the same direction less than 180 ms apart count as repeats.
/// macOS and iPad keyboards report the phase themselves; there the detector only measures the interval that
/// retimes `repeatAnimation`.
public nonisolated struct RepeatDetector: Sendable, Hashable {
    /// Moves in the same direction closer together than this are repeats (tvOS).
    public static let defaultThreshold = 0.18
    /// The range a measured repeat interval is clamped to before it retimes the repeat animation.
    public static let animationIntervalRange: ClosedRange<Double> = 0.06...0.2
    /// The repeat interval `EtagereConfiguration.repeatAnimation` is designed for. A measured interval changes the
    /// animation's speed by `referenceInterval / interval`, so the default 120 ms linear step lasts exactly one
    /// repeat interval.
    public static let referenceInterval = 0.12

    public var threshold: Double
    private var lastMove: EtagereMove?
    private var lastTime: Double?

    public init(threshold: Double = RepeatDetector.defaultThreshold) {
        self.threshold = threshold
    }

    /// Registers a move at `time` and reports whether it repeats the previous move.
    public mutating func register(_ move: EtagereMove, at time: Double) -> RepeatSample {
        defer {
            lastMove = move
            lastTime = time
        }
        guard move == lastMove, let lastTime, time >= lastTime else {
            return RepeatSample(isRepeat: false, interval: nil)
        }
        let interval = time - lastTime
        return RepeatSample(isRepeat: interval < threshold, interval: interval)
    }

    /// Forgets the previous move, for example when the Etagere loses focus.
    public mutating func reset() {
        lastMove = nil
        lastTime = nil
    }

    /// A measured repeat interval clamped to `animationIntervalRange` (60-200 ms). Not a number gives the reference.
    public static func animationInterval(forMeasured interval: Double) -> Double {
        guard !interval.isNaN else { return referenceInterval }
        return min(max(interval, animationIntervalRange.lowerBound), animationIntervalRange.upperBound)
    }
}
