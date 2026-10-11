# Design judging

Three directions were built as runnable SwiftUI prototypes on a shared kit (`design/PrototypeKit`) and judged through three lenses. The UI spec (`ui-spec.md`) is synthesised from these results.

| Lens | Winner |
|---|---|
| MAC-NATIVE CRAFT | Instrument (a-instrument) |
| Task flow and usability | Console (c-console) |
| Visual delight and identity | Chart Table (b-chart-table) |

## Mac-native craft

**Scope:** MAC-NATIVE CRAFT: would Apple ship this? Judged on HIG conformance on macOS 26, correct Liquid Glass (glass on controls and navigation, never on content; GlassEffectContainer grouping; legibility), system controls, toolbar, sidebar and inspector conventions, SF Symbols, SF Pro and SF Mono, semantic colour and accent, light/dark parity, accessibility (contrast, Reduce Transparency, Reduce Motion, VoiceOver feasibility for the board), keyboard navigation, window resizing and minimum sizes, and menu bar extra and HUD conventions. Evidence: every snapshot of all three directions, a read of the live-path code (glass, commands, focus, accessibility), and new renders at each direction's declared minimum window size. Those renders were made in-process and offscreen in /Users/aaron/Developer/Sextant/design/judging/native-craft/minsize/out-{a,b,c}/.

**Winner:** Instrument (a-instrument)

### Instrument (a-instrument): 8

Sub-scores: higStructure 9, liquidGlassUsage 8, systemControlsAndTypography 7, lightDarkParity 9, accessibility 4, keyboardNavigation 8, windowingAndResizing 6, menuBarAndHUD 8

**Strengths**

- The structure is what Apple ships for a pro document app. It uses a real NavigationSplitView with an .inspector column, a native .toolbar using ToolbarSpacer, and navigationTitle/navigationSubtitle ('My MacOS Layout · Main · fw 25.0'), so the system draws the toolbar glass platters, the floating sidebar and the inspector column (01-main-dark, 02-main-light).
- Liquid Glass sits only where the HIG wants it: the system toolbar plus small floating capsules over the board. These are the Lighting tool capsule (06-led-paint), the LIVE capsule (10-live), the heatmap summary (13-heatmap), the error banner (19-error), the ⌘K palette (20-command-palette) and the HUD (12-overlay-hud). The sidebar, inspector, documents and sheets stay flat and dense, which is correct.
- The Xcode-style activity capsule in the principal slot carries device identity, serial, build/flash status and a progress hairline (07-flash-guide, 08-flash-progress, 19-error). It is a native-feeling home for status, and a future sync indicator fits there too.
- Build & Flash and Import use real .sheet presentations with a five-step indicator, a size meter, the pinhole guidance and a Cancel/primary pair (07, 08, 09). These are proper modal semantics.
- Firmware Settings is a native grouped Form (.formStyle(.grouped)) like System Settings. It has search, 'Modified only', 'Default X · Reset to Default' and an inspector listing the changed values with the defaults struck through (18-settings).
- The sidebar is a native List(.sidebar) with .onMove and a context menu for layers. It is the only direction with a Settings scene, which the brief requires for app preferences, and a full menu bar of commands (Product, Key, Layer).
- Undo is named in the Edit menu ('Undo Set Hold') and routes to the focused NSTextView first (Commands.swift undo()/redo()). Of the three, only this direction gets text-field undo right.
- Keyboard navigation uses SwiftUI focus: a .focusable() board with onKeyPress for the arrows, Return, Tab, Delete and Esc. Lenses use a native segmented Picker. Record Key uses local key events and needs no TCC.
- Light and dark have true parity. The deepened layer colours keep #00F0FF and #42FF00 legible on porcelain (02 vs 01).
- The HUD is a real nonactivating, click-through NSPanel (HUDController: .nonactivatingPanel, ignoresMouseEvents) with 'release to hide' (12). The MenuBarExtra uses .window style with a layer list showing ⌃⌥ shortcuts (11-menubar).

**Weaknesses**

- Accessibility is almost unaddressed. There are 0 accessibilityLabel/Element calls, so each KeyCap is unlabeled to VoiceOver. There are 0 Reduce Motion and 0 Reduce Transparency checks, even though the palette, capsules and HUD are glass.
- Text uses hand-tuned grey tiers instead of semantic label colours. text4 #B4B4B9 on white is about 2.1:1 and text3 #8A8A90 about 3.4:1, both below 4.5:1, and neither responds to Increase Contrast.
- The inspector buttons and pop-ups use a pure-SwiftUI BezelButtonStyle, a snapshot workaround that leaked into the live app. They are not stock NSButton/NSPopUpButton bezels.
- Build & Flash is a hand-drawn accent capsule with a drop shadow and .sharedBackgroundVisibility(.hidden), not .buttonStyle(.glassProminent).
- The declared minimum window size can't be reached. minWidth is 1180, but the render at 1180×720 came out 1367×720 because sidebar min 220 + inspector min 300 + centre exceed it. At 720 pt height, the inline picker pushes the modifier grid off the bottom of the inspector (minsize/out-a/04-keycode-picker.png).
- The key-kind channel is too quiet for 'meaning at a glance': a 4.5% tint plus a short bottom bar (01, 02). The 7–8 pt per-cap index numerals at about 30% alpha add noise and are on by default.
- There are three layer switchers at once: the sidebar rows, the centre layer strip and the toolbar layer menu (01). That is redundant chrome.
- The sidebar toggle is documented as ⌘0. The system shortcut is ⌃⌘S (View ▸ Hide Sidebar), and InspectorCommands provides the inspector toggle.
- The menu bar extra icon is static (keyboard.badge.ellipsis) and doesn't show the current layer.

**MustKeep**

