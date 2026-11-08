# 0016. English first in the interface; documentation languages

- Status: Accepted
- Date: 2026-11-08 (decision D22)

## Context

The audience is European and multilingual; the owner and the first users are Italian.

## Decision

1. The addon interface is **English** in the first version, with every string behind AceLocale keys, so `itIT` and other languages can be added without touching the code.
2. **Public documentation in English**: README, wiki, ADRs, CONTRIBUTING, CHANGELOG, issues and pull requests. `README.it.md` is the Italian front page.
3. The internal specification in `docs/specs/` is written in **Italian**, with code names, APIs and interface texts in English.
4. Texts written by Guild Masters (subtitle, description) are never translated.

## Consequences

- Positive: reachable by every player; Italian kept where the team works.
- Negative: two README files to keep in step.
