# Fonts

The interface uses **Roboto** and, for links, codes, times and commands, **Roboto Mono** (SPEC-04 §5.2). The files are TrueType, taken from the static downloads of Google Fonts:

- `Roboto-Regular.ttf`, `Roboto-Medium.ttf`, `Roboto-Bold.ttf`, `Roboto-Black.ttf`
- `RobotoMono-Regular.ttf`, `RobotoMono-Medium.ttf`

**Licence.** Both families are published under the **SIL Open Font License, Version 1.1**. The texts are next to the fonts: [OFL-Roboto.txt](OFL-Roboto.txt) (copyright 2011 The Roboto Project Authors) and [OFL-RobotoMono.txt](OFL-RobotoMono.txt) (copyright 2015 The Roboto Mono Project Authors). The OFL requires that the fonts stay under it, so these files are **not** under the GPL-3.0 of the addon's code; they may be bundled and redistributed with the addon as long as they are not sold by themselves and the licence text and copyright notice travel with them. Neither family declares a Reserved Font Name. The fonts are used unmodified.

`tools/check_addon.py` fails when a font used by `UI/Skin.lua` or the licence text of its family is missing. If the client cannot load a file, that style uses the client's own font and `/gf debug` lists it as `fallback` ([ADR 0020](../../../docs/adr/0020-original-media-own-nine-slice-and-font-fallback.md)).
