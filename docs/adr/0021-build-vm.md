# 21. The build VM: a throwaway, offline, read-only Linux guest

Status: accepted, 2026-10-11. Implements ADR 0018's container backend.

## Context
ADR 0018 makes container builds the default. The build compiles code generated from untrusted layouts, so it should be isolated, reproducible and leave nothing behind.

## Decision
`ContainerToolchain` uses Apple's Containerization 0.49.0 directly (SextantBuild only). Each build boots a throwaway VM on a pinned, read-only `rootfs.ext4` (Debian bookworm, gcc-arm-none-eabi 12.2.1, qmk, make, dfu-suffix), shares the pinned `qmk_firmware` checkout (fork `firmware25` @93b2b9e, modules @13890cd) over virtiofs, gives the build a tmpfs `/tmp` and a per-build `BUILD_DIR`, has no network, and stops on every exit path, cancellation included. `status()` checks for the kernel, init filesystem, root filesystem and pinned checkout, and never downloads. The app gains `com.apple.security.virtualization`. `NativeToolchain` (swift-subprocess) remains the fallback.

## Consequences
- A build can't reach the network or the user's files beyond the shared checkout and its keymap folder.
- The setup step that downloads and verifies the images is not built yet (no download without the user's go-ahead); until then every build reports "needs setup" and Oryx's own binary is the fallback.
- No VM has booted yet; the first real build is a hardware-free Phase 0 item.
