# PrototypeKit

## API summary

PrototypeKit 1.0.0 is an SPM library for macOS 26 with no dependencies. Add it with `.package(path: "design/PrototypeKit")` and product "PrototypeKit". Every public type has doc comments; Sources/PrototypeKit/PrototypeKit.swift is the map. It is utilities only: no colours, fonts or styling.

Name changes, to avoid SwiftUI/AppKit clashes:
- The layout type is `KeyboardLayout`, not `Layout`, because `Layout` is a SwiftUI protocol.
- Colours are `HexColor`, not `RGBColor`, which is a legacy QuickDraw struct.
- Do not add a `Layout` alias.

MODEL (Model/)
- `KeyboardLayout`:
  - fields: id ("KlgM7"), revisionId ("40xJ7M"), title, geometry, firmwareVersion ("25.0"), revisionMessage, createdAt, md5, layers, combos, settings (sparse [String: SettingValue]), navigator (NavigatorConfig).
  - decode: `init(oryxJSON: Data)`, `init(oryxFile:)`.
  - lookup: `key(layer:index:)`, `updateKey(layer:index:_:)`, `layerNames`, `keyCount`, `settingValue(_:)`.
  - transparency: `resolvedKey(layer:index:activeLayers:)` returns `ResolvedKey` (own, effective, sourceLayer, isInherited). The default active set is {0, layer}, which is what Oryx shows.
  - `keysActivating(layer:)` finds the key that holds a layer, e.g. the thumb.
  - `moveLayer(from:to:)` and `removeLayer(at:)` remap MO/TG/TO/TT/OSL/LM references; references to a deleted layer become KC_NO.
  - `diff(from:)` returns `LayoutDiff` (keyChanges [KeyChange with before/after/changedSlots/labelChanged/colorChanged], added/removed/renamed/recoloured layers).
- `Layer`: id, title, color, keys[52]. `.transparent(title:)`.
- `Key`:
  - fields: tap, hold, doubleTap, tapHold (each `KeyAction?`), customLabel, glowColor, tappingTerm.
  - subscript[KeySlot], filledSlots, actions, isTransparent, kind, referencedLayers. Statics `.transparent`, `.none`.
- `KeyAction`:
  - fields: code (QMK name as Oryx stores it), layer, modifiers, macro, color, description. Oryx's `modifier` "MOD_*" string is folded into modifiers.
  - canonicalCode, isTransparent / isNone / isLayerAction / isModifier / isLEDControl.
  - constructors: `.code(_:modifiers:)`, `.momentary(n)`, `.toggle(n)`, `.moveTo(n)`, `.oneShotLayer(n)`, `.setColor(c)`.
- `KeySlot`: tap / hold / doubleTap / tapHold, with title and symbolName.
- `KeyKind`: regular, modifier, multiFunction, tapDance, ledControl, macro, customLabel, layerKey, transparent, none.
  - Each has title, explanation and symbolName.
  - Classification order: transparent > none > macro > customLabel > tapDance > multiFunction > layer / LED / modifier / regular.
  - An all-null key is transparent, because Oryx generates KC_TRANSPARENT for it.
- `Modifiers` (OptionSet, left/right distinct): glyphs (⌃⌥⇧⌘ order), names, qmkMaskNames, `init?(qmkMask:)`, `wrapQMK`, `.hyper`, `.meh`.
- `Macro` (name, steps [MacroStep code/modifiers/delay ms], endsWithEnter, holdsOption, maxSteps 24).
- `Combo` (keyIndices, layer?, output); `NavigatorConfig` (kind, side, options).
- `HexColor`: hex init/output, `.color`, `.nsColor`, hsb, luminance.

LEGENDS (Legends/)
- `Legends.legend(for: Key, layerNames:)` returns `KeyLegend`:
  - kind; primary and secondary `ActionLegend`, plus primarySlot / secondarySlot.
  - annotation: the underlying "⌘[" under a custom label.
  - slots: all populated slots.
  - qmk: whole-key expression such as "LT(1, KC_ENTER)" or "MT(MOD_LALT, KC_Z)".
  - swatch.
