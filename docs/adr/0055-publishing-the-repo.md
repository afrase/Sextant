# 55. Publishing the repo

Status: accepted, 2026-10-12.

## Context
The user is publishing Sextant at github.com/afrase/Sextant. The private repo held material that is not ours to publish: files extracted from Oryx's web app (keycode descriptions, setting descriptions, design tokens, GraphQL documents), Oryx screenshots, ZSA's default Voyager layout, four other people's public Oryx layouts with their source zips, and the early design prototypes and judging renders. Some tests used those layouts as golden samples, so removing them must not leave a fresh clone with failing tests. The repo had no license, no CI and no contributor docs.

## Decision
- **A reference folder outside the repo.** The material moves, at the same relative paths, to `~/Developer/Sextant-reference/`, which has its own README. The repo keeps the author's own layout (`docs/research/oryx-examples/my-layout-KlgM7-*.json` and `sources/KlgM7-40xJ7M-source.zip`), `design/PrototypeKit` and `docs/design`. Docs mention the reference folder in plain text, never as a link.
- **Tests read `SEXTANT_REFERENCE`.** A test that needs a moved file reads it from the folder that variable names, at the same relative path. Without it (or when the folder is missing) the test is skipped, or its sample cases drop out of the argument list, so the author's own layout is always tested. `scripts/check` sets the variable to `$HOME/Developer/Sextant-reference` when it is unset and that folder exists.
- **The material leaves the history.** After the branches that change it are merged, the maintainer rewrites `main` with `git filter-branch --index-filter 'git rm -r -q --cached --ignore-unmatch -- <paths>' --prune-empty`, deletes `refs/original`, checks that none of the removed blobs is still reachable, and pushes `main` only. Commits keep the author's name and email. The paths, exact case, anchored at the repo root:
  - `docs/research/data/oryx-keycodes.json`
  - `docs/research/data/04-oryx-settings-catalog.json`
  - `docs/research/data/oryx-config-settings.json`
  - `docs/research/data/oryx-design-tokens.json`
  - `docs/research/data/oryx-graphql-operations.json`
  - `docs/oryx-ui`
  - `design/explorations`
  - `design/judging`
  - `docs/research/oryx-examples/voyager-default.json`
  - `docs/research/oryx-examples/voyager-e5Rrr.json`
  - `docs/research/oryx-examples/voyager-JRGQm.json`
  - `docs/research/oryx-examples/voyager-m9dpx.json`
  - `docs/research/oryx-examples/voyager-XlrR4.json`
  - `docs/research/oryx-examples/sources/e5Rrr-source.zip`
  - `docs/research/oryx-examples/sources/JRGQm-source.zip`
  - `docs/research/oryx-examples/sources/m9dpx-source.zip`
  - `docs/research/oryx-examples/sources/XlrR4-source.zip`
- **CI on GitHub Actions.** `.github/workflows/ci.yml` runs `scripts/check` on the hosted `macos-26` runner with Xcode 26.6 selected explicitly, `actions/checkout` pinned by commit, and read-only permissions. GitHub sets `CI=true`, which skips the pixel snapshot tests (their references are rendered on the developer's macOS) and the report-only Periphery scan (nobody reads it there, and its index-store path is Swift Build's layout). CI runs without `SEXTANT_REFERENCE`.
- **MIT license**, "Copyright (c) 2026 Aaron Frase". The app's `NSHumanReadableCopyright` says the same and keeps the not-affiliated line.
- **Repo docs:** a README for users and contributors, `CONTRIBUTING.md`, and `SECURITY.md`, which sends reports through GitHub's private vulnerability reporting.

## Consequences
- A fresh clone builds and passes `scripts/check` with no extra files. The developer's machine still runs the full golden set through the reference folder.
- CI catches compiler and formatter drift between Xcode 26.6 (Swift 6.2/6.3) and the developer's newer toolchain. Board-rendering regressions are caught only by local runs.
- The design spec's `A-nn`, `B-nn` and `C-nn` snapshot references, and the research notes that cite the Oryx extracts, now point at files only the author has.
- Every clone and branch cut before the rewrite still holds the removed objects; branches must be rebased onto the rewritten `main`, never merged from the old one.
- QMK (GPL-2.0-or-later) is downloaded by the app at build time, pinned by checksum, and never bundled. The one exception in the tree is the author's Oryx source zip, kept as golden test data: it holds Oryx's generated keymap and a QMK-built firmware binary, which stay under their own licenses.
