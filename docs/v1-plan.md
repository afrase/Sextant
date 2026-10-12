# v1 plan

Planned 2026-10-12 from ui-spec §13.5 and the code at c7f8422. Each slice is implemented, reviewed, verified and merged on its own branch. Open questions for the user are at the end; answers go in the slice ADRs.

## Summary

v1 is about 21 slices in 5 waves. Sizes: 3 S, 9 M and 9 L (two of them close to XL).

**Wave 0 can start as soon as the three in-flight worktrees merge.** It needs no user answers and no hardware. Those worktrees touch LayersSection, PalettePanel, KeycodePicker, KeyCap and LayoutWindowModel, and they claim ADR 0036. Wave 0 builds the shared groundwork once, so later slices only add new files plus one-line hooks:
- page routing, a board pick mode and assign targets;
- every new issue kind, EditSession extension hooks, and a cap decoration hook;
- the raw-HID command channel and un-debounced press feed;
- the "which layout is on the keyboard" lookup;
- the settings generator for the 12 settings that make today's MVP builds refuse (ADR 0030's gap), plus the real-toolchain compile of JRGQm, m9dpx and XlrR4 under the pin.

**Waves 1 and 2 are document features.** None of them sends anything to the keyboard. They reach it only by flashing, and each flash needs the user's OK.
- Wave 1: tap dance checks and per-key tapping term, the Macros page, Save Revision and History, exports and Print (this also builds the MVP's unfinished Export items), and the Keyboard and Advanced panes.
- Wave 2: the Combos lens, multi-select with copy, paste and Copy Layer To, all the firmware settings, and the first keyboard write (Move Keyboard to Layer plus ⌃⌥0–9). History's Flash This Revision and Export Source Zip also land in wave 2.

**Waves 3 and 4 are live features.** They build and test against FakeKeyboardLink, FakeDeviceWatcher and FakeHID. They do nothing in the app until live access is turned on.
- Wave 3: the menu bar extra with the activation policy, the overlay HUD, the RGB preview, and Select Key by Pressing It.
- Wave 4: the Heatmap and App Layers.

**What gets sent to the keyboard** (32-byte reports, report ID 0). Three things write:
- `04 01 n` (SET_LAYER): the menu bar tiles, the layer shortcuts, the Keyboard menu and App Layers.
- `05 01`, `09 r g b`, `06 i r g b` and `05 00`: the RGB preview.
- A DFU flash: Flash This Revision, through the existing guards.

Everything else only reads the events that come after the pairing handshake (FE, 00, 01). The pinned firmware (fork 93b2b9e, modules 13890cd) already supports every v1 feature. The only generator work is the settings mapping and three small refusals for dances, macro steps and combo members. The five goldens must stay byte-identical.

**Two MVP leftovers are in the plan** because v1 needs them: the shared exporter (Layout JSON, QMK Source zip, Firmware bin) in wave 1, and Main Window ⌘0, which the menu bar slice turns on. Still out of the plan: Next and Previous Issue, Flash Oryx's Build of This Revision, and the Help menu.

All user-facing text is Sextant's own, in US spelling ("LED Color"), with no ZSA descriptions or trade dress. App-aware switching is called "App Layers", never "Smart Layers".

ADR numbers 0037–0054 are assigned per slice, assuming the in-flight workflow lands only 0036.

I didn't build or run anything: the plan rests on the four reader maps, spot-checked against the code (Destination, the Lens menu, the KeyboardLink signature, the disabled menu items, PackageLibrary's formatVersion refusal, the RealToolchainTests arguments, the in-flight worktree diffs). The biggest risk: the RGB preview leaves its colors on the board if Sextant crashes, and App Layers is the first feature that writes to the keyboard without a click each time.

## Wave 0: groundwork (no hardware, no user answers needed)

Every v1 page, lens and live feature collides on the same few spots. Those are: the Bool `showsFirmwareSettings` (26 uses in 10 files), the exhaustive `LayoutIssue.Kind` switch in KeyText, EditSession's private `edit`/`target`, KeyCap, and the receive-only KeyboardLink port. Doing those changes once lets later slices add new files with one-line hooks. The five slices are disjoint and none touches the keyboard. Start after the three in-flight worktrees merge, because 0.1 and 0.2 edit their files.

### 0.1 Pages, board pick mode and assign targets (M)

- Replace `LayoutWindowModel.showsFirmwareSettings` with `destination: Destination` and declare every v1 page now: `.layer(Int)`, `.firmwareSettings`, `.combos`, `.macros`, `.history`, `.appLayers`. WindowDetail and InspectorColumn route the unbuilt pages to EmptyView. They have no sidebar row yet, so nobody can reach them; each feature slice later adds its row and swaps its one route line.
- Combos and Changes are board modes driven by the destination, not `Lens` cases. `Lens.allCases` drives View ▸ Lens (⌃⌘n), the canvas picker and the palette, and spec §9.1 lists only Keys, Lighting and Heatmap.
- Update LayerCommands ⌘1–9 and the palette's setting rows to use `destination`.
- Board pick mode as a value: prompt text, an `onPick(index) -> Bool` closure and cancel. BoardView taps go to it first, the LensLane shows its capsule, and the Esc ladder cancels it (§9.3 step 4). Combos (choosing members) and Macros (Assign to Key) then never edit BoardView.
- Palette assign target as a value: scope-token text, an optional key to preview, and an assign closure. Today's key-slot assignment becomes the default value. Combo output, macro step and '3 keys' targets are then built in their own slices without editing the picker.
- Move NavigatorDisc out of BoardView.swift into its own file; Export, LayerMap and the HUD reuse it.
- Tests: destination routing; Esc cancels a pick; a target that isn't a key never changes the selected key; window snapshots stay pixel-identical.

**Owns:** `Sources/SextantUI/Sidebar/Sidebar.swift`, `Sources/SextantUI/Sidebar/LayoutPagesSection.swift`, `Sources/SextantUI/Window/LayoutWindowModel.swift`, `Sources/SextantUI/Window/WindowDetail.swift`, `Sources/SextantUI/Inspector/InspectorColumn.swift`, `Sources/SextantUI/Commands/LayerCommands.swift`, `Sources/SextantUI/Picker/KeycodePicker.swift`, `Sources/SextantUI/Picker/PalettePanel.swift`, `Sources/SextantUI/Board/BoardView.swift`, `Sources/SextantUI/Board/NavigatorDisc.swift (new)`, `Sources/SextantUI/Canvas/LensLane.swift`, `Sources/SextantSnapshots/Scenes+Import.swift`, `Tests/SextantUITests/LayoutWindowModelTests.swift`, `Tests/SextantUITests/PaletteTests.swift`, `Tests/SextantUITests/ImportSliceTests.swift`

**Shared touches:** Rebase after the palette-dismissal worktree (PalettePanel, KeycodePicker, EditCommands, LayoutWindowModel) and the layer-rename worktree (LayersSection) merge. Regenerate Localizable.xcstrings at merge.

**Hardware:** No. Pure UI.

**ADR:** 0037 Document pages, board pick mode and assign targets (amends 0028), shared with 0.2

### 0.2 Shared model hooks: issue kinds, EditSession extensions, cap decoration (S)

- Add every v1 `LayoutIssue.Kind` in one pass, each with Sextant's own text in `KeyText.issueText`: a dance slot that can't run in a dance; a per-key term ignored because the setting is off; a duplicate combo trigger; a combo member that is transparent or a tap dance; a combo outside 2–6 keys; rolling neighbors (warning); a macro step code with no send_string alias.
- Add a combo locator to LayoutIssue. Delete the dead `.tapDanceUnsupported`.
- No producers yet. Each feature later adds its own check function plus one call line in `check`.
- EditSession: make `edit(...)` and `target(...)` internal, so each feature adds `EditSession+<Feature>.swift` instead of editing EditSession.swift.
- Add `EditorSelection.combo: String?`. The undo Snapshot already carries the selection.
- KeyCapModel decoration hook, shared by the Changes, Combos and Heatmap modes: dimmed (40–45%), a ring color, a corner mark as plain data (symbol, color, accessibility text) with the §4.8 priority (issue > diff > combo number > LED dot or index), and an optional fill for heat. The defaults draw exactly today's caps.
- Tests: undo restores the combo selection; the corner-priority unit test; board snapshots stay pixel-identical.

**Owns:** `Sources/SextantDomain/Model/LayoutIssues.swift`, `Sources/SextantUI/Board/KeyText.swift`, `Sources/SextantApplication/EditSession.swift`, `Sources/SextantUI/Board/KeyCap.swift`, `Tests/SextantDomainTests/LayoutIssuesTests.swift`, `Tests/SextantApplicationTests/EditSessionTests.swift`, `Tests/SextantUITests/KeyTextTests.swift`, `Tests/SextantUITests/BoardSnapshotTests.swift`

**Shared touches:** KeyCap.swift, KeyTextTests and the board snapshot references are being changed by the activator-glow worktree, so branch after it merges.

**Hardware:** No.

**ADR:** 0037 (with 0.1)

