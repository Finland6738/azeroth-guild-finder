# M4 — Applications

**Goal:** a player applies with one click, officers receive and decide, the player learns the result; officers are notified by a floating icon.

**Exit criterion:** the full flow works in game with an officer online, with the officer coming online later, and with two officers in sync.

### M4.1 — Application model and the applicant's flow
- Branch: `step/m4-1-applicant`
- Depends on: M3.8
- Spec: SPEC-07 §1–§2, §7, ADR 0005
- Scope: `Data/Applications.lua` (record, states, `stateRev`, APP-01…APP-06: one open application **per character**, 14-day expiry, 7-day cooldown after a decline); Apply button states on the card and the guild page; confirmation with **optional role checkboxes** (only roles valid for the class); My Application tab with status, Withdraw, View guild.
- Done when:
  - [ ] Every Apply state of SPEC-05 §4 is shown with its reason.
- Tests: every rule and transition.

### M4.2 — Delivery to officers
- Branch: `step/m4-2-delivery`
- Depends on: M4.1, M3.7
- Spec: SPEC-07 §3, SPEC-02 §3
- Scope: contacts seen in `ANN` with `c=1` (30 minutes), `APPLY`/`APPACK`/`APPPING`/`APPWD` by whisper, retries on each contact appearance, listen-only explanation.
- Done when:
  - [ ] Simulator: an application reaches an officer who comes online hours later.
- Tests: delivery, retries, withdraw before and after receipt.

### M4.3 — Officer inbox and sync
- Branch: `step/m4-3-inbox-sync`
- Depends on: M4.2
- Spec: SPEC-07 §4
- Scope: `officerInbox` per character, `APPSYNC` over `OFFICER` (or the M0 fallback), conflict rules, 30-day history, cleanup when the officer role is lost, limit 200.
- Done when:
  - [ ] Two officers converge on the same inbox after offline periods.
- Tests: conflicts and final-state precedence.

### M4.4 — Applications panel
- Branch: `step/m4-4-panel`
- Depends on: M4.3, M2.4
- Spec: SPEC-07 §5, mockup [04](../specs/mockups/img/clean/04-applications.webp)
- Scope: `UI/Applications.lua`: Pending / History, application cards (class icon, roles, level, race, item level, time, status), Invite (from M0.6 result), Decline with confirmation, Whisper, counters, notification options.
- Done when:
  - [ ] Invite and Decline change the state and reach the applicant.
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
