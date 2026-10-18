import CoreGraphics
@_spi(EtagereDebug) import EtagereKit
import SwiftUI
import Testing

/// T22 (behavior §7.3): every frame renders through the public `Etagere`, at fixed fractional phases through the
/// `phaseOverride` hook. The assertions are a non-nil image of the expected size; set `ETAGERE_SNAPSHOT_DIR` to
/// look at the frames. A few pixel checks pin down what a smoke test cannot: the Anchor Spot and RTL mirroring
/// here, and the highlights in both modes, the seam bar and the shelf status in `SnapshotPixelTests`.
@MainActor
@Suite("T22 snapshot smoke tests (ImageRenderer)")
struct SnapshotSmokeTests {
    private static let shelfSize = CGSize(width: 1280, height: 340)
    private static let etagereSize = CGSize(width: 1280, height: 900)
    private static let cardPhases = [0, 0.25, 0.5, 0.75, 1]

    @Test("T22 one shelf per anchor at phases 0, 0.25, 0.5, 0.75 and 1", arguments: EtagereHorizontalAlignment.allCases)
    func shelfPhases(alignment: EtagereHorizontalAlignment) {
        let model = EtagereModel(
            shelves: [Fixture.shelf("live", cardCount: 8)],
            configuration: EtagereConfiguration(horizontalAlignment: alignment)
        )
        for phase in Self.cardPhases {
            let image = SnapshotHarness.render(
                SnapshotHarness.etagere(model, override: EtagerePhaseOverride(cardPhase: phase)),
                size: Self.shelfSize, name: "shelf-\(alignment)-\(phase)"
            )
            expectSize(image, Self.shelfSize)
        }
    }

    @Test("T22 short rings, a wrap backward and a single card render", arguments: [1, 3])
    func shortRings(cardCount: Int) {
        let model = EtagereModel(shelves: [Fixture.shelf("short", cardCount: cardCount)])
        for phase in [0, -0.5, -1] {
            let image = SnapshotHarness.render(
                SnapshotHarness.etagere(model, override: EtagerePhaseOverride(cardPhase: phase)),
                size: Self.shelfSize, name: "short-\(cardCount)-\(phase)"
            )
            expectSize(image, Self.shelfSize)
        }
    }

    @Test("T22 the vertical ShelvesRing at phases 0, -0.5 and -1", arguments: EtagereVerticalAlignment.allCases)
    func verticalRing(alignment: EtagereVerticalAlignment) {
        let model = EtagereModel(
            shelves: [
                Fixture.shelf("favorites", cardCount: 8), Fixture.shelf("live", cardCount: 12),
                Fixture.shelf("recent", cardCount: 3)
            ],
            configuration: EtagereConfiguration(verticalAlignment: alignment)
        )
        for phase in [0, -0.5, -1] {
            let image = SnapshotHarness.render(
                SnapshotHarness.etagere(model, override: EtagerePhaseOverride(shelfPhase: phase)),
                size: Self.etagereSize, name: "vertical-\(alignment)-\(phase)"
            )
            expectSize(image, Self.etagereSize)
        }
    }

    @Test("T22 an empty shelf renders its placeholder card in both modes", arguments: EtagereVerticalMode.allCases)
    func emptyShelf(mode: EtagereVerticalMode) {
        let model = EtagereModel(
            shelves: [
                Shelf(id: "recordings", title: "Recent Recordings", cards: [], emptyMessage: "Add a DVR in Settings"),
                Fixture.shelf("live", cardCount: 4)
            ],
            configuration: EtagereConfiguration(verticalMode: mode)
        )
        let image = SnapshotHarness.render(
            SnapshotHarness.etagere(model, override: EtagerePhaseOverride()), size: Self.etagereSize,
            name: "empty-\(mode)"
        )
        expectSize(image, Self.etagereSize)
    }

    @Test("T23 a box-art card renders through the same harness, standing on a common baseline")
    func boxArt() {
        var configuration = EtagereConfiguration(horizontalAlignment: .center)
        configuration.cardCrossAlignment = .bottom
        let games = ["Pinball", "Kart", "Puzzle", "Racer", "Golf"].enumerated().map {
            BoxArtCard(id: 100 + $0.offset, name: $0.element)
        }
        let model = EtagereModel(
            shelves: [Shelf(id: "owned", title: "Owned", cards: games)], configuration: configuration
        )
        let size = CGSize(width: 1280, height: 600)
        for phase in [0, 0.5] {
            let image = SnapshotHarness.render(
                SnapshotHarness.etagere(model, override: EtagerePhaseOverride(cardPhase: phase)),
                size: size, name: "boxart-\(phase)"
            )
            expectSize(image, size)
        }
    }

    @Test("The Active ShelfCard sits at the leading Anchor Spot, mirrored in right-to-left layouts (behavior §1.11)",
          arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func anchorSpotMirrors(direction: LayoutDirection) throws {
        let model = EtagereModel(shelves: [Shelf(id: "swatches", title: "Swatches", cards: (0..<6).map {
            SwatchCard(id: "card\($0)")
        })])
        let view = SnapshotHarness.etagere(model).environment(\.layoutDirection, direction)
        let image = try #require(SnapshotHarness.render(view, size: Self.shelfSize, name: "swatch-\(direction)"))
        let red = SnapshotHarness.columns(in: image, row: image.height / 3, matching: SnapshotHarness.systemRed)
        let first = try #require(red.first)
        let last = try #require(red.last)
        let center = Double(first + last) / 2
        let width = Double(image.width)
        if direction == .leftToRight {
            #expect(center < width / 3, "the anchor is at the leading (left) edge")
        } else {
            #expect(center > width * 2 / 3, "the anchor is at the leading (right) edge")
        }
    }

    @Test("Snapshot rendering honours the card phase: half way, the next card has grown half way")
    func halfWayPhase() throws {
        let model = EtagereModel(shelves: [Shelf(id: "swatches", title: "Swatches", cards: (0..<6).map {
            SwatchCard(id: "card\($0)")
        })])
        let atRest = try #require(SnapshotHarness.render(
            SnapshotHarness.etagere(model, override: EtagerePhaseOverride(cardPhase: 0)),
            size: Self.shelfSize, name: "swatch-rest"
        ))
        let row = atRest.height / 3
        let restRed = SnapshotHarness.columns(in: atRest, row: row, matching: SnapshotHarness.systemRed)
        let restGray = SnapshotHarness.columns(in: atRest, row: row, matching: SnapshotHarness.idleGray)
        #expect(!restRed.isEmpty)
        #expect(!restGray.isEmpty)
        let halfWay = try #require(SnapshotHarness.render(
            SnapshotHarness.etagere(model, override: EtagerePhaseOverride(cardPhase: 0.5)),
            size: Self.shelfSize, name: "swatch-half"
        ))
        // At a fractional phase the anchored copy is the rounded phase, so card 1 is the red one.
        let halfRed = SnapshotHarness.columns(in: halfWay, row: row, matching: SnapshotHarness.systemRed)
        let restWidth = try #require(restRed.last) - (try #require(restRed.first))
        let halfWidth = try #require(halfRed.last) - (try #require(halfRed.first))
        #expect(halfWidth < restWidth, "half way to the anchor, the incoming card is smaller than at rest")
    }

    private func expectSize(_ image: CGImage?, _ size: CGSize, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(image != nil, sourceLocation: sourceLocation)
        #expect(image?.width == Int(size.width), sourceLocation: sourceLocation)
        #expect(image?.height == Int(size.height), sourceLocation: sourceLocation)
    }
}
