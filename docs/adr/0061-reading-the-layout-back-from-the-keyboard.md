# 61. Reading the layout back from the keyboard, so two Macs know what it runs

Status: accepted, 2026-10-16; revised 2026-10-17 after review (storing off by default, links in their own file, fixes
listed at the end). Amends ADRs 0019 (firmware identity), 0038 (live commands), 0039 (OnKeyboard) and 0045 (the raw-HID
log).

## Context
The user plugs one Voyager into a work laptop and a home laptop, and each day the other laptop "doesn't have the firmware".
A Sextant build's serial is `sx-<first 8 hex of the library entry id>-<fingerprint>` (ADR 0019). Each Mac imported the
layout on its own, so the entry ids differ, and the libraries aren't synced, so their content differs too. On the other Mac
`OnKeyboard.running` is nil: the device card says "not in your library", the menu bar can't name the layers, the overlay
never shows, the Heatmap pauses, and Build & Flash asks to replace the layout. The user asked whether Sextant could pull the
layout off the keyboard instead.

Stock firmware can't: ZSA's live protocol has no way to read the keymap (research 03 §0), and reading the image back over
DFU needs flash mode and gives a lossy keymap (progress.md, 2026-10-15). But Sextant generates the firmware, so it can store
the layout in it and answer a request for it.

