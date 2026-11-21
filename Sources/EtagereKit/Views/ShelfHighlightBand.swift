import SwiftUI

/// The Active Shelf highlight across a shelf's width (R25): between the horizontal insets, or, with
/// `extendsHighlightPastEdges`, past an edge the shelf's cards run past at rest, so the tint follows them off
/// screen (D12). It reads the shelf in its own body, so rotating the Active Shelf re-renders only this view (D4).
struct ShelfHighlightBand<Card: ShelfCardContent>: View {
    let state: ShelfState<Card>
    let layout: EtagereLayout
    let configuration: EtagereConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let edges = configuration.extendsHighlightPastEdges
            ? layout.overflowEdges(of: state, configuration: configuration) : .none
        let insets = layout.highlightInsets(edges)
        ActiveShelfHighlight(cornerRadius: layout.highlightCornerRadius)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .animation(reduceMotion ? nil : configuration.highlightAnimation, value: edges)
    }
}

extension EtagereLayout {
    /// The edges an active shelf's cards run past at its current rotation (D12); none for an empty shelf.
    func overflowEdges<Card: ShelfCardContent>(
        of state: ShelfState<Card>, configuration: EtagereConfiguration
    ) -> RingOverflowEdges {
        let cards = state.cards
        guard !cards.isEmpty else { return .none }
        let rotation = state.rotation
        let strip = RingStrip(
            geometry: ringGeometry(configuration), cardSize: cardSize, itemCount: cards.count,
            covering: rotation...rotation
        ) { cards[$0].cardAspectRatio }
        return strip.overflowEdges(at: rotation)
    }

    /// The highlight's leading and trailing padding inside the Etagere's width: half the horizontal inset outside
    /// the insets, or past an edge the cards run past by the corner radius, so its square end meets the edge (D12).
    func highlightInsets(_ edges: RingOverflowEdges) -> (leading: CGFloat, trailing: CGFloat) {
        let pastEdge = -highlightCornerRadius
        let pad = highlightPadding.width
        return (
            edges.leading ? pastEdge : leadingInset - pad,
            edges.trailing ? pastEdge : trailingInset - pad
        )
    }
}
