# EtagereKit

A SwiftUI navigation component for Mac, iPad, iPhone and Apple TV: a vertical stack of shelves
(the **Etagere**), each holding a flat, circular row of cards (the **ShelfRing**). The selected
card on each shelf stays at a fixed spot and the ring turns around it, so the thing you're about
to pick is always in the same place. Think of a TV app's Home screen, a game library or a photo
album browser.

- **Rings, not lists.** Left and right turn the active shelf's ring; a bar marks the seam between
  the last and first card, so you can tell when you've gone all the way round. Short rings never
  repeat cards to fill the row.
- **Two vertical modes.** A ring of shelves that slides under a fixed highlight (the default), or
  a cursor that moves between shelves in a scrolling stack and hands focus to controls above or
  below.
- **Every input.** Arrow keys with key repeat, the Mac trackpad and mouse wheel, touch drags with
  haptics, the Siri Remote's clicks and swipes, and game controllers. Rapid input retargets the
  animation instead of queueing it.
- **Accessible.** VoiceOver adjustable shelves with a rotor and seam announcements, named actions
  for the context menu, Reduce Motion, Increase Contrast, Dynamic Type and right-to-left layouts.
- **Cheap at any size.** A 10,000-card ring renders as many views as a 12-card one, and turning
  one shelf re-renders only that shelf.
- **Generic and type-safe.** Shelves hold your own card type, which draws its own face. No
  `AnyView`, no dependencies.

## Requirements

- macOS 26, iOS and iPadOS 26, or tvOS 27
- Swift 6.2 (Xcode 27) or later

## Installation

Add the package in Xcode (File › Add Package Dependencies…) or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/centennial-oss/EtagereKit.git", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: ["EtagereKit"])
]
```

The API can still change before 1.0; pin a minor version (`.upToNextMinor(from: "0.1.0")`) if
you'd rather pick up changes deliberately.

## Usage

A card type conforms to `ShelfCardContent` and draws its own face. Shelves are homogeneous: an
`Etagere<GameBox>` can only ever hold `GameBox` cards.

```swift
import EtagereKit
import SwiftUI

nonisolated struct GameBox: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
}

nonisolated extension GameBox: ShelfCardContent {
    static var faceAspectRatio: CGFloat { 0.71 }    // box art; cards default to 16:9
    var accessibilityTitle: String { "\(name), game" }

    @MainActor
    func makeFace(context: ShelfCardContext) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.indigo.gradient)
            .overlay { Text(name).font(.headline).padding() }
    }
}

struct LibraryView: View {
    @State private var model = EtagereModel(
        shelves: [
            Shelf(id: "owned", title: "Owned", cards: [
                GameBox(id: 1, name: "Pinball"), GameBox(id: 2, name: "Kart"), GameBox(id: 3, name: "Puzzle")
            ]),
            Shelf(id: "wishlist", title: "Wishlist", cards: [], emptyMessage: "Nothing on your wishlist yet")
        ],
        configuration: EtagereConfiguration(horizontalAlignment: .leading, verticalMode: .ring)
    )

    var body: some View {
        Etagere(
            model: model,
            onActivate: { game in print("Play \(game.name)") },
            onActivateEmptyShelf: { shelfID in print("Add something to \(shelfID)") },
            onExit: { /* Esc, Back or controller B: move focus to your sidebar */ }
        )
        .etagereContextMenu { game in
            EtagereAction("Remove", systemImage: "trash", role: .destructive) { print("Remove \(game.name)") }
        }
    }
}
```

More that the model and view offer:

- **Content updates** with `model.replaceShelves(_:)` keep the active shelf and each shelf's
  anchored card, so a background refresh never moves the selection. `Shelf.isUpdating` shows a
  subdued "Updating" label.
- **Saving the selection:** store `model.position` (an `EtagerePosition`, `Codable` when your card
  IDs are) and call `model.restore(_:)` on the next launch.
- **Mode 2 edges:** `.onEtagereEdge { edge in ... }` moves focus to a control above or below and
  returns `true`; otherwise the cursor bumps.
- **Play/Pause on the Siri Remote** activates the card unless `.onEtagerePlayPause { ... }`
  returns `true` to keep the press for your app.
- **Game controllers:** EtagereKit installs no GameController handlers of its own. Forward the
  d-pad, left stick, A and B to an `EtagereGamepad` and attach it with `.etagereGamepad(_:)`.

### Allowing only one card type in an app

If your app should only ever put one kind of card on a shelf, give the card a `fileprivate`
initializer with factory functions, name only typealiases (`typealias VideoShelf =
Shelf<VideoCard>`), and add a SwiftLint rule that rejects any other specialization.
[docs/etagere.md](docs/etagere.md) §5 has the pattern and the rule.

### Isolation

EtagereKit uses Swift 6 with MainActor default isolation. Card types and the other value types
are `nonisolated`; `EtagereModel`, `ShelfState` and the views stay on the main actor. In an app
target that also uses MainActor default isolation, declare your card type `nonisolated` and put
its conformance in a `nonisolated extension`, as above, or the build fails on a main-actor
isolated conformance.

## Documentation

- [docs/etagere.md](docs/etagere.md): terms, the numbered requirements (R1–R29, D1–D8), the
  generic API, configuration and the design decisions.
- [docs/etagere-behavior.md](docs/etagere-behavior.md): ring geometry and animation, the two
  vertical modes, input on each platform, accessibility, performance, starting metrics and the
  test plan, with what the build changed (§7.6).

Code comments and tests cite these IDs (R…, D…, T…, Q…) so each behavior can be traced to its
requirement.

## Development

```sh
make build    # lint, unit tests, and builds for macOS, iOS and tvOS
make test     # unit tests on macOS (swift test)
make lint     # SwiftLint, strict
```

`make lint` needs SwiftLint (`brew install swiftlint`). The rules: files under 400 lines, lines
under 120 characters, names of at least 3 characters, cyclomatic complexity of 15 or less.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
