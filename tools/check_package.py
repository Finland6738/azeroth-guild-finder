"""Offline check of what the release package contains (ADR 0022). No network, no secrets.

Two modes:

  python -I -X utf8 tools/check_package.py
      Reads .pkgmeta and the files git tracks, and works out what the BigWigs packager would put in the zip: the
      packager copies only tracked files, skips every dotfile and dot-folder, skips what `ignore:` matches (a shell
      pattern against the path from the repository root, `*` crossing folders), adds the `externals:` and moves the
      addon folder to the top of the package (`move-folders:`). It then checks the result (see check_contents).
      Add --list to print the files.

  python -I -X utf8 tools/check_package.py --zip .release/AzerothGuildFinder-v1.0.0-forever.zip [--tag v1.0.0] [--list]
      Checks a zip the packager really built, with the same rules plus: the version in the TOC was filled in (and is
      the tag), and every file the TOC and embeds.xml load is inside.

Rules: the GPL-3.0 LICENSE and the OFL text of every bundled font family ship; Tests/, docs/, tools/, .github,
Markdown files and other development files do not; no packaged Lua file can run as a development build (the
`--@debug@` block of Core/Config.lua is commented out by the packager, so Config.DEV is false in a release);
every Lua file in the addon is loaded by the TOC.

Also called by tools/check_docs.py (with a self-test of the zip rules on small made-up zips).
"""
import argparse
import fnmatch
import io
import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import fetch_libs  # noqa: E402  (the one parser of the externals block)

PKGMETA = os.path.join(ROOT, ".pkgmeta")
LICENSE_FIRST_LINE = "GNU GENERAL PUBLIC LICENSE"

# Never in a package, whatever .pkgmeta says (matched on the path inside the package, folder by folder).
FORBIDDEN_DIRS = {"Tests", "docs", "tools", ".github", ".git", ".idea", ".vscode", ".claude", "__pycache__"}
FORBIDDEN_FILES = {".pkgmeta", ".gitignore", ".gitattributes", ".luarc.json", "local.ini"}
FORBIDDEN_SUFFIXES = (".md", ".pyc", ".ini")


# --- .pkgmeta -----------------------------------------------------------------------------------------------------

def parse_pkgmeta(text):
    """{'package-as': str, 'move-folders': {src: dest}, 'ignore': [patterns], 'externals': {path: (url, tag)}}.
    A deliberately small YAML subset: the same one tools/fetch_libs.py reads."""
    meta = {"package-as": None, "move-folders": {}, "ignore": [], "externals": fetch_libs.parse_externals(text)}
    phase = None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if not line.startswith(" "):
            key, _, value = line.partition(":")
            phase = key.strip()
            if phase == "package-as":
                meta["package-as"] = value.strip()
            continue
        item = line.strip()
        if phase == "ignore" and item.startswith("- "):
            meta["ignore"].append(item[2:].strip().strip('"').strip("'"))
        elif phase == "move-folders" and ":" in item:
            src, _, dest = item.partition(":")
            meta["move-folders"][src.strip()] = dest.strip()
    return meta


def ignored(path, patterns):
    """The packager's match_pattern: a bash glob against the repository-relative path, where * crosses folders.
    An ignore entry that names a folder ignores everything under it; one that does not exist as a file matches a file
    or a folder of that name."""
    for pattern in patterns:
        if fnmatch.fnmatchcase(path, pattern) or fnmatch.fnmatchcase(path, pattern + "/*"):
            return True
    return False


def tracked_files():
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [f for f in out.splitlines() if f and os.path.isfile(os.path.join(ROOT, f))]


# --- debug block (the packager's lua_filter) ----------------------------------------------------------------------

DEBUG_OPEN, DEBUG_CLOSE = "--@debug@", "--@end-debug@"


def packager_debug_filter(text):
    """What the packager does to a Lua file: `--@debug@` becomes `--[==[@debug@` and `--@end-debug@` becomes
    `--@end-debug@]==]`, which comments the block out."""
    return text.replace(DEBUG_OPEN, "--[==[@debug@").replace(DEBUG_CLOSE, DEBUG_CLOSE + "]==]")


def active_code(text):
    """The Lua text without long comments (--[==[ ... ]==]) and line comments (strings are not parsed; the check only
    looks for a DEV assignment)."""
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    return "\n".join(line.split("--", 1)[0] for line in text.splitlines())


DEV_TRUE = re.compile(r"\bDEV\s*=\s*true\b")