### 0.3 Live command channel and press feed (M)

- `KeyboardCommand` (application): `.moveToLayer(Int)`, `.lighting(Bool)`, `.setLED(index:r:g:b:)`, `.setAllLEDs(r:g:b:)`.
- Port: `KeyboardLink.session(with:board:commands: AsyncStream<KeyboardCommand>)`. RawHIDLink merges commands into its existing private `Input` stream. It sends only in the `.live` phase and keeps the 5 ms pacing.
- Encoding (32 bytes, report ID 0): `04 01 n`, `05 01` / `05 00`, `06 i r g b`, `09 r g b`. Refuse layer >= 32 (oryx.c shifts 1UL << n) and LED >= the board's key count (52) without writing.
- Parse `08 <state>` into `LiveEvent.lighting` (no stop byte) and `FF <code>` into `LiveEvent.error`.
- `LiveSession.send(_:) throws(DeviceError)`, failing when not live, when access is off, or when Keymapp holds the board; plus `canSend`.
- `LiveSession.activity()`: key-down (index, layer) and layer events tapped before the 60 Hz debounce, so taps under 16 ms survive; silent during secure input.
- RefusingKeyboardLink refuses commands, and FakeKeyboardLink records them.
- Never sent: 03, 08 (brightness steps), 07, 0A, 0B, 0C.
- No UI and no callers yet.

**Owns:** `Sources/SextantApplication/Ports/Device.swift`, `Sources/SextantApplication/LiveSession.swift`, `Sources/SextantDevice/RawHIDLink.swift`, `Sources/SextantApp/HardwareGate.swift`, `Sources/SextantSnapshots/Scenes+Device.swift`, `Tests/SextantApplicationTests/DeviceFakes.swift`, `Tests/SextantApplicationTests/LiveSessionTests.swift`, `Tests/SextantApplicationTests/FlashModeClaimTests.swift`, `Tests/SextantDeviceTests/RawHIDLinkTests.swift`, `Tests/SextantUITests/DeviceAndBuildTests.swift`, `docs/architecture.md (§3.1 port table)`

**Shared touches:** The port signature change reaches every KeyboardLink conformer and fake. It lands in wave 0 so nobody else is editing them.

**Hardware:** Not to build: everything is tested on FakeHID, and nothing calls send in the app yet. Trying any command on the Voyager needs SextantLiveAccessEnabled turned on (pairing writes FE, 00, 01), plus the user's OK in chat for each category: SET_LAYER `04 01 n`, and RGB takeover `05`/`06`/`09`.

**ADR:** 0038 Live keyboard commands: what may be sent, when (a user gesture or an enabled rule, never at launch), clamps, release paths (amends 0012, 0022, 0023, 0034)

### 0.4 Which layout the keyboard runs (OnKeyboard) (S)

- `OnKeyboard` (application, `@MainActor @Observable`, app-wide) resolves the library entry, revision and layout from `LiveSession.firmwareSerial`. The serial comes from read-only USB enumeration, so this works with live access off.
- An Oryx serial maps to the import revision whose `layout.oryx.serial` matches.
- An `sx-` serial maps to the working copy when FirmwareIdentity matches it, otherwise to the newest matching flash revision.
- Anything else gives nil.
- It refreshes on serial change, library refresh and flash, and never shows unflashed edits as being on the keyboard.
- A serial-to-revision helper beside FirmwareIdentity, used by History's ON KEYBOARD badge.
- Built once in the composition root and passed in SextantServices.
- Tests with InMemoryLibrary: an Oryx serial; an sx- serial after later edits; an unknown serial.

**Owns:** `Sources/SextantApplication/OnKeyboard.swift (new)`, `Sources/SextantApplication/FirmwareIdentityRule.swift`, `Sources/SextantUI/SextantServices.swift`, `Sources/SextantApp/SextantMain.swift`, `Tests/SextantApplicationTests/OnKeyboardTests.swift (new)`, `Tests/SextantApplicationTests/FirmwareIdentityTests.swift`, `Tests/SextantApplicationTests/InMemoryLibrary.swift`

**Shared touches:** One line each in SextantMain and SextantServices.

**Hardware:** No. It reads the USB serial from read-only enumeration.

**ADR:** 0039 The keyboard's layout is the flashed revision, never unflashed edits

### 0.5 Firmware settings generator, part 1 (L)

- First, close ADR 0030's gap. Today, changing any of these on the MVP page makes every build refuse:
- debounce → DEBOUNCE
- tapCodeDelay → TAP_CODE_DELAY
- oneShotTapToggle → ONESHOT_TAP_TOGGLE
- the 9 Navigator options: rotation, scroll-only, the aim, turbo and drag-scroll layers as C arrays, aim divider, turbo multiplier, one-shot automouse and its timeout
- Then the settings whose define is clear in the pinned fork:
- retroTapping, holdOnOtherKeyPress
- tappingForceHold → QUICK_TAP_TERM 0 (TAPPING_FORCE_HOLD is gone from the fork)
- AUTO_SHIFT_MODIFIERS and NO_AUTO_SHIFT_*
- MOUSEKEY_*, with #undef first
- RGB hue and value steps; rgbUsbSuspend → #undef RGB_MATRIX_SLEEP
- NO_USB_STARTUP_CHECK; LAYER_LOCK_IDLE_TIMEOUT (seconds to ms)
- disableNKRO, lowPollingRate
- Leave refused (ADR 0020) until decided: liveTraining and stenography. Space Cadet and legacyDualFunctionDances move to slice 2.3, because they touch QMKGenerator.swift and QMKCodes.
- Table test: each setting off its default writes its define, and the default writes nothing. Switch `refusesSettingsAndNavigatorOptionsItCantWrite` to a setting that stays refused. The 5 goldens stay byte-identical.
- This slice owns RealToolchainTests' argument list for all of v1. Add JRGQm, m9dpx and XlrR4 (dances, combos, macros and a per-key term, never compiled under pin 93b2b9e), plus an every-setting-changed layout with a trackpad and with a trackball. Run with SEXTANT_REAL_TOOLCHAIN=1 on the already-installed toolchain, so nothing new is downloaded.

**Owns:** `Sources/SextantBuild/QMKConfig.swift`, `Sources/SextantBuild/KeymapSource.swift`, `Sources/SextantBuild/KeymapTemplates.swift`, `Tests/SextantBuildTests/QMKGeneratorTests.swift`, `Tests/SextantBuildTests/RealToolchainTests.swift`, `docs/research/02-firmware-and-flashing.md (§12 item 5)`

**Shared touches:** None in wave 0. Oryx never showed its output for about 6 of these: tapCodeDelay's value, NKRO, polling, aim divider, turbo multiplier and one-shot automouse. They follow question 4, and the rest of the slice doesn't wait for it.

**Hardware:** No raw HID. Settings reach the board only through a flash, and each flash needs the user's OK. The trackball options can't be tried (the user has a trackpad).

**ADR:** 0040 Firmware settings mapping (amends 0020 and 0030)

## Wave 1: document features I (no hardware)

These are the biggest gaps that need no keyboard. Tap dances and per-key terms finish the key editor. Macros and History are new pages built on wave 0's hooks. Exports bring the app's first file panel, which the MVP's own Export items and History's Export Source Zip need. The Settings panes create the switches the live features read. Each slice mostly adds new files; the shared files get one-line hooks.

### 1.1 Tap dances and per-key tapping term (M)

- A domain predicate for 'can run inside a dance' (KeyAction+Dance.swift). `KeymapPlan.token` uses it, and a test checks that it agrees with `QMKCodes.statements` across the whole catalog.
- A dance issue producer flags the slot when it holds a macro, an RGB color key, a QK_ or firmware key, or TG/TT/OSL/LM/DF/OSM, or when the tap isn't a KC_ key. Today these fail only at build time; §7.5 wants them caught first.
- Hide the no-op `dancesTapAction` row, since Oryx's output is the same either way. Record why in the ADR.
- Per-key term, domain operation: store nil at the global term; copy the value to keys with identical actions; bound it to 0…1000.
- `EditSession+TappingTerm`: 'Set Tapping Term' is one undo step and also turns `perKeyTappingTerm` on.
- An imported term while the setting is off raises the warning issue.
- Key inspector row (§5.1 item 7): Global or Custom, a field with a 10 ms stepper, and the delta from global. It shows when the key has a hold, double tap or tap-then-hold slot; test the slots, not `kind`.
- Remove 'tap dance before generator support' from spec §7.5.
- Tests:
- issues land on the right slot, and the 7 fixtures raise none;
- one undo step restores both the term and the setting;
- goldens e5Rrr, JRGQm and XlrR4 unchanged;
- snapshots of a flagged dance slot and a Custom term, light and dark.

