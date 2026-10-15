# 54. App Layers: rules beside the layout, and when SET_LAYER may be sent without a click

Status: accepted, 2026-10-15; the user confirmed the consent model the same day. v1 plan slice 4.2.
Builds on ADRs 0038 (keyboard commands), 0039 (the keyboard's layout is the flashed revision), 0048 (Move Keyboard to
Layer), 0049 (the menu bar panel) and 0057 (Live View starts by hand); amends spec §8.1, §8.3 and §8.6, and ADR
0007's codec (two layer fields).

## Context
Spec §8.6 adds App Layers: when an app comes forward, the keyboard moves to a layer chosen for that app, and back to the
base layer when the user leaves it. It is the first feature that writes to the keyboard (SET_LAYER, `04 01 n`) without a
click each time, which the hardware-safety rule otherwise forbids. The v1 plan's question 2 asked the user whether that
is acceptable; the user hasn't answered yet, so the plan's recommendation is built and marked as such here.

Rules need a home. Kept in `layout.json`, every rule edit would change the layout's content hash, mark it "Edited" and
change the `sx-` fingerprint, so the keyboard would seem to run another build after a rule change. The frontmost app is
private enough that recording it needs care: which apps the user switches to, and when, is a log of their work.

## Decision
- **The consent model (the user confirmed it, 2026-10-15).** The plan's recommendation, built as it stands:
  - a layout's switch, "Switch layers when you change apps", together with at least one enabled rule, is the consent. The
    switch is off by default and adding a rule doesn't turn it on;
  - nothing is sent at launch (the app in front then only sets where switching starts from), when Live View starts, or
    when a rule or the switch changes: only an app switch sends;
  - it pauses, sending nothing and replaying nothing later, whenever Live View is off or not yet paired, Keymapp holds
    the board, the keyboard is in flash mode or unplugged, or the keyboard runs a layout other than the rules' own
    (another library layout, whose own rules then apply, or one Sextant doesn't have);
  - every layer is checked against the layout the keyboard runs as it was flashed (ADR 0039): a rule whose layer that
    build lacks (added since the flash, or deleted) counts as no rule.

  If the user answers otherwise, this part gets a new ADR.
- **What is sent.** Only `.moveToLayer(n)` through `OnKeyboard.moveKeyboard(toLayer:)`, so every refusal of ADR 0048
  applies (`04 01 n` then `01`; never `04 00 n`, which ADR 0038 makes unencodable). An activated app's enabled rule moves
  to its layer; leaving an app whose rule says Return to Main for one without a rule moves to layer 0; Stay sends
  nothing. The move is sent even when the keyboard reports that layer already: `05 <layer> FE` is the highest active
  layer, which may be a held layer key's, and research note O2 shows a stale one. layer_move is harmless when the
  keyboard is there.
- **A move waits for the keys to come up.** layer_move under a held MO(n) turns layer n off, so the key's release
  drops the keyboard to the base layer whatever the rule says, and under a held modifier it changes what the chord
  types. A settled app's move waits until `LiveSession.pressedKeys` is empty; a later activation replaces it. During
  secure input the presses are hidden, so it doesn't wait.
- **The pauses are the layer move's refusals.** `state(for:)` asks `moveKeyboard(toLayer: 0, dryRun: true)` (ADR 0048)
  and reports its `LayerMoveRefusal`, so App Layers' status can't drift from what a send would do; only "another layout
  runs" is its own, saying whether that layout's rules are on.
- **The latest activation wins.** An app must stay frontmost for 150 ms (on the injected clock) before App Layers acts,
  so a burst of activations (windows closing, a Space changing) moves the keyboard once, for the app that ends up in
  front. "The app left" is the last one that settled. Coming back to that app (from Sextant, or at the end of a burst)
  isn't a switch: it cancels any move still waiting and sends nothing.
- **Sextant isn't an app.** Its own activations (a layout window, Settings, the menu bar panel when it activates the
  app) never apply a rule and never count as leaving the app before: the last app to settle stays "frontmost". One
  also cancels a move still settling or waiting for the keys to come up, since that app never ended up in front. So
  opening Sextant and going back to the same app moves nothing: a layer chosen in Sextant meanwhile (a menu bar tile,
  Move Keyboard to Layer, a window's layer menu) holds, and a rule changed or the switch turned on there waits for a real
  app switch.
- **Layer ids survive Oryx revisions.** A rule names its layer by `Layer.id`, which an import takes from Oryx's layer
  `hashId`; Oryx gives every layer a new one in each revision and names the one before as `prevHashId`. So Add as
  Revision (`EditSession.applyImport`) keeps the document's id for each imported layer whose `hashId` or `prevHashId`
  is what Oryx last called one of its layers (`KeyboardLayout.keepingLayerIDs(of:)`, pure domain), and keeps Oryx's
  current id beside it (`Layer.oryxID`, written as `oryxHashId`; `prevHashId` is read and used at once, never written, so a fresh import's content hash doesn't move). The Oryx query asks for
  `prevHashId`, which Oryx's own `LayoutData` fragment reads. When an Oryx revision was skipped between imports, a
  layer's `prevHashId` names one Sextant never saw; it then takes the one unmatched earlier layer with the same title,
  when the title is unique on both sides (amended 2026-10-15). Nothing is matched by position: a layer added or moved in
  Oryx would take another layer's rules. Rules, Heatmap counts (ADR 0053) and History's comparisons follow their layers
  through every later revision. A layout without these fields is written as before, so existing content hashes and
  `sx-` fingerprints don't change.
- **The decision is pure domain.** `AppLayerRules.target(activated:previous:in:)` takes bundle ids and the keyboard's
  layout and returns the layer or nil; `AppLayerRule` holds the bundle id, the app's name, the layer's id (so a rule
  follows its layer when layers move), When leaving and Enabled.
- **Rules live beside the layout.** `app-layers.json` in the package, through two `LayoutLibrary` methods
  (`appLayerRules(of:)`, `saveAppLayerRules(_:for:)`), with its own `formatVersion` (1). A missing file reads as no rules.
  Saving it never touches `layout.json` or `meta.json`, so the content hash, the modification date, "Edited", the
  revisions and the `sx-` fingerprint stay as they were. Duplicate copies it (one that can't be read doesn't stop the
  copy, and neither does one that can't be written once the copy exists: the rules are optional beside it); Trash
  takes it with the package. A file that can't be read (damaged, or from a newer Sextant) is never
  overwritten: the page says so and editing is off.
- **Rule edits aren't document edits.** They save at once, in order, and aren't on the window's undo stack, like Settings,
  so Remove Rule asks first. A failed save keeps the change in memory for the run and stays in `saveError(for:)`, per
  layout, until `retrySave(for:)` or a later save of that layout lands. The page shows it with [Try Again] and the menu
  bar row with a warning mark: a switch turned off that didn't save would be on again at the next launch, resuming
  writes the user stopped.
- **Ports and adapter.** `FrontmostAppWatcher` (`Ports/System.swift`): the frontmost app now, then each app that comes
  forward; the running apps with a Dock icon, again as apps launch and quit; the app at a URL (Add App › Choose…). A `MacApp` is a bundle id and a
  name, nothing else. `WorkspaceAppWatcher` adapts `NSWorkspace.didActivateApplicationNotification` in the `SextantApp`
  composition root (no TCC; there is no `SextantSystem` target).
- **`AppLayerSwitcher`** (application, app-wide, on `SextantServices`) follows the watcher, loads the rules of the layout
  the keyboard runs, sends, and answers `state(for:)` (off, paused with the reason, on) and `applied(for:)` (the frontmost
  app's rule while the keyboard is on its layer) for the UI.
- **Privacy.** The switch history is the last 20 switches, newest first, in memory only: the app names ("Xcode →
  Sym+Num", "Left Xcode → Main") and the time, no bundle ids, never logged or stored. Bundle ids are kept only in the
  rules the user makes. Each switch notes the library layout whose rule made it, so a layout's page lists only its own
  (`history(for:)`): another layout's switches name that layout's layers.
- **UI.** The App Layers page (header with the switch and Add App…, a Now card with the keyboard's layer map, the rules
  table, the footnote), `AppLayersInspector` (the rule, a warning when its layer is gone or not flashed yet, Recent
  Switches), the sidebar row with the rule count, the empty state, the lens lane's app-rule capsule ("Xcode is frontmost
  → keyboard on Sym+Num" [Rules…], last in priority; "Xcode → Sym+Num" when the lane is narrow, as beside the Lighting
  lens's tools at 1120 pt, which give way first), and the menu bar panel's App Layers row (what holds now, and the
  keyboard layout's switch). The row shows only when that layout has rules; the layer list then shows one row fewer
  before it scrolls, as it does for the Heatmap's typing line (ADR 0053), and the two switches sit 6 pt apart, so the
  panel stays under 520 pt with all 32 reachable layers, both lines and secure input on (the typing line then says the
  pause for the mini map too).
  The Now card offers Turn On Live View while Live View is off; App Layers itself never starts it. The feature is never
  called "Smart Layers"; the footnote, in Sextant's words, says layer_move also turns off toggled, one-shot and the
  Navigator's mouse layers. Oryx's keys for Keymapp's feature (`ORYX_SL_TOGG`, `ORYX_SL_TRIGG`) are labeled "Smart
  Layers" and "Smart Layer" in the catalog, not "App Layers": they don't touch Sextant's rules.

## Consequences
- Agents never send SET_LAYER to the user's Voyager. `AppLayerSwitcherTests` run on `FakeFrontmostAppWatcher`,
  `FakeKeyboardLink`, `FakeDeviceWatcher` and a `TestClock`; snapshots use a stand-in keyboard and frontmost app. The real
  adapter is never started in tests. The user approved SET_LAYER on 2026-10-15, and a layer move and back passed on their Voyager (`RealKeyboardTests`).
- A layer the user toggles is dropped by the move when they switch apps, as the footnote says; a held one isn't, since the
  move waits for its release.
- Sextant itself coming forward isn't an app switch (`ownBundleID`, from the composition root), and neither is going
  back from it to the app before: reading the rules, clicking [Rules…] or opening the menu bar panel leaves the keyboard
  where the last app put it, so the Now card and the lane can show the rule that holds. Add App doesn't offer Sextant.
- A move waiting for the keys to come up is dropped when Sextant comes forward: the keyboard stays where it was until
  the next app switch.
- Revisions imported before layer ids were kept carry Oryx's ids of their day: restoring one of those leaves rules
  made since orphaned (the inspector says the layer is gone) until they are pointed at a layer again. A working copy
  from such an import still matches: its ids are the `prevHashId`s of Oryx's next revision.
- The rules of a layout apply only while the keyboard runs it; a duplicate's copied rules apply once the duplicate is
  flashed.
- Not done: per-window rules, rules by window title, and moving on launch or on Live View start.
