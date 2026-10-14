# Sextant UI specification

Version 1.0 · 2026-10-11 · Status: the chosen direction for MVP and v1. The user decided all nine taste calls on 2026-10-11 (§14).

**Inputs**
- `docs/design/brief.md`
- the Oryx screenshot tour (kept in the reference folder)
- `docs/research/00-overview.md`, sections 2, 3, 5 and 6
- the three design explorations under `design/explorations/` (a-instrument, b-chart-table, c-console) and their snapshots, kept in the reference folder
- the three judge reports: Mac-native craft, task flow, and visual delight

**Conventions**
- **Phase tags.** **MVP**, **v1** and **Future** mark the build phase. They follow the brief and research §3.
- **Units.** Sizes are in points. `u` means the side of one rendered 1u keycap: the cap itself, not the pitch.
- **Colours.** Values are written *light / dark*.
- **Snapshot references.** `A-nn` refers to `design/explorations/a-instrument/snapshots/nn-*.png` in the reference folder. `B-nn` is the same for b-chart-table and `C-nn` for c-console.
- **Real data.** Examples use the user's real layout, "My MacOS Layout" (`KlgM7/40xJ7M`). It has three layers: Main (no colour), Sym+Num (`#00F0FF`) and Brd+Sys (`#42FF00`). Keys are named by Oryx index; for example, key 24 is `LT(1, KC_ENTER)`.
- **Layer numbering.** Layers are numbered from 0 everywhere ("Layer 1 · Sym+Num"), to match QMK.

---

## 1. Direction and rationale

### 1.1 Decision

Sextant is built on **Instrument** (a-instrument) as its structural base, with targeted grafts from **Chart Table** (b-chart-table) and **Console** (c-console).

The identity in one line: *a precision instrument for your keyboard*. It is a calm, native macOS document window, with the board as the lit object at its centre.

### 1.2 Judge results

| Judge lens | Instrument | Chart Table | Console | Lens winner |
|---|---|---|---|---|
| Mac-native craft | **8.0** | 5.5 | 6.5 | Instrument |
| Task flow and usability | 7.4 | 6.4 | **8.2** | Console |
| Visual delight and identity | 7.6 | **8.6** | 7.1 | Chart Table |
| Mean | **7.67** | 6.83 | 7.27 | |

Each judge picked a different winner. Instrument is first on craft and second on both other lenses, which makes it the most robust base.

The main complaints about Instrument can all be fixed without changing its structure: a board that moves and is small, a cramped picker, a weak identity, and missing accessibility. The weaknesses of the other two are structural:
- **Chart Table:** hidden title bar and custom chrome, glass on content panels, nautical theming, the system accent ignored.
- **Console:** custom title-bar tabs, a 10-tab drawer standing in for a sidebar and inspector, a permanent live strip, a window-wide key monitor with bare-letter shortcuts, and a mono, uppercase web-tool voice.

### 1.3 Why Instrument is the base (evidence)

- **It is built from the system frame.** It uses `NavigationSplitView` with a native sidebar `List`, an `.inspector`, and a native `.toolbar` with title and subtitle (A-01, A-02). Build & Flash and Import are real `.sheet`s (A-07, A-08, A-09). Firmware Settings is a grouped `Form` (A-18). It has a Settings scene, full menu commands, and named undo that goes to text fields first.
- **Its glass is HIG-correct.** The system draws the toolbar glass. App glass is limited to small floating capsules and the palette (A-06, A-10, A-13, A-20). Documents and inspectors stay flat.
- **Its two-channel key encoding keeps kind and layer apart.** Kind is a bottom signal bar and layer is an outer ring, so they never compete for the same pixels. The visual judge named this as the fix for Chart Table's muddy Brd+Sys caps (A-10 versus B-10).
- **Its explanation layer is the best of the three.** It shows "Transparent. Acts as Z from Main · Override on Sym+Num" (A-05), the Changed (9) list with struck-through defaults (A-18), and errors mapped to the key in four places (A-19).

### 1.4 Debts fixed in Instrument

| Problem in the prototype | Fix in this spec | Ref |
|---|---|---|
| The board moved about 29 pt when a key was selected or deselected, or the lens changed, because the strip was conditional | The canvas uses fixed bands, and the context strip is always reserved (§3.3) | A-01 vs A-06, A-10, A-13 |
| Small board: about 49 pt caps and large dead space | Half gap 3.0u, no status bar, layer strip removed. About 52 pt caps at 1440 pt with both columns, about 66 pt with the sidebar hidden (§4.1) | A-05, A-17 |
| Three layer switchers | The sidebar is the navigator. The canvas header has one jump menu. The toolbar layer menu is removed | A-01 |
| Inline picker: 5 results, icon-only categories, pushes fields off-screen | A floating picker over the opposite half of the board, with live preview and ⌘⏎ (§5.6) | A-04, minsize render |
| Layer actions set with two pop-up menus | A segmented action control plus layer chips (§5.3) | A-01 |
| Cancel enabled while writing; "Flash Now" button | Cancel is disabled during erase, write and verify. Flashing auto-advances when the bootloader appears (§7) | A-07, A-08 |
| A green check next to "Not yet on keyboard" | An amber arrow-up icon with "Not on keyboard · 5 edits" | A-06 |
| Live was a lens that replaced the key inspector | Live is a mode over any lens, plus a Device popover (§8.2) | A-10 |
| No VoiceOver, Reduce Motion or Reduce Transparency; greys below 4.5:1 | §11 | judge |
| A custom bezel button style and a hand-drawn Build button in the live app | Stock controls, and `.glassProminent` for Build & Flash | judge |
| A minimum width of 1180 pt that the column minimums made unreachable (it rendered at 1367 pt) | Honest column minimums (§3.2) | minsize/out-a |
| Sidebar and inspector toggles bound to ⌘0 and ⌥⌘0 | `SidebarCommands` (⌃⌘S) and `InspectorCommands` | judge |
| Key numbers on every cap by default | Off by default. Shown in # legend mode | A-01 |
| Magma heatmap | Single-hue ramp (§8.5) | A-13 vs B-13 |
| Weak identity | The sextant mark, a bench grid, layer atmosphere and a graduated flash ring (§10.7) | judge |
| Combos and History replaced the board | Both become board lenses (§2.2) | A-15, A-17 |
| A kind channel too quiet to read at a glance | Hold bands on dual-function keys, plus the signal bar (§4.4) | A-01 vs C-01 |
| A static menu bar icon | The sextant glyph plus the active layer number (§8.3) | A-11 |
| The event log showed typed letters | Positions only, paused during Secure Event Input (§8.2) | A-10 |

### 1.5 Grafts

