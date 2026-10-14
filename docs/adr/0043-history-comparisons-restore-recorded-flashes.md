# 43. History: comparisons, restore and recorded flashes

Status: accepted, 2026-10-12. v1 plan slice 1.3. Builds on ADRs 0024 (import as a revision), 0037 (pages and the cap decoration hook) and 0039 (the keyboard's layout is the flashed revision).

## Context
Storage has kept revisions since the MVP: an import, every flash, and ⌘S (whose menu item was disabled). Nothing showed them. Spec §8.7 asks for a History page with a timeline, a Changes board that compares a revision with its parent, Current, On keyboard or another revision, Restore, and Save Revision with a suggested message.

Four things weren't settled:
- `LayoutDiff` covered only keys and layers, so a revision that changed only settings read as "no changes". Combos have no stable ids, because Oryx numbers them by position.
- `BuildFlashSession.record()` appended a flash of an older build straight to the library (a `shortcut:`), so the open window's `revisions` missed it until the layout was reopened.
- Once the comparison can be later than the revision (Current), the board's badges need a direction.
- A revision can have other layers, another layer order or another Navigator side than the document.

## Decision
- **`LayoutChanges`** (domain, `KeyboardLayout.changes(from:)`, in `LayoutDiff+Summary.swift`) is the key and layer diff plus:
  - the ids of changed settings, Navigator options included;
  - combos added and removed, compared by content with the id ignored;
  - a Navigator flag for its kind, side or automouse layer;
  - a flag for the layout's title (Rename Layout) and one for the order of the layers both sides have (Move Layer).

  Each own key on a layer the old layout lacks counts as added, so a new layer shows on the board. `count` totals every kind of change, so every edit Sextant makes counts and ⌘S never opens on a blank suggestion. Oryx's swatches and revision info aren't counted: only an import changes them. `LayoutDiff` and `diff(from:)` are unchanged.
- **Badges always describe the board's keys, the selected revision's, against the comparison** (old = comparison, new = revision).
  - Against the parent, this reads forward in time.
  - Against Current or a later revision, it reads backward. "Added" marks a key the comparison lacks, which Restore would bring back; "removed" marks one Restore would take away.
  - The rule is the same for every comparison. The header names the comparison, and the lane capsule counts each badge.
- **Comparisons:**
  - Previous revision is the default. The first revision has no parent, so its caps are plain.
  - Current is the working copy, unsaved edits included.
  - On keyboard is `OnKeyboard.running` when it names this layout's entry. Its revision is compared by id, and its layout is the flashed one, never later edits.
  - Another Revision is a submenu, in place of the spec's "Choose…" dialog. Choosing the revision being compared with falls back to Previous revision, since a revision compared with itself shows nothing.
- **The Changes board keeps the document's geometry.**
  - BoardView reads a `BoardDisplay` (a layout and a layer) from the environment. With one, it is read-only: no painting, swapping, ⌫, edit actions or issue rings.
  - The Navigator disc stays where the document has it, so no key moves even when the revision's Navigator sat elsewhere.
  - The revision's layer is the document's selected layer, matched by id. A layer only the revision has (deleted since) can be chosen from the strip or the header's layer menu, and stays until another layer is chosen or the page closes.
  - The footer's kind key lists the kinds on the layer the board shows.
- **The board's marks use the ADR 0037 hook.** `capDecoration(layer:index:)` gains a `.history` case, and `HistoryModel` builds the marks:
  - changed is an orange `circle.fill`, added a green `plus.circle.fill`, removed a red `minus.circle.fill`, each with a 2 pt ring in its color;
  - unchanged keys are at 40%.

  The board asks once per cap, so the diff is worked out once per input: the revision, the comparison, the loaded count, the edit count (for Current) and the keyboard's revision.
- **Restore** (`EditSession.restoreRevision`, in `EditSession+History.swift`):
  - It loads the revision and checkpoints unsaved edits with the helper taken out of `applyImport`.
  - It appends a `.save` revision, "Restored revision N", before it touches the document. So a failure (a load, the checkpoint, the append) leaves the document as it was.
  - It then makes the revision the document as one undo step ("Restore Revision"), keeping the title. Undo leaves the appended revisions, as after an import.
  - It does nothing when the document already equals the revision, bar the title. The button is off then, and while a restore runs, so a double click can't append its revisions twice. Refusing it while a flash writes is slice 2.5's.
  - It reuses `.save` rather than adding a `RevisionSource` case that older builds couldn't decode.
- **`recordRevision`** appends a revision of any layout and makes it the "Edited" baseline, as the library compares the working copy with the newest revision. So undoing back to a flashed build clears "Edited" in the window as on reopening. `BuildFlashSession.record()` always records the build through it, which closes the shortcut: the revision holds exactly what was flashed, even when an edit lands while it is recorded (`saveRevision` would record the document after its flush).
- **`HistoryModel`** is made per open layout by the window (`LayoutWindowModel.history`). It caches revision layouts by id (revisions never change) and the timeline's counts. It loads them when the page shows and whenever a revision is added. `OnKeyboard` reaches the window from `SextantServices`, through `LayoutWindowModel(onKeyboard:)`.
- **Save Revision (⌘S)** is on when the document differs from its last revision, and is a palette command too. The suggested message puts keys first: "Edited 5 keys on Brd+Sys", or "Edited 12 keys on 3 layers". Otherwise it names the first other kind of change: "Edited layers" (layer order included), "Changed 2 settings", "Edited combos", "Changed the Navigator", "Renamed the layout". It reads only the last revision. A blank message stores none.
- **The palette's Documents group** lists revisions ("Revision 3", with the message). Choosing one opens History on it.
- **Not in this slice:** the author (not modeled), the firmware size delta, Flash This Revision… and Export Source Zip…. Slice 2.5 adds the last three.

## Consequences
- A revision that changed only settings counts them in the timeline ("1 change") and in the lane capsule ("1 other change").
- A page visit reads each revision's JSON once per window. That is quick for tens of revisions. Hundreds take longer, and the board shows the document until they load (the strip says so, or that the revision couldn't be read). ⌘S reads one revision, however long History is.
- Past four revisions the timeline scrolls on its own and keeps the selected one in view, so its details and Restore stay on screen.
- Layers match by id, so a layer that was deleted and added again reads as removed plus added.
- The sidebar gains a History row with the revision count, so every window snapshot changes in that row.
- On History, the window subtitle reads "History", or "History · Edited".

