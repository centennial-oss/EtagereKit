import SwiftUI

/// The Etagere (etagere.md §1, R1-R29): a vertical stack of shelves, each a horizontally rotating ring of cards,
/// with one selection, the Active ShelfCard. It draws its model, turns every platform's input into model changes,
/// and calls the host for "go", the empty-shelf action, leaving, the context menu and mode 2's edges.
///
/// ```swift
/// Etagere(model: home) { card in
///     player.play(card)
/// } onActivateEmptyShelf: { shelfID in
///     settings.open(for: shelfID)
/// } onExit: {
///     focus = .sidebar
/// }
/// .etagereContextMenu { card in
///     EtagereAction("Favorite", systemImage: "heart") { favorites.toggle(card) }
/// }
/// ```
///
/// The Etagere fills the space it is given and is one focusable element (on tvOS in mode 2, each shelf is). Its
/// metrics follow its own width (D7). It draws into the horizontal safe area so cards can slide off the edge, and
/// keeps the Anchor Spot inside it.
public struct Etagere<Card: ShelfCardContent>: View {
    private let model: EtagereModel<Card>
    var handlers: EtagereHandlers<Card>
    var phaseOverride: EtagerePhaseOverride?
    /// tvOS only: drive the Etagere from a UIKit presses bridge instead of SwiftUI's commands (behavior §3.3).
    var usesRemotePressBridge = false
    /// Game-controller input the host forwards (`etagereGamepad`).
    var gamepad: EtagereGamepad?
    var gamepadRequiresFocus = true

    @State private var controller: EtagereController<Card>
    @State private var measuredTitleHeight: CGFloat?
    @Namespace private var rotorNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - model: The shelves and the selection. Keep it alive for as long as the Etagere's screen exists, and save
    ///     `model.position` to restore it on the next launch (Q8).
    ///   - onActivate: "Go" on the Active ShelfCard (R8): Return, keypad Enter, Space or K, Select or Play/Pause
    ///     on the Siri Remote (see `onEtagerePlayPause`), controller A (see `etagereGamepad`), VoiceOver's default
    ///     action, or a click or tap on the anchored card.
    ///   - onActivateEmptyShelf: "Go" on an empty shelf's placeholder card (Q7), with that shelf's ID.
    ///   - onExit: Leaving the Etagere (R27): Esc, Menu/Back on the Siri Remote, controller B (see
    ///     `etagereGamepad`). Move focus to the sidebar.
    public init(
        model: EtagereModel<Card>,
        onActivate: @escaping (Card) -> Void,
        onActivateEmptyShelf: @escaping (String) -> Void = { _ in },
        onExit: @escaping () -> Void
    ) {
        self.model = model
        handlers = EtagereHandlers(
            onActivate: onActivate, onActivateEmptyShelf: onActivateEmptyShelf, onExit: onExit
        )
        _controller = State(initialValue: EtagereController(model: model))
    }

    public var body: some View {
        // Not observed by any view: the controller only holds the latest callbacks and settings.
        controller.update(model: model, handlers: handlers, reduceMotion: reduceMotion)
        return content
    }

    @ViewBuilder private var content: some View {
        let configuration = model.configuration
        let isTelevision = EtagereWidthClass.platformIsTelevision
        GeometryReader { proxy in
            let metrics = configuration.metrics.resolved(containerWidth: proxy.size.width)
            let layout = EtagereLayout(
                size: proxy.size, safeArea: proxy.safeAreaInsets, metrics: metrics,
                aspectRatio: Card.faceAspectRatio, titleHeight: measuredTitleHeight
            )
            shelves(layout: layout, mode: configuration.verticalMode)
                // A different model is a different Etagere: its views observe the new model from scratch.
                .id(ObjectIdentifier(model))
                .background {
                    TitleMeasurer(font: metrics.titleStyle.font) { height in
                        if measuredTitleHeight != height { measuredTitleHeight = height }
                    }
                }
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .modifier(EtagereInput(controller: controller, isFocusable: isContainerFocusable))
        .modifier(EtagereAccessibility(
            controller: controller, rotorNamespace: rotorNamespace,
            isSingleElement: isTelevision && configuration.verticalMode == .ring
        ))
        .modifier(GamepadAttachment(gamepad: gamepad, controller: controller, requiresFocus: gamepadRequiresFocus))
        .modifier(RemotePressInput(controller: controller, isEnabled: usesRemotePressBridge))
    }

    @ViewBuilder
    private func shelves(layout: EtagereLayout, mode: EtagereVerticalMode) -> some View {
        switch mode {
        case .ring:
            VerticalShelfRing(
                controller: controller, layout: layout, phaseOverride: phaseOverride, rotorNamespace: rotorNamespace
            )
        case .cursor:
            CursorEtagere(
                controller: controller, layout: layout, phaseOverride: phaseOverride, rotorNamespace: rotorNamespace
            )
        }
    }

    /// One focusable element, except on tvOS in mode 2 (each row is focusable) and behind the remote bridge (its
    /// UIKit view takes focus).
    private var isContainerFocusable: Bool {
        if usesRemotePressBridge { return false }
        return !(EtagereWidthClass.platformIsTelevision && model.configuration.verticalMode == .cursor)
    }
}

/// Measures one line of the shelf title font, so the ShelvesRing knows a shelf's height at any Dynamic Type size.
private struct TitleMeasurer: View {
    let font: Font
    let onMeasure: (CGFloat) -> Void

