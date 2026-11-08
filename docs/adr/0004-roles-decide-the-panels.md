# 0004. The player's guild role decides the panels

- Status: Accepted
- Date: 2026-11-08 ([SPEC-00 §5](../specs/SPEC-00-vision-scope.md))

## Context

Albion Online shows the same three tabs to everyone. Here each kind of player needs something different, and showing other guilds to someone who already has one only adds noise.

## Decision

| Role (read from the client) | Panels |
|---|---|
| No guild | Find a Guild, My Application |
| Member | My Guild (read-only) |
| Officer (`C_GuildInfo.IsGuildOfficer()`) | My Guild (read-only), Applications |
| Guild Master (`IsGuildLeader()`), no listing | Create Listing only |
| Guild Master, listing published | My Guild (edit, delist), Applications |

Only the **actual Guild Master** creates or edits a listing, and the guild name is read from the game, never typed. The role is read again on guild and rank events, and before every save. Settings are always the first entry of the side rail.

## Alternatives considered

- **The same tabs for everyone.** Simpler, but it shows actions a player cannot use. Rejected.

## Consequences

- Positive: each player sees only what they can use; nobody can publish a listing for a guild by typing its name.
- Negative: a guild member cannot browse other guilds from the addon.
