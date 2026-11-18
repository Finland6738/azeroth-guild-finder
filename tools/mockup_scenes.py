"""Every case of the interface as a design preview (see tools/make_mockups.py), part 1: Find a Guild, the guild page,
applying and My Application. One function per image, registered with @scene(file name, caption). A scene returns the
HTML that goes inside the 1280x820 stage."""
from mockup_lib import *  # noqa: F401,F403

SCENES = []


def scene(name, caption):
    def deco(fn):
        SCENES.append((name, caption, fn))
        return fn
    return deco


def dim(inner):
    return f'<div class="dim">{inner}</div>'


def snack(text, extra=""):
    return f'<div class="snack">{text}{extra}</div>'


# ======================================================================================================================
# Find a Guild
# ======================================================================================================================
def browse_left(active=0, recruiting=False, myclass=False, reqs=False, newb=False, roles=(), lang=None, paces=(),
                activity=None, day_on=(), t_from=None, t_to=None, min_active=None, open_menu=""):
    head = "Filters" if not active else f'Filters <span style="opacity:.75;font-weight:500">· {active} active</span>'
    rl = [("t", "Tank"), ("h", "Healer"), ("m", "Melee"), ("r", "Ranged")]
    roles_html = "".join(f'<span class="chip {"on" if k in roles else ""}">{role(k)}{n}</span>' for k, n in rl)
    tf = field(t_from or "Any", select=True, sq=True, style="width:112px;height:34px", muted=not t_from)
    tt = field(t_to or "Any", select=True, sq=True, style="width:112px;height:34px", muted=not t_to)
    return left(f'''{brand()}
      <div class="plate"><span>{head}</span>{ms("restart_alt")}</div>
      <div>{opt("Recruiting only", recruiting)}{opt('Looking for my class <span class="caption">(Mage)</span>', myclass)}{opt("Requirements met", reqs)}{opt("New player friendly", newb)}</div>
      <div><div class="field-label">My role</div><div class="chips">{roles_html}</div></div>
      <div style="position:relative"><div class="field-label">Guild language</div>{field(lang or "Any language", "translate", True, muted=not lang)}{open_menu}</div>
      <div><div class="field-label">Commitment</div>{chips(["Casual", "Softcore", "Hardcore"], on=paces)}</div>
      <div><div class="field-label">Activity</div>{field(activity or "Any activity", "castle", True, muted=not activity)}</div>
      <div><div class="field-label">Play days &amp; time <span class="caption">(your time)</span></div>{days(day_on)}
        <div style="display:flex;gap:10px;align-items:center;margin-top:10px">{tf}<span class="muted">–</span>{tt}</div></div>
      <div class="opt" style="margin-top:2px"><span>Min. active members</span>{field(min_active or "Any", select=True, sq=True, style="width:76px;height:32px", muted=not min_active)}</div>''')


def three_cards(first_hover=True):
    apply_ = btn("Apply", "primary")
    discord = btn("Discord", "discord", "sm", "forum")
    c1 = gcard("Aurora", "Open recruitment · small-scale PvP and a relaxed raid night on Wednesdays", AUR, ("emerald", 3),
               tag("IT") + tag("EN") + pace("soft") + tag("Looking for your class", "ok", "check_circle"), discord + apply_,
               info_cells(31, 149, 'Mon–Fri <span class="mono">20:00–23:30</span>', looking(["priest", "shaman", "warrior", "mage"], 1),
                          "World PvP · Raids · Battlegrounds", "Level 20+", "Updated 2 days ago"), hover=first_hover)
    c2 = gcard("Ordine Cremisi", "Italian raiding guild. Calm evenings, no drama, loot council.", CRIM, ("ember", 11),
               tag("IT") + pace("casual") + tag("Looking for your class", "ok", "check_circle"), discord + apply_,
               info_cells(18, 62, 'Wed, Sat, Sun <span class="mono">21:00–00:00</span>', looking(["mage", "warlock", "druid"]),
                          "Raids · Dungeons · Social &amp; Chat", "Level 25+", "Updated today"))
    c3 = gcard("Ordine del Drago", "Hardcore progression. Voice chat required on raid nights.", DRAG, ("frost", 5),
               tag("IT") + pace("hard") + tag("Requirements not met", "bad", "cancel"), discord + btn("Apply", "disabled"),
               info_cells(44, 98, 'Every day <span class="mono">21:00–01:00</span>', looking(["mage", "priest"]),
                          "Raids · Dungeons", "Level 40+ (you are 32)", "Updated 5 days ago", req_bad=True))
    return c1 + c2 + c3


