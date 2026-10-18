import CoreGraphics
import EtagereKit
import Testing

@Suite("ShelfState: rotation, settle tokens and content changes (etagere.md §4.2, behavior §1.10)")
struct ShelfStateTests {
    private func state(_ ids: [String]) -> ShelfState<PlainCard> {
        ShelfState(Shelf(id: "shelf", title: "Shelf", cards: ids.map { PlainCard($0) }))
    }

    // MARK: T11

    @Test("T11 rotate(by:) moves the anchored index by floorMod", arguments: Fixture.ringSizes)
    func rotateBy(size: Int) {
        let shelf = ShelfState(Shelf(id: "shelf", title: "Shelf", cards: Fixture.cards(size)))
        var total = 0
        for delta in [1, 1, -1, -3, 5, 41, -100] {
            let token = shelf.rotate(by: delta)
            if size > 1 {
                total += delta
                #expect(token != ShelfState<PlainCard>.noOpToken)
            } else {
                #expect(token == ShelfState<PlainCard>.noOpToken)
            }
            #expect(shelf.rotation == total)
            #expect(shelf.anchoredIndex == RingMath.floorMod(total, size))
            #expect(shelf.anchoredCard == shelf.cards[RingMath.floorMod(total, size)])
        }
    }

    @Test("T11 an empty shelf never rotates and has no anchored card")
    func emptyShelfRotation() {
        let shelf = state([])
        #expect(shelf.rotate(by: 1) == ShelfState<PlainCard>.noOpToken)
        #expect(shelf.rotation == 0)
        #expect(shelf.anchoredIndex == nil)
        #expect(shelf.anchoredCard == nil)
        #expect(shelf.isEmpty)
        #expect(shelf.renderSlots(rest: 0...3).isEmpty)
    }

    // MARK: T12

    @Test("T12 rotate(toCard:) takes the shortest way; ties go forward", arguments: [2, 3, 4, 8, 40])
    func rotateToCard(size: Int) {
        let shelf = ShelfState(Shelf(id: "shelf", title: "Shelf", cards: Fixture.cards(size)))
        shelf.rotate(by: -2 * size + 1)
        for target in 0..<size {
            let before = shelf.rotation
            let origin = shelf.anchoredIndex ?? 0
            shelf.rotate(toCard: shelf.cards[target].id)
            let delta = shelf.rotation - before
            #expect(shelf.anchoredIndex == target)
            #expect(abs(delta) <= size / 2)
            let forward = RingMath.floorMod(target - origin, size)
            if size.isMultiple(of: 2), forward == size / 2 {
                #expect(delta == size / 2, "a tie goes forward")
            }
        }
    }

    @Test("T12 rotate(toCard:) is a no-op for a missing or already anchored card")
    func rotateToCardNoOps() {
        let shelf = state(["A", "B", "C"])
        #expect(shelf.rotate(toCard: "A") == ShelfState<PlainCard>.noOpToken)
        #expect(shelf.rotate(toCard: "Z") == ShelfState<PlainCard>.noOpToken)
        #expect(shelf.rotation == 0)
        shelf.rotate(toCard: "C")
        #expect(shelf.rotation == -1)
    }

    // MARK: T13

    @Test("T13 the latest settle token settles; an older one shrinks the window only behind the newer flights")
    func settleTokens() {
        let shelf = state(["A", "B", "C", "D"])
        let first = shelf.rotate(by: 1)
        let second = shelf.rotate(by: 1)
        #expect(shelf.rotation == 2)
        #expect(shelf.settledRotation == 0)
        #expect(shelf.rotationsInFlight == 0...2)
        #expect(!shelf.isSettled)
        shelf.settle(first)
        #expect(shelf.settledRotation == 1, "the first flight is over; the second one stays rendered")
        #expect(shelf.rotationsInFlight == 1...2)
        #expect(!shelf.isSettled)
        shelf.settle(first)
        shelf.settle(ShelfState<PlainCard>.noOpToken)
        #expect(shelf.rotationsInFlight == 1...2, "a repeated or no-op token changes nothing")
        shelf.settle(second)
        #expect(shelf.settledRotation == 2)
        #expect(shelf.isSettled)
        // A no-op move does not invalidate a pending token.
        let third = shelf.rotate(by: -1)
        shelf.rotate(toCard: "B")
        shelf.settle(third)
        #expect(shelf.settledRotation == 1)
        #expect(shelf.isSettled)
    }

