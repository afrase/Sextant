# Design directions

Each direction is a runnable SwiftUI prototype in `design/explorations/`. Snapshots are rendered offscreen, so Liquid Glass is approximate in the PNGs; run the prototype to see the real thing.

## Instrument (direction A) (`a-instrument`)

- **Run:** `cd /Users/aaron/Developer/Sextant/design/explorations/a-instrument && swift run SextantInstrument`
- **Snapshots:** `cd /Users/aaron/Developer/Sextant/design/explorations/a-instrument && swift run SextantInstrument --snapshot snapshots   (optional: --only 01-main-dark,19-error  --scale 2)`
- **Snapshot folder:** `/Users/aaron/Developer/Sextant/design/explorations/a-instrument/snapshots` (20 scenes)

### Concept

Instrument treats Sextant as a precision pro tool in the lineage of Xcode, Final Cut Pro and Logic. It is one calm document window with three stable columns, and the centre board never shrinks or reflows.

**Layout**
- **Sidebar:** the layout library, then layers (colour chip, index, name, assigned-key count, a live badge on the layer the keyboard is on), then layout documents (Combos, Macros, App Layers, History, Firmware Settings). A pinned device card at the bottom shows connection, the 4 status LEDs, the active layer, the serial (verified against the layout) and the firmware/protocol version.
- **Centre:** the board, large and crisp, with a compact layer strip above it. One board is read through four "lenses" (Keys, Lighting, Heatmap, Live), the way Logic shows one track in different views. Under the board, a "key across layers" strip acts as a channel strip for the selected key, showing what it does on every layer at once.
- **Inspector:** Xcode-dense, with right-aligned labels:
  - a header with a cap preview, kind badge, the whole-key QMK expression and the matrix position;
  - four slot tabs that each preview their action;
  - a structured slot form: keycode field with inline picker, ⌃⌥⇧⌘ L/R chips plus Hyper/Meh, a layer-action menu, and "Sends";
  - key properties: a 10-character label, LED colour and tapping term;
  - Record Key, Transparent and Disable.
- **Toolbar (Liquid Glass):**
  - a Run-style accent "Build & Flash" button at the leading edge (Stop while busy);
  - an Xcode-style activity capsule in the centre, combining device identity and serial with build/flash status, detail and a progress hairline;
  - then the layer switcher, undo/redo, Open Quickly (⌘K) and the inspector toggle.

**Flows**
- Build & Flash is a sheet with a five-step indicator (Build, Flash Mode, Write, Verify, Done). It covers the build log, the size meter, a pinhole schematic or the hold-Space-then-Reset alternative, segmented Erase/Write/Verify progress, and done and failed states.
- Build errors map back to the key everywhere: the cap badge, the capsule, the board banner and the inspector callout with a one-click fix.
- Firmware settings are a searchable grouped Form with modified state.

**Distinct from the other directions:** no canvas metaphor or navigation styling (that is Chart Table), and no command-line or console-first chrome (that is Console). Instrument is document, inspector and toolbar.

### Interaction model

All edits go through PrototypeKit's EditorStore, so every change is undoable and named ("Undo Set Hold"). It works on the user's real layout (Samples.layout).

**Select and navigate**
- Click a key, or focus the board and use ←↑→↓. Navigation crosses halves and reaches the thumbs.
- Esc deselects.
- ⌘1/⌘2/⌘3 switch layers; so do the layer strip, the toolbar layer menu and the sidebar rows.
- ⌃⌘1–4 switch lens (Keys, Lighting, Heatmap, Live).
- ⌥⌘0 toggles the inspector; ⌘0 toggles the sidebar (system).

**Edit a key**
- Return, ⌘E or double-click opens the inline keycode picker under the keycode field. The search field is focused: type a name, glyph or QMK code ("⌘", "[", "vol"), use ↑↓ to choose, ⏎ to assign, esc to close. Category chips and recents sit above the results.
- Tab or ⌃1–⌃4 switch slots (Tap / Hold / Double tap / Tap + Hold). The slot tabs also show what each slot does.
- Modifier chips toggle Left/Right ⌃⌥⇧⌘; Hyper and Meh are one click.
- The Layer menu sets MO/TG/TO/TT/OSL and the target layer.
- The Label field enforces 10 characters with a counter.
- LED colour swatches set the per-key colour.
- ⌘⌫ makes a key transparent; ⇧⌘⌫ disables it.
- "Override on <layer>" copies an inherited key onto the current layer.

**Record Key (⇧⌘R)** is an explicit mode. The button reads "Listening… press a key, esc to cancel"; the next key press with its modifiers is assigned. It uses local SwiftUI key events only, with no Input Monitoring.

**Undo / redo:** ⌘Z / ⇧⌘Z, via the menu or the toolbar. Text fields keep their own undo first.

**Layers:** add (+ in the strip, sidebar, or ⇧⌘N), rename, duplicate, move up/down, colour, delete (sidebar context menu or the Layer menu), or drag to reorder in the sidebar. Layer references follow moves.

