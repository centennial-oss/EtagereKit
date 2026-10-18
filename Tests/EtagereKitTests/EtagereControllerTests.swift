@testable import EtagereKit
import SwiftUI
import Testing

/// Records what the controller hands the host.
@MainActor
final class HostLog {
    var activated: [String] = []
    var emptyShelves: [String] = []
    var exits = 0
    var edges: [VerticalEdge] = []

    func handlers(edge: ((VerticalEdge) -> Bool)? = nil) -> EtagereHandlers<PlainCard> {
        var handlers = EtagereHandlers<PlainCard>(
            onActivate: { [self] in activated.append($0.id) },
            onActivateEmptyShelf: { [self] in emptyShelves.append($0) },
            onExit: { [self] in exits += 1 }
        )
        if let edge {
            handlers.onEdge = { [self] in
                edges.append($0)
                return edge($0)
            }
        }
        return handlers
    }
}

@MainActor
@Suite("The controller: intents, bumps, edges and pointer input (behavior §1.8, §2, §3, Q2, Q7)")
struct EtagereControllerTests {
    private func controller(
        _ model: EtagereModel<PlainCard>, log: HostLog, reduceMotion: Bool = false,
        edge: ((VerticalEdge) -> Bool)? = nil
    ) -> EtagereController<PlainCard> {
        let controller = EtagereController(model: model)
        controller.update(model: model, handlers: log.handlers(edge: edge), reduceMotion: reduceMotion)
        return controller
    }

    @Test("Go plays the Active ShelfCard, or runs the empty-shelf action (Q7); exit calls the host")
    func activationAndExit() {
        let model = EtagereModel(shelves: [
            Fixture.shelf("live", cardCount: 3), Shelf(id: "dvr", title: "DVR", cards: [], emptyMessage: "Add one")
        ])
        let log = HostLog()
        let controller = controller(model, log: log, reduceMotion: true)
        #expect(controller.perform(key: .returnKey, isRightToLeft: false))
        #expect(controller.perform(key: .letterK, isRightToLeft: true))
        #expect(log.activated == ["live-A", "live-A"])
        controller.perform(.move(.nextShelf))
        #expect(controller.perform(key: .space, isRightToLeft: false))
        #expect(log.emptyShelves == ["dvr"])
        #expect(controller.perform(key: .escape, isRightToLeft: false))
        #expect(log.exits == 1)
        #expect(!controller.perform(.contextMenu), "the platform's own context menu presents the actions")
    }

