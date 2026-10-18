# EtagereKit: Etagere, Shelf, ShelfRing and ShelfCard

EtagereKit is a reusable SwiftUI navigation component for Apple platforms: a vertical stack of
shelves (the Etagere), each holding a flat, circular, horizontally rotating row of cards (the
ShelfRing). The selected card on each shelf stays at a fixed Anchor Spot and the ring turns
around it. This document lists every requirement as a numbered item (R1..R29, plus derived items
D1..D8) so code and tests can trace them, then specifies the package, the generic API, how a host
app restricts its shelves to one card type, and the design decisions (Q1..Q8). The companion
document [etagere-behavior.md](etagere-behavior.md) specifies the ring geometry and animation
rules, the two vertical navigation modes, input per platform, accessibility, performance, metrics
and the test plan.

Status: built 2026-10-11 and used since then as the Home screen of a live-TV and video app, on a
Mac and a real Apple TV and in the iPad and iPhone simulators. Differences from this spec are listed in
[etagere-behavior.md](etagere-behavior.md) §7.6.

Verification tags: **(verified)** means compiled, rendered or checked against the Xcode 27 SDK
interfaces during research. **(believed)** means it comes from memory or a secondary source and
needs a device or simulator check before we rely on it.

---

## 1. Terms

| Term | Meaning |
|---|---|
| Etagere | The whole control: a vertical stack of Shelves, plus one selection. |
| Shelf | One titled row. Holds one ShelfRing. |
| ShelfRing | The circular list of ShelfCards on a Shelf, drawn as a flat carousel row. |
| ShelfCard | One item on a ring, of the host app's card type (for example a `VideoCard`). |
| ShelvesRing | The vertical ring of shelves in vertical mode 1. |
| Anchor Spot | The fixed position (leading, center or trailing) where a ring's selected card rests. |
| Anchored card | The card at a shelf's Anchor Spot. Every non-empty shelf has one. |
| Active Shelf | The one shelf that currently has the selection. |
| Active ShelfCard | The anchored card on the Active Shelf. "Go" triggers it. |
| Seam | The boundary between a ring's last and first card, drawn as a bar. |
| Slot | A position relative to the Anchor Spot: 0 is the anchor, +1 the next card, -1 the previous. |
| Rotation | An unbounded integer per ring; the anchored index is `floorMod(rotation, N)`. |
| Lap | How many times the ring has wrapped for one rendered copy of a card: `floorDiv(v, N)`. |
| Rest window | The slots shown at full opacity when the ring is not moving. |
| Fade slot | The slot just outside the rest window on each side. Always at opacity 0 at rest. |
| Ghost copy | A second rendered copy of the same card (different lap) during a wrap. |

---

## 2. Requirements

These restate the original request in testable form. Where its words are quoted, they are in
quotation marks. R5 is designed in §4-§5 here; R6-R20
in [etagere-behavior.md](etagere-behavior.md) §1; R21-R28 in its §2; input in its §3. Its §7
maps every requirement to tests.

### 2.1 Structure and reuse

- **R1.** The Etagere is a vertical stack of Shelves.
- **R2.** Each Shelf has one horizontal ShelfRing: a circular list of ShelfCards.
- **R3.** In a video app a ShelfCard is a video thumbnail, or a stylish generated card when there
  is no thumbnail.
- **R4.** The Etagere is reusable in other apps, where a ShelfCard can render other types the user
  cycles through (for example video game boxes).
- **R5.** A host app can allow only its own card type on its shelves (a video app: only
  VideoCards). Enforce this "in the most idiomatic Swift way", for example a factory function or
  another constraint; generics are preferred.

### 2.2 Anchor, selection and enlargement

- **R6.** The selected ShelfCard of a shelf sits at the Anchor Spot. The Anchor Spot is on the left
  by default and can be set to the middle or the right at the Etagere level, through a
  `horizontalAlignment` property (or similar).
- **R7.** The anchored card is enlarged whenever its Shelf is the Active Shelf.
- **R8.** The anchored card on the Active Shelf is the Active ShelfCard. It is what the "go" input
  triggers: Enter, Space, K, the center button on the Apple TV remote, and similar.
