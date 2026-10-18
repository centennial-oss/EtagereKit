import CoreGraphics
@_spi(EtagereDebug) @testable import EtagereKit
import SwiftUI
import Testing

/// T22's pixel checks (behavior §7.3): where the Active Shelf highlight and the seam bar land in rendered frames.
/// Frames render through the public `Etagere` at scale 1, so points are pixels, and the expected places come from
/// the same `EtagereLayout` the Etagere uses. A shelf title's height is measured while rendering, so checks that
/// depend on a shelf's height take it from the frame.
@MainActor
@Suite("T22 snapshot pixel checks: the Active Shelf highlight, the seam bar and the shelf status")
struct SnapshotPixelTests {
    private static let etagereSize = CGSize(width: 1280, height: 900)
    private static let shelfSize = CGSize(width: 1280, height: 340)

    private static func layout(_ size: CGSize, configuration: EtagereConfiguration) -> EtagereLayout {
        EtagereLayout(
            size: size, safeArea: EdgeInsets(), metrics: configuration.metrics.resolved(containerWidth: size.width),
            aspectRatio: SwatchCard.faceAspectRatio, titleHeight: nil
        )
    }

    private static func swatchShelf(_ id: String, cardCount: Int, isUpdating: Bool = false) -> Shelf<SwatchCard> {
        Shelf(
            id: id, title: id.capitalized, cards: (0..<cardCount).map { SwatchCard(id: "\(id)-\($0)") },
            isUpdating: isUpdating
        )
    }

