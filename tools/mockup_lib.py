"""HTML building blocks for tools/make_mockups.py (design previews of the Azeroth Guild Finder interface).

Pure string helpers: no browser, no file access. The look comes from docs/specs/mockups/html/agf.css (Albion-style
parchment on a Material 3 skeleton, Roboto) and agf.js (original emblems and banner art). All texts are the addon's
own English strings (AzerothGuildFinder/Locale/enUS.lua). Class icons are the game's own, hot-linked at render time by agf.js (never stored); emblems and banners are original.
"""
import json

# ---- emblems (original shield art of agf.js) -------------------------------------------------------------------
AUR = {"bg": "#141c2c", "bc": "#d7dde4", "ec": "#ffffff", "symbol": "star", "border": "solid"}
CRIM = {"bg": "#14090a", "bc": "#6d1515", "ec": "#b3171d", "symbol": "cross", "border": "double"}
DRAG = {"bg": "#1f3a58", "bc": "#e3b43d", "ec": "#e3b43d", "symbol": "beast", "border": "studded"}
SCAR = {"bg": "#4a1414", "bc": "#e3b43d", "ec": "#e3b43d", "symbol": "crown", "border": "double"}
VERD = {"bg": "#1d3a22", "bc": "#e3b43d", "ec": "#e3b43d", "symbol": "leaf", "border": "solid"}
BRAND = {"bg": "#c9a06a", "bc": "#7a5430", "ec": "#5a3a1c", "symbol": "tower", "border": "solid"}
MOON = {"bg": "#241a3c", "bc": "#b9a9e8", "ec": "#e8e0ff", "symbol": "crescent", "border": "thin"}
FLAME = {"bg": "#3a1408", "bc": "#f2bf3c", "ec": "#ff9a3c", "symbol": "flame", "border": "bold"}

CLASSES = ["warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"]
CLASS_NAMES = {c: c.capitalize() for c in CLASSES}
CLASS_COLOR = {"warrior": "#c69b6d", "paladin": "#f48cba", "hunter": "#aad372", "rogue": "#fff468", "priest": "#f5f5f5",
               "shaman": "#0070dd", "mage": "#3fc7eb", "warlock": "#8788ee", "druid": "#ff7c0a"}
# class text colours that stay readable on parchment (the addon darkens the light ones)
CLASS_TEXT = {"warrior": "#8a6a40", "paladin": "#b04a7a", "hunter": "#4f7a22", "rogue": "#7a6c00", "priest": "#6b6b6b",
              "shaman": "#0058b0", "mage": "#1d86a6", "warlock": "#5a5ad0", "druid": "#b85500"}


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def emb(o, style="", cls=""):
    return f"<div class=\"{cls}\" style=\"{style}\" data-emblem='{json.dumps(o)}'></div>"


def cl(c, size=""):
    return f'<span data-cls="{c}" class="{size}"></span>'


def role(r, size=""):
    return f'<span data-role="{r}" class="{size}"></span>'


def art(theme, seed, cls="", style=""):
    return f'<div class="{cls}" style="{style}" data-art="{theme}:{seed}"></div>'


def ms(name, style="", cls=""):
    return f'<span class="ms {cls}" style="{style}">{name}</span>'


def tag(text, kind="", icon=""):
    i = ms(icon, "font-size:14px") if icon else ""
    return f'<span class="tag {kind}">{i}{text}</span>'


def pace(kind):
    return {"casual": tag("CASUAL", "pace casual", "local_cafe"), "soft": tag("SOFTCORE", "pace soft", "event_available"),
            "hard": tag("HARDCORE", "pace hard", "local_fire_department")}[kind]


def btn(text, kind="tonal", size="sm", icon="", extra=""):
    i = ms(icon) if icon else ""
    return f'<span class="btn {kind} {size}" {extra}>{i}{text}</span>'


def sw(on=False):
    return f'<span class="sw {"on" if on else ""}"></span>'


def opt(label, on=False, help=""):
    h = f'<br><span class="caption">{help}</span>' if help else ""
    return f'<div class="opt"><span>{label}{h}</span>{sw(on)}</div>'


def field(text, icon="", select=False, sq=False, style="", muted=False):
    c = "field" + (" select" if select else "") + (" sq" if sq else "")
    i = ms(icon) if icon else ""
    t = f'<span class="ph-t">{text}</span>' if muted else f"<span>{text}</span>"
    return f'<div class="{c}" style="{style}">{i}{t}</div>'


def chips(items, on=()):
    return '<div class="chips">' + "".join(f'<span class="chip {"on" if i in on else ""}">{x}</span>' for i, x in enumerate(items)) + "</div>"


def seg(items, on):
    return '<div class="seg">' + "".join(f'<span class="{"on" if i == on else ""}">{x}</span>' for i, x in enumerate(items)) + "</div>"


def card(inner, kind="", style=""):
    return f'<div class="card {kind}" style="{style}">{inner}</div>'


def h3(icon, text, extra=""):
    return f'<h3>{ms(icon)}{text}{extra}</h3>'


def days(on, letters="MTWTFSS"):
    return '<div class="days">' + "".join(f'<span class="{"on" if i in on else ""}">{c}</span>' for i, c in enumerate(letters)) + "</div>"