def browse_right(list_html, count="142 guilds", query=None, status=("142 guilds known · synced 2 min ago", "ok"), hint=None):
    q = (f'<span>{query}</span><span class="grow"></span>{ms("close", "font-size:18px")}' if query else '<span class="ph-t">Search guild name...</span>')
    hdr = (f'<div class="field" style="width:360px">{ms("search")}{q}</div><div class="grow"></div><div style="text-align:right">'
           f'<div class="title-s">{count}</div><div class="caption">{ms("sort_by_alpha", "font-size:15px")} Sorted A-Z</div></div>')
    hint_html = f'<div class="caption" style="margin:-6px 0 8px 14px;color:var(--bad)">{hint}</div>' if hint else ""
    st = (f'<div class="statusbar"><span class="dot {"" if status[1] == "ok" else "off"}"></span>{status[0]}<span style="flex:1"></span>'
          f'{ms("info", "color:var(--ink-3)", "o")}Only guilds of your faction and realm</div>')
    return (f'<div class="page page-right"><div class="ph" style="gap:14px">{hdr}</div>{hint_html}'
            f'<div class="content">{list_html}<div class="scroll"></div></div>{st}</div>')


def find(left_html, right_html):
    return window(left_html, right_html, "none", "FindGuild")


@scene("find-a-guild-list", "Find a Guild: the guilds of your realm and faction, A-Z, with the filters on the left page")
def _():
    return find(browse_left(), browse_right(three_cards(), "142 guilds"))


@scene("find-a-guild-filters", "Find a Guild: filters on (Recruiting, Looking for my class, Ranged DPS, Italian, Raids, weekend evenings)")
def _():
    lf = browse_left(8, True, True, False, False, ("r",), "Italian, English", ("Softcore",), "Raids, Battlegrounds", (5, 6), "20:00", "23:30", "10")
    return find(lf, browse_right(three_cards(), "3 of 142 guilds"))


@scene("find-a-guild-language-menu", "Find a Guild: the language filter lets you tick several languages")
def _():
    items = [("English", True), ("German", False), ("French", False), ("Spanish", False), ("Italian", True), ("Portuguese", False),
             ("Russian", False), ("Polish", False), ("Other", False)]
    menu = '<div class="dropdown">' + "".join(f'<div class="di"><span class="cb {"on" if on else ""}"></span>{n}</div>' for n, on in items) + "</div>"
    return find(browse_left(1, lang="2 selected", open_menu=menu), browse_right(three_cards(False), "142 guilds"))


@scene("find-a-guild-search", "Find a Guild: searching by guild name (three letters or more); the count says how many of the whole list match")
def _():
    return find(browse_left(), browse_right(three_cards(), "3 of 142 guilds", query="ord"))


@scene("find-a-guild-search-short", "Find a Guild: the search waits for at least three letters")
def _():
    return find(browse_left(), browse_right(three_cards(False), "142 guilds", query="or", hint="Type at least 3 letters"))


def _centered(icon, text):
    return f'<div class="empty">{ms(icon, "font-size:46px;color:#8a5a2a;opacity:.8")}<div class="body-m muted" style="max-width:380px">{text}</div></div>'


@scene("find-a-guild-loading", "Find a Guild: first start, looking for guilds (the first sync can take a minute)")
def _():
    return find(browse_left(), browse_right(_centered("progress_activity", "Looking for guilds... this can take a minute the first time"),
                                            "0 guilds", status=("0 guilds known · syncing...", "off")))


@scene("find-a-guild-no-peers", "Find a Guild: nobody else with the addon is online right now")
def _():
    return find(browse_left(), browse_right(_centered("wifi_off", "No other Guild Finder users online right now. Listings will appear as they come online."),
                                            "0 guilds", status=("0 guilds known · not synced yet", "off")))


@scene("find-a-guild-empty", "Find a Guild: connected, but no guild has published a listing for your realm and faction yet")
def _():
    return find(browse_left(), browse_right(_centered("travel_explore", "No guild has published a listing for your realm and faction yet. Listings appear here as soon as one does."),
                                            "0 guilds", status=("0 guilds known · synced just now", "ok")))


