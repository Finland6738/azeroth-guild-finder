"""Offline tests of Azeroth Guild Finder: the addon runs in Lua 5.1 (through lupa) on a mock WoW client.

Usage: python -X utf8 Tests/run_tests.py [filter] [-v]
  filter   run only the tests whose "file > group > test" name contains this text (case-insensitive)
  -v       print a traceback under every failure
Exit code: 0 all tests passed, 1 a test failed, 2 the harness could not start (lupa or libraries missing, bad TOC).

What it does (ADR 0019): reads AzerothGuildFinder.toc, follows every embeds.xml / Include / Script, loads the mock client
(Tests/mock/*.lua), then the addon files in TOC order exactly like the client (each file gets the addon name and a
private table), restores SavedVariables, fires ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD and runs every
Tests/test_*.lua, each test on a freshly built client. The Ace3 and LibDBIcon libraries are the real ones from
AzerothGuildFinder/Libs/ (tools/fetch_libs.py downloads them; this script runs it when they are missing).
"""
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDON_NAME = "AzerothGuildFinder"
ADDON_DIR = os.path.join(ROOT, ADDON_NAME)
LUPA_PINNED = "2.8"
# The Forever API dump is optional: with it the mock rejects event names the client does not have.
API_DUMP = os.environ.get("AGF_API_DUMP") or os.path.join(os.path.dirname(ROOT), "WoW-Addons", "docs", "api.json")


def die(message, code=2):
    sys.stderr.write(message + "\n")
    sys.exit(code)


try:
    from lupa import lua51
    import lupa
except ImportError:
    die(f"lupa is required: python -m pip install lupa=={LUPA_PINNED}")


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def split_path(value):
    return re.split(r"[\\/]", value.strip())


def read_toc(path):
    """Returns ({field: value}, [file lines in order])."""
    fields, files = {}, []
    with open(path, encoding="utf-8-sig") as f:
        for raw in f.read().splitlines():
            line = raw.strip()
            m = re.match(r"^##\s*([^:]+?)\s*:\s*(.*)$", line)
            if m:
                fields[m.group(1)] = m.group(2)
            elif line and not line.startswith("#"):
                files.append(re.sub(r"\s*\[[^\]]*\]\s*$", "", line))   # [AllowLoadGameMode ...] and similar
    return fields, files


def local_name(element):
    return element.tag.rsplit("}", 1)[-1]


def exact_case(path):
    """True when every component of `path` below the repository root has exactly the case on disk (the client is
    case-insensitive and CI is not: a TOC line that works on Windows must still work on Linux)."""
    current = ROOT
    for part in os.path.relpath(path, ROOT).split(os.sep):
        if part not in os.listdir(current):
            return False
        current = os.path.join(current, part)
    return True


def expand(files, base, plan, missing):
    """Appends {path, name | code} entries for every Lua file, following XML files in document order."""
    for entry in files:
        path = os.path.join(base, *split_path(entry))
        if not os.path.isfile(path) or not exact_case(path):
            missing.append(path)
            continue
        if path.lower().endswith(".xml"):
            expand_xml(path, plan, missing)
        else:
            plan.append({"path": path, "name": rel(path)})


def expand_xml(path, plan, missing):
    base = os.path.dirname(path)
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        die(f"{rel(path)}: not valid XML ({e})")
    for element in tree.getroot().iter():
        kind = local_name(element)
        target = element.get("file")
        if kind in ("Script", "Include") and target:
            expand([target], base, plan, missing)
        elif kind == "Script" and (element.text or "").strip():
            plan.append({"code": element.text, "name": rel(path) + " (inline script)"})


def build_plan():
    toc = os.path.join(ADDON_DIR, ADDON_NAME + ".toc")
    if not os.path.isfile(toc):
        die(f"{rel(toc)} is missing")
    fields, files = read_toc(toc)
    plan, missing = [], []
    expand(files, ADDON_DIR, plan, missing)
    return fields, plan, missing


def load_events():
    """Names of the events of the Forever client, or None when the API dump is not available."""
    if not os.path.isfile(API_DUMP):
        return None
    with open(API_DUMP, encoding="utf-8") as f:
        dump = json.load(f)
    names = set()
    for system in dump.get("systems", []):
        for event in system.get("events", []):
            names.add(event.get("literalName") or event.get("name"))
    return sorted(n for n in names if n) or None


def b(text):
    return text.encode("utf-8")


