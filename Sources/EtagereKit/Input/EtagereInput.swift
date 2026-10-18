import SwiftUI

/// The Etagere's focus and key input (behavior §3): one focusable element whose keys, commands and taps go through
/// `EtagereKeyMap` to the controller. macOS and iPadOS use `onKeyPress` with phases (repeat included); macOS leaves
/// Esc to `onExitCommand`. tvOS uses the remote's move, exit, play/pause and select commands; Play/Pause asks the
/// host first (`onEtagerePlayPause`). In mode 1 every direction is consumed (R27); in mode 2 a move the model does
/// not consume reaches the host's edge handler.
struct EtagereInput<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    /// False on tvOS in mode 2, where each shelf row takes focus itself (behavior §2.2).
    let isFocusable: Bool
    @FocusState private var isFocused: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    private var isRightToLeft: Bool { layoutDirection == .rightToLeft }

    func body(content: Content) -> some View {
        focusTarget(content)
            .onChange(of: isFocused) { _, focused in
                if isFocusable { controller.viewState.hasKeyboardFocus = focused }
                if !focused { controller.resetRepeat() }
            }
            .modifier(platformInput)
    }

    /// The Etagere as one focus target, or, on tvOS in mode 2, left alone: `.focusable(false)` there would also
    /// keep the focus engine away from the shelf rows inside it, so focus could never enter them.
    @ViewBuilder
    private func focusTarget(_ content: Content) -> some View {
        if isFocusable {
            #if os(tvOS)
            // A button, not a focusable view with a tap gesture: on a real Siri Remote the tap gesture shared Select
            // with the context menu's long press and often missed a click (seen on an Apple TV, 2026-10-12). A button's
            // primary action is how tvOS delivers Select; a long press still opens the context menu.
            RemoteSelectTarget(content: content) { controller.perform(.activate) }
                .focused($isFocused)
            #else
            content
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
            #endif
        } else {
            content
        }
    }

    #if os(tvOS)
    private var platformInput: some ViewModifier {
        RemoteCommandInput(controller: controller, isRightToLeft: isRightToLeft, takesVerticalMoves: isFocusable)
    }
    #else
    private var platformInput: some ViewModifier {
        KeyboardInput(controller: controller, isRightToLeft: isRightToLeft) { isFocused = true }
    }
    #endif
}

#if !os(tvOS)
/// Hardware keys on macOS and iPadOS (and iPhone with a keyboard).
private struct KeyboardInput<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let isRightToLeft: Bool
    let requestFocus: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: [.down, .repeat]) { press in
                handle(press)
            }
            #if os(macOS)
            .onExitCommand {
                controller.perform(.exit)
            }
            // A click anywhere on the Etagere gives it keyboard focus, so the arrows work next.
            .simultaneousGesture(TapGesture().onEnded(requestFocus))
            #endif
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]),
              let key = EtagereKey(character: press.key.character) else { return .ignored }
        #if os(macOS)
        // Esc reaches `onExitCommand`, which also covers the system's cancel operation.
        if key == .escape { return .ignored }
        #endif
        let isRepeat = press.phase == .repeat
        let intent = EtagereKeyMap.intent(for: key, isRightToLeft: isRightToLeft)
        if isRepeat, intent == .activate || intent == .exit {
            // "Go" and exit never repeat.
            return .handled
        }
        return controller.perform(intent, reportedRepeat: isRepeat) ? .handled : .ignored
    }
}
#endif

#if os(tvOS)
/// The Siri Remote and controllers through the focus engine (behavior §3.2). tvOS reports no repeat phase, so the
/// controller's `RepeatDetector` treats moves under 180 ms apart as repeats.
private struct RemoteCommandInput<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let isRightToLeft: Bool
    /// False in mode 2, where up and down are native focus moves between the shelf rows, each row is the focused
    /// element, and the top and bottom rows handle their own edges (`CursorRowEdges`).
    let takesVerticalMoves: Bool

    func body(content: Content) -> some View {
        content
            .onMoveCommand { direction in
                guard let key = key(for: direction) else { return }
                controller.perform(key: key, isRightToLeft: isRightToLeft)
            }
            .onExitCommand {
                controller.perform(.exit)
            }
            .onPlayPauseCommand {
                controller.playPause()
            }
            // Select arrives through the focus target's button (`RemoteSelectTarget`), in mode 2 the row's.
            .modifier(ActiveCardContextMenu(controller: controller))
    }

    private func key(for direction: MoveCommandDirection) -> EtagereKey? {
        switch direction {
        case .left: .leftArrow
        case .right: .rightArrow
        case .up: takesVerticalMoves ? .upArrow : nil
        case .down: takesVerticalMoves ? .downArrow : nil
        @unknown default: nil
        }
    }
}
#endif

