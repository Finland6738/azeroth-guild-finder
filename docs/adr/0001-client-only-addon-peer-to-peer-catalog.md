# 0001. A client-only addon with a peer-to-peer catalog

- Status: Accepted
- Date: 2026-11-08 (decision D2 of [SPEC-00](../specs/SPEC-00-vision-scope.md))

## Context

WoW Forever has no guild finder for players without a guild. An addon cannot run code on Blizzard's servers, and the project does not want an external service (a website or a bot) that players would have to trust, pay for or keep online. Guild listings must still reach players who are not in the guild that wrote them.

## Decision

1. **Only the addon**: no server, no website, no external database.
2. **The catalog lives in every client**: each installation keeps the listings it has seen in its SavedVariables and exchanges them with the other installations over a hidden custom chat channel ([ADR 0003](0003-hidden-channel-and-versioned-protocol.md)).
3. **The guild is the source of truth for its own listing**: the Guild Master writes it, the guild channel (delivered by the server only to members) spreads it to the members, and every member with the addon announces it publicly. A listing stays visible while any member is online.
4. Details that the list does not need (description, contacts) are downloaded on demand from whoever holds them.
5. **Before any code**, spike S1 checks whether Blizzard's own Club Finder (`C_ClubFinder`) is enabled on Forever: if it is, it may replace the peer-to-peer catalog ([SPEC-09](../specs/SPEC-09-quality-release.md)).

## Alternatives considered

- **A server-side module or an external website.** Reliable and authoritative, but it needs hosting and trust, and it is not possible on official realms. Rejected.
- **Only the guild channel.** Players without a guild would see nothing. Rejected.
- **Yell or say broadcasts.** Limited to nearby players. Rejected.

## Consequences

- Positive: free, nothing to host, works on official realms.
- Negative: a listing is visible only while a client that knows it is online; a fresh install fills its catalog over seconds or minutes; integrity is reasonable, not cryptographic ([SPEC-02 §8](../specs/SPEC-02-network-protocol.md)).