    @Test("T13 a stale token never undoes newer state: the latest settles all, and a jump forgets every flight")
    func staleTokens() {
        let shelf = state(["A", "B", "C", "D", "E", "F"])
        let first = shelf.rotate(by: 1)
        let second = shelf.rotate(by: 1)
        let third = shelf.rotate(by: 1)
        shelf.settle(second)
        #expect(shelf.rotationsInFlight == 0...3, "the first flight still runs, so nothing behind it is dropped")
        shelf.settle(third)
        #expect(shelf.isSettled, "the latest animation ending settles the ring")
        shelf.settle(first)
        #expect(shelf.rotation == 3 && shelf.isSettled)

        let before = shelf.rotate(by: 2)
        #expect(shelf.jump(toCard: "A"))
        #expect(shelf.rotation == 0 && shelf.isSettled)
        let after = shelf.rotate(by: -1)
        shelf.settle(before)
        #expect(shelf.rotationsInFlight == -1...0, "a flight from before the jump is forgotten")
        shelf.settle(after)
        #expect(shelf.isSettled)
    }

    // MARK: T14

    @Test("T14 the same IDs are a no-op for the rotation; changed contents are taken")
    func replaceWithSameIDs() {
        let shelf = state(["A", "B", "C", "D"])
        let token = shelf.rotate(by: 6)
        shelf.replaceCards(["A", "B", "C", "D"].map { PlainCard($0) })
        #expect(shelf.rotation == 6)
        #expect(shelf.settledRotation == 0)
        shelf.settle(token)
        #expect(shelf.settledRotation == 6, "the pending animation's token is still valid")
        shelf.replaceCards([PlainCard("A"), PlainCard("B"), PlainCard("C", title: "Renamed"), PlainCard("D")])
        #expect(shelf.rotation == 6)
        #expect(shelf.anchoredCard?.title == "Renamed")
        #expect(shelf.jumpGeneration == 0)
    }

    @Test("T14 a reorder keeps the anchored card and its lap, and crossfades the ring (behavior §1.8)")
    func replaceReorder() {
        let shelf = state(["A", "B", "C", "D"])
        shelf.rotate(by: 9)
        #expect(shelf.anchoredCard?.id == "B")
        #expect(RingMath.floorDiv(shelf.rotation, 4) == 2)
        shelf.replaceCards(["D", "C", "B", "A"].map { PlainCard($0) })
        #expect(shelf.anchoredCard?.id == "B")
        #expect(shelf.rotation == 10)
        #expect(shelf.settledRotation == 10)
        #expect(shelf.jumpGeneration == 1, "the neighbours changed slots, so the ring crossfades")
        shelf.replaceCards(["X", "D", "C", "B", "A", "Y"].map { PlainCard($0) })
        #expect(shelf.anchoredCard?.id == "B")
        #expect(RingMath.floorDiv(shelf.rotation, 6) == 2)
        #expect(shelf.isSettled)
        #expect(shelf.jumpGeneration == 2, "an insert is a reload too")
    }

    @Test("T14 every change to the card IDs crossfades the ring; new contents under the same IDs do not")
    func replaceCrossfades() {
        let shelf = state([])
        shelf.replaceCards(["A", "B"].map { PlainCard($0) })
        #expect(shelf.jumpGeneration == 1, "the placeholder gives way to cards")
        shelf.replaceCards(["A", "B", "C"].map { PlainCard($0) })
        #expect(shelf.jumpGeneration == 2, "an append changes the ring's last card and its seam")
        shelf.replaceCards([PlainCard("A", title: "Renamed"), PlainCard("B"), PlainCard("C")])
        #expect(shelf.jumpGeneration == 2)
        shelf.replaceCards([PlainCard("A", title: "Renamed"), PlainCard("B"), PlainCard("C")])
        #expect(shelf.jumpGeneration == 2)
        shelf.replaceCards([])
        #expect(shelf.jumpGeneration == 3, "the cards give way to the placeholder")
    }