- The NavigationSplitView + .inspector + native .toolbar skeleton, with navigationTitle/navigationSubtitle carrying the layout and layer (01-main-dark).
- The toolbar activity capsule (device · serial · status · progress hairline) as the single status surface for build, flash, errors and future sync (07, 08, 19).
- Real sheets for Build & Flash and Import, with the step indicator, the size meter and the A/B flash-mode guidance (07, 08, 09).
- Firmware Settings as a native grouped Form with search, Modified-only, Reset to Default and an inspector list of changed values (18-settings).
- A build error mapped to the key everywhere: capsule text, board banner with Show Key (⌘'), red cap ring and badge, and an inspector callout with one-click Fix (19-error).
- Glass restricted to small floating capsules over the board and to the palette/HUD, with documents and inspectors flat (06, 10, 13, 20).
- The key-across-layers strip under the board (01, 05) and the 'Transparent. Acts as Z from Main · Override on Sym+Num' callout (05-layer-symnum).
- Named undo in the Edit menu, routed to text fields first (Commands.swift).
- Lenses as a native segmented Picker with ⌃⌘1–4.
- The Settings scene for app preferences, and the MenuBarExtra(.window) panel with the layer list and shortcuts (11-menubar).

**MustFix**

- Make the board VoiceOver-operable. Give each KeyCap .accessibilityElement(children: .ignore), a label like 'Key 19, Z, hold Left Option, Main', .isSelected, and custom actions (Edit Keycode, Make Transparent, Record). Add an accessibilityRotor for layers and key kinds.
- Wire accessibilityReduceTransparency (opaque fills for the glass capsules, palette and HUD) and accessibilityReduceMotion (picker and palette become fades).
- Replace the Tone.text2/3/4 greys with .secondary/.tertiary label styles, or raise text3/text4 to at least 4.5:1, and honour colorSchemeContrast.
- In the live app, use stock .bordered/.borderedProminent buttons and Picker(.menu); keep the bezel style behind isSnapshot only.
- Make Build & Flash a Label inside .buttonStyle(.glassProminent) with .controlSize(.large), as Console does.
- Make the minimum size honest. Reconcile minWidth with the column minimums, or auto-collapse the sidebar below about 1360 pt. Make the inspector scroll so the picker never pushes slot controls off-screen at 720 pt height.
- Strengthen the kind channel with a real hold band carrying the hold action's glyph, as in Console 01 or Chart Table 20. Add a non-colour cue for Differentiate Without Color.
- Default the cap indices to off, or show them only on hover or selection.
- Drop the toolbar layer menu, or keep it only as the narrow-width fallback, so layer switching lives in the sidebar plus the strip.
- Use the system sidebar and inspector commands (⌃⌘S, InspectorCommands), not ⌘0 and ⌥⌘0.
- Make the MenuBarExtra label reflect the active layer, for example a layer-coloured index badge.

### Console (c-console): 6.5

Sub-scores: higStructure 6, liquidGlassUsage 7, systemControlsAndTypography 5, lightDarkParity 8, accessibility 5, keyboardNavigation 6, windowingAndResizing 7, menuBarAndHUD 8

**Strengths**

- It uses the correct macOS 26 toolbar API for the primary action: Build & Flash is .buttonStyle(.glassProminent) with .controlSize(.large), next to a glass ⌘K search field (01-main-dark; ConsoleWindow.swift).
- It is the only direction with a Reduce Transparency fallback. FloatingSurface draws a solid frosted panel when reduceTransparency is on. Reduce Motion is also honoured on keycaps and tabs.
- It honours the system accent colour (84 Color.accentColor uses).
- The function band on each cap shows what the hold does, with its glyph on a tinted band (⌥L on Z, cyan Sym+Num on ⏎). This is the clearest at-a-glance kind and hold signal of the three (01, 02).
- The minimum size is honest: the 1240×780 render came out exactly 1240×780. Compact fallbacks engage (icon-only slot footers), and the board never moves when the drawer opens (minsize/out-c/03).
- Flash-mode guidance is drawn on the real board, with numbered callouts on Space and Reset (07). The console log lines link to the failing key (19-error).
- The menu bar panel reads like a native menu, with rows carrying ⌘B, ⌘0 and ⌘Q equivalents plus Quit (11-menubar). The HUD is a tinted glass, nonactivating, click-through NSPanel (12).
- The side-by-side Tap/Hold/Double/Tap+Hold slot columns and the Through Layers stack make comparison easy (01, 03).
- Light and dark have good parity (02, 05, 14, 16, 18).

**Weaknesses**

- The Safari/Arc-style layer tabs in the title bar are custom, not native window tabs. ⌘T for New Layer collides with the macOS tab convention.
- There are two layer controls with different meanings. The title-bar tabs pick the editing layer and the LCD 'LAYER Main/Sym+Num/Brd+Sys' track shows the physical layer. 15-history-diff shows the Brd+Sys tab selected while the LCD reads Main.
- There is no sidebar or inspector. A custom 10-tab drawer bar replaces them, a non-standard control in which Flash, Settings and History all live as drawer tabs, so Flash is not modal.
- SF Mono uppercase tracked section labels (TAP, HOLD, THROUGH LAYERS, LAYER ON THE KEYBOARD) and the LCD wells give a Raycast/DAW web-tool voice, not Apple's sentence-case SF Pro headers.
- Keyboard routing goes through a window-wide NSEvent local monitor with bare-letter shortcuts (R, [, ], /, ?). This bypasses the responder chain, Full Keyboard Access and VoiceOver key handling. There are 0 onKeyPress or focusable uses.
- ⌘Z always goes to the store (ConsoleCommands), so text fields lose their own undo.
- There is no Settings scene, and firmware settings are custom cards rather than a grouped Form (18-settings).
- The board gets about 55% of the window height. At the minimum size it shrinks to about 45 pt keys and slot titles truncate ('Left Opti…', minsize/out-c/03). The always-on live strip costs about 52 pt of height.
- There are 0 accessibility labels on caps.

**MustKeep**

- .buttonStyle(.glassProminent) for the toolbar Build & Flash (ConsoleWindow.swift BuildButton).
- The FloatingSurface pattern: real .glassEffect live, with a solid frosted fallback under accessibilityReduceTransparency.
- The cap function band that names the hold action with its glyph and target-layer colour (01, 02).
- Flash-mode callouts drawn on the actual Space and Reset keys (07-flash-guide).
- Build log lines that deep-link to the offending key (19-error).
- The menu bar panel's native-menu rows with key equivalents and Quit (11-menubar).
- The Aa/KC/# legend-mode switch as a small floating control (01).
- Honest minimum size with compact fallbacks that never move the board.

**MustFix**

- Replace the custom title-bar tabs with sidebar rows or a native segmented control, and move New Layer off ⌘T.
- Show one layer concept at a time. Fold the physical-layer readout into the toolbar status (Follow on/off) instead of a second three-way track.
- Move to focus-based key handling (.focusable + onKeyPress) and drop bare-letter global shortcuts, or scope them to the focused board.
- Route ⌘Z to the first-responder text field before the document store.
- Use SF Pro sentence-case section headers, and keep SF Mono for codes, bytes and ms only.
- Make Build & Flash a sheet. Move Key editing to an .inspector and keep the drawer for at most a few lenses, or drop it.
- Add a Settings scene, and render firmware settings as a grouped Form.
- Add VoiceOver labels and actions to caps.
- Collapse the live strip into the toolbar status to give the board more height.

### Chart Table (b-chart-table): 5.5

Sub-scores: higStructure 4, liquidGlassUsage 6, systemControlsAndTypography 5, lightDarkParity 8, accessibility 4, keyboardNavigation 7, windowingAndResizing 5, menuBarAndHUD 5

**Strengths**

- It is the most Liquid-Glass-forward composition, in the macOS 26 Maps/Freeform idiom: floating glass status cluster, layer dock and tool dock over an opaque canvas (01-main-dark, 02-main-light).
- It is the only direction that uses GlassEffectContainer (ChartGlassGroup) so the dock capsules merge and morph, and it uses interactive glass (.interactive()) for controls.
- Reduce Motion is handled thoroughly. ChartMotion.spring/snappy/gentle(reduce) swap springs for 0.15–0.2 s fades in 8 places.
- The keycode picker floats over the other half and live-previews the highlighted code on the target key. ⌘⏎ assigns and advances (04-keycode-picker, 21-keycode-search). This is the best picker interaction of the three.
- Record Key has an explicit 'Listening for a key…' tile with Cancel (22-record-key). The hold band on caps shows what holding does (20-key-hold-edit-dark).
- The board's frame is derived only from the window size, so it truly never moves. Paper and night charts give striking, consistent light and dark parity.

**Weaknesses**

- The window chrome is custom. There is no NSToolbar (.windowStyle(.hiddenTitleBar) plus titlebarAppearsTransparent and titleVisibility .hidden), and no sidebar or inspector. That loses toolbar customisation, standard sidebar and inspector commands, and the system toolbar glass.
- The system accent colour is ignored: 0 Color.accentColor uses, with chart blue #1F6FEB/#4C9BFF hard-coded for selection and primary actions.
- Liquid Glass is used for content-heavy surfaces: the Firmware Settings panel with its section list and rows (18-settings), the key editor card (03), the Paint and Live shelves (06, 10) and the Flash HUD (07). There is no Reduce Transparency fallback (0 hits).
- The menu bar extra uses the 'safari' SF Symbol, a restricted Apple-product symbol that reads as Safari. The panel header repeats it (11-menubar).
- There is no Settings scene. Flash and Firmware Settings are custom centred overlays, not sheets or windows, so they lack standard modal, Esc and default-button semantics and VoiceOver modality.
- New York serif is used for UI chrome, the legend and custom-label keycaps ('Back', 'Prev Tab' in serif among SF legends, 04 and 23). The low-contrast italic marginalia and the decorative isobaths, graticule and compass will fight legibility under real glass.
- At the declared minimum width the editor card falls back to a callout that covers neighbouring keys (minsize/out-b/23-custom-label-edit.png at 1120 pt). Content also forced the height to 772 pt, above the declared 740.
- The overlay HUD is not wired as an NSPanel. The undo group replaces text-field undo. Only 2 accessibilityLabel uses, and none on caps.

**MustKeep**

- GlassEffectContainer grouping with interactive glass for floating control clusters (Glass.swift ChartGlassGroup).
- The ChartMotion(reduce) helper: every spring degrades to a short fade under Reduce Motion.
- The keycode picker that live-previews the highlighted code on the target key, with ⌘⏎ assign-and-advance and ⇥ to cycle categories (04, 21).
- The hold band on caps showing the hold action (20-key-hold-edit-dark).
- The explicit Record Key listening tile with Cancel and Esc (22-record-key).
- Background flashing: 'Hide' keeps the flash running with progress on the toolbar status (07).
- A board frame computed only from window size, never from panels.

**MustFix**

- Use Color.accentColor, or the tint environment, for selection and primary actions.
- Restore a native NSToolbar and window title. Put editing in a native .inspector or popover rather than a glass card.
- Take glass off content panels: settings as a window or sheet with a grouped Form, flash as a sheet, shelves as an inspector. Add a Reduce Transparency fallback to ChartGlass.
- Replace the 'safari' menu bar symbol with a neutral, non-Apple-product symbol that reflects the current layer.
- Add a Settings scene for app preferences.
- Use SF Pro for chrome and keycaps. Keep New York, if at all, to one decorative title, and drop italic low-contrast marginalia.
- Tone the isobaths, graticule and compass down, or switch them off under Increase Contrast, so glass over them stays legible.
- Fix minimum-width behaviour so the editor never covers keys, and make minHeight honest (content forces 772 pt).
- Wire the overlay HUD as a nonactivating, click-through NSPanel.
- Add VoiceOver labels and actions to caps, and keep text-field undo.

**Grafts proposed**

- From Console: replace Instrument's hand-drawn Build & Flash capsule with Console's Label in .buttonStyle(.glassProminent) and .controlSize(.large) (c-console ConsoleWindow.swift BuildButton).
- From Console: adopt the FloatingSurface modifier, real .glassEffect with a solid frosted fallback under accessibilityReduceTransparency, for Instrument's lens capsules, ⌘K palette and HUD (12, 20).
- From Console: replace Instrument's thin kind bar and 4.5% tint with Console's function band, which names the hold action with its glyph and target-layer colour (c-console 01/02, e.g. ⌥L on Z, cyan Sym+Num on ⏎). Keep Instrument's 1 pt layer ring for the layer channel.
- From Console: in Instrument's Build & Flash sheet step 2, also draw numbered callouts on the real Space and Reset keys of the board behind the sheet, or in the sheet's close-up (c-console 07-flash-guide).
- From Console: make build-log lines deep-link to the offending key in Instrument's sheet log and in the error callout (c-console 19-error).
- From Console: menu bar panel rows with key equivalents (Build & Flash… ⌘B, Open Sextant, Quit ⌘Q) added to Instrument's 11-menubar layout. Make the MenuBarExtra label show the active layer.
- From Console: the Aa/KC/# legend-mode switch as a small floating glass control on the board, instead of hiding QMK codes and indices behind ⌥⌘C/⌥⌘I only.
- From Chart Table: in Instrument's inline picker, live-preview the highlighted keycode on the target cap and add ⌘⏎ assign-and-advance and ⇥ to cycle categories (b-chart-table 04, 21).
- From Chart Table: the ChartMotion(reduce) helper pattern so every Instrument animation (picker expand, palette scale, pressed-key glow, HUD) degrades to a 0.15–0.2 s fade under Reduce Motion.
- From Chart Table: wrap adjacent floating glass (the Lighting tool capsule plus status chip, the LIVE capsule) in a GlassEffectContainer with .interactive() glass, so they group and morph like system glass.
- From Chart Table: a 'Hide' button on the Build & Flash sheet that lets the flash continue in the toolbar activity capsule, Xcode-style, instead of a modal the user must sit through (b-chart-table 07).
- From Chart Table: the explicit Record Key 'Listening…' tile with a Cancel button in the slot area, not only a button-label change (b-chart-table 22, c-console 21).

**Rationale**

Instrument wins on native craft, and it isn't close. It is the only direction that is built from the macOS 26 system frame rather than painted over it:
- a NavigationSplitView with a native sidebar List, .onMove and context menus;
- an .inspector column;
- a native .toolbar using ToolbarSpacer, with title and subtitle in the title bar;
- real .sheet modals for Build & Flash and Import;
- a grouped Form for firmware settings, like System Settings;
- a Settings scene, which the brief requires;
- full menu commands, with named undo routed to text fields first;
- focus-based onKeyPress board navigation.

Its Liquid Glass usage is also the most HIG-correct. The system supplies the toolbar glass, and app-drawn glass is limited to small capsules floating over the board plus the palette and HUD; documents and inspectors stay flat. Light/dark parity is excellent (01 vs 02). Its main debts are fixable in place:
- accessibility: 0 VoiceOver labels, and no Reduce Motion or Reduce Transparency handling;
- hand-tuned text greys below 4.5:1;
- a snapshot-workaround bezel style leaking into live controls;
- a hand-drawn rather than .glassProminent primary button;
- a declared minimum width (1180) that the column minimums make unreachable (renders at 1367);
- a key-kind signal too faint to read at a glance.

Console ranks second. It has the best accessibility hooks (a Reduce Transparency fallback, Reduce Motion), uses the correct .glassProminent API, honours the accent colour, keeps its minimum size honest and has the clearest cap function band. But the structure is not Mac-native: Safari-style tabs in the title bar, two competing layer controls, a 10-tab custom drawer standing in for sidebar and inspector, a window-wide NSEvent monitor with bare-letter shortcuts, and a mono, uppercase web-tool type voice.

Chart Table is the most beautiful and the most Liquid-Glass-forward, with the best picker interaction and Reduce Motion discipline. Apple would not ship its chrome, though:
- the title bar and toolbar are hidden;
- the system accent colour is ignored;
- glass is spread over content-heavy panels (settings, flash, shelves, the editor card) with no Reduce Transparency fallback;
- the Apple-product 'safari' symbol is used as its menu bar icon;
- there is no Settings scene;
- serif type is used in the UI chrome and on keycaps;
- at minimum width the editor card covers keys (verified render).

Recommended path: build on Instrument's skeleton. Graft in Console's .glassProminent button, Reduce Transparency surface, function band, on-board flash callouts, log-to-key links and menu-bar rows. Graft in Chart Table's live-preview picker with ⌘⏎ assign-and-advance, its Reduce Motion helper, GlassEffectContainer grouping and background-able flash. Then pay down Instrument's accessibility and contrast debt before anything ships.

## Task flow and usability

**Scope:** Task flow and usability. I walked the 10 core tasks in each direction and counted the clicks, keystrokes, mode changes and hidden steps. I also judged discoverability against power, keyboard-first operation, layout stability, error and empty states, information density, and how well each scales to the v1 features. I read all 64 snapshots and confirmed two claims in code: Instrument's board moves (BoardEditor.swift:25, BoardRender.swift:66) and Chart Table's Wake trail shows typed text (Chrome.swift:320-356).

**Winner:** Console (c-console)

### Console (c-console): 8.2

Sub-scores: tapHoldEdit 9, assignLayerKey 9, findKeycodeFast 8, switchManageLayers 8, seeInherited 9, paintLEDs 9, buildFlashSafely 9, liveDeviceState 9, macroCombo 9, findSetting 7, discoverability 8, keyboardFirst 9, layoutStability 8, errorEmptyStates 9, density 7, v1Scaling 7

**Strengths**

- Tap and hold has the least friction of the three. The four slots sit side by side (01, 03), so you compare them without switching tabs. Setting a home-row mod takes four clicks: key, Hold column, Modifier, then ⌥L. The board stays fully visible the whole time.
- Assigning a layer key is two clicks with no popups: Hold → Layer → 'While held, activate' chip (01). The palette also offers the concrete action 'Hold for Sym+Num MO(1)'. Layer numbers match QMK (L0, L1, L2 and 'LAYER 1 · HOLD RETURN').
- Inherited keys are explained in three places. The 'Through layers' column shows the same position on every layer with fall-through arrows. The centre readout says '47 own · 5 inherited' (05). A transparent key's Tap slot becomes '+ Override · Transparent: uses Main' (04, 21).
- Live state is always visible. The live strip shows connection, the physical layer, the 4 status LEDs and keys down above every task (01, 10). The status bar says 'Board runs 40xJ7M' or 'Board is 1 build behind' (06), which tells you whether a flash is needed.
- Flashing guidance is drawn on the user's own board: numbered callouts on Space (1) and Reset (2) plus the pinhole marker (07). During the write, the strip turns into a progress line, the board dims as offline, and Cancel is disabled (08). The build log sits beside it.
- Errors map back to the key in four places: a red ring and badge on the key, a callout in the centre gap, the drawer card with the compiler excerpt and 'Fix & rebuild', and log lines that link to 'Brd+Sys k45' (19). The Flash tab carries a red badge.
- Macros and combos are edited without losing the board. The Macro tab (16) has a library list, a proportional time lane, a step inspector and the plaintext warning, with the assigned key highlighted on the board. Combos (17) are picked on the board, with layer-scope chips and a warning that J and K are rolling neighbours.
- The Colours tab (06) is the best LED flow. Brush, Fill, Pick and Erase each have a single-key shortcut (B, G, I, E), each stroke is one undo step, painted keys are listed grouped by colour with per-colour remove, and there is a live RGB-takeover preview.
- Most keyboard-first of the three. With no query, ⌘K suggests actions for the selected key ('Edit Hold · Left Option · 2', 20). It also offers ⇥ to change slot, ⌘↵ to assign and advance to the next key, R to record, [ and ] to step layers, and 1–4 for slots. The status bar keeps hints visible ('⌘K palette · ↵ edit key · ⌘J drawer').
- Empty states teach: '+ Add double-tap · Tap twice quickly · tap dance' and '+ Add tap then hold' (01).

**Weaknesses**

- The drawer is too short for long documents. Settings (18) shows only about 3 setting cards, and the section rail is cut off at 'Stenography'. History and Macro are similarly cramped. Getting more room means dragging the handle, which shrinks the board, so the promise that the board never moves holds only while the user accepts a cramped drawer.
- The keycode picker (04) covers almost the whole board, including the target key k12. Unlike Chart Table's picker, it gives no live preview on the board.
- The primary 'Build & Flash' button looks the same while flashing (08) and after a failed build (19). Only the strip and the drawer show the state, so the toolbar never says Stop, Building or Failed.
- The LCD 'LAYER Main | Sym+Num | Brd+Sys' track looks like a segmented control but is read-only (LiveStrip.swift:157). It sits right beside the editor's layer tabs. In 04, 05 and 21 the tab reads Sym+Num while the LCD reads Main, and nothing explains the difference between the editor layer and the physical layer.
- Entry points are redundant and the drawer is crowded. Heatmap is both a strip toggle and a drawer tab, there are already 10 drawer tabs, and at the 1240 pt minimum width the compact fallbacks hide labels.
- The event monitor (10) shows typed letters (D, L, R, O) for every press. Raw HID sees passwords typed in any app, so this is a privacy problem.
- The WPM sparkline and activity numbers spend chrome on decoration while the user is editing.

**MustKeep**

- Four slots side by side, each with its own Change/Record/Clear (or Pick/Record when empty) and an empty state that explains itself (01, 03).
- The 'Through layers' column with fall-through arrows, plus '+ Override' on a transparent slot (04, 05).
- A persistent live status line: connection, physical layer, status LEDs, keys down and 'Board runs <rev> / N builds behind' (01, 06, 10).
- Flash guidance drawn as numbered callouts on the real Space and Reset keys, with the board dimmed as offline during the write (07, 08).
- Error mapping in four places, with log lines that link to the key and a one-click 'Fix & rebuild' (19).
- A context-first ⌘K: slot actions for the selected key, commands with shortcuts, settings with live values, and an Oryx link that offers 'Import as new / Replace (undoable) / Compare' (09, 20).
- The Colours tool rail with B/G/I/E shortcuts and painted keys grouped by colour (06).
- The macro library, proportional time lane and step inspector, with the board kept visible (16). Combo picking on the board with layer scope and the rolling-neighbour warning (17).
- The REC badge on the armed key, with Esc never captured (21).

**MustFix**

- Give long documents room without silently shrinking the board. Use snap heights for the drawer, or a deliberate 'expand drawer' or pop-out window for Settings, History and Macros (18).
- The picker must leave the target key visible and preview the highlighted keycode on it. Float it over the opposite half, as Chart Table does (04).
- Make the primary toolbar button reflect build and flash state: Building…/Stop, then progress, then Failed (08, 19).
- Either make the LCD layer track an explicit 'Move keyboard to layer' control or restyle it as a plain readout. Label the editor layer and the physical layer as different things.
- Mask keystroke content in the event monitor. Show the key index and position, never the letter, by default, and pause while Secure Event Input is active (10).
- Cut duplicate entry points (Heatmap appears twice) and plan the drawer tab bar for v1 growth, for example with an overflow menu or by grouping the document and device tabs.

### Instrument (a-instrument): 7.4

Sub-scores: tapHoldEdit 8, assignLayerKey 7, findKeycodeFast 6, switchManageLayers 8, seeInherited 9, paintLEDs 8, buildFlashSafely 7, liveDeviceState 7, macroCombo 8, findSetting 9, discoverability 9, keyboardFirst 7, layoutStability 6, errorEmptyStates 8, density 7, v1Scaling 8

**Strengths**

- The most discoverable of the three. The sidebar lists every surface (Combos 2, Macros 2, App Layers 4, History 4, Firmware Settings 9), the four lenses are a labelled segmented control, and the inspector buttons show their shortcuts (Record Key ⇧⌘R, Transparent ⌘⌫, Disable ⇧⌘⌫) (01).
- Best at explaining inheritance. A transparent key gets 'Transparent. Acts as Z from Main' with an 'Override on Sym+Num' button (05). The status bar reads 'KC_TRANSPARENT → MT(MOD_LALT, KC_Z)', and the key-across-layers strip shows the key on every layer.
- Firmware Settings (18) is the best place to find a setting. It is a full-height grouped Form with search, 'Modified only' and the default value, and the inspector shows changed counts per section plus a 'Changed (9)' list with the old default struck through. ⌘K also finds settings with their current values (20).
- The sidebar's pinned device card is always visible. It shows connection, LEDs, layer, the serial with a 'matches' check, and firmware and protocol (01). The live badge on the layer row shows the physical layer while you edit.
- Layer management is complete and discoverable: sidebar rows with key counts, drag to reorder, context menus, '+ Add Layer', and named undo for each step.
- Build errors appear in the capsule, as a board banner with Show Key, as a red ring on the key, and as an inspector callout with Fix (19).
- The Combos document (17) has a clear instruction under the board ('Click keys on the board to add them to or remove them from combo 1') and a table, so editing a combo is explicit.

**Weaknesses**

- The board moves. KeyStackStrip renders only when the lens is Keys and a key is selected (BoardEditor.swift:25), and BoardRender scales to min(width, height) (BoardRender.swift:66). So selecting a key, pressing Esc or switching lens moves the board about 29 pt (compare 01 with 06, 10 and 13). On a shorter, height-limited window the board would also shrink. This breaks the brief's principle 5 and the designer's own claim.
- Finding a keycode is cramped. The inline picker (04) shows 5 results in a 380 pt column, its 16 category chips are icon-only, it pushes the Modifiers and Key fields below the fold, it gives no preview on the board, and there is no assign-and-advance for rapid remapping.
- Setting a layer hold goes through two popup menus ('Hold for' and the target), plus a keycode field that also says 'Sym+Num MO(1)'. That is two controls expressing the same thing (01).
- There are three layer switchers (the layer strip, the sidebar Layers section and the toolbar layer menu) plus the menu shortcuts. They spend space without adding power (01).
- Combos, Macros, App Layers and History replace the board entirely (14–17), so the user leaves the board to do v1 tasks.
- Flash safety gaps. Cancel stays enabled during the write (08). The prototype's primary 'Flash Now' button in the waiting state teaches a wrong affordance (07). The capsule shows a green check next to 'Not yet on keyboard · 5 edits' (06), which signals the opposite state.
- Pressed keys show only in the Live lens, and that lens swaps out the key inspector (10), so you cannot watch the keyboard and edit at once. In 14 the device card says layer Main while the app rule says it just moved the keyboard to Sym+Num.
- The centre column wastes vertical space. At 1440×900 the keys are about 45 pt, smaller than in the other two directions.

**MustKeep**

- The sidebar as a scalable index of documents, with counts and a pinned device card that verifies the serial against the layout (01).
- 'Transparent. Acts as <legend> from <layer>' with an 'Override on <layer>' button (05).
- The Settings Form with full-height search, 'Modified only', default and Reset per row, and the inspector's 'Changed (N)' list with old defaults struck through (18).
- Shortcut hints printed on the inspector action buttons (01).
- Segmented Erase / Write / Verify progress, with target address, speed and time left (08).
- The kind key that lists only the kinds present on the current layer (01, 05).
- The History layer tabs with per-layer change counts (Brd+Sys 4), plus the before→after change table (15).

**MustFix**

- Never insert or remove views above or below the board. Reserve the space for the key-across-layers strip permanently, or move it into the inspector.
- Make the picker roomier and give it labelled categories, a live preview on the target key, and ⌘⏎ assign-and-advance.
- Replace the Layer popups with visible layer chips and a segmented MO/TG/TO/TT/OSL control.
- Disable Cancel during erase and write. Auto-advance when the bootloader appears instead of offering 'Flash Now'. Use a neutral or amber state icon for 'Not yet on keyboard'.
- Collapse the three layer switchers into one primary switcher.
- Mask keystroke letters in the Live event log (10).

### Chart Table (b-chart-table): 6.4

Sub-scores: tapHoldEdit 8, assignLayerKey 7, findKeycodeFast 9, switchManageLayers 6, seeInherited 6, paintLEDs 7, buildFlashSafely 7, liveDeviceState 6, macroCombo 6, findSetting 6, discoverability 5, keyboardFirst 8, layoutStability 9, errorEmptyStates 8, density 5, v1Scaling 5

**Strengths**

- The most stable layout. The board's frame comes from the window size alone. The key card docks in the gap, and the shelves use a reserved bottom band, so the keys stay in the same place across 01, 03, 06, 10, 13, 15 and 17.
- The best keycode picker (04, 21). It has a labelled category rail with counts and a keycap grid or ranked list showing QMK aliases. It floats over the opposite half, so the target key previews the highlighted code live. ⌘⏎ assigns and moves to the next key, ⇥ cycles categories, and the footer shows every hint.
- The Hold editor reads like a sentence. 'Holding: Modifier | Layer | Key | Nothing', then 'Acts as ⌃⌥⇧⌘ + L/R', then 'Tap types Z; hold for Left Option.' (03). A home-row mod takes four or five clicks, all on visible controls.
- The error card (19) is tethered to the failing key. It shows keymap.c:31, the Tap slot and a caret under the bad code, with 'Fix & Rebuild', 'Edit Key' and 'Show Log'. The status button turns red and reads 'Build Failed'.
- The flash HUD (07, 08) is calm. Cancel is disabled while writing, 'Hide' keeps the flash running with progress in the status button, and it tells you 'Flashing starts by itself when the keyboard appears'.
- Strong keyboard support: arrows cross halves, Esc steps back one level at a time (recording, then shelf, then card, then lens, then selection), V/P/H/C/L/A switch lenses, and dragging one key onto another swaps them in one undo step.

**Weaknesses**

- Weakest discoverability. The six lens tools in the dock are icon-only (01). The Maps-style location arrow means 'follow the keyboard'. Settings, Macros and Import have no visible entry point on the board, only ⇧⌘, ⌘K or selecting a macro key. The nautical names (Soundings, Logbook, Route, Wake) need translating.
- Layer numbering is off by one. The dock shows Main 1, Sym+Num 2, Brd+Sys 3 and the readout says 'layer 1 of 3' (01), while the QMK expressions and Oryx use LT(1,…) for Sym+Num. Reading MO(1) next to 'Sym+Num 2' invites mistakes.
- Device state is cryptic. The pill reads only 'Voyager ----', with no connection word, serial match or firmware (01). In 14 the LEDs are all off even though the board is on Sym+Num.
- Inheritance is shown only as ghost caps. Nothing explains which layer a key falls through to, and there is no Override action until you select the key (05).
- Progress numbers disagree. The ring reads 79% 'WRITING' while the caption says 42,103 of 65,786 bytes (64%) (08). The status button shows '50%' while it is still waiting for the bootloader (07).
- The fixed-height shelves don't scale. A 24-step macro route, a long revision history and more than six app-rule cards would all overflow sideways (14–16). Macros exist only as a 'route' on a key, with no library (16).
- The Wake trail in the Live shelf shows readable typed text ('LLO_WORLD', 10; Chrome.swift:320-356). That is a keystroke display and a privacy risk.
- Information density is low. Much of the screen is decoration (isobaths, compass, margin legend), and editing detail is confined to a roughly 340 pt card. The card covers the trackpad and compass (03), and below about 372 pt of gap it falls back to a side callout that covers neighbouring keys.
- The card's footer actions (make transparent, disable, ⋯) are icon-only (03, 23).

**MustKeep**

- Compute the board frame from the window size alone and reserve a band for transient UI, so nothing that opens or closes moves the keys.
- A picker that floats over the opposite half and live-previews the highlighted keycode on the target key, plus ⌘⏎ assign-and-next (04, 21).
- The Hold segmented control 'Modifier | Layer | Key | Nothing' with a plain-English summary sentence (03).
- The Esc ladder (recording → shelf → card → lens → selection).
- Cancel disabled during the write, with 'Hide' keeping the flash running in the toolbar status (08).
- An error card tethered to the failing key, with a code excerpt and 'Fix & Rebuild' (19).
- Drag one key onto another to swap them, as one undo step.

**MustFix**

- Use QMK's 0-based layer numbers everywhere.
- Label the lens tools, or at least give them a labelled overflow, and put visible entry points to Settings, Macros and Import in the chrome.
- Give the device pill a status word and a serial-match indicator.
- Show one progress number with an honest label. Show no percentage while waiting for the bootloader.
- Remove the typed-text Wake trail.
- Give macros a library, and make the shelves scroll or expand for long content.

**Grafts proposed**

- From Chart Table, compute the board frame from the window size alone. Give Console's drawer fixed snap heights (collapsed, standard, expanded) that only an explicit user action changes, and keep long documents in an expanded or pop-out mode instead of free-dragging the board smaller (fixes c-console 18).
- From Chart Table 04 and 21, float the keycode picker over the opposite half so the target key stays visible and live-previews the highlighted code. Keep Console's ⇥ next-slot and ⌘↵ assign-and-advance (fixes c-console 04).
- From Chart Table 03, add the plain-English summary sentence under the slots ('Tap types Z; hold for Left Option.'), and add 'Nothing' to Console's Hold segmented control.
- From Chart Table, add the Esc ladder (recording → palette → drawer focus → lens → selection) and drag-to-swap keys on the board as one undo step.
- From Chart Table 08, make 'Hide' keep a flash running with progress in the toolbar. From Instrument 08, morph the primary button into Stop and progress. Together these fix c-console 08 and 19, where the Build & Flash button never changes state.
- From Instrument 18, show a 'Changed (N)' list with old defaults struck through and per-section changed counts, in a full-height settings view: either the expanded drawer or Instrument's Form layout.
- From Instrument 05, add an explicit 'Acts as <legend> from <layer>' line with an 'Override on <layer>' button inside Console's Identity column.
- From Instrument 01, make the device line verify the serial against the layout ('KlgM7/40xJ7M ✓ matches') and add a live badge on the layer tab that the physical board is on. Console already has the pip; also style the LCD as a plain readout so it isn't mistaken for a control.
- From Instrument 08, add the segmented Erase / Write / Verify bar with target address, speed and time left to Console's Flash step.
- From Instrument 15, add per-layer change counts on the layer chips in History, so a diff across layers is discoverable.
- From Instrument 01 and 05, have the kind key list only the kinds present on the current layer, to cut legend noise in Console's stage legend.

**Rationale**

Seen as task flow, Console makes the 10 core tasks the shortest and most legible, and it keeps the whole board in view for nearly all of them.

**Core tasks:**
- **Tap and hold:** four clicks with no popups, and the slots sit side by side so you compare them at a glance (01, 03).
- **Layer key:** two clicks on visible chips, with 0-based layer numbers that match the QMK expression.
- **Inheritance:** told three ways: the Through-layers column, the own/inherited counts and the Override slot.
- **LEDs:** the Colours tab with tool shortcuts and painted keys grouped by colour (06) is the most efficient painting flow.
- **Macros and combos:** edited with the board still visible (16, 17).
- **Live state:** always on screen, in the strip and the 'Board runs 40xJ7M / 1 build behind' status.
- **Flashing:** the safest and most legible flow, with callouts on the real Space and Reset keys, the board dimmed as offline during the write, and Cancel disabled (07, 08). Errors land on the key with log links and one-click Fix (19).

**Instrument** is the most discoverable, and the strongest for settings and for explaining inheritance (05, 18). But its board moves whenever a key is selected or deselected or the lens changes: the conditional KeyStackStrip plus min(width, height) scaling breaks principle 5. Its picker is cramped, with icon-only categories and no assign-and-advance (04). Cancel stays live during the write (08). And v1 documents replace the board.

**Chart Table** has the best layout stability and the best picker, with live preview on the target key and ⌘⏎ (04, 21). It is the weakest on discoverability: icon-only lens tools, no visible entry to Settings, Macros or Import, a cryptic device pill, and layer numbers 1/2/3 that contradict LT(1,…). Its fixed shelves won't scale to v1 content.

Console's real problems are fixable by grafting:
- a cramped drawer for long documents (18);
- a picker that hides the board (04);
- a Build button that never changes state (08, 19);
- an LCD layer track that looks clickable but is read-only.

Chart Table supplies the stable-frame discipline and the preview-in-place picker; Instrument supplies the settings view, the Override callout and the run/stop button behaviour.

One issue applies to all three: each shows typed characters from raw HID (Instrument 10 event log, Chart Table 10 Wake trail, Console 10 event monitor). That would expose passwords typed in any app, so the final design should show key positions only, never letters, and pause during Secure Event Input.

## Visual delight and identity

**Scope:** Visual delight and identity: does it meet the user's "modern slick" bar? Covers aesthetic polish (spacing, hierarchy, alignment, type), board render quality (caps, legends, key-kind colours, layer treatment), a distinctive Sextant identity without ZSA trade dress, restraint versus gimmick, first impression, and how good the menu bar extra and HUD look. I viewed all 64 snapshots and made 2x crops of the boards (left half Main dark/light, right half Brd+Sys live) to compare cap craft. I also grepped the sources to confirm live glass and Reduce Motion handling: Chart Table uses glassEffect with GlassEffectContainer and handles Reduce Motion in 8 places; Instrument has no Reduce Motion handling; Console handles Reduce Motion and Reduce Transparency.

**Winner:** Chart Table (b-chart-table)

### Chart Table (b-chart-table): 8.6

Sub-scores: polish 8, boardRender 9.5, keyKindSystem 7.5, layerColourTreatment 8.5, identity 9.5, restraint 7, firstImpression 9.5, menuBarAndHUD 8, lightDarkParity 9

**Strengths**

- Best first impression of the three. 01-main-dark and 02-main-light look like an object, not a form. The board fills the window with caps of about 68 pt (Instrument and Console are about 49 pt), so it is really the hero. The paper and night charts are cohesive and look nothing like Oryx.
- Best cap craft (crop of 01). Soft convex shading, a contact shadow, big SF Pro legends, and Mac glyphs with small L/R marks. The tap+hold 'hold band' across the bottom third ('esc' on =, ⌥L on Z, the stacked-layer glyph plus 'Sym+Num' on the thumb) is the clearest secondary-legend treatment in any direction.
- Layer colour treatment in 05-layer-symnum and 14 is excellent. Cyan rims and glow, dashed submerged ghosts for inherited keys, the holding thumb hatched, and isobaths re-tinted to the layer colour, so the whole room changes colour with the layer. In light mode, lime and cyan are darkened by HSB and stay legible (15, 19).
- The name finally means something. A restrained compass rose, graticule, edge graduations and a New York title block give a memorable Sextant identity with zero ZSA trade dress. The menu bar extra (11) carries a compass mark as the app's signature.
- Build & Flash HUD (07, 08). A big progress ring on a graduated sextant-style bezel, a calm searching arc, a paperclip-and-pinhole illustration, and a single-hue stacked size meter. This is the most delightful and brand-coherent flash moment of the three.
- On-board overlays are beautifully drawn. In 17-combos, combos are bearing arcs ending in output pills. The 15-history-diff logbook keeps changed keys vivid and everything else quiet. The 19-error red reticle has a dotted tether to a docked card. The 06 paint stroke shows a brush trail and tip.
- Soundings heatmap (13) uses a refined single-hue blue scale with italic serif counts and contour rings from usage. It is far more tasteful than the magma ramps in a-13 and c-13.
- Typographic voice: SF Pro for UI, SF Mono for QMK, and New York for things 'printed on the chart'. Settings defaults in italic serif ('Default 200 ms' in 18) and the serif title block feel editorial and premium.
- Glass is reserved for floating chrome: a status cluster top-right, a layer dock and lens tools bottom-centre, and shelves. The canvas stays opaque. This is the right Liquid Glass hierarchy, and Reduce Motion is wired.

**Weaknesses**

- Kind washes mix with the layer rim into muddy colours. On Brd+Sys in dark mode, amber lighting caps and coral custom-label caps under the lime rim turn olive and brown (10-live, 16-macro-editor, crop b10-right: Back, Prev Tab, Next Tab, Forward look muddy). Kind and layer compete for the same pixels.
- Decoration risks gimmick. Over a day of use, the compass rose in the gap, full-window isobaths, edge graduations and nautical names (Soundings, Logbook, Macro Route, Wake) could feel themed rather than 'modern slick'. In 02-light the contour lines and margin legend are a little busy behind the board.
- Polish slips: the card title truncates to 'Z · Left Opt…' (03, 20). The docked card covers the trackpad disc (03, 20, 23). Combo output pills sit on top of the E/R and U/I legends (17). The menu bar panel has a dead band above Open Sextant and Build & Flash (11).
- The Paint Lights lens in light mode (06) makes every unpainted key a saturated lime glow, so the painted keys don't stand out.
- Serif custom labels ('Back', 'Prev Tab' in New York) on a coral wash look heavy and smudgy in dark mode (10, 16), and mixing two families on caps hurts the board's uniformity.
- The always-on margin legend lists all nine kinds even when only three are present (01, 02).
- Glass in every PNG is a hand-built stand-in. The real look of the dock and status cluster is unverified, and the custom canvas will feel less stock-Apple than a split view. There is no visible home for the layout library or documents.

**MustKeep**

- The large, window-derived board frame with about 68 pt caps, and the cap rendering: convex shading, contact shadow, big legends, L/R marks (01, 02).
- The tap+hold hold band across the bottom third, tinted by what the hold does, with the stacked-layer glyph and layer name on layer-taps (01, 03).
- The layer rim plus glow, the holding thumb hatched in the layer colour, dashed submerged ghosts for inherited keys, and HSB-darkened layer colours on light backgrounds (05, 14, 15).
- The flash HUD's graduated sextant bezel ring and calm searching arc, and the single-hue stacked size meter (07, 08).
- The Soundings single-hue heatmap with usage contours (13). It is more refined than any magma ramp.
- Combo bearing arcs with output pills (17), and the diff that leaves unchanged keys quiet and rings changed keys with badges (15).
- The error reticle with a tether to a docked card offering Fix & Rebuild (19).
- The Sextant compass mark as the app icon motif and menu bar glyph (11). It is a real identity with no trade dress.
- New York for the title block, defaults and annotations: an editorial accent used sparingly.
- Floating glass for chrome only (status cluster, layer dock, shelves) over an opaque canvas.

**MustFix**

- Separate kind from layer pixels. Replace full-cap kind washes (lighting amber, custom-label coral, macro orchid) with Instrument's bottom signal bar plus faint tint, keeping the hold band for tap+hold. Brd+Sys must not turn olive or brown (10, 16).
- Turn the theme down: lower isobath and graticule contrast by about 40% in light mode, shrink the compass rose or let it fade when a card is docked, and use plain labels first (Heatmap, History, Macro), with the nautical names as subtitles at most.
- Fix the truncated card title (03, 20). Keep docked cards and combo pills off the trackpad disc and key legends (03, 17).
- Paint lens: dim keys that only inherit the layer colour to about 35% so painted keys pop (06).
- Set custom labels in SF Pro semibold on a neutral cap with a kind bar, or keep New York only in light mode, at a lighter weight (10, 23).
- The margin legend should list only the kinds present on the current layer.
- Close the empty band in the menu bar panel (11).
- Verify real glassEffect in a live build, with a Reduce Transparency frosted fallback. Give the layout library and documents a native home, such as a collapsible sidebar.

### Instrument (a-instrument): 7.6

Sub-scores: polish 9, boardRender 7.5, keyKindSystem 8.5, layerColourTreatment 8.5, identity 5.5, restraint 9.5, firstImpression 7, menuBarAndHUD 8, lightDarkParity 8.5

**Strengths**

- The most Apple-made of the three. The Xcode-grade toolbar has a Run-style Build & Flash button and an activity capsule. The inspector is dense with right-aligned labels, there is a native sidebar, and alignment and spacing are disciplined everywhere (01, 03, 18).
- The most principled key-kind system. The kind signal bar plus faint tint and the layer ring never compete for pixels (crop of 01: indigo bars on ⇧ and ⌃, amber on = and Z, amber 'Esc' secondary). Brd+Sys stays clean under the lime ring (10, crop a10-right).
- The light-mode 'porcelain' board with deepened layer colours (02, 15, 17) is elegant and calm.
- The error state is excellent and native (19). The capsule reads 'Build Failed · 1 error · key 45', with a red banner, a red ring and badge on the key, and an inspector callout with Fix.
- Settings is a stock grouped Form with a sections navigator and a 'Changed (9)' list with struck-through defaults (18). It is a delightful, very Apple detail.
- The 'key across layers' strip under the board (01, 05) is a quietly useful visual.
- The HUD (12) has cyan rims with glow, a lit '1' and a 'release to hide' pill, and the glass looks right. The menu bar panel (11) is clean and native, with a mini map and layer rows with shortcuts.
- The command palette (20) reads like Spotlight: grouped results, mono QMK, crisp.

**Weaknesses**

- Weak identity. It is 'Xcode for keyboards', and nothing in it would make someone remember 'Sextant' (01, 14, 16). It meets 'native' but undershoots 'slick'.
- The board is not the hero. Squeezed between two columns, the caps are about 49 pt and the board floats in large dead space above and below (05, 13, 17). The recessed bench lift is invisible in dark mode.
- A monospaced index on every cap by default adds a layer of grey noise to the board (crop of 01).
- The kind bars are so restrained that Main reads almost monochrome at a glance. Meaning-at-a-glance is weaker than Chart Table's hold bands.
- The magma heatmap on caps (13) is garish; orange and magenta blocks fight the calm chrome.
- Reduce Motion is not wired. Dark glass inspector controls needed a custom bezel workaround, so they aren't stock controls.

**MustKeep**

- The two-channel encoding: kind as a short bottom signal bar plus a 4.5% tint, and layer as a 1 pt outer ring with a soft glow in dark mode (01, 05, 10).
- The Xcode-style status capsule: device, serial and build state with a progress hairline. It shows 'Build Failed · 1 error · key 45' and links to the key (07, 19).
- Settings with a 'Changed (N)' summary and struck-through default values, plus 'Default X · Reset to Default' on modified rows (18).
- The key-across-layers strip (01, 05) and the transparent-key callout 'Acts as Z from Main · Override on Sym+Num' (05).
- Explicit grey text tiers (text2/3/4) so hierarchy holds over glass.
- The kind legend lists only kinds present on the current layer (01 bottom).
- The menu bar panel's restraint and native list rows with ⌃⌥1–3 shortcuts (11).

**MustFix**

- Make the board the hero: enlarge it to fill the centre column and reduce dead vertical space (05, 17). Consider an auto-hiding sidebar.
- Turn cap indices off by default and show them on hover, on selection or with ⌥⌘I.
- Add some identity: an app mark, a signature moment in flash and live, and a signature material. Today it could be any pro app.
- Replace the magma cap fills with a calmer single-hue or two-hue ramp (13).
- Wire Reduce Motion and Reduce Transparency.

### Console (c-console): 7.1

Sub-scores: polish 7.5, boardRender 7, keyKindSystem 7.5, layerColourTreatment 7.5, identity 8, restraint 6, firstImpression 7, menuBarAndHUD 8.5, lightDarkParity 8

**Strengths**

- The strongest 'connected to hardware' identity. The live strip LCD has a layer track, 4 status LEDs, keys down as keycaps and a typing sparkline (01, 10). The Device tab's event monitor (10) makes the keyboard feel alive.
- Best flash guidance visual. The real board shows numbered callouts on Space (1) and Reset (2) plus a pinhole marker, with everything else dimmed (07).
- The best menu bar extra (11). Three big layer tiles with the active one lit in its colour, a live mini map, WPM sparkline and today's count, and an app-rule row. It is dense but delightful.
- The layer-tinted glass HUD (12) gives the held layer an unmistakable identity.
- Record mode styled as DAW record-arm: a red ring and REC badge on the key plus a 'Listening…' tile (21). You can read it instantly.
- The four slots side by side and the 'Through layers' stack with fall-through arrows (01, 03) are great information design.
- The macro sequencer lane, with proportional delays on a time ruler (16), is the best macro visual.
- Layer tabs in the title bar with colour chips and a live pip (01, 14) are a nice native-adjacent touch.

**Weaknesses**

- Too much chrome. Title-bar tabs, the live strip, drawer tabs and the status bar stack into four bands, and the board gets under half the window with caps of about 49 pt (01, 13, 19). The first impression is busy, more DAW or web dashboard than calm Apple.
- Heavy use of tracked mono uppercase labels (TAP, HOLD, THROUGH LAYERS, BUILD → FLASH, CONSOLE) gives a dev-tool voice that drifts from 'slick native'.
- Loud cap details. Colour keys carry full-saturation bands with mono hex text '#000EFF' (10, 15). The 2 pt 'lamp' line on every owned key (05, 14, 21) becomes a field of tiny dashes. The green and cyan stage washes from the top look like a gradient wash (14, 16).
- Glyph ambiguity: the Esc hold band on = renders as a circular arrow that reads as reload or undo (01, 03). PgUp, PgDn, Home and End are arrow glyphs without captions (10). The brief asks for words.
- Thumb hold bands with tiny rotated 'Sym+Num' text are hard to read at this cap size (01).
- The size meter in 07 uses a multi-hue categorical stack, inconsistent with the calm palette elsewhere.

**MustKeep**

- On-board flash guidance with numbered callouts on the real Space and Reset caps and a pinhole marker (07).
- The menu bar extra's structure: big lit layer tiles, live mini map, WPM and today's count, the app-rule row and the HUD toggle (11).
- Record-arm styling: a red ring plus REC badge on the target key, and esc cancels (21).
- The Through layers stack with fall-through arrows, showing the same position on every layer (01, 03).
- The macro lane with a time ruler and proportional delays (16).
- The layer-tinted HUD glass (12), as a tint option.
- The live layer track and LED readout concept (01, 10), compressed into a device pill or popover rather than a full band.
- Clickable error log lines that link to the key (19).

**MustFix**

- Collapse the chrome: merge the live strip into a toolbar device capsule and give the board at least 60% of the height.
- Use words or captions for Esc, PgUp, PgDn, Home and End. Replace the circular-arrow Esc glyph with 'esc'.
- Drop hex text from caps; show a swatch only. Remove the lamp lines in favour of a single rim.
- Reduce the mono uppercase labels to section headers only.
- Use a single-hue size meter (07).

**Grafts proposed**

- From Instrument: the two-channel key-kind encoding. Kind becomes a short bottom signal bar plus a faint tint, and layer stays Chart Table's rim and glow. This replaces Chart Table's full-cap washes for lighting, custom label, macro and tap dance, and removes the olive and brown mixing on Brd+Sys (fix b-10-live and b-16-macro-editor using a-10-live and the a-01-main-dark crop as reference). Keep Chart Table's hold band for tap+hold.
- From Instrument: the Xcode-style status capsule detail in Chart Table's status cluster. Show 'Build Failed · 1 error · key 45' and a progress hairline in the device or Build pill (a-19-error, a-07-flash-guide) rather than only the red 'Build Failed' button (b-19-error).
- From Instrument: in Settings, a 'Changed (N)' list with struck-through defaults and 'Default X · Reset to Default' (a-18-settings), added to Chart Table's settings panel sidebar (b-18-settings).
- From Instrument: the kind legend lists only kinds present on the current layer (a-01-main-dark bottom), replacing Chart Table's always-full margin legend (b-01, b-02).
- From Instrument: explicit grey text tiers for labels over glass, and the transparent-key callout 'Acts as Z from Main · Override on Sym+Num' (a-05-layer-symnum) inside Chart Table's docked card.
- From Console: the Through layers stack with fall-through arrows (c-03-key-hold-edit), or Instrument's key-across-layers strip (a-05). Add it as a row in Chart Table's docked key card (b-03).
- From Console: on-board flash guidance with numbered callouts on the real Space and Reset caps and a pinhole marker (c-07-flash-guide). While waiting for the bootloader, Chart Table's HUD should shrink to a side card so the real board is visible (b-07).
- From Console: record-arm styling, a red ring plus REC badge on the target key (c-21-record-key), replacing Chart Table's in-card tile alone (b-22).
- From Console: the menu bar extra's lit layer tiles, WPM and today line and app-rule row (c-11-menubar), merged with Chart Table's pocket chart and compass mark (b-11-menubar). Remove Chart Table's dead band above the buttons.
- From Console: proportional delays on a time ruler for the macro lane (c-16-macro-editor), applied to Chart Table's Macro Route waypoints (b-16).
- From Console: the live layer track and LED readout (c-01, c-10), compressed into Chart Table's device pill popover and Live shelf (b-10-live). Not as a permanent band.

**Rationale**

Chart Table wins. Through a visual-delight lens it is the only direction that clears the user's 'modern slick' bar on first sight, and the only one with an identity you would remember.

**Why Chart Table**
- **The board is the hero.** The caps are about 68 pt, against about 49 pt in Instrument and Console (01, 02).
- **Best cap craft.** The hold-band secondary legend is the clearest of the three (01, 03, 20).
- **Layer colour as atmosphere.** The rim and glow, plus isobaths re-tinted to the layer colour, make the layer something you feel, not just a badge (05, 14).
- **Signature moments.** These include the sextant-bezel flash ring (07, 08), the single-hue soundings heatmap (13), the combo bearing arcs (17) and the error reticle with a tether to its card (19).
- **A name with a visual.** The compass mark turns 'Sextant' into an identity, with no ZSA trade dress anywhere.

**Chart Table's real risks**
- **Kind and layer collide.** Kind washes mix with the layer rim into muddy olive and brown on Brd+Sys (10, 16).
- **Theming could tip into gimmick.** This applies to the compass, the isobaths and the nautical names.
- **Polish slips.** The card title truncates, the card covers the trackpad disc, and the combo pills cover legends.

All of these can be fixed. The best fix for the first comes straight from Instrument's two-channel kind and layer system.

**Instrument (second)** is the most polished and the most Apple-native, with the cleanest kind encoding and a superb error state and settings. But it reads as 'Xcode for keyboards'. Its board is small, the centre column has dead space, and index numbers sit on every cap, so its identity scores lowest.

**Console (third)** has the best live and hardware personality and the best menu bar extra, flash callouts and record-arm moments. But four bands of chrome, mono-uppercase density and loud cap details (hex text, lamp dashes, an ambiguous Esc glyph) make it the busiest and least restrained.

**Recommended final**
- Chart Table's canvas, caps, layer atmosphere and flash HUD, with the theme turned down by about 40% and plain feature names first.
- Instrument's kind encoding, status capsule, settings change summary and grey text tiers.
- Console's through-layers stack, on-board flash callouts, record-arm styling, menu bar tiles and macro time ruler.

**Snapshot files**
- /Users/aaron/Developer/Sextant/design/explorations/a-instrument/snapshots/
- /Users/aaron/Developer/Sextant/design/explorations/b-chart-table/snapshots/
- /Users/aaron/Developer/Sextant/design/explorations/c-console/snapshots/
- My 2x board crops are in /private/tmp/claude-501/-Users-aaron-Developer/ddf7da44-df94-4702-ad26-d64a9e4c9626/scratchpad/crops/ (a01-left, a02-left, a10-right, b01-left, b02-left, b10-right, c01-left, c02-left, c10-right).
