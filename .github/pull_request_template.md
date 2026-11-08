<!--
Write the title and the description in English. Say what changed and WHY, and say honestly what you did NOT verify
(in particular everything that needs the real game client).
-->

## What and why

<!-- A short summary of the change. For a milestone step: the step id (for example M1.2) and its goal. -->

## Not verified

<!-- Everything that could not be checked offline (the real client, other players online...). Write "nothing" if so. -->

## Checklist

Every step or fix PR updates the CHANGELOG, the affected docs and the affected wiki pages **in the same PR**
([CONTRIBUTING.md](../CONTRIBUTING.md), section 5). The wiki is never edited on GitHub: it is published from `docs/wiki/`.

- [ ] I have read and agree to the [Licensing of contributions](../CONTRIBUTING.md#licensing-of-contributions) (GPL-3.0); external contributors signed off their commits (`git commit -s`).
- [ ] The checks pass: `python -I -X utf8 tools/check_docs.py` (and the addon tests, when present). CI must be green before merging.
- [ ] `CHANGELOG.md` is updated in the "Unreleased" section.
- [ ] The docs are updated: `docs/specs/` if behaviour changed, an ADR in `docs/adr/` if a decision changed (and the ADR index), `README.md` **and** `README.it.md` for features, commands and status.
- [ ] **The wiki pages in `docs/wiki/` are updated for any user-visible change.**
- [ ] No personal data anywhere: no names, emails or personal paths (only `Finland6738` and noreply addresses).
- [ ] If the PR is a pure refactor or tests only: the label `no-docs-needed` is set.

Closes #
