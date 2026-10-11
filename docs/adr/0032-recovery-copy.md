# 32. A recovery copy of every change until its autosave lands

Status: accepted, 2026-10-11

## Context
The user asked that nobody ever lose work. Autosave is debounced by 1 s (spec §2.3) and quitting flushes it (ADR 0026), but two gaps remained: a crash or force quit inside that second, and a save that fails (disk full, the package moved or unwritable), after which the edits lived only in memory.

## Decision
`EditSession` writes the whole layout to a recovery copy on every change (edits, undo, redo, imports), at once and in order, skipping writes a newer change has superseded. When an autosave lands with no change since, the copy is discarded. `Library.open` asks the store for the copy: if it differs from the working copy, it becomes the document, is saved like any edit, and `EditSession.recoveredUnsavedChanges` tells the window. An identical copy is dropped.

`PackageLibrary` keeps the copies in `<library>/.recovery/<id>.json`: the same volume, so writes stay atomic, and not `$TMPDIR`, which macOS empties on restart, exactly when a recovery copy matters. A copy that isn't newer than `layout.json` is stale (a save landed and only the discard was lost) and is deleted. An unreadable copy is logged and kept, because it may be the only record of those edits. Trashing a layout drops its copy.

## Consequences
- A crash loses nothing that was on screen; a failing save keeps retrying while every change is still on disk.
- One extra small atomic write per change, off the main actor.
- The copy shares the library's disk: it doesn't help if the whole volume is full or gone.
- A layout whose `layout.json` can't be read doesn't open, so its recovery copy isn't offered (shortcut: restore it by hand from `.recovery/`; add a recovery path if it ever happens).
