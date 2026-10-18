import SwiftUI
#if os(tvOS)
import UIKit
#endif

/// The fallback for the Siri Remote's dropped presses (FB15272007, FB16045173; behavior §3.3): a UIKit view that
/// takes focus and reads presses directly, instead of SwiftUI's move, exit and play/pause commands. Off unless the
/// host turns it on with `etagereRemotePressBridge()`; nothing on other platforms.
struct RemotePressInput<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let isEnabled: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        #if os(tvOS)
        if isEnabled {
            content.background {
                RemotePressBridge(
                    onKey: { [controller, layoutDirection] key in
                        controller.perform(key: key, isRightToLeft: layoutDirection == .rightToLeft)
                    },
                    onPlayPause: { [controller] in controller.playPause() },
                    onFocusChange: { [controller] focused in
                        controller.viewState.hasKeyboardFocus = focused
                        if !focused { controller.resetRepeat() }
                    }
                )
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(tvOS)
extension Etagere {
    /// Reads the Siri Remote's presses through a UIKit bridge instead of SwiftUI's commands, for remotes that drop
    /// the first press after a view loads or a direction changes. Off by default; meant for a debug setting until
    /// the dropped-press reports are checked on tvOS 27 hardware.
    public func etagereRemotePressBridge(_ enabled: Bool = true) -> Etagere {
        var copy = self
        copy.usesRemotePressBridge = enabled
        return copy
    }
}

private struct RemotePressBridge: UIViewRepresentable {
    let onKey: (EtagereKey) -> Bool
    let onPlayPause: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> PressBridgeView {
        let view = PressBridgeView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: PressBridgeView, context: Context) {
        view.onKey = onKey
        view.onPlayPause = onPlayPause
        view.onFocusChange = onFocusChange
    }
}

/// Focusable, and turns arrow, Select and Menu presses into Etagere keys and Play/Pause into the controller's
/// Play/Pause (the host's handler, then "go"). Presses it does not use go on up the responder chain, began and
/// ended alike.
final class PressBridgeView: UIView {
    var onKey: ((EtagereKey) -> Bool)?
    var onPlayPause: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    private var handledPresses = Set<ObjectIdentifier>()

    override var canBecomeFocused: Bool { true }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        onFocusChange?(isFocused)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            if press.type == .playPause, let onPlayPause {
                onPlayPause()
                handledPresses.insert(ObjectIdentifier(press))
            } else if let key = Self.key(for: press.type), onKey?(key) == true {
                handledPresses.insert(ObjectIdentifier(press))
            } else {
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = finish(presses)
        if !unhandled.isEmpty {
            super.pressesEnded(unhandled, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = finish(presses)
        if !unhandled.isEmpty {
            super.pressesCancelled(unhandled, with: event)
        }
    }

    /// Forgets the presses this view handled and returns the others.
    private func finish(_ presses: Set<UIPress>) -> Set<UIPress> {
        presses.filter { handledPresses.remove(ObjectIdentifier($0)) == nil }
    }

    static func key(for type: UIPress.PressType) -> EtagereKey? {
        switch type {
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .select: .returnKey
        case .menu: .escape
        default: nil
        }
    }
}
#endif
