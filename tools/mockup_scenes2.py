"""Design-preview scenes, part 2: the listing editor, emblems, My Guild, the Applications panel, the notification icon,
Settings, the diagnostics box, the minimap button and the chat commands (see tools/make_mockups.py)."""
from mockup_lib import *  # noqa: F401,F403
from mockup_scenes import SCENES, scene, dim, snack, lf_card, guild_right, REQ_OK


# ======================================================================================================================
# Listing editor (Guild Master)
# ======================================================================================================================
STEP_NAMES = ["Identity", "About", "Activity", "Recruitment", "Requirements", "Contact", "Preview &amp; publish"]


def stepper(active, states, ready):
    rows = []
    for i, n in enumerate(STEP_NAMES):
        st = states.get(i, "")
        right_ = {"done": ms("check_circle"), "bad": ms("error")}.get(st, "")
        opt_ = '<span class="caption" style="margin-left:auto">optional</span>' if i == 5 and not st else ""
        rows.append(f'<div class="step {st} {"on" if i == active else ""}"><span class="n">{i + 1}</span>{n}{opt_}{right_}</div>')
    return (f'<div class="plate"><span>Listing sections</span><span style="font-weight:500;opacity:.8">{ready} / 7 ready</span></div>'
            f'<div class="steps">{"".join(rows)}</div>')


def checklist(items):
    rows = []
    for st, text, hint in items:
        icon, color = {"ok": ("check_circle", "var(--ok)"), "bad": ("error", "var(--bad)"), "todo": ("radio_button_unchecked", "var(--ink-3)")}[st]
        weight = "<b>" + text + "</b>" if st == "bad" else text
        rows.append(f'<div class="check" style="{"color:var(--bad)" if st == "bad" else ""}">{ms(icon, "color:" + color)}{weight}</div>')
        if hint:
            rows.append(f'<div class="caption" style="margin:-4px 0 2px 26px">{hint}</div>')
    return card(h3("checklist", "Before publishing") + "".join(rows), "e")


ALL_OK = [("ok", "You are the Guild Master", ""), ("ok", "Subtitle", ""), ("ok", "Description: at least 30 characters", ""),
          ("ok", "Main language", ""), ("ok", "Commitment (Casual, Softcore or Hardcore)", ""), ("ok", "1 to 3 activities", ""),
          ("ok", "Emblem (tabard or designed)", ""), ("ok", '"Looking for" set, or recruitment closed', ""),
          ("ok", "Discord code valid (only if filled in)", "")]


def mini_card(emblem=AUR, sub="Open recruitment · small-scale PvP", classes=("warrior", "priest", "shaman", "mage", "druid")):
    cs = "".join(cl(c, "sm") for c in classes)
    return (f'<div class="gcard mini" style="margin:0;box-shadow:var(--e2);border-radius:8px;background:rgba(255,245,225,.4)"><div class="top">{art("emerald", 3, "art")}'
            f'{emb(emblem, cls="emb")}<div class="txt"><div class="name">Aurora</div><div class="sub">{sub}</div><div style="display:flex;gap:3px;margin-top:6px">{cs}</div></div></div></div>')


STEP_ITEMS = {0: ("Subtitle", "Emblem"), 1: ("Description", "Main language"), 2: ("Commitment", "1 to 3"), 3: ('"Looking for"',), 5: ("Discord",)}


def derive_states(check):
    """Each step is done when its checklist items are all green, in error when one is red; Requirements has no item (it is optional)."""
    out = {4: "done"}
    for i, keys in STEP_ITEMS.items():
        sts = [st for st, text, _ in check if any(text.startswith(k) for k in keys)]
        out[i] = "bad" if "bad" in sts else ("done" if sts and all(x == "ok" for x in sts) else "")
    out[6] = "done" if all(st == "ok" for st, _, _ in check) else ""
    return out


def editor(step, content, states, ready, check=ALL_OK, publish=("Publish listing", True), draft="Draft saved automatically · 2 min ago",
           emblem=AUR, sub_title="Create your listing", next_btn=True):
    states = derive_states(check)
    ready = sum(1 for v in states.values() if v == "done")
    pub_cls = "primary" if publish[1] else "disabled"
    fix = "" if publish[1] else f'<div class="caption" style="text-align:center;margin-top:-4px;color:var(--bad)">{publish[2]}</div>'
    lh = left(f'{brand(emblem, "Aurora", sub_title, True)}{stepper(step, states, ready)}<div style="flex:1"></div>'
              f'<div class="caption">{ms("cloud_done", "font-size:16px;color:var(--ok)")} {draft}</div>'
              f'<span class="btn lg {pub_cls}" style="width:100%">{publish[0]}</span>{fix}'
              f'<div style="text-align:center">{btn("Discard changes", "ghost", "sm")}</div>')
    nxt = btn("Next", "tonal", "md", "arrow_forward") if next_btn else ""
    hdr = f'{btn("Back", "ghost", "md", "arrow_back") if step else ""}{nxt}'
    side = (f'<div style="display:flex;flex-direction:column;gap:12px"><div class="overline">Live preview</div>{mini_card(emblem)}{checklist(check)}'
            f'{field("Guild name: <b style=\"color:var(--ink)\">Aurora</b>", "lock", sq=True, style="background:#efe2c6")}'
            f'<div class="caption" style="margin-top:-6px">Taken from your guild in game. Rename the guild in game to change it. Only the Guild Master can create or edit the listing.</div></div>')
    inner = f'<div style="display:grid;grid-template-columns:1fr 300px;gap:18px"><div style="display:flex;flex-direction:column;gap:12px">{content}</div>{side}</div>'
    rh = right(STEP_NAMES[step], inner, overline=f"Step {step + 1} of 7", header_extra=hdr)
    return window(lh, rh, "gm_new", "CreateListing")


def lbl(text, extra=""):
    return f'<div class="field-label">{text} {extra}</div>'


def hint(text, bad=False):
    return f'<div class="field-help" style="{"color:var(--bad)" if bad else ""}">{text}</div>'


