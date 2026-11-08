# 0012. Four roles, up to three activities and a commitment level

- Status: Accepted (the activity list waits for confirmation against Forever's content)
- Date: 2026-11-08 ([SPEC-03 §5](../specs/SPEC-03-data-model.md), [mockup](../specs/mockups/img/08-editor-activity.webp))

## Context

Players filter guilds by what they play and how seriously. "DPS" alone is too vague, long tag lists make every guild look the same, and the time a guild expects from its members matters as much as its content.

## Decision

1. **Roles**: Tank, Healer, **Melee DPS**, **Ranged DPS**, each with its own badge (shield, cross, crossed swords, target). Impossible class-role pairs are disabled.
2. **Activities**: a closed list of 13 (Raids, Dungeons, Leveling, Questing & Exploration, Battlegrounds, World PvP, Professions & Crafting, Gold & Trading, Reputation & Collecting, Roleplay, Social & Chat, Events & Community, Housing if Forever has it). A guild picks **1 to 3**, in order of importance; the first is its main focus.
3. **Commitment**: one required choice among **Casual**, **Softcore** and **Hardcore**, each with its meaning written under it. "Hardcore" means the guild's commitment, not a permadeath mode.

## Consequences

- Positive: clearer listings and sharper filters.
- Negative: the activity list must be checked against the content really present on Forever before release.
