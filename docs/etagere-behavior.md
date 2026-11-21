# EtagereKit behavior: ring geometry, navigation, input and tests

This is the second half of the EtagereKit spec. The first half, [etagere.md](etagere.md), holds
the terms, the numbered requirements (R1..R29, D1..D12), the generic API, how a host allows only
one card type, and the design decisions (Q1..Q8). This half specifies how a
ShelfRing places, sizes and fades its cards at rest and during animation, the two vertical
navigation modes, the input mapping on each platform, accessibility, performance, starting
metrics, the test plan that traces every requirement, and the risks.

Status: written as the design on 2026-10-10 and built on 2026-10-11; §7.6 lists where the build
differs.

Verification tags: **(verified)** means compiled, rendered or checked against the Xcode 27 SDK
interfaces during research. **(believed)** means it comes from memory or a secondary source and
needs a device or simulator check before we rely on it.

---

## 1. ShelfRing geometry and animation

### 1.1 Variables

`N` card count. `w` idle card width. `W = w * activeScale` active width (`W = w` on an inactive
shelf). `p` card spacing. `V` shelf viewport width. `Lin`/`Tin` leading and trailing insets.
`r` rotation (unbounded `Int`). Virtual index `v` is a position in the unrolled infinite ring:
its card is `cards[floorMod(v, N)]` and its lap is `floorDiv(v, N)`. Slot `s = v - r`; while
animating, `s = v - phase` is continuous.

### 1.2 Slot functions (pure, `RingGeometry`)

```
anchorCenter = leading:  Lin + W/2
               center:   (Lin + V - Tin) / 2
               trailing: V - Tin - W/2
anchorHop    = (W + w)/2 + p           // center distance anchor <-> neighbour
step         = w + p                   // center distance between idle neighbours
emphasis(s)  = max(0, 1 - |s|)         // 1 at the anchor, 0 one slot away
length(s)    = w + (W - w) * emphasis(s)
center(s)    = anchorCenter + sign(s) * (min(|s|, 1) * anchorHop + max(|s| - 1, 0) * step)
```

Because `center` is piecewise linear and `length` is linear in `|s|` on [0, 1], the gap between
neighbours is exactly `p` at every animation frame (verified at s = 0.5 and 1.5: gap 32.0 with
p = 32). Cards never overlap or open gaps mid-flight (R12, R18). Spacing is always `p`, never
stretched to fill the shelf (R16: never justified).

`slotsFittingAfter = ceil((V - (anchorCenter + anchorHop - w/2)) / step)` counts slots after
the anchor that are at least partly visible. `slotsFittingBefore` mirrors it.

### 1.3 Rest window: no repetition (R19, R16)

```
leading:  0 ... min(N-1, slotsFittingAfter)          // nothing at rest before the anchor
trailing: -min(N-1, slotsFittingBefore) ... 0
center:   after  = min(fitAfter, ceil((N-1)/2))
          before = min(fitBefore, N-1-after)
          after  = min(fitAfter, N-1-before)          // an extra card goes to the "next" side
```

The window never holds more than `N` slots, so a short ring never shows a card twice at rest.
Verified cases: leading N=3 gives 0...2; center N=4 gives -1...2 (`D [A] B C`); trailing N=3
gives -2...0 (`B C [A]`); leading N=40 at 1920 pt with 300 pt cards gives 0...5.

Order never reverses. With a trailing anchor, previous cards sit to the left and "next" slides in
from the trailing edge (decision Q3).

### 1.4 Fade rule (R13, R15, R17)

```
opacity(s) = 1                                    if lower <= s <= upper
           = max(0, 1 - (s - upper) / fade)       if s > upper
           = max(0, 1 - (lower - s) / fade)       if s < lower      // fade = fadeLengthInSlots
```

