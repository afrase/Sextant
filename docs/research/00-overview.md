# 00 - Overview: how Oryx works, and how Sextant should replace it

Study date: 2026-10-11. Project: **Sextant**, a native macOS (Swift/SwiftUI) configurator for the user's ZSA Voyager.
Target device: layout `KlgM7`, revision `40xJ7M`, geometry `voyager`, firmware "25.0". It has 3 layers (Main, Sym+Num, Brd+Sys) of 52 keys each, plus a Navigator **trackpad** on the right half (`oryx/layout-full.json` `revision.navigators.right.kind = "trackpad"`).
Audience: the engineer who will build Sextant. This file is the map. Details and primary citations are in the linked reports.

Conventions:
- `02 §8.5` means section 8.5 of `02-firmware-and-flashing.md`. Each report cites primary sources (repo@commit:path:line, URL or bundle offset) and ends with an "Independent verification" section. Where a verification contradicted its author, this overview follows the verification.
- **INFERRED** marks a conclusion drawn by reasoning, not read in a source.
- **[00-verified]** marks a fact I re-checked myself for this overview. "Bundle" means `downloads/oryx-frontend/index-xhNfd6BI.js` (md5 `34fbb4d676e5dd056e2acf1999f26dae`, fetched 2026-10-11). Offsets are **byte** offsets into that file and are valid only for that deploy.
- Paths were written relative to the study session's scratchpad. In this repo: `study/*` → `docs/research/data/*`; `oryx/layout*.json`, `oryx/examples/*` → `docs/research/oryx-examples/`; the generated Oryx source zips (golden tests) → `docs/research/oryx-examples/sources/`. `downloads/*` (bundles, clones) were not kept.

**Report 01 (Oryx internals)** was blocked from being written during the study, so this overview cites its artifacts directly. Afterwards it was rendered from the agent's structured findings plus its independent verification: [01-oryx-internals.md](01-oryx-internals.md). Gap 10.A.1 still applies to the parts noted there.

| Report | Scope |
|---|---|
| [01-oryx-internals.md](01-oryx-internals.md) | Oryx SPA and GraphQL API, auth, edit/compile lifecycle, data model, keycode catalog, Voyager geometry, design tokens, WebUSB flasher |
| [02-firmware-and-flashing.md](02-firmware-and-flashing.md) | Generated QMK source, the Oryx JSON to C mapping, ZSA's QMK fork, local builds, the `.bin` format, the Ignition bootloader, the DFU algorithm, brick risk, macOS USB |
| [03-live-hid-and-ecosystem.md](03-live-hid-and-ecosystem.md) | The Oryx raw-HID protocol v5, Keymapp and its gRPC API, HID exclusivity, TCC, sandbox, VIA/Vial, dynamic keymaps, open-source host apps |
| [04-features-prior-art-legal.md](04-features-prior-art-legal.md) | Oryx feature inventory, prior art, ToS, trademarks, licences, the name, user pain points |
| [05-open-hardware-and-configurators.md](05-open-hardware-and-configurators.md) | Voyager hardware from open sources, Corne and other open splits, open configurators (QMK Configurator, VIA, Vial, ZMK Studio), reuse |

---

## 1. How Oryx works end to end

### 1.1 Diagram

```
 EDIT   configure.zsa.io SPA (MobX-state-tree models; Apollo-style GraphQL client)
 |        load    : POST https://oryx.zsa.io/graphql  query getLayout(hashId, revisionId|"latest", geometry)
 |        catalog : GET  https://configure.zsa.io/metadata.json   (2,526 keycodes, 61 categories)
 |        a compiled revision is read-only. "Start making changes":
 |                  mutation createLayout(title, revisionHashId, geometry, parentHashId, mcuAlternate)
 |                  -> new DRAFT revision (qmkVersion = null). Same layout if you own it, else a fork.
 |        each edit : updateKey(layerHashId, keyData, position)   [debounced 400 ms per key]
 |                    updateLayer / createLayer / reorderLayers / updateLayerColor / swapKeys
 |                    updateRevisionConfig(whole sparse config)   [debounced 400 ms]
 |                    upsertCombo / updateNavigators / updateRevisionSwatch / ...
 |                    saveLayoutSnapshot(layout) every 10 s while the network is failing
 v
 SAVE+COMPILE   mutation compileRevision(hashId)  -- synchronous, no polling
 |        ZSA server (closed): Oryx JSON --generator--> keymap.c, config.h, rules.mk, keymap.json (+ i18n.h)
 |                             qmk compile -j8  on zsa/qmk_firmware@firmware25 + modules/zsa
 |                             arm-none-eabi-gcc 12.2.1 (Debian), objcopy -O binary, dfu-suffix -v 3297 -p 0791
 |        returns md5, altMd5, qmkVersion, qmkUptodate, buildErrorLog, buildSource, buildConfig, buildRules
 v
 DOWNLOAD  GET https://oryx.zsa.io/firmware/{revisionHashId}     -> .bin (+16-byte DFU suffix); revision.md5 = md5(file)
 |         GET https://oryx.zsa.io/source/{revisionHashId}       -> zip: 4 sources, build.log, .bin, .bin.md5, README
 |         GET https://oryx.zsa.io/firmware/latest/{layoutHashId} -> {"latest": "<revisionHashId>"}
 v
 FLASH     user enters the bootloader: reset button (top edge, left half, above the 3 key) | QK_BOOT key | Bootmagic (top-left key; wipes EEPROM)
 |         Ignition bootloader enumerates as 3297:0791 (STM32) or 3297:1791 (GD32)
 |         flasher: Oryx WebUSB (Chromium only) | Keymapp | zapp CLI | dfu-util
 |         DFU 1.1 + ST DfuSe over EP0: erase 2 KiB pages from 0x08002000, write 2 KiB blocks, leave
 v
 RUN       keyboard re-enumerates as 3297:1977, USB serial "KlgM7/40xJ7M" (= SERIAL_NUMBER = layout/revision)
 |         4 HID interfaces; IF#1 = raw HID, usage page 0xFF60 / usage 0x61, 32-byte reports, no report ID
 v
 LIVE      WebHID (Oryx), Keymapp, typ.ing, zapp, community tools: Oryx protocol v0x05
           00 GET_FW_VERSION -> serial -> getLayout ; 01 PAIRING_INIT -> layer + key-down/up (col,row) events
           host can SET_LAYER, take over per-LED RGB, drive 4 status LEDs, step brightness. It cannot read or write the keymap.
```

Sources:
- Load query and fragments: `study/oryx-graphql-operations.json` (`getLayout` at char offset 635,491; `RevisionData` and `LayoutData` fragments).
- Bearer JWT from `localStorage.jwtToken`: bundle @631,007 [00-verified].
- Catalog: `BB="/metadata.json"` at bundle @695,823 [00-verified]. Counts: `study/oryx-keycodes.json` `_source`.
- Read-only rule: `get editable(){… return t?!1:e.qmkVersion===null||e.compiling===!0}` at bundle @794,080 [00-verified]. The draft-creating call `createLayout` with `mcuAlternate:S` is at @762,340 [00-verified].
- Mutation semantics and debounce timings: `study/oryx-graphql-operations.json` (`purpose` fields) and `study/oryx-config-settings.json` `persistenceRules`. These are from report 01's extraction and were not re-verified.
- Server build: 02 §2-§3 (`build.log` line 1 is the exact gmake command; line 5 is the compiler).
- Endpoints: 02 §2 and §8.4; zapp `zapp-oryx/src/lib.rs` lines 21-31 and 144-200 (04 verification row 5). `hexUrl`/`zipUrl` in GraphQL are signed Rails ActiveStorage redirects to DigitalOcean Spaces (02 §2).
- Flash: 02 §8. Bootloader entry: 02 §8.2. Live: 03 §3-§4.

