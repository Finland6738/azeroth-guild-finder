# 0020. Interface construction: generated original media, our own nine-slice, fonts with a fallback

- Status: Accepted
- Date: 2026-11-08 ([docs/roadmap/M2-find-a-guild.md](../roadmap/M2-find-a-guild.md), step M2.4; continues [ADR 0008](0008-albion-skin-on-material-3-skeleton.md))

## Context

ADR 0008 chose the look (an Albion-like skin on a Material 3 skeleton) and said that our own nine-slice textures, shadows and fonts must be produced and tested at several scales. M2.4 builds the window and the widgets, so the way they are built has to be fixed: where the art comes from, how a pill or a card is stretched without distortion, how the type scale reaches the screen, and how the interface logic is tested without the game.

## Decision

1. **Original media, made by a script.** Every file in `AzerothGuildFinder/Media/` is drawn by `tools/make_media.py` (Pillow) from shapes, gradients and noise: nothing of Blizzard's or Albion's is read, traced or copied, and the files can be rebuilt byte for byte. They are 32-bit uncompressed TGA files with power-of-two sizes. Most are white or grey **masks** that the addon colours with `SetVertexColor` (one `pill.tga` serves the red, blue, parchment, grey and gold variants); the four role badges are drawn in colour. Art of the game itself (class icons, later banners and emblem pieces) is **referenced** from `Data/Assets.lua` by path or atlas, with a `verify` flag until the real client confirms it, and never copied.
2. **Our own nine-slice.** `W.NineSlice` stretches a mask over a frame with nine plain textures and `SetTexCoord` (corner margin 16 of 64 texels, corner size on screen set by the caller, half the height for a pill). It does not use `SetTextureSliceMargins`, so it works on every client build, and the same mask draws a fill, a rim, a gloss or a soft shadow when the caller tints it.
3. **Fonts through font objects with a fallback.** The type scale of SPEC-04 §5.2 is a table in `UI/Skin.lua`; `Skin.CreateFonts` makes one font object per style (`AGF_Headline`, `AGF_Body`, ...), at least 12 px. A style whose file `Media/Fonts/<Family>-<Weight>.ttf` the client cannot load (`SetFont` returns false) uses the client's own font and is listed as `fallback` in `/gf debug`. The window therefore works before the Roboto files are added; adding them changes nothing in the code. The font files and their licence file are an owner decision (see `Media/Fonts/README.md`); until they are added, no Roboto file is shipped.
4. **Logic apart from frames.** What can be decided without the client lives in plain Lua and is unit tested: `UI/Nav.lua` (role → tabs, page stacks, scale and position arithmetic), `UI/Skin.lua` (tokens). The widgets (`UI/Widgets/`) and the window (`UI/Main.lua`) are tested on the mock client for state and callbacks; what they look like is checked in game with the development-only widget gallery (`/gf debug gallery`) and the checklist in `docs/checklists/M2.md`.
5. **Pages plug into the window.** `Main:RegisterPage(id, def)` gives each page its own left, header and content frames, built once and shown only while the page is current; a page keeps its own state in the stack entry it is given. The window starts again on the first tab of the new role when `ROLE_CHANGED` arrives.
6. **Checks.** `tools/check_addon.py` (run by `check_docs.py` and CI) fails when UI code names a `Media/` texture that does not exist or an `L["KEY"]` that has no English string, because AceLocale answers a missing key with the key itself and nobody would notice.

## Alternatives considered

- **Blizzard backdrops and textures.** Quick, but the look would be the game's, and the owner asked for something closer to Albion. Rejected in ADR 0008.
- **Hand-painted textures in an editor.** Not reproducible from the repository, and every change to a colour or a radius would need the editor. A script with a seed gives the same files every time and the parameters are in the commit history.
- **`SetTextureSliceMargins` / `NineSlice` templates of the game.** Fewer textures to create, but they depend on engine support that the Forever build has not been checked for, and they cannot draw our shapes.
- **Bundling Roboto in this step.** The files are binary, their licence file must travel with them and the choice of weights is the owner's; the fallback keeps the step independent of that decision.

## Consequences

- Positive: the whole interface can change colour or radius by editing one script and tokens; the tests keep the behaviour stable; a missing font or texture never breaks the window.
- Negative: the textures are generated at 64 px and look as good as the nine-slice stretching allows; `Pillow` is needed to regenerate them (a development tool, not a runtime dependency); how it looks in the real client at 60 % and 140 % is still unverified.
