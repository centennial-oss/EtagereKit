@testable import EtagereKit
import Testing

/// A small seeded generator, so the mixed-direction sequences are the same on every run.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@Suite("The render window under held keys and mixed input (behavior §1.5, D3, D4)")
struct RenderWindowTests {
    private static let geometry = Fixture.referenceGeometry()

    @Test("D4 a 200-step hold on a 200-card shelf renders as many cards after 20 steps as after 200")
    func heldKeyStaysBounded() {
        let model = Fixture.model(cardCounts: [200])
        let held = HeldAnimations(model)
        let shelf = model.shelves[0]
        let rest = Self.geometry.restWindow(count: 200)
        var counts: [Int] = []
        for step in 0..<200 {
            model.move(.nextCard, isRepeat: step > 0, repeatInterval: 0.11, reduceMotion: false)
            // Each repeat ends two repeats later; the first step is a spring that ends three steps later still.
            if step >= 2, step - 2 != 0 { held.finish(step - 2) }
            if step == 5 { held.finish(0) }
            counts.append(shelf.renderSlots(rest: rest).count)
        }
        #expect(shelf.rotation == 200)
        #expect(counts.max() ?? 0 <= rest.count + 2 + 6, "never more than the slow first step in flight")
        #expect(counts.dropFirst(10).allSatisfy { $0 <= rest.count + 2 + 2 }, "two steps in flight at a time")
        #expect(counts[199] == counts[20], "the window does not grow with the length of the hold")
        held.finishAll()
        #expect(shelf.isSettled)
        #expect(shelf.renderSlots(rest: rest).count == rest.count + 2)
    }

    @Test("D4 holding down in mode 1 renders a few shelves, not the whole ShelvesRing")
    func heldShelfKeyStaysBounded() {
        let model = Fixture.model(cardCounts: Array(repeating: 2, count: 60))
        let held = HeldAnimations(model)
        let rest = 0...2
        var largest = 0
        for step in 0..<200 {
            model.move(.nextShelf, isRepeat: step > 0, repeatInterval: 0.11, reduceMotion: false)
            if step >= 2 { held.finish(step - 2) }
            largest = max(largest, model.shelfRenderSlots(rest: rest).count)
        }
        #expect(model.shelfRotation == 200)
        #expect(largest <= rest.count + 2 + 2)
        held.finishAll()
        #expect(model.shelfRotationsInFlight == 200...200)
    }

    @Test("D4 an animation whose completion never arrives cannot grow the window past the backstop")
    func lostCompletionIsBounded() {
        let model = Fixture.model(cardCounts: [500])
        let held = HeldAnimations(model)
        let shelf = model.shelves[0]
        let rest = Self.geometry.restWindow(count: 500)
        for step in 0..<300 {
            model.move(.nextCard, isRepeat: step > 0, repeatInterval: 0.11, reduceMotion: false)
            if step >= 2 { held.finish(step - 1) }
        }
        #expect(shelf.rotationsInFlight == (300 - RingFlights.maximumLag)...300)
        #expect(shelf.renderSlots(rest: rest).count == rest.count + 2 + RingFlights.maximumLag)
        held.finish(299)
        #expect(shelf.isSettled, "the latest animation ending settles the ring, lost completions or not")
    }

    @Test("Mixed directions never drop a visible card, whatever order the animations end in",
          arguments: [1, 7, 42, 2026] as [UInt64])
    func mixedDirectionsKeepVisibleCards(seed: UInt64) {
        let model = Fixture.model(cardCounts: [40])
        let held = HeldAnimations(model)
        let shelf = model.shelves[0]
        let rest = Self.geometry.restWindow(count: 40)
        var generator = SplitMix64(seed: seed)
        // `starts[i]` is the rotation animation i began at; `ended[i]` whether its completion has arrived.
        var starts: [Int] = []
        var ended: [Bool] = []
        for step in 0..<150 {
            starts.append(shelf.rotation)
            ended.append(false)
            let move: EtagereMove = Bool.random(using: &generator) ? .nextCard : .previousCard
            model.move(move, isRepeat: step > 0, repeatInterval: 0.11, reduceMotion: false)
            for _ in 0..<Int.random(in: 0...2, using: &generator) {
                let open = ended.indices.filter { !ended[$0] }
                guard let index = open.randomElement(using: &generator) else { break }
                held.finish(index)
                ended[index] = true
            }
            expectVisibleCardsRendered(shelf: shelf, rest: rest, starts: starts, ended: ended)
        }
    }

    /// Animations that start later end no earlier, so once one has ended every earlier one has too. The ring's
    /// presentation then lies between the rotations it has had since the oldest animation still running began
    /// (overlapping animations add up); every card visible at any of those phases must be rendered.
    private func expectVisibleCardsRendered(
        shelf: ShelfState<PlainCard>, rest: ClosedRange<Int>, starts: [Int], ended: [Bool]
    ) {
        let lastEnded = ended.lastIndex(of: true) ?? -1
        let oldestRunning = ended.indices.first { $0 > lastEnded && !ended[$0] }
        let path = (oldestRunning.map { Array(starts[$0...]) } ?? []) + [shelf.rotation]
        let low = path.min() ?? shelf.rotation
        let high = path.max() ?? shelf.rotation
        let rendered = Set(shelf.renderSlots(rest: rest).map(\.virtualIndex))
        #expect(rendered.count <= rest.count + 2 + 2 * RingFlights.maximumLag)
        for phase in slots(from: Double(low), through: Double(high), by: 0.25) {
            let candidates = (low + rest.lowerBound - 3)...(high + rest.upperBound + 3)
            for virtualIndex in candidates {
                let opacity = Self.geometry.opacity(at: Double(virtualIndex) - phase, rest: rest)
                #expect(opacity == 0 || rendered.contains(virtualIndex), "card \(virtualIndex) at phase \(phase)")
            }
        }
    }
}