- **R9.** Only one ShelfCard can be selected across all Shelves, so there is exactly one Active
  Shelf.
- **R10.** Anchored cards on inactive shelves are not enlarged. Only the true Active ShelfCard is.

### 2.3 Rotation and animation

- **R11.** Left or right on the Active Shelf rotates the ShelfRing (not a selection cursor) to
  bring the next or previous card to the Anchor Spot.
- **R12.** Rotation is a short animated transition. Every card shifts to its new place. The new
  Active ShelfCard grows to its new size, and the outgoing Active ShelfCard dims and shrinks as it
  slides off the leading side.
- **R13.** When the ring moves the other way, the card at the far end that will be cut off dims
  and fades as it slides off screen.
- **R14.** If the card leaving view at one end of the ring is also the incoming selected card, it
  "should occupy both spots at the same time during transition".
- **R15.** Center-aligned shelves use the same fade strategy at both ends, as needed.

### 2.4 Alignment, fading, repetition and the seam

- **R16.** Shelves are left, right or center aligned by `horizontalAlignment`, and never
  justified. A gap at the end(s) opposite the Anchor Spot is acceptable.
- **R17.** Cards fade to 0% opacity as they transition off screen, reaching 0% at "a distance 2x
  its width + the current padding size between ShelfCards", so that it looks right regardless of
  how far the ring's end is from the shelf edge. The interpretation is open question Q1 (§7).
- **R18.** The ring is circular in behavior but flat on screen: not 3D, no visible circle, no
  parallax. It looks like a basic carousel row.
- **R19.** If there are too few cards to exceed the shelf's width, they do not repeat to fill the
  row.
- **R20.** A vertical bar marks the seam between the last and the first ShelfCard, whichever card
  is anchored, so the user can tell when they have completed a full cycle.

### 2.5 Vertical navigation

- **R21.** The Etagere supports two vertical navigation modes. Mode 1 is the default.
- **R22.** Mode 1: up and down (arrows, d-pad or swipes, as the platform allows) slide the shelves
  vertically through a ring of shelves (the ShelvesRing), just as cards slide in a ShelfRing.
- **R23.** A `verticalAlignment` property sets the vertical Anchor Spot of the Etagere.
- **R24.** Mode 2: the selection moves up and down between shelves without shifting the shelves'
  positions.
- **R25.** In both modes the Active Shelf has an indicator, such as a tinted background behind it.
  In mode 2 the indicator animates up and down during the transition.
- **R26.** In mode 2, if the shelves exceed the available height, the Etagere scrolls.
- **R27.** In mode 1 the Etagere is the only control on the page that accepts directional input,
  because up, down, left and right never leave it. On Apple TV the Back button leaves it, and the
  host decides where focus goes (for example its sidebar or menu).
- **R28.** Mode 2 with selectable controls above or below the Etagere: moving past the top or
  bottom shelf reaches them ([etagere-behavior.md](etagere-behavior.md) §2.2, decision Q2).

### 2.6 Host usage

- **R29.** The first host app's Home screen is an Etagere with shelves such as Favorites, Live TV
  Channels and Recent Recordings, holding the appropriate cards.

### 2.7 Derived requirements (from the decisions and research)

- **D1. App-agnostic package.** No host-app types or branding in EtagereKit, and no
  dependencies. Swift 6 language mode, MainActor default isolation, `nonisolated` model types.
- **D2. RTL.** Alignment names are leading/center/trailing and top/center/bottom, never
  left/right. RTL changes only the physical-to-logical input mapping and the drawing mirror.
- **D3. Never lock input.** Rapid presses and key repeat retarget the animation. "Go" during an
  animation activates the card that is arriving.
- **D4. Cost independent of ring length.** A 10,000-card ring renders as many views as a 12-card
  ring. Rotating one shelf re-renders only that shelf.
- **D5. No live video for card faces.** Card art never comes from playing or tuning live video.
- **D6. Accessibility.** VoiceOver, Reduce Motion, Increase Contrast, full keyboard access,
  Dynamic Type.