def to_lua_list(lua, items):
    return lua.table_from([b(i) for i in items])


def zcompress(data, wbits, level):
    c = zlib.compressobj(level, zlib.DEFLATED, wbits)
    return c.compress(bytes(data)) + c.flush()


def zdecompress(data, wbits):
    try:
        d = zlib.decompressobj(wbits)
        out = d.decompress(bytes(data))
        out += d.flush()
        if not d.eof:
            return False, b"incomplete compressed data"
        return True, out
    except zlib.error as e:
        return False, b(str(e))


def main(argv):
    flt, verbose = "", False
    for arg in argv:
        if arg == "-v":
            verbose = True
        elif arg.startswith("-"):
            die(f"unknown option {arg}")
        else:
            flt = arg
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if lupa.__version__ != LUPA_PINNED:
        print(f"note: lupa {lupa.__version__} is installed, the project pins {LUPA_PINNED}")

    fields, plan, missing = build_plan()
    if missing and any("Libs" in split_path(rel(m)) for m in missing):
        print("Libraries are missing: running tools/fetch_libs.py")
        result = subprocess.run([sys.executable, "-I", "-X", "utf8", os.path.join(ROOT, "tools", "fetch_libs.py")])
        if result.returncode != 0:
            die("Could not fetch the libraries. Run: python -I -X utf8 tools/fetch_libs.py")
        fields, plan, missing = build_plan()
    if missing:
        die("Files listed by the TOC or embeds.xml are missing:\n  " + "\n  ".join(rel(m) for m in missing))

    mock_files = [{"path": os.path.join(HERE, "mock", n), "name": f"Tests/mock/{n}"}
                  for n in sorted(os.listdir(os.path.join(HERE, "mock"))) if n.endswith(".lua")]
    test_files = [{"path": os.path.join(HERE, n), "name": n}
                  for n in sorted(os.listdir(HERE)) if re.match(r"^test_.*\.lua$", n)]
    saved_vars = [v.strip() for key in ("SavedVariables", "SavedVariablesPerCharacter")
                  for v in fields.get(key, "").split(",") if v.strip()]
    events = load_events()

    # encoding=None: Lua strings are bytes, so binary data (compressed payloads) passes through untouched.
    lua = lua51.LuaRuntime(encoding=None, unpack_returned_tuples=True, register_eval=False, register_builtins=False)

    def read_file(path):
        with open(path.decode("utf-8"), "rb") as f:
            return f.read()

    def log(text):
        sys.stdout.write(text.decode("utf-8", "replace"))
        sys.stdout.flush()

    cfg = lua.table_from({
        b"addonName": b(ADDON_NAME),
        b"assertPath": b(os.path.join(HERE, "lib", "assert.lua")),
        b"tocFields": lua.table_from({b(k): b(v) for k, v in fields.items()}),
        b"savedVars": to_lua_list(lua, saved_vars),
        b"plan": lua.table_from([lua.table_from({(b"code" if "code" in p else b"path"): b(p.get("code") or p["path"]),
                                                  b"name": b(p["name"])}) for p in plan]),
        b"mockFiles": lua.table_from([lua.table_from({b"path": b(f["path"]), b"name": b(f["name"])}) for f in mock_files]),
        b"testFiles": lua.table_from([lua.table_from({b"path": b(f["path"]), b"name": b(f["name"])}) for f in test_files]),
        b"events": lua.table_from({b(e): True for e in events}) if events else None,
        b"filter": b(flt),
        b"verbose": verbose,
        b"readfile": read_file,
        b"log": log,
        b"zcompress": zcompress,
        b"zdecompress": zdecompress,
    })

    if not test_files:
        die("No Tests/test_*.lua files found")
    compile_chunk = lua.eval(b"function(src, name) local c, e = loadstring(src, name); if not c then error(e) end; return c end")
    chunk = compile_chunk(read_file(b(os.path.join(HERE, "lib", "harness.lua"))), b"@Tests/lib/harness.lua")
    H = chunk(cfg)
    print(f"Azeroth Guild Finder offline tests: {len(plan)} addon files, {len(mock_files)} mock files"
          + ("" if events else ", API dump not found (event names are not validated)"))
    passed, failed, files = H.run()
    print(f"\n{passed + failed} tests in {files} files: {passed} passed, {failed} failed.")
    return 1 if failed or passed == 0 else 0   # running nothing is not a pass


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
