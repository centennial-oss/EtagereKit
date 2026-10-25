#if os(macOS)
import AppKit
import EtagereKit
import SwiftUI
import Testing

/// T24 (behavior §7.1): a ring whose list shrinks while it is on screen. SwiftUI can update a `ForEach` child with
/// a slot from the previous body pass before the body runs again, so each ring must index the same snapshot of its
/// list that its slots came from. `ImageRenderer` builds a fresh tree each time and never sees the stale slot, so
/// these tests keep one `NSHostingView` alive across the change.
@MainActor
@Suite("T24 rings shrinking on screen")
struct RingShrinkTests {
    private static let size = CGSize(width: 1280, height: 900)

    @Test("T24 removing the last shelf and the last two cards", arguments: EtagereVerticalMode.allCases)
    func removeLast(mode: EtagereVerticalMode) {
        let model = Fixture.model(cardCounts: [5, 5, 5], configuration: EtagereConfiguration(verticalMode: mode))
        let host = Self.host(model)
        model.replaceShelves([
            Fixture.shelf("s0", cardCount: 3), Fixture.shelf("s1", cardCount: 5)
        ])
        Self.render(host)
        #expect(model.shelves.map(\.id) == ["s0", "s1"])
        #expect(model.shelves[0].cards.count == 3)
    }

    @Test("T24 removing the Active Shelf and its anchored card", arguments: EtagereVerticalMode.allCases)
    func removeActive(mode: EtagereVerticalMode) {
        let model = Fixture.model(cardCounts: [5, 5, 5], configuration: EtagereConfiguration(verticalMode: mode))
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        model.shelves[1].rotate(by: 4)
        let host = Self.host(model)
        #expect(model.activeShelf?.id == "s2")
        model.shelves[1].replaceCards(Array(model.shelves[1].cards.prefix(3)))
        Self.render(host)
        model.replaceShelves([Fixture.shelf("s0", cardCount: 5), Fixture.shelf("s1", cardCount: 3)])
        Self.render(host)
        #expect(model.shelves.map(\.id) == ["s0", "s1"])
        #expect(model.activeShelf != nil)
    }

    private static func host(_ model: EtagereModel<PlainCard>) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: Etagere(model: model) { _ in } onExit: {})
        host.frame = CGRect(origin: .zero, size: size)
        render(host)
        return host
    }

    private static func render(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
    }
}
#endif
