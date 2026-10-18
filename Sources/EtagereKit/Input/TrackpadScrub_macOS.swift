#if os(macOS)
import AppKit
import SwiftUI

/// Two-finger trackpad scrubs and mouse-wheel notches over one shelf (behavior §3.3). SwiftUI has no scroll-wheel
/// modifier, so this installs a local `NSEvent` scroll monitor while the pointer hovers the shelf and removes it when
/// the pointer leaves or the shelf disappears; it is never app-wide. A horizontal trackpad gesture drags the ring
/// and flings on release; a horizontal wheel, or Shift with a vertical wheel, steps one card per notch. Vertical
/// gestures pass through to the page. Hovering also gives the shelf a subtle highlight.
struct TrackpadScrub: ViewModifier {
    let shelfID: String
    let viewState: EtagereViewState
    let step: CGFloat
    let isRightToLeft: Bool
    let itemCount: Int
    let isEnabled: Bool
    let onDrag: (Double) -> Void
    let onRelease: (Int) -> Void
    let onNotch: (Int) -> Void
    @State private var monitor = ScrollMonitor()

    func body(content: Content) -> some View {
        monitor.update(ScrollMonitor.Settings(
            step: step, isRightToLeft: isRightToLeft, itemCount: itemCount, onDrag: onDrag, onRelease: onRelease,
            onNotch: onNotch
        ))
        return content
            .onHover { hovering in
                if hovering, isEnabled, itemCount > 1 {
                    monitor.install()
                } else {
                    monitor.remove()
                }
                if hovering {
                    viewState.hoveredShelfID = shelfID
                } else if viewState.hoveredShelfID == shelfID {
                    viewState.hoveredShelfID = nil
                }
            }
            .onDisappear {
                monitor.remove()
                if viewState.hoveredShelfID == shelfID { viewState.hoveredShelfID = nil }
            }
    }
}

/// Owns one local scroll-wheel monitor and the gesture it is following.
final class ScrollMonitor {
    struct Settings {
        var step: CGFloat
        var isRightToLeft: Bool
        var itemCount: Int
        var onDrag: (Double) -> Void
        var onRelease: (Int) -> Void
        var onNotch: (Int) -> Void
    }

    private var settings: Settings?
    private var token: Any?
    private var tracker = ScrubTracker()

    isolated deinit {
        remove()
    }

    /// Takes the shelf's current geometry and callbacks; called while the shelf evaluates its body.
    func update(_ newSettings: Settings) {
        settings = newSettings
    }

    func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return handle(event) ? nil : event
        }
    }

    /// Removes the monitor. A gesture still in progress is released where it is, so the ring never stays mid-drag.
    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        if tracker.isTracking {
            _ = apply(tracker.handle(.init(phase: .cancelled), isRightToLeft: settings?.isRightToLeft ?? false))
        }
        tracker = ScrubTracker()
    }

    /// Returns true when the event is consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let settings else { return false }
        let scroll = ScrubTracker.Event(
            phase: Self.phase(of: event), deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
            time: event.timestamp, isShiftDown: event.modifierFlags.contains(.shift)
        )
        let output = tracker.handle(scroll, isRightToLeft: settings.isRightToLeft)
        return apply(output)
    }

    private func apply(_ output: ScrubTracker.Output) -> Bool {
        guard let settings, let action = output.action else { return output.consumes }
        switch action {
        case .step(let step):
            settings.onNotch(step)
        case .drag(let translation):
            let slots = RingDragMath.slots(
                forTranslation: translation, step: settings.step, isRightToLeft: settings.isRightToLeft
            )
            settings.onDrag(RingDragMath.liveSlots(slots, itemCount: settings.itemCount))
        case .release(let translation, let velocity):
            let slots = RingDragMath.liveSlots(
                RingDragMath.slots(
                    forTranslation: translation, step: settings.step, isRightToLeft: settings.isRightToLeft
                ),
                itemCount: settings.itemCount
            )
            let predicted = RingDragMath.projectedSlots(
                forVelocity: velocity, step: settings.step, isRightToLeft: settings.isRightToLeft
            )
            settings.onRelease(
                RingDragMath.releaseDelta(dragSlots: slots, predictedSlots: predicted, itemCount: settings.itemCount)
            )
        }
        return output.consumes
    }

    private static func phase(of event: NSEvent) -> ScrubTracker.Phase {
        guard event.hasPreciseScrollingDeltas else { return .wheel }
        if !event.momentumPhase.isEmpty {
            return .momentum(isLast: event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled))
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { return .began }
        if event.phase.contains(.ended) { return .ended }
        if event.phase.contains(.cancelled) { return .cancelled }
        return .changed
    }
}
#endif
