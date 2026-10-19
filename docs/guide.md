# Using Sextant

A tour of what Sextant does beyond editing keys. The [README](../README.md) covers installing it; [the UI spec](design/ui-spec.md) has every detail.

## Editing

A layout window has three columns: the layers and pages in the sidebar, the board in the middle, and an inspector for whatever you select. Select a key to change its tap, hold, double-tap and tap-then-hold actions, its modifier chord, label, LED color and tapping term. Select several keys (⌘-click adds a key, ⇧-click a range) to edit them together. Cut, copy and paste work on keys, and Copy To copies a layer onto another. Everything undoes.

The sidebar's pages edit the rest of the layout: Combos, Macros, App Layers, History and Firmware Settings (including the Navigator trackpad or trackball). ⌘K opens the command palette, which finds commands, keys, layers, keycodes, firmware settings, macros, combos and revisions.

## Importing

File ▸ Import from Oryx… (⇧⌘I) takes a layout link from Oryx, or reads the layout id the connected keyboard reports. Sextant reads Oryx's public GraphQL only: no login, and nothing changes in your Oryx account. An import can become a new layout or a new revision of one you have.

## Build & Flash

Build & Flash (⌘R) builds the firmware on your Mac, asks you to put the keyboard in flash mode, checks the image and writes it (see [Safety](../README.md#safety)). The first build downloads about 200 MB of build tools, each checked by size and SHA-256. It asks first if the keyboard runs a different layout.

## Live view

The live view shows the active layer and the keys you press. It starts only when you turn it on: click the live button in the toolbar, or choose Keyboard ▸ Live View. Plugging the keyboard in never starts it, because pairing writes to the keyboard.

While it's on:

- **Select by pressing:** Key ▸ Select Key by Pressing It (⇧⌘L) selects the next key you press on the keyboard.
- **Move the keyboard to a layer:** Keyboard ▸ Move Keyboard to Layer, the Device popover or the menu bar. Settings › Keyboard can turn on global shortcuts that do the same from any app, ⌃⌥0–⌃⌥9 unless you record others. They're off by default, and while they're on other apps don't get those keys.
- **Layer overlay:** holding a layer key brings up that layer's map over whichever app you're in; letting go hides it. A layer you lock (a toggle, say) shows a small reminder instead until the keyboard is back on its base layer. The overlay never takes focus or clicks, hides while you type in a password field, and can be turned off in Settings › Keyboard, the Keyboard menu or the Device popover. Settings › Keyboard also sets where it appears (any corner, edge or the centre, how far from the edge, and on which display), its opacity, size and delay, whether typing on the layer hides it (until you pause for the delay, or until you hold the layer again), and its Preview button shows it with those settings while you adjust them.
- **Lighting preview:** the Lighting inspector's Preview on Keyboard switch (or Keyboard ▸ Preview Lighting on Keyboard) shows the layer you're painting on the keyboard's LEDs, at a brightness you choose. Nothing is saved to the keyboard: the preview ends when you leave Lighting, open another layout, close the window, turn the live view off, put the Mac to sleep or quit, and the keyboard's own lighting comes back. If Sextant crashes during a preview, the colors stay until you unplug the keyboard.

## Two Macs, one keyboard

Turn on Settings › Build › Store the layout in the firmware, and Sextant stores the layout inside the firmware it builds (about 1–2 KB of the 120 KB the firmware may take). When you plug the keyboard into another Mac and turn the live view on, Sextant there reads the layout back from the keyboard if it doesn't have that version. The first time, it asks where it goes: a new layout, or a new revision of one you have. After that, each Mac picks up the other's flashes by itself, as a revision marked "From the keyboard", so the overlay, the menu bar, the heatmap and App Layers keep working. If you've changed the layout on that Mac since its last flash, nothing is replaced: the layout window offers "Keyboard runs revision N" and Use It.

It's off by default: while it's on, any app on a Mac the keyboard is plugged into could read the layout, macros included. The keyboard has to be flashed once with it on before another Mac can read it. If a layout is too large to store, or the firmware would be too large with it, the build leaves it out and its log says so.

## Menu bar

Sextant's menu bar item shows the keyboard's layer and, while a flash writes, its progress. Its panel can turn the live view on, move the keyboard to a layer, and start Build & Flash. When you close Sextant's last window it leaves the Dock and stays in the menu bar; open it again from the menu bar item, Spotlight or Finder. Settings › General can keep the Dock icon instead, or hide the menu bar item.

## App Layers

The App Layers page moves the keyboard to a layer when an app comes forward: Xcode on your symbols layer, say, and back to the base layer when you leave it. It's off until you turn on "Switch layers when you change apps" with at least one rule, and it works only while the live view is on and the keyboard runs that layout as you flashed it; it sends nothing at launch. The rules are saved beside the layout, so they never mark it edited. Sextant remembers the last 20 switches, by app name, until it quits.

## Heatmap

The Heatmap lens (View ▸ Lens ▸ Heatmap, ⌃⌘3) colors each key by how often you press it, with layer share, hand balance, a finger histogram and your busiest keys, over 24 hours, 7 days, 30 days or everything kept. Recording is off until you turn it on in Settings › Privacy or the lens, and then counts only while the live view is on and the keyboard runs a layout in your library. It saves counts per key position by the hour, never characters or the order you typed in, pauses in password fields, and stays on your Mac. Counts are kept for 30 days unless you choose otherwise; Clear Heatmap Data… deletes them.

## Updates

Once a day, Sextant asks GitHub whether a newer version is out, and says so in the menu bar panel and the Sextant menu. Sextant ▸ Check for Updates… asks now. The Software Update window links the release notes and the download, or shows the `brew upgrade --cask sextant` command when Homebrew installed Sextant; nothing downloads or installs by itself. Skip This Version stops the notice until a newer one. Settings › General turns the daily check off.

## History and export

File ▸ Save Revision… (⌘S) keeps a snapshot on the History page, where you can compare it with the current layout and restore it; every flash is recorded there too. File ▸ Export saves the layout's JSON, its QMK source, the firmware (.bin), an image of a layer (PNG) or all layers (PDF).

## Your data

Layouts live in `~/Library/Application Support/Sextant/Library/`. The heatmap's counts, when recording is on, live beside them in `Heatmap/`, outside the layouts, so exports never include them. An Oryx import tells ZSA your IP address and the layout id you asked for. Once a day Sextant asks GitHub for its newest release, which tells GitHub your IP address and Sextant's version. Nothing else leaves your Mac except the build tools' download.
