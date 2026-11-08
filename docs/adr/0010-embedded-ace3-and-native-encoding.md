# 0010. Embedded Ace3 and LibDBIcon, native encoding

- Status: Accepted
- Date: 2026-11-08 ([SPEC-01 §5](../specs/SPEC-01-platform-architecture.md))

## Context

Addon messages are limited to 255 bytes and to a server-side rate. Splitting, throttling, saved data, localization and the minimap button are solved problems.

## Decision

1. Embed AceAddon, AceEvent, AceDB, AceComm (with ChatThrottleLib), AceLocale and AceConsole, plus LibDataBroker and LibDBIcon, at pinned versions verified on Forever.
2. Do not use AceGUI (the parchment look needs our own widgets) nor AceSerializer: `C_EncodingUtil` provides CBOR, compression and Base64 natively.
3. Libraries come from `.pkgmeta` externals; they are not copied into the repository by hand.

## Consequences

- Positive: reliable splitting and throttling, standard minimap button, less code to maintain.
- Negative: library updates must be checked against the Forever client.