def thumbs(on=0, n=7):
    themes = [("emerald", 3), ("ember", 21), ("frost", 5), ("dusk", 9), ("gold", 4), ("storm", 8)]
    out = f'<div class="thumb {"on" if on == 0 else ""}" style="background:var(--parch);display:grid;place-items:center"><span class="caption">Default</span></div>'
    for i, (t, s) in enumerate(themes[: n - 1], 1):
        out += f'<div class="thumb {"on" if on == i else ""}" data-art="{t}:{s}"></div>'
    return f'<div class="thumbs">{out}</div>'


def emblem_card(mode=0, note="Copied from your guild tabard.", button="", emblem=AUR):
    return card(lbl("Emblem") + seg([f'{ms("checkroom", "font-size:16px")}Guild tabard', "Custom emblem"], mode) +
                f'<div style="display:flex;gap:16px;align-items:center;margin-top:12px">{emb(emblem, "width:72px;height:86px")}<div style="flex:1"><div class="body-m">{note}</div><div style="margin-top:8px">{button}</div></div></div>', style="padding:12px 14px")


def step_identity(mode=0, note="Copied from your guild tabard.", button="", emblem=AUR, ban=0):
    return (card(lbl("Guild name") + field("Aurora", "lock", sq=True, style="background:#efe2c6") + hint("Taken from your guild in game."), style="padding:10px 14px") +
            card(lbl("Subtitle", '<span class="caption" style="float:right">38 / 60</span>') + field("Open recruitment · small-scale PvP", sq=True) + hint("Shown under the guild name in the list. Required."), style="padding:10px 14px") +
            card(lbl("Banner") + thumbs(ban) + hint("The picture behind your guild's card and page. Optional."), style="padding:10px 14px") +
            emblem_card(mode, note, button, emblem))


DESC = "Competitive guild focused on small-scale PvP, with a relaxed raid night on Wednesdays. We help new players gear up and level. Italian first, English welcome."


@scene("editor-identity", "Listing editor, step 1 Identity: guild name, subtitle, banner and emblem (here copied from the guild tabard)")
def _():
    return editor(0, step_identity(), {}, 0, check=[("ok", "You are the Guild Master", ""), ("ok", "Subtitle", ""), ("todo", "Description: at least 30 characters", "")] + [("todo", t, "") for t in ["Main language", "Commitment (Casual, Softcore or Hardcore)", "1 to 3 activities"]] + [("ok", "Emblem (tabard or designed)", "")] + [("todo", '"Looking for" set, or recruitment closed', "")],
                  publish=("Publish listing", False, 'Fix "Description" to publish'))


@scene("editor-about", "Listing editor, step 2 About: the description (at least 30 characters) and the languages")
def _():
    c = (card(lbl("Description", '<span class="caption" style="float:right">153 / 500 · 3 / 12 lines</span>') +
              f'<div class="field textarea" style="min-height:120px;font-size:13.5px"><span>{DESC}</span></div>' + hint("Tell players who you are, when you play and what you expect."), style="padding:10px 14px") +
         card(lbl("Languages") + f'<div style="display:flex;gap:14px;align-items:flex-end"><div style="width:200px">{lbl("Main language")}{field("Italian", "translate", True)}</div>'
              f'<div style="flex:1">{lbl("Also spoken")}<div class="chips"><span class="chip on">English</span><span class="chip">German</span><span class="chip">French</span><span class="chip">Spanish</span></div></div></div>'
              + hint("The main language is required. Players can filter by any of the languages you list."), style="padding:10px 14px"))
    return editor(1, c, {0: "done"}, 4, check=ALL_OK[:3] + [("ok", "Main language", "")] + [("todo", t, "") for t in ["Commitment (Casual, Softcore or Hardcore)", "1 to 3 activities"]] + ALL_OK[6:], publish=("Publish listing", False, 'Fix "Commitment" to publish'))


@scene("editor-activity", "Listing editor, step 3 Activity: commitment, up to three activities in order of importance, play days and hours")
def _():
    acts = ["Raids", "Dungeons", "Leveling", "Questing &amp; Exploration", "Battlegrounds", "World PvP", "Professions &amp; Crafting", "Gold &amp; Trading", "Reputation &amp; Collecting", "Roleplay", "Social &amp; Chat", "Events &amp; Community", "Housing"]
    pick = {5: 1, 0: 2, 4: 3}
    ch = "".join(f'<span class="chip {"on numd" if i in pick else ""}">{f"<span class=num>{pick[i]}</span>" if i in pick else ""}{a}</span>' for i, a in enumerate(acts))
    c = (card(lbl("Commitment", '<span class="caption">(required, one choice)</span>') + seg(["Casual", "Softcore", "Hardcore"], 1) +
              hint("Regular activities and some scheduled events; attendance is welcome but not required."), style="padding:10px 14px") +
         card(lbl("Activities", '<span class="caption">(1 to 3, in order of importance)</span><span class="caption" style="float:right">3 / 3</span>') + f'<div class="chips">{ch}</div>' +
              hint("Up to 3 activities: remove one to pick another. Number 1 is your main focus."), style="padding:10px 14px") +
         card(lbl("Play days &amp; time", '<span class="caption">(your local time, saved as UTC)</span>') + days((0, 1, 2, 3, 4)) +
              f'<div style="display:flex;gap:10px;align-items:center;margin-top:10px"><span class="muted">From</span>{field("20:00", select=True, sq=True, style="width:110px;height:34px")}<span class="muted">To</span>{field("23:30", select=True, sq=True, style="width:110px;height:34px")}<span style="flex:1"></span><span class="opt" style="gap:8px">All day {sw(False)}</span></div>'
              + hint("Players see it in their own time zone · 19:00 – 22:30 UTC"), style="padding:10px 14px"))
    return editor(2, c, {0: "done", 1: "done"}, 6, check=ALL_OK[:6] + ALL_OK[6:7] + [("todo", '"Looking for" set, or recruitment closed', ""), ("ok", "Discord code valid (only if filled in)", "")], publish=("Publish listing", False, 'Fix "Looking for" to publish'))


def look_table(rows):
    hd = "".join(f'<th>{role(r, "lg")}<br>{n}</th>' for r, n in [("t", "Tank"), ("h", "Healer"), ("m", "Melee"), ("r", "Ranged")])
    body = f'<tr class="any"><td><div class="who">{ms("groups", "color:#b8820f")}Any class</div></td>' + "<td><span class=cb></span></td>" * 4 + "</tr>"
    for c, cells in rows:
        tds = "".join(f'<td><span class="cb {x}"></span></td>' for x in cells)
        body += f'<tr><td><div class="who">{cl(c, "sm")}{CLASS_NAMES[c]}</div></td>{tds}</tr>'
    return f'<table class="grid"><tr><th>Class</th>{hd}</tr>{body}</table>'


