# 01 — Oryx web app internals

> Rendered from the research agent's structured return value: the harness blocked the agent from writing this file directly.
> Where **Independent verification** (bottom) disagrees with a finding, the verification wins.

## Summary

I studied Oryx (configure.zsa.io) by reading its code as data; nothing was executed. Sources: the live bundle index-xhNfd6BI.js (md5 34fbb4d6…), 155 other chunk/CSS/font/image files, /metadata.json, the user's layout, five public example layouts, zsa/qmk_firmware firmware25@93b2b9e, zsa/qmk_modules@13890cd, zsa/zapp, the Vial Voyager port, Corne's QMK info.json, and ZSA's Voyager bottom-plate STL.

Oryx is a Vite/React/mobx-state-tree app. It uses Apollo against a Rails graphql-ruby server at https://oryx.zsa.io/graphql. Introspection is off, so I rebuilt the schema from the 73 documents in the bundle (68 operations, 5 fragments). Anonymous access covers reading public layouts, the latest-revision lookup and downloading .bin/source. Every write needs a Bearer JWT, which the browser keeps in localStorage.jwtToken; there are no cookies and no CSRF.

Edits are saved per key: updateKey(layerHashId, position, keyJSON), debounced 400 ms, and only on draft revisions (qmkVersion null). compileRevision is one synchronous mutation with no polling. The binary comes from GET /firmware/<rev>.

I documented the full data model: KeyStep, macros (max 24 steps), combos (2-6 keys), the sparse config (91 keys, 100 UI settings) and its client-side rules. I built a 2,526-key catalog with kinds, macOS glyphs and availability rules. The Voyager geometry is verified: key index = QMK k<i> = LED index = live-training matrix map, and Main key 0 is KC_EQUAL/KC_ESCAPE. I also captured the design tokens: blue = multi-function, green = modifier, Inter, 5 px radius. The bundle contains a complete WebUSB DFU flasher for the Voyager "ignition" bootloader, now documented byte-for-byte.

For the user's request on open-source material: QMK keyboards/zsa/voyager (GPL-2.0) is the authoritative firmware geometry. ZSA publishes only bottom-plate STLs (137.85×136.87 mm per half), not PCB or top-shell files. The Corne (foostan/crkbd, CC-BY-4.0) is the nearest open sibling: 6 columns per half like the Voyager, but 3 rows and 3 thumbs (42 keys) instead of 4 rows and 2 thumbs (52 keys). I recommend a data-driven KLE/QMK-style renderer.

## Key findings