def check_dev_code(files, problems, filtered):
    """files: {package path: text of a .lua file}. filtered: True when the packager already ran (a zip)."""
    for path, text in sorted(files.items()):
        if filtered:
            if DEBUG_OPEN in text:
                problems.append(f"{path}: still has an unprocessed {DEBUG_OPEN} marker")
            body = text
        else:
            if text.count(DEBUG_OPEN) != text.count(DEBUG_CLOSE):
                problems.append(f"{path}: {DEBUG_OPEN} and {DEBUG_CLOSE} do not pair up")
            body = packager_debug_filter(text)
        if DEV_TRUE.search(active_code(body)):
            problems.append(f"{path}: sets DEV = true outside a {DEBUG_OPEN} block, so a release would be a development build")


def check_config_block(config_text, problems):
    """Core/Config.lua is the one place that turns development mode on, and only between the debug markers."""
    if "Config.DEV = false" not in config_text:
        problems.append("Core/Config.lua: no 'Config.DEV = false' default")
    m = re.search(re.escape(DEBUG_OPEN) + r"(.*?)" + re.escape(DEBUG_CLOSE), config_text, re.S)
    if not m or not DEV_TRUE.search(m.group(1)):
        problems.append(f"Core/Config.lua: 'Config.DEV = true' must sit between {DEBUG_OPEN} and {DEBUG_CLOSE}")


# --- the common rules ---------------------------------------------------------------------------------------------

def forbidden_reason(path):
    """Why a path inside the package (below the addon folder) must not be there, or None."""
    parts = path.split("/")
    for part in parts[:-1]:
        if part in FORBIDDEN_DIRS:
            return f"development folder {part}/"
    name = parts[-1]
    if name in FORBIDDEN_FILES or name.endswith(FORBIDDEN_SUFFIXES):
        return "development or documentation file"
    return None


def font_families(files):
    """Family names of the .ttf files under Media/Fonts: Roboto-Regular.ttf -> Roboto."""
    out = set()
    for f in files:
        m = re.match(r"^Media/Fonts/([A-Za-z0-9]+)-[A-Za-z0-9]+\.ttf$", f)
        if m:
            out.add(m.group(1))
    return out


