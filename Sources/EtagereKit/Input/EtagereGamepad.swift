import SwiftUI

/// Game-controller input for the Etagere on iOS and macOS (behavior §3.3), fed by the host.
///
/// GameController's handlers belong to whoever set them last, so EtagereKit never sets any. The host keeps its one
/// set of handlers per controller (next to its own back button, say) and forwards the d-pad, the left stick and
/// the A and B buttons here. Attach the gamepad with `Etagere.etagereGamepad(_:requiresFocus:)`: an Etagere takes
/// the input only while it has focus in an active window, so one gamepad can serve every window, and the most
/// recently focused Etagere wins. Directions count past half way and repeat after 400 ms, then every 110 ms, while
/// held; the d-pad wins over the stick. A plays the Active ShelfCard and B leaves the Etagere. Each method returns
/// whether an Etagere took the input, so the host can use what it did not (B as its own back button, for example).
///
/// ```swift
/// // Once per connected controller, with `controller.handlerQueue = .main`:
/// pad.dpad.valueChangedHandler = { _, xValue, yValue in
///     MainActor.assumeIsolated { gamepad.directionChanged(.dpad, xValue: xValue, yValue: yValue) }
/// }
/// pad.leftThumbstick.valueChangedHandler = { _, xValue, yValue in
///     MainActor.assumeIsolated { gamepad.directionChanged(.leftStick, xValue: xValue, yValue: yValue) }
/// }
/// pad.buttonA.pressedChangedHandler = { _, _, pressed in
///     MainActor.assumeIsolated { gamepad.buttonChanged(.buttonA, isPressed: pressed) }
/// }
/// pad.buttonB.pressedChangedHandler = { _, _, pressed in
///     MainActor.assumeIsolated {
///         if !gamepad.buttonChanged(.buttonB, isPressed: pressed), pressed { goBack() }
///     }
/// }
///
/// Etagere(model: home) { card in play(card) } onExit: { focusSidebar() }
///     .etagereGamepad(gamepad)
/// ```
///
/// tvOS needs none of this: its focus engine already turns controllers into remote commands.
@MainActor
public final class EtagereGamepad {
    /// The controls that move the selection.
    public enum DirectionalControl: Sendable, Hashable {
        case dpad, leftStick
    }

    /// The buttons the Etagere uses.
    public enum Button: Sendable, Hashable {
        /// Plays the Active ShelfCard, like Return.
        case buttonA
        /// Leaves the Etagere, like Esc.
        case buttonB
    }

    /// The focused Etagere: who it is and how it takes a key (`isRepeat` set for a held direction's repeats).
    private struct Target {
        let owner: ObjectIdentifier
        let press: (EtagereKey, Bool) -> Bool
    }

    private var dpadKey: EtagereKey?
    private var stickKey: EtagereKey?
    /// The direction held now, and whether the focused Etagere took its press.
    private var heldKey: EtagereKey?
    private var heldKeyIsTaken = false
    private var takenButtons = Set<Button>()
    private var repeatTask: Task<Void, Never>?
    private var target: Target?
    private let waitBeforeRepeat: @MainActor (Int) async -> Void

    public init() {
        waitBeforeRepeat = { index in
            try? await Task.sleep(for: .seconds(ControllerStick.delay(beforeRepeat: index)))
        }
    }

    /// For tests: `waitBeforeRepeat` returns when the `index`th repeat of a held direction is due.
    init(waitBeforeRepeat: @escaping @MainActor (Int) async -> Void) {
        self.waitBeforeRepeat = waitBeforeRepeat
    }

    /// True while an Etagere takes this gamepad's input: one that has focus in an active window (or, attached with
    /// `requiresFocus: false`, one on screen in an active window).
    public var isAttached: Bool { target != nil }

    /// A d-pad or stick position, as GameController reports it: each axis in -1...1, y positive upward. Returns
    /// whether an Etagere took it: a new direction it used, or the release or repeat of one it took.
    @discardableResult
    public func directionChanged(_ control: DirectionalControl, xValue: Float, yValue: Float) -> Bool {
        let key = ControllerStick.key(xValue: xValue, yValue: yValue)
        switch control {
        case .dpad: dpadKey = key
        case .leftStick: stickKey = key
        }
        return hold(dpadKey ?? stickKey)
    }