@scene("editor-recruitment", "Listing editor, step 4 Recruitment: status and the Looking for grid (class by role), new player friendly, applications through the addon")
def _():
    rows = [("warrior", ["on", "x", "", "x"]), ("hunter", ["x", "x", "x", ""]), ("rogue", ["x", "x", "", "x"]), ("priest", ["x", "on", "x", ""]),
            ("shaman", ["x", "on", "", ""]), ("mage", ["x", "x", "x", "on"]), ("warlock", ["x", "x", "x", ""]), ("druid", ["on", "on", "on", ""])]
    c = (f'<div>{lbl("Recruitment status")}{seg(["Open to all", "Selected classes", "Closed"], 1)}<div class="field-help">Only the classes and roles ticked below are wanted.</div></div>' +
         card(h3("person_search", "Looking for", '<span class="caption" style="margin-left:auto">5 chosen</span>') + look_table(rows) +
              '<div class="caption" style="margin-top:6px">Dimmed = role not available for that class · Horde classes only</div>', style="padding:10px 14px") +
         card(opt("New player friendly", True) + opt("Accept applications through the addon", True, "If off, players only see your contacts."), style="padding:6px 14px"))
    return editor(3, c, {0: "done", 1: "done", 2: "done"}, 7 - 3, check=ALL_OK)


@scene("editor-recruitment-closed", "Listing editor, step 4 Recruitment set to Closed: the grid is replaced by a note and the listing says it is not recruiting")
def _():
    c = (f'<div>{lbl("Recruitment status")}{seg(["Open to all", "Selected classes", "Closed"], 2)}<div class="field-help">Not recruiting: the listing says so and asks for nobody.</div></div>' +
         card(h3("person_search", "Looking for") + '<div class="body-m muted">Recruitment is closed. Choose another status above to pick classes.</div>', style="padding:12px 14px"))
    return editor(3, c, {0: "done", 1: "done", 2: "done", 3: "done"}, 4, check=ALL_OK)


@scene("editor-requirements", "Listing editor, step 5 Requirements: minimum level (slider), optional minimum item level and a note")
def _():
    slider = ('<div style="display:flex;align-items:center;gap:14px"><div style="flex:1;height:10px;border-radius:5px;background:linear-gradient(90deg,#7a4a22 0 33%,#d9c19a 33%);box-shadow:inset 0 0 0 1.5px #6a4526;position:relative">'
              '<span style="position:absolute;left:33%;top:-6px;width:22px;height:22px;border-radius:50%;background:radial-gradient(circle at 35% 30%,#ffe28a,#f2bf3c 55%,#b8820f);box-shadow:0 0 0 2px #3a2a10"></span></div>'
              '<span class="title-m mono" style="width:80px">Level 20</span></div>')
    c = (card(lbl("Minimum level") + slider + hint("Move the slider. Level 1 means no minimum."), style="padding:12px 14px") +
         card(lbl("Minimum item level (optional)") + opt("Ask for a minimum item level", True) + field("60", sq=True, style="width:140px") + hint("Players below it see that they do not meet the requirement."), style="padding:12px 14px") +
         card(lbl("Note", '<span class="caption" style="float:right">31 / 120</span>') + field("Voice chat required for raids", sq=True) + hint("Shown with the requirements. Optional."), style="padding:12px 14px"))
    return editor(4, c, {0: "done", 1: "done", 2: "done", 3: "done"}, 4, check=ALL_OK)


@scene("editor-contact", "Listing editor, step 6 Contact (optional): Discord invite code and up to three guild characters to whisper")
def _():
    chosen = (f'<div class="chips" style="margin-bottom:8px"><span class="chip">{cl("shaman", "sm")}Lyryn · Level 60 {ms("close", "font-size:15px")}</span><span class="chip">{cl("warrior", "sm")}Kaelthar · Level 58 {ms("close", "font-size:15px")}</span></div>')
    members = "".join(f'<div class="di" style="display:flex;gap:10px;align-items:center;height:32px">{cl(c, "sm")}<b>{n}</b><span class="caption">Level {lv}</span><span class="dot" style="margin-left:auto"></span></div>' for c, n, lv in [("mage", "Nym", 41), ("priest", "Mirelle", 60), ("rogue", "Velis", 35)])
    c = (card(lbl("Discord") + field("aurora-it", "forum") + hint("Paste the invite link or only its code: the code is kept. Optional.") +
              f'<div class="caption" style="margin-top:6px;color:var(--ok)">{ms("check_circle", "font-size:15px")} Invite code: aurora-it</div>', style="padding:10px 14px") +
         card(lbl("Characters to contact", '<span class="caption">(up to 3, from your guild)</span><span class="caption" style="float:right">2 / 3</span>') + chosen +
              field("Type a character name", "search", muted=True) + f'<div class="overline" style="margin:10px 0 2px">Online now</div>{members}', style="padding:10px 14px"))
    return editor(5, c, {0: "done", 1: "done", 2: "done", 3: "done", 4: "done"}, 5, check=ALL_OK)


@scene("editor-contact-invalid", "Listing editor, step 6 Contact: a Discord code that is not valid blocks publishing and says why")
def _():
    c = card(lbl("Discord") + field("aurora it!", "forum", style="box-shadow:inset 0 2px 3px rgba(90,50,10,.25),0 0 0 2px var(--bad)") +
             hint("An invite code only has letters, digits and hyphens, for example aurora-it.", True), style="padding:10px 14px") + \
        card(lbl("Characters to contact", '<span class="caption">(up to 3, from your guild)</span><span class="caption" style="float:right">0 / 3</span>') +
             field("Type a character name", "search", muted=True) + hint("Nobody chosen yet. Players can whisper these characters."), style="padding:10px 14px")
    chk = ALL_OK[:-1] + [("bad", "Discord code valid (only if filled in)", "Paste the invite link or only its code, for example aurora-it.")]
    return editor(5, c, {0: "done", 1: "done", 2: "done", 3: "done", 4: "done", 5: "bad"}, 5, check=chk, publish=("Publish listing", False, 'Fix "Contact" to publish'))


