# 37b. Shared model hooks: issue kinds, EditSession extensions, cap decoration

Status: accepted, 2026-10-12. v1 plan slice 0.2. The plan gives slices 0.1 and 0.2 one number, 37, and builds them in parallel, so this is the second half of ADR 0037 (pages, board pick mode and assign targets); the merger folds it into 0037.

## Context
The v1 document features (tap dances and per-key terms, Macros, Combos, Changes, History, Heatmap) are built in parallel branches. Three spots would collide on every one of them:
- the exhaustive `LayoutIssue.Kind` switch in `KeyText.issueText`;
- `EditSession`'s private members, which forced every new edit into EditSession.swift;
- `KeyCap`, which each board mode would have edited to draw its rings, badges, dimming and heat.

Combo issues also had no locator: `.emptyCombo` carried `key: nil`, so two empty combos showed as one issue and the text couldn't say which. And `.tapDanceUnsupported` was dead, since the generator builds tap dances.

## Decision
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

## Consequences
- The defaults draw today's caps. Seventeen board, window, inspector and picker scenes rendered offscreen from main and from this branch are identical, pixel for pixel. The existing snapshot references pass unchanged. A new snapshot of decorated caps, light and dark, pins the badge, number, ring, opacity, fill, count and ink.
- The board doesn't set decorations yet. BoardView belongs to slice 0.1 in wave 0, so its two lines come in at the 0.1 merge: `capModels()` applies a decoration source per key index, and the cap's `KeyText.value(…)` call passes `decoration: model.decoration`. Changes, Combos and Heatmap then fill in that source from their own files, and KeyCap.swift stays untouched.
- SF Symbols number circles only up to 50, so a combo numbered above 50 has no number symbol.
- `Token` is now `Equatable` (light, dark and alphas), so `KeyCapModel` stays `Equatable` and an unchanged cap doesn't redraw.
- Slice 2.2 (multi-select) keeps `target(_:_:)` working next to its `targets()`, because extension files call it.
