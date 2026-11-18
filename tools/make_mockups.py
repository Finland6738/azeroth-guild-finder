"""Generates the design-preview images of the whole interface into assets/ (one image per case).

Every image is drawn from the addon's own layout and English texts (UI/*.lua, Locale/enUS.lua) in the look of the
mockups of docs/specs/mockups/ (original emblems and banners; class icons are the game's icons hot-linked from the Wowhead CDN at render time, as the older mockups do, and
nothing is stored in the repository; the fonts come from Google Fonts). Nothing has been run in the real
WoW client yet, so each image carries a "Design preview" strip at the bottom.

Usage:
    python -X utf8 tools/make_mockups.py              all images
    python -X utf8 tools/make_mockups.py guild-page   only the images whose name contains the text
    python -X utf8 tools/make_mockups.py --index      only rewrite assets/README.md (no browser needed)

Needs headless Chrome or Edge (the CHROME environment variable overrides the search) and Pillow (it writes the WebP files).
The scenes are in tools/mockup_scenes.py and tools/mockup_scenes2.py, the building blocks in tools/mockup_lib.py.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
CSS_DIR = os.path.join(ROOT, "docs", "specs", "mockups", "html")
OUT = os.path.join(ROOT, "assets")
W, H, STRIP = 1280, 820, 34

EXTRA_CSS = """
body { background: #110d0a; width: 1280px; }
.dp { height: 34px; display: flex; align-items: center; gap: 10px; padding: 0 16px; background: #1b140e; color: #e9dcc2; font: 400 12.5px/16px Roboto, sans-serif; border-top: 1px solid #4a3a26; white-space: nowrap; overflow: hidden; }
.dp b { background: #f2bf3c; color: #2b1a05; padding: 2px 8px; border-radius: 4px; font-weight: 700; letter-spacing: .6px; font-size: 11px; }
.dp .cap { color: #fff3d1; font-weight: 500; overflow: hidden; text-overflow: ellipsis; }
.dp .r { margin-left: auto; color: #bfa77a; }
.dot.bad { background: #c0392b; box-shadow: 0 0 0 2px rgba(192,57,43,.25); }
.seg { display: inline-flex; border-radius: var(--r-pill); box-shadow: 0 0 0 1.5px #7a5430; overflow: hidden; }
.seg > span { display: inline-flex; align-items: center; gap: 6px; height: 34px; padding: 0 16px; font: 500 13px/1 Roboto; color: #4a2c12; border-left: 1.5px solid #7a5430; background: rgba(255,245,225,.5); }
.seg > span:first-child { border-left: 0; }
.seg > span.on { background: linear-gradient(#7a4a22, #5a3315); color: #ffeac2; }
.seg > span.on::before { content: "check"; font-family: 'Material Symbols Rounded'; font-size: 16px; }
.steps { display: flex; flex-direction: column; gap: 4px; }
.step { display: flex; align-items: center; gap: 10px; height: 40px; padding: 0 12px; border-radius: var(--r-sm); font: 500 14px/18px Roboto; color: #4b2e14; }
.step .n { width: 24px; height: 24px; border-radius: 50%; display: grid; place-items: center; font: 700 12px/1 Roboto; background: rgba(110,70,30,.18); }
.step .ms { margin-left: auto; font-size: 20px; }
.step.done .n { background: var(--ok); color: #fff; } .step.done .ms { color: var(--ok); }
.step.bad .n { background: var(--bad); color: #fff; } .step.bad .ms { color: var(--bad); }
.step.on { background: linear-gradient(#fff2d4, #f6dfb1); box-shadow: inset 0 0 0 2px var(--gold-2), var(--e1); }
.counter { display: flex; gap: 10px; } .counter .card { flex: 1; text-align: center; padding: 10px; }
.app { display: flex; align-items: center; gap: 14px; padding: 12px 14px; margin-bottom: 10px; border-radius: var(--r-md); background: linear-gradient(#fff3da, #f7e1b9); box-shadow: var(--e2), inset 0 0 0 1px rgba(160,110,60,.3); }
.app .who { flex: 1; min-width: 0; } .app .nm { font: 700 16px/20px Roboto; }
.app .meta { font: 400 13px/18px Roboto; color: var(--ink-2); display: flex; gap: 10px; align-items: center; margin-top: 2px; white-space: nowrap; }
.app .meta .ms { font-size: 16px; color: #8a5a2a; } .app.new { box-shadow: var(--e2), inset 0 0 0 2px var(--gold); }
.hist { display: grid; grid-template-columns: 26px 1.3fr 1fr 1.3fr; align-items: center; gap: 10px; height: 38px; padding: 0 12px; border-bottom: 1px solid rgba(160,110,60,.25); font: 400 13px/16px Roboto; }
.hist:last-child { border: 0; }
.empty { height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; gap: 10px; }
.hero-emb { width: 150px; height: 180px; margin: 4px auto 0; filter: drop-shadow(0 6px 6px rgba(60,30,0,.45)); }
.gname { text-align: center; font: 900 28px/32px Roboto; color: #3a200c; margin-top: 4px; } .gsub { text-align: center; font: 400 13.5px/19px Roboto; color: #5d3d20; }
.contact { display: flex; align-items: center; gap: 10px; height: 34px; font: 400 13.5px/18px Roboto; }
.banner { position: relative; height: 130px; border-radius: var(--r-md); overflow: hidden; box-shadow: var(--e2), inset 0 0 0 2px #6e4c2c; }
.banner svg { width: 100%; height: 100%; display: block; }
.banner::after { content: ""; position: absolute; inset: 0; background: linear-gradient(180deg, transparent 45%, rgba(246,214,166,.95) 100%); }
.lf { position: relative; margin: -50px 18px 0; z-index: 2; }
.lf-grid { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 4px; }
.lf-item { display: flex; align-items: center; gap: 10px; padding: 8px 12px 8px 8px; border-radius: var(--r-sm); background: rgba(255,255,255,.55); box-shadow: inset 0 0 0 1px rgba(184,130,15,.45); }
.lf-item b { display: block; font: 700 13.5px/16px Roboto; } .lf-item .roles { display: flex; gap: 4px; margin-top: 3px; }
.cols { display: grid; grid-template-columns: 1.1fr 1fr; gap: 12px; margin-top: 12px; } .stack { display: flex; flex-direction: column; gap: 12px; }
.req { display: flex; align-items: center; gap: 8px; font: 400 13.5px/22px Roboto; }
.mini.gcard .top { min-height: 92px; padding: 8px; gap: 10px; } .mini.gcard .emb { width: 58px; height: 70px; }
.mini.gcard .name { font-size: 15px; line-height: 18px; } .mini.gcard .sub { font-size: 11.5px; line-height: 15px; } .mini.gcard .art { width: 60%; }
table.grid { border-collapse: separate; border-spacing: 0 3px; width: 100%; }
table.grid th { font: 700 11.5px/14px Roboto; vertical-align: bottom; color: var(--ink-2); text-align: center; padding-bottom: 2px; } table.grid th:first-child { text-align: left; }
table.grid td { text-align: center; height: 28px; background: rgba(255,245,225,.35); }
table.grid td:first-child { text-align: left; padding-left: 8px; border-radius: 6px 0 0 6px; font: 500 13.5px/1 Roboto; } table.grid td:last-child { border-radius: 0 6px 6px 0; }
table.grid td .who { display: flex; align-items: center; gap: 10px; } table.grid tr.any td { background: rgba(242,191,60,.18); }
.check { display: flex; align-items: center; gap: 8px; font: 400 13px/22px Roboto; } .check .ms { font-size: 18px; }
.thumbs { display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; } .thumb { height: 44px; border-radius: 6px; overflow: hidden; box-shadow: inset 0 0 0 1.5px #6e4c2c; }
.thumb svg { width: 100%; height: 100%; display: block; } .thumb.on { box-shadow: 0 0 0 2px #fff7e0, 0 0 0 4px var(--gold-2); }
.sec { display: flex; flex-direction: column; gap: 8px; } .sec-h { display: flex; align-items: center; gap: 10px; } .sec-h .plate { flex: 1; padding: 6px 12px; font-size: 13px; }
.sw-row { display: flex; gap: 6px; flex-wrap: wrap; } .swatch { width: 26px; height: 26px; border-radius: 6px; box-shadow: inset 0 0 0 1.5px rgba(0,0,0,.45), 0 1px 2px rgba(0,0,0,.3); }
.swatch.on { box-shadow: 0 0 0 2px #fff7e0, 0 0 0 4px var(--gold-2), 0 2px 4px rgba(0,0,0,.4); }
.syms { display: grid; gap: 6px; } .sym { width: 46px; height: 46px; border-radius: 8px; padding: 7px; background: linear-gradient(#5b636b, #2c3136); box-shadow: inset 0 0 0 2px #8e979f, inset 0 0 0 3px #1a1d20, var(--e1); }
.sym.on { box-shadow: inset 0 0 0 2px var(--gold), inset 0 0 0 3px #2b1c06, 0 0 10px rgba(242,191,60,.6); }
.stepper { display: inline-flex; align-items: center; gap: 4px; height: 32px; padding: 0 4px; border-radius: var(--r-pill); background: linear-gradient(#5c646c, #30353b); color: #f0f3f6; font: 500 12.5px/1 Roboto; box-shadow: 0 0 0 1.5px #111, var(--e1); }
.stepper .ms { width: 24px; height: 24px; border-radius: 50%; display: grid; place-items: center; background: radial-gradient(circle at 40% 35%, #ffe28a, var(--gold) 55%, var(--gold-2)); color: #2b1a05; font-size: 18px; }
.stepper b { padding: 0 8px; min-width: 120px; text-align: center; font-weight: 500; }
.preview { width: 100%; height: 300px; border-radius: var(--r-md); position: relative; overflow: hidden; box-shadow: inset 0 0 0 2px #6e4c2c, var(--e2); }
.preview .bg { position: absolute; inset: 0; } .preview .bg svg { width: 100%; height: 100%; }
.preview .big { position: absolute; left: 50%; top: 24px; width: 180px; height: 216px; transform: translateX(-50%); filter: drop-shadow(0 10px 10px rgba(0,0,0,.6)); }
.dim { position: absolute; inset: 0; z-index: 30; background: rgba(8,6,4,.55); display: grid; place-items: center; }
.modal { border-radius: var(--r-md); padding: 20px 22px; background-image: var(--grain), radial-gradient(ellipse at 50% 30%, var(--parch-hi), var(--parch) 70%); background-color: var(--parch); background-blend-mode: multiply, normal; box-shadow: 0 0 0 2px #3a4047, 0 0 0 3px #8a939b, var(--e5); }
.snack { position: absolute; left: 50%; bottom: 44px; transform: translateX(-50%); z-index: 40; display: flex; align-items: center; gap: 14px; padding: 12px 18px; border-radius: var(--r-sm); background: #2d241b; color: #f7ead2; font: 400 14px/18px Roboto; box-shadow: var(--e3); }
.dropdown { position: absolute; left: 0; top: 66px; width: 100%; z-index: 20; padding: 6px 0; border-radius: var(--r-sm); background: #fff4dd; box-shadow: 0 0 0 2px #3a4047, var(--e5); }
.dropdown .di { display: flex; align-items: center; gap: 10px; height: 30px; padding: 0 12px; font: 400 13.5px/18px Roboto; }
.world { position: absolute; inset: 0; } .world svg { width: 100%; height: 100%; }
.minimap { position: absolute; right: 30px; top: 24px; width: 170px; height: 170px; border-radius: 50%; background: radial-gradient(circle at 40% 40%, #5d7a46, #2f4426 70%); box-shadow: 0 0 0 6px #3b3f44, 0 0 0 8px #9aa4ae, var(--e3); z-index: 2; }
.mm-btn { position: absolute; width: 34px; height: 34px; border-radius: 50%; background: radial-gradient(circle at 35% 30%, #eef2f6, #8f99a3 60%, #4a525a); box-shadow: var(--e2); display: grid; place-items: center; }
.mm-btn .in { width: 26px; height: 30px; }
.chat { position: absolute; left: 20px; bottom: 120px; width: 470px; padding: 10px 12px; border-radius: 6px; background: rgba(0,0,0,.42); font: 400 13px/20px Roboto; color: #e9e2d4; z-index: 2; }
.bar { position: absolute; left: 50%; bottom: 20px; transform: translateX(-50%); display: flex; gap: 4px; padding: 6px; border-radius: 8px; background: rgba(15,15,15,.75); box-shadow: 0 0 0 2px #50565c; z-index: 2; }
.bar span { width: 40px; height: 40px; border-radius: 5px; background: linear-gradient(135deg, #5e5040, #2a241d); box-shadow: inset 0 0 0 1.5px #8c7a5c; }
.fab { position: absolute; width: 64px; height: 64px; border-radius: 50%; display: grid; place-items: center; z-index: 5; background: radial-gradient(circle at 35% 30%, #4a5058, #1d2024 70%); box-shadow: 0 0 0 3px var(--gold), 0 0 0 5px #2b1c06, 0 0 22px 6px rgba(242,191,60,.55), var(--e5); }
.fab .in { width: 40px; height: 48px; } .fab .badge { position: absolute; top: -4px; right: -6px; min-width: 26px; height: 26px; font-size: 14px; }
.pop { position: absolute; width: 400px; border-radius: var(--r-md); padding: 14px 14px 10px; z-index: 6; background-image: var(--grain), radial-gradient(ellipse at 50% 30%, var(--parch-hi), var(--parch) 70%); background-color: var(--parch); background-blend-mode: multiply, normal; box-shadow: 0 0 0 2px #3a4047, 0 0 0 3px #8a939b, var(--e5); }
.qi { display: flex; align-items: center; gap: 10px; padding: 8px; border-radius: var(--r-sm); background: rgba(255,245,225,.55); margin-bottom: 6px; box-shadow: inset 0 0 0 1px rgba(160,110,60,.3); }
.qi .who { flex: 1; } .qi b { display: block; font: 700 14px/18px Roboto; } .qi .caption { font-size: 11.5px; }
.menu { position: absolute; width: 290px; padding: 6px 0; z-index: 6; border-radius: var(--r-xs); background: #1f1a15; border: 1px solid #6b5a40; box-shadow: var(--e5); color: #f3e6cf; font: 400 13px/18px Roboto; }
.menu div { display: flex; align-items: center; gap: 10px; height: 34px; padding: 0 14px; } .menu .ms { font-size: 18px; width: 18px; color: var(--gold); }
.menu .t { font: 700 11.5px/16px Roboto; letter-spacing: 1px; text-transform: uppercase; color: #bfa77a; height: 28px; } .menu .hr { height: 1px; padding: 0; margin: 4px 0; background: #4a3f30; }
.tooltip { z-index: 9; }
.ms.spin { animation: none; }
"""

# Class icons: the game's own icons, hot-linked from the Wowhead CDN at render time by agf.js (the same as the older
# mockups); no icon file is stored in the repository. The render fails instead of drawing letters when one does not load.
WAIT_JS = r"""
document.addEventListener('DOMContentLoaded', () => {
  window.__icons = 0; window.__iconsFailed = 0;
  document.querySelectorAll('[data-cls]').forEach(el => {
    const m = /url\(["']?([^"')]+)/.exec(el.style.backgroundImage || ''); if (!m) { window.__iconsFailed++; return; }
    const img = new Image(); const d = document.documentElement; img.onload = () => { d.dataset.icons = ++window.__icons + '/' + window.__iconsFailed; }; img.onerror = () => { d.dataset.icons = window.__icons + '/' + (++window.__iconsFailed); }; img.src = m[1];
  });
});
"""


def page(name, caption, body):
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{name}</title>
<link rel="stylesheet" href="{{CSS}}/agf.css"><style>{EXTRA_CSS}</style><script src="{{CSS}}/agf.js"></script><script>{WAIT_JS}</script></head>
<body><div class="stage">{body}</div>
<div class="dp"><b>DESIGN PREVIEW</b><span class="cap">{caption}</span><span class="r">Not a screenshot: nothing has run in WoW Forever yet</span></div></body></html>"""


def find_browser():
    pf, pf86 = os.environ.get("ProgramFiles", ""), os.environ.get("ProgramFiles(x86)", "")
    for p in [os.environ.get("CHROME", ""), os.path.join(pf, "Google", "Chrome", "Application", "chrome.exe"),
              os.path.join(pf86, "Google", "Chrome", "Application", "chrome.exe"), os.path.join(pf86, "Microsoft", "Edge", "Application", "msedge.exe"),
              os.path.join(pf, "Microsoft", "Edge", "Application", "msedge.exe"), "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
              "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]:
        if p and os.path.exists(p):
            return p
    for n in ("google-chrome", "chromium", "chrome", "msedge"):
        if shutil.which(n):
            return shutil.which(n)
    sys.exit("No Chrome or Edge found: set the CHROME environment variable to its path.")


def preflight(chrome, tmp, css, scene):
    """Stops when the class icons cannot be loaded (no network, CDN down): letters or blanks must never be published."""
    name, caption, fn = scene
    src = os.path.join(tmp, "preflight.html")
    open(src, "w", encoding="utf-8", newline="\n").write(page(name, caption, fn()).replace("{CSS}", css))
    dom = subprocess.run([chrome, "--headless=new", "--disable-gpu", "--virtual-time-budget=9000", "--dump-dom", "file:///" + src.replace("\\", "/")],
                         capture_output=True, text=True, timeout=120).stdout
    import re
    m = re.search(r'data-icons="(\d+)/(\d+)"', dom)
    if not m or int(m.group(1)) < 3 or int(m.group(2)) > 0:
        sys.exit("The class icons did not load (wow.zamimg.com unreachable?): nothing was rendered. Result: " + (m.group(0) if m else "no icon loaded"))
    print("class icons loaded:", m.group(1))


def to_webp(png, webp):
    """The browser's PNG becomes a lossy WebP (quality 84): flat parchment and metal stay sharp at about 60-110 KB."""
    from PIL import Image
    Image.open(png).convert("RGB").save(webp, "WEBP", quality=84, method=6)
    os.remove(png)


def write_index(rows):
    lines = ["# Interface previews", "",
             "One image for every case of the Azeroth Guild Finder interface, so you can see what the addon looks like before you install it.", "",
             "> **Design previews, not screenshots.** They are drawn from the addon's own layout and texts, in the look of the specification's mockups, "
             "with original emblems and banner art; the class icons are the game's own, loaded from the Wowhead CDN when the images are made and not stored in the repository. Nothing has been run in the WoW Forever client yet, so the real window may differ in small details "
             "(for example the banner pictures come from the game, and fonts are the game's own). Every image says so in its bottom strip.", "",
             "The images are generated by `tools/make_mockups.py` (`python -X utf8 tools/make_mockups.py`): rerun it after a change of the interface. "
             "The scenes are in `tools/mockup_scenes.py` and `tools/mockup_scenes2.py`.", "",
             "The addon has only an English interface for now, so there is no translated set.", ""]
    groups = {}
    for name, cap in rows:
        groups.setdefault(prefix_of(name), []).append((name, cap))
    for title in GROUP_ORDER:
        items = groups.get(title)
        if not items:
            continue
        lines += [f"## {title}", "", "| Preview | What it shows |", "|---|---|"]
        for name, cap in items:
            lines.append(f"| [![{cap}]({name}.webp)]({name}.webp) | **{name}**<br>{cap} |")
        lines.append("")
    open(os.path.join(OUT, "README.md"), "w", encoding="utf-8", newline="\n").write("\n".join(lines))


GROUP_ORDER = ["Find a Guild", "Guild page and applying", "My Application", "Listing editor", "Emblems", "My Guild", "Applications panel",
               "Notifications, minimap and chat", "Settings and diagnostics"]


def prefix_of(name):
    for pre, g in [("find-a-guild", "Find a Guild"), ("guild-page", "Guild page and applying"), ("apply", "Guild page and applying"),
                   ("my-application", "My Application"), ("editor", "Listing editor"), ("emblem", "Emblems"), ("my-guild", "My Guild"),
                   ("applications", "Applications panel"), ("notification", "Notifications, minimap and chat"), ("minimap", "Notifications, minimap and chat"),
                   ("chat", "Notifications, minimap and chat"), ("settings", "Settings and diagnostics"), ("diagnostics", "Settings and diagnostics")]:
        if name.startswith(pre):
            return g
    return "Other"



def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    import mockup_scenes2  # noqa: F401  (registers the scenes of part 2 after those of part 1)
    from mockup_scenes import SCENES
    names = [s[0] for s in SCENES]
    assert len(names) == len(set(names)), "duplicate scene names"
    os.makedirs(OUT, exist_ok=True)
    only = args[0] if args else ""
    if "--index" not in sys.argv:
        chrome = find_browser()
        tmp = tempfile.mkdtemp(prefix="agf-mockups-")
        css = "file:///" + CSS_DIR.replace("\\", "/")
        try:
            preflight(chrome, tmp, css, SCENES[0])
            for name, caption, fn in SCENES:
                if only and only not in name:
                    continue
                html = page(name, caption, fn()).replace("{CSS}", css)
                src = os.path.join(tmp, name + ".html")
                open(src, "w", encoding="utf-8", newline="\n").write(html)
                out = os.path.join(tmp, name + ".png")
                subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size={W},{H + STRIP}",
                                "--virtual-time-budget=9000", f"--screenshot={out}", "file:///" + src.replace("\\", "/")],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=120)
                to_webp(out, os.path.join(OUT, name + ".webp"))
                print(f"{name}.webp  {os.path.getsize(os.path.join(OUT, name + '.webp')) // 1024} KB")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    write_index([(n, c) for n, c, _ in SCENES])
    print(f"{len(SCENES)} scenes, index written to assets/README.md")


if __name__ == "__main__":
    main()