### 1.2 Endpoints and protocols at a glance

| Step | Endpoint / protocol | Auth | Notes |
|---|---|---|---|
| Read layout | `POST https://oryx.zsa.io/graphql`, query `layout(hashId, revisionId, geometry)` | none for public or unlisted layouts | Introspection is disabled (`downloads/oryx-graphql/introspection.json`: "Field '__schema' doesn't exist"). The schema is reconstructed from 73 client documents: `study/oryx-schema.reconstructed.graphql`. `revisionId: "latest"` and `hashId: "default"` + `geometry` both work (schema comments). |
| Edit | 50 GraphQL mutations (`updateKey`, `updateLayer`, `updateRevisionConfig`, `upsertCombo`, ...) | `Authorization: Bearer <JWT>` (INFERRED for all mutations; none were called) | Undocumented, no public write API (04 §5.1). |
| Compile | `mutation compileRevision(hashId)` | JWT | Synchronous; returns md5 and build logs (`oryx-graphql-operations.json`). |
| Firmware | `GET /firmware/{rev}`; `?alt=true` only for **Moonlander rev B** (`3297:2003`); `?collate=true` for Moonlander/Halfmoon | none | `?alt=true` returns 404 for the user's revision (03 verification C2). Oryx web flips to `?alt=true` only when `requiresAltFirmware`, which is `vendorId===12951 && productId===8195` (bundle @883,627 [00-verified]). |
| Source | `GET /source/{rev}` | none | zip; the `.bin` inside matches `/firmware/{rev}` when fetched at the same time (02 verification C1, O5) |
| Latest | `GET /firmware/latest/{layoutId}`; `/firmware/latest/{geometry}/default` | none | used by `zapp update` (04 verification, omissions) |
| Flash | USB DFU 1.1 + DfuSe to `3297:0791`/`3297:1791`, interface 0, alt 0 | - | 02 §8.5 has the byte-level algorithm. Oryx downloads with the expected md5 and then **ignores** the comparison: `return t==Dc(s),Promise.resolve(s)` (bundle @885,887 [00-verified]). |
| Live | raw HID `0xFF60/0x61`, 32-byte reports | none; no TCC prompt | Oryx protocol v0x05: 14 commands, 15 events (03 §3 and verification C1) |
| Keymapp API | gRPC over a Unix socket `~/Library/Application Support/.keymapp/keymapp.sock` | opt-in, off by default | write-mostly, no event stream (03 §5.2) |

**Firmware for a revision is not immutable.** The `.bin` served for `40xJ7M` changed from md5 `4d59bb3d…` to `4f0376c0…` (02 verification C1). The re-fetched source zip has entry timestamps of **2026-10-11 00:01:52 UTC**, against the original build of 2026-09-16 05:08 UTC (`downloads/factcheck-01/src-now/source.zip` [00-verified]). Only the arbitrary `DUAL_FUNC_0` placeholder changed (`LT(15,KC_1)` → `LT(15,KC_F)`). What triggered the rebuild is unknown (section 10).

---

## 2. Data model and key-index to geometry mapping

### 2.1 Oryx's model (what Sextant imports)

```
Layout   { hashId, title, geometry: "voyager", privacy, tags[], parent, isDefault, revision }
Revision { hashId, title (= commit message), createdAt, model: "v1", qmkVersion (null = editable draft),
           qmkUptodate, md5, altMd5, config: Json (sparse), navigators: Json {left?, right?},
           combos[{name, layerIdx, keyIndices[], trigger: Key}], swatch {colors[10]}, tour,
           layers[{hashId, title, position, color "#RRGGBB"|null, automouse, builtIn, prevHashId, keys: Json[52]}],
           mcuAlternateRevisionHash, mcuAlternateLayoutHash, alternates[] }
Key      { tap, hold, doubleTap, tapHold : KeyStep | null,
           customLabel, icon, emoji, glowColor, lockGlowColor, tappingTerm (signed delta ms), about, aboutPosition,
           UI-state leaked into storage: swapped, detached, pristine, swapping, history }
KeyStep  { code, layer, modifier, modifiers {leftCtrl..rightGui: 8 bools},
           macro {keys[{code, delay, modifiers}], name, endEnter, applyAlt}, color, description }
```

Sources: `study/oryx-schema.reconstructed.graphql`; 02 §4.2; 04 §2.1.

Rules the importer must honour:
- **`config` is sparse.** A value equal to the catalog default is deleted, so missing keys mean "default". Apply the defaults from `study/04-oryx-settings-catalog.json` (14 sections, 100 settings). There are client-side coupling rules: `tappingTerm > 500` auto-enables `permissiveHold`, and turning `chordalHold` on sets `chordalHoldExcludeThumbs`. All of them are listed in `study/oryx-config-settings.json` `persistenceRules`.
- **Navigator settings live in `revision.navigators`, not `config`.** The model is in `oryx-config-settings.json` `navigatorModel`.
- **Codes are QMK names with aliases.** Stored codes are modern QMK names. The catalog maps them through the `wh` alias table, and an unknown code becomes `KC_TRANSPARENT` in Oryx (`oryx-keycodes.json` `_source.unknownCodeFallback`). Some codes are Oryx-only pseudo-codes that only the generator resolves: `KC_MAC_COPY`, `MAC_SPOTLIGHT`, `RGB_SLD`, `ORYX_SL_TOGG`, … (`kind: "oryx-custom"`, 18 codes), plus the `RGB` set-colour key (`kind: "oryx-color"`), which carries its colour in `KeyStep.color`.
- **Ignore `customLabel`, `icon`, `emoji` and `about*` for firmware.** They never reach generated code (02 §4.3).

### 2.2 Key index to matrix to LED to geometry

There is one identity for the Voyager: **Oryx key index N = QMK label `kNN` = RGB LED index N**. The other key orders all differ from it.

| Consumer | Addresses a key by | Conversion |
|---|---|---|
| Oryx JSON `keys[]`, combos `keyIndices`, Oryx `SET_RGB_LED` | index N | identity |
| Generated `LAYOUT_voyager(...)` arguments | interleaved order | arg order = `0-5, 26-31, 6-11, 32-37, 12-17, 38-43, 18-23, 44-49, 24, 25, 50, 51` |
| Oryx live events `06/07 <col> <row>` | matrix (col,row) | grid below |
| VIA/Vial dynamic keymap | (layer,row,col); byte offset `(row*7+col)*2`, 168 B/layer | grid below |

Matrix grid (12 rows × 7 cols; cell = Oryx index; rows 0-5 are the left half on MCU GPIO, rows 6-11 the right half via the MCP23018):

