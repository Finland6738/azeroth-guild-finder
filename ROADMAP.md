# Roadmap

This page is the short version and the rules every step follows. **The development steps of each milestone are in [docs/roadmap/](docs/roadmap/README.md)**, one file per milestone; the checks behind the plan are in [SPEC-09](docs/specs/SPEC-09-quality-release.md) (Italian).

## Milestones

| Milestone | Branch prefix | Content | Exit criterion |
|---|---|---|---|
| **[M0 – Spike](docs/roadmap/M0-spike.md)** | `step/m0-…` | A probe addon (not distributed) answers checks S1–S11 in the real client: Club Finder, channel and whisper messages, minimum level to send, `OFFICER` channel, throttling, guild globals, tabard pieces, textures, invite, chat lockdown | results in `docs/spike/M0-results.md`, ADRs updated |
| **[M1 – Foundations](docs/roadmap/M1-foundations.md)** | `step/m1-…` | Addon skeleton (TOC 16001, Ace3, `.pkgmeta`), Compat, Config with schema versions, Codec, Transport, Channel, offline tests with a mock client | two clients exchange messages in the simulator |
| **[M2 – Find a Guild](docs/roadmap/M2-find-a-guild.md)** | `step/m2-…` | Catalog, Sync, name normalization, list, search and filters | the list fills from a simulated network (done); in game, a test listing announced by one client appears in another (waiting for the owner) |
| **[M3 – Listings](docs/roadmap/M3-listings.md)** | `step/m3-…` | Listing editor, My Guild, emblems, banners, statistics | a real Guild Master publishes a listing and a second client without a guild sees it within 2 minutes (done in the simulator; in game waiting for the owner) |
| **[M4 – Applications](docs/roadmap/M4-applications.md)** | `step/m4-…` | Applications, officer inbox and sync, notification icon, My Application | full flow with an officer online and offline (done in the simulator: officer online, officer coming online later, two officers in sync; in game waiting for the owner) |
| **[M5 – Release](docs/roadmap/M5-release.md)** | `step/m5-…` | Settings, polish, release checklist, packaging for GitHub and CurseForge | `v0.9` beta, then `v1.0.0` |

Later ([V2 backlog](docs/roadmap/V2-backlog.md)): recommended guilds, raid and PvP statistics, Italian interface, integration in Blizzard's guild window, signed listings if abuse appears.

## Rules for every step

1. Take the next unticked step of the current milestone file and start its branch from an up-to-date `main` (`step/m<N>-<k>-<name>`).
2. Keep the step small; open an issue for anything outside it.
3. Update in the same branch: `CHANGELOG.md`, the affected specs and ADRs, `README.md` and `README.it.md` when features or status change, and **`docs/wiki/` for anything a user can see**.
4. Run `python -I -X utf8 tools/check_docs.py` (and the addon tests from M1).
5. Ship: `python -I -X utf8 tools/ship_step.py --title "M<N>: <summary>" --body-file <pr.md>` pushes, opens the pull request, waits for CI and squash merges it ([ADR 0013](docs/adr/0013-git-flow-and-automated-shipping.md)). The wiki is published automatically after the merge.
6. The pull request says honestly what was **not** verified in the real client, and ticks the step's checkboxes in its milestone file.
