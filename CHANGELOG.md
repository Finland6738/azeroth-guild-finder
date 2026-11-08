# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Design

- Specification of the first version in `docs/specs/` (SPEC-00 to SPEC-10, in Italian): scope and roles, platform and peer-to-peer architecture, network protocol, data model, interface, applications, emblems, quality and release, risks and open questions.
- Mockups v2 in `docs/specs/mockups/`: design system (Albion-like skin on a Material Design 3 skeleton, Roboto and Roboto Mono), Find a Guild, guild page, listing editor (recruitment and activity steps), emblem designer, applications, notification icon, role-based states. Rendered to WebP by `render.sh`.
- Four roles (Tank, Healer, Melee DPS, Ranged DPS), up to three activities per guild and a commitment level (Casual, Softcore, Hardcore).
- Architecture decisions 0001–0018 in `docs/adr/`.

### Planning

- Development roadmap in `docs/roadmap/`: one file per milestone (M0 spike to M5 release, 44 steps) with branch, dependencies, scope, acceptance criteria, tests, docs and real-client checks, plus the V2 backlog.
- Decisions confirmed by the owner: names (addon, channel `AzGuildFinder`, prefix `AzGF`, `/gf`), one open application per character, optional role checkboxes in the application, 14-day expiry, 7-day cooldown, unique players as a range, anonymous alt count on by default.

### Spike

- M0.1: throwaway probe addon `AzGF_Probe` in `tools/probe/` (`/agfp list|run|export|reset`, check registry, results in `AzGF_ProbeDB`; checks S1–S11 are stubs), `tools/install_probe.py` with `tools/local.example.ini`, and `docs/spike/README.md`. Never distributed; not yet run in the real client.
- Probe M0.2: checks S1 (Club Finder), S7 (guild APIs, async roster) and S11 (chat lockdown snapshots, `/agfp snapshot <label>`) in `tools/probe/AzGF_Probe/Checks_Environment.lua`; owner instructions in `docs/spike/README.md`.
- Probe M0.3: checks S2 (exchange in the test channel `AzGFProbe` with prefix `AzGFP`: `/agfp join|leave|ping|pong`), S3 (level, play time and trial-account flags recorded with every send) and S6 (`/agfp burst <n> <gap>`: throttle result codes and messages received by the peer) in `tools/probe/AzGF_Probe/Checks_Channel.lua`; two-client instructions in `docs/spike/README.md`.
- Probe M0.4: checks S4 (`/agfp whisper <name>`: addon whisper result code, reply, round trip, sender level and trial flags; the name is never stored) and S5 (`/agfp officer`, `/agfp guild`: result codes, sender guild role, distribution each message arrived on, plain-member reception) in `tools/probe/AzGF_Probe/Checks_Whisper.lua`; in-game instructions in `docs/spike/README.md`.
- Probe M0.5: checks S8 (`/agfp tabard`: every field of `C_GuildInfo.GetGuildTabardInfo("player")`, and a hidden `TabardModel` cycled with `CycleVariation` over every variation to find which index is which and to list emblem, border and background fileIDs and colours as numbers; `Save()` is never called; `/agfp export tabard` gives a Lua table for `Data/TabardParts.lua`) and S9 (`/agfp gallery`: movable 860 x 140 header preview with parchment fade and dark sample text, thumbnails of banner, parchment, class icon, role icon and emblem candidates, `/agfp tex` for extra candidates, `/agfp mark <n> ok|bad`, `/agfp export gallery`) in `tools/probe/AzGF_Probe/Checks_Tabard.lua` and `Checks_Textures.lua`; in-game instructions in `docs/spike/README.md`.
- Probe M0.6: check S10 (`/agfp invite <name>`: a small window with an Invite button calling `C_GuildInfo.Invite` from a hardware event; `/agfp invite-timer <name>`: the same call from a timer; `pcall` result, blocked-action events and the system messages that follow are recorded, the name is never stored) in `tools/probe/AzGF_Probe/Checks_Invite.lua`; in-game instructions in `docs/spike/README.md`.

### Addon

- M1.1: addon skeleton `AzerothGuildFinder/` (TOC with Interface 16001, SavedVariables, AddOn Compartment entry points; `embeds.xml`; `Bindings.xml` with "Toggle Guild Finder"; `Locale/enUS.lua`; `Core/Init.lua` with the AceAddon object, the Forever check and `/gf` and `/guildfinder` with `/gf help`; other commands print "coming soon"). `.pkgmeta` pins Ace3 (Release-r1403), LibDataBroker (v1.1.4) and LibDBIcon (v8.0.4); `tools/fetch_libs.py` downloads them into the git-ignored `Libs/`, `tools/install_addon.py` copies the addon into the AddOns folder, `tools/check_addon.py` checks the TOC and `embeds.xml`. Not yet loaded in the real client.
- M1.3: `Core/Compat.lua`, the only door to the game API. `Compat.Resolve` and `Compat.Call` (`pcall`; state `available`, `missing`, `error` or `restricted`, secret values dropped through `issecretvalue`/`canaccessvalue`), typed helpers for guild (with a `C_Club` fallback), player, chat lockdown and `Enum.AddOnRestrictionType`, server time, `C_EncodingUtil` wrappers and channels, and a capability table filled at login (`Compat:Probe()`). `/gf debug` prints version, client build, project id and each capability; modules add sections with `AddDebugSection`. APIs marked [verify] in the specification degrade cleanly because the M0 probe has not run yet.

### Project

- M0.7 (results and decisions) is deferred until the owner's in-game results; M1+ proceed on the specification's assumptions and will be revised after M0.7.

- README in English and Italian, CONTRIBUTING, Code of Conduct, roadmap, GPL-3.0 licence, funding link.
- Automation: CI (`Tests`), docs rule (`Docs rule`), wiki sync from `docs/wiki/`, advisory DCO check, issue and pull request templates, `tools/ship_step.py` (commit, push, pull request, CI, squash merge).
- User manual draft in `docs/wiki/`.
- M1.2: offline test harness. `Tests/run_tests.py` runs the addon in Lua 5.1 through lupa (pinned 2.8) on a mock WoW client: it parses the TOC and `embeds.xml`, loads the real Ace3 and LibDBIcon libraries and the addon files in TOC order, fires `ADDON_LOADED`, `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`, and runs every `Tests/test_*.lua` on a freshly built client (optional filter, `-v`). `Tests/mock/` imitates frames and events, `C_Timer` with `Mock.Advance`, a controllable clock, `C_ChatInfo` addon messages and channels, a configurable guild and roster, the player and client build, and `C_EncodingUtil` (CBOR, Base64, hex, zlib compression); `Mock.Reload()` simulates `/reload` with a SavedVariables round trip. `Tests/lib/assert.lua` provides `describe`/`it` and the assertions. Sample and mock self-tests; CI installs lupa, fetches the libraries and runs the suite; `tools/ship_step.py` runs the tests without `-I`. `.luarc.json` for the Lua language server. ADR 0019.