**Owns:** `Sources/SextantDomain/Model/KeyAction+Dance.swift (new)`, `Sources/SextantDomain/Model/Layout+TappingTerm.swift (new)`, `Sources/SextantApplication/EditSession+TappingTerm.swift (new)`, `Sources/SextantUI/Inspector/TappingTermRow.swift (new)`, `Sources/SextantUI/Inspector/KeyInspector.swift`, `Sources/SextantBuild/QMKCodes.swift`, `Sources/SextantUI/FirmwareSettings/FirmwareSettingsPage.swift`, `Tests/SextantUITests/KeyInspectorTests.swift`, `Sources/SextantSnapshots/Scenes+Inspector.swift`

**Shared touches:** QMKGenerator.swift (`KeymapPlan.token` only; Macros edits the macro emitter). LayoutIssues.swift (one call line in `check`). LayoutIssuesTests and QMKGeneratorTests get added cases. ui-spec §7.5.

**Hardware:** No raw HID. Dance timing and terms can only be felt after a flash, which needs the user's OK each time.

**ADR:** 0041 Tap dance checks and per-key tapping terms

### 1.2 Macros page (L)

- Library model:
- Assigned macros stay inline, in Oryx's shape, and are listed by locator (key or combo).
- Unassigned macros go in a new optional drafts field in layout.json, written only when non-empty. Every existing content hash, the 'Edited' baseline and the sx- fingerprint stay the same.
- Only packages that contain drafts get formatVersion 2. An older build then refuses them (`.newerFormat`) instead of silently dropping the drafts.
- Domain operations (Layout+Macros.swift):
- new, rename and delete a macro;
- insert, delete, duplicate and move steps;
- set a step's code, modifiers and delay; the options;
- assign to a key (the tap becomes the macro and the hold is cleared); unassign.
- A predicate for codes that can be macro steps. The issue producer flags step codes with no send_string alias, and the generator refuses them; today MO or a QK_ code inside SS_TAP is a compile error.
- `EditSession+Macros`: one named undo step per operation. EditorSelection gains macro and step.
- UI per §6.3:
- MacrosPage: library list, editor header, timeline lane, step Table, options, preview, lock footer;
- MacroStepInspector, whose key tile opens the picker filtered to step-safe codes;
- Record Steps, reusing KeyRecorder's local monitor (Esc stops; delays rounded to 10 ms);
- Assign to Key through the board pick mode;
- the picker's Macros category;
- the sidebar row with its count, the empty state, and palette Documents rows.
- Never log macro contents: they can hold secrets.
- Tests:
- the library over JRGQm (66 uses) and XlrR4 (Alt-code macros);
- codec round trip with drafts; content hash unchanged for every fixture; formatVersion behavior;
- undo names; step refusal; the recorder; goldens unchanged.
- Snapshots: JRGQm, XlrR4, empty state, step inspector, recording, assign capsule; light and dark; 1120×640.

**Owns:** `Sources/SextantDomain/Model/Layout+Macros.swift (new)`, `Sources/SextantDomain/Model/OryxCodec.swift`, `Sources/SextantStorage/PackageLibrary.swift`, `Sources/SextantApplication/EditSession+Macros.swift (new)`, `Sources/SextantUI/Macros/ (new: MacrosPage, MacrosModel, MacroTimeline, MacroStepInspector)`, `Sources/SextantUI/Picker/KeyRecorder.swift`, `Sources/SextantSnapshots/Scenes+Macros.swift (new)`, `Tests/SextantDomainTests/LayoutCodecTests.swift`, `Tests/SextantDomainTests/MacroTests.swift (new)`, `Tests/SextantStorageTests/PackageLibraryTests.swift`, `Tests/SextantUITests/KeyRecorderTests.swift`, `docs/architecture.md (§6 format)`

**Shared touches:** One-line hooks only:
- Layout.swift (one stored field) and LayoutIssues.swift (one call line);
- QMKGenerator.swift (the macro emitter only);
- EditorSelection (two fields);
- LayoutPagesSection (one row), WindowDetail and InspectorColumn (one route line each);
- KeycodePicker (the Macros category and one Documents line);
- Scenes.swift (one line).

**Hardware:** No raw HID. Record Steps uses the Mac's keyboard through an NSEvent local monitor (no TCC prompt). Macros reach the board only through a flash, with the user's OK each time.

**ADR:** 0042 Macro library and the layout format (drafts field, formatVersion 2 only when drafts exist)

### 1.3 Save Revision and History (L)

