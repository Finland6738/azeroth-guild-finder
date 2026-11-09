"""Generates the addon's own texture files in AzerothGuildFinder/Media/ (ADR 0020).

Everything is drawn here from shapes, noise and gradients: no Blizzard, Albion or third-party art is read, traced or
copied. The textures are white or grey masks that the addon tints with SetVertexColor, except the four role badges,
which are drawn in colour. 32-bit uncompressed TGA with power-of-two sizes, as the client wants.

Usage: python -X utf8 tools/make_media.py [--preview <png>]   (needs Pillow: python -m pip install pillow)
  --preview  also writes a contact sheet of every texture on a parchment background (not part of the addon)
The output is deterministic: running it twice gives identical files.
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "AzerothGuildFinder", "Media")
SS = 4   # supersampling: shapes are drawn 4 times larger and reduced, which gives smooth edges

WHITE = (255, 255, 255)


def new_mask(size, ss=SS):
    return Image.new("L", (size * ss, size * ss), 0)


def rrect_mask(size, inset, radius, ss=SS):
    """A rounded rectangle in a size x size texture, `inset` and `radius` in texture pixels."""
    m = new_mask(size, ss)
    ImageDraw.Draw(m).rounded_rectangle(
        [inset * ss, inset * ss, (size - inset) * ss - 1, (size - inset) * ss - 1], radius=radius * ss, fill=255)
    return m


def ring_mask(size, inset, radius, width, ss=SS):
    outer = rrect_mask(size, inset, radius, ss)
    inner = rrect_mask(size, inset + width, max(radius - width, 0), ss)
    return ImageChops.subtract(outer, inner)


def circle_mask(size, inset, ss=SS):
    m = new_mask(size, ss)
    ImageDraw.Draw(m).ellipse([inset * ss, inset * ss, (size - inset) * ss - 1, (size - inset) * ss - 1], fill=255)
    return m


def to_rgba(mask, rgb=WHITE, gray=None, size=None):
    """mask (L) plus colour -> RGBA at the final size. `gray`: an L image used as the colour (tintable shading)."""
    size = size or mask.size[0] // SS
    if gray is None:
        color = Image.new("RGB", mask.size, rgb)
    else:
        color = Image.merge("RGB", (gray, gray, gray))
    img = color.convert("RGBA")
    img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


def vgradient(size, top, bottom, ss=SS):
    """L image, `top` value at the top edge to `bottom` at the bottom edge."""
    px = size * ss
    g = Image.linear_gradient("L").resize((px, px))   # black top -> white bottom
    return g.point(lambda v: int(top + (bottom - top) * v / 255.0))


def scale_alpha(img, factor):
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r, g, b, a.point(lambda v: int(v * factor))))


# --------------------------------------------------------------------------------------------------------------------
# Nine-slice shapes (corner margin = size / 4 for the 64 px ones)
# --------------------------------------------------------------------------------------------------------------------
def pill_base():
    m = rrect_mask(64, 0, 16)
    return to_rgba(m, gray=vgradient(64, 255, 196))


def pill_rim():
    return to_rgba(ring_mask(64, 0, 16, 2))


def pill_gloss():
    """Light on the top half only: strongest at the top edge, nothing from the middle down."""
    m = rrect_mask(64, 3, 13)
    fade = Image.new("L", m.size, 0)
    fade.paste(vgradient(32, 150, 0), (0, 0))   # the upper half; the lower half stays empty
    return to_rgba(ImageChops.multiply(m, fade))


def card_fill():
    return to_rgba(rrect_mask(64, 0, 14))


def card_edge():
    return to_rgba(ring_mask(64, 0, 14, 2))


def field_fill():
    m = rrect_mask(64, 0, 16)
    return to_rgba(m, gray=vgradient(64, 232, 255))   # a darker top edge reads as an inset field


def field_ring():
    return to_rgba(ring_mask(64, 0, 16, 3))


def shadow_soft():
    """A soft shadow: the shape is 32 px in from the edge and blurred; display it larger than the thing it shadows."""
    size = 128
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([40, 40, size - 41, size - 41], radius=14, fill=255)
    m = m.filter(ImageFilter.GaussianBlur(14))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    img.putalpha(m)
    return img


# --------------------------------------------------------------------------------------------------------------------
# Round shapes
# --------------------------------------------------------------------------------------------------------------------
def disc():
    return to_rgba(circle_mask(64, 0))


def disc_ring():
    outer = circle_mask(64, 0)
    inner = circle_mask(64, 4)
    return to_rgba(ImageChops.subtract(outer, inner))


def disc_shiny():
    """A glossy disc: bright spot at the upper left, dark edge; grey, tinted by the addon."""
    ss = SS
    px = 64 * ss
    cx, cy = px * 0.38, px * 0.32
    img = Image.new("L", (px, px), 0)
    pix = img.load()
    maxd = px * 0.8
    for y in range(px):
        for x in range(px):
            d = math.hypot(x - cx, y - cy) / maxd
            pix[x, y] = max(70, min(255, int(255 - 185 * d)))
    return to_rgba(circle_mask(64, 0), gray=img)


# --------------------------------------------------------------------------------------------------------------------
# Glyphs: white on transparent, 64 x 64, tinted by the addon
# --------------------------------------------------------------------------------------------------------------------
def glyph(draw_fn, size=64):
    ss = 8
    img = Image.new("L", (size * ss, size * ss), 0)
    d = ImageDraw.Draw(img)
    draw_fn(d, ss)
    img = img.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), WHITE + (0,))
    out.putalpha(img)
    return out


def line(d, ss, pts, width):
    d.line([(x * ss, y * ss) for x, y in pts], fill=255, width=int(width * ss), joint="curve")
    r = width * ss / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x * ss - r, y * ss - r, x * ss + r, y * ss + r], fill=255)


def g_check(d, ss): line(d, ss, [(14, 34), (26, 46), (50, 18)], 8)
def g_close(d, ss):
    line(d, ss, [(16, 16), (48, 48)], 8)
    line(d, ss, [(48, 16), (16, 48)], 8)
def g_back(d, ss): line(d, ss, [(40, 12), (20, 32), (40, 52)], 8)
def g_plus(d, ss):
    line(d, ss, [(32, 12), (32, 52)], 8)
    line(d, ss, [(12, 32), (52, 32)], 8)


def g_search(d, ss):
    d.ellipse([10 * ss, 10 * ss, 42 * ss, 42 * ss], outline=255, width=7 * ss)
    line(d, ss, [(38, 38), (54, 54)], 9)


def g_gear(d, ss):
    cx = cy = 32
    for i in range(8):
        a = math.pi * i / 4
        x, y = cx + 22 * math.cos(a), cy + 22 * math.sin(a)
        line(d, ss, [(cx + 15 * math.cos(a), cy + 15 * math.sin(a)), (x, y)], 9)
    d.ellipse([(cx - 19) * ss, (cy - 19) * ss, (cx + 19) * ss, (cy + 19) * ss], fill=255)
    d.ellipse([(cx - 8) * ss, (cy - 8) * ss, (cx + 8) * ss, (cy + 8) * ss], fill=0)


def g_doc(d, ss):
    d.rounded_rectangle([14 * ss, 6 * ss, 50 * ss, 58 * ss], radius=5 * ss, fill=255)
    for y in (22, 33, 44):
        d.rectangle([21 * ss, y * ss, 43 * ss, (y + 4) * ss], fill=0)


def g_shield(d, ss):
    d.polygon([(32 * ss, 6 * ss), (54 * ss, 14 * ss), (54 * ss, 32 * ss), (46 * ss, 46 * ss), (32 * ss, 58 * ss),
               (18 * ss, 46 * ss), (10 * ss, 32 * ss), (10 * ss, 14 * ss)], fill=255)
    d.polygon([(32 * ss, 14 * ss), (46 * ss, 19 * ss), (46 * ss, 31 * ss), (32 * ss, 50 * ss)], fill=0)


def g_inbox(d, ss):
    d.polygon([(8 * ss, 36 * ss), (18 * ss, 12 * ss), (46 * ss, 12 * ss), (56 * ss, 36 * ss), (56 * ss, 54 * ss),
               (8 * ss, 54 * ss)], fill=255)
    d.polygon([(8 * ss, 36 * ss), (22 * ss, 36 * ss), (26 * ss, 44 * ss), (38 * ss, 44 * ss), (42 * ss, 36 * ss),
               (56 * ss, 36 * ss), (56 * ss, 40 * ss), (44 * ss, 40 * ss), (40 * ss, 48 * ss), (24 * ss, 48 * ss),
               (20 * ss, 40 * ss), (8 * ss, 40 * ss)], fill=0)


def g_copy(d, ss):
    d.rounded_rectangle([20 * ss, 20 * ss, 54 * ss, 56 * ss], radius=5 * ss, fill=255)
    d.rounded_rectangle([10 * ss, 8 * ss, 44 * ss, 44 * ss], radius=5 * ss, outline=255, width=5 * ss)


# --------------------------------------------------------------------------------------------------------------------
# Role badges (colour): a coloured disc with a light ring and a white symbol
# --------------------------------------------------------------------------------------------------------------------
ROLE_COLORS = {"tank": (44, 79, 134), "healer": (47, 122, 54), "melee": (142, 42, 31), "ranged": (106, 63, 158)}


def role_badge(role):
    ss = 8
    size = 64
    px = size * ss
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, px - 1, px - 1], fill=(185, 163, 122, 255))
    d.ellipse([4 * ss, 4 * ss, px - 4 * ss - 1, px - 4 * ss - 1], fill=ROLE_COLORS[role] + (255,))
    sym = Image.new("L", (px, px), 0)
    s = ImageDraw.Draw(sym)
    if role == "tank":
        s.polygon([(32 * ss, 14 * ss), (46 * ss, 19 * ss), (46 * ss, 31 * ss), (40 * ss, 42 * ss), (32 * ss, 50 * ss),
                   (24 * ss, 42 * ss), (18 * ss, 31 * ss), (18 * ss, 19 * ss)], fill=255)
    elif role == "healer":
        s.polygon([(27 * ss, 14 * ss), (37 * ss, 14 * ss), (37 * ss, 27 * ss), (50 * ss, 27 * ss), (50 * ss, 37 * ss),
                   (37 * ss, 37 * ss), (37 * ss, 50 * ss), (27 * ss, 50 * ss), (27 * ss, 37 * ss), (14 * ss, 37 * ss),
                   (14 * ss, 27 * ss), (27 * ss, 27 * ss)], fill=255)
    elif role == "melee":
        for sign in (1, -1):
            x0, x1 = (16, 44) if sign == 1 else (48, 20)
            s.line([(x0 * ss, 16 * ss), (x1 * ss, 44 * ss)], fill=255, width=5 * ss)
            hx, hy = (42, 38) if sign == 1 else (22, 38)
            s.line([((hx - 6 * sign) * ss, (hy + 6) * ss), ((hx + 6 * sign) * ss, (hy - 6) * ss)], fill=255, width=4 * ss)
    else:   # ranged: a target
        for r, w in ((19, 4), (11, 4)):
            s.ellipse([(32 - r) * ss, (32 - r) * ss, (32 + r) * ss, (32 + r) * ss], outline=255, width=w * ss)
        s.ellipse([(32 - 4) * ss, (32 - 4) * ss, (32 + 4) * ss, (32 + 4) * ss], fill=255)
    white = Image.new("RGBA", (px, px), (255, 244, 220, 255))
    img = Image.composite(white, img, sym)
    return img.resize((size, size), Image.LANCZOS)


# --------------------------------------------------------------------------------------------------------------------
# Parchment grain: a seamless tile of brown speckle, drawn with an alpha so it can lie over any parchment colour
# --------------------------------------------------------------------------------------------------------------------
def parchment_grain(size=128):
    rng = random.Random(20261108)
    base = Image.new("L", (size, size))
    base.putdata([rng.randint(0, 255) for _ in range(size * size)])
    tiled = Image.new("L", (size * 3, size * 3))
    for ix in range(3):
        for iy in range(3):
            tiled.paste(base, (ix * size, iy * size))
    tiled = tiled.filter(ImageFilter.GaussianBlur(0.9))
    tile = tiled.crop((size, size, size * 2, size * 2))
    # stretch the contrast, keep it subtle
    lo, hi = tile.getextrema()
    span = max(1, hi - lo)
    alpha = tile.point(lambda v: int(70 * (v - lo) / span))
    img = Image.new("RGBA", (size, size), (110, 66, 22, 0))
    img.putalpha(alpha)
    return img


def shade_h():
    """Horizontal fade 64 x 4: dark at the left edge, nothing at the right (page gutter, shadows at a page edge)."""
    img = Image.new("RGBA", (64, 4), (40, 20, 0, 0))
    a = Image.new("L", (64, 4))
    a.putdata([int(150 * (1 - x / 63.0) ** 1.6) for _ in range(4) for x in range(64)])
    img.putalpha(a)
    return img


def fade_h():
    """Horizontal fade 64 x 4: a white pixel row that is opaque at the left edge and clear at the right (the banner of a
    guild card melts into the parchment; the addon tints it with the card colour)."""
    img = Image.new("RGBA", (64, 4), WHITE + (0,))
    a = Image.new("L", (64, 4))
    a.putdata([int(255 * (1 - x / 63.0) ** 1.3) for _ in range(4) for x in range(64)])
    img.putalpha(a)
    return img


def solid():
    return Image.new("RGBA", (8, 8), WHITE + (255,))


# --------------------------------------------------------------------------------------------------------------------
# Emblem (SPEC-08 §2.4): the shield the guild emblem is drawn on, its gloss, the metal frame, the addon's own border styles
# and symbols. The shield is the shape of the mockups (agf.js), in a 100 x 120 box, centred in a 128 px square texture.
# The game's tabard pieces are NOT here: they are referenced by path or fileID from Data/TabardParts.lua.
# --------------------------------------------------------------------------------------------------------------------
EMB = 128
EMB_SS = 8
EMB_SCALE = EMB / 120.0
EMB_OX = (EMB - 100 * EMB_SCALE) / 2.0
SHIELD = [("M", 12, 10), ("L", 88, 10), ("L", 88, 58), ("Q", 88, 96, 50, 114), ("Q", 12, 96, 12, 58)]
SHIELD_IN = [("M", 19, 17), ("L", 81, 17), ("L", 81, 58), ("Q", 81, 90, 50, 106), ("Q", 19, 90, 19, 58)]
METAL_STOPS = [(0.0, (244, 247, 250)), (0.35, (163, 173, 183)), (0.55, (227, 232, 237)), (1.0, (90, 99, 108))]


def shield_points(path, scale_about=None, steps=24):
    """The closed outline of a path (box units), in supersampled texture pixels; `scale_about` = (k, cx, cy)."""
    pts, cur = [], None
    for seg in path:
        if seg[0] in ("M", "L"):
            cur = (seg[1], seg[2])
            pts.append(cur)
        else:
            _, cx, cy, x, y = seg
            x0, y0 = cur
            for i in range(1, steps + 1):
                t = i / steps
                pts.append(((1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x,
                            (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t * t * y))
            cur = (x, y)
    if scale_about:
        k, ax, ay = scale_about
        pts = [(ax + (x - ax) * k, ay + (y - ay) * k) for x, y in pts]
    f = EMB_SS * EMB_SCALE
    return [((x * EMB_SCALE + EMB_OX) * EMB_SS, y * f) for x, y in pts]


def emb_canvas():
    return Image.new("L", (EMB * EMB_SS, EMB * EMB_SS), 0)


def emb_fill(path):
    m = emb_canvas()
    ImageDraw.Draw(m).polygon(shield_points(path), fill=255)
    return m


def emb_stroke(path, width, scale_about=None):
    m = emb_canvas()
    pts = shield_points(path, scale_about)
    w = int(width * EMB_SCALE * EMB_SS)
    ImageDraw.Draw(m).line(pts + [pts[0], pts[1]], fill=255, width=w, joint="curve")
    return m


def emb_out(color_img, mask):
    img = color_img.convert("RGBA")
    img.putalpha(mask)
    return img.resize((EMB, EMB), Image.LANCZOS)


def emblem_field():
    """The shield, white at the top to light grey at the point: tinted with the background colour, it keeps a soft shading."""
    m = emb_fill(SHIELD)
    px = EMB * EMB_SS
    g = Image.linear_gradient("L").resize((px, px)).point(lambda v: int(240 - 60 * v / 255.0))
    return emb_out(Image.merge("RGB", (g, g, g)), m)


def emblem_gloss():
    """Untinted light: a bright spot at the upper left that fades out, darker towards the point; only inside the shield."""
    px = EMB * EMB_SS
    small = 128
    light = Image.new("RGBA", (small, small))
    pix = light.load()
    cx, cy, r = small * 0.38, small * 0.28, small * 0.85
    for y in range(small):
        for x in range(small):
            d = math.hypot(x - cx, y - cy) / r
            if d < 0.6:
                pix[x, y] = (255, 255, 255, int(72 * (1 - d / 0.6)))
            else:
                pix[x, y] = (0, 0, 0, int(min(1.0, (d - 0.6) / 0.4) * 80))
    light = light.resize((px, px), Image.BILINEAR)
    a = ImageChops.multiply(light.split()[3], emb_fill(SHIELD))
    light.putalpha(a)
    return light.resize((EMB, EMB), Image.LANCZOS)


def metal_gradient():
    px = EMB * EMB_SS
    small = 64
    img = Image.new("RGB", (small, small))
    pix = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2.0 * (small - 1))
            for (t0, c0), (t1, c1) in zip(METAL_STOPS, METAL_STOPS[1:]):
                if t0 <= t <= t1:
                    k = (t - t0) / (t1 - t0)
                    pix[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
                    break
    return img.resize((px, px), Image.BILINEAR)


def emblem_frame(dark_w=9, metal_w=6):
    """The steel rim around the shield (colour baked in, untinted): a dark outline, the steel band, a thin inner shadow."""
    px = EMB * EMB_SS
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (px, px), (29, 33, 38, 255)), (0, 0), emb_stroke(SHIELD, dark_w))
    metal = metal_gradient().convert("RGBA")
    out.paste(metal, (0, 0), emb_stroke(SHIELD, metal_w))
    inner = emb_stroke(SHIELD, 1.2, (1 - (metal_w / 2.0 + 0.8) / 50.0, 50, 60)).point(lambda v: int(v * 0.35))
    shade = Image.new("RGBA", (px, px), (0, 0, 0, 255))
    shade.putalpha(inner)
    out = Image.alpha_composite(out, shade)
    return out.resize((EMB, EMB), Image.LANCZOS)


def dots_along(path, every, radius):
    """A mask with round dots every `every` box units along the inner shield line."""
    m = emb_canvas()
    d = ImageDraw.Draw(m)
    pts = shield_points(path, steps=200)
    step, acc, r = every * EMB_SCALE * EMB_SS, 0.0, radius * EMB_SCALE * EMB_SS
    last = pts[0]
    d.ellipse([last[0] - r, last[1] - r, last[0] + r, last[1] + r], fill=255)
    for p in pts[1:] + [pts[0]]:
        acc += math.hypot(p[0] - last[0], p[1] - last[1])
        last = p
        if acc >= step:
            acc = 0.0
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)
    return m


def emblem_border(style):
    """One of the addon's own border styles, white (tinted with the border colour), along the inner edge of the shield."""
    white = Image.new("RGB", (EMB * EMB_SS, EMB * EMB_SS), WHITE)
    if style == 0:      # solid
        m = emb_stroke(SHIELD_IN, 4)
    elif style == 1:    # thin
        m = emb_stroke(SHIELD_IN, 2.2)
    elif style == 2:    # double
        m = ImageChops.lighter(emb_stroke(SHIELD_IN, 3), emb_stroke(SHIELD_IN, 2, (0.86, 50, 60)))
    elif style == 3:    # studded: round studs along the edge
        m = dots_along(SHIELD_IN, 7.0, 2.6)
    elif style == 4:    # bold
        m = emb_stroke(SHIELD_IN, 7)
    else:               # notched: a solid line with notches cut across it
        m = ImageChops.subtract(emb_stroke(SHIELD_IN, 4.5), dots_along(SHIELD_IN, 9.0, 1.4))
    return emb_out(white, m)


