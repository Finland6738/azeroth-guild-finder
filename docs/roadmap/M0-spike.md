# M0 — Spike in the real client

**Goal:** answer, in the real WoW Forever client, the questions the design cannot answer offline ([SPEC-09 §1](../specs/SPEC-09-quality-release.md#1-spike-tecnico-m0)), before writing the addon.

**Who:** the owner in game, ideally with two accounts or a second player; the session prepares the probe and reads the results.

**Exit criterion:** `docs/spike/M0-results.md` answers S1–S11, the affected specs and ADRs are updated, and there is a clear **go / revise** decision for the peer-to-peer design.

The probe addon `AzGF_Probe` lives in `tools/probe/` and is **never distributed**. It uses a **test channel** (`AzGFProbe`), never the real `AzGuildFinder`, because a joined channel may stay in the game's list.

### M0.1 — Probe addon skeleton
- Branch: `step/m0-1-probe-skeleton`
- Depends on: —
- Spec: SPEC-09 §1, ADR 0002
- Scope: `tools/probe/AzGF_Probe/` (TOC 16001, one Lua file), `/agfp` commands, a results table saved in `AzGF_ProbeDB`, `/agfp export` showing all results as text to copy; `tools/install_probe.py` to copy it into the AddOns folder (path read from `tools/local.ini`, not tracked).
- Done when:
  - [ ] The probe loads on Forever without errors and `/agfp` lists the checks. *(in game; not verified yet)*
  - [ ] Every check writes `{id, result, details, build, time}`; `/agfp export` copies them. *(in game; not verified yet)*
  - [x] Offline: probe files, `/agfp` commands, check registry, `tools/install_probe.py` and `docs/spike/README.md` exist; `check_docs.py` passes.
- Tests: none (it is a throwaway tool); `check_docs.py` passes.
- Docs: `docs/spike/README.md` with how to install and run the probe.
- Real client: everything.

### M0.2 — Environment and Club Finder (S1, S7, S11)
- Branch: `step/m0-2-environment`
- Depends on: M0.1
- Scope: checks for `C_ClubFinder.IsEnabled/ShouldShowClubFinder/GetClubFinderDisableReason`; presence and results of `GetGuildInfo`, `GetNumGuildMembers`, `GetGuildRosterInfo`, `GetGuildRosterLastOnline`, `GetMaxPlayerLevel`, `GetAverageItemLevel`, `C_Club.GetGuildClubId`/`GetMemberInfo`; `C_ChatInfo.InChatMessagingLockdown` and `AreOutgoingAddonChatMessagesRestricted` outside and inside an instance, a battleground and combat.
- Done when:
  - [ ] S1 answered: Club Finder enabled or not, with the reason.
  - [ ] S7 answered: which guild functions exist and what they return (names replaced with placeholders).
  - [ ] S11 answered: when chat lockdown is active.
- Real client: everything.

### M0.3 — Channel messaging and throttling (S2, S3, S6)
- Branch: `step/m0-3-channel`
- Depends on: M0.1
- Scope: join `AzGFProbe` with `JoinChannelByName`, hide it, send and receive `SendAddonMessage(..., "CHANNEL", id)` between two clients; record `SendAddonMessageResult` codes; burst test to find the throttle; repeat with characters of level 1, 5, 10, 20 and, if possible, a new or trial account.
- Done when:
  - [ ] S2: two clients exchange messages in the channel.
  - [ ] S3: the lowest level (or play time) that can send is known.
  - [ ] S6: safe sending rate measured; `CHANNEL_GAP` confirmed or changed.
  - [x] Offline: `Checks_Channel.lua` (join, hide, filter, ping/pong, burst, level and account flags), the `/agfp` commands and the owner instructions in `docs/spike/README.md` exist; `check_docs.py` passes.
- Real client: everything.

### M0.4 — Whisper and officer channel (S4, S5)
- Branch: `step/m0-4-whisper-officer`
- Depends on: M0.1
- Scope: addon whisper to a non-friend (also from a low-level character); addon messages on `OFFICER` from an officer and from a plain member.
- Done when:
  - [ ] S4: addon whispers work (or not) for low-level characters.
  - [ ] S5: `OFFICER` works as an addon channel, or the fallback over `GUILD` is chosen.
- Real client: everything.

### M0.5 — Tabard pieces and textures (S8, S9)
- Branch: `step/m0-5-tabard-textures`
- Depends on: M0.1
- Scope: `C_GuildInfo.GetGuildTabardInfo("player")` fields; a hidden `TabardModel` cycled with `CycleVariation` over every variation, recording `GetUpper*File` fileIDs and colours (never `Save()`); a texture gallery for the banner candidates, the parchment, class icons (`ClassIcon_<Class>` vs the `classicon-<class>` atlas) and the role icons.
- Done when:
  - [ ] S8: the tabard structure is documented and a list of emblem, border and background fileIDs and colours is exported.
  - [ ] S9: 12–16 banner images and the parchment are verified, with fileIDs.
  - [x] Offline: `Checks_Tabard.lua` (info dump, `TabardModel` catalogue, `/agfp tabard`, `/agfp export tabard`), `Checks_Textures.lua` (gallery, `/agfp tex`, `/agfp mark`, `/agfp export gallery`) and the owner instructions in `docs/spike/README.md` exist; `check_docs.py` passes.
- Real client: everything.

### M0.6 — Guild invite (S10)
- Branch: `step/m0-6-invite`
- Depends on: M0.1
- Scope: `C_GuildInfo.Invite(name)` called from a button click (hardware event) and from a timer; result and error messages.
- Done when:
  - [ ] S10: whether Invite can be called from the addon's button, or the `/ginvite` fallback is needed.
- Real client: everything.

### M0.7 — Results and decisions
> **M0.7 deferred** until the owner's in-game results; M1+ proceed on the specification's assumptions and will be revised after M0.7.
- Branch: `step/m0-7-results`
- Depends on: M0.2–M0.6
- Scope: `docs/spike/M0-results.md` (one row per check, with the evidence), updates to SPEC-01/02/07/08/09 and ADRs (new ADRs for any changed decision), `Data/TabardParts` and banner registry values recorded for M3.
- Done when:
  - [ ] Every check S1–S11 has a result and a consequence.
  - [ ] Go / revise decision written; if S1 is positive, a revised plan for M1–M4 is proposed to the owner before continuing.
- Docs: specs, ADRs, ROADMAP, README status.