- File ▸ Save Revision… (⌘S): a sheet with a message prefilled from the diff ('Edited 5 keys on Brd+Sys'). Disabled when nothing changed since the last revision.
- LayoutDiff gains settings, combos (compared by content, because combo ids aren't stable), Navigator flags and per-layer counts.
- `EditSession+History`, restoreRevision:
- reuses the checkpoint helper extracted from applyImport;
- is one undo step and keeps the title;
- appends a .save revision 'Restored revision 3'.
- `EditSession+History`, also:
- recordRevision closes BuildFlashSession.record()'s shortcut, so a flash of an older build shows up in `revisions`;
- revisionLayout(id), cached in HistoryModel (an extension can't add the cache's stored property).
- History page, model and inspector:
- HistoryModel: comparison with the parent, Current, On keyboard, or Choose…;
- HistoryInspector: a timeline with ORYX, LOCAL and ON KEYBOARD badges (ON KEYBOARD through OnKeyboard), details, a per-layer bar, a changes table, and Restore.
- History page, around the board: the Compare-with header, the lane capsule, the change-count context strip, the sidebar row with its count, the empty state, and revisions in the palette.
- Changes board:
- BoardView reads one display layout (the revision plus its diff) and keeps the session's geometry, so keys never move;
- editing gestures are off;
- caps use the wave-0 decoration hook (badges, ring, unchanged keys at 40%);
- a 'Changed keys' rotor.
- Deferred to 2.5: Flash This Revision…, Export Source Zip…, and the firmware size delta.
- Tests:
- LayoutDiff tests;
- saving moves the baseline; restore checkpoints unsaved edits, is one undo step, and leaves the document unchanged when a library write fails;
- recordRevision; HistoryModel defaults; the prefill text.
- Snapshots: the History window in light, dark and at 1120×640; the save sheet; the diff board with Increase Contrast and Differentiate Without Color.

**Owns:** `Sources/SextantDomain/Model/LayoutDiff+Summary.swift (new)`, `Sources/SextantApplication/EditSession+History.swift (new)`, `Sources/SextantApplication/BuildFlashSession.swift (record() only)`, `Sources/SextantUI/History/ (new: HistoryModel, HistoryInspector, SaveRevisionSheet, ChangesStrip)`, `Sources/SextantUI/Board/BoardView.swift`, `Sources/SextantUI/Canvas/CanvasColumn.swift`, `Sources/SextantUI/Canvas/ContextStrip.swift`, `Sources/SextantSnapshots/SnapshotTool.swift (fixture: an edited revision)`, `Sources/SextantSnapshots/Scenes+History.swift (new)`, `Tests/SextantDomainTests/LayoutDiffTests.swift (new)`, `Tests/SextantUITests/HistoryModelTests.swift (new)`, `Tests/SextantApplicationTests/BuildFlashSessionTests.swift`

**Shared touches:** One-line hooks only:
- FileCommands (the ⌘S line, next to 1.4's Export submenu) and WindowPresentations (the sheet);
- LensLane (the capsule);
- LayoutPagesSection, WindowDetail and InspectorColumn;
- one KeycodePicker Documents line; Scenes.swift.
This is wave 1's only big BoardView edit.

**Hardware:** No. ON KEYBOARD uses the USB serial from read-only enumeration and works with live access off.

**ADR:** 0043 History: comparisons (badge direction against Current), restore, recorded flashes

### 1.4 Exports and Print (M (L with SVG))

- One shared exporter: a fileExporter plus a FileDocument per content type. It also finishes the MVP's disabled Export items:
- Layout JSON;
- QMK Source (.zip): generated through the FirmwareGenerator port, zipped with NSFileCoordinator .forUploading, no library;
- Firmware (.bin): the last build's image.
- A static BoardImage: title and shown layer, with KeyCap, BoardCanvas and NavigatorDisc; no selection, issues or presses; light appearance.
- PNG at 2x through ImageRenderer.
- A vector PDF with one page per layer, through ImageRenderer into a CGContext PDF.
- Print Layout… (⌘P) runs PDFKit's printOperation as a sheet. Add PDFKit to the UI import rule in .swiftlint.yml.
- SVG only if the user wants it (question 6): hand-written from BoardLayout frames, with every label XML-escaped. Legends lose their SF Symbols.
- No ZSA art. The exported board is Sextant's own geometry.
- Tests:
- PNG pixel size; PDF page counts (3 for KlgM7, 12 for JRGQm);
- the zip holds GeneratedSource's files; the JSON round-trips;
- (with SVG) it parses and escapes a hostile label;
- a BoardImage snapshot reference.
The user checks ⌘P in the app.

**Owns:** `Sources/SextantUI/Export/ (new: BoardImage, LayoutExport, PrintLayout, optional BoardSVG)`, `Sources/SextantUI/Commands/SextantCommands.swift`, `.swiftlint.yml`, `Tests/SextantUITests/LayoutExportTests.swift (new)`

**Shared touches:** FileCommands (the Export submenu, next to 1.3's ⌘S line), WindowPresentations (the exporter presenter, next to 1.3's sheet), one exporter-state line in LayoutWindowModel, one line in Scenes.swift.

**Hardware:** No. The firmware export only writes a file.

**ADR:** 0044 Exports and Print (shared exporter, PDF in place of or alongside SVG, PDFKit in the UI layer)

### 1.5 Keyboard and Advanced Settings panes (M)

- Keyboard pane (§8.9):
- 'Show key presses on the board' (on by default), also as a Device popover toggle;
- 'Follow the keyboard by default' (on): LiveSession gets an injected `followsOnConnect` closure, read live;
- an Overlay group (on/off, delay 0–500 ms in 10 ms steps with 150 the default, position, size S/M/L, tint, toggled-layer Full / Reminder / Nothing), backed by overlay setting enums the HUD shares;
- the Form scrolls.
- Advanced pane, the raw-HID log ('Developer raw-HID log (positions only)', off by default):
- an in-memory RawHIDTrace ring buffer of about 500 reports;
- fed by an optional trace sink in RawHIDLink that is wired only while the setting is on;
- shown as a disclosure in the Device popover that can be copied, which also covers the deferred Event monitor;
- cleared when turned off; never written to disk or os_log.
- Advanced pane: 'Reset all warnings', backed by a registry of one-time-note keys.
- Fix the heatmap retention default to the spec's 30 days (it is 90 today).
- Fix spec §2.1's pane names to match §8.9.
- Tests:
- with follow-by-default off, connecting leaves isFollowing false;
- the ring buffer cap and clear; the sink sees every report, trimmed at the stop byte;
- presses are hidden when the setting is off; Reset clears seenLiveDataNote.
- Snapshots: settings-keyboard in light and dark, settings-advanced, device-popover-trace.

**Owns:** `Sources/SextantUI/Settings/SettingsView.swift`, `Sources/SextantUI/Settings/KeyboardSettings.swift (new)`, `Sources/SextantUI/Settings/AdvancedSettings.swift (new)`, `Sources/SextantApplication/RawHIDTrace.swift (new)`, `Sources/SextantApplication/LiveSession.swift`, `Sources/SextantDevice/RawHIDLink.swift`, `Sources/SextantUI/Device/LiveWindow.swift`, `Sources/SextantUI/Device/DevicePopover.swift`, `Tests/SextantApplicationTests/RawHIDTraceTests.swift (new)`, `Tests/SextantUITests/SettingsTests.swift (new)`

**Shared touches:** Ports/Device.swift (HIDTraceEntry) and one wiring line in SextantMain. Branch after 0.3 merges, because it reshapes LiveSession and RawHIDLink.

**Hardware:** No. The panes send nothing. The trace only observes what the link already sends and receives, and it sees nothing while live access is off.

**ADR:** 0045 Keyboard and Advanced panes; raw-HID trace kept in memory only (amends 0023)

## Wave 2: document features II, plus the first keyboard write

Combos waits for Macros: its Choose Output takes a macro through the picker's Macros category. Multi-select changes EditSession's core key edits, so it runs once every other feature keeps its EditSession code in extension files. The settings UI and the second generator pass wait for the tap dance work (legacyDualFunctionDances reuses TapDanceSource). Move Keyboard to Layer is the smallest keyboard write and creates the LayerMap that the menu bar and HUD reuse. History's extras need 1.3 and 1.4's exporter.

### 2.1 Combos lens (L)

- Domain (Layout+Combos.swift):
- create a combo, delete it, toggle a member key, set its output, layer and name;
- issue producers: duplicate trigger set on the same layer, transparent or tap-dance members, more than 6 keys (`comboTooManyKeys`; `emptyCombo` already covers fewer than 2), and rolling neighbors from BoardGeometry neighbors (warning).
- Generator: refuse the bad members in KeymapPlan's combo loop.
- `EditSession+Combos`: one named undo step each, with selection by combo id.
- UI per §6.4:
- ring, number and 45% dimming through the cap decoration hook;
- ComboOverlay: 2 pt traces drawn only in the gaps, and output pills placed from BoardLayout polygons, never over a legend;
- creation mode: N or '+ New Combo', then clicks through the board pick mode, then Choose Output opens the picker as 'Combo 3 › Output' through an assign target.
- UI, the rest:
- the 'Active on' menu in the header, worded to match question 3's answer;
- lens-lane capsule, context-strip cards, and ComboInspector (trigger chips, output tile, Active on, a combo-term link to Firmware Settings, warnings);
- the 8 combo color tokens with a contrast test;
- VoiceOver labels ('in combo 2: J + K → Esc');
- sidebar row with count, empty state, palette Documents rows.
- Tests:
- edits, issues, and the remap when a layer is deleted;
- undo names; a combo made in Sextant emits COMBO() and COMBO_COUNT; goldens JRGQm and m9dpx unchanged;
- a geometry test that no pill intersects a legend across all 32 of JRGQm's combos;
- creation mode and the Esc ladder.
- Snapshots: JRGQm (dense) and m9dpx, creation, empty state; light and dark; 1120×640.

**Owns:** `Sources/SextantDomain/Model/Layout+Combos.swift (new)`, `Sources/SextantDomain/Board/BoardGeometry.swift`, `Sources/SextantApplication/EditSession+Combos.swift (new)`, `Sources/SextantUI/Combos/ (new: CombosModel, ComboInspector, ComboOverlay, ComboCards)`, `Sources/SextantUI/Theme/Tokens.swift`, `Sources/SextantSnapshots/Scenes+Combos.swift (new)`, `Tests/SextantDomainTests/ComboTests.swift (new)`, `Tests/SextantUITests/TokenContrastTests.swift`

**Shared touches:** One-line hooks or small hunks only:
- QMKGenerator.swift (the combo loop only) and LayoutIssues.swift (one call line);
- BoardView (one overlay layer; 2.2 edits the click handling);
- CanvasColumn header and ContextStrip (a mode branch);
- LensLane, LayoutPagesSection, WindowDetail and InspectorColumn (route lines);
- one KeycodePicker Documents line; Scenes.swift.

**Hardware:** No raw HID. Combos reach the board only through a flash, with the user's OK each time.

**ADR:** 0046 Combos: meaning of 'Active on', member rules, lens drawing

### 2.2 Multi-select, copy and paste, Copy Layer To (L)

- EditSession core:
- `EditorSelection.keyIndices`, with keyIndex kept as the anchor;
- select(keys:) and toggle(key:);
- add `targets()` next to `target(_:_:)`, which extension files (tapping term, macros) still call;
- every key edit loops inside one `edit` ('Make 3 Keys Transparent');
- `copyKeys`.
- BoardView:
- ⌘-click toggles a key; ⇧-click selects a range in reading order;
- one ring per selected key;
- arrows, Esc and drag collapse the selection to one key;
- Keys lens only;
- a VoiceOver 'Add to Selection' action.
- MultiKeyInspector ('3 keys'): a slot editor that applies to every selected key, plus Make Transparent, Disable, LED Color, Copy To Layer… and Clear Label.
- Key menus act on every selected key. The picker gets a '3 keys › Tap on Main' assign target.
- Copy and paste: `.onCopyCommand`, `.onCutCommand` and `.onPasteCommand` on the focused board, so text fields keep the standard behavior.
- Pasteboard data:
- a `com.sextant.keys` JSON flavor, plus a plain-string QMK expression flavor;
- the domain `CopiedKeys` validates at the trust boundary: size cap, board and key count, index range, labels clamped to 10 characters.
- Copy Layer To:
- `EditSession.copyLayer` keeps the target layer's id, title and color, and is one undo step;
- `appendLayer` for 'New layer';
- a shared submenu used by the Layer menu, the sidebar context menu and the layer inspector;
- crossing to another layout goes through `Library.copyLayer` only if question 8 says so.
- Tests:
- the existing single-key EditSession tests pass untouched;
- multi-key edits and copyKeys are one undo step each; undo restores the multi-selection;
- the range follows reading order;
- CopiedKeys round-trips JRGQm and XlrR4 and refuses hostile payloads;
- the pasteboard tests use a uniquely named NSPasteboard, never .general.
The user checks ⌘C and ⌘V in the app.

**Owns:** `Sources/SextantApplication/EditSession.swift`, `Sources/SextantDomain/Model/CopiedKeys.swift (new)`, `Sources/SextantUI/Board/KeyPasteboard.swift (new)`, `Sources/SextantUI/Inspector/MultiKeyInspector.swift (new)`, `Sources/SextantUI/Inspector/CopyLayerMenu.swift (new)`, `Sources/SextantUI/Inspector/KeyDragSwap.swift`, `Sources/SextantUI/Inspector/KeyColour.swift`, `Sources/SextantUI/Inspector/LayerInspector.swift`, `Sources/SextantUI/Sidebar/LayersSection.swift`, `Sources/SextantUI/Commands/KeyCommands.swift`, `Sources/SextantApplication/Library.swift`, `Tests/SextantDomainTests/CopiedKeysTests.swift (new)`, `Tests/SextantUITests/KeyPasteboardTests.swift (new)`, `Tests/SextantApplicationTests/LibraryManagementTests.swift`

**Shared touches:** BoardView (click handling and rings; 2.1 adds only an overlay), InspectorColumn (one routing branch), ContextStrip ('3 keys selected'), LayerCommands (the Copy Layer To line), LayoutWindowModel (the selected count), KeycodePicker (`keySlotTarget` becomes the '3 keys' default target, ADR 0037; the picker's Macros rows call `session.assignMacro` on the tap rather than `target.assign`, so route them for multi-key targets too), Resources/Info.plist (optional UTType). The only slice allowed to edit EditSession.swift itself in wave 2.

**Hardware:** No.

**ADR:** 0047 Multi-select, the keys pasteboard type, Copy Layer To

### 2.3 All firmware settings: the page and the second generator pass (L (with 0.5, the settings item is XL))

- Generator pass 2:
- legacyDualFunctionDances builds tap+hold keys that aren't mod-tap or layer-tap as dances (a KeymapPlan.token branch reusing TapDanceSource);
- enableSpaceCadet sets SPACE_CADET_ENABLE and lifts the SC_ refusal in QMKCodes;
- liveTraining and steno follow question 5.
- Page (§8.8):
- show every Voyager section (drop `isCore`);
- the animation picker (48 effects, with Sextant's own names);
- ⌘F search over titles, descriptions, ids and synonyms, with the match count; a new `Setting.synonyms` field in Sextant's own words;
- a 'Modified only' toggle.
- Coupling rules in `LayoutSettings.store`, shown inline: tappingTerm > 500 turns on permissiveHold; chordalHold sets excludeThumbs; the Auto Shift sub-toggles follow the master. A coupled change is one undo step, and so is Reset All.
- International toggles gate the picker's International category. Only locales with codes show (UK, US international); imported values are kept.
- No ZSA description text ships; the catalog summaries are already Sextant's own.
- Tests:
- coupling and synonym search; undo steps;
- legacy dances emit TD(); Space Cadet compiles under the real toolchain (take it out of QMKGeneratorTests' `stillRefused` and add one Mapping row; the every-setting layout is built from that table);
- keep `dancesTapAction` hidden (ADR 0041's `FirmwareSettings.hidden`) when dropping `isCore`, and out of the changed total, the sidebar badge and the Changed list; fold the plan's "0040 amended: dancesTapAction" into ADR 0041 rather than deciding it again;
- narrow `oneShotAutoMouseTimeout`'s navigatorKinds to the trackpad, so the page hides it on a trackball and setNavigator drops it (today it shows there, and turning it on stops the build by name);
- goldens unchanged.
- Snapshots: full page, search, Modified only, animation picker, trackball Navigator; light and dark; minimum size.

**Owns:** `Sources/SextantDomain/Settings/SettingsCatalogData.swift`, `Sources/SextantDomain/Settings/SettingsCatalog.swift`, `Sources/SextantDomain/Settings/LayoutSettings.swift`, `Sources/SextantApplication/EditSession+Settings.swift (new)`, `Sources/SextantBuild/QMKConfig.swift`, `Sources/SextantBuild/QMKCodes.swift`, `Sources/SextantUI/FirmwareSettings/FirmwareSettingsPage.swift`, `Sources/SextantUI/FirmwareSettings/FirmwareSettingsInspector.swift`, `Sources/SextantUI/Commands/EditCommands.swift`, `Sources/SextantSnapshots/Scenes+Settings.swift (new)`, `Tests/SextantDomainTests/LayoutSettingsTests.swift`, `Tests/SextantDomainTests/CatalogTests.swift`

**Shared touches:** QMKGenerator.swift (the token branch; 2.1 edits the combo loop), QMKGeneratorTests (Space Cadet: out of `stillRefused`, one Mapping row), KeycodePicker (International gating), Scenes.swift.

**Hardware:** No raw HID. Changes reach the board through a flash, with the user's OK each time. NKRO, polling, steno and the trackball can only be checked on the device or with a steno host.

**ADR:** 0040 amended: coupling rules, International, liveTraining, Stenography, dancesTapAction

### 2.4 Move Keyboard to Layer, LayerMap and global layer shortcuts (M)

- `OnKeyboard.moveKeyboard(toLayer:)` sends `.moveToLayer(n)` through `LiveSession.send`. It checks that n exists in the keyboard's layout (only layer 0 when the layout is unknown).
- A read-only LayerMap view: KeyboardLayout, layer and PressedKeys, with caps ringed in the layer color and the NavigatorDisc. Accessibility is one element: 'Sym+Num layer, keys down k24'.
- Keyboard ▸ Move Keyboard to Layer ▸ and the same menu in the Device popover. Items are disabled with a reason ('Live keyboard access is off').
- Global ⌃⌥0–9 through a HotKeys port and a use case, LayerShortcuts:
- off by default; register and unregister when the setting changes;
- report conflicts; never offer modifier sets that are only ⌥ or ⌥⇧ (macOS 15+ rejects them);
- make sure a global key and the app's menu item don't both fire for one press.
- Remapping:
- if question 7 is yes, through the library's recorder;
- otherwise a ~150-line Carbon adapter in a new SextantSystem target with its own lint rule, and a modifier-set picker.
- The shortcuts group goes in Settings › Keyboard.
- Tests: FakeHID bytes come from 0.3. Here:
- LayerShortcuts with FakeHotKeys and FakeKeyboardLink: off registers nothing, on registers 10, pressing 2 sends one `.moveToLayer(2)`, 7 on a 3-layer layout sends nothing, access off sends nothing and says why;
- menu enablement;
- snapshots layer-map-brdsys in light and dark.
The real hot-key adapter stays out of `swift test`, where it would grab ⌃⌥digits system-wide.

**Owns:** `Sources/SextantUI/Device/LayerMap.swift (new)`, `Sources/SextantUI/Device/MoveKeyboardToLayerMenu.swift (new)`, `Sources/SextantApplication/Ports/HotKeys.swift (new)`, `Sources/SextantApplication/LayerShortcuts.swift (new)`, `Sources/SextantSystem/CarbonHotKeys.swift (new; or the library adapter)`, `Sources/SextantUI/Commands/KeyboardCommands.swift`, `Package.swift`, `Tests/SextantApplicationTests/LayerShortcutsTests.swift (new)`

**Shared touches:** OnKeyboard.swift (one method), DevicePopover (one menu), KeyboardSettings.swift (one group, from 1.5), .swiftlint.yml, SextantMain and SextantServices (one line each), docs/architecture.md §1 and §3.1.

**Hardware:** Yes, before any try on the Voyager: it sends `04 01 <n>` (SET_LAYER, layer_move), one report per user action, only over a paired session. That needs SextantLiveAccessEnabled on, plus the user's OK in chat for SET_LAYER. Agents test only on fakes.

**ADR:** 0048 Moving the keyboard's layer and global layer shortcuts (hot-key home or library)

### 2.5 History extras: Flash This Revision, Export Source Zip, size delta (M)

- BuildFlashSession gets a layout override, so Flash This Revision… builds and records the chosen revision. record() already handles a build that differs from session.layout.
- Refuse Restore or Flash This Revision while a flash is writing.
- Export Source Zip… through 1.4's exporter.
- At record(), store Sextant's built image with `storeFirmware`, so a revision can show its firmware size delta. Hide the delta when no image exists.
- Tests: Flash This Revision builds and records the revision's layout through FakeGenerator, FakeToolchain and FakeFlasher; the zip holds the revision's GeneratedSource; the size delta appears and is hidden when missing.

**Owns:** `Sources/SextantApplication/BuildFlashSession.swift`, `Sources/SextantUI/History/HistoryInspector.swift`, `Tests/SextantApplicationTests/BuildFlashSessionTests.swift`

**Shared touches:** The Build & Flash sheet's entry point (LayoutWindowModel.build, one parameter).

**Hardware:** Flashing only, through the approved DFU path with every guard unchanged. Agents test on FakeFlasher. A real flash needs the user's OK in chat for that flash.

**ADR:** 0043 amended

## Wave 3: live features in the window and menu bar (built on fakes; do nothing in the app while live access is off)

These need wave 0's command channel and OnKeyboard, 1.5's settings, and 2.4's LayerMap and layer move. They read `05`, `06` and `07` events from a paired session, and the RGB preview writes. All are built and tested on FakeKeyboardLink, FakeDeviceWatcher and FakeHID, and can only be tried on the Voyager once the user turns live access on and approves each write category.

### 3.1 Menu bar extra and activation policy (L)

- SextantMark shape: a 60° arc with 7 ticks and an index arm. It is drawn into a template NSImage, because MenuBarExtra labels render only Image and Text.
- the layer digit is composed into the image;
- 50% alpha with no number when no keyboard is connected;
- the arc fills with a new `LiveSession.flashProgress`, in 5% steps;
- a non-template variant for the optional layer-color dot (off by default).
- A pure MenuBarLabelState that maps connection, layer and progress to the glyph and text.
- MenuBarPanel (360 pt, under 520 pt tall):
- header with status-LED pips taken from the layer bits;
- layer tiles for 4 layers or fewer, otherwise rows with ⌃⌥ hints, built from OnKeyboard;
- the LayerMap mini map, paused during secure input;
- the overlay switch, bound to 1.5's setting;
- native rows: Build & Flash… ⌘R with progress, Open Sextant ⌘0, Settings…, Quit.
- Panel states: no keyboard, flash mode, access off, held by Keymapp, unknown layout.
- An app-wide window request: open or bring forward the window of the keyboard's layout (`openWindow` then `NSApp.activate()`); a pending Build & Flash that the window consumes; enable Window ▸ Main Window ⌘0.
- Settings › General:
- 'Show in menu bar' (on by default; the spec gives no default);
- 'Keep Sextant in the menu bar when its windows are closed'.
- AppPresence:
- switches to .accessory only with 0 layout windows and both settings on;
- switches back to .regular before any open, and whenever either setting is turned off.
- Tests:
- label states; the tiles-versus-rows threshold (3 layers against JRGQm's 12); the panel height cap;
- request routing; the AppPresence policy and its call order; flashProgress.
- Snapshots of the panel as a plain view (tiles, list, no keyboard, access off, flashing; light and dark) and of the labels.
The user checks template rendering, dismissal and focus in the app.

**Owns:** `Sources/SextantUI/MenuBar/ (new: MenuBarPanel, MenuBarLabel, AppPresence)`, `Sources/SextantUI/Theme/SextantMark.swift (new)`, `Sources/SextantUI/SextantScenes.swift`, `Sources/SextantSnapshots/Scenes+MenuBar.swift (new)`, `Tests/SextantUITests/MenuBarTests.swift (new)`, `Tests/SextantUITests/AppPresenceTests.swift (new)`

**Shared touches:** LiveSession and BuildFlashSession (the flashProgress field, set next to isWritingFirmware), SettingsView (the General rows), SextantCommands (Main Window), LayoutWindow (window count and pending request), Scenes.swift.

**Hardware:** Reading needs live access on: pairing writes FE, 00, 01. Tile and row clicks send `04 01 <n>` through 2.4, under the same SET_LAYER approval. Nothing new is sent.

**ADR:** 0049 Menu bar extra and activation policy (default on, pre-rendered label, flashed revision shown)

### 3.2 Overlay HUD (L)

- Domain `LayerHold.classify(layout:layer:pressed:)` returns base, momentary(heldBy:) or locked.
- momentary: a pressed MO, LT hold, LM, held TT or OSL key that activates the layer;
- locked: anything else (TG, TO, DF, a tapped TT, a dance TO, a host SET_LAYER).
The keyboard reports only the highest layer and the physical positions, so this has to be inferred.
- OverlayModel (`@MainActor @Observable`, with an injected clock):
- the delay (default 150 ms); the full overlay or the 'Sym+Num locked' pill;
- hides on the holder's key-up even with no layer event, which covers the 03 O2 dedupe gap;
- hidden during secure input, and while a Sextant key window shows the same layer.
- OverlayPanel, an NSPanel subclass:
- nonactivating and borderless, level .statusBar, ignores the mouse, joins all Spaces and full-screen apps;
- canBecomeKey and canBecomeMain are false;
- sits on the pointer's screen and repositions when screens change;
- an 8 pt rise, or a fade under Reduce Motion.
- HUDView: LayerMap with keys ringed in the layer color; neutral glass with the optional 20% tint; opaque under Reduce Transparency.
- One setting backs the Device popover, Keyboard menu and menu bar switches.
- Lifetime: owned by the composition root, not by a window.
- 'Hidden in full-screen video' is a recorded deviation: CGDisplayIsCaptured is deprecated and the build treats warnings as errors.
- Tests:
- LayerHold over the goldens (KlgM7 MO holds; XlrR4 tap TO; JRGQm hold TO and TT; e5Rrr double-tap TO; m9dpx OSL);
- OverlayModel with TestClock (add the already-pinned Clocks product to SextantUITests; no download).
- Snapshots: the HUD in light, dark, tinted, sizes S and L, the pill, Reduce Transparency.
The user checks focus and click-through in the app.

**Owns:** `Sources/SextantDomain/Model/LayerHold.swift (new)`, `Sources/SextantUI/Overlay/ (new: OverlayModel, OverlayPanel, HUDView)`, `Sources/SextantSnapshots/Scenes+Overlay.swift (new)`, `Tests/SextantDomainTests/LayerHoldTests.swift (new)`, `Tests/SextantUITests/OverlayModelTests.swift (new)`

**Shared touches:** KeyboardCommands (the overlay line), DevicePopover (one toggle), LayoutWindow (reports key and layer), SextantMain or SextantScenes (lifetime), Package.swift (test dependency), Scenes.swift.

**Hardware:** Sends nothing. It reads `05`, `06` and `07` from a paired session, so it needs live access on. Until then it never appears.

**ADR:** 0050 Overlay HUD: momentary-or-locked inference, full-screen-video deviation

### 3.3 RGB takeover preview (M)

- Domain `KeyboardLayout.ledColor(layer:index:)`: the key's own color, else the layer color, else off. KeymapSource uses it, and every golden stays byte-identical.
- The LightingPreview use case:
- claims the lights for one window at a time;
- per frame, sends `09` with the most common color, then `06` for each LED that differs, then only diffs, latest wins per LED;
- applies brightness on the host (r, g, b × the slider);
- re-sends the frame after a reconnect.
- Release with `05 00` on toggle off, lens exit, layout switch, window close, sleep (NSWorkspace.willSleepNotification) and quit (a bounded wait in AppDelegate). On disconnect, release without sending. The toggle starts off at every launch.
- LightingInspector 'On the keyboard' section:
- the toggle, the Brightness slider, and Sextant's own footnote, which also mentions rgbTimeout and RGB being turned off;
- disabled states ('Needs live access', 'Previewing in <layout>').
- Keyboard ▸ Preview Lighting on Keyboard toggle.
- Tests:
- ledColor; goldens unchanged;
- with FakeKeyboardLink: the first frame is 09 then the 06 diffs; one painted key sends a single 06; brightness scaling; every release path sends 05 00; a second window's claim is refused; a reconnect re-sends; nothing is sent when not live.
- Snapshots: the inspector connected and disconnected, light and dark.

**Owns:** `Sources/SextantDomain/Model/Layout+LED.swift (new)`, `Sources/SextantBuild/KeymapSource.swift`, `Sources/SextantApplication/LightingPreview.swift (new)`, `Sources/SextantUI/Inspector/LightingInspector.swift`, `Tests/SextantApplicationTests/LightingPreviewTests.swift (new)`, `Tests/SextantUITests/LayersAndLightingTests.swift`

**Shared touches:** KeyboardCommands (the preview line), SextantMain (quit and sleep release), LayoutWindow (close releases), LayoutWindowModel (feeds frames), SextantServices, Scenes+Layers.swift.

**Hardware:** Yes, before any try on the Voyager: it sends `05 01` (expects the ack `08 01`), `09 r g b`, `06 i r g b` with i clamped to 0–51, and `05 00` on every release (expects `08 00`). Never 08, 07 or 0A. It needs live access on plus the user's OK in chat for RGB takeover. If Sextant crashes or the quit wait times out, the colors stay until the board is unplugged. Nothing is written at the next launch.

**ADR:** 0051 RGB takeover preview: claim, frames, release paths

### 3.4 Select Key by Pressing It (⇧⌘L) (S)

- A select-by-press mode in LayoutWindowModel that excludes Record Key and the palette.
- The next key-down from `LiveSession.activity()` calls `select(key:)` on the shown layer and announces 'Selected key 24 · ⏎'.
- A lane capsule: 'Press a key on the keyboard… esc cancels', with Cancel.
- A local monitor, shared with KeyRecorder, swallows Mac-side keyDown and flagsChanged while armed and until the selected key's raw-HID key-up. This keeps the same press out of type-to-search and the Esc ladder.
- The menu item is enabled only when the board shows and the link is live. Otherwise it is disabled with a help tag.
- The mode ends on resign-key or when the session drops.
- Tests (UI model, with fakes):
- row 5, col 0 selects key 24;
- a down and up within 16 ms still selects;
- Esc and Cancel end the mode; it excludes Record Key and the palette;
- presses are ignored during secure input.
- A snapshot of the capsule.

**Owns:** `Sources/SextantUI/Board/SelectByPress.swift (new)`, `Tests/SextantUITests/SelectByPressTests.swift (new)`

**Shared touches:** KeyCommands (the ⇧⌘L line), LayoutWindowModel (one state line), LiveWindow, KeyRecorder (the shared monitor), LensLane (the capsule), BoardView (Esc rung), Scenes+Picker.swift.

**Hardware:** Sends nothing new. It reads key-down events, which stream only from a paired session, so it needs live access on.

**ADR:** 0052 Select Key by Pressing It (extends spec §13.2's local-monitor exception)

## Wave 4: live features that work in the background (recording and automatic switching)

Both run without a click per action, and each needs its own privacy or consent ADR. The Heatmap stores typing positions. App Layers sends SET_LAYER whenever the frontmost app changes. Both need wave 0's channel and OnKeyboard, and App Layers reuses 2.4's layer move and LayerMap. Each adds one row to 3.1's menu bar panel (the app-rule row and the typing-stats line).

### 4.1 Heatmap lens and its recording (L)

- Domain:
- port KeyHeatmap from design/PrototypeKit (seed only, no dependency): counts by layer id and index, log intensity, top N;
- HeatmapStats: layer share, hand balance, per finger, layer holds;
- a `Finger` per key in BoardDefinition, from the generated table;
- CSV export with cells escaped against formula injection (the '=' legend exists), and JSON export.
- Application, HeatmapStore port and HeatmapRecorder (app-wide), which:
- counts key-downs from `activity()` against the last reported layer;
- records only when OnKeyboard resolves a library layout; skips during secure input;
- flushes every 60 s and at quit, and prunes by retention;
- does nothing until the Privacy toggle is on.
- Storage adapter: `Application Support/Sextant/Heatmap/<layoutUUID>/<yyyy-MM-dd>.json` with hourly buckets. It lives outside the .sextant packages, so exports and duplicates never carry typing data. Writes are atomic and damaged files are tolerated. Trashing a layout deletes its folder.
- UI, lens and board:
- `Lens.heatmap` (gets ⌃⌘3 automatically);
- heat ramp tokens with OKLab interpolation, a single blue hue flipped in dark mode;
- heat fill and a compact count ('22k') through the cap decoration hook, with the count in each cap's accessibilityValue.
- UI, around the board:
- the lane summary and context cards;
- HeatmapInspector: ranges, layer share, hands, a finger histogram, top 8, Export CSV and JSON, Clear;
- empty states; Clear Heatmap Data… in Privacy;
- the menu bar typing-stats line, shown only while recording is on.
- Tests:
- domain math and CSV escaping;
- the recorder with TestClock and fakes: off by default, key-downs only, by layer id, nothing during secure input or for firmware of another layout, flush, prune, clear;
- storage contract in a temp folder;
- heat-ramp contrast.
- Snapshots: light, dark, inspector, recording off, no data.

**Owns:** `Sources/SextantDomain/Heatmap/ (new)`, `Sources/SextantDomain/Board/BoardDefinition.swift`, `Sources/SextantDomain/Board/VoyagerKeys.swift (regenerated)`, `scripts/gen-board-definition.py`, `Sources/SextantApplication/Ports/Heatmap.swift (new)`, `Sources/SextantApplication/HeatmapRecorder.swift (new)`, `Sources/SextantStorage/HeatmapFiles.swift (new)`, `Sources/SextantUI/Heatmap/ (new: HeatmapInspector, HeatmapStrip)`, `Sources/SextantSnapshots/Scenes+Heatmap.swift (new)`, `Tests/SextantDomainTests/HeatmapTests.swift (new)`, `Tests/SextantApplicationTests/HeatmapRecorderTests.swift (new)`, `Tests/SextantStorageTests/HeatmapFilesTests.swift (new)`

**Shared touches:** One-line hooks or small hunks only:
- the Lens enum (the only v1 Lens case) in LayoutWindowModel;
- Tokens.swift and TokenContrastTests;
- LensLane, ContextStrip and InspectorColumn (mode branches);
- SettingsView Privacy (Clear);
- SextantMain, SextantServices and SextantScenes (one line each);
- MenuBarPanel (one row); Scenes.swift.

**Hardware:** Sends nothing new. Data exists only from a paired session, so it needs live access on, and recording stays off until the user opts in.

**ADR:** 0053 Heatmap recording and storage: opt-in, hourly aggregates, outside the packages, paused during secure input (amends 0023's 'never stored')

### 4.2 App Layers (L)

- Domain: AppLayerRule (bundle id, name, layer id, When leaving: Return to Main or Stay, enabled) and AppLayerRules (master switch). A pure decision function maps an activation to a target layer index.
- Storage: a sidecar `app-layers.json` in each package, through two new LayoutLibrary methods. It stays out of layout.json, so a rule edit doesn't change the content hash, the 'Edited' state or the sx- fingerprint. Duplicate and Trash carry it automatically.
- Application:
- a FrontmostAppWatcher port;
- an AppLayerSwitcher (app-wide) that sends `.moveToLayer(n)`, or `.moveToLayer(0)` when leaving a Return to Main app;
- skips the send when the keyboard is already on n; acts only on the latest activation;
- pauses when not live, when access is off, when Keymapp holds the board, or when another layout is flashed;
- keeps the last 20 switches (app names only) in memory.
- Adapter: an NSWorkspace watcher, in SextantApp beside HardwareGate, or in SextantSystem if 2.4 created it.
- UI: the App Layers page (the 'Switch layers when you change apps' toggle, a Now card with LayerMap, a rules Table, Add App… from running apps or Choose…), AppLayersInspector, the lane capsule, the sidebar row with its count, the empty state, and the menu bar app-rule row.
- The footnote is Sextant's own and says layer_move also drops toggled, one-shot and automouse layers. Never call the feature 'Smart Layers'.
- Tests:
- the decision table;
- the switcher with FakeFrontmostAppWatcher, FakeKeyboardLink and FakeDeviceWatcher: activation sends, leaving sends 0 or nothing, deduplication, last-wins, every pause case, the capped name-only history;
- sidecar contract: a missing file reads as empty, Duplicate copies it, the hash doesn't change;
- snapshots of the page, inspector and empty state, light and dark.

**Owns:** `Sources/SextantDomain/Model/AppLayerRules.swift (new)`, `Sources/SextantApplication/Ports/System.swift (new)`, `Sources/SextantApplication/AppLayerSwitcher.swift (new)`, `Sources/SextantApp/WorkspaceAppWatcher.swift (new)`, `Sources/SextantUI/AppLayers/ (new: AppLayersPage, AppLayersInspector)`, `Sources/SextantSnapshots/Scenes+AppLayers.swift (new)`, `Tests/SextantDomainTests/AppLayerRulesTests.swift (new)`, `Tests/SextantApplicationTests/AppLayerSwitcherTests.swift (new)`

**Shared touches:** One-line hooks or small hunks only:
- Ports/LayoutLibrary.swift and PackageLibrary.swift (two methods); InMemoryLibrary and PackageLibraryTests;
- LayoutPagesSection, WindowDetail and InspectorColumn (route lines); LensLane;
- SextantMain and SextantServices; MenuBarPanel (one row); docs/architecture.md §1 and §6.

**Hardware:** Yes, before any try on the Voyager: it sends `04 01 <n>` on app activation and `04 01 00` when leaving a Return to Main app; never `04 00 n`. It needs live access on plus the user's OK for SET_LAYER. In the shipped app, the master toggle and enabled rules count as consent (question 2), and nothing is sent at launch unless rules are on.

**ADR:** 0054 App Layers: sidecar rules and when SET_LAYER may be sent automatically

## Keeping merges clean

Rules that keep merges clean:

1. **Before wave 0.** Merge the three in-flight worktrees first: layer rename (LayersSection, ADR 0036), activator glow (KeyCap, KeyTextTests, board snapshot refs) and palette dismissal (PalettePanel, KeycodePicker, EditCommands, LayoutWindowModel). Slices 0.1 and 0.2 rewrite those files.

2. **Localizable.xcstrings.** Every slice touches it. Never hand-merge: take main's copy, then rerun scripts/strings after each merge.

3. **docs/decisions.md and docs/progress.md.** Slices write only their own ADR file, under the pre-assigned numbers 0037–0054. The merger adds the decisions.md row and the progress.md line, so these two files never conflict between branches. If the in-flight workflow takes more numbers than 0036, shift the numbers at merge.

4. **Pages (Destination).** Slice 0.1 declares every v1 page up front: combos, macros, history, appLayers and firmwareSettings. Each feature then adds one row in LayoutPagesSection and replaces its one EmptyView route line in WindowDetail and in InspectorColumn.

5. **Lens enum.** Only the Heatmap adds a case, and gets ⌃⌘3 automatically. Combos and Changes are board modes driven by the destination: `Lens.allCases` feeds View ▸ Lens, the canvas picker and the palette, and spec §9.1 lists only Keys, Lighting and Heatmap.

6. **EditSession.swift.** Slice 0.2 makes `edit` and `target` internal. Every feature puts its operations in `EditSession+<Feature>.swift`. Only 2.2 (multi-select) edits EditSession.swift itself, and it keeps `target(_:_:)` working next to `targets()`, because extension files already call it. EditorSelection only gains additive fields (combo in 0.2, macro and step in 1.2, keyIndices in 2.2).

7. **LayoutIssues and KeyText.** Slice 0.2 adds every new Kind and its Sextant-written text in one pass and deletes `.tapDanceUnsupported`. Each feature adds its own check function plus one call line in `check`.

8. **QMKGenerator.swift and the goldens.**
- Separate functions per slice: 1.1 `KeymapPlan.token` (dance predicate), 1.2 the macro emitter (step refusal), 2.1 the combo loop (member refusal), 2.3 a token branch (legacyDualFunctionDances).
- QMKConfig.swift belongs to 0.5, then 2.3.
- QMKGeneratorGoldenTests must stay byte-identical for every slice, including 3.3's ledColor refactor.
- RealToolchainTests' argument list belongs to 0.5 for all of v1; 2.3 adds Space Cadet through QMKGeneratorTests' Mapping table, which builds the every-setting layout.

9. **Layout.swift.** New domain operations go in new files: Layout+Macros, Layout+Combos, Layout+TappingTerm, LayoutDiff+Summary, Layout+LED. Layout.swift itself gets one stored field, for macro drafts.

10. **The layout format.** Only 1.2 changes layout.json: an optional drafts field, written only when non-empty, with formatVersion 2 only for packages that have drafts. App Layers uses a sidecar file and the Heatmap stores outside the packages, so content hashes and sx- fingerprints never move.

11. **KeyCap and BoardView.**
- Slice 0.2's decoration hook lets Changes, Combos and Heatmap fill in values from their own files without editing KeyCap: each adds one case to `LayoutWindowModel.capDecoration(layer:index:)` (LayoutWindowModel+Decorations.swift), which BoardView already reads.
- Slice 0.1's pick-mode hook and Esc rung let Combos and Macros avoid BoardView click code; it also moves NavigatorDisc out of BoardView.
- Only one slice per wave makes a big BoardView edit: 1.3 (the display layout for Changes) and 2.2 (click handling and rings). 2.1 adds only an overlay layer and 3.4 one Esc rung.

12. **Picker and palette.** Slice 0.1's assign-target value means Combos and Macros never edit the assign path; Multi-select edits only `keySlotTarget`. The Documents group gets one appended line each from Macros, History and Combos. International gating comes from 2.3.

13. **LayoutWindowModel.** Each feature keeps its state in its own `@Observable` model (MacrosModel, HistoryModel, CombosModel, overlay and heatmap models) behind one stored property. No feature logic goes in LayoutWindowModel.swift.

14. **Menus.** The placeholder lines already exist in FileCommands, KeyCommands, KeyboardCommands and SextantCommands. Each slice replaces only its own line. Where lines sit next to each other (Save Revision next to Export; Move Keyboard, Preview Lighting and Show Overlay together), the conflicts are trivial: merge them one after another.

15. **Composition root** (SextantMain, SextantServices, SextantScenes). One line per app-wide service: OnKeyboard, the trace, LayerShortcuts, the overlay, the lighting preview, the heatmap recorder, the app-layer switcher.

16. **Snapshots.** Each slice adds a `Scenes+<Feature>.swift` file and one `scenes += await x(f)` line in Scenes.swift. 1.3 owns the edited-revision fixture in SnapshotTool.

17. **Device code.** Slice 0.3 changes the KeyboardLink signature, which reaches every fake and Scenes+Device, in wave 0 before anyone else edits them. 1.5 must branch after 0.3 merges (LiveSession, RawHIDLink).

18. **Merge order within a wave.** Smallest and most isolated first, so the large slices rebase once:
- wave 0: 0.4, 0.2, 0.1, 0.3, 0.5;
- wave 1: 1.5, 1.1, 1.4, 1.2, 1.3;
- wave 2: 2.5, 2.4, 2.3, 2.1, 2.2;
- wave 3: 3.4, 3.3, 3.2, 3.1;
- wave 4: 4.1, 4.2.
Run scripts/check after every merge, not only per branch.

## Questions for the user

- **When will you turn on live access (SextantLiveAccessEnabled), and will you approve trying the two new write categories on your Voyager: moving its layer (SET_LAYER `04 01 n`) and the RGB preview (`05 01`, `09`, `06`, `05 00`)?**
  - Why: Waves 3 and 4 and slice 2.4 (menu bar, HUD, layer shortcuts, RGB preview, Heatmap, App Layers, Select Key) build and test on fakes. In the app they do nothing until live access is on, and agents may not send either command to the keyboard without your OK in chat for that category. Your answer decides whether those waves get tried on the keyboard as they land, or ship inert.
  - Recommendation: Build waves 0–2 first; they need no hardware. Turn live access on before slice 2.4 merges, so the first write (a single SET_LAYER from the Keyboard menu) can be tried with your OK. Approve RGB takeover separately when slice 3.3 is ready. If you'd rather keep it off, waves 3 and 4 still get built and tested, but stay inert.

- **Is it OK for App Layers to change the keyboard's layer automatically, with no click each time, once you've turned on its master switch and at least one rule?**
  - Why: Every other write is a direct user action. App Layers sends SET_LAYER whenever the frontmost app changes. That is a new consent model under the hardware-safety rule, and it decides whether slice 4.2 gets built as the spec describes.
  - Recommendation: Yes, with limits: - the master switch plus an enabled rule counts as consent; - nothing is sent at launch unless rules are on; - it pauses whenever the keyboard runs another layout, Keymapp holds it, or live access is off; - each layer is checked against the flashed layout. Record this in ADR 0054.

- **Combos' 'Active on': keep Oryx's meaning (a combo uses the keycodes at those positions on the chosen layer and fires wherever those keycodes are), or make it a true per-layer restriction?**
  - Why: QMK combos are keyed by keycode. A real per-layer restriction needs COMBO_SHOULD_TRIGGER code and stops matching Oryx's output, which breaks golden parity for JRGQm and m9dpx. It also decides the wording in the header and inspector.
  - Recommendation: Keep Oryx's meaning for golden parity, describe it honestly in Sextant's own words, and record it in ADR 0046. Offer the real restriction later, if ever.

- **For the firmware settings whose output Oryx's samples never showed (tap code delay, NKRO, polling rate, the trackball's aim divider and turbo multiplier, one-shot automouse), should Sextant use its own mapping, or should I fetch more public Oryx layouts that set them?**
  - Why: Fetching means read-only GraphQL calls plus /source zip downloads. It adds more ZSA-derived samples that must be stripped before any public push. Using Sextant's own mapping means a layout with those settings may build slightly differently from Oryx. This changes slices 0.5 and 2.3.
  - Recommendation: Use Sextant's own mapping, proved by unit tests and a real-toolchain build with every setting changed (ADR 0040). It needs no downloads and adds no ZSA material.

- **Which settings may v1 leave out or limit: liveTraining (Oryx's live-training switch), Stenography, and International beyond UK and US-international?**
  - Why: Turning liveTraining off probably drops the zsa/oryx module, which would break Sextant's live view, Keymapp and the RGB preview. Steno is useless without the 44 steno keycodes, which Sextant's catalog lacks. 36 International toggles exist, but Sextant only has UK and US-international keycodes. Each choice changes slice 2.3.
  - Recommendation: Hide liveTraining and keep it always on. Hide Stenography until steno keycodes exist. Show International only for locales Sextant has codes for, and use those toggles to gate the picker's International category, keeping imported values. Also hide the no-op 'dances tap action' row. Audio and enableNavigator stay hidden, so about 95 settings show for the Voyager.

- **Is SVG export required, or can a vector PDF stand in for it (PNG + PDF + Print)?**
  - Why: Foundation has no SVG writer, so SVG means a hand-written exporter, about one size step more work (M → L). Its legends lose SF Symbols, which degrade to text or Unicode arrows. The PDF comes free from the print path and stays vector with the real legends.
  - Recommendation: Ship PNG, a vector PDF and Print in slice 1.4. Leave SVG out of v1 unless you need it for something specific.

- **May I add sindresorhus/KeyboardShortcuts (MIT, pinned to an exact version; a package download) for the ⌃⌥0–9 layer shortcuts and their remapping?**
  - Why: ADR 0018 says to prefer established libraries, but to ask before adding one. Without it, I write a small Carbon adapter in a new SextantSystem target, and 'remappable' shrinks to a modifier-set picker (⌃⌥, ⌃⌥⌘, ⌃⇧, ⇧⌥⌘). The library also brings a recorder, so each layer's shortcut can be remapped. This changes slice 2.4's targets.
  - Recommendation: Yes, adopt the library behind the HotKeys port. The App Layers NSWorkspace watcher then lives in the SextantApp composition root, and no new target is needed. If you'd rather not add a dependency, the Carbon adapter with a modifier-set picker covers the spec's minimum.

- **Copy Layer To…: only within the same layout, or also into another layout in your library?**
  - Why: The spec doesn't say. Crossing layouts adds a Library path that goes through the other layout's open window or a temporary session, and takes slice 2.2's part from S to M. Layer keys such as MO(2) keep their index and may point at the wrong layer in the other layout.
  - Recommendation: Within the same layout for v1: replace an existing layer's keys, or add a new layer. Across layouts later, if you find yourself wanting it.
