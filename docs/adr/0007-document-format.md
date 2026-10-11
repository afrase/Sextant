# 7. Document format: Oryx-shaped JSON in `.sextant` packages

Status: accepted, 2026-10-11

## Context
Spec §2.3 asks for a library of `.sextant` packages holding plain JSON, a lossless superset of Oryx's revision JSON, with stable ids and content hashes from day one. Import, storage and export all need to read or write layouts.

## Decision
- `KeyboardLayout`'s `Codable` conformance *is* Oryx's revision shape (`tap.code`, 8-boolean `modifiers`, sparse `config`, `navigators`, `combos`, `swatch`). One codec serves Oryx import, `layout.json` and Export ▸ Layout JSON. Nil fields are omitted on write.
- "Lossless" covers every field that reaches firmware or Sextant's display. Oryx's leaked UI state (`swapped`, `pristine`, `history`…) and display-only fields Sextant does not show (`icon`, `emoji`, `about`, `aboutPosition`, `tour`) are dropped on import.
- Package layout: `meta.json` (format version, UUID, origin, content hash), `layout.json`, append-only `revisions/NNNN-<hash>.json`, `firmware/<rev>.bin` + `.md5`.
- The content hash is SHA-256 of the canonical JSON, computed in the storage adapter (CryptoKit is not allowed in the domain).

## Consequences
- No second schema to keep in sync, and Oryx fixtures double as storage fixtures.
- Re-exporting to Oryx would lose icons and emoji; Sextant never writes to Oryx (decision 2), so this costs nothing today. Revisit if write-back is ever approved.
- Change detection in the UI uses value equality and `diff(from:)`, so the domain needs no hash function.
