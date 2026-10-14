# 49. Menu bar extra and activation policy

Status: accepted, 2026-10-15. Builds on ADRs 0038, 0039, 0045, 0048 and 0057; amends spec §2.1, §8.3, §8.9 and §9.1.

## Context
Spec §8.3 adds a menu bar extra in v1: a label with the sextant mark and the keyboard's layer, and a panel with the
layer as tiles or rows, a mini map, the overlay switch and native rows (Build & Flash…, Open Sextant, Settings…, Quit).
Spec §2.1 adds a setting that takes Sextant out of the Dock once its last layout window closes. Several things were
left open: whether the extra shows by default, how a label made of a template glyph and a number can be drawn when a
`MenuBarExtra` label renders only an Image and a Text, what the panel shows while Live View is off (ADR 0057), which
layout its Build & Flash and Open Sextant act on, and how a menu-bar-only app avoids leaving the user with no Dock icon
and no menu bar item.

## Decision
- **Shown by default.** Settings › General › "Show in menu bar" is on by default (the spec gave none): the extra is
  where the layer moves and the shortcut refusals of ADR 0048 can be seen without opening a window. It is the
  `MenuBarExtra(isInserted:)` binding, so removing the item from the menu bar (⌘-drag) turns the setting off too. "Show
  the layer's color in the menu bar" and "Keep Sextant in the menu bar when its windows are closed" are off by default
  and only apply while it shows.
- **A pre-rendered label.** `MenuBarLabelState` (pure) maps the connection, layer and flash progress to the glyph and its
  VoiceOver text, and draws one `NSImage`: the mark (`SextantGlyph`, the Welcome's `SextantMark` stroked heavier as one
  filled outline) with the layer number composed in, in SF Pro Rounded 11 bold. It is a template image, so the menu bar
  tints it. With no keyboard the mark is at 50% alpha and has no number; a number shows only while a paired session
  reports a layer. While a flash writes, a band fills the arc from its left end with `LiveSession.flashProgress`. With
  the color dot on, the image is not a template: the mark and number are drawn in the label color as the system draws
  the image, and the dot in the layer's color.
- **`LiveSession.flashProgress`** (application) is the whole write in 0–1, erasing as the first half and writing as the
  second, in 5% steps so the menu bar redraws at most twenty times. `BuildFlashSession` sets it next to
  `isWritingFirmware`: 0 when the write starts, nil when the flash is recorded or fails. Verifying keeps it at 1.
- **The panel** (`MenuBarPanel`, 360 pt) draws from a `MenuBarPanelState` value read from `LiveSession`, `OnKeyboard`,
  `LayerShortcuts` and `Library`:
  - the header names the board, the connection, and what the keyboard runs as it was flashed: the library title and
    revision number (ADR 0039), or its serial when Sextant doesn't have that layout; the status-light pips show the layer;
  - no keyboard, flash mode (with the write's progress) and held by Keymapp each show a line saying so;
  - **Live View off** shows "Turn On Live View", which calls `LiveSession.startLive()` as the toolbar's button does.
    It is the only way the panel starts anything, and only on that click; nothing starts when the panel opens;
  - with Live View on, "Layer on the keyboard" has a tile per layer up to four, otherwise rows with each layer's global
    shortcut (`LayerShortcuts.menuShortcut(forLayer:)`, so only while the shortcuts are on and that one can fire). A
    click goes through `OnKeyboard.moveKeyboard(toLayer:)` only. While that would send nothing (still connecting), the
    items are disabled under the refusal's own words; a layout Sextant doesn't have offers layer 0 alone, under the same
    heading Move Keyboard to Layer uses. The rows scroll after five, which with all 32 reachable layers keeps the panel
    under 520 pt (spec §13.3; a test measures every state);
  - the `LayerMap` of the keyboard's layer with the keys held down, paused during secure input;
  - the overlay switch, bound to Settings › Keyboard's `showsOverlay` (ADR 0045);
  - menu-style rows with their shortcuts: Build & Flash… (⌘R; "Flashing… 64%" while a flash writes), Open Sextant (⌘0),
    Settings… (⌘,) and Quit Sextant (⌘Q).
- **Window requests.** `WindowRouter` (UI, app-wide, built once in the composition root with an `AppPresence`) serves
  the panel and Window ▸ Main Window (⌘0, now enabled). It opens or brings forward the window of a target layout with
  `openWindow(id:value:)`, then calls `NSApp.activate()`. The target is the layout a Build & Flash is flashing, else the
  keyboard's (`OnKeyboard`), else one open in a window, else the most recently modified; an empty library opens the
  Welcome, unless a window is already open. Build & Flash… also leaves a pending request for that layout, which its
  window takes when it shows the layout and can build, and runs as ⌘R does. A request no window takes within 10 s is
  dropped, so it never starts a build the next time that layout opens. While a flash is under way, the row only brings
  its window forward.
- **Activation policy.** `AppPresence` counts layout windows (each reports its appearance and disappearance) and sets
  `.accessory` only when the last one closes while both "Show in menu bar" and "Keep Sextant in the menu bar…" are on.
  It sets `.regular` before any request opens a window (so the Dock icon and the main menu are back before the window
  appears), when a window appears by any other path, and as soon as either setting is turned off. Turning both on doesn't
  hide the Dock icon until the last window closes. Since `.accessory` needs the extra in the menu bar, Sextant always has
  one of the two.

## Consequences
- Nothing new is written to the keyboard. Reading needs Live View on (pairing writes `FE`, `00`, `01`, ADR 0057); tile and
  row clicks send `04 01 <n>` through ADR 0048's move, under the same SET_LAYER approval. Agents test only on stand-ins:
  `MenuBarTests` and `AppPresenceTests` use fake devices, a recorder for the policy and closures for `openWindow`.
- The panel's state is a value with a public initializer, so `SextantSnapshots` draws every state without a keyboard.
- Unverified in the app, for the user to check: the template rendering of the label in light and dark menu bars, the
  color-dot variant's label color, the panel's dismissal after a row opens a window, and focus.
- The rows don't close the panel themselves: it is expected to close when the window they open becomes key, which every
  row but the layer items and the overlay switch does. The user checks this in the app.
- The pending Build & Flash is UI state, not a use case: it lives only until a window takes it or 10 s pass.