    /// A button press or release. Returns whether an Etagere took it; a release goes with its press.
    @discardableResult
    public func buttonChanged(_ button: Button, isPressed: Bool) -> Bool {
        guard isPressed else { return takenButtons.remove(button) != nil }
        guard let target, target.press(button == .buttonA ? .returnKey : .escape, false) else { return false }
        takenButtons.insert(button)
        return true
    }

    /// Lets go of every direction and button, for example when a controller disconnects or the app moves to the
    /// background.
    public func releaseAll() {
        stopRepeating()
        dpadKey = nil
        stickKey = nil
        heldKey = nil
        heldKeyIsTaken = false
        takenButtons.removeAll()
    }

    // MARK: Etagere side

    /// Makes `owner` the Etagere that takes the input. A direction or button held for another Etagere stays
    /// with it (its repeats stop, and its release reports as taken): this one only sees the next press.
    func attach(owner: ObjectIdentifier, press: @escaping (EtagereKey, Bool) -> Bool) {
        if target?.owner != owner { stopRepeating() }
        target = Target(owner: owner, press: press)
    }

    /// Stops sending input to `owner`, if it is the Etagere taking it.
    func detach(owner: ObjectIdentifier) {
        guard target?.owner == owner else { return }
        target = nil
        stopRepeating()
    }

    // MARK: Holding a direction

    /// Presses `key` once and repeats it while it stays held; nil releases.
    private func hold(_ key: EtagereKey?) -> Bool {
        guard key != heldKey else { return heldKeyIsTaken }
        let releasedTakenKey = heldKeyIsTaken
        stopRepeating()
        heldKey = key
        heldKeyIsTaken = false
        guard let key else { return releasedTakenKey }
        guard let target, target.press(key, false) else { return false }
        heldKeyIsTaken = true
        startRepeating(key)
        return true
    }

    private func startRepeating(_ key: EtagereKey) {
        repeatTask = Task { [weak self, waitBeforeRepeat] in
            var index = 0
            while !Task.isCancelled {
                await waitBeforeRepeat(index)
                guard !Task.isCancelled, let self, heldKey == key, let target else { return }
                _ = target.press(key, true)
                index += 1
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// Connects an `EtagereGamepad` to one Etagere while it has focus (unless the host says otherwise) in an active
/// window, and disconnects it as soon as either ends. Nothing global happens: the gamepad only learns which
/// Etagere to call.
struct GamepadAttachment<Card: ShelfCardContent>: ViewModifier {
    let gamepad: EtagereGamepad?
    let controller: EtagereController<Card>
    let requiresFocus: Bool
    @State private var attached: EtagereGamepad?
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.layoutDirection) private var layoutDirection

    private struct Link: Equatable {
        var gamepad: ObjectIdentifier?
        var isRightToLeft: Bool
    }

    func body(content: Content) -> some View {
        let isLive = appearsActive && (!requiresFocus || controller.viewState.hasKeyboardFocus)
        let link = Link(
            gamepad: isLive ? gamepad.map(ObjectIdentifier.init) : nil, isRightToLeft: layoutDirection == .rightToLeft
        )
        content
            .onAppear { connect(link) }
            .onChange(of: link) { _, newLink in connect(newLink) }
            .onDisappear { connect(Link(gamepad: nil, isRightToLeft: false)) }
    }

    private func connect(_ link: Link) {
        let owner = ObjectIdentifier(controller)
        if let attached, link.gamepad != ObjectIdentifier(attached) {
            attached.detach(owner: owner)
            self.attached = nil
        }
        guard let gamepad, link.gamepad == ObjectIdentifier(gamepad) else { return }
        let isRightToLeft = link.isRightToLeft
        gamepad.attach(owner: owner) { [weak controller] key, isRepeat in
            controller?.perform(key: key, isRightToLeft: isRightToLeft, reportedRepeat: isRepeat) ?? false
        }
        attached = gamepad
    }
}