def star_points(cx, cy, r1, r2, n, rot=0.0):
    pts = []
    for i in range(n * 2):
        r = r2 if i % 2 else r1
        a = math.pi * i / n - math.pi / 2 + rot
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def sc(ss, pts):
    return [(x * ss, y * ss) for x, y in pts]


def s_star(d, ss):
    d.polygon(sc(ss, star_points(32, 32, 29, 9, 4)), fill=255)
    d.polygon(sc(ss, star_points(32, 32, 18, 7, 4, math.pi / 4)), fill=255)


def s_star8(d, ss):
    d.polygon(sc(ss, star_points(32, 32, 28, 11, 8)), fill=255)


def s_sun(d, ss):
    d.polygon(sc(ss, star_points(32, 32, 29, 15, 12)), fill=255)
    d.ellipse([20 * ss, 20 * ss, 44 * ss, 44 * ss], fill=255)


def s_cross(d, ss):
    d.rectangle([27 * ss, 5 * ss, 37 * ss, 59 * ss], fill=255)
    d.rectangle([10 * ss, 20 * ss, 54 * ss, 30 * ss], fill=255)


def s_crescent(d, ss):
    d.ellipse([6 * ss, 6 * ss, 58 * ss, 58 * ss], fill=255)
    d.ellipse([18 * ss, 0, 66 * ss, 52 * ss], fill=0)
    d.polygon(sc(ss, star_points(46, 34, 8, 3, 4)), fill=255)


