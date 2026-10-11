# 04 - Oryx feature inventory, prior art, legal/ToS constraints, and user pain points (plus open-source Voyager and Corne background)

Study date: 2026-10-11. Project: **Sextant**, a native macOS (Swift/SwiftUI) replacement for ZSA's web configurator Oryx (`configure.zsa.io`).
Target device: the user's ZSA Voyager. Layout `KlgM7`, revision `40xJ7M`, firmware "25.0", 3 layers, and a Navigator **trackpad** on the right half (`revision.navigators.right.kind = "trackpad"` in `oryx/layout-full.json`).
Audience: the engineer who will build Sextant.

Conventions:
- Every claim carries a source: a URL, `repo@commit:path:line`, or `asset-file@byte-offset` for the Oryx web bundle.
- **INFERRED** marks conclusions drawn from code or the absence of evidence rather than stated by a source.
- "Bundle" means the Oryx production assets fetched 2026-10-11 from `https://configure.zsa.io/assets/`. They are stored locally in `downloads/oryx-web/assets/`. The main bundle is `index-xhNfd6BI.js`, md5 `34fbb4d676e5dd056e2acf1999f26dae`. File hashes change on every ZSA deploy, so the offsets are only valid for this build.
- Paths are relative to the scratchpad `scratchpad/` unless shown as absolute.

Related reports:
- `study/03-live-hid-and-ecosystem.md` covers the raw-HID protocol, Keymapp internals and VIA/Vial in depth. This report links to it rather than repeating it.
- `study/02-firmware-and-flashing.md` covers building and flashing.
- `study/05-open-hardware-and-configurators.md` covers Voyager hardware, Corne and other open splits, and open configurators in depth.
- Machine-readable companions:
  - `study/04-oryx-settings-catalog.json`: all 14 settings sections and 100 settings, verified against the bundle (see `_verified`).
  - `study/04-prior-art-repos.tsv`: GitHub metadata for 69 repositories.
  - `study/oryx-keycodes.json`: another researcher's keycode catalog derived from `configure.zsa.io/metadata.json`. Its schema changed while I worked, so treat its field names as unstable.

---

## 0. Summary

### 0.1 What Oryx is today (2026-10-11)