@scene("find-a-guild-no-match-filters", "Find a Guild: no guild matches the filters, with a button to reset them")
def _():
    body = f'<div class="empty">{ms("filter_alt_off", "font-size:46px;color:#8a5a2a;opacity:.8")}<div class="title-m">No guild matches your filters</div>{btn("Reset filters", "tonal", "md", "restart_alt")}</div>'
    return find(browse_left(5, True, True, True, True, ("t",), None, ("Hardcore",), None), browse_right(body, "0 of 142 guilds"))


@scene("find-a-guild-no-match-query", "Find a Guild: no guild name contains the search text")
def _():
    body = f'<div class="empty">{ms("search_off", "font-size:46px;color:#8a5a2a;opacity:.8")}<div class="title-m">No guild name contains "zzq"</div></div>'
    return find(browse_left(), browse_right(body, "0 of 142 guilds", query="zzq"))


@scene("find-a-guild-apply-states", "The Apply button on a guild card in each case, with the reason shown when it is disabled")
def _():
    rows = [
        ("Can apply", btn("Apply", "primary"), "You are not in a guild, the requirements are met and nothing else is open."),
        ("Requirements not met", btn("Apply", "disabled"), '<span style="color:var(--bad)"><b>Requirements not met: level 40</b></span> (and/or item level)'),
        ("Application open here", btn("Applied · Waiting for an officer", "tonal"), "Click to see your application in the My Application tab."),
        ("Received by the guild", btn("Applied · Received", "tonal"), "An officer's addon answered: the application reached the guild."),
        ("Open somewhere else", btn("Apply", "disabled"), "<b>You already applied to Ordine Cremisi.</b> Withdraw it first: one open application at a time."),
        ("Declined recently", btn("Apply", "disabled"), "<b>You can apply again on 24 Nov.</b> A guild that declines you can be tried again after 7 days."),
        ("Already in a guild", btn("Apply", "disabled"), "<b>You are already in a guild.</b> Only characters without a guild can apply."),
        ("Cannot send addon messages", btn("Apply", "disabled"), "<b>Your character can't send addon messages yet.</b> Use the guild's contacts meanwhile."),
        ("Saved data is newer", btn("Apply", "disabled"), "<b>Saved data is read-only.</b> Update the addon to apply."),
    ]
    out = "".join(f'<div class="app" style="margin-bottom:9px;padding:10px 14px"><div style="width:220px"><b>{a}</b></div><div style="width:270px;flex:none">{b}</div><div class="caption" style="flex:1;font-size:12.5px;line-height:17px">{c}</div></div>' for a, b, c in rows)
    lf = left(f'{brand()}<div class="plate"><span>Apply button</span>{ms("how_to_reg")}</div><div class="caption">The button of every guild card and of the guild page. A grey button always says why.</div>')
    return window(lf, right("Apply button states", out), "none", "FindGuild")


# ======================================================================================================================
# Guild page
# ======================================================================================================================
def lf_card(state="some", you="They need your class: Mage · Ranged DPS", classes=None):
    classes = classes or [("priest", "h"), ("shaman", "h"), ("warrior", "t"), ("mage", "r"), ("druid", "tmh")]
    head = {"some": tag("Recruiting: selected classes only", "ok"), "all": tag("Recruiting", "ok"), "closed": tag("Recruiting closed", "bad")}[state]
    youtag = f'<span class="tag ok" style="margin-left:auto">{ms("check_circle", "font-size:14px")}{you}</span>' if you else ""
    if state == "closed":
        grid = '<div class="body-m muted" style="margin-top:4px">Applications via addon are closed. Use the contacts below.</div>'
    elif state == "all":
        grid = (f'<div class="lf-grid"><div class="lf-item">{ms("groups", "font-size:30px;color:#b8820f")}<div><b>Any class</b>'
                f'<div class="roles">{role("t")}{role("h")}{role("m")}{role("r")}</div></div></div></div>')
    else:
        items = "".join(f'<div class="lf-item">{cl(c, "lg")}<div><b>{CLASS_NAMES[c]}</b><div class="roles">{"".join(role({"t": "t", "h": "h", "m": "m", "r": "r"}[r]) for r in rs)}</div></div></div>' for c, rs in classes)
        grid = (f'<div class="lf-grid">{items}</div><div class="caption" style="display:flex;gap:14px;margin-top:8px;align-items:center">'
                f'<span>{role("t")} Tank</span><span>{role("h")} Healer</span><span>{role("m")} Melee DPS</span><span>{role("r")} Ranged DPS</span></div>')
    return f'<div class="card gold lf"><h3>{ms("person_search", "color:#b8820f")}Looking for {head}{youtag}</h3>{grid}</div>'


