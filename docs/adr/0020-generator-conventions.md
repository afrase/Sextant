# 20. QMK generator conventions: refuse rather than guess, validate every token

Status: accepted, 2026-10-11

## Context
The generator turns layouts (often imported, so untrusted) into C that is compiled and flashed. Oryx's generator is closed; research 02 §4 specifies it empirically from five layouts. A background security review found the first version pasted keycodes and the serial into C unchecked.

## Decision
- **Validate every data-derived token** before it becomes C: codes must be C identifiers, the serial is pattern-checked, animation ids come only from the generator's own table, numbers are bounded integers, and no layout text (titles, labels, macro names) reaches the C. Anything else is a `GeneratorError`, never output.
- **Refuse rather than drop:** settings and Navigator options whose QMK output was never observed, the knob, macros or firmware keys inside dual-function keys or tap dances, missing layer targets and wrong key counts all stop the build with a message naming the key, rather than building something that silently differs.
- `keymap.c` lists **one key per line** inside `LAYOUT_voyager`, so the line-based source map points compiler errors at exact keys.
- MT/LT/`*_T` only when QMK can express the pair (basic tap, single-modifier or MO(0–15) hold); everything else is the DUAL_FUNC pattern. Placeholders, dances, macros and colour keys are numbered deterministically in Oryx's order.
- Colours: hue `round(h × 256) mod 256`, saturation and value × 255; Oryx differs by up to 2 hue steps, invisible on the LEDs.
- Golden tests compare all five Oryx samples after normalising whitespace, `//` comments and DUAL_FUNC placeholders, with three commented allowances for Oryx quirks; removing an allowance fails the test.

## Consequences
- Some layouts Oryx would build are refused until their output is observed; each refusal names the setting or key.
- The trackball output follows a December 2025 sample and is unverified against the pinned modules commit.
