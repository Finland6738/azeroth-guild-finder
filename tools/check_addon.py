"""Offline checks of the addon package: TOC interface, listed files, embeds.xml (Libs only when fetched).

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


def main():
    problems = []
    check(problems)
    for p in problems:
        print(p)
    print(f"Addon check: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
