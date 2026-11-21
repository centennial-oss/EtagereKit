import CoreGraphics
@_spi(EtagereDebug) @testable import EtagereKit
import SwiftUI
import Testing

/// A flat card with its own shape, for strips of mixed widths.
private nonisolated struct OverflowSwatchCard: ShelfCardContent {
    let id: String
    let cardAspectRatio: CGFloat?

    var accessibilityTitle: String { id }

    @MainActor
    func makeFace(context: ShelfCardContext) -> some View {
        Rectangle().fill(context.isActive ? Color.red : Color.gray)
    }
}

@MainActor
@Suite("T31 the Active Shelf highlight runs past the edges its cards run past (D12)")
struct HighlightOverflowTests {
    private static let size = CGSize(width: 1280, height: 900)

    private static func layout(_ configuration: EtagereConfiguration = EtagereConfiguration()) -> EtagereLayout {
        EtagereLayout(
            size: size, safeArea: EdgeInsets(), metrics: configuration.metrics.resolved(containerWidth: size.width),
            aspectRatio: 16.0 / 9.0, titleHeight: 20
        )
    }

    private static func edges(
        count: Int, rotation: Int = 0, alignment: EtagereHorizontalAlignment = .leading, ratio: CGFloat? = nil
    ) -> RingOverflowEdges {
        let configuration = EtagereConfiguration(horizontalAlignment: alignment)
        let cards = (0..<count).map { OverflowSwatchCard(id: "c\($0)", cardAspectRatio: ratio) }
        let model = EtagereModel(shelves: [Shelf(id: "shelf", title: "Shelf", cards: cards)])
        for _ in 0..<rotation {
            _ = model.move(.nextCard, isRepeat: false, reduceMotion: true)
        }
        let state = model.shelves[0]
        #expect(state.rotation == rotation || count == 0)
        return layout(configuration).overflowEdges(of: state, configuration: configuration)
    }

    @Test("T31 the anchor's side: a long ring runs past the far edge, a short one fits")
    func edgesByAnchor() {
        // Regular class at 1280 pt: about four 16:9 cards fit after a leading anchor.
        #expect(Self.edges(count: 8) == RingOverflowEdges(leading: false, trailing: true))
        #expect(Self.edges(count: 8, rotation: 5) == RingOverflowEdges(leading: false, trailing: true))
        #expect(Self.edges(count: 3) == .none)
        #expect(Self.edges(count: 1) == .none)
        #expect(Self.edges(count: 0) == .none)
        #expect(Self.edges(count: 8, alignment: .trailing) == RingOverflowEdges(leading: true, trailing: false))
        #expect(Self.edges(count: 9, alignment: .center) == RingOverflowEdges(leading: true, trailing: true))
        #expect(Self.edges(count: 3, alignment: .center) == .none)
    }

    @Test("T31 cards of their own widths: narrow posters fit where as many 16:9 cards run past the edge")
    func edgesWithCardWidths() {
        #expect(Self.edges(count: 6) == RingOverflowEdges(leading: false, trailing: true))
        #expect(Self.edges(count: 6, ratio: 0.5) == .none)
        #expect(Self.edges(count: 6, ratio: 2.5) == RingOverflowEdges(leading: false, trailing: true))
    }

    @Test("T31 the highlight ends half an inset outside the cards, or past an edge by its corner radius")
    func highlightInsets() {
        let layout = Self.layout()
        let pad = layout.highlightPadding.width
        let inside = layout.highlightInsets(.none)
        #expect(inside.leading == layout.leadingInset - pad && inside.trailing == layout.trailingInset - pad)
        let past = layout.highlightInsets(RingOverflowEdges(leading: true, trailing: true))
        #expect(past.leading == -layout.highlightCornerRadius && past.trailing == -layout.highlightCornerRadius)
        #expect(EtagereConfiguration().extendsHighlightPastEdges, "on by default")
    }

    @Test("T31 rendered: the tint reaches the trailing edge only when the cards do and the option is on",
          arguments: [EtagereVerticalMode.cursor, .ring])
    func renderedHighlight(mode: EtagereVerticalMode) throws {
        func tintAtTrailingEdge(cardCount: Int, extends: Bool) throws -> Bool {
            var configuration = EtagereConfiguration(verticalMode: mode)
            configuration.extendsHighlightPastEdges = extends
            let cards = (0..<cardCount).map { SwatchCard(id: "c\($0)") }
            let model = EtagereModel(
                shelves: [Shelf(id: "shelf", title: "Shelf", cards: cards)], configuration: configuration
            )
            let image = try #require(SnapshotHarness.render(
                SnapshotHarness.etagere(model, override: EtagerePhaseOverride()), size: Self.size,
                name: "highlight-overflow-\(mode)-\(cardCount)-\(extends)"
            ))
            let pixels = try #require(PixelImage(image))
            let layout = Self.layout(configuration)
            // Beside the title, above the cards, where only the highlight draws.
            let row = Int(layout.topInset) + 2
            #expect(pixels.color(column: Int(layout.leadingInset) - 2, row: row).isHighlightTint, "the highlight")
            return pixels.color(column: Int(Self.size.width) - 2, row: row).isHighlightTint
        }
        #expect(try tintAtTrailingEdge(cardCount: 8, extends: true))
        #expect(try !tintAtTrailingEdge(cardCount: 8, extends: false))
        #expect(try !tintAtTrailingEdge(cardCount: 3, extends: true))
    }
}
