# M1 — Foundations

**Goal:** the addon skeleton and the technical base every feature uses: tests, Compat, saved data, the internal bus, roles, normalization, codec, transport and channel.

**Exit criterion:** in the network simulator two or more clients exchange messages within the traffic budget; in the real client two installations exchange a ping on `AzGuildFinder` (`/gf debug ping`).

### M1.1 — Addon skeleton and packaging metadata
- Branch: `step/m1-1-skeleton`
- Depends on: M0.7
- Spec: SPEC-01 §4–§5, ADR 0010
- Scope: `AzerothGuildFinder/` with `AzerothGuildFinder.toc` (Interface 16001, SavedVariables, `AddonCompartmentFunc`), `embeds.xml`, `Bindings.xml` (empty binding "Toggle Guild Finder"), `Locale/enUS.lua`, `Core/Init.lua` (AceAddon, Forever check), `/gf help`; `.pkgmeta` with pinned externals (LibStub, CallbackHandler, AceAddon, AceEvent, AceDB, AceComm, AceLocale, AceConsole, LibDataBroker, LibDBIcon); `tools/install_addon.py` (copies the addon into the AddOns folder from `tools/local.ini`).
- Done when:
  - [ ] The addon loads on Forever with no Lua error and `/gf help` prints the commands. *(in-game check, pending)*
  - [x] Libraries resolve from `.pkgmeta` (no library copied by hand): `tools/fetch_libs.py` reads the pinned tags.
- Tests: a TOC check (interface, files exist) in `tools/check_docs.py` or the test suite.
  - [x] `tools/check_addon.py`, called by `check_docs.py`.
- Docs: README "Development", CONTRIBUTING §3, wiki Commands.
- Real client: the addon loads.

### M1.2 — Offline test harness
- Branch: `step/m1-2-test-harness`
- Depends on: M1.1
- Spec: SPEC-09 §2
- Scope: `Tests/run_tests.py` (Lua 5.1 through `lupa`), `Tests/mock/` (frames, events, `C_Timer`, `C_ChatInfo`, `C_GuildInfo`, `C_EncodingUtil` stand-ins, SavedVariables round trip), a tiny assertion library, `.luarc.json` pointing to `../WoW-Addons/types`; CI already runs the suite when it exists.
- Done when:
  - [x] `python -I -X utf8 Tests/run_tests.py` runs a sample test green locally and in CI. (CI uses `-I`; locally lupa in the user site-packages needs the plain `python -X utf8`, which `tools/ship_step.py` uses.)
  - [x] A `/reload` simulation passes SavedVariables from one run to the next (`Mock.Reload()`).
- Docs: CONTRIBUTING §4, ADR for the test approach if it differs from azeroth-unspoken.
  - [x] CONTRIBUTING §4, README "Development", ADR 0019 (it differs: real Ace3, clock and chat recorder, in-place reload).

### M1.3 — Compat layer and capability probe
- Branch: `step/m1-3-compat`
- Depends on: M1.2
- Spec: SPEC-01 §1 and §7, ADR 0002
- Scope: `Core/Compat.lua`: guarded calls, existence checks, secret values, restriction state, chat lockdown, outgoing restriction; the list of APIs from M0 results; `/gf debug` prints what is available.
- Done when:
  - [ ] Every game API used later is reached through Compat.
  - [ ] `/gf debug` reports each capability as available, missing or restricted.
- Tests: Compat with missing functions, erroring functions, secret values.

### M1.4 — Saved data and schema versions
- Branch: `step/m1-4-config`
- Depends on: M1.2
- Spec: SPEC-01 §6, ADR 0011
- Scope: `Core/Config.lua`: `AzerothGuildFinderDB` and `AzerothGuildFinderCharDB`, schema version 1, defaults merge, rules and `Sanitize`, migrations framework, read-only mode for newer data, `accountSecret` creation.
- Done when:
  - [ ] Damaged or newer saved data never breaks loading and is reported in `/gf debug`.
- Tests: defaults, validation, a dummy migration, newer schema read-only, idempotent reload.

### M1.5 — Event bus, roles and name normalization
- Branch: `step/m1-5-bus-role-normalize`
- Depends on: M1.3
- Spec: SPEC-00 §5, SPEC-03 §1 and §7, ADR 0004, ADR 0009
- Scope: `Core/Bus.lua` (internal events), `Core/Role.lua` (no guild / member / officer / Guild Master, `ROLE_CHANGED` on guild and rank events, `guildKey`), `Core/Normalize.lua` (`sortKey`, search key, UTF-8 length, FNV-1a hash).
- Done when:
  - [ ] The role matrix of SPEC-00 §5 is computed from the client state.
  - [ ] `sortKey` handles accents, digits, symbols and empty keys as specified.
- Tests: every role transition; the normalization examples of SPEC-03 §7.

### M1.6 — Codec
- Branch: `step/m1-6-codec`
- Depends on: M1.2
- Spec: SPEC-02 §2, ADR 0003
- Scope: `Net/Codec.lua`: envelope `{v, t, ...}`, CBOR (`C_EncodingUtil`), compression above 120 bytes with a flag byte, Base64, 8 KB decompressed limit, unknown fields ignored, newer `v` detected.
- Done when:
  - [ ] Round trip of every message type; malformed input returns an error, never raises.
- Tests: round trips, corrupted and oversized payloads, future version.

### M1.7 — Transport
- Branch: `step/m1-7-transport`
- Depends on: M1.3, M1.6
- Spec: SPEC-02 §4, SPEC-01 §7–§8
- Scope: `Net/Transport.lua`: queues per distribution (CHANNEL, WHISPER, GUILD, OFFICER), ChatThrottleLib priorities, NET-01…NET-04, queue during lockdown and restrictions, result codes, **listen-only mode** on `InvalidChannel`.
- Done when:
  - [ ] Traffic stays within the budget under load; lockdown holds and later releases messages.
- Tests: rate limits with a fake clock, retries, listen-only switch.

### M1.8 — Channel and network simulator
- Branch: `step/m1-8-channel-simulator`
- Depends on: M1.7
- Spec: SPEC-02 §1
- Scope: `Net/Channel.lua` (join `AzGuildFinder`, hide from chat windows, move to the end, filter notices, retry every 60 s, channel limit warning); `Tests/sim/` virtual network with N clients, latency and loss; `/gf debug ping`.
- Done when:
  - [ ] In the simulator, N clients see each other's pings.
  - [ ] **Exit check in game:** two real installations exchange a ping on `AzGuildFinder`.
- Real client: join, hiding, ping.