@scene("editor-publish", "Listing editor, step 7 Preview & publish: everything is green, so Publish listing is open")
def _():
    full = (f'<div class="overline">Your listing in the list</div>' + mini_card() +
            card(h3("task_alt", "Everything is ready") + '<div class="body-m">Everything is ready. Other players see the listing within a few minutes of publishing.</div>', "gold"))
    return editor(6, full, {i: "done" for i in range(6)}, 7, next_btn=False)


@scene("editor-publish-not-ready", "Listing editor, step 7 when something is missing: Publish stays disabled and names the step to fix")
def _():
    msg = card(h3("pending_actions", "Not ready yet") + '<div class="body-m">Everything in the list must be green before the listing can be published.</div>', "gold")
    chk = [("ok", "You are the Guild Master", ""), ("ok", "Subtitle", ""), ("bad", "Description: at least 30 characters", "12 of 30 characters"), ("ok", "Main language", ""),
           ("ok", "Commitment (Casual, Softcore or Hardcore)", ""), ("bad", "1 to 3 activities", "Pick between 1 and 3 activities."), ("ok", "Emblem (tabard or designed)", ""),
           ("bad", '"Looking for" set, or recruitment closed', "Choose classes and roles, or set recruitment to Closed."), ("ok", "Discord code valid (only if filled in)", "")]
    return editor(6, f'<div class="overline">Your listing in the list</div>{mini_card()}{msg}', {0: "done", 1: "bad", 2: "bad", 3: "bad", 4: "done", 5: "done"}, 3, check=chk,
                  publish=("Publish listing", False, 'Fix "About" to publish'), next_btn=False)


@scene("editor-edit-published", "Editing a published listing: Save changes appears, with Discard changes and Delist")
def _():
    msg = card(h3("edit_note", "Changes since the last published version") + '<div class="body-m">Players keep seeing the last published version until you save. One published change every 5 minutes.</div>', "gold")
    return editor(6, f'<div class="overline">Your listing in the list</div>{mini_card()}{msg}', {i: "done" for i in range(6)}, 7, publish=("Save changes", True),
                  sub_title="Edit listing", draft="Draft saved automatically · just now", next_btn=False)


def confirm(text, yes, no, fg_scene, yes_kind="primary"):
    return fg_scene + dim(f'<div class="modal" style="width:480px"><div class="body-l" style="margin-bottom:16px">{text}</div><div style="display:flex;justify-content:flex-end;gap:10px">{btn(no, "tonal", "md")}{btn(yes, yes_kind, "md")}</div></div>')


@scene("editor-discard-confirm", "Listing editor: asking for confirmation before discarding your changes")
def _():
    return confirm("Discard your changes and go back to the last published version?", "Discard changes", "Cancel",
                   editor(6, f'<div class="overline">Your listing in the list</div>{mini_card()}', {i: "done" for i in range(6)}, 7, publish=("Save changes", True), sub_title="Edit listing", next_btn=False))


@scene("editor-published", "After publishing: a note says the listing will reach other players over the next minutes")
def _():
    return editor(6, f'<div class="overline">Your listing in the list</div>{mini_card()}', {i: "done" for i in range(6)}, 7, publish=("Save changes", True), sub_title="Edit listing", next_btn=False) + \
        snack("Listing published. It will reach other players over the next minutes.")


# ======================================================================================================================
# Emblems
# ======================================================================================================================
@scene("emblem-tabard-copied", "Emblem from the guild tabard: copied as it is (emblem, border and colours), your in-game tabard is never changed")
def _():
    return editor(0, step_identity(0, "Copied from your guild tabard.", btn("Design emblem", "tonal", "sm", "palette")), {}, 0, check=[("ok", "You are the Guild Master", ""), ("ok", "Subtitle", ""), ("ok", "Emblem (tabard or designed)", "")] + [("todo", t, "") for t in ["Description: at least 30 characters", "Main language", "Commitment (Casual, Softcore or Hardcore)", "1 to 3 activities", '"Looking for" set, or recruitment closed']],
                  publish=("Publish listing", False, 'Fix "About" to publish'))


@scene("emblem-tabard-changed", "Emblem when the guild tabard changed in game: the editor offers to update the copy")
def _():
    return editor(0, step_identity(0, "Your tabard changed: update the emblem?", btn("Update emblem", "primary", "sm", "sync")), {}, 0, check=[("ok", "You are the Guild Master", ""), ("ok", "Subtitle", ""), ("ok", "Emblem (tabard or designed)", "")] + [("todo", t, "") for t in ["Description: at least 30 characters", "Main language", "Commitment (Casual, Softcore or Hardcore)", "1 to 3 activities", '"Looking for" set, or recruitment closed']],
                  publish=("Publish listing", False, 'Fix "About" to publish'))


@scene("emblem-no-tabard", "Emblem when the guild has no tabard yet: design one here; the in-game tabard is never changed")
def _():
    return editor(0, step_identity(1, "No guild tabard yet: design an emblem. Your in-game tabard is never changed.", btn("Design emblem", "primary", "sm", "palette"), SCAR),
                  {}, 0, emblem=SCAR, check=[("ok", "You are the Guild Master", ""), ("ok", "Subtitle", "")] + [("todo", t, "") for t in ["Description: at least 30 characters", "Main language", "Commitment (Casual, Softcore or Hardcore)", "1 to 3 activities", "Emblem (tabard or designed)", '"Looking for" set, or recruitment closed']],
                  publish=("Publish listing", False, 'Fix "About" to publish'))


def sw_row(colors, on):
    return '<div class="sw-row">' + "".join(f'<span class="swatch {"on" if i == on else ""}" style="background:{c}"></span>' for i, c in enumerate(colors)) + "</div>"