**Lighting:**
- Paint, Erase or Pick tools; drag across keys to paint.
- ⌥-click picks up a colour.
- Saturation/brightness field, hue strip and swatches; set the layer colour from the brush.
- A live-preview toggle and a brightness slider.

**Live:** follows the keyboard's active layer and lights pressed keys (mock script). An event log is shown. While a layer is held in Live, a click-through HUD panel appears at the bottom of the screen.

**Build & Flash (⌘R), Build (⌘B), Stop (⌘.):**
- The sheet walks through the steps. In the prototype, the bootloader is "detected" after 4 s, or press Flash Now.
- Product ▸ Simulate Build Error demonstrates the failure path. Show Key (⌘') reveals the mapped key, and Fix applies the suggestion.

**Import (⇧⌘I):** paste a link or use the connected keyboard, preview, then Import (undoable).

**Open Quickly (⌘K):** commands, layers, any key in the layout ("where is Esc?" jumps to it), and firmware settings. Use ↑↓ and ⏎.

**Documents:**
- Combos: select a combo, then click keys to add or remove them.
- Macros: select steps; the inspector edits modifiers and delay.
- App Layers: toggle rules.
- History: pick a revision and a layer tab to see the diff.
- Settings: search, "Modified only", Reset to Default, and the inspector's section navigator scrolls the Form.

**Menu bar extra:** shows the current layer, lets you switch layers, and offers Build & Flash.

### Visual language

**Colour**
- Neutral graphite (dark) and porcelain (light) surfaces, all defined as appearance-adaptive tokens.
- The board sits on a recessed "bench" with a soft radial lift.
- The system accent is reserved for selection and the primary action.
- Text uses explicit grey tiers (text2/3/4) instead of vibrant semantic styles, so hierarchy holds over glass sidebars and inspectors.
- Layer colours are user data. They are used as-is in dark mode and deepened in light mode so #42FF00 and #00F0FF stay visible.

**Key-kind system: two separate channels**
1. Kind is a short signal bar along the bottom of each cap plus a faint 4.5% tint, like a Logic region carrying its track colour:
   - modifier: indigo
   - tap + hold: amber
   - layer: teal, or the target layer's own colour
   - lighting: yellow
   - custom label: blue
   - macro: violet
   - tap dance: rose
   - disabled: grey with a nosign glyph
   - regular: no bar
2. Layer is a 1 pt outer ring in the layer colour, with a faint glow in dark mode.

So kind and layer never compete for the same pixels.

Other cap states:
- Transparent keys are dashed, with the inherited legend at 42% opacity.
- The key that holds the displayed layer is hatched in that layer's colour.
- Set-colour keys show a glowing swatch; per-key LED colour is a small corner dot.
- Reset (QK_BOOT) is set in red.
- Selection is a 2 pt accent ring offset outside the cap; build errors use a red ring and badge.
- Every cap carries its tiny monospaced index (toggle with ⌥⌘I). The QMK-codes view toggles with ⌥⌘C.
- The kind key under the board lists only the kinds present on the current layer.

**Type**
- SF Pro for UI. SF Mono for anything the firmware cares about: QMK expressions, indices, serials, byte counts, ms values.
- Mac glyphs ⌘⌥⌃⇧ with small L/R marks.
- SF Symbols for media, RGB, editing and arrows; words for Home/End/PgUp/PgDn/Esc/Space/Reset.

**Materials and Liquid Glass**
- Used for system chrome and floating things only: the toolbar platters, the glass lens capsules over the board (paint tools, LIVE, heatmap summary), the ⌘K palette, and the HUD.
- Documents and inspectors stay flat and dense.
- Inspector controls use a pure-SwiftUI bezel style so they match across appearances.

**Heatmap:** a magma-like perceptual ramp (violet → magenta → red → orange → yellow), with legend colour chosen by luminance.

**Motion (live app; disabled in snapshots):**
- the picker expands with a snappy 0.2 s move+fade;
- the palette scales in from 0.98;
- pressed keys light instantly in the layer colour with a glow;
- the HUD appears and hides with the held layer.
Reduce Motion should drop the transitions to fades (not yet wired).

### Limitations

**Snapshot fidelity vs the live app**
- Liquid Glass and materials are flattened by PrototypeKit's LayerFlattener: the toolbar platters, glass capsules and palette show as flat translucent fills, with no blur, refraction or highlight. The HUD (12) uses SwiftUI's own ImageRenderer glass, which is closer to real.
- Sheets (07–09) are composited overlays, not real sheets, and there is no real window shadow.
- The palette is an in-window overlay that, in the snapshot, covers only the centre column.
- Menu-style controls (layer menu, layer-action menu) render closed; open menus and popovers are never captured.

**Workarounds I applied for the snapshots**
- In dark mode, AppKit push buttons and pop-ups inside the glass inspector rendered as blank white capsules. I replaced them with a pure-SwiftUI bezel style, so the PNGs match the live app but those controls are not stock NSButtons.
- Semantic secondary/tertiary text and inherited-colour SF Symbols came out too faint or vanished in the glass columns. I use explicit grey tokens and apply colours directly to images.

**Interactive mode was not launched by me**, to avoid stealing focus on your Mac. It builds cleanly and every view is exercised by the snapshot run, but the following haven't been tried by hand:
- window activation, the MenuBarExtra and the Settings window;
- the HUD NSPanel;
- the record-key focus and ⌘Z routing.

**Prototype shortcuts**
- The library items other than My MacOS Layout are static.
- The tapping-term stepper, LED-brightness preview, Export CSV, Add Step / Record Steps, Assign to Key, Add App, Compare, Restore / Flash Revision and Export Source are visual only.
- Combo output and layer scope aren't editable yet; macro edits live in the app model rather than the document, so they aren't undoable.
- App rules, the heatmap range and the history samples are fixed mock data.
- "Fix" for the build error hard-codes the KC_LBRC suggestion.
- The bootloader is auto-"detected" after 4 s.
- The "Writing (Colemak)" and "Voyager Default" library entries and the app-switch log are invented mock data.

**Polish gaps**
- Reduce Motion and Reduce Transparency aren't specially handled.
- QMK-codes mode is basic.
- The flash-guide half-board close-up is still smallish.
- PrototypeKit renders =/Esc as DUAL(KC_EQUAL, KC_ESCAPE).

### Next steps

1. Launch interactively on a spare display and verify:
   - activation and the menu bar extra;
   - HUD panel placement and click-through;
   - Record Key focus and ⌘Z routing;
   - board focus after clicking into the inspector;
   - real Liquid Glass on the toolbar, lens capsules and palette.
2. Add combo output and layer editing, and move macros into the document model, so they're undoable like keys.
3. Wire Reduce Motion (fades only) and Reduce Transparency (opaque capsules and palette). Run an accessibility pass: VoiceOver labels on caps (legend + kind + layer) and the slot tabs.
4. Board refinements:
   - multi-select (⇧-click or marquee) for bulk paint, transparent and copy;
   - drag-to-swap keys;
   - mirror left/right;
   - a hover popover with full slot details.
5. Add a dedicated issue navigator, Xcode-style, for multiple build warnings and errors. Add the "too large" failure path with its size-meter overflow.
6. Try a narrower inspector or a 3.0u half gap at 1280 pt windows, to keep keys at 44 pt or more.
7. Compare side by side with Chart Table and Console. Candidates to borrow across directions: the key-across-layers channel strip, the two-channel kind/layer cap system, and the activity capsule.

## Chart Table (`b-chart-table`)

- **Run:** `cd /Users/aaron/Developer/Sextant/design/explorations/b-chart-table && swift run SextantChart    (headless check of the same model intents the UI uses, no window: swift run SextantChart --selftest; all 25 checks pass)`
- **Snapshots:** `cd /Users/aaron/Developer/Sextant/design/explorations/b-chart-table && swift run SextantChart --snapshot ./snapshots   (optional: --only 03-key-hold-edit,10-live  --scale 2). 23 scenes in about 70 s, all in-process: .prohibited activation policy, windows off-screen at alpha 0, no TCC.`
- **Snapshot folder:** `/Users/aaron/Developer/Sextant/design/explorations/b-chart-table/snapshots` (23 scenes)

### Concept

CHART TABLE treats the keyboard as land on a nautical chart. The window is one canvas: a paper chart in light mode and a night chart in dark mode. The two halves are islands ringed by isobaths, made by contouring a Gaussian field over the real key positions, with shallow-water tint near the board, a fine graticule aligned to key pitch, graduated edge scales and a restrained compass rose in the gap.

Chrome nearly disappears. Floating Liquid Glass carries a status cluster top-right (undo/redo, a search pill, a device pill whose four status LEDs mirror the hardware, a Maps-style 'follow' location button, and Build & Flash) and a dock of layer-colour capsules plus lens tools bottom-centre. The title block and margin legends are printed on the chart itself, not glass.

The board is sacred. Its frame is computed only from the window size, with the bottom band reserved for a glass shelf, so nothing that opens or closes ever moves or resizes it. The key editor card docks in the open water between the halves (about 390 pt wide at 1440 pt) and is tied to the selected key by a dotted tether drawn beneath the caps, so editing never hides a key. In narrower windows it falls back to a callout beside the key.

⌘K is a Spotlight-style palette and also the keycode picker. While assigning, it floats over the other half so the target key previews the highlighted keycode live. Pasting an Oryx link turns the palette into an import preview.

Lenses (Edit, Paint Lights, Soundings, Combos, Logbook, App Layers) re-colour the same board and put their controls in the shelf. Build & Flash takes over as a centred glass HUD with a big progress ring on a graduated sextant-style bezel.

The navigation metaphor is kept to visuals and a few names (Soundings for the heatmap, Logbook for history, a macro as a 'route' of waypoints and legs, Wake for recent keys). Every label still says plainly what it does.

### Interaction model

SELECT AND NAVIGATE: Click a key to select it (sighting reticle) and open the docked card. Arrow keys move the reticle across halves and into the thumbs (geometry.neighbor). Return opens the card; with the card open, Return opens the picker for the current slot. Esc steps back: recording, then live shelf, then card, then lens, then selection. Clicking empty chart deselects. Hovering outlines the key under the pointer.

EDIT A KEY: Slot tiles Tap / Hold / Double / Tap-Hold, also ⌥1–⌥4.
- Tap: action tile with Change… (⏎ or ⌘⏎), Record (⌘R) and Clear; chord modifiers ⌃⌥⇧⌘ toggles with a Left/Right choice; layer functions get Hold/Toggle/Switch/One-shot/Tap-toggle plus layer chips.
- Hold: a segmented Modifier / Layer / Key / Nothing. Modifier gives ⌃⌥⇧⌘ toggles and L/R for home-row mods (Hyper/Meh mapped). Layer gives layer chips (MO).
- Below the slots: custom label (10 characters, rendered in New York) and LED colour swatches.
- Footer: QMK expression (selectable), Make Transparent, Disable, and a ⋯ menu.
- On the board, Delete makes the key transparent. Dragging one key onto another swaps them, shown with a dashed bearing line, as one undo step.

PICK A KEYCODE (⌘K, or Change… / Return): Type to search all 320 keycodes; glyphs like ⌘ and [ work. The category rail browses 15 categories, and ⇥ cycles them. ↑↓ moves the highlight and the target key previews it. ⏎ assigns; ⌘⏎ assigns and advances to the next key with the palette still open, for fast remapping. Esc closes. With nothing typed you get Suggested (hold-for-layer and modifiers for hold slots, plus recents).

RECORD KEY: An explicit mode (⌘R or the Record button) shows a 'Listening…' tile. The next key press inside Sextant is assigned, modifiers included, through a local NSEvent monitor (no Input Monitoring prompt). Esc cancels.

COMMAND PALETTE (⌘K, nothing selected): Commands, keys on the board ('back' finds Brd+Sys Back and jumps to it), keycodes for the selected key, and paste-an-Oryx-link import (⇧⌘I pre-fills it).

LAYERS: Click a dock capsule or press ⌘1–⌘9. A layer change ripples out from the thumb that holds it. Context menu: Rename (or double-click), Colour, Duplicate (⌘D), Move Left/Right (⌥⌘←/→), Delete (⌘⌫). + or ⇧⌘N adds a layer. Inherited keys are shown as dashed ghosts.

LENSES: Dock tools, or V/P/H/C/L/A on the board, or ⌥⌘ plus that letter from the View menu.
- Paint: click or drag across keys; each stroke is one undo step. Fill Layer and Clear Keys in the shelf.
- Soundings: 24h/7d/30d range, top keys, Export CSV.
- Combos: click 2–6 keys, then Choose Output.
- Logbook: pick a waypoint and the board shows that revision with changed keys marked; Restore.
- App Layers: per-app rule switches.

LIVE: The location button (⌘L) follows the keyboard: the board shows whatever layer is held, and pressed keys light with sonar rings. The device pill (⇧⌘L) opens the Live shelf.

BUILD AND FLASH: ⌘B. The HUD shows Build → Flash mode (pinhole guidance) → Write → Verify, with the size meter and calm progress. Hide keeps it running, with progress shown on the status button. On failure the board jumps to the offending key with a docked error card offering Fix & Rebuild.

FIRMWARE SETTINGS: ⇧⌘, opens a searchable panel with section sidebar, Modified filter, defaults and Reset.

UNDO: Every edit is undoable with a readable name. ⌘Z / ⇧⌘Z come from the Edit menu, which shows the action name, and from the glass undo/redo pair.

MENU BAR EXTRA: current layer, pocket chart, quick layer switch, Build & Flash.

### Visual language

COLOUR
- Paper chart: paper #F4F2EC, chart ink #2E4A66, printed text #22344A, shallow tint #5B8DB8 at 2–11% in smooth terraces.
- Night chart: #0A1019, line ink #8DB4DA, shallow tint #2B5C8A.
- Accent is chart blue (#1F6FEB / #4C9BFF), used for selection, focus and primary actions. Status colours (success, warning, danger) are reserved.
- Layer colours come from the user's data. On paper they are darkened by HSB for legibility (cyan to teal, lime to green); on the night chart they glow as-is. Main has no colour and uses ink, drawn as a hollow dot.
- On a coloured layer, the isobaths and shallow water take on the layer's colour.

TYPE
- SF Pro for UI and keycaps: letters 0.33u medium, words 0.185u semibold, captions under symbols. SF Symbols for modifiers, editing, navigation and media.
- New York (serif) for everything 'printed on the chart': title block, italic annotations, marginalia, depth-scale labels, soundings counts, macro leg lengths. Custom labels are also set in New York, because they are your words, like place names on a chart.
- SF Mono for QMK expressions and hex.

MATERIALS
- Every floating piece is Liquid Glass in the app: glassEffect, interactive glass for controls, tinted for layer/selection, and GlassEffectContainer so dock capsules merge and morph.
- The board and chart are opaque paper/ink. Glass sits over them, never inside them.
- Scrims dim the chart for modal moments: palette light, settings medium, flash HUD strong with a board scale-down and blur.

KEY-KIND SYSTEM (caps stay paper-white or slate; meaning rides on top)
- Modifier: indigo wash with L/R mark.
- Tap + hold: a coloured hold band across the bottom third showing what holding does, tinted by the hold's kind (indigo for modifiers, the target layer colour plus a stack glyph for layer-tap).
- Layer key: target-layer wash.
- Lighting: amber wash with symbol and caption.
- Custom label: coral wash, serif label, underlying chord underneath.
- Macro: orchid. Tap dance: rose.
- Transparent: a dashed 'submerged' ghost with the inherited legend at 36%.
- Disabled: hatch.
- The key that holds the displayed layer: diagonal hatching in the layer colour.
- Non-base layers: rim plus glow in the layer colour.
- Per-key LED: a small glowing corner dot.
- Set-colour keys: a swatch.
- Escape renders as 'esc'.

LENSES
- Paint: backlit under-glow (rim plus halo), with own colours stronger than layer colours.
- Soundings: single-hue blue scale, light to dark on paper and flipped on the night chart, log-normalised, with bathymetric contours.
- Logbook: green/amber/red rings and badges, unchanged keys quiet.
- Combos: coloured rings and bearing arcs with output badges.

MOTION (every animation respects Reduce Motion; springs become 0.15–0.2 s fades)
- The reticle snaps between keys on a snappy spring.
- Layer changes ripple from the activating thumb outward, staggered by distance, with fade and scale.
- The compass rose turns to each layer's heading (72° steps).
- Cards and palettes scale in from their anchor; shelves rise from the bottom.
- Pressed keys depress and emit looping sonar rings.
- The flash ring animates; the bootloader wait is a slow rotating arc; the pinhole pulses.

### Limitations

SNAPSHOT FIDELITY VERSUS THE LIVE APP
- Liquid Glass cannot be captured offscreen. PrototypeKit's flattener draws regular glass flat and tinted glass as accent blue, so snapshots branch on isSnapshot and draw a hand-built stand-in: translucent body (about 80–90%), top-lit specular rim, hairline edge, contact shadow. It has no blur, refraction or lensing. The live app uses real glassEffect (tinted and interactive) inside GlassEffectContainer, so dock morphing and glass highlights are only visible when running.
- .blur and other layer filters do not render offscreen, so behind the flash HUD the snapshots show only the scrim and scale, not the blur.
- Animations (layer ripple, rose rotation, sonar rings, waiting arc, pinhole pulse) appear as static frames.
- Hover outlines and the drag-to-swap bearing line are not shown.
- Text fields in snapshots are deliberately unfocused (no caret or selection).
- The menu bar panel (11) and overlay (12) are rendered as content scenes on my own panel background and a mock desktop. The real MenuBarExtra and an NSPanel overlay are not captured.

PROTOTYPE GAPS
- The overlay HUD is designed and rendered but not wired as a real click-through NSPanel.
- App Layers rules toggle but do not watch NSWorkspace for the frontmost app.
- 'Open as New Layout', 'Compare…', the combo 'Choose Output…' picker (it assigns Delete as a placeholder), and the animation-select and layer-select setting controls are stubs.
- Macro steps can be edited (modifiers, delay, add, delete) but not reordered by drag.
- In the flash HUD, the bootloader 'detection' is simulated by double-clicking the 'Listening for the bootloader' status (labelled as prototype-only).
- Undo/redo replaces the Edit menu's undo group, so text fields don't get their own ⌘Z.
- Keycode Record maps US-layout keys only.
- The docked card assumes a gap of at least about 372 pt. Below that (minimum window 1120 pt) it falls back to a side callout, which can cover neighbouring keys.

NOT VERIFIED
- I did not launch the interactive window myself, to avoid putting a window in front of the user. It compiles, the snapshot path exercises the same views, and --selftest drives the same model intents headlessly (25 checks pass), but live focus and keyboard handling (onKeyPress on the board, palette arrow keys) are untested by eye.

### Next steps

1. Run it interactively and tune feel: spring constants, the layer ripple's delay per pitch, tether routing as the card resizes, and whether palette ↑↓/⇥ reach onKeyPress inside the field editor (fall back to an NSEvent local monitor if not).
2. Wire the real surfaces: a nonactivating click-through NSPanel for the overlay; NSWorkspace frontmost-app observation for App Layers; MenuBarExtra state shared with the main window; device pill states for searching, heldByAnotherApp ('Keymapp is connected') and bootloader.
3. Finish the stubs: a combo output picker (reuse the palette with a combo target token), macro step reorder and record-into-macro, the animation-select sheet, layer-select chips, a Logbook compare-two-revisions mode (before/after split caps), and 'Open as New Layout' as a document window.
4. Accessibility: VoiceOver labels per cap (kind + legend + hold) with the board as an accessibility container in key order; Reduce Transparency check (glass becomes opaque, so verify chart contrast underneath); keyboard-only route through the dock and shelf; increase-contrast variants of the ghost caps.
5. Design checks: validate the key-kind hues for colour-vision deficiency against both chart surfaces (dataviz validator) and add a texture fallback for the hold band; tune the paper hue against real Liquid Glass on device; decide whether the compass rose and edge graduations earn their place at small window sizes; test 1120×740.
6. Performance: contour artwork is cached per size/pitch/mode. Precompute it off the main actor on window resize, and only redraw the band image when the layer tint changes.
7. Compare with INSTRUMENT and CONSOLE on the shared moments (03, 04, 07, 10). The ideas most worth stealing back into whichever direction wins: the gap-docked editor that never hides a key, live keycode preview on the target key, assign-and-advance (⌘⏎), and errors mapped to the key with a one-click fix.

## Console (`c-console`)

- **Run:** `cd /Users/aaron/Developer/Sextant/design/explorations/c-console && swift run SextantConsole`
- **Snapshots:** `cd /Users/aaron/Developer/Sextant/design/explorations/c-console && swift run SextantConsole --snapshot snapshots   (the directory is optional and defaults to ./snapshots; also takes --only 01-main-dark,10-live and --scale 2). Rendering is in-process through PrototypeKit's SnapshotRunner: activation policy is .prohibited, windows are offscreen at alpha 0, and no TCC APIs are used. All 21 scenes take about 60 s.`
- **Snapshot folder:** `/Users/aaron/Developer/Sextant/design/explorations/c-console/snapshots` (21 scenes)

### Concept

CONSOLE treats Sextant as a live instrument console: a DAW transport bar, Logic's editor drawer and a Raycast command line, with the connected keyboard as the protagonist.

Window, top to bottom:
1. Title bar: layers are Safari/Arc-style tabs with colour chips. The tab for the layer the physical board is on carries a pulsing live pip. Beside them sit a native glass ⌘K field and an accent Build & Flash button.
2. Live strip: the keyboard's status line, built like a DAW transport.
   - Left: connection and identity.
   - Centre: a recessed LCD with a layer track whose lit segment slides as the physical layer changes, 4 status LEDs, keys down as keycaps, and a typing sparkline with WPM.
   - Right: Follow, Heatmap and HUD toggles.
   - During a flash the strip becomes the bootloader progress line.
3. Board stage (upper split): the board at a stable size on a recessed stage, with a centre readout (layer name, number, the key that holds it, own vs inherited counts) and the trackpad.
4. Drawer (lower split): resizable, with 10 tabs in two groups.
   - Document: Key, Macro, Combos, Colours, Settings.
   - Physical board: Device, Heatmap, App Layers, History, Flash.

The key idea is "the drawer picks the board's lens; the board never moves". The same board re-skins to the task: edit, heat, LED preview, revision diff, combo picking, flash-mode guidance (callouts on the actual Space and Reset keys), error (the failing key ringed), or offline during a write. Drawer content is clipped to its height, so only the grab handle resizes the board.

The key editor puts the four slots side by side so they compare at a glance. A "through layers" column shows the same position on every layer, highest first, with fall-through arrows.

⌘K is the front door to everything, Raycast-style:
- keycodes, assigned to the focused slot, including concrete layer actions such as "Hold for Sym+Num MO(1)";
- commands with their shortcuts, firmware settings with live values, and any key on the board by legend;
- pasted Oryx links, with an import preview pane;
- in assign scope it becomes the keycode picker: a category rail and a keycap grid, ⇥ to change slot, ⌘↵ to assign and advance.

The menu bar extra is a pocket console: one-click layer moves, a live mini map, WPM, the app rule in force, HUD and flash. The HUD is a click-through glass panel tinted with the layer colour. It appears only while a layer is held and shows that layer's map with your fingers on it.

How it stays distinct from the other directions: the main inspector is a drawer, not a sidebar, unlike INSTRUMENT. It has mono LCD readouts, a live strip and a palette-first workflow, unlike CHART TABLE. It uses no navigation metaphor at all.

### Interaction model

Core tasks:
- **Select a key:** click it, or use ←↑→↓. Selection crosses the halves and reaches the thumbs. Esc deselects.
- **Edit a slot:** pick a slot with ⇥ / ⇧⇥ or 1–4 (Tap, Hold, Double tap, Tap+Hold), or click its column.
  - ↵ (or ⌘↵) opens the picker scoped to "key · slot".
  - In the picker: type to search 320 codes by name, code or glyph. ↑↓ move (arrows move in the category grid). ↵ assigns, ⌘↵ assigns and moves to the next key, ⇥ switches slot, esc closes.
  - ⌫ clears the slot; ⇧⌫ makes the key transparent.
  - Hold column: segmented Modifier | Layer | Key, an L/R modifier chooser and layer chips (MO). Tap columns: a ⌃⌥⇧⌘ L/R chord grid.
  - Identity column: label (10 characters), LED colour, Transparent, Disable, copy QMK.
- **Record key:** R, ⌥⌘R, or the Record button arms the slot (red ring, REC badge). The next physical key is assigned, including a chord such as ⇧` → LSFT(KC_GRAVE) or a lone modifier. Esc cancels and is never captured.
- **Command palette:** ⌘K, or / and ? on the board. It holds commands, settings (opens the setting in the Settings tab), keys on the board ("vol" finds Vol± on Brd+Sys), layers, and Oryx links (paste a URL; ↵ imports undoably).
- **Layers:**
  - ⌘1–⌘9 switch layers; [ and ] step through them.
  - ⌘T adds a layer and ⇧⌘D duplicates the current one.
  - Double-click a tab to rename it; its context menu also offers Duplicate, Colour, Move Left/Right and Delete.
  - Follow (⌘L) makes the editor track the physical layer.
- **Undo:** ⌘Z / ⇧⌘Z. Every edit goes through EditorStore's UndoManager and restores the selection; the drawer header shows the action name ("Undo Set Hold").
- **LED paint:** open the Colours tab (⌥⌘4) for the LED lens.
  - Tools: B brush, G fill layer, I pick, E erase.
  - Click or drag across keys; one stroke is one undo step.
  - Set the layer colour from the brush, and toggle live RGB-takeover preview.
- **Combos:** New, then click 2–6 keys on the board (numbered rings, dotted link), then Done. Esc cancels. Each combo can be scoped to a layer.
- **Build & flash:** ⌘B. The Flash tab runs a stepper (generate → compile → link → flash mode → erase → write → verify), with the size meter and live log.
  - At flash mode the board shows callouts on Space and Reset plus the pinhole; "I pressed it" stands in for bootloader detection in the mock.
  - During the write the strip becomes a progress bar and the board goes offline.
  - On failure the key is ringed. Log lines link to it, and the card offers Show key and Fix & rebuild.
- **Drawer:** ⌥⌘1–⌥⌘0 select tabs. ⌘J or double-clicking the handle collapses it; dragging the handle resizes the board.
- **Lenses and legends:** Heatmap ⇧⌘H. The legend switch toggles Aa (glyphs), KC (QMK codes on every key) and # (indices).
- **Settings:** filter 100 settings, All / Modified, sections with modified counts, inline toggles and sliders, and Reset to default (stored sparsely).
- **History:** pick a revision to see a per-key diff on the board and a before→after list; Restore.
- **Menu bar extra:** one-click layer moves, live map, rule toggle, HUD toggle, Build & Flash, Open.
- **HUD:** appears automatically while a layer is held; never takes focus.

Keyboard handling is a local NSEvent monitor scoped to the main window. It needs no permissions, is bypassed when a text field has focus, and focus is dropped when you click the board. The routing logic is a pure function exercised by --selftest.

### Visual language

**Colour.** Graphite neutrals: a recessed stage, a chrome band for the toolbar and strip, a solid drawer, and recessed "LCD" wells. Colour appears only where it means something:
- **System accent:** selection, focus and the picker.
- **Live green:** connection, presses on the base layer, LEDs and the sparkline.
- **Layer colours** (the user's #00F0FF and #42FF00):
  - tab chips and underline;
  - a faint stage wash from the top;
  - a 2 pt "lamp" line on each key the layer owns;
  - hold bands that point at that layer;
  - live presses while on that layer;
  - the HUD tint.
  Very bright layer colours are darkened automatically in light mode for legibility.
- **Status:** amber for flash in progress; red for errors and Record.
- **Key-kind signal palette** (Sextant's own, not Oryx's): modifier blue, tap+hold teal, tap dance pink, lighting amber, custom-label violet, macro coral. Layer keys use their target layer's colour.

**Type.** SF Pro for UI. SF Mono for everything that is code or measurement: QMK expressions, k-indices, hex, bytes, ms, revision ids, the event monitor and log, plus small tracked uppercase section labels (TAP, HOLD, THROUGH LAYERS, KEYS DOWN), which give the sharp information-design voice. Numbers use monospaced digits.

**Key-kind visual system.**
- Caps are neutral and convex, with a top-lip highlight.
- A lower "function band" holds the secondary action, tinted by what it does:
  - ⏎ shows a cyan Sym+Num band and ␣ a green Brd+Sys band;
  - Z/⌥ and '/⇧ show blue modifier bands; =/⎋ shows a teal band.
- Single-function specials get a whole-cap tint: blue for modifiers, coral for macros, pink for tap dance.
- Lighting keys are amber glyphs.
- Set-colour keys show their colour as a band with the mono hex.
- Custom labels show the label, with the real shortcut (⇧⌘[) in mono on a violet band.
- Transparent keys are dashed ghost caps with the inherited legend at 36%. Disabled keys show a nosign glyph.
- The key that holds the displayed layer is outlined and filled in the layer colour.
- Modifiers carry L/R mono subscripts.
- Legend modes: Aa (glyphs), KC (QMK) and # (index).
- The stage legend explains the colours and changes per lens: kinds, heat ramp, key/layer/off LED, or added/changed/removed.

**Materials and Liquid Glass.**
- Native toolbar glass: the ⌘K field platter and the prominent glass Build button.
- Liquid Glass for the floating palette and the stage controls (lens badge, legend, legend-mode switch), via one FloatingSurface/StageGlass modifier. That modifier draws a solid frosted surface under Reduce Transparency, and also in snapshots.
- The HUD uses `.glassEffect` tinted with the layer colour.
- The menu bar panel is a material panel.
- Readouts sit in recessed wells; the drawer is solid and calm.

**Motion.**
- The LCD layer segment slides to the new physical layer (matchedGeometry spring).
- Live pips pulse outward.
- Pressed keys depress (scale 0.93 spring) and glow in the layer colour.
- The drawer snaps open and closed.
- The HUD fades in over 120 ms and out over 180 ms.
- Reduce Motion turns off the pulses and press scaling.

### Limitations

**Runtime coverage.** I did not open the interactive app on screen in this session, so I wouldn't take over a Mac you may be using. It is verified by a clean build and by --selftest (38 headless checks through the real model and key routing):
- navigation, the picker, ranking, undo/redo, the palette and Oryx import;
- Record mode, layers, painting, combos and sparse settings;
- the simulated build→flash, and live simulation with Follow.

These are compiled but untested at runtime: toolbar item layout and hit-testing, menu shortcuts, MenuBarExtra, the HUD NSPanel, drag-resize, hover states, rotated-thumb hit-testing and first-responder edge cases.

**Snapshot fidelity versus the live app.**
- Liquid Glass can't be composited offscreen. The palette, stage controls and toolbar field show frosted near-opaque approximations, deliberately branched on isSnapshot so they read like frosted glass rather than PrototypeKit's flat grey fill. There is no blur, refraction or specular light.
- Prominent glass in the toolbar renders as plain glass offscreen, so Build & Flash is drawn as an accent capsule in snapshots only.
- The HUD scene uses ImageRenderer glass: tinted and translucent, but no real backdrop blur.
- Real menus, popovers and context menus (the layer-tab menu) and the actual menu-bar placement are not captured. The menu bar panel is rendered on its own at 360×500.
- Animations are frozen; the pulses, the sliding layer segment and press springs are not visible.

**Mock data.**
- The device is a frozen or looping script.
- The WPM, sparkline and "today" counts are synthetic.
- The heatmap period switch does not change the data.
- The interactive document is the user's real layout plus PrototypeKit's sample combos. Macros are a sample library; one is assigned to Brd+Sys k17 only in scene 16.

**Stubs.** Export CSV, Swap, Add frontmost app, Record steps / Test macro, editing macro steps (selection and inspector are display-only), changing combo output, Open in browser, the Navigator/animation layer-select settings, and the RGB-takeover toggle.

**Assumptions.**
- The reset pinhole is drawn mid-top-edge of the left half, from the guidance text; its exact position is not verified.
- Record mode maps ANSI key codes only.

**Small windows.** At the 1240×780 minimum, compact fallbacks kick in (icon-only slot footers, L0/L1/L2 in the LCD, unlabelled toggles) and the board shrinks to about 42 pt keys. That shrink comes only from the window size, never from panels.

### Next steps

1. Run it interactively on a real display:
   - tune glass tints and translucency over the stage;
   - check toolbar spacing with real glass;
   - test focus handling between the board, the label field and the palette;
   - verify hit-testing on rotated thumbs and drag-paint feel.
2. Make the board a real focusable element: visible keyboard focus, and VoiceOver labels per cap ("Z, tap, hold Left Option, key 19"). Audit contrast for the bright layer colours in light mode.
3. Finish the stubs:
   - macro step editing (drag to reorder, delay field, record steps from physical keys);
   - combo output picker (reuse the palette's assign scope);
   - drag to swap keys;
   - CSV export through a save panel;
   - an "Add frontmost app" rule.
4. Add a tap-dance demonstration key and a modifier-chord example, so every key kind shows on the real layout.
5. Replace the mock with CoreHID for the live layer, presses and status LEDs, and RGB takeover for the Colours preview. Handle "in use by Keymapp" in the strip.
6. Add drag-to-reorder for the title-bar layer tabs, and multi-select with bulk paint and bulk transparent.
7. Measure the real reset-pinhole location for the guide.
8. Compare side by side with INSTRUMENT and CHART TABLE. Candidates to keep from Console whatever the winning shell:
   - the drawer-picks-the-board-lens idea;
   - side-by-side slot columns;
   - the LCD live strip;
   - ⌘K as the keycode picker.