## Decision
- **The layout record.** With the setting on (below), a Sextant build stores a `LayoutRecord` (domain): `SXL`, a version, the layout's library ids
  (the building Mac's entry id first, then the ids it is linked to on other Macs, at most 16), the JSON's length, then the
  layout's firmware JSON (sorted keys, no macro drafts: the same bytes the fingerprint is the CRC of) compressed with raw
  DEFLATE. For the user's layout the JSON is 5,526 bytes and the record 1,151; the image grows by 1,336 bytes with the
  handler, from 62,392 to 63,728 of the 122,880 the application window holds. It takes no RAM beyond a 32-byte reply on the
  stack. Over 32 KiB, the build stores none and says so in its log; a firmware too large with the record builds again
  without it, and the log says so too.
- **The read command.** The generator adds `sextant_layout.c` and, in `rules.mk`, `SRC += sextant_layout.c` and
  `override EXTRALDFLAGS += -Wl,--wrap=raw_hid_receive` (`override`, because `QMKBuild` already sets `EXTRALDFLAGS` on make's command line through `qmk compile -e`, and make ignores a plain `+=` to such a variable; reproduced with make 4.3). GNU ld then sends QMK's one call of `raw_hid_receive` (`usb_main.c`) to
  `__wrap_raw_hid_receive`, which answers reports starting `53` and hands every other report to zsa/oryx unchanged
  (`__real_raw_hid_receive`). ZSA's sources aren't patched or copied. Oryx's builds don't use LTO, which `--wrap` doesn't
  survive in every toolchain.
  - Request `53 01 <offset hi> <offset lo>`; reply `53 01 <status> <size hi> <size lo> <offset hi> <offset lo> <count>`
    and up to 24 bytes. Status 0 is data, 1 an offset at or past the end, 2 an unknown request.
  - `0x53` is outside every Oryx command and event id. On firmware without the record, zsa/oryx answers `FF FF` (unknown
    command) and does nothing else (`oryx.c`'s `default:`), so asking is harmless anywhere.
  - Without a record (Settings › Build › Store the layout in the firmware off, or too large) the generated source is
    byte-identical to before, so the golden tests hold. Export Source Zip stays without it.
- **The link.** `KeyboardCommand.readLayoutRecord(offset:)` is the one command added to ADR 0038's list; it changes nothing
  on the keyboard. `LiveSession.readLayoutRecord(progress:)` asks for each part in turn over a paired Live View session,
  matches replies by offset, asks again once after 500 ms, and fails as `noRecord` on `FF FF`. A size over 32 KiB is refused at
  the first part. The Developer raw-HID log keeps
  only the 8-byte header of a reply (amends ADR 0045): the record holds macro text, which is never logged (ADR 0042).
- **Linked layouts.** A library entry keeps `aliases`, its ids on other Macs, in its package's `links.json` (written only
  when there are some). Not a key in `meta.json`: an older Sextant rewrites that from the keys it knows, which would drop
  the links at its next save, but never opens `links.json`. A serial or a record naming an alias is that layout. Matching a Sextant serial
  compares its fingerprint, the content, so the same layout flashed from another Mac reads as `current` (amends ADR 0019) and
  `OnKeyboard` finds a revision by fingerprint whichever Mac's id the serial carries (amends ADR 0039).
- **`KeyboardLayoutPull`** (application, app-wide) reads by itself once per serial per connection when Live View is paired
  and `OnKeyboard` has no layout for the serial, never while flashing. It checks the record against the serial: the CRC of
  its JSON must be a Sextant serial's fingerprint, or the layout's Oryx serial must be the Oryx serial. Then:
  - **Linked** (an entry's id or aliases meet the record's ids, or an Oryx serial and an entry from that Oryx layout): it
    links the record's ids and adds the keyboard's layout as a revision ("From the keyboard"; `.flash`, or `.import` for an
    Oryx serial), through the open document when there is one. It also becomes the working copy when the working copy
    equals its latest flash or import, that is when nothing newer than what was last put on a keyboard would be replaced;
    otherwise the layout window offers "Keyboard runs revision N · Use It". Use It makes the working copy exactly that revision, the keyboard's title included (the title is part of the fingerprint), keeping only the local macro drafts, as one undo step after a checkpoint; the offer then ends.
  - For an Oryx serial, only a layout from that Oryx layout counts as linked or is offered, since OnKeyboard finds an Oryx serial's import revision by the layout's origin; otherwise the choice is a new layout, from that Oryx layout.
  - A Sextant serial's record must also decode to a layout that re-encodes to the serial's fingerprint (a newer Sextant's field this one drops would otherwise be added again at every connect); else it fails as unreadable.
  - **Not linked:** the device card, the Device popover and the menu bar offer Add to Library…, which opens the Layout on
    the Keyboard window: a new layout, or a revision of the layout the user picks (the same Oryx layout or name is
    suggested), which becomes its working copy after a checkpoint (ADR 0024's rule). That links the two from then on.
  - The keyboard's layout is kept exactly, title included, since changing it would change its fingerprint.
- Nothing is offered until `OnKeyboard` has looked the serial up for the current library and flash state (`resolvedSerial`), so a known layout never flashes "not in your library" on connect.
- **Consent.** The read goes only over a Live View session the user started (ADR 0057). Get Layout on the device card turns
  Live View on and reads; the click is the consent. Agents never send it; the user tries it on the keyboard.
- **Settings › Build › Store the layout in the firmware**, off by default (the user's call): any app on a Mac the keyboard is
  plugged into can read the record, macros included, with no prompt. Reading the image needed flash mode before.

## Consequences
- The keyboard has to be flashed once from Sextant with the setting on before another Mac can read it; the first read links the
  two layouts, and after that each Mac picks up the other's flashes by itself whenever Live View is on.
- The firmware grows by the record (about 2 KB here; at most 32 KiB, inside the 120 KiB window).
- Unverified on hardware until the user tries it: the wrapped receive on the Voyager, and Keymapp and Oryx ignoring `53`
  replies they see (they get every input report).
- The pulled revision has no firmware image, so Flash This Revision rebuilds it.
- Layouts made before this release on two Macs stay unlinked until the first read; linking needs no sync service.

## Revision after review (2026-10-17)
An adversarial review of the first version found these, all fixed:
- **Linking only takes other Macs' ids.** A record names every id the building Mac's layout is linked to, which can include
  this Mac's other layouts (the other Mac had linked two of them to one of its own). Linking now leaves out the ids of this
  Mac's layouts and their aliases; before, a build of one layout could read as another, with no replace confirmation.
- **Several matches are offered, not picked.** When the record names more than one library layout, or an Oryx serial has
  more than one layout from that Oryx layout, the pull offers Add to Library… instead of taking the first.
- **Edits typed during a read stay.** Adopting re-checks the working copy after its waits, with nothing awaited before
  the edit; if it moved, the keyboard's layout is only recorded and "Keyboard runs revision N" is offered.
- **Unplugged mid-read.** The automatic read runs apart from the loop that follows the keyboard, so an unplug during a read
  still counts as a new connection.
- **The Dock.** Only titled, non-panel windows closing can leave the Dock (ADR 0049), so the menu bar panel's close while
  Open Sextant or Settings… opens a window doesn't.
- **Smaller:** a live read refuses a size over 32 KiB at the first part; adding to a layout links before it replaces the
  working copy, so a failed link leaves it as it was; a damaged `links.json` is replaced at the next link; a rebuild without
  the record doesn't start after Stop; when several layouts are named, one of them is the suggestion.