@scene("emblem-designer", "Emblem designer: background, border (6 styles) and emblem pieces with their colours, a big live preview, Random and Reset")
def _():
    bgc = ["#141c2c", "#4a1414", "#1f3a58", "#1d3a22", "#241a3c", "#3a1408", "#d7dde4", "#1b1b1b"]
    fgc = ["#e3b43d", "#d7dde4", "#1b1b1b", "#8a1d1d", "#2a64bd", "#246227", "#ff7c0a", "#ffffff"]
    syms = "".join(f'<div class="sym {"on" if s == "crown" else ""}" data-emblem=\'{{"bg":"transparent","bc":"transparent","ec":"{"#f2bf3c" if s == "crown" else "#f0f0f0"}","symbol":"{s}","border":"none","bare":true}}\'></div>' for s in ["star", "star8", "sun", "cross", "crescent", "sword", "crown", "tower", "flame", "hood", "beast", "leaf"])
    body = f'''<div style="display:grid;grid-template-columns:1fr 280px;gap:20px">
      <div style="display:flex;flex-direction:column;gap:12px">
        <div class="sec"><div class="plate">Background</div>{sw_row(bgc, 1)}<div class="caption">Colour 2 of 8</div></div>
        <div class="sec"><div class="sec-h"><div class="plate">Border</div><div class="stepper"><span class="ms">chevron_left</span><b>Style 3 of 6 - Double</b><span class="ms">chevron_right</span></div></div>{sw_row(fgc, 0)}</div>
        <div class="sec"><div class="sec-h"><div class="plate">Emblem</div><div class="stepper"><span class="ms">chevron_left</span><b>Page 1 of 4</b><span class="ms">chevron_right</span></div></div>
          <div class="syms" style="grid-template-columns:repeat(6,46px)">{syms}</div>{sw_row(fgc, 0)}</div>
        <div class="caption">Pieces are the game's own tabard emblems and colours, drawn by your game (nothing is copied), plus a few Guild Finder symbols.</div>
        <div class="caption" style="color:var(--ink-2)">{ms("info", "font-size:15px", "o")} The list of tabard pieces is still being checked in the game: some emblems may change or show as '?' in this version.</div>
      </div>
      <div style="display:flex;flex-direction:column;gap:12px"><div class="preview" style="height:260px"><div class="bg" data-art="ember:21"></div><div class="big" style="width:150px;height:180px;top:34px" data-emblem='{json.dumps(SCAR)}'></div></div>
        <div style="display:flex;gap:8px">{btn("Random", "tonal", "sm", "casino").replace("btn", "btn", 1)}{btn("Reset", "tonal", "sm", "restart_alt")}</div>
        <div class="caption">Reset: back to the published design, or to your guild tabard, or to the starting design.</div></div></div>'''
    bg = editor(0, step_identity(1, "Designed in Guild Finder. Your in-game tabard is never changed.", btn("Design emblem", "primary", "sm", "palette"), SCAR), {}, 0, emblem=SCAR)
    return bg + dim(f'<div class="modal" style="width:860px;padding:18px 22px"><div style="display:flex;align-items:center;margin-bottom:12px"><div class="title-l" style="flex:1">Emblem designer</div>{btn("Done", "primary", "md")}</div>{body}</div>')


import json  # noqa: E402  (used by the designer scene)


# ======================================================================================================================
# My Guild (member, officer, Guild Master)
# ======================================================================================================================
def my_guild(role_key, role_label, extra_left="", apps=None, tabs=None, badges=None):
    lh = left(f'{brand(AUR, "Aurora", role_label, True)}<div class="caption">This is how players without a guild see your guild.</div>'
              f'<div style="flex:1"></div>{extra_left}')
    rh = right("My Guild", f'<div style="overflow:hidden;height:100%">{guild_right(lf_card(you=None), REQ_OK)}</div>', status=(f"{role_label} · This is how players without a guild see your guild.", "ok"))
    return window(lh, rh, tabs or role_key, "MyGuild", badges)


def apps_box(text, n):
    return card(f'<div class="overline">APPLICATIONS</div><div class="body-m">{text}</div>' + (f'<div style="margin-top:8px">{btn("Open Applications", "tonal", "sm", "inbox")}</div>' if n else ""), style="padding:10px 12px")


@scene("my-guild-member", "My Guild for a member: the guild's own listing, read-only; only the Guild Master can edit it")
def _():
    lock = card(f'<div class="caption">{ms("lock", "font-size:15px")} Only the Guild Master can edit the listing.</div>', style="padding:8px 10px")
    return my_guild("member", "Member", lock)


@scene("my-guild-officer", "My Guild for an officer: the listing, a count of waiting applications and the Applications tab on the rail")
def _():
    lock = card(f'<div class="caption">{ms("lock", "font-size:15px")} Only the Guild Master can edit the listing.</div>', style="padding:8px 10px")
    return my_guild("officer", "Officer", apps_box("2 applications are waiting. Open the Applications tab.", 2) + lock, badges={"Applications": 2})


@scene("my-guild-guild-master", "My Guild for the Guild Master: Edit listing and Delist, plus the applications count")
def _():
    gm = apps_box("No application is waiting. Open the Applications tab.", 0) + f'<span class="btn primary md" style="width:100%">Edit listing</span><div style="text-align:center">{btn("Delist", "tonal", "md")}</div>'
    return my_guild("gm", "Guild Master", gm)


@scene("my-guild-delist-confirm", "My Guild for the Guild Master: asking for confirmation before removing the guild from Guild Finder")
def _():
    gm = apps_box("No application is waiting. Open the Applications tab.", 0) + f'<span class="btn primary md" style="width:100%">Edit listing</span><div style="text-align:center">{btn("Delist", "tonal", "md")}</div>'
    return confirm("Remove your guild from Guild Finder? Pending applications will be closed.", "Delist", "Cancel", my_guild("gm", "Guild Master", gm))


def my_guild_empty(title, body, extra="", role_label="Officer"):
    lh = left(f'{brand(AUR, "Aurora", role_label, True)}<div style="flex:1"></div>')
    rh = right("My Guild", empty_state(title, body, emblem=BRAND) + extra, status=None)
    return window(lh, rh, "officer_new", "MyGuild")


@scene("my-guild-no-listing", "My Guild when the guild has no listing yet: a member or officer can copy a message for the Guild Master")
def _():
    copy = (f'<div style="max-width:440px;margin:0 auto"><div class="copy">{ms("content_copy", "color:var(--blue)")}<span class="grow"><span class="sel">Please list our guild on Guild Finder (/gf).</span></span></div>'
            '<div class="caption" style="text-align:center;margin-top:8px">Select the message and press Ctrl+C, then send it to your Guild Master.</div></div>')
    return my_guild_empty("Your guild has no listing yet", "Ask your Guild Master to publish one with Guild Finder. Applications will appear here once the guild is listed.", copy)


