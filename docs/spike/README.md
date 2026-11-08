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
| `/agfp export` | Opens a movable frame with all results as plain text, already selected: press Ctrl+C |
| `/agfp reset` | Clears the stored results |

Results are saved in `AzGF_ProbeDB.results[id]` as `{id, result, details, build, time}` where `result` is `pass`, `fail`, `info` or `todo`. Checks not yet implemented record "not implemented yet"; S1, S7 and S11 are implemented in M0.2 (`Checks_Environment.lua`), the others follow in M0.3–M0.6. Snapshots are stored in `AzGF_ProbeDB.snapshots` and included in `/agfp export`.

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
