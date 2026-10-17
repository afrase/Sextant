# 63. An update checker that tells, and doesn't install

Status: accepted, 2026-10-17.

## Context
Sextant ships through GitHub releases and a Homebrew cask (ADR 0058), and nothing told a user a newer version was out. The
user asked for an update checker. Offered a notify-only check or Sparkle (download, install, relaunch), they chose notify
only for now, with Sparkle possible later; offered daily checks on by default or only on request, they chose daily, on by
default.

Sparkle would add a package, an EdDSA signing key kept as a GitHub secret and an appcast the release workflow publishes.
It also fights Homebrew, which then thinks the app is out of date, and Sparkle may refuse to replace one ad-hoc-signed
build with another, since their code signatures don't match. Notify only needs none of that.

## Decision
- **Domain:** `AppVersion` reads release tags and the bundle's short version (`v0.2.0`, `1.0.0-beta.1`) and orders them by
  semantic-versioning precedence: a pre-release ranks below its release.
- **Port:** `ReleaseFeed.latest()` returns the newest `AppRelease` (version, release page, the zip, the date), never a draft
  or a pre-release.
- **Adapter:** `SextantUpdates.GitHubReleaseFeed`, a new target that imports Foundation only. It sends one unauthenticated
  `GET https://api.github.com/repos/afrase/Sextant/releases/latest` with the User-Agent GitHub requires,
  `Sextant/<version> (macOS; update check)`. It sends no credentials or other identifiers: its own ephemeral session keeps
  no cookies or cache, sends `Accept-Language: en` rather than the Mac's languages, and gives up after 30 s. It hands on
  only `https` links to github.com: the release page, and the `Sextant-X.Y.Z.zip` the release workflow attaches.
  Until that zip is attached (the build runs after a release is published), the release has no download and isn't
  offered, so nobody is told to update to something they can't download or `brew upgrade` to.
- **Use case:** `UpdateChecker` (application, app-wide).
  - It checks 10 s after launch, then whenever a day has passed since the last answer. It looks every hour, so a Mac that
    slept or was offline checks soon after.
  - Checking automatically is on by default; Settings › General turns it off.
  - The user can always ask.
  - A build without a version (`swift run`) never checks by itself.
  - A check that fails says why in the window, and keeps what was found: the newer release found is saved, so the
    notice survives being offline and a relaunch within the day.
  - A check asked for while one runs waits for that one.
  - Skip This Version stops the notice until a newer release is out.
  - It keeps the choice, the last answer's date, the skipped version and the release found in UserDefaults.
- **UI:**
  - **Sextant ▸ Check for Updates…** opens the Software Update window and checks. Once an update is found, the item
    reads "Update to Sextant X.Y.Z…", so the menu says so even when the menu bar item is hidden. It is a small view
    inside the command group, so it follows the checker.
  - **The Software Update window** gives the status and Release Notes. It also offers Download, or, when Homebrew's
    Caskroom has Sextant and it runs from /Applications, `brew upgrade --cask sextant` with Copy. It also has Skip This Version, the automatic switch
    and the last check's date.
  - **The menu bar panel** shows "Sextant X.Y.Z is available." with Details….
  - **Settings › General** has an Updates section: the switch, the status, Check Now, and a footer saying what GitHub sees.
- **The bundle's version:** `scripts/bundle` defaults it to the newest `vX.Y.Z` tag, so a local build isn't told that
  release is an update (pre-release tags are skipped). Release builds still set it from their tag; a clone without
  tags gets 0.1.0 and is offered every release.

## Consequences
- **Privacy:** Sextant now goes online once a day by itself. GitHub sees the Mac's IP address and Sextant's version. The
  README's Privacy section and the guide say so.
- **Rate limit:** unauthenticated API calls are limited to 60 an hour per IP address; a daily check, or a few manual ones,
  stays far below it.
- **Moving to Sparkle later** replaces the adapter and the window's actions. The domain version, the schedule and the
  settings carry over.
