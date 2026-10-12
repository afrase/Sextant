# 37b. Shared model hooks: issue kinds, EditSession extensions, cap decoration

Status: accepted, 2026-10-12. Shares number 37 with ADR 0037 (pages, board pick mode and assign targets); v1 plan slice 0.2.

## Context
The v1 document features (tap dances and per-key terms, Macros, Combos, Changes, Heatmap) are built in parallel branches. Three spots would collide on every one of them:
- the exhaustive `LayoutIssue.Kind` switch in `KeyText.issueText`;
- `EditSession`'s private `edit` and `target`, which forced every new edit into EditSession.swift;
- `KeyCap`, which each board mode would have edited to draw its rings, badges and dimming.

Combo issues also had no locator: `.emptyCombo` carried `key: nil`, so two empty combos showed as one issue and the text couldn't say which. And `.tapDanceUnsupported` was dead, since the generator builds tap dances.

## Decision
- **Every v1 issue kind is declared now,** each with Sextant's own text: `macroStepNotTypable(step:code:)`, `comboKeyCount`, `duplicateComboTrigger`, `comboKeyTransparent`, `comboKeyTapDance`, `rollingNeighbors` (a warning), `notInTapDance` and `tappingTermIgnored` (a warning). No check raises them yet; each feature adds its own check function and one call line in `check`. Transparent and tap-dance combo keys are two kinds, so the text can say which. `.tapDanceUnsupported` is deleted.
- **`LayoutIssue.combo`** holds the combo's id. The existing combo checks set it, so each broken combo is its own issue, and the text names the combo: "Empty combo · Combo 3", or the combo's name when it has one.
- **`edit(_:select:_:)` and `target(_:_:)` are internal.** A feature puts its edits in `EditSession+<Feature>.swift` in SextantApplication. `EditorSelection.combo` holds the selected combo's id; the undo snapshot already carries the selection.
- **`KeyCapModel.decoration`** (`CapDecoration`) is plain data a board mode fills in: an opacity (unchanged keys 0.4, non-members 0.45), a 2 pt ring, a top-right badge, a top-left number and a fill. A badge or number is an SF Symbol name, a colour token and its words for VoiceOver ("plus.circle.fill", "3.circle.fill"). It is drawn like the issue badge: white shows through the symbol's cut-out.
- **Corner priority follows spec §4.8,** in `KeyCapModel.topRight`: issue > unknown code > badge > LED dot. The number has the top-left corner to itself. The plan's single chain (issue > diff > combo number > LED dot) put the combo number in the same corner; the spec gives it the other one. Rings: issue > decoration ring > layer ring. A decoration ring also hides the activator's halo, as an issue does.

## Consequences
- The defaults draw today's caps. Offscreen renders of both board snapshots and a row of caps, made before and after, match pixel for pixel. The renderer has its own run-to-run noise (up to 3 per channel), so the comparison was between runs in the same noise state.
- The board doesn't set decorations yet. Changes, Combos and Heatmap each set them where BoardView builds its cap models, and append a mark's `accessibilityText` to the cap's VoiceOver value. KeyCap.swift stays untouched.
- `Token` is now `Equatable` (light, dark and alphas), so `KeyCapModel` stays `Equatable` and an unchanged cap doesn't redraw.
- Slice 2.2 (multi-select) keeps `target(_:_:)` working next to its `targets()`, because extension files call it.
