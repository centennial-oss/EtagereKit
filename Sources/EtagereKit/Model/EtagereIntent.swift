/// A logical move. The input layer maps physical arrows, swipes and remote presses onto it, so right-to-left
/// layouts change only that mapping, never the model (D2).
public nonisolated enum EtagereMove: String, Sendable, Hashable, CaseIterable, Codable {
    case previousCard, nextCard, previousShelf, nextShelf

    /// True for card moves (they rotate the Active Shelf's ring), false for shelf moves.
    public var isHorizontal: Bool {
        self == .previousCard || self == .nextCard
    }

    /// -1 for the previous card or shelf, +1 for the next one.
    public var delta: Int {
        switch self {
        case .previousCard, .previousShelf: -1
        case .nextCard, .nextShelf: 1
        }
    }
}

/// Everything the Etagere does in response to input, on every platform (behavior §3.1).
public nonisolated enum EtagereIntent: Sendable, Hashable {
    case move(EtagereMove)
    /// "Go" on the Active ShelfCard (R8), or the host's action for an empty shelf (Q7).
    case activate
    case contextMenu
    /// Leave the Etagere: the host moves focus to its sidebar (R27).
    case exit
}

/// Which animation a move uses (behavior §1.8, §2.2, §4), chosen by a pure function so it can be tested (T19). The
/// model resolves it with `EtagereConfiguration.animation(for:)`.
public nonisolated enum EtagereAnimationChoice: Sendable, Hashable {
    /// Reduce Motion: the state changes at once, with no sliding.
    case immediate
    /// One card step: `stepAnimation`.
    case cardStep
    /// One shelf step in mode 1, turning the ShelvesRing: `shelfStepAnimation`.
    case shelfStep
    /// One cursor step in mode 2, sliding the Active Shelf highlight: `highlightAnimation` (R25).
    case highlightStep
    /// A key or button repeat, in either direction and either mode: `repeatAnimation`, retimed to the measured
    /// repeat interval (clamped to `RepeatDetector.animationIntervalRange`) when there is one, so the ring or the
    /// highlight keeps pace with the keys.
    case repeating(interval: Double?)

    public static func choose(
        for move: EtagereMove,
        verticalMode: EtagereVerticalMode,
        isRepeat: Bool,
        repeatInterval: Double? = nil,
        reduceMotion: Bool
    ) -> EtagereAnimationChoice {
        if reduceMotion { return .immediate }
        if isRepeat { return .repeating(interval: repeatInterval.map(RepeatDetector.animationInterval(forMeasured:))) }
        if move.isHorizontal { return .cardStep }
        return switch verticalMode {
        case .ring: .shelfStep
        case .cursor: .highlightStep
        }
    }
}
