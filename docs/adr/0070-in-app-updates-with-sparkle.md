# 70. In-app updates with Sparkle

Status: accepted, 2026-11-14. Supersedes ADR 0063.

## Context
ADR 0063's update checker only told the user about a new release: they then downloaded the zip or ran `brew upgrade`. The user asked for updates from inside Sextant, as Sparkle does. Offered Sparkle's standard windows or Sextant's own window over a custom Sparkle user driver, they chose Sparkle's windows. Offered marking the cask `auto_updates` or leaving it as it was, they chose `auto_updates`. They also asked to bump the dependencies that were out of date.

What the tools allow (checked against Sparkle 2.10.1's source and docs, and on this Mac):
- Sparkle accepts an update when its EdDSA signature is valid, even if the old and new code signatures don't match (`SUUpdateValidator`). Ad-hoc builds, whose signatures change with every build, can update each other.
- The hardened runtime's library validation refuses an ad-hoc `Sparkle.framework` in an ad-hoc app: neither has a Team ID ("mapping process and mapped file (non-platform) have different Team IDs", reproduced with a probe binary). `com.apple.security.cs.disable-library-validation` lets it load.
- Sparkle's SwiftPM artifact includes `sign_update` and `generate_keys`, so the release workflow needs no other download.
- Sparkle 2.9+ can require a signed feed (`SURequireSignedFeed`); release notes embedded in the feed are covered by its signature.

## Decision
- **Package:** Sparkle 2.10.1 (MIT), pinned exactly, linked only into `SextantUpdates`. SwiftLint's `updates_imports` rule now allows `Sparkle` there and nowhere else changes.
- **Port:** `SoftwareUpdater` (main actor): whether the build can update itself, the two choices, the last check, the version, `start(report:)` and `checkForUpdates()`. It reports `SoftwareUpdateEvent`s: whether a check may start, an update found in the background, the user saw it, the session ended, a check answered.
- **Adapter:** `SextantUpdates.SparkleUpdater` wraps `SPUUpdater` with Sparkle's standard user driver.
  - A build can update itself only as a `.app` with a version, an `https` `SUFeedURL` and a 32-byte `SUPublicEDKey`. `swift run`, and a bundle without the key, show "This build can't update itself."
  - **Gentle reminders:** a scheduled check shows Sparkle's window only when it would be in immediate focus, which Sparkle decides: Sextant has just launched, or the Mac has been idle. Otherwise it reports the update, whether or not Sextant is in front, and the menu bar panel and the Sextant menu remind the user ("Sextant X.Y.Z is available." with Details…, "Update to Sextant X.Y.Z…"). Sextant often runs from the menu bar for days, and a window over the user's work would be rude.
  - **The choices follow Sparkle:** Sparkle's update window has its own "Automatically download and install updates" checkbox, and turning checks off turns automatic installs off. The adapter observes both settings (KVO) and Settings shows what Sparkle has.
  - **Settings move:** ADR 0063's keys are removed at launch; a user who had turned automatic checks off keeps them off (`SUEnableAutomaticChecks = NO`).
- **Use case:** `SoftwareUpdates` (application, app-wide) mirrors the updater for the UI and forwards the choices. The old `UpdateChecker`, `ReleaseFeed`, `AppRelease`, `UpdateCheckError` and `GitHubReleaseFeed` are gone; `AppVersion` (domain) stays.
- **UI:** Sparkle's windows show the notes, download, install and relaunch. The Software Update window is gone.
  - Sextant ▸ Check for Updates… brings Sextant forward and asks Sparkle; it is disabled while Sparkle can't check.
  - Settings › General › Updates has the daily-check switch, a new "Download and install updates automatically" switch (off by default, Sparkle's default), the version, the last check and Check Now.
- **Info.plist:** the feed is `https://raw.githubusercontent.com/afrase/Sextant/appcast/appcast.xml`: an orphan `appcast` branch holding one file. A release's own assets would be simpler (`releases/latest/download/appcast.xml`), but "latest" moves when a release is published, before its build. A failed build would leave every copy of Sextant with no feed until the next good release; the branch changes only after a release has built. Daily checks are on by default (`SUEnableAutomaticChecks`), so Sparkle doesn't ask at the second launch. The feed must be signed (`SURequireSignedFeed`), and an update is verified before it is unpacked (`SUVerifyUpdateBeforeExtraction`). Sparkle compares `CFBundleVersion`, the commit count, which grows with every release from `main`.
- **Bundle (`scripts/bundle`):** copies `Sparkle.framework` into `Contents/Frameworks` without its XPC services (Sextant isn't sandboxed) and adds the `@executable_path/../Frameworks` rpath. It signs inside out, as Sparkle documents, instead of `--deep`. Ad-hoc builds use `Resources/SextantAdHoc.entitlements`, which turns off library validation; a Developer ID build keeps `Sextant.entitlements` and library validation.
- **Release (`.github/workflows/release.yml`, `scripts/appcast`):** for a release that isn't a pre-release, the workflow writes `appcast.xml` before it publishes anything. It is one item with GitHub's rendering of the release notes embedded, the zip's EdDSA signature, the minimum macOS, and the feed's own signature.
  - **Key:** the private key is the `SPARKLE_ED_PRIVATE_KEY` secret, passed to `sign_update` on standard input. `scripts/verify-update-signature.swift` (CryptoKit) checks the zip's signature against the built app's `SUPublicEDKey`. With no secret, no public key or a key that doesn't match, the job fails before the zip is attached: no copy of Sextant could install that release.
  - **Order:** the workflow attaches the zip, checksum and appcast to the release, then commits the appcast to the `appcast` branch, then updates the cask. A run by hand that rebuilds an older release leaves a newer feed alone. A run by hand reads whether the tag is a pre-release from the release itself.
- **Homebrew:** the cask says `auto_updates true`, so `brew upgrade` leaves Sextant to Sparkle (`--greedy` still upgrades it).
- **Dependencies:** swift-subprocess 1.0.1 → 1.0.2 and swift-snapshot-testing 1.19.6 → 1.19.7. The rest were current.

## Consequences
- **One-time setup by the user:** generate the key pair (`generate_keys`, which keeps the private key in their login keychain), put the public key in Info.plist, and store the private key as the `SPARKLE_ED_PRIVATE_KEY` repository secret. Losing the private key means shipping a release that users install by hand once.
- **Moving to Sparkle needs one manual update.** Copies from v0.5.x and earlier only know ADR 0063's checker; they are told about the first Sparkle release and update by hand or with Homebrew, and update themselves from then on.
- **Ad-hoc builds give up library validation.** Another dylib could be loaded into Sextant from its own bundle. The hardened runtime still refuses `DYLD_` environment variables. A Developer ID build gets library validation back without code changes.
- **Privacy:** unchanged in kind. Once a day (and when asked), Sparkle fetches the appcast from GitHub with a User-Agent of Sextant's and Sparkle's versions, and no system profile. The README, the guide and Settings › General say so.
- **No release is possible until the key is set up:** the workflow refuses to publish a release that Sextant couldn't install in-app. Pre-releases still build.
- **Rebuilding the newest release by hand** replaces its zip a moment before the feed names the new signature. A check in that moment fails verification safely and works on the next try.
- **raw.githubusercontent.com caches for about five minutes,** so a new release reaches the feed a few minutes after the workflow ends.
- **TCC grants still reset with each ad-hoc update** (Accessibility for the trackpad driver), as they did with `brew upgrade`. Only a Developer ID signature avoids it.
- Sparkle's own windows aren't drawn by `SextantSnapshots`; the Settings section (on a release build and on one that can't update) and the menu bar reminder are.
