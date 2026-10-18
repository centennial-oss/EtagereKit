import CoreGraphics
import EtagereKit
import Foundation
import Testing

/// T23 (model part): a second app's card type, box art with integer IDs and a 0.71 aspect ratio, drives the same
/// model with no changes to EtagereKit (R4, D1). The rendering half belongs to the snapshot harness of T22.
@Suite("T23 reuse with a box-art card")
struct ReuseTests {
    private let games = ["Pinball", "Kart", "Puzzle", "Racer", "Golf"]

    private func boxes(_ names: [String], from first: Int = 100) -> [BoxArtCard] {
        names.enumerated().map { BoxArtCard(id: first + $0.offset, name: $0.element) }
    }

    @Test("T23 the box-art card keeps its own aspect ratio; video cards default to 16:9")
    func aspectRatios() {
        #expect(BoxArtCard.faceAspectRatio == 0.71)
        let videoAspect: CGFloat = 16.0 / 9.0
        #expect(PlainCard.faceAspectRatio == videoAspect)
        let metrics = EtagereResolvedMetrics.starting(.regular, containerWidth: 1280)
        #expect(metrics.reservedRingHeight(aspectRatio: BoxArtCard.faceAspectRatio)
            > metrics.reservedRingHeight(aspectRatio: PlainCard.faceAspectRatio))
        #expect(abs(metrics.cardHeight(aspectRatio: 0.71) - metrics.cardWidth / 0.71) < 1e-9)
        var configuration = EtagereConfiguration(horizontalAlignment: .center)
        configuration.cardCrossAlignment = .bottom
        #expect(configuration.cardCrossAlignment == .bottom)
    }

    @Test("T23 box art drives the same model: moves, the single selection, activation", arguments: RingAnchor.allCases)
    func modelWithBoxArt(anchor: RingAnchor) {
        let alignment = EtagereHorizontalAlignment(rawValue: anchor.rawValue) ?? .leading
        let model = EtagereModel(
            shelves: [
                Shelf(id: "owned", title: "Owned", cards: boxes(games)),
                Shelf(id: "wishlist", title: "Wishlist", cards: boxes(["Chess"], from: 900)),
                Shelf(id: "lent", title: "Lent Out", cards: [], emptyMessage: "Nothing lent")
            ],
            configuration: EtagereConfiguration(horizontalAlignment: alignment)
        )
        #expect(model.activeCard?.name == "Pinball")
        model.move(.previousCard, isRepeat: false, reduceMotion: false)
        #expect(model.activeCard?.name == "Golf")
        #expect(model.activation == .card(BoxArtCard(id: 104, name: "Golf")))
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        #expect(model.move(.nextCard, isRepeat: false, reduceMotion: true))
        #expect(model.activeCard?.id == 900)
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        #expect(model.activation == .emptyShelf(shelfID: "lent"))

        let size = CGSize(width: 200, height: 200 / BoxArtCard.faceAspectRatio)
        let rendered = (-1...7).compactMap {
            model.cardContext(shelfVirtualIndex: 0, cardVirtualIndex: $0, faceSize: size)
        }
        #expect(rendered.filter(\.isAnchored).count == 1)
        #expect(rendered.allSatisfy { !$0.isActive && $0.ringCount == 5 && $0.faceSize == size })
    }

    @Test("T23 rotate(toCard:) and replaceCards work with integer IDs")
    func ringOperationsWithIntegerIDs() {
        let shelf = ShelfState(Shelf(id: "owned", title: "Owned", cards: boxes(games)))
        shelf.rotate(toCard: 103)
        #expect(shelf.anchoredCard?.name == "Racer")
        #expect(shelf.rotation == -2)
        shelf.replaceCards(boxes(["Racer", "Kart"], from: 103))
        #expect(shelf.anchoredCard?.id == 103)
        #expect(RingMath.floorDiv(shelf.rotation, 2) == -1, "the lap survives the refresh")
    }

    @Test("T23 the saved position works with integer IDs")
    func positionWithIntegerIDs() throws {
        let model = EtagereModel(shelves: [Shelf(id: "owned", title: "Owned", cards: boxes(games))])
        model.move(.nextCard, isRepeat: false, reduceMotion: true)
        model.move(.nextCard, isRepeat: true, repeatInterval: 0.07, reduceMotion: true)
        let data = try JSONEncoder().encode(model.position)
        let decoded = try JSONDecoder().decode(EtagerePosition<Int>.self, from: data)
        let restored = EtagereModel(shelves: [Shelf(id: "owned", title: "Owned", cards: boxes(games))])
        restored.restore(decoded)
        #expect(restored.activeCard?.name == "Puzzle")
        #expect(restored.activeCard?.accessibilityTitle == "Puzzle, game")
    }
}
