import SwiftUI

/// Places one card of a ShelfRing for a continuous `slot` (behavior §1.7): its offset along the ring, its opacity by
/// the fade rule and its stacking order. `slot` and `activity` are the animatable data, so SwiftUI re-evaluates
/// this modifier, and not the card face, on every animation frame, and the non-linear rules (fade only past the
/// rest edge, grow only near the anchor) hold mid-flight instead of being interpolated between the end points.
///
/// Offsets are leading-based. SwiftUI mirrors leading-based offsets in right-to-left layouts (checked with
/// `ImageRenderer`), which is exactly the `x' = V - x` of behavior §1.11, so this modifier does not mirror again.
@Animatable
struct RingSlotEffect: ViewModifier {
    var slot: Double
    /// 1 when the shelf is active, 0 when not; animates when the selection moves to or from the shelf (§1.9).
    var activity: Double
    @AnimatableIgnored var geometry: RingGeometry
    /// The rest window of the active ring and of the inactive ring: they can differ by one slot, and the opacity
    /// blends between them with `activity`.
    @AnimatableIgnored var activeRest: ClosedRange<Int>
    @AnimatableIgnored var inactiveRest: ClosedRange<Int>

    func body(content: Content) -> some View {
        let ring = geometry.withActivity(activity)
        let activeOpacity = ring.opacity(at: slot, rest: activeRest)
        let inactiveOpacity = ring.opacity(at: slot, rest: inactiveRest)
        content
            .opacity(inactiveOpacity + (activeOpacity - inactiveOpacity) * activity)
            .offset(x: ring.center(at: slot) - ring.idleLength / 2)
            .zIndex(Double(ring.emphasis(at: slot)) * activity)
    }
}

/// The emphasis of one card: the Active ShelfCard grows (`scaleEffect`, never a frame change, so faces lay out
/// once) and every other card dims (R7, R10, R12). Split from `RingSlotEffect` so that under Reduce Motion a card
/// whose emphasis changes can be replaced and crossfaded at its new size while its position jumps (behavior §4).
@Animatable
struct CardEmphasisEffect: ViewModifier {
    var slot: Double
    var activity: Double
    @AnimatableIgnored var geometry: RingGeometry
    @AnimatableIgnored var idleDim: Double
    @AnimatableIgnored var shelfDim: Double
    @AnimatableIgnored var scaleAnchor: UnitPoint

    func body(content: Content) -> some View {
        let ring = geometry.withActivity(activity)
        let emphasis = Double(ring.emphasis(at: slot)) * activity
        content
            .scaleEffect(ring.length(at: slot) / max(ring.idleLength, 1), anchor: scaleAnchor)
            .brightness(-(idleDim * (1 - emphasis) + shelfDim * (1 - activity)))
    }
}

/// Everything a rendered card needs from its ring, applied as one modifier.
///
/// Under Reduce Motion (behavior §4) nothing slides or zooms: positions jump, and a card that gains or loses the
/// emphasis is replaced by a copy at its new size, the two crossfading over 150 ms where the card now sits. Every
/// other card keeps its size, and its dimming eases over the same 150 ms.
struct RingSlotPlacement: ViewModifier {
    var slot: Double
    var activity: Double
    var geometry: RingGeometry
    var activeRest: ClosedRange<Int>
    var inactiveRest: ClosedRange<Int>
    var idleDim: Double
    var shelfDim: Double
    var scaleAnchor: UnitPoint
    /// Changes whenever the card's emphasis should change: its ring's rotation or its shelf's activity.
    var emphasisKey: Int
    /// True for the Active ShelfCard (the anchored card of the Active Shelf).
    var isEmphasized: Bool
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .modifier(CardEmphasisEffect(
                slot: slot, activity: activity, geometry: geometry, idleDim: idleDim, shelfDim: shelfDim,
                scaleAnchor: scaleAnchor
            ))
            .id(Self.crossfadeIdentity(isEmphasized: isEmphasized, reduceMotion: reduceMotion))
            .transition(.opacity)
            // The value only changes under Reduce Motion, so otherwise the move's own animation passes through.
            .animation(EtagereCrossfade.reduceMotion, value: reduceMotion ? emphasisKey : nil)
            .modifier(RingSlotEffect(
                slot: slot, activity: activity, geometry: geometry, activeRest: activeRest, inactiveRest: inactiveRest
            ))
    }

    /// The identity of a card's emphasis layer. Under Reduce Motion it follows the emphasis, so gaining or losing
    /// it replaces the card and crossfades the two sizes instead of animating a zoom. Otherwise it never changes:
    /// the emphasis animates with the ring.
    static func crossfadeIdentity(isEmphasized: Bool, reduceMotion: Bool) -> Bool? {
        reduceMotion ? isEmphasized : nil
    }
}

/// Places one shelf of the vertical ShelvesRing (mode 1, behavior §2.1): the same geometry on the y axis. Shelves
/// do not grow at the anchor; they fade past the rest edge like cards.
@Animatable
struct VerticalSlotEffect: ViewModifier {
    var slot: Double
    @AnimatableIgnored var geometry: RingGeometry
    @AnimatableIgnored var rest: ClosedRange<Int>

    func body(content: Content) -> some View {
        content
            .opacity(geometry.opacity(at: slot, rest: rest))
            .offset(y: geometry.center(at: slot) - geometry.idleLength / 2)
    }
}