@scene("my-guild-loading", "My Guild right after login: waiting for the guild's listing to arrive from the Guild Master's addon")
def _():
    return my_guild_empty("Waiting for your guild's listing...", "If your guild is listed, its Guild Master's addon sends the listing within a minute of your login. Nothing to do.", role_label="Member")


# ======================================================================================================================
# Applications panel (Guild Master and officers)
# ======================================================================================================================
def app_row(c, name, line, ilvl, when, tagh, new=False, cname=None):
    col = CLASS_TEXT[c]
    n = f'{name} <span class="tag gold" style="vertical-align:middle">NEW</span>' if new else name
    return (f'<div class="app {"new" if new else ""}">{cl(c, "lg")}<div class="who"><div class="nm" style="color:{col}">{n}</div>'
            f'<div class="meta"><span>{line}</span><span>{ms("shield_with_heart")} {ilvl}</span><span>{ms("schedule")}{when}</span>{tagh}</div></div>'
            f'<span class="icon-btn">{ms("chat")}</span>{btn("Decline", "tonal", "sm")}{btn("Invite", "primary", "sm", "person_add")}</div>')


def pending_rows():
    return (app_row("mage", "Elarin", "Mage · Level 32 · Troll", "iLvl —", "2 h ago", tag("RECEIVED", "ok"), True) +
            app_row("priest", "Mirelle", "Priest · Level 60 · Undead", "iLvl 58", "Yesterday", tag("RECEIVED", "ok")) +
            app_row("warrior", "Brogan", "Warrior · Level 17 · Orc", "iLvl —", "3 days ago", tag("EXPIRES IN 11 DAYS")))


def apps_left(pending, accepted, show=0, officer=True, sub=None):
    role_ = "YOU ARE AN OFFICER" if officer else "YOU ARE THE GUILD MASTER"
    return left(f'''{brand(AUR, "Aurora", role_.title().replace("You Are", "You are").replace("The Guild Master", "the Guild Master").replace("An Officer", "an officer"), True)}
      <div class="plate"><span>Applications</span>{ms("inbox")}</div>
      <div class="counter"><div class="card"><div class="stat"><div class="n">{pending}</div><div class="l">Pending</div></div></div><div class="card"><div class="stat"><div class="n">{accepted}</div><div class="l">Accepted · 30 days</div></div></div></div>
      <div><div class="field-label">Show</div>{seg([f"Pending ({pending})", "History"], show)}</div><div class="divider"></div>
      {opt("Notification icon on screen", True)}{opt("Only when something is pending", False)}{opt("Sound on new application", True)}<div style="flex:1"></div>
      {card('<div class="title-s" style="display:flex;align-items:center;gap:6px">' + ms("sync", "color:var(--ok)") + 'Shared with officers</div><div class="caption">The Guild Master and every officer keep the same list. A decision reaches the others within seconds over the officer channel, and an officer who was away catches up at login.</div>', style="padding:10px 12px")}''')


def apps(show=0, rows=None, title=None, status=None, pending=3, accepted=5, officer=True):
    lh = apps_left(pending, accepted, show, officer)
    ttl = title or ("Pending applications" if show == 0 else "Recent history")
    rh = right(ttl, rows or "", status=status or (f"{pending} pending · shared with the officers of your guild", "ok"), badge=pending or None,
               header_extra='<span class="caption">Applications expire after 14 days</span>' if show == 0 else "")
    return window(lh, rh, "officer" if officer else "gm", "Applications", {"Applications": pending} if pending else None)


@scene("applications-pending", "Applications panel (officers and Guild Master): pending applications with Whisper, Decline and Invite")
def _():
    return apps(0, pending_rows())


def hist_rows():
    def h(c, n, line, kind, by):
        t = {"accepted": tag("ACCEPTED", "ok"), "declined": tag("DECLINED", "bad"), "withdrawn": tag("WITHDRAWN"), "expired": tag("EXPIRED")}[kind]
        return f'<div class="hist">{cl(c, "sm")}<span><b>{n}</b> · {line}</span><span style="justify-self:start">{t}</span><span class="caption">{by}</span></div>'
    return card(h("shaman", "Tharok", "Shaman 41", "accepted", "by Lyryn · 5 Nov") + h("rogue", "Velis", "Rogue 12", "declined", "by Kaelthar · 3 Nov") +
                h("druid", "Nym", "Druid 25", "withdrawn", "by the player · 1 Nov") + h("hunter", "Orsa", "Hunter 30", "expired", "after 14 days · 28 Oct"), style="padding:4px 6px")


@scene("applications-history", "Applications panel, History: accepted, declined, withdrawn and expired applications of the last 30 days")
def _():
    return apps(1, hist_rows())


@scene("applications-empty-pending", "Applications panel with nothing pending: the addon answers applicants by itself while you are online")
def _():
    return apps(0, empty_state("No pending applications", "When a player applies to your guild it appears here. You do not have to do anything to receive them: your addon answers applicants by itself while you are online.", icon="inbox"),
                status=("0 pending · shared with the officers of your guild", "off"), pending=0)


@scene("applications-empty-history", "Applications panel, History with nothing in it yet")
def _():
    return apps(1, empty_state("Nothing in the history yet", "Accepted, declined, withdrawn and expired applications stay here for 30 days.", icon="history"), pending=0, accepted=0, status=("0 pending · shared with the officers of your guild", "off"))


@scene("applications-decline-confirm", "Applications panel: asking for confirmation before declining an application")
def _():
    return confirm("Decline the application of Elarin? The player learns it the next time they meet an officer of the guild online.", "Decline", "Cancel", apps(0, pending_rows()))


@scene("applications-invited", "Applications panel after Invite: a note says the guild invite was sent")
def _():
    return apps(0, pending_rows()) + snack("Guild invite sent to Elarin.")


@scene("applications-offline", "Applications panel when the applicant is offline: Invite explains it and the application stays pending")
def _():
    return apps(0, pending_rows()) + snack("Elarin is offline. Try again later.")