- **D7. Layout from container size**, never device idiom or orientation (iPhone Duo, Split View).
- **D8. Content refresh keeps the selection.** Reloading a shelf's content (for example a channel
  lineup) does not move the anchored card.

---

## 3. Package and placement

- A SwiftPM package at the repository root, tools version 6.2, platforms `.macOS("26.0")`,
  `.iOS("26.0")`, `.tvOS("27.0")` (the string forms: in Xcode 27.0's `PackageDescription` the
  `.v27` constants need tools 6.4, verified), target setting `.defaultIsolation(MainActor.self)`
  (verified available at tools 6.2) and the upcoming feature `MemberImportVisibility`. No
  dependencies. `make lint` and `make test` run locally and in CI.
- Layout:

```
Package.swift
Sources/EtagereKit/
  Model/     ShelfCardContent.swift  Shelf.swift  ShelfState.swift  EtagereModel.swift  EtagereModelContent.swift
             RingFlights.swift  EtagereConfiguration.swift  EtagereMetrics.swift  EtagereIntent.swift
  Geometry/  RingGeometry.swift  RingSlots.swift          (pure, nonisolated, fully unit tested)
  Views/     ShelfCard.swift  ShelfRingView.swift  ShelfRowView.swift  RingSlotEffect.swift  SeamBar.swift
             VerticalShelfRing.swift  CursorEtagere.swift  Etagere.swift  EtagereAction.swift
             EtagereController.swift  EtagereLayout.swift  ActiveShelfHighlight.swift
  Input/     EtagereInput.swift  EtagereKeyMap.swift  RepeatDetector.swift  InputMath.swift
             EtagereModelInput.swift  TrackpadScrub_macOS.swift  RingDragGesture_iOS.swift
             RemoteInputBridge_tvOS.swift  EtagereGamepad.swift
  Accessibility/ ShelfAccessibility.swift
Tests/EtagereKitTests/   geometry, model, input, layout, reuse and snapshot tests
```

- Lint rules (`.swiftlint.yml`): files under 400 lines, lines under 120 characters, identifiers
  at least 3 characters. This is why the intent enum uses `previousShelf`/`nextShelf` rather than
  `up`/`down`.

---

## 4. Generic API

### 4.1 Why generics, not type erasure

| Criterion | Generics + self-rendering protocol (chosen) | Type erasure (`AnyShelfCard`, `AnyView`) | Content closure (`Etagere<Item, CardView>`) |
|---|---|---|---|
| One card type per host app | Enforced by the type: an `Etagere<VideoCard>` cannot hold anything else | Not enforceable; everything erases | Item type enforced, renderer chosen at each call site |
| Mixed card kinds in one shelf | Impossible (wanted) | Possible | Impossible |
| SwiftUI diffing and cost | Static types, structural identity, no `AnyView` | `AnyView` defeats structural diffing and allocates | Static |
| Reuse in another app | `struct GameBoxCard: ShelfCardContent` | Easy | Easy |
| Generic parameters | One, so typealiases are clean | None | Two; the typealias must also name the view |

The card type renders its own face through an associated type, the same pattern as
`ButtonStyle.makeBody`. One generic parameter is enough, shelves are homogeneous by construction,
and there is no `AnyView`. If a one-off renderer is ever needed, add a constrained convenience
`init` that takes a closure; do not reach for `AnyView`.

### 4.2 Core types

Sketch of the public API (the sources have the exact signatures):

