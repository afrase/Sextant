# 33. A slim native toolchain, sandboxed, instead of the build VM

Status: accepted, 2026-10-11. Supersedes the build backend of ADR 0018 and ADR 0021.

## Context
ADR 0018 made a Linux VM with a pinned Debian image the default build backend, estimated at about 1 GB. The user asked why a whole Debian image is needed for a compiler and left the choice to the lead. Measured on 2026-10-11 (HTTP HEAD and registry manifests, nothing downloaded):

| Piece | Download |
|---|---|
| VM kernel: Containerization's recommended source is the Kata release bundle, fetched whole for one `vmlinux` | 290.6 MB |
| VM init filesystem `ghcr.io/apple/containerization/vminit:0.49.0` | 69.3 MB |
| Arm GNU Toolchain 12.2.rel1, `arm-none-eabi`, Linux aarch64 host | 147.6 MB |
| Arm GNU Toolchain 12.2.rel1, `arm-none-eabi`, macOS arm64 host | 109.8 MB |
| python-build-standalone CPython 3.12.15, macOS arm64, stripped | 25.0 MB |
| `qmk` and its Python requirements (Pillow is the only native one) | 7.0 MB |
| GNU make 4.4.1 (Homebrew bottle, no dependencies) | 0.4 MB |
| ChibiOS at the fork's pin: 368.5 MB of files, 306 MB of them vendor headers for other chips | pruned to about 25–42 MB on disk |

Even a slimmed VM image pays about 360 MB for the kernel and init before any compiler. A Voyager build needs only the compiler, GNU make 4, Python with the `qmk` CLI (its makefiles call `qmk` for about 14 generators, and `qmk` refuses to start unless every package in `requirements.txt` is importable), and the firmware sources. `dfu-suffix` is not needed: the domain already writes and checks DFU suffixes (`FirmwareImage`).

## Decision
- **Native toolchain, one pinned set.** The setup step (spec §7.3) downloads Arm's 12.2.rel1 macOS toolchain (ZSA builds with 12.2.1 from the same release), CPython from python-build-standalone, the `qmk` wheels, GNU make 4.4.1 and the firmware sources at the fork's pinned commits. Every artifact is pinned by URL, byte size and SHA-256 in `ToolchainPins`; a larger response is cut off, a mismatch deletes the file, and nothing unverified is unpacked. Wheels install with `pip --no-index --no-deps` from the verified files only.
- **Pruned while unpacking** (`/usr/bin/tar` include and exclude patterns): the compiler keeps the Cortex-M4F hard-float libraries (STM32F303 and GD32F303 are both Cortex-M4F) and drops C++, GDB and docs; ChibiOS drops other vendors' headers, demos and tests.
- **Where it lives:** `~/Library/Caches/com.sextant.app/Toolchain`. QMK's makefiles don't handle spaces in paths, which rules out Application Support; the Caches folder is also left out of Time Machine, and everything in it can be downloaded again. A marker with the pins is written last, so an interrupted setup reads as not set up; verified downloads are kept for the retry.
- **Sandboxed builds:** every build runs under `sandbox-exec` (the mechanism Bazel and Nix use on macOS) with a profile that denies the network, denies writes outside the build's folders, and denies reads in the home folder outside the toolchain. A hostile layout that got past the generator's validation (ADR 0020) could neither read the user's files into the firmware nor send anything anywhere.
- **The DFU suffix is ours:** builds pass `DFU_SUFFIX=true` and Sextant appends the suffix with `FirmwareImage.withSuffix`, so the flasher's own checks cover it.
- **One setup at a time:** the composition root shares one installer between windows.
- The container backend, the Containerization package and the virtualization entitlement are removed, and Settings › Build no longer offers a choice.

## Consequences
- About 190 MB to download, estimated before the firmware tarballs are measured, instead of about 1.5 GB with the VM's kernel and init. No VM boot per build.
- The firmware tarballs' SHA-256s are recorded at the first approved download; until then setup refuses to run. GitHub archive checksums are stable by GitHub's 2023 commitment; a change fails closed.
- `sandbox-exec` is deprecated but still shipped and widely used. If it ever disappears, builds fail rather than run unsandboxed.
- Downloaded executables run outside a VM. They are pinned by hash and never quarantined, because URLSession in a non-sandboxed app doesn't quarantine downloads.
- The compiler build matches ZSA's release, not Debian's package build; outputs can differ in bytes while the code is the same.
- A smaller app: Containerization's dependency tree (gRPC, SwiftNIO and more) leaves the build.