1. Architecture: Oryx is a Vite + React SPA on Cloudflare. It uses mobx-state-tree models (root store Tj, [IDX@859641]), Apollo Client with the link chain [auth tB, networkError nB, sync rB, HttpLink iB] (uri https://oryx.zsa.io/graphql, credentials:'same-origin', [IDX@630961-631552]), TanStack Router [IDX@992199] and a Fuse-style key search. Source maps are not served: /assets/index-xhNfd6BI.js.map returns the SPA HTML. The backend is Rails + graphql-ruby behind Caddy/Cloudflare (headers x-runtime, oryx-env: production, oryx-qmk-version: 25; ActiveStorage blob URLs). CORS allows only https://configure.zsa.io, which does not affect a native app. Editor URL: /:geometry/layouts/:layoutId/:revisionId|latest/:layerIdx[/:keyIdx/:keyTab]; other routes include /config/:slug, /combos/:comboStep, /tour, /navigator/:side, /embed, /print, /search, /my-layouts and /templates/layers/*.
2. GraphQL: introspection is disabled ('Field __schema doesn't exist on type Query'). The bundle compiles in 73 documents: 68 operations and 5 fragments (TourData, RevisionData, LayoutData, UserLayoutData, UserData). All of them, with file offsets and purposes, are in study/oryx-graphql-operations.json; the reconstructed SDL is in study/oryx-schema.reconstructed.graphql. Canonical fetch: query getLayout($hashId,$revisionId,$geometry){ layout(hashId,geometry,revisionId){ privacy geometry hashId parent{hashId} tags{id hashId name} title user{annotation annotationPublic name hashId pictureUrl} isDefault lastRevisionCompiled isLatestRevision revision{ alternates{hashId model} createdAt hashId navigators model title config swatch qmkVersion qmkUptodate hasDeletedLayers md5 altMd5 combos{keyIndices layerIdx name trigger} tour{hashId url steps:tourSteps{hashId intro outro position content keyIndex comboIndex keyIndices layer{hashId position}}} layers{automouse builtIn hashId keys position title color prevHashId} mcuAlternateRevisionHash mcuAlternateLayoutHash } } }. revisionId may be 'latest'. Revision.hexUrl/zipUrl exist on the server but the client builds its own URLs. Six documents are unassigned dead code: updateLayoutMcu, getLayoutIdByLegacyId, migrateLegacyLayout, getAlternateFirmwareLinks, reportRevision, orderData.
3. Mutations used by the editor (none were called during the study):
- Layout and revision: createLayout(title, revisionHashId, geometry, parentHashId, mcuAlternate); updateLayoutTitle/Tags/Privacy; deleteLayout; saveLayoutSnapshot(layout: Json); compileRevision(hashId){md5 altMd5 qmkVersion qmkUptodate buildErrorLog buildSource buildConfig buildRules}; updateRevisionModel/Config(config: Json)/Swatch/Title/Intro/Outro; updateRevisionAutomouse(revisionHash, layerPosition, automouse); updateNavigators(revisionHash, navigators: Json); forkRevision; deleteRevision; publishTour.
- Layers and keys: createLayer(newKeys: Json, revisionHashId, position, title, automouse); updateLayer(hashId, newKeys, position, title); updateLayerColor; reorderLayers(hashId, direction: LayerReorderDirection = left|right|beginning|end); deleteLayer; restoreLayer; updateKey(hashId = LAYER hashId, keyData: Json, position = key index); swapKeys.
- Combos and tours: upsertCombo(revisionHashId, comboIdx|null, name, layerIdx, keyIndices, trigger: Json); deleteCombo; reorderCombos; updateTourStep; reorderTourStep.
- Analytics: trackEvent(event: TrackingEvent = training|download_hex|download_zip seen, payload).
- Account: signupWithEmail, requestPasswordReset, resetPassword, updateUsername, emailChangeRequest, changeEmailWithToken, deleteAccount, ackMacroRisks, otpChallenge, disable2fa.
- Templates and admin: createOrUpdateLayerTemplate, deleteLayerTemplate, createTag, submitQcReport.
Queries: layout, searchLayouts(start, limit, tags, geometry, anonymous, withTour), getDeletedLayers, getTour, currentUser, myLayouts (with the revision history list), authenticate(authToken), loginWithEmail (a query), otp, statsExport, tags, searchLayerTemplates, layerTemplate, layerTemplatesForLayer.
4. Auth as seen in code:
- Link tB adds 'Authorization: Bearer <localStorage.jwtToken>' whenever a token exists [IDX@630961].
- oryx.zsa.io is cross-origin and requests use credentials same-origin, so no cookies are sent and there is no CSRF token.
- Getting a JWT: loginWithEmail (a query), signupWithEmail, or OAuth. The OAuth flow is https://oryx.zsa.io/auth/{twitter,github,google_oauth2} → configure.zsa.io/auth/callback?authToken=X → query authenticate(authToken){token user{...}}. Each path stores the token in localStorage.jwtToken.
- Logout: https://oryx.zsa.io/authenticate/logout. 2FA uses otp / otpChallenge / disable2fa.
- Keymapp account linking: POST https://oryx.zsa.io/authenticate/auth_phrase with the Bearer token returns {phrase}, refreshed every 60 s for the user to paste into Keymapp. The exchange endpoint on the Keymapp side is not in the web bundle.
- Error strings: NotFound, PrivateLayout.
- Offline recovery: network errors queue the revision, and saveLayoutSnapshot(whole MST snapshot) is retried every 10 s (H7=1e4); a toast appears after 5 errors [IDX@767941].
5. REST endpoints, all anonymous and verified:
- GET https://oryx.zsa.io/firmware/<revHash> returns the .bin. For 40xJ7M it is 65,804 bytes with md5 4d59bb3d… = revision.md5.
- ?alt=true returns the alternate-MCU build (compare altMd5). ?collate=true is for Moonlander/Halfmoon only.
- GET /source/<revHash> returns the generated QMK source zip.
- GET /firmware/latest/<layoutHash> → {"latest":"<rev>"}; KlgM7 → 40xJ7M. GET /firmware/latest/<geometry>/default → voyager → B495Jd.
- GraphQL hexUrl/zipUrl are Rails ActiveStorage redirects (302) to signed DigitalOcean Spaces URLs that expire after 7 days.
- Other hosts: https://configure.zsa.io/metadata.json (key catalog), https://assets.configure.zsa.io/<icon>-<light|dark>.svg (key icons), https://colours.zsa.io/name/<hex> (colour names), and https://oryx.zsa.io//error-report (JS error POSTs every 5 s).
- ZSA's own open-source client zsa/zapp (zapp-oryx/src/lib.rs lines 21-197) uses the same REST contract.
6. Revision lifecycle and saving:
- Revision.editable = qmkVersion === null || compiling [IDX@794055], so a compiled revision is frozen.
- 'Click here to start making changes' calls layout.clone(rev) → createLayout(title, revisionHashId, parentHashId = current layout, geometry, mcuAlternate) → {hashId, revision}. INFERRED: for the owner this adds a new draft revision to the same layout; for anyone else it creates a fork.
- There is no Save button. Each Key has an MST onPatch handler, debounced 400 ms, that calls updateKey(layerHashId, position, Key.serialize = {glowColor, lockGlowColor, customLabel, tappingTerm, tap, hold, doubleTap, tapHold, icon, emoji}) [IDX@711194].
- Patches to /glowColor /setLockGlowColor /swapping /swapped /customLabelEditing /history /tappingTerm /pristine are skipped by the auto-persist [IDX@696994].
- createLayer/updateLayer send 52 × {customLabel, glowColor, tap, hold, doubleTap, tapHold, icon, emoji}, dropping lockGlowColor and tappingTerm.
- Config is saved as the whole sparse object, debounced 400 ms.
7. Compile and download. compile() [IDX@799354] runs four steps:
1. clear disallowed tap-only steps;
2. heal combo triggers that point to missing layers;
3. if the title is empty, set it to 'Keyboard layout edited.';
4. call the single mutation compileRevision(hashId).
The response already carries md5, altMd5, qmkVersion and the build logs/source/config/rules. There is NO job id, subscription or polling; the UI just waits on that one HTTP request. After it returns, qmkVersion is set and the revision is read-only with firmware/source URLs. Browser flashing then fetches /firmware/<rev>. The md5 check in iG() is computed but its result is ignored [IDX@885766].
8. Data model (MST, exact):
- Layout (vc @760002): hashId, title, geometry ∈ {ergodox-ez, ergodox-ez-st, planck-ez, moonlander, voyager, halfmoon}, privacy, isDefault, parent, tags, user, revision.
- Revision (uj @793061): hashId, title (commit message), createdAt, model (voyager 'v1'), qmkVersion (null = draft), qmkUptodate, md5, altMd5, config, swatch{colors[10]}, navigators{left,right}, combos|null, tour, layers[], alternates[{hashId, model}], hasDeletedLayers, mcuAlternate*.
- Layer (rv @755796): hashId, title (default 'Layer'), position (= QMK layer), color '#RRGGBB'|null, builtIn adjust|raise|lower|base|null, automouse, prevHashId, keys[52].
- Key ('Key' ag @697186): tap/hold/doubleTap/tapHold: KeyStep|null, customLabel, icon, emoji, glowColor (stored uppercase), lockGlowColor, tappingTerm (0..1000 ms; null = config.tappingTerm, default 200).
- KeyStep (mi @745318): code, layer (for MO/TG/TO/TT/OSL/LM), modifier (one MOD_* mask, OSM/LM only), modifiers {leftCtrl, leftShift, leftAlt, leftGui, rightCtrl, rightShift, rightAlt, rightGui} (setting one side clears its twin), macro (tap only; then code = KC_TRANSPARENT), color ('#rrggbb', only for code RGB), description (free text).
- Stored key JSON is schemaless. It can also carry legacy about/aboutPosition and leaked client fields (pristine, history, detached, swapping, swapped); missing fields mean null.
9. Macros: tap = {code:'KC_TRANSPARENT', macro:{name, keys:[{code, modifiers, delay}], endEnter, applyAlt}}.
- Steps: up to 5 freely (Ve=5). Steps 6-24 (pf=24) require a logged-in user who has acknowledged ackMacroRisks: 'Macros are stored non-encrypted and are published' [index-Bvxi2_Kp.js@117356-121709].
- Delay ('Then wait'): default 100 ms, range 0..5000 ms; a new step inherits the previous step's delay (gC=100 @751530).
- applyAlt ('Hold Alt pressed (send Unicode)') clears per-step modifiers and hides delays. endEnter appends Enter.
- Only catalog keys with macro:true are offered; macro step codes are rewritten through the alias map on load.
- Generated firmware uses an ST_MACRO_n custom keycode with SEND_STRING(SS_LCTL(SS_LGUI(SS_TAP(X_1)))SS_DELAY(100)…).
10. Combos are revision-level: {name (required), layerIdx, keyIndices 2..6 (kw=2, rg=6 @632250), trigger: full Key snapshot (stored with detached:true; its tap is what is sent)}. They are saved with upsertCombo(comboIdx null = create), debounced 400 ms. A combo stays a draft (unsaved) while it has no name, fewer than 2 keys, or a blank trigger. Two combos conflict when they are on the same layer and their keys have identical action sets. A key that belongs to a combo cannot be modified. Combo keys must be comboPickable and must not be tap-dance or transparent keys (LT, mod-tap and modifier-hold keys are allowed). The combo term is config.comboTerm (default 50, range 10-100 ms). The 'Combos' picker category appears only when revision.combos != null.
11. Editor classification rules (views in [IDX]):
- isTapDance @700724: doubleTap or tapHold present; OR tap+hold where the tap is a layer key, ALL_T/MEH_T, has modifiers, or is shifted.
- isModTap: not a tap dance, tap not shifted and not a layer key, hold is a modifier → MT().
- isLT: hold ∈ {MO, LOWER, RAISE} with a plain tap → LT().
- isMagic: not tap-only and not hold-only, with hold/doubleTap/tapHold present.
- KeyStep conflicts: layer key without a layer; target layer ≥ layer count; forward-only key targeting its own or a lower layer.
- 'Preceded': key i on layer L is disabled when a lower layer's key i is the forward layer key to L, unless config.ambidexLT applies to MO/LM/TT.
- danceError: multi-mod on non-tap steps of a dance, or Hyper/Meh on both tap and hold.
- Lock keys: Caps, Num, Scroll (KC_CAPSLOCK/KC_NUMLOCK/KC_SCROLLLOCK or KC_CAPS/KC_NUM/KC_SCRL) allow lockGlowColor.
- cssClass precedence: danger > disabled > magic > modifier > macro > shine > custom.
- Per-key tapping term is shown only when config.perKeyTappingTerm is on and the key is magic, and it is copied to identical LT/mod-tap keys (QMK per-key terms are keyed by keycode).
12. Key picker availability tv(key, ctx) [IDX@731106], checked in order:
1. macro context requires macro:true;
2. combo trigger requires comboTrigger:true;
3. space-cadet keys require config.enableSpaceCadet, are not allowed in tap dances, and tap/hold must not collide;
4. key.geometry must include the geometry;
5. key.models must include revision.model;
6. LOWER/RAISE only on the builtIn base layer;
7. the category must not be filtered by D7;
8. Hyper/Meh not allowed on hold in a tap dance;
9. forward layer keys need a higher layer (maxLayers 16 for OSL/LM);
10. QK_LLCK not on layer 0;
11. the key's own step flag (tap|hold|doubleTap|tapHold) must be true.
D7 [IDX@729315] hides: combos unless revision.combos; autoshift unless config.autoshift; Dynamic Macros unless config.enableDynamicMacros; navigator unless revision.navigators; each of the 37 locale/steno categories unless config.<code>.
Defaults on pick: a layer key gets the first allowed layer; OSM/LM get MOD_LSFT; RGB gets color '#550000'; changing code clears modifiers, description and macro. Typing a physical key picks the entry whose jsCode equals KeyboardEvent.code; Ctrl/Shift/Alt land on hold.
13. revision.config (model Hw @677679) has 91 keys. The UI catalog Kd [IDX@641536] has 14 sections and 100 settings (the Navigator section writes into revision.navigators, not config). Three legacy keys have no UI: leaderTimeout, ignoreModTap, disableTraining. Selected defaults:
- tappingTerm 200 (0-1000); comboTerm 50 (10-100); autoshiftTimeout 175 (50-350); debounce voyager 5 (0-50).
- mouseInterval 20, mouseDelay 10, mouseMaxSpeed 10, mouseTimeToMax 30, mouseWheelInterval 80, mouseWheelMaxSpeed 8, mouseWheelTimeToMaxSpeed 40, mouseWheelDelay 400.
- rgbTimeout 0-15 min; rgbHueStep 8; rgbBriStep 16; disabledAnimations: 48 options.
- flowTap 100 (toggleable); oneShotTapToggle 2-5; oneShotTimeout 100-8000.
Client rules:
- Sparse: a value equal to its default is deleted (flowTap excepted).
- tappingTerm > 500 auto-enables permissiveHold.
- audioClick and audioDisable are mutually exclusive.
- Autoshift sub-toggles and the master toggle are coupled.
- chordalHold sets chordalHoldExcludeThumbs to the same value.
- ambidexLT=false clears preceded keys.
- Legacy migrations: disableTraining → liveTraining=false; ignoreModTap=false → holdOnOtherKeyPress=true.
The user's config is {qmkCanary:true}. Everything is in study/oryx-config-settings.json.
14. Keycode catalog (study/oryx-keycodes.json, from /metadata.json: 2,526 keys, 61 categories; Keymapp uses the same data as keymapp-startup-data.json).
- Per-key fields: code, label, per-step flags tap/hold/doubleTap/tapHold, modifiable, shifted, macro, comboPickable, comboTrigger, tag, searchLabel, jsCode, description, priority, glyph, os{osx,win,linux,others}, params, geometry, models, is_space_cadet.
- Label resolution jB() [IDX@696009]: use os[current] if present, else os.others; a null label becomes ''. The macOS resolution is stored per key; e.g. KC_LGUI → 'Left Command' with glyph command_left U+E947, and F14/F15 → brightness glyphs.
- Kinds (this study's classification against fw25 headers and zsa/qmk_modules):
  - qmk 1,762 — plain QMK names;
  - qmk-legacy-name 242 — e.g. KC_LCTRL→KC_LEFT_CTRL, MAGIC_TOGGLE_NKRO→NK_TOGG;
  - qmk-function 7 — MO, TG, TO, TT, OSL, LM, OSM;
  - qmk-mod-tap 2 — ALL_T, MEH_T;
  - qmk-mod-mask 10 — MOD_*;
  - zsa-module 14 — navigator keys, KC_MS_JIGGLER_TOGGLE, KC_MS_DBL_CLICK, TOGGLE_LAYER_COLOR, LED_LEVEL;
  - oryx-color 1 — RGB;
  - oryx-builtin-layer 6 — LOWER/RAISE variants;
  - oryx-custom 18 — RGB_SLD, KC_PC_*, KC_MAC_*, MAC_SPOTLIGHT/LOCK/DND/SIRI/MISSION_CONTROL, MOON_LED_LEVEL, WEBUSB_PAIR, ORYX_SL_TOGG/TRIGG;
  - oryx-locale-alias 464.
- 82 icon-font glyphs with code points are included.
15. Keycode naming gotcha: the catalog uses legacy QMK names (KC_LCTRL, KC_BSPACE, KC_PGUP, RESET, CAPS_WORD), while stored layouts use modern names (KC_LEFT_CTRL, KC_BSPC, KC_PAGE_UP, QK_BOOT, CW_TOGG). The alias map wh [IDX@739359] has 298 entries mapping stored → catalog; examples: LOWER_LT→MO, KC_HYPR→ALL_T, and the oddity KC_KP_EQUAL→KC_EQUAL. All 34 non-catalog codes found across the user's layout and the 5 example layouts resolve through this map. A code with no catalog entry and no alias is silently rewritten to KC_TRANSPARENT by the client. Data bug: MOD_RALT.os.osx.glyph is the text 'Right Option', not an icon name. INFERRED: the server normalises to modern names on save, because key 18 (written by the current client) is stored as KC_LEFT_CTRL and the client has no reverse map. Recommendation: Sextant stores modern names, keeps unknown codes, and uses the map only on import.
16. Voyager geometry (study/voyager-geometry.json, all asserted by script):
- Layout key index i = QMK k<i> (fw25 keyboard.json lines 163-214) = RGB LED index i (rgb_matrix lines 103-154; setLedColor uses led = key index) = jC[row][col] live-training map [IDX@867072].
- Halves: 0-23 left 4×6 row-major (col 0 = outer); 24/25 left thumbs (upper-outer / lower-inner); 26-49 right 4×6 (col 0 = inner); 50/51 right thumbs (lower-inner / upper-outer).
- Home row: 13-17 and 38-42. Left half = index ≤ 25.
- The QMK LAYOUT_voyager argument order interleaves the halves: 0-5, 26-31, 6-11, 32-37, 12-17, 38-43, 18-23, 44-49, 24, 25, 50, 51.
- Matrix is 12×7 (ROW2COL) with two quirks: k23 at [4,4] and k44 at [10,2].
- USB 0x3297:0x1977, STM32F303, bootloader custom.
- Cross-checks: Main key 0 = tap KC_EQUAL / hold KC_ESCAPE; key 24 = KC_ENTER/MO 1 and key 51 = KC_SPACE/MO 2, matching LT(1,KC_ENTER) / LT(2,KC_SPACE) in keymap.c.
17. Oryx board rendering (CSS rules .editor .voyager; render order from Rocket-CfXlil5s.js@31011):
- DOM order: half-row-left[0-5], navigator.left, logo, navigator.right, half-row-right[26-31]; then L/R rows 6-11/32-37, 12-17/38-43, 18-23/44-49; then clusters(left[24,25], fluke, right[50,51]).
- Grid: padding 15px; columns repeat(6,1fr) 1fr 3fr 1fr repeat(6,1fr) (17 fr across 15 tracks); rows repeat(4,1fr) 2fr; gaps 4px.
- Keys: square (padding-top 100%), radius 5px, 1px solid var(--border-color).
- Column stagger: left nth-child(3,5) translateY(-15%), (4) -30%; right (2,4) -15%, (3) -30%.
- Thumbs: .clusters{grid-column 6 / span 5; 3 cols; column-gap 10%; margin-top 8%}; each cluster is a 2-col grid with 4px gap; left rotate(30deg), right rotate(-30deg) about the cluster centre.
- Pixel model for a .voyager element W px wide: fr = (W-86)/17; trackX[t] = 15 + Σ widths + 4t; rowY[r] = 15 + r(fr+4); cluster x0 = trackX[5], Wc = 7fr+16, colW = 0.8Wc/3, thumb key = (colW-4)/2 ≈ 0.936fr.
- Example at W=1000: fr = 53.77; key 0 centre (41.9, 41.9); key 24 centre (332.6, 289.0), 30°.
18. Physical/open geometry (for the user's open-source request):
- QMK keyboard.json gives physical x/y in 1u with a 0.25/0.5u column stagger and no rotation or size for the thumbs: k24 (5,4.5), k25 (6,4.75), k50 (9,4.75), k51 (10,4.5).
- The community Vial KLE (vial-voyager/vial.json) draws the thumb clusters at ±35° with the inner thumb 1.35u tall; Oryx draws both thumbs square at ±30°. Treat the Oryx render as stylised.
- ZSA publishes only bottom-plate STLs (https://www.zsa.io/assets/voyager/voyager_stl.zip, linked from zsa.io/voyager/printables; no license stated). Each half measures 137.85 × 136.87 × 2.33 mm (binary STL, 12,114 and 12,092 triangles).
- No PCB or top-shell files exist among the 16 repos of github.com/zsa.
- Corne: foostan/crkbd hardware is CC-BY-4.0 and QMK keyboards/crkbd/info.json is GPL-2.0. It has the same 6-column column-staggered split, but LAYOUT_split_3x6_3 has 42 keys (3 rows + 3 thumbs, the inner thumb 1.5u tall and unrotated); a 3x5_3 variant also exists.
- Recommendation: a data-driven renderer taking {x,y,w,h,r,rx,ry} per key index, with an Oryx-faithful Voyager preset, so a Corne or other QMK board can be added from info.json.
19. Design tokens (study/oryx-design-tokens.json, verified against [CSS] md5 fbfc9e29…):
- Theme: <html data-theme>; localStorage.theme = light (default) / dark / os.
- Light palette: body #ffffff, text #323546, key fill #ffffff, key border #d7d7d7, tab bar #efefef, tab #f6f6f6, active tab #ffffff, link #008cba.
- Dark palette: body #191324, text #efeefb, key #191324, border #c6c8c9, tab bar #323546, link #5ac5e0.
- Key types (light/dark), with legend text from Legend-LTsHAjDy.js:
  - magic (blue) #e1ebff/#0a2d70 — 'A key with more than one function'; a '+' badge marks more than two;
  - modifier (green) #ebffe1/#1a6111 — 'A modifier key (Shift, for example)';
  - macro #e0dbff/#654598;
  - LED control (shine) #fff1ba/#877100;
  - custom label #ffbfa3/#7c3e04;
  - invalid #da2c2c/#8d081c with white text;
  - disabled = 45° stripes.
- Glow: box-shadow 0 0 8px <glowColor || layer.color>; in light theme, colours with luminosity > .9 become #c2e5fa.
- Fonts: Inter 400/700; body 14px; legend 16px (20px for labels under 3 chars, 12px for labels over 8).
- Modifier prefix: 1/2/3+ modifiers use long/medium/short names (Command/Cmd/C, Opt/OPT/O on macOS).
- Sub-legend tag ('hold', 'tap', 'tap/hold', 'numpad', locale code) at .7em, top-right or bottom-right; icon-font glyph at 1.8em with the layer number overlaid.
- Layer tabs: 50px tall, min-width 130px, active tab bold. Primary button .button: Inter 18px, #fff on #d48f2e, padding 10px 15px, hover var(--link-color) — used for 'Save to my keyboard' / 'Compile this layout'.
20. WebHID live training (bundle; details in 03):
- Filter: vendorId ∈ {0xFEED, 0x3297} × product IDs (Voyager 0x1977), usagePage 0xFF60, usage 0x61.
- Reports: 32-byte sendReport(0, [cmd, …]) followed by a 1 s sleep; inbound bytes are parsed as Int8 and split on 0xFE.
- Commands used: 0 GET_FW_VERSION (reply 'layoutId/revisionId' → fetches the layout), 1 PAIRING_INIT, 2 PAIRING_VALIDATE, 5 RGB_CONTROL, 6 SET_RGB_LED [led=keyIndex, r, g, b], 7 SET_STATUS_LED.
- Events: 6/7 key down/up (col,row) → jC → key index; 5 = layer change.
- Heatmap hue = (1 - min(presses/300, .999))·240.
- A training trackEvent is coded but never fires: the counter is reset before the >0 check.
- Legacy WebUSB bulk protocol constants are in dG [IDX@896692].
21. WebUSB DFU flasher for the Voyager 'ignition' bootloader (class $C [IDX@880215], constants [IDX@879827]):
- requestDevice filters: 0483:DF11 and 3297:{0791, 1791, 2000, 2001, 2002, 2003}. Ignition STM32 PIDs: 0x0791, 0x2000-0x2003. GD32 ignition: 0x1791. PID 0x2003 ⇒ fetch ?alt=true.
- Setup: open, selectConfiguration(1), claimInterface(0); class/interface control transfers with index 0.
- DFU requests: DNLOAD=1, GETSTATUS=3 (6 bytes: status, LE24 pollTimeout, state), CLRSTATUS=4, GETSTATE=5. State 5 = dfuDNLOAD_IDLE, 10 = dfuERROR.
- DfuSe commands sent as DNLOAD block 0: 0x21+addr32le = set address, 0x41+addr32le = erase page.
- Address ranges: ignition flashes 0x08002000..0x08042000 (8 KiB bootloader); ST DFU 0x08000000..0x08040000. Pages and chunks are 2048 bytes.
- Sequence:
  1. clear the error state;
  2. strip the 16-byte DFU suffix ('UFD' at bytes 8-10, VID at 4-5, PID at 2-3; must match a filter);
  3. erase pages up to len + 2-4 KiB;
  4. for each 2 KiB chunk: set address, DNLOAD with block 2, poll GETSTATUS (sleep pollTimeout, up to 100 tries) until state 5;
  5. reboot with a zero-length DNLOAD followed by GETSTATUS.
- Voyager qmkVersion ≠ 24.0 uses 'double compilation': GD32 boards take the image after the first STM32-PID suffix.
- The user's bin has a single suffix at offset 65,788: ff ff 91 07 97 32 00 01 55 46 44 10 fd 09 4f 2e (PID 0x0791, VID 0x3297). INFERRED: it is STM32-only.
22. Example layouts in scratchpad/oryx/examples/ (full LayoutData):
- voyager-default.json (E5AmY/B495Jd, stock): RGB colour keys, tour.
- voyager-JRGQm.json: 12 layers, 66 macros, 32 combos, tap dances, LM/OSM, swatch, trackpad navigator, rich config, tour.
- voyager-m9dpx.json: ZSA Robin; combos, colour keys, leaked history/pristine fields.
- voyager-e5Rrr.json: autoshift, tap dances with layer targets.
- voyager-XlrR4.json: per-key tapping term, UK locale.
They were found via searchLayouts(geometry:'voyager', withTour:true), which returned 134 results.
In firmware, a layer colour becomes a per-LED HSV ledmap row (#00F0FF → {131,255,255}, #42FF00 → {74,255,255}). RGB set-colour keys become custom keycodes HSV_h_s_v (user keymap.c lines 8-13, 38).
23. Implications for Sextant:
1. Import public layouts anonymously via the getLayout document and resolve 'latest' via /firmware/latest/<id>. These are stable contracts that ZSA's own zapp also uses.
2. Model layouts as in the data-model finding (a typed Key/KeyStep/Macro/Combo graph), storing modern QMK names and tolerating extra or legacy fields.
3. Drive the picker from oryx-keycodes.json (or /metadata.json, cached), implementing the tv/D7 rules and the macOS label/glyph resolution. The oryx icon font is ZSA's asset: check its licence before shipping it.
4. Render with the CSS grid model and the token palette in light and dark (blue = magic, green = modifier).
5. Flash using the documented DFU sequence ported to IOKit/libusb, handling GD32 PID 0x1791.
6. Treat writes back to Oryx (JWT + undocumented mutations) as out of scope or experimental; ZSA offers no third-party auth.

## Critical claims (author-flagged)

| # | Claim | Source |
|---|---|---|
| 1 | GraphQL introspection is disabled; the server rejects __schema and __type. | POST https://oryx.zsa.io/graphql (earlier run), response saved in scratchpad/downloads/oryx-graphql/introspection.json and type_probe.json: "Field '__schema' doesn't exist on type 'Query'" |
| 2 | The client sends Authorization: Bearer <localStorage.jwtToken> and no cookies (credentials: same-origin to a cross-origin host). | configure.zsa.io/assets/index-xhNfd6BI.js (md5 34fbb4d676e5dd056e2acf1999f26dae) offset ~630961 (tB link) and ~631310 (new HttpLink({uri:"https://oryx.zsa.io/graphql",credentials:"same-origin"})) |
| 3 | compileRevision is a single synchronous mutation returning md5/altMd5/qmkVersion/build logs; there is no build-status polling. | index-xhNfd6BI.js offset ~637915 (document hB) and ~799354 (compile action awaits the mutation and then sets md5, buildErrorLog etc.); no pollInterval or subscription outside Apollo library code |
| 4 | Firmware download is GET https://oryx.zsa.io/firmware/<revisionHashId> (?alt=true for the alternate MCU, ?collate=true for Moonlander/Halfmoon); the user's file md5 equals revision.md5. | index-xhNfd6BI.js ~885766 (iG) and ~794765 (Revision.hexUrl); zsa/zapp@a1be758 zapp-oryx/src/lib.rs lines 186-197; scratchpad/downloads/oryx-firmware-endpoint/firmware-40xJ7M.bin md5 4d59bb3dba601672ecefd27e2641561c = layout.json revision.md5 |
| 5 | GET https://oryx.zsa.io/firmware/latest/KlgM7 returns {"latest":"40xJ7M"}; /firmware/latest/voyager/default returns {"latest":"B495Jd"}. | curl 2026-10-11, saved in scratchpad/downloads/oryx01-rest-probe/; endpoint pattern from zsa/zapp lib.rs lines 156-158 |
| 6 | Edits persist per key via updateKey(hashId=layer hashId, keyData=Key.serialize, position=key index), debounced 400 ms and only while the revision is editable (qmkVersion === null). | index-xhNfd6BI.js ~711194 (persistUpdate → mutation DB), ~694185 (DB document), ~794055 (Revision.editable) |
| 7 | Macros allow up to 24 steps (5 without an account and ackMacroRisks); the per-step delay defaults to 100 ms with a UI range of 0-5000 ms. | configure.zsa.io/assets/index-Bvxi2_Kp.js offsets 117356 (pf=24, Ve=5) to 121709; delay input defaultValue:100, min:0, max:5e3; index-xhNfd6BI.js ~751530 (gC=100) |
| 8 | Combos require 2 to 6 keys; the trigger is a full Key snapshot saved with upsertCombo. | index-xhNfd6BI.js ~632250 (kw=2, rg=6), ~632260 (Nw model and persistUpdate) |
| 9 | revision.config is sparse: a value equal to its default is deleted (except flowTap); tappingTerm > 500 auto-enables permissiveHold. | index-xhNfd6BI.js Hw model ~677679, actions ~679900 (setter c()) |
| 10 | The key catalog is loaded from /metadata.json: 2,526 keys in 61 categories with per-OS label/glyph resolution. | index-xhNfd6BI.js ~695804 (BB="/metadata.json") and ~696009 (jB); https://configure.zsa.io/metadata.json etag 513e874d0de2797707bf77682043087a |
| 11 | Stored layouts use modern QMK names while the catalog uses legacy names; a 298-entry alias map (stored → catalog) bridges them, and unknown codes are rewritten to KC_TRANSPARENT. | index-xhNfd6BI.js ~739359 (wh map) and ~745318 (KeyStep.afterCreate); verified against the codes used in oryx/layout.json and the 5 example layouts |
| 12 | Voyager layout index i equals QMK k<i>, the RGB LED index i and the jC[row][col] live-training index, for all 52 keys. | zsa/qmk_firmware@93b2b9ec firmware25 keyboards/zsa/voyager/keyboard.json lines 103-154 (rgb_matrix) and 163-214 (LAYOUT); index-xhNfd6BI.js ~867072 (jC); asserted by scratchpad/scripts/oryx01b/build_geometry2.py |
| 13 | Main-layer key 0 of the user's layout is tap KC_EQUAL / hold KC_ESCAPE. | scratchpad/oryx/layout-full.json, layers[0].keys[0] (asserted in build_geometry2.py) |
| 14 | Oryx draws the Voyager as a CSS grid of repeat(6,1fr) 1fr 3fr 1fr repeat(6,1fr) with 4px gaps and ±15%/30% column stagger, and thumb clusters rotated +30°/-30°. | configure.zsa.io/assets/index-Dfb1Qukz.css (md5 fbfc9e2986bbfe0c192d8f4322fcb7b5) rules .editor .voyager, .clusters, .left-cluster, .right-cluster, .half-row-left/right .key:nth-child; render order in Rocket-CfXlil5s.js ~31011 |
| 15 | Key colour coding: magic (more than one function) = #e1ebff light / #0a2d70 dark; modifier = #ebffe1 / #1a6111; macro #e0dbff; LED control #fff1ba; custom #ffbfa3; invalid #da2c2c. | index-Dfb1Qukz.css :root and [data-theme=dark] variables --key-*; Legend-LTsHAjDy.js legend texts; Key.cssClass at index-xhNfd6BI.js ~708663 |
| 16 | The primary button is Inter 18px, white on #d48f2e with padding 10px 15px and hover var(--link-color). | index-Dfb1Qukz.css rule .button{...background-color:#d48f2e;...font-size:18px;...padding:10px 15p...} |
| 17 | The WebUSB DFU flasher targets VID 0x3297 with PIDs 0x0791/0x1791/0x2000-0x2003 (plus ST 0483:DF11), flashes from 0x08002000 in 2048-byte pages, and uses DfuSe commands 0x21 (set address) and 0x41 (erase). | index-xhNfd6BI.js ~879827 (b1, g1, zj, ru=2048, S1=0x08000000, Kj=0x08040000, qj=0x08002000, Qj=0x08042000, request codes) and ~880215 (class $C methods) |
| 18 | The user's compiled .bin carries one DFU suffix ff ff 91 07 97 32 00 01 55 46 44 10 fd 09 4f 2e (PID 0x0791, VID 0x3297) at offset 65,788. | scratchpad/downloads/layout-bin/firmware.bin parsed with python3 -I (UFD search) |
| 19 | ZSA publishes only Voyager bottom-plate STLs (137.85 × 136.87 × 2.33 mm per half), not PCB or top-shell CAD. | https://zsa.io/voyager/printables (WebFetch 2026-10-11); https://www.zsa.io/assets/voyager/voyager_stl.zip (md5 07307400a967a833eed7aa1cf7d927b5) parsed by scripts/oryx01b/stl_probe.py; gh api orgs/zsa/repos (16 repos, none with hardware) |
| 20 | The Corne (crkbd) is open hardware (CC-BY-4.0) with a 42-key 3x6+3 QMK layout; its inner thumb is 1.5u tall and unrotated in QMK info.json. | gh api repos/foostan/crkbd (license CC-BY-4.0); qmk/qmk_firmware master keyboards/crkbd/info.json LAYOUT_split_3x6_3 (scratchpad/downloads/corne-qmk/info.json) |
| 21 | OAuth sign-in goes through https://oryx.zsa.io/auth/{twitter,github,google_oauth2} and returns an authToken that is exchanged with query authenticate(authToken){token user}. | configure.zsa.io/assets/sign-in-BCBZB8U0.js (href `${j}auth/...`), callback-DlFrykU-.js, index-xhNfd6BI.js ~900501 (vG document) |

## Open questions

- What are the server-side enum values for TrackingEvent and LayerReorderDirection? Only client usage was observed (training/download_hex/download_zip; left/right/beginning/end).
- Does createLayout(parentHashId = own layout) always append a draft revision to the same layout for the owner, and fork for everyone else? This is implied by the client branch A==e.layoutId and was not tested.
- Does the server normalise legacy catalog names (KC_LCTRL) to modern names (KC_LEFT_CTRL) on updateKey? This is implied by stored data and was not tested.
- How does the Oryx code generator emit the 18 oryx-custom and 464 oryx-locale-alias codes? Only RGB_SLD, HSV_*, ST_MACRO_*, DUAL_FUNC_* and the KC_PC_UNDO i18n.h define were seen in the generated sources.
- Does /firmware/<rev> ever return a combined STM32+GD32 image for GD32 Voyagers (PID 0x1791)? The user's image is STM32-only.
- The pixel grid model is derived from CSS and was not rendered (Chrome tools were off-limits); the `height:2%` thumb-key rule is assumed negligible.
- Is the real thumb-cluster angle 30° (Oryx render) or 35° (community Vial KLE)? ZSA publishes no top-shell or PCB CAD.
- What is the licence of the oryx icon font (oryx-BM0RGHzK.ttf), and may Sextant redistribute it? If not, map the glyph names to SF Symbols.
- The final report could not be written as study/01-oryx-internals.md because the harness blocked report .md files. Should the orchestrator render keyFindings into that file?

## Artifacts

- `docs/research/data/oryx-keycodes.json`
- `docs/research/data/voyager-geometry.json`
- `docs/research/data/oryx-design-tokens.json`
- `docs/research/data/oryx-config-settings.json`
- `docs/research/data/oryx-graphql-operations.json`
- `docs/research/data/oryx-schema.reconstructed.graphql`
- `docs/research/oryx-examples/voyager-default.json`
- `docs/research/oryx-examples/voyager-JRGQm.json`
- `docs/research/oryx-examples/voyager-m9dpx.json`
- `docs/research/oryx-examples/voyager-e5Rrr.json`
- `docs/research/oryx-examples/voyager-XlrR4.json`
- `scratchpad/oryx/layout-full.json`
- `scratchpad/downloads/oryx-web/assets`
- `scratchpad/downloads/oryx-web/metadata.json`
- `scratchpad/downloads/oryx01-rest-probe`
- `scratchpad/downloads/voyager-shell-stl`
- `scratchpad/downloads/corne-qmk`
- `scratchpad/work/oryx01b/gql_all.json`
- `scratchpad/work/oryx01b/bundle-manifest.tsv`
- `scratchpad/work/oryx01b/tbl_ops.md`
- `scratchpad/work/oryx01b/tbl_geometry2.md`
- `scratchpad/work/oryx01b/tbl_categories2.md`
- `scratchpad/work/oryx01b/tbl_settings2.md`
- `scratchpad/scripts/oryx01b`

## Independent verification

I checked 21 claims against primary sources: 12 confirmed, 9 partially correct, none refuted. About 18 requests went to ZSA, all read-only. The live configure.zsa.io bundles are byte-identical to the ones the author analysed (index-xhNfd6BI.js md5 34fbb4d6…, CSS fbfc9e29…, macro chunk 2af293f8…), so the bundle offsets hold. Confirmed claims cover the endpoint and auth model, synchronous compileRevision, the combo and config rules, the metadata catalog, the 52-key index identity (Oryx index = k<i> label = RGB index = jC[row][col]), and the CSS geometry and colours.

The most consequential correction is in the firmware claims. The md5 4d59bb3d… cited for revision 40xJ7M is stale. The revision was recompiled around 2026-10-11 00:01Z and is now 4f0376c0…. The only source change was the random-looking filler keycode in `DUAL_FUNC_0 LT(15, KC_1)` → `LT(15, KC_F)`, so the binary bytes and DFU suffix CRC change without any layout edit. Oryx's own flasher computes the md5 but never enforces it.

Other corrections:
- The 0x08002000 start address applies only to the Ignition bootloader; ST DFU devices flash from 0x08000000. The Voyager image is extracted by scanning for the first matching DFU suffix, and every 2048-byte write is SET_ADDRESS then DNLOAD with wValue=2.
- Revision.editable also depends on embed mode and compiling, not just qmkVersion === null.
- The macro step gates are \"not signed in OR not acknowledged\", and the 24 cap only blocks the append button.
- The alias map leaves tap/hold codes unchanged and rewrites only macro-step codes.
- The STL plate thickness is 2.32 mm, and ZSA does publish other hardware files (a Voyager leg STL, ErgoDox schematics).
- crkbd ships both a CC-BY-4.0 and an MIT licence file.

The report file 01-oryx-internals.md does not exist, so I did not append to it, and subagent rules stop me from creating it. This structured output is the verification record.

| # | Claim | Verdict | Evidence | Correction |
|---|---|---|---|---|
| 1 | GraphQL introspection is disabled; the server rejects __schema and __type. | **confirmed** | Re-probed live on 2026-10-11 with POST https://oryx.zsa.io/graphql {__schema{queryType{name}}}. The response was {"errors":[{"message":"Field '__schema' doesn't exist on type 'Query'",..."code":"undefinedField"}]}, saved as downloads/factcheck-01/intro1.json. The earlier saved introspection.json and type_probe.json say the same thing for __schema and __type. A plain {__typename} query still works and returns {"data":{"__typename":"Query"}} (typename.json). |  |
| 2 | The client sends Authorization: Bearer <localStorage.jwtToken> and no cookies (credentials: same-origin to a cross-origin host). | **confirmed** | The live index-xhNfd6BI.js has md5 34fbb4d676e5dd056e2acf1999f26dae, which matches the author's copy. Near offset 631334: tB=new Ii(...nt.getItem("jwtToken")...{Authorization:`Bearer ${n}`}) and iB=new AO({uri:"https://oryx.zsa.io/graphql",credentials:"same-origin"}). The link chain is GN([tB,nB,rB,iB]). The server's CORS headers contain only access-control-allow-origin: https://configure.zsa.io, with no allow-credentials header. One nuance: nt is a localStorage wrapper that falls back to an in-memory map when storage is unavailable. |  |
| 3 | compileRevision is a single synchronous mutation returning md5/altMd5/qmkVersion/build logs; there is no build-status polling. | **confirmed** | Offset 637958: hB = mutation($hashId){compileRevision(hashId){md5 altMd5 qmkVersion qmkUptodate buildErrorLog buildSource buildConfig buildRules}}. The compile action at offset 799582 runs four steps in order: clearTapOnlyKeys on every layer, healTrigger on every combo, setting a default title if it is empty, then awaiting xe.mutate(hB) and assigning the results. The only pollInterval and startPolling references are inside the Apollo library (offsets 584856-605262). The action also destructures hasDeletedLayers, which the selection does not request, so it is always undefined. A 10 s setInterval does exist (H7=1e4), but it drives saveLayoutSnapshot retries, not build status. |  |
| 4 | Firmware download is GET https://oryx.zsa.io/firmware/<revisionHashId> (?alt=true for the alternate MCU, ?collate=true for Moonlander/Halfmoon); the user's file md5 equals revision.md5 (4d59bb3d...). | **partially-correct** | The endpoints match zsa/zapp@a1be75837323001ad1ae8e5787d88cd33f2ccc46 zapp-oryx/src/lib.rs lines 183-197 (fetched raw), iG near offset 885869 (`"https://oryx.zsa.io/firmware/"+e; n&&(r+="?alt=true")`) and Revision.hexUrl near offset 794765 (?collate=true for moonlander/halfmoon). Live GET /firmware/40xJ7M at 2026-10-11 00:09Z returned 200 with 65,804 bytes, but the md5 was 4f0376c0cf280fdc21e3df5b189685e9. Re-running the same read-only getLayout query now also returns revision.md5 4f0376c0…, with layers and config byte-identical to oryx/layout.json. The old file is still 4d59bb3d…. The two binaries differ in only 6 bytes. | The rule "downloaded bin md5 == revision.md5" holds, but the value 4d59bb3d… is stale. Revision 40xJ7M was recompiled around 2026-10-11 00:01Z (zip entry timestamps). The fresh /source/40xJ7M zip shows the only source change is keymap.c line 17, from `#define DUAL_FUNC_0 LT(15, KC_1)` to `LT(15, KC_F)`. The generator's filler keycode for dual-function keys is not stable, so md5 can change for the same revisionId without any layout edit. Two more points. ?collate=true is only added by the Revision.hexUrl download link; the web flasher iG never uses it. iG computes md5 but throws the result away (`return t==Dc(s),Promise.resolve(s)`), so Oryx does not actually verify the file. |
| 5 | GET https://oryx.zsa.io/firmware/latest/KlgM7 returns {"latest":"40xJ7M"}; /firmware/latest/voyager/default returns {"latest":"B495Jd"}. | **confirmed** | Live curl on 2026-10-11 around 00:09Z returned {"latest":"40xJ7M"} and {"latest":"B495Jd"}, saved in downloads/factcheck-01/latest-*.json. The URL patterns match zsa/zapp@a1be758 zapp-oryx/src/lib.rs lines 155-159. |  |
| 6 | Edits persist per key via updateKey(hashId=layer hashId, keyData=Key.serialize, position=key index), debounced 400 ms and only while the revision is editable (qmkVersion === null). | **partially-correct** | Offset 694258: DB = mutation($hashId,$key:Json!,$position:Int!){updateKey(hashId,keyData:$key,position){status}}. Offset 711194: persistUpdate sends {hashId: Wn(e,2).hashId (grandparent = Layer), key: e.serialize, position: e.index} only if G.editable. It is triggered by Hc(e,Xh(cb,400)). Hc is MST onPatch (offset 338332) and Xh is lodash.debounce. Patches on paths in UB are skipped: /glowColor, /setLockGlowColor, /swapping, /swapped, /customLabelEditing, /history, /tappingTerm, /pristine. Detached nodes are skipped too. | Revision.editable (offset 794055) is `isEmbed ? false : (qmkVersion === null \|\| compiling === true)`, not simply qmkVersion === null. Per-key tappingTerm does not go through the debounced patch path; it is persisted explicitly by updateTappingTerm, which also propagates to duplicate LT/ModTap keys. |
| 7 | Macros allow up to 24 steps (5 without an account and ackMacroRisks); the per-step delay defaults to 100 ms with a UI range of 0-5000 ms. | **partially-correct** | index-Bvxi2_Kp.js (md5 2af293f8b985a78bedcb9bccf209befb, live = saved) defines pf=24 and Ve=5. The flags are g=(user.ackMacroRisks==false && h>=5) and y=(!user.logged && h>=5). The "Add another step" button appears when h<5, or when 5<=h<24 and neither gate applies. The delay input is {defaultValue:100,min:0,max:5e3,unit:"ms"} and is hidden when macro.applyAlt is set. In index-xhNfd6BI.js, gC=100 is the model default for MacroStep.delay (offset 751523). | The 5-step gate applies when the user is not signed in (a sign-up prompt is shown) OR is signed in with ackMacroRisks==false (an acknowledge button calls the acknowledgeMacroRisks mutation). The original wording joins these with "and", which is wrong. The cap of 24 only applies to the append button. The insert link "Add a step here", shown between steps, has no count check, so the UI can probably exceed 24 (INFERRED). The 24 limit is client-side UI; no server or firmware limit was verified. |
| 8 | Combos require 2 to 6 keys; the trigger is a full Key snapshot saved with upsertCombo. | **confirmed** | Near offset 632250: kw=2, rg=6. toggleKeyIndex only pushes while keyIndices.length<rg. isDraft = !name \|\| keyIndices.length<2 \|\| trigger.isBlank, and drafts are never persisted. The trigger field is _.late(()=>ag) where ag=_.model("Key",{glowColor,lockGlowColor,customLabel,icon,emoji,tap,hold,doubleTap,tapHold,...}). Saving calls upsertCombo(revisionHashId, comboIdx (null when new), name, layerIdx, keyIndices, trigger) through a 400 ms debounced onPatch. deleteCombo and reorderCombos(sequence) are separate mutations. |  |
| 9 | revision.config is sparse: a value equal to its default is deleted (except flowTap); tappingTerm > 500 auto-enables permissiveHold. | **confirmed** | The setter c(y,v) at offset 679500-682900 does: if any settings-catalog entry has key===y and default===v, then g[y]=undefined (except flowTap, which is kept). If y==='tappingTerm' && v>500 and permissiveHold is not already set, it sets permissiveHold=true and records that with a volatile flag; a later tappingTerm<=500 turns it off again only if it was auto-enabled. Other coupled rules: audioClick and audioDisable are mutually exclusive; autoshift is tied to its three sub-flags; ambidexLT=false clears preceded keys; chordalHold sets chordalHoldExcludeThumbs. configData drops undefined values and 'pristine' and is sent via updateRevisionConfig(hashId, config) with a 400 ms debounce. The user's live config is just {"qmkCanary":true}. |  |
| 10 | The key catalog is loaded from /metadata.json: 2,526 keys in 61 categories with per-OS label/glyph resolution. | **confirmed** | The live https://configure.zsa.io/metadata.json has etag "513e874d0de2797707bf77682043087a" and md5 4bcbfb14582266b6d6a4cd601d6e330f, identical to the saved copy. It contains keys[2526] (all codes unique, 0 deleted) and categories[61]. BB="/metadata.json" is at offset 695804, and jB applies t.os[vn] or t.os.others to label and glyph, then filters out deleted entries. Only 10 keys carry an os map, using the keys osx, win, linux and others. |  |
| 11 | Stored layouts use modern QMK names while the catalog uses legacy names; a 298-entry alias map (stored → catalog) bridges them, and unknown codes are rewritten to KC_TRANSPARENT. | **partially-correct** | I parsed wh at offset 739359 and got exactly 298 unique entries; 296 targets exist in the catalog, while KC_PWR→KC_POWER and SE_AE→SS_ADIA do not. In the user's layout, 95 of 111 unique codes match the catalog directly, 15 go through the alias map (e.g. KC_BSPC→KC_BSPACE, KC_LEFT_SHIFT→KC_LSHIFT, QK_BOOT→RESET, KC_PGDN→KC_PGDOWN), and 0 are unknown. The 5 example layouts show the same pattern. | Stored layouts mix naming styles: most codes match the catalog directly, and only a minority need the map. In KeyStep.afterCreate (offset 750408) the stored code is NOT rewritten; only keyData is resolved through the alias. Macro steps (nv.afterCreate, offset 752035) DO rewrite code to the alias target. A code becomes KC_TRANSPARENT if neither the code nor its alias target is in the catalog, so a stored KC_PWR would be silently wiped (INFERRED from code path). |
| 12 | Voyager layout index i equals QMK k<i>, the RGB LED index i and the jC[row][col] live-training index, for all 52 keys. | **confirmed** | Fetched zsa/qmk_firmware@93b2b9ec3368f86c5eb5a2e3f934049f8daef885 (current firmware25 head) keyboards/zsa/voyager/keyboard.json. The rgb_matrix.layout entries are on lines 103-154 and LAYOUT entries on lines 163-214. For each label k<n>: the RGB entry at index n has the same matrix, and jC[row][col]==n holds for all 52 keys (jC is at offset 867072 and is indexed jC[M][C] with C=col, M=row from the HID packet). The user's layers[0].keys are 0-25 left half and 26-51 right half (keys[6]=KC_TAB, keys[26]=KC_6). | There is one caveat the implementer must not miss. The LAYOUT()/LAYOUT_voyager() argument order in keymap.c interleaves the halves row by row: [0-5, 26-31, 6-11, 32-37, 12-17, 38-43, 18-23, 44-49, 24, 25, 50, 51]. So 'k<i>' means the label, not the macro argument position. |
| 13 | Main-layer key 0 of the user's layout is tap KC_EQUAL / hold KC_ESCAPE. | **confirmed** | oryx/layout.json, oryx/layout-full.json and a live re-fetch all give layers[0].keys[0] = tap KC_EQUAL, hold KC_ESCAPE. The generated keymap.c compiles it as `DUAL_FUNC_0` = LT(15, <filler>), with process_record_user registering KC_EQUAL on tap and KC_ESCAPE on hold (keymap.c lines 17 and 130-142). |  |
| 14 | Oryx draws the Voyager as a CSS grid of repeat(6,1fr) 1fr 3fr 1fr repeat(6,1fr) with 4px gaps and ±15%/30% column stagger, and thumb clusters rotated +30°/-30°. | **confirmed** | Live index-Dfb1Qukz.css (md5 fbfc9e2986bbfe0c192d8f4322fcb7b5) contains: .editor .voyager{padding:15px;display:grid;grid-template-columns:repeat(6,1fr) 1fr 3fr 1fr repeat(6,1fr);grid-template-rows:repeat(4,1fr) 2fr;column-gap:4px;row-gap:4px}. On the left half, nth-child(3) and (5) get translateY(-15%) and (4) gets -30%. On the right half, (2) and (4) get -15% and (3) gets -30%. .clusters spans grid-column 6 / span 5 with column-gap 10% and margin-top 8%. .left-cluster is rotate(30deg) and .right-cluster rotate(-30deg), with popovers counter-rotated. Rocket-CfXlil5s.js (saved copy, md5 9a64356f…) at offset 31011 renders the rows as L0-5 \| navigator-left, logo, navigator-right \| R26-31, then L6-11\|R32-37, L12-17\|R38-43, L18-23\|R44-49, then clusters [24,25] and [50,51]. |  |
| 15 | Key colour coding: magic = #e1ebff / #0a2d70; modifier = #ebffe1 / #1a6111; macro #e0dbff; LED control #fff1ba; custom #ffbfa3; invalid #da2c2c. | **confirmed** | CSS :root defines --key-magic #e1ebff, --key-modifier #ebffe1, --key-macro #e0dbff, --key-shine #fff1ba, --key-custom #ffbfa3 and --key-danger #da2c2c. [data-theme=dark] defines magic #0a2d70, modifier #1a6111, macro #654598, shine #877100, custom #7c3e04 and danger #8d081c. Key.cssClass (offset 708663) picks the first match in this order: danger (conflictual) > disabled (preceded) > magic > modifier > macro > shine > custom. isMagic means having hold, doubleTap or tapHold while not tap-only or hold-only; isShine means tap.keyData.category==='shine'. A --key-dual-function variable (#ffd1f7) exists but cssClass never emits it. |  |
| 16 | The primary button is Inter 18px, white on #d48f2e with padding 10px 15px and hover var(--link-color). | **confirmed** | The rule is .button{font-family:Inter,sans-serif;color:#fff;background-color:#d48f2e;font-size:18px;line-height:1em;border:1px solid transparent;padding:10px 15px;transition:background-color .4s ease-in-out}. There are two .button:hover rules: #bfbfbf at byte 15275 and var(--link-color) at byte 38480. The later one wins, so hover is #008cba in light mode and #5ac5e0 in dark mode. .button:hover:disabled keeps #d48f2e. |  |
| 17 | The WebUSB DFU flasher targets VID 0x3297 with PIDs 0x0791/0x1791/0x2000-0x2003 (plus ST 0483:DF11), flashes from 0x08002000 in 2048-byte pages, and uses DfuSe commands 0x21 (set address) and 0x41 (erase). | **partially-correct** | Offset 880056: b1 = 0483:DF11 plus VID 12951 (0x3297) with PIDs 1937 (0x0791), 6033 (0x1791) and 8192-8195 (0x2000-0x2003). g1 (Ignition STM32) = 0x0791 and 0x2000-0x2003; zj (GD32) = 0x1791. ru=2048, S1=0x08000000, Kj=0x08040000, qj=0x08002000, Qj=0x08042000, eG=0x21, tG=0x41. flash() is at offset ~884000. | 0x08002000 (limit 0x08042000) applies only to Ignition-bootloader PIDs. A plain ST DFU device (0483:DF11) is flashed from 0x08000000 (limit 0x08040000). The byte-level sequence is: (1) erase with 0x41 + LE32 address every 2048 B, from start to start+len+2048, plus another 2048 if that fits under the limit; (2) for each 2048-byte chunk, send SET_ADDRESS (0x21 + LE32), then DFU_DNLOAD with wValue=2 and wIndex=0, then poll GETSTATUS until state 5; (3) leave with a zero-length DNLOAD followed by GETSTATUS. For voyager with qmkVersion != "24.0" (_doubleCompilation), the image comes from scanning for the FIRST DFU suffix whose PID is in g1. STM32 Ignition takes the bytes before it. GD32 (0x1791) takes the bytes after it and strips a trailing 0x1791 suffix. PID 0x2003 sets requiresAltFirmware, which fetches ?alt=true. |
| 18 | The user's compiled .bin carries one DFU suffix ff ff 91 07 97 32 00 01 55 46 44 10 fd 09 4f 2e (PID 0x0791, VID 0x3297) at offset 65,788. | **partially-correct** | I parsed the file with python3 -I (scripts/fc01/suffix.py). layout-bin/firmware.bin (md5 4d59bb3d…) has exactly one suffix at 65788: bcdDevice 0xFFFF, PID 0x0791, VID 0x3297, bcdDFU 0x0100, 'UFD', bLength 0x10, CRC 0x2e4f09fd. The stored CRC equals ~crc32(bytes[0:65800]), i.e. CRC-32 without the final XOR. The vector table holds SP 0x20000400 and Reset 0x080022BD, so the image is linked for 0x08002000. | This is true of the old build only. The current build (md5 4f0376c0…) has the same layout at the same offset, but its CRC bytes are 76 c4 6e ac. The last 4 bytes change with every recompile, so an implementation must not hardcode them. |
| 19 | ZSA publishes only Voyager bottom-plate STLs (137.85 × 136.87 × 2.33 mm per half), not PCB or top-shell CAD. | **partially-correct** | voyager_stl.zip (md5 07307400…) contains only bottom_plate_left.STL and bottom_plate_right.STL, both dated 2023-07-19 and binary (12114 and 12092 facets). Their bounding box is 137.8496 × 136.8683 × 2.3179 mm. https://www.zsa.io/voyager/printables (fetched 2026-10-11) links /assets/voyager/voyager_stl.zip and describes it as "the STL file for the shell of the unit". The same page also links /assets/printables/voyager-printable-leg.stl. gh api orgs/zsa/repos returns 16 repos, and zsa/docs contains ErgoDox EZ schematic PDFs. | The thickness is 2.32 mm, not 2.33. ZSA also hosts a Voyager leg STL. The statement that none of the ZSA repos contain hardware is wrong for ErgoDox EZ (zsa/docs has its schematics). It is still true that nothing for the Voyager PCB or top shell is published. |
| 20 | The Corne (crkbd) is open hardware (CC-BY-4.0) with a 42-key 3x6+3 QMK layout; its inner thumb is 1.5u tall and unrotated in QMK info.json. | **partially-correct** | gh api repos/foostan/crkbd reports license CC-BY-4.0, but the repo root has both LICENSE_CC (Attribution 4.0 International) and LICENSE_MIT ("Copyright (c) 2023 foostan", last changed in commit 3658b4753a on 2023-12-15), and the README states no licence. The repo publishes pcbs/ (common, corne-cherry, corne-chocolate) and cases/ (3x5, 3x6). In qmk/qmk_firmware@7a1bbf37c5c07da4ea0a162bb139083a46ef40a1 keyboards/crkbd/info.json, LAYOUT is an alias of LAYOUT_split_3x6_3 (42 keys). Only the matrix [3,5] and [7,5] keys have h:1.5, with no r/rx/ry. There is also LAYOUT_split_3x5_3 (36 keys), and the USB VID is 0x4653. | The repo is dual-licensed by file (CC BY 4.0 and MIT). It is probably CC for the hardware and MIT for the code, but that split is INFERRED, since nothing in the repo states which applies to what. |
| 21 | OAuth sign-in goes through https://oryx.zsa.io/auth/{twitter,github,google_oauth2} and returns an authToken that is exchanged with query authenticate(authToken){token user}. | **confirmed** | In sign-in-BCBZB8U0.js, const j="https://oryx.zsa.io/" and the hrefs are `${j}auth/twitter`, `${j}auth/github` and `${j}auth/google_oauth2`. callback-DlFrykU-.js reads l.search.authToken and calls user.authenticate(t), then follows force2faSetup or force2faChallenge redirects. vG at offset 900544 is query($authToken){authenticate(authToken){token user{...UserData}}}. A loginWithEmail(email,password){token user} query also exists. |  |

### Omissions noted by the verifier

- The md5 of a revision is not stable. Recompiling the same revisionId with identical layers and config changed the binary, because the generator's filler keycode for dual-function keys changed (`DUAL_FUNC_0 LT(15, KC_1)` became `LT(15, KC_F)`). This changed revision.md5 and the suffix CRC. The app must not cache md5 per revisionId. It should fetch md5 together with the binary and re-check after any compile.
- Oryx's web flasher does not verify the firmware. iG computes the md5 and then discards the result (`return t==Dc(s),Promise.resolve(s)`). A native app should verify the binary against revision.md5 (or altMd5 for ?alt=true) and validate the DFU suffix CRC (~crc32 over everything before the CRC field) before flashing.
- There is a network-failure fallback store (wC). When a mutation fails on an editable revision, the layout hash is queued in unsyncedRevisions. Every 10 s (H7=1e4) a sync loop sends saveLayoutSnapshot(layout: Json!) with the whole serialized layout. A toast appears after 5 network errors (G7=5).
- Client error telemetry: a window.onerror handler batches errors and POSTs them to "https://oryx.zsa.io//error-report" (with the double slash). Analytics events go through mutation event(event: TrackingEvent!, payload: Json), e.g. 'training'.
- A compiled revision can only be edited by first calling createLayout(revisionHashId, title, parentHashId, geometry, mcuAlternate). The /new route uses it, and so does LayoutStore. When parentHashId is the user's own layout, the call returns the same layoutId with a new editable revision. The schema artifact lists this mutation, but the edit flow should be stated explicitly.
- Per-key tappingTerm is excluded from the debounced updateKey path. It is persisted by updateTappingTerm, which also rewrites duplicate LT/ModTap keys. A tapping term equal to the revision default (config.tappingTerm, otherwise 200) is stored as null.
- The user's revision has a right-hand Navigator trackpad (revision.navigators.right.kind='trackpad'). It is persisted through a separate mutation (revisionHash, navigators: Json) with a 400 ms debounce, and the build includes the zsa/navigator_trackpad module. Any feature list for this user's app needs to cover it.
- The user's layout stores hold-only keys (tap null, hold KC_LEFT_CTRL at index 18; hold KC_LEFT_GUI at index 25), and the generator compiles them as plain keycodes. Serialization and round-tripping must preserve the tap:null/hold:X form.
- The hexUrl that GraphQL returns is a Rails active_storage redirect: a 302 to a presigned DigitalOcean Spaces URL that expires after 604800 s. /firmware/<rev> serves the binary directly with a 200, and /source/<rev> serves the zip, which includes <name>.bin.md5 and build.log.
- Not re-verified: Legend-LTsHAjDy.js beyond the legend strings, and the live USB PID of the attached keyboard (ioreg and hidutil showed no USB devices from this sandbox). Rocket-CfXlil5s.js was checked only from the saved copy, not refetched.
- I did not append the '## Independent verification' section to the report: docs/research/data/01-oryx-internals.md does not exist, and subagent rules forbid creating report .md files. These results are returned here instead. Fresh evidence is in scratchpad/downloads/factcheck-01/ (index-live.js, index-live.css, Bvxi2_Kp.js, fw-40xJ7M.bin, layout-now.json, src-now/, voyager-keyboard.json, crkbd-info.json, zapp-lib.rs, metadata.json, wh.json) and the helper scripts are in scratchpad/scripts/fc01/.
