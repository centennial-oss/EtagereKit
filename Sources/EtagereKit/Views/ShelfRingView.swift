import SwiftUI

/// One horizontal ShelfRing (behavior §1): the cards of one shelf in their render window, each copy keyed by
/// `(cardID, lap)` so a wrapping card can be on screen twice (R14), plus the seam bar. The Etagere routes keys to
/// the model; the ring handles its own pointer, touch and trackpad input. It reads its shelf's `ShelfState`, so
/// rotating one shelf re-renders only that ring (D4), and it never reads its own geometry: the Etagere measures
/// once and hands every ring the same layout.
struct ShelfRingView<Card: ShelfCardContent>: View {
    let controller: EtagereController<Card>
    let state: ShelfState<Card>
    /// The shelf copy this ring belongs to: mode 1 can render a shelf twice while the ShelvesRing wraps.
    let shelfVirtualIndex: Int
    let isActive: Bool
    let layout: EtagereLayout
    let configuration: EtagereConfiguration
    /// Snapshot and debug rendering: an absolute ring phase, and the activity at a fractional shelf phase.
    var phaseOverride: Double?
    var activityOverride: Double?
    /// False for a ghost copy of a shelf, which takes no input.
    var isInteractive = true

    @State private var dragSlots = 0.0
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let alignment = configuration.cardCrossAlignment.stackAlignment
        let geometry = layout.ringGeometry(configuration)
        let bump = controller.viewState.cardBump.trigger(forShelf: state.id)
        ZStack(alignment: alignment) {
            ringContent(geometry: geometry)
                .id(state.jumpGeneration)
                .transition(.opacity)
        }
        .animation(EtagereCrossfade.jump, value: state.jumpGeneration)
        .frame(width: layout.size.width, height: layout.ringHeight, alignment: alignment)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: bump) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            CubicKeyframe(bump.offset, duration: 0.08)
            SpringKeyframe(0, duration: 0.32, spring: .bouncy)
        }
        .contentShape(Rectangle())
        .modifier(ringInput(geometry: geometry))
        .modifier(SeamAnnouncement(lap: lap, isActive: isActive && isInteractive))
        .clipShape(Rectangle().inset(by: -12))
    }

    private var lap: Int {
        state.cards.isEmpty ? 0 : RingMath.floorDiv(state.rotation, state.cards.count)
    }

    private var activity: Double { activityOverride ?? (isActive ? 1 : 0) }

    private var emphasisKey: Int { state.rotation * 2 + (isActive ? 1 : 0) }

    @ViewBuilder
    private func ringContent(geometry: RingGeometry) -> some View {
        let alignment = configuration.cardCrossAlignment.stackAlignment
        ZStack(alignment: alignment) {
            if state.isEmpty {
                placeholder(geometry: geometry)
            } else {
                cards(geometry: geometry)
            }
        }
        .frame(width: layout.size.width, height: layout.ringHeight, alignment: alignment)
    }

    // MARK: Cards

    @ViewBuilder
    private func cards(geometry: RingGeometry) -> some View {
        // One snapshot for the slots and the cards: SwiftUI can update a card with a slot from the previous pass
        // before this body runs again, so a card never indexes the live list, which may have shrunk.
        let cards = state.cards
        let count = cards.count
        let activeRest = geometry.restWindow(count: count)
        let inactiveRest = geometry.withActivity(0).restWindow(count: count)
        let targetRest = isActive ? activeRest : inactiveRest
        let phase = phaseOverride ?? Double(state.rotation) + dragSlots
        let slots = RingMath.renderSlots(
            itemCount: count, covering: RingPhase.coveredRotations(state.rotationsInFlight, phase: phase),
            rest: RingPhase.union(activeRest, inactiveRest)
        ) { cards[$0].id }
        let anchored = phaseOverride.map { Int($0.rounded()) } ?? state.rotation
        ForEach(slots) { slot in
            if cards.indices.contains(slot.ringIndex) {
                let context = ShelfCardContext(
                    isActive: isActive && slot.virtualIndex == anchored, isAnchored: slot.virtualIndex == anchored,
                    isShelfActive: isActive, ringIndex: slot.ringIndex, ringCount: count, faceSize: layout.cardSize
                )
                let card = cards[slot.ringIndex]
                ShelfCard(
                    card: card, context: context,
                    showsFocusRing: context.isActive && controller.viewState.hasKeyboardFocus,
                    showsContrastOutline: context.isActive && contrast == .increased
                )
                .equatable()
                .modifier(placement(slot: Double(slot.virtualIndex) - phase, isEmphasized: context.isActive,
                                    geometry: geometry, activeRest: activeRest, inactiveRest: inactiveRest))
                .modifier(CardPointerInput(
                    isEnabled: isInteractive && targetRest.contains(slot.virtualIndex - state.rotation),
                    actions: controller.handlers.cardActions == nil ? nil : { [controller] in
                        controller.handlers.cardActions?(card) ?? []
                    }
                ) { [controller, state, shelfVirtualIndex] in
                    controller.tapCard(
                        on: state, shelfVirtualIndex: shelfVirtualIndex, cardVirtualIndex: slot.virtualIndex
                    )
                })
            }
        }
        if configuration.showsSeam {
            let barFrame = max(layout.metrics.seamWidth, SeamBar.increasedContrastThickness)
            ForEach(slots.filter(\.isSeamOwner)) { slot in
                SeamBar(axis: .vertical, length: layout.cardSize.height * 0.8, thickness: layout.metrics.seamWidth)
                    .frame(width: barFrame, height: layout.cardSize.height)
                    .modifier(SeamEffect(
                        slot: Double(slot.virtualIndex) - phase, activity: activity, geometry: geometry,
                        activeRest: activeRest, inactiveRest: inactiveRest, barWidth: barFrame
                    ))
            }
        }
    }

    // MARK: Empty shelf

    private func placeholder(geometry: RingGeometry) -> some View {
        EmptyShelfCard(
            message: state.emptyMessage ?? "", size: layout.cardSize,
            showsFocusRing: isActive && controller.viewState.hasKeyboardFocus,
            showsContrastOutline: isActive && contrast == .increased
        )
        .equatable()
        .modifier(placement(
            slot: 0, isEmphasized: isActive, geometry: geometry, activeRest: 0...0, inactiveRest: 0...0
        ))
        .modifier(CardPointerInput(
            isEnabled: isInteractive,
            actions: controller.handlers.emptyShelfActions == nil ? nil : { [controller, id = state.id] in
                controller.handlers.emptyShelfActions?(id) ?? []
            }
        ) { [controller, shelfVirtualIndex] in
            controller.tapPlaceholder(shelfVirtualIndex: shelfVirtualIndex)
        })
    }

    private func placement(
        slot: Double, isEmphasized: Bool, geometry: RingGeometry, activeRest: ClosedRange<Int>,
        inactiveRest: ClosedRange<Int>
    ) -> RingSlotPlacement {
        RingSlotPlacement(
            slot: slot, activity: activity, geometry: geometry, activeRest: activeRest, inactiveRest: inactiveRest,
            idleDim: configuration.idleDim, shelfDim: configuration.inactiveShelfDim,
            scaleAnchor: configuration.cardCrossAlignment.scaleAnchor, emphasisKey: emphasisKey,
            isEmphasized: isEmphasized, reduceMotion: reduceMotion
        )
    }

    // MARK: Drags, scrubs and haptics

    private func ringInput(geometry: RingGeometry) -> RingInput<Card> {
        RingInput(
            controller: controller, state: state, step: geometry.step,
            isRightToLeft: layoutDirection == .rightToLeft, isEnabled: isInteractive,
            dragSlots: $dragSlots
        )
    }
}
