# M4 — Applications

**Goal:** a player applies with one click, officers receive and decide, the player learns the result; officers are notified by a floating icon.

**Exit criterion:** the full flow works in game with an officer online, with the officer coming online later, and with two officers in sync.

### M4.1 — Application model and the applicant's flow
- Branch: `step/m4-1-applicant`
- Depends on: M3.8
- Spec: SPEC-07 §1–§2, §7, ADR 0005
- Scope: `Data/Applications.lua` (record, states, `stateRev`, APP-01…APP-06: one open application **per character**, 14-day expiry, 7-day cooldown after a decline); Apply button states on the card and the guild page; confirmation with **optional role checkboxes** (only roles valid for the class); My Application tab with status, Withdraw, View guild.
- Done when:
  - [x] Offline: `Data/Applications.lua` keeps the record of SPEC-03 §8 per character (`AzerothGuildFinderCharDB.application`), with the states and transitions of SPEC-07 §2 checked pair by pair, `stateRev` raised at every change, APP-01…APP-06 (no guild, one open application per character, `apps = true` and the requirements, the roles of the class only, 14-day expiry, 7-day cooldown after a decline), the officers' conflict rule for M4.3, the repair of damaged saved data, and a clean hook for M4.2 (`Applications:Outbox()`, Bus `APPLICATION_OUTBOX`, `Applications:OnAck`); nothing is sent (`Tests/test_applications.lua`).
  - [x] Offline: every Apply state of SPEC-05 §4 is shown with its reason on the card and on the guild page (on the button, in the tooltip, and in a line under the guild page's button); the confirmation offers only the roles of the player's class, none ticked; My Application shows the status with its explanation, the road, the roles, the expiry, Withdraw (asks first) and View guild, the empty state, and a dot on the tab for a change the player did not make (`Tests/test_ui_apply.lua`).
  - [ ] In game: the Apply button, the confirmation and My Application look like mockups 01, 02 and 06 D, every state reads well at 60 % and 140 %, and an application survives `/reload` and a logout on that character only ([checklist](../checklists/M4.md)).
- Tests: every rule and transition.

### M4.2 — Delivery to officers
- Branch: `step/m4-2-delivery`
- Depends on: M4.1, M3.7
- Spec: SPEC-07 §3, SPEC-02 §3
- Scope: contacts seen in `ANN` with `c=1` (30 minutes), `APPLY`/`APPACK`/`APPPING`/`APPWD` by whisper, retries on each contact appearance, listen-only explanation.
- Done when:
  - [x] Offline: `Net/Delivery.lua` keeps the contacts heard in an `ANN` with `c=1` for 30 minutes (the contact's periodic turn is skipped only for another contact's ANN), whispers `APPLY` / `APPPING` / `APPWD` (ALERT) to the most recent one, tries the next after 15 s without `APPACK`, retries at every contact appearance with a per-contact backoff (60 s doubled up to 30 minutes), takes an `APPACK` only from a contact it whispered, withdraws before and after receipt, at most 6 whispers a minute; the officer side checks every field of an `APPLY` (INT-06, the applicant must be the sender), keeps it in the minimal store `Data/Inbox.lua` (`officerInbox`, 200 per guild) and answers `APPACK`, `APPPING` and `APPWD` (tombstone for an unknown id), at most 6 answers a minute per sender; My Application explains when the game does not let the character send (`Tests/test_delivery.lua`, `Tests/test_stats.lua`).
  - [x] Simulator: an application reaches an officer who comes online hours later (three simulated hours, then one periodic turn), and a decision taken while the applicant was away is learned at the next contact (`Tests/test_delivery.lua`).
  - [ ] In game: an application reaches an officer online and an officer who logs in later, a withdrawal reaches the officer, and a refused whisper is explained ([checklist](../checklists/M4.md)).
- Tests: delivery, retries, withdraw before and after receipt.

### M4.3 — Officer inbox and sync
- Branch: `step/m4-3-inbox-sync`
- Depends on: M4.2
- Spec: SPEC-07 §4
- Scope: `officerInbox` per character, `APPSYNC` over `OFFICER` (or the M0 fallback), conflict rules, 30-day history, cleanup when the officer role is lost, limit 200.
- Done when:
  - [x] Offline: `Data/Inbox.lua` keeps `officerInbox[guildKey]` per character with a version per record that orders every conflict the same way on every client (a final state wins over an open one, then the higher `stateRev`, then accepted > declined > withdrawn > expired, then a complete record over a tombstone, then a hash of `upd` and `by`), merges another officer's copy (a tombstone completed with the application's fields, APP-02 at the newer application's time), expires open records at 14 days at the moment they expired, drops closed ones 30 days after their last change, keeps at most 200 per guild (the oldest closed record makes room; a closed record older than all those kept is not taken back) and repairs damaged saved data; `Net/InboxSync.lua` sends every local change over `OFFICER` within 2 s (10 records a message), the compact list `{id: version}` 5–15 s after login, answers a list with only the ids that differ, asks each missing record from one officer only, checks every field of every message and record (INT-06), at most 10 messages a minute and one message of records per 1.5 s; a character that is no longer a contact stops at once and deletes its boxes a minute after its next login; the `GUILD` fallback of SPEC-02 §7 is one constant, with GUILD messages taken only from a rank that reads officer chat (`Tests/test_inbox_sync.lua`).
  - [x] Simulator: two officers and the Guild Master, each offline while the others act (a decline against an accept of the same application, a withdrawal that reached only one of them, applications only one of them had), converge on the same inbox after their logins; a member hears nothing; 60 records are copied to an officer that logs in, each sent once, within the module's budget (`Tests/test_inbox_sync.lua`).
  - [ ] In game: `OFFICER` carries the addon messages (spike S5, or the `GUILD` fallback is switched on), two officers on two accounts end with the same inbox after one of them was offline, a plain member receives nothing, and a demoted officer's inbox is gone after a relog ([checklist](../checklists/M4.md)).
- Tests: conflicts and final-state precedence.

### M4.4 — Applications panel
- Branch: `step/m4-4-panel`
- Depends on: M4.3, M2.4
- Spec: SPEC-07 §5, mockup [04](../specs/mockups/img/clean/04-applications.webp)
- Scope: `UI/Applications.lua`: Pending / History, application cards (class icon, roles, level, race, item level, time, status), Invite (from M0.6 result), Decline with confirmation, Whisper, counters, notification options.
- Done when:
  - [x] Offline: `UI/ApplicationsModel.lua` (pure Lua) decides who sees the panel (only the Guild Master and the officers), splits the inbox into Pending (newest first) and History (last change first, an open record past 14 days counts as expired), counts them, and builds every field of a card (class, roles, level, race, item level, how long ago, RECEIVED / EXPIRES IN n DAYS / INVITING... / NEW) and of a history line ("by Lyryn · 5 Nov 2026"); `Data/Decisions.lua` declines (`Inbox:Decide`, which the sync sends to the other officers and the applicant learns at its next contact) and invites through `Compat.Guild.Invite` (`C_GuildInfo.Invite`): accepted only when the game's "invited" message arrives or 3 quiet seconds pass without an error, refused with the game's own words (offline, already in a guild, no permission), and with the call missing, restricted or blocked (`ADDON_ACTION_FORBIDDEN`) the fallback `/ginvite Name` in the chat box with "Mark as invited"; the panel (`UI/Applications.lua`) has the Pending / History switch, the counters, the cards with Invite, Decline (asks first) and Whisper, scrolling, the three notification options (also in Settings for the Guild Master and officers, ready for M4.5), the badge on the tab and a line in My Guild (`Tests/test_apps_model.lua`, `Tests/test_decisions.lua`, `Tests/test_ui_applications.lua`).
  - [x] Simulator: a decline or an invite taken by one officer reaches the other officer within seconds and the applicant at its next contact (with the accepted chat line); an invite the game refused changes nothing anywhere; an officer who was away catches up at login (`Tests/test_decisions.lua`).
  - [ ] In game: the panel looks like mockup 04 at 60 % and 140 %, Invite sends the real guild invite (spike S10: from the button, or the `/ginvite` fallback), the offline answer is shown, Decline reaches the applicant, and two officers see the same list ([checklist](../checklists/M4.md)).
- Tests: the view model, the counters, Invite and Decline transitions that sync and notify the applicant, the invite fallback, role visibility.
- Docs: SPEC-07 §5, wiki Managing Applications and Commands and Settings, CHANGELOG, the M4 checklist.
- Real client: Invite.

### M4.5 — Notification icon
- Branch: `step/m4-5-notification`
- Depends on: M4.4
- Spec: SPEC-07 §6, mockup [05](../specs/mockups/img/clean/05-notification.webp)
- Scope: floating metal button with the guild emblem and badge, pulse on new application, quick list (last 5) with Invite and Decline, drag and lock, right-click menu, chat line with "Open", optional sound, `/gf notify`.
- Done when:
  - [ ] Shown only to the Guild Master and officers of a listed guild; position saved per character.

### M4.6 — Closing cases and milestone check
- Branch: `step/m4-6-closing`
- Depends on: M4.1–M4.5
- Scope: `PLAYER_GUILD_UPDATE` closes an application as accepted; delisting declines pending applications; expiry; exit check in `docs/checklists/M4.md`.
- Done when:
  - [ ] Exit criterion met in game.
- Docs: wiki Applying, Managing Applications, FAQ.