| row\col | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| 0 | - | 0 | 1 | 2 | 3 | 4 | 5 |
| 1 | - | 6 | 7 | 8 | 9 | 10 | 11 |
| 2 | - | 12 | 13 | 14 | 15 | 16 | 17 |
| 3 | - | 18 | 19 | 20 | 21 | 22 | - |
| 4 | - | - | - | - | 23 | - | - |
| 5 | 24 | 25 | - | - | - | - | - |
| 6 | 26 | 27 | 28 | 29 | 30 | 31 | - |
| 7 | 32 | 33 | 34 | 35 | 36 | 37 | - |
| 8 | 38 | 39 | 40 | 41 | 42 | 43 | - |
| 9 | - | 45 | 46 | 47 | 48 | 49 | - |
| 10 | - | - | 44 | - | - | - | - |
| 11 | - | - | - | - | - | 50 | 51 |

Sources: 05 §2.4 and 03 §3.6. Both verifications rebuilt this table independently with 0 mismatches. 44 mismatches appear if `LAYOUT` array position is mistaken for the index (05 verification row 3).

Visual layout:
- Indices 0-23 are the left 4×6 block, row-major, column 0 at the pinky side.
- Indices 26-49 are the right 4×6 block, row-major, column 0 at the index-finger side.
- Thumbs: 24 sits under the innermost main column at QMK (5, 4.5) and 25 is further toward the board centre at (6, 4.75). The right thumbs mirror this: 51 at (10, 4.5) and 50 at (9, 4.75). The clusters rotate +30° (left) and -30° (right) in Oryx's renderer.
- Use coordinates rather than "inner/outer" wording, which conflicts between sources (`voyager-geometry.json` `indexing` vs. the j7j7 README cited in 04 §4.1).

Machine-readable artifacts (use these, do not retype tables):