With the default `fade = 1`, a card is fully transparent after one slot of travel past the
ring's rest edge. In that one-slot move the card sweeps across its own width, the gap and the
next slot's width: **2w + p**, the figure in R17. The fade is measured from the ring's rest
edge, not from the screen edge, so a 3-card ring in the middle of a wide shelf fades its leaving
card over the same distance as a long ring at the screen edge ("regardless of distance from the
edge"). Because the fade is in slots, it follows the "current padding" and card size of each
width class automatically. Values above 1 would leave the fade slot partly visible at rest (a
visible repeat, breaking R19), so the setting is clamped to 0.25...1. Q1 in
[etagere.md](etagere.md) lists the alternatives.

Combined with emphasis: the outgoing Active ShelfCard dims, shrinks and fades as it slides off
the leading side (R12), and the far-end card dims and fades as it slides off (R13). With a center
anchor both ends use the same rule (R15).

### 1.5 Render window, identity and ghost copies (R14, D4)

```
renderRange = [min(r, settled) + lower - 1, max(r, settled) + upper + 1]   // virtual indices
id(v)       = RingSlotKey(itemID: cards[floorMod(v, N)].id, lap: floorDiv(v, N))
```

- The extra slot on each side is always at opacity 0, so views are inserted and removed only
  while invisible; no insertion or removal transitions are needed.
- A card leaving one end while entering the other is two views with different laps: the ghost
  copy that "occupies both spots at the same time" (R14). Rendered and checked: in a 3-card
  leading ring moving backward, the last card slides off the far end (lap 0) while its lap -1
  copy grows into the anchor (verified).
- `settledRotation` updates in `withAnimation(_:completionCriteria: .removed) { ... } completion:`
  (as built, each completed flight advances it; see §7.6) and the latest token settles everything, so cards in flight stay rendered until fully gone, even under
  rapid input (D3).
- Card IDs must be unique within a shelf. A host's card factories should guarantee this.

### 1.6 Seam bar (R20)

- Drawn for each rendered copy of the last card (`ringIndex == N-1`), only when `N >= 2`.
- Position: `center(s) + length(s)/2 + p/2`, the middle of the gap after the last card. It uses
  the last card's opacity, so it rides and fades with the ring.
- It shows after the last card even when the first card is not next to it: `A B C |` at rest
  with A anchored, `D | [A] B C` with a center anchor, `B C | [A]` with a trailing anchor.
- With a leading anchor and the first card anchored in a long ring, the seam lies in the exit
  zone before the anchor and is not visible at rest; the user sees it slide out as the ring
  wraps (Q5).
- Style: a 3 pt capsule (4 pt on tvOS), 80% of the idle card height, `.secondary`. Under Increase
  Contrast: 4 pt in the accent color. On iOS, a light haptic when the seam crosses the anchor.

### 1.7 Animation mechanics

```swift
@Animatable
struct RingSlotEffect: ViewModifier {
    var slot: Double          // v - phase; animatable
    var activity: Double      // 1 when the shelf is active, 0 when not; animatable
    @AnimatableIgnored var geometry: RingGeometry
    @AnimatableIgnored var rest: ClosedRange<Int>
    @AnimatableIgnored var idleDim: Double
    @AnimatableIgnored var shelfDim: Double
    @AnimatableIgnored var isRightToLeft: Bool
    func body(content: Content) -> some View {
        // scaleEffect(length/w), brightness(-dim), opacity(rule above),
        // offset(x: center - w/2) mirrored for RTL, zIndex(emphasis)
    }
}
```

- When `rotation` changes inside `withAnimation`, each persisted view interpolates `slot`, and the
  modifier re-evaluates the non-linear rules every frame: cards grow only near the anchor and fade
  only past the rest edge. The card face is opaque `content` and does not re-render.
- Size changes use `.scaleEffect`, never frame changes: faces lay out once at idle size, text
  never reflows, and the cost is a transform.
- Every shelf reserves the enlarged card height (`w / aspect * activeScale`), so activating a
  shelf never reflows the page. Cards are centered on the cross axis by default (`.bottom` is
  offered for box art).
- **Growth reserve (D10).** `activeGrowthReserve` (0...1, default 1) is the part of the growth
  each ring reserves: `h * (1 + (activeScale - 1) * reserve)` for idle card height `h`. Below 1,
  inactive rings keep less empty space under their cards and the Active ShelfCard grows past its
  ring, over the space between shelves, in the direction the cross alignment gives: `.top` grows
  only downward, `.bottom` only upward (into the title's space first), `.center` half each way.
  The active shelf draws above its neighbours, the ring's clip leaves room for the overflow, and
  the Etagere's top and bottom insets grow so the top or bottom shelf's enlarged card stays on
  screen. The Active Shelf highlight keeps the shelf's reserved size; the card may cover its edge.
- The `@Animatable` macro compiles on all three platforms (verified), and frames rendered at
  fractional phases through the prototype's `phaseOverride` hook match the math (verified). The
  live per-frame interpolation has not yet been watched in a running app (believed). Check it by
  eye first.

### 1.8 Rapid input, key repeat, drags and jumps (D3)

- **Never lock input.** Each command updates the model at once (`rotation +/- 1`). `activeCard`
  is the target, so "go" mid-animation plays the card that is arriving.
- **Retargeting.** `.snappy` is a spring; a new transaction retargets from the current
  presentation value and keeps velocity (believed). The render window covers the whole in-flight
  range, so nothing pops.
- **Key repeat.** `onKeyPress` reports `.repeat` phases on macOS and iPad keyboards (verified).
  Repeats use `repeatAnimation`, linear, retimed to the measured repeat interval clamped to
  60-200 ms, so the ring scrolls continuously. tvOS gives no phase; treat move commands under
  180 ms apart as repeats (believed).
- **Drags and flings** (touch, trackpad): render with `phase = Double(rotation) + dragSlots`; on
  release, `delta = round(dragSlots + predictedSlots)` clamped to `±min(N, 30)`, animated with
  `.smooth(duration: 0.45)`.
- **Jumps** (type-ahead, a tap more than 6 slots away, reloads): set `rotation` without animation
  and crossfade the ring (`.id(jumpGeneration)` with `.transition(.opacity)`).
- **Pointer and touch.** A tap or click on a visible non-anchored card rotates to it the shortest
  way (`rotate(toCard:)`; ties go forward). A tap or click on the anchored card activates it.

### 1.9 Inactive shelves and the single selection (R7, R9, R10)

- Each shelf keeps its own rotation, so returning to a shelf finds the same anchored card.
- `activity` animates 1 to 0 when a shelf loses the selection: its anchored card shrinks to idle
  size and the neighbours close up in the same transaction. All its cards dim by
  `inactiveShelfDim`.
- The only selection is `activeShelf.anchoredCard`. `ShelfCardContext.isActive` is true for
  exactly one card in the Etagere.

### 1.10 Content changes, empty and tiny shelves (D8)

- `replaceCards` is a no-op when the ID list is unchanged (a periodic content refresh usually
  is). Otherwise it re-bases `rotation` so the same card ID stays anchored and keeps its lap. If
  that card is gone, the card now at the old anchored index (clamped) is anchored, rather than
  jumping to the first card. (The prototype falls back to index 0; change that.)
- An empty shelf renders `emptyMessage` as one non-rotating placeholder card with no seam (for
  example "Connect a DVR source in Settings"). It stays navigable (decision Q7).
- With `N = 1` there is no rotation and no seam. Left and right are still consumed in mode 1
  (R27) and give a small 8 pt bump instead of moving.

### 1.11 RTL (D2)

Geometry is computed in leading-based coordinates and mirrored with `x' = V - x`. The input layer
maps physical right to `nextCard` in left-to-right layouts and to `previousCard` in right-to-left
layouts. The model never knows the direction.

### 1.12 Cards of different widths (D9)

A card's `cardAspectRatio` (nil by default) gives it its own idle width `w_v = h * clamp(ratio,
0.5, 2.5)`, where `h = w / faceAspectRatio` is the shelf's idle card height; a card without one
has `w_v = w`. The ratio `w_v / w` is all the geometry needs (`RingWidths`). Every card grows by
the same factor `g = W / w`, so heights stay the shelf's and `CardEmphasisEffect` is unchanged.

```
length(v, phase) = w_v * (1 + (g - 1) * emphasis(v - phase))
anchorCenter(v)  = leading: Lin + g*w_v/2,  center: (Lin + V - Tin)/2,  trailing: V - Tin - g*w_v/2
r = floor(phase), t = phase - r
pin       = (1 - t) * anchorCenter(r) + t * anchorCenter(r + 1)
center(r) = pin - t * (length(r)/2 + p + length(r + 1)/2)
center(v + 1) = center(v) + length(v)/2 + p + length(v + 1)/2      // and the mirror for v - 1
```

The anchor point moves from one anchored card's anchor center to the next and divides the
distance between their centers in proportion `t`; every other card follows with exactly `p`
between neighbours. With equal widths this is §1.2's `center(s)` (T25 checks it numerically).

- **Rest window.** Depends on the anchored card: the §1.3 rule, counting cards whose near edge
  is inside the viewport at their own widths. The ring computes it for every rotation in flight
  (plus one on each side), so a step between two anchored cards of different widths can change
  the window.
- **Fades.** Between rotations `r` and `r + 1`, a card in both rest windows is opaque, one only in
  `r`'s fades out over `fadeLength` slots of travel, one only in `r + 1`'s fades in, others are
  transparent. With one window for every rotation this is the §1.4 rule.
- **Render window.** The union of those rest windows around the rotations in flight, plus one
  transparent slot on each side (§1.5). Widths are read for a window of virtual indices bounded by
  how many of the narrowest allowed cards fit in the viewport, so the cost still follows the
  viewport, never `N` (D4).
- **Seam, ghosts, drags.** The seam sits in the middle of the gap after the last card at its own
  width; ghost copies are separate virtual indices, so they take their card's width. Drags and
  scrubs convert points to slots with the mean idle width of the anchored card and the next one,
  plus `p`.
- **Uniform rings.** When every card in the window has the shelf's width, the ring stores no
  widths and uses the uniform functions, so a host that never sets `cardAspectRatio` draws exactly
  as before. The placeholder card of an empty shelf has the shelf's shape.

---

## 2. Vertical navigation

### 2.1 Mode 1: the ShelvesRing (default; R21, R22, R23, R25, R27)

```
 Mode 1, verticalAlignment = .top, 3 shelves, "next shelf" pressed

             before                           after
 +----------------------------+   +----------------------------+
 |#Favorites   [A] B C D ...  |   |#Live TV     [A] B C D ...  |  <- highlight (#) stays at the anchor
 | Live TV      A  B C D ...  |   | Recent       A  B C        |
 | Recent       A  B C        |   | Favorites    A  B C D ...  |  <- lap +1 copy, faded in from below
 +----------------------------+   +----------------------------+
 During the move, Favorites slides up and fades out above the anchor while its next-lap copy
 enters at the bottom. Only the active shelf's anchored card is enlarged ([A]).
```

- `VerticalShelfRing` reuses `RingGeometry` on the y axis: `idleLength` = title height + reserved
  shelf height, `activeLength == idleLength` (shelves do not grow), `spacing` = shelf spacing,
  anchor from `verticalAlignment`. Same rest window (no repeated shelves at rest with a typical 3-5
  shelves), same fade rule, same `(shelfID, lap)` identity. Both copies of a wrapping shelf
  observe the same `ShelfState`; only the copy nearest the anchor is active. Rendered with a
  wrapping ghost shelf (verified, via `phaseOverride`).
- **Indicator.** A tinted rounded rectangle (`.tint.opacity(0.12...0.16)`) fixed at the anchor
  slot; shelves slide beneath it. Not Liquid Glass: glass belongs to the floating navigation
  layer (for example the app's sidebar).
- **Highlight width (D12).** Both modes' highlights span the shelf between the horizontal insets,
  reaching half an inset past them. When the Active Shelf's cards run past an edge at rest (a card
  in its rest window starts before the leading inset or ends after the trailing one), the highlight
  runs past that edge by its corner radius, so its square end meets the edge and the tint follows
  the cards off screen. A shelf rotation or a new Active Shelf that changes this animates with
  `highlightAnimation`. `extendsHighlightPastEdges = false` keeps the highlight inside the insets.
- **Shelf seam.** A horizontal bar between the last and first shelf, by the same rule as §1.6
  (`showsShelfSeam`, Q4).
- **Input capture (R27).** The Etagere is one focusable element and consumes up, down, left and
  right; vertical moves always return `true`. A page using mode 1 has no other focusable
  controls: page actions such as "Edit Home" go in the context menu or settings (Q6).
- **Leaving.** Back/Menu on tvOS (`onExitCommand`), Esc on macOS (`onExitCommand`) and iOS
  (`onKeyPress(.escape)`), or controller B, calls `onExit`; the host moves focus (for example to
  its sidebar).
  Tab on macOS and iPad still moves keyboard focus, as full keyboard access requires.
- **tvOS focus trap.** The host disables the region that does not own focus (for example its
  sidebar while content has focus), so a left swipe cannot be taken by the focus engine. This is believed to
  work and must be checked on a device. One research note suggested `.focusSection()` on the
  Etagere instead; `focusSection` guides focus between sections but does not stop it leaving, and
  it is unavailable on iOS (verified), so the region-disable approach is the primary one.

### 2.2 Mode 2: cursor (R24, R25, R26, R28)

```
 +--------------------------------+
 | [ controls above, if any ]     |  <- "up" from the top shelf moves focus here (proposed)
 |#Favorites   [A] B C D ...      |  <- one highlight view slides between rows
 | Live TV     [A] B C ...        |
 | Recent      ...                |  ScrollView keeps the active row at verticalAlignment
 +--------------------------------+
```

- `ScrollView(.vertical)` with a `LazyVStack` of shelves, `.scrollTargetLayout()`, and
  `.scrollPosition(id:anchor:)` where the anchor is `verticalAlignment` (`.top/.center/.bottom`).
  When shelves overflow, the active shelf is kept at the vertical anchor where possible (R26).
  No wrap in mode 2.
- **Indicator.** One tinted rounded rectangle behind the active shelf with
  `matchedGeometryEffect(id: "activeShelf", in:)`, animated with `highlightAnimation` so it slides
  up and down (R25). It spans the shelf as in mode 1, past an edge its cards run past (D12).
- **Edges and the truncated sentence (R28).** Proposed completion: "...above or below the
  Etagere, up on the top shelf (or down on the bottom shelf) moves focus out of the Etagere to
  those controls; if there are none, the cursor stops at the edge with an 8 pt rubber-band bump
  and does not wrap." `move()` returns `false` at an edge and the host's `onEtagereEdge` callback
  moves focus. See Q2 for the alternatives that were rejected.
- **tvOS.** Each shelf is its own focus target, so vertical movement is native focus, which is
  reliable for swipes, scrolls automatically and reaches controls above and below. Each shelf
  handles only left/right with `onMoveCommand`. The host's disabled sidebar region keeps "left"
  from leaking out.
- **macOS and iPad keyboards.** Arrow keys do not move focus between focusable views natively
  (only Tab does), so the Etagere handles up/down with `onKeyPress` and calls `onEtagereEdge` at
  the ends.
- **Touch.** The scroll view scrolls natively; tapping a shelf makes it active.

---

## 3. Input

### 3.1 Intents

Every platform maps its input to `EtagereIntent`: the four `EtagereMove` cases, `activate`,
`contextMenu` and `exit`. The SwiftUI mapping (`EtagereInput`) compiles for macOS, iOS and tvOS
(verified). The physical-to-logical key map is a pure function (`EtagereKeyMap`) so it can be
unit tested, including RTL. Extra drivers feed the same model methods.

### 3.2 Mapping

| Intent | tvOS (Siri Remote, controllers) | macOS | iPadOS / iOS (incl. iPhone Duo) |
|---|---|---|---|
| previous/next card | Clickpad left/right and horizontal swipes (`onMoveCommand`) | Left/right arrows (`onKeyPress`, with repeat); two-finger trackpad scrub; click a card | Horizontal drag/fling; tap a card; hardware arrows |
| previous/next shelf | Up/down and swipes: `onMoveCommand` in mode 1, native focus in mode 2 | Up/down arrows (`onKeyPress`) | Mode 1: vertical drag on the Etagere. Mode 2: native scroll, tap a shelf |
| activate ("go", R8) | Select click (`onTapGesture`), Play/Pause (`onPlayPauseCommand`, unless the host claims it with `.onEtagerePlayPause`, for example to dismiss a mini player) | Return, keypad Enter, Space, K; double-click | Tap the anchored card; Return, Space, K; controller A |
| context menu | Long-press Select (`contextMenu`, or `onLongPressGesture(minimumDuration: 0.5)`) | Right-click | Long-press with preview |
| exit (to the host) | Menu/Back (`onExitCommand`). The host must not handle it at its top level, so Menu there returns to the tvOS Home screen | Esc (`onExitCommand`) | Esc (`onKeyPress(.escape)`); controller B |

Verified SDK facts behind this table: `onMoveCommand`, `onExitCommand` and `focusSection` are
unavailable on iOS; `onPlayPauseCommand` is tvOS-only; `keyboardShortcut` is unavailable on tvOS;
`onKeyPress` with phases exists on macOS 14, iOS 17 and tvOS 17.

### 3.3 Platform notes

- **tvOS dropped presses.** Forum reports (FB15272007, FB16045173) say `onMoveCommand` and
  `Button` can miss the first press after a view loads or after a direction change on the silver
  Siri Remote; status on tvOS 26/27 is unknown. Fallback behind a flag: a UIKit bridge view that
  overrides `pressesBegan`/`pressesEnded`, adds an indirect-touch pan recognizer for fling
  velocity and a Select long-press recognizer, and refuses focus updates while content owns
  focus (believed; not compiled).
- **tvOS swipe tails.** A swipe can end with a stray command on the other axis. Ship without a
  gate, log cross-axis moves less than 150 ms after a swipe, and revisit after device testing
  (another project's 700 ms gate was reverted because it ate deliberate quick swipes).
- **macOS trackpad.** SwiftUI has no scroll-wheel modifier (verified). Use a local `NSEvent`
  scroll monitor scoped to the hovered shelf and removed on disappear, or it will swallow scroll
  events app-wide (believed; sketch not compiled). Shift + wheel or a horizontal wheel steps one
  card per notch. Hover gives a subtle highlight.
- **iOS touch.** Inside a vertical `ScrollView` a SwiftUI `DragGesture` competes with scrolling.
  Use `UIGestureRecognizerRepresentable` (iOS 18+, iOS-only, verified) with a pan recognizer that
  begins only when horizontal velocity dominates. `sensoryFeedback(.selection)` on rotation.
- **Game controllers.** A `GCController` bridge for iOS and macOS: d-pad and left stick
  (threshold 0.5) move with 400 ms initial and 110 ms repeat; A activates, B exits; the Home
  button is left to the system. On tvOS the focus engine already drives controllers (believed).

---

## 4. Accessibility and Reduce Motion (D6)

- **VoiceOver.** Each shelf is one adjustable element: label = shelf title, value =
  "card title, 3 of 8", increment/decrement rotate, the default action activates, and named
  actions such as "Add to Multi-view" and "Favorite" mirror the context menu. VoiceOver focus on
  a shelf makes it the Active Shelf. Add a "Shelves" rotor. Announce "Start of list" when the
  seam crosses the anchor. On tvOS, where mode 1 is one big focusable element, keep its label and
  value live for the active shelf and card.
- **Card labels.** `accessibilityTitle` gives a full phrase, for example "KUSA 9.1, NBC, live now,
  favorite".
- **Reduce Motion.** No sliding: positions update without animation (`move(..., reduceMotion:
  true)` passes a nil animation, as in the prototype), and only the old and new active cards
  crossfade their emphasis over 150 ms. The vertical ring and the mode 2 highlight crossfade too.
- **Increase Contrast.** A 4 pt accent seam, an outline on the Active ShelfCard and a stronger
  shelf tint.
- **Keyboard focus.** `focusEffectDisabled()` removes the system ring, so draw our own accent
  ring around the Active ShelfCard while the Etagere has keyboard focus.
- **Text.** Dynamic Type for titles on macOS and iOS; tvOS uses its type ramp and Dynamic Text.

---

## 5. Performance (D4, D5)

- Rendered views per shelf = rest window + 2 fade slots + slots in flight, independent of `N`.
  At 1920 pt with 300 pt cards that is about 8 views at rest (verified by construction).
- Each `ShelfState` is its own `@Observable`, so rotating one shelf invalidates only that
  `ShelfRingView`; per-frame work is that shelf's `RingSlotEffect` bodies.
- One geometry read (`onGeometryChange` or `GeometryReader`) per shelf, never per card.
- Faces stay cheap and `Equatable`. `.compositingGroup()` per card; never `.drawingGroup()` on
  faces with text.
- No live video in cards. Never tune a channel or start a stream to make a thumbnail: on a TV
  tuner each grab would hold a tuner. Network art uses `AsyncImage`, which caches HTTP responses on the 27
  SDKs (verified from the WWDC26 session summary); local thumbnails go through an `NSCache`-backed
  ImageIO downsampler at display size.
- Measure rotation under key repeat with the Instruments SwiftUI template on macOS first, then on
  Apple TV. The `@Animatable` path has not been profiled under fast input (believed fine).

---

## 6. Starting metrics (tune on device)

Chosen from the container width (D7), never from device type.

| Width class | cardWidth (16:9) | activeScale | cardSpacing | shelfSpacing | Title font |
|---|---|---|---|---|---|
| Compact, < 500 pt | `clamp(width * 0.46, 150, 230)` | 1.15 | 14 | 18 | `.headline` |
| Medium, 500-900 pt | `clamp(width * 0.24, 170, 240)` | 1.25 | 20 | 24 | `.title3.bold()` |
| Regular, 900-1600 pt | `clamp(width * 0.19, 200, 320)` | 1.3 | 24 | 28 | `.title2.bold()` |
| tvOS, 1920 pt | 360 | 1.25 | 40 | 36 | tvOS `.headline` |

Animations: card step `.snappy(0.28)`, repeat linear 60-200 ms, shelf step `.snappy(0.32)`,
highlight `.snappy(0.3)`. On tvOS read the safe-area insets for the leading inset; do not
hardcode them.

Each class also starts with a title-to-cards gap (12 pt on tvOS, 6 pt elsewhere), a horizontal
inset (16, 24 and 32 pt, 48 pt on tvOS; a larger safe area wins) and a growth reserve of 1. A
host can change all three, and the title style, with `.fixed` metrics (D10). `.callout`, a step
below `.headline`, is offered for dense layouts; no class starts with it. tvOS started with its
`.title3` (`.televisionTitle3`, still available) until 2026-11-21, when it proved too large on a
real screen; it now starts with tvOS's `.headline`.

`titleFontSize` (nil by default) sets the title's point size in place of its style's. The title
keeps the style's weight (regular for `.callout`, semibold for `.headline`, bold for `.title3Bold`
and `.title2Bold`, medium on tvOS) and still scales with Dynamic Type relative to the style's text
style; the "Updating" status beside it is 80% of its size, so it never sets the line's height.
Until the Etagere measures the title, a point size `s` is estimated at `ceil(1.25 s)`, which gives
each style's own estimate at its default size. Zero, negative and non-finite sizes count as nil.

### 6.1 Fitting shelves to a height (D10)

The top and bottom insets are `round(shelfSpacing * 0.4) + 4` (the highlight's reach plus 4 pt),
or the safe area when it is larger, or more when an Active ShelfCard grows past its shelf (§1.7).
`count` shelves take `topInset + bottomInset + count * shelfHeight + (count - 1) * shelfSpacing`,
with `shelfHeight = titleHeight + titleSpacing + reservedRingHeight`.
`EtagereResolvedMetrics.fitting(shelves:in:aspectRatio:...)` returns the largest card width at
which `count` shelves fill a height, found by bisection on that same layout so it keeps fitting if
these formulas change; with the default reserve it equals the closed form. `EtagereMetrics.fitting`
does it inside the Etagere with the title height it measures. In mode 1 with a top anchor the
fitted shelves are the rest window; a bottom inset larger than the shelf spacing leaves the next
shelf peeking into it.

---

## 7. Test plan

Unit tests use Swift Testing (`import Testing`), run on macOS with no network or devices, and
are parameterized across anchors, ring sizes `N` in {1, 2, 3, 4, 8, 40} and viewport widths
{400, 1280, 1920}.

### 7.1 EtagereKit unit tests

| ID | Test | Requirements |
|---|---|---|
| T1 | `restWindow` never holds more than `N` slots; leading never shows slots < 0, trailing never > 0; center puts the extra card on the "next" side. Known cases: leading N=3 → 0...2, N=40 at 1920 → 0...5, center N=4 → -1...2, N=3 → -1...1, trailing N=3 → -2...0 | R16, R19, R15 |
| T2 | `anchorCenter` per alignment: leading = `Lin + W/2`, center = midpoint, trailing = `V - Tin - W/2` | R6, R16 |
| T3 | Constant gap: for `s` from -3 to 6 in 0.05 steps, the gap between cards at `s` and `s+1` equals `p` within 1e-6 | R12, R18 |
| T4 | `length(0) == W`, `length(±1) == w`, monotonic in between; with activity 0, `length(0) == w` | R7, R10, R12 |
| T5 | Opacity is 1 inside the window, 0.5 at `upper + 0.5`, 0 at `upper + fade` and `lower - fade`; `fadeLengthInSlots` is clamped to 0.25...1 | R13, R15, R17 |
| T6 | Fade distance in points over one slot equals `step` whether the ring ends at the screen edge (N=40) or mid-shelf (N=3 in a 3000 pt viewport) | R17 |
| T7 | Backward wrap, N=3, rotation -1, settled 0: card C is rendered twice with laps [-1, 0]; render count is independent of N (N=12 vs N=10,000) | R14, D4 |
| T8 | Render range covers every in-flight slot when `rotation = settled + 5` | D3 |
| T9 | `floorDiv`/`floorMod` with negative values | R11 |
| T10 | Seam owners: only `ringIndex == N-1`; none when N=1; bar at the middle of the gap | R20 |
| T11 | `rotate(by:)` moves the anchored index by `floorMod`; no-op for N ≤ 1 | R11 |
| T12 | `rotate(toCard:)` takes the shortest way; ties go forward | R11 |
| T13 | Only the latest settle token updates `settledRotation` | D3 |
| T14 | `replaceCards`: same IDs is a no-op; reorder keeps the anchored ID and lap; removal anchors the card at the old index | D8 |
| T15 | A multi-shelf model has exactly one card with `isActive == true`; `activeCard == activeShelf.anchoredCard` | R1, R2, R8, R9, R10 |
| T16 | The default `verticalMode` is `.ring`. Mode 1: vertical moves always return true and wrap; left/right return true even for N ≤ 1. Mode 2: returns false at the top and bottom, no wrap | R21, R22, R24, R27, R28 |
| T17 | Vertical geometry: `activeLength == idleLength`; 3-5 shelves never repeat at rest; top/center/bottom anchors | R22, R23 |
| T18 | `EtagereKeyMap`: arrows → moves in LTR and mirrored in RTL; Return, keypad Enter, Space, K → activate; Esc → exit | R8, R11, D2 |
| T19 | With `reduceMotion`, the chosen animation is nil and the model state matches the animated path | D6 |
| T23 | Reuse: a test-only `BoxArtCard` (aspect 0.71, no SwiftUI beyond its face) drives the same model and renders through T22's harness | R4, D1 |
| T24 | A ring whose list shrinks on screen: in a live hosting view (not `ImageRenderer`, which never reuses a tree), remove the last shelf and cards, then the Active Shelf and its anchored card, in both modes; nothing traps. Each ring indexes the same snapshot of its list that its render slots came from | D8 |
| T25 | Cards of different widths: with equal widths the general slot functions equal §1.2; mixed widths keep the gap at `p` for phases -3...6; at rest the anchored card sits at the Anchor Spot at its enlarged width; positions are continuous across rotations; ratios clamp to 0.5...2.5 and invalid ones keep the shelf's shape; the seam follows the last card's width; a rendered poster card is narrower than its 16:9 neighbours | D9, R6, R12, R18, R20 |
| T26 | Per-rotation rest windows count cards at their own widths and equal §1.3 for equal widths; fades out of one window and into the next are continuous and equal §1.4 for one window; the widths window is the same for 40 and 10,000 cards | D9, R13, R17, R19, D4 |
| T27 | Layout knobs: `.callout` and its estimate; per-class title gap and inset, custom ones reaching the layout, the safe area winning; the growth reserve's ring height and clamping; overflow direction by cross alignment and the insets that keep it on screen | D10 |
| T28 | Fitting: three tvOS shelves fill 1080 pt as the closed form gives and are mode 1's rest window; fitting with a safe area and with a card growing past its ring; edge cases; `EtagereMetrics.fitting` resolves to the helper | D10 |
| T29 | Context menus: dividers never lead, trail or repeat; VoiceOver's actions skip dividers and Cancel | D11 |
| T30 | Title point size: the estimate from a point size and the fallback for invalid ones; the rule matching each style's estimate; fitting with a larger title gives smaller cards; a rendered title follows the size, and its status stays smaller | D10 |
| T31 | Highlight overflow: a long ring runs past the far edge for each anchor and a short one fits; narrow and wide card shapes change it; the highlight's insets inside and past an edge; rendered in both modes, the tint reaches the trailing edge only with overflowing cards and the option on | D12 |

### 7.2 Host app tests

These belong to the host app, not this package (etagere.md §5):

| ID | Test | Requirements |
|---|---|---|
| T20 | The host's card factories build stable IDs, never a host name or address (fixtures, not the network); empty shelves carry their message | R3, R5, R29 |
| T21 | Lint self-test: run SwiftLint explicitly, with the app's config, on a fixture containing `Shelf<GameBox>` and expect the one-card-type rule to fail; the typealias passes. The fixture lives outside the linted paths, so the strict lint never sees it | R5 |

### 7.3 Snapshot smoke tests

T22: `ImageRenderer` renders one shelf per anchor at phases {0, 0.25, 0.5, 0.75, 1} and the
vertical ring at {0, -0.5, -1}, through the `phaseOverride` hook. Assert a non-nil image of the
expected size, plus mode 2 with the highlight on two different rows. Pixel diffs are optional.
Covers R12-R15, R20, R22, R25.

### 7.4 Manual checks

Watch the live `@Animatable` interpolation (the open (believed) item); arrow keys at the fastest
key-repeat setting; trackpad scrub and fling; Esc leaving the Etagere and Tab behavior in mode 1;
mode 2 edge escape, and mode 2 with more shelves than fit (it scrolls and keeps the active shelf
at the vertical anchor); VoiceOver adjustable shelves and the seam announcement; Reduce Motion;
Increase Contrast; an RTL pseudo-language. tvOS, iPad, iPhone and iPhone Duo checks come with
those platforms: remote clickpad vs swipe, the dropped-press bug, Menu at the root leaving the
app, the disabled-sidebar trap, touch drag inside a vertical scroll view, controllers, and fold
and unfold without losing the selection.

### 7.5 Traceability

| Requirement | Tests or checks |
|---|---|
| R1, R2 | T15, T22 |
| R3 | T20 |
| R4 | T23 |
| R5 | T20, T21 (plus the compiler: an `Etagere<VideoCard>` cannot hold another type) |
| R6 | T2 |
| R7 | T4 |
| R8 | T15, T18 |
| R9 | T15 |
| R10 | T4, T15 |
| R11 | T9, T11, T12, T18 |
| R12 | T3, T4, T22, manual |
| R13 | T5, T22 |
| R14 | T7, T22 |
| R15 | T1, T5, T22 |
| R16 | T1, T2 |
| R17 | T5, T6 |
| R18 | T3, manual |
| R19 | T1 |
| R20 | T10, T22 |
| R21 | T16 |
| R22 | T16, T17, T22 |
| R23 | T17 |
| R24 | T16 |
| R25 | T22, manual |
| R26 | manual |
| R27 | T16, manual (Esc and Back) |
| R28 | T16 (once Q2 is answered) |
| R29 | T20 |
| D1 | T23; package builds for macOS, iOS and tvOS in `make build` |
| D2 | T18, manual RTL |
| D3 | T8, T13, manual key repeat |
| D4 | T7 |
| D5 | Code review: faces never play or tune live video |
| D6 | T19, manual VoiceOver, Reduce Motion, Increase Contrast |
| D7 | Code review: metrics come from container width only |
| D8 | T14, T24 |
| D9 | T25, T26 |
| D10 | T27, T28, T30 |
| D11 | T29; manual: the divider in a tvOS long-press menu |
| D12 | T31 |

---

## 7.6 As built (2026-10-11)

The package implements this spec with these differences, each checked during the build:

- **RTL.** SwiftUI already mirrors leading-based offsets and `.leading` alignment in right-to-left layouts (checked with `ImageRenderer`), so `RingSlotEffect` does not mirror again; a pixel test pins it. Drags and trackpad scrubs are physical movements, so `RingDragMath` still mirrors them.
- **Two effects.** `RingSlotEffect` handles position, opacity and stacking order; `CardEmphasisEffect` handles scale and brightness. Under Reduce Motion positions jump and nothing zooms: a card that gains or loses the emphasis is replaced at its new size and the two crossfade over 150 ms, while other cards' dimming eases over the same 150 ms. The vertical ring and the mode 2 highlight crossfade.
- **Render window under held keys (D4).** Each animated rotation is a flight with its own settle token (`RingFlights`). The window covers every rotation since the oldest flight still running began (`rotationsInFlight`), so overlapping animations never drop a card in flight, and it moves up behind them as they end: a held key keeps it two or three cards wider than at rest, however long the ring. The latest token still settles everything, a jump forgets all flights, and a backstop caps the window at 40 slots from the target if a completion never arrives. `settledRotation` now means where the oldest running animation began; T13 is updated accordingly (an older token shrinks the window only up to the newer flights; a stale token changes nothing).
- **Game controllers are fed by the host.** EtagereKit installs no GameController handlers, because they belong to whoever set them last. The host forwards the d-pad, left stick, A and B to an `EtagereGamepad`, and `.etagereGamepad(_:requiresFocus:)` lets an Etagere take them only while it has focus in an active window. Each call reports whether the input was taken, so B can fall back to the host's back action.
- **Play/Pause.** `.onEtagerePlayPause` runs first; true keeps the press for the host (for example to dismiss a mini player while something plays), false plays the Active ShelfCard.
- **tvOS mode 2 edges.** The top and bottom rows carry their own move command: when the focus engine finds nothing beyond the edge, `onEtagereEdge` runs or the cursor bumps 8 pt; between rows, up and down stay native focus moves. A command within 100 ms of focus arriving on the row is ignored. Believed, checked by tvOS UI tests: a row receives the command only when focus cannot move.
- **Shelf status.** `Shelf.isUpdating` shows a subdued "Updating" after the title and adds ", Updating" to the shelf's VoiceOver value. It never moves a card.
- **Snapshots.** Besides the T22 smoke renders, pixel checks pin the mode 2 highlight on the active row, the mode 1 highlight fixed at the anchor for each vertical alignment, the seam bar in the middle of the gap after the last card, and the shelf status.
- **One geometry read for the whole Etagere**, not one per shelf: every ring gets the same layout.
- **Opacity blends between the active and inactive rest windows**, because an inactive ring can show one more card than the active one; without the blend a card popped when its shelf became active.
- **VoiceOver focus tracking** is attached only while VoiceOver runs (`accessibilityFocused` makes `ImageRenderer` draw blank). Backward wraps announce "End of list", forward wraps "Start of list". Strings are English until the package gets a string catalog.
- **Context menus are data.** `.etagereContextMenu` takes `EtagereAction` values, so the menu and VoiceOver's named actions always match. `.onEtagereEdge` returns `true` when the host moved focus; otherwise the 8 pt bump plays.
- **Pointer input.** Drags, trackpad scrubs and wheel notches turn the shelf under the pointer without selecting it; taps select. VoiceOver focus and taps on a mode 1 shelf turn forward to the tapped copy rather than the shortest way, so VoiceOver focus stays on that element.
- **Snapshots.** Any `EtagerePhaseOverride` draws mode 2 without its scroll view, because `ImageRenderer` can't draw a scroll view on macOS.
- **Not built yet:** tvOS swipe-tail logging and the remote bridge's pan and long-press recognizers (the bridge handles presses only).
- **Seen only in tests so far** (add host-fed controllers, the Play/Pause hook and the tvOS mode 2 edges): the live `@Animatable` interpolation under key repeat, retargeting and settling, the mode 2 highlight and scroll anchoring, trackpad and wheel input, iOS drag inside a scroll view and haptics, controllers, the tvOS remote paths, VoiceOver, Reduce Motion, Increase Contrast and RTL (the manual checks in §7.4).
- **Host customization (2026-11-21, D9-D12).** Cards may set their own width (§1.12), the layout
  knobs of §6 and §6.1 are public (the title's point size among them), and context menus take
  dividers. A divider is drawn with
  `Divider()`; that it shows as a separator in a tvOS long-press menu is believed, not yet seen on a
  device. Variable widths are checked by unit and pixel tests; their animation has not been watched
  in a running app. The Active Shelf highlight follows overflowing cards past the edge (D12) and
  tvOS titles start at `.headline`; both are checked in rendered frames on macOS, not yet on a TV.
- **Since then (2026-10-16):** used in a host app on a Mac and a real Apple TV (Siri Remote clicks and swipes, Select through a button, Back to the host) and driven by the host's tvOS UI tests in the simulator. Touch drag inside a scroll view, haptics, hardware keyboards and game controllers still need a check on a real device.

---

## 8. Risks

- **tvOS dropped presses and the focus trap** are unverified on tvOS 26/27. Mitigation: the UIKit
  bridge behind a flag and early device testing.
- **Mode 1 is unconventional on tvOS.** One large focusable element needs careful VoiceOver
  labels, and App Review expects Menu at the root to leave the app.
- **`@Animatable` under very fast input** has not been profiled.
- **Fade rule** was chosen from four readings of R17 (Q1); `fadeLengthInSlots` tunes it.
- **Trackpad monitor scope**: an unscoped monitor would swallow scrolling app-wide.

---
