# 0006. Honest, aggregate statistics only

- Status: Accepted
- Date: 2026-11-08 ([SPEC-03 §4](../specs/SPEC-03-data-model.md))

## Context

Total member counts hide inactive guilds. Players want to know how alive a guild is, but individual members must not be exposed.

## Decision

1. Only aggregates are published: total members, **active characters in the last 7 days**, **unique active players** (an estimate), characters at max level, and the class mix of active characters.
2. Unique players are estimated with anonymous tokens: each installation hashes a local secret with the guild key and tells its own guild (over `GUILD` only) the token and the **number** of its active characters, never their names. When not every member uses the addon the page shows a range ("19–24") with an explanation. Members can opt out.
3. **No founding date**: the client offers no reliable source. "Listed since" and "Updated" are shown instead.
4. No rankings, scores or leaderboards.

## Consequences

- Positive: numbers that reflect real activity; nothing personal is published.
- Negative: unique players are an estimate; raid progress and PvP statistics wait for a later version.