| Artifact | Use it for |
|---|---|
| `study/voyager-matrix-led-map.json` | **Authoritative** per-key table generated from QMK sources: matrix, `LAYOUT` arg index, LED index/flags/coords, IS31FL3731 channels, swap-hands mirror, VIA offset (05 §2.4) |
| `study/voyager-geometry.json` | Rendering: Oryx CSS-grid model (17 fr columns `6+1+3+1+6`; rows `4×1fr + 2fr`; stagger: left cols 3 and 5 at -15 %, col 4 at -30 %, mirrored on the right; thumbs ±30°) plus a pixel model, QMK key units and LED coordinates. The CSS model is INFERRED from stylesheets, not measured in a browser. |
| `study/oryx-keycodes.json` | Import mapping: 2,526 Oryx catalog keys, aliases, which slots each code may occupy, `requires` rules, macOS labels/glyphs. **ZSA-authored text; do not ship** (04 §5.3). The schema changed during the study, so treat field names as unstable. |
| `study/04-oryx-settings-catalog.json`, `study/oryx-config-settings.json` | Settings: 100 settings with defaults/ranges, visibility, persistence rules, config and Navigator models |
| `study/oryx-graphql-operations.json`, `study/oryx-schema.reconstructed.graphql` | All 68 operations and 5 fragments the Oryx client uses |
| `study/oryx-design-tokens.json` | Oryx look: theme variables, key-type colours, label sizing, swatch and named colours, icon-font glyph map (the glyphs themselves are ZSA's copyright) |
| `study/02-voyager-flash-constants.json` | VID/PIDs, DFU requests, addresses, suffix layout, pinned build commits. **Its `user_build.md5` and `crc` are a historical sample** (02 verification C1). Its `?alt=true` note applies to the Moonlander only. |
| `oryx/layout.json`, `oryx/layout-full.json`, `oryx/examples/*.json` | The user's layout and 5 public fw25 Voyager layouts. Their generated sources (`downloads/layout-source*/`, `downloads/oryx-source-JRGQm/`, `downloads/oryx-sources-examples/`) are the generator golden tests (02 §4.8). |

### 2.3 Sextant's own model (recommendation, INFERRED)

- **Store a local document that is a lossless superset of Oryx's revision JSON**, keyed by key index for ZSA boards.
  - Keep unknown fields so a round-trip is exact.
  - Strip the leaked UI-state fields on export.
  - Write it as plain JSON in a package or folder, so it can be versioned in git.
- **Put a board definition beside it**, following the 05 §3.4 shape: matrix size, a key list with matrix position, rect, rotation, hand, cluster and LED index, the LED list, USB IDs, and `flashTargets`.
- **Use the matrix position as the canonical key identity in the engine.** The Oryx index stays a per-board view, so a second board (Corne) is data, not code (section 8).

---

## 3. Feature inventory (tiered)

The full Oryx inventory is 04 §2. User pain points are 04 §6. Tiers assume architecture (d1) from section 4.

**MVP: "I can stop using Oryx for my own layout"**
- [ ] Import from Oryx, read-only, from a URL/hashId or from `layout/revision` read off the USB serial. The user's layout lives there today, and read access is precedented by ZSA's own zapp (04 §5.1).
- [ ] Local document with autosave and undo/redo. Offline-first; Oryx has no undo (04 §2.10).
- [ ] Native Voyager board rendering: stagger, rotated thumbs, legends with macOS glyphs, light and dark themes. This is the core editor surface (`voyager-geometry.json`).
- [ ] Key editor with tap + hold slots, per-slot modifiers, transparent/none. The user has 8 hold keys on Main, including hold-only modifiers (keys 18 and 25).
- [ ] Layer keys MO/TG/TO/TT/OSL/LM, OSM, and firmware keys such as `QK_BOOT`. Basic QMK; the user's `QK_BOOT` is at layer 2, index 31.
- [ ] Layers: add, rename, reorder, delete, layer colour, per-key `glowColor`, custom labels. The user has 2 coloured layers and 4 labels.
- [ ] Colour keys (`RGB` set-colour, `RGB_SLD`, `TOGGLE_LAYER_COLOR`). The user's layer 2 has 5 of them.
- [ ] Keycode picker with search, generated from the ZSA fork's QMK hjson (keycodes **0.0.7**) with Sextant's own labels. This avoids ZSA copyright and the upstream 0.0.9 drift (04 §5.3, 05 §4.3).
- [ ] Core tap-hold settings: tapping term, permissive hold, hold-on-other-key, chordal hold (+ thumb exclusion), flow tap, one-shot, debounce, RGB timeout. These are the home-row-mod knobs people actually use (04 §2.5).
- [ ] Navigator trackpad and trackball settings carried into generation. The user has a trackpad, and it must not regress (02 §4.7).
- [ ] Generator producing `keymap.c`/`config.h`/`rules.mk`/`keymap.json` with Oryx semantics, with golden tests against the 5 JSON/source pairs. This is the heart of the local build path (02 §4).
- [ ] Local build backend pinned to fork commit `93b2b9e` + `modules/zsa` `13890cd`, with progress and error display (02 §7).
- [ ] Native DFU flasher with hard safety guards, bootloader detection, and reset-button UX. Replaces WebUSB, Keymapp and zapp (02 §8, §10.3).
- [ ] Download and flash the **Oryx-compiled** `.bin` of an imported revision, with md5 verified at download time. A zero-toolchain fallback and a reference image.
- [ ] Device panel: presence, serial, protocol version, active layer over raw HID. It confirms what is flashed and costs little (03 §3).

**v1: Oryx and Keymapp parity, plus the cheap wins Oryx lacks**
- [ ] Tap dance (double-tap, tap-then-hold). Parity (02 §4.4).
- [ ] Macros: 24 steps, per-step modifiers, delays 0-5000 ms, `endEnter`/`applyAlt`. Parity, and local macros are never uploaded (04 §2.3, §6 #6).
- [ ] Combos: 2-6 keys, layout-wide, outputting a keycode, macro or layer. Parity (04 §2.4).
- [ ] All 100 settings, 48 animation toggles and 36 locale packs (`i18n.h`). Parity (`04-oryx-settings-catalog.json`).
- [ ] Per-key tapping term, lock-indicator colours, caps-lock status LED. Parity.
- [ ] Live key-press highlight and a local heatmap with CSV/JSON export. Keymapp parity; Keymapp cannot export (kontroll#14).
- [ ] Click-through transparent overlay/HUD plus a menubar item. The most-built community tool of 2026 (04 §3.7 item 4).
- [ ] App-aware layer switching via `SET_LAYER`, the "Smart Layers" equivalent under a different name. Keymapp parity.
- [ ] Git-backed revision history with a visual per-key diff. Oryx has neither (04 §6 #5).
- [ ] Copy, swap and duplicate layers; multi-select; mirror left/right. Bulk editing Oryx refuses (04 §6 #10).
- [ ] Firmware-size meter and build errors mapped to keys. Oryx's "over the top" error is opaque (04 §6 #12).
- [ ] Command palette and full keyboard navigation. Oryx is mouse-only (04 §6 #9).
- [ ] Export the source zip, print view, SVG/PNG. Sharing without Oryx.
- [ ] Host RGB effects through RGB takeover, and status-LED control. Cheap over the live protocol (03 §3.3).

**Later**
- [ ] QMK features Oryx lacks: key overrides, leader, repeat key, autocorrect, tri-layer, per-key hold options. The main differentiator (04 §2.18).
- [ ] Custom-C overlay files kept apart from generated code. Power users; avoids the merge conflicts of the GitHub-Actions workflow (04 §3.7 item 3).
- [ ] Layout profiles with quick-switch flashing (04 §6 #16).
- [ ] Legends computed from the active macOS input source. Fixes locale confusion (04 §6 #11).
- [ ] Tap-hold "timing lab" or simulator, clean-room (04 §5.4 D, §6 #7).
- [ ] CLI, URL scheme and Shortcuts actions. Agent-friendly, as ZSA and the community already lean (04 §3.7 item 7).
- [ ] Oryx write-back, **only with ZSA's written permission** (04 §5.1).
- [ ] Dynamic-keymap ("flash once, remap live") firmware and a VIA/Vial driver. Instant edits, but heavy (section 4 c).
- [ ] More boards: Moonlander, and Corne and others through VIA/Vial. The data model is ready (section 8).
- [ ] Practice drills on the user's own layers. typ.ing covers this today.

**Out of scope**
- Oryx accounts, login, private layouts, the Keymapp auth phrase. Needs ZSA permission, and the ToS position is grey (04 §5.1).
- Public layout search, tour authoring, embeds, the layer-template marketplace. These are Oryx cloud and community services.
- The Navigator gesture companion app, which is closed. Coexist with it, do not replace it (04 §2.9).
- Audio keys (not on the Voyager), Planck built-in layers, ErgoDox and Planck boards.
- ZMK Studio and wireless boards, which are a different protocol family (05 §4.5).
- Windows and Linux. The project is macOS-native.
- Bundling GCC, QMK or prebuilt firmware in the app. That brings GPL and notarization burdens (04 §5.4).

---

## 4. Architecture options for getting a layout onto the keyboard

The native editor, document model and DFU flasher are common to every option. The options differ in **who produces the firmware** and **where the keymap lives**. Effort is for one engineer, beyond the shared editor and flasher: S < 1 wk, M 1-3 wk, L 1-2 mo, XL > 2 mo. These sizes are INFERRED.

| | (a) Oryx-backed: edit natively, sync via Oryx's API, Oryx compiles | (b) Local build: generate QMK, compile ZSA fork locally, flash natively | (c) Dynamic keymap: VIA/Vial-style firmware flashed once, remap over raw HID | (d1) **Hybrid: (b) + read-only Oryx** |
|---|---|---|---|---|
| Feasibility | Proven technically: jyn514's `oryx_sync.py` replays mutations with a Bearer token (04 §3.3). But there is no sanctioned third-party auth, the mutations are undocumented, and introspection is off. | High. The generator is specified empirically from 5 JSON/source pairs (02 §4), the fork and modules are public GPL-2.0, and toolchains exist (02 §7). | Medium. The Vial and RMK ports prove the MCU and bootloader can do it (03 §7.2), but **both drop the Navigator, the Oryx protocol and per-layer LED maps**. A hybrid that keeps them does not exist. The default 1 KB EEPROM fits about 4-5 layers (03 §7.6). | High: the union of (b) and the read-only half of (a) |
| Effort | M (sync mapping and login) | L: generator M-L, build backend M, flasher S-M | XL: custom firmware plus a VIA/Vial driver plus upkeep at every ZSA firmware bump | L |
| Risk | **High policy and breakage risk**: no ToS, unannounced writes, App Store 5.2.2 needs authorization, any Oryx deploy can break it. Brick risk: low, same as Oryx. | Generator divergence on unobserved rules (02 §12.5); about 1 GB toolchain management; fork drift (`firmware26`). Brick risk: low. The target is always `zsa/voyager`, linked at 0x08002000, and the reset button always reaches Ignition (02 §8.7). | Firmware maintenance; a `raw_hid_receive` clash and command-ID collisions to solve (03 §7.1); EEPROM bitfield differences between the ZSA fork and upstream (05 verification O6). Brick risk: soft-brick possible, still recoverable via the reset button. | as (b) |
| Fidelity to Oryx | 100 %, but capped at Oryx's features | High, and can exceed Oryx (QMK extras). Keeps the Oryx live protocol and Navigator modules. | Partial unless reimplemented (per-layer RGB, DUAL_FUNC, Navigator); gains instant remap | High; Oryx's own binary is available for imported revisions |
| Offline | No | Yes, after a one-time fork and toolchain download | Yes | Yes; import needs the network once |
| ZSA services / ToS | Total dependence; ToS-grey writes | GitHub repos only; no Oryx at runtime | None | Read-only Oryx endpoints, precedented by zapp; ask ZSA (04 §5.1) |
| Extra upside | none | Full QMK power; custom C | The same driver serves Corne and about 2,000 VIA boards (05 §5.2) | Gradual migration: works on day 1 with Oryx's binaries |

Other hybrids considered:
- **(d2) Later: build (c) on top of (b)'s infrastructure.** Sextant-built firmware would keep `zsa/oryx`, the Navigator modules and per-layer LEDs, and add VIA's dynamic keymap behind a command dispatcher plus an enlarged wear-levelling area (03 §7.7). This is the only route to instant remaps that does not cost the user their trackpad. Treat it as an R&D track gated on Phase 0 findings.
- **(d3) Oryx as a compile-only service.** This still needs the write mutations, so it has the same ToS problem as (a). Rejected.
- **QMK API cloud compile (`api.qmk.fm`).** It builds upstream QMK only: no ZSA modules, no Oryx protocol, no Navigator, and it takes layers only. Rejected (02 §7.5 E, 05 §4.2).

### Recommendation: (d1), local-first with read-only Oryx

- Sextant owns the layout as a local document.
- It imports from Oryx read-only.
- It **generates Oryx-equivalent QMK source** and builds it locally against ZSA's fork with the ZSA modules, so the Oryx live protocol, Navigator support and Keymapp/zapp interoperability are kept.
- It flashes with a native Swift DFU implementation.
- Oryx-compiled firmware for an imported revision stays available as a no-toolchain fallback and as the reference image.
- Oryx write-back and dynamic-keymap firmware are deferred, each behind an explicit gate.

### Phased path

| Phase | Deliverable | Exit criterion |
|---|---|---|
| **0. Spikes** (gate everything that writes to the device) | (1) Read-only captures: normal mode (`hidutil list`, `ioreg -p IOUSB -l -w0`) and bootloader mode (PID **0791 vs 1791**, DFU functional descriptor). (2) Swift raw-HID client: `FE`, `00`, `01`, events, RGB takeover and release. (3) Swift DFU flasher re-flashing the user's **own current Oryx `.bin`**, md5-verified. This is the first write, and it needs the user's explicit go-ahead. (4) Build spike: compile the user's source zip in a gcc 12.2.1 container and compare with the `.bin` **from the same zip**; measure time. | Variant known. Flash round-trips. Build is byte-identical or behaviourally identical. |
| **1. MVP** | Section 3 MVP list | The user's current layout round-trips: import, build, flash, then live layer shown and serial verified. Golden tests pass on all 5 JSON/source pairs (user + JRGQm, e5Rrr, m9dpx, XlrR4). |
| **2. v1** | Oryx + Keymapp parity (section 3 v1) | All 5 pairs, plus more mined via `searchLayouts`, generate equivalent firmware; the overlay and heatmap are in daily use |
| **3. Beyond Oryx** | QMK extras, custom C, profiles, CLI | - |
| **4. Optional R&D** | (d2) dynamic-keymap firmware, then a VIA/Vial driver (Corne) | Navigator and per-layer LEDs kept; EEPROM budget documented |

Safety rules for the flasher. They are non-negotiable and come from 02 §8, §10.3 and the 02 verification.
- Never erase or write below `0x08002000` or at or above `0x08042000`. Never send MASS_ERASE (`41` alone).
- Accept only images whose last 16 bytes are a valid DFU suffix with a matching CRC and VID `0x3297`, and whose suffix PID equals the connected bootloader PID. Refuse a single STM32 image on `0x1791`.
- Verify `md5(file) == revision.md5` at download time.
- Sanity-check the vector table (INFERRED addition): initial MSP inside `0x20000000-0x20008000`, reset vector odd and inside `[0x08002000, 0x08020000)`.
- Cap the GETSTATUS polls and treat `dfuERROR` as failure. **This deliberately departs from both zapp and Oryx**, which loop or continue silently (02 verification O1, C4).
- Implement from the DFU 1.1 and ST DfuSe (AN3156) specifications, and use zapp, Oryx web and dfu-util only as behavioural references. Wally is **not** a valid reference: it has suffix-parse and poll-timeout bugs, a 0x08000000 base and mass-erase (02 §8.5). That contradicts 04 §5.5's suggestion to use it.

---

## 5. Live features over raw HID

Protocol: 03 §3. Session lessons from open-source clients: 03 §9.5. Everything here works with the **stock Oryx firmware** the user already has, and with any Sextant-built firmware that keeps the `zsa/oryx` module.

| Feature | Wire (host→kb / kb→host) | Notes |
|---|---|---|
| Identify board and layout | none: read the USB serial `KlgM7/40xJ7M` (`kIOHIDSerialNumberKey`); or `00` → `00 <ascii> FE` | No pairing needed. The serial carries layout/revision. |
| Protocol version | `FE` → `FE 05 FE` | Accept a range; never test for equality (`voyager-disco` breaks on fw25). Automouse needs ≥ 5. |
| Pair / start events | `01` → `04 FE`, then `05 <layer> FE` | No challenge since fw22. **Pairing never ends**: `03` is unhandled and only a reboot clears it (03 verification O6). |
| Active layer | `05 <highest layer> FE` on change | Dedupe bug: a change back to the layer the firmware last recorded can go unreported. Re-send `01` to resync (03 verification O2). |
| Key-press highlight, heatmap | `06/07 <col> <row> FE` | Physical presses, before tap-hold resolution. No snapshot of keys already held. Map (col,row) through the section 2.2 grid. |
| Set layer (app-aware layers) | `04 01 <n>` (layer_move), `04 00 <n>` (layer_off) | Needs pairing. `layer_move` clears momentary layers. |
| RGB takeover | `05 01` / `05 00` → `08 <state>` (no stop byte); `06 <led> r g b`; `09 r g b` | **Clamp led ≤ 51**: firmware has no bounds check. Output scales with global brightness (max 175). Kept in RAM only; **send `05 00` on quit and sleep**. Suppresses the per-layer ledmap while active. |
| Status LEDs | `07 <0..3> <on>`; release with `0A 00` → `0B 00` | After release the LEDs stay dark until the next layer change |
| Brightness | `08 01` / `08 00` | Not persisted |
| Automouse | `0B`/`0C` | Needs the `zsa/automouse` module. **Not in the user's build**, so the board replies `FF FF`. |
| Not possible | - | Read or write the keymap, jump to the bootloader, un-pair, see held keys |

Swift implementation, macOS 15+ (CoreHID) or any version (IOHIDManager). Sources: 03 §8.1 and `bogo/probe` `RawHIDMonitor.swift`, which is MIT.
1. **Match strictly.** Use `VID 0x3297`, `PID 0x1977` **or `0x1978`** (03 verification O1), `kIOHIDPrimaryUsagePageKey 0xFF60`, `kIOHIDPrimaryUsageKey 0x61`. Never open the keyboard, mouse or digitizer interfaces; those trigger Input Monitoring.
2. **Open with `kIOHIDOptionsTypeNone`. Never seize.** Run I/O on a dedicated dispatch queue (`IOHIDDeviceSetDispatchQueue` + `IOHIDDeviceActivate`). Register a 32-byte input-report callback and keep it registered while open.
3. **Write** with `IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, buf, 32)`: report ID 0, exactly 32 bytes, no leading 0x00. With CoreHID use `dispatchSetReportRequest(type: .output, id: nil, data:)`; `id: nil` is untested (03 §10 item 6).
4. **Session steps.**
   1. Drain stale reports.
   2. Send `FE` (400 ms timeout, ×2), then `00`.
   3. Send `01`, and wait up to about 700 ms for `05`.
   4. Parse to the first `0xFE`. `08` and `0B` replies have no stop byte.
   5. Pace writes at no more than about 1 report/ms (52 LEDs ≈ 52 ms).
   6. Re-check presence about once a second. Reconnect with backoff.
5. **Coexistence.**
   - `kIOReturnExclusiveAccess` (`0xE00002C5`), or CoreHID `.deviceSeized` / `HIDDeviceError.exclusiveAccess`, means Keymapp (hidapi seizes by default) holds the board. Show "Keymapp is connected" rather than an error.
   - Chrome-based clients (Oryx; typ.ing, INFERRED) open non-exclusively and can coexist, but they share the firmware's single `paired` / `rgb_control` state (03 §5.4).
6. **Privacy.** Any paired host receives every physical keypress, and the interface needs no OS permission. Keep events in memory, say so in the privacy text, and never log them (03 §3.8).

---

## 6. macOS platform notes

| Concern | Choice | Source / status |
|---|---|---|
| Raw HID | IOHIDManager (any macOS), or CoreHID (`HIDDeviceManager`/`HIDDeviceClient`, macOS 15+, async, seize notifications) | 03 §8.1. CoreHID has no field use with ZSA boards yet. |
| TCC | The vendor interface `0xFF60` needs **no Input Monitoring**: the kernel requires TCC only for GD Keyboard, GD Mouse and Digitizer TouchPad. DFU mode exposes no HID at all. | IOHIDFamily `IOHIDDevice.cpp` 527-531, plus field reports (03 §8.2) |
| DFU transport | Non-sandboxed: **IOUSBHost** (`IOUSBHostInterface` + `sendDeviceRequest` on EP0, about 300 lines). No `DeviceCapture`, since macOS binds no driver to a DFU interface (INFERRED). libusb, dfu-util and zapp are not needed. | 02 §10.1 |
| DFU under App Sandbox | `com.apple.security.device.usb` allows only `IOUSBDeviceUserClientV2`/`IOUSBInterfaceUserClientV3` (+ `IOHIDLibUserClient`). IOUSBHost objects likely use `AppleUSBHost*` clients and would be **denied** (INFERRED). Sandbox options: IOUSBLib (COM-style), or macOS 27 **AccessoryAccess** (`AAUSBAccessoryManager`, entitlement `com.apple.developer.accessory-access.usb`, may need Apple approval). | `application.sb` 114-123; 02 verification O3 |
| Device watching | `IOServiceAddMatchingNotification` for VID `0x3297`, PIDs `{0x1977, 0x1978, 0x0791, 0x1791}`. Read `bcdDevice` in bootloader mode as the Ignition version. | 02 §10.3 |
| Local build | Apple **Containerization** (Swift package, Apache-2.0, macOS 26+, Apple silicon, pre-1.0 at tag 0.49.0, entitlement `com.apple.security.virtualization`) running a pinned Debian bookworm image with gcc 12.2.1. Or a managed native toolchain (`qmk_toolchains` gcc 15.2, 139 MB, plus a `uv` venv with `qmk` and GNU make 4.x) in `~/Library/Application Support/Sextant/`. macOS `/usr/bin/make` 3.81 breaks `qmk compile -j`. | 02 §7 and verification row 10 |
| Network | Oryx read-only requests. Under the sandbox add `com.apple.security.network.client` (standard entitlement; INFERRED, not studied). Send a descriptive User-Agent and cache by revision **plus md5**. | 04 §5.1; 02 verification C1 |
| App-aware layers | `NSWorkspace` frontmost-app notifications, then `SET_LAYER`. No TCC expected (INFERRED). | - |
| Keymapp API (optional) | gRPC (`grpc-swift-2` with the UDS transport) to `keymapp.sock`, only to ask Keymapp to `DisconnectKeyboard`. Non-sandboxed builds only (INFERRED). | 03 §5.2-§5.3 |
| Distribution | **Developer ID, hardened runtime, notarization, Sparkle; not the Mac App Store.** Guideline 2.5.2 bars downloading or executing code (toolchain, INFERRED reading), and 5.2.2 needs ZSA's authorization for Oryx endpoints. Every Mach-O in the bundle must be signed, so do not bundle toolchains. Start non-sandboxed; adopt the sandbox only after the USB test. A future store edition limited to viewing and flashing is plausible, since sandboxed Keymapp ships there (04 verification). | 02 §10.2; 04 §5.6 |
| Minimum OS | macOS 26 if the container backend is the default; otherwise 15 for CoreHID. The user runs macOS 27.0.1 on arm64. | 02 §7.2 |

---

## 7. Risks and legal/trademark constraints

Not legal advice. This digests 04 §5 and its verification.

**Top engineering risks**

| # | Risk | Mitigation |
|---|---|---|
| 1 | **The MCU variant is unknown** (STM32 `0791` vs GD32 `1791`), and how a GD32 Voyager gets fw25 firmware is unresolved. Every fw25 file seen is a single STM32 image. | Phase 0 capture. Refuse to flash STM32 images on `1791`. Do not ship building or flashing for GD32 until resolved (03 verification C2). |
| 2 | The generator diverges from Oryx on rules not yet observed | Golden tests on 5 pairs. Mine more public layouts with read-only `searchLayouts` (02 §12.5). |
| 3 | Oryx changes its schema or endpoints (introspection off, bundle hash changes each deploy) | Keep import thin and versioned; keep a fixture-based contract test; fail soft |
| 4 | The firmware for a revision is rebuilt server-side, so its md5 changes | Never cache by revision ID alone; fetch md5 and `.bin` together |
| 5 | Keymapp seizes HID | Detect the seize and explain it; optionally use the Keymapp API's `DisconnectKeyboard` |
| 6 | Keystroke telemetry: pairing never ends | In-memory only; privacy text; pair only while a live view is open (INFERRED) |
| 7 | Toolchain weight (about 1 GB) and the pre-1.0 Containerization API | Pluggable `BuildBackend` with a native fallback; pin image digests and the fork commit |
| 8 | The sandbox USB API is uncertain | Ship non-sandboxed first (section 6) |
| 9 | Bricking | Low: Ignition sits in `0x08000000-0x08001FFF` and is never touched, and the reset button always works (02 §8.7). Enforce the guard list in section 4. True brick recovery would need SWD plus a non-public Ignition image. |
| 10 | EEPROM survives reflash; Bootmagic formats it. Moving between ZSA and upstream/Vial firmware can misread `keyboard_config` bits. | Document it; offer an "EEPROM reset" key; avoid cross-firmware hops without a reset (05 verification O6) |

**ZSA terms and API use**
- ZSA publishes **no Terms of Service or API terms**. The footer link 301s to `/privacy`, which has no terms.
- `configure.zsa.io/robots.txt` disallows everything but `/`, and it does not cover `oryx.zsa.io`.
- Read-only access to the user's own layouts mirrors ZSA's own zapp and is defensible. It is **not** a granted right.
- **Email `contact@zsa.io` before any public release.** Do not use mutations or emulate the auth phrase without permission. Disclose in the privacy text that requests reveal IP and layout ID to ZSA. (04 §5.1 and verification rows 3-5.)

**Licences**
- QMK and `zsa/qmk_modules` are GPL-2.0. Generating source and running a toolchain on the user's Mac creates no obligation for a closed Sextant.
- Shipping firmware, bundling QMK, or running a cloud build service triggers source-offer duties.
- Porting QMK logic into Swift is a GPL-derivative risk. QMK's written policy addresses firmware, so applying it to host apps is INFERRED.
- zapp is **MIT + Commons Clause**. Linking it forbids selling Sextant, and even a free app must carry the Clause notice. Reimplement DFU instead (04 §5.5 and verification).
- ZSA's icon font, product renders and `metadata.json` descriptions are ZSA copyright. Generate keycode tables from QMK hjson and write Sextant's own text (04 §5.3).

**Trademarks and naming**
- Per third-party aggregators: MOONLANDER and ERGODOX EZ are registered; VOYAGER, ZSA, NAVIGATOR and TYP.ING are applications; ORYX and KEYMAPP have no record but carry common-law rights. The USPTO TSDR API needed a key, so statuses are unverified. CIPO and EUIPO were not checked (04 §5.2).
- Never put Oryx, Keymapp, Wally, Zapp, Kontroll or Voyager in the app name, bundle ID or icon.
- Use nominative wording ("for the ZSA Voyager") and a non-affiliation disclaimer.
- Do not reuse ZSA's coined feature names: say "app-aware layers", not "Smart Layers".

**Is "Sextant" clear?**
- **Clear enough for a free or open project; not yet cleared for commercial use.**
- No conflict in the keyboard and QMK space.
- The App Store already lists several celestial-navigation "Sextant" apps, so a store listing needs a distinct name such as "Sextant: Keymap Studio".
- Historic SEXTANT marks are cancelled or in unrelated classes.
- A Swift package `KittyMac/Sextant` exists, so don't name an SPM module exactly `Sextant`.
- Get professional clearance (Classes 9 and 42; USPTO, CIPO, EUIPO) before any paid launch (04 §5.7).

---

## 8. Open hardware and open configurators (the user's question about open-source information and the Corne)

**What is open about the Voyager**
- Open:
  - the firmware: GPL-2.0, in ZSA's fork `firmware25` and upstream `qmk/qmk_firmware` `keyboards/zsa/voyager`;
  - ZSA's modules, including the Oryx protocol;
  - the generated source of every Oryx revision;
  - kontroll and wally (MIT) and zapp (MIT + Commons Clause).
- **Not open:** the schematic, PCB and case files (none in ZSA's 16 public repos; only ErgoDox EZ schematics exist in `zsa/docs`), the Ignition bootloader, Oryx's generator and server, Keymapp, and the Navigator companion app.
- Sources: 05 §2.1 and verification row 6; 03 §9.1.

The GPL firmware still documents the hardware well (05 §2.2-§2.3):
- one STM32F303xB-class MCU in the left half (128 KB flash; possibly GD32F303CB silicon);
- an MCP23018 expander scanning the right half over I2C on the TRRS cable (the I2C link is INFERRED);
- two IS31FL3731 LED drivers (7-bit addresses 0x74 and 0x77);
- 4 status LEDs;
- Navigator at 7-bit I2C 0x2C (trackpad, Cirque) and 0x28 (trackball bridge). These are the corrected addresses from the 05 verification.

**What Sextant can reuse**

| Asset | How to reuse | Licence note |
|---|---|---|
| `study/voyager-matrix-led-map.json` | Built-in Voyager definition | facts derived from GPL QMK files |
| QMK `keyboard.json`/`info.json` (`keyboards.qmk.fm/v1/keyboards/<kb>/info.json`, 3,760 boards) | Geometry importer for any board. QMK lacks rotation, so take rotation from KLE or ZMK. | GPL-2.0 data, fetched at runtime |
| QMK keycode hjson, **versioned** (ZSA fork 0.0.7, upstream 0.0.9, vial-qmk 0.0.7) | Generate Swift keycode tables at build time | GPL repo; numeric values are facts |
| VIA protocol (32-byte, big-endian) and Vial (`0xFE` prefix, self-describing XZ `vial.json`, decodable with Apple's Compression framework, unlock gate) | Implement natively if (d2) or Corne support happens | protocol, clean-room (03 §7.3-§7.4, 05 §4.3-§4.4) |
| VIA definitions (2,029 v3 JSON) | Fetch at runtime by `VID*65536+PID`. Served definitions use a compiled format, and a missing one returns 200 HTML. | GPL-3.0 (05 verification O3-O4) |
| ZMK Studio `.proto` | `swift-protobuf`, only if wireless boards are ever in scope | MIT |
| KLE format / `kle-serial` | Geometry import | MIT (KLE app itself: all rights reserved) |
| MIT Swift prior art: `bogo/probe` (raw HID), `buckleypaul/zmkonfig` (local files + git + diff + flash), `qmk/qmk_toolbox` (Swift flasher UI) | Read and borrow patterns | MIT. GPL projects (LayerLens, keyfinder, VIA app, vial-gui) are ideas only (04 §3.8). |
| `martinezooo/keyjitsu` (Rust, MIT, macOS, Voyager) | **Study before designing.** It already does Keymapp parity plus local QMK builds plus flashing. | MIT; it links zapp-core (Commons Clause) |

**Corne vs. Voyager (05 §3.2)**
- Both are column-staggered 6-column splits.
- The Corne has 42 keys (3×6+3) and **an MCU in each half**, joined by a serial link. Both halves must be flashed. Bootloaders are Caterina on rev1 and RP2040 UF2 on v4. The ecosystem is VIA/Vial first, and v4's official firmware downloads are VIA and Vial UF2s (05 verification row 17).
- The Voyager has 52 keys, one MCU, one DFU target, and Oryx-only tooling.
- For a configurator the differences reduce to key count, geometry, matrix, LED map, the number of flash targets, and which protocol and firmware family applies.

**Should the data model be multi-board from day one? Yes, the model; no, the features.**
- Make the core types board-agnostic now: `KeyboardDefinition` / `PhysicalKey` keyed by matrix position (05 §3.4), `Transport` / `ProtocolDriver` (Oryx now, VIA/Vial later), and `FirmwareTarget` / `BuildBackend` / `Flasher` protocols.
- Never hard-code 52, the Oryx index or the Voyager PIDs outside the Voyager definition.
- The cost is small (INFERRED), and it prevents a rewrite.
- Ship and test **Voyager only** until v1. A Corne needs a different firmware family (upstream QMK or Vial, not ZSA's fork), different bootloaders (UF2/Caterina), per-half flashing, and a VIA/Vial driver. That is a product decision for later (section 9).

---

## 9. Decisions the user must make

| # | Question | Options | Recommendation |
|---|---|---|---|
| 1 | Primary architecture | (a) Oryx-backed sync; (b) local build; (c) dynamic-keymap firmware; (d1) local build + read-only Oryx | **(d1)**. (d2) dynamic keymap later as R&D. |
| 2 | Relationship with Oryx | none; read-only import; two-way sync | **Read-only import** now. Email ZSA before release; consider write-back only with written permission. |
| 3 | Default build backend | Apple Containerization with gcc 12.2.1 (exact ZSA compiler, macOS 26+); managed native toolchain (gcc 15.2, faster, more moving parts); user-installed QMK | **Container default, native fallback**, pending the Phase 0 spike (reproducibility, speed, disk) |
| 4 | Firmware identity of Sextant builds (`SERIAL_NUMBER`, Oryx module) | keep the imported Oryx `layout/revision`; a Sextant namespace (e.g. `sx:<doc>/<build>`); `default/latest` | **Keep the `zsa/oryx` module and use a Sextant-namespaced serial.** Reusing an Oryx ID would make Keymapp, typ.ing and zapp show a stale Oryx layout. They cannot fetch local layouts anyway (03 §4). INFERRED; confirm Keymapp's behaviour on a non-Oryx serial. |
| 5 | Distribution and app licence | closed Developer ID; open source MIT; open source GPL-3.0; Mac App Store | **Developer ID + notarized.** Pick free/open vs. commercial first. If open, GPL-3.0 makes the QMK, VIA and Vial data reusable as-is. If commercial: closed, clean-room tables, no zapp-core. |
| 6 | Minimum macOS | 15 (CoreHID); 26 (Containerization); 27 (AccessoryAccess) | **26** if decision 3 is the container; else 15 |
| 7 | Dynamic-keymap firmware | never; later R&D (d2); adopt an existing Vial/RMK port | **Later, only as (d2).** Existing ports would drop the user's trackpad. |
| 8 | Multi-board | Voyager-only code; board-agnostic model with Voyager-only features; full multi-board now | **Board-agnostic model, Voyager-only features until v1** |
| 9 | Keymapp replacement scope | editor only; editor + live view; plus overlay, heatmap and app-aware layers | **Live view in MVP; overlay, heatmap and app-aware layers in v1** |
| 10 | Name | keep "Sextant"; rename | **Keep for development.** Distinct store or marketing name and professional clearance before any paid launch. |
| 11 | Phase 0 hardware actions | approve or deny: read-only USB captures in bootloader mode; one re-flash of the user's current Oryx `.bin` with Sextant's flasher | **Approve both.** The re-flash restores the same firmware and is recoverable via the reset button. |

---

## 10. Gaps (drives the next round)

**A. Missing or lost work**
1. **Report 01 does not exist.** Its artifacts survive, but these were never written up or verified:
   - the Oryx editor's state model (MobX-state-tree `Key.serialize`, `KeyStep.afterCreate`, availability rules `tv()`/`D7()`);
   - the exact debounce, offline-sync and draft-revision lifecycle;
   - rendering details;
   - the "report section 4.3" that `oryx-keycodes.json` cites for availability rules.
   - A fact-check run left downloads in `downloads/factcheck-01/` but no verdicts. **Next:** a short 01 write-up from `work/oryx01/` and `downloads/factcheck-01/`, re-verified against the bundle.
2. **`oryx-keycodes.json` schema is unstable** (04 §1). Freeze it and record its generator script before building import on it.

**B. Hardware (needs the board; read-only)**

3. Which bootloader PID the user's board has (`0791` STM32 vs `1791` GD32), and the Ignition DFU descriptors: `wTransferSize`, `bcdDFUVersion`, `bmAttributes`, the alt-setting string, whether `DFU_UPLOAD` read-back works (02 §12 items 1-2).
4. Normal-mode HID properties as macOS sees them (`hidutil list | grep 0x3297`), and the meaning of runtime PID `0x1978` (03 verification O1).
5. Whether the reset button is wired to A8 or NRST. Ignition's behaviour on MASS_ERASE and below-0x08002000 writes is unknown. **Do not test it.**

**C. Oryx and firmware behaviour**

6. **The GD32 path for fw25.**
   - Oryx web has "double compilation" for the Voyager.
   - The schema has `mcuAlternateRevisionHash`/`mcuAlternateLayoutHash`, `createLayout(mcuAlternate)` and `getAlternateFirmwareLinks`, all null in the 6 layouts.
   - Every fw25 `.bin` seen is a single STM32 image.
   - What a GD32 owner receives is unresolved. Resolve it read-only (inspect `getAlternateFirmwareLinks` usage in the bundle) and, if needed, by asking ZSA.
7. **Why `40xJ7M` was rebuilt at 2026-10-11 00:01:52 UTC.** Possibly the concurrently driven browser session, or a server-side recompile. Determine whether viewing or `qmkUptodate` triggers compiles; this affects caching.
8. **Generator rules not yet observed** (02 §12 item 5):
   - `endEnter`, `dancesTapAction`, `legacyDualFunctionDances`, `ambidexLT`, `layerLockIdleTimeout`, `debounce`, `disableNKRO`, `lowPollingRate`, `tapCodeDelay`, `holdOnOtherKeyPress`, `retroTapping`, `tappingForceHold`, steno, `liveTraining=false` (does it drop `ORYX_ENABLE`?);
   - combos outputting macros or layers; `lockGlowColor`; `LAYER_STATE_32BIT` for more than 16 layers;
   - Oryx-only codes (`KC_MAC_*`, `MAC_*`, `ORYX_SL_TOGG/TRIGG`). The firmware's `toggle_smart_layer()` has no caller in fw25 (03 §10 item 5), so the generator must emit the call.
   - Trackpad settings (`tap`, `tapRight`, `scrollInertia`, `sensitivity`): the user's non-null values produced **no** `config.h` defines. Which values do?
   - Already observed for this overview [00-verified]: a tap-less hold modifier emits the bare modifier keycode (user keys 18 and 25 → `KC_LEFT_CTRL`, `KC_LEFT_GUI`, `keymap.c` lines 24-25).
9. **Settings-default drift:** Tap Flow defaults to 100 in the bundle but 150 in the blog (04 §7 item 2). The chordal-hold thumb question is resolved by the client rule that enabling `chordalHold` sets `chordalHoldExcludeThumbs` (`oryx-config-settings.json` `persistenceRules`).
10. Server-side limits under write (24/5 macro steps, 32 layers): untested and untestable without mutations (04 verification).

**D. macOS platform (needs on-device spikes)**

11. Can IOUSBHost open the bootloader under the sandbox with `device.usb` only, or are IOUSBLib or AccessoryAccess required? Does AccessoryAccess's entitlement need Apple approval? (02 verification O3)
12. CoreHID with a report-ID-less interface (`id: nil`) (03 §10 item 6).
13. Coexistence rows still INFERRED: our non-seizing client vs. Keymapp connecting later; Chrome plus Sextant sharing pairing and RGB state (03 §5.4).
14. What the closed Navigator companion app opens, and whether it seizes the raw-HID interface (03 §10 item 8).
15. Typing latency after Sextant quits while paired: does macOS keep draining the IN endpoint? (03 §3.5 hazard, INFERRED)
16. Containerization in practice: OCI image source and pinning, kernel image, sandbox + virtualization entitlement, first-run download size; build time and byte-reproducibility (02 §12 item 4).

**E. Contradictions resolved in this overview (keep the reports consistent)**

17. `?alt=true` is for the **Moonlander rev B only**. 03 §6/§7.6/§7.7, 04 §4.1/§7 item 3 and the comment in `02-voyager-flash-constants.json` imply a Voyager alternate-MCU URL; that is refuted (03 C2, 04 row 17).
18. RMK Voyager port USB identity: `4C4B:4643`, serial `vial:f64c2b3c;rmk:<ver>`. 05 §5.1 says it stays `3297:1977`; that is refuted (05 row 19, 03 C3).
19. 04 §5.1 assumes compiled revisions are immutable. The firmware is not (item 7).
20. Oryx protocol counts: 14 commands and 15 events, not 13/13 (03 C1).
21. Navigator I2C addresses: 7-bit 0x2C/0x28, not 0x58/0x50 (05 row 8).
22. "Corne v4 ships with VIA" is unsupported (05 row 17). ZSA has 16 public repos, not 17 (05 row 6).
23. Match runtime PIDs `0x1977|0x1978`, not 0x1977 only (03 §0 vs verification O1).
24. Wally as a DFU reference (04 §5.5) vs. its documented bugs (02 §8.5). Use the specs, zapp and Oryx instead.
25. 02 §10 recommends IOUSBHost; that holds only outside the sandbox (02 O3).
26. "Inner/outer thumb" wording conflicts between `voyager-geometry.json` and the j7j7 README (04 §4.1). Use coordinates.

**F. Not researched yet**

27. Keymapp's behaviour when the serial is not an Oryx ID (decision 4).
28. A ZSA permission email: not sent.
29. Reddit (r/zsaVoyager, r/ErgoMechKeyboards) pain points: blocked (04 §1).
30. Trademark verification in USPTO TSDR (needs an API key), CIPO and EUIPO.
31. Accessibility of the native editor (VoiceOver, keyboard-only); no report covered it.
32. Firmware-size budget per feature for the size meter. Today there is about 54 KB of headroom in the 120 KB window (03 §7.6).
