# 0022. Release packaging with the BigWigs packager, CurseForge optional

- Status: Accepted
- Date: 2026-11-18 ([docs/roadmap/M5-release.md](../roadmap/M5-release.md), step M5.5)

## Context

[SPEC-09 §4](../specs/SPEC-09-quality-release.md) asks for packages built by the BigWigs packager in a GitHub Action, published on GitHub Releases and CurseForge. `.pkgmeta` already pins the libraries ([ADR 0010](0010-embedded-ace3-and-native-encoding.md)) and the addon lives in a subfolder of the repository. The CurseForge project and its API token do not exist yet, and a tag is the one outward-facing act of the whole release: the workflow has to be ready and checked before the owner pushes anything.

## Decision

1. **Trigger**: pushing a tag `vMAJOR.MINOR.PATCH`, optionally `-alpha`, `-beta` or `-rc` with `.N` (`v1.0.0`, `v0.9.0-beta.1`). Any other `v*` tag stops the run with an error. The version in the TOC (`## Version: @project-version@`) and in the zip name is the tag.
2. **Two phases, one packager**: the workflow (`.github/workflows/release.yml`) first builds the zip with the packager in "build only" mode (`-d`), checks it, and creates the GitHub Release itself (`gh release create`) with that very zip. Only afterwards, if CurseForge is configured, the packager runs again without a GitHub token, so it uploads to CurseForge and nowhere else. The packager's own all-in-one upload would publish before anyone could look at the zip, cannot make a draft, and does not know `-rc`.
3. **Pre-releases**: a tag with a suffix is a GitHub pre-release. The packager knows only `alpha` and `beta`; a release candidate would be filed on CurseForge as a stable release, so `-rc` tags are **not** uploaded to CurseForge (the run says so in a notice).
4. **CurseForge is optional and silent when missing**: the upload runs only if the repository secret `CF_API_KEY` exists **and** the TOC has `## X-Curse-Project-ID: <number>` (the line ships commented out as a placeholder). Otherwise the step is skipped with a notice and the run stays green. The secret is passed to the packager as `CF_API_TOKEN`, the name it now documents (`CF_API_KEY` is its deprecated alias).
5. **A manual run publishes nothing**: *Run workflow* builds, checks and keeps the zip as a workflow artifact. With the input `draft_tag` it also creates a **draft** GitHub Release of that name (the tag is made only inside the runner and never pushed), the way to see the real asset before a real tag. A manual run never touches CurseForge and never creates a public release, even when started on a tag.
6. **The package check** (`tools/check_package.py`, offline): from `.pkgmeta` and the tracked files it works out what the packager would ship, and from a built zip (`--zip`) what it really shipped. It fails when the GPL-3.0 `LICENSE` or the OFL text of a bundled font family is missing, when `Tests/`, `docs/`, `tools/`, `.github`, Markdown or other development files would ship, when a Lua file sets `DEV = true` outside the `--@debug@` block, when a Lua file is not loaded by the TOC, and (zip only) when the TOC version was not filled in or is not the tag. CI runs it on every pull request, the release workflow runs it on the sources and on the zip before publishing, and `tools/check_docs.py` includes it with a self-test of the zip rules.
7. **Licences ship**: `LICENSE` is not in `ignore:`. The repository root is the package, so the file lands inside the addon folder next to the TOC (the packager merges the moved addon subfolder into the package folder); the OFL texts sit next to the fonts and were never ignored.
8. **Development code is gated by the packager**: `Core/Config.lua` sets `Config.DEV = false` and turns it on only between `--@debug@` and `--@end-debug@`, which the packager comments out in every package (`Net/Sync.lua` also ignores test listings when it is false). `/gf debug announce|seed|publish|delist|gallery` refuse to run when it is false. Those Lua files still ship (they are loaded by the TOC) but cannot act.
9. **Pinned actions**: every action is pinned to a commit SHA, the packager to the commit of `v2.7.0`.

## Alternatives considered

- **The packager's own GitHub upload** (`GITHUB_OAUTH`): fewer lines, but no draft, no `-rc`, and the zip cannot be checked before it is public.
- **Uploading to CurseForge first**: a bad file on CurseForge cannot be recalled; a GitHub Release can be edited or deleted.
- **A `LICENSE` copy inside `AzerothGuildFinder/`**: unnecessary, the packager already merges the root files into the package.
- **Failing the run when `CF_API_KEY` is missing**: the first tags (alpha, beta) are meant to run before the CurseForge project exists.

## Consequences

- The first real run is the proof: nothing here has been executed in GitHub Actions yet. [docs/RELEASING.md](../RELEASING.md) says how the owner tries it safely (manual run, then a draft, then a test tag).
- Whether the packager knows the CurseForge game version for WoW Forever (Interface 16001, game type `forever` in packager 2.7.0) is to be seen at the first upload.