def s_sword(d, ss):
    d.polygon(sc(ss, [(32, 3), (37, 12), (37, 42), (27, 42), (27, 12)]), fill=255)
    d.rounded_rectangle([16 * ss, 42 * ss, 48 * ss, 48 * ss], radius=2 * ss, fill=255)
    d.rectangle([29 * ss, 48 * ss, 35 * ss, 56 * ss], fill=255)
    d.ellipse([27 * ss, 54 * ss, 37 * ss, 63 * ss], fill=255)


def s_crown(d, ss):
    d.polygon(sc(ss, [(8, 46), (8, 16), (21, 31), (32, 9), (43, 31), (56, 16), (56, 46)]), fill=255)
    d.rounded_rectangle([8 * ss, 50 * ss, 56 * ss, 57 * ss], radius=2 * ss, fill=255)


def s_tower(d, ss):
    d.polygon(sc(ss, [(14, 60), (14, 18), (19, 18), (19, 10), (25, 10), (25, 18), (29, 18), (29, 10), (35, 10), (35, 18),
                      (39, 18), (39, 10), (45, 10), (45, 18), (50, 18), (50, 60)]), fill=255)
    d.rounded_rectangle([27 * ss, 42 * ss, 37 * ss, 62 * ss], radius=5 * ss, fill=0)
    d.rectangle([29 * ss, 26 * ss, 35 * ss, 33 * ss], fill=0)


