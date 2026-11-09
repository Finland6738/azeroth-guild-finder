# M2 — Find a Guild

**Goal:** a player without a guild opens `/gf`, sees the catalog fill from the network, searches and filters it, and opens a guild page.

**Exit criterion:** in the simulator 50 clients and 100 guilds converge in under 5 simulated minutes within the traffic budget; in game, a test listing announced by one client appears in the list of another.

### M2.1 — Enums, listing schema and validation
- Branch: `step/m2-1-schema`
- Depends on: M1.5
- Spec: SPEC-03 §2–§6, ADR 0012
- Scope: `Data/Enums.lua` (languages, 13 activities, commitment, roles, class-role validity, faction classes), `Data/Listing.lua` (summary and detail records, `Sanitize`, text escaping, Discord code extraction), ordered `tags` (1–3) and `pace`.
- Done when:
  - [x] Every field of SPEC-03 §2–§3 is validated as specified.
- Tests: limits, escaping of `|`, UTF-8 lengths, invalid enums, Discord link forms.

### M2.2 — Catalog store
- Branch: `step/m2-2-catalog`
- Depends on: M2.1, M1.4
- Spec: SPEC-02 §8, SPEC-03 §1, SPEC-05 §1
- Scope: `Data/Catalog.lua`: per realm and faction, merge rules INT-01…INT-05, staleness (14 days "may be inactive", hidden at 30, purged at 60), 500-listing limit, search and filter index, `CATALOG_UPDATED`.
- Done when:
  - [x] Conflicting and late updates converge to the same listing on every client.
- Tests: ordering, ownerId conflicts, one-guild-per-sender rule, delist and re-announce, expiry.

### M2.3 — Catalog sync
- Branch: `step/m2-3-sync`
- Depends on: M2.2, M1.8
- Spec: SPEC-02 §3, §5, §6
- Scope: `Net/Sync.lua`: receive `ANN`/`DEL`; `CATREQ` with digest, `CATACK` suppression, `CAT` by whisper in batches of 10; `DETREQ`/`DETACK`/`DET`; retries and back-off; a dev-only `/gf debug announce` that sends a **test** listing ignored by release builds.
- Done when:
  - [x] Simulator: 50 clients and 100 guilds converge in < 5 simulated minutes without exceeding NET-01.
  - [ ] In game: a test listing announced by one client appears in another ([checklist](../checklists/M2.md)).
- Tests: the simulator scenario, message loss, listen-only clients.
- Real client: the exit check of the milestone.

### M2.4 — Main window and widgets
- Branch: `step/m2-4-window-widgets`
- Depends on: M1.5
- Spec: SPEC-04, ADR 0008, mockup [00](../specs/mockups/img/clean/00-design-system.webp)
- Scope: `UI/Main.lua` (book layout, side rail with Settings first and role tabs, gold close button, Esc, drag, scale 60–140 %, saved position, page stack with Back), `UI/Widgets/` (pill buttons, chips, switches, segmented, fields, copy field, cards, tags, badges, role badges, class icons with class-colour ring, tooltip, snackbar), `Media/` nine-slice textures, Roboto and Roboto Mono font objects; minimap button (LibDBIcon), Addon Compartment, key binding, `/gf`.
- Done when:
  - [x] Offline: the role → tabs mapping, the page stacks, the scale and the position are tested; in the mock client all four entry points open the window and it shows the tabs of the current role.
  - [ ] In game: the window opens from all four entry points and shows the tabs of the current role ([checklist](../checklists/M2.md)).
  - [ ] In game: widgets match the design system at 100 % and stay readable at 60 % and 140 % ([checklist](../checklists/M2.md)).
- Tests: role → tabs mapping; page stack.
- Docs: wiki Interface Tour, Commands and Settings.
- Real client: look and feel, fonts (Roboto and Roboto Mono are bundled, see ADR 0020: check that the client loads them), scaling.

