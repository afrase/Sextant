# 48. Moving the keyboard's layer, and global layer shortcuts

Status: accepted, 2026-10-14. Builds on ADRs 0038, 0039 and 0057; amends spec §9.4.

## Context
v1's first keyboard write moves its layer (`04 01 n`, SET_LAYER, ADR 0038) from Keyboard ▸ Move Keyboard to Layer, the
Device popover and global shortcuts, ⌃⌥0–⌃⌥9 by default (spec §9.4). The menu bar extra and App Layers will reuse the
same move, and the menu bar and the overlay HUD need a small read-only map of a layer.

A layer number the keyboard's build doesn't have isn't harmless: past the build's layer state it truncates to no layer
and drops the board to its default layer (ADR 0038). Live View is off until the user turns it on, and nothing is written
before then (ADR 0057).

Spec §9.4 named Carbon's `RegisterEventHotKey`, with remapping in Settings. The user approved
sindresorhus/KeyboardShortcuts (MIT), which wraps that call (no TCC) and adds a recorder, rather than a hand-written
Carbon adapter with only a modifier-set picker.

## Decision
- **One move.** `OnKeyboard.moveKeyboard(toLayer:dryRun:)` sends `.moveToLayer(n)` through `LiveSession.send`, and only
  over a paired Live View session, to a layer of the layout the keyboard runs: `running.layout`'s layers, or only layer 0
  when Sextant doesn't hold that layout. Otherwise it throws a `LayerMoveRefusal` with Sextant's words: no keyboard, flash
  mode, Live View off ("Turn on Live View to move the keyboard’s layer."), held by Keymapp, still connecting, unknown
  layout, no such layer. A dry run only answers, so the menus can disable their items without sending.
- **Menus.** Keyboard ▸ Move Keyboard to Layer and the Device popover's copy list the keyboard layout's layers by name,
  check the one it's on, and move it to the one chosen. While it can't move, the items are disabled under a heading that
  gives the reason; when Sextant doesn't have the keyboard's layout, a heading says why only layer 0 is offered. The
  Keyboard menu's copy reads the app-wide `OnKeyboard` and `LiveSession`, so it works with no layout window open or
  with Settings key.
- **Shortcuts.** `LayerShortcuts` (application, app-wide, on `SextantServices`) drives a `HotKeys` port: register ten
  layer shortcuts, unregister them, read each one, report conflicts. Off by default; turning it on registers all ten,
  turning it off unregisters them, and the choice is saved through a closure from the composition root
  (`KeyboardSettings.layerShortcutsOn`). A press goes through the same move. One that can't move sends nothing; it beeps,
  since Sextant may be in the background, and Settings › Keyboard shows why under its switch. `refusal` is derived from
  the refused layer by a dry run, so it gives the reason as things stand now and clears once that press would send
  (Live View turned on since, say); it never asks for a fix the user has already made. The menu bar extra (slice 3.1)
  is where a reason can show without opening Settings; until then the beep and Settings are all.
- **Standing aside for Sextant's recorders.** Carbon consumes a registered hot key's press before AppKit sees it, so
  with the shortcuts on, Record Key and Record Steps could never record ⌃⌥ digits, and the press would move the keyboard
  instead. `RecordKeyMonitor` calls `LayerShortcuts.suspend()` while it listens and `resume()` when it ends (calls
  nest); the port's `setPaused(_:)` maps to the library's `KeyboardShortcuts.isEnabled`, which unregisters the hot keys
  with Carbon until it's turned back on. Conflicts are reread on resume, not while paused.
- **Conflicts.** A shortcut the system won't register (another app holds it exclusively) or that a macOS shortcut uses
  is listed under the shortcuts with what to do. The recorder refuses a shortcut without ⌃ or ⌘ and one another layer has: with only ⌥ or
  ⇧, or none, a global shortcut takes a key the user types with in every app (⌥2 types ™). macOS itself would take ⌥
  alone: the refusal the library documents hit only sandboxed apps on macOS 15.0 and 15.1, and Sextant is neither. The
  library's own checks still apply: it blocks a shortcut the app's menus use and warns about a macOS one.
- **One press, one move.** The menu items show a layer's shortcut only while the shortcuts are on and that one can fire.
  A registered hot key takes the key press before the app's menus see it (Carbon in normal use; while a menu is open the
  library's own event monitor takes and consumes it), so a press never runs both the hot key and the menu item. With
  the shortcuts off, the menu items have no shortcut, so ⌃⌥ digits do nothing in Sextant either. The popover's copy never
  shows shortcuts: a pop-up button's menu answers its key equivalents while the popover is key.
- **Where the library lives.** `KeyboardShortcuts` 3.1.0 (MIT, pinned exactly; released 2026-09-11, Swift 6 with
  main-actor default isolation, swift-tools 6.2, so it builds on CI's Swift 6.3) is a dependency of the `SextantApp`
  composition root only. `KeyboardShortcutsHotKeys` adapts it to `HotKeys` there (one `KeyboardShortcuts.Name` per layer,
  `moveKeyboardToLayer<n>`, ⌃⌥n initially, stored by the library in UserDefaults and made only once the shortcuts are on
  or being recorded) and hands `SextantScenes` the recorder as a `LayerShortcutRecorder` view factory, so `SextantUI`
  never imports the library (its lint rule refuses it). No `SextantSystem` target.
- **The port is main-actor**, unlike the async `Sendable` ports: the system delivers hot-key events on the main thread
  and the library is main-actor.
- **LayerMap** (`SextantUI/Device`) draws one layer of a layout read-only, scaled to fit, with the Navigator disc, the
  caps the layer defines ringed in its color (the board's own `KeyCap`) and the keys down lit. VoiceOver reads it as one
  element: "Sym+Num layer, keys down k24". The menu bar extra and the HUD use it; nothing in the window does yet.

## Consequences
- Agents never send SET_LAYER to the user's Voyager. `LayerShortcutsTests` runs on `FakeHotKeys`, `FakeKeyboardLink` and
  `FakeDeviceWatcher`; the real adapter is never built into `swift test`, so no test takes ⌃⌥ digits system-wide. Trying
  a real move needs the user's OK in chat for SET_LAYER.
- The shortcuts work without a window and whichever app is frontmost, but only while Live View is on.
- Another app that registers the same keys without holding them exclusively isn't detected; which app gets the press is
  then up to the system.
- Two layers can't share a shortcut through the recorder, but nothing stops two names sharing one in UserDefaults; the
  library then runs both handlers, which move to both layers in turn.
- Settings snapshots draw a stand-in for the recorder (the snapshot tool doesn't link the library).
