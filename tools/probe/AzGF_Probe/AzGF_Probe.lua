-- AzGF Probe: throwaway spike addon for Azeroth Guild Finder (milestone M0). Never distributed.
-- Answers checks S1-S11 (docs/specs/SPEC-09-quality-release.md, section 1) in the real client.
-- Lua 5.1. Every game API call goes through pcall. Never print or store player or guild names: use placeholders.

local ADDON_NAME = ...

-- The REAL channel is "AzGuildFinder": this probe must NEVER join it or send to it (a joined channel may stay in the
-- player's list). Later steps (M0.3+) use only the test channel below.
local TEST_CHANNEL = "AzGFProbe"
local REAL_CHANNEL = "AzGuildFinder" -- only used to refuse it, see Probe:AssertTestChannel

-- exportTexts[name] = function() return text end: extra texts for "/agfp export <name>" (M0.5: tabard, gallery)
local Probe = { checks = {}, order = {}, commands = {}, exportHooks = {}, exportTexts = {}, TEST_CHANNEL = TEST_CHANNEL }
_G.AzGF_Probe = Probe

local PREFIX = "|cff66ccffAzGF Probe:|r "
local RESULTS = { pass = true, fail = true, info = true, todo = true }

local function out(msg)
    print(PREFIX .. tostring(msg))
end
Probe.Print = out

--- Safe call of a game API: returns ok, ...results (never raises). Use this for every game API call.
function Probe.Call(fn, ...)
    if type(fn) ~= "function" then
        return false, "API missing"
    end
    return pcall(fn, ...)
end

--- Refuses the real channel. Call it with any channel name before joining or sending.
function Probe:AssertTestChannel(name)
    if name == REAL_CHANNEL then
        error("the probe must never use the real channel " .. REAL_CHANNEL)
    end
    return name
end

local function db()
    AzGF_ProbeDB = AzGF_ProbeDB or {}
    AzGF_ProbeDB.results = AzGF_ProbeDB.results or {}
    return AzGF_ProbeDB
end

local function buildString()
    local ok, version, build = pcall(GetBuildInfo)
    if ok then
        return tostring(version) .. "." .. tostring(build)
    end
    return "unknown"
end

--- Registers a check. fn(probe) returns result ("pass"|"fail"|"info"|"todo"), details (string).
function Probe:Register(id, description, fn)
    assert(type(id) == "string" and type(fn) == "function", "Register(id, description, fn)")
    if not self.checks[id] then
        self.order[#self.order + 1] = id
    end
    self.checks[id] = { id = id, description = description, fn = fn }
end

--- Stores a result in AzGF_ProbeDB.results[id].
function Probe:Record(id, result, details)
    if not RESULTS[result] then
        result = "info"
    end
    local entry = {
        id = id,
        result = result,
        details = tostring(details or ""),
        build = buildString(),
        time = date("%Y-%m-%d %H:%M:%S"),
    }
    db().results[id] = entry
    return entry
end

--- Runs one check inside pcall and stores its result.
function Probe:Run(id)
    local check = self.checks[id]
    if not check then
        out("unknown check '" .. tostring(id) .. "' (try /agfp list)")
        return
    end
    local ok, result, details = pcall(check.fn, self)
    if not ok then
        result, details = "fail", "error: " .. tostring(result)
    end
    local entry = self:Record(id, result, details)
    out(string.format("%s [%s] %s", id, entry.result, entry.details))
    return entry
end

function Probe:List()
    for _, id in ipairs(self.order) do
        local check, last = self.checks[id], db().results[id]
        out(string.format("%s - %s - %s", id, check.description,
            last and (last.result .. ": " .. last.details) or "no result"))
    end
end

function Probe:ExportText()
    local lines = { "AzGF Probe results (build " .. buildString() .. ")" }
    for _, id in ipairs(self.order) do
        local r = db().results[id]
        if r then
            lines[#lines + 1] = string.format("%s | %s | %s | build %s | %s", id, r.result, r.details, r.build, r.time)
        else
            lines[#lines + 1] = id .. " | no result"
        end
    end
    if self.SnapshotLines then
        for _, l in ipairs(self:SnapshotLines()) do
            lines[#lines + 1] = l
        end
    end
    -- extra sections added by the check files (Probe.exportHooks[name] = function() return { lines } end)
    for _, hook in ipairs(self.exportHooks) do
        local ok, extra = pcall(hook, self)
        if ok and type(extra) == "table" then
            for _, l in ipairs(extra) do
                lines[#lines + 1] = l
            end
        end
    end
    return table.concat(lines, "\n")
end

function Probe:Reset()
    db().results = {}
    db().snapshots = nil
    db().channel = nil
    db().whisper = nil
    db().tabard = nil
    db().textures = nil
    out("results cleared")
end

local exportFrame
--- Opens the export frame with the results, or with `text` when given (a string).
function Probe:Export(text)
    if not exportFrame then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local f = CreateFrame("Frame", "AzGF_ProbeExportFrame", UIParent, template)
        f:SetSize(560, 340)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 8, right = 8, top = 8, bottom = 8 },
            })
        end
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -14)
        title:SetText("AzGF Probe export (Ctrl+C to copy, drag to move)")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        local scroll = CreateFrame("ScrollFrame", "AzGF_ProbeExportScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -40)
        scroll:SetPoint("BOTTOMRIGHT", -36, 18)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(500)
        pcall(edit.SetMaxLetters, edit, 0) -- 0 = no limit: the tabard catalogue is long
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        exportFrame = f
    end
    exportFrame.edit:SetText(text or self:ExportText())
    exportFrame:Show()
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
end

-- Checks S1-S11: stubs in M0.1; M0.2-M0.6 replace them by calling Probe:Register with the same id
-- (S1, S7, S11 live in Checks_Environment.lua and S2, S3, S6 in Checks_Channel.lua, S4, S5 in Checks_Whisper.lua, S8 in
-- Checks_Tabard.lua and S9 in Checks_Textures.lua and S10 in Checks_Invite.lua, loaded after this file;
-- those files also add slash commands with Probe.commands[name] = function(arg, rest)).
local STUBS = {
    { "S2", "Join the test channel and exchange addon messages between two clients" },
    { "S3", "Lowest level (or play time) that can send in the channel" },
    { "S4", "Addon WHISPER to a non-friend, also from a low-level character" },
    { "S5", "OFFICER as an addon channel" },
    { "S6", "Real channel throttle (messages per second before throttling)" },
    { "S8", "Tabard info and TabardModel CycleVariation catalogue" },
    { "S9", "Texture gallery: banners, parchment, class and role icons" },
}
for _, stub in ipairs(STUBS) do
    Probe:Register(stub[1], stub[2], function()
        return "todo", "not implemented yet"
    end)
end

local USAGE = "/agfp [list] | run <id> | snapshot <label> | join | leave | ping | pong | burst <n> <gap> | channel | whisper <name> | officer | guild | invite <name> | invite-timer <name> | tabard [slow|stop|status|info] | gallery | tex <path|fileID|atlas:name> | mark <n> ok|bad|clear | export [tabard|gallery] | reset"

SLASH_AZGFPROBE1 = "/agfp"
SlashCmdList["AZGFPROBE"] = function(msg)
    local cmd, arg, rest = (msg or ""):match("^%s*(%S*)%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "list" then
        Probe:List()
    elseif cmd == "run" and arg ~= "" then
        Probe:Run(arg:upper())
    elseif cmd == "snapshot" then
        if Probe.Snapshot then
            local label = (arg .. " " .. rest):gsub("^%s+", ""):gsub("%s+$", "")
            out("snapshot: " .. Probe:Snapshot(label))
        end
    elseif cmd == "export" then
        local textFn = Probe.exportTexts[arg:lower()]
        if arg ~= "" and not textFn then
            out("unknown export '" .. arg .. "' (available: tabard, gallery; or plain /agfp export)")
        elseif textFn then
            local ok, text = pcall(textFn)
            Probe:Export(ok and text or ("export error: " .. tostring(text)))
        else
            Probe:Export()
        end
    elseif cmd == "reset" then
        Probe:Reset()
    elseif Probe.commands[cmd] then
        local ok, err = pcall(Probe.commands[cmd], arg, rest)
        if not ok then
            out("error in /agfp " .. cmd .. ": " .. tostring(err))
        end
    else
        out(USAGE)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, name)
    if name == ADDON_NAME then
        db()
        out("loaded (development only). " .. USAGE)
    end
end)
