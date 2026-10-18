import CoreGraphics
import EtagereKit
import Testing

@Suite("EtagereModel: the single selection and vertical modes (R9, R21-R28)")
struct EtagereModelTests {
    private static let faceSize = CGSize(width: 300, height: 168.75)

    /// Every rendered card copy on every rendered shelf copy, including ghost copies in flight.
    private func renderedContexts(_ model: EtagereModel<PlainCard>) -> [(shelfID: String, context: ShelfCardContext)] {
        let reach = model.shelves.count + 1
        let shelfRange = (model.shelfRotation - reach)...(model.shelfRotation + reach)
        return shelfRange.flatMap { shelfIndex in
            let shelf = model.shelves[RingMath.floorMod(shelfIndex, model.shelves.count)]
            return shelf.renderSlots(rest: -3...6).compactMap { slot in
                model.cardContext(shelfVirtualIndex: shelfIndex, cardVirtualIndex: slot.virtualIndex,
                                  faceSize: Self.faceSize)
                    .map { (shelf.id, $0) }
            }
        }
    }

    // MARK: T15

    @Test("T15 exactly one card is the Active ShelfCard", arguments: EtagereVerticalMode.allCases)
    func singleSelection(mode: EtagereVerticalMode) {
        let model = Fixture.model(cardCounts: [3, 8, 1, 40, 2], configuration: EtagereConfiguration(verticalMode: mode))
        let moves: [EtagereMove] = [.nextCard, .nextShelf, .previousCard, .previousCard, .nextShelf, .nextShelf,
                                    .nextCard, .nextShelf, .previousShelf, .nextShelf, .nextShelf, .previousCard]
        for move in moves {
            model.move(move, isRepeat: false, reduceMotion: false)
            // Leave a card ring in flight on another shelf too, so ghost copies are rendered.
            model.shelves[0].rotate(by: -1)
            let active = renderedContexts(model).filter { $0.context.isActive }
            #expect(active.count == 1, "after \(move)")
            #expect(active.first?.shelfID == model.activeShelf?.id)
            #expect(active.first?.context.ringIndex == model.activeShelf?.anchoredIndex)
            #expect(model.activeCard == model.activeShelf?.anchoredCard)
            #expect(model.activeCard != nil)
        }
    }

    @Test("T15 anchored cards on inactive shelves are not active")
    func inactiveAnchors() {
        let model = Fixture.model(cardCounts: [3, 4, 5])
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        let anchored = renderedContexts(model).filter { $0.context.isAnchored }
        #expect(anchored.contains { $0.shelfID == "s0" && !$0.context.isActive && !$0.context.isShelfActive })
        #expect(anchored.filter(\.context.isActive).map(\.shelfID) == ["s1"])
        #expect(model.activeCard?.id == "s1-A")
    }

    // MARK: T16

    @Test("T16 the default vertical mode is the ring (mode 1)")
    func defaultMode() {
        #expect(EtagereConfiguration().verticalMode == .ring)
        #expect(Fixture.model(cardCounts: [3]).configuration.verticalMode == .ring)
    }

    @Test("T16 mode 1: vertical moves are always consumed and wrap", arguments: [1, 2, 3, 5])
    func ringModeWraps(shelfCount: Int) {
        let model = Fixture.model(cardCounts: Array(repeating: 3, count: shelfCount))
        for press in 1...(shelfCount + 1) {
            #expect(model.move(.nextShelf, isRepeat: false, reduceMotion: true))
            #expect(model.activeShelfIndex == (shelfCount > 1 ? press % shelfCount : 0))
        }
        let ring = Fixture.model(cardCounts: Array(repeating: 3, count: shelfCount))
        #expect(ring.move(.previousShelf, isRepeat: false, reduceMotion: true))
        #expect(ring.activeShelfIndex == shelfCount - 1)
        #expect(ring.shelfRotation == (shelfCount > 1 ? -1 : 0), "unbounded, so the wrapping shelf keeps its lap")
    }

    @Test("T16 mode 1: left and right are consumed even for N <= 1", arguments: [0, 1, 2, 3, 4, 8, 40])
    func ringModeConsumesHorizontal(size: Int) {
        let model = Fixture.model(cardCounts: [size])
        #expect(model.move(.nextCard, isRepeat: false, reduceMotion: true))
        #expect(model.move(.previousCard, isRepeat: true, reduceMotion: true))
        #expect(model.move(.previousCard, isRepeat: false, reduceMotion: true))
        let shelf = model.shelves[0]
        #expect(shelf.rotation == (size > 1 ? -1 : 0))
    }

    @Test("T16 mode 1 with no shelves still consumes every move")
    func ringModeWithoutShelves() {
        let model = Fixture.model(cardCounts: [])
        for move in EtagereMove.allCases {
            #expect(model.move(move, isRepeat: false, reduceMotion: false))
        }
        #expect(model.activeShelf == nil)
        #expect(model.activeCard == nil)
        #expect(model.activation == nil)
    }

