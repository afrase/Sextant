# 24. Importing over an existing layout: checkpoint first, keep the user's title

Status: accepted, 2026-10-11

## Context
Spec §8.1 offers "Add as Revision of ‘My MacOS Layout’" when the library already has the Oryx layout. The local working copy may hold edits no revision records.

## Decision
- Before applying the import, if the working copy differs from its last revision, save it as a `.save` revision "Before importing from Oryx". The import is then an `.import` revision and an undoable edit of the open document (or of a temporary session when no window has it open). A failed working-copy write aborts with the error.
- The library layout keeps its own title.
- Oryx's firmware is optional: a download or checksum failure is a preview note, not an import failure (spec §8.1). A verified image is stored per revision for "Flash Oryx's build".
- `LayoutLibrary.save` keeps an Oryx origin in step with `layout.oryx.revisionId` when the layout ids match.

## Consequences
- No local edit is ever lost to an import; the cost is an occasional extra checkpoint.
