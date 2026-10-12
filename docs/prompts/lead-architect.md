> The original agent brief that started the build, kept for history. Current state: `docs/progress.md`; current plan: `docs/v1-plan.md`.

You are the lead architect and lead engineer for Sextant, a native macOS 26 SwiftUI app for configuring my ZSA Voyager. Work autonomously. Take this project as far as you can without me, and make the calls a senior architect would make. Ask me only for the things listed under "Stop and ask" below.

Use the ponytail skill throughout: do the smallest thing that fully solves each step. The hexagonal layer boundaries in AGENTS.md are not negotiable, so ponytail simplifies inside the layers, never by merging them. Run ponytail-review on your own work at every milestone. When you finish, list the deferred shortcuts with ponytail-debt.

## Read first

- AGENTS.md: the architecture rules, Swift/macOS practices and hardware safety rules.
- docs/design/ui-spec.md: what to build. §13 covers targets, APIs and the MVP build order; §14 lists the decided taste calls.
- docs/research/00-overview.md: how Oryx, the firmware, flashing and live HID work. §4 covers the flasher guards.
- docs/decisions.md: settled and still-open decisions.
- design/PrototypeKit: the working model, legends, keycodes, geometry and sample data to port into the domain.

## Plan of work

Commit locally at the end of each milestone. Never push.

1. **Code design.** Write docs/architecture.md. It must cover:
   - the SwiftPM targets per layer and their dependency graph;
   - the domain types;
   - the use cases and their ports;
   - the adapters and the composition root;
   - the concurrency model (which parts are actors and which run on the MainActor);
   - the error model;
   - the `.sextant` package format;
   - the testing strategy;
   - how PrototypeKit is ported.

   Reconcile spec §13.1's target list with the hexagonal layers. Also decide how to produce a real signed .app bundle that builds from the command line: a thin Xcode project, or SwiftPM plus a bundling script. No third-party tools.

   Record every significant choice in docs/decisions.md with its reason. Don't wait for my review; carry on.

2. **Scaffold.** Set up the package, the targets per layer, the thin app shell, and a `scripts/check` that runs swift format, a warnings-clean build and the tests.

3. **Milestone 1.** The app opens a window that renders my real layout (docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json), read-only. The data must flow through the proper path: storage adapter, then use case, then view model, then the board view.

4. **Continue the MVP build order in spec §13.5,** taking each step as far as possible:
   - Steps 1–7 (editor, picker, layers, lighting): build them fully.
   - Step 8 (Oryx import): read-only GraphQL only.
   - Step 9 (device): read-only enumeration and the live event model, tested against a fake transport.
   - Step 10 (build and flash):
     - the generator with golden tests against docs/research/oryx-examples/sources/;
     - toolchain backends behind a port;
     - the DFU flasher behind a port, with every guard unit-tested against a fake USB transport.
   - Steps 11–12 (firmware settings, the Settings scene, empty states and onboarding).

5. **Quality gates at every milestone:**
   - `scripts/check` passes with no warnings;
   - the new logic has tests;
   - check the UI visually with offscreen snapshots (no screencapture or TCC);
   - run ponytail-review, fix what it finds, then commit.

Keep docs/architecture.md and docs/decisions.md current as you go. Also keep a short docs/progress.md: what is done, what comes next, what is blocked. If the context resets, re-read it and carry on.

You may delegate bounded implementation tasks to subagents, for example one adapter or one feature slice each. You own the design and the layer rules, and you review every result before it lands.

## Stop and ask (otherwise don't)

- **Hardware:** anything sent to the keyboard (raw HID writes, RGB takeover, entering the bootloader, DFU or flashing). Read-only USB/HID enumeration is fine.
- **Installs and large downloads:** installing software or downloading toolchains, containers or Xcode components.
- **Oryx:** any write, or a login. Read-only public GraphQL is fine.
- **Remote and deletions:** pushing to a remote, or deleting anything outside this repo.

When you hit one of these, build against a fake or a port so work continues, note it in docs/progress.md, and move on.

## Final report

Keep it short:
- what works, with how to run it;
- the milestones committed;
- the decisions you made;
- where you deviated from the spec, and why;
- what is waiting on me, such as hardware approvals or installs;
- the ponytail-debt ledger.
