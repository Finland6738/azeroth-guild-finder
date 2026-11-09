"""Offline checks of the addon package: TOC interface, listed files, embeds.xml (Libs only when fetched).

It also checks that every texture of Media/ named in the UI code exists, and that every L["KEY"] used in the code
has an English string (AceLocale answers with the key itself for a missing one, which would hide the mistake).

Usage: python -I -X utf8 tools/check_addon.py (also called by tools/check_docs.py)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "AzerothGuildFinder")
TOC = os.path.join(ADDON, "AzerothGuildFinder.toc")
INTERFACE = "16001"
REQUIRED_TOC_KEYS = ("Title", "Author", "Version", "SavedVariables", "SavedVariablesPerCharacter")


def _path(base, rel):
    return os.path.join(base, *re.split(r"[\\/]", rel.strip()))


def check_embeds(embeds, problems):
    base = os.path.dirname(embeds)
    with open(embeds, encoding="utf-8") as f:
        text = f.read()
    for kind, rel in re.findall(r'<(Script|Include)\s+file="([^"]+)"', text):
        if re.split(r"[\\/]", rel)[0] == "Libs" and not os.path.isdir(os.path.join(ADDON, "Libs")):
            continue   # libraries are fetched, not committed
        target = _path(base, rel)
        if not os.path.isfile(target):
            problems.append(f"{os.path.relpath(embeds, ROOT)}: missing {rel}")
        elif kind == "Include" and rel.lower().endswith(".xml"):
            check_embeds(target, problems)


LUA_DIRS = ("Core", "Data", "Net", "UI")
MEDIA_PATTERNS = (
    r'NineSlice\(\s*[\w.]+\s*,\s*"(\w+)"',          # W.NineSlice(parent, "card", ...)
    r'W\.Texture\(\s*[\w.]+\s*,\s*"(\w+)"',         # W.Texture(parent, "glyph_gear", ...)
    r'W\.Media\(\s*"(\w+)"\s*\)',                    # W.Media("solid")
    r'glyph(?:Texture)?\s*=\s*"(\w+)"',                # glyph = "glyph_back"
    r'glyph\s*=\s*"(\w+)"',
    r'SetGlyph\(\s*"(\w+)"',
    r'\w+\s*=\s*"(role_\w+)"',                        # ROLE_MEDIA values
    r'media\s*=\s*"(\w+)"',                           # media = "emblem_border_0" (Data/TabardParts.lua, Emblems.Layers)
)


def lua_files():
    for sub in LUA_DIRS:
        for folder, _, names in os.walk(os.path.join(ADDON, sub)):
            for name in names:
                if name.endswith(".lua"):
                    yield os.path.join(folder, name)


def check_media(problems):
    media = os.path.join(ADDON, "Media")
    have = {f[:-4] for f in os.listdir(media) if f.endswith(".tga")} if os.path.isdir(media) else set()
    for path in lua_files():
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for pattern in MEDIA_PATTERNS:
            for name in re.findall(pattern, text):
                if name not in have:
                    problems.append(f"{os.path.relpath(path, ROOT)}: Media/{name}.tga is used but missing")


def check_fonts(problems):
    """Every family and weight of the type scale in UI/Skin.lua must have its file and the OFL text of its family."""
    skin = os.path.join(ADDON, "UI", "Skin.lua")
    if not os.path.isfile(skin):
        return
    with open(skin, encoding="utf-8") as f:
        text = f.read()
    fonts = os.path.join(ADDON, "Media", "Fonts")
    families = set()
    for family, weight in re.findall(r'family = "(\w+)", weight = "(\w+)"', text):
        families.add(family)
        if not os.path.isfile(os.path.join(fonts, f"{family}-{weight}.ttf")):
            problems.append(f"Media/Fonts/{family}-{weight}.ttf is used by UI/Skin.lua but missing")
    for family in sorted(families):
        if not os.path.isfile(os.path.join(fonts, f"OFL-{family}.txt")):
            problems.append(f"Media/Fonts/OFL-{family}.txt (the licence of the font) is missing")


def check_locale(problems):
    locale = os.path.join(ADDON, "Locale", "enUS.lua")
    if not os.path.isfile(locale):
        return
    with open(locale, encoding="utf-8") as f:
        have = set(re.findall(r'^L\["([^"]+)"\]\s*=', f.read(), re.M))
    for path in lua_files():
        with open(path, encoding="utf-8") as f:
            text = f.read()
        used = set(re.findall(r'L\["([A-Za-z0-9_]+)"\]', text)) | set(re.findall(r'labelKey\s*=\s*"(\w+)"', text))
        for key in sorted(used - have):
            problems.append(f"{os.path.relpath(path, ROOT)}: L[\"{key}\"] has no string in Locale/enUS.lua")


def check(problems):
    if not os.path.isfile(TOC):
        problems.append("AzerothGuildFinder/AzerothGuildFinder.toc is missing")
        return
    with open(TOC, encoding="utf-8") as f:
        lines = f.read().splitlines()
    meta = {}
    files = []
    for line in lines:
        m = re.match(r"^##\s*([\w-]+)\s*:\s*(.*)$", line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
        elif line.strip() and not line.startswith("#"):
            files.append(line.strip())
    if meta.get("Interface") != INTERFACE:
        problems.append(f"TOC Interface is {meta.get('Interface')!r}, expected {INTERFACE}")
    for key in REQUIRED_TOC_KEYS:
        if not meta.get(key):
            problems.append(f"TOC is missing ## {key}")
    if not files:
        problems.append("TOC lists no files")
    for rel in files:
        if not os.path.isfile(_path(ADDON, rel)):
            problems.append(f"TOC lists a missing file: {rel}")
        elif rel.lower().endswith("embeds.xml"):
            check_embeds(_path(ADDON, rel), problems)
    if not os.path.isfile(os.path.join(ADDON, "Bindings.xml")):
        problems.append("AzerothGuildFinder/Bindings.xml is missing")
    check_media(problems)
    check_locale(problems)
    check_fonts(problems)


def main():
    problems = []
    check(problems)
    for p in problems:
        print(p)
    print(f"Addon check: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
