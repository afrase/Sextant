# Decisions

| # | Date | Decision | Notes |
|---|---|---|---|
| 1 | 2026-10-11 | Name: **Sextant** | Fine for development. A paid store release needs a distinct listing name and trademark clearance (research 00 §7). Don't name an SPM module exactly `Sextant`. |
| 2 | 2026-10-11 | Architecture: **local-first hybrid (d1)** | Sextant owns the layout document; read-only import from Oryx; generates QMK source and builds it locally against ZSA's fork (`firmware25`, keeping the `zsa/oryx` and Navigator modules); native Swift DFU flasher with hard safety guards; Oryx-compiled `.bin` as fallback. Oryx write-back and live-remap firmware are deferred behind explicit gates (00 §4). |
| 3 | 2026-10-11 | Minimum OS: **macOS 26** | Liquid Glass design language, current SwiftUI, Apple Containerization as the build backend. |
| 4 | 2026-10-11 | UI design scope: **design every surface, build in phases** | Editor, live layer/key view, menu bar item, floating overlay/HUD, heatmap and app-aware layers are all designed now. Build order: editor, then live view (MVP), then the rest (v1). |

UI taste calls: all nine decided 2026-10-11 (ui-spec §14).

Still open (00 §9): build-backend default (pending the Phase 0 spike), firmware identity/serial, licence and distribution, Phase 0 hardware approval.

## Future ideas (not scheduled)

- **Sync and backup server** (2026-10-11, the user's idea). An optional self-hosted Go server for layout and revision backups and multi-Mac sync. Details are in `design/brief.md`, surface 16. Its consequence for the MVP: the document model gets stable IDs and append-only, hashed history from the start.
- **Replacing the Ignition bootloader: not pursued.** It is possible in principle as a clean-room rewrite flashed over SWD. But it is the only path that can hard-brick the board, and it adds nothing Sextant needs, because Ignition already accepts any unsigned firmware. Revisit only as a hardware-lab project with an SWD probe.