def guild_right(lf, req_lines, loading=None):
    if loading:
        return f'{art("emerald", 3, "banner")}{lf}<div class="empty" style="margin-top:20px">{loading}</div>'
    stats = (f'<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px 12px"><div class="stat"><div class="n">31</div><div class="l">Active characters · 7 days</div></div>'
             f'<div class="stat"><div class="n">19–24</div><div class="l">Unique players · 7 days {ms("info", "font-size:14px", "o")}</div></div>'
             f'<div class="stat"><div class="n sm">149</div><div class="l">Total members</div></div><div class="stat"><div class="n sm">12</div><div class="l">At max level</div></div></div>'
             + classbar([("warrior", 18), ("priest", 11), ("mage", 14), ("hunter", 9), ("rogue", 13), ("shaman", 10), ("druid", 15), ("paladin", 10)])
             + '<div class="caption" style="margin-top:6px">Class mix of active characters</div>')
    about = card(h3("auto_stories", "About") + '<div class="body-m">Competitive guild focused on small-scale PvP, with a relaxed raid night on Wednesdays. We help new players gear up and level. Italian first, English welcome.</div>')
    act = card(h3("event", "Activity") + f'<div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">{pace("soft")}<span class="caption">Regular activities and some scheduled events</span></div>'
               '<div class="chips" style="margin-bottom:10px"><span class="chip"><span class="num">1</span>World PvP</span><span class="chip"><span class="num">2</span>Raids</span><span class="chip"><span class="num">3</span>Battlegrounds</span></div>'
               + days((0, 1, 2, 3, 4)) + '<div style="margin-top:10px"><span class="mono title-m">20:00 – 23:30</span> <span class="caption">your time</span> · <span class="mono caption">19:00 – 22:30 UTC</span></div>')
    how = card('<div style="display:flex;align-items:center;gap:18px">' + ms("help", "font-size:28px;color:#8a5a2a") +
               '<div style="flex:1"><div class="title-s">How applying works</div><div class="caption">1. Apply sends your character, class and level · 2. Officers are notified in game · 3. If accepted you get the normal guild invite. One open application at a time, it expires after 14 days.</div></div></div>', style="margin-top:14px")
    return (f'{art("emerald", 3, "banner")}{lf}<div class="cols"><div class="stack">{about}{act}</div><div class="stack">'
            f'{card(h3("groups", "Members", chr(60) + "span class=caption style=margin-left:auto>updated 3 h ago</span>") + stats)}{card(h3("verified", "Requirements") + req_lines)}</div></div>{how}')


REQ_OK = (f'<div class="req">{ms("check_circle", "color:var(--ok)")}Level 20+ <span class="caption">(you are 32)</span></div>'
          f'<div class="req">{ms("remove", "color:var(--ink-3)", "o")}<span class="muted">No item level requirement</span></div>'
          f'<div class="req">{ms("sticky_note_2", "color:var(--ink-3)", "o")}<i class="muted">"Discord voice chat for raids"</i></div>')
REQ_BAD = (f'<div class="req" style="color:var(--bad)">{ms("cancel", "color:var(--bad)")}<b>Level 40+</b> <span class="caption">(you are 32)</span></div>'
           f'<div class="req" style="color:var(--bad)">{ms("cancel", "color:var(--bad)")}<b>Item level 60+</b> <span class="caption">(you have 48)</span></div>'
           f'<div class="req">{ms("sticky_note_2", "color:var(--ink-3)", "o")}<i class="muted">"Voice chat required on raid nights"</i></div>')


