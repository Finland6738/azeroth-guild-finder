# 0005. One-click applications delivered through online officers

- Status: Accepted
- Date: 2026-11-08 ([SPEC-07](../specs/SPEC-07-applications.md))

## Context

Applying must be as simple as in Albion (one button), but without a server an application can only reach someone who is online.

## Decision

1. **Apply** sends name, class, race, level and item level, read automatically, plus the roles the player optionally ticks in the confirmation (Tank, Healer, Melee DPS, Ranged DPS, only those possible for the class): no free text. At most **one open application per character** (not per account); it expires after 14 days; after a decline the same guild can be applied to again after 7 days.
2. It is delivered by whisper to a **contact**: the Guild Master or an officer seen online recently (their public announcements carry a contact flag). With no contact online it stays "sent" and is retried each time a contact appears.
3. Officers keep a shared inbox in sync over the `OFFICER` channel; the highest `stateRev` wins.
4. **Invite** uses the game's own guild invite. The applicant learns the result at the next contact.
5. Officers and the Guild Master get a movable notification icon with a badge and a quick list. The Guild Master can close applications through the addon.

## Alternatives considered

- **A form with a free-text message.** More work for new players, more moderation problems. Rejected for the first version.
- **Storing applications at every member.** It spreads applicants' data beyond the officers. Rejected.

## Consequences

- Positive: one click, no external tool, no data outside the guild's officers.
- Negative: applicant and officers must be online at overlapping times; contacts (Discord, whisper) remain the fallback.
