import CoreGraphics
import EtagereKit
import Foundation
import Testing

@Suite("EtagereModel content: replaceShelves (D8), empty shelves (Q7) and the saved position (Q8)")
struct EtagereModelContentTests {
    private func shelves(_ spec: [(String, Int)]) -> [Shelf<PlainCard>] {
        spec.map { Fixture.shelf($0.0, cardCount: $0.1) }
    }

    // MARK: replaceShelves

    @Test("replaceShelves with the same IDs keeps every state, rotation and anchor, and takes new titles")
    func replaceSameIDs() {
        let model = EtagereModel(shelves: shelves([("fav", 4), ("live", 8)]))
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        model.move(.nextCard, isRepeat: false, reduceMotion: true)
        let states = model.shelves
        var updated = shelves([("fav", 4), ("live", 8)])
        updated[1].title = "Live TV"
        model.replaceShelves(updated)
        #expect(zip(model.shelves, states).allSatisfy { $0 === $1 })
        #expect(model.shelfRotation == 1)
        #expect(model.activeCard?.id == "live-B")
        #expect(model.activeShelf?.title == "Live TV")
        #expect(model.shelfJumpGeneration == 0, "the same shelf IDs: nothing jumps")
        #expect(model.shelves.allSatisfy { $0.jumpGeneration == 0 })
    }