def apply_block(kind="ok"):
    big = lambda t, k: f'<span class="btn {k} lg" style="width:100%">{t}</span>'
    why = lambda t: f'<div class="caption" style="text-align:center;color:var(--bad)">{t}</div>'
    cap = lambda t: f'<div class="caption" style="text-align:center">{t}</div>'
    return {
        "ok": big("Apply to Aurora", "primary") + cap("One click: officers are notified in game. One open application at a time."),
        "unmet": big("Apply to Aurora", "disabled") + why("<b>Requirements not met: level 40, item level 60</b>"),
        "closed": card(cap("Applications via addon are closed. Use the contacts below."), style="padding:10px 12px"),
        "sent": big("Applied · Waiting for an officer", "tonal") + cap("Your application is open. Follow it in the My Application tab."),
        "elsewhere": big("Apply to Aurora", "disabled") + why("<b>You already applied to Ordine Cremisi</b><br>Withdraw it first: one open application at a time."),
    }[kind]


def guild_left(apply_html, discord=True, contacts=True):
    dc = (f'<div class="overline">Contact</div><div class="copy">{ms("forum", "color:var(--blue)")}<span class="grow"><span class="sel">https://discord.gg/aurora-it</span></span>{ms("content_copy", "color:var(--blue);font-size:18px")}</div>'
          '<div class="caption" style="margin-top:-6px">Selected. Press <b class="mono">Ctrl+C</b> to copy.</div>' if discord else
          '<div class="overline">Contact</div><div class="caption">No Discord link.</div>')
    ct = (f'<div class="contact"><span class="dot"></span><b>Lyryn</b><span style="flex:1"></span>{btn("Whisper", "tonal", "sm", "chat")}</div>'
          f'<div class="contact"><span class="dot off"></span><b>Kaelthar</b><span style="flex:1"></span>{btn("Whisper", "tonal", "sm", "chat")}</div>' if contacts else
          '<div class="caption">No contact characters listed.</div>')
    return left(f'''{btn("Back", "tonal", "sm", "arrow_back")}
      <div class="hero-emb">{emb(AUR, "width:100%;height:100%")}</div>
      <div><div class="gname">Aurora</div><div class="gsub">Open recruitment · small-scale PvP</div>
        <div style="display:flex;gap:6px;justify-content:center;margin-top:8px"><span class="tag">ITALIAN</span><span class="tag">ENGLISH</span><span class="tag" style="background:#5a1414;color:#ffd9a0">HORDE</span></div>
        <div style="display:flex;gap:6px;justify-content:center;margin-top:6px">{pace("soft")}</div></div>
      {apply_html}<div class="divider"></div>{dc}{ct}<div style="flex:1"></div>
      <div class="caption">Listed since <b>12 Oct 2026</b> · Updated <b>2 days ago</b></div>''', 10)


def guild_page(apply_kind="ok", lf=None, req=REQ_OK, loading=None, **left_kw):
    lh = guild_left(apply_block(apply_kind), **left_kw)
    rh = f'<div class="page page-right"><div class="content">{guild_right(lf or lf_card(), req, loading)}</div></div>'
    return window(lh, rh, "none", "FindGuild")


@scene("guild-page-recruiting", "Guild page of a recruiting guild: you meet the requirements and they need your class, so Apply is open")
def _():
    return guild_page("ok")


@scene("guild-page-requirements-unmet", "Guild page when you do not meet the requirements: Apply is disabled and says which ones")
def _():
    return guild_page("unmet", lf_card(you=None), REQ_BAD)


@scene("guild-page-not-recruiting", "Guild page of a guild that is not recruiting: no Apply button, only the contacts")
def _():
    return guild_page("closed", lf_card("closed", you=None))


@scene("guild-page-any-class", "Guild page of a guild that recruits any class")
def _():
    return guild_page("ok", lf_card("all", you="They need your class: Mage · any role"))


@scene("guild-page-no-contacts", "Guild page of a guild that listed neither a Discord link nor contact characters")
def _():
    return guild_page("ok", discord=False, contacts=False)


@scene("guild-page-applied", "Guild page after you applied: the button says Applied · Waiting for an officer and opens My Application")
def _():
    return guild_page("sent")


@scene("guild-page-apply-elsewhere", "Guild page while another application of yours is open: Apply is disabled until you withdraw it")
def _():
    return guild_page("elsewhere")


@scene("guild-page-loading-details", "Guild page while the description, activity and statistics are loading from other players")
def _():
    return guild_page("ok", loading=f'{ms("progress_activity", "font-size:40px;color:#8a5a2a")}<div class="body-m muted">Loading details...</div>')


