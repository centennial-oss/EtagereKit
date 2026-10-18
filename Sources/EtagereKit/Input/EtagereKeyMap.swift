/// The physical keys the Etagere reacts to, independent of any UI framework's key type.
public nonisolated enum EtagereKey: String, Sendable, Hashable, CaseIterable {
    case leftArrow, rightArrow, upArrow, downArrow
    case returnKey, keypadEnter, space, letterK
    case escape

    /// The key for a key press's character, as SwiftUI's `KeyEquivalent.character` and AppKit's
    /// `NSEvent.charactersIgnoringModifiers` report it: arrows as the function-key characters U+F700-U+F703,
    /// Return as "\r", keypad Enter as U+0003, Escape as U+001B. Nil for any other character. Callers pass only
    /// presses without the Command, Option or Control modifiers.
    public init?(character: Character) {
        switch character {
        case "\u{F702}": self = .leftArrow
        case "\u{F703}": self = .rightArrow
        case "\u{F700}": self = .upArrow
        case "\u{F701}": self = .downArrow
        case "\r", "\n": self = .returnKey
        case "\u{3}": self = .keypadEnter
        case " ": self = .space
        case "k", "K": self = .letterK
        case "\u{1B}": self = .escape
        default: return nil
        }
    }
}

/// Maps physical keys to intents (behavior §3.2, T18). Pure, so it is unit tested, including right-to-left
/// layouts, where the left and right arrows swap: physical right is "next" in left-to-right layouts and "previous"
/// in right-to-left ones (behavior §1.11). Up and down never change. The Siri Remote's and a game controller's
/// directions go through the same map as the arrows.
public nonisolated enum EtagereKeyMap {
    public static func intent(for key: EtagereKey, isRightToLeft: Bool) -> EtagereIntent {
        switch key {
        case .leftArrow: .move(isRightToLeft ? .nextCard : .previousCard)
        case .rightArrow: .move(isRightToLeft ? .previousCard : .nextCard)
        case .upArrow: .move(.previousShelf)
        case .downArrow: .move(.nextShelf)
        case .returnKey, .keypadEnter, .space, .letterK: .activate
        case .escape: .exit
        }
    }

    /// The intent for a key press's character, or nil when the Etagere does not use that key.
    public static func intent(forCharacter character: Character, isRightToLeft: Bool) -> EtagereIntent? {
        EtagereKey(character: character).map { intent(for: $0, isRightToLeft: isRightToLeft) }
    }
}
