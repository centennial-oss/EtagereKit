#if os(iOS)
import SwiftUI
import UIKit

/// Touch drags and flings on a ring (behavior §1.8, §3.3). Inside a vertical `ScrollView` a SwiftUI `DragGesture`
/// competes with scrolling, so this is a UIKit pan recognizer that begins only when its own axis dominates the
/// velocity: horizontal on a ShelfRing, vertical on the mode 1 ShelvesRing. While the finger is down the ring
/// renders at `rotation + dragSlots`; on release it turns by `round(dragSlots + predicted)`, clamped to
/// `±min(N, 30)`.
struct RingDragInput: ViewModifier {
    let axis: Axis
    let step: CGFloat
    let isRightToLeft: Bool
    let itemCount: Int
    let isEnabled: Bool
    let onDrag: (Double) -> Void
    let onRelease: (Int) -> Void

    func body(content: Content) -> some View {
        if isEnabled, itemCount > 1 {
            content.gesture(RingPanGesture(axis: axis, onChange: changed, onEnd: ended))
        } else {
            content
        }
    }

    private func changed(translation: CGFloat) {
        let slots = RingDragMath.slots(forTranslation: translation, step: step, isRightToLeft: isRightToLeft)
        onDrag(RingDragMath.liveSlots(slots, itemCount: itemCount))
    }

    private func ended(translation: CGFloat, velocity: CGFloat) {
        let slots = RingDragMath.liveSlots(
            RingDragMath.slots(forTranslation: translation, step: step, isRightToLeft: isRightToLeft),
            itemCount: itemCount
        )
        let predicted = RingDragMath.projectedSlots(forVelocity: velocity, step: step, isRightToLeft: isRightToLeft)
        onRelease(RingDragMath.releaseDelta(dragSlots: slots, predictedSlots: predicted, itemCount: itemCount))
    }
}

/// A pan recognizer that reports the translation and velocity along one axis.
private struct RingPanGesture: UIGestureRecognizerRepresentable {
    let axis: Axis
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> AxisGate {
        AxisGate(axis: axis)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.axis = axis
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        let velocity = recognizer.velocity(in: recognizer.view)
        let distance = axis == .horizontal ? translation.x : translation.y
        switch recognizer.state {
        case .began, .changed:
            onChange(distance)
        case .ended:
            onEnd(distance, axis == .horizontal ? velocity.x : velocity.y)
        case .cancelled, .failed:
            onEnd(distance, 0)
        default:
            break
        }
    }
}

/// Lets the pan begin only when its axis dominates, so vertical scrolling and the other axis keep working.
final class AxisGate: NSObject, UIGestureRecognizerDelegate {
    var axis: Axis

    init(axis: Axis) {
        self.axis = axis
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return axis == .horizontal ? abs(velocity.x) > abs(velocity.y) : abs(velocity.y) > abs(velocity.x)
    }
}

/// The selection haptic on every rotation and a light impact when the seam crosses the anchor (behavior §1.6, §3.3).
struct RingHaptics: ViewModifier {
    let rotation: Int
    let itemCount: Int
    let isEnabled: Bool

    func body(content: Content) -> some View {
        let lap = itemCount > 0 ? RingMath.floorDiv(rotation, itemCount) : 0
        content
            .sensoryFeedback(.selection, trigger: rotation) { _, _ in isEnabled }
            .sensoryFeedback(.impact(weight: .light), trigger: lap) { _, _ in isEnabled }
    }
}
#endif