    @Test("T14 a reorder on a negative lap keeps that lap")
    func replaceReorderNegativeLap() {
        let shelf = state(["A", "B", "C", "D"])
        shelf.rotate(by: -3)
        #expect(shelf.anchoredCard?.id == "B")
        shelf.replaceCards(["B", "A", "C"].map { PlainCard($0) })
        #expect(shelf.anchoredCard?.id == "B")
        #expect(shelf.rotation == -3)
        #expect(RingMath.floorDiv(shelf.rotation, 3) == -1)
    }

    @Test("T14 removing the anchored card anchors the card now at its old index", arguments: [
        (1, ["A", "C", "D"], "C"), (3, ["A", "B", "C"], "C"), (3, ["B"], "B"), (0, ["B", "C", "D"], "B")
    ])
    func replaceRemoval(anchoredIndex: Int, newIDs: [String], expected: String) {
        let shelf = state(["A", "B", "C", "D"])
        shelf.rotate(by: 8 + anchoredIndex)
        shelf.replaceCards(newIDs.map { PlainCard($0) })
        #expect(shelf.anchoredCard?.id == expected)
        #expect(RingMath.floorDiv(shelf.rotation, newIDs.count) == 2)
        #expect(shelf.jumpGeneration == 1, "the anchored card changed, so the ring crossfades")
        #expect(shelf.isSettled)
    }

    @Test("T14 a pending token is ignored after the cards change")
    func replaceInvalidatesTokens() {
        let shelf = state(["A", "B", "C"])
        let token = shelf.rotate(by: 1)
        shelf.replaceCards(["C", "B", "A"].map { PlainCard($0) })
        let settled = shelf.settledRotation
        #expect(settled == shelf.rotation)
        shelf.rotate(by: 1)
        shelf.settle(token)
        #expect(shelf.settledRotation == settled)
    }

    @Test("Empty to non-empty and back")
    func replaceEmpty() {
        let shelf = state([])
        shelf.replaceCards(["A", "B"].map { PlainCard($0) })
        #expect(shelf.anchoredCard?.id == "A")
        shelf.rotate(by: 3)
        shelf.replaceCards([])
        #expect(shelf.rotation == 0)
        #expect(shelf.anchoredCard == nil)
    }

    @Test("Duplicate card IDs keep only their first occurrence")
    func duplicateCardIDs() {
        let shelf = state(["A", "B", "A", "C", "B"])
        #expect(shelf.cards.map(\.id) == ["A", "B", "C"])
        shelf.replaceCards(["C", "C", "D"].map { PlainCard($0) })
        #expect(shelf.cards.map(\.id) == ["C", "D"])
    }

    @Test("jump(toCard:) anchors without animating on the current lap")
    func jump() {
        let shelf = state(["A", "B", "C", "D"])
        shelf.rotate(by: 5)
        #expect(shelf.jump(toCard: "D"))
        #expect(shelf.anchoredCard?.id == "D")
        #expect(shelf.rotation == 7)
        #expect(shelf.isSettled)
        #expect(shelf.jumpGeneration == 1)
        #expect(shelf.jump(toCard: "D"))
        #expect(shelf.jumpGeneration == 1, "already anchored and settled: nothing to do")
        #expect(!shelf.jump(toCard: "Z"))
        #expect(shelf.rotation == 7)
    }

    @Test("Card contexts: only the copy at the rotation is anchored")
    func cardContexts() {
        let shelf = state(["A", "B", "C"])
        shelf.rotate(by: -1)
        let size = CGSize(width: 300, height: 168.75)
        let arriving = shelf.cardContext(virtualIndex: -1, isShelfActive: true, faceSize: size)
        let leaving = shelf.cardContext(virtualIndex: 2, isShelfActive: true, faceSize: size)
        #expect(arriving?.isActive == true)
        #expect(arriving?.ringIndex == 2)
        #expect(leaving?.isAnchored == false)
        #expect(leaving?.ringIndex == 2)
        #expect(leaving?.ringCount == 3)
        let inactive = shelf.cardContext(virtualIndex: -1, isShelfActive: false, faceSize: size)
        #expect(inactive?.isAnchored == true)
        #expect(inactive?.isActive == false)
        #expect(state([]).cardContext(virtualIndex: 0, isShelfActive: true, faceSize: size) == nil)
    }
}
