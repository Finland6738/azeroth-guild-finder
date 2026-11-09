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

## Clarification (M3.6, 2026-11-09)

The decision stands; building it settled three details ([SPEC-08 §2](../specs/SPEC-08-assets-emblems-l10n.md)):

- **Indices on the wire, fileIDs in the catalogue.** A listing carries the index of each piece in `Data/TabardParts.lua` (and RGB colours), not the fileID, as the banner carries its index `bg`. The catalogue maps an index to the game's fileID or path, so it is the only place that names game files; the validation is a small integer range; and an index a client does not know, or a file it cannot load, falls back the same way.
- **The catalogue is provisional until M0.7.** Without the probe results the game's emblems are drawn from the guild window's emblem sheet by index (as the game's own `SetLargeGuildTabardTextures` does), and the border styles are drawn by the addon. M0.7 updates that one file.
- **A few symbols of our own.** Eight emblem symbols drawn by `tools/make_media.py` ship in `Media/` next to the game's pieces, so the designer works even on a client that cannot load the game's emblems. They are original art (ADR 0020); the game's tabard pieces are still never copied.

## Consequences

- Positive: consistent emblems, no redistribution of third-party art.
- Negative: the list of tabard pieces depends on spike S8; until M0.7 it is provisional.