TEXTURES = {
    "pill": pill_base, "pill_rim": pill_rim, "pill_gloss": pill_gloss,
    "card": card_fill, "card_edge": card_edge,
    "field": field_fill, "field_ring": field_ring,
    "shadow": shadow_soft,
    "disc": disc, "disc_ring": disc_ring, "disc_shiny": disc_shiny,
    "glyph_check": lambda: glyph(g_check), "glyph_close": lambda: glyph(g_close), "glyph_back": lambda: glyph(g_back),
    "glyph_plus": lambda: glyph(g_plus), "glyph_search": lambda: glyph(g_search), "glyph_gear": lambda: glyph(g_gear),
    "glyph_doc": lambda: glyph(g_doc), "glyph_shield": lambda: glyph(g_shield), "glyph_inbox": lambda: glyph(g_inbox),
    "glyph_copy": lambda: glyph(g_copy),
    "role_tank": lambda: role_badge("tank"), "role_healer": lambda: role_badge("healer"),
    "role_melee": lambda: role_badge("melee"), "role_ranged": lambda: role_badge("ranged"),
    "parchment": parchment_grain, "shade_h": shade_h, "fade_h": fade_h, "solid": solid,
    "emblem_field": emblem_field, "emblem_gloss": emblem_gloss,
    "emblem_frame": emblem_frame, "emblem_frame_small": lambda: emblem_frame(13, 9),
    "emblem_border_0": lambda: emblem_border(0), "emblem_border_1": lambda: emblem_border(1),
    "emblem_border_2": lambda: emblem_border(2), "emblem_border_3": lambda: emblem_border(3),
    "emblem_border_4": lambda: emblem_border(4), "emblem_border_5": lambda: emblem_border(5),
    "emblem_sym_star": lambda: glyph(s_star), "emblem_sym_star8": lambda: glyph(s_star8),
    "emblem_sym_sun": lambda: glyph(s_sun), "emblem_sym_cross": lambda: glyph(s_cross),
    "emblem_sym_crescent": lambda: glyph(s_crescent), "emblem_sym_sword": lambda: glyph(s_sword),
    "emblem_sym_crown": lambda: glyph(s_crown), "emblem_sym_tower": lambda: glyph(s_tower),
}


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    images = {}
    for name, make in TEXTURES.items():
        img = make().convert("RGBA")
        w, h = img.size
        assert w & (w - 1) == 0 and h & (h - 1) == 0, f"{name}: {w}x{h} is not a power of two"
        img.save(os.path.join(OUT, name + ".tga"), format="TGA", compression=None)
        images[name] = img
    print(f"{len(images)} textures written to AzerothGuildFinder/Media/")
    if "--preview" in argv:
        path = argv[argv.index("--preview") + 1]
        cols, cell = 8, 96
        rows = (len(images) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * cell, rows * cell), (233, 200, 151, 255))
        for i, (name, img) in enumerate(images.items()):
            tile = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
            shown = img.resize((min(img.size[0], 80) if img.size[0] >= img.size[1] else 80, 64 if img.size[1] < 64 else 80))
            if name in ("pill", "card", "field", "disc_shiny"):
                tint = Image.new("RGBA", shown.size, (184, 31, 37, 255))
                shown = ImageChops.multiply(shown, tint)
            elif name.startswith(("glyph", "pill_rim", "card_edge", "field_ring", "disc", "shade", "solid")):
                tint = Image.new("RGBA", shown.size, (60, 36, 18, 255))
                shown = Image.composite(tint, Image.new("RGBA", shown.size, (0, 0, 0, 0)), shown.split()[3])
            tile.paste(shown, (8, 8), shown)
            sheet.alpha_composite(tile, ((i % cols) * cell, (i // cols) * cell))
        sheet.save(path)
        print("preview:", path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
