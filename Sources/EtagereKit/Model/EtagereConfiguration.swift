import SwiftUI

/// Where each shelf's Anchor Spot sits (R6, R16). Leading by default; never justified. Right-to-left layouts mirror
/// leading and trailing (D2).
public nonisolated enum EtagereHorizontalAlignment: String, Sendable, Hashable, CaseIterable, Codable {
    case leading, center, trailing

    public var ringAnchor: RingAnchor {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// Where the Active Shelf sits vertically (R23): the anchor of the ShelvesRing in mode 1, and the scroll anchor that
/// keeps the active shelf in view in mode 2.
public nonisolated enum EtagereVerticalAlignment: String, Sendable, Hashable, CaseIterable, Codable {
    case top, center, bottom

    public var ringAnchor: RingAnchor {
        switch self {
        case .top: .leading
        case .center: .center
        case .bottom: .trailing
        }
    }
}

/// How up and down move between shelves (R21).
public nonisolated enum EtagereVerticalMode: String, Sendable, Hashable, CaseIterable, Codable {
    /// Mode 1 (the default): the shelves rotate through a vertical ring, the ShelvesRing, and the Etagere consumes
    /// every direction (R22, R27).
    case ring
    /// Mode 2: the shelves stay put (scrolling when they overflow) and a cursor moves between them; it stops at the
    /// top and bottom so focus can leave for controls above or below (R24, R26, R28, Q2).
    case cursor
}

/// How cards sit on a shelf's cross axis inside the height reserved for the enlarged card.
public nonisolated enum ShelfCardCrossAlignment: String, Sendable, Hashable, CaseIterable, Codable {
    case top
    /// The default: cards grow from their middle.
    case center
    /// Cards stand on a common baseline, as box art does.
    case bottom
}

/// Everything about the Etagere's look and motion that a host may set (etagere.md §4.3).
public nonisolated struct EtagereConfiguration: Sendable, Equatable {
    /// R6, R16.
    public var horizontalAlignment: EtagereHorizontalAlignment
    /// R23.
    public var verticalAlignment: EtagereVerticalAlignment
    /// R21.
    public var verticalMode: EtagereVerticalMode
    /// Card sizes and spacing, resolved from the container width (behavior §6, D7).
    public var metrics: EtagereMetrics = .automatic
    public var cardCrossAlignment: ShelfCardCrossAlignment = .center
    /// Brightness drop for the cards on the Active Shelf other than the Active ShelfCard.
    public var idleDim = 0.12
    /// Extra brightness drop for every card on the other shelves.
    public var inactiveShelfDim = 0.15
    /// The bar between each ring's last and first card (R20).
    public var showsSeam = true
    /// The bar between the last and the first shelf in mode 1 (Q4: on by default).
    public var showsShelfSeam = true
    /// One card step.
    public var stepAnimation: Animation = .snappy(duration: 0.28)
    /// Key repeat (behavior §1.8): a linear step lasting `RepeatDetector.referenceInterval` (120 ms). A measured
    /// repeat interval, clamped to 60-200 ms, retimes it with `speed(referenceInterval / interval)`, so each step
    /// lasts one repeat and the ring keeps pace with the keys. The speed scales whatever duration this animation
    /// has, so a replacement must also last 120 ms; only its curve may differ.
    public var repeatAnimation: Animation = .linear(duration: 0.12)
    /// One shelf step in mode 1: the ShelvesRing turns.
    public var shelfStepAnimation: Animation = .snappy(duration: 0.32)
    /// One shelf step in mode 2: the Active Shelf highlight slides to the next row (R25).
    public var highlightAnimation: Animation = .snappy(duration: 0.3)
    private var storedFadeLength = 1.0

    public init(
        horizontalAlignment: EtagereHorizontalAlignment = .leading,
        verticalAlignment: EtagereVerticalAlignment = .top,
        verticalMode: EtagereVerticalMode = .ring
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.verticalMode = verticalMode
    }

    /// Slots of travel past a ring's rest edge over which a leaving card fades out (R17). Decision Q1 (etagere.md §7):
    /// fully transparent after one slot. Clamped to `RingGeometry.fadeLengthRange` (0.25...1).
    public var fadeLengthInSlots: Double {
        get { storedFadeLength }
        set { storedFadeLength = RingGeometry.clampedFadeLength(newValue) }
    }

    /// The animation for a choice made by `EtagereAnimationChoice.choose`: nil for `.immediate` (Reduce Motion).
    /// A repeat interval is clamped to `RepeatDetector.animationIntervalRange` here too, so no interval, not even
    /// zero, a negative value or NaN, gives an infinite, negative or undefined speed.
    public func animation(for choice: EtagereAnimationChoice) -> Animation? {
        switch choice {
        case .immediate:
            nil
        case .cardStep:
            stepAnimation
        case .shelfStep:
            shelfStepAnimation
        case .highlightStep:
            highlightAnimation
        case .repeating(let interval):
            interval.map(retimedRepeatAnimation(forMeasured:)) ?? repeatAnimation
        }
    }

    private func retimedRepeatAnimation(forMeasured interval: Double) -> Animation {
        let clamped = RepeatDetector.animationInterval(forMeasured: interval)
        return repeatAnimation.speed(RepeatDetector.referenceInterval / clamped)
    }
}
