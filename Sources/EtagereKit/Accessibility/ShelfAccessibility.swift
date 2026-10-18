import Accessibility
import SwiftUI

/// The words VoiceOver hears (behavior §4). Pure, so they are unit tested. English for now: the package has no
/// string catalog yet.
nonisolated enum ShelfAccessibilityText {
    static let rotorLabel = "Shelves"
    static let emptyShelf = "Empty shelf"
    static let startOfList = "Start of list"
    static let endOfList = "End of list"
    /// Shown next to the title of a shelf the host is refreshing, and read with its value.
    static let updating = "Updating"

    /// A shelf's value: "card title, 3 of 8", or the placeholder's message on an empty shelf, followed by
    /// "Updating" while the host refreshes the shelf.
    static func value(
        cardTitle: String?, index: Int?, count: Int, emptyMessage: String?, isUpdating: Bool = false
    ) -> String {
        let content: String
        if let cardTitle, let index, count > 0 {
            content = "\(cardTitle), \(index + 1) of \(count)"
        } else {
            let message = emptyMessage ?? ""
            content = message.isEmpty ? emptyShelf : message
        }
        return isUpdating ? "\(content), \(updating)" : content
    }

    /// What to announce when the seam crosses the Anchor Spot: wrapping forward lands on the first card, wrapping
    /// backward on the last one.
    static func seamAnnouncement(fromLap oldLap: Int, toLap newLap: Int) -> String? {
        guard oldLap != newLap else { return nil }
        return newLap > oldLap ? startOfList : endOfList
    }
}

extension ShelfState {
    /// The VoiceOver value of this shelf.
    var accessibilityValueText: String {
        ShelfAccessibilityText.value(
            cardTitle: anchoredCard?.accessibilityTitle, index: anchoredIndex, count: cards.count,
            emptyMessage: emptyMessage, isUpdating: isUpdating
        )
    }
}

/// Each shelf is one adjustable VoiceOver element (behavior §4): its title as the label, the anchored card and its
/// position as the value, increment and decrement to turn it, the default action to play its card, and the card's
/// context-menu actions as named actions. VoiceOver focus makes it the Active Shelf (the container watches the
/// focus binding). A ghost copy of a shelf is hidden; the modifiers stay the same either way, so a copy keeps its
/// identity as it moves in and out of the rest window.
struct ShelfAccessibility<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let state: ShelfState<Card>
    let shelfVirtualIndex: Int
    let isActive: Bool
    let isAccessible: Bool
    let rotorNamespace: Namespace.ID
    let focus: AccessibilityFocusState<String?>.Binding

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(state.title))
            .accessibilityValue(Text(state.accessibilityValueText))
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: controller.adjust(state, shelfVirtualIndex: shelfVirtualIndex, by: 1)
                case .decrement: controller.adjust(state, shelfVirtualIndex: shelfVirtualIndex, by: -1)
                @unknown default: break
                }
            }
            .accessibilityAction {
                controller.activate(shelfVirtualIndex: shelfVirtualIndex)
            }
            .accessibilityActions {
                EtagereActionMenu(actions: controller.handlers.actions(for: activation))
            }
            .modifier(VoiceOverFocus(focus: focus, shelfID: state.id))
            .accessibilityRotorEntry(id: state.id, in: rotorNamespace)
            .accessibilityHidden(!isAccessible)
    }

    private var activation: EtagereActivation<Card> {
        state.anchoredCard.map { .card($0) } ?? .emptyShelf(shelfID: state.id)
    }
}

/// Binds VoiceOver focus to a shelf only while VoiceOver runs. Nothing else needs it, and an
/// `accessibilityFocused` modifier keeps `ImageRenderer` from drawing the view, which the snapshot tests rely on.
private struct VoiceOverFocus: ViewModifier {
    let focus: AccessibilityFocusState<String?>.Binding
    let shelfID: String
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        if voiceOverEnabled {
            content.accessibilityFocused(focus, equals: shelfID)
        } else {
            content
        }
    }
}

/// The Etagere-wide accessibility: a "Shelves" rotor that jumps to any shelf, making it active first so mode 1
/// renders it (behavior §4). Where the Etagere is a single focusable element (tvOS, mode 1), it is also one
/// adjustable element whose label and value follow the Active Shelf and its card.
struct EtagereAccessibility<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let rotorNamespace: Namespace.ID
    let isSingleElement: Bool

    func body(content: Content) -> some View {
        let model = controller.model
        if isSingleElement {
            content
                .accessibilityElement(children: .ignore)
                .modifier(ActiveShelfSummary(controller: controller))
        } else {
            content
                .accessibilityElement(children: .contain)
                .accessibilityRotor(Text(ShelfAccessibilityText.rotorLabel)) {
                    ForEach(model.shelves) { shelf in
                        AccessibilityRotorEntry(Text(shelf.title), id: shelf.id, in: rotorNamespace) {
                            controller.selectShelf(id: shelf.id)
                        }
                    }
                }
        }
    }
}

/// The live label and value of a single-element Etagere: the Active Shelf and its anchored card.
private struct ActiveShelfSummary<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>

    func body(content: Content) -> some View {
        let shelf = controller.model.activeShelf
        content
            .accessibilityLabel(Text(shelf?.title ?? ShelfAccessibilityText.emptyShelf))
            .accessibilityValue(Text(shelf?.accessibilityValueText ?? ""))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: controller.perform(.move(.nextCard))
                case .decrement: controller.perform(.move(.previousCard))
                @unknown default: break
                }
            }
            .accessibilityAction {
                controller.activate()
            }
            .accessibilityActions {
                EtagereActionMenu(actions: controller.handlers.actions(for: controller.model.activation))
            }
    }
}

/// Announces "Start of list" when the seam crosses the Active Shelf's anchor (Q5: there is no visible marker), and
/// "End of list" when it crosses backward.
struct SeamAnnouncement: ViewModifier {
    let lap: Int
    let isActive: Bool

    func body(content: Content) -> some View {
        content.onChange(of: lap) { oldLap, newLap in
            guard isActive,
                  let text = ShelfAccessibilityText.seamAnnouncement(fromLap: oldLap, toLap: newLap) else { return }
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
