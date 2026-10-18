import SwiftUI

/// One shelf as both vertical modes draw it: its title (with a quiet "Updating" while the host refreshes it) above
/// its ring, one adjustable VoiceOver element, and on macOS a subtle highlight while the pointer hovers it.
struct ShelfRowView<Card: ShelfCardContent>: View {
    let controller: EtagereController<Card>
    let state: ShelfState<Card>
    let shelfVirtualIndex: Int
    let isActive: Bool
    let layout: EtagereLayout
    let configuration: EtagereConfiguration
    /// Snapshot and debug rendering (`EtagerePhaseOverride`).
    var cardPhase: Double?
    var activityOverride: Double?
    /// False for a ghost copy outside the rest window: hidden from VoiceOver and pointer input.
    var isAccessible = true
    let rotorNamespace: Namespace.ID
    let focus: AccessibilityFocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: layout.titleSpacing) {
            ShelfTitle(state: state, isActive: isActive, style: layout.metrics.titleStyle)
                .frame(maxWidth: .infinity, minHeight: layout.titleHeight, alignment: .bottomLeading)
                .padding(.leading, layout.leadingInset)
                .padding(.trailing, layout.trailingInset)
            ShelfRingView(
                controller: controller, state: state, shelfVirtualIndex: shelfVirtualIndex, isActive: isActive,
                layout: layout, configuration: configuration, phaseOverride: cardPhase,
                activityOverride: activityOverride, isInteractive: isAccessible
            )
        }
        .frame(width: layout.size.width, height: layout.shelfHeight, alignment: .topLeading)
        .background {
            ShelfHoverHighlight(viewState: controller.viewState, shelfID: state.id, isActive: isActive, layout: layout)
        }
        .modifier(RowPointerInput(isEnabled: isAccessible) { [controller, shelfVirtualIndex] in
            controller.selectShelf(virtualIndex: shelfVirtualIndex)
        })
        .modifier(ShelfAccessibility(
            controller: controller, state: state, shelfVirtualIndex: shelfVirtualIndex, isActive: isActive,
            isAccessible: isAccessible, rotorNamespace: rotorNamespace, focus: focus
        ))
    }
}

/// A shelf's title, and while the host refreshes the shelf a subdued "Updating" after it (Shelf.isUpdating). The
/// status is smaller than the title, so it never changes the title's measured height; VoiceOver reads it with
/// the shelf's value instead. It fades in and out, which Reduce Motion allows.
private struct ShelfTitle<Card: ShelfCardContent>: View {
    let state: ShelfState<Card>
    let isActive: Bool
    let style: EtagereTitleStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(state.title)
                .font(style.font)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
            if state.isUpdating {
                Text(ShelfAccessibilityText.updating)
                    .font(style.statusFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(EtagereCrossfade.jump, value: state.isUpdating)
    }
}

/// The hover highlight of an inactive shelf (macOS). Its own view, so a hover re-renders only the highlights.
private struct ShelfHoverHighlight: View {
    let viewState: EtagereViewState
    let shelfID: String
    let isActive: Bool
    let layout: EtagereLayout

    static var opacity: Double { 0.05 }

    var body: some View {
        let pad = layout.highlightPadding
        RoundedRectangle(cornerRadius: layout.highlightCornerRadius, style: .continuous)
            .fill(.primary.opacity(!isActive && viewState.hoveredShelfID == shelfID ? Self.opacity : 0))
            .padding(.vertical, -pad.height)
            .padding(.leading, layout.leadingInset - pad.width)
            .padding(.trailing, layout.trailingInset - pad.width)
            .accessibilityHidden(true)
    }
}

/// A tap or click on a shelf outside its cards (its title or the gaps) makes it active (macOS and iOS; on tvOS the
/// focus engine does that).
struct RowPointerInput: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .allowsHitTesting(isEnabled)
        #endif
    }
}
