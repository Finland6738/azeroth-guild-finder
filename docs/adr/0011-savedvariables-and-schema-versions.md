# 0011. SavedVariables and schema versions

- Status: Accepted
- Date: 2026-11-08 ([SPEC-01 §6](../specs/SPEC-01-platform-architecture.md))

## Context

The addon keeps a catalog, drafts, applications and settings. Saved files can be edited by hand, damaged, or come from a newer version of the addon.

## Decision

1. Two variables: `AzerothGuildFinderDB` (account: catalog, settings, a local secret never sent) and `AzerothGuildFinderCharDB` (character: own application, officer inbox, listing draft, window positions).
2. One schema version with step-by-step migrations, defaults merged recursively, values validated and brought back within limits at load, as in azeroth-unspoken.
3. Data from a newer schema is read but never rewritten.
4. Limits: at most 500 listings per realm and faction, 200 applications per guild inbox, cached details dropped after 60 days unseen.

## Consequences

- Positive: user data survives updates; a damaged file does not break the addon.
- Negative: every format change needs a migration and a test.