```swift
public nonisolated struct ShelfCardContext: Sendable, Equatable {
    public var isActive: Bool        // the Active ShelfCard (R8)
    public var isAnchored: Bool      // anchored on its shelf, active or not
    public var isShelfActive: Bool
    public var ringIndex: Int
    public var ringCount: Int
    public var faceSize: CGSize      // idle size; the ring scales the active card
}

public protocol ShelfCardContent: Identifiable, Equatable, Sendable where ID: Sendable {
    associatedtype Face: View
    static var faceAspectRatio: CGFloat { get }     // default 16:9; about 0.71 for box art
    var accessibilityTitle: String { get }
    @MainActor @ViewBuilder func makeFace(context: ShelfCardContext) -> Face
}

public nonisolated struct Shelf<Card: ShelfCardContent>: Identifiable, Sendable {
    public let id: String
    public var title: String
    public var cards: [Card]
    public var emptyMessage: String?   // one non-rotating placeholder card when `cards` is empty
}

@Observable public final class ShelfState<Card: ShelfCardContent>: Identifiable {
    public private(set) var cards: [Card]
    public private(set) var rotation: Int          // unbounded; anchored index = floorMod(rotation, N)
    public private(set) var settledRotation: Int   // last rotation whose animation finished
    public var anchoredCard: Card? { get }
    @discardableResult public func rotate(by delta: Int) -> Int        // returns a settle token
    @discardableResult public func rotate(toCard id: Card.ID) -> Int   // shortest way; ties go forward
    public func settle(_ token: Int)
    public func replaceCards(_ newCards: [Card])                       // behavior §1.10
}

@Observable public final class EtagereModel<Card: ShelfCardContent> {
    public private(set) var shelves: [ShelfState<Card>]   // one observable per shelf (D4)
    public private(set) var shelfRotation: Int            // ring: unbounded; cursor: 0..<count
    public var configuration: EtagereConfiguration
    public var activeShelf: ShelfState<Card>? { get }
    public var activeCard: Card? { activeShelf?.anchoredCard }   // the single selection (R9)
    public init(shelves: [Shelf<Card>], configuration: EtagereConfiguration = .init())
    /// Returns false when the move is not consumed (mode 2 at an edge) so focus may leave.
    @discardableResult
    public func move(_ move: EtagereMove, isRepeat: Bool, reduceMotion: Bool) -> Bool
    public func activateShelf(id: String)                  // mode 2 focus, VoiceOver focus
    public func replaceShelves(_ shelves: [Shelf<Card>])   // keeps the active shelf and anchors
}

public nonisolated enum EtagereMove: Sendable { case previousCard, nextCard, previousShelf, nextShelf }
public nonisolated enum EtagereIntent: Sendable { case move(EtagereMove), activate, contextMenu, exit }

public struct Etagere<Card: ShelfCardContent>: View {
    public init(model: EtagereModel<Card>,
                onActivate: @escaping (Card) -> Void,   // "go" on the Active ShelfCard
                onExit: @escaping () -> Void)           // Back / Menu / Esc: the host moves focus
}
// Optional modifiers: .etagereContextMenu { card in ... } and, for mode 2,
// .onEtagereEdge { edge in ... } which moves focus to a control above or below (behavior §2.2).
```

`ShelfCard<Content>` is the chrome around a face: idle size, continuous corner shape and
`.compositingGroup()` so a fading card composites once instead of per sub-layer.

### 4.3 Configuration

The public properties use the requirement names. Internally both alignments map to one
`RingAnchor { leading, center, trailing }` used by `RingGeometry` on either axis.

```swift
public nonisolated enum EtagereHorizontalAlignment: Sendable { case leading, center, trailing }
public nonisolated enum EtagereVerticalAlignment: Sendable { case top, center, bottom }
public nonisolated enum EtagereVerticalMode: Sendable { case ring, cursor }   // mode 1, mode 2

public nonisolated struct EtagereConfiguration: Sendable, Equatable {
    public var horizontalAlignment: EtagereHorizontalAlignment = .leading   // R6, R16
    public var verticalAlignment: EtagereVerticalAlignment = .top           // R23
    public var verticalMode: EtagereVerticalMode = .ring                    // R21
    public var metrics: EtagereMetrics = .regular       // sizes and spacing (behavior §6)
    public var cardCrossAlignment: ShelfCardCrossAlignment = .center        // .bottom for box art
    public var idleDim = 0.12            // brightness drop for non-active cards on the active shelf
    public var inactiveShelfDim = 0.15   // extra drop for every card on other shelves
    public var showsSeam = true          // R20
    public var showsShelfSeam = true     // mode 1 bar between the last and first shelf (Q4)
    public var fadeLengthInSlots = 1.0   // R17; clamped to 0.25...1 (behavior §1.4, Q1)
    public var stepAnimation: Animation = .snappy(duration: 0.28)
    public var repeatAnimation: Animation = .linear(duration: 0.12)   // retimed to the repeat rate
    public var shelfStepAnimation: Animation = .snappy(duration: 0.32)
    public var highlightAnimation: Animation = .snappy(duration: 0.3)
}
```