    @Test("T16 mode 2: moves past the top or bottom are not consumed and do not wrap", arguments: [1, 2, 3, 5])
    func cursorModeEdges(shelfCount: Int) {
        let model = Fixture.model(
            cardCounts: Array(repeating: 3, count: shelfCount),
            configuration: EtagereConfiguration(verticalMode: .cursor)
        )
        #expect(!model.move(.previousShelf, isRepeat: false, reduceMotion: true))
        #expect(model.shelfRotation == 0)
        for index in 1..<max(shelfCount, 1) {
            #expect(model.move(.nextShelf, isRepeat: false, reduceMotion: false))
            #expect(model.shelfRotation == index)
        }
        #expect(!model.move(.nextShelf, isRepeat: false, reduceMotion: true))
        #expect(!model.move(.nextShelf, isRepeat: true, reduceMotion: false))
        #expect(model.shelfRotation == shelfCount - 1)
        // Horizontal moves on the active shelf are still consumed.
        #expect(model.move(.nextCard, isRepeat: false, reduceMotion: true))
        #expect(model.activeCard?.id == "s\(shelfCount - 1)-B")
    }

    @Test("T16 mode 2 with no shelves consumes nothing")
    func cursorModeWithoutShelves() {
        let model = Fixture.model(cardCounts: [], configuration: EtagereConfiguration(verticalMode: .cursor))
        for move in EtagereMove.allCases {
            #expect(!model.move(move, isRepeat: false, reduceMotion: true))
        }
    }

    @Test("Switching to mode 2 brings the rotation into the shelf indices and keeps the Active Shelf")
    func modeSwitch() {
        let model = Fixture.model(cardCounts: [2, 2, 2])
        for _ in 0..<4 { model.move(.previousShelf, isRepeat: false, reduceMotion: true) }
        #expect(model.shelfRotation == -4)
        let active = model.activeShelf?.id
        let jumps = model.shelfJumpGeneration
        model.configuration.verticalMode = .cursor
        #expect(model.shelfRotation == 2)
        #expect(model.activeShelf?.id == active)
        #expect(model.shelfJumpGeneration == jumps + 1)
        model.configuration.idleDim = 0.2
        #expect(model.shelfJumpGeneration == jumps + 1)
        model.configuration.verticalMode = .ring
        #expect(model.shelfRotation == 2)
    }

    // MARK: activateShelf

    @Test("activateShelf: mode 1 rotates the shortest way, ties forward")
    func activateShelfRing() {
        let model = Fixture.model(cardCounts: [1, 1, 1, 1])
        #expect(model.activateShelf(id: "s3"))
        #expect(model.shelfRotation == -1)
        #expect(model.activateShelf(id: "s1"))
        #expect(model.shelfRotation == 1, "s3 to s1 is a tie in a ring of 4: forward")
        #expect(model.activateShelf(id: "s1"))
        #expect(model.shelfRotation == 1)
        #expect(!model.activateShelf(id: "missing"))
        #expect(model.activeShelf?.id == "s1")
    }

    @Test("activateShelf: mode 2 moves the cursor")
    func activateShelfCursor() {
        let model = Fixture.model(cardCounts: [1, 1, 1, 1], configuration: EtagereConfiguration(verticalMode: .cursor))
        #expect(model.activateShelf(id: "s3", animation: model.configuration.highlightAnimation))
        #expect(model.shelfRotation == 3)
        #expect(model.activateShelf(id: "s0"))
        #expect(model.shelfRotation == 0)
        #expect(model.settledShelfRotation == 0)
    }

    @Test("Shelf lookup and per-shelf rings stay independent (behavior §1.9)")
    func shelvesKeepTheirRotation() {
        let model = Fixture.model(cardCounts: [4, 4])
        model.move(.nextCard, isRepeat: false, reduceMotion: true)
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        model.move(.previousCard, isRepeat: false, reduceMotion: true)
        model.move(.previousShelf, isRepeat: false, reduceMotion: true)
        #expect(model.activeCard?.id == "s0-B")
        #expect(model.shelf(id: "s1")?.anchoredCard?.id == "s1-D")
        #expect(model.shelf(id: "nope") == nil)
    }

    @Test("Duplicate shelf IDs keep only their first occurrence")
    func duplicateShelves() {
        let model = EtagereModel(shelves: [
            Fixture.shelf("a", cardCount: 1), Fixture.shelf("b", cardCount: 2), Fixture.shelf("a", cardCount: 3)
        ])
        #expect(model.shelves.map(\.id) == ["a", "b"])
        #expect(model.shelves[0].cards.count == 1)
    }
}
