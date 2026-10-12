# 39. The keyboard's layout is the flashed revision, never unflashed edits

Status: accepted, 2026-10-12. Builds on ADR 0019.

## Context
Most v1 features need to know which library layout the keyboard runs, and exactly which version of it: the menu bar extra, the overlay HUD, the layer shortcuts, the Heatmap, App Layers, and History's ON KEYBOARD badge and "On keyboard" comparison. Until now each window only asked whether the keyboard runs *its* layout (`FirmwareMatch`), and the sidebar only asked whether it runs *some* build of an entry (`LibraryEntry.isOnKeyboard`). Neither says which layer names, colors and keys are on the keyboard after the document has been edited since the flash.

## Decision
- **`OnKeyboard`** is an app-wide use case (`@MainActor @Observable`), built once in the composition root and passed in `SextantServices`. Its `running` value holds the library entry, the revision and that revision's layout, or nil.
- It works only from the serial `LiveSession` reports. Read-only USB enumeration supplies that serial, so it works with live access off.
- **An Oryx serial** (`layoutId/revisionId`) names the newest import revision whose layout carries that serial. Edited revisions keep their Oryx info, so only import revisions count.
- **A Sextant serial** (`sx-<id>-<fingerprint>`) names the working copy when it has the same fingerprint, which means the same content. Otherwise it names the newest flash revision with that fingerprint. The fingerprint depends on content alone, so no import baseline is needed.
- **Anything else is nil:** no keyboard, another layout, an Oryx revision never imported, or a build whose revision the library doesn't hold.
- The revision lookup is a helper beside the identity rule, `FirmwareIdentity.revision(runningSerial:of:revisions:library:)`, which History's badge can call for its own layout.
- It re-resolves when the serial changes, when the library refreshes, and when flash mode is released. A flash records its revision before releasing flash mode, so the release picks up a revision that wasn't there when the keyboard reconnected.

## Consequences
- Edits made since the flash never show as being on the keyboard, even in an open window whose document has moved on.
- When a flash's revision couldn't be recorded but the working copy still matches, `running` has the working copy's layout and no revision.
- The sidebar's "On keyboard" badge still uses `isOnKeyboard`, so it shows for any build of the entry, including an Oryx revision that was never imported.
- Resolving loads the matching revisions' JSON, newest first, and stops at the first match. This happens only when one of the three triggers fires, not on every edit.
- Two entries can claim one serial, for example the same Oryx layout imported twice. The most recently modified entry with a matching revision wins.