## Amendment: Flash This Revision, Export Source Zip and the size delta (v1 plan slice 2.5, 2026-10-14)

The decision above left three History actions for slice 2.5. They extend it rather than change it, so they are recorded here.

- **Flash This Revision…** goes through the window's own Build & Flash, never a second path to the flasher.
  - `BuildFlashSession.buildAndFlash(connectedKeyboard:revision:)` takes a `RevisionLayout` (a revision with the layout it recorded). The run builds that layout instead of the working copy; the issue gate, the replace confirmation, setup, Try Again and every flasher guard are unchanged, and Replace, setup and Try Again go on with the same revision. ⌘B and ⌘R start from the working copy again. `LayoutWindowModel.build(_:revision:)` is the one entry point.
  - The revision is built exactly as recorded, title included, under the identity rule's serial for that layout (an unchanged latest import still builds as Oryx's). `record()` already recorded what was flashed rather than the document, so the flash becomes a new `.flash` revision, "Flashed revision 2", and the working copy stays as it is (and "Edited" against it).
  - The sheet names it: "My MacOS Layout, revision 2 → ZSA Voyager", until Stop, Cancel or Done ends the run (`stop()` forgets the revision, so the idle sheet's Build & Flash is the working copy's again). A revision's build errors point at no key: compile errors aren't mapped through the source map, and a generator error drops its key, since the board, Show Key and the capsule's "key N" are the working copy's, whose keys may differ.
  - Blocking issues in a revision get their own words: "Revision 2 has 1 issue", rows with no Show Key, and [Restore This Revision] beside Close (when the revision isn't already the layout), because a recorded revision can't be fixed where it is.
- **Export Source Zip…** is File ▸ Export's QMK Source for the revision's layout: `ExportKind.revisionSource(RevisionLayout)` takes the same path as `.qmkSource` through `export(_:)`, with `BuildFlashSession.source(of:)` and the identity the build would flash, named "<title> Revision 2 QMK Source" (ADR 0044).
- **Size delta.** Every flash now keeps its image: after `record()` appends the revision it calls `storeFirmware` under that revision's id, with the md5 taken at build time. Failing to keep it is logged and changes nothing else. `firmwareSize(of:)` reads the revision's image and the newest earlier revision that has one, skipping saves (never built) and imports (Oryx's image sits under Oryx's revision id and is a different build, so it never counts). The inspector shows "Firmware 66 kB · +292 B since revision 4", the size alone when no earlier image exists, and nothing when the revision has none. VoiceOver reads the change in words. Sizes are the payload, without the 16-byte DFU suffix, read again when a flash finishes (its image lands after its revision).
- **Refused while a flash writes.** Restore and Flash This Revision are off, and refused if called, while this window's flash can't be stopped (validating through verifying) or another window's is writing (`LiveSession.isWritingFirmware`).
- **Menus and palette.** Spec §11 wants every action in a menu, and wave 1 left Restore and Compare in the inspector. On the History page: File ▸ Restore This Revision, File ▸ Export ▸ This Revision’s QMK Source (.zip)…, View ▸ Compare Revision With ▸ (the header's comparisons), and Keyboard ▸ Flash This Revision…; the palette gets Restore This Revision, Flash This Revision…, Export Source Zip… and "Compare with: …". They act on the revision History shows, so they are off on every other page.

Consequences: each flash adds its image (tens of kilobytes) to the package. Packages flashed before this change have no images, so their flash revisions show no size until they are flashed again.
