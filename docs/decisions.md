# Decisions

The index of settled decisions. From decision 6 on, each has an ADR in [`adr/`](adr/README.md) with its context and consequences.

| # | Date | Decision | Notes |
|---|---|---|---|
| 1 | 2026-10-11 | Name: **Sextant** | Fine for development. A paid store release needs a distinct listing name and trademark clearance (research 00 §7). Don't name an SPM module exactly `Sextant`. |
| 2 | 2026-10-11 | Architecture: **local-first hybrid (d1)** | Sextant owns the layout document; read-only import from Oryx; generates QMK source and builds it locally against ZSA's fork (`firmware25`, keeping the `zsa/oryx` and Navigator modules); native Swift DFU flasher with hard safety guards; Oryx-compiled `.bin` as fallback. Oryx write-back and live-remap firmware are deferred behind explicit gates (00 §4). |
| 3 | 2026-10-11 | Minimum OS: **macOS 26** | Liquid Glass design language, current SwiftUI, Apple Containerization as the build backend. |
| 4 | 2026-10-11 | UI design scope: **design every surface, build in phases** | Editor, live layer/key view, menu bar item, floating overlay/HUD, heatmap and app-aware layers are all designed now. Build order: editor, then live view (MVP), then the rest (v1). |
| 5 | 2026-10-11 | Code architecture: **clean / hexagonal**, plus Swift and macOS best practices | Domain, then application (use cases and ports), then adapters (storage, Oryx, QMK build, USB DFU, raw HID), then a SwiftUI driving adapter, with the app target as the composition root. Layers are enforced as SwiftPM targets. Swift 6 strict concurrency, Observation, Swift Testing, os.Logger, and a thin app shell. The user's reason: this structure works well for AI-built projects. Details are in `CLAUDE.md`. |
| 6 | 2026-10-11 | Module layout: one target per layer or adapter group | [ADR 0006](adr/0006-module-layout.md). Reconciles spec §13.1 with decision 5. |
| 7 | 2026-10-11 | Document format: Oryx-shaped JSON in `.sextant` packages | [ADR 0007](adr/0007-document-format.md). One codec; display-only Oryx fields dropped; SHA-256 in storage. |
| 8 | 2026-10-11 | Domain data compiled in; visual tokens in code | [ADR 0008](adr/0008-no-resource-bundles-in-domain.md) |
| 9 | 2026-10-11 | UI-facing use cases are `@MainActor @Observable` | [ADR 0009](adr/0009-observable-use-cases.md). Selection lives in `EditSession`. |
| 10 | 2026-10-11 | Typed throws on ports and use cases | [ADR 0010](adr/0010-typed-errors.md) |
| 11 | 2026-10-11 | App bundle: SwiftPM plus `scripts/bundle`, no Xcode project | [ADR 0011](adr/0011-app-bundle.md) |
| 12 | 2026-10-11 | Hardware writes wired off until the user approves | [ADR 0012](adr/0012-hardware-gate.md) |
| 13 | 2026-10-11 | Firmware checks: structure in domain, md5 in adapters | [ADR 0013](adr/0013-firmware-integrity-split.md) |
| 14 | 2026-10-11 | ~~One process-based toolchain adapter, two configurations~~ (superseded by 18) | [ADR 0014](adr/0014-toolchain-backends.md). Containerization not adopted for now. |
| 15 | 2026-10-11 | Keys with no actions are transparent | [ADR 0015](adr/0015-null-keys-are-transparent.md). Deviates from spec §4.6, following Oryx's generated source. |
| 16 | 2026-10-11 | One String Catalog, resolved from the main bundle | [ADR 0016](adr/0016-string-catalog.md). `scripts/strings` syncs it. |
| 17 | 2026-10-11 | Boards are data: everything board-specific comes from `BoardDefinition` | [ADR 0017](adr/0017-boards-are-data.md). The user's future goal of more keyboards. |
| 18 | 2026-10-11 | Prefer community libraries and tools; container builds by default | [ADR 0018](adr/0018-libraries-and-tooling.md). Supersedes ADR 0014. SwiftLint, Periphery, Apple and Point-Free packages. |
| 19 | 2026-10-11 | Firmware serial: Oryx's when unchanged since import, else `sx:` fingerprint | [ADR 0019](adr/0019-firmware-identity.md). Resolves research 00 §9 item 4 for now. |
| 20 | 2026-10-11 | Generator: validate every token, refuse rather than guess | [ADR 0020](adr/0020-generator-conventions.md). Follows a security finding. |
| 21 | 2026-10-11 | Build VM: throwaway, offline, read-only Linux guest | [ADR 0021](adr/0021-build-vm.md) |
| 22 | 2026-10-11 | Device I/O policy for raw HID and DFU | [ADR 0022](adr/0022-device-io-policy.md) |
| 23 | 2026-10-11 | Live session: coalesced to 60 Hz, in memory, reconnecting | [ADR 0023](adr/0023-live-session-policy.md) |
| 24 | 2026-10-11 | Import over an existing layout: checkpoint first, keep the title | [ADR 0024](adr/0024-import-as-revision.md) |
| 25 | 2026-10-11 | Window minimums and board rendering | [ADR 0025](adr/0025-window-and-board-ui.md). Deviates from spec §3.2 ideals. |
| 26 | 2026-10-11 | One window per layout; quitting flushes open documents | [ADR 0026](adr/0026-one-window-per-layout.md). From the integration review. |
| 27 | 2026-10-11 | Key inspector: drag to swap as a gesture, chorded modifier holds, commit rules | [ADR 0027](adr/0027-key-inspector.md). Deviates from spec §13.2 (no `.draggable`). Since the merge the generator also builds Oryx's `ALL_T`/`MEH_T` holds in dual-function keys and tap dances, so the chording is a choice now, not a workaround. |
| 28 | 2026-10-11 | One floating panel for the palette and picker; positional Record Key | [ADR 0028](adr/0028-palette-picker-record-key.md). |
| 29 | 2026-10-11 | Layers and Lighting lens UI | [ADR 0029](adr/0029-layers-and-lighting-ui.md). Gesture gating corrected at merge. |
| 30 | 2026-10-11 | Import sheet, firmware settings storage, library management, app settings | [ADR 0030](adr/0030-import-settings-and-library-ui.md). Welcome, not an automatic default layout (the user's call). Since the integration review New Window has no shortcut (⌥⌘N is Legends ▸ Key Numbers, spec §9.1). |
| 31 | 2026-10-11 | Device and Build & Flash in the window | [ADR 0031](adr/0031-device-and-build-flash-ui.md). Since the integration review flash mode is claimed per run (`claimFlashMode(for:owner:)`), and quitting or closing a window waits while a flash writes. |
| 32 | 2026-10-11 | A recovery copy of every change until its autosave lands | [ADR 0032](adr/0032-recovery-copy.md). The user's request: never lose work. The window says when edits were restored. |
| 33 | 2026-10-11 | A slim native toolchain, sandboxed, instead of the build VM | [ADR 0033](adr/0033-native-sandboxed-toolchain.md). Supersedes the build backend of ADRs 0018 and 0021. The user asked why a whole Debian image; about 190 MB instead of about 1.5 GB with the VM's kernel and init. The lead's call, at the user's request. |
| 34 | 2026-10-11 | Separate switches for flashing and live access | [ADR 0034](adr/0034-separate-flashing-and-live-access.md). The user approved flashing only; with flashing off, Build & Flash stops before asking for flash mode. |
| 35 | 2026-10-11 | Choosing the Navigator, and trackball firmware for the pinned modules | [ADR 0035](adr/0035-choosing-the-navigator.md). The user's request: set a trackpad or trackball and its side, as Oryx does. A new kind keeps the options both kinds have; the automouse layer is the layout's (Oryx's layer flag) and outlasts None; a trackball sensitivity slider; the trackball builds with `zsa/navigator_trackball`, not e5Rrr's in-tree driver. |
| 36 | 2026-10-12 | Layer clicks respond at once: rename from the context menu, ease-out crossfade | [ADR 0036](adr/0036-layer-clicks-respond-at-once.md). The user's request: rename on right-click, not double-click. The double-click gesture held every click's selection about 360 ms. Supersedes ADR 0029's rename gesture. |

UI taste calls: all nine decided 2026-10-11 (ui-spec §14).

Still open (00 §9): build-backend default (pending the Phase 0 spike), firmware identity/serial, licence and distribution, Phase 0 hardware approval.

## Future ideas (not scheduled)

- **Sync and backup server** (2026-10-11, the user's idea). An optional self-hosted Go server for layout and revision backups and multi-Mac sync. Details are in `design/brief.md`, surface 16. Its consequence for the MVP: the document model gets stable IDs and append-only, hashed history from the start.
- **Replacing the Ignition bootloader: not pursued.** It is possible in principle as a clean-room rewrite flashed over SWD. But it is the only path that can hard-brick the board, and it adds nothing Sextant needs, because Ignition already accepts any unsigned firmware. Revisit only as a hardware-lab project with an SWD probe.
