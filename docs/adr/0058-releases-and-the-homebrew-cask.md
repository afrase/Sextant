# 58. Releases from published GitHub releases, and a Homebrew cask in the user's tap

Status: accepted, 2026-10-15.

## Context
Sextant had no release builds: users built from source with `scripts/bundle`. The user wants a GoReleaser-like flow, "draft a release in github with a tag and it just publishes that tag", and an install through Homebrew from their existing tap, github.com/afrase/homebrew-tap (two formulae so far).

What the current tools allow (checked against Homebrew 7.0.9's own docs and GitHub's):
- GitHub runs no workflow for a draft release's `created`, `edited` or `deleted` events; `published` fires when a release (or a pre-release, including one published from a draft) is published.
- `brew install --cask afrase/tap/sextant` taps `afrase/homebrew-tap` itself and, since Homebrew 6's tap trust, trusts only that cask. The one-argument short form needs a repo named `homebrew-<name>`; a tap inside the Sextant repo would need `brew tap afrase/sextant https://github.com/afrase/Sextant` first, and would clone the app's whole history.
- Homebrew 5 removed `--no-quarantine`, and official casks must pass Gatekeeper. Sextant has no Developer ID, so its builds are signed ad hoc and not notarized; Gatekeeper refuses their first launch once downloaded.
- Homebrew 7 replaces Ruby `postflight` blocks with declarative `postflight_steps` (official taps reject the old blocks; third-party taps keep them only for now). Its `run` step calls one executable with literal arguments and expands `{{appdir}}`.

## Decision
- **The trigger is a published release.** `.github/workflows/release.yml` runs on `release: published` (and by hand, for an existing release's tag). It refuses a tag that isn't `vX.Y.Z` or `vX.Y.Z-suffix`, checks out that tag with full history, runs `scripts/check`, builds with `SEXTANT_VERSION` from the tag, and attaches `Sextant-X.Y.Z.zip` and its `.sha256` to the release (`gh release upload --clobber`, so a rerun replaces them). The user writes the notes in GitHub's release form (Generate release notes covers the changelog); nothing else needs a tool like GoReleaser.
- **The cask lives in the user's tap**, `Casks/sextant.rb`, generated from `packaging/homebrew/sextant.rb` in this repo (so the cask changes with the code that needs it). The workflow fills in the version and checksum and pushes to `afrase/homebrew-tap` with a `HOMEBREW_TAP_TOKEN` secret (a fine-grained token with Contents read and write on that one repo). Without the secret, or for a pre-release, the cask is left alone. Install: `brew install --cask afrase/tap/sextant`.
- **The cask clears the quarantine flag itself** with a `postflight_steps` `run` of `/usr/bin/xattr -dr com.apple.quarantine {{appdir}}/Sextant.app`, which is what `--no-quarantine` did. Installing from the user's own tap stands in for Gatekeeper's first-launch check. It requires Apple silicon (the build tools Sextant downloads are arm64) and macOS 26.
- **Signing stays ad hoc** until there is a Developer ID; `scripts/bundle` already signs with `SEXTANT_SIGN_IDENTITY` and `scripts/notarize` notarizes, so a signed, notarized release later changes only the workflow's environment and drops the quarantine step.

## Consequences
- Releasing is: Draft a new release, choose a new `vX.Y.Z` tag on `main`, generate notes, Publish. The zip and checksum appear on the release a few minutes later, and the cask follows.
- The workflow's environment, not the tag, is trusted: tag names are validated before checkout, and every value reaches the shell through environment variables.
- A downloaded zip opened by hand still meets Gatekeeper (System Settings › Privacy & Security › Open Anyway); the README says so.
- If Homebrew restricts `run` steps or quarantine clearing in third-party taps, the fix is a Developer ID and notarization, not another workaround.