    var body: some View {
        Text(verbatim: "Ag")
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height.rounded(.up)
            } action: { height in
                onMeasure(height)
            }
    }
}

// MARK: - Modifiers

extension Etagere {
    /// Extra actions for a card, shown in its context menu (right-click, long press, or a long press of Select on
    /// the Siri Remote) and offered to VoiceOver as named actions on its shelf (Q6). Mode 1 pages have no other
    /// controls, so actions such as "Edit Home" belong here.
    public func etagereContextMenu(
        @EtagereActionBuilder _ actions: @escaping (Card) -> [EtagereAction]
    ) -> Etagere {
        var copy = self
        copy.handlers.cardActions = actions
        return copy
    }

    /// Card actions, plus actions for an empty shelf's placeholder card, with that shelf's ID.
    public func etagereContextMenu(
        @EtagereActionBuilder _ actions: @escaping (Card) -> [EtagereAction],
        @EtagereActionBuilder emptyShelf: @escaping (String) -> [EtagereAction]
    ) -> Etagere {
        var copy = self
        copy.handlers.cardActions = actions
        copy.handlers.emptyShelfActions = emptyShelf
        return copy
    }

    /// Mode 2: called when "previous shelf" is pressed on the top shelf or "next shelf" on the bottom one (Q2).
    /// Move focus to the control above or below the Etagere and return true; return false when there is none,
    /// and the cursor stops with a small bump. It never wraps. Without this modifier the cursor always bumps. On
    /// tvOS, where up and down are native focus moves, the focus engine reaches a focusable control beyond the edge
    /// by itself; this is called only when it finds none.
    public func onEtagereEdge(_ action: @escaping (VerticalEdge) -> Bool) -> Etagere {
        var copy = self
        copy.handlers.onEdge = action
        return copy
    }

    /// Play/Pause on the Siri Remote (tvOS; nothing elsewhere). By default it plays the Active ShelfCard, as Select
    /// does (behavior §3.2). `action` runs first: do the host's own Play/Pause work there (dismissing a mini player,
    /// for example) and return true, or return false to let the Etagere play the card. While the Etagere has focus
    /// it receives Play/Pause before any `onPlayPauseCommand` further up the hierarchy, so the host's work for that
    /// case belongs here.
    public func onEtagerePlayPause(_ action: @escaping () -> Bool) -> Etagere {
        var copy = self
        copy.handlers.onPlayPause = action
        return copy
    }

    /// Takes game-controller input that the host forwards to `gamepad` (iOS and macOS; behavior §3.3): the d-pad and
    /// the left stick move, A plays, B leaves. EtagereKit never installs GameController handlers; see
    /// `EtagereGamepad`. The Etagere takes the input only while it has focus in an active window. Pass
    /// `requiresFocus: false` where it may never get focus (an iPhone or iPad without a hardware keyboard): it then
    /// takes the input whenever it is on screen in an active window. Nil detaches it.
    public func etagereGamepad(_ gamepad: EtagereGamepad?, requiresFocus: Bool = true) -> Etagere {
        var copy = self
        copy.gamepad = gamepad
        copy.gamepadRequiresFocus = requiresFocus
        return copy
    }

    /// Renders fixed fractional phases instead of the model's rotations, for snapshot tests and debug rendering.
    @_spi(EtagereDebug)
    public func phaseOverride(_ override: EtagerePhaseOverride?) -> Etagere {
        var copy = self
        copy.phaseOverride = override
        return copy
    }
}
