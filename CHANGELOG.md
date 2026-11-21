# Changelog

EtagereKit follows [Semantic Versioning](https://semver.org). Before 1.0, a minor version may
change the API.

## 0.2.0

What a host needs to fit the Etagere to its own layouts, without copying EtagereKit's internals.

- **Cards sized by their artwork** (D9): `ShelfCardContent.cardAspectRatio` (default nil) gives a
  card its own width, the shelf's card height times that ratio, clamped to 0.5...2.5. Every card
  keeps the shelf's idle and active heights. Positions, the constant gap, rest windows, fades, the
  seam and ghost copies follow each card's width. Cards without a ratio draw exactly as before.
- **Title style `.callout`**, a step below `.headline`, with `EtagereTitleStyle.estimatedHeight`
  now public.
- **Adjustable title size:** `EtagereResolvedMetrics.titleFontSize` (default nil) sets the shelf
  title's point size. The title keeps its style's weight and still scales with Dynamic Type; its
  status text is 80% of it. With `estimatedTitleHeight`, `validTitleFontSize`,
  `EtagereTitleStyle.textStyle`, `.weight` and `estimatedHeight(pointSize:)`.
- **`EtagereResolvedMetrics`** gains `titleSpacing`, `horizontalInset` and `activeGrowthReserve`
  (with `defaultTitleSpacing(for:)`, `defaultHorizontalInset(for:)`, `clampedGrowthReserve`,
  `activeOverflow(aspectRatio:)`, `highlightVerticalPadding` and `verticalInset`). The new
  initializer parameters have defaults that keep today's values. A growth reserve below 1 lets the
  Active ShelfCard grow over the space between shelves instead of every ring keeping room for it.
- **Fitting shelves to a height:** `EtagereResolvedMetrics.fitting(shelves:in:aspectRatio:...)`
  and `EtagereMetrics.fitting(shelves:base:)`, resolved inside the Etagere with its measured title
  height, plus `EtagereMetrics.resolved(containerSize:...)`.
- **The highlight follows overflowing cards** (D12): when the Active Shelf's cards run past the
  edge of the Etagere, its highlight runs past that edge with them instead of ending at the inset.
  On by default; `EtagereConfiguration.extendsHighlightPastEdges = false` restores the old look.
- **Smaller tvOS shelf titles:** tvOS now starts with `.headline` instead of `.televisionTitle3`
  (tvOS `.title3`), which is still available. Set `titleStyle` or `titleFontSize` for another size.
- **Context menu dividers:** `EtagereAction.divider`. Dividers first, last or doubled are dropped;
  VoiceOver's named actions skip dividers and actions with the `.cancel` role.
- **Breaking:** `EtagereTitleStyle` and `EtagereMetrics` have new cases, so an exhaustive `switch`
  over either needs them.

## 0.1.1

- Fixed a crash (`Index out of range`) when shelves or cards were removed while the Etagere was
  on screen: a ring now indexes the same snapshot of its list that its render slots came from
  (T24). No API change.

## 0.1.0

First public release: the Etagere, shelves of rotating card rings, with both vertical navigation
modes, input for keyboards, trackpads, touch, the Siri Remote and game controllers, VoiceOver
support, and position save and restore.
