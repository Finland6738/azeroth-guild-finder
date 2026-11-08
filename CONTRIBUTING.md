# Contributing to Azeroth Guild Finder

Thank you for your interest! This guide explains how to report problems, propose ideas and change the project.

## Language

Issues, pull requests, commit messages and public documentation are in **English**. The internal specification in `docs/specs/` is in Italian ([ADR 0016](docs/adr/0016-english-first-ui-and-documentation-languages.md)). Discussions can be in English or Italian.

## Contents

1. [Before you start](#1-before-you-start)
2. [Reporting a problem or proposing an idea](#2-reporting-a-problem-or-proposing-an-idea)
3. [Changing the code](#3-changing-the-code)
4. [Checks and tests](#4-checks-and-tests)
5. [Git, issues and pull requests](#5-git-issues-and-pull-requests)
6. [What is not accepted](#6-what-is-not-accepted)
7. [Licensing of contributions](#licensing-of-contributions)

## 1. Before you start

- Read the [specification](docs/specs/README.md) and the [ADRs](docs/adr/README.md): they explain what the addon does and why.
- The addon targets **WoW Forever, Interface 16001**. Check every API in the Forever API dump ([ADR 0002](docs/adr/0002-wow-forever-target-and-api-dump.md)) and guard it with the Compat layer.

## 2. Reporting a problem or proposing an idea

- **Bugs**: open an issue with the *Bug report* form.
- **Ideas and questions**: start a topic in the [Feedback discussions](https://github.com/Finland6738/azeroth-guild-finder/discussions/categories/feedback); a concrete request can become a *Feature request* issue.
- **Checks in the real client**: use the *In-game test report* form.
- **Privacy**: never paste other players' names, whispers, account names or folder paths from your PC.

## 3. Changing the code

- Modules are isolated and talk through the internal event bus ([SPEC-01 §3](docs/specs/SPEC-01-platform-architecture.md)).
- Every visible string goes through AceLocale (`L["KEY"]`).
- Saved data changes need a schema migration ([ADR 0011](docs/adr/0011-savedvariables-and-schema-versions.md)).
- Never call game textures by copying files: reference them by fileID ([ADR 0007](docs/adr/0007-emblems-from-tabard-pieces.md)).
- The addon lives in `AzerothGuildFinder/` (Lua 5.1 only). Libraries are never committed: they are pinned in `.pkgmeta`; run `python -I -X utf8 tools/fetch_libs.py` to download them and `python -I -X utf8 tools/install_addon.py` to copy the addon into your AddOns folder (path in the git-ignored `tools/local.ini`).
- Mockups: edit `docs/specs/mockups/html/`, then run `bash docs/specs/mockups/render.sh` (Chrome and Python with Pillow).

## 4. Checks and tests

```
python -I -X utf8 tools/check_docs.py
python -m pip install lupa==2.8            # once
python -X utf8 Tests/run_tests.py          # all offline tests
python -X utf8 Tests/run_tests.py reload   # only the tests whose name contains "reload"; -v adds tracebacks
```

`check_docs.py` checks the addon TOC and `embeds.xml` (Interface 16001, every listed file exists), relative links, the wiki sidebar and links, the ADR index, personal data (emails and personal paths) and LF line endings. CI runs it and the offline tests on every pull request. CI runs the tests with `-I`; if lupa is in your user site-packages, leave `-I` out locally.

**How the tests work** ([ADR 0019](docs/adr/0019-offline-tests-with-lupa-and-a-mock-client.md)): the runner loads a mock WoW client (`Tests/mock/`), then the real libraries and the addon files in TOC order, fires the login events, and runs every `Tests/test_*.lua`. Each test starts on a freshly built client. The libraries must be fetched first (`tools/fetch_libs.py`; the runner does it if they are missing).

**Writing a test**: add `Tests/test_<area>.lua`. `Tests/test_addon.lua` is the model.

```lua
describe("guild role", function()
	before_boot(function(mock)                 -- runs before the addon loads, for every test of this group
		mock.guild.Set({ name = "Night Watch", myRank = 1 })
	end)

	it("sees the officer rank", function()
		truthy(C_GuildInfo.IsGuildOfficer())   -- the game's globals are plain globals
		Mock.guild.SetMyRank(3)                -- fires PLAYER_GUILD_UPDATE
		falsy(C_GuildInfo.IsGuildOfficer())
	end)
end)
```

- Assertions: `eq`, `ne`, `truthy`, `falsy`, `isNil`, `notNil`, `deepEq`, `near`, `contains`, `matches`, `raises(fn, pattern)`, `fail`. `T.log(...)` prints while debugging.
- Read game globals (`AzerothGuildFinder`, `C_EncodingUtil`, ...) **inside** the test, not at the top of the file: the game is rebuilt before each test.
- The fake client: `Mock.Fire(event, ...)`, `Mock.Advance(seconds)` (timers and `OnUpdate`), `Mock.Slash("/gf help")`, `Mock.output` / `Mock.PlainOutput()` (chat lines), `Mock.chat` (sent addon messages, `lockdown`, `forceResult`, `QueueResults`, `Receive`), `Mock.guild` (`Set`, `Leave`, `SetMyRank`, `invites`), `Mock.player`, `Mock.errors`. A Lua error inside a handler is caught as in the client and fails the test unless you call `Mock.ClearErrors()`.
- `Mock.Reload()` simulates `/reload`: the declared SavedVariables are serialized, the Lua state is rebuilt, the variables come back before `ADDON_LOADED`; time, player and guild stay. `T.boot(setup)` starts a completely new client.
- If a test needs an API the mock does not have, add it to the right file in `Tests/mock/` in the same pull request, say in its header which dump entry it imitates, and flag any value the dump does not give.

**Writing a network test** (the simulator, `Tests/sim/sim.lua`): `Sim` is a global in every test file. It builds N complete clients, each with its own game environment, mock client, SavedVariables and copy of the addon, connected by a virtual channel, whisper, guild and officer routing on one shared clock.

```lua
describe("pings", function()
	it("every client hears the others", function()
		local sim = Sim.new{ clients = 5, latency = { 0.05, 0.3 }, loss = 0.0, seed = 7 }   -- returns once all clients joined the channel
		local a = sim:client(1)
		a:slash("/gf debug ping")                       -- Mock.Slash on that client
		sim:advance(8)                                  -- simulated seconds, every client runs frame by frame
		eq(a:addon().Ping.state.last.answers, 4)        -- a:addon() is that client's AzerothGuildFinder, a.E its globals, a.Mock its mock
		local st = sim:stats()                          -- messages and bytes per client and per minute (reset with sim:resetStats())
		eq(st.perClient[1].byDist.CHANNEL.msgs, 1)
	end)
end)
```

- Options of `Sim.new`: `clients`, `latency` (seconds, or `{ min, max }`), `loss` (probability, or `function(from, to, entry)`), `seed`, `step`, `echo`, `ready`, `guild(i)`, `setup(Mock, i, client)`, `restrict`, `sync`, `onSend`, `onDeliver`; the full list is at the top of the file.
- The catalog sync (`Net/Sync.lua`) starts by itself in every simulated client, as in the game: pass `sync = false` when a test counts the traffic of something else. Single-client tests never sync by themselves (`Sync.AUTO` is off); call `Sync:Request()` when a test needs it.
- Lua 5.1's `math.random` is the C library's `rand()`: the same seed gives the same run on one system, but Windows and Linux (CI) draw different numbers. Wait for an event (`sim:advanceUntil`) rather than a fixed time when the outcome depends on random delays.
- Messages from one client to another arrive in the order they were sent, as on the real server (AceComm needs it to put multipart messages back together); the latency is drawn per delivery, but never overtakes an earlier message of the same pair.
- Per client: `c:slash`, `c:output()`, `c:addon()`, `c:reload()`, `c:restrict{ listenOnly, lockdown, restricted }`, `c:setGuild(name, rank)`, `c:setOnline(false)`, `c:stats()`. Per network: `sim:advance(s)`, `sim:advanceUntil(fn, limit)`, `sim:setLoss`, `sim:setLatency`, `sim:stats()`.
- Listen to what a client receives with its own Bus: `c:addon().Bus:On("NET_MESSAGE", function(msg, sender, dist) ... end)`. Build the sender of a whisper with `c:fullName()`.
- Everything is deterministic for a given `seed`. A Lua error inside any client fails the test, like in the single-client tests. Fifty clients boot and run five simulated minutes in about three seconds; use a bigger `step` (0.2) only when a test does not depend on sub-second timing.
- What the simulator does not do: it does not model the server's own throttling or the real client (only the addon's queue and ChatThrottleLib are real), so it shows that the protocol converges and stays inside the budget, not that Forever agrees ([the in-game checks](docs/checklists/M1.md)).

## 5. Git, issues and pull requests

- One branch per step or fix from an up-to-date `main`: `step/m<N>-<name>`, `fix/<name>`, `docs/<name>`, `chore/<name>`.
- Small commits with clear messages in English.
- Every pull request updates **in the same PR**: `CHANGELOG.md` ("Unreleased"), the affected docs (specs, ADRs and the ADR index, both READMEs) and **the wiki pages in `docs/wiki/` for any user-visible change**. The *Docs rule* check enforces it for changes under `AzerothGuildFinder/`; use the label `no-docs-needed` only for pure refactors or tests.
- The wiki is **never edited on GitHub**: it is published from `docs/wiki/` after every merge ([ADR 0014](docs/adr/0014-github-wiki-generated-from-docs-wiki.md)).
- `main` is protected: the checks `Tests` and `Docs rule` must be green; pull requests are squash merged.
- The maintainer's steps are shipped with `tools/ship_step.py` ([ADR 0013](docs/adr/0013-git-flow-and-automated-shipping.md)).
- A pull request that fixes an issue says `Closes #N`.

## 6. What is not accepted

- Code that sends anything outside the game, telemetry or external services.
- Files copied from the game client or from other games.
- Rankings, paid placement or features that publish data about single players.
- Personal data in the repository.

## Licensing of contributions

By submitting a contribution you agree that it is released under the project's licence, the [GNU GPL v3.0](LICENSE), and you certify that you have the right to submit it (Developer Certificate of Origin: sign off your commits with `git commit -s`).