    @Test("Mode 1 consumes moves that cannot move and bumps instead (R27, behavior §1.10)")
    func modeOneBumps() {
        let model = EtagereModel(shelves: [Fixture.shelf("only", cardCount: 1)])
        let log = HostLog()
        let controller = controller(model, log: log)
        #expect(controller.perform(.move(.nextCard)))
        #expect(controller.viewState.cardBump == EtagereBump(count: 1, direction: 1, shelfID: "only"))
        #expect(controller.viewState.cardBump.trigger(forShelf: "only").count == 1)
        #expect(controller.viewState.cardBump.trigger(forShelf: "other") == EtagereBump(),
                "another ring never replays this bump")
        #expect(controller.perform(.move(.previousShelf)))
        #expect(controller.viewState.shelfBump == EtagereBump(count: 1, direction: -1))
        #expect(controller.viewState.shelfBump.offset == EtagereBump.distance, "previous pushes toward the bottom")
        #expect(controller.viewState.cardBump.offset == -EtagereBump.distance, "next pushes toward the leading edge")
    }

    @Test("Mode 2 at an edge asks the host; without a handler, or when it has nowhere to go, the cursor bumps (Q2)")
    func modeTwoEdges() {
        let configuration = EtagereConfiguration(verticalMode: .cursor)
        let model = EtagereModel(shelves: [Fixture.shelf("a", cardCount: 2), Fixture.shelf("b", cardCount: 2)],
                                 configuration: configuration)
        let log = HostLog()
        let plain = controller(model, log: log, reduceMotion: false)
        #expect(plain.perform(.move(.previousShelf)), "no handler: consumed with a bump")
        #expect(plain.viewState.shelfBump.count == 1)

        let escaping = controller(model, log: log, edge: { $0 == .top })
        #expect(escaping.perform(.move(.previousShelf)))
        #expect(log.edges == [.top])
        #expect(escaping.viewState.shelfBump == EtagereBump(), "focus moved out, so no bump")
        #expect(escaping.perform(.move(.nextShelf)))
        #expect(model.activeShelf?.id == "b")
        #expect(escaping.perform(.move(.nextShelf)))
        #expect(log.edges == [.top, .bottom])
        #expect(escaping.viewState.shelfBump.count == 1, "nothing below: the cursor bumps and does not wrap")
        #expect(model.activeShelf?.id == "b")
    }

    @Test("tvOS mode 2: an edge row's command asks the host or bumps, unless it is the move that brought focus there")
    func modeTwoRowEdges() {
        let configuration = EtagereConfiguration(verticalMode: .cursor)
        let model = EtagereModel(shelves: [Fixture.shelf("a", cardCount: 2), Fixture.shelf("b", cardCount: 2)],
                                 configuration: configuration)
        let log = HostLog()
        let controller = controller(model, log: log, edge: { $0 == .bottom })
        controller.rowFocusChanged(at: 10)
        controller.reachEdge(.top, at: 10.05)
        #expect(log.edges.isEmpty, "focus just arrived on the top row: this is the move that brought it")
        controller.reachEdge(.top, at: 10.5)
        #expect(log.edges == [.top])
        #expect(controller.viewState.shelfBump.count == 1, "nothing above: the cursor bumps and does not wrap")
        #expect(model.activeShelf?.id == "a")
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        controller.rowFocusChanged(at: 11)
        controller.reachEdge(.bottom, at: 11.5)
        #expect(log.edges == [.top, .bottom])
        #expect(controller.viewState.shelfBump.count == 1, "the host moved focus below, so no bump")
        #expect(model.activeShelf?.id == "b")

        let edges = (0..<3).map { CursorEtagere<PlainCard>.edges(ofRow: $0, count: 3) }
        #expect(edges == [[.top], [], [.bottom]])
        #expect(CursorEtagere<PlainCard>.edges(ofRow: 0, count: 1) == [.top, .bottom])
    }

    @Test("Play/Pause plays the Active ShelfCard unless the host's handler uses it (behavior §3.2)")
    func playPause() {
        let model = EtagereModel(shelves: [
            Fixture.shelf("live", cardCount: 3), Shelf(id: "dvr", title: "DVR", cards: [], emptyMessage: "Add one")
        ])
        let log = HostLog()
        let plain = controller(model, log: log, reduceMotion: true)
        plain.playPause()
        #expect(log.activated == ["live-A"], "by default Play/Pause is go")

        var handlers = log.handlers()
        var hostUsesIt = true
        var asked = 0
        handlers.onPlayPause = {
            asked += 1
            return hostUsesIt
        }
        let hooked = EtagereController(model: model)
        hooked.update(model: model, handlers: handlers, reduceMotion: true)
        hooked.playPause()
        #expect(asked == 1)
        #expect(log.activated == ["live-A"], "the host dismissed its mini player instead")
        hostUsesIt = false
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        hooked.playPause()
        #expect(asked == 2)
        #expect(log.emptyShelves == ["dvr"], "the host passed: go on the empty shelf, with its ID (Q7)")
    }

    @Test("Mode 2 consumes left and right on an empty shelf, and leaves them alone with no shelves at all")
    func modeTwoEmptyShelf() {
        let configuration = EtagereConfiguration(verticalMode: .cursor)
        let log = HostLog()
        let empty = EtagereModel(
            shelves: [Shelf<PlainCard>(id: "empty", title: "Empty", cards: [])], configuration: configuration
        )
        let emptyController = controller(empty, log: log)
        #expect(emptyController.perform(.move(.nextCard)))
        #expect(emptyController.viewState.cardBump.count == 1)

        let reduced = controller(empty, log: log, reduceMotion: true)
        #expect(reduced.perform(.move(.nextShelf)))
        #expect(reduced.viewState.shelfBump == EtagereBump(), "Reduce Motion never bumps")

        let none = EtagereModel<PlainCard>(shelves: [], configuration: configuration)
        #expect(!controller(none, log: log).perform(.move(.previousCard)), "nothing to consume it")
    }

    @Test("wouldMove: what moves, rather than only being consumed", arguments: EtagereVerticalMode.allCases)
    func wouldMove(mode: EtagereVerticalMode) {
        let model = Fixture.model(cardCounts: [1, 4], configuration: EtagereConfiguration(verticalMode: mode))
        #expect(!model.wouldMove(.nextCard))
        #expect(model.wouldMove(.nextShelf))
        #expect(model.wouldMove(.previousShelf) == (mode == .ring))
        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        #expect(model.wouldMove(.previousCard))
        #expect(model.wouldMove(.nextShelf) == (mode == .ring))
    }

    @Test("A tap on an inactive shelf's card selects it; on the Active ShelfCard it plays, once")
    func tapToActivate() {
        let model = Fixture.model(cardCounts: [5, 5])
        let log = HostLog()
        let controller = controller(model, log: log, reduceMotion: true)
        let second = model.shelves[1]
        controller.tapCard(on: second, shelfVirtualIndex: 1, cardVirtualIndex: 0, at: 1)
        #expect(model.activeShelf?.id == "s1")
        #expect(model.shelfRotation == 1, "mode 1 turns to the tapped copy")
        #expect(log.activated.isEmpty, "the first tap only selects")
        controller.tapCard(on: second, shelfVirtualIndex: 1, cardVirtualIndex: 0, at: 2)
        controller.tapCard(on: second, shelfVirtualIndex: 1, cardVirtualIndex: 0, at: 2.2)
        #expect(log.activated == ["s1-A"], "a double-click on the anchored card plays once")
        controller.tapCard(on: second, shelfVirtualIndex: 1, cardVirtualIndex: 0, at: 2.7)
        #expect(log.activated == ["s1-A", "s1-A"])
    }

    @Test("A tap on a visible card turns the shortest way; farther than six slots it jumps (behavior §1.8)")
    func tapToRotate() {
        let model = Fixture.model(cardCounts: [3, 20])
        let log = HostLog()
        let controller = controller(model, log: log, reduceMotion: true)
        let short = model.shelves[0]
        controller.tapCard(on: short, shelfVirtualIndex: 0, cardVirtualIndex: 2)
        #expect(short.rotation == -1, "C is one step back, not two forward")
        #expect(short.anchoredCard?.id == "s0-C")
        controller.tapCard(on: short, shelfVirtualIndex: 0, cardVirtualIndex: 2, at: 100)
        #expect(log.activated == ["s0-C"], "a second click on the arriving card plays it (a double-click)")

        model.move(.nextShelf, isRepeat: false, reduceMotion: true)
        let long = model.shelves[1]
        controller.tapCard(on: long, shelfVirtualIndex: 1, cardVirtualIndex: 7)
        #expect(long.anchoredCard?.id == "s1-H")
        #expect(long.jumpGeneration == 1, "seven slots away: a jump, crossfaded")
        controller.tapCard(on: long, shelfVirtualIndex: 1, cardVirtualIndex: 13)
        #expect(long.anchoredCard?.id == "s1-N")
        #expect(long.jumpGeneration == 1, "six slots away: animated")
    }

    @Test("A placeholder tap selects its shelf, then runs the empty-shelf action")
    func placeholderTap() {
        let model = EtagereModel(shelves: [
            Fixture.shelf("a", cardCount: 2), Shelf<PlainCard>(id: "none", title: "None", cards: [])
        ])
        let log = HostLog()
        let controller = controller(model, log: log, reduceMotion: true)
        controller.tapPlaceholder(shelfVirtualIndex: 1, at: 0)
        #expect(log.emptyShelves.isEmpty)
        controller.tapPlaceholder(shelfVirtualIndex: 1, at: 1)
        #expect(log.emptyShelves == ["none"])
    }

    @Test("Drag release, wheel notches and VoiceOver turn the right shelf and settle")
    func dragsScrubsAndVoiceOver() {
        let model = Fixture.model(cardCounts: [8, 8])
        let held = HeldAnimations(model)
        let log = HostLog()
        let controller = controller(model, log: log)
        let inactive = model.shelves[1]
        var offsetReset = false
        controller.releaseDrag(on: inactive, delta: 3) { offsetReset = true }
        #expect(offsetReset)
        #expect(inactive.anchoredCard?.id == "s1-D")
        #expect(model.activeShelf?.id == "s0", "dragging a shelf does not select it")
        #expect(held.animations == [EtagereController<PlainCard>.releaseAnimation])
        held.finishAll()
        #expect(inactive.isSettled)

        controller.scrubStep(on: inactive, step: -1, at: 0)
        controller.scrubStep(on: inactive, step: -1, at: 0.05)
        #expect(inactive.anchoredCard?.id == "s1-B")
        #expect(held.animations.count == 3)
        #expect(held.animations[1] == model.configuration.stepAnimation)
        #expect(held.animations[2] != model.configuration.stepAnimation, "a quick second notch is a repeat")

        controller.adjust(inactive, shelfVirtualIndex: 1, by: 1)
        #expect(model.activeShelf?.id == "s1", "VoiceOver's adjust selects the shelf it turns")
        #expect(inactive.anchoredCard?.id == "s1-C")
        controller.activate(shelfVirtualIndex: 0)
        #expect(log.activated == ["s0-A"])
    }

    @Test("Selecting a shelf copy turns mode 1 to that copy, and mode 2 to that row; the rotor takes the shortest way")
    func shelfSelection() {
        let ring = Fixture.model(cardCounts: [2, 2, 2])
        let log = HostLog()
        let ringController = controller(ring, log: log, reduceMotion: true)
        ringController.selectShelf(virtualIndex: 2)
        #expect(ring.shelfRotation == 2, "forward to the copy the user chose, not the shortest way back")
        ringController.selectShelf(id: "s0")
        #expect(ring.shelfRotation == 3)

        let cursor = Fixture.model(cardCounts: [2, 2, 2], configuration: EtagereConfiguration(verticalMode: .cursor))
        let cursorController = controller(cursor, log: log, reduceMotion: true)
        cursorController.selectShelf(virtualIndex: 2)
        #expect(cursor.shelfRotation == 2)
        cursorController.selectShelf(virtualIndex: 5)
        #expect(cursor.shelfRotation == 2, "mode 2 has no copies outside its rows")
    }

    @Test("The context-menu actions follow what go would act on")
    func contextActions() {
        var handlers = EtagereHandlers<PlainCard>()
        #expect(!handlers.hasActions)
        handlers.cardActions = { card in [EtagereAction("Favorite \(card.id)") {}] }
        handlers.emptyShelfActions = { shelfID in [EtagereAction("Set up \(shelfID)", systemImage: "gear") {}] }
        #expect(handlers.hasActions)
        #expect(handlers.actions(for: .card(PlainCard("x"))).map(\.title) == ["Favorite x"])
        #expect(handlers.actions(for: .emptyShelf(shelfID: "dvr")).map(\.title) == ["Set up dvr"])
        #expect(handlers.actions(for: nil).isEmpty)
    }

    @Test("The action builder takes conditions and loops")
    func actionBuilder() {
        @EtagereActionBuilder
        func build(isFavorite: Bool, extras: [String]) -> [EtagereAction] {
            if isFavorite {
                EtagereAction("Unfavorite", systemImage: "heart.slash") {}
            } else {
                EtagereAction("Favorite", systemImage: "heart") {}
            }
            for extra in extras {
                EtagereAction(extra, role: .destructive) {}
            }
            EtagereAction("Edit Home") {}
        }
        #expect(build(isFavorite: true, extras: []).map(\.title) == ["Unfavorite", "Edit Home"])
        #expect(build(isFavorite: false, extras: ["Remove"]).map(\.title) == ["Favorite", "Remove", "Edit Home"])
    }
}
