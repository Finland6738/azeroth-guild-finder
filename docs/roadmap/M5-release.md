# M5 — Release

**Goal:** a complete, polished, documented addon published on GitHub Releases and CurseForge.

**Exit criterion:** `v1.0.0` published on both, with the release checklist passed and the wiki up to date.

### M5.1 — Settings page
- Branch: `step/m5-1-settings`
- Spec: SPEC-04 §4
- Scope: Settings panel (`Settings.RegisterCanvasLayoutCategory`) and the Settings rail page: minimap button, notification icon and "only when pending", sound, anonymous alt count, scale, reset positions.
- Done when:
  - [x] Offline: one definition of the options (`UI/SettingsModel.lua`: minimap button, window size, anonymous alt count, notification icon, only when pending, sound; defaults taken from `Config.defaults` and equal to the wiki table) is drawn by one builder (`UI/SettingsPage.lua`) for both the Settings rail page and the panel in the game's Settings window (`Settings.RegisterCanvasLayoutCategory`, skipped with a note in `/gf debug` when the client lacks it); every option persists across a reload, applies at once (minimap button, window scale, Stats sharing, notification icon, Bus event), a damaged value falls back to its default, *Reset window position* puts back the window and the notification icon, the panel's Defaults button restores everything (`Tests/test_settings.lua`).
  - [ ] In game: the panel appears under *Options → AddOns* (or is absent without breaking anything), the page and the panel show the same values and follow each other, every option takes effect and is kept after `/reload` and a logout ([checklist](../checklists/M5.md)).

### M5.2 — Visual polish and accessibility
- Branch: `step/m5-2-polish`
- Scope: final nine-slice textures, shadows and grain; contrast check; tooltips on every icon; 1280 × 720 and scales 64–140 %; keyboard: Esc, Backspace for Back.
- Done when:
  - [ ] The real window matches the design system; no text under 12 px at 100 %.
- Real client: everything.

### M5.3 — Localization readiness
- Branch: `step/m5-3-l10n`
- Scope: every visible string through `L[...]`; a test that fails on hard-coded strings in `UI/`; key naming guide; `itIT` left for V2.
- Done when:
  - [ ] The string audit test passes.

### M5.4 — Diagnostics
- Branch: `step/m5-4-diagnostics`
- Scope: `/gf debug` report (versions, capabilities, catalog size, sync state, last errors, listen-only reason) in a copy box, with no player names.
- Done when:
  - [ ] The bug report form's "debug output" can be filled from it.

### M5.5 — Packaging and release workflow
- Branch: `step/m5-5-packaging`
- Spec: SPEC-09 §4
- Scope: `.github/workflows/release.yml` with the BigWigs packager on a version tag: GitHub Release and CurseForge upload (secret `CF_API_KEY`, project id in the TOC); `## Version: @project-version@`; `.pkgmeta` ignores `Tests/`, `docs/`, `tools/`.
- Done when:
  - [ ] A test tag produces a correct zip on a draft release.
- Needs the owner: the CurseForge project and its API token.

### M5.6 — Beta v0.9
- Branch: `step/m5-6-beta`
- Scope: release checklist in `docs/checklists/release.md` (roles, sync, applications, reload, combat, instances, scaling), beta with a few real guilds, an Announcements discussion, fixes as `fix/...` branches.
- Done when:
  - [ ] Checklist passed; no open `priority:high` bug.

### M5.7 — v1.0.0
- Branch: `step/m5-7-release`
- Scope: version bump, CHANGELOG release section, README and wiki status "released", CurseForge description, announcement.
- Done when:
  - [ ] `v1.0.0` is on GitHub Releases and CurseForge.
