# 13. Firmware checks: structure in the domain, md5 in the adapters

Status: accepted, 2026-10-11

## Context
The flasher guards (AGENTS.md, research 00 §4) are a DFU suffix with matching CRC, VID and PID, the address window, a vector-table sanity check and an md5 check. The domain may not import CryptoKit, and a hand-written MD5 is code nobody should maintain.

## Decision
`FirmwareImage.validate(forBootloaderPID:)` in the domain checks the suffix, CRC-32, VID/PID (refusing single images on `0x1791`), size and vector table. `OryxClient` verifies md5 at download; locally built images get their md5 recorded at build time; `DFUFlasher` verifies md5 and re-runs the domain validation for the connected PID before its first transfer. The address window and the MASS_ERASE ban are enforced inside `DFUFlasher` on every request.

## Consequences
- Every guard is checked twice (use case and flasher) and unit-tested in both places.
- The domain stays pure.