@scene("guild-page-details-unavailable", "Guild page when nobody who has the details is online right now")
def _():
    return guild_page("ok", loading=f'{ms("cloud_off", "font-size:40px;color:#8a5a2a")}<div class="body-m muted">Details unavailable right now (no one who has them is online)</div>')


@scene("guild-page-listing-gone", "Guild page of a listing that was removed while you were looking at it")
def _():
    lh = left(btn("Back", "tonal", "sm", "arrow_back") + '<div style="flex:1"></div>')
    rh = right("", empty_state("", "This listing is no longer available. Go back to the list.", icon="block"), header=False)
    return window(lh, rh, "none", "FindGuild")


@scene("apply-confirmation", "Apply confirmation: your character, the roles you play (optional) and what is sent, then Apply")
def _():
    dlg = f'''<div class="modal" style="width:520px"><div class="title-m" style="margin-bottom:12px">Apply to Aurora with Elarin (Mage 32)?</div>
      <div class="field-label">Roles you play (optional)</div>
      <div class="chips" style="margin-bottom:6px"><span class="chip on">{role("r")}Ranged DPS</span></div>
      <div class="caption" style="margin-bottom:12px">Tick the roles you play, or none. Only the roles of your class are offered.</div>
      <div class="card" style="padding:10px 12px;margin-bottom:16px"><div class="caption">{ms("lock", "font-size:15px")} Sent automatically: name, class, race, level and item level. Only the Guild Master and the officers see it. No message, no form.</div></div>
      <div style="display:flex;justify-content:flex-end;gap:10px">{btn("Cancel", "tonal", "md")}{btn("Apply", "primary", "md")}</div></div>'''
    return guild_page("ok") + dim(dlg)


@scene("apply-saved", "After you press Apply: a note says it is saved and will be delivered when an officer is online")
def _():
    return guild_page("sent") + snack("Saved. It will be delivered when an officer of Aurora comes online.", f'<span class="btn ghost sm" style="color:var(--gold)">View</span>')


# ======================================================================================================================
# My Application
# ======================================================================================================================
MA = {
    "sent": ("schedule", "warn", "Waiting for an officer to come online", "Saved on this character. It will be delivered when an officer of Aurora comes online with Guild Finder. Stay online to let it go out.", 1, "open"),
    "received": ("mark_email_read", "ok", "Received by the guild", "An officer of Aurora has your application. If accepted you get the normal guild invite in game.", 2, "open"),
    "accepted": ("how_to_reg", "ok", "Accepted: check your guild invite", "Aurora accepted your application. Accept the guild invite when it appears.", 3, "closed"),
    "declined": ("cancel", "bad", "Declined", "Aurora declined your application. You can apply to other guilds now.", -3, "closed"),
    "joined": ("celebration", "ok", "Accepted: you joined", "You are a member of Aurora. Your application is closed.", 3, "closed"),
    "delisted": ("playlist_remove", "warn", "Guild removed from the list", "Aurora was removed from Guild Finder, so your application was closed. This is not a refusal: you can apply to other guilds now, and to this one again if it comes back.", 0, "closed"),
    "withdrawing": ("hourglass_top", "warn", "Withdrawing...", "Your withdrawal from Aurora reaches the guild when an officer comes online. You can already apply to another guild.", 0, "closed"),
    "withdrawn": ("undo", "off", "Withdrawn", "You withdrew your application to Aurora. You can apply to another guild.", 0, "closed"),
    "expired": ("timer_off", "off", "Expired", "Your application to Aurora expired after 14 days without a decision. You can apply again.", 0, "closed"),
    "cant_send": ("sync_problem", "bad", "Waiting for an officer to come online", "Right now the game does not let this character send addon messages, so nothing can go out yet. It stays saved and goes out by itself when sending works again; meanwhile the guild page lists the guild's contacts.", 1, "open"),
}
MA_COLORS = {"ok": ("var(--ok-bg)", "var(--ok)", "#2d4a22"), "bad": ("var(--bad-bg)", "var(--bad)", "#6a1a14"),
             "warn": ("#f8e9c0", "#8a5a0a", "#5a3d0a"), "off": ("rgba(255,244,222,.6)", "var(--ink-2)", "var(--ink-2)")}