### M2.5 — Find a Guild list
- Branch: `step/m2-5-list`
- Depends on: M2.2, M2.4
- Spec: SPEC-05 §1, mockup [01](../specs/mockups/img/clean/01-browse.webp)
- Scope: `UI/Browse.lua`: search box (3 letters, normalized), result count and "Sorted A → Z", guild cards (emblem placeholder until M3.6, banner, tags, commitment, info band), virtual scrolling, status bar, empty and loading states; `/gf debug seed` fills the **local** catalog with fake listings (never broadcast).
- Done when:
  - [x] Offline: 500 listings scroll through a pool of six row frames in the mock client; ordering and search follow SPEC-03 §7; the states and their messages are tested.
  - [ ] In game: 500 listings (`/gf debug seed 500`) scroll smoothly; ordering and search follow SPEC-03 §7 ([checklist](../checklists/M2.md)).
  - [ ] In game: the cards, states and status bar match the mockup ([checklist](../checklists/M2.md)).
- Tests: ordering, search, state messages, recycling of the virtual scroll with 500 listings, throttle and debounce.
- Docs: wiki Finding a Guild, Commands and Settings.
- Real client: scrolling feel, clipping of the cards, class icons, banner fileIDs (`Assets.BANNERS`), the spinner.

### M2.6 — Filters
- Branch: `step/m2-6-filters`
- Depends on: M2.5
- Spec: SPEC-05 §2
- Scope: left-page filters (recruiting, my class, requirements, new players, role, language, commitment, activity, days and local time across midnight, minimum active members), saved per character, active count, reset. The rules are a pure module (`UI/FilterModel.lua`); `UI/FilterPanel.lua` only draws the controls.
- Done when:
  - [x] Offline: every filter rule of SPEC-05 §2 is applied (each filter, combinations, the active count and the reset, the state saved per character and repaired when damaged, play times across midnight and across time zones), and the controls drive the list on the mock client.
  - [ ] In game: the filters narrow the list as SPEC-05 §2 says and survive `/reload` and a relog ([checklist](../checklists/M2.md)).
  - [ ] In game: the left page matches the mockup and every list opens and scrolls correctly at 60 %, 100 % and 140 % ([checklist](../checklists/M2.md)).
- Tests: each filter, combinations, time ranges across midnight and time zones (`Tests/test_filter_model.lua`); the panel, the count, the reset and the saved state (`Tests/test_ui_filters.lua`); the new widgets (`Tests/test_ui_widgets.lua`).
- Docs: wiki Finding a Guild.
- Real client: the look of the left page, the lists (selects) over the other controls, the role icons in the chips, the behaviour of the mouse wheel in a long list, the time zone and daylight saving of the computer.

### M2.7 — Guild page (visitor)
- Branch: `step/m2-7-guild-page`
- Depends on: M2.5, M2.3
- Spec: SPEC-05 §3, mockup [02](../specs/mockups/img/clean/02-guild-page.webp)
- Scope: `UI/GuildPage.lua`: left page (emblem, name, tags, Discord copy field with select-all, contacts with Whisper), right page (banner, gold "Looking for" card with role legend and "they need your class", About, Activity, Members, Requirements checked against the player, How applying works), details loading and unavailable states. The Apply button is hidden until M4.
- Done when:
  - [x] Offline: the page renders from a summary only and completes when the detail arrives (or says it is unavailable after 20 s); the requirements are checked against the player, days and times are shown in the player's time zone, the Discord field, the contacts with Whisper, "Looking for" with "they need your class" and the members numbers come from the model, and the page copes with a listing that goes away or has missing fields, on the mock client.
  - [ ] In game: the page matches the mockup, the detail arrives from another client and completes the page, Whisper opens the chat box, the Discord field copies, the page scrolls ([checklist](../checklists/M2.md)).
- Tests: requirement checks, local time conversion, "Looking for", members, layout arithmetic (`Tests/test_guild_page_model.lua`); the page on the mock client: summary only, detail arriving, unavailable, late detail, contacts, Whisper, listing gone, scrolling, the development seed (`Tests/test_ui_guild_page.lua`).
- Docs: wiki Finding a Guild, The Guild Page.
- Real client: the look of both pages (the wrapped texts and the height of the right page depend on the font), the banner fileIDs (`Assets.BANNERS`, still empty), `ChatFrame_OpenChat` on Forever, the Discord field's select-all, the mouse wheel over the cards, whether a contact heard in the last hour is really online.

### M2.8 — Milestone check and docs
- Branch: `step/m2-8-check`
- Depends on: M2.1–M2.7
- Scope: run the exit checks, record results in `docs/checklists/M2.md`, update README status and wiki screenshots if the real window differs from the mockups.
- Done when:
  - [ ] Exit criterion met and recorded.