#if os(tvOS)
/// One remote focus target that plays on Select: the content as the label of a button that draws nothing of its own
/// (the Etagere draws its own focus), keeping the content's accessibility elements (the adjustable shelves).
struct RemoteSelectTarget<Label: View>: View {
    let content: Label
    let action: () -> Void

    var body: some View {
        Button(action: action) { content }
            .buttonStyle(RemoteSelectButtonStyle())
            .focusEffectDisabled()
            .accessibilityElement(children: .contain)
    }
}

private struct RemoteSelectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#endif

/// The context menu for whatever "go" acts on, for a single focusable Etagere (tvOS: a long press of Select).
struct ActiveCardContextMenu<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>

    func body(content: Content) -> some View {
        if controller.handlers.hasActions {
            content.contextMenu {
                ActiveActionsMenu(controller: controller)
            }
        } else {
            content
        }
    }
}

/// Reads the activation when the menu is built, so the Etagere does not re-render on every rotation for it.
private struct ActiveActionsMenu<Card: ShelfCardContent>: View {
    let controller: EtagereController<Card>

    var body: some View {
        EtagereActionMenu(actions: controller.handlers.actions(for: controller.model.activation))
    }
}

/// A tap or click on one rendered card, and its context menu (macOS and iOS). Cards are not focusable on tvOS, so
/// there the remote's commands and the Etagere-wide context menu cover them.
struct CardPointerInput: ViewModifier {
    let isEnabled: Bool
    /// The card's context-menu actions, built only when the menu is.
    let actions: (() -> [EtagereAction])?
    let action: () -> Void

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content
            .onTapGesture(perform: action)
            .modifier(CardContextMenu(actions: actions))
            .allowsHitTesting(isEnabled)
        #endif
    }
}

private struct CardContextMenu: ViewModifier {
    let actions: (() -> [EtagereAction])?

    func body(content: Content) -> some View {
        if let actions {
            content.contextMenu {
                LazyActionMenu(provider: actions)
            }
        } else {
            content
        }
    }
}

private struct LazyActionMenu: View {
    let provider: () -> [EtagereAction]

    var body: some View {
        EtagereActionMenu(actions: provider())
    }
}

/// A ring's own drag, scrub and haptics: touch drags and selection haptics on iOS, the trackpad and mouse wheel
/// on macOS, nothing on tvOS.
struct RingInput<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let state: ShelfState<Card>
    let step: CGFloat
    let isRightToLeft: Bool
    let isEnabled: Bool
    @Binding var dragSlots: Double

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .modifier(RingDragInput(
                axis: .horizontal, step: step, isRightToLeft: isRightToLeft, itemCount: state.cards.count,
                isEnabled: isEnabled, onDrag: { dragSlots = $0 }, onRelease: release
            ))
            .modifier(RingHaptics(rotation: state.rotation, itemCount: state.cards.count, isEnabled: isEnabled))
        #elseif os(macOS)
        content
            .modifier(TrackpadScrub(
                shelfID: state.id, viewState: controller.viewState, step: step, isRightToLeft: isRightToLeft,
                itemCount: state.cards.count, isEnabled: isEnabled, onDrag: { dragSlots = $0 }, onRelease: release,
                onNotch: { controller.scrubStep(on: state, step: $0) }
            ))
        #else
        content
        #endif
    }

    private func release(_ delta: Int) {
        controller.releaseDrag(on: state, delta: delta) {
            dragSlots = 0
        }
    }
}

/// The ShelvesRing's vertical drag in mode 1 (iOS); nothing elsewhere.
struct ShelvesInput<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let step: CGFloat
    let shelfCount: Int
    @Binding var dragSlots: Double

    func body(content: Content) -> some View {
        #if os(iOS)
        content.modifier(RingDragInput(
            axis: .vertical, step: step, isRightToLeft: false, itemCount: shelfCount, isEnabled: shelfCount > 1,
            onDrag: { dragSlots = $0 },
            onRelease: { delta in controller.releaseShelvesDrag(delta: delta) { dragSlots = 0 } }
        ))
        #else
        content
        #endif
    }
}