Early renders used dims of 0.18 and 0.28. Together (0.46) they made inactive shelves far
too dark in rendered frames, so the starting values are 0.12 and 0.15. Tune on device.

### 4.4 Swift 6 isolation

The app target and the package use MainActor default isolation. A struct declared without
`nonisolated` in such a target gets main-actor-isolated conformances (SE-0470), and
`ShelfCardContent` refines `Sendable`, so the build fails (verified):

> main actor-isolated conformance of 'PlainCard' to 'Equatable' cannot satisfy conformance
> requirement for a 'Sendable' type parameter

Rule: every card and model value type (your card type, `Shelf`, configuration, geometry) is
`nonisolated`. `ShelfState`, `EtagereModel` and views stay on the main actor. `makeFace` is
explicitly `@MainActor`.

---

## 5. One card type per host app (R3, R5)

A host that should only ever show one kind of card, such as a video app's `VideoCard`, keeps
everything about it in one folder of the app:

```swift
// VideoCard.swift — the only file that can construct a VideoCard
nonisolated struct VideoCard: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case liveChannel, recording, movie, episode }
    let id: String              // stable, never a host name or address
    let kind: Kind
    let title: String
    let subtitle: String?
    let artworkURL: URL?        // nil: a generated face, a deterministic gradient from `id` (R3)
    let progress: Double?       // resume position, 0...1

    // Declared in the struct body, so Swift does not synthesize an internal memberwise init.
    fileprivate init(id: String, kind: Kind, title: String, subtitle: String?,
                     artworkURL: URL?, progress: Double?) { ... }
}

extension VideoCard {                // same file: the only callers of the init
    static func make(from item: MediaItem) -> VideoCard
}

typealias VideoShelf = Shelf<VideoCard>
typealias VideoShelfState = ShelfState<VideoCard>
typealias VideoEtagere = Etagere<VideoCard>
typealias VideoEtagereModel = EtagereModel<VideoCard>
```

The face, `nonisolated extension VideoCard: ShelfCardContent`, goes in its own file (a plain
extension fails to compile under MainActor default isolation, because its members would be
main-actor-isolated), so `VideoCard.swift` does not import SwiftUI. New kinds of video are new
`Kind` cases, never new card types.

Enforcement has three layers:

1. **Types.** Each Etagere is homogeneous. App code names only the typealiases.
2. **Construction.** The `fileprivate` init means cards come only from the factories, so IDs and
   faces stay consistent. The init must be declared inside the struct body: an init declared in an
   extension would leave Swift's internal memberwise init in place.
3. **CI lint.** A SwiftLint custom rule in the app's `.swiftlint.yml` turns any other
   specialization into an error. Tested with swiftlint 0.65.1: it flags `Shelf<GameBox>` and
   `EtagereModel<GameBox>` and allows `Shelf<VideoCard>` (verified). The rule can't see inferred
   generics, so a second rule allows `ShelfCardContent` only in the card's folder. Prove both
   still fire by running swiftlint with the app's config on a fixture outside the linted paths.

```yaml
custom_rules:
  etagere_video_cards_only:
    name: "Shelves hold VideoCard only"
    regex: '\b(Etagere|EtagereModel|Shelf|ShelfState|ShelfCard|ShelfRingView)<(?!VideoCard\b)'
    match_kinds: [identifier, typeidentifier]
    message: "Use VideoEtagere / VideoShelf; only VideoCard may go on a shelf."
    severity: error
```

With `MemberImportVisibility` on, every file that uses `Shelf` or `EtagereModel` members through
the typealiases must `import EtagereKit`, so a lint rule that kept the import inside the card's
folder would forbid exactly that. If an import boundary is ever wanted, it needs wrapper structs
instead of bare typealiases.

