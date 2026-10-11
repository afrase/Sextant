# Sextant

A native macOS (Swift/SwiftUI) configurator for the ZSA Voyager. It edits layouts locally, imports from Oryx, builds firmware, flashes it, and shows what the keyboard is doing live.

Sextant is an independent project, not affiliated with or endorsed by ZSA Technology Labs. "ZSA", "Voyager", "Oryx" and "Keymapp" are ZSA's marks; they are used here only to describe compatibility.

## Status

Research and UI design are done; code design is next.

- [docs/research/00-overview.md](docs/research/00-overview.md): how Oryx works end to end, the recommended architecture, feature tiers, risks, open decisions and gaps.
- [docs/oryx-ui/](docs/oryx-ui/): a screenshot tour of Oryx's viewer and editor, with design takeaways.
- `docs/research/data/`: machine-readable artifacts covering geometry, the matrix/LED map, keycodes, settings, the GraphQL operations and flash constants.
- `docs/research/oryx-examples/`: the user's layout and 5 public Voyager layouts, plus their Oryx-generated QMK sources, for golden tests.
- [docs/design/ui-spec.md](docs/design/ui-spec.md): the UI specification. It uses the Instrument direction as the base and grafts in parts of the other two. Open taste questions are in `docs/design/open-questions.json`.
- [docs/design/directions.md](docs/design/directions.md) and [docs/design/judging.md](docs/design/judging.md): the three prototype directions and how they were judged.
- `design/`: the shared `PrototypeKit` and three runnable SwiftUI prototypes. Run one with `swift run` in its folder, or render snapshots with `--snapshot`.

