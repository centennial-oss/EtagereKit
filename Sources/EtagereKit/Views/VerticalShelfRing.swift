import SwiftUI

/// Mode 1 (behavior §2.1): the shelves ride the vertical ShelvesRing with the same geometry as cards on the y axis,
/// each copy keyed by `(shelfID, lap)` so a wrapping shelf can be on screen twice. Both copies observe the same
/// `ShelfState`; only the copy at `shelfRotation` is active. A tinted highlight stays fixed at the anchor while the
/// shelves slide beneath it, and a seam bar marks the gap between the last and first shelf (Q4).
struct VerticalShelfRing<Card: ShelfCardContent>: View {
    let controller: EtagereController<Card>
    let layout: EtagereLayout
    var phaseOverride: EtagerePhaseOverride?
    let rotorNamespace: Namespace.ID

    @State private var dragSlots = 0.0
    @AccessibilityFocusState private var focusedShelf: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the ring crossfades on: a jump, and under Reduce Motion every shelf move (behavior §4).
    private nonisolated struct CrossfadeKey: Hashable, Sendable {
        var jump: Int
        var reduceMotionRotation: Int?
    }

    var body: some View {
        let model = controller.model
        let geometry = layout.shelvesGeometry(model.configuration)
        let rest = geometry.restWindow(count: model.shelves.count)
        let phase = phaseOverride?.shelfPhase ?? Double(model.shelfRotation) + dragSlots
        let key = CrossfadeKey(
            jump: model.shelfJumpGeneration, reduceMotionRotation: reduceMotion ? model.shelfRotation : nil
        )
        let bump = controller.viewState.shelfBump
        ZStack(alignment: .topLeading) {
            if !model.shelves.isEmpty {
                highlight(geometry: geometry)
            }
            shelves(geometry: geometry, rest: rest, phase: phase)
                .id(key)
                .transition(.opacity)
        }
        .animation(reduceMotion ? EtagereCrossfade.reduceMotion : EtagereCrossfade.jump, value: key)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: bump) { content, offset in
            content.offset(y: offset)
        } keyframes: { _ in
            CubicKeyframe(bump.offset, duration: 0.08)
            SpringKeyframe(0, duration: 0.32, spring: .bouncy)
        }
        .contentShape(Rectangle())
        .modifier(ShelvesInput(
            controller: controller, step: geometry.step, shelfCount: model.shelves.count, dragSlots: $dragSlots
        ))
        .clipped()
        .onChange(of: focusedShelf) { _, shelfID in
            guard let shelfID, let copy = accessibleCopy(of: shelfID, rest: rest) else { return }
            controller.selectShelf(virtualIndex: copy)
        }
    }

    private func highlight(geometry: RingGeometry) -> some View {
        let pad = layout.highlightPadding
        return ActiveShelfHighlight(cornerRadius: layout.highlightCornerRadius)
            .frame(
                width: max(0, layout.size.width - layout.leadingInset - layout.trailingInset + 2 * pad.width),
                height: layout.shelfHeight + 2 * pad.height
            )
            .offset(
                x: layout.leadingInset - pad.width,
                y: geometry.center(at: 0) - layout.shelfHeight / 2 - pad.height
            )
    }

    private func shelves(geometry: RingGeometry, rest: ClosedRange<Int>, phase: Double) -> some View {
        let model = controller.model
        let configuration = model.configuration
        let slots = RingMath.renderSlots(
            itemCount: model.shelves.count,
            covering: RingPhase.coveredRotations(model.shelfRotationsInFlight, phase: phase), rest: rest
        ) { model.shelves[$0].id }
        let seamThickness = max(layout.metrics.seamWidth, SeamBar.increasedContrastThickness)
        return ZStack(alignment: .topLeading) {
            ForEach(slots) { slot in
                let relative = Double(slot.virtualIndex) - phase
                let isActive = model.isShelfActive(virtualIndex: slot.virtualIndex)
                ShelfRowView(
                    controller: controller, state: model.shelves[slot.ringIndex], shelfVirtualIndex: slot.virtualIndex,
                    isActive: isActive, layout: layout, configuration: configuration,
                    cardPhase: isActive ? phaseOverride?.cardPhase : nil,
                    activityOverride: phaseOverride?.shelfPhase == nil ? nil : RingPhase.activity(atSlot: relative),
                    isAccessible: rest.contains(slot.virtualIndex - model.shelfRotation),
                    rotorNamespace: rotorNamespace, focus: $focusedShelf
                )
                .modifier(VerticalSlotEffect(slot: relative, geometry: geometry, rest: rest))
            }
            if configuration.showsShelfSeam {
                ForEach(slots.filter(\.isSeamOwner)) { slot in
                    SeamBar(
                        axis: .horizontal,
                        length: max(0, layout.size.width - layout.leadingInset - layout.trailingInset),
                        thickness: layout.metrics.seamWidth
                    )
                    .frame(height: seamThickness)
                    .padding(.leading, layout.leadingInset)
                    .modifier(ShelfSeamEffect(
                        slot: Double(slot.virtualIndex) - phase, geometry: geometry, rest: rest,
                        barHeight: seamThickness
                    ))
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    /// The rendered copy of a shelf that VoiceOver can reach: the one inside the rest window.
    private func accessibleCopy(of shelfID: String, rest: ClosedRange<Int>) -> Int? {
        let model = controller.model
        guard !model.shelves.isEmpty else { return nil }
        return rest.lazy
            .map { model.shelfRotation + $0 }
            .first { model.shelves[RingMath.floorMod($0, model.shelves.count)].id == shelfID }
    }
}