def toc_info(toc_text):
    meta, listed = {}, []
    for line in toc_text.splitlines():
        m = re.match(r"^##\s*([\w-]+)\s*:\s*(.*)$", line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
        elif line.strip() and not line.startswith("#"):
            listed.append(line.strip().replace("\\", "/"))
    return meta, listed


def check_contents(files, texts, problems, zip_mode, tag=None):
    """files: set of paths relative to the addon folder (AzerothGuildFinder/ in the zip). texts: {path: str} for the
    text files that are checked (TOC, LICENSE, .lua, embeds.xml)."""
    toc_name = "AzerothGuildFinder.toc"
    if toc_name not in files:
        problems.append(f"{toc_name} is not in the package")
        return
    for path in sorted(files):
        if path.startswith("Libs/"):
            continue   # the libraries come as their authors made them, minus what .pkgmeta ignores
        why = forbidden_reason(path)
        if why:
            problems.append(f"{path} would ship: {why}")

    # Licences.
    if "LICENSE" not in files:
        problems.append("LICENSE (the GPL-3.0 text) does not ship: do not ignore it in .pkgmeta")
    elif LICENSE_FIRST_LINE not in texts.get("LICENSE", LICENSE_FIRST_LINE):
        problems.append("LICENSE is not the GPL text")
    families = font_families(files)
    if not families:
        problems.append("no font under Media/Fonts/ ships (the interface needs Roboto)")
    for family in sorted(families):
        if f"Media/Fonts/OFL-{family}.txt" not in files:
            problems.append(f"Media/Fonts/OFL-{family}.txt (the licence of the {family} fonts) does not ship")

    # The TOC and what it loads.
    meta, listed = toc_info(texts.get(toc_name, ""))
    version = meta.get("Version", "")
    if zip_mode:
        if not version or "@" in version:
            problems.append(f"the TOC version is {version!r}: the packager did not fill it in")
        elif tag and version != tag:
            problems.append(f"the TOC version is {version!r} but the tag is {tag!r}")
    elif version != "@project-version@":
        problems.append(f"the TOC version is {version!r}: it must stay '## Version: @project-version@'")
    project_id = meta.get("X-Curse-Project-ID")
    if project_id is not None and not project_id.isdigit():
        problems.append(f"## X-Curse-Project-ID is {project_id!r}: it must be the number of the CurseForge project")
    for rel in listed:
        if rel not in files:
            problems.append(f"the TOC loads {rel} but it is not in the package")
    loaded = set(listed)
    for rel in listed:
        if rel.lower().endswith(".xml") and rel in texts:
            base = os.path.dirname(rel)
            for _kind, inc in re.findall(r'<(Script|Include)\s+file="([^"]+)"', texts[rel]):
                target = os.path.normpath(os.path.join(base, inc.replace("\\", "/"))).replace("\\", "/")
                loaded.add(target)
                if target not in files and (zip_mode or not target.startswith("Libs/")):   # sources: Libs/ is fetched
                    problems.append(f"{rel} loads {inc} but it is not in the package")
    for path in sorted(files):
        if path.endswith(".lua") and not path.startswith("Libs/") and path not in loaded:
            problems.append(f"{path} ships but nothing loads it (not in the TOC)")
    if zip_mode and not any(f.startswith("Libs/Ace3/") for f in files):
        problems.append("Libs/Ace3 is not in the package: the externals of .pkgmeta were not embedded")

    # Development code.
    lua = {p: t for p, t in texts.items() if p.endswith(".lua") and not p.startswith("Libs/")}
    check_dev_code(lua, problems, filtered=zip_mode)
    if not zip_mode and "Core/Config.lua" in texts:
        check_config_block(texts["Core/Config.lua"], problems)


# --- source mode --------------------------------------------------------------------------------------------------

def simulate(meta, tracked):
    """Paths relative to the addon folder that the packager would ship, and the externals it would add."""
    package = meta["package-as"]
    moves = meta["move-folders"]
    shipped = {}
    for path in tracked:
        if any(part.startswith(".") for part in path.split("/")):
            continue   # dotfiles and dot-folders are pruned
        if ignored(path, meta["ignore"]):
            continue
        shipped[path] = path
    # The repository root is the package, then each move-folders entry merges into its destination.
    result = {}
    for path in shipped:
        inside = package + "/" + path
        for src, dest in moves.items():
            prefix = src + "/"   # move-folders paths start at the release folder, where the package folder sits
            if inside.startswith(prefix):
                inside = dest + "/" + inside[len(prefix):]
                break
        result[inside] = path
    return package, result


def check_source():
    problems = []
    with open(PKGMETA, encoding="utf-8") as f:
        meta = parse_pkgmeta(f.read())
    if not meta["package-as"]:
        problems.append(".pkgmeta: no package-as")
        return problems, {}
    package, result = simulate(meta, tracked_files())
    prefix = package + "/"
    files, texts, origin = set(), {}, {}
    for inside, path in result.items():
        if not inside.startswith(prefix):
            problems.append(f"{path} would ship outside the folder {package}/: {inside}")
            continue
        rel = inside[len(prefix):]
        files.add(rel)
        origin[rel] = path
        if rel in ("LICENSE", "AzerothGuildFinder.toc", "Core/Config.lua") or rel.endswith((".lua", ".xml")):
            with open(os.path.join(ROOT, *path.split("/")), encoding="utf-8", newline="") as f:
                texts[rel] = f.read()
    # Externals are fetched into Libs/ by the packager (fetch_libs puts them in the same place for development).
    for ext_path in meta["externals"]:
        dest = package + "/" + ext_path
        for src, d in meta["move-folders"].items():
            if dest.startswith(src + "/"):
                dest = d + "/" + dest[len(src) + 1:]
        if dest.startswith(prefix):
            files.add(dest[len(prefix):] + "/")
    files_for_rules = {f for f in files if not f.endswith("/")}
    check_contents(files_for_rules, texts, problems, zip_mode=False)
    return problems, {"files": sorted(files), "externals": meta["externals"]}


# --- zip mode -----------------------------------------------------------------------------------------------------

def read_zip(zf):
    """(files, texts) of a package zip, paths relative to its single top folder; problems for anything else."""
    problems = []
    names = [n for n in zf.namelist() if not n.endswith("/")]
    tops = {n.split("/", 1)[0] for n in names}
    if len(tops) != 1:
        problems.append(f"the zip must have one top folder, it has: {sorted(tops)}")
        return problems, set(), {}
    top = tops.pop()
    files, texts = set(), {}
    for n in names:
        rel = n[len(top) + 1:]
        files.add(rel)
        if rel in ("LICENSE", "AzerothGuildFinder.toc") or rel.endswith((".lua", ".xml")):
            texts[rel] = zf.read(n).decode("utf-8", errors="replace")
    if top != "AzerothGuildFinder":
        problems.append(f"the top folder is {top!r}, it must be AzerothGuildFinder (the addon folder name)")
    return problems, files, texts


def check_zip(path, tag=None):
    with zipfile.ZipFile(path) as zf:
        problems, files, texts = read_zip(zf)
        if files:
            check_contents(files, texts, problems, zip_mode=True, tag=tag)
        total = sum(i.file_size for i in zf.infolist())
    return problems, {"files": sorted(files), "bytes": total}


# --- self-test (called by check_docs.py) --------------------------------------------------------------------------

def _zip(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for name, text in files.items():
            zf.writestr(name, text)
    buf.seek(0)
    return zipfile.ZipFile(buf)


GOOD = {
    "AzerothGuildFinder/AzerothGuildFinder.toc": "## Version: v1.0.0\nembeds.xml\nCore\\Config.lua\n",
    "AzerothGuildFinder/embeds.xml": '<Ui><Script file="Libs\\Ace3\\x.lua"/></Ui>',
    "AzerothGuildFinder/Libs/Ace3/x.lua": "-- lib\n",
    "AzerothGuildFinder/Core/Config.lua": "Config.DEV = false\n--[==[@debug@\nConfig.DEV = true\n--@end-debug@]==]\n",
    "AzerothGuildFinder/LICENSE": "GNU GENERAL PUBLIC LICENSE\n",
    "AzerothGuildFinder/Media/Fonts/Roboto-Regular.ttf": "x",
    "AzerothGuildFinder/Media/Fonts/OFL-Roboto.txt": "OFL",
}


def self_test(problems):
    """The zip rules must accept a good package and refuse each kind of bad one."""
    def run(files, tag=None):
        with _zip(files) as zf:
            found, names, texts = read_zip(zf)
            if names:
                check_contents(names, texts, found, zip_mode=True, tag=tag)
            return found

    if run(GOOD, "v1.0.0"):
        problems.append(f"tools/check_package.py: the good test package was refused: {run(GOOD, 'v1.0.0')}")
    cases = {
        "a missing LICENSE": ({k: v for k, v in GOOD.items() if not k.endswith("/LICENSE")}, "LICENSE"),
        "a missing font licence": ({k: v for k, v in GOOD.items() if "OFL-" not in k}, "OFL-Roboto.txt"),
        "a Tests folder": ({**GOOD, "AzerothGuildFinder/Tests/a.lua": ""}, "development folder Tests/"),
        "a Markdown file": ({**GOOD, "AzerothGuildFinder/README.md": ""}, "documentation file"),
        "an unfilled version": ({**GOOD, "AzerothGuildFinder/AzerothGuildFinder.toc":
                                 GOOD["AzerothGuildFinder/AzerothGuildFinder.toc"].replace("v1.0.0", "@project-version@")},
                                "did not fill it in"),
        "development mode left on": ({**GOOD, "AzerothGuildFinder/Core/Config.lua": "Config.DEV = true\n"}, "DEV = true"),
        "a Lua file nothing loads": ({**GOOD, "AzerothGuildFinder/Extra.lua": ""}, "nothing loads it"),
        "no Libs": ({k: v for k, v in GOOD.items() if "/Libs/" not in k}, "Libs"),
    }
    for label, (files, expect) in cases.items():
        found = run(files, "v1.0.0")
        if not any(expect in p for p in found):
            problems.append(f"tools/check_package.py: {label} was not caught (got {found})")
    if not any("tag" in p for p in run(GOOD, "v2.0.0")):
        problems.append("tools/check_package.py: a TOC version that differs from the tag was not caught")
    # The packager's marker handling, on the real file shape.
    cfg = "Config.DEV = false\n--@debug@\nConfig.DEV = true\n--@end-debug@\nx = 1\n"
    probe = []
    check_dev_code({"Core/Config.lua": cfg}, probe, filtered=False)
    check_config_block(cfg, probe)
    if probe:
        problems.append(f"tools/check_package.py: a correct debug block was refused: {probe}")
    probe = []
    check_dev_code({"Core/Config.lua": "Config.DEV = true\n"}, probe, filtered=False)
    if not probe:
        problems.append("tools/check_package.py: DEV = true outside the debug block was not caught")


def check(problems):
    found, _ = check_source()
    problems.extend(f"package: {p}" for p in found)
    self_test(problems)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--zip", help="check a zip built by the packager instead of the sources")
    ap.add_argument("--tag", help="with --zip: the version tag the TOC must carry")
    ap.add_argument("--list", action="store_true", help="print the files of the package")
    args = ap.parse_args(argv)
    if args.zip:
        problems, info = check_zip(args.zip, args.tag)
        what = os.path.basename(args.zip)
    else:
        problems, info = check_source()
        self_test(problems)
        what = "the package as .pkgmeta describes it"
    if args.list:
        print(f"#### Package contents: {what}\n```")
        for f in info.get("files", []):
            print(f)
        for path, (url, tag) in info.get("externals", {}).items():
            print(f"(external) {path} <- {url} @ {tag}")
        if "bytes" in info:
            print(f"{len(info['files'])} files, {info['bytes']:,} bytes unpacked")
        print("```")
    for p in problems:
        print(p)
    print(f"Package check of {what}: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
