import SwiftUI

/// One extra action on a card, shown in its context menu (right-click, long-press, or a long press of Select on the
/// Siri Remote) and offered to VoiceOver as a named action on the shelf, so the two always match (behavior §4,
/// Q6). Actions are data rather than menu views for exactly that reason. `EtagereAction.divider` separates groups
/// of actions in the menu (D11).
public struct EtagereAction {
    public var title: String
    /// An SF Symbol name.
    public var systemImage: String?
    /// `.destructive` draws the action in red. `.cancel` only closes the menu, so VoiceOver does not offer it.
    public var role: ButtonRole?
    public var handler: () -> Void
    /// True for `EtagereAction.divider`.
    public private(set) var isDivider = false

    public init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        handler = action
    }

    /// A line between groups of actions in the context menu (D11), drawn as a `Divider`. A divider first, last or
    /// next to another one is dropped, so conditional groups need no bookkeeping, and VoiceOver's named actions
    /// skip dividers.
    public static var divider: EtagereAction {
        var action = EtagereAction("") {}
        action.isDivider = true
        return action
    }

    /// The context menu's items: the actions, without a divider first, last or right after another divider.
    static func menuItems(_ actions: [EtagereAction]) -> [EtagereAction] {
        var items: [EtagereAction] = []
        for action in actions where !(action.isDivider && (items.last?.isDivider ?? true)) {
            items.append(action)
        }
        if items.last?.isDivider == true { items.removeLast() }
        return items
    }

    /// VoiceOver's named actions: no dividers, and no Cancel, which only closes a menu.
    static func accessibilityItems(_ actions: [EtagereAction]) -> [EtagereAction] {
        actions.filter { !$0.isDivider && $0.role != .cancel }
    }
}

/// Builds a list of `EtagereAction`s with `if`, `switch` and `for`, like a view builder.
@resultBuilder
public enum EtagereActionBuilder {
    public static func buildExpression(_ action: EtagereAction) -> [EtagereAction] { [action] }
    public static func buildExpression(_ actions: [EtagereAction]) -> [EtagereAction] { actions }
    public static func buildBlock(_ parts: [EtagereAction]...) -> [EtagereAction] { parts.flatMap(\.self) }
    public static func buildOptional(_ part: [EtagereAction]?) -> [EtagereAction] { part ?? [] }
    public static func buildEither(first part: [EtagereAction]) -> [EtagereAction] { part }
    public static func buildEither(second part: [EtagereAction]) -> [EtagereAction] { part }
    public static func buildArray(_ parts: [[EtagereAction]]) -> [EtagereAction] { parts.flatMap(\.self) }
    public static func buildLimitedAvailability(_ part: [EtagereAction]) -> [EtagereAction] { part }
}

/// The menu items for a list of actions, or VoiceOver's named actions for them.
struct EtagereActionMenu: View {
    let actions: [EtagereAction]
    /// True inside `accessibilityActions`: no dividers and no Cancel.
    var isAccessibility = false

    var body: some View {
        let items = isAccessibility ? EtagereAction.accessibilityItems(actions) : EtagereAction.menuItems(actions)
        ForEach(items.indices, id: \.self) { index in
            let action = items[index]
            if action.isDivider {
                Divider()
            } else if let systemImage = action.systemImage {
                Button(action.title, systemImage: systemImage, role: action.role, action: action.handler)
            } else {
                Button(action.title, role: action.role, action: action.handler)
            }
        }
    }
}

/// Everything the host hands the Etagere besides its model.
struct EtagereHandlers<Card: ShelfCardContent> {
    var onActivate: (Card) -> Void = { _ in }
    var onActivateEmptyShelf: (String) -> Void = { _ in }
    var onExit: () -> Void = {}
    /// Mode 2 edge escape (Q2): returns true when the host moved focus out of the Etagere.
    var onEdge: ((VerticalEdge) -> Bool)?
    /// Play/Pause on the Siri Remote, before "go": returns true when the host used the press itself.
    var onPlayPause: (() -> Bool)?
    var cardActions: ((Card) -> [EtagereAction])?
    var emptyShelfActions: ((String) -> [EtagereAction])?

    /// The context-menu actions for what "go" would act on, or for a particular activation.
    func actions(for activation: EtagereActivation<Card>?) -> [EtagereAction] {
        switch activation {
        case .card(let card): cardActions?(card) ?? []
        case .emptyShelf(let shelfID): emptyShelfActions?(shelfID) ?? []
        case nil: []
        }
    }

    var hasActions: Bool { cardActions != nil || emptyShelfActions != nil }
}
