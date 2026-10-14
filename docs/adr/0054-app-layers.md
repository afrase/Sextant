# 54. App Layers: rules beside the layout, and when SET_LAYER may be sent without a click

Status: accepted, 2026-10-15, except the consent model, which awaits the user's confirmation (below). v1 plan slice 4.2.
Builds on ADRs 0038 (keyboard commands), 0039 (the keyboard's layout is the flashed revision), 0048 (Move Keyboard to
Layer), 0049 (the menu bar panel) and 0057 (Live View starts by hand); amends spec §8.3 and §8.6.

## Context
Spec §8.6 adds App Layers: when an app comes forward, the keyboard moves to a layer chosen for that app, and back to the
base layer when the user leaves it. It is the first feature that writes to the keyboard (SET_LAYER, `04 01 n`) without a
click each time, which the hardware-safety rule otherwise forbids. The v1 plan's question 2 asked the user whether that
is acceptable; the user hasn't answered yet, so the plan's recommendation is built and marked as such here.

Rules need a home. Kept in `layout.json`, every rule edit would change the layout's content hash, mark it "Edited" and
change the `sx-` fingerprint, so the keyboard would seem to run another build after a rule change. The frontmost app is
private enough that recording it needs care: which apps the user switches to, and when, is a log of their work.

## Decision
- **The consent model (awaiting the user's confirmation).** The plan's recommendation, built as it stands:
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
  nothing. Nothing is sent when the keyboard already reports that layer.
- **The latest activation wins.** An app must stay frontmost for 150 ms (on the injected clock) before App Layers acts,
  so a burst of activations (windows closing, a Space changing) moves the keyboard once, for the app that ends up in
  front. "The app left" is the last one that settled.
- **The decision is pure domain.** `AppLayerRules.target(activated:previous:in:)` takes bundle ids and the keyboard's
  layout and returns the layer or nil; `AppLayerRule` holds the bundle id, the app's name, the layer's id (so a rule
  follows its layer when layers move), When leaving and Enabled.
- **Rules live beside the layout.** `app-layers.json` in the package, through two `LayoutLibrary` methods
  (`appLayerRules(of:)`, `saveAppLayerRules(_:for:)`), with its own `formatVersion` (1). A missing file reads as no rules.
  Saving it never touches `layout.json` or `meta.json`, so the content hash, the modification date, "Edited", the
  revisions and the `sx-` fingerprint stay as they were. Duplicate copies it (one that can't be read doesn't stop the
  copy); Trash takes it with the package. A file that can't be read (damaged, or from a newer Sextant) is never
  overwritten: the page says so and editing is off.
- **Rule edits aren't document edits.** They save at once, in order, and aren't on the window's undo stack, like Settings.
  A failed save is kept in `saveError`; the rules in memory keep the change.
- **Ports and adapter.** `FrontmostAppWatcher` (`Ports/System.swift`): the frontmost app now, then each app that comes
  forward; the running apps with a Dock icon; the app at a URL (Add App › Choose…). A `MacApp` is a bundle id and a
  name, nothing else. `WorkspaceAppWatcher` adapts `NSWorkspace.didActivateApplicationNotification` in the `SextantApp`
  composition root (no TCC; there is no `SextantSystem` target).
- **`AppLayerSwitcher`** (application, app-wide, on `SextantServices`) follows the watcher, loads the rules of the layout
  the keyboard runs, sends, and answers `state(for:)` (off, paused with the reason, on) and `applied(for:)` (the frontmost
  app's rule while the keyboard is on its layer) for the UI.
- **Privacy.** The switch history is the last 20 switches, newest first, in memory only: the app names ("Xcode →
  Sym+Num", "Left Xcode → Main") and the time, no bundle ids, never logged or stored. Bundle ids are kept only in the
  rules the user makes.
- **UI.** The App Layers page (header with the switch and Add App…, a Now card with the keyboard's layer map, the rules
  table, the footnote), `AppLayersInspector` (the rule, a warning when its layer is gone or not flashed yet, Recent
  Switches), the sidebar row with the rule count, the empty state, the lens lane's app-rule capsule ("Xcode is frontmost
  → keyboard on Sym+Num" [Rules…], last in priority), and the menu bar panel's App Layers row (what holds now, and the
  keyboard layout's switch). The row shows only when that layout has rules; the layer list then shows one row fewer
  before it scrolls, and the two switches sit 6 pt apart, so the panel stays under 520 pt with all 32 reachable layers.
  The Now card offers Turn On Live View while Live View is off; App Layers itself never starts it. The feature is never
  called "Smart Layers"; the footnote, in Sextant's words, says layer_move also turns off toggled, one-shot and the
  Navigator's mouse layers.

## Consequences
- Agents never send SET_LAYER to the user's Voyager. `AppLayerSwitcherTests` run on `FakeFrontmostAppWatcher`,
  `FakeKeyboardLink`, `FakeDeviceWatcher` and a `TestClock`; snapshots use a stand-in keyboard and frontmost app. The real
  adapter is never started in tests. Trying App Layers on the keyboard needs the user's OK in chat for SET_LAYER.
- A layer the user holds or toggles is dropped by the move when they switch apps, as the footnote says.
- Switching to Sextant itself is an app switch like any other: leaving a Return to Main app for Sextant returns to Main.
- The rules of a layout apply only while the keyboard runs it; a duplicate's copied rules apply once the duplicate is
  flashed.
- Not done: per-window rules, rules by window title, and moving on launch or on Live View start.
