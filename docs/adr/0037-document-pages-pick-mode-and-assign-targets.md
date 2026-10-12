# 37. Document pages, board pick mode, assign targets and shared model hooks

Status: accepted, 2026-10-12. Amends ADR 0028: the picker writes to a target, not only the selected slot. v1 plan slices 0.1 (pages, picks, targets) and 0.2 (shared model hooks), built in parallel and merged as one decision.

## Pages, picks and targets

### Context
v1 adds four document pages next to Firmware Settings (spec §2.2: Combos, Macros, History, App Layers). It adds two gestures that take board clicks: Assign to Key (§6.3) and choosing a combo's members (§6.4). It also adds picker targets that aren't a key's slot: "Combo 3 › Output", macro steps, multi-selection. In the MVP the destination was a Bool, `showsFirmwareSettings` (26 uses in 10 files). The picker could write only the selected key's slot (ADR 0028), and every board click selected. Without shared hooks, every feature slice would edit the same sidebar, detail, inspector, picker and board code (v1 plan, wave 0).

### Decision
- **`destination: Destination` replaces the Bool.** `Destination` declares every v1 page now: `.layer(Int)`, `.firmwareSettings`, `.combos`, `.macros`, `.history` and `.appLayers`.
  - A layer is the session's selected layer, so Follow and undo keep moving it. The model stores only `page` (nil on the board) and derives `.layer(n)`.
  - WindowDetail reads `page`, so a layer switch still doesn't re-run it.
  - Combos and History show the board (§2.2), so changing the layer there keeps the page. A layer picked by hand and the layer commands leave only the pages that replace the board. Choosing a layer as the destination (sidebar, ⌘1–9, ⌘K's layer rows, Find Key) always shows its plain board.
  - The unbuilt pages route to `EmptyView` in WindowDetail and InspectorColumn and have no sidebar row, so nothing reaches them. Each feature adds its row and replaces its one route line.
- **Combos and Changes are board modes of their destinations, not `Lens` cases.** `Lens.allCases` drives View ▸ Lens (⌃⌘n), the canvas picker and the palette, and spec §9.1 lists only Keys, Lighting and Heatmap.
- **`BoardPick` is a gesture in progress:** a prompt, `onPick(index) -> Bool` and `onCancel`, on the window model.
  - While one is set, board clicks, VoiceOver's activate and ⏎ on the focused board go to it instead of selecting, so the keyboard alone can pick (arrows, then ⏎). Typing and ⌫ do nothing, and painting and drag-to-swap are off. `true` from `onPick` ends it.
  - Starting one, or showing the board while one is on, focuses the board, so ⏎ and esc work at once.
  - Its prompt takes the lens lane's status capsule, with [Cancel], ahead of an issue. It is the only place that says what a click does. Record Key started during a pick hides it until recording ends, since esc ends recording first (§9.3 step 1).
  - Esc on the board cancels it before deselecting (§9.3 step 4, then step 5).
  - Opening another layout cancels it, so its `onCancel` runs.
  - The selected key's picker can still open during a pick (Key ▸ Change Keycode…), but a click on a key closes it and goes to the pick instead of retargeting.
- **`AssignTarget` is what the picker writes to:** the scope token's text, an optional key to show and preview, the current value, and an assign closure.
  - `Palette.target` holds a feature's target. Nil means the selected key's slot, which is today's behavior. It is built live from the selection, so ⌘⏎, ⌥⇥ and a click on another key still retarget it.
  - A feature's target works on any page. ⌘⏎ assigns and closes (there is no next key), ⌥⇥ does nothing, and a click on a key closes the panel like any click outside. The footer leaves out "& next" and ⇧⌘R. Dropping the token drops the target.
  - The board previews a target's key only on the shown layer, with the keycode as `assign` receives it: only the selected slot keeps its chord.
  - Opening another layout closes the panel, since a target's closure edits the layout it was made for.
- **NavigatorDisc moves to its own file** for Export, LayerMap and the HUD.

### Consequences
- Features add files plus one-line hooks: a sidebar row, one route line each in WindowDetail and InspectorColumn, and a `BoardPick` or `AssignTarget` value. Combos and Macros never edit BoardView's click code or the picker's assign path.
- The general palette offers "Assign to …" keycode rows only where the key is shown. On a page they used to do nothing.
- In the Lighting lens a pick shows plain caps, since lit caps take no clicks.
- Multi-select's "3 keys › Tap on Main" is the default target, not a feature's: slice 2.2 replaces `keySlotTarget`, the one picker function it edits, so ⏎, typing, ⌥⇥, ⌘⏎ and click-to-retarget keep working for it.
- A destination change doesn't end a pick. Assign to Key starts on the Macros page and switches to the board, so the feature that makes a pick ends it.
- Window snapshots are pixel-identical.

## Shared model hooks

### Context
The v1 document features (tap dances and per-key terms, Macros, Combos, Changes, History, Heatmap) are built in parallel branches. Three spots would collide on every one of them:
- the exhaustive `LayoutIssue.Kind` switch in `KeyText.issueText`;
- `EditSession`'s private members, which forced every new edit into EditSession.swift;
- `KeyCap`, which each board mode would have edited to draw its rings, badges, dimming and heat.

Combo issues also had no locator: `.emptyCombo` carried `key: nil`, so two empty combos showed as one issue and the text couldn't say which. And `.tapDanceUnsupported` was dead, since the generator builds tap dances.

### Decision
- **Every v1 issue kind is declared now,** each with Sextant's own text: `macroStepNotTypable(step:code:)`, `comboTooManyKeys`, `duplicateComboTrigger`, `comboKeyTransparent`, `comboKeyTapDance`, `rollingNeighbors` (a warning), `notInTapDance` and `tappingTermIgnored` (a warning). No check raises them yet; each feature adds its own check function and one call line in `check`. `.tapDanceUnsupported` is deleted.
  - Transparent and tap-dance combo keys are two kinds, so the text can say which.
  - `comboTooManyKeys` is only for more than 6 keys. `emptyCombo` already covers fewer than 2, so one fault never raises two errors, and the count in "Combo has 7 keys; 6 is the most" is always plural.
  - A combo key's payload is its board index. The text names it by what it shows on the combo's layer, as spec §6.4 does: "Keys J and K are rolling neighbors · Combo 2". A key that shows nothing (transparent all the way down, or disabled) is named by its index.
- **`LayoutIssue.combo`** holds the combo's id. The existing combo checks set it, so each broken combo is its own issue, and the text names the combo: "Empty combo · Combo 3", or the combo's name when it has one.
- **EditSession's extension points are internal:** `edit(_:select:_:)`, `target(_:_:)`, `checkpoint(_:)` (taken out of `applyImport`), `library`, `revisionBaseline` and the setter of `revisions`. A feature puts its edits in `EditSession+<Feature>.swift` in SextantApplication. History can then restore a revision without editing EditSession.swift.
- **`EditorSelection.combo`** holds the selected combo's id; the undo snapshot already carries the selection. An edit that removes the selected combo clears it, so it never points at nothing (Delete Layer takes the combos limited to that layer). An import clears it too: Oryx numbers combo ids by position, so the old id could name another combo.
- **`KeyCapModel.decoration`** (`CapDecoration`) is plain data a board mode fills in:
  - an opacity (unchanged keys 0.4, non-members 0.45) and a 2 pt ring;
  - a top-right badge and a top-left number, each an SF Symbol name, a color token and its words for VoiceOver ("plus.circle.fill", "3.circle.fill"). They are drawn like the issue badge: white shows through the symbol's cut-out;
  - a fill and a count for heat. The count sits under the legend in 0.12u mono (spec §4.3) and has its own words for VoiceOver ("22k", "22,044 presses"). On a fill, the legend and the hold band take black or white ink by luminance, as a pressed key does (spec §8.5).
- **`KeyText.value`** appends the badge's, number's and count's words to a cap's VoiceOver value, through a `decoration` parameter.
- **Corner priority follows spec §4.8,** in `KeyCapModel.topRight`: issue > unknown code > badge > LED dot. The number has the top-left corner to itself. The plan's single chain (issue > diff > combo number > LED dot) put the combo number in the same corner; the spec gives it the other one. Rings: issue > decoration ring > layer ring. A decoration ring also hides the activator's halo, as an issue does.

### Consequences
- The defaults draw today's caps: board, window, inspector and picker renders match main's within the offscreen renderer's own run-to-run noise, and the existing snapshot references pass unchanged. A new snapshot of decorated caps, light and dark, pins the badge, number, ring, opacity, fill, count and ink.
- BoardView asks the window for each cap's decoration, `LayoutWindowModel.capDecoration(layer:index:)` in LayoutWindowModel+Decorations.swift, and passes it to the cap's VoiceOver value. Changes, Combos and Heatmap each add one case there and build their decoration in their own files, so none of them edits BoardView or KeyCap.
- SF Symbols number circles only up to 50, so a combo numbered above 50 has no number symbol.
- `Token` is now `Equatable` (light, dark and alphas), so `KeyCapModel` stays `Equatable` and an unchanged cap doesn't redraw.
- Slice 2.2 (multi-select) keeps `target(_:_:)` working next to its `targets()`, because extension files call it.
