# 14. One process-based toolchain adapter with two configurations

Status: superseded by ADR 0018 (container backend by default, packages allowed), 2026-10-11

## Context
Research recommends Apple Containerization (container image with ZSA's gcc 12.2.1) as the default and a managed native toolchain as the fallback. Containerization is a third-party package from the project's point of view, and both backends need large downloads, which need the user's approval.

## Decision
`ProcessToolchain` implements the `Toolchain` port by running a command in a per-build directory, streaming its output and parsing diagnostics and the size line. Two configurations: `.native(qmkHome:)` (`qmk compile` with GNU make 4 and arm-none-eabi on `PATH`) and `.container(image:)` (Apple's `container` CLI with a pinned image). The Containerization Swift package is not adopted. Tests use a fake process runner.

## Consequences
- No new dependency; both backends share one tested code path.
- Real builds stay blocked until the user approves installing a toolchain or the container image (tracked in `docs/progress.md`). Oryx's own binary remains the no-toolchain fallback.
- Revisit Containerization after the Phase 0 build spike.
