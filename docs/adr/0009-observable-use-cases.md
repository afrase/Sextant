# 9. Use cases that hold UI-facing state are `@MainActor @Observable`

Status: accepted, 2026-10-11

## Context
Editing with undo, import, the live session and Build & Flash are use cases (application layer), and SwiftUI views must observe their state. Mirroring that state into separate view-model copies would duplicate every property.

## Decision
`EditSession`, `Library`, `ImportFromOryx`, `LiveSession` and `BuildFlashSession` are `@MainActor @Observable` classes in `SextantApplication`. Observation is a standard-library module, not a UI framework. UI view models hold a use case and add only presentation state (lens, legend mode, picker query, popover flags). The editor selection (layer, key, slot) lives in `EditSession`, because every undo step restores it along with the layout (spec §5, PrototypeKit `EditorStore`).

## Consequences
- No mirrored state and no sync bugs between layers.
- The application layer depends on Observation and runs on the main actor; port calls are awaited off it.
- Use cases are testable without SwiftUI.