    private func render(
        _ model: EtagereModel<SwatchCard>, size: CGSize, override: EtagerePhaseOverride = EtagerePhaseOverride(),
        name: String
    ) throws -> PixelImage {
        let image = try #require(SnapshotHarness.render(SnapshotHarness.etagere(model, override: override),
                                                        size: size, name: name))
        return try #require(PixelImage(image))
    }

    /// The rows of the Active Shelf highlight, read down a column in its leading padding, two points before the
    /// titles and cards start (where its rounded corners barely cut in).
    private func highlightRows(_ image: PixelImage, layout: EtagereLayout) throws -> [Int] {
        let rows = image.rows(column: Int(layout.leadingInset) - 2) { $0.isHighlightTint }
        #expect(rows.isOneRun, "one highlight: \(rows.first ?? -1)...\(rows.last ?? -1), \(rows.count) rows")
        return rows
    }

    @Test("T22 mode 2: the highlight sits behind the Active Shelf, on the first row and on the third")
    func cursorHighlightFollowsTheActiveRow() throws {
        let model = EtagereModel(
            shelves: (0..<4).map { Self.swatchShelf("row\($0)", cardCount: 6) },
            configuration: EtagereConfiguration(verticalMode: .cursor)
        )
        let layout = Self.layout(Self.etagereSize, configuration: model.configuration)
        let pad = layout.highlightPadding.height
        // Any override draws mode 2 without its scroll view, which ImageRenderer cannot draw.
        let first = try highlightRows(render(model, size: Self.etagereSize, name: "cursor-row0"), layout: layout)
        #expect(model.move(.nextShelf, isRepeat: false, reduceMotion: true))
        #expect(model.move(.nextShelf, isRepeat: false, reduceMotion: true))
        #expect(model.activeShelf?.id == "row2")
        let third = try highlightRows(render(model, size: Self.etagereSize, name: "cursor-row2"), layout: layout)

        // The highlight reaches `pad` above and below its row, and row i starts at topInset + i * (shelf + spacing).
        // Its corners trim a pixel at each end of the column, so the centers carry the measurements.
        let firstTop = Double(try #require(first.first))
        #expect(abs(firstTop - (layout.topInset - pad)) <= 1.5, "row 0 starts at the top inset: \(firstTop)")
        let firstCenter = try #require(first.spanCenter) + 0.5
        let thirdCenter = try #require(third.spanCenter) + 0.5
        let shelfHeight = 2 * (firstCenter - layout.topInset)
        #expect(abs(shelfHeight - layout.shelfHeight) < 16, "about one shelf tall: \(shelfHeight)")
        let expected = firstCenter + 2 * (shelfHeight + layout.metrics.shelfSpacing)
        #expect(abs(thirdCenter - expected) <= 1, "row 2's highlight at \(thirdCenter), expected \(expected)")
        #expect(abs(third.count - first.count) <= 1, "the same highlight, moved")
    }

    @Test("T22 mode 1: the highlight stays at the anchor while the shelves slide beneath it",
          arguments: EtagereVerticalAlignment.allCases)
    func ringHighlightStaysAtTheAnchor(alignment: EtagereVerticalAlignment) throws {
        let model = EtagereModel(
            shelves: ["favorites", "live", "recent"].map { Self.swatchShelf($0, cardCount: 5) },
            configuration: EtagereConfiguration(verticalAlignment: alignment)
        )
        let layout = Self.layout(Self.etagereSize, configuration: model.configuration)
        let pad = layout.highlightPadding.height
        let atRest = try highlightRows(
            render(model, size: Self.etagereSize, override: EtagerePhaseOverride(shelfPhase: 0),
                   name: "ring-highlight-\(alignment)-0"),
            layout: layout
        )
        let sliding = try highlightRows(
            render(model, size: Self.etagereSize, override: EtagerePhaseOverride(shelfPhase: -0.5),
                   name: "ring-highlight-\(alignment)-half"),
            layout: layout
        )
        #expect(atRest == sliding, "the highlight does not move with the shelves")
        let top = Double(try #require(atRest.first))
        let bottom = Double(try #require(atRest.last)) + 1
        switch alignment {
        case .top:
            #expect(abs(top - (layout.topInset - pad)) <= 1.5, "anchored at the top inset: \(top)")
        case .center:
            #expect(abs((top + bottom) / 2 - layout.size.height / 2) <= 1.5, "centered: \(top)...\(bottom)")
        case .bottom:
            let expected = layout.size.height - layout.bottomInset + pad
            #expect(abs(bottom - expected) <= 1.5, "anchored at the bottom inset: \(bottom), expected \(expected)")
        }
    }

    @Test("T10, T22 the seam bar sits in the middle of the gap after the last card")
    func seamBarInTheGap() throws {
        let model = EtagereModel(shelves: [Self.swatchShelf("swatches", cardCount: 3)])
        let layout = Self.layout(Self.shelfSize, configuration: model.configuration)
        let ring = layout.ringGeometry(model.configuration)
        let image = try render(model, size: Self.shelfSize, name: "seam-gap")
        // The bar is centered on the cards' row, as the red Active ShelfCard is.
        let red = image.rows(column: Int(ring.center(at: 0))) { $0.isClose(to: SnapshotHarness.systemRed) }
        let row = Int(try #require(red.spanCenter))
        // Leading anchor, three cards: A B C | at rest, so the bar follows C at slot 2.
        let gap = (Int(ring.trailingEdge(at: 2).rounded(.up)) + 1)..<Int(ring.leadingEdge(at: 3).rounded(.down))
        let bar = image.columns(row: row, in: gap) { $0.isDark }
        #expect(bar.isOneRun, "one bar in the gap: \(bar)")
        let center = try #require(bar.spanCenter) + 0.5
        let expected = Double(ring.seamCenter(afterSlot: 2))
        #expect(abs(center - expected) <= 1, "the bar is centered at \(center), expected \(expected)")
        #expect(bar.count <= Int(layout.metrics.seamWidth) + 2)
    }

    @Test("An updating shelf shows a quiet status after its title (Shelf.isUpdating)")
    func updatingStatusFollowsTheTitle() throws {
        func titleEnd(isUpdating: Bool) throws -> Int {
            let model = EtagereModel(shelves: [Self.swatchShelf("live", cardCount: 0, isUpdating: isUpdating)])
            let layout = Self.layout(Self.shelfSize, configuration: model.configuration)
            let image = try render(model, size: Self.shelfSize, name: "updating-\(isUpdating)")
            // The title's line, above the placeholder card.
            let titleRows = Int(layout.topInset)..<Int(layout.topInset + layout.titleHeight)
            let ink = titleRows.flatMap { image.columns(row: $0) { $0.isDark } }
            return try #require(ink.max())
        }
        let plain = try titleEnd(isUpdating: false)
        let updating = try titleEnd(isUpdating: true)
        #expect(updating > plain + 30, "the status follows the title: \(plain) -> \(updating)")
    }
}