@scene("applications-manual-invite", "Applications panel when the game will not send the invite by itself: send it by hand, then Mark as invited")
def _():
    rows = pending_rows().replace('<span class="btn primary sm"><span class="ms">person_add</span>Invite</span>', '<span class="btn primary sm"><span class="ms">person_add</span>Mark as invited</span>', 1)
    return apps(0, rows) + snack("Press Enter to send the invite to Elarin, then press Mark as invited.")


@scene("applications-not-officer", "Applications panel for someone who lost the officer rank: only the Guild Master and the officers see applications")
def _():
    lh = left(f'{brand(AUR, "Aurora", "Member", True)}<div style="flex:1"></div>')
    body = empty_state("Only the Guild Master and the officers see applications", "Applications for a guild reach its Guild Master and its officers.", icon="lock")
    return window(lh, right("Applications", body), "officer", "Applications")


# ======================================================================================================================
# Notification icon (Guild Master and officers), minimap button, chat
# ======================================================================================================================
WORLD_CSS_FAB = ('left:760px;top:250px')


def world(inner, art_theme="frost:31"):
    return (f'<div class="world" data-art="{art_theme}"></div>' + minimap() + f'<div class="chat">{CHAT_LINES}</div>'
            '<div class="bar">' + "<span></span>" * 12 + "</div>" + inner)


CHAT_LINES = ('<div style="color:#ffd27a">[Guild Finder] New application from <b style="color:#3fc7eb">Elarin</b> (Mage 32). <u>Open</u></div>'
              '<div style="color:#40ff40">[Guild] [Kaelthar]: a mage, finally!</div><div style="color:#ff7fff">[Lyryn] whispers: I will check it tonight</div>')


def minimap(tip=False):
    t = ""
    if tip:
        t = ('<div class="tooltip" style="left:-250px;top:100px;width:230px"><div style="color:#ffedc2;font-weight:500;margin-bottom:3px">Azeroth Guild Finder</div>'
             '<div>Left click: open or close</div><div>Right click: settings</div><div style="color:#f2bf3c">3 pending applications</div></div>')
    return (f'<div class="minimap"><div class="mm-btn" style="left:-8px;top:110px"><div class="in">{emb(BRAND)}</div></div>{t}</div>')


def fab(n=3, x=760, y=250):
    b = f'<span class="badge">{n}</span>' if n else ""
    return f'<div class="fab" style="left:{x}px;top:{y}px"><div class="in">{emb(AUR)}</div>{b}</div>'


def quick_item(c, name, line, when):
    return (f'<div class="qi">{cl(c)}<div class="who"><b style="color:{CLASS_TEXT[c]}">{name}</b><span class="caption">{line} · {when}</span></div>{btn("Decline", "tonal", "sm")}{btn("Invite", "primary", "sm")}</div>')


def pop(inner, x=440, y=336):
    return (f'<div class="pop" style="left:{x}px;top:{y}px"><div style="display:flex;align-items:center;gap:8px;margin-bottom:10px"><span class="title-m" style="flex:1">Pending applications</span>'
            f'<span class="caption">Aurora</span>{ms("close", "font-size:18px;color:var(--ink-2)")}</div>{inner}</div>')


@scene("notification-icon", "The notification icon: a round button with the number of pending applications, plus one chat line with an Open link")
def _():
    return world(fab())


@scene("notification-icon-tooltip", "The notification icon's tooltip: how many applications are pending, and what the clicks do")
def _():
    tip = ('<div class="tooltip" style="left:640px;top:330px;width:230px"><div style="color:#ffedc2;font-weight:500;margin-bottom:3px">Guild Finder applications</div><div>3 pending</div>'
           '<div style="color:#bfb19a">Left click: the last applications</div><div style="color:#bfb19a">Right click: options. Drag to move.</div></div>')
    return world(fab() + tip)


@scene("notification-quick-list", "Left click on the notification icon: the last pending applications with Invite and Decline, and Open all applications")
def _():
    items = quick_item("mage", "Elarin", "Mage 32", "2 h ago") + quick_item("priest", "Mirelle", "Priest 60", "yesterday") + quick_item("warrior", "Brogan", "Warrior 17", "3 days ago")
    return world(fab() + pop(items + f'<div style="text-align:right;margin-top:4px">{btn("Open all applications", "ghost", "md", "arrow_forward")}</div>'))


@scene("notification-quick-list-more", "The quick list shows five applications at most and says how many more are waiting")
def _():
    items = quick_item("mage", "Elarin", "Mage 32", "2 h ago") + quick_item("priest", "Mirelle", "Priest 60", "yesterday") + quick_item("warrior", "Brogan", "Warrior 17", "3 days ago")
    return world(fab(8) + pop(items + '<div class="caption" style="margin:2px 8px 6px">and 5 more</div>' + f'<div style="text-align:right">{btn("Open all applications", "ghost", "md", "arrow_forward")}</div>', 440, 300))


@scene("notification-quick-list-empty", "The quick list with nothing pending")
def _():
    return world(fab(0) + pop('<div class="body-m muted" style="text-align:center;padding:18px 0 8px">No pending applications.</div>' + f'<div style="text-align:right">{btn("Open all applications", "ghost", "md", "arrow_forward")}</div>'))


@scene("notification-decline-confirm", "Declining from the quick list asks first: Decline or Keep")
def _():
    items = quick_item("mage", "Elarin", "Mage 32", "2 h ago")
    ask = (f'<div class="body-m" style="margin:6px 4px 10px"><b>Decline Elarin?</b></div><div style="display:flex;justify-content:flex-end;gap:8px">{btn("Keep", "tonal", "sm")}{btn("Decline", "primary", "sm")}</div>')
    return world(fab(1) + pop(items.split('<span class="btn')[0] + "</div>" + ask))


@scene("notification-icon-menu", "Right click on the notification icon: lock position, show only when something is pending, sound, hide")
def _():
    menu = ('<div class="menu" style="left:860px;top:150px"><div class="t">Applications icon</div>'
            f'<div>{ms("lock")}Lock position</div><div>{ms("check", "color:transparent")}Show only when something is pending</div><div>{ms("volume_up")}Sound on new application</div>'
            f'<div class="hr"></div><div>{ms("visibility_off")}Hide icon</div></div>')
    return world(fab() + menu)


@scene("minimap-button", "The minimap button with its tooltip: left click opens Guild Finder, right click opens Settings")
def _():
    return world("", "dusk:12").replace('<div class="minimap">', '<div class="minimap">', 1).replace(minimap(), minimap(True))


