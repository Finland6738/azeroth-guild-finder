# Media

The textures of the addon's own windows. **All of them are original**: `tools/make_media.py` draws them from shapes, gradients and noise (no Blizzard, Albion or third-party art is read or copied) and writes them here as 32-bit uncompressed TGA files with power-of-two sizes. They are part of the addon and covered by its GPL-3.0 licence. Do not edit them by hand: change the script and run it again (`python -X utf8 tools/make_media.py`, needs Pillow).

| File | Use |
|---|---|
| `pill`, `pill_rim`, `pill_gloss` | buttons, switches, segmented controls, badges (a mask, tinted) |
| `card`, `card_edge` | cards, chips, tags, pages, class-icon rings |
| `field`, `field_ring` | text fields and copy fields |
| `shadow` | soft shadows under the window, cards and buttons |
| `disc`, `disc_ring`, `disc_shiny` | round buttons, the close button, knobs, dots |
| `glyph_*` | white icons of the side rail and buttons (tinted) |
| `role_tank`, `role_healer`, `role_melee`, `role_ranged` | the four role badges, in colour |
| `parchment`, `shade_h`, `fade_h`, `solid` | page grain, page-edge shading, the fade of a guild card's banner into the parchment, a plain white pixel |
| `emblem_field`, `emblem_gloss`, `emblem_frame`, `emblem_frame_small` | the guild emblem: the shield (tinted with the background colour), its light, the steel frame (thicker for 48 and 64 px) |
| `emblem_border_0` … `emblem_border_5` | the addon's own border styles (solid, thin, double, studded, bold, notched), tinted with the border colour |
| `emblem_sym_*` | the addon's own emblem symbols (star, eight-pointed star, sun, cross, crescent, sword, crown, tower), tinted |

The art of the game itself (class icons, later banners, the game's tabard emblems) is **not** here: it is referenced by path or atlas from `Data/Assets.lua`. Fonts: see [Fonts/README.md](Fonts/README.md).
