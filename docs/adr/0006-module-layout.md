# 6. Module layout: one SwiftPM target per layer or adapter group

Status: accepted, 2026-10-11

## Context
Decision 5 adopts clean / hexagonal architecture enforced by module boundaries. Spec §13.1 lists `SextantKit`, `SextantBoard`, `SextantDevice`, `SextantBuild` and `SextantApp`, which predate that decision and mix layers (`SextantKit` holds both the model and the undoable editor store; `SextantDevice` holds both I/O and the live session).

## Decision
One package at the repo root with targets `SextantDomain`, `SextantApplication`, `SextantStorage`, `SextantOryx`, `SextantBuild`, `SextantDevice`, `SextantUI`, the executable `SextantApp` (composition root) and the dev-tool executable `SextantSnapshots`. `SextantBoard` becomes the folder `SextantUI/Board`. Live and build orchestration move into use cases in `SextantApplication`; the device and build targets keep only I/O.

## Consequences
- A wrong import fails to compile. Adapters cannot see each other or the UI.
- Nine targets instead of five; each test target mirrors one of them.
- The board is not reusable outside `SextantUI`, which is fine because the HUD and menu bar extra are UI too.
