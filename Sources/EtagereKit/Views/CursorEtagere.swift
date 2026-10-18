import SwiftUI

/// Mode 2 (behavior §2.2): the shelves stay put in a scrolling column and one highlight slides between rows (R24,
/// R25). The scroll position keeps the Active Shelf at the vertical alignment where it can (R26); the cursor never
/// wraps. On tvOS each row takes focus itself, so up and down are native focus moves that also reach controls above
/// and below; where there is nothing above the top row (or below the bottom one), that row's move command asks the
/// host and otherwise bumps. Elsewhere the Etagere moves the cursor and asks the host at the ends (Q2).
struct CursorEtagere<Card: ShelfCardContent>: View {
    let controller: EtagereController<Card>
    let layout: EtagereLayout
    var phaseOverride: EtagerePhaseOverride?
    let rotorNamespace: Namespace.ID

    @Namespace private var highlightNamespace
    @State private var scrolledShelfID: String?
    @FocusState private var focusedRow: String?
    @AccessibilityFocusState private var focusedShelf: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let model = controller.model
        let configuration = model.configuration
        Group {
            if phaseOverride == nil {
                ScrollView(.vertical) {
                    column
                }
                .scrollPosition(id: $scrolledShelfID, anchor: configuration.verticalAlignment.scrollAnchor)
            } else {
                // Snapshot and debug rendering: `ImageRenderer` cannot draw a scroll view.
                column.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            scrolledShelfID = model.activeShelf?.id
        }
        .onChange(of: model.activeShelf?.id) { _, shelfID in
            withAnimation(reduceMotion ? nil : configuration.highlightAnimation) {
                scrolledShelfID = shelfID
            }
            if focusedRow != nil, focusedRow != shelfID {
                focusedRow = shelfID
            }
        }
        .onChange(of: focusedRow) { _, shelfID in
            controller.rowFocusChanged()
            controller.viewState.hasKeyboardFocus = shelfID != nil
            if let shelfID { selectShelf(id: shelfID) }
        }
        .onChange(of: focusedShelf) { _, shelfID in
            if let shelfID { selectShelf(id: shelfID) }
        }
    }

    private var column: some View {
        let model = controller.model
        let configuration = model.configuration
        let bump = controller.viewState.shelfBump
        return LazyVStack(alignment: .leading, spacing: layout.metrics.shelfSpacing) {
            ForEach(Array(model.shelves.enumerated()), id: \.element.id) { index, shelf in
                row(index: index, shelf: shelf, configuration: configuration)
            }
        }
        .scrollTargetLayout()
        .padding(.top, layout.topInset)
        .padding(.bottom, layout.bottomInset)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: bump) { content, offset in
            content.offset(y: offset)
        } keyframes: { _ in
            CubicKeyframe(bump.offset, duration: 0.08)
            SpringKeyframe(0, duration: 0.32, spring: .bouncy)
        }
    }

    private func row(index: Int, shelf: ShelfState<Card>, configuration: EtagereConfiguration) -> some View {
        let isActive = controller.model.isShelfActive(virtualIndex: index)
        return ShelfRowView(
            controller: controller, state: shelf, shelfVirtualIndex: index, isActive: isActive, layout: layout,
            configuration: configuration, cardPhase: isActive ? phaseOverride?.cardPhase : nil,
            rotorNamespace: rotorNamespace, focus: $focusedShelf
        )
        .background {
            ZStack {
                if isActive {
                    highlight(index: index)
                }
            }
            // Under Reduce Motion only the highlight crossfades; the value never changes otherwise, so the
            // move's `highlightAnimation` slides it.
            .animation(EtagereCrossfade.reduceMotion, value: reduceMotion ? isActive : nil)
        }
        .modifier(CursorRowFocus(
            controller: controller, shelfID: shelf.id, focus: $focusedRow,
            edges: Self.edges(ofRow: index, count: controller.model.shelves.count)
        ))
    }

    /// One highlight that slides between rows with `highlightAnimation` through `matchedGeometryEffect`; under
    /// Reduce Motion each row's highlight has its own identity, so it crossfades instead (behavior §4).
    private func highlight(index: Int) -> some View {
        let pad = layout.highlightPadding
        return ActiveShelfHighlight(cornerRadius: layout.highlightCornerRadius)
            .padding(.vertical, -pad.height)
            .padding(.leading, layout.leadingInset - pad.width)
            .padding(.trailing, layout.trailingInset - pad.width)
            .matchedGeometryEffect(id: reduceMotion ? "activeShelf-\(index)" : "activeShelf", in: highlightNamespace)
            .transition(.opacity)
    }

    /// The Etagere's edges a row sits on: the top for the first row, the bottom for the last.
    static func edges(ofRow index: Int, count: Int) -> Set<VerticalEdge> {
        var edges = Set<VerticalEdge>()
        if index == 0 { edges.insert(.top) }
        if index == count - 1 { edges.insert(.bottom) }
        return edges
    }

    private func selectShelf(id: String) {
        guard let index = controller.model.shelves.firstIndex(where: { $0.id == id }) else { return }
        controller.selectShelf(virtualIndex: index)
    }
}

/// On tvOS each mode 2 row is its own focus target (behavior §2.2) and Select on it plays the Active ShelfCard.
/// Elsewhere the Etagere is the one focusable element.
private struct CursorRowFocus<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let shelfID: String
    let focus: FocusState<String?>.Binding
    /// The Etagere's edges this row sits on.
    let edges: Set<VerticalEdge>

    func body(content: Content) -> some View {
        #if os(tvOS)
        RemoteSelectTarget(content: content) { controller.perform(.activate) }
            .focused(focus, equals: shelfID)
            .modifier(CursorRowEdges(controller: controller, edges: edges))
        #else
        content
        #endif
    }
}

#if os(tvOS)
/// The top and bottom rows of mode 2 on tvOS (Q2). Between rows, up and down are native focus moves and never
/// reach a handler. Past the top or bottom row with no control there, the focus engine has nowhere to go and the
/// command arrives here: the host's `onEtagereEdge` may move focus, or the cursor stops with a bump. Only the edge
/// rows get a handler, so the rows between keep the container's (left and right turn the ring). A row's handler
/// takes every direction, so it turns the ring too and leaves the direction away from its edge alone.
private struct CursorRowEdges<Card: ShelfCardContent>: ViewModifier {
    let controller: EtagereController<Card>
    let edges: Set<VerticalEdge>
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        if edges.isEmpty {
            content
        } else {
            content.onMoveCommand { direction in
                switch direction {
                case .left: controller.perform(key: .leftArrow, isRightToLeft: layoutDirection == .rightToLeft)
                case .right: controller.perform(key: .rightArrow, isRightToLeft: layoutDirection == .rightToLeft)
                case .up: if edges.contains(.top) { controller.reachEdge(.top) }
                case .down: if edges.contains(.bottom) { controller.reachEdge(.bottom) }
                @unknown default: break
                }
            }
        }
    }
}
#endif
