# 0008. Interface: an Albion-like skin on a Material Design 3 skeleton

- Status: Accepted
- Date: 2026-11-08 ([SPEC-04 §5](../specs/SPEC-04-ui-shell-navigation.md), [mockups](../specs/mockups/img/clean/00-design-system.webp))

## Context

The owner liked the look of Albion Online's guild finder but found its icon-only tabs hard to understand. Pure Material Design would look like a phone app pasted over the game.

## Decision

1. **Look from Albion**: an open book with two pages, parchment with grain, metal frames, glossy pill buttons (red for the main action, blue only for Discord), banner art faded into the parchment, a round gold close button.
2. **Structure from Material 3**: 8 px grid, type scale, navigation rail **with labels**, filled and tonal buttons, filter chips, switches, segmented buttons, cards, snackbars, badges.
3. **Side rail**: metal tabs stacked one under the other, **Settings first**, then the tabs of the player's role.
4. **Fonts**: Roboto for the interface, Roboto Mono only for links, codes, times and commands; shipped in `Media/Fonts/` with their open licence and used only by the addon's own windows. Minimum 12 px at 100 % scale; body contrast at least 7:1.
5. **Icons**: the game's own class icons, with a thin ring in the class colour; four role badges of our own (Tank, Healer, Melee DPS, Ranged DPS).

## Alternatives considered

- **Blizzard's default frames.** Familiar but plain; the owner asked for something closer to Albion.
- **Pure Material Design.** Out of place inside the game. Rejected.

## Consequences

- Positive: an attractive window that is also easy to read and to use.
- Negative: our own nine-slice textures, shadows and fonts must be produced and tested at several scales.
