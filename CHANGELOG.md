# Changelog

EtagereKit follows [Semantic Versioning](https://semver.org). Before 1.0, a minor version may
change the API.

## 0.1.1

- Fixed a crash (`Index out of range`) when shelves or cards were removed while the Etagere was
  on screen: a ring now indexes the same snapshot of its list that its render slots came from
  (T24). No API change.

## 0.1.0

First public release: the Etagere, shelves of rotating card rings, with both vertical navigation
modes, input for keyboards, trackpads, touch, the Siri Remote and game controllers, VoiceOver
support, and position save and restore.
