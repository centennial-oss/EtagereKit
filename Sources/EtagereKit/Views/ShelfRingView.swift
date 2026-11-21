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
        .clipShape(RingClip(horizontal: 12, vertical: 12 + layout.ringOverflow))
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
        let phase = phaseOverride ?? Double(state.rotation) + dragSlots
        let covered = RingPhase.coveredRotations(state.rotationsInFlight, phase: phase)
        let strip = strip(geometry: geometry, cards: cards, covering: covered)
        let targetRest = strip.restWindow(at: state.rotation, isActive: isActive)
        let slots = RingMath.renderSlots(itemCount: count, covering: covered, rest: strip.renderRest) { cards[$0].id }
        let anchored = phaseOverride.map { Int($0.rounded()) } ?? state.rotation
        ForEach(slots) { slot in
            if cards.indices.contains(slot.ringIndex) {
                let faceSize = CGSize(width: strip.idleWidth(of: slot.virtualIndex), height: layout.cardSize.height)
                let context = ShelfCardContext(
                    isActive: isActive && slot.virtualIndex == anchored, isAnchored: slot.virtualIndex == anchored,
                    isShelfActive: isActive, ringIndex: slot.ringIndex, ringCount: count, faceSize: faceSize
                )
                let card = cards[slot.ringIndex]
                ShelfCard(
                    card: card, context: context,
                    showsFocusRing: context.isActive && controller.viewState.hasKeyboardFocus,
                    showsContrastOutline: context.isActive && contrast == .increased
                )
                .equatable()
                .modifier(placement(slot: Double(slot.virtualIndex) - phase, virtualIndex: slot.virtualIndex,
                                    isEmphasized: context.isActive, strip: strip))
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
                        slot: Double(slot.virtualIndex) - phase, activity: activity,
                        virtualIndex: slot.virtualIndex, strip: strip, barWidth: barFrame
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
        .modifier(placement(slot: 0, virtualIndex: 0, isEmphasized: isActive, strip: .placeholder(geometry: geometry)))
        .modifier(CardPointerInput(
            isEnabled: isInteractive,
            actions: controller.handlers.emptyShelfActions == nil ? nil : { [controller, id = state.id] in
                controller.handlers.emptyShelfActions?(id) ?? []
            }
        ) { [controller, shelfVirtualIndex] in
            controller.tapPlaceholder(shelfVirtualIndex: shelfVirtualIndex)
        })
    }

    /// The card widths and rest windows around the rotations in flight (behavior §1.12).
    private func strip(geometry: RingGeometry, cards: [Card], covering rotations: ClosedRange<Int>) -> RingStrip {
        RingStrip(
            geometry: geometry, cardSize: layout.cardSize, itemCount: cards.count, covering: rotations
        ) { cards[$0].cardAspectRatio }
    }

    private func placement(
        slot: Double, virtualIndex: Int, isEmphasized: Bool, strip: RingStrip
    ) -> RingSlotPlacement {
        RingSlotPlacement(
            slot: slot, activity: activity, virtualIndex: virtualIndex, strip: strip,
            idleDim: configuration.idleDim, shelfDim: configuration.inactiveShelfDim,
            scaleAnchor: configuration.cardCrossAlignment.scaleAnchor, emphasisKey: emphasisKey,
            isEmphasized: isEmphasized, reduceMotion: reduceMotion
        )
    }

    // MARK: Drags, scrubs and haptics

    /// Drags and scrubs move one slot per the anchored card's step (behavior §1.12).
    private func ringInput(geometry: RingGeometry) -> RingInput<Card> {
        let cards = state.cards
        let rotation = state.rotation
        let widths = cards.isEmpty ? RingWidths.uniform : RingWidths.window(rotation...(rotation + 1)) { index in
            let card = cards[RingMath.floorMod(index, cards.count)]
            return RingWidths.widthRatio(cardAspectRatio: card.cardAspectRatio, cardSize: layout.cardSize)
        }
        return RingInput(
            controller: controller, state: state, step: geometry.dragStep(at: rotation, widths: widths),
            isRightToLeft: layoutDirection == .rightToLeft, isEnabled: isInteractive,
            dragSlots: $dragSlots
        )
    }
}
