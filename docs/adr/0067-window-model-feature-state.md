# 67. The window model keeps the document, routing and input modes; features hold their own state

Status: accepted, 2026-10-23.

## Context
`LayoutWindowModel` had grown into the place every feature parked its window state: the Lighting brush and its
confirmations, the layer rename and its alerts, the layout rows' rename and trash prompts, the export panel's file, the
Build & Flash sheet and the Device popover, the picker's recents and panel plumbing, the Firmware Settings scroll target.
About sixty stored properties across one 500-line file and 22 extension files. The pages that came later
(`MacrosModel`, `CombosModel`, `HeatmapModel`, `AppLayersModel`, `FirmwareSettingsModel`) already kept their state in a
model of their own that the window holds; the earlier features never got the same treatment.

## Decision
- **Each feature's window state lives in a small `@MainActor @Observable` model the window holds as a `let`:**
  `LayersModel` (rename in place, Clear Layer and Delete Layer confirmations), `LightingModel` (the brush, Clear Key
  Colours and the Custom… colour sheet), `LayoutsModel` (Rename Layout… and Move to Trash…), `ExportModel` (the one
  pending export, shared with the Heatmap's exports), `DeviceModel` (the Build & Flash sheet and log, the Device popover,
  the imported layout the serial is matched against, and the stand-ins a window without a live session shows) and
  `PickerModel` (recent keycodes and commands, the board-focus and dismissing-click plumbing). `FirmwareSettingsModel`
  takes the scroll target. Views bind to them directly (`@Bindable var lighting = model.lighting`).
- **The window keeps what is the window's:** the document (`session`, `buildFlash`, `history`), routing (`destination`,
  `page`, `lens`, `legendMode`, the columns), its input modes (`palette`, `recorder`, `selectByPress`, `boardPick`), the
  injected app-wide use cases, and the orchestration that needs the session. The `extension LayoutWindowModel` files stay
  where they are: a feature's actions still read the session and the window's routing, and now its own model.
- **Nothing moved that one window-wide rule reads across features.** `isEditingText` reads the models it needs; the
  stand-ins behind `activity` and `isFollowing` moved with the device state they belong to.

## Consequences
- The window model lost 23 stored properties and no behaviour; every test passed unchanged in intent, with call sites
  renamed (`model.lighting.brushColor`, `model.device.showsBuildSheet`, `model.exports.pending`).
- A new feature adds a `<Feature>Model` and one `let` on the window, as the pages already did, rather than fields.
- `buildFlash` stays on the window: it is a per-layout use case the window opens and closes, like `session`, not
  presentation state.
