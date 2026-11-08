-- AzGF Probe, M0.6: C_GuildInfo.Invite from an addon button (S10).
-- Lua 5.1. Every game API call goes through pcall. The target name is NEVER stored: it is "<target>" everywhere (also in the
-- system messages that follow the call).

local Probe = _G.AzGF_Probe
if not Probe or not Probe.Channel then
    return
end

local C = Probe.Channel
local out = Probe.Print
local WINDOW = 5 -- seconds during which events after an attempt are attached to it

local function db()
    AzGF_ProbeDB = AzGF_ProbeDB or {}
    local d = AzGF_ProbeDB.invite
    if not d then
        d = {}
        AzGF_ProbeDB.invite = d
    end
    d.attempts = d.attempts or {}
    return d
end

local S = { target = nil, current = nil, frame = nil }

local function escape(s)
    return (s:gsub("(%W)", "%%%1"))
end

local function maskTarget(text, target)
    text = tostring(text)
    if target and target ~= "" then
        text = text:gsub(escape(target), "<target>")
        local short = target:match("^([^%-]+)")
        if short and short ~= target then
            text = text:gsub(escape(short), "<target>")
        end
    end
    return text
end

local function canInviteText()
    local parts = {}
    local ok, v = pcall(function()
        return C_GuildInfo and C_GuildInfo.CanGuildInvite and C_GuildInfo.CanGuildInvite()
    end)
    if ok and v ~= nil then
        parts[#parts + 1] = "C_GuildInfo.CanGuildInvite=" .. tostring(v)
    end
    local ok2, v2 = pcall(function()
        return CanGuildInvite and CanGuildInvite()
    end)
    if ok2 and v2 ~= nil then
        parts[#parts + 1] = "CanGuildInvite=" .. tostring(v2)
    end
    local ok3, g = pcall(IsInGuild)
    parts[#parts + 1] = "inGuild=" .. tostring(ok3 and g and true or false)
    return table.concat(parts, " ")
end

-- Event listener: attaches events to the attempt in progress ------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, name in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CHAT_MSG_SYSTEM", "UI_ERROR_MESSAGE" }) do
    pcall(ev.RegisterEvent, ev, name)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    local cur = S.current
    if not cur or C.getTime() > cur.untilTime then
        return
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if a1 == "AzGF_Probe" then
            cur.blocked[#cur.blocked + 1] = event .. ": " .. maskTarget(a2, S.target)
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        cur.system[#cur.system + 1] = maskTarget(a1, S.target)
    elseif event == "UI_ERROR_MESSAGE" then
        cur.system[#cur.system + 1] = "UI_ERROR: " .. maskTarget(a2, S.target)
    end
end)

local function attempt(path, target)
    local fn = C_GuildInfo and C_GuildInfo.Invite
    local entry = { time = C.now(), path = path, target = "<target>", blocked = {}, system = {}, can = canInviteText(),
        untilTime = C.getTime() + WINDOW }
    S.target = target
    S.current = entry
    if type(fn) ~= "function" then
        entry.ok, entry.err = false, "C_GuildInfo.Invite is not a function"
    else
        local ok, err = pcall(fn, target)
        entry.ok, entry.err = ok, ok and "" or maskTarget(err, target)
    end
    C.push(db().attempts, entry)
    out(string.format("invite via %s: pcall %s%s (listening %ds for blocked-action events and system messages)", path,
        entry.ok and "ok" or "ERROR", entry.ok and "" or (" - " .. tostring(entry.err)), WINDOW))
    C_Timer.After(WINDOW + 0.5, function()
        out(string.format("invite via %s: %d blocked event(s), %d system message(s); /agfp run S10 for the verdict", path,
            #entry.blocked, #entry.system))
        if S.current == entry then
            S.current = nil
            S.target = nil
        end
    end)
end

local function showFrame(target)
    local f = S.frame
    if not f then
        f = CreateFrame("Frame", "AzGFProbeInviteFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(260, 90)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        end
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -12)
        title:SetText("AzGF Probe: S10 guild invite")
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(200, 26)
        btn:SetPoint("CENTER", 0, -6)
        btn:SetScript("OnClick", function()
            attempt("button", f.target)
        end)
        f.button = btn
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        S.frame = f
    end
    f.target = target
    -- the real name is only on the button label (screen), never stored or printed
    f.button:SetText("Invite " .. target)
    f:Show()
end

Probe.commands.invite = function(arg)
    if not arg or arg == "" then
        out("usage: /agfp invite <character name> (the name is never stored: it is logged as <target>)")
        return
    end
    showFrame(arg)
    out("click the button in the small window: it calls C_GuildInfo.Invite (hardware event)")
end
Probe.commands["invite-timer"] = function(arg)
    if not arg or arg == "" then
        out("usage: /agfp invite-timer <character name> (calls Invite 1 s later from a timer, no hardware event)")
        return
    end
    out("calling C_GuildInfo.Invite from a timer in 1 s (no hardware event)")
    C_Timer.After(1, function()
        attempt("timer", arg)
    end)
end

-- Export ------------------------------------------------------------------------------------------------------------------------------
function Probe:InviteLines()
    local lines = {}
    for i, e in ipairs(db().attempts) do
        lines[#lines + 1] = string.format("S10 attempt %d | %s | via %s | target %s | pcall %s %s | %s | blocked: %s | system: %s", i,
            e.time, e.path, e.target, e.ok and "ok" or "ERROR", e.err or "", e.can or "",
            #e.blocked > 0 and table.concat(e.blocked, "; ") or "none",
            #e.system > 0 and table.concat(e.system, " / ") or "none")
    end
    return lines
end
table.insert(Probe.exportHooks, function(self)
    return self:InviteLines()
end)

-- Check -------------------------------------------------------------------------------------------------------------------------------
Probe:Register("S10", "C_GuildInfo.Invite from an addon button (/agfp invite <name>, /agfp invite-timer <name>)", function()
    local btn, timer = {}, {}
    for _, e in ipairs(db().attempts) do
        table.insert(e.path == "button" and btn or timer, e)
    end
    local function summary(t)
        local ok, blocked = 0, 0
        for _, e in ipairs(t) do
            if e.ok then
                ok = ok + 1
            end
            if #e.blocked > 0 then
                blocked = blocked + 1
            end
        end
        return string.format("%d attempts, pcall ok %d, with blocked-action events %d", #t, ok, blocked)
    end
    local text = string.format("button: %s; timer: %s; %s", summary(btn), summary(timer), canInviteText())
    if #btn == 0 then
        return "info", text .. "; no button attempt yet (/agfp invite <name> and click the button)"
    end
    local last = btn[#btn]
    if last.ok and #last.blocked == 0 then
        return "pass", text .. "; the button path ran without a blocked-action event (the system messages in /agfp export tell whether the invite was sent)"
    end
    return "fail", text .. "; button path blocked or errored: fallback is /ginvite <name> pre-filled in the chat box"
end)