---

## 6. History

The package was seeded from a SwiftPM prototype (the ring math, the models and the views, checked
by rendering frames with `ImageRenderer`) and built out on 2026-10-11, with the input, focus and
accessibility work that followed on Apple TV, iPad and iPhone.
[etagere-behavior.md](etagere-behavior.md) §7.6 lists where the build differs from the spec.

---

## 7. Design decisions

All eight were settled on 2026-10-11 by taking the proposal; each question keeps its ID because
the code and tests cite it.

**Q1. Fade distance.** The request says cards fade to 0% "as it reaches a distance 2x its width +
the current padding". The design reads this as: fully transparent after one slot of travel past
the ring's rest edge, because one slot of travel sweeps exactly `2w + p` of shelf:

```
 far end of a leading ring, "previous" pressed: card C moves from the last rest slot to the fade slot

 before:   [   B   ]   [   C   ]
 after:                [   B   ]   [   C   ]      <- C is now in the fade slot: opacity 0
                       |<- w ->|<p>|<- w ->|
                       |<---- 2w + p ----->|      ground C sweeps during the move
```

Alternatives, with opacity by position past the rest edge at the prototype's metrics (w = 300,
p = 32, so one slot = 332 pt and 2w + p = 632 pt ≈ 1.9 slots; the tvOS starting metrics 360/40
give the same ratio of about 1.9 slots):

| Reading | -0.5 slot | 0 (rest edge) | +0.5 | +1 (fade slot) | +1.5 |
|---|---|---|---|---|---|
| A. Proposed: 0 after one slot of travel (sweep = 2w + p) | 1 | 1 | 0.5 | 0 | 0 |
| B. 0 after the card itself travels 2w + p | 1 | 1 | 0.74 | 0.47 | 0.21 |
| C. Edge vignette: a 2w + p ramp ending at the fade slot | 0.79 | 0.53 | 0.26 | 0 | 0 |

- **B** leaves the fade slot at 47% opacity at rest: a half-visible extra card, which in a short
  ring is a repeated card (breaks R19).
- **C** keeps R19 but shows the last resting card at the far end already about half faded, a
  common carousel look. It cannot apply on the leading side, where the outgoing anchored card
  rests at full size.
- **D. Measured from the screen edge** instead of the ring's edge (not tabulated; it depends on
  the viewport): in long rings the fade happens where cards are already clipped, and a short ring
  ending mid-shelf would not fade at all, so the wrapped card would show at full opacity (breaks
  R19 and "regardless of distance from the edge").

Decided: A, with `fadeLengthInSlots` (0.25...1) available for tuning.

**Q2. Mode 2 with controls above or below.** Decided: up on the top shelf (or down on the bottom
shelf) moves focus to those controls; with no controls there, the cursor stops at the edge (no
wrap) with a small bump. Rejected: wrapping to the other end, and treating the controls as
pseudo-shelves that the highlight also covers.

**Q3. Trailing anchor order.** Decided: `B C | [A]`, previous cards to the left and the next card
entering from the trailing edge; a trailing anchor doesn't reverse the order.

**Q4. Vertical seam.** Decided: mode 1 also draws a horizontal bar between the last and first
shelf (`showsShelfSeam`, on by default).

**Q5. Seam at the start of a long leading ring.** With the first card anchored, the seam sits just
before the anchor in the exit zone and is not visible at rest; the user sees it slide past as the
ring wraps. Decided: no visible "start of list" marker; VoiceOver announces "Start of list".

**Q6. Mode 1 pages have no other controls.** Decided: page actions (for example "Edit Home") go
in the long-press menu or the app's settings.

**Q7. Empty shelves.** Decided: the shelf shows one placeholder card that stays navigable, where
"go" runs a host action (for example opening settings to add a source).

**Q8. Remember position.** Decided: the active shelf and each shelf's anchored card come back on
the next launch. The model exposes them as `EtagereModel.position` (an `EtagerePosition`) and
`restore(_:)`; the host stores the value.

