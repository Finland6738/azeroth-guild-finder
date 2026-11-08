# 0013. Git flow and automated shipping of milestone steps

- Status: Accepted
- Date: 2026-11-08 (same rules as azeroth-unspoken, ADR 0009 there)

## Context

The project is developed in milestone steps, often by automated sessions while the owner is away. The owner asked that every finished step is committed, pushed, opened as a pull request and merged **automatically**, and that the wiki follows every change.

## Decision

1. `main` is always working; nobody commits to it directly (the only exception was the initial bootstrap commit of the empty repository).
2. One branch per step from an up-to-date `main`: `step/m<N>-<name>` for roadmap steps, `fix/…`, `docs/…`, `chore/…` for the rest.
3. Small commits; messages, pull requests and issues in English.
4. **Authorized automation**: when a step is finished, `python -I -X utf8 tools/ship_step.py --title … --body-file …` runs the local checks, merges `origin/main` if needed, pushes, opens the pull request, waits for the required CI checks and, only if they are green, squash merges with `--delete-branch`. On any failure it stops and the pull request stays open with the reason.
5. Every pull request says honestly what was **not** verified, especially anything that needs the real client.
6. Never `--force` on `main`, never rewrite published history, never skip hooks.
7. Choices that belong to the owner (licence, names, scope) are not made autonomously: an issue is opened with the options.

## Consequences

- Positive: one readable commit per step on `main`, no manual merge work, CI as the gate.
- Negative: no human review before merge; the checks must be good enough to be trusted.