def my_application(state, withdraw_confirm=False):
    icon, col, title, body, step, hint = MA[state]
    bg, fg, tx = MA_COLORS[col]
    steps = ""
    if state not in ("delisted", "withdrawing", "withdrawn", "expired"):
        last = {3: tag("ACCEPTED", "ok"), -3: tag("DECLINED", "bad")}.get(step, tag("ACCEPTED / DECLINED"))
        steps = (f'<div style="display:flex;gap:4px;margin-top:12px;align-items:center">{tag("SENT", "ok")}{ms("chevron_right", "font-size:16px")}'
                 f'{tag("RECEIVED", "ok" if step in (2, 3, -3) else "")}{ms("chevron_right", "font-size:16px")}{last}</div>')
    expires = '<div class="caption" style="margin-top:6px">Expires in 12 days without a decision.</div>' if hint == "open" else ""
    withdraw = btn("Withdraw", "tonal", "sm") if hint == "open" else ""
    conf = ""
    if withdraw_confirm:
        conf = card('<div class="body-m" style="margin-bottom:10px">Withdraw your application to Aurora? You can apply to another guild right away.</div>'
                    f'<div style="display:flex;gap:10px;justify-content:flex-end">{btn("Cancel", "tonal")}{btn("Withdraw", "primary")}</div>', "e", "margin-top:14px;max-width:440px")
    note = {"open": "Want another guild? Withdraw first: one open application at a time.",
            "closed": "This application is closed. You can apply to a guild in Find a Guild."}[hint]
    lh = left(f'{brand(BRAND, "Guild Finder", "Elarin · Mage 32")}<div style="flex:1"></div><div class="caption">{note}</div>')
    body_html = f'''<div style="display:flex;gap:14px;align-items:center">{emb(AUR, "width:64px;height:78px")}
        <div><div class="title-l">Aurora</div><div class="caption">Applied 2 h ago</div></div></div>
      <div class="card" style="margin-top:14px;background:{bg};box-shadow:inset 0 0 0 1.5px {fg}"><div class="title-s" style="color:{fg};display:flex;gap:8px;align-items:center">{ms(icon)}{title}</div>
        <div class="body-m" style="color:{tx};margin-top:4px">{body}</div>{expires}</div>{steps}
      <div class="caption" style="margin-top:12px">Roles: Ranged DPS</div>
      <div style="display:flex;gap:10px;margin-top:14px">{btn("View guild", "tonal", "sm")}{withdraw}</div>{conf}'''
    return window(lh, right("My Application", body_html, status=(title, "ok" if hint == "open" else "off")), "none", "MyApplication")


def _ma(name, state, cap, wc=False):
    scene(name, cap)(lambda: my_application(state, wc))


_ma("my-application-sent", "sent", "My Application: sent, saved on your character and waiting for an officer to come online")
_ma("my-application-received", "received", "My Application: an officer received it")
_ma("my-application-accepted", "accepted", "My Application: accepted, check your guild invite")
_ma("my-application-declined", "declined", "My Application: declined, you can apply elsewhere")
_ma("my-application-joined", "joined", "My Application: you joined the guild, the application closes as accepted")
_ma("my-application-delisted", "delisted", "My Application: the guild left Guild Finder, so the application was closed (not a refusal)")
_ma("my-application-withdrawing", "withdrawing", "My Application: withdrawing, the guild learns it when an officer is online")
_ma("my-application-withdrawn", "withdrawn", "My Application: withdrawn")
_ma("my-application-expired", "expired", "My Application: expired after 14 days without a decision")
_ma("my-application-cant-send", "cant_send", "My Application: this character cannot send addon messages yet, so the application stays saved")
_ma("my-application-withdraw-confirm", "received", "My Application: asking for confirmation before withdrawing", True)


@scene("my-application-empty", "My Application before you applied anywhere: it points you to Find a Guild")
def _():
    lh = left(f'{brand(BRAND, "Guild Finder", "Elarin · Mage 32")}<div style="flex:1"></div><div class="caption">One open application at a time. It expires after 14 days without a decision.</div>')
    body = empty_state("You haven't applied to any guild", "Open a guild in Find a Guild and press Apply. One click sends your character to its officers.",
                       icon="assignment_ind", button=btn("Find a Guild", "primary", "md", "travel_explore"))
    return window(lh, right("My Application", body, status=("You haven't applied to any guild", "off")), "none", "MyApplication")
