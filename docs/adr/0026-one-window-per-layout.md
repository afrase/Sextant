# 26. One window per layout; quitting flushes open documents

Status: accepted, 2026-10-11

## Context
Spec §2.1 allows several layout windows, one layout per window. The integration review found that two windows could hold separate `EditSession`s for the same layout, so each autosave overwrote the other's edits on disk, and that quitting within a second of an edit lost it (autosave is debounced by 1 s).

## Decision
A layout is open in at most one window. `Library` keeps the registry of open sessions (`isOpen`, `close`); opening a layout that another window has brings that window forward instead of loading a second session, and `open` writes a lingering session's pending save before reading the file. An app delegate answers `applicationShouldTerminate` with `.terminateLater`, awaits `Library.flushOpenSessions()`, then lets the app quit.

## Consequences
- Edits can't be lost between windows or at quit.
- Showing the same layout side by side (for example two layers) would need a second view on one session, not a second session.
