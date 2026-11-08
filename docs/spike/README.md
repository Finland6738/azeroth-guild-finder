# Spike: the probe addon

`AzGF_Probe` is a **throwaway** addon used in milestone M0 to answer, in the real WoW Forever client, the questions the design cannot answer offline ([SPEC-09 §1](../specs/SPEC-09-quality-release.md#1-spike-tecnico-m0), in Italian). It lives in `tools/probe/AzGF_Probe/` and is **never distributed**: it is not part of any release.

Safety rules of the probe: every game API call is wrapped in `pcall`, no player or guild name is ever printed or stored (placeholders only), and it never joins or sends to the real channel `AzGuildFinder`; the later steps use the test channel `AzGFProbe`.

## Install

1. Copy `tools/local.example.ini` to `tools/local.ini` (git-ignored) and set `addons` to your `Interface/AddOns` folder of WoW Forever.
2. Run:

```bash
python -I -X utf8 tools/install_probe.py
```

3. In game, `/reload` (or restart the client). The chat shows "AzGF Probe: loaded".

## Commands

| Command | What it does |
|---|---|
| `/agfp` or `/agfp list` | Lists the checks S1–S11 with a short description and the last result |
| `/agfp run <id>` | Runs one check, for example `/agfp run S1` |
| `/agfp snapshot <label>` | Stores a chat-lockdown snapshot (S11) tagged with your label, for example `/agfp snapshot dungeon` |
| `/agfp join` | Joins the **test channel** `AzGFProbe`, hides it from every chat frame and filters its notices (S2) |
| `/agfp leave` | Leaves the test channel and stops rejoining at login |
| `/agfp ping` | Sends one small addon message to the channel and records the result code (S2, S3) |
| `/agfp pong [on\|off]` | Toggles the automatic reply: with it ON, this client answers every ping from another client so the sender sees the round trip |
| `/agfp burst <n> <gapSeconds>` | Sends `n` messages of about 200 bytes with a fixed gap and records the result codes (S6); `/agfp burst stop` aborts |
| `/agfp channel` | Prints the channel status, the counters and the bursts seen by this client |
| `/agfp export` | Opens a movable frame with all results as plain text, already selected: press Ctrl+C |
| `/agfp reset` | Clears the stored results |

Results are saved in `AzGF_ProbeDB.results[id]` as `{id, result, details, build, time}` where `result` is `pass`, `fail`, `info` or `todo`. Checks not yet implemented record "not implemented yet"; S1, S7 and S11 are implemented in M0.2 (`Checks_Environment.lua`), S2, S3 and S6 in M0.3 (`Checks_Channel.lua`), the others follow in M0.4–M0.6. Snapshots are stored in `AzGF_ProbeDB.snapshots` and included in `/agfp export`.

## M0.2: what to do in game (S1, S7, S11)

No names are ever stored or printed: only counts, types and field names. After `/reload` run the commands below and then `/agfp export`.

**S1, Club Finder.** Log in with any character (guilded or not, any level; ideally one of each) and run `/agfp run S1`. It records whether `C_ClubFinder.IsEnabled`, `ShouldShowClubFinder`, `GetClubFinderDisableReason` and `IsCommunityFinderEnabled` exist and what they return. Also note, outside the probe, whether the Guild Finder button or tab exists in the Communities/Guild window, and tell it in the report.

**S7, guild APIs.** Stand anywhere in a city, with a character **in a guild** (the more members, the better) and run `/agfp run S7`. The roster arrives asynchronously: wait up to 10 seconds and the final line is printed in chat ("S7 [info] ... GUILD_ROSTER_UPDATE after ..."). Repeat with a character **without a guild** (the guild-dependent calls are then reported as not run). If you can, repeat as a guild officer and as a plain member.

**S11, chat lockdown.** Capture a snapshot in each situation, with `/agfp snapshot <label>`:

1. `/agfp snapshot outside`: standing in a city or the open world, out of combat.
2. `/agfp snapshot combat`: in combat (attack a training dummy or a mob).
3. `/agfp snapshot dungeon`: inside a dungeon instance, before and during a boss encounter (`dungeon-boss`).
4. `/agfp snapshot battleground`: inside a battleground, during the match.
5. Any other context you suspect (raid, arena, scenario, Mythic+): use a clear label.

Then `/agfp run S11` once (it records one more snapshot) and `/agfp export`: all snapshots are listed after the check results.

## M0.3: what to do in game (S2, S3, S6)

The probe only ever uses the **test channel** `AzGFProbe` and the test prefix `AzGFP`: never the real `AzGuildFinder`. The channel is a normal (permanent) custom channel, joined with `JoinChannelByName`, removed from all chat frames and moved to the end of the channel list, and its join/leave notices are hidden. Names are never printed or saved: other players appear as `<peer 1>`, `<peer 2>`, ... and your own echo as `<self>`. Every game call is in `pcall`.

You need **two clients that can be in the same channel**: two accounts on the same realm and faction, or you and a friend who installs the probe too (`tools/install_probe.py`). Both run `/reload` first. Call them **A** (sender) and **B** (receiver).

**S2, exchange in the channel.**

1. A and B: `/agfp join`. Within 3 seconds chat says "joined the test channel (index N)". If it says it could not join after 3 attempts, that is already a result: note your level and run `/agfp export` (the join log includes the channel notices). The probe rejoins automatically at every login until you run `/agfp leave`.
2. B: `/agfp pong on` (auto-reply).
3. A: `/agfp ping`. A prints "ping #1 sent, result 0:Success" (or another code) and, if B answered, "pong for ping #1 from <peer 1>: round trip N ms".
4. Do it again the other way round (`/agfp pong on` on A, `/agfp ping` on B), so both directions are measured.
5. Both: `/agfp run S2` and `/agfp export`. The export lists every send (kind, length, result code with its enum name) and every receive (kind, peer placeholder, channel, length, one-way delay in whole seconds from the server clocks, round trip in ms for pongs). S2 is `pass` only if this client both sent with result 0 and received a message from another client.
6. Finally `/agfp leave` on both and look at the game's channel list: does `AzGFProbe` stay there? Tell it in the report.

Also report the `Enum.SendAddonMessageResult{...}` line of the export: it is the real table of result codes.

**S3, lowest level that can send.** Repeat on characters of **level 1, 5, 10 and 20** (and on a new, trial or starter account if you have one; the export records `IsTrialAccount`, `IsVeteranTrialAccount`, `IsRestrictedAccount` and the total play time). On each character, with the other client **B already in the channel** and `/agfp pong on`:

1. `/reload`, then `/agfp join`: does the join work at this level? (the S3 line counts joins ok and failed per level)
2. `/agfp ping` three times, a few seconds apart. Result `0:Success` and B receives it: this level can send. Result `7:InvalidChannel` (or another error): it cannot. If the result is 0 but B receives nothing, note that too: the server dropped it silently.
3. `/agfp run S3`, then `/agfp export`: one `S3 L<level> ...` line per level and account kind, with joins, sends, result codes and messages received from others.

The answer for the spec is the lowest level (or play time) with sends ok **and** received by B. All characters of the account share the saved results, so a single `/agfp export` at the end is enough.

**S6, throttle.** Both clients in the channel, with characters that can send (S3 ok), away from combat, instances and battlegrounds (the lockdown would hide the throttle). B only listens. A runs the bursts below in order, waiting about 30 seconds between them so the throttle recovers:

| Burst | Command on A | Duration |
|---|---|---|
| 1 | `/agfp burst 20 2.0` | about 40 s |
| 2 | `/agfp burst 20 1.2` | about 24 s (the `CHANNEL_GAP` of the spec) |
| 3 | `/agfp burst 20 0.8` | about 16 s |
| 4 | `/agfp burst 20 0.5` | about 10 s |
| 5 | `/agfp burst 30 0.25` | about 8 s |

After each burst A prints "burst N finished: X/Y sent OK, throttled Z, first failure at I (code)". At the end B runs `/agfp channel` (or `/agfp run S6`) and both run `/agfp export`: for every burst the receiver lists `got X/n` and `missing[...]` (the gaps before the last message received; a burst that stops early shows `got < n`).

How to read it, gap by gap:

- **A sent everything with `0:Success` and B got all n**: the gap is safe.
- **A got throttle codes (`AddonMessageThrottle`, `ChannelThrottle`, others)**: the client refused to send from message I on: the gap is too small, and I tells how many messages the bucket allows in a burst before it starts.
- **A got only `0:Success` but B got fewer than n**: the server dropped messages silently, which is worse than a visible code: that gap is not safe even though the client did not complain.
- **Deciding `CHANNEL_GAP`**: keep 1.2 s if the 1.2 s burst is clean (no failure, nothing lost). If it is not, use the smallest clean gap of the sequence above it (2.0 s) and record it. If 0.8 s and faster are clean too, 1.2 s stays as the safety margin. A gap is valid only if the "actual gap min/avg/max" of the export is close to the announced one (timers wait whole frames).
- Repeat the clean gap with B sending to A, to see whether the limit is per client.

Send the exports of A and B in the report. `/agfp reset` clears everything before a new session.

## Reporting results

Run `/agfp export`, copy the text and paste it into an issue using the **In-game test report** form. The decisions are collected in `docs/spike/M0-results.md` in step M0.7.

## Checks

| # | Check | Step | Result |
|---|---|---|---|
| S1 | Club Finder enabled or not, and why | M0.2 | |
| S2 | Join the test channel, exchange addon messages | M0.3 | |
| S3 | Lowest level or play time that can send in the channel | M0.3 | |
| S4 | Addon whisper to a non-friend, also from a low-level character | M0.4 | |
| S5 | `OFFICER` as an addon channel | M0.4 | |
| S6 | Real channel throttle | M0.3 | |
| S7 | Guild globals and `C_Club` | M0.2 | |
| S8 | Tabard info and `CycleVariation` catalogue | M0.5 | |
| S9 | Banner, parchment, class and role textures | M0.5 | |
| S10 | `C_GuildInfo.Invite` from an addon button | M0.6 | |
| S11 | Chat messaging lockdown | M0.2 | |