def classbar(parts):
    return '<div class="classbar">' + "".join(f'<span style="width:{w}%;background:{CLASS_COLOR[c]}"></span>' for c, w in parts) + "</div>"


# ---- window shell -----------------------------------------------------------------------------------------------
TABS = {
    "Settings": ("settings", "Settings"),
    "FindGuild": ("travel_explore", "Find a<br>Guild"),
    "MyApplication": ("assignment_ind", "My<br>Application"),
    "MyGuild": ("shield", "My<br>Guild"),
    "CreateListing": ("edit_note", "Create<br>Listing"),
    "Applications": ("inbox", "Applications"),
}
ROLE_TABS = {"none": ["Settings", "FindGuild", "MyApplication"], "member": ["Settings", "MyGuild"],
             "officer": ["Settings", "MyGuild", "Applications"], "gm": ["Settings", "MyGuild", "Applications"],
             "gm_new": ["Settings", "CreateListing"], "officer_new": ["Settings", "MyGuild"]}


def rail(role_key, active, badges=None):
    badges = badges or {}
    out = ['<div class="close"><span class="ms">close</span></div><div class="rail">']
    for t in ROLE_TABS[role_key]:
        icon, label = TABS[t]
        b = f'<span class="badge">{badges[t]}</span>' if t in badges else ""
        out.append(f'<div class="dest {"on" if t == active else ""}"><div class="ic">{ms(icon)}</div><div class="lb">{label}</div>{b}</div>')
    out.append("</div>")
    return "".join(out)


def brand(emblem=BRAND, title="Guild Finder", sub="Azeroth", small=False):
    h1 = ' style="font-size:24px"' if small else ""
    return f'<div class="brand"><div class="crest" data-emblem=\'{json.dumps(emblem)}\'></div><div><h1{h1}>{title}</h1><div class="sub">{sub}</div></div></div>'


def left(inner, flex_gap=None):
    st = f' style="gap:{flex_gap}px"' if flex_gap else ""
    return f'<div class="page page-left"{st}>{inner}</div>'


def right(title, inner, status=None, back=False, header_extra="", badge=None, overline=None, content_style="", header=True):
    """status: (text, 'ok'|'off'|'bad') shown in the status line like Main:SetStatus."""
    hd = ""
    if header:
        b = btn("Back", "ghost", "sm", "arrow_back") if back else ""
        ttl = f"<div><div class=\"overline\">{overline}</div><h2>{title}</h2></div>" if overline else f"<h2>{title}</h2>"
        bd = f'<span class="badge">{badge}</span>' if badge else ""
        hd = f'<div class="ph">{b}{ttl}{bd}<div class="grow"></div>{header_extra}</div>'
    st = ""
    if status:
        dot = {"ok": "dot", "off": "dot off", "bad": "dot bad"}[status[1]]
        st = f'<div class="statusbar"><span class="{dot}"></span>{status[0]}</div>'
    return f'<div class="page page-right">{hd}<div class="content" style="{content_style}">{inner}</div>{st}</div>'


def window(left_html, right_html, role_key, active, badges=None):
    return f'<div class="book">{left_html}{right_html}{rail(role_key, active, badges)}</div>'


def empty_state(title, body, emblem=None, button="", icon=""):
    e = emb(emblem, "width:70px;height:84px;opacity:.45") if emblem else (ms(icon, "font-size:44px;color:#8a5a2a;opacity:.7") if icon else "")
    return (f'<div class="empty">{e}<div class="title-m">{title}</div>'
            f'<div class="body-m muted" style="max-width:380px">{body}</div>{button}</div>')


# ---- guild list card --------------------------------------------------------------------------------------------
def gcard(name, sub, emblem, theme, tags, actions, info, hover=False, selected=False, flag=""):
    cls = "gcard" + (" hover" if hover else "") + (" sel" if selected else "")
    a = art(*theme, cls="art") if theme else ""
    cells = "".join(f"<div>{c}</div>" for c in info)
    return (f'<div class="{cls}"><div class="top">{a}{emb(emblem, cls="emb")}<div class="txt"><div class="name">{name}</div>'
            f'<div class="sub">{sub}</div><div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap">{tags}</div></div>'
            f'<div class="actions">{actions}</div>{flag}</div><div class="info">{cells}</div></div>')


def looking(classes, more=0):
    cs = "".join(cl(c, "sm") for c in classes)
    m = f'<span class="caption">+{more}</span>' if more else ""
    return f'{ms("person_search")}Looking for {cs}{m}'


def info_cells(active, total, when, want, acts, req, upd, req_ok=True, req_bad=False):
    r = (f'<span style="color:var(--bad)">{ms("block", "color:var(--bad)")}{req}</span>' if req_bad else
         f'{ms("verified")}{req} {ms("check", "color:var(--ok)")}' if req_ok else f'{ms("verified")}{req}')
    return [f'{ms("groups")}<b>{active}</b>&nbsp;active <span class="muted">/ {total}</span>', f'{ms("event")}{when}', want,
            f'{ms("castle")}{acts}', r, f'{ms("update")}<span class="muted">{upd}</span>']