@scene("chat-commands", "The slash commands in the chat window: /gf help, /gf scale, /gf notify and /gf reset")
def _():
    lines = [("/gf help", None), ("[Guild Finder] Commands:", "#ffd27a"), ("  /gf: open or close Guild Finder", "#e9e2d4"), ("  /gf notify: show or hide the applications notification icon", "#e9e2d4"),
             ("  /gf reset: reset the window position", "#e9e2d4"), ("  /gf scale: show or set the window size: /gf scale 60 to 140", "#e9e2d4"),
             ("  /gf debug: diagnostics report to copy into a bug report ('/gf debug ping' tests the channel)", "#e9e2d4"), ("  /gf help: show this list", "#e9e2d4"),
             ("/gf scale 80", None), ("[Guild Finder] Window size set to 80%.", "#ffd27a"), ("/gf notify", None), ("[Guild Finder] Notification icon hidden. Type /gf notify to show it again.", "#ffd27a"),
             ("/gf reset", None), ("[Guild Finder] Window position reset.", "#ffd27a"), ("/gf debug ping", None), ("[Guild Finder] Ping sent on the channel, collecting answers for 5 seconds...", "#ffd27a"),
             ("[Guild Finder] 4 peer(s) answered. Round trip: shortest 120 ms, average 210 ms, longest 340 ms.", "#ffd27a")]
    html = "".join(f'<div style="color:{c or "#fff"}">{t if c else "<b>&gt; " + t + "</b>"}</div>' for t, c in lines)
    return (f'<div class="world" data-art="storm:6"></div><div class="chat" style="left:40px;bottom:60px;top:40px;width:900px;font-size:15px;line-height:24px;padding:16px 20px;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end">{html}</div>')


@scene("diagnostics-box", "/gf debug: the diagnostics report in a box, Select all and Ctrl+C to copy it into a bug report (no player or guild names)")
def _():
    rep = """Azeroth Guild Finder diagnostics
addon: 0.1.0
client: 1.15.7 (build 63000)
interface: 16001
project id: 5 (WoW Forever)
locale: enUS

== Listen-only ==
listen-only: no
== Last errors ==
no addon errors recorded this session
== Compat ==
C_AddOns.GetAddOnMetadata: available
C_ChatInfo.SendAddonMessage: available
C_Timer.After: available
== Role ==
Role: none, in a guild: no
== Catalog ==
guilds known: 142, last sync: 2 min ago
== Channel ==
joined: yes, peers heard: 4"""
    box = (f'<div class="modal" style="width:640px;padding:20px 20px 18px;background:#f3e2bd"><div class="title-l">Diagnostics</div>'
           f'<div class="caption" style="margin:4px 0 10px">Press Ctrl+C to copy the report, then paste it into the bug report. It holds no player or guild names.</div>'
           f'<div class="field sq" style="height:auto;align-items:flex-start;padding:10px 12px;display:block;background:#fff4dd"><pre class="mono" style="margin:0;font-size:12px;line-height:17px;white-space:pre-wrap;color:var(--ink)">{rep}</pre></div>'
           f'<div style="display:flex;justify-content:flex-end;gap:10px;margin-top:14px">{btn("Close", "tonal", "md")}{btn("Select all", "primary", "md")}</div></div>')
    return f'<div class="world" data-art="frost:31"></div>{dim(box)}'


# ======================================================================================================================
# Settings
# ======================================================================================================================
def slider(label, value, pct):
    return (f'<div class="field-label">{label}</div><div style="display:flex;align-items:center;gap:12px"><div style="flex:1;height:10px;border-radius:5px;background:linear-gradient(90deg,#7a4a22 0 {pct}%,#d9c19a {pct}%);box-shadow:inset 0 0 0 1.5px #6a4526;position:relative">'
            f'<span style="position:absolute;left:{pct}%;top:-6px;width:22px;height:22px;margin-left:-11px;border-radius:50%;background:radial-gradient(circle at 35% 30%,#ffe28a,#f2bf3c 55%,#b8820f);box-shadow:0 0 0 2px #3a2a10"></span></div><span class="title-s mono" style="width:56px">{value}</span></div>')


def settings(role_key, notif=False):
    win = card(h3("web_asset", "Window") + '<div class="caption" style="margin-bottom:10px">The window can be dragged by its left page and its title bar. Its size and place are remembered.</div>' +
               slider("Window size", "100%", 50) + '<div class="field-help" style="margin-bottom:10px">Also: /gf scale 60 to 140. On a small screen the window is reduced to fit.</div>' +
               opt("Show minimap button", True, "The round button on the minimap: left click opens Guild Finder, right click opens these settings.") +
               f'<div style="margin-top:10px">{btn("Reset window position", "tonal", "sm", "restart_alt")}</div>')
    priv = card(h3("shield", "Privacy") + opt("Share anonymous alt count with my guild", True, "Tells your guild only how many of your characters played this week, never which ones. Guild Finder uses it to estimate how many different players are active."))
    nt = card(h3("notifications", "Notifications") + '<div class="caption" style="margin-bottom:8px">For the Guild Master and the officers: how the game tells you about new applications.</div>' +
              opt("Notification icon on screen", True, "A round button with the number of pending applications. Only the Guild Master and the officers of a listed guild see it.") +
              opt("Only when something is pending", False, "Hides the notification icon while there is no pending application.") + opt("Sound on new application", True, "Plays a short sound when an application arrives.")) if notif else ""
    lh = left(f'{brand()}<div style="flex:1"></div><div class="caption">A change takes effect at once and is saved: there is no Apply button.</div>')
    rh = right("Settings", f'<div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;align-items:start"><div style="display:flex;flex-direction:column;gap:14px">{win}</div><div style="display:flex;flex-direction:column;gap:14px">{priv}{nt}</div></div>')
    return window(lh, rh, role_key, "Settings")


@scene("settings", "Settings for a player without a guild: window size and position, minimap button, privacy")
def _():
    return settings("none")


@scene("settings-officer", "Settings for the Guild Master and the officers: the same, plus the Notifications card")
def _():
    return settings("officer", True)


@scene("settings-reset-done", "Settings after Reset window position: a note confirms it")
def _():
    return settings("none") + snack("Window position reset.")
