# 15. Keys with no actions are transparent (deviates from spec §4.6)

Status: accepted, 2026-10-11

## Context
Spec §4.6 says keys Oryx stores with no tap and no hold (Brd+Sys keys 18 and 43 in the user's layout) render as Disabled with the tooltip "No action". Oryx's generated `keymap.c` for that revision emits `KC_TRANSPARENT` for both, so on the keyboard they fall through to the layer below.

## Decision
The codec stores an action-less key as `KC_TRANSPARENT`, and the board draws it as transparent with the inherited legend. The firmware is the source of truth when the spec and the generated source disagree.

## Consequences
- What the board shows matches what the keyboard does.
- One representation for "transparent", so diffs don't flag `null` → `KC_TRANSPARENT` as a change.
