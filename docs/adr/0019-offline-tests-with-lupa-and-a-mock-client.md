# 0019. Offline tests with lupa and a mock client

- Status: Accepted
- Date: 2026-11-08 ([docs/roadmap/M1-foundations.md](../roadmap/M1-foundations.md), step M1.2)

## Context

The addon only runs inside WoW Forever, which cannot be started in continuous integration, and the owner cannot test in the client for every step (M0 results are still pending). Most of the logic (roles, codec, transport, catalog sync, applications) does not depend on graphics, so it can be tested outside the game. [SPEC-09 §2](../specs/SPEC-09-quality-release.md) asks for the approach of the sibling project azeroth-unspoken (its ADR 0007): Lua 5.1 through [lupa](https://github.com/scoder/lupa) on a mock client. This project differs in three ways: it embeds the real Ace3 libraries, its core is a network protocol that needs a controllable clock and a message recorder, and SavedVariables must survive a simulated `/reload`.

## Decision

1. **Runner**: `Tests/run_tests.py` uses `lupa.lua51` (pinned `lupa==2.8`, Lua 5.1 like the client). It reads `AzerothGuildFinder.toc`, follows `embeds.xml` (`Script`, `Include`) and loads the addon files **in TOC order**, each called with the addon name and a private namespace table, like the client. The real Ace3, LibDataBroker and LibDBIcon from `AzerothGuildFinder/Libs/` are loaded too (`tools/fetch_libs.py` downloads them from the tags pinned in `.pkgmeta`; the runner runs it when they are missing). A TOC or XML path whose case differs from the file on disk fails, because CI is case-sensitive and the client is not.
2. **Two Lua worlds in one state**: the harness and the test files run in the real globals; the mock client, the libraries and the addon run in a separate table (`setfenv`), emptied and rebuilt in place at every boot. Every test gets a freshly built client and addon (a test must read game globals when it runs, not when its file loads).
3. **Mock client** in `Tests/mock/*.lua`, loaded in file-name order, one area per file: Lua environment (xpcall with arguments, helpers, `bit`, `Enum`, `print` capture), controllable clock (`GetTime`, `GetServerTime`, `time`, `date`, always UTC), frames and events (`CreateFrame`, scripts, `RegisterEvent`, `Mock.Fire`, slash commands), `C_Timer` and `Mock.Advance(seconds)` (timers and `OnUpdate` run frame by frame), `C_ChatInfo` addon messages (recorded sends, result codes, lockdown, forced results, `Mock.chat.Receive`) and channels, a configurable guild and roster (`Mock.guild.Set`), the player and client build, and `C_EncodingUtil` (CBOR, Base64, hex in Lua; compression through Python's zlib). Each file says which dump entries it imitates and what it does not do. Event names are checked against `../WoW-Addons/docs/api.json` when it is present ([ADR 0002](0002-wow-forever-target-and-api-dump.md): consulted at run time, never copied).
4. **Client behaviour kept on purpose**: errors raised inside handlers, timers and slash commands are caught like the client's error handler does and collected in `Mock.errors`; the test fails if any is left. Calling a widget method the mock does not have fails loudly instead of being ignored.
5. **`/reload` simulation**: `Mock.Reload()` fires `PLAYER_LOGOUT`, serializes the SavedVariables declared in the TOC to Lua text (functions, cycles and non-finite numbers are errors), rebuilds the Lua state, restores the variables before `ADDON_LOADED` and fires `PLAYER_ENTERING_WORLD(false, true)`. The world (clock, player, guild, chat records) is carried over, because it belongs to the game and not to the UI.
6. **Tests**: `Tests/test_*.lua`, written with `describe`, `it`, `before_boot` and the assertions of `Tests/lib/assert.lua` (`eq`, `truthy`, `deepEq`, `raises`, ...). `python -I -X utf8 Tests/run_tests.py [filter] [-v]` exits with 1 if a test fails or none ran. CI runs the suite in the job "Tests" after `tools/fetch_libs.py`; `tools/ship_step.py` runs it before every pull request (without `-I`, because lupa may live in the user's site-packages).
7. **Every step adds tests for what it builds**; a mock that does not yet cover an API the step uses is extended in the same pull request, citing the dump entry.

## Alternatives considered

- **A system Lua with busted or luaunit**: no Python launcher to read the TOC, and a separate install on Windows. lupa installs with one `pip` command.
- **Stubbing the libraries**: hides real library behaviour (AceAddon's `xpcall` arguments, ChatThrottleLib's `OnUpdate` pacing, AceDB keys); the first run of the harness already found a client behaviour (`xpcall` forwarding arguments) that a stub would have hidden.
- **Reloading by starting a new Lua runtime**: a test running inside the old runtime could not follow it; rebuilding one environment table in place keeps `_G` and `Mock` valid.
- **A full simulator of the WoW interface**: too expensive; the mock covers what the addon uses and grows with it.

## The network simulator (M1.8)

`Tests/sim/sim.lua` runs N clients as N **instances of the harness inside the one Lua state** (`H.newWorld()`): each has its own game environment table, mock client, clock, timers, chat, guild and SavedVariables, and loads its own copy of the libraries and the addon, so a client knows nothing of the others except what the simulator delivers as `CHAT_MSG_ADDON`. The simulator advances them frame by frame on a shared clock and routes what each one sent (`Mock.chat.sent`) to the others with latency, loss and restrictions.

Considered and rejected: **one `lupa` runtime per client**. Tables cannot cross between runtimes, so every inspection a test makes (Bus listeners, `Transport:Stats()`, the catalog of M2) would go through serialized strings or per-call glue, and the M2.3 scenario of 50 clients and 100 guilds would need a second protocol only to look inside a client. Isolation is the same: nothing is shared except the plain Lua library functions, which the addon does not change. Cost: fifty clients boot and run five simulated minutes in about three seconds.

## Consequences

- Positive: a test run takes about a second; the network simulator of M1.8 builds on `Mock.chat` and `Mock.Advance`; Ace3 is exercised for real.
- Negative:
  - **a green test shows that the code agrees with our assumptions about the client, not that the client agrees**: the M0 probe results and the in-game checks of each step stay necessary;
  - values the dump does not give (`Enum.SendAddonMessageResult`, the CBOR byte layout, compressed sizes) are retail or standard values in the mock, flagged in each file; tests must not depend on exact compressed bytes;
  - the mock must grow with the addon and can drift from the client;
  - drawing, anchoring and mouse behaviour cannot be verified offline.

## References

- [SPEC-09 §2](../specs/SPEC-09-quality-release.md), azeroth-unspoken ADR 0007 (the approach this follows).
- `Tests/run_tests.py`, `Tests/lib/`, `Tests/mock/`, `Tests/test_*.lua`; [CONTRIBUTING §4](../../CONTRIBUTING.md#4-checks-and-tests).