| From | What | Where it lands | Ref |
|---|---|---|---|
| Console | Hold band naming the hold action (glyph, L/R, or the target layer's colour and name) | Cap anatomy, §4.2 | C-01, C-02 |
| Console | FloatingSurface: real glass, opaque under Reduce Transparency | `SurfaceStyle`, §10.4 | code |
| Console | `.glassProminent` Build & Flash | Toolbar, §3.4 | code |
| Console | Numbered callouts on the real Space and Reset keys | Flash mode step, §7.3 | C-07 |
| Console | Log lines link to the key | Build log and issue callout, §7.5 | C-19 |
| Console | Record-arm styling: red ring and REC badge | Record Key, §5.8 | C-21 |
| Console | Aa / KC / # legend switch | Board footer, §3.7 | C-01 |
| Console | Through layers, with fall-through arrows | Context strip, §3.7 | C-03 |
| Console | Teaching empty-slot copy | Slot editors, §5.2 | C-01 |
| Console | Menu bar layer tiles, rows with key equivalents, Quit | Menu bar extra, §8.3 | C-11 |
| Console | Macro time ruler with proportional delays | Macros page, §6.3 | C-16 |
| Console | Painted keys grouped by colour; B/E/I/G tools | Lighting, §6.2 | C-06 |
| Console | "Board runs revision X / N edits behind" | Activity capsule, §3.5 | C-01, C-06 |
| Console | Rolling-neighbour combo warning | Combos, §6.4 | C-17 |
| Chart Table | Floating picker over the opposite half, live preview, ⌘⏎, ⇥, labelled rail | §5.6 | B-04, B-21 |
| Chart Table | Hold segmented control "Modifier · Layer · Key · Nothing", plus a summary sentence | §5.2 | B-03 |
| Chart Table | Motion helper with Reduce Motion fades | `SextantMotion`, §10.6 | code |
| Chart Table | GlassEffectContainer with interactive glass | Lens lane, §10.4 | code |
| Chart Table | Hide keeps flashing; Cancel disabled while writing | §7.6 | B-07, B-08 |
| Chart Table | Graduated sextant ring; sextant mark | §7.3, §10.7 | B-08, B-11 |
| Chart Table | Convex cap craft; captions under symbols | §4.2, §4.3 | B-01, B-06 |
| Chart Table | Error card with code excerpt and caret | Issue callout, §7.5 | B-19 |
| Chart Table | Esc ladder; drag to swap | §9.3, §5.9 | — |
| Chart Table | Layer atmosphere on the bench, toned down | §4.10 | B-05 |
| Chart Table | Single-hue heatmap | §8.5 | B-13 |
| Chart Table | Board frame computed only from the canvas area | §3.3 | code |
| Chart Table | Combo rings, traces and output pills | §6.4 | B-17 |

### 1.6 Rejected, and why

| Rejected | From | Why |
|---|---|---|
| Nautical canvas: isobaths, compass rose, graduated margins, nautical names (Soundings, Logbook, Route, Wake), New York serif in the chrome and on caps | Chart Table | Themed rather than "modern slick". It hurts legibility under glass. Plain names are clearer. The judges asked for the theme to be turned down by about 40%; this spec keeps only the precision cues (§4.10) |
| Hidden title bar, custom chrome, no NSToolbar, a custom accent colour | Chart Table | Loses native toolbar glass, customisation, title, sidebar and inspector commands, and the user's accent |
| Glass on content panels (editor card, shelves, settings, flash HUD) | Chart Table | The HIG puts glass on controls and navigation, not content |
| Editor card docked in the gap between the halves | Chart Table | Falls back to covering keys at narrow widths (minsize/out-b). The inspector is stable and dense |
| "safari" menu bar symbol; layers numbered from 1 | Chart Table | A restricted Apple product symbol, and numbering that contradicts `LT(1, …)` |
| A typed-text "Wake" trail | Chart Table | Shows keystrokes from any app |
| Safari- or Arc-style layer tabs in the title bar; ⌘T for New Layer | Console | Not native tabs, and it collides with the tab convention |
| A permanent live strip with an LCD layer track | Console | Costs 52 pt of height. It looks like a control but is read-only, and it gives a second layer concept (C-15) |
| A 10-tab drawer standing in for the sidebar and inspector; Flash as a drawer tab | Console | Non-standard. Long documents get cramped (C-18). Flashing needs modal semantics |
| A window-wide NSEvent monitor and bare-letter global shortcuts | Console | Bypasses the responder chain, Full Keyboard Access and VoiceOver |
| Tracked mono uppercase section labels; WPM sparkline chrome; hex text on caps; "lamp" lines; a circular-arrow Esc glyph | Console | Web-tool voice and visual noise. The Esc glyph reads as Undo |
| Multi-hue size meter; magma heatmaps | Console, Instrument | Inconsistent with the calm palette; garish |
| Toolbar layer menu; layer strip; Live lens; status bar; per-cap indices on by default | Instrument | Redundant chrome, a moving board, and noise |

---

## 2. Information architecture

### 2.1 Scenes and windows

| Scene | Type | Contents | Phase |
|---|---|---|---|
| Layout window | `WindowGroup(id: "layout", for: LayoutID.self)` | One layout per window: sidebar, canvas and inspector. Several windows can be open | MVP |
| Settings | `Settings { SettingsView() }`, opened with ⌘, | App preferences (§8.9) | MVP (General, Build, Privacy); v1 (Keyboard, Advanced) |
| Build & Flash | `.sheet` on the layout window | Build, flash mode, write, verify, done (§7) | MVP |
| Import from Oryx | `.sheet` | Link or connected keyboard; preview (§8.1) | MVP |
| Save Revision | `.sheet` (small) | Message field (§8.7) | MVP |
| Device | `.popover` from the activity capsule and the sidebar device card | Identity, live layer, LEDs, keys down, event monitor (§8.2) | MVP |
| Command palette and keycode picker | In-window floating glass panel (overlay) | §5.6, §5.7 | MVP |
| Menu bar extra | `MenuBarExtra(isInserted:)` with `.menuBarExtraStyle(.window)` | §8.3 | v1 |
| Overlay HUD | AppKit `NSPanel`: nonactivating, borderless, click-through, hosting SwiftUI | §8.4 | v1 |
| Welcome | The layout window's empty state (not a separate window) | §12.1 | MVP |

**Activation policy.** The app is `.regular`, with a Dock icon. In v1, the Settings option "Keep Sextant in the menu bar when its windows are closed" switches the policy to `.accessory` once the last layout window closes.

### 2.2 Navigation model

- **The sidebar selects the destination.** A destination is one layer, one layout document page (Combos, Macros, App Layers, History, Firmware Settings), or another layout in the library.
- **The destination selects the centre content and the inspector content.**

| Destination | Centre | Board lens | Inspector |
|---|---|---|---|
| Layer *n* | Board canvas | Keys, Lighting or Heatmap (segmented control in the canvas header) | Key editor / Brush / Heat stats; Layer summary when nothing is selected |
| Combos (v1) | Board canvas | Combos | Combo editor |
| History (v1) | Board canvas | Changes (diff) | Revision timeline, changes and actions |
| Macros (v1) | Macros page | — | Step inspector |
| App Layers (v1) | App Layers page | — | Rule inspector |
| Firmware Settings | Settings Form page | — | Sections and Changed list |

**Rules**
- **The board never moves.** Its frame depends only on the centre column's size, after fixed bands are subtracted (§3.3). Switching lens, selecting a key, opening the picker, recording, showing banners and Follow mode all leave every key exactly where it was.
- **Sextant never opens, closes or resizes the sidebar or inspector on its own.** Only the user does, by toggle or by window resize.
- **Live is not a lens.** When a keyboard is connected, pressed keys light in every board lens. Follow mode (§8.2) makes the displayed layer track the physical layer.
- **Selection.**
  - The selection is a key index plus a slot. It persists across layers, so ⌘1 to ⌘9 keep the same key selected, and across lenses.
  - In the Lighting lens, a click paints instead of selecting.
  - In the Combos lens, a click selects a combo the key is in, or adds or removes the key while a combo's keys are being chosen.
- **State restoration.** Each window restores its layout, destination, lens, selected key and slot, the sidebar and inspector visibility, and its frame. Use `SceneStorage`, plus restoration of `WindowGroup(for:)` values.

### 2.3 Document and library model

**Library (decided, §14 item 7)**
- Sextant manages a library at `~/Library/Application Support/Sextant/Library/`.
- Each layout is a `.sextant` package: a folder of plain, git-friendly JSON. It holds `layout.json`, `revisions/<n>-<id>.json` (append-only), `firmware/<rev>.bin` and `.md5`, and `meta.json` (UUID, content hash, origin).
- The document model is a lossless superset of Oryx's revision JSON (research §2.3). It has stable UUIDs and content hashes from day one, so sync can be added later (Future).

**Sidebar "Layouts" section**
- Lists the library: title, origin and revision, and badges.
- Badges: **On keyboard** when the connected keyboard's serial matches the layout; **Oryx · read-only source** when it was imported; **Local draft**.
- Clicking a layout opens it in this window. ⌘-click, or the context menu item Open in New Window, opens a new window.
- Row context menu: Open in New Window, Duplicate, Rename…, Show in Finder, Export ▸, Delete… (confirmation; moved to the Trash).

**Saving**
- **Autosave.** Edits are debounced by 1 s and written to `layout.json`.
- **Undo.** Every edit is undoable with a named action, through the window's `UndoManager`.
- **Revisions are checkpoints.** Each records the source device (Future), the date and the content hash. They are created by:
  - an import;
  - every flash (automatically: "Flashed 11 Oct 14:02", or "Flashed revision 2" for History's Flash This Revision…);
  - ⌘S, Save Revision…, which asks for a message.
- **Imported titles.** Oryx's " [fork]" suffix is stripped from titles on import.

### 2.4 Glossary (user-facing names)

| Term | Meaning |
|---|---|
| Layout | A document: layers, combos, macros, settings, history |
| Layer | Numbered from 0. Has a name and an optional colour (the colour is also the layer's LED colour on the keyboard) |
| Key | One of the 52 positions on a layer, addressed by index (key 0 to key 51) |
| Slot | Tap, Hold, Double tap, Tap then hold |
| Kinds | Regular, Modifier, Dual-function, Layer, Lighting, Label, Macro, Tap dance, Transparent, Disabled. Firmware keys, such as Reset, are marked as dangerous |
| Revision | An immutable checkpoint in History |
| Lens | A way of reading the same board: Keys, Lighting, Heatmap, Combos, Changes |
| Follow | The displayed layer tracks the physical keyboard's layer |

"Dual-function" replaces Oryx's "multi-function". It avoids clashing with the slot named "Tap then hold". Instrument used "Tap + Hold" for both, which confused them (A-01).

---

## 3. Main window

### 3.1 Regions

```
+--------------------------------------------------------------------------------------------------+
| [sidebar] [Build & Flash]  My MacOS Layout     ( * Voyager KlgM7/40xJ7M | ^ Not on keyboard · 5 edits )   |
|           Sym+Num · Edited                       [Undo][Redo]  [Follow]  [Search  Cmd-K]  [Inspector] |
+----------------+-------------------------------------------------------------+-------------------+
| SIDEBAR        | CANVAS HEADER (44)   [■ Sym+Num v] Layer 1 · held by ⏎ ...  [Keys|Lighting|Heatmap] | INSPECTOR  |
|  Layouts       | LENS LANE (36)            ( glass capsules, centred )       |  (scrolls)        |
|  Layers        |                                                             |  header           |
|  Layout        | BOARD AREA (flex; board fitted, centred at 46% height)      |  slot strip       |
|   Combos  2    |                                                             |  slot editor      |
|   Macros  2    |                                                             |  key properties   |
|   App Layers 4 |                                                             |  actions          |
|   History  4   | CONTEXT STRIP (76)   key on every layer / lens info         |                   |
|   Firmware  9  | BOARD FOOTER (32)    kind key ...........  [Aa | KC | #]     |                   |
| [device card]  |                                                             |                   |
+----------------+-------------------------------------------------------------+-------------------+
```

### 3.2 Sizes and minimums

| Region | Min | Ideal | Max | Notes |
|---|---|---|---|---|
| Sidebar | 200 | 228 | 300 | `.navigationSplitViewColumnWidth(min:ideal:max:)`. Collapsible with ⌃⌘S |
| Centre column | 640 | flex | — | `.frame(minWidth: 640)` on the detail view |
| Inspector | 280 | 300 | 360 | `.inspectorColumnWidth(min:ideal:max:)`. Toggle through `InspectorCommands` |
| Toolbar plus title bar | system | ≈52 | — | Unified toolbar |
| Window minimum height | 640 | — | — | Below 640 the board would drop under the 36 pt minimum cap size |

**Honest window minimums.** The minimum width is 640 plus the visible columns:
- 1120 with both columns;
- 920 with the inspector only;
- 840 with the sidebar only;
- 640 with neither.

Do not declare a `minWidth` the columns can't satisfy (Instrument declared 1180 but rendered at 1367).

**Default size.** 1440×900, clamped to the screen's visible frame. On displays at least 1728 pt wide, open at 1600×1000.

### 3.3 The board-stability contract

The centre column is a fixed vertical stack. The board's frame is a pure function of the centre column's size:

| Band | Height | Contents |
|---|---|---|
| Canvas header | 44 | Layer jump menu and readout (leading); lens control or document control (trailing) |
| Lens lane | 36 | Up to two glass capsules, centred: a lens tools capsule and a status capsule (§3.7) |
| Board area | flex | The board, fitted with 24 pt padding and centred. Its vertical centre is at 46% |
| Context strip | 76 | The selected key on every layer, or lens-specific information |
| Board footer | 32 | Kind key (leading); Aa / KC / # switch (trailing) |

**Cap size calculation**
- `pitch = min((W − 48) / 15.0, (H − 48) / 6.7)`, where `W` and `H` are the board area.
- `cap = pitch / 1.11`.
- `cap` is clamped to 36–76 pt. Above 76 pt the board stays at 76 and the extra space becomes bench.

**Typical cap sizes**
- 1440×900 with both columns: about 52 pt.
- 1440×900 with the sidebar hidden: about 66 pt.
- 1728×1117 with both columns: about 69 pt.

**Floating items never take board space.** Banners, the picker, the palette, popovers, the record tile and hover tooltips all float over the canvas and never change band heights. Everything transient goes in the lens lane or in a floating panel.

### 3.4 Title bar and toolbar

**Title bar**
- `navigationTitle` is the layout name, for example "My MacOS Layout".
- `navigationSubtitle` is the destination name, plus " · Edited" when there are edits since the last revision. Examples: "Sym+Num · Edited", "Firmware Settings".

**Toolbar items**, leading to trailing. Use `.toolbar(id: "layout")` so the toolbar is customisable.

| # | Item | Placement | Control | Notes |
|---|---|---|---|---|
| 1 | Sidebar toggle | system | — | Provided by `NavigationSplitView` |
| 2 | **Build & Flash** | `.navigation` | `Button { Label("Build & Flash", systemImage: "bolt.fill") }.buttonStyle(.glassProminent).controlSize(.large)` | States: idle "Build & Flash"; building or waiting "Stop" (`stop.fill`, red tint); writing or verifying "Writing…" (disabled, with a determinate ring in the icon); failed "Build & Flash", with the error shown in the capsule. Tooltip with ⌘R |
| 3 | Title and subtitle | system | — | |
| 4 | **Activity capsule** | `.principal` | Custom view, width 280–520 (ideal 440) | §3.5. Two click targets: the device segment opens the Device popover; the status segment opens the Build & Flash sheet or the build log |
| 5 | `ToolbarSpacer(.flexible)` | | | |
| 6 | Undo / Redo | `.primaryAction` group (one shared platter) | `arrow.uturn.backward` / `arrow.uturn.forward` | Tooltips name the action: "Undo Set Hold (⌘Z)" |
| 7 | `ToolbarSpacer(.fixed)` | | | |
| 8 | Follow Keyboard | `.primaryAction` | Toggle button, `dot.radiowaves.left.and.right` | Shown selected when on. Disabled when no keyboard is connected. ⌘L |
| 9 | Search | `.primaryAction` | A capsule labelled "Search  ⌘K" in windows of 1280 pt or wider, otherwise `magnifyingglass` | Opens the palette, or closes it when open (as ⌘K does) |
| 10 | Inspector toggle | `.primaryAction` | `sidebar.trailing` | Same command as `InspectorCommands` |

There is no layer menu in the toolbar.

### 3.5 Activity capsule

Layout: `[● Voyager  KlgM7/40xJ7M] │ [icon  status text ……… detail]`, with a 2 pt progress hairline along the bottom edge. A trailing slot is reserved for a Future sync glyph.

| State | Icon | Status text | Detail | Hairline |
|---|---|---|---|---|
| No keyboard | grey dot | "No keyboard" | — | — |
| Keyboard runs this revision, no edits since | `checkmark.circle.fill` (green) | "On keyboard" | revision date | — |
| Edits not yet flashed | `arrow.up.circle` (orange) | "Not on keyboard" | "5 edits" | — |
| Keyboard runs another layout | `exclamationmark.triangle.fill` (orange) | "Keyboard runs another layout" | `Q9x2/aa11` | — |
| Keymapp holds the device | `lock.fill` (secondary) | "In use by Keymapp" | — | — |
| Live issues (pre-build) | `exclamationmark.triangle.fill` | "2 issues" | "key 45" | — |
| Building | spinner | "Compiling keymap.c" | "12 of 41" | determinate |
| Built (⌘B only) | `checkmark.circle.fill` | "Built" | "65,786 B · 26%" | — |
| Waiting for flash mode | `button.horizontal.top.press` (orange) | "Waiting for flash mode" | "Press the reset button" | indeterminate shimmer (Reduce Motion: static) |
| Writing / Verifying | spinner | "Writing · 64%" / "Verifying · 40%" | bytes | determinate, per phase |
| Flashed | `checkmark.seal.fill` (green) | "Flashed" | revision id | Shown for 8 s, then "On keyboard" |
| Build failed | `xmark.octagon.fill` (red) | "Build Failed" | "1 error · key 45" | — |
| Flash failed | `xmark.octagon.fill` | "Flashing didn't finish" | "Try again" | — |

**Rules**
- The **device dot** is green when connected, orange in flash mode, and grey when absent. A serial that doesn't match the layout gets a trailing orange "≠" in the device segment.
- **Width.** At widths below 360 pt the serial and the detail hide.
- **Accessibility.** The capsule is two buttons, each with its own label.

### 3.6 Sidebar

`List(selection:)` with `.listStyle(.sidebar)`. The sections, in order:

**1. Layouts** (collapsible, remembers its state)
- One row per library layout (§2.3).
- The open layout is selected.

**2. Layers**
- **Row contents:** colour chip (10 pt rounded square; base layer neutral), index in monospaced digits, name, then a trailing `.badge(assignedCount)`.
- **Live badge.** A `dot.radiowaves.left.and.right` badge marks the layer the physical keyboard is on.
- **Add Layer.** A final row, "Add Layer", with a `plus` symbol (⇧⌘N).
- **Reordering.** Drag to reorder with `.onMove`. Layer references follow the move, as one undo step: "Move Layer".
- **Context menu:** Rename… (edits the name in place; no double-click, which held every click's selection until it timed out), Colour ▸ (layout swatches, Custom…, No Colour), Duplicate, Move Up / Move Down, Copy Layer To ▸ (v1; §6.1), Clear Layer…, Delete Layer….

**3. Layout**
- Combos, Macros, App Layers and History each carry a count badge.
- Firmware Settings carries an accent badge with the modified count.

**Pinned device card**
- Pinned with `.safeAreaInset(edge: .bottom)` on the List, as a flat card on the sidebar material.
- Line 1: status dot, "ZSA Voyager", and four status-LED pips on the trailing edge.
- Line 2: "Connected · USB".
- A grid of rows:
  - Layer: chip and name;
  - Layout: `KlgM7/40xJ7M` in mono, followed by ✓ "matches", or ⚠ "different layout";
  - Firmware: "25.0 · protocol 5".
- Click to open the Device popover.
- **Other states:**
  - "No keyboard · Connect your Voyager with USB";
  - "Flash mode (bootloader)";
  - "In use by Keymapp";
  - "Runs KlgM7/40xJ7M · not in your library", with an [Import] button.

### 3.7 Canvas

**Canvas header (44 pt)**
- **Leading:** a pop-up button with the layer chip, the layer name and a chevron. It is the jump menu, and is always present.
- **Readout,** in callout size, secondary: "Layer 1 · held by ⏎ (key 24) · 47 own · 5 inherited". Variants:
  - "Layer 0 · base · 52 keys" for the base layer;
  - "LIVE · following the keyboard" while following.
- **Trailing:** a `Picker(.segmented)` for the lens (Keys / Lighting / Heatmap), at small control size.
- **Document lenses** replace the trailing control:
  - Combos: "Keys from: All layers ▾", a filter: every combo, or only those reading one layer, which it then shows (ADR 0046);
  - History: "Compare with: Previous revision ▾".

**Lens lane (36 pt)**
- An `HStack` inside a `GlassEffectContainer(spacing: 8)`, centred. It holds at most:
  1. a **lens capsule**: Lighting tools, Heatmap summary, Combos "New Combo" with the count (while choosing keys: the keys so far with [Choose Output…] or [Done]), or the History comparison;
  2. a **status capsule**, by priority: board pick or Select Key by Pressing It > error > recording > Follow/live > app rule. A board pick (choosing combo members, Assign to Key) comes first because only its prompt says what a click does; Select Key by Pressing It's capsule likewise says what the next press does (§5.8.1). Record Key started during a pick hides it until recording ends, since esc ends recording first (§9.3, ADR 0037). The pick capsule's [Cancel] is the window's cancel shortcut (esc, ⌘.), so esc ends a pick even when the board misses it (ADR 0042). Choosing another page drops the pick.
- Capsules are 28 pt tall. They use `.glassEffect(.regular.interactive(), in: .capsule)` and appear with `.glassEffectTransition(.materialize)`.

| Status capsule | Content | Action |
|---|---|---|
| Error | `xmark.octagon.fill` "Unknown keycode on Brd+Sys · key 45 · Tap · keymap.c:31" | [Show Key] (⌘') |
| Recording | red dot "Listening for a key… esc cancels" | [Cancel] |
| Board pick (v1) | `hand.point.up.left` "Click a key to play ‘Open Keymap’ on tap · esc cancels" | [Cancel] (esc, ⌘.) |
| Select by press (v1) | `keyboard` "Press a key on the keyboard to select it"; `eye.slash` "Paused: secure input is on · esc cancels" | [Cancel] |
| Live (Follow on) | green dot "LIVE · Brd+Sys held by Space · 2 keys down" | [Stop Following] |
| App rule (v1) | "Xcode is frontmost → keyboard on Sym+Num" | [Rules…] |

**Board area.** See §4.

**Context strip (76 pt)**
- **Keys lens, key selected:** one card per layer, from layer 0 upwards. Each card is 60 pt tall and holds a mini cap (36 pt), the layer chip and name, and a one-line description.
  - Examples: "⏎ · hold Sym+Num", "Inherits ⏎", "Esc".
  - The current layer's card has an accent outline.
  - Transparent cards are dashed, with a `←` fall-through arrow between cards.
  - Clicking a card switches to that layer and keeps the key selected.
  - The strip scrolls horizontally when there are more than 6 layers.
- **Keys lens, nothing selected:** a hint, "Select a key to see it on every layer · ⏎ edits · ⌘K finds anything". After first use it becomes per-layer key counts.
- **Lighting:** a card per layer with the layer colour and "19 of 52 keys have their own colour".
- **Heatmap:** layer share cards. With a key selected, that key's count on each layer.
- **Combos:** combo cards ("J + K → Esc", then the name and "Keys from Main"), scrolling horizontally. Click one to select it and show its layer. The last card is "+ New Combo". With no combos, the empty state (§12.4).
- **Changes:** per-layer change counts ("Brd+Sys · 4 changes"). Click one to show that layer.

**Board footer (32 pt)**
- **Leading: the kind key.** It lists only the kinds present on the displayed layer, each with a mini cap swatch and a name. Hovering or pressing a kind dims every other key to 35%.
- **Trailing: the legend mode switch** "Aa · KC · #". A small glass segmented control (`Picker(.segmented)` inside a glass capsule).

### 3.8 Inspector routing

| Destination / lens | Inspector | Empty state |
|---|---|---|
| Layer · Keys | Key editor (§5.1) | Layer summary: name field, colour, index, "Held by ⏎ (key 24) on Main", counts by kind, and the layer actions Duplicate, Copy To…, Clear… |
| Layer · Lighting | Brush and layer lighting (§6.2) | — |
| Layer · Heatmap | Heat statistics (§8.5) | "Heatmap recording is off" with [Turn On…] |
| Combos | Combo editor (§6.4) | "Select a combo or press N to make one" |
| History | Timeline, changes and actions (§8.7) | — |
| Macros | Step inspector (§6.3) | "Select a step" |
| App Layers | Rule inspector (§8.6) | — |
| Firmware Settings | Sections and Changed (N) (§8.8) | — |

**Inspector conventions**
- The inspector is a `ScrollView` with 16 pt horizontal padding.
- Labels are right-aligned in an 84 pt column.
- Controls are stock: `.bordered` buttons, `Picker(.segmented)`, `Toggle`, `TextField`, `ColorPicker`.
- Text uses semantic `.primary`, `.secondary` and `.tertiary`.
- Section headers are SF Pro `.headline` in sentence case.

---

## 4. Board rendering

### 4.1 Geometry and scale

- **Source.** `BoardGeometry.voyager(stagger: .oryx, halfGap: 3.0, navigator: <from layout>)`. This is calibrated from `voyager-geometry.json` and Oryx's render:
  - column stagger of 0.15u and 0.30u;
  - thumbs rotated ±30° around the cluster pivot;
  - the inner thumb (keys 25 and 50) is 1u × 1.35u.
- **Board size.** 15.0 pitch units wide by about 6.7 tall.
- **Spacing.** The gap between caps is 0.11 × cap.
- **Navigator.** For a layout with a Navigator, draw a recessed, non-interactive disc of 0.95 pitch at the inner edge of the half it is attached to (Firmware Settings › Navigator › Side), between rows 1 and 2. Use a trackpad or trackball glyph and the tooltip "Navigator trackpad · settings in Firmware Settings › Navigator" ("Navigator trackball · …" for a trackball).
- **Thumbs.** Thumbs and their legends rotate together, as on the hardware. Hit-testing uses a rotated `contentShape`.
- **Optical centring.** The board is centred horizontally. Vertically, its centre sits at 46% of the board area.

### 4.2 Cap anatomy

```
 +---------------------------+
 | 19                     o  |  corner indicators: top-left = index or combo number;
 |                           |  top-right = issue / diff / LED dot (§4.8)
 |            Z              |  primary legend zone (top 70%, or 100% when there is no band)
 |                           |
 |---------------------------|  band hairline: kind colour at 45%
 |           ⌥ L             |  hold band: 30% of height (26% on the tall thumb)
 +---------------------------+
        ----                    signal bar (only when there is no band): 0.36u × max(2, 0.05u), 0.08u from the bottom
```

- **Shape.** `RoundedRectangle(cornerRadius: 0.16u, style: .continuous)`.
- **Face.** A vertical gradient from `cap.top` to `cap.bottom`.
- **Edges.** A 0.75 pt `cap.edge` stroke and a 1 pt `cap.highlight` inner top edge.
- **Shadow.** Light mode: two layers (y 1, r 2, 10%; y 2, r 6, 6%). Dark mode: y 2, r 5, 45%.
- **Hold band.**
  - Fill: the kind colour at 12% (light) or 18% (dark), clipped to the cap.
  - Text: the band ink token (§10.1).
  - On a layer-tap key, the band shows `square.stack.3d.up.fill` and the target layer's name, in that layer's ink colour.
- **Signal bar.** A capsule in the kind colour, used for single-function special kinds. The cap face also gets a tint of the kind colour at no more than 5%.

### 4.3 Legend typography and naming

All sizes are relative to `u`. Legends use SF Pro, except where noted.

| Legend | Size / weight | Rules |
|---|---|---|
| Single character (A, 1, [) | 0.36u medium | Letters in upper case |
| Modifier glyph (⌃ ⌥ ⇧ ⌘) | 0.34u regular, with an L/R mark at 0.13u bold, 70% opacity, baseline −0.04u | Hyper and Meh are written as words at 0.20u semibold |
| Short word (Esc, Tab, F12, Home, PgUp) | 0.22u semibold | Title-case short words: Esc, Space, Home, End, PgUp, PgDn, Ins, PrtSc, Reset |
| Long label (5–10 characters, e.g. "Prev Tab") | 0.17u semibold, 2 lines, minimum scale 0.75 | Custom labels in SF Pro, never serif |
| Label annotation (the real chord) | 0.13u SF Mono, secondary | Under the label, e.g. "⇧⌘[" |
| SF Symbol legend | 0.30u regular, or 0.25u with a caption | §10.5 |
| Caption under a symbol | 0.13u medium, secondary | Sextant's own words: Vol+, Vol−, Mute, Play, Next, Prev, RGB, Layer RGB, Effect, Solid, LED−, LED+, Hue+, Colour |
| Hold band legend | 0.15u semibold (glyph); 0.14u semibold layer name plus a 0.13u stack glyph | One line, minimum scale 0.7 |
| "hold" marker on hold-only keys | 0.11u medium, tertiary | In the band position, with no band fill (Main keys 18 and 25) |
| Index (# mode, or with ⌥⌘N) | 0.12u SF Mono medium, 40% | Top-left, 0.07u inset |
| QMK mode | 0.12u SF Mono, up to 3 lines | Shows the whole-key expression; the band is hidden |
| Heat count | 0.12u SF Mono, monospaced digits | Under the legend |

**Glyph rules**
- **Glyph legends:** ⏎ for Return, ⇥ for Tab, ⌫ for Backspace, ⌦ for Delete, ⇪ for Caps Lock.
- **Arrows** use the `arrow.left`, `arrow.up`, `arrow.right` and `arrow.down` symbols.
- **Word legends:** Esc, Space, Home, End, PgUp and PgDn. This follows the brief, and the ⎋ glyph is used only in menus and hints.
- **Shifted punctuation** shows the produced character, for example "!" for `KC_EXLM`.
- **Oryx macOS pseudo-codes** (`KC_MAC_COPY`, etc.) show a word ("Copy") with the chord as an annotation ("⌘C").
- **`QK_BOOT`** shows "Reset" in system red, with a red signal bar. Its tooltip is "Puts the keyboard in flash mode".
- **Unknown codes** show the raw code in mono with a warning badge.

### 4.4 Key-kind system

There are three independent channels, so they never compete for the same pixels:
1. **Layer channel.** A 1.25 pt outer ring in the layer colour (§4.5).
2. **Secondary-action channel.** The hold band, which says what the hold does.
3. **Kind channel.** The signal bar plus a faint tint, used only when there is no band.

| Kind | Primary legend | Band | Signal bar and tint | Example |
|---|---|---|---|---|
| Regular | The keycode | — | — | Q |
| Modifier (tap) | Glyph with L/R | — | `kind.modifier` | Main key 12 ⇧L |
| Hold-only modifier | Glyph with L/R | "hold" marker, no fill | `kind.modifier` | Main keys 18 (⌃L) and 25 (⌘L) |
| Dual-function, modifier hold | Tap legend | `kind.modifier` band: "⌥ L" | — | Z / ⌥ (key 19), ' / ⇧ (key 43) |
| Dual-function, key hold | Tap legend | `kind.holdKey` band: "Esc" | — | = / Esc (key 0) |
| Dual-function, layer hold | Tap legend | Target layer band: stack glyph and "Sym+Num" | — | ⏎ (key 24), Space (key 51) |
| Layer key (MO, TG, TO, TT, OSL) | Stack glyph, target name, and an action caption (hold, toggle, go to, tap-toggle, one-shot) | — | Target layer colour (`kind.layer` when the target has none) | — |
| Lighting | Symbol with caption | — | `kind.lighting` | Brd+Sys key 0 "RGB" |
| Set-colour key | A 0.30u glowing swatch disc, captioned "Colour" | — | `kind.lighting` | Brd+Sys keys 21–23 |
| Label | Label text with an annotation | — | `kind.label` | Brd+Sys keys 44–47 "Back", "Prev Tab" |
| Macro | Macro name (label style) | — | `kind.macro` | "Open Keymap" |
| Tap dance | Tap legend | The hold, if there is one; otherwise the double-tap action with a "2×" prefix | `kind.tapDance` (also drawn when a band is present, offset 0.04u below it) | — |
| Transparent | Inherited legend at 40% | Inherited band outline at 40% | Dashed outline, no face | Sym+Num key 19 |
| Disabled (`KC_NO`) | `nosign` at 0.24u, 50% | — | 45° hatch at 12% | Brd+Sys keys 18 and 43 |
| Firmware danger (`QK_BOOT`) | "Reset" in red | — | `status.danger` | Brd+Sys key 31 |

**The kind key** in the board footer uses the same mini-cap swatch for each kind. Its names are Regular, Modifier, Dual-function, Layer, Lighting, Label, Macro, Tap dance, Transparent and Disabled.

### 4.5 Layer colour treatment

Layer colours are user data, and they are also firmware LED colours.

**Display transforms**, computed once per layer and cached:
- **`layer.display`** is used for rings, chips and glows.
  - Dark mode: the colour as stored.
  - Light mode: reduce HSB brightness in 0.02 steps until the contrast against `#FFFFFF` is at least 3:1. #00F0FF becomes about #00959E, and #42FF00 becomes about #299E00.
- **`layer.ink`** is used for text on chips and bands.
  - Light mode: reduce until the contrast is at least 4.5:1. That gives about #007880 and #218000.
  - Dark mode: the colour as stored, or lightened until it reaches 4.5:1 against `#2A2A2E`.
- **Base layer** (no colour): the chip is neutral `#8E8E93 / #98989D`. There are no rings.

**On a non-base layer**
- Every key the layer **owns** (not inherited) gets a 1.25 pt ring in `layer.display`, outset by 1 pt.
  - Dark mode adds a 6 pt glow at 45%.
  - Light mode makes the ring 1.5 pt, with no glow.
- **The key holding the displayed layer** (for example key 24 on Sym+Num, Space on Brd+Sys) is the most prominent key on that layer, so it reads as "hold this to get here". It is static: no pulse.
  - Face: tinted with `layer.display` at 10% light / 16% dark, and hatched in the layer colour: 45° lines spaced 0.10u, at 30% in light mode and 38% in dark.
  - Its inherited legend and band draw at full strength, not at the transparent 40%.
  - Ring: it gets the ring even though it is transparent on that layer, 0.5 pt thicker than an owned key's (2 pt light, 1.75 pt dark, 2.5 pt with Increase Contrast).
  - Halo: a 0.12u glow in `layer.display` (75% light, 90% dark), drawn behind the cap, on the board only (the context strip, inspector header and scope token keep the tint and ring). An issue ring replaces both the ring and the halo.
- **Atmosphere.** A radial wash of `layer.display` sits on the bench behind the board: 5% light, 7% dark, radius 0.6 × the board width. It crossfades over 0.3 s on layer change.

### 4.6 Transparent, inherited and disabled keys

- **Transparent.**
  - Face: `cap.ghost.fill`, with no shadow.
  - Outline: a 1 pt dashed stroke (3 on, 2.5 off) in `cap.ghost.stroke`.
  - Legend: the effective legend from the layer below, at 40%.
  - The tooltip and inspector say "Transparent. Acts as Z (hold ⌥) from Main".
- **Empty slot (`null`).** Oryx stores some keys with no tap and no hold, such as Brd+Sys keys 18 and 43. Render them as Disabled with the tooltip "No action".

### 4.7 States

| State | Treatment | Reduce Motion / Increase Contrast |
|---|---|---|
| Hover | 1 pt outline, `.primary` at 22% | Increase Contrast: 40% |
| Selected | 2 pt accent ring, offset 2.5 pt outside the cap, following its rotation | Ring 3 pt |
| Board focused and selected | Selection ring plus a 4 pt accent glow at 35% | Glow off; ring 3 pt |
| Picker preview | Dashed 1.5 pt accent ring; the previewed legend at 75% replaces the current one | — |
| Pressed (live) | Face filled with `layer.display` (live green on the base layer) at 80% dark / 65% light; 0.18u glow in dark mode; scale 0.96; legend ink chosen by luminance. Fades out over 0.12 s on release | No scale |
| Recording | 2 pt system red ring and a top-centre "REC" badge (0.11u heavy, red capsule); the ring pulses at 0.9 s | Static ring |
| Issue | 2 pt red (error) or orange (warning) ring, with a 14 pt "!" badge at top right | — |
| Diff | Added: `plus.circle.fill` green. Changed: orange dot. Removed: `minus.circle.fill` red. 2 pt ring in the same colour. Unchanged keys at 40% | Badges carry glyphs, so colour is not the only cue |
| Combo member | 2 pt ring in the combo colour, with a numbered badge at top left | — |
| Dimmed (kind-key hover, combo non-member) | 35–45% opacity | — |
| Drag to swap | The source lifts (shadow plus scale 1.04). A dashed line runs to the target, which shows an accent outline | No lift |

### 4.8 Corner indicator priority

- **Top-right**, in priority order: issue > diff > LED dot. Only one shows.
  - The LED dot is 0.11u, 0.09u inset, with a 0.5 pt edge. It shows when the key has its own LED colour.
- **Top-left**, in priority order: combo number > index.

### 4.9 Legend modes

| Mode | Shortcut | Shows |
|---|---|---|
| Aa (default) | ⌥⌘1 is taken by slots, so use the menu or the footer switch | Glyph legends with bands |
| KC | ⌥⌘C | The whole-key QMK expression, e.g. `LT(1, KC_ENTER)` |
| # | ⌥⌘N | The index at 0.30u mono, with the primary legend at 0.14u |

### 4.10 Bench

The bench is the content surface behind the board. It is never glass.

- **Base and lift.**
  - Light mode: `#EDEDF0`, with a soft radial lift (`#F7F7F9` at the centre).
  - Dark mode: `#141416`, with a lift of `#202024`. Instrument's dark lift was invisible, so it is raised here.
- **Precision grid.** Hairlines on the key pitch, aligned to the board's grid, at 4% (light) or 4.5% (dark). The grid fades out radially beyond 1.5 pitch from the board's bounds.
  - It is off under Increase Contrast.
  - It can be turned off in Settings › General.
  - This is the only remnant of the "chart" identity: precision, not nautical theming.
- **Layer atmosphere** (§4.5).

### 4.11 Accessibility for caps

- **Board container.** `.accessibilityElement(children: .contain)`, with the label "Keyboard, Sym+Num layer, 52 keys".
- **Reading order.** The left half row by row, then the left thumbs, then the right half row by row, then the right thumbs. Use `.accessibilitySortPriority`.
- **Each cap** is `.accessibilityElement(children: .ignore)` with:
  - **Label** (short): "Return, hold for Sym+Num", "Z, inherited", "Reset".
  - **Value:**
    - "Dual-function. Tap sends Return. Hold activates layer 1, Sym+Num. Left thumb, outer key, key 24."
    - "Transparent on Sym+Num. Acts as Z, hold Left Option, from Main. Left hand, bottom row, column 2, key 19."
  - **Traits:** `.isButton`, plus `.isSelected` when selected.
  - **Hint:** "Press Return to change. Actions available."
  - **Custom actions:** Change Tap, Change Hold, Record Key, Make Transparent, Disable, Override on This Layer, Show on Other Layers, Copy QMK Expression.
- **Rotors.** Layers (switch the displayed layer), Key kinds (one entry per kind present), Issues, Changed keys (Changes lens), Painted keys (Lighting lens).
- **Live changes are not announced per key.** Layer changes while following are announced, at most once a second: "Sym+Num layer".

---

## 5. Key editor, keycode picker, command palette, Record Key

### 5.1 Inspector layout (Keys lens, key selected)

1. **Header.**
   - A 52 pt cap preview, using the same KeyCap view as the board.
   - Title (`.title3` semibold): the action name or label, e.g. "Return" or "Prev Tab".
   - A kind badge (capsule with a mini signal bar), e.g. "Dual-function".
   - A layer chip.
   - Subtitle: "Left thumb · key 24".
   - QMK row: `LT(1, KC_ENTER)` in mono, selectable, with a copy button. The matrix position "R5 C0" is in tertiary text on the trailing edge.
2. **Issue callout** (when the key has a build or live issue; §7.5).
3. **Transparent callout** (when this layer's key is `KC_TRNS`).
   - Copy: "Transparent on Sym+Num. Acts as Z (hold ⌥) from Main."
   - Button: [Override on Sym+Num]. It copies the inherited definition onto this layer as one undoable step, named "Override Key".
4. **Slot strip.**
   - Four equal tabs: Tap · Hold · Double tap · Tap then hold.
   - Each tab shows its title (caption) and a mini legend, or `plus` in tertiary when empty.
   - The selected tab has a 1.5 pt accent outline and an accent title.
   - Keyboard: ⇥ / ⇧⇥ with board focus, and ⌥⌘1–⌥⌘4.
5. **Summary sentence** (`.callout`, secondary). Examples:
   - "Tap sends Return. Hold activates Sym+Num (MO 1)."
   - "Tap types Z; hold for Left Option."
6. **Slot editor** (§5.2).
7. **Key section.**
   - Label: `TextField` limited to 10 characters, with a "0/10" counter and the placeholder "None — shows the keycode". Footnote: "Shown in Sextant only; not sent to the keyboard."
   - LED colour: a swatch row.
     - Layer colour (default): a hollow ring in the layer colour.
     - Off.
     - The layout's 10 swatches.
     - Custom…, which opens a `ColorPicker`.
   - Tapping term (v1): "Global (180 ms)" or Custom, with a field and stepper in 10 ms steps, showing the delta from global ("+20 ms from global"). It shows for a key with a hold, a double tap or a tap then hold, or one that already has its own term. A custom term turns on Per-key tapping term in the same undo step, "Set Tapping Term"; a value equal to the global term is stored as Global (ADR 0041).
8. **Actions.**
   - [Record Key] at full width, with "⇧⌘R" right-aligned in secondary text.
   - [Make Transparent ⌘⌫] and [Disable ⇧⌘⌫] at half width each.
   - All stock `.bordered` buttons.

### 5.2 Slot editors

**Tap, and Double tap**
- **Action tile.** 44 pt tall: mini cap, name, and the QMK code in mono caption, with a trailing `magnifyingglass`. Clicking it or pressing ⏎ opens the picker. The buttons below are [Change… ⏎], [Record ⇧⌘R] and [Clear].
- **Chord with.**
  - A 2×4 grid of toggle buttons, in rows L and R and columns ⌃ ⌥ ⇧ ⌘ (`.toggleStyle(.button)`, accent when on).
  - [Hyper] and [Meh] shortcut toggles sit beside the grid.
  - The result shows in the QMK row, e.g. `RGUI(KC_LBRC)`.
- **Layer action.** Shown when the action is a layer keycode (§5.3).
- **Empty state.** A dashed tile: "+ Add double-tap · Tap twice quickly to send another key". It has [Pick] and [Record] buttons.

**Hold, and Tap then hold**
- A segmented control: **Holding: Modifier · Layer · Key · Nothing**.
- **Modifier:**
  - ⌃ ⌥ ⇧ ⌘ toggles (more than one allowed, e.g. `MT(MOD_LCTL|MOD_LSFT)`);
  - a Left / Right segmented control;
  - Hyper and Meh.
- **Layer:** layer chips (colour, index and name). The current layer is marked "this layer". The result is `LT(n, …)`.
- **Key:** an action tile, as for Tap (dual-function keys such as = / Esc).
- **Nothing:** clears the slot.
- **Empty state:** "+ Add hold · Hold for a modifier or layer".

### 5.3 Layer actions

| Option | QMK | Caption on the cap |
|---|---|---|
| Hold | `MO(n)` | hold |
| Toggle | `TG(n)` | toggle |
| Go to | `TO(n)` | go to |
| Tap-toggle | `TT(n)` | tap-toggle |
| One-shot | `OSL(n)` | one-shot |
| Hold + mods (in a More ▾ menu) | `LM(n, mods)` | hold |

- The control is a `Picker(.segmented)` with the first five options, plus a "More" menu.
- Below it sit the layer chips.
- A warning appears when the target is the key's own layer, or a layer that the key's own layer cannot reach.

### 5.4 Multi-selection (v1)

- **Selecting.** ⌘-click toggles a key in the selection. ⇧-click selects a range in reading order (VoiceOver's: the left half row by row, its thumbs, then the right half), from the anchor: the key selected first, which the slot editor shows. Only on the plain board in the Keys lens; another lens or a pick acts on the anchor alone, and the others show again in the Keys lens. Arrows and a drag collapse the selection to one key, and esc first keeps only the anchor (§9.3). VoiceOver's "Add to Selection" action stands in for ⌘-click (ADR 0047).
- **Board.** A ring on every selected key; the context strip says "3 keys selected · ⌘-click adds or removes a key · esc keeps one".
- **Inspector.** It shows "3 keys", the layer and the key numbers, and a slot strip with each slot's shared value or "Mixed". Common actions: Make Transparent, Disable, Set LED Colour, Copy To Layer ▸, Clear Label.
- **Slot editing** across keys applies one value to all of them, as one undo step ("Set Tap on 3 Keys"). When the keys differ in the slot it says "Mixed: 3 different" with Change… and Clear. The picker's target is "3 keys › Tap on Main", with no cap and no preview on one key, and its footer says "Now mixed" when the keys differ; each key keeps its own chord, and a macro from the Macros category goes on every key's tap.
- **Key menus** act on every selected key (Override on This Layer on the inherited ones); Record Key and Copy QMK Expression act on the anchor. Show Issue and Find Key select the key alone.

### 5.5 Direct manipulation

- **Drag one key onto another to swap them** on the current layer, as one undo step: "Swap Keys". ⌥-drag copies instead. This is MVP, since it is cheap and is Oryx parity.
- **Copy and paste (v1).** ⌘C copies the selected keys' full definitions, and ⌘V, with a key selected, pastes one key onto every selected key ("Paste Key"), or several keys back to their own places on the shown layer, which it then selects ("Paste 3 Keys"). ⌘X copies and makes them transparent. These act on keys only while the board has focus. The pasteboard gets a `com.sextant.keys` flavor and the keys' QMK expressions as text; what is pasted is checked first (ADR 0047).
- **Type to search.** Typing a printable character while the board has focus opens the picker in assign scope, pre-filled with that character. This doesn't apply in the Lighting lens (B/E/I/G) or the Combos lens (N).

### 5.6 Keycode picker (assign scope)

The picker is the command palette component in **assign scope**.

**Placement**
- A floating glass panel (`SurfaceStyle.floating`, corner radius 22) over the **half of the board opposite the target key**. The target cap always stays visible.
- Thumb keys use the same rule.
- **Width** is the smaller of 560 and (centre width / 2 + 40). **Height** is 440.
- In centre columns narrower than 800 pt, the category rail collapses to icons with tooltips.

**Live preview.** The target cap shows the highlighted keycode in the preview state (§4.7).

**Header**
- A scope token shows the target: "[Z] › Hold on Main". ⌫ on an empty field removes the token and turns the panel into the general palette. A long title (a long macro name) is cut in the middle at 200 pt, so its end ("› Step 3") and the field stay visible.
- A target that isn't a key ("Combo 3 › Output", a macro step) has no cap and no board preview. ⌘⏎ assigns and closes, the footer leaves out "& next" and ⇧⌘R, and the selected key never changes (ADR 0037).
- The search field is focused, with the placeholder "Search N keycodes, or type a character". N is the sum of the rail's counts for this target, so the two always agree: a layer function counts once per layer, a key's tap adds the layout's macros, and a macro step's picker counts only the keys a step can type.

**Category rail** (160 pt, labelled, with counts):
- Suggested (recents, plus slot-aware suggestions: layers and modifiers for Hold);
- Letters, Digits, Modifiers, Punctuation, Navigation, Editing, Function Keys, Media, Mouse, Lighting, Layers, System, Firmware, International, Numpad, Navigator;
- Macros (v1): the layout's macros. On a key's tap a choice goes there as Assign to Key puts it; a key's other slots offer none, since a macro plays only from a tap. Another target, such as a combo's output, gets a copy.
- Special (Transparent, Disabled).

**Results**
- Browsing a category shows a keycap tile grid: 84 pt tiles with a 50 pt cap and the short code in 11 pt mono, so legends read at a glance.
- Searching shows a ranked list. Each row has a cap, the name, the QMK code with aliases, a shifted hint ("⇧ {"), the category, and a ✓ on the current value.

**Search ranking**
1. exact glyph ("[", "⌘");
2. exact code or alias (`KC_LBRC`, `LBRACKET`);
3. name prefix;
4. word match ("vol" finds Volume Up and Volume Down);
5. fuzzy.

**Keys**

| Key | Action |
|---|---|
| ↑ ↓ (and ← → in the grid) | Move |
| ⏎ | Assign |
| ⌘⏎ | Assign and move to the next key in reading order, keeping the picker open |
| ⇥ / ⇧⇥ | Next / previous category |
| ⌥⇥ | Next slot |
| ⇧⌘R | Switch to Record |
| esc | Close |

**Dismissal**
- esc closes the picker wherever focus is in its window. An input method's composition takes esc first, and Record Key is never on at the same time.
- A click outside the panel closes it, and the click still does what it would have done (selects that layer, presses that button). A click inside the panel never closes it.
- A click on a key on the board retargets the picker to that key instead, so several keys can be assigned in turn. Focus stays on the board, so typing starts a fresh search there.
- ⌘K or ⇧⌘O switches to the general palette.
- The panel also closes when its window stops being key.
- Closing gives keyboard focus to the board, so arrows and ⏎ keep working, unless the click that closed it focused a text field or a list.

**Footer** (tertiary, with key hints): "↑↓ move · ⏎ assign · ⌘⏎ assign & next · ⇥ category · ⇧⌘R record · esc close". The current value is on the leading side: "Now KC_TRANSPARENT".

**Motion.** The panel appears with a fade and a scale from 0.98 at its anchor, over 0.16 s (§10.6). When it comes from the general palette, it morphs using `glassEffectID`.

### 5.7 Command palette (⌘K, general scope)

**Placement and size.** A floating glass panel at the top centre of the window, 24 pt below the toolbar. It is 640 pt wide, and up to 480 pt tall.

**Result groups, in order**
- **Suggested for the selected key:** "Change Hold · Left Option · ⌥⌘2", and similar.
- **Commands,** with their shortcuts on the trailing edge.
- **Keys in this layout:** "Esc · Sym+Num · key 0". Choosing one jumps to that layer and selects the key.
- **Layers.**
- **Keycodes:** "Assign to Z › Tap…". This enters assign scope.
- **Firmware settings,** with their live values: "Tapping term · 180 ms · changed". Choosing one opens the Settings page scrolled to that row.
- **Documents (v1):** macros, combos and revisions.

**Pasting an Oryx link** (a `configure.zsa.io` URL) makes the top result "Import from Oryx…". A preview pane on the right shows a mini board and counts. ⏎ opens the Import sheet pre-filled.

**Empty query:** shows Suggested, then Recent commands.

**Keys:** ↑ ↓, ⏎ to run, ⌘⏎ for the alternate action (open in a new window, or assign and advance), and esc to close. ⇧⌘O is an alias for ⌘K. ⌘K while the palette shows closes it, like Spotlight.

**Dismissal:** as the picker's (§5.6), except that a click on a key closes the palette and selects the key.

### 5.8 Record Key mode

**Starting.** ⇧⌘R, the [Record Key] button, or [Record] on a slot tile.

**While recording**
- The slot tile becomes a red-tinted "Listening… Press a key on your keyboard · esc cancels" tile with [Cancel].
- The target cap shows the recording state (§4.7).
- The lens lane shows the Recording capsule.

**Capture**
- Use `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])`. Install it only while recording, scoped to the key window. It needs no Input Monitoring.
- **What is assigned:** the next key-down, with its held modifiers and their side. Left and right are told apart by device-dependent flag bits.
- **A lone modifier** that is pressed and released assigns that modifier itself (e.g. Right Shift).
- **Key mapping** goes from position (`keyCode`, `kVK_*`) to a QMK code. It covers ANSI, ISO and JIS.

**Esc always cancels.** It is never recorded. To assign Esc, use the picker. The tile says so: "To assign Esc, search for it instead."

**Recording also ends** when the window resigns key, the user changes key, or the picker opens.

### 5.8.1 Select Key by Pressing It (v1)

- **Starting.** Key ▸ Select Key by Pressing It (⇧⌘L), while the board shows, no pick is under way and Live View is on and paired. Otherwise the item is disabled and its help tag says why ("Turn on Live View (Keyboard ▸ Live View) to select a key by pressing it."); it never turns Live View on itself. It ends Record Key, Record Steps and the palette, and they end it.
- **While waiting,** the lens lane shows "Press a key on the keyboard to select it" with [Cancel]. It doesn't promise esc: with the keyboard as the Mac's only one, its Esc is a press to select. While secure input is on, when no press reaches Sextant, it shows "Paused: secure input is on · esc cancels" (then any esc cancels). VoiceOver hears the capsule's text when the mode starts, pauses and resumes, and "Stopped selecting a key by pressing it." when it ends before a press.
- **The next key-down on the keyboard** selects that key on the shown layer, as a click does, and VoiceOver hears "Selected key 24, Return, hold for Sym+Num" (on History, the shown revision's legend). ⇧⌘L typed on the keyboard is not that press: a key-down within 50 ms of the start, or while a key held at the start (its ⇧ and ⌘) is still down, is skipped. The same local monitor as Record Key swallows the Mac's own copy of the selected press until its key-up and 50 ms after, or a tapping term and 50 ms after for a key the tapping term times, since a tap dance sends its tap that late. The global layer shortcuts stand aside meanwhile, as during Record Key, so the press can't also move the keyboard's layer.
- **It ends** on esc from the Mac (after 50 ms: a keyboard press meanwhile was the keyboard's own Esc, and is selected), [Cancel], the window resigning key, the session dropping, the board hiding, or a pick starting. After a press it ends on that key's release, which the session's held keys also show when secure input drops the key-up, or on an esc that isn't the press's own copy (ADR 0052).

---

## 6. Layers, lighting, macros, combos, tap dance

### 6.1 Layers (MVP)

- **Where they are managed.** The sidebar's Layers section and the Layer menu. The canvas header has a jump menu.
- **Switching layers.**
  - ⌘1–⌘9 select layers 0–8.
  - ⇧⌘[ and ⇧⌘] select the previous and next layer.
  - Clicking a context-strip card switches to that layer.
- **New Layer (⇧⌘N)** appends a layer with the name "Layer 3", no colour, and all keys transparent. Inline rename starts at once.
- **Duplicate (⇧⌘D)** copies keys, LED colours and the colour, as "Sym+Num Copy".
- **Copy Layer To ▸ (v1)** lists the layout's other layers, then New Layer. A layer keeps its name and colour and takes the copied keys; New Layer adds "Sym+Num Copy" at the end. One undo step, which shows that layer. Within one layout only (ADR 0047).
- **Delete Layer….**
  - If layer keys or holds reference the layer, an alert lists them: "3 keys switch to Brd+Sys: key 51 on Main…".
  - Options: [Delete and Clear References] / [Cancel].
  - It is undoable.
- **Moving a layer** (drag, or ⌥⌘↑ / ⌥⌘↓) renumbers it, and every `MO`, `LT`, `TG`, `TO`, `TT`, `OSL` and `LM` reference follows the move.
- **Colour.** Chosen from the layout swatches, Custom, or None (base). The colour is also the layer's LED colour on the keyboard. The footnote says so.
- **Limits.** The UI is comfortable up to 8 layers. The sidebar scrolls, and ⌘ shortcuts cover the first nine.

### 6.2 Lighting lens (MVP; keyboard preview v1)

**Board rendering**
- **Own colour:** a full backlight. The face tint is the colour at 40%, with a 2 pt rim in the colour and a 10 pt glow (dark mode).
- **Inherited from the layer colour:** the same treatment at 35% strength. This is a judge fix, so that painted keys pop.
- **No colour** (no own colour, and the layer has none): the face is `#E6E6EA / #121214`, with "off".
- Legend ink is chosen by luminance.

**Lens-lane capsule**
- A segmented tool control: Paint (`paintbrush.pointed.fill`, B), Erase (`eraser`, E), Pick (`eyedropper`, I) and Fill Layer (`drop.fill`, G).
- After it: the brush swatch, its hex value, and "Painting Brd+Sys".

**Gestures**
- Click or drag across keys to paint. Hit-testing uses the key polygons. Each stroke is one undo group, e.g. "Paint 6 Keys".
- ⌥-click picks the colour from a key. Picking only reads keys; it does not sample the screen.
- Fill Layer sets the layer colour to the brush colour, as "Set Layer Colour".
- Hovering shows a dashed ring in the brush colour.

**Inspector**
- **Brush:** an HSB square (268×120), a hue strip, a hex field, and H, S and B readouts.
- **Swatches:** the layout's 10 swatch slots. Right-click › Set from Brush.
- **Layer colour:** chip and hex, with [Use Brush] and [None].
- **Painted on Brd+Sys:** grouped by colour. Each row has a swatch, the hex value, mini caps, a count and ⊗ (remove).
- [Clear Key Colours…].
- **On the keyboard (v1):**
  - "Preview while painting" toggle, plus a Brightness slider.
  - Footnote: "Shows these colours on the connected keyboard over raw HID. Nothing is written until you flash. Preview ends when you leave Lighting."
  - Release RGB takeover on lens exit, window close, quit and sleep.

### 6.3 Macros page (v1)

**Centre column**
- **Header:** the page title "Macros", the subtitle "A key types a sequence of up to 24 steps", and [New Macro].
- **Left: a 200 pt macro library list.** Each row shows the name, "8 steps · 210 ms", and the assigned key, or "not on a key yet".
  - An unnamed macro shows its key's label, else what it types in quotes ("“keymap⏎”"), else "Empty Macro".
  - Macros on keys and combos come first, in layer and key order, then the ones on no key yet (drafts, ADR 0042). A macro on several keys is a row per copy.
  - Row context menu: Assign to Key…, Remove from Key (it becomes a draft), Delete Macro. ⌫ deletes the selected macro. The list scrolls to the selected macro (New Macro, ⌘K, Assign to Key).
  - A key's label names its macro on the board, so it follows the macro: renaming a macro on a key's tap shows the new name on the cap, and a macro leaving a key's tap takes the label with it.
- **Right: the editor.**
  - Title (an editable name), plus "8/24 steps · ≈0.29 s · plays on tap of Brd+Sys key 17", [Assign to Key…], and a ⋯ menu with Remove from Key and Delete Macro.
  - **Timeline lane.**
    - Steps are drawn as keycaps.
    - Delays are proportional gaps: hatched, labelled "150 ms", and drawn over a time ruler in ms.
    - Modifier badges sit on the caps, e.g. "⇧⌘" on O.
  - Above the table: [Add Step] (the picker, offering only keys a step can type; a shifted symbol such as "{" becomes its key with ⇧), [Record Steps] and a "Keep pauses" checkbox.
  - **Step table:** #, Key, Mods, Wait, QMK. At 1120×640, Key holds every legend a step can type ("Web Home") and QMK holds two modifiers on a short key (`LCTL(LGUI(KC_1))`); a longer chord is cut in the middle, with the whole expression in its tooltip, and an imported step's long legend beside its warning ("Clear EEPROM") is cut at the end, with the key's name in its tooltip. Wider windows give both columns room. Steps can be reordered by dragging. ⌫ deletes the selected step; a double click opens its key in the picker. A step `SEND_STRING` can't type shows a warning.
  - **Options:** "End with ⏎ Return" and "Hold ⌥ while typing (Unicode)".
  - **Preview:** "Types: ⇧⌘O ⧗150 k e y m a p ⧗60 ⏎".
  - A footer warning, with `lock.fill`: "Macros are stored on the keyboard as plain keystrokes. Never put a password in one."

**Inspector (step).** Key tile (opens the picker as "Open Keymap › Step 3", offering only keys `SEND_STRING` can type), the modifier grid, "Then wait" (slider plus field, 0–5000 ms; the slider runs on a square-root scale so short waits get most of its track; a drag is one undo step), [Duplicate] and [Delete].

**Actions**
- **Record Steps.** Captures continuously through the same local monitor as Record Key. Each key, or a lone modifier, becomes the next step after the selected one. Esc stops, and so do leaving the page, choosing another macro, opening the palette or picker, the window resigning key, and reaching 24 steps. With "Keep pauses" (off by default) the time between two key presses becomes the first one's wait, rounded to 10 ms and capped at 5 s; a lone modifier counts from its press. Only the step recorded last takes a pause, so a step clicked meanwhile keeps its own wait.
- **Assign to Key…** switches to the board with the status capsule "Click a key to play ‘Open Keymap’ on tap · esc cancels". The click puts the macro on that key's tap and clears its other slots and its label. A draft moves there; a macro already on a key is copied. The page comes back when the pick ends; choosing another page meanwhile drops the pick. The capsule's [Cancel] also answers esc, so esc cancels even if the board missed it.
- **Show Key** on an issue in a key's macro (a step `SEND_STRING` can't type) opens the macro here, at that step.

### 6.4 Combos lens (v1)

**What a combo's layer means (ADR 0046).** QMK matches combos by keycode. A combo reads the keycodes at its keys on one layer ("Keys from"; none means the base layer), and fires whenever keys typing those keycodes go down together, on any layer. This is Oryx's meaning, so builds match Oryx's; Sextant says it in its own words and never calls it a per-layer restriction.

**Board**
- Combo keys are ringed in the combo's colour and numbered (from 10, the number is text in a filled circle: SF Symbols squeezes two digits past reading on a cap, and circles none past 50). A key in several combos takes the lowest number; VoiceOver hears every one: "in combo 2: J + K → Escape".
- A 2 pt trace joins the members (the shortest tree between their centres), drawn only in the gaps between caps. While several combos are drawn, a line that would pass under a cap outside its combo is left out: what showed of it would end at that cap and read as joining it. A combo drawn alone keeps every line. A combo that would then show neither a line nor its number on a key (F + J, both in lower combos) has its number beside the cap's own on each such key, so every combo on the board can be traced to its keys.
- An output pill (combo colour, its number and the output legend, black or white ink by luminance) sits in the nearest gap above the members. It must never overlap a legend, a number or another pill; if there is no gap, it moves further out, beside or above the board, up to six keys away, and is left out when nothing fits.
- Non-member keys are at 45%. A selected combo is drawn alone. With no combo to show, nothing dims.
- The board shows the shown layer: the base layer, the layer chosen in "Keys from", or a selected combo's layer. A click selects a combo the key is in, preferring one that reads the shown layer, and shows that combo's layer; ⌫ deletes the selected combo; esc goes back to every combo; painting and drag-to-swap are off. A selected combo counts as selected only while the board shows its layer. VoiceOver's hint on a cap is "Selects a combo with this key.", with no key-editing actions.

**Creating a combo**
- N, the context strip's "+ New Combo", the lens capsule or the inspector starts creation. The lens lane says "Click 2–6 keys, then Choose Output · esc cancels". A second click takes a key out; a seventh is refused.
- Choose Output (2–6 keys) opens the picker in assign scope, with the target "Combo 3 › Output". It accepts a keycode, a macro, or a layer action, but not Transparent or No Action. The choice makes the combo (one undo step, "New Combo") on the shown layer's keys; closing the picker keeps the keys chosen.
- Edit Keys… changes a combo's keys the same way; Done keeps them as one undo step.

**Inspector**
- The combo's number and title, and a Name field.
- Trigger keys as chips, removable down to 2.
- Output tile ("Sends"), which opens the picker.
- "Keys from": a layer picker, with the line "Sextant reads the keys at these spots on Main. The combo fires whenever keys typing the same keycodes go down together, on any layer."
- Combo window: "50 ms, every combo · Firmware Settings ›".
- Warnings:
  - "Keys J and K are rolling neighbors" (keys side by side on one row of one half): "Fast typing may set this combo off by accident."
  - Another combo listening for the same keycodes (from any layer: QMK matches keycodes), more than 6 keys, a transparent, disabled or tap-dance key, and two keys typing the same keycode (QMK finds both presses at one place, so the combo never fires).
- [Edit Keys…] and [Delete Combo].

**Combo colours** are Sextant's own categorical palette (§10.1).

### 6.5 Tap dance (slot UI MVP; firmware v1)

- **Tap dance is not a separate document.** A key becomes a tap dance when its Double tap or Tap then hold slot is filled.
- **Cap:** a `kind.tapDance` signal bar; the band follows §4.4.
- **Inspector:** the summary sentence covers all slots: "Tap types A. Double-tap types Esc. Tap then hold: Left Command."
- **The generator builds tap dances.** A slot whose action can't run inside a dance (a macro, a lighting key, a firmware key, TG, OSL and the like), or a tap that isn't a key, raises a live issue on that slot: "Action can't run in a tap dance", or on the tap "A tap dance's tap must be a key" (ADR 0041).

---

## 7. Build and flash

### 7.1 Entry points

- **Build & Flash** (⌘R) is the toolbar button and the Keyboard menu item. It is also in the menu bar extra (v1).
- **Build** (⌘B) compiles and measures without flashing. The capsule then reads "Built · 65,786 B". Clicking the capsule offers [Flash…].
- **Stop** (⌘.) works while building or waiting for flash mode. It is disabled during erase, write and verify, and quitting waits for them, so a quit never cuts off the write or the record of what was flashed.
- **Flash Oryx's Build of This Revision…** is available when the document's content hash equals an imported revision. It needs no toolchain. Oryx's build is md5-verified at download.

### 7.2 Sheet anatomy

**Size.** 640 pt wide, sized to content up to 640 pt high: default sheet sizing with `.frame(maxHeight: 640)`. The header and footer stay put and the body scrolls past the cap. Not `.presentationSizing(.fitted)`, which freezes the sheet at its first height.

**Header**
- An accent tile with `bolt.fill`.
- Title, which depends on the step.
- Subtitle: "My MacOS Layout → ZSA Voyager KlgM7/40xJ7M".
- "Step 2 of 5" on the trailing edge.

**Step indicator.** Five nodes: Build · Flash mode · Write · Verify · Done. Each has a sublabel, for example "65.8 KB", "Waiting", "64%" or "Found".

**Body.** Depends on the step (§7.3).

**Footer**
- Leading: `lock.shield`, with "Sextant only writes to the Voyager's bootloader (3297:0791) and verifies every byte."
- Trailing: [Hide] [Cancel/Stop], plus a contextual primary button: Done, Try Again or Fix & Rebuild.

### 7.3 States, body and copy

| State | Title | Body | Buttons |
|---|---|---|---|
| Set up build tools (first build only) | "Set up the build tools" | Explains the backend: an Apple container image or a managed toolchain, about 1 GB, stored in Application Support. Shows a download progress bar. When Oryx's binary applies, offers [Use Oryx's build instead] | [Cancel] [Download and Build] |
| Building | "Building firmware" | Rows: Generate source ✓, Compile (12 of 41), Link. A "Show Log" disclosure tails 6 mono lines; its lines link to keys. A size meter appears after Link | [Hide] [Stop] |
| Too large | "Firmware is 3,214 bytes too large" | The size meter turns red. Shows the biggest contributors (e.g. "RGB animations · 18.5 KB") and suggestions such as "Turn off unused animations (Firmware Settings › RGB)" | [Open Firmware Settings] [Close] |
| Flash mode | "Put the keyboard in flash mode" | Card A and card B (below). Status line: spinner, "Waiting for the keyboard to enter flash mode…". Info: "The keyboard's lights go dark and it disconnects while in flash mode. That's expected. Sextant starts writing as soon as it sees the bootloader." | [Hide] [Cancel] |
| Still waiting (after 45 s) | (same) | Adds, above the cards so it shows without scrolling: "Still waiting? Connect the cable straight to this Mac rather than through a hub, then press the reset button once more." | (same) |
| Writing | "Flashing" | The sextant ring (below), with the phase percentage. A 3-segment bar: Erase / Write / Verify. Facts: Target STM32 · 0x08002000 / 33 pages erased / ≈24 KB/s / ≈1 s left. An orange callout: "Keep the keyboard connected until this finishes." | [Hide], [Cancel] (disabled, with the tooltip "Can't stop while writing. If the cable comes out, the keyboard stays in flash mode and you can simply flash again.") |
| Verifying | "Verifying" | The same ring. "Reading back and comparing every byte." | Same as Writing |
| Done | "Flashed" | `checkmark.seal.fill` (bounces once). "Your Voyager is running My MacOS Layout, revision q7Lm2E." "It reconnected and reported KlgM7/q7Lm2E ✓." "Saved as a revision in History." | [Done] (default) |
| Build failed | "Build failed: 1 error" | The issue list, each with message, location and key. Each row has [Show Key] (it closes the sheet and selects the key) and [Fix] | [Close] [Fix & Rebuild] |
| Flash failed | "Flashing didn't finish" | "Nothing is broken: the bootloader can't be overwritten, so you can always try again. Put the keyboard in flash mode again to retry." [Show Details] (DFU status, step, address) | [Close] [Try Again] |

Both cards show the same small top-down drawing of the board, drawn by Sextant from the board's own key shapes: blank keys on a case that follows them, thumb clusters joined to their halves, no product art. The cards are equally tall. Steps never name keys by index; key numbers meant nothing to the user (2026-10-11).

**Flash mode, card A: the reset button**
- Title: "Use the reset button".
- The drawing marks the reset button on the case's top edge above the key the board definition names (`resetButtonKey`: the Voyager's key 3, "near the '3' key in the default layout", zsa.io/go): an accent pill in a ring, with a halo that pulses outward (held still under Reduce Motion). That key shows its Main legend. (A symbol alone, and before it an abstract drawing of the half's top edge, confused the user, 2026-10-11; Oryx's site points at the button on a top-down picture.)
- Copy: "Press the reset button on the top edge of the left half, above the 3 key." The key is named by what it shows on Main (a layer key by its layer, "above the Nav key"), the same name the drawing prints on it; with nothing there, "above the top-row key in column 4". (The Voyager has a button, not a pinhole; the user confirmed on hardware, 2026-10-11.)
- VoiceOver: the drawing reads "Keyboard drawing with the reset button marked on the top edge of the left half, above the 3 key".

**Flash mode, card B: the Reset key (Console graft)**
- Title: "Or use your Reset key".
- The drawing fills the keys to press in the accent colour, each with its step number: one per hold, then the Reset key.
- Steps name each key by what it shows on Main, with its place below (`KeyText.position`): 1 "Hold Space" / "Right thumb, outer key"; 2 "Press the key that shows “-” on Main" / "Right hand, top row, far right". A key acting on Main is named by its own legend ("Hold Space", "Hold Nav"); any other key by what it shows there, letters, modifiers, media and layer keys alike ("the key that shows “Nav” on Main"); a key with nothing on Main is "the key". Places name the home row by row (the outer pinky keys too) and tell the two thumb keys apart ("inner key" nearer the middle, "outer key").
- VoiceOver: the drawing reads "Keyboard drawing with the keys to press numbered. 1: Right thumb, outer key; 2: Right hand, top row, far right".
- The path is computed: find the `QK_BOOT` key, then the chain of `MO` or `LT` holds from layer 0 that reaches its layer.
- If there is no reachable `QK_BOOT`, card B is replaced by the tip "Add a Reset key (QK_BOOT) to a layer to enter flash mode from the keyboard."

**Sextant ring (signature)**
- 168 pt across, with a graduated bezel: a tick every 3.6°, and a major tick every 36°.
- The progress arc is in the accent colour.
- The centre shows the **phase percentage**, set in `.system(size: 40, weight: .semibold).monospacedDigit()`, with the phase name below it.
- Show one number, labelled honestly: the current phase's percentage. The 3-segment bar shows overall position. Never show a percentage while waiting for the bootloader.

**Size meter**
- A single-hue stacked bar in accent shades, against the board's flash capacity. The capacity comes from the board definition's flash target; do not hard-code it.
- Breakdown: QMK core and USB, RGB matrix and animations, ChibiOS, Oryx live connection, Navigator, keymap and layer colours. Then the free bytes.

### 7.4 Safety in the UI (non-negotiable)

These follow research §4, "Safety rules for the flasher".

- **Auto-advance.** Writing starts only when a Voyager bootloader (VID `0x3297`, PID `0x0791` or `0x1791`) appears, and only after the image passes validation: a DFU suffix with matching CRC, VID and PID, an address range of `[0x08002000, 0x08042000)`, and a vector-table sanity check. There is no "Flash Now" button.
- **Validation failure** stops with: "Sextant won't flash this image" plus the reason, in technical detail. There is no override.
- **More than one bootloader** stops with: "Connect only one keyboard in flash mode."
- **Different layout.** If the connected keyboard runs a different layout, confirm before the build starts:
  - "Replace the layout on this keyboard?"
  - "This keyboard runs ‘Writing (Colemak)’ (Q9x2/aa11). Flashing replaces it with ‘My MacOS Layout’. You can flash the old one back from History."
  - Buttons: [Cancel] [Replace and Flash]. A "Don't ask again for this keyboard" checkbox.
- **Cancelling while waiting in flash mode:** "Your keyboard is waiting in flash mode. Unplug it and plug it back in to return to the layout it had."
- **No disruptive moves.** The sheet never moves focus to another app and never takes over the screen.

### 7.5 Error mapping and live issues

**Source map.** The generator emits a source map from `keymap.c` line to (layer, key, slot, field). Compiler diagnostics (`file:line:col: error: …`) are parsed and mapped through it.

**A mapped error appears in six places:**
1. the capsule: "Build Failed · 1 error · key 45";
2. the lens lane status capsule, with [Show Key];
3. the cap: red ring and "!" badge;
4. the sidebar: a red badge on the layer row;
5. the build-log line, which is a link: "→ Brd+Sys key 45";
6. the inspector issue callout, at the top. The callout contains:
   - Title: "Unknown keycode on Brd+Sys".
   - Body: "The Prev Tab key uses KC_LBRACKETT, which the firmware doesn't know."
   - Location: "keymap.c:31 · Tap slot".
   - A code excerpt in mono, with a red caret under the bad token.
   - Suggestion: "Did you mean KC_LBRC ([)?" [Fix]. Fix applies it as an undoable "Fix Keycode".
   - [Fix & Rebuild].

**Unmapped errors** appear only in the log, with [Copy Log].

**Live issues** are checked on every edit, before any build:
- unknown keycodes;
- references to missing layers;
- unreachable layers (a warning);
- macros over 24 steps;
- a macro step `SEND_STRING` can't type (v1);
- empty combos;
- combos over 6 keys (fewer than 2 is an empty combo), duplicate trigger keys, and transparent or tap-dance combo keys (v1);
- rolling-neighbor combo keys (a warning, v1);
- a tap dance slot whose action can't run in a dance (v1);
- a per-key tapping term while per-key terms are off (a warning, v1);
- an estimated size near the limit (a warning).

A combo's issue names the combo ("Empty combo · Combo 3").

They use the same badges, with orange for warnings. ⌘' and ⇧⌘' move to the next and previous issue.

### 7.6 Hide and background flashing

- [Hide] dismisses the sheet. Building, waiting and writing continue, and the toolbar capsule shows progress.
- Clicking the capsule's status segment re-presents the sheet.
- When a hidden flash finishes:
  - the capsule shows "Flashed" (or the failure);
  - with "Notify when a flash finishes" turned on (an opt-in Settings toggle; asks for notification permission when turned on), a user notification is posted.
- The sheet never re-presents itself.
- **Other windows** show "Flashing from ‘My MacOS Layout’" in their capsule, and their Build & Flash button is disabled.

---

## 8. Other surfaces

### 8.1 Import from Oryx (MVP)

**Entry points.** File ▸ Import from Oryx… (⇧⌘I). Pasting a `configure.zsa.io` URL into ⌘K or onto a focused board. The Welcome state. The device card's [Import].

**Sheet layout**
- Header with `square.and.arrow.down`, and the segmented control **Link · Connected Keyboard**.
- **Link.** A URL field that validates live. Parsed tokens appear as chips: Board Voyager, Layout KlgM7, Revision 40xJ7M, Layer 0. "Matches the connected keyboard" appears in green when the serial agrees.
- **Connected Keyboard.** "Your Voyager reports KlgM7/40xJ7M". The layout is fetched read-only from Oryx.
- **Progress checklist:** Read link → Fetch layout → Check firmware (md5) → Convert.
- **Notes,** for example:
  - "4 custom labels are shown in Sextant only."
  - "Navigator trackpad found on the right half; its settings come along."
  - "Oryx stays read-only. Sextant keeps its own copy."
- **Preview:** a board with layer tabs, plus summary statistics: 3 layers, 130 keys, 6 dual-function, 4 labels, 3 colour keys, 0 macros.
- **Footer.**
  - [Cancel].
  - Primary: [Import as New Layout].
  - If the library already has a layout with this Oryx hashId: [Add as Revision of ‘My MacOS Layout’]. It is undoable and appears in History.
  - Checkbox: "Open after importing".

**Errors**

| Case | Copy |
|---|---|
| Offline | "Sextant couldn't reach Oryx. Check your connection and try again." [Try Again] |
| Not found or private | "This layout is private or doesn't exist. Sextant can only import public layouts." |
| Other board | "This is a Moonlander layout. Sextant supports the ZSA Voyager for now." |
| Unknown codes | "2 keys use codes Sextant doesn't know yet. They're kept as they are and marked." (the import continues) |
| md5 mismatch | "Oryx's firmware didn't match its checksum, so Sextant didn't keep it. The layout imported fine." |

**Future:** "Restore from Backup…" sits next to Import in the File menu.

### 8.2 Device, live and Follow (MVP)

**Device popover** (360 pt; from the capsule's device segment or the sidebar card)
- **Header:** `keyboard`, "ZSA Voyager", "Connected over USB".
- **Identity:**
  - Layout `KlgM7`, Revision `40xJ7M`, with ✓ "matches this layout" or ⚠ "different layout";
  - Firmware 25.0, protocol 5, USB 3297:1977;
  - Navigator: Trackpad, right half.
- **Live:**
  - Active layer chip: "Brd+Sys · layer 2 · held by Space".
  - Status LEDs: 4 dots, with "= 2 in binary".
  - Keys down, as positions (mini caps of non-character keys; character keys appear as "•").
  - An "Event monitor" disclosure listing time, down or up, `k40`, and `R8 C2`. It shows **positions only, never letters**. In v1 this is the "Raw-HID log" disclosure, shown while Settings › Advanced turns the log on; like the rest of the live view, it keeps nothing during secure input (ADR 0045).
- **Controls:**
  - Follow the keyboard's layer (⌘L);
  - Show key presses on the board;
  - Show overlay while a layer is held (v1);
  - Move keyboard to layer ▸ (v1).
- **Footer note:** "Key events stay in memory on this Mac and are never written to disk. Live display pauses while you type in a password field."

**Live behaviour**
- **Pressed keys** light in every lens (§4.7). The default is on (Settings › Keyboard).
- **Secure input.** While `IsSecureEventInputEnabled()` is true (polled at 1 Hz, and checked at every event for the press feed), presses are not shown, and the Device popover says "Paused: secure input is on".
- **Follow** is a Maps-style tracking mode:
  - It turns on automatically when a keyboard connects, unless Settings › Keyboard › "Follow the keyboard by default" is off. This is the brief's "live" principle.
  - When it is on, the displayed layer is the physical layer.
  - Choosing a layer by hand (sidebar, ⌘1–9, the jump menu) turns Follow off, and the toolbar toggle shows off.
  - ⌘L resumes it.
- **Coexistence.** If Keymapp holds the device: "In use by Keymapp. Quit Keymapp or disconnect it there; Sextant connects automatically."
- **HID protocol details** follow research §5. Release RGB takeover on quit and sleep. Never seize the device.

### 8.3 Menu bar extra (v1)

**Label**
- A template image of the sextant mark, followed by the active layer index in SF Pro Rounded 11 bold, e.g. "◠ 2".
- Disconnected: the glyph at 50%, with no number.
- Flashing: the arc fills with progress.
- Optional, off by default: a small layer-colour dot.

**Panel** (360 pt, `.window` style)
1. **Header:** sextant mark, "ZSA Voyager", "Connected · KlgM7/40xJ7M", the status-LED pips, and a gear button that opens Settings.
2. **"Layer on the keyboard"** (held by Space).
   - With 4 or fewer layers: one tile per layer, each with its index (L0), name and colour chip. The active tile is lit in its layer colour.
   - With more layers: list rows with ⌃⌥ hints.
   - Clicking moves the keyboard to that layer. Caption: "Switching here moves the keyboard to that layer."
3. **Mini map** of the active layer, with pressed keys lit (paused during secure input).
4. **App-aware layers:** "Xcode → Sym+Num", with a switch.
5. **"Show overlay while holding a layer"** switch.
6. **Native menu-style rows:** Build & Flash… (⌘R; shows progress while flashing), Open Sextant (⌘0), Settings… (⌘,), Quit Sextant (⌘Q).

Typing statistics (WPM, today's count) appear only when heatmap recording is on, and then only as one line under the mini map.

### 8.4 Overlay HUD (v1)

**Panel.** An `NSPanel` configured as follows:
- style mask `[.nonactivatingPanel, .borderless]`, `level = .statusBar`;
- `ignoresMouseEvents = true`, `hidesOnDeactivate = false`, `isOpaque = false`, `backgroundColor = .clear`;
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`;
- it never becomes key.

**Geometry**
- Width: the smaller of 720 and 46% of the screen width. Sizes S, M (the default) and L are set in Settings.
- Corner radius 24, padding 20.
- Position: bottom centre, 72 pt above the bottom of the visible frame, on the screen that holds the pointer. Settings › Keyboard can move it to top centre, 72 pt below the top of the visible frame, which keeps it clear of the menu bar and the notch.

**Content**
- Header row: a layer index tile in the layer colour, the layer name, "held with ⏎", the status-LED dots, and a trailing hint ("release to hide").
- The layer's map, with pressed keys lit.

**Material**
- `.glassEffect(.regular)`, or via `NSGlassEffectView`.
- Option: tint with the layer colour at 20% (off by default).
- Under Reduce Transparency, an opaque dark panel.

**Timing**
- A momentary layer shows the HUD after a 150 ms hold delay (configurable from 0 to 500 ms). It fades in over 0.12 s and out over 0.18 s after release.
- A toggled layer (`TG` or `TO`) shows a compact reminder pill instead: "Sym+Num locked", 32 pt tall, in the same position, until the keyboard returns to the base layer. Settings offers: full overlay, reminder (the default), or nothing.

The HUD is hidden during secure input, in full-screen video (when the screen is captured), and while Sextant's own window is key and showing the same layer.

### 8.5 Heatmap lens (v1)

- **Data.**
  - Press counts per position, per layer, in hourly buckets. Stored locally.
  - **Off until the user opts in** (Settings › Privacy).
  - Retention defaults to 30 days.
- **Board.**
  - Cap faces use the single-hue ramp (§10.1), normalised on a log scale over the range.
  - Counts in mono are shown under the legends: "22k".
  - Legend ink is chosen by luminance.
- **Lens lane:** "175,044 presses · 7 days · Main 87%".
- **Inspector:**
  - a range picker: 24 h / 7 days / 30 days / All;
  - total presses;
  - a layer share bar;
  - hand balance;
  - a per-finger histogram;
  - the busiest keys (top 8);
  - layer holds;
  - [Export CSV…] and [Export JSON…];
  - [Clear Heatmap Data…];
  - the note "Counted on this Mac only. Nothing is uploaded."

### 8.6 App-aware layers page (v1)

- **Header.** Title, and a master toggle "Switch layers when you change apps".
- **Now card:** "Xcode is frontmost → keyboard on Sym+Num", with a mini board of that layer.
- **Rules table.** Columns: app icon and name, bundle id (secondary), layer chip pop-up, "When leaving" (Return to Main / Stay), and Enabled. [Add App…] offers running apps plus Choose….
- **Inspector:** rule details, and recent switches (app names only).
- **Mechanism:** `NSWorkspace.didActivateApplicationNotification` drives a raw HID `layer_move`. Footnote: "Moves the keyboard to the layer, like Go to (TO). Holding a layer key still works on top."

### 8.7 History and diff (v1)

**Revisions** are created by an import, every flash, and ⌘S Save Revision… (a sheet with a message field, prefilled "Edited 5 keys on Brd+Sys"). ⌘S is on when the layout differs from its last revision. The suggestion names keys first ("Edited 12 keys on 3 layers"), otherwise the first other change ("Changed 2 settings", "Renamed the layout"); a blank message stores none (ADR 0043).

**Changes lens**
- The board shows the selected revision's layout against what it is compared with. The default comparison is its parent; alternatives are Current, On keyboard, or Another Revision ▸ (a submenu of the other revisions). Choosing the revision being compared with goes back to its parent.
- Badges follow §4.7. Unchanged keys are quiet. Badges always describe the board's keys, the selected revision's, against the comparison. Against Current or a later revision they read backward: "added" marks a key the comparison lacks, which Restore would bring back (ADR 0043).
- What counts as a change: keys and layers (layers match by id; every own key of a new layer is added), the layer order, settings (Navigator options included), combos (compared by content, since Oryx numbers their ids by position), the Navigator's kind, side and automouse layer, and the layout's title.
- The board keeps the layout's geometry and Navigator side, so no key moves, and it is read-only: no painting, swapping, ⌫, edit actions or issue rings. The revision's layer is the selected one, matched by id. A layer only the revision has can be chosen from the strip or the header's layer menu; it stays until another layer is chosen. The footer's kind key lists the kinds on the layer shown.
- The lens capsule counts each badge ("Revision 2 · 1 added · 3 changed · 1 removed"), plus "N other changes" for settings, combos, layers, the Navigator and the title.
- The context strip shows per-layer change counts. Layers the comparison has and the revision lacks follow, dashed, as "Removed".

**Inspector**
- **Timeline:** a vertical list. Each row has a node, the id in mono, badges (ORYX, LOCAL, ON KEYBOARD), the message, the date and the number of changes. Past four revisions it scrolls on its own, keeping the selected one in view, so the details below stay on screen. VoiceOver reads a row as "Revision 2, Edited 5 keys on Brd+Sys", with the date and count as its value.
  - ON KEYBOARD marks the revision the keyboard runs: the import revision for Oryx's own build, or the newest matching flash revision for a Sextant build. Edits made since the flash are never on the keyboard (ADR 0039). The "On keyboard" comparison uses the same revision.
- **Selected revision:** details (source, date, message), a per-layer change bar, the other changes (layers, settings, combos, the Navigator), and a changes table (key, before cap → after cap, slots changed). A row shows its layer and selects the key. The author isn't modeled. A revision Sextant flashed shows its firmware's size and the change since the newest earlier revision with a kept image: "Firmware 66 kB · +292 B since revision 4". Every flash keeps its image for this; a save never has one, and an import's image is Oryx's build, so it never counts. Without an image the line is hidden (ADR 0043).
- **Actions:**
  - [Restore This Revision]: checkpoints unsaved edits, records the restore as a new revision ("Restored revision 3") and makes it the layout as one undo step, keeping the title; nothing is lost. It is off when the layout already equals the revision, and while a restore runs.
  - [Flash This Revision…]: builds the revision as it was recorded and flashes it through the Build & Flash sheet ("My MacOS Layout, revision 2 → ZSA Voyager"), with every flasher check unchanged. The flash is recorded as a new revision, "Flashed revision 2"; the working copy stays as it is. A revision's build errors point at no key, since the board shows the working copy.
  - [Export Source Zip…]: the QMK source a build of the revision compiles, zipped, through File ▸ Export's panel ("<title> Revision 2 QMK Source").
  - If the revision has issues that block a build (§7.5), the sheet says "Revision 2 has 1 issue": a revision can't be changed, so its rows offer no Show Key, and [Restore This Revision] makes it the layout to fix them in.
  - Restore and Flash This Revision are off while a flash is writing, from this window or another.
  - Keyboard ▸ Flash This Revision… is History's selected revision. Keyboard ▸ Flash Oryx's Build of This Revision… (§7.1, not in v1) means the import the working copy equals, which can be another revision; the slice that enables it should give the two distinct titles.
  - Every action is also in the menus (File ▸ Restore This Revision, File ▸ Export ▸ This Revision’s QMK Source (.zip)…, View ▸ Compare Revision With ▸, Keyboard ▸ Flash This Revision…) and the palette (Restore This Revision, Flash This Revision…, Export Source Zip…, "Compare with: …"), on the History page only.
- **Empty state:** §12.4. The context strip reads "No revisions yet" and Compare with is off.

**Future**
- The source device is shown on each revision.
- A sync conflict appears as two sibling revisions, with a per-key merge: "Use left / Use right" on each changed key.

### 8.8 Firmware Settings page (every setting Sextant offers, v1)

**Centre column**
- **Header:** `slider.horizontal.3` tile, "Firmware Settings", "Built into the firmware · 9 changed from defaults" ("9 changed from defaults" in a narrow window), a search field (⌘F, Edit ▸ Find Setting…; Esc clears it), and a "Modified only" checkbox. While a filter is on, the second line says what it shows: "11 settings match ‘hold’", "3 changed settings". No match shows the system's search empty state; Modified only with nothing changed says so, with Show All Settings.
- **Form:** `Form { Section … }.formStyle(.grouped)`, with the sections that have a setting Sextant offers, in catalog order: 12 sections and 60 settings for the Voyager (ADR 0040).
- **Each row:**
  - the title (semibold when modified, with a leading accent dot);
  - a control: `Toggle`, a `Slider` with a value field and unit, a layer menu, or the animation list;
  - a plain-English description in Sextant's own words (ZSA's text must not be shipped);
  - a coupling note where one applies (a `link` symbol and a line);
  - a footer: "Default 200 ms · Reset to Default" when modified, and the setting id in mono on the trailing edge.
- **Animations** (RGB Lighting): "46 of 48 included", and under a disclosure a checkbox per animation in Sextant's names, with Include All and Include None. Each change is one undo step.
- **Navigator section** (always shown, ADR 0035): it starts with "Navigator" (None · Trackpad · Trackball, segmented) and "Side" (Left · Right, disabled with None), then the attached kind's settings. Footer: "Choose the module attached to your keyboard. The change takes effect after you build and flash." A new kind starts from its defaults; moving keeps the options. The knob isn't offered. The one-shot auto-mouse idle timeout is a trackpad option.
- **Section footers:** Mouse Keys says the keyboard's own mouse key speeds apply at the defaults; International says only the input sources Sextant has keycodes for are listed.
- **Coupling rules** (ADR 0040), each one undo step with the change that causes it and said inline: a tapping term over 500 ms turns on Permissive hold; Chordal hold on or off does the same to Exclude thumbs; Auto Shift turned on with punctuation, numbers and letters all off turns them on, and turning all three off turns it off. The Auto Shift options and Exclude thumbs wait while the setting they follow is off: the control is disabled, the title dimmed, and the footer says "Used while Auto Shift is on"; Reset to Default still works.
- **Hidden** (kept when imported, never written; ADR 0040, 0041): "Prefer tap in tap-and-hold dances" (`dancesTapAction`), the live connection (always on), Steno keycodes and GeminiPR, and the locales Sextant has no keycodes for (only English (UK) and US International show). Audio and Navigator support don't apply to the Voyager. The two locale toggles gate the picker's `UK_` and `US_` codes (its categories, search and recents); a search that matches gated codes ends with "English (UK) keycodes are off · N more matches", which goes to the toggle.
- **Search** matches titles, descriptions, ids and synonyms (Sextant's words: "chatter" finds Debounce time); every word must match. The count includes the Navigator's module choice when the query names it. A section the inspector points at, or a setting the palette points at, clears a filter that hides it.
- **What a layout shows** (`KeyboardLayout.offers`): an offered setting for the attached Navigator, whose dependency is on. Modified only, the header's count, the badge and the Changed list all count only those, so every changed value has a row.

**Inspector**
- Sections, with modified counts; clicking one scrolls the Form.
- **Changed (9):** each row shows the name, the struck-through default and the new value.
- [Reset All to Defaults…] (confirmation); one undo step, "Reset Firmware Settings". Hidden imported values stay.
- The footnote "Settings take effect after you build and flash. Values equal to the default aren't stored."
- **Kept, Not Used (N)**, when a stored value the page doesn't show differs from its default (a hidden setting, another Navigator's option, or one waiting on a setting that's off): each name and value, and "Hidden, for another Navigator, or waiting on a setting that's off. Kept in the layout; builds don't use them."

### 8.9 App Settings (Settings scene)

| Pane | Contents | Phase |
|---|---|---|
| General | Open at login. Show in menu bar. When the keyboard connects: Open Sextant / Do nothing. Show grid behind the keyboard. Notify when a flash finishes (opt-in) | MVP (menu bar options v1) |
| Keyboard | Show key presses on the board (on). Follow the keyboard by default (on). Overlay: on/off (on), delay (0–500 ms in 10 ms steps, 150), position (bottom or top center), size (S/M/L, M), tint with layer color (off), toggled-layer behavior (full overlay, reminder or nothing; reminder). Layer shortcuts: global shortcuts to move the keyboard to a layer (⌃⌥0–9, off by default; a recorder per layer while on) | v1 |
| Build | Build tools: Apple container (recommended) or managed toolchain, with status, disk use, [Update] and [Remove]. Firmware source pinned to ZSA fork commit `93b2b9e` and modules `13890cd`. "Use Oryx's build when the layout is unchanged since import" | MVP |
| Privacy | Heatmap recording (off by default), retention, [Clear Heatmap Data…]. Explanatory text about raw HID and secure input | MVP |
| Advanced | Developer raw-HID log (positions only): the last 500 reports, in memory only, off at each launch, cleared when turned off, paused during secure input, shown in the Device popover (ADR 0045). Reset all warnings | v1 |
| Sync | Server URL, device pairing, end-to-end encryption (hidden until built) | Future |

### 8.10 Room left for Future sync

- A trailing slot in the activity capsule holds the sync glyph: `arrow.triangle.2.circlepath` while syncing, `externaldrive.connected.to.line.below` when connected to the server. Do not use iCloud symbols for a self-hosted server.
- The menu bar extra header has a sync line.
- Settings gets a Sync pane.
- History shows the source device per revision.
- File ▸ Restore from Backup….

---

## 9. Keyboard shortcuts and menus

### 9.1 Menus

**Sextant:** About Sextant · Settings… ⌘, · Services · Hide ⌘H · Hide Others ⌥⌘H · Quit ⌘Q

**File**

| Item | Shortcut | Phase |
|---|---|---|
| New Layout | ⌘N | MVP |
| Import from Oryx… | ⇧⌘I | MVP |
| Import from Connected Keyboard | — | MVP |
| Restore from Backup… | — | Future |
| Close Window | ⌘W | MVP |
| Save Revision… | ⌘S | MVP |
| Restore This Revision (History) | — | v1 |
| Duplicate Layout | — | MVP |
| Rename Layout… | — | MVP |
| Export ▸ Layout JSON…, QMK Source (.zip)…, Firmware (.bin)…, This Revision’s QMK Source (.zip)… (History), Image (PNG)…, All Layers (PDF)… (one save panel; Firmware is the last build while the layout is unchanged; the PNG is the shown layer, the PDF a page per layer without cap shadows; no SVG, ADR 0044) | — | MVP (image v1) |
| Show in Finder | — | MVP |
| Print Layout… (every layer, a page each, through the system print sheet) | ⌘P | v1 |

**Edit**

| Item | Shortcut | Notes |
|---|---|---|
| Undo *Action* / Redo *Action* | ⌘Z / ⇧⌘Z | System group, not replaced. Text fields keep their own undo |
| Cut / Copy / Paste | ⌘X ⌘C ⌘V | With board focus these act on keys (v1). Otherwise standard |
| Delete | ⌫ | The standard item. Deletes the selected combo on the Combos page and the selected macro on the Macros page (a focused step there); otherwise standard, as in a text field. While it is enabled it takes ⌫ before the focused view (v1) |
| New Combo · Edit Combo Keys… | — | Combos page only, with a combo selected for Edit Combo Keys… (N also starts one with board focus) (v1) |
| New Macro · Record Steps · Assign to Key… | — | Macros page only, with a macro selected for the last two (v1). These page items and Delete are ⌘K commands too |
| Make Transparent | ⌘⌫ | Also ⌫ with board focus |
| Find Key… | ⌘F | Palette, keys scope. On the Firmware Settings page it reads Find Setting…, closes the palette and focuses its search |
| Command Palette | ⌘K (alias ⇧⌘O) | |

**View**

| Item | Shortcut |
|---|---|
| Show/Hide Sidebar | ⌃⌘S (`SidebarCommands`) |
| Show/Hide Inspector | system shortcut (`InspectorCommands`) |
| Lens ▸ Keys / Lighting / Heatmap | ⌃⌘1 / ⌃⌘2 / ⌃⌘3 |
| Compare Revision With ▸ Previous revision / Current / On keyboard / Another Revision ▸ (History) | — |
| Legends ▸ Symbols / QMK Codes / Key Numbers | — / ⌥⌘C / ⌥⌘N |
| Show Grid Behind Keyboard | — |
| Enter Full Screen | ⌃⌘F (system) |

**Layer**

| Item | Shortcut |
|---|---|
| New Layer | ⇧⌘N |
| Duplicate Layer | ⇧⌘D |
| Rename Layer… | — (or the sidebar row's context menu) |
| Layer Colour ▸ | — |
| Move Layer Up / Down | ⌥⌘↑ / ⌥⌘↓ |
| Copy Layer To ▸ (v1) · Clear Layer… · Delete Layer… | — |
| Show Previous / Next Layer | ⇧⌘[ / ⇧⌘] |
| Show Layer 0 … 8 | ⌘1 … ⌘9 |

**Key**

| Item | Shortcut |
|---|---|
| Change Keycode… | ⏎ (board focus) |
| Record Key | ⇧⌘R |
| Edit Slot ▸ Tap / Hold / Double Tap / Tap Then Hold | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 / ⌥⌘4 |
| Make Transparent | ⌘⌫ |
| Disable Key | ⇧⌘⌫ |
| Override on This Layer | — |
| LED Colour ▸ | — |
| Select Key by Pressing It (on the Voyager) | ⇧⌘L (v1) |
| Copy QMK Expression | ⌥⇧⌘C |

**Keyboard** (device and firmware)

| Item | Shortcut |
|---|---|
| Build | ⌘B |
| Build & Flash | ⌘R |
| Stop | ⌘. |
| Show Build Log | ⇧⌘B |
| Flash This Revision… (History) | — |
| Next Issue / Previous Issue | ⌘' / ⇧⌘' |
| Follow Keyboard | ⌘L |
| Move Keyboard to Layer ▸ (the keyboard layout's layers; disabled with the reason until Live View is on; also in the Device popover) | ⌃⌥0–9 (global, opt-in, v1) |
| Preview Lighting on Keyboard | — (v1) |
| Show Overlay While Holding a Layer | — (v1) |
| Device Info… | — (opens the Device popover) |
| Flash Oryx's Build of This Revision… | — |

**Window:** standard items, plus Main Window ⌘0.

**Help:** Sextant Help · Keyboard Shortcuts ⌘/ · Flashing Help · Privacy.

### 9.2 Keys while the board has focus

The board is one tab stop. These keys are handled with `.onKeyPress` and `.onMoveCommand` on the focused board view, never by a window-wide monitor.

| Key | Action |
|---|---|
| ← ↑ → ↓ | Move the selection to the geometric neighbour. Crosses the halves and reaches the thumbs (`BoardGeometry.neighbor`) |
| ⏎ | Open the picker for the current slot. During a board pick (§6.3, §6.4), pick the selected key; typing and ⌫ then do nothing |
| ⇥ / ⇧⇥ | Next / previous slot |
| ⌫ | Make Transparent; on the Combos page, delete the selected combo (§6.4) |
| Space | Show the inherited key (peek) while held, on a transparent key (v1) |
| Any printable character | Open the picker pre-filled (§5.5) |
| B / E / I / G | Lighting lens tools |
| N | On the Combos page: new combo (§6.4) |
| esc | The Esc ladder (§9.3) |

### 9.3 Esc ladder

Each press of esc steps back one level:
1. Recording, or Select Key by Pressing It → cancel (§5.8.1).
2. Picker or palette → close, wherever focus is in the window.
3. Popover → close.
4. An in-progress gesture (combo creation, paint stroke, Assign to Key) → cancel. A board pick also takes esc through its capsule's [Cancel], the window's cancel shortcut (ADR 0042).
5. Several selected keys → keep only the anchor (ADR 0047).
6. Key selection → deselect. On the Combos page a selected combo goes first, back to every combo (§6.4).

Esc never switches lens or destination.

### 9.4 Global shortcuts (opt-in, v1)

⌃⌥0–⌃⌥9 move the keyboard to a layer. They are registered with Carbon `RegisterEventHotKey` through sindresorhus/KeyboardShortcuts, which needs no TCC. They are off by default and can be remapped in Settings › Keyboard with the library's recorder; a shortcut needs ⌃ or ⌘, since with only ⌥ or ⇧ it would take a key the user types with (⌥2 types ™). They pause while Record Key or Record Steps listens, so those can record ⌃⌥ digits. They move the keyboard only while Live View is on; a press that can't beeps, and Settings › Keyboard says why, under the switch, until the cause is gone. Shortcuts another app or macOS already uses are listed there. The Keyboard menu's Move Keyboard to Layer items show them only while they're on and can fire, so one press never runs both (ADR 0048).

### 9.5 Conflicts avoided

- ⌘T is left free for the tab convention.
- ⌘E keeps its "Use Selection for Find" meaning, so it is not used for editing.
- ⌘0 and ⌥⌘0 are not used for the sidebar or inspector.
- ⌃1–⌃4 are left to Mission Control.
- Bare letters work only when the board has focus.
- ⌘R and ⌘B follow Xcode's "Run" and "Build". The user is an Xcode user. Decided (§14 item 3).

---

## 10. Visual system

### 10.1 Colour tokens

**System colours (use as they are)**

| Token | Value | Use |
|---|---|---|
| `accent` | `Color.accentColor` | Selection, focus, primary actions, picker highlight, progress |
| `text.primary`, `.secondary`, `.tertiary` | `.primary`, `.secondary`, `.tertiary` | All chrome text in the sidebar, inspector, sheets and pages |
| `separator` | `Color(nsColor: .separatorColor)` | Hairlines in chrome |
| `status.success` | `.systemGreen` | Success, connection, live on the base layer |
| `status.warning` | `.systemOrange` | Warnings, waiting, edits not on the keyboard |
| `status.danger` | `.systemRed` | Errors, Record, Reset, removed |

**Bench and caps** (asset-catalog colours with Any, Dark and High Contrast variants)

| Token | Light | Dark | High contrast |
|---|---|---|---|
| `bench.base` | `#EDEDF0` | `#141416` | same |
| `bench.lift` | `#F7F7F9` | `#202024` | same |
| `bench.grid` | black 4% | white 4.5% | off |
| `bench.layerWash` | `layer.display` 5% | `layer.display` 7% | 0 |
| `cap.top` | `#FFFFFF` | `#3A3A3F` | — |
| `cap.bottom` | `#F4F4F6` | `#303035` | — |
| `cap.edge` | black 13% | white 10% | black 30% / white 28% |
| `cap.highlight` | white 90% | white 8% | — |
| `cap.legend` | `#1D1D1F` | `#F2F2F4` | — |
| `cap.legend2` | `#5E5E63` (6.4:1 on white) | `#AEAEB4` (7.5:1) | — |
| `cap.ghost.stroke` | black 22% | white 18% | 40% |
| `cap.ghost.fill` | black 2% | white 2.5% | — |
| `cap.unlit` (Lighting) | `#E6E6EA` | `#121214` | — |
| `ring.selection` | `accent`, 2 pt | `accent`, 2 pt | 3 pt |

**Key kinds**
- The bar and band hairline use the token. The band fill is the token at 12% (light) or 18% (dark). Band text uses `ink`.
- Light values are at least 4.5:1 on the band, and at least 3:1 for the bar on the cap.
- Dark `ink` values are at least 4.5:1 on the band, except where the band falls back to `cap.legend`.

| Token | Light | Dark | Dark `ink` on band |
|---|---|---|---|
| `kind.modifier` | `#4F4CCF` | `#A9A7FF` | `cap.legend` (fallback) |
| `kind.holdKey` | `#9E4700` | `#FFB870` | `#FFB870` |
| `kind.layer` (target has no colour) | `#0A6E67` | `#5FE3D3` | `#5FE3D3` |
| `kind.lighting` | `#7D5A00` | `#FFD43B` | `#FFD43B` |
| `kind.label` | `#0A6C94` | `#80D5F6` | `#80D5F6` |
| `kind.macro` | `#7A35C4` | `#D6B8FF` | `#D6B8FF` |
| `kind.tapDance` | `#A3275F` | `#FF9CC8` | `cap.legend` (fallback) |
| `kind.disabled` | `#6E6E73` | `#A8A8AE` | `cap.legend` |
| `kind.danger` | `status.danger` | `status.danger` | `cap.legend` |

**Layer colours.** `layer.display` and `layer.ink` are computed (§4.5). Unit tests must assert the contrast thresholds for the user's two colours and for the 10 default swatches.

**Live:** `live.pressed` is `layer.display`, falling back to `status.success` on the base layer.

**Heat ramp** (single hue, 5 stops, interpolated in OKLab)

| Mode | Stops |
|---|---|
| Light | `#EAF1FB` `#B9D0F0` `#7FA8E3` `#3F74C8` `#123E8C` |
| Dark | `#18202D` `#1F3A63` `#2F5FA0` `#5B91D9` `#A8CCFF` |

**Diff:** added `status.success`, changed `status.warning`, removed `status.danger`.

**Combo palette** (Sextant's own; rings at 2 pt): `#F08C00` `#D6336C` `#1C7ED6` `#0CA678` `#7048E8` `#74B816` `#E03131` `#1098AD`. Each is darkened to 3:1 on the light bench and lightened to 3:1 on the dark cap for drawing; combo n takes colour n − 1, round the palette (ADR 0046).

**Swatches.** These are the layout's 10 colours, which are user data. New layouts use a Sextant default set, not Oryx's.

### 10.2 Type scale

| Use | Style | Notes |
|---|---|---|
| Page title (Macros, Firmware Settings) | `.title2` semibold | |
| Inspector title (key name) | `.title3` semibold | |
| Section header | `.headline`, sentence case | Never tracked uppercase |
| Body, row values | `.body` | |
| Row labels | `.body`, `.secondary`, right-aligned | |
| Descriptions, footnotes | `.callout` / `.subheadline`, `.secondary` | |
| Captions, metadata | `.caption`, `.secondary` / `.tertiary` | |
| Firmware-facing values (QMK, ids, hex, bytes, ms, serials) | `.system(.body or .callout or .caption, design: .monospaced)` | Use `.monospacedDigit()` on counters |
| Big numerals (flash ring, totals) | `.system(size: 40, weight: .semibold).monospacedDigit()` | |
| Lens-lane capsule text | `.callout` medium | |
| Keycap legends | §4.3 | |

The only uppercase label is the "LIVE" badge and the "REC" badge. SF Mono is never used for prose or headings.

### 10.3 Spacing, sizes and radii

- **Grid:** 4 pt. The scale is 4, 8, 12, 16, 20, 24 and 32.
- **Inspector:**
  - 16 pt horizontal padding;
  - 28 pt row height;
  - 12 pt between rows in a group, and 20 pt between sections, with a separator;
  - an 84 pt label column.
- **Canvas:** 20 pt horizontal inset for the header and footer, and 24 pt padding around the board.
- **Glass capsules:** 28 pt (small) or 32 pt (regular) tall, with 12 pt horizontal padding.
- **Radii:**
  - caps 0.16u, continuous;
  - capsules fully rounded;
  - floating panels 22, or `ConcentricRectangle` where it is concentric with the window;
  - cards on pages 10;
  - the HUD 24.
- **Hit targets:** at least 24×24 in chrome. Caps are at least 36 pt.

### 10.4 Materials and Liquid Glass

**Where glass goes**
- The toolbar. The system draws it, including the platters for the capsule, undo and redo, and search.
- Lens-lane capsules.
- The board-footer legend switch.
- The command palette and the keycode picker.
- The HUD.
- Popovers (system).
- Sheets (system).

**Where it never goes:** the bench, caps, the sidebar list content, the inspector body, document pages, Form rows, the build log, and sheet bodies. These are flat and dense.

**Implementation**
- `SurfaceStyle` is a single modifier. It applies `.glassEffect(.regular, in: shape)` (or `.regular.interactive()` for controls). Under `accessibilityReduceTransparency`, or in snapshots, it draws an opaque `#FBFBFD / #26262B` surface at 96% with a hairline and a shadow.
- Adjacent floating glass is wrapped in `GlassEffectContainer(spacing: 8)`: the lens-lane capsules, and the legend switch with its segments.
- **Morphing.**
  - The palette becoming the picker uses `glassEffectID(_:in:)`.
  - Lens-lane capsules appear and disappear with `glassEffectTransition(.materialize)`.
  - The tool capsule and status capsule merge with `glassEffectUnion` when they are within 8 pt.
- **Tint** only for the HUD option (layer colour at 20%) and for the recording capsule (red at 15%). No tinted glass elsewhere.
- **The primary action** is `.buttonStyle(.glassProminent)`. Secondary floating buttons use `.buttonStyle(.glass)`.
- **Legibility over glass** uses semantic `.primary` and `.secondary` text. The snapshot runner may substitute explicit greys behind `isSnapshot` only.

### 10.5 SF Symbols inventory

All names below were checked against the macOS 27 SDK in this session.

| Area | Symbols |
|---|---|
| Build and flash | `bolt.fill` (Build & Flash), `stop.fill` (Stop), `hammer.fill` (Build), `checkmark.seal.fill` (flashed), `button.horizontal.top.press` and `target` (reset button), `lock.shield` (safety note) |
| Status | `checkmark.circle.fill`, `arrow.up.circle`, `exclamationmark.triangle.fill`, `xmark.octagon.fill`, `info.circle`, `lock.fill` |
| Device and live | `keyboard`, `dot.radiowaves.left.and.right` (live, follow), `cable.connector`, `rectangle.and.hand.point.up.left` (Navigator trackpad; `trackpad` does not exist), `eye.slash` (paused) |
| Chrome | `sidebar.leading`, `sidebar.trailing`, `arrow.uturn.backward`, `arrow.uturn.forward`, `magnifyingglass`, `chevron.down`, `plus`, `ellipsis.circle` |
| Destinations and lenses | `square.3.layers.3d` (Layers), `keyboard` (Keys), `lightbulb` (Lighting), `flame` (Heatmap), `point.3.connected.trianglepath.dotted` (Combos), `list.bullet.rectangle` (Macros), `macwindow.on.rectangle` (App Layers), `clock.arrow.circlepath` (History), `slider.horizontal.3` (Firmware Settings) |
| Key editing | `record.circle` (Record), `square.dashed` (Transparent), `nosign` (Disable), `square.and.pencil` (Override), `doc.on.doc` (Copy), `rectangle.2.swap` (Swap), `square.stack.3d.up.fill` (layer key / hold) |
| Lighting | `paintbrush.pointed.fill`, `eraser`, `eyedropper`, `drop.fill`, `swatchpalette`, `sun.max`, `sun.min`, `wand.and.sparkles`, `lightspectrum.horizontal` |
| Media | `speaker.wave.3.fill`, `speaker.wave.1.fill`, `speaker.slash.fill`, `playpause.fill`, `forward.end.fill`, `backward.end.fill`, `stop.fill` |
| Navigation | `arrow.left`, `arrow.up`, `arrow.right`, `arrow.down` (Home, End, PgUp and PgDn are words) |
| Mouse | `computermouse`, `cursorarrow.click`, `cursorarrow.rays` |
| Import and export | `square.and.arrow.down`, `square.and.arrow.up`, `doc.zipper` |
| Diff | `plus.circle.fill`, `minus.circle.fill` |
| Future sync | `arrow.triangle.2.circlepath`, `externaldrive.connected.to.line.below` |
| Custom (template, in an asset catalog) | `sextant.mark` (the 60° graduated arc with an index arm), used in the app icon, menu bar, empty states and About |

Modifiers on caps and in hints are text glyphs (⌃ ⌥ ⇧ ⌘ ⇪ ⌫ ⌦ ⏎ ⇥), not the `command` or `option` symbols, so they match menu typography.

### 10.6 Motion

`SextantMotion` reads `accessibilityReduceMotion`.

| Token | Normal | Reduce Motion |
|---|---|---|
| `snappy` | `.spring(response: 0.26, dampingFraction: 0.86)` | `.easeInOut(duration: 0.15)` |
| `standard` | `.spring(response: 0.38, dampingFraction: 0.82)` | `.easeInOut(duration: 0.18)` |
| `gentle` | `.spring(response: 0.6, dampingFraction: 0.9)` | `.easeInOut(duration: 0.2)` |

| Moment | Spec | Reduce Motion |
|---|---|---|
| Selection ring moves | `snappy` | Instant |
| Layer change | Caps crossfade over 0.18 s, ease-out (an ease-in start looked late after a click). A ripple runs from the thumb that holds the layer (or the board centre), staggered 6 ms per pitch unit up to 90 ms, with scale 0.98 → 1 | Crossfade only |
| Layer atmosphere | Linear crossfade, 0.3 s | Same |
| Palette and picker appear | Fade plus scale 0.98 → 1, 0.16 s ease-out. The palette morphs into the picker with `standard` | Fade, 0.12 s |
| Lens-lane capsule | `.materialize` | Fade |
| Pressed key | Instant on; fade 0.12 s on release; scale 0.96 | No scale |
| Recording ring | Opacity pulse, 0.9 s, repeating | Static |
| Waiting for flash mode | Arc shimmer, 2.4 s per turn; reset-button halo pulse, 1.6 s | Static, with the status text only; the halo holds still |
| Flash ring progress | Linear interpolation, 0.25 s | Same |
| Done seal | `symbolEffect(.bounce)` once | None |
| HUD | In 0.12 s with an 8 pt rise; out 0.18 s | Fade |

### 10.7 Identity

- **The sextant mark.** A 60° graduated arc (7 ticks) with an index arm. It is Sextant's only brand element. It appears in:
  - the app icon: a graphite squircle with a simple porcelain marine sextant in profile (graduated limb, brass index arm, mirrors, short telescope), no keys and no Voyager outline;
  - the menu bar glyph, with the layer number;
  - empty states, large and tertiary;
  - About.
- **Signature moments:**
  - the graduated flash ring (§7.3);
  - the precision grid and layer atmosphere on the bench (§4.10);
  - the menu bar arc filling as the flash progresses.
- **No ZSA trade dress.** No ZSA logo, Voyager wordmark or art, Oryx icon font, or Oryx palette. "ZSA Voyager" appears in text only.

---

## 11. Accessibility

- **VoiceOver.** The board model is in §4.11. In addition:
  - the context-strip cards are buttons labelled "Sym+Num: inherits Return";
  - the slot tabs are a tab group;
  - the picker results are a list, with each row labelled "Left Bracket, KC_LBRC, Punctuation";
  - the activity capsule is two buttons;
  - announcements cover: build succeeded or failed; flashing at 25%, 50%, 75% and done; a layer change while following (throttled); and record captured: "Assigned Left Command plus Left Bracket".
- **Keyboard only.**
  - Tab order: sidebar → canvas header controls → board → context strip → inspector.
  - All actions are reachable from menus.
  - Stock controls support Full Keyboard Access.
  - The board draws its own focus ring, so use `.focusEffectDisabled()` with the custom accent glow.
- **Contrast.**
  - Chrome text uses semantic colours.
  - Custom tokens meet 4.5:1 for text and 3:1 for graphics (§10.1).
  - Contrast is checked by unit tests.
  - `colorSchemeContrast == .increased` switches to the High Contrast variants: 2 pt layer rings (2.5 pt on the key holding the layer), kind bars 1 pt taller with a 0.5 pt dark edge, no grid, and opaque glass.
- **Reduce Transparency.** Every app-drawn glass surface goes through `SurfaceStyle` and becomes opaque. The HUD becomes opaque.
- **Reduce Motion:** §10.6.
- **Differentiate Without Color.** When `accessibilityDifferentiateWithoutColor` is on:
  - caps add a 0.12u kind glyph at bottom right: ⌘ (modifier), `square.stack.3d.up.fill` (layer), `lightbulb` (lighting), "Aa" (label), `list.bullet` (macro), "2×" (tap dance);
  - layer rings become dashed on inherited-hatched keys;
  - diff and issue badges already carry glyphs.
- **Pointer.** Each cap has a `.help` tooltip with the full description after 1 s.

---

## 12. Empty, loading and error states; onboarding

### 12.1 First launch (empty library)

**Centre**
- A large tertiary sextant mark.
- "Bring your layout to Sextant".
- Three cards:
  1. **Import from your Voyager.** Enabled when a keyboard is connected. "Reads the layout ID from the keyboard and downloads it from Oryx, read-only."
  2. **Paste an Oryx link.**
  3. **Start from a blank QWERTY layout.** Authored by Sextant.

**Other regions**
- The sidebar shows the device card.
- The inspector shows "No layout open".

There are no tours or coach marks. The context-strip hint and the shortcut hints on buttons do the teaching.

### 12.2 First build

The "Set up the build tools" step (§7.3). Oryx's build is offered when it applies.

### 12.3 First connect

The device card becomes live and Follow turns on, unless Settings › Keyboard turns that off. A one-time inline note in the Device popover explains live data and privacy.

### 12.4 Empty states

| Surface | Copy | Action |
|---|---|---|
| Combos | "No combos yet. Press two or more keys together to send another key." | [New Combo] |
| Macros | "No macros yet. A macro types a sequence of keys from one key press." | [New Macro] |
| App Layers | "Switch the keyboard's layer automatically when you change apps." | [Add App…] |
| History | "Revisions appear when you import, flash, or save a revision (⌘S)." | [Save Revision…] |
| Heatmap (off) | "Heatmap recording is off. Sextant can count key presses on this Mac to show which keys you use most." | [Turn On…] |
| Heatmap (no data) | "No presses recorded in this range yet." | Range picker |
| Device (none) | "Connect your Voyager with a USB cable." | — |
| Palette (no results) | "No matches for ‘xyz’. Try a QMK name like KC_LBRC or a symbol like [." | — |
| Inspector (no selection) | Layer summary (§3.8) | — |

### 12.5 Loading

- **Spinners appear only after 1 s.** This applies to connecting, fetching and importing.
- **The import checklist** shows each step's state.
- **The toolchain download** shows bytes and an ETA.
- **Building** shows file progress.
- **Nothing blocks the board,** except the modal sheets.

### 12.6 Error catalog

| Condition | Where | Copy |
|---|---|---|
| Keymapp holds the device | Device card, capsule, popover | "In use by Keymapp. Quit Keymapp or disconnect it there; Sextant connects automatically." |
| Device disconnected mid-session | Capsule | "No keyboard" (live highlights stop; no alert) |
| Different layout on the keyboard | Capsule, device card | "Keyboard runs another layout" [Import] or [Flash this layout…] |
| Build error mapped to a key | Six places (§7.5) | §7.5 |
| Build error not mapped | Sheet, log | "The compiler reported an error Sextant couldn't place on a key." [Copy Log] |
| Too large | Sheet | §7.3 |
| Bootloader timeout | Sheet | "Still waiting?" (§7.3); no hard failure |
| DFU failure | Sheet | "Flashing didn't finish…" (§7.3) |
| Image validation | Sheet | "Sextant won't flash this image: <reason>." |
| Import failures | Import sheet | §8.1 |
| Toolchain download failed | Sheet | "The build tools didn't download. Check your connection and try again." [Try Again] [Use Oryx's build] |
| Unknown keycode in a layout | Cap badge, live issue | "KC_FOO isn't a keycode Sextant knows. It's kept as is." |

**Copy style.**
- Sentence case and plain words, with no exclamation marks.
- Say what happened, what it means, and what to do next.
- Use "keyboard" for the device and "layout" for the document.

---

## 13. SwiftUI on macOS 26: implementation notes and build order

### 13.1 Packages and targets

Use SwiftPM, with no third-party dependencies. Do not name a module exactly `Sextant` (decision 1).

| Target | Contents |
|---|---|
| `SextantKit` | Document model, Oryx import and export, `BoardGeometry`, legends, keycode catalog, settings catalog, undoable `EditorStore`. Today this lives in `design/PrototypeKit` |
| `SextantBoard` | `KeyCap`, `BoardView`, lenses, accessibility |
| `SextantDevice` | Raw HID actor (IOHIDManager or CoreHID), live session, RGB takeover, DFU flasher (IOUSBHost), device watcher |
| `SextantBuild` | Generator plus source map, toolchain backends, compiler-diagnostic parser, size analysis |
| `SextantApp` | Scenes, windows, inspectors, palette, sheets, menu bar extra, HUD |

### 13.2 APIs per surface

All of these were confirmed in the macOS 27 SDK during this session.

- **Window.**
  - `NavigationSplitView(columnVisibility:)`, with `.navigationSplitViewColumnWidth`.
  - `.inspector(isPresented:)` attached to the detail view, with `.inspectorColumnWidth`.
  - `.navigationTitle` and `.navigationSubtitle`.
  - `.toolbar(id:)` with `ToolbarItem(id:placement:)`, `ToolbarSpacer(.fixed or .flexible)`, and `.sharedBackgroundVisibility(.hidden)` only where a custom capsule must not get a platter.
  - Commands: `SidebarCommands()`, `InspectorCommands()`, and `CommandMenu("Layer")`, `CommandMenu("Key")` and `CommandMenu("Keyboard")`. Do not replace `.undoRedo`.
- **Glass.** `.glassEffect(_:in:)`, `Glass.regular`, `.interactive()`, `.tint(_:)`, `GlassEffectContainer(spacing:)`, `glassEffectID(_:in:)`, `glassEffectUnion`, `glassEffectTransition(.materialize)`, `.buttonStyle(.glass)` and `.glassProminent`, and `ConcentricRectangle`. In AppKit, use `NSGlassEffectView` for the HUD.
- **Focus and keys.** `.focusable()`, `.focused($board)`, `.focusEffectDisabled()`, `.onKeyPress(keys:phases:)`, `.onKeyPress(characters:)` and `.onMoveCommand`. Use `NSEvent.addLocalMonitorForEvents` only during Record, Record Steps and Select Key by Pressing It (ADR 0052).
- **Accessibility.** `.accessibilityElement(children:)`, `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint`, `.accessibilityAddTraits(.isSelected)`, `.accessibilityAction(named:)`, `.accessibilityRotor`, `.accessibilitySortPriority`, and `AccessibilityNotification.Announcement` (Accessibility framework). Read the environment values `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `accessibilityDifferentiateWithoutColor` and `colorSchemeContrast`.
- **Scenes.**
  - `WindowGroup(id:for:)`, `Settings`, and `MenuBarExtra(isInserted:)` with `.menuBarExtraStyle(.window)`.
  - From the menu bar, `openWindow` followed by `NSApp.activate()`.
  - `.restorationBehavior`, `.defaultSize`, `.windowResizability(.contentMinSize)`.
- **Sheets and popovers.** `.sheet` with its default sizing, a pinned header and footer around a `ScrollView`, and a `maxHeight` cap (§7.2). `.popover(isPresented:arrowEdge:)` for the Device popover.
- **Drag to swap.** `.draggable` and `.dropDestination` on caps, with a payload of a key reference within the same window.
- **No-TCC device and system APIs.**
  - Raw HID on usage page `0xFF60`.
  - IOUSBHost DFU.
  - `IsSecureEventInputEnabled()`.
  - `RegisterEventHotKey`.
  - `NSWorkspace` frontmost-app notifications.
  - Never use the keyboard or mouse HID interfaces, Accessibility, Input Monitoring or ScreenCaptureKit.

### 13.3 Pitfalls learned from the prototypes

1. **Liquid Glass can't be captured offscreen.** `.blur` and layer filters can't either. Keep PrototypeKit's in-process snapshot runner for design QA, with `isSnapshot` fallbacks inside `SurfaceStyle`, and verify real glass in the live app.
2. **Don't ship snapshot workarounds.**
   - Instrument's pure-SwiftUI bezel buttons, and its explicit greys in the inspector, existed because AppKit controls and semantic colours rendered wrongly offscreen. They belong behind `isSnapshot` only.
   - Console's accent capsule for `.glassProminent` is the same kind of workaround.
3. **Keep the window minimum honest.** It must equal the sum of the visible column minimums. Test-render at each minimum.
4. **The board must not depend on optional views.** Instrument's conditional `KeyStackStrip` plus `min(w, h)` scaling moved the board. Compute the board frame from the board-area size alone (§3.3).
5. **Undo.** Register document edits on the window's `UndoManager`, with `setActionName`. Group paint strokes and drags with `beginUndoGrouping` and `endUndoGrouping`. Commit a text field as one store action when editing ends. Never route ⌘Z away from the first responder (Console and Chart Table broke text-field undo).
6. **Performance.** Keep pressed state per cap, as an observable keyed by index. A press must not invalidate all 52 caps. Use `Equatable` inputs for caps. Never wrap glass in `.drawingGroup()`.
7. **Concurrency.** Swift 6 strict mode. HID callbacks run on a dispatch queue owned by an actor. Publish to `@MainActor` models at no more than 60 Hz. DFU runs on its own actor, with capped polls.
8. **HUD.** It must never activate the app or take key status: `canBecomeKey` is `false`. Reposition it on `NSApplication.didChangeScreenParametersNotification`.
9. **Menu bar extra in `.window` style.** It is an NSPanel. Keep it under 520 pt tall and give it no text fields.
10. **Record mapping** must be positional (`keyCode`), not character-based, so it works on non-US layouts. Sides come from device-dependent modifier bits.
11. **Write Sextant's own text.** Descriptions for settings and keycodes must be Sextant's own. `oryx-keycodes.json` and the setting descriptions are ZSA text and must not ship (research §2.2).

### 13.4 Design QA

- Keep a `--snapshot` scene list that mirrors this spec: 01–20, plus min-size renders at 1120×640 and 640×640 (sidebar and inspector hidden).
- Rendering stays in-process and offscreen, with the `.prohibited` activation policy. It needs no TCC.
- Each scene is reviewed in light, dark, Increase Contrast and Reduce Transparency.
- Contrast unit tests cover every custom token and the layer transforms.

### 13.5 Build order

**MVP** (gate: the user's own layout round-trips through import, build, flash, live layer and serial check)

| # | Work | Spec |
|---|---|---|
| 1 | Foundations: library and document, undo, geometry, legends, tokens, `SurfaceStyle`, `SextantMotion` | §2.3, §4, §10 |
| 2 | Window skeleton: split view, inspector, toolbar, canvas bands, commands, honest minimums | §3, §9 |
| 3 | Board render: caps, kinds, layer treatment, states, focus, keyboard navigation, accessibility | §4, §11 |
| 4 | Key inspector: slots, Tap and Hold editors, layer actions, label, LED colour, Transparent and Disable, drag to swap | §5.1–§5.5 |
| 5 | Palette and picker (assign scope, preview, ⌘⏎), and Record Key | §5.6–§5.8 |
| 6 | Layers management | §6.1 |
| 7 | Lighting lens and painting (no keyboard preview) | §6.2 |
| 8 | Import from Oryx (link and connected keyboard) | §8.1 |
| 9 | Device: presence, serial, protocol, live layer, presses, Follow, popover, secure-input pause | §8.2 |
| 10 | Build & Flash: tools setup, build, size meter, live issues, source-map error mapping, DFU with guards, verify, Hide, Oryx fallback | §7 |
| 11 | Firmware Settings page (core tapping, one-shot, debounce, RGB timeout and Navigator sections) | §8.8 |
| 12 | Settings scene (General, Build, Privacy), empty states, onboarding | §8.9, §12 |

**v1**
- Tap dance firmware support.
- The Combos lens.
- The Macros page.
- History with the Changes lens, and Save Revision.
- The Heatmap lens and its recording.
- App Layers.
- The menu bar extra.
- The overlay HUD.
- Every firmware setting Sextant offers (60 for the Voyager).
- RGB takeover preview.
- Per-key tapping term.
- Multi-select, copy and paste of keys, and Copy Layer To.
- Export of images, and printing.
- Select Key by Pressing It.
- Global layer shortcuts.
- The Keyboard and Advanced Settings panes.

**Future**
- Sync and backup: the capsule glyph, the Settings pane, the source device on each revision, Restore from Backup, and the merge UI.
- QMK features beyond Oryx.
- Profiles.
- A CLI and Shortcuts actions.
- More boards. The geometry and the board definition are data, so these need no new code.

---

## 14. Taste calls (decided 2026-10-11)

The user picked the recommended option for all nine, with no notes. The spec above already follows these answers.

1. **Sidebar:** shown by default and remembered per window; ⌃⌘S hides it. Caps are about 52 pt at 1440 pt wide.
2. **Bench:** a plain bench, plus a faint precision grid at key pitch and a subtle layer-colour wash on non-base layers. The grid can be turned off in Settings.
3. **Shortcuts:** ⌘R Build & Flash, ⌘B Build only, ⌘. Stop, as in Xcode.
4. **Flash progress:** the graduated sextant-bezel ring with the phase percentage, plus a small Erase/Write/Verify segmented bar and the facts.
5. **Heatmap:** a single-hue blue ramp, log-scaled, light to dark in light mode and flipped in dark mode.
6. **Privacy:** live press highlights are on by default. They show positions only, stay in memory and pause during secure input. Heatmap recording is off until the user opts in.
7. **Storage:** a Sextant-managed library of `.sextant` packages (plain JSON) in Application Support. It is listed in the sidebar, with Show in Finder and Export.
8. **Menu bar extra:** lit layer tiles, a live mini map, the app-rule and overlay switches, and native rows (Build & Flash ⌘R, Open, Settings, Quit). It shows no typing stats unless heatmap recording is on.
9. **Overlay HUD:** neutral Liquid Glass, with keys ringed in the layer colour. "Tint with layer colour" is an option in Settings.

Source: the review page's answer store (`answers/q1`–`q9`); the questions are in `open-questions.json`.
