# M3 — Listings

**Goal:** a Guild Master publishes and maintains the guild's listing; members and officers see it in My Guild; listings carry emblems and honest statistics.

**Exit criterion:** a real Guild Master publishes a listing and a second client without a guild sees it within 2 minutes, with the emblem and the statistics.

### M3.1 — Own listing and guild sync
- Branch: `step/m3-1-own-listing`
- Depends on: M2.3
- Spec: SPEC-06 §3–§5, SPEC-02 §7, ADR 0004, ADR 0021
- Scope: `Data/OwnListing.lua`: draft, publish (`rev`, `upd`, `first`, `own`), `GLIST`/`GLREQ` over `GUILD` with the Guild Master check from the roster, delist (`DEL`), Guild Master change, one publish every 5 minutes, `IsGuildLeader()` re-check before saving.
- Done when:
  - [x] Offline: members accept the Guild Master's listing only over `GUILD` and only from the Guild Master of the roster, and refuse one from anybody else (an officer included); copies are ordered by `rev`, then `upd`; delist, the change of Guild Master, the 5-minute limit (also after `/reload`), the `IsGuildLeader()` re-check, `GLREQ` and the relay on the channel are tested; in the simulator the members of a guild receive the Guild Master's listing, refuse a forged one, and a client without a guild sees it in its catalog.
  - [ ] In game: members receive the Guild Master's listing over `GUILD` and refuse one from anybody else ([checklist](../checklists/M3.md)).
- Tests: GM verification, rev ordering, delist, GM change, rate limit.
- Real client: the roster's rank index 0 and the sender name of a `GUILD` addon message (realm suffix), how soon the roster is there after login, `GUILD_RANKS_UPDATE` after a change of Guild Master.

### M3.2 — Editor shell and checklist
- Branch: `step/m3-2-editor-shell`
- Depends on: M3.1, M2.4
- Spec: SPEC-06 §2, mockups [03](../specs/mockups/img/clean/03-listing-editor.webp) and [08](../specs/mockups/img/clean/08-editor-activity.webp)
- Scope: `UI/Editor.lua`: 7-step stepper with status, Back/Next, auto-saved draft, live preview card, "Before publishing" checklist linking to steps, Publish / Save changes / Discard / Delist.
- Done when:
  - [x] Offline: Publish stays disabled, with the reason written under it, until every required item is green, the character is the Guild Master and the 5-minute limit has passed; Save changes also needs a change; the checklist rules, the stepper, the draft auto-save (also after closing the window and `/reload`), Discard changes, Delist, the live preview and the step registration API are tested on the mock client; anybody but the Guild Master gets a note over the page and no save.
  - [ ] In game: the Guild Master sees the stepper, the live preview and the checklist as in the mockups, a click on a checklist item goes to its step, and the draft is still there after `/reload` ([checklist](../checklists/M3.md)).
  - [ ] In game: Publish turns on only when every item is green, shows the reason while it is off, waits out the 5-minute limit, and Delist and Discard changes ask first ([checklist](../checklists/M3.md)).
- Tests: checklist rules, reasons Publish is off, draft auto-save, stepper navigation, step registration (`Tests/test_editor_model.lua`, `Tests/test_ui_editor.lua`).
- Docs: wiki Creating a Listing; SPEC-06 §2 (how the shell is built).
- Real client: look of the stepper, cards and checklist at 60 %, 100 % and 140 %; the Publish button's reason text under the 260 px button; `GUILD_RANKS_UPDATE` while the editor is open.

### M3.3 — Identity and About steps
- Branch: `step/m3-3-identity-about`
- Depends on: M3.2
- Scope: guild name locked from the game, subtitle (60), banner gallery from the verified registry, description (500, 12 lines), main and secondary languages.
- Done when:
  - [x] Offline: the subtitle is cut at 60 characters on one line and the description at 500 characters and 12 lines (counted as `Listing.CleanText` publishes them, UTF-8 characters, a line break counts as a character), both with a counter; the main language is required, the other languages never include it twice, and the checklist follows (`Tests/test_editor_steps.lua`).
  - [ ] In game: the Identity and About pages look like the mockup, the guild name is locked, the counters move as you type and the multi-line box behaves (Enter, paste, 12 lines) ([checklist](../checklists/M3.md)).
  - [ ] In game: the banner gallery shows verified pictures: read the fileIDs in game (M0.7 / the M2 gallery check), fill `Assets.BANNERS` and tick here. Until then no banner is offered and `bg` stays empty.