- `ActionLegend`: text (glyph/short text incl. chord glyphs like "⇧⌘["), symbol (SF Symbol), name, side (.left/.right for the L/R mark), modifiers, layer/layerName, color, qmk, category, isUnknown.
- `Legends.legend(layout:layer:index:activeLayers:)` returns `ResolvedLegend`: legend, isInherited (draw dimmed), sourceLayer, ownKind, activatesDisplayedLayer (Oryx's hatched key).
- Layer holds read e.g. "Sym+Num" with name "Hold for Sym+Num". QK_BOOT reads "Reset". Mac glyphs: ⌘ ⌥ ⌃ ⇧ ⇪ ⌫ ⌦ ⏎ ⇥ ⎋ ␣ ← ↓ ↑ → ↖ ↘ ⇞ ⇟.
- `KeycodeCatalog`:
  - entries: 320 `KeycodeEntry` values with code, aliases, label, name, symbol, keywords, category, shiftedLabel, side, needsLayer / needsModifiers / needsColor.
  - lookup: `entry(for:)` (aliases accepted), `canonicalCode(_:)`, `entries(in:)`, `layerFunctions`, `modifierCodes`, `modifier(forCode:)`.
  - search: `search(_:category:limit:)` and `rankedSearch`. Each term must match; exact > prefix > word prefix > substring > word-anchored subsequence; glyphs and characters ("⌘", "[") match literally.
- `KeycodeCategory` has 15 cases with title and symbolName: letters, digits, modifiers, punctuation, navigation, editing, functionKeys, media, mouse, lighting, layers, system, international, numpad, navigator.

GEOMETRY (Geometry/)
- `BoardGeometry.voyager`, or `.voyager(stagger: .oryx|.qmk, halfGap: 4.9, navigator: .right)`. Units are key pitch, y down.
  - keys: `KeyShape` with index, hand, cluster, row, column, center, size, rotation in degrees (clockwise +), isHomeRow, matrix, qmkPosition, ledPosition, corners, boundingBox.
  - `navigator` anchor, `bounds`, `bounds(of: hand)`, `keys(on:)`.
  - `neighbor(of:toward:)` for arrow-key selection; it crosses halves and reaches the thumbs.
  - `layout(keySize:spacing:padding:)`, `layout(keySize:spacingRatio:)`, `layout(fitting:spacingRatio:padding:)`.
- `BoardLayout` (points): frames [KeyFrame with center, size, rotation, rect, corners, boundingBox, contains], navigator, size, keysBounds, `bounds(of:)`, `keyIndex(at:)` (rotation-aware hit test).
- Views:
  - `BoardCanvas(layout:) { frame in … }` places your key views; no styling.
  - `FittedBoardCanvas { frame, layout in … }` fits the available space.

SAMPLES (Samples/)
- Data:
  - `Samples.layout`: the user's real layout, with createdAt and the right-half trackpad filled in.
  - `layoutWithCombos`, `combos` (J+K → Esc, D+F → Tab), `macros` / `macro`. "Open Keymap" is ⌘⇧O, 150 ms, "keymap", 60 ms, ⏎.
  - `appRules` (Xcode → 1, Figma → 2, Terminal → 1, Music → 2, Safari off), `frontmostAppBundleIdentifier`, `appRuleActiveLayer`.
  - `heatmap`, `history`, `oryxImport`, `buildFailure`, `settingsOverrides` (illustrative non-defaults), `settingsCatalog`, `geometry`.
- `MockDevice` (@MainActor @Observable):
  - identity: name, serialNumber "KlgM7/40xJ7M", firmwareVersion "25.0", protocolVersion 5, VID/PID, navigator.
  - live state: connection (.connected / .searching / .heldByAnotherApp / .bootloader / .disconnected), activeLayer, pressedKeys, statusLEDs (layer bits), ledBrightness, lastEvent, pressCounts.
  - control: `seek(to:)`, `frozen(at:)`, `start(loop:speed:)`, `stop()`, `apply(_:)`.
  - `LiveScript.typingAndLayerHold`: types "hello world", holds Space for Brd+Sys and presses ↑↑→→→ (2.0–3.6 s), holds Enter for Sym+Num and types (12) (4.0–5.3 s), then "ok". Seek 2.6 shows layer 2 with 51 and 40 down; 4.6 shows layer 1 with 24 and 44 down.
- `KeyHeatmap`: count, total, maxCount, intensity (log option), top, csv(layout:), layerActivations, layerShare, period. About 175k keystrokes over 7 days; Space is the hottest key.
- `RevisionHistory` / `LayoutRevision`: four revisions with per-key diffs of [0, 2, 4, 4]. `diff(from:to:)`, `diffToPrevious(_:)`.
- `BuildFlashSimulator` (@MainActor @Observable):
  - phase: `BuildFlashPhase` = idle, generating, compiling(progress, file), linking, built, waitingForBootloader, erasing, flashing(progress, bytes), verifying, done, failed(BuildFailure). Each has overallProgress, title, guidance, isBusy.
  - log [BuildLogLine with level and optional KeyRef].
  - sizeMeter: `FirmwareSizeMeter.sample` is 65,786 of 122,880 bytes with a breakdown; `.overflow` exists too.
  - control: `at(.step)` / `jump(to:)` for deterministic states, `startBuild()`, `continueAfterBootloader()`, `simulateFailure`, `cancel()`.
  - `BuildFailure.unknownKeycode` is mapped to Brd+Sys key 45, slot tap, keymap.c line 31, with a suggestion. `.tooLarge` covers the size overflow.
- `OryxLayoutReference(string)` parses configure.zsa.io URLs, "KlgM7/40xJ7M" serials and bare ids.
- `OryxImportPreview.sample` covers https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0: input, reference, source (pastedURL / connectedKeyboard), layout, summary (3 layers, 130 assigned keys, 6 dual-function, 4 labels, 3 colour keys), steps, notes.
- `SettingsCatalog.voyager`: 14 `SettingsSection`s and 100 `Setting`s. Each setting has id, title, summary, control (toggle / slider / layerSelect / animationSelect), defaultValue, range, unit, isToggleable, marks, boards, navigatorKinds, dependsOn, options, and `format(_:)`. The catalog has `search`, `modified(in:)` and `section(containing:)`. `SettingValue` is bool / number / text / integers / strings.
- `PrototypeResources` gives URLs for the three bundled JSON files.

EDITOR
- `EditorStore` (@MainActor @Observable): layout (private(set)), selection `EditorSelection(layer, keyIndex, slot)`, undoManager, geometry, hasUnsavedChanges, changeCount, canUndo / canRedo / undoActionName, `undo()` / `redo()`, selectedKey / selectedAction / currentLayer, `legend(at:)`.
- Selection: `select(layer:)`, `select(key:slot:)`, `moveSelection(.left/.right/.up/.down)`.
- Undoable edits, each with a readable action name:
  - `setAction`, `setCode`, `setTap`, `setHold`, `setHoldLayer`, `setModifiers`, `setLabel`, `setColor`, `paint(_:keys:)`, `makeTransparent`, `disable`, `setKey`, `swapKeys`.
  - `addLayer`, `duplicateLayer`, `renameLayer`, `setLayerColor`, `moveLayer` (references and selection follow), `deleteLayer`.
  - `setTitle`, `setSetting` (stored sparsely), `setCombos`, `replaceLayout`.
- Every edit snapshots the layout and selection, so undo restores both.

SNAPSHOTS: see snapshotHowTo. Types: `SnapshotScene`, `SnapshotOverlay`, `SnapshotRunner`, `SnapshotAppearance`, and the `EnvironmentValues.isSnapshot` flag.

## Snapshots

SETUP IN A PROTOTYPE APP
```swift
@main @MainActor enum Entry {
    static func main() {
        SnapshotRunner.handleCommandLine(MyScenes.all)  // exits after rendering if --snapshot <dir> was passed
        MyApp.main()                                    // normal SwiftUI App otherwise
    }
}
```
Run `swift run MyApp --snapshot ./snapshots [--only a,b] [--scale 2]`. You can also call `SnapshotRunner.run(scenes:outputDirectory:scale:)` or `SnapshotRunner.render(scene) -> CGImage`. Each scene is written as a PNG tagged 144 dpi.

Call `handleCommandLine` before anything touches `NSApplication.shared`. That lets it install a private NSApplication subclass that reports the app as active and the snapshot window as key, so controls draw in their active state. Validated with a separate consumer package using the SwiftUI `App` lifecycle.

SCENES
`SnapshotScene("name", size:, appearance: .light/.dark, chrome:, background:, windowFrame:, settleTime: 0.35, overlays: []) { View }`. `SnapshotScene.pair(...)` makes the -light and -dark pair.

Chrome options:
- `.window(title:)` (default): a real titled NSWindow with full-size content. The view is hosted in NSHostingController with `sceneBridgingOptions = [.toolbars, .title]`, so `.toolbar`, `.navigationTitle`/`Subtitle`, NavigationSplitView sidebars and `.inspector` populate real AppKit chrome. It is captured with `cacheDisplay` on the window's frame view (NSThemeFrame), which includes the titlebar, traffic lights and toolbar.
- `.content`: the view alone in a borderless offscreen window. AppKit controls work.
- `.imageRenderer`: SwiftUI ImageRenderer, no window.

windowFrame options:
- `.rounded` (default): the real 16 pt corner radius read from the frame view, plus a hairline edge.
- `.square`.
- `.shadowed(padding:)`.

`@Environment(\.isSnapshot)` is true while rendering. `controlActiveState` is `.key`, and animations are disabled.

NO TCC, NO VISIBLE WINDOWS
- Rendering is entirely in-process. No screencapture, ScreenCaptureKit, CGWindowList or Accessibility API is used.
- Activation policy is `.prohibited`: no Dock icon, and the app never activates.
- Windows are created at (-30000, -30000) with alpha 0 and are never ordered in. No orderFront or makeKey calls.

FIDELITY, measured on macOS 27.0.1 by rendering, inspecting the layer trees and viewing the PNGs

Faithful in .window and .content:
- Layout, text, SF Symbols, shapes, gradients, images, Canvas, accent colour.
- AppKit-backed controls in their active state: switch toggles, TextField, segmented Picker, Slider, List/outline rows and selection, grouped Form.
- Titlebar, traffic lights, window title and subtitle, toolbar items and their glass platters.
- Light and dark appearance, at 2x on any display.

Approximated in .window and .content, which without the window server render wrong or blank:
- Liquid Glass (NSGlassEffectView, `.glassEffect`, `.buttonStyle(.glass)`):
  - The glass overlay is an opaque white layer that becomes glass only through a window-server filter, and content shows through a CAPortalLayer. Raw `cacheDisplay` therefore gives blank sidebars, inspectors and toolbar items.
  - LayerFlattener hides the portals, so content renders directly, and draws a flat translucent fill in the glass's real shape and corner radius (read from its CASDFElementLayer) with a 0.5 pt edge.
  - There is no blur, refraction, specular highlight or glass shadow.
  - Prominent glass and any tinted glass are filled with the accent colour. A custom tint like `.tint(.orange)` cannot be read back; if it matters, branch on `isSnapshot`.
- Materials (`.regularMaterial`, NSVisualEffectView): flat base colour, no backdrop blur.
- Vibrancy (vibrantColorMatrix filter): the layer's own colour matrix is applied to its bitmap on a plain sibling layer; SwiftUI's ImageLayer reverts in-place edits. Colours are close, though dark secondary labels come out a little dimmer. Vibrant 1 pt separators use separatorColor.
- Selection material: selectedContentBackgroundColor.
- Scroll-edge effects are omitted (their destIn masks would otherwise erase content).
- No real window shadow; `.shadowed` draws one.
- AppKit won't make a window smaller than its content's minimum size (toolbar plus split columns). The PNG then has the real size and the runner prints a "note:" line.

.imageRenderer:
- Draws SwiftUI's own software glass and materials, which look closer to real glass, and prominent glass is accent-coloured.
- Every AppKit-backed control (switch Toggle, TextField, Picker, List, Table, Form rows, Menu, NSViewRepresentable) becomes a yellow "unsupported" placeholder.
- Use it for pure-SwiftUI drawings such as the board, a HUD or a menu-bar panel. `snapshots/glass-*` shows both paths side by side.

Never capturable: real sheets, popovers, menus, alerts, tooltips, the menu bar or MenuBarExtra menus, drag images, the cursor, and mid-flight animations. Presenting them would put a window on screen, so don't.

SHEETS, POPOVERS AND MENUS
Render the overlay content separately and composite it with `overlays:`. Positions are window points with a top-left origin.
- `.sheet(width: 560) { … }` fits the content height; `.sheet(size:top:)` sets it exactly. The sheet is centred under the toolbar with the parent dimmed, 20 pt corners and a shadow.
- `.popover(size:anchor:edge:)` draws a bubble with an arrow pointing at a window-space rect. For a key, that's the KeyFrame's boundingBox plus the canvas origin.
- `.menu(size:at:)` draws a menu-coloured panel; build the rows yourself with Text, Divider and shortcut text.
- `SnapshotOverlay(.frame(rect), …)` places content at an exact frame.

A width or height of 0 is fitted to the content. Content that overflows its size prints a note instead of clipping silently.

DETERMINISM
Use `MockDevice.frozen(at:)`, `BuildFlashSimulator.at(.waitingForBootloader)` and similar states, and the fixed Samples. About 0.4 s per window scene.

## Notes

BUILD AND RUN
- `swift build` and a clean rebuild pass with zero warnings and zero errors (Swift 6 language mode).
- `swift run PrototypeKitDemo` runs about 120 self-checks, all passing, then writes 12 PNGs to design/PrototypeKit/snapshots/.
- Flags: `--check` runs the checks only; `--snapshot <dir> [--only a,b]` renders only.
- The images:
  - board-main-light and board-main-dark: the required neutral render of Main.
  - board-brdsys-light: inherited legends, colour keys, custom labels.
  - board-indices-light: the Sym+Num layer with key indices and MockDevice-pressed keys at 4.6 s.
  - window-light and window-dark: sidebar, toolbar and inspector.
  - window-sheet-light and window-popover-dark: composited sheet, popover and menu.
  - glass-content-* and glass-imagerenderer-*: glass on the two windowless paths.
- I looked at every PNG.

VERIFIED AGAINST Oryx's read-only layout view (the screenshot is kept in the reference folder)
- Stagger: column 3 is highest and columns 2 and 4 are half-raised, mirrored on the right half (0.15/0.30u, taken from voyager-geometry.json's translateY values).
- Thumbs: both pairs are rotated ±30°. The inner thumb (25/50) is 1u × 1.35u and top-aligned with the outer one (24/51).
- Navigator: the circle sits by the right half's inner edge.
- Legends: "= / ⎋", "Z / ⌥L", "' / ⇧R", "/ / ⌥R", "⏎ / Sym+Num", "␣ / Brd+Sys", hold-only ⌃L ⌘L, ⌃R, ⌫.
- Brd+Sys: inherited keys come from Main, not Sym+Num (e.g. key 26 shows 6, not F6), exactly as Oryx does. Back / Prev Tab / Next Tab / Forward show their ⌘[ / ⇧⌘[ annotations, colour keys show swatch dots, and key 51 is marked as holding the layer.

GEOMETRY
- The research JSON's thumb model is inferred from CSS and wrong about thumb sizes; it lists both thumbs as 0.933 squares. The screenshot clearly shows a taller inner thumb, so the thumb pivot, sizes and the 4.9u half gap are calibrated from pixel measurements of the screenshot.
- Thumbs use 1u-wide caps (Oryx draws them 0.933 wide).
- `stagger: .qmk` gives QMK's 0.25/0.5u alternative. The true physical stagger is unknown, since ZSA publishes no CAD.
- A self-check confirms that no caps overlap.

COVERAGE
- All 111 codes in the user's layout and all 198 codes across the 5 public example layouts are catalogued.
- All 139 SF Symbol names used were validated with NSImage.
- Labels, names, keywords and settings text are in our own words. The trimmed settings JSON keeps Oryx's ids, types, defaults and ranges (Voyager debounce default is 5). The generator script is in the scratchpad, not in the package.

MOCK DATA ASSUMPTIONS
- The status LEDs show the active layer's bits, per the research notes on voyager.c.
- The reset pinhole is on the top edge of the left half.
- The user's real config is empty (only qmkCanary), so `Samples.settingsOverrides` is illustrative.
- Revisions 1–3 and the build error are synthesised plausibly.
- The firmware size (65,786 of 122,880 bytes) and md5 come from the real build artifacts.

SNAPSHOT ENGINEERING
- Setting `sizingOptions = []` on the hosting controller made NavigationSplitView throw "more Update Constraints passes than views". Default sizing is kept, so a window may grow to its minimum size, and the runner prints a note when it does.
- The window subclass overrides a few private AppKit selectors (`_hasActiveAppearance` and similar) so switch tracks draw in their active colour. These are plain method overrides on a throwaway offscreen window.

FILES
- I wrote only inside design/PrototypeKit: Package.swift, Sources/, snapshots/, .gitignore, and .build/ from building.
- Scratch experiments are in the session scratchpad (snapexp/ and consumer/).
- No markdown files were written.
