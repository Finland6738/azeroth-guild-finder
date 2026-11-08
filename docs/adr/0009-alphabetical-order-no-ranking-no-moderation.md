# 0009. Always alphabetical, no ranking, no moderation

- Status: Accepted
- Date: 2026-11-08 (decisions D18 and D19)

## Context

Finders that sort by activity or by the last update reward guilds that post again and again. A peer-to-peer addon also has no staff to moderate.

## Decision

1. The list is **always sorted A to Z** by a normalized key: accents folded to plain letters, case ignored, digits, spaces and symbols removed; the original name is shown. Ties are broken by the original name; names with an empty key go last.
2. Name search uses the same normalization and needs at least 3 letters.
3. No sort menu, no boosting, no paid placement.
4. No reports, word filters or staff tools in the addon.

## Consequences

- Positive: fair and predictable; no reason to spam updates.
- Negative: no protection against offensive texts besides the game's own reporting tools.