### M3.4 — Activity step
- Branch: `step/m3-4-activity`
- Depends on: M3.2
- Spec: ADR 0012
- Scope: commitment segmented button (required, explanations), activities chips **max 3** in order with numbers and the "up to 3" hint, days and local time saved as UTC.
- Done when:
  - [x] Offline: the commitment is required (Casual, Softcore or Hardcore, explained under the button); at most 3 activities, kept in the order picked and numbered, a fourth cannot be picked (the others are greyed out with the reason), removing one renumbers the rest; the play days and a local time window are saved as UTC (`t0`/`t1`, the days move with a start that falls on another UTC day), correct across DST and midnight and a round trip with the visitors' conversion `BrowseModel.ToLocal`; the checklist follows (`Tests/test_editor_activity.lua`).
  - [ ] In game: the Activity page looks like the mockup, the chips wrap and number, the time menus and the All day switch behave, and the page fits the window ([checklist](../checklists/M3.md)).
- Tests: max-3 rule, ordering and renumbering, commitment requirement, UTC conversion across DST and midnight (round trip with `BrowseModel.ToLocal`), checklist integration.

### M3.5 — Recruitment, Requirements and Contact steps
- Branch: `step/m3-5-recruitment-contact`
- Depends on: M3.2
- Scope: status, class × role grid (faction classes, impossible pairs disabled, Any class), new player friendly, applications on/off; minimum level, optional item level, note; Discord code with link extraction, up to 3 contacts from the roster.
- Done when:
  - [ ] The grid produces the `want` map of SPEC-03; invalid Discord input is explained.

### M3.6 — Emblems
- Branch: `step/m3-6-emblems`
- Depends on: M0.5, M2.4
- Spec: SPEC-08 §2, ADR 0007, mockup [07](../specs/mockups/img/clean/07-emblem-designer.webp)
- Scope: `UI/Emblem.lua` renderer (background, border, emblem, metal frame; 48/64/96/150 px; fallback shield with initial), tabard read with `GUILDTABARD_UPDATE` prompt, `Data/TabardParts.lua` from M0, the custom designer (background, border style and colour, emblem pages and colour, Random, Reset).
- Done when:
  - [ ] Tabard and custom emblems render identically on every client; unknown fileIDs fall back cleanly.
- Real client: rendering of tabard pieces.

### M3.7 — Statistics and announcements
- Branch: `step/m3-7-stats-announce`
- Depends on: M3.1
- Spec: SPEC-03 §4, SPEC-02 §5, ADR 0006
- Scope: `Data/Stats.lua` (members, active characters, at max level, class mix from the roster), `GTOK` tokens with `want` replies and 7-day store, unique players range, opt-out setting; periodic `ANN` every 30 ± 10 minutes with suppression and the contact flag.
- Done when:
  - [ ] Statistics match SPEC-03 §4 with partial addon coverage; announcements respect the suppression rule.
- Tests: ranges with partial coverage, opt-out, suppression in the simulator.

### M3.8 — My Guild states and milestone check
- Branch: `step/m3-8-my-guild`
- Depends on: M3.1–M3.7
- Spec: SPEC-06 §1, mockup [06](../specs/mockups/img/clean/06-states.webp)
- Scope: My Guild for members (read-only), officers, Guild Master (Edit, Delist); empty states; exit check recorded in `docs/checklists/M3.md`.
- Done when:
  - [ ] Every role sees exactly the panels of SPEC-00 §5.
  - [ ] Exit criterion met in game.
- Docs: wiki Publishing a Listing, Emblems.
