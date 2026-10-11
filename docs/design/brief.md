# Sextant UI design brief

## Product

Sextant is a native macOS app for configuring a ZSA Voyager split keyboard. It replaces both of ZSA's tools:
- Oryx, the web editor plus cloud compiler;
- Keymapp, the desktop app for flashing and the live layer view.

The user wants a **modern, slick, native macOS app**.

Decided: local-first hybrid architecture, minimum **macOS 26** (Liquid Glass), and every surface designed now even though they ship in phases. See `../decisions.md` and `../research/00-overview.md`.

## The hardware

- 52 keys. Each half is a 4×6 column-staggered block plus 2 rotated thumb keys (±30°).
- Per-key RGB and 4 status LEDs.
- The user's board has a **Navigator trackpad** on the right half.
- The keyboard identifies its layout over USB.
- Live data over raw HID: active layer, physical key down/up, RGB takeover, status LEDs. The keymap itself can't be changed live; that needs a rebuild and reflash.

## The user's real layout (design with it, not lorem ipsum)

- File: `../research/oryx-examples/my-layout-KlgM7-40xJ7M.json`.
- Name: "My MacOS Layout". Layers: **Main**, **Sym+Num** (cyan `#00F0FF`), **Brd+Sys** (green `#42FF00`).
- Main is QWERTY with:
  - dual-function keys (`=`/Esc, Z/⌥, `/`/⌥, `'`/⇧);
  - hold-only modifiers (⇧, ⌃, ⌘);
  - layer keys on the thumbs: hold for Sym+Num / Brd+Sys.
- Brd+Sys has:
  - RGB controls and media keys;
  - arrows and Home/End/PgUp/PgDn;
  - custom-labelled shortcuts ("Back", "Prev Tab", "Next Tab", "Forward");
  - colour keys and `QK_BOOT` ("Reset").
- Geometry: `../research/data/voyager-geometry.json`.
- Matrix and LED map: `../research/data/voyager-matrix-led-map.json`.
- Settings catalog (100 settings, 14 sections): `../research/data/oryx-config-settings.json` and `../research/data/04-oryx-settings-catalog.json`.

## Principles

1. **Native first.** Use SwiftUI on macOS 26: Liquid Glass (`glassEffect`, `GlassEffectContainer`, glass button styles), SF Symbols, system materials, semantic colours, standard controls, `NavigationSplitView` and `.inspector` where they fit. Respect light and dark mode, the accent colour, Reduce Transparency and Reduce Motion. It should feel like Apple made it, not like a web page in a window.
2. **The keyboard is the hero.** A precise, beautiful board render using the real stagger and thumb angles, readable legends with Mac glyphs (⌘ ⌥ ⌃ ⇧ ⇪ ⌫ ⏎ ⇥ ⎋), and clear secondary legends for hold and other functions.
3. **Meaning at a glance.** Distinguish key kinds: regular, modifier, multi-function (tap+hold), tap dance, LED/RGB control, macro, custom label, layer key, transparent (inherits from below; render dimmed with the inherited legend), none/disabled. Re-express these natively, not with Oryx's palette. Each layer has a colour; keys on non-base layers carry it.
4. **Keyboard-first and undoable.** Arrow keys move selection across the board, Return edits, ⌘Z/⇧⌘Z everywhere, a ⌘K command palette, and "Record key" as an explicit mode (Oryx's implicit capture is a trap). Oryx has no undo and is mouse-only.
5. **Stable layout.** Panels must not reflow or shrink the board unexpectedly (Oryx's slide-in panels shrink it). Use inspectors, popovers and sheets with intent.
6. **Live.** When the keyboard is connected, show it: the active layer follows the physical board and pressed keys light up. The app should feel connected to the hardware.
7. **Safe flashing.** Build and flash is a clear, calm, guided flow: build progress, size meter, "press the reset pinhole" guidance, progress, verification, success. Errors are mapped back to keys.
8. **No ZSA trade dress.** Don't use ZSA logos, the Voyager wordmark/art, Oryx's icon font or their exact colours. Refer to "ZSA Voyager" in text only.

## Surfaces (design all; MVP builds the first group)

**Core (MVP)**
1. Main window: layout document, layers, board canvas, key inspector, toolbar (layer switch, build/flash, device status, undo/redo, search/palette).
2. Key editor: tap / hold / double-tap / tap-then-hold slots; modifiers per slot; custom label; per-key colour; layer actions (MO/TG/TO/TT/OSL); transparent/none.
3. Keycode picker: search, categories (letters, digits, modifiers, punctuation, navigation, media, mouse, RGB, layers, function keys, system, firmware, international, numpad, Navigator), recents, Record key.
4. Layers: add, rename, reorder, delete, colour; switching; inherited (transparent) keys shown dimmed.
5. LED/colour painting: per-key colours and layer colour, swatches.
6. Build & flash flow: build, size meter, bootloader guidance, flash, verify, done; failure states.
7. Import from Oryx: paste a URL, or detect the connected board's layout from its USB serial.
8. Device / live panel: connection, firmware and layout identity, live active layer, pressed keys.

**v1 (design now, build later)**
9. Menu bar extra: current layer, quick layer switch, connection, flash.
10. Floating overlay HUD: click-through, shows the active layer's map while a layer is held, like Keymapp's overlay.
11. Heatmap: key-usage frequency on the board, time range, export.
12. App-aware layers: rules mapping frontmost app to layer.
13. History and diff: revision timeline with a visual per-key diff.
14. Macro editor (24 steps, delays, modifiers) and combo editor (pick 2-6 keys on the board, choose an output).
15. Layout settings: 100 firmware settings in 14 sections, searchable, showing defaults and modified state. App preferences go in the standard Settings window.

**Future (after v1; leave room in the design, don't build yet)**
16. Sync and backup server. An optional, self-hosted server that the app syncs with to back up layouts and keep several Macs in step.
    - **Server:** Go, one static binary with SQLite, runnable on a home server or Raspberry Pi.
    - **Local first stays:** the app works fully offline, and sync is opt-in.
    - **What syncs:**
      - layout documents with their full revision history;
      - the firmware `.bin` built for each revision, with its md5;
      - app-aware layer rules.

      Heatmap data syncs only if the user opts in, because it is keystroke data.
    - **Backups:** each flash records a snapshot. Any revision can be restored on any Mac.
    - **Conflicts:** history is append-only. Concurrent edits become two revisions, which the History and diff view (13) lets you compare and merge per key.
    - **Security:** pair devices with a token and use TLS. Offer end-to-end encryption, because macros can contain typed text.
    - **UI to leave room for:**
      - a sync status indicator in the window chrome and the menu bar extra;
      - a Sync pane in Settings for the server URL and device pairing;
      - the source device on each revision in History;
      - "Restore from backup" alongside Import.
    - **Possible extra:** the same server could build firmware with the QMK toolchain, which would keep that toolchain (about 1 GB) off the Mac.
    - **MVP implication:** documents and revisions get stable UUIDs, content hashes and append-only history from day one, so adding sync later needs no migration.
    - **Open:** a self-hosted server versus iCloud, which needs no server but only works between Apple devices.

## Oryx lessons (from `../oryx-ui/README.md`)

**Keep:**
- colour-coded key kinds;
- per-layer glow;
- dimmed inherited legends;
- simple vs advanced legend detail;
- the plain-English setting descriptions with defaults.

**Beat:**
- popover-plus-panel cramming;
- a board that shrinks when panels open;
- no undo;
- mouse-only editing;
- opaque compile errors;
- no diff or history view;
- the implicit key-capture trap.
