- always run `make build` after every code change. It runs the linter, the unit tests, and the iOS and tvOS simulator builds; its exit code must be 0 before the work is done. Documentation-only changes don't need it.

- linter rules to follow before you write code, so `make build` doesn't send you back:
  - max 400 lines per file; split into more files instead.
  - max 120 characters per line.
  - var/let names and struct members at least 3 characters long (`id` and `url` are allowed).
  - function bodies under 150 lines and type bodies under 400, not counting comments.
  - cyclomatic complexity of 15 or less per function (`make lint` uses `--strict`, so the warning level fails).

- do not use the plus (+) character in filenames.

- EtagereKit is app-agnostic and has no dependencies. Never add an app's types, branding, identifiers, `UserDefaults.standard` or notification names; whatever an app needs (storage, focus targets, game controllers, Play/Pause) is injected or handled through the public hooks.

- Swift 6 language mode with MainActor default isolation. Card types and other value types (configuration, geometry, positions) are `nonisolated`; `EtagereModel`, `ShelfState` and the views stay on the main actor; `makeFace` is `@MainActor`.

- multiplatform: macOS 26.0, iOS/iPadOS 26.0 and tvOS 27.0. Every change must compile for all three (`make build` builds them). Keep platform-specific code small and in per-platform files (the `_macOS`, `_iOS` and `_tvOS` suffixes) rather than scattered `#if os(...)`.

- `docs/etagere.md` and `docs/etagere-behavior.md` are the spec. Requirements (R…, D…), tests (T…) and design decisions (Q…) are numbered, and code comments and tests cite them; keep the IDs stable and record changes in the docs in the same change (behavior §7.6 lists where the build differs from the spec).

- unit tests use Swift Testing (`import Testing`) in `Tests/EtagereKitTests`. They run on macOS with `make test` and never need the network or a device. Snapshot tests render with `ImageRenderer`.

- public API changes: note them in `CHANGELOG.md` and the README's usage section. Before 1.0 a minor version may break the API; after it, follow semantic versioning.