    @Test("replaceShelves keeps the Active Shelf and its lap through a reorder",
          arguments: EtagereVerticalMode.allCases)
    func replaceReorder(mode: EtagereVerticalMode) {
        let model = EtagereModel(
            shelves: shelves([("a", 3), ("b", 3), ("c", 3)]), configuration: EtagereConfiguration(verticalMode: mode)
        )
        model.activateShelf(id: "b")
        if mode == .ring {
            for _ in 0..<3 { model.move(.nextShelf, isRepeat: false, reduceMotion: true) }
        }
        let lap = RingMath.floorDiv(model.shelfRotation, 3)
        model.shelf(id: "c")?.rotate(by: 2)
        let jumps = model.shelfJumpGeneration
        model.replaceShelves(shelves([("c", 3), ("new", 2), ("a", 3), ("b", 3)]))
        #expect(model.activeShelf?.id == "b")
        #expect(RingMath.floorDiv(model.shelfRotation, 4) == lap)
        #expect(model.shelfRotation == lap * 4 + 3)
        #expect(model.shelf(id: "c")?.anchoredCard?.id == "c-C", "each shelf keeps its anchored card")
        #expect(model.shelf(id: "c")?.jumpGeneration == 0, "its cards did not change")
        #expect(model.shelf(id: "new")?.rotation == 0)
        #expect(model.settledShelfRotation == model.shelfRotation)
        #expect(model.shelfJumpGeneration == jumps + 1, "the Active Shelf stays, but the shelves crossfade")
        if mode == .cursor { #expect((0..<4).contains(model.shelfRotation)) }
    }

    @Test("replaceShelves: when the Active Shelf is gone, the shelf now at its old index (clamped) is active")
    func replaceRemovesActive() {
        let model = EtagereModel(shelves: shelves([("a", 1), ("b", 1), ("c", 1)]))
        model.activateShelf(id: "b")
        let jumps = model.shelfJumpGeneration
        model.replaceShelves(shelves([("a", 1), ("c", 1)]))
        #expect(model.activeShelf?.id == "c")
        #expect(model.shelfJumpGeneration == jumps + 1)
        model.replaceShelves(shelves([("a", 1)]))
        #expect(model.activeShelf?.id == "a")
        model.replaceShelves([])
        #expect(model.activeShelf == nil)
        #expect(model.shelfRotation == 0)
        model.replaceShelves(shelves([("x", 2)]))
        #expect(model.activeCard?.id == "x-A")
        #expect(model.shelfJumpGeneration == jumps + 4, "every change to the shelf IDs crossfades")
    }

    @Test("replaceShelves passes card changes to the kept shelves (behavior §1.10)")
    func replaceCardsThroughShelves() {
        let model = EtagereModel(shelves: shelves([("a", 4)]))
        model.move(.nextCard, isRepeat: false, reduceMotion: true)
        model.replaceShelves([Shelf(id: "a", title: "A", cards: ["a-D", "a-B", "a-Z"].map { PlainCard($0) })])
        #expect(model.activeCard?.id == "a-B")
        model.replaceShelves([Shelf(id: "a", title: "A", cards: ["a-D", "a-Z"].map { PlainCard($0) })])
        #expect(model.activeCard?.id == "a-Z")
    }

    // MARK: Q7: empty shelves

    @Test("Q7 empty shelves stay, are navigable, and activate as an empty shelf")
    func emptyShelves() {
        let model = EtagereModel(shelves: [
            Fixture.shelf("fav", cardCount: 2),
            Fixture.shelf("recordings", cardCount: 0, emptyMessage: "Connect a DVR source in Settings"),
            Fixture.shelf("live", cardCount: 3)
        ])
        #expect(model.shelves.count == 3)
        #expect(model.activation == .card(PlainCard("fav-A")))
        #expect(model.move(.nextShelf, isRepeat: false, reduceMotion: true))
        #expect(model.activeShelf?.id == "recordings")
        #expect(model.activeShelf?.isEmpty == true)
        #expect(model.activeShelf?.emptyMessage == "Connect a DVR source in Settings")
        #expect(model.activeCard == nil)
        #expect(model.activation == .emptyShelf(shelfID: "recordings"))
        #expect(model.move(.nextCard, isRepeat: false, reduceMotion: true))
        #expect(model.move(.previousCard, isRepeat: false, reduceMotion: false))
        #expect(model.activeShelf?.rotation == 0)
        let size = CGSize(width: 200, height: 112.5)
        #expect(model.cardContext(shelfVirtualIndex: 1, cardVirtualIndex: 0, faceSize: size) == nil)
        #expect(model.move(.nextShelf, isRepeat: false, reduceMotion: true))
        #expect(model.activeCard?.id == "live-A")
    }

    @Test("Q7 in mode 2 an empty shelf is a cursor stop and still consumes left and right")
    func emptyShelfInCursorMode() {
        let model = EtagereModel(
            shelves: [Fixture.shelf("empty", cardCount: 0), Fixture.shelf("live", cardCount: 3)],
            configuration: EtagereConfiguration(verticalMode: .cursor)
        )
        #expect(model.activation == .emptyShelf(shelfID: "empty"))
        #expect(model.move(.nextCard, isRepeat: false, reduceMotion: true))
        #expect(!model.move(.previousShelf, isRepeat: false, reduceMotion: true))
        #expect(model.move(.nextShelf, isRepeat: false, reduceMotion: true))
        #expect(model.activation == .card(PlainCard("live-A")))
    }

    @Test("Q7 a shelf that empties keeps its place, and fills again from its first card")
    func shelfEmptiesAndRefills() {
        let model = EtagereModel(shelves: shelves([("a", 3), ("b", 3)]))
        model.move(.nextCard, isRepeat: false, reduceMotion: true)
        model.replaceShelves([Shelf(id: "a", title: "A", cards: []), Fixture.shelf("b", cardCount: 3)])
        #expect(model.activeShelf?.id == "a")
        #expect(model.activeCard == nil)
        model.replaceShelves(shelves([("a", 3), ("b", 3)]))
        #expect(model.activeCard?.id == "a-A")
    }

    // MARK: Updating status

    @Test("A shelf's updating status comes from the host and changes without moving anything")
    func updatingStatus() {
        let live = Fixture.shelf("live", cardCount: 3)
        var updating = live
        updating.isUpdating = true
        #expect(live.isUpdating == false, "off by default")
        let model = EtagereModel(shelves: [updating, Fixture.shelf("fav", cardCount: 2)])
        let state = model.shelves[0]
        #expect(state.isUpdating)
        model.move(.nextCard, isRepeat: false, reduceMotion: true)
        model.replaceShelves([live, Fixture.shelf("fav", cardCount: 2)])
        #expect(model.shelves[0] === state)
        #expect(!state.isUpdating)
        #expect(state.anchoredCard?.id == "live-B", "the selection stays")
        #expect(state.jumpGeneration == 0 && model.shelfJumpGeneration == 0, "nothing jumps or crossfades")
    }

    // MARK: Q8: position

    @Test("Q8 the position holds the Active Shelf and each non-empty shelf's anchored card")
    func positionSnapshot() {
        let model = EtagereModel(shelves: shelves([("a", 3), ("empty", 0), ("c", 5)]))
        model.move(.previousShelf, isRepeat: false, reduceMotion: true)
        model.move(.previousCard, isRepeat: false, reduceMotion: true)
        model.shelf(id: "a")?.rotate(by: 1)
        let position = model.position
        #expect(position.activeShelfID == "c")
        #expect(position.anchoredCardIDs == ["a": "a-B", "c": "c-E"])
        #expect(EtagereModel<PlainCard>(shelves: []).position == EtagerePosition())
    }

    @Test("Q8 restoring a position reproduces the selection", arguments: EtagereVerticalMode.allCases)
    func restoreRoundTrip(mode: EtagereVerticalMode) {
        let configuration = EtagereConfiguration(verticalMode: mode)
        let spec = [("a", 3), ("b", 8), ("c", 2)]
        let original = EtagereModel(shelves: shelves(spec), configuration: configuration)
        original.move(.nextCard, isRepeat: false, reduceMotion: true)
        original.move(.nextShelf, isRepeat: false, reduceMotion: true)
        original.move(.previousCard, isRepeat: false, reduceMotion: true)
        original.move(.nextShelf, isRepeat: false, reduceMotion: true)

        let restored = EtagereModel(shelves: shelves(spec), configuration: configuration)
        restored.restore(original.position)
        #expect(restored.position == original.position)
        #expect(restored.activeCard == original.activeCard)
        #expect(restored.activeShelf?.id == "c")
        #expect(restored.shelves.allSatisfy { $0.isSettled })
        #expect(restored.settledShelfRotation == restored.shelfRotation)
        if mode == .cursor { #expect(restored.shelfRotation == 2) }
    }

    @Test("Q8 restore skips missing shelves and cards")
    func restoreToleratesMissing() {
        let model = EtagereModel(shelves: shelves([("a", 3), ("b", 3), ("c", 3)]))
        model.activateShelf(id: "b")
        let position = EtagerePosition(
            activeShelfID: "gone", anchoredCardIDs: ["a": "a-C", "b": "b-missing", "gone": "gone-A"]
        )
        model.restore(position)
        #expect(model.activeShelf?.id == "b", "a missing active shelf leaves the current one active")
        #expect(model.shelf(id: "a")?.anchoredCard?.id == "a-C")
        #expect(model.shelf(id: "b")?.anchoredCard?.id == "b-A")
        #expect(model.shelf(id: "b")?.jumpGeneration == 0)
        #expect(model.shelf(id: "c")?.anchoredCard?.id == "c-A")

        model.restore(EtagerePosition(activeShelfID: "c"))
        #expect(model.activeShelf?.id == "c")
        model.restore(EtagerePosition())
        #expect(model.activeShelf?.id == "c")
    }

    @Test("Q8 the position is Codable for the host to persist")
    func positionCodable() throws {
        let position = EtagerePosition(activeShelfID: "live", anchoredCardIDs: ["live": "tvch:Antenna:9.1"])
        let data = try JSONEncoder().encode(position)
        #expect(try JSONDecoder().decode(EtagerePosition<String>.self, from: data) == position)
        let empty = try JSONDecoder().decode(EtagerePosition<String>.self, from: Data(#"{"anchoredCardIDs":{}}"#.utf8))
        #expect(empty == EtagerePosition())
    }
}