- **Price and hosting.** Oryx is a free web app with no paid tier (section 2.15). It "lives in the cloud, and makes firmware for your board" ([zsa.io/oryx](https://www.zsa.io/oryx)) by compiling ZSA's QMK fork (`firmware25`) on ZSA's servers.
- **Per-key actions.** Each key has four action slots: tap, hold, double-tap and tap-then-hold.
- **Keycodes.** About 2,526 keycodes in 61 categories, 36 of them locale packs.
- **Macros.** Up to **24 steps**, each with its own modifiers and a 0-5000 ms delay. Accounts that are anonymous or have not acknowledged the risk are capped at **5 steps** (`index-Bvxi2_Kp.js@117410`: `pf=24,Ve=5`).
- **Combos.** Up to **6 keys** each (`index-xhNfd6BI.js@632262`: `rg=6`).
- **Lighting.** Per-key and per-layer RGB.
- **Settings.** 14 global settings sections with 100 settings (`study/04-oryx-settings-catalog.json`).
- **Navigator.** Trackball and trackpad configuration. Two Navigators at once have been supported since Aug 2026.
- **Sharing and discovery.** Layout tours, layer templates, tag search, iframe embeds, print view and per-key deep links.
- **Firmware delivery.**
  - Browser flashing (WebUSB, Chromium only).
  - Keymapp, ZSA's closed desktop app.
  - Zapp, ZSA's open CLI, since Apr 2026.
- **Training has left Oryx.** The Oryx "Train" link now points to `https://typ.ing/oryx` (`index-xhNfd6BI.js@941107`). ZSA finished moving Live Training to typ.ing in Jan 2026 ([Ergo newsletter 2026-01](https://the-ergo-archive.zsa.io/newsletters/2026/01.html)).
- **Removed features.**
  - Per-key History (undo/redo) launched in Jun 2023 and was disabled in Oct 2023 ([blog.zsa.io/history](https://blog.zsa.io/history/)).
  - The Dec-2023 "QMK Next" toggle is gone from the bundle. The user's revision still carries `config.qmkCanary: true`, a leftover (INFERRED).
- **Absent** (sections 2.10 and 2.18):
  - no undo
  - no diff or compare between revisions
  - no portable export beyond the source zip and firmware
  - no public write API
  - essentially no keyboard shortcuts
  - no Key Overrides, Leader, Repeat Key, Autocorrect, Tri-layer, `DF` or native Unicode keycodes

### 0.2 Prior art

- **No complete native Oryx replacement exists.**
- **Closest:** **keyjitsu** (Rust/egui, MIT, beta since Aug 2026, macOS-first). It edits all 4 slots, builds QMK locally (generating tap dances itself), flashes through ZSA's `zapp-core`, and adds a click-through overlay, heatmap with CSV export, an RGB effect sequencer and app-aware layer switching. It reads Oryx anonymously and never writes back.
- **Swift prior art worth reading:**
  - **bogo/probe**: MIT. Voyager raw-HID HUD that imports `keymap.c` or the Oryx source zip.
  - **buckleypaul/zmkonfig**: MIT. Native ZMK editor that preserves the file byte-for-byte outside edited ranges, and has diff, commit, CI watch and flash.
  - **qmk/qmk_toolbox**: MIT. Its macOS flasher is written in Swift.
  - **keyfinder**: GPL-3.0. ZSA layer overlay.
  - **LayerLens**: GPL-3.0. VIA overlay.
- **"Escape hatch" tools prove the demand for Oryx's GUI plus full QMK:**
  - **poulainpi/oryx-with-custom-qmk**: 223 stars, MIT, GitHub Actions. ZSA blogged about it.
  - **voyager-keyboard-helper**
  - **oryx-bench**: TOML + Zig overlays, lint, deterministic builds.
- **Git versioning and two-way sync:** **jyn514's `oryx_sync.py`** keeps a git-owned snapshot, diffs it against Oryx and *writes back* through undocumented GraphQL mutations with a bearer token. That is a ToS-grey area (section 5.1).

### 0.3 Legal

- **No Terms of Service.** ZSA publishes none for Oryx or its API.
  - Oryx's footer link `zsa.io/privacy-policy-and-terms-of-service/` redirects (301) to `/privacy`, which contains no terms (section 5.1).
  - `configure.zsa.io/robots.txt` disallows everything except `/`.
- **Unauthenticated read precedent.** The GraphQL endpoint and `/firmware/{revisionId}` need no authentication. ZSA's own open-source Zapp reads them.
- **Sextant's policy:** read-only, per-user, cached access to the user's own layouts is defensible, but it is not a granted right (INFERRED).
  - Ask ZSA (`contact@zsa.io`) for written permission before release. Mac App Store guideline 5.2.2 needs that authorization anyway.
  - Never use mutations or Keymapp's auth-phrase login without permission.
- **Trademarks** (third-party aggregators; verify in USPTO TSDR):
  - MOONLANDER and ERGODOX EZ are registered.
  - VOYAGER, ZSA, NAVIGATOR and TYP.ING are applications.
  - No record was found for ORYX or KEYMAPP, but common-law rights still apply.
  - Say "for the ZSA Voyager" nominatively, add a non-affiliation disclaimer, and never put Oryx, Keymapp, Wally, Zapp or Kontroll in Sextant's name or icon.
- **QMK GPL-2.0:**
  - Generating keymap source and invoking a toolchain the user installs is fine for a closed Sextant.
  - Shipping compiled firmware or bundling QMK means GPL source obligations.
  - Downloading and running a toolchain is barred on the Mac App Store (guideline 2.5.2).
  - So: **distribute with Developer ID + notarization**, not on the Mac App Store.
- **Zapp's license is MIT + Commons Clause.** It forbids selling a product whose value derives substantially from Zapp, so don't link `zapp-core` into a paid app.
- **The name "Sextant":**
  - No conflict found among keyboard or developer tools.
  - The App Store already has several celestial-navigation "Sextant" apps.
  - A Swift package `KittyMac/Sextant` (MIT, JSONPath) exists, a module-name clash only if both are imported.
  - Historic SEXTANT software marks exist.
  - Run a formal trademark clearance before any commercial launch.

### 0.4 Pain points

Users complain about, or build tools around:
1. cloud and Chromium-only workflows
2. recompile-and-reflash for every change
3. missing QMK features, and merge conflicts in the workarounds
4. no undo, diff or git
5. macro limits and public-by-default macros
6. home-row-mod tuning
7. Keymapp's exclusive HID access, lack of menubar or transparency, and no heatmap export
8. mouse-only editing
9. no layer duplication or bulk edits
10. locale confusion

Each maps to a concrete native-app opportunity (section 6).

### 0.5 Open-source Voyager and Corne (the user's added request)

- **Voyager firmware is fully open:**
  - upstream `qmk/qmk_firmware/keyboards/zsa/voyager`
  - `zsa/qmk_firmware@firmware25`
  - `zsa/qmk_modules`, GPL-2.0-or-later
- **Voyager hardware design files are not published** (INFERRED: absent from ZSA's GitHub; `zsa/docs` holds only ErgoDox EZ schematics). Spare parts and teardown guides are offered.
- **Hardware facts readable from QMK:**
  - 12x7 matrix
  - right half read through an MCP23018 I/O expander
  - 2x IS31FL3731 drivers for 52 RGB LEDs
  - 4 status LEDs
  - "Ignition" bootloader
  - MCU: STM32F303xB-class (128 KB flash) per QMK PR #23912; a GD32F303CB per the RMK port. The upstream readme's "xC" is stale (05 §2.1).
- **Corne:** open hardware (MIT + CC-BY-4.0), 36 or 42 keys, supported by QMK, Vial, VIA and ZMK (with ZMK Studio).
- **What Corne teaches Sextant:**
  1. Render geometry from QMK `keyboard.json` / `info.json` rather than hard-coding it.
  2. The Corne world shows the live-remap UX (VIA, Vial, ZMK Studio) that Oryx firmware cannot do (section 4).

---

## 1. Sources examined

| Source | Version / date | Local copy |
|---|---|---|
| ZSA blog (all 168 posts, JSON Feed v1) | `https://blog.zsa.io/posts.json`, newest post 2026-08-11 ("Dual Navigators"); sitemap cross-checked, no posts missing | `downloads/zsa-blog/posts.json`, text in `study_tmp_blog/*.txt` |
| ZSA site pages | `zsa.io/{oryx,smart,training,tools,keymapp,flash,help,trust}`, fetched 2026-10-11 | `downloads/zsa-site/*.html`, text in `work/04/site-*.txt` |
| ZSA privacy policy | `https://www.zsa.io/privacy`, "Effective date: April 30, 2026" | `downloads/zsa-legal-04/pp-tos.html`, `work/04/privacy-2026-10-11.txt` |
| robots.txt | configure.zsa.io (200), oryx.zsa.io (404), www.zsa.io (200) | `downloads/zsa-legal-04/robots-*.txt` |
| The Ergo newsletter archive | 2026-01 to 2026-09 | `downloads/ergo-archive/`, text in `work/04/ergo-2026-*.txt` |
| Oryx web bundle | `configure.zsa.io/assets/*` (156 files), main `index-xhNfd6BI.js` md5 `34fbb4d6…` | `downloads/oryx-web/assets/`; UI string dump `work/04/oryx-ui-strings.tsv` |
| Oryx settings catalog | `const Kd=[…]` at `index-xhNfd6BI.js@641538`; visibility filter `function OU(` at `@676678` | `study/04-oryx-settings-catalog.json` |
| Oryx keycode catalog | `configure.zsa.io/metadata.json` (see `_source` in the file) | `study/oryx-keycodes.json` (other researcher; schema evolving) |
| User layout + examples | GraphQL read of `KlgM7/40xJ7M`; example Voyager layouts | `oryx/layout-full.json`, `oryx/examples/*.json` |
| Generated source zips | user `KlgM7`, example `JRGQm` | `downloads/layout-source-c/extracted/`, `downloads/oryx-source-JRGQm/extracted/` |
| `zsa/zapp` | `a1be75837323001ad1ae8e5787d88cd33f2ccc46` (v1.0.2, 2026-07-09) | `downloads/zapp/zapp/` |
| `poulainpi/oryx-with-custom-qmk` | `26bfbe6fbb4059554743575e177124ad2488a311` (2026-05-14) | `downloads/oryx-with-custom-qmk/repo/` |
| `zsa/qmk_modules` | `13890cd7856175de20798689d15ba6a46bf0c5c7` (2026-08-10) | GitHub API |
| Upstream QMK Voyager | `qmk/qmk_firmware` master: `keyboards/zsa/voyager` last change `47575d4a` (2025-01-20); `keyboard.json` last change `089a8191` (2024-06-16) | `downloads/qmk-voyager-kbjson/` (copied from master `7a1bbf37`) |
| QMK license docs | `docs/license_violations.md` @ `2cbcd76e` (2026-03-16; local blob `390280df` matches), `LICENSE` (GPLv2) | `downloads/qmk-docs/` |
| Corne | `foostan/crkbd` (LICENSE_MIT + LICENSE_CC); `qmk/qmk_firmware/keyboards/crkbd/info.json` @ `c9cd92ec`; ZMK `app/boards/shields/corne` | `downloads/corne-04/` |
| Prior-art READMEs | 13 from an earlier run plus 16 fetched now | `downloads/gh-readmes/`, `downloads/gh-readmes-04/` |
| GitHub metadata | 69 repos via `gh api repos/…` | `study/04-prior-art-repos.tsv` |
| Hacker News | Algolia dumps ("oryx", "keymapp", "zsa voyager") and 3 threads | `downloads/hn/` |
| Reviews | benfrain.com (2023-11-12), filiphalas.com (2024-06-02), cheeseturbulence.com (2026-01-31) | WebFetch (not stored) |
| Apple App Review Guidelines | `https://developer.apple.com/app-store/review/guidelines/` | WebFetch (not stored) |
| Trademark data | Justia, uspto.report and Trademarkia snippets via web search (direct pages returned 403) | not stored; **verify in USPTO TSDR** |

**Not reachable:**
- Reddit returned 403 to curl and is blocked for WebSearch/WebFetch, so r/ErgoMechKeyboards and r/zsaVoyager could not be read.
- ZSA has no public forum or feature board (INFERRED: none linked from zsa.io or the blog, and none found by web search); support is by email ([zsa.io/help](https://www.zsa.io/help): "Not Facebook, Reddit, or Twitter … Just plain old email").
- Pain points are therefore drawn from HN, GitHub issues, reviews, ZSA's own blog acknowledgements, and the motivations stated in community tools' READMEs.

---
## 2. Oryx feature inventory (as of 2026-10-11)

Legend:
- **V** column: `all` = available on every ZSA board including the Voyager. `V+` = also available on the Voyager. `not V` = not available on the Voyager. `V-spec` = specific to the Voyager or the Voyager/Moonlander family.
- Abbreviations: B = `https://blog.zsa.io/<slug>/`, KC = `study/oryx-keycodes.json`, CAT = `study/04-oryx-settings-catalog.json`, LJ = `oryx/layout-full.json`.

### 2.1 Per-key data model and slots

The model below is from the stored layout JSON (LJ). Each layer has `title`, `color`, `position`, `hashId`, `prevHashId`, `builtIn`, `automouse` and `keys[52]`. Each key has:

| Field | Meaning | Source |
|---|---|---|
| `tap`, `hold`, `doubleTap`, `tapHold` | The 4 action slots. Each is `{code, modifiers, modifier, layer, macro, color, description}` | LJ (key objects); B `2101-introducing-tap-dance` |
| `customLabel` | User text legend | B `2008-oryx-changes` |
| `icon` / `emoji` | Icon from ZSA's hand-made set, or an emoji. An icon takes over the whole legend | B `2208-emoji-keys` |
| `glowColor` | Per-key colour on this layer | B `layout-buffet-backlighting` |
| `lockGlowColor` | Colour shown while Caps, Num or Scroll Lock is on (only Caps Lock on macOS) | B `lock-indicator` |
| `tappingTerm` | Per-key tapping term (needs the global "Per-key tapping term" setting) | B `per-key-dynamic-tapping-terms`; CAT `perKeyTappingTerm` |
| `about`, `aboutPosition` | Layout-tour annotation text and its order | B `2004-layout-tours`; LJ |

### 2.2 Key actions

| Feature | What Oryx does, and its limits | V | Source |
|---|---|---|---|
| Single key / modified key | Any keycode on tap. Ctrl, Shift, Alt/Opt and GUI/Cmd can be added per slot to send shortcuts such as Cmd+S in one keystroke | all | [zsa.io/oryx](https://www.zsa.io/oryx); LJ `modifiers` |
| Hold (dual-function) | A tap action plus a hold action. Since May 2025 *any* tap+hold pair is generated as a QMK dual-function key; before that, anything other than "key + modifier/layer" became a Tap Dance. A setting restores the old behaviour | all | B `tap-hold-update`; CAT `legacyDualFunctionDances` |
| Double-tap, tap-then-hold | Tap Dance, up to 4 functions per key. A Tap Dance can switch layers (TO, MO) since Mar 2021. Macros are allowed only on the tap slot (INFERRED from the key model, which only creates `e.tap.macro`: `index-xhNfd6BI.js@711526`). The Jan-2021 post says "Tap Dance can't run macros" | all | B `2101-introducing-tap-dance`, B `2103-tap-dance-layers` |
| "Shortcut Tap", "Two-Character key" | Dual-function variants Oryx makes easy: a character on tap and a shortcut or second character on hold | all | B `layout-buffet-dual-function-keys` |
| Advanced view | Badges: "D" = dual-function, "T"/"+" = Tap Dance. A Legend explains the key types | all | B `compact-layouts`; `Legend-LTsHAjDy.js@11968`; `_revisionId-CtR9sUEn.js@204803` |
| Transparent / None | Every key defaults to transparent (falls through the layer stack). `KC_NO` disables a key | all | B `introducing-transparent-keys-dynamic-macros-and-more` |
| One-shot modifier (OSM) | Tap-only. Includes Hyper and Meh one-shots. Timeout and tap-toggle settings apply | all | KC `OSM`; B `easy-to-use-nkro-and-other-configurator-updates`; CAT `oneShot*` |
| Hyper / Meh | `ALL_T` / `MEH_T` on tap+hold | all | KC |
| Space Cadet | Shift, Ctrl or Alt held; "(" or ")" on tap. Needs "Enable space cadet" | all | KC (`requires: config.enableSpaceCadet`); CAT `enableSpaceCadet` |
| Layer: MO | Hold or tap-hold. Only to *higher* layers | all | KC `MO.requires` |
| Layer: TG, TT | Tap. Higher layers only | all | KC |
| Layer: TO | Any slot, any layer (also lower ones) | all | KC; B `2103-tap-dance-layers` |
| Layer: OSL | Tap. Target layer < 16 | all | KC `OSL.params.maxLayers=16` |
| Layer: LM (layer + modifier) | Hold. Target layer < 16. Added Feb 2021 | all | KC; B `2102-changes-roudnup` |
| Layer Lock (`QK_LLCK`) | Tap, on any layer > 0. Feb 2024. "Layer lock idle timeout" setting (0-360 s) | all | B `layer-lock`; CAT `layerLockIdleTimeout` |
| `DF`, Tri-layer | **Not offered**. "Tri-layer … isn't something we support in Oryx" | - | KC (no `DF`); B `layout-buffet-layers` |
| Unblock TT/MO/LM in destination layer | By default the key that leads to a layer is reserved on that layer; this setting frees it | all | B `2008-oryx-changes`; CAT `ambidexLT` |
| Smart Layers keys | "Trigger Smart Layer" and "Toggle Smart Layer" keycodes. The app-to-layer mapping lives in Keymapp (Windows/macOS only) | all | KC `ORYX_SL_*`; B `smart-layers`; [zsa.io/smart](https://www.zsa.io/smart) |
| Caps Word | Tap only. May 2022 caveats: not inside multi-function keys, and doesn't capitalize letters sent by multi-function keys | all | B `2206-caps-word`; KC |
| Auto Shift | 7 settings plus 6 runtime keycodes (on, off, toggle, report, up, down) | all | CAT `autoshift*`; KC `autoshift` |
| Dynamic tapping term | Keys: term +5 ms, -5 ms, and print (types the value) | all | B `per-key-dynamic-tapping-terms`; KC `DT_*` |
| Mouse keys | Move, wheel in 4 directions, buttons 1-8, acceleration 0-2. Speed curves in settings | all | KC `mouse`; CAT `mouse*` |
| Double Click, Mouse Jiggler | Jan 2026, tap only. Jiggler moves the cursor every second and lights an indicator LED. Both ship as open QMK modules | all | B `mouse-jiggler-and-double-click`; `zsa/qmk_modules@13890cd` (`doubleclick/`, `mousejiggler/`) |
| Media keys | 19, including Calc, Eject, Mail, Mute, Play, Next/Prev, Volume. WWW Back/Fwd are Windows-only | all | KC `media`; B `oryx-august-updates` |
| System keys | Brightness up/down, Power, Sleep, Wake | all | KC `system` |
| macOS-specific keys | Mission Control, Spotlight, Do Not Disturb, Lock Screen, Dictation. Tap only; "not available on dual-function keys or Tap Dance keys" | all | B `2212-macos-keycodes`; KC |
| Copy/Cut/Paste/Undo | PC and macOS variants, plus Find | all | KC `other` |
| International | Lang 1-9, Int 1-9 (JIS/Korean), plus 36 locale keycode packs enabled per layout | all | KC; CAT `international` |
| Steno | 44 steno keycodes. TX Bolt by default or GeminiPR. "Steno and Live Training don't mix" | all | CAT `stenography`; `_slug-Dpv49v-0.js` |
| Firmware keys | Reset to bootloader, EEPROM wipe, NKRO toggle | all | KC `fw` |
| Dynamic macros | 2 slots (record 1/2, play 1/2, stop). Ephemeral (lost on power-off). Needs "Enable dynamic macros" | all | B `introducing-transparent-keys…`; KC `macro`; CAT `enableDynamicMacros` |
| Combo keys | Combo on, off, toggle (only when the layout has combos) | all | KC `CMB_*` |
| Audio / music keys | 7 keycodes | **not V** (Planck EZ, Moonlander) | KC `audio.requires` |
| Indicator brightness `LED_LEVEL` | Cycles the status LEDs through brightness levels including off (25 % steps per the 2019 post) | **V+** (Voyager, Planck, ErgoDox) | KC; B `oryx-august-updates` |
| Indicator toggle | Moonlander only | not V | KC |
| Navigator keys | Aim, Turbo, Toggle Aim/Turbo/Scroll, Drag Scroll, CPI +/-, Clear Speed, Vertical Scroll Lock. CPI +/- move by 5 and reset on unplug | **V-spec** (needs a Navigator) | KC `navigator`; B `layout-buffet-mousing`, B `press-to-exit-auto-mouse-and-updates` |
| "Oryx" pairing key `WEBUSB_PAIR` | Legacy key. Since firmware 21, pairing uses 3 random keys instead, so the key is no longer needed | all | B `2206-bye-oryx-key`; KC |
| Copy key / paste to many | Jun 2024. Copy one key and paste it onto any number of keys (Edit mode only) | all | B `copy-keys`; `_revisionId-CtR9sUEn.js@7636` |
| Swap keys | Sep 2020. Swap two keys, across layers too. Macros, labels and colours move with them. ZSA deliberately offers no copy-layer, for firmware-size reasons | all | B `2009-swap-keys`; `_revisionId-CtR9sUEn.js@7133` |
| Link to key | Copies a URL to a key in a given layer, layout and revision | all | B `copy-keys` |
| Home-row-mod hint | When a key looks like a home-row mod, the key popup suggests enabling Chordal Hold | all | `useTourPreload-BzJOYeur.js@94016` ("It looks like you're trying out home row mods.") |

### 2.3 Macros

| Aspect | Value | Source |
|---|---|---|
| Max steps | **24** (`pf=24`). Before Apr 2025 the limit was 5 characters, and 4 before Feb 2021 | `index-Bvxi2_Kp.js@117410`; B `longer-oryx-macros`; B `2102-changes-roudnup` |
| Steps without an account or without acknowledgement | **5** (`Ve=5`). More steps need sign-in plus "I understand and acknowledge". The acknowledgement is stored server-side (mutation `acknowledgeMacroRisks`) "like accepting an EULA" | `index-Bvxi2_Kp.js@117410`, `@122501`; `index-xhNfd6BI.js@904354` (`acknowledgeMacroRisks`); B `longer-oryx-macros` |
| Per-step fields | `{code, modifiers, delay}`. Steps can be reordered (▲/▼) and deleted | `index-xhNfd6BI.js@752341` (MST model `SC`) |
| Delay | "Then wait" 0-**5000** ms per step, default **100** ms. 0 ms is allowed but unreliable; ZSA suggests ≥ 50 ms | `index-Bvxi2_Kp.js@120993` (`min:0,max:5e3`, `defaultValue:100`); B `longer-oryx-macros` |
| Options | `endEnter` (append Enter); `applyAlt` = "Hold Alt pressed (send Unicode)" for Windows Alt-codes, which clears per-step modifiers and hides delays | `index-xhNfd6BI.js@752341`; B `2008-oryx-changes` |
| Name | Optional macro name | model `SC.name` |
| Character set | Only unshifted base keycodes. Shifted or international characters are made from the base key plus modifiers | B `missing-macro-characters` |
| Unicode | No QMK Unicode keycodes. Use macros instead: Windows Alt-codes, macOS "Unicode Hex Input" (BMP only), Linux Ctrl+Shift+U | B `2008-oryx-changes`; KC (no `UC_*`) |
| Privacy | Macros are public by default. Private layouts are still plain text on the server | [zsa.io/privacy](https://www.zsa.io/privacy) "User Content"; B `longer-oryx-macros` |
| Placement | Tap slot of a key, or a combo output | model; B `2212-combos` |

### 2.4 Combos

| Aspect | Value | Source |
|---|---|---|
| Keys per combo | up to **6** (`rg=6`) | `index-xhNfd6BI.js@632262`; `_comboStep-0hH-FJFg.js@2814`; B `2212-combos` |
| Output | A keycode, a macro, or a layer switch (including hold and one-shot) | B `2212-combos` |
| Scope | **Layout-wide.** Combos match keys on any layer ("Combos look at keys, not layers") | B `2212-combos` |
| Excluded triggers | Tap Dance keys. Per-keycode `comboTrigger` and `comboPickable` flags | B `2212-combos`; KC |
| Combo term | 10-100 ms, default 50 | CAT `comboTerm` |
| UI | Named combos, a sidebar list, hover-highlight, edit/delete, conflict warning ("This combo is conflicting with combo …") | `_comboStep-0hH-FJFg.js@4929`; B `2212-combos` |
| Templates | Combos are *not* carried into layer templates | B `2212-combos` |

### 2.5 Tap-hold tuning (global, Voyager-relevant)

All from CAT unless noted. Ranges are slider min-max.

| Setting (key) | Default / range | Note / source |
|---|---|---|
| Tapping term `tappingTerm` | 200 ms, 0-1000 | |
| Per-key tapping term `perKeyTappingTerm` | off | Apr 2023, B `per-key-dynamic-tapping-terms` |
| Tap flow `flowTap` | toggleable, default **100** (bundle), 1-1000 | The May 2025 post says 150 ms is the default; the bundle says 100 (INFERRED: the default changed). B `tap-flow` |
| Prefer tap action in tap-hold tap dances `dancesTapAction` | on | |
| Troubleshoot media keys in Windows 10 `tapCodeDelay` | off | |
| Retro tapping `retroTapping` | off | |
| Permissive hold `permissiveHold` | off | |
| Hold on other key press `holdOnOtherKeyPress` | off | |
| Tapping force hold `tappingForceHold` | off | Apr 2019, B `introducing-transparent-keys…` |
| Legacy two-function tap dances `legacyDualFunctionDances` | off | B `tap-hold-update` |
| Chordal Hold `chordalHold` | off | Mar 2025, "one of the most requested features", B `chordal-hold` |
| Exclude thumb keys from Chordal Hold `chordalHoldExcludeThumbs` | **off** in the bundle. Shown for ergodox-ez(-st), moonlander, halfmoon, voyager | The Jun-2025 editor's note says thumbs are excluded "by default"; the current catalog makes it an opt-in toggle. When on, generated firmware marks thumbs `'*'` in `chordal_hold_layout` (`downloads/oryx-source-JRGQm/extracted/zsa_voyager_analyst-developer_source/keymap.c:230-236`; rows of `'L'`×6/`'R'`×6, thumbs `'*','*','*','*'`) |
| Oneshot tap toggle `oneShotTapToggle` | toggleable, 2-5 | |
| Oneshot timeout `oneShotTimeout` | toggleable, 100-8000 ms | |
| Achordion | **not offered**. Custom QMK only | B `oryx-custom-qmk-features` |

### 2.6 Layers

| Feature | Detail | V | Source |
|---|---|---|---|
| Count | "Create up to 32 virtual layers". OSL and LM can only target layers < 16. The user's firmware defines `LAYER_STATE_8BIT` (3 layers), so Oryx sizes the layer bitmask to the layout (INFERRED) | all | [zsa.io/oryx](https://www.zsa.io/oryx); KC; `downloads/layout-source-c/extracted/*_source/config.h` |
| Name, colour | Layer title; whole-layer colour ("Lights the whole keyboard in:") | all | LJ; `LayerColor-BD7PIMXY.js` |
| Reorder | Move left / right / to beginning / to end (replaced drag-and-drop in 2019) | all | `Legend-LTsHAjDy.js`; B `introducing-transparent-keys…` |
| Delete / restore | "Delete layer". Deleted layers can be brought back via "+ → Restore Layers" (`revision.hasDeletedLayers`) | all | `Legend-LTsHAjDy.js@8147`; LJ |
| Layer templates | Oct 2022. App-specific layers from the community, filtered by OS, searched by tag, previewed, "Add to my layout" | all | B `2210-layer-templates`; routes `/templates/layers/$geometry/search`, `/templates/layers/preview/$hashId` |
| Built-in layer groups | Planck Lower/Raise/Adjust ("Built-in tabs") | not V | B `introducing-transparent-keys…`; `Legend-LTsHAjDy.js` |
| Auto-mouse layer | Per Navigator; layer field `automouse` | V-spec | B `dual-navigators`; LJ |

### 2.7 Lighting

| Feature | Detail | V | Source |
|---|---|---|---|
| Two lighting modes | "Core" (animations, adjusted on the board) and "Custom" (per-key and per-layer colours set in Oryx). Custom overrides Core for the whole layer | V+ (model `v1`) | B `lighting-terms`; B `layout-buffet-backlighting`; KC `RGB.requires: model in [shine, glow, mk1, v1]` |
| Colour tools | Per-key colour, layer colour, "Individual keys" paint-bucket, swatches, eyedropper (2019), HEX input | V+ | B `layout-buffet-backlighting`; `ColorPopover-CXVviGF3.js`; B `introducing-transparent-keys…` |
| Lock indicator colours | Aug 2025 | V+ | B `lock-indicator` |
| Animation list | 48 animations that can be individually disabled (saves firmware space) | V+ | CAT `disabledAnimations`; B `2301-pick-animations` |
| RGB settings | Hue step 1-24 (8), brightness step 1-24 (16), disable after inactivity 0-15 min, disable when suspended (on) | V+ | CAT `rgb*` |
| Lighting keys | 13 colour-control keycodes | V+ | KC `shine` |
| Status LEDs | 4 LEDs (binary layer number by default). "Enable caps lock status" uses an indicator LED | V-spec (4 LEDs) | upstream `keyboards/zsa/voyager/readme.md`, `voyager.c:111-116`; CAT `capsLockStatus` |

### 2.8 Global settings (all sections)

Full catalog with descriptions: `study/04-oryx-settings-catalog.json`.

Visibility rules (`index-xhNfd6BI.js@676678`, `function OU`):
- Audio is hidden for ErgoDox and **Voyager**.
- Navigator is shown only when a Navigator is attached.
- RGB is hidden for model `original`.
- `glow:true` settings are hidden for model `shine` or `standard`.

The settings page has:
- a free-text filter over titles and descriptions ("Begin typing to filter settings…", `_slug-Dpv49v-0.js@83884`)
- "Reset all settings" (`@83426`)
- per-setting reset-to-default

| Section (slug) | # | Settings (default) | V |
|---|---|---|---|
| Auto shift (`autoshift`) | 7 | enable (off); timeout 175 ms (50-350); modifiers (off); special keys, numeric, letters, tab (all on) | V+ |
| Audio (`audio`) | 2 | silent mode, audio click | **not V** |
| Combo (`combo`) | 1 | combo term 50 ms (10-100) | V+ |
| Debounce (`debounce`) | 1 | debounce 0-50 ms; per-board default, **voyager 5** | V+ |
| International (`international`) | 36 | one toggle per locale keycode pack: Belgian, Bépo, Brazilian, Canadian multilingual, Croatian, Czech, Danish, English - Great Britain, Estonian, French, French Canadian, German, Hungarian, Icelandic, Italian, Japanese, Kazakh, Korean, Lithuanian (AZERTY), Nordic, Norwegian, Polish (programmer's), Portuguese, Portuguese macOS, Romanian, Russian, Slovak, Slovenian, Spanish, Spanish-Latin American, Swedish, Swiss French, Swiss German, Turkish, Ukrainian, US - International | V+ |
| Misc (`misc`) | 10 | caps lock status; disable USB startup check; wake-up delay 0-500; layer-lock idle timeout 0-360 s; **"Oryx connection"** (raw-HID protocol for Keymapp, typ.ing and Zapp; on); disable NKRO; low polling rate (125 Hz); enable dynamic macros; enable space cadet; enable Navigator (ErgoDox EZ ST and Halfmoon only) | V+ |
| Mouse Keys (`mouse`) | 8 | mouseInterval 20 (1-40); mouseDelay 10 (0-40); mouseMaxSpeed 10 (1-14); mouseTimeToMax 30 (1-120); mouseWheelInterval 80 (20-200); mouseWheelMaxSpeed 8 (1-16); mouseWheelTimeToMaxSpeed 40 (1-80); mouseWheelDelay 400 (0-800) | V+ |
| RGB (`rgb`) | 5 | see 2.7 | V+ |
| Stenography (`stenography`) | 2 | steno; GeminiPR | V+ |
| Tapping (`tapping`) | 5 | see 2.5 | V+ |
| Tapping (Dual-functions) (`tapping-dual`) | 5 | see 2.5 | V+ |
| Oneshot (`oneshot`) | 2 | see 2.5 | V+ |
| Holding (`holding`) | 3 | unblock TT/MO/LM; chordal hold; exclude thumbs | V+ |
| Navigator (`navigator`) | 13 | see 2.9 | V-spec |

Counts per section are from CAT. Several Misc settings were introduced in B `2102-changes-roudnup` (USB/KVM troubleshooting: startup check, 125 Hz polling, disable NKRO, disable Live Training) and B `2103-tap-dance-layers` (caps-lock status).

### 2.9 Navigator (trackball / trackpad), Voyager and Moonlander

| Feature | Detail | Source |
|---|---|---|
| Devices | Trackball (Aug 2025) and trackpad (May 2026). One per side; **two at once** since Aug 2026, and they must be one of each kind | HN story [45015468](https://news.ycombinator.com/item?id=45015468) "The Navigator: A trackball for your Voyager" (2025-08-25, `downloads/hn/oryx_stories.json`); B `dual-navigators`; [Ergo 2026-05](https://the-ergo-archive.zsa.io/newsletters/2026/05.html), [2026-08](https://the-ergo-archive.zsa.io/newsletters/2026/08.html) |
| Per-device settings | Auto-mouse activation threshold (10, 0-100); deactivation delay (650 ms, 1-5000); "Press to exit auto-mouse" (Oct 2025) with idle timeout (10 s, 1-15); rotation (-180 to 180°); and, for trackball only, invert scroll X/Y, scroll only, Aim/Turbo speed (Slower/Default/Faster), Aim layers, Turbo layers, Drag-scroll layers | CAT `navigator`; B `press-to-exit-auto-mouse-and-updates`, B `navigator-trackpad-feature-update`, B `navigator-sensitivity-rotate-settings` |
| Stored but outside CAT | Trackpad fields in LJ: `tap`, `tapRight`, `scrollWithTwoFingers`, `scrollInertia`, `sensitivity`, `scrollSensitivity`, `orientation`; plus Navigator panel sliders "Trackball sensitivity" and "Scrolling sensitivity" | LJ `revision.navigators.right`; `Rocket-CfXlil5s.js` |
| Firmware | QMK modules `navigator_trackball` (pointing_device), `navigator_trackpad` (digitizer), `automouse` (GPL-2.0-or-later). The user's `rules.mk` sets `PRECISION_TRACKPAD_ENABLE = yes`, `PRECISION_TRACKPAD_DRIVER = navigator_trackpad` | `zsa/qmk_modules@13890cd` `*/qmk_module.json`; `downloads/layout-source-c/extracted/*_source/rules.mk` |
| macOS companion app | Closed-source "Navigator companion app" (macOS) supplies gestures, because macOS gives third-party trackpads only basic mouse drivers | B `navigator-trackpad-feature-update`; [zsa.io/privacy](https://www.zsa.io/privacy) |
| Flashing caveat | "You won't be able to use your Navigator while flashing." | `_revisionId-CtR9sUEn.js` (string) |

### 2.10 Layout lifecycle, accounts, sharing

| Feature | Detail | Source |
|---|---|---|
| Anonymous use | Allowed. Anonymous layouts persist indefinitely and aren't linked to anyone | [zsa.io/privacy](https://www.zsa.io/privacy) |
| Accounts | Since Jun 2019. Email, Google or GitHub login (Facebook removed); 2FA with recovery codes; change email; reset password; delete account | B `whats-new-with-oryx-i18n-ui-improvements-and-more`; B `2008-oryx-changes`; `sign-in-BCBZB8U0.js`; `index-C5XEMRdr.js` |
| Data export | **Only "Live training statistics"**. There is no layout export besides the source zip and firmware | `index-C5XEMRdr.js@6177` |
| Keymapp sign-in | 60-second "auth phrase" copied from `/account/auth_phrase` into Keymapp (`oryx.zsa.io/authenticate/auth_phrase`) | `auth_phrase-BzkQAU9L.js@4554` |
| Revisions | Every compile creates a revision with optional notes ("Some notes about what you changed:"); the title is used as a commit message (Zapp prints it) | `_revisionId-CtR9sUEn.js@217486`; `downloads/zapp/zapp/zapp-oryx/src/lib.rs:26-31,71-108` |
| Revision management | Revision timeline per layout ("(Edits not described.)"); fork revision; delete revision; "Revision not compiled"; `latest` alias; `layout.new` (opens your latest layout as a new draft revision) | `MyLayoutDetails-BTNpgP_c.js@2377,@2525`; B `2010-layout-new-live-training` |
| Firmware badge | Shows when a layout was built on an older QMK; "clone and recompile" to update (`revision.qmkVersion`, `qmkUptodate`) | B `whats-new-with-oryx-i18n…`; LJ |
| Fork / clone | Clone any public layout; the user's layout title ends "[fork]" | [zsa.io/oryx](https://www.zsa.io/oryx); LJ `title` |
| Rename / delete layouts | Since Sep 2019 | B `1909-oryx-changelog` |
| Privacy | Public by default. "Make layout private/public" needs an account. Private ≠ encrypted | `_revisionId-CtR9sUEn.js@204360`; [zsa.io/privacy](https://www.zsa.io/privacy) |
| Tags and search | Up to **6 tags, ≤ 15 characters each**; tagged layouts become searchable. Search by tag with filters "Include anonymous layouts" and "With tour" (Elastic-backed since 2020) | `_revisionId-CtR9sUEn.js@215715`; `search-B_iANk67.js@8257,@8459`; B `2008-oryx-changes` |
| Embed | "Copy embed code" (public layouts, view mode): an `<iframe src="/embed/{geometry}/layouts/{id}/{rev}/0">` in a 60 %-padding wrapper | `_revisionId-CtR9sUEn.js@204514`; B `2005-layout-embeds` |
| Print | "Print layout" → `/{geometry}/print/{layoutId}/{revisionId}` (read-only view); a printable PDF has existed since 2019 | `_revisionId-CtR9sUEn.js@203731`; route at `index-xhNfd6BI.js@964073`; B `oryx-august-updates` |
| Default layouts | Page of stock layouts per board, each with a tour | route `/default-layouts`; `DefaultLayouts-Cqkkx6ZL.js` |
| UI | Light/Dark/Auto theme; onboarding tour; Advanced/Simple view; custom-labels toggle | `index-xhNfd6BI.js@944308`; `_revisionId-CtR9sUEn.js`; B `2008-oryx-changes` |
| Mobile | Editing on phones is routed to "Oryx is a desktop experience"; embeds have a mobile viewer | `mobile-error-p0oEDk1s.js@318`; B `2005-layout-embeds` |
| History / undo | Jun 2023: per-key undo/redo history; **disabled Oct 2023** because of performance cost. "Restore Layers" remains | B `history` |
| Diff / compare | **None.** No compare or diff UI strings exist in the bundle (INFERRED) | `work/04/oryx-ui-strings.tsv` |
| Keyboard shortcuts | **Essentially none.** The only handlers are Enter, Escape and Tab in dialogs and arrows in tours (INFERRED from a scan of the assets for `key===` / `keyCode`) | B `2004-layout-tours` (arrows, Esc) |

### 2.11 Layout tours and annotations

- **Annotation types.** Tours annotate a single key, multiple keys ("batch"), a combo or a layer, plus an intro and outro. Text is Markdown with a preview. Routes: `/key/$keyIdx/annotate`, `/batch-keys/$keys/annotate`, `/combo/$comboIdx/annotate`, `/layer/annotate`, `/intro`, `/outro`, `/edit-tour`, `/play` (`index-xhNfd6BI.js` route table).
- **Gated authoring.** Creating tours requires applying at `/apply-tour`, as an anti-spam measure (B `2004-layout-tours`). The user has the `annotation` and `annotationPublic` flags (LJ `user`).
- **Publishing.** A tour can be published or unpublished, can carry an optional video URL ("Also available as a video"), and can be previewed "from here" (`_revisionId-CtR9sUEn.js`; `index-jZ48jwCm.js`).
- **Playback.** Arrow keys and Esc navigate a tour (B `2004-layout-tours`).

### 2.12 Build, download and flash

| Feature | Detail | Source |
|---|---|---|
| Compile | Cloud build (Docker image with pinned gcc-arm-none-eabi, per 2020). The layout must have a name. Shows build errors and an over-size error ("Your firmware is over the top!") | B `2008-oryx-changes`; `_revisionId-CtR9sUEn.js@163999` |
| Download firmware | `.bin` for the Voyager (REST `oryx.zsa.io/firmware/{revisionId}`) | `zsa/zapp@a1be758:zapp-oryx/src/lib.rs:193-200` |
| Download source | zip with `*_source/{keymap.c, keymap.json, config.h, rules.mk, i18n.h?}`, `README.md`, `build.log`, `.bin`, `.bin.md5` (REST `oryx.zsa.io/source/{revisionId}`) | `downloads/oryx-source-JRGQm/extracted/`; `poulainpi/oryx-with-custom-qmk@26bfbe6:.github/workflows/fetch-and-build-layout.yml:54` |
| Source zip README | Explains building against ZSA's fork or mainline and links the community custom-QMK tool | `downloads/oryx-source-JRGQm/extracted/README.md` |
| Generated `keymap.json` | Declares QMK community modules: `zsa/oryx`, `zsa/mousejiggler`, `zsa/navigator_trackpad`, `zsa/automouse`, `zsa/defaults` | same, `keymap.json` |
| Firmware identity | `#define SERIAL_NUMBER "KlgM7/40xJ7M"`, so layout and revision are readable from the USB serial-number string with no HID protocol at all. Zapp parses it with `serial.split_once('/')` to check for newer revisions. Keymapp also sends this hash to Oryx | `downloads/layout-source-c/extracted/*_source/config.h`; `zsa/zapp@a1be758:zapp/src/main.rs:106-107`, `zapp-core/src/device/monitor.rs:65`; B `introducing-zapp`; [zsa.io/privacy](https://www.zsa.io/privacy) |
| Flash in browser | WebUSB, Chromium only; needs a click while the board is in bootloader; Windows needs Keymapp's driver; Linux needs udev rules (`/udev` page) | B `2206-live-flashing`; `_revisionId-CtR9sUEn.js@175472`; [zsa.io/flash](https://www.zsa.io/flash) |
| Keymapp / Zapp | Desktop GUI flasher and viewer; CLI flasher (`zapp flash <file\|url>`, `zapp update`) | [zsa.io/flash](https://www.zsa.io/flash); B `introducing-zapp`; 03 §5 |
| Custom-QMK escape hatch | Download source and build locally. ZSA links poulainpi's tool and blogged a full tutorial, but "we won't be able to help you troubleshoot" custom QMK | B `oryx-custom-qmk-features`; source README |

### 2.13 Training (formerly "Train" in Oryx, now typ.ing)

| Era | Feature | Source |
|---|---|---|
| Dec 2019 | Live Training over WebHID: pressed keys, chords and layer changes shown live | B `1912-live-training` |
| Feb 2020 | Code snippets, custom texts (stored locally), session length, mistyped-character summary | B `2002-live-training-improvements` |
| Oct 2020 | Numbers/symbols drills with adaptive repetition; book excerpts | B `2010-layout-new-live-training` |
| Dec 2020 | Heat map | B `2012-introducing-heatmaps` |
| Jun 2022 | Pairing by typing 3 random keys (firmware 21+) | B `2206-bye-oryx-key` |
| Nov 2022 / Mar 2023 | Whack-a-Key (single-key precision); lights the correct key on the board | B `whack-a-key`, B `2303-lights` |
| 2024 to Jan 2026 | Features moved to **typ.ing**; "Code Mode is the last one to make the move" | [Ergo 2026-01](https://the-ergo-archive.zsa.io/newsletters/2026/01.html) |
| now | Oryx nav "Train" → `https://typ.ing/oryx`. Live view via `/connect`; slash-command, keyboard-only UI; "Make sure the Keymapp app isn't open … it will conflict" | `index-xhNfd6BI.js@941107`; `downloads/typing-04/oryx.html`; [zsa.io/training](https://www.zsa.io/training) |
| now | Heatmap lives in Keymapp (processed on-device) | [zsa.io/keymapp](https://www.zsa.io/keymapp); [zsa.io/privacy](https://www.zsa.io/privacy) |

### 2.14 Keymapp (the companion app Sextant may also replace)

The protocol, API and implementation are in 03 §5. Features:
- live layout view (can be pinned always on top)
- per-layer heatmap
- Smart Layers (app-to-layer, Windows and macOS only)
- flashing
- an "Edit" shortcut to Oryx
- an opt-in local API (Kontroll)

Sources: [zsa.io/keymapp](https://www.zsa.io/keymapp), B `keymapp`, B `smart-layers`, B `introducing-kontroll`.

Documented limitations ([zsa.io/smart](https://www.zsa.io/smart)):
- "Can't minimize to menubar or system tray"
- "you can't make the window semi-transparent"
- overlays such as Spotlight and Alfred aren't detected as active apps

Since Dec 2023 it is also on the Mac App Store (B `2312-updates`). That build is sandboxed, so its API socket lives under `~/Library/Containers/io.zsa.keymapp/…` (`zsa/kontroll#15`).

### 2.15 Paid tier

**None found.**
- The bundle contains no user-facing pricing, plan, subscription, "Pro" or "Premium" strings (scan of all 156 assets; the only "subscribe" and "upgrade" matches are inside third-party libraries such as MobX and JSZip).
- No blog post mentions an "Oryx Pro". The only "Premium" is a card deck (B `zsa-cards-premium`).
- [zsa.io/oryx](https://www.zsa.io/oryx): "Even if you don't yet own one of our keyboards, Oryx is worth checking out."

### 2.16 Internal and admin-only surfaces

These are not user features, but they appear in the route table:
- `/qc` is a factory test page (key test, RGB test, status LEDs, serial numbers; `qc-CoQYcMsw.js`).
- The Layer Template admin editor (`LayerTemplateAdminEditorPanel-DZ0fF7MH.js`).
- Tour access grants ("Grant/Remove access to tours").

Sextant does not need them.

### 2.17 Feature timeline (Oryx and adjacent)

| Date | Change | Source |
|---|---|---|
| 2019-01 | NKRO toggle key; one-shot Hyper/Meh | B `easy-to-use-nkro-and-other-configurator-updates` |
| 2019-04 | Transparent keys shown; dynamic macros; eyedropper; tapping force hold | B `introducing-transparent-keys-dynamic-macros-and-more` |
| 2019-06/07 | User accounts; more locales; firmware badge; key glow; layer colour toggle | B `whats-new-with-oryx-i18n-ui-improvements-and-more` |
| 2019-08/09 | Indicator brightness key; smart LED brightness; rename/delete layouts; Space Cadet in all locales | B `oryx-august-updates`, B `1909-oryx-changelog` |
| 2019-12 | Live Training | B `1912-live-training` |
| 2020-03/04/05 | Macros; layout tours; embeds and mobile viewer | B `2003-oryx-macros`, B `2004-layout-tours`, B `2005-layout-embeds` |
| 2020-08/09 | Custom labels; 2FA; Elastic search; swap keys | B `2008-oryx-changes`, B `2009-swap-keys` |
| 2020-10/12 | layout.new; number/symbol training; heat maps | B `2010-…`, B `2012-…` |
| 2021-01/02/03 | Tap Dance; 29 locales; KVM troubleshooting settings; LM; LED timeout; Tap Dance layer switching; caps-lock indicator | B `2101-…`, B `2102-…`, B `2103-…` |
| 2022-06/08/10/12 | Browser flashing; pairing without the Oryx key; Caps Word; icons/emoji; layer templates; Combos; macOS keycodes | B `2206-*`, B `2208-emoji-keys`, B `2210-layer-templates`, B `2212-*` |
| 2023-01/04/06/10 | Animation toggles; dynamic and per-key tapping term; History (then disabled in Oct); Keymapp (launched with the Voyager in 2023, all boards from Nov) | B `2301-pick-animations`, B `per-key-dynamic-tapping-terms`, B `history`, B `keymapp` |
| 2024-02/03/06/07 | Layer Lock; Smart Layers (GA May); copy keys and link to key; Kontroll | B `layer-lock`, B `smart-layers`, B `copy-keys`, B `introducing-kontroll` |
| 2024-11 | Custom-QMK GitHub workflow tutorial | B `oryx-custom-qmk-features` |
| 2025-03/04/05 | Chordal Hold; 24-step macros with delays; Tap Flow; any tap+hold becomes dual-function | B `chordal-hold`, B `longer-oryx-macros`, B `tap-flow`, B `tap-hold-update` |
| 2025-08/10 | Lock-indicator colours; Navigator trackball; press-to-exit auto-mouse | B `lock-indicator`, B `press-to-exit-auto-mouse-and-updates` |
| 2026-01/03/04 | Double Click and Mouse Jiggler; Aim/Turbo speeds and per-layer activation, trackball rotation, auto-mouse rewrite; Zapp | B `mouse-jiggler-and-double-click`, B `navigator-sensitivity-rotate-settings`, B `introducing-zapp` |
| 2026-05/06/08 | Navigator trackpad and macOS companion app; dual Navigators, scroll-only, per-Navigator auto-mouse layers | Ergo 2026-05/06; B `navigator-trackpad-feature-update`, B `dual-navigators` |

### 2.18 QMK capabilities Oryx does NOT expose

These are relevant to Sextant's scope decisions.

| Capability | Status in Oryx | Source |
|---|---|---|
| Key Overrides | not offered; custom QMK only | B `oryx-custom-qmk-features` (lists it as code-only) |
| Achordion | not offered; Chordal Hold is the in-core successor | B `chordal-hold`, B `oryx-custom-qmk-features` |
| Repeat Key, Autocorrect | not offered | B `oryx-custom-qmk-features`; KC (no `QK_REP`, no `AC_*`) |
| Leader key | not offered (no `QK_LEAD` keycode). A third party wrote that Oryx "likely will not add Leader Key anytime soon due to the UI complexity" | KC; [filiphalas.com](https://filiphalas.com/getting-started-qmk-zsa-voyager) (2024-06-02) |
| Tri-layer, `DF`, Swap Hands | not offered | B `layout-buffet-layers`; KC |
| Unicode keycodes (UC/UM/UP), OS detection | not offered; macros only | KC; B `2008-oryx-changes` |
| Per-key permissive-hold / hold-on-other-key / quick-tap | not offered (global only) | `j7j7/voyager-keyboard-helper` README comparison table; CAT |
| Per-layer combos | not offered (layout-wide only) | B `2212-combos` |
| Right-half-disconnected "gaming mode" | not offered; needs a custom `housekeeping_task_user` | upstream `keyboards/zsa/voyager/readme.md` |
| Arbitrary C | not offered | B `oryx-custom-qmk-features` |

---
## 3. Prior art

Metadata (stars, language, license, created and pushed dates) is from `gh api repos/<owner>/<repo>` on 2026-10-11 (`study/04-prior-art-repos.tsv`). GitHub's license detection is shown as given. Where the LICENSE file says something else, both are noted.

**Maturity scale:**
- **prod**: maintained and used by many people
- **beta**: working, early
- **proto**: experiment or single-author
- **stale**: no pushes for more than a year

### 3.1 ZSA's own open-source pieces

| Project | What it does | Lang | License | Activity | Maturity | Learn / reuse |
|---|---|---|---|---|---|---|
| [zsa/qmk_firmware](https://github.com/zsa/qmk_firmware) | QMK fork that Oryx compiles; default branch `firmware25` | C | GPL-2.0 | pushed 2026-09-02 | prod | The build target for any local compile. Pin the branch to `revision.qmkVersion` |
| [zsa/qmk_modules](https://github.com/zsa/qmk_modules) | QMK community modules: `oryx` (raw-HID protocol), `automouse`, `defaults` (ZSA keycodes), `doubleclick`, `keycolors`, `mousejiggler`, `navigator_trackball`, `navigator_trackpad` | C | GPL-2.0 (modules say GPL-2.0-or-later) | `13890cd` 2026-08-10 | prod | Needed for parity in local builds (Navigator, jiggler, live protocol) |
| [zsa/zapp](https://github.com/zsa/zapp) | CLI flasher: `flash <file\|Oryx URL>`, `update` (reads `layoutId/revisionId` from the board, fetches the latest). Crates `zapp-core` (DFU/HalfKay, firmware parsing, device watcher) and `zapp-oryx` (GraphQL + `/firmware/…`) | Rust | **MIT + Commons Clause** (`LICENSE.md`); GitHub says NOASSERTION | v1.0.2 2026-07-09; 209 stars | prod | The cleanest reference for Oryx REST endpoints (`/firmware/{rev}`, `?alt=true`, `?collate=true`, `/firmware/latest/{layoutId}`) and flashing. See 5.5 for the licence restriction |
| [zsa/kontroll](https://github.com/zsa/kontroll) | CLI for Keymapp's gRPC API; ships `keymapp.proto` | Rust | MIT | 1.0.4, 2025-02-22; 263 stars | stable | The proto can be reused to interoperate with Keymapp (03 §5.2) |
| [zsa/wally](https://github.com/zsa/wally) / wally-cli | Legacy flasher (Teensy HalfKay, STM32 DFU) | Go | MIT (`license.md`); GitHub NOASSERTION | 2024-08-21; cli archived | legacy | DFU sequence reference |
| [zsa/USBDeviceSwift](https://github.com/zsa/USBDeviceSwift) | 2019 fork of a pure-Swift IOKit USB/HID wrapper ([upstream](https://github.com/Arti3DPlayer/USBDeviceSwift), 315 stars, last push 2023-12) | Swift | MIT | 2019 | stale | Evidence that ZSA once prototyped in Swift; superseded by CoreHID/IOHIDManager (03 §8) |
| [zsa/oryx-with-custom-qmk](https://github.com/zsa/oryx-with-custom-qmk) | ZSA's fork of poulainpi's tool | - | MIT | 2025-02-06 | - | Shows ZSA endorses the "Oryx + custom QMK" workflow |

### 3.2 Oryx bridges and escape hatches (keep Oryx's GUI, add QMK power)

| Project | What it does | Lang | License | Activity | Maturity | Learn / reuse |
|---|---|---|---|---|---|---|
| [poulainpi/oryx-with-custom-qmk](https://github.com/poulainpi/oryx-with-custom-qmk) | GitHub Action. Queries GraphQL for `revision{hashId,qmkVersion,title}`, downloads `oryx.zsa.io/source/{revisionHashId}`, commits to an `oryx` branch, merges into `main` (user's custom C), builds with Docker `qmk setup zsa/qmk_firmware -b firmware{N}` | YAML/Docker | MIT | 2024-09-23 → 2026-05-14; **223 stars** | prod | Strongest demand signal. Issues show the pain: the merge-back step is under-documented (#16; merge conflicts are described in the ZSA blog tutorial and by filiphalas.com), Oryx description characters breaking the action (#42), firmware-version bumps breaking builds (#40, #44, #49), Navigator support asked (#61) |
| [nivekmai/oryx-build-extension](https://github.com/nivekmai/oryx-build-extension) | Chrome/Firefox extension: adds a bar to Oryx that triggers the workflow above and downloads the result | TS | MIT (GitHub); the Firefox AMO listing says GPL-3.0 | 2025-01 → 2026-05; 87 Chrome / 3 Firefox users ([CWS](https://chromewebstore.google.com/detail/oryx-extension/bocjciklgnhkejkdfilcikhjfbmbcjal), [AMO](https://addons.mozilla.org/en-US/firefox/addon/oryx-extension/)) | proto | Users want one-click "compile with my customizations" |
| [j7j7/voyager-keyboard-helper](https://github.com/j7j7/voyager-keyboard-helper) | Node script: takes the Oryx source zip from `~/Downloads`, appends C snippets (per-key chordal-hold exceptions, per-key permissive hold, flow-aware tapping term, unlimited macros, core patches), builds with the ZSA fork, flashes. Keys are addressed by Oryx `layer/key` index | JS | MIT | 2026-09-21 | proto | Lists exactly which per-key tap-hold knobs Oryx lacks (2.18) |
| [Enriquefft/oryx-bench](https://github.com/Enriquefft/oryx-bench) | "Workbench": Oryx *or* local `layout.toml`, plus `overlay/features.toml` (achordion, key overrides, macros, combos, tap-hold) and Zig/C overlays. Lint (e.g. `lt-on-high-freq`), deterministic Docker builds, flashes via zapp, auto-pulls from Oryx (GraphQL check cached 60 s). States "Oryx has no public write API" | Rust | MIT | v0.1.0, 2026-04-07 → 04-24 | proto | Good model for a declarative overlay and lint layer; designed to be driven by an AI agent |
| [Phoscur/oryx-macro-hax](https://github.com/Phoscur/oryx-macro-hax) (+ oryx-layer-inserter) | Post-processes the Oryx source to expand macros; companion tool copies layers between layouts | TS | none | 2021-12 → 2025-04; 7 stars | stale | Shows demand for copying layers across layouts |
| [jonberenguer/oryx-complex-macros](https://github.com/jonberenguer/oryx-complex-macros) | Placeholder-macro substitution (pre-2025 macro limit) | Python | MIT | archived 2021 | dead | - |
| YiftahCooper/…, KyleRoarty/oryx-with-custom-qmk | Forks of poulainpi | C | MIT | 2026 | - | - |

### 3.3 Oryx data clients: sync, git, convert, render

| Project | What it does | Lang | License | Activity | Learn / reuse |
|---|---|---|---|---|---|
| [jyn514/dotfiles `tools/moonlander/oryx_sync.py`](https://github.com/jyn514/dotfiles/blob/065018eced60383b67b04c73edbaf86258c04f98/tools/moonlander/oryx_sync.py) | Git-owned layout snapshot. `difflib` unified diff against Oryx; `--apply` replays changes through **undocumented GraphQL mutations** (`UpdateLayer`, `CreateLayer`, `DeleteLayer`, `UpsertCombo`, `DeleteCombo`, `UpdateLayoutTitle/Tags/Privacy`, `UpdateNavigators`, `UpdateRevisionAutomouse`, `UpdateRevisionModel`, `ForkRevision`, `DeleteLayout`) with `ORYX_TOKEN` as a Bearer token. Canonicalizes key fields `glowColor, lockGlowColor, customLabel, tappingTerm, tap, hold, doubleTap, tapHold, icon, emoji` | Python | Unlicense | file commit `065018ec` 2026-09-06 | Shows two-way sync is technically possible and what a canonical diff needs. Legal/ToS risk in 5.1 |
| johnstegeman/my_custom_oryx, unindented/zsa-voyager-keymaps, luanzeba/dotfiles `bin/oryx`, sammyhenningsson/kibard `tools/sync-oryx.py`, ito-rafael/keebab workflows | Scripts that pull Oryx layouts and commit them to git | Shell/Python | mixed / none | 2025-2026 | Repeated demand for **git versioning** (found via `gh search code "oryx.zsa.io/graphql"`, `work/04/gh-code-oryx-graphql.txt`) |
| [moosylog/voyago](https://github.com/moosylog/voyago) | Converts an Oryx source zip / `keymap.c` into a MoErgo Go60 ZMK JSON, with an "action required" report | JS | none | 2026-05 | Example of converting Oryx's C output (parsing `keymap.c` rather than the GraphQL JSON) |
| [ickc/unified-keyboard-config](https://github.com/ickc/unified-keyboard-config) | One source of truth producing QMK (Moonlander) and ZMK layouts; lossy by design | Python | BSD-3-Clause | 2025-11 → 2026-10 | Multi-board model |
| [AlexWorland/zsa-voyager-rgb](https://github.com/AlexWorland/zsa-voyager-rgb) | Fetches the layout via GraphQL, colours keys by category (alpha, mod, nav, …), injects RGB code into QMK, flashes | C | MIT | 2026-02 | Feature idea: **auto-colour by key category** |
| [caksoylar/keymap-drawer](https://github.com/caksoylar/keymap-drawer) | Draws QMK/ZMK keymaps as SVG with hold-taps and combos. QMK input via `keymap.json` (e.g. `qmk c2json` on an Oryx `keymap.c`) | Python | MIT | 2022 → 2026-08-12; **1338 stars**; prod | Visual language for hold/tap/combos; export target ("Export SVG/PNG") |
| ai-ecoverse/skills (`skills/oryx`), lucaspimentel/agent-skills (`zsa-layouts`) | AI-agent "skills" that fetch Oryx layouts | various | Apache-2.0 / ? | 2026 | Expect agent-driven use, so a CLI or AppleScript/Shortcuts surface is valuable |
| Keyderboard (Show HN [45815162](https://news.ycombinator.com/item?id=45815162), 2025-11-04) | Website for sharing and **comparing** ZSA layouts | web | ? | **domain unresolvable on 2026-10-11** | Demand for comparison and discovery |

### 3.4 Desktop companions, overlays and local managers (Voyager/ZSA-specific)

| Project | What it does | Lang | License | Activity | Maturity | Learn / reuse |
|---|---|---|---|---|---|---|
| [martinezooo/keyjitsu](https://github.com/martinezooo/keyjitsu) | **Most complete local alternative.** GUI + CLI + TUI. Edits the 4 slots with an Oryx-style picker; per-key glow; local QMK build (`qmk setup zsa/qmk_firmware -b firmware25`, about 2 GB) generating tap dances; flash via `zapp-core`; heatmap with CSV; "Peek" click-through transparent overlay; FX Studio RGB sequencer; Autolayer (frontmost bundle id); built-in-keyboard "guard" via `hidutil`; profiles. Reads Oryx anonymously, never writes back; encodes a local state id in the firmware serial | Rust (egui, hidapi) | MIT (LICENSE file); GitHub NOASSERTION | 2026-08-11 → 2026-10-09; 26 stars | beta, macOS-only tested | Closest competitor. Its README feature table vs Keymapp is a ready-made requirements list. (It marks Keymapp as lacking autolayer, which overlooks Smart Layers) |
| [bogo/probe](https://github.com/bogo/probe) | Floating transparent AppKit HUD: live key highlights, layers, heatmap, WPM stats; imports `keymap.c`, `.qmk`, or the Oryx source zip; sends the Oryx pairing command; Sparkle updates; XcodeGen; `ProbeCore` Swift package with tests | **Swift 6** | MIT | 2026-04-30 → 05-03; 3 stars | proto | Directly reusable Swift patterns: raw-HID pairing, HUD window, source-zip import, screenshot tests |
| [emileakbarzadeh/keyfinder](https://github.com/emileakbarzadeh/keyfinder) | macOS overlay on layers ≥ 1; loads the *installed* revision from Oryx on connect; offline cache; flash via Zapp; published CPU and memory numbers (idle ~0.005 % CPU, 12 MB) | Swift | GPL-3.0 (README: "AI-generated") | 2026-09-30 → 10-06 | proto | Performance targets; "typing layer on F18" peek. GPL, so ideas only |
| [nestoralonsovina/zsa-layout-overlay](https://github.com/nestoralonsovina/zsa-layout-overlay) | Click-through overlay, Oryx URL import, follows the focused screen | Swift (hidapi) | none | 2026-05 | proto | read only (no license) |
| [pmaxhogan/starview](https://github.com/pmaxhogan/starview) | Windows/macOS overlay shown only off the base layer; re-syncs from Oryx every 5 min | Rust | MIT | 2026-06 → 07 | proto | - |
| [ajmasia/gnome-shell-extension-zsa-helper](https://github.com/ajmasia/gnome-shell-extension-zsa-helper), [nt1998/voyager-overlay](https://github.com/nt1998/voyager-overlay) | GNOME and Hyprland overlays using real Voyager geometry | TS / Python | GPL-3.0 / none | 2026 | proto | - |
| [eshaan-mehta/zsa-typer-tui](https://github.com/eshaan-mehta/zsa-typer-tui) | Terminal typing trainer with Voyager live view | Rust | MIT | 2026-10-09 | proto | typ.ing-style training is reproducible locally |
| [jeprecated/zsa-keymapp-python](https://github.com/jeprecated/zsa-keymapp-python) (+ `-talon`) | Keymapp API from Python and Talon voice | Python | none | 2025-01 → 2026-03; 23 stars | proto | Voice and foot-pedal layer control is a real use case |
| [fram74/omarchy-voyager](https://github.com/fram74/omarchy-voyager) | Switch between saved Oryx layout *profiles* by flashing via Zapp; good non-affiliation disclaimer text | Python | NOASSERTION (README: MIT) | 2026-08 | proto | **Layout profiles**; disclaimer wording |
| [dmweis/ergodox-live-training-driver](https://github.com/dmweis/ergodox-live-training-driver) | Early (2020) live-training protocol driver | Rust | Apache-2.0 | stale 2021 | stale | - |

### 3.5 Alternative Voyager firmware (no-reflash remapping)

| Project | What it does | License | Activity | Notes |
|---|---|---|---|---|
| Vial keymap in [vial-kb/vial-qmk](https://github.com/vial-kb/vial-qmk) `keyboards/zsa/voyager/keymaps/vial` | VIA/Vial dynamic keymap; lighting "none"; no Oryx protocol, no Navigator | GPL-2.0 | added 2025-04-11 | Details in 03 §7.2 |
| [jpds/rmk-zsa-voyager](https://github.com/jpds/rmk-zsa-voyager) | [RMK](https://github.com/rmk-rs/rmk) (Rust/Embassy) firmware: **live keymap editing via Vial**, 6 animated RGB effects, 16 palettes, 4-bit layer LEDs, chordal hold. Flashed with `dfu-util -d 3297:0791 -a 0 -s 0x08002000:leave` | Apache-2.0 | 2026-04-30 → 09-19; 7 stars | States the MCU is GD32F303CB (STM32F303CB-compatible). No Navigator mentioned (INFERRED: unsupported) |

### 3.6 Configurators for other ecosystems (UX and data-format references)

| Project | What it does | Lang | License | Activity | Learn |
|---|---|---|---|---|---|
| [the-via/app](https://github.com/the-via/app) (usevia.app) | Live keymap, macro and RGB editing over raw HID; boards need a VIA JSON definition plus a `keymaps/via` | TS | GPL-3.0 | 2026-09-22; 1631 stars | The "instant remap" UX benchmark; definition JSON uses KLE geometry |
| [vial-kb/vial-gui](https://github.com/vial-kb/vial-gui) | Real-time QMK config: tap dance, combos, key overrides, alt-repeat, QMK settings over HID, unlock combo | Python/Qt | GPL-2.0 | 2026-05-25; 1430 stars | Dynamic entries (`vial.h:37-62`, 03 §7.4); `.vil` save/load |
| [zmkfirmware/zmk-studio](https://github.com/zmkfirmware/zmk-studio) | Runtime ZMK keymap editing (USB; BLE on Linux), `&studio_unlock`, layer rename, physical-layout switch. Combos, behaviour properties and import/export are still "planned" ([docs](https://zmk.dev/docs/features/studio)) | TS + Rust (Tauri) | Apache-2.0 | 2026-07-02; 322 stars | Pending-changes save/discard model; unlock gesture |
| [nickcoutsos/keymap-editor](https://github.com/nickcoutsos/keymap-editor) | Web ZMK keymap editor with GitHub integration; demo is a Corne. "Source code updates are no longer shared here" | JS | MIT | 2084 stars | Git-backed editing UX |
| [buckleypaul/zmkonfig](https://github.com/buckleypaul/zmkonfig) | **Native macOS** ZMK editor: draws the board from `info.json` or keymap-editor-contrib; edits bindings; "**never regenerates your `.keymap`**" (byte-range edits, round-trip test); shows the diff; commits and pushes; watches GitHub Actions; flashes; explains bindings in English | **Swift** (about 1 MB of Swift) | MIT | 2026-08-09 → 09-29 | Best architectural precedent for Sextant's "local files + git + diff + build + flash" loop |
| [FireBall1725/LayerLens](https://github.com/FireBall1725/LayerLens) | macOS overlay for QMK/Vial; VIA protocol keymap viewer; layout auto-resolved from the VIA keyboards repo by VID:PID; Swift rewrite of [srwi/keypeek](https://github.com/srwi/keypeek) | Swift | GPL-3.0 | 2026-05 → 08 | ideas only (GPL) |
| [hello-malek/micromap](https://github.com/hello-malek/micromap) | Native macOS configurator for one VIA device; persists drafts locally; writes only after explicit confirmation | Swift | NOASSERTION | 2026-07 | Draft → confirm → write pattern |
| [qmk/qmk_toolbox](https://github.com/qmk/qmk_toolbox) | Flasher for many bootloaders (dfu-util for ARM DFU); HID console on usage page `0xFF31` | C# + **Swift** (macOS app) | MIT | 2026-08-20; 3104 stars | Reusable Swift flashing UI patterns |
| [qmk/qmk_configurator](https://github.com/qmk/qmk_configurator) | Web configurator for upstream QMK boards (includes `zsa/voyager`); exports `keymap.json` | JS | no LICENSE file (INFERRED: all rights reserved) | 849 stars | `keymap.json` interchange |
| [ijprest/keyboard-layout-editor](https://github.com/ijprest/keyboard-layout-editor) | KLE geometry JSON | JS | "Other" (`LICENSE.md`) | 2024-09 | Geometry format used by VIA definitions |
| [pqrs-org/Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements), [jtroo/kanata](https://github.com/jtroo/kanata) | OS-level remappers | C++ / Rust | Unlicense / LGPL-3.0 | active | Context: macOS users combine firmware layers with host remapping; Sextant can avoid duplicating that |

### 3.7 Lessons for Sextant

1. **Everyone reads Oryx the same way.** GraphQL `layout(hashId, revisionId, geometry)` plus REST `/firmware/{rev}` and `/source/{rev}`, unauthenticated (zapp, poulainpi, keyjitsu, keyfinder, oryx-bench). Nobody writes back except jyn514's token-based script. Copy the read path; treat write-back as optional and permission-gated.
2. **Local builds are the norm for power features.** keyjitsu, oryx-bench, voyager-helper and poulainpi all compile ZSA's fork with `qmk` and arm-gcc (about 2 GB). Sextant should manage the toolchain outside its app bundle (5.4, 5.6).
3. **Customizations must survive re-generation.** Successful tools either own the whole model (keyjitsu), keep overlays separate (oryx-bench, voyager-helper), or edit byte ranges (zmkonfig). Merge conflicts are the top complaint about the GitHub-Actions approach.
4. **The overlay is a product in itself.** At least seven overlays or HUDs appeared in 2026 (keyfinder, zsa-layout-overlay, starview, the GNOME helper, voyager-overlay, probe, keyjitsu Peek), all wanting click-through transparency, show-on-non-base-layer, per-monitor placement and hold-to-peek. Keymapp cannot be transparent or live in the menubar ([zsa.io/smart](https://www.zsa.io/smart)).
5. **The exclusive HID channel creates friction.** keyjitsu and typ.ing both tell users to quit Keymapp (03 §5.4).
6. **Git and diff are wanted.** Several users version Oryx JSON in git, and jyn514 built a canonical diff.
7. **Agent-friendliness matters to ZSA and to users.** Zapp's blog pitches Claude Code; oryx-bench is "designed to be driven by … Claude Code". Ship a CLI or URL-scheme surface.

### 3.8 Reuse licence compatibility (for a Sextant of unknown licence)

| Licence | Projects | Reuse in a closed or permissive Sextant |
|---|---|---|
| MIT / BSD / Unlicense | kontroll (`keymapp.proto`), wally, probe, keyjitsu, oryx-bench, zmkonfig, qmk_toolbox, USBDeviceSwift, keymap-drawer, starview, poulainpi, jyn514 script, Karabiner | Yes, keeping copyright notices (MIT/BSD) |
| Apache-2.0 | zmk-studio, RMK, rmk-zsa-voyager | Yes, with NOTICE and patent terms |
| MIT + Commons Clause | **zapp** (`zapp-core`, `zapp-oryx`) | Free Sextant: OK. Paid Sextant, or one whose value derives "substantially" from Zapp: **no**. Reimplement DFU instead (INFERRED legal reading; 5.5) |
| GPL-2.0 / GPL-3.0 | QMK, zsa/qmk_modules, vial-gui, VIA app, keyfinder, LayerLens, keypeek, gnome extension | Only if Sextant itself is GPL-compatible. Otherwise study for ideas and clean-room |
| LGPL-3.0 | kanata | Avoid static linking |
| No licence | zsa-layout-overlay, voyago, oryx-macro-hax, zsa-keymapp-python, qmk_configurator | Read only |

---
## 4. Open-source knowledge about the Voyager, and what the Corne teaches (user request)

> User request (relayed by the harness): "We should also look for any information open source about the keyboard. Corne keyboards are open source and are similar."

This section is a concise digest aimed at feature and UX scope. **`study/05-open-hardware-and-configurators.md`** (another researcher) covers the Voyager's hardware, its matrix and LED mapping, Corne and other open splits, and open configurators in much more depth. Where the two differ, prefer 05 on hardware facts.

### 4.1 What is open about the Voyager

| Item | Fact | Source |
|---|---|---|
| Firmware (upstream) | `qmk/qmk_firmware` `keyboards/zsa/voyager/` (`config.h`, `halconf.h`, `keyboard.json`, `keymaps/`, `ld/`, `matrix.c`, `mcuconf.h`, `readme.md`, `rules.mk`, `voyager.c`, `voyager.h`), GPL-2.0. Maintainers: drashna and ZSA. Last change `47575d4a` (2025-01-20) | GitHub API listing; `keyboards/zsa/voyager/readme.md` |
| Firmware (what Oryx builds) | `zsa/qmk_firmware` branch `firmware25`, plus `zsa/qmk_modules` (GPL-2.0-or-later) | 03 §1; 3.1 above |
| Generated layout source | Every Oryx revision's C source is downloadable (`/source/{rev}`): `keymap.c`, `keymap.json` (module list), `config.h`, `rules.mk`, README, build log, `.bin` | 2.12 |
| USB identity | VID `0x3297`, PID `0x1977` (app); bootloader `3297:0791`; app image at `0x08002000` | `keyboard.json` `usb`; `jpds/rmk-zsa-voyager` README; 03 §2 |
| Matrix | `MATRIX_ROWS 12`, `MATRIX_COLS 7`, diode `ROW2COL`. The right half is read through an MCP23018 I/O expander (`mcp23018_leds[2]` in `voyager.c:9`) | upstream `config.h`; `voyager.c` |
| Physical layout | `LAYOUT` with 52 keys. Array positions 0-47 are 4 rows × 12 (row-major across both halves) and 48-51 are the thumb keys at y 4.5/4.75. Column stagger is encoded as y offsets of 0, 0.25 and 0.5. Each entry has a `kNN` label and a `matrix` [row, col] | `downloads/qmk-voyager-kbjson/keyboard.json` |
| Oryx key order | Oryx indexes keys left half first (0-23 rows, 24-25 thumbs), then right half (26-49 rows, 50-51 thumbs). This equals the `kNN` label number and the RGB LED index, **not** the `LAYOUT` array position, so the renderer must map label → index | 03 §3.6 (with `jC[row][col]` table); `j7j7/voyager-keyboard-helper` README ("Key 25 is the left outer thumb", 50/51 right thumbs) |
| RGB | `is31fl3731` driver, 2 chips (`IS31FL3731_I2C_ADDRESS_GND` and `_VCC`), **52 LEDs** (one per key), `max_brightness 175`, sleep on suspend | upstream `config.h`; `keyboard.json` `rgb_matrix` |
| Status LEDs | 4 indicator LEDs (`STATUS_LED_1..4`), by default the binary layer number (`voyager.c:111-116`). `VOYAGER_USER_LEDS` repurposes them, e.g. for caps lock (`voyager.c:218`) | upstream `readme.md`, `voyager.c` |
| Bootloader | ZSA "Ignition" bootloader. `bootloader_jump()` charges a capacitor on A8/A9 because "The ignition bootloader is checking for a high signal on A8 for 100ms" | `voyager.c:297-305` |
| Bootmagic | Enabled with key matrix `[0,1]` (top-left key); compiled into the user's build | `keyboard.json` `bootmagic`; user `build.log` (`bootmagic/bootmagic.c`) |
| MCU | The upstream readme says "Hardware Supported: Voyager (STM32F303xC)", but report 05 §2.1 shows that line is stale: QMK PR #23912 (2024-06) moved the linker to the **xB** size, 128 KB flash / 32 KB RAM. The RMK port says the chip is a "GD32F303CB … (STM32F303CB-compatible)". keyjitsu mentions "dual STM32+GD32 images", and Zapp has an `Alternate` (`?alt=true`) firmware variant, so MCU variants exist (INFERRED) | upstream readme; `05-open-hardware-and-configurators.md` §2.1; `jpds/rmk-zsa-voyager` README; keyjitsu README; `zsa/zapp@a1be758:zapp-oryx/src/lib.rs:173-190` |
| Split "gaming mode" hook | `is_transport_connected()` lets firmware switch layers when the right half is unplugged (custom code only, not in Oryx) | upstream `readme.md` |
| Live protocol | Oryx raw-HID protocol, fully specified in `zsa/qmk_modules/oryx` | 03 §3 |
| Alternative firmware | Vial keymap (QMK) and RMK (Rust) both support **live remap without reflashing** | 3.5 |

### 4.2 What is not open

| Item | Status | Source |
|---|---|---|
| PCB, schematics, case CAD | **Not published** (INFERRED). No Voyager hardware repo in the `zsa` GitHub org (16 public repos listed); `zsa/docs` contains only ErgoDox EZ schematics. ZSA sells spare parts (Voyager left PCB $120, right $100, legs, backplate) and publishes teardown guides | `gh api orgs/zsa/repos`; `zsa/docs` listing; B `2105-right-to-repair` |
| Oryx web app and backend, Keymapp, Navigator companion app | Closed. "Like Oryx itself, we will not be open-sourcing Keymapp" | B `keymapp`; [zsa.io/training](https://www.zsa.io/training) FAQ ("The server-side component is a part of Oryx, which is not open-source") |
| Open | Kontroll and Zapp | [zsa.io/privacy](https://www.zsa.io/privacy) |
| Printables | ZSA does publish 3D-printable accessories (wrist rest, Navigator shells, trackball crown), and community DIY designs are on the blog | Ergo 2026-06/09; B `diy-*` |

### 4.3 Voyager-inspired open hardware (not compatible PCBs; useful for geometry and community)

| Project | What | License | Stars |
|---|---|---|---|
| [carrefinho/forager](https://github.com/carrefinho/forager) | 34-key wireless split, "Condensed ZSA Voyager layout without outer pinkie column and number row", ZMK, XIAO nRF52840, Choc v1 | CERN-OHL-P-2.0 | 425 |
| [tuxedocurly/mantaray_keyboard](https://github.com/tuxedocurly/mantaray_keyboard) | "ZSA Voyager inspired" low-profile split, pro-micro, OLED | CERN-OHL-S-2.0 | 70 |
| [shoedler/shoedler54](https://github.com/shoedler/shoedler54) | 54-key wireless split inspired by the Voyager and silakka54 | GPL-3.0 | 26 |
| [WibblyGhost/southerly-split-keeb](https://github.com/WibblyGhost/southerly-split-keeb) | Voyager-based homebuilt split (ergogen, KiCad) | Apache-2.0 | 17 |

### 4.4 The Corne (crkbd) and how it compares

| | Corne | ZSA Voyager |
|---|---|---|
| Hardware licence | Open: `foostan/crkbd` ships **LICENSE_MIT** and **LICENSE_CC** (CC-BY-4.0, GitHub's detection) | Closed hardware (4.2) |
| Keys | `LAYOUT_split_3x6_3` = **42** (3 rows × 6 + 3 thumbs per side); `LAYOUT_split_3x5_3` = 36 | **52** = 4 rows × 6 + **2** thumbs per side |
| Firmware ecosystems | QMK `keyboards/crkbd` (rev1, rev4_0, rev4_1); Vial `keyboards/crkbd`; VIA definition `the-via/keyboards/v3/crkbd/crkbd.json`; ZMK shield `corne` with features `keys, display, underglow, studio` (**ZMK Studio supported**) | QMK (`zsa/voyager`); Oryx (ZSA fork); community Vial keymap; RMK |
| Configurators | VIA, Vial, ZMK Studio, nickcoutsos Keymap Editor (its demo is a Corne), QMK Configurator | Oryx (cloud, compile + flash); QMK Configurator (upstream build, without ZSA modules) |
| Live remap | Yes (VIA/Vial/ZMK Studio) | Not with Oryx firmware (03 §7) |
| Source | `foostan/crkbd` README; `qmk/qmk_firmware/keyboards/crkbd/info.json` @ `c9cd92ec`; `vial-kb/vial-qmk` `keyboards/crkbd`; `zmkfirmware/zmk` `app/boards/shields/corne/corne.zmk.yml` | 4.1 |

**What this means for Sextant** (INFERRED design guidance):
1. **Geometry from data, not code.** Corne and Voyager are both column-staggered 6-column splits. Render any board from QMK `keyboard.json`/`info.json` `layouts` (x, y, w, h, r), which is the same input keymap-drawer, zmkonfig and QMK Configurator use. Overlay Oryx's key-index mapping only for ZSA boards. A Corne layout maps onto a Voyager's rows 2-4 plus thumbs (one thumb short per side), which ZSA's own "shifted layout" post exploits in reverse (B `voyager-shifted-layout`, B `compact-layouts`).
2. **The Corne ecosystem is the UX benchmark for "instant" editing.** VIA/Vial/ZMK Studio change keys over HID with no reflash; Oryx users cannot (cheeseturbulence review: "Every config change needs recompile and reflash"). Sextant can only match this by offering an optional Vial/RMK firmware path (03 §7.7) or by making the compile-flash loop very fast and local.
3. **Data interchange.** Supporting import and export of QMK `keymap.json`, VIA/Vial definition JSON (KLE geometry) and keymap-drawer YAML would make Sextant useful beyond ZSA boards. A Corne owner could use Sextant through VIA/Vial later; that is out of scope for v1 (INFERRED).

---
## 5. Legal: ToS, API use, trademarks, licences, distribution, and the name

> Not legal advice. Items marked INFERRED are engineering judgements to raise with counsel before a commercial release.

### 5.1 ZSA terms and automated access to Oryx

**Facts:**
1. **ZSA publishes no Terms of Service or API terms.**
   - Oryx's footer links "Privacy policy" to `https://zsa.io/privacy-policy-and-terms-of-service/` (`index-xhNfd6BI.js@943681`). That URL returns `301` to `https://www.zsa.io/privacy-policy-and-terms-of-service/`, then `301` to `https://www.zsa.io/privacy` (curl, 2026-10-11).
   - The privacy page has 24 sections. None of them is about terms, licensing, acceptable use or automated access (`work/04/privacy-2026-10-11.txt`; zero matches for "terms").
   - `https://www.zsa.io/{terms,tos,legal,terms-of-service}` all return 404.
   - The zsa.io footer links only Trust, Help, Returns, FAQ, Privacy and Warranty.
2. **The privacy policy** ([zsa.io/privacy](https://www.zsa.io/privacy), effective 2026-04-30; ZSA Technology Labs, Toronto, subject to PIPEDA and Quebec Law 25) states:
   - Oryx layouts and macros are **public by default**. "An untagged public layout can be reached only by its unique URL, which contains a hard-to-guess identifier."
   - Private layouts need an account. Anonymous layouts persist indefinitely.
   - "When Keymapp or Zapp needs to fetch a keyboard layout, it sends the layout's hash identifier (which is stored in your keyboard's firmware) to Oryx. The request is logged on our servers and includes your IP address."
   - ZSA's local apps send update checks, anonymous telemetry and crash reports (self-hosted Sentry).
3. **robots.txt:**
   - `configure.zsa.io/robots.txt` is `user-agent: * / Allow: /$ / Disallow: /`, which disallows all crawling except the home page.
   - `oryx.zsa.io/robots.txt` returns 404.
   - `www.zsa.io` allows everything (`downloads/zsa-legal-04/robots-*.txt`).
4. **ZSA itself ships open-source clients of the same unauthenticated endpoints.**
   - Zapp calls `POST https://oryx.zsa.io/graphql` (`layout(hashId, revisionId, geometry){ revision { title } }`), `GET /firmware/{rev}` and `GET /firmware/latest/{layoutId}` (`zsa/zapp@a1be758:zapp-oryx/src/lib.rs:21-31,71-108,144-200`).
   - ZSA blogged and linked poulainpi's workflow, which uses GraphQL and `GET /source/{rev}` (B `oryx-custom-qmk-features`; source zip README).
   - Kontroll was open-sourced as "a reference implementation for the Keymapp API … you can re-implement some or all API calls in your own software" (B `introducing-kontroll`).
5. **Writes are a different matter.** Oryx's own edits go through GraphQL mutations that need a session token (`acknowledgeMacroRisks`, … in the bundle; jyn514's script needs `ORYX_TOKEN`). These mutations are undocumented and unannounced. oryx-bench concludes "Oryx has no public write API".

**Recommendations for Sextant** (INFERRED):

| Do | Don't |
|---|---|
| Read only layouts the user names: a pasted URL or hashId, or the `layoutId/revisionId` read from the board's USB serial (`SERIAL_NUMBER`). This mirrors what Zapp and Keymapp do | Crawl `configure.zsa.io` (robots) or enumerate or search public layouts in bulk. Don't mirror other people's layouts |
| Send a descriptive `User-Agent` (e.g. `Sextant/1.0 (+https://…; contact)`); cache by revision hash (compiled revisions appear immutable: new edits create a new revision hashId, per `layout.new`/fork behaviour; verify); back off on errors | Poll aggressively. One metadata check per user action, or at most a slow timer, like starview's 5 min or oryx-bench's 60 s |
| Treat write-back, private layouts and login as **opt-in features requiring ZSA's written OK** | Emulate Keymapp's auth-phrase login (`/account/auth_phrase` → `oryx.zsa.io/authenticate/auth_phrase`) or replay Oryx mutations without permission |
| Email `contact@zsa.io` describing Sextant and asking for (a) permission to read the GraphQL/firmware/source endpoints, (b) any rate limits, (c) whether write-back is acceptable. ZSA's support is email-first ([zsa.io/help](https://www.zsa.io/help)) | Rely on silence as consent for a commercial product. Mac App Store guideline 5.2.2 requires that "Authorization must be provided upon request" for third-party services |
| Disclose in Sextant's privacy policy that requests to `oryx.zsa.io` reveal the user's IP address and layout ID to ZSA | Store Oryx tokens unless write-back is approved; if so, use the Keychain |

### 5.2 Trademarks

**ZSA marks.** Status is from third-party aggregators (Justia, uspto.report, Trademarkia) via web search; the direct pages returned HTTP 403. **Verify in USPTO TSDR / Trademark Search.**

| Mark | Status (per aggregator) | Goods / services |
|---|---|---|
| MOONLANDER | **Registered**, Reg. 6164380 (serial 87342516, filed 2017-02, reg. 2020-09-29) | keyboards, keyboard controllers |
| ERGODOX EZ | **Registered**, Reg. 5566759 (serial 87484279; class 35 online retail); new application serial 99025540 (2025, keyboards) | |
| VOYAGER | **Application**, serial 97087577 (filed 2021-10-22), "live/pending" | computer keyboards |
| ZSA | Application, serial 90130326 (filed 2020-08) | |
| NAVIGATOR | Application, serial 99023241 (filed 2025-01) | computer mice, trackballs |
| TYP.ING | Application, serial 99051130 | |
| ORYX, KEYMAPP | **No record found**. ZSA still has common-law rights from use (INFERRED). Many unrelated "Oryx" marks exist | |

**Naming guidance** (INFERRED, aligned with the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)):
- Guideline 4.1(c): "You cannot use another developer's icon, brand, or product name in your app's icon or name, without approval from the developer."
- Guideline 2.3.7: do not "pack any of your metadata with trademarked terms".
- Guideline 5.2.1: no "protected third-party material such as trademarks".
- **Do:** call the product "Sextant". Use a descriptive line such as "A native Mac configurator for ZSA Voyager keyboards". Mention ZSA products only to state compatibility. Add a disclaimer, for example: *"Sextant is an independent project, not affiliated with or endorsed by ZSA Technology Labs. ZSA, Voyager, Moonlander, ErgoDox EZ, Navigator, Oryx, Keymapp and Zapp are trademarks of their respective owners."* keyjitsu and omarchy-voyager use similar wording.
- **Don't:**
  - use "Oryx", "Keymapp", "Wally", "Zapp" or "Kontroll" in the app name, bundle ID, icon or feature names
  - reuse ZSA's coined feature names as Sextant's own ("Smart Layers" → say "app-aware layers"; "Live Training" / "typ.ing" → "practice"; "Layout Buffet")
  - use ZSA logos or product renders

### 5.3 Copyright in Oryx assets (INFERRED)

- **Bundle code.** Oryx's JavaScript and CSS are proprietary. Use them for interoperability research only, never copy them.
- **Icons.** The icon font (`oryx-BM0RGHzK.ttf/.woff`) and the "hundreds of icons" ZSA "recreated … by hand" (B `2208-emoji-keys`) are ZSA's copyright. Sextant should map the stored `icon` IDs to its own glyphs (for example SF Symbols) and fall back to text.
- **Keycode metadata.** Keycode labels and descriptions in `configure.zsa.io/metadata.json` are ZSA-authored text. Generate Sextant's keycode table from QMK sources (`zsa/qmk_firmware` `quantum/keycodes.h`, `data/constants/keycodes/*.hjson`) and write Sextant's own descriptions. Keycode names and numeric values are interface facts, but the source files are GPL-2.0. Generate the table at build time, keep attribution, and have counsel confirm that shipping a derived name→value table does not make Sextant a GPL derivative.
- **Templates.** Layer templates and default layouts are curated content. Fetch them on demand for the user rather than bundling them.

### 5.4 QMK (GPL-2.0) obligations by scenario (INFERRED reading of GPLv2 §§2-3 and QMK's policy)

QMK's position, quoted from `qmk/qmk_firmware@2cbcd76e:docs/license_violations.md:63-70`: "QMK Firmware's license requires full disclosure of source code for any firmware which is based on QMK … Any other non-QMK firmware which includes portions of QMK Firmware, such as adaptation of `via.c` … **even if used as a reference when translated to another programming language**."

| Scenario | Obligation |
|---|---|
| A. Sextant generates `keymap.c` / `config.h` / `rules.mk` / `keymap.json` and drives a QMK toolchain **installed by the user**; firmware stays on the user's Mac | Sextant distributes no QMK code, so it has no GPL obligation and may be closed-source. The user holds the full source of their firmware |
| B. Sextant downloads ZSA's QMK fork on demand (`git clone` from GitHub) | Same as A; Sextant is not distributing |
| C. Sextant **bundles** QMK source or prebuilt firmware (e.g. a recovery `.bin`, a Vial base image), or runs a **cloud build service** returning `.bin` | Distribution of GPL works: ship or offer complete corresponding source, including generated keymaps and modified modules (GPLv2 §3). Bundled source is mere aggregation (§2, last paragraph) if not linked into Sextant |
| D. Sextant **ports QMK logic** into Swift (e.g. a tap-hold simulator translated from `action_tapping.c`, or VIA/Oryx protocol code copied from `via.c` / `oryx.c`) | By QMK's stated position this makes Sextant a derivative, so it must be GPL-compatible. Prefer clean-room implementations from documentation (the Oryx protocol is documented in 03). Note: `zsa/qmk_modules` is GPL-2.0-or-later |
| E. Sextant bundles `arm-none-eabi-gcc` or `dfu-util` binaries | GCC (GPL-3.0 with runtime exception) and dfu-util (GPL-2.0) binaries carry source-offer duties and clash with Mac App Store terms. Prefer guiding the user to install them (Homebrew/Arm) or downloading the official archives at runtime |

### 5.5 Licences of ZSA tools Sextant might reuse

| Tool | Licence (file) | Reuse note |
|---|---|---|
| Wally, wally-cli | MIT (`license.md`, © 2019-2020 ZSA) | Free to reuse with notice |
| Kontroll (+ `proto/keymapp.proto`) | MIT (© 2024 ZSA) | Reuse the proto to talk to Keymapp |
| Zapp | **MIT + Commons Clause** (`LICENSE.md`, © 2026 ZSA). "the grant of rights under the License will not include … the right to Sell the Software … 'Sell' means … to provide to third parties, for a fee or other consideration … a product or service whose value derives, entirely or substantially, from the functionality of the Software." | OK in a free Sextant. **Avoid in a paid Sextant**; reimplement STM32 DFU (ST AN3156 / DfuSe) using wally (MIT) and dfu-util documentation as references |
| zsa/qmk_firmware, zsa/qmk_modules | GPL-2.0 / GPL-2.0-or-later | See 5.4 |
| oryx-with-custom-qmk | MIT (© 2024 Pierre Poulain; added after issue #12) | Reuse the workflow ideas |

### 5.6 Distribution channel

- **Mac App Store:**
  - Guideline 2.5.2: apps "may not download, install, or execute code which introduces or changes features or functionality of the app".
  - Guideline 2.4.5(ii): Mac App Store apps "cannot install code or resources in shared locations".
  - The sandbox needs `com.apple.security.device.usb` for HID (03 §8.3).
  - Guideline 5.2.2 requires permission for third-party services.
  - A MAS build therefore could not manage a QMK toolchain, and would need ZSA's written authorization to use Oryx's endpoints. There are also GPL/App Store tensions if any GPL code is bundled (INFERRED).
- **Recommendation:** distribute **outside the Mac App Store** with Developer ID signing, notarization and Sparkle updates (bogo/probe uses Sparkle 2). Optionally, later, a MAS "viewer/overlay" edition with no compile, once ZSA has authorized it.

### 5.7 The name "Sextant"

| Where | Finding | Source |
|---|---|---|
| Keyboard / QMK space | **No conflict found** (`gh search repos "sextant keyboard"`, `"sextant qmk"`: 0 results) | `work/04/gh-sextant.txt` |
| GitHub, developer tools | `schneems/sextant` (Ruby, Rails routes, 573 stars, 2017); `mattpocock/sextant` (TS, app-flow charting, 2020); **`reactiveui/Sextant`** (.NET navigation library, MIT, active 2026-10); **`KittyMac/Sextant`** (Swift JSONPath, MIT, active 2026-07; an SPM module named `Sextant`, so avoid that module name for Sextant's own packages, or alias it); `SneWs/Sextant` ("A git UI", C#); `parenworks/sextant` (Common Lisp LSP); `jonlipsky/sextant` (.NET code indexer) | `gh search repos sextant` (2026-10-11) |
| App Store | "Sextant — Celestial Nav" (Mac-compatible), "Sextant Navigation", "EZ Sextant", "Sextant Calculator", "Sextant Coffee" | web search of apps.apple.com, e.g. [Sextant — Celestial Nav](https://apps.apple.com/us/app/sextant-celestial-nav/id6758679821), [EZ Sextant](https://apps.apple.com/us/app/ez-sextant/id6477748851) |
| Trademarks | SEXTANT, Class 9 risk-underwriting software, registered 1996, **cancelled 2007** (Healthcare Underwriters Mutual); SEXTANT (Softa Group, serial 76557259, management-advice software; status not shown); SEXTANT AVIONIQUE (Thales, 1989); SEXTANT TECHNOLOGY CONSULTING (serial 76321163). Unrelated "Sextant" software products: Black Knight Technology, Sextant USA | web search snippets (uspto.report, Justia) |
| Other | "Sextant" is also a Unicode term (BLOCK SEXTANT characters, Symbols for Legacy Computing, [U+1FB00 chart](https://www.unicode.org/charts/PDF/U1FB00.pdf)) used by terminal emulators | Unicode |

**Verdict** (INFERRED): fine as the project and product name for a free or open tool. It is a common nautical word with scattered unrelated software uses and no live conflict in keyboards. Before a commercial launch:
- do a professional clearance (USPTO/CIPO/EUIPO, Class 9 and 42)
- choose a distinctive App Store/marketing name (e.g. "Sextant: Keymap Studio"), since store names must be unique
- avoid naming internal Swift packages `Sextant`

---
## 6. Pain points and wishes, and what a native app could do better

Evidence is limited to reachable sources. Reddit was blocked (section 1), so this list may under-represent r/zsaVoyager. "ZSA" in the evidence column means ZSA's own statement.

| # | Pain point | Evidence | Native-app opportunity |
|---|---|---|---|
| 1 | **Cloud-only editing and compiling**; nothing works offline | "It lives in the cloud, and makes firmware for your board" ([zsa.io/oryx](https://www.zsa.io/oryx)); HN [43366574](https://news.ycombinator.com/item?id=43366574) (2025-03-14): "I'd prefer having a native desktop app to configure my keyboard"; keyjitsu: "No daemon, no login, no cloud"; oryx-bench's "Local-only" persona | Offline-first local document model (plain JSON or YAML in a folder or git repo). Local QMK build. Oryx is an optional import/sync source |
| 2 | **Chromium-only** flashing and live view (WebUSB/WebHID); Firefox/Safari/ChromeOS excluded | ZSA: B `2206-live-flashing`, B `1912-live-training`; HN 43366574: "ZSA Oryx is the one place I'm annoyed by Firefox not supporting it" | Native IOKit HID + DFU; no browser at all |
| 3 | **Every change needs recompile + reflash**; slow loop | cheeseturbulence.com (2026-01-31): "Every config change needs recompile and reflash (time-consuming)"; HN [43361260](https://news.ycombinator.com/item?id=43361260): "Downloading the firmware and then flashing with another program gets old pretty quickly" | One-key "Build & Flash" with automatic bootloader detection; incremental local builds; a staged-changes queue (keyjitsu's "pending"); optional Vial/RMK firmware for instant remaps (03 §7.7) |
| 4 | **Missing QMK features**, and the workaround (custom QMK via GitHub) causes merge conflicts and CI breakage | ZSA: B `oryx-custom-qmk-features` ("we won't be able to help you troubleshoot"); filiphalas.com (2024-06-02): "current limitations and missing QMK tweaks eventually drew me into the QMK rabbit hole" and the tool "didn't … work well enough … due to merge conflicts"; poulainpi (223 stars) issues #16, #40, #42, #44, #49; voyager-keyboard-helper; oryx-bench | First-class UI for Key Overrides, Leader, Repeat Key, Autocorrect, tri-layer, per-key permissive/hold-on-other/quick-tap, Achordion-style exceptions. Plus "custom C overlay" files kept separate from generated code, so regeneration never conflicts (zmkonfig/oryx-bench patterns) |
| 5 | **No undo, no history, no diff, no git** | ZSA: B `history`: per-key history removed Oct 2023 because "tracking every single action … had very real performance implications". No compare UI in the bundle (2.10). Users script git sync (3.3); jyn514 built a canonical diff; Keyderboard pitched "comparing ZSA layouts" | Native undo/redo (cheap locally). **Visual revision diff** (per-key highlights across layers, settings diff). Git-backed history with readable commit messages. Branches for experiments |
| 6 | **Macro limits and public macros** | ZSA: B `2003-oryx-macros` (5 chars, password concerns); B `macro-expansion`; B `longer-oryx-macros` (24 steps; sign-in + acknowledgement; "Oryx is not a password manager"); oryx-macro-hax: "annoying (though reasonable) limitation"; oryx-complex-macros | Local macros (never uploaded), limited only by flash size. A macro recorder that captures typed sequences with timing. OS-specific Unicode helper. A clear "firmware is readable" warning instead of server-side policing |
| 7 | **Tap-hold / home-row-mod tuning is opaque** | benfrain.com (2023-11-12): "I couldn't even get through a single typing test without a bunch of unwanted modifier keys firing" … "no idea what combination of settings I had managed to apply"; ZSA: Chordal Hold was "one of the most requested features" (B `chordal-hold`); B `layout-buffet-dual-function-keys`: "everything is connected"; Oryx now shows a home-row-mod hint (`useTourPreload-BzJOYeur.js@94016`) | A "timing lab": show which settings differ from defaults, explain interactions, offer presets (HRM-safe, gaming), and simulate a typed key sequence against the settings (clean-room logic, see 5.4 D). Integrate dynamic-tapping-term readouts from the live protocol |
| 8 | **Keymapp friction**: exclusive HID, no menubar, no transparency, no heatmap export, layer names not exposed | ZSA: [zsa.io/smart](https://www.zsa.io/smart) limitations; typ.ing: "Make sure the Keymapp app isn't open … it will conflict"; `zsa/kontroll` issues #14 (export heatmap), #22 (layer friendly name), #26 (`set-rgb` overrides layer colours), #19 (crash on many RGB calls), #15 (App Store sandbox path); at least seven 2026 overlays or HUDs (3.4) | Menubar app with a **click-through, transparent overlay** (per-monitor, peek-on-hold, auto-hide on base layer); heatmap CSV/JSON export; layer names everywhere; open HID non-exclusively (03 §5.4); per-key RGB effects that compose with layer colours; app-aware layers via `NSWorkspace` |
| 9 | **Mouse-only editing; no in-layout search** | Bundle has essentially no shortcuts (2.10, INFERRED). ZSA's own typ.ing is "entirely keyboard-based" (`downloads/typing-04/oryx.html`) | Command palette (⌘K), arrow-key navigation over the board, type-to-assign keycodes, "find every key that sends X / uses layer N", full menu-bar shortcuts |
| 10 | **Limited bulk editing; no layer duplication** | ZSA deliberately has no duplicate-layer ("Copying is prone to create layouts that are just too big", B `2009-swap-keys`); copy/paste key only since 2024 (B `copy-keys`); Phoscur's oryx-layer-inserter copies layers between layouts | Duplicate, merge and import layers (including from another Oryx URL) with a live **firmware-size budget meter**; multi-select assign; mirror left/right; local template library |
| 11 | **Locale confusion**: keys don't output the legend; some characters "missing" in macros | ZSA: B `keys-not-matching-output`, B `missing-macro-characters`, B `international-setup`; 36 locale packs (CAT) | Read the active macOS input source (Text Input Sources) and render legends as the OS will actually type them; warn on mismatch; auto-pick the base key + Shift/Option for macros |
| 12 | **Firmware too big / opaque build errors** | "Your firmware is over the top!" (`_revisionId-CtR9sUEn.js@163999`); B `2301-memory`, B `2301-pick-animations`; the Oryx-connection setting suggests disabling animations to save bytes (CAT `liveTraining`) | Show the size before building; attribute bytes to features; offer one-click trims (unused animations); show compiler errors mapped to keys |
| 13 | **Public-by-default layouts** | [zsa.io/privacy](https://www.zsa.io/privacy) "Layouts you create in Oryx are public by default" | Private by default; explicit "Publish to Oryx" or share-as-file |
| 14 | **Navigator setup is split** between Oryx settings, the Navigator panel and the macOS companion app | ZSA: B `navigator-trackpad-feature-update`, B `press-to-exit-auto-mouse-and-updates` ("we changed how the Navigator menu looks") | One native Navigator pane (firmware-side settings). Coexist with, and do not replace, ZSA's closed gesture companion (open question 7.5) |
| 15 | **Training and analytics scattered** (Oryx → typ.ing; heatmap in Keymapp) | Ergo 2026-01; [zsa.io/training](https://www.zsa.io/training); [zsa.io/keymapp](https://www.zsa.io/keymapp) | Offline drills on the user's own layers (Whack-a-Key style); heatmap-driven placement suggestions |
| 16 | **Switching whole layouts or profiles means reflashing via another tool** | omarchy-voyager (profiles via Zapp); Smart Layers covers only layers | Profile library with pre-built binaries and a quick-switch flash; or "layer sets" inside one layout (B `layout-buffet-layers`) |

**What users like, so Sextant must not regress:**
- the visual, approachable editor ("Oryx is a wonderful tool to play with your layout", benfrain; "There are more settings in Oryx than I could possibly ever need", cheeseturbulence)
- tours and embeds for sharing
- default layouts
- browser flashing on macOS with zero setup (B `2206-live-flashing`)
- ZSA's email support ([zsa.io/help](https://www.zsa.io/help) testimonials; benfrain.com: "They were very sympathetic and helpful")

---

## 7. Open questions

1. **Permission and rate limits.** Will ZSA authorize Sextant's read access to `oryx.zsa.io/graphql`, `/firmware/…` and `/source/…` (and possibly writes)? Are there rate limits? (Email `contact@zsa.io`, 5.1.)
2. **Default drift.** The Tap Flow default is 150 ms in the May 2025 blog but 100 in the bundle. The thumb exclusion for Chordal Hold is "by default" in a Jun 2025 note but an opt-in toggle (default off) in the bundle. Confirm by generating source for a fresh layout. This matters for import fidelity.
3. **Voyager MCU variants.** STM32F303xB-class per QMK PR #23912 (05 §2.1) versus GD32F303CB (RMK port). Which boards get Oryx's `alt` firmware variant? This affects local builds and DFU (with 03 §9 item 3).
4. **Layer cap.** Is the 32-layer cap enforced server-side? How does Oryx block OSL/LM targets ≥ 16 in the UI? (KC encodes `maxLayers: 16`.)
5. **Navigator companion app.** How does it talk to the trackpad, and can Sextant's HID use coexist with it? (Closed source; not inspected.)
6. **Reddit.** r/zsaVoyager and r/ErgoMechKeyboards could not be read (403). A manual pass may add pain points.
7. **Trademarks.** Statuses come from aggregators; verify in USPTO TSDR. Canada (CIPO) and EU (EUIPO) were not checked. ZSA is Canadian.
8. **Default firmware features.** Should Sextant-built firmware keep the ZSA "Oryx connection" protocol on by default so typ.ing, Keymapp and Zapp keep working? (Recommended: yes.)

---

## 8. Requests made during this study (topic 04)

**ZSA properties: 11 HTTP requests, all read-only, no auth, no GraphQL calls, nothing sent to the keyboard:**
- `GET https://zsa.io/privacy-policy-and-terms-of-service/` (+2 redirects) → `downloads/zsa-legal-04/pp-tos.html`
- `GET https://www.zsa.io/{terms,tos,legal,terms-of-service}` (4, all 404)
- `GET robots.txt` on configure.zsa.io, oryx.zsa.io, www.zsa.io (3)
- `GET https://typ.ing/oryx` (1) → `downloads/typing-04/oryx.html`

Everything else (blog, site pages, bundle, layout JSON, source zips) was reused from the earlier run's downloads, after checking: bundle md5 matches across its three copies; the blog feed covers every sitemap post; the settings catalog was re-verified against the bundle.

**Non-ZSA requests:**
- GitHub API about 200 calls (repo metadata, READMEs, issues, code search, file contents)
- WebSearch about 10
- WebFetch about 10: benfrain.com, filiphalas.com, rancic.org, cheeseturbulence.com, danieldk.eu, zmk.dev, get.vial.today, addons.mozilla.org, chromewebstore.google.com, developer.apple.com. Failed or blocked: notebookcheck.net, uspto.report, justia.com (403), keyderboard.com (NXDOMAIN).
- Reddit: 3 curl attempts (403 or a redirect to a block page)
- USPTO tmsearch API: 1 attempt (405)

**Local artifacts written:**
- `study/04-features-prior-art-legal.md` (this report)
- `study/04-oryx-settings-catalog.json` (verified; `_verified` note added)
- `study/04-prior-art-repos.tsv`
- working files in `work/04/` and `scripts/04/`
- downloads in `downloads/{zsa-legal-04,typing-04,reddit-04,trademarks-04,corne-04,gh-readmes-04}/`

---

## Independent verification

Fact-checker pass, 2026-10-11. I checked 23 claims against primary sources: the bundle files in `downloads/oryx-web/assets/` (md5 of `index-xhNfd6BI.js` re-checked as `34fbb4d6…`), the clean `zsa/zapp` clone at `a1be758` (tag v1.0.2, `git status` clean), the GitHub API, and live read-only requests. My own downloads are in `downloads/factcheck-04/` and my helper scripts in `scripts-factcheck04/`.

**Requests to ZSA in this pass: 11, all unauthenticated GETs.** No GraphQL calls and no mutations.
- `www.zsa.io`: 6 legal-path probes, the old privacy/ToS URL and the sitemap (8)
- `configure.zsa.io/robots.txt` (1)
- `oryx.zsa.io/firmware/latest/KlgM7` (1)
- `oryx.zsa.io/firmware/40xJ7M`, first 16 bytes only (1)
- `typ.ing` was not re-fetched

**Not checked live:** the Voyager was not connected, so `ioreg` and `hidutil` showed no ZSA device and the USB serial string could not be read.

### Results

| # | Claim (report section) | Verdict | Evidence (primary source) |
|---|---|---|---|
| 1 | Macros: max 24 steps; 5 steps without sign-in or acknowledgement; delay 0-5000 ms, default 100 (0.1, 2.3) | **confirmed** | `index-Bvxi2_Kp.js@117410` `pf=24,Ve=5`. `@117847` `g=(e==null?void 0:e.ackMacroRisks)==!1&&h>=Ve`, followed by `y=!e.logged&&h>=Ve`. `@121368`: the "Add another step" link is shown while `h<Ve`. `@121578`: `h>=Ve&&h<pf` shows "I understand and acknowledge" or "Please create an account to add more steps". `@121000`: `label:"Then wait",…defaultValue:100,unit:"ms",min:0,max:5e3`. Blog `longer-oryx-macros` (2025-04-01): "up to 24 steps", and acknowledgement is needed for macros "longer than five characters". |
| 2 | Combos are limited to 6 keys (0.1, 2.4) | **confirmed** | `index-xhNfd6BI.js@632258` `kw=2,rg=6`. The export `rg as ad` is imported by `_comboStep-0hH-FJFg.js` as `_`, which renders "You can select a maximum of ",_," keys." (`@2514`). Validation at `@873540` returns "Please select at least ${kw} keys" and "Max amount of keys selected". Blog `2212-combos`: "A combo can include up to six keys." The minimum is **2** keys, which the report omits. |
| 3 | ZSA publishes no Terms of Service. The footer link redirects (301) to `/privacy`, which has no terms. `/terms`, `/tos`, `/legal` and `/terms-of-service` return 404 (0.3, 5.1) | **confirmed** (as of 2026-10-11, based on absence of evidence) | Live `curl https://zsa.io/privacy-policy-and-terms-of-service/` returned 301 to `www.zsa.io/…/`. The saved `pp-tos.headers` shows a second 301 to `/privacy`. `www.zsa.io/{terms,tos,legal,terms-of-service,terms-of-use,terms-and-conditions}` all returned 404. `www.zsa.io/sitemap.xml` lists no terms or legal page; its only policy-type pages are `/privacy`, `/return-policy`, `/warranty` and FAQ pages. The privacy text (`factcheck-04/privacy-local.txt`) has zero matches for "term". In the bundle, the only "terms" string is the footer URL at `index-xhNfd6BI.js@943681`. Terms shown only at checkout cannot be ruled out (INFERRED). |
| 4 | `configure.zsa.io/robots.txt` disallows everything except `/` (5.1) | **confirmed** | Live: `user-agent: *` / `Allow: /$` / `Disallow: /`. This does not cover `oryx.zsa.io`, which is where the API lives. |
| 5 | Zapp calls GraphQL, `/firmware/{rev}` and `/firmware/latest/{layoutId}` without authentication, and parses the serial as `layoutId/revisionId` (0.3, 5.1) | **confirmed** | `zsa/zapp@a1be758`:<br>- `zapp-oryx/src/lib.rs:21` sets `ORYX_API_URL`.<br>- `:26-31` holds the query `layout(hashId,revisionId,geometry){revision{title}}`.<br>- `:85-90` sends the POST to `/graphql` with no auth header.<br>- `:155-161` calls `/firmware/latest/{layout_id}`, or `/firmware/latest/{geometry}/default` when the id is `default`.<br>- `:197-199` calls `/firmware/{rev}{"" \| ?alt=true \| ?collate=true}`.<br>- `zapp/src/main.rs:106-107` does `connected.serial.split_once('/')`.<br>Live, with no credentials: `GET /firmware/latest/KlgM7` returned 200 `{"latest":"40xJ7M"}`, and `GET /firmware/40xJ7M` returned 200 `application/octet-stream`. |
| 6 | Zapp is MIT + Commons Clause, which forbids selling a product whose value derives substantially from it (3.8, 5.5) | **confirmed** | `LICENSE.md:1-11`: "the right to Sell the Software … for a fee or other consideration … a product or service whose value derives, entirely or substantially, from the functionality of the Software". The report omits `LICENSE.md:7`: "Any license notice or attribution required by the License must also include this Commons Clause License Condition notice." So even a **free** app that links `zapp-core` must ship that notice. |
| 7 | Per-key History was disabled in Oct 2023 because of its performance cost (0.1, 2.10) | **partially-correct** | Blog `history` (Oct 2023 update) gives **two** reasons: "It didn't get much use … On the other hand, tracking every single action … had very real performance implications". The report gives only the second reason; the quote in section 6 row 5 is accurate. The bundle still has "Restore Layers" (`Legend-LTsHAjDy.js`, `_revisionId-CtR9sUEn.js`), and "See past edits" is absent. |
| 8 | Live Training moved to typ.ing, with Code Mode the last feature to move (Jan 2026); the Train link points to `typ.ing/oryx` (0.1, 2.13) | **confirmed** | `ergo-archive/2026-01.html`: "We've been steadily moving features from Oryx Live Training into typ.ing, and Code Mode is the last one to make the move." `index-xhNfd6BI.js@941115`: `href:"https://typ.ing/oryx",children:"Train"`. |
| 9 | Settings visibility: Audio is hidden for the Voyager; Navigator is shown only when a Navigator is attached (2.8) | **partially-correct** | `index-xhNfd6BI.js@676678` (`function OU(e,t,n,r)`):<br>- It filters `audio` for `ergodox-ez`, `ergodox-ez-st` and `voyager` (correct).<br>- It keeps `navigator` only if `r.left.kind` or `r.right.kind` is `"trackball"` or `"trackpad"`. Here `r` is the layout's saved **`revision.navigators`**, passed in by `_slug-Dpv49v-0.js` (`navigators:p` … `st(O,e,a,p)`). It is not a physically attached device.<br>Also, the "`glow:true` hidden for shine/standard" rule in 2.8 is **not** in `OU`. It is in `_slug-Dpv49v-0.js` (`d.glow===!0&&(a==="shine"||a==="standard")`), next to `capsLockStatus` being hidden for `planck-ez`. |
| 10 | QMK treats firmware that includes or translates QMK code as GPL-covered (5.4) | **confirmed** (quote); the application in 5.4 D is INFERRED | `qmk/qmk_firmware@2cbcd76ef0:docs/license_violations.md:63-69`; the blob `390280df` was confirmed through the GitHub API at that ref. The text is about **firmware** ("Any other non-QMK firmware which includes portions of QMK Firmware … even if used as a reference when translated to another programming language"). Scenario 5.4 D's "By QMK's stated position this makes Sextant a derivative" stretches that text to a host-side Swift app. The conclusion may still hold under ordinary copyright and GPL rules for translations, but QMK does not state it. |
| 11 | Mac App Store 2.5.2 bars downloading or running code; 5.2.2 needs permission from third-party services; 4.1(c) bars another developer's product name in an app's name or icon (5.2, 5.6) | **confirmed** (the toolchain conclusion is INFERRED) | Fetched 2026-10-11 (`factcheck-04/apple-guidelines.txt`):<br>- 2.5.2: "nor may they download, install, or execute code which introduces or changes features or functionality of the app".<br>- 5.2.2: "ensure that you are specifically permitted to do so under the service's terms of use. Authorization must be provided upon request."<br>- 4.1(c): "You cannot use another developer's icon, brand, or product name in your app's icon or name, without approval from the developer."<br>- 2.4.5(ii): "cannot install code or resources in shared locations".<br>2.5.2 is scoped to code that changes the app's functionality. Applying it to driving an external compiler is a reasonable but INFERRED reading. |
| 12 | Generated firmware sets `SERIAL_NUMBER` to `"KlgM7/40xJ7M"` and declares the modules `zsa/oryx`, `mousejiggler`, `navigator_trackpad`, `automouse` and `defaults` (2.12) | **partially-correct** | The user's `layout-source-c/…/config.h:2` does have `#define SERIAL_NUMBER "KlgM7/40xJ7M"`. But the **user's** `keymap.json` declares only `["zsa/oryx","zsa/navigator_trackpad","zsa/defaults"]`. The five-module list comes from the example layout `JRGQm`, whose serial is `"JRGQm/7vbZQA"`. The module list depends on which features a layout uses (jiggler, auto-mouse, trackball or trackpad). |
| 13 | Voyager hardware from upstream QMK: 12x7 matrix, MCP23018 expander, 2x IS31FL3731, 52 LEDs, 4 status LEDs, Ignition bootloader (0.5, 4.1) | **confirmed** (some citations need fixing) | Upstream `config.h:7-8` has `MATRIX_COLS 7` and `MATRIX_ROWS 12`. `:10-11` set `IS31FL3731_I2C_ADDRESS_GND` and `_VCC`. `keyboard.json` has `rgb_matrix.driver "is31fl3731"`, 52 layout entries, `max_brightness 175` and `bootloader "custom"`. `voyager.c:111-116` sets `STATUS_LED_1..4`, and `:297-305` carries the Ignition A8/A9 comment.<br>Citation fixes:<br>- `voyager.c:9` (`mcp23018_leds[2]`) holds status LEDs 3 and 4 (`voyager.h:15-16`). The right-half **matrix** read through the MCP23018 is in `matrix.c` (`mcp23018_readPins`) and `rules.mk` (`SRC += matrix.c mcp23018.c`).<br>- `voyager.c:218` sits under `#ifdef CAPS_LOCK_STATUS`, which is Oryx's "caps lock status" setting: LED 4 shows caps and LEDs 1-3 still show the layer. It is not under `VOYAGER_USER_LEDS`, which disables the layer-LED function entirely (`voyager.c:104`).<br>The GitHub API confirms the last directory change `47575d4af1` (2025-01-20) and `keyboard.json` `089a819179` (2024-06-16). PR #23912 (merged 2024-06-20) says "Voyager is using the xB version of the STM32F303". |
| 14 | Corne hardware is dual-licensed MIT and CC-BY-4.0; the ZMK `corne` shield declares Studio support (0.5, 4.4) | **confirmed** (with a nuance) | The `foostan/crkbd` root holds `LICENSE_CC` ("Attribution 4.0 International") and `LICENSE_MIT` ("Copyright (c) 2023 foostan"), and GitHub detects CC-BY-4.0. The README never says which licence covers which files, so "dual-licensed" is an interpretation (INFERRED). `zmkfirmware/zmk@4dd95d7840` `app/boards/shields/corne/corne.zmk.yml` lists `features: keys, display, underglow, studio`. QMK `crkbd` has `LAYOUT_split_3x5_3`=36 and `3x6_3`=42 keys, plus an unmentioned `r2g` directory. |
| 15 | keyjitsu: MIT, created 2026-08-11, beta, links `zapp-core` (0.2, 3.4) | **confirmed** | GitHub API: created `2026-08-11T22:28:20Z`, licence NOASSERTION. The `LICENSE` file is "MIT License". README: "**Beta.** Only tested on **macOS** with the **ZSA Voyager**". `Cargo.toml:29` has `zapp-core = { git = "https://github.com/zsa/zapp" }`, unpinned. "Most complete" is a judgement call. |
| 16 | USB identity: VID `0x3297`, PID `0x1977` (app); bootloader `3297:0791`; app image at `0x08002000` (4.1) | **partially-correct** (incomplete; matters for flashing) | `zapp-core/src/device/ids.rs:59-60,74` and `:106`: Voyager app PIDs are **`0x1977` and `0x1978`**. Bootloader PIDs are **`0x0791` (Ignition STM32) and `0x1791` (Ignition GD32)**, and both flash at `0x0800_2000` (`ids.rs:37-40`). The ZSA fork's `rules.mk` has `DFU_ARGS = -d 3297:0791 -a 0 -s 0x08002000:leave`. A flasher that matches only `0791` would miss GD32 Voyagers. Report 02 covers this correctly. |
| 17 | MCU variants are evidenced by Zapp's `Alternate` (`?alt=true`) firmware; open question 3 asks which boards get it (4.1, 7.3) | **refuted** (as evidence; the conclusion that MCU variants exist still holds) | Zapp uses `Alternate` **only** when `is_moonlander_revb(pid)` is true (`pid == 0x1972`): `main.rs:135-139`, `ids.rs:112-114`. Its doc comment (`lib.rs:176`) says "alternate MCU (e.g. Moonlander rev B)". `Collated` is used only for `moonlander` (`main.rs:90-95`). Better evidence for Voyager variants is the bootloader PID `0x1791` and `firmware/mod.rs:14` ("Dual-firmware file (e.g., Ignition Voyager STM32+GD32 …)"). The user's `.bin` (65,804 bytes) has a single DFU suffix, PID `0x0791`. Zapp's checker would still let it flash onto a `0x1791` device, because it only rejects mixing Ignition with plain STM32-DFU images (`flash/mod.rs:41-101`). |
| 18 | Oryx key index = `kNN` label = RGB LED index, not the `LAYOUT` array position (4.1) | **confirmed** | In upstream `keyboard.json`, for all 52 `LAYOUT` entries the `rgb_matrix` index at the same `matrix` cell equals the label number (0 mismatches, `scripts-factcheck04/`). In the user's layout, `keys[24]` is `KC_ENTER` with hold to layer 1, which is `keymap.c` `LAYOUT` position 48 `LT(1, KC_ENTER)`. `keys[51]` is `KC_SPACE`, which is position 51 `LT(2, KC_SPACE)`. |
| 19 | `jpds/rmk-zsa-voyager`: Apache-2.0; flashed with `dfu-util -d 3297:0791 -a 0 -s 0x08002000:leave`; GD32F303CB (3.5) | **partially-correct** | README:55 has the command exactly as given. README:74: "Licensed under either of Apache License 2.0 or MIT at your option", so it is dual-licensed; GitHub shows only Apache-2.0. The README says GD32F303CB but flashes via `0791`, which Zapp labels "Ignition STM32". That conflicts with Zapp and is still unresolved. |
| 20 | jyn514 `oryx_sync.py` writes back through undocumented mutations with `ORYX_TOKEN` as a Bearer token; Unlicense (0.2, 3.3) | **confirmed** | The file at `065018ec` has `headers["authorization"] = f"Bearer {self.token}"` at line 100 and `ORYX_TOKEN` at lines 518-520. The mutation list also includes `UpdateRevisionConfig` and `UpdateRevisionSwatch`, which the report does not list. The repo licence is Unlicense. |
| 21 | poulainpi's workflow reads GraphQL `revision{hashId,qmkVersion,title}` and downloads `oryx.zsa.io/source/{rev}`; MIT, 223 stars (2.12, 3.2) | **confirmed** | `fetch-and-build-layout.yml@26bfbe6` lines 46 and 54. GitHub API: MIT, 223 stars, pushed 2026-05-14. |
| 22 | Settings defaults: Tap Flow 100 (1-1000, toggleable); "Exclude thumbs" off; debounce on the Voyager 5; combo term 50 (10-100); tags limited to 6 × 15 characters (2.4, 2.5, 2.8, 2.10) | **confirmed** | `index-xhNfd6BI.js`:<br>- `key:"flowTap",…min:1,max:1e3,default:100,toggleable:!0`<br>- `key:"chordalHoldExcludeThumbs",…geometry:[…,"voyager"],default:!1`<br>- debounce `default:{…,voyager:5}`<br>- `comboTerm` `min:10,max:100,default:50`<br>`_revisionId-CtR9sUEn.js`: "You can select 6 tags max, a tag cannot exceed 15 characters". |
| 23 | Trademark statuses: VOYAGER application 97087577, MOONLANDER Reg. 6164380, and others (5.2) | **unverifiable** | The USPTO TSDR API returned 401: "Beginning October 2, you'll need to register for an API key". The report already flags these as aggregator-sourced. |

### Corrections to apply

1. **4.1 "USB identity" row.** Add app PID `0x1978` and the GD32 bootloader `3297:1791`, citing `zsa/zapp@a1be758:zapp-core/src/device/ids.rs:54-79,98-114`. Sextant's device matching must accept both bootloader PIDs.
2. **4.1 "MCU" row and open question 7.3.** Replace the `?alt=true` evidence. In Zapp, `Alternate` is used only for the Moonlander rev B (`0x1972`). Cite the `0x1791` "Ignition GD32" bootloader PID and the `IgnitionDual` "Voyager STM32+GD32" comment (`zapp-core/src/firmware/mod.rs:14`) instead.
3. **2.12 "Generated keymap.json" row.** Say the module list varies by layout. The user's `KlgM7` declares `zsa/oryx`, `zsa/navigator_trackpad` and `zsa/defaults`; the five-module list belongs to the `JRGQm` example.
4. **2.8 visibility rules.** Navigator visibility depends on the saved `revision.navigators` config, not on hardware detection. The `glow` filter lives in `_slug-Dpv49v-0.js`, not in `OU`.
5. **2.10 History row (and 0.1).** Add the low-usage reason ZSA gave.
6. **4.1 Status LEDs row.** `voyager.c:218` is the `CAPS_LOCK_STATUS` path, which is Oryx's caps-lock setting. `VOYAGER_USER_LEDS` turns off the default layer display.
7. **4.1 Matrix row.** For the MCP23018 matrix read, cite `matrix.c` and `rules.mk`; `voyager.c:9` is the status-LED state.
8. **3.5 / 3.8.** `rmk-zsa-voyager` is Apache-2.0 **or** MIT.
9. **5.4 D.** Mark "By QMK's stated position" as an extension: QMK's policy text addresses firmware.

### Important omissions noticed

- **Commons Clause notice duty** (`zapp/LICENSE.md:7`). Any distribution that links `zapp-core` must carry the Commons Clause notice, even in a free app.
- **Zapp's flash-safety check.** `zapp-core/src/flash/mod.rs:41-101` refuses to put a plain STM32-DFU image (linked at `0x0800_0000`) on an Ignition device (`0x0800_2000`), and the reverse, because a mismatch "would brick the keyboard". It picks the matching image out of dual-image files by bootloader PID (`flash/dfu.rs:58-66`). Sextant's flasher should copy these rules: read the DFU-suffix PID and compare it with the bootloader PID.
- **Zapp's stock-layout endpoint.** Zapp uses `/firmware/latest/{geometry}/default` for stock layouts (`lib.rs:155-156`). Report 3.1 lists only `/firmware/latest/{layoutId}`.
- **Keymapp is on the Mac App Store** (B `2312-updates`; `zsa/kontroll#15` shows the sandbox container path). So a sandboxed app that does HID and firmware flashing has passed review (INFERRED: the store build includes flashing). The Mac App Store objection in 5.6 applies to **local compilation and toolchain management**, not to an edit + Oryx-compile + flash app. A store edition would still need ZSA's 5.2.2 authorization.
- **Combos need at least 2 keys** (`kw=2`).
- **The macro step cap is not fully enforced in the client** (INFERRED). The per-step "Add a step here" insert link (`index-Bvxi2_Kp.js@121327`) is not gated by `Ve`/`pf` in the client code. Sextant should enforce the 24-step and 5-step limits itself rather than assume Oryx's server rejects longer macros. Server behaviour was not tested, because that would need a mutation.
- **`robots.txt` scope.** `configure.zsa.io/robots.txt` covers the web UI host only. The API host `oryx.zsa.io` has no `robots.txt` (404), so robots rules neither permit nor forbid API use. The ZSA-permission recommendation in 5.1 is the right basis.
