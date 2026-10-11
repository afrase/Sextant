# 10. Typed throws on ports and use cases

Status: accepted, 2026-10-11

## Context
CLAUDE.md asks for typed errors and `LocalizedError` for anything the user sees. The spec has an exact error catalog (§8.1, §12.6).

## Decision
Every port and use case declares a typed error enum (`LibraryError`, `OryxError`, `BuildError`, `ToolchainError`, `DeviceError`, `FlashError`) and uses Swift 6 typed throws (`throws(OryxError)`). Domain errors are `FirmwareImageError`, `OryxDecodingError` and `LayoutError`. Adapters map platform errors at the boundary. User-facing cases conform to `LocalizedError` with the spec's copy.

## Consequences
- Each error case is exhaustively handled in the UI, and the spec copy sits next to the case it describes.
- Adapters carry some mapping boilerplate (`do { … } catch { throw .io(…) }`).
