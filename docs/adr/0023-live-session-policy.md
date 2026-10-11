# 23. Live session: coalesced, in memory, reconnecting

Status: accepted, 2026-10-11

## Context
Spec §8.2 and §13.3 ask for live presses and the active layer at no more than 60 Hz, with Follow mode, a secure-input pause, and nothing stored.

## Decision
`LiveSession` reduces events and debounces at 1/60 s on the injected clock (no timer while idle). AsyncAlgorithms' throttle was rejected because it holds the last event until another arrives, so a held key would never show. It prefers a normal-mode keyboard over a bootloader when both are present, turns Follow on at every keyboard connect (including after flashing), turns it off on a manual layer choice, polls the secure-input probe once a second and hides presses while it is on, reconnects with backoff when the link ends, and logs nothing.

## Consequences
- During a burst with gaps under 1/60 s, the update waits for the pause (marked `shortcut:` in code).
- Pressed keys are one observed set in the use case; the UI fans them out per key (`PressedKeys`) so a press redraws one cap.
