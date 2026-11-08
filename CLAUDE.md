# Instructions for development sessions

The owner speaks Italian: talk to them in Italian. Code, commits, pull requests, issues, README, wiki and ADRs are in English; the specification in `docs/specs/` is in Italian ([ADR 0016](docs/adr/0016-english-first-ui-and-documentation-languages.md)).

## Where things are

- Specification: `docs/specs/` (SPEC-00…SPEC-10). Decisions: `docs/adr/` (index in `docs/adr/README.md`). User manual: `docs/wiki/`. Plan: `ROADMAP.md`.
- Mockups: `docs/specs/mockups/html/` (sources) → `bash docs/specs/mockups/render.sh` → `docs/specs/mockups/img/` (WebP).
- WoW Forever API dump: `../WoW-Addons/docs/api.json` (consult only, never copy, [ADR 0002](docs/adr/0002-wow-forever-target-and-api-dump.md)).

## Git automation (authorized by the owner, ADR 0013)

For every milestone step or fix:

1. Branch from an up-to-date `main`: `step/m<N>-<name>` (or `fix/…`, `docs/…`, `chore/…`). Never commit to `main`.
2. Do the work. In the same branch update `CHANGELOG.md`, the affected specs/ADRs (and the ADR index), `README.md` + `README.it.md` when features or status change, and `docs/wiki/` for anything user-visible.
3. Run `python -I -X utf8 tools/check_docs.py` (plus the addon tests once they exist).
4. Write the pull request body (what and why, what was **not** verified in the real client) and ship **without asking**:
   `python -I -X utf8 tools/ship_step.py --title "M<N>: <summary>" --body-file <file> --commit "<message>"`
   It pushes, opens the PR, waits for CI and squash merges. If it stops, leave the PR open and report why.
5. The wiki is published by the `Wiki sync` workflow after the merge: never edit the wiki on GitHub.

Do not decide alone what belongs to the owner (licence, names, scope, deleting their data): ask, or open an issue with the options.

## Privacy

No personal data in the repository: no real names, emails (only GitHub noreply addresses), or personal paths (use `<WoW folder>` and similar). `tools/check_docs.py` fails on them.
