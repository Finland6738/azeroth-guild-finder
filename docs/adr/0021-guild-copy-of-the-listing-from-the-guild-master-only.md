# 0021. The guild copy of the listing comes from the Guild Master only

- Status: Accepted
- Date: 2026-11-09 ([docs/roadmap/M3-listings.md](../roadmap/M3-listings.md), step M3.1; continues [ADR 0004](0004-roles-decide-the-panels.md) and [ADR 0001](0001-client-only-addon-peer-to-peer-catalog.md))

## Context

M3.1 builds `Data/OwnListing.lua`: the Guild Master publishes the listing, the members of the guild keep a copy for My Guild and repeat it on the public channel. SPEC-02 §7 and SPEC-06 §3–§5 describe the flow, but three points were open or contradicted each other:

- SPEC-02 §7 says that a `GLREQ` is answered "by the Guild Master, or by any member with the newest `rev`". INT-02 says that a member accepts a `GLIST` only from the Guild Master of the roster. A member's answer would therefore always be refused.
- SPEC-06 §4 says that delisting sends "a `GLIST` with the delisted state", without saying how that state is ordered against the listed copy of the same revision.
- How the roster check behaves before the client has loaded the roster, and what a new Guild Master builds on when the old one's `GLIST` never reached them.

## Decision

1. **Only the Guild Master is a source of the guild copy.** A `GLIST` is accepted only when it arrives over `GUILD` and its sender is, by base name (without the realm suffix), the member with rank index 0 in the roster (`Compat.Guild.LeaderName`). What the message says about its author is never trusted. While the roster is not loaded, the newest `GLIST` waits up to 30 s for `GUILD_ROSTER_UPDATE` and is then checked or dropped.
2. **Only the Guild Master answers `GLREQ`.** One `GLIST` over `GUILD` reaches every member, so the Guild Master waits 2 s to gather the requests and answers at most once every 30 s. A member asks at login and when the public catalog shows a newer revision than its copy, after 3–10 s, and stays silent when a `GLIST` or another member's `GLREQ` for the same or an older revision arrives first; at most one `GLREQ` every 5 minutes. When the Guild Master is offline, a member has no guild copy; the public catalog still has the listing.
3. **Withdrawing is a revision.** Delist publishes `rev + 1` with `del = true` (the content stays, so the editor can publish it again with one click) in a `GLIST`, and `DEL {k, rev + 1}` on the channel. Publishing again takes `rev + 2`, which relists the guild everywhere (INT-05). No ordering rule is needed for "listed and withdrawn at the same revision".
4. **Revisions and identity.** A publication takes the highest revision this client knows for the guild (guild copy, public summary, public withdrawal) plus one. `first` and `own` come from the guild copy, else from the public catalog (a new Guild Master whose copy never arrived), else they are created. So a change of Guild Master keeps the `ownerId` and other clients keep accepting the listing (INT-03).
5. **Relays.** A member that accepts a newer copy repeats it with an `ANN` after 5–30 s, unless an `ANN` of that revision was heard in the last 60 s (SPEC-02 §5); an officer sets `c = 1`. A withdrawn copy is repeated as a `DEL` only by a member that announced the guild itself in this session, because the other clients accept a `DEL` only from someone they heard announce the guild (INT-05).
6. **Limits.** At most one publication every 5 minutes, counted from the last publication and saved per character (`ownListing.pubAt`), so a `/reload` does not reset it. Drafts and withdrawals are not limited. `IsGuildLeader()` is read from the client again before every save, publication or withdrawal.
7. **Storage.** `AzerothGuildFinderCharDB.ownListing.published` is the guild copy for every role (the Guild Master's publication or the member's newest accepted `GLIST`), tagged by its guild key; `ownListing.draft` is the Guild Master's work in progress, tagged the same way. A copy or a draft of another guild is ignored, not deleted.

## Alternatives considered

- **Members answer `GLREQ` too, as SPEC-02 §7 said.** Faster when the Guild Master is offline, but INT-02 makes every such answer worthless, and accepting it would let any member write the guild copy. Without signatures (V2) the roster is the only authority.
- **A `delisted` flag at the same revision.** It needs an extra rule to order "listed" and "withdrawn" copies of one revision on every client, and a late copy could undo a withdrawal. A new revision avoids both.
- **Relaying the `DEL` from every member.** Up to 40 messages for one withdrawal; most would be refused by INT-05 anyway.
- **No wait for the roster.** The first `GLIST` after login often arrives before the roster; refusing it would lose the copy until the next request.

## Consequences

- Positive: a member's copy is exactly what the Guild Master of the roster sent; the change of Guild Master needs no special message; withdrawal and relisting follow the same ordering as every other change.
- Negative: while the Guild Master is offline, a member who never received the copy sees only the public catalog. A withdrawal reaches the clients that heard an announcer of the guild; the others drop the listing when it ages out (14, 30, 60 days, SPEC-03).
- To verify in the real client: whether the roster's rank index 0 and the sender of a `GUILD` addon message match by name on WoW Forever, and how soon the roster is available after login.
