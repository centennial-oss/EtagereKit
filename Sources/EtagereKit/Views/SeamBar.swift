import SwiftUI

/// The bar that marks a ring's seam, between its last and first item (R20, behavior §1.6): a capsule in
/// `.secondary`, or under Increase Contrast a 4 pt capsule in the accent color. Vertical between cards; horizontal
/// between the last and first shelf of the ShelvesRing (Q4).
struct SeamBar: View {
    var axis: Axis
    var length: CGFloat
    var thickness: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    static var increasedContrastThickness: CGFloat { 4 }

    var body: some View {
        let increased = contrast == .increased
        let width = increased ? max(thickness, Self.increasedContrastThickness) : thickness
        let size = axis == .vertical ? CGSize(width: width, height: length) : CGSize(width: length, height: width)
        Group {
            if increased {
                Capsule().fill(.tint)
            } else {
                Capsule().fill(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Places a card ring's seam bar in the middle of the gap after the last card at `slot` (the copy at
/// `virtualIndex`), with that card's opacity, so it rides and fades with the ring (behavior §1.6). The bar's frame
/// is `barWidth` wide.
@Animatable
struct SeamEffect: ViewModifier {
    var slot: Double
    var activity: Double
    @AnimatableIgnored var virtualIndex: Int
    @AnimatableIgnored var strip: RingStrip
    @AnimatableIgnored var barWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(strip.opacity(of: virtualIndex, slot: slot, activity: activity))
            .offset(x: strip.seamCenter(after: virtualIndex, slot: slot, activity: activity) - barWidth / 2)
    }
}

/// Places the ShelvesRing's seam bar in the gap below the last shelf at `slot` (mode 1, Q4).
@Animatable
struct ShelfSeamEffect: ViewModifier {
    var slot: Double
    @AnimatableIgnored var geometry: RingGeometry
    @AnimatableIgnored var rest: ClosedRange<Int>
    @AnimatableIgnored var barHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(geometry.opacity(at: slot, rest: rest))
            .offset(y: geometry.seamCenter(afterSlot: slot) - barHeight / 2)
    }
}
