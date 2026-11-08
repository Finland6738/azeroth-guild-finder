# 0007. Emblems built from the game's tabard pieces; nothing copied

- Status: Accepted
- Date: 2026-11-08 ([SPEC-08 §2](../specs/SPEC-08-assets-emblems-l10n.md))

## Context

Every listing needs an emblem. Many guilds have a tabard, some do not. Albion Online has a pleasant emblem designer. Copying image files, from Blizzard or from Albion, into a distributed addon is not allowed and not needed.

## Decision

1. One renderer, two sources, the same layers: background colour, border, emblem with its colour, inside a metal shield frame of our own.
2. **If the guild has a tabard**, its pieces are copied as they are (`C_GuildInfo.GetGuildTabardInfo`): emblem, border, colours.
3. **Otherwise** an Albion-style designer composes an emblem from **the same tabard pieces**, listed once with a hidden `TabardModel` (`CycleVariation`, `GetUpper*File`) by `/gf debug tabard`. `Save()` is never called: the real tabard never changes.
4. Game textures are referenced by **fileID**; only our own frames, masks and fonts ship in `Media/`. Albion's art is not used, only the idea of its designer.

## Consequences

- Positive: consistent emblems, no redistribution of third-party art.
- Negative: the list of tabard pieces depends on spike S8.
