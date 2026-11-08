-- AzGF Probe, M0.2: environment checks S1 (Club Finder), S7 (guild APIs), S11 (chat lockdown snapshots).
-- Lua 5.1. Every game API call goes through pcall. Never record player, guild or realm names: only types, counts, shapes.

local Probe = _G.AzGF_Probe
if not Probe then
    return
end

local call = Probe.Call

local function db()
    AzGF_ProbeDB = AzGF_ProbeDB or {}
    return AzGF_ProbeDB
end

--- Describes a value without leaking text: strings become "string(<name>)" (or the placeholder given).
local function describe(v, placeholder)
    local t = type(v)
    if t == "string" then
        return placeholder or "string<name>"
    elseif t == "table" then
        local keys = {}
        for k, val in pairs(v) do
            keys[#keys + 1] = tostring(k) .. ":" .. type(val)
        end
        table.sort(keys)
        return "table{" .. table.concat(keys, ",") .. "}"
    elseif t == "nil" then
        return "nil"
    end
    return t .. "=" .. tostring(v)
end

--- Calls fn(...) safely and describes the results ("missing" when the API does not exist).
local function probeApi(label, fn, placeholder, ...)
    if type(fn) ~= "function" then
        return label .. ": missing"
    end
    local r = { call(fn, ...) }
    if not r[1] then
        return label .. ": error"
    end
    local parts = {}
    for i = 2, #r do
        parts[#parts + 1] = describe(r[i], placeholder)
    end
    if #parts == 0 then
        parts[1] = "no return"
    end
    return label .. ": " .. table.concat(parts, "/")
end

local function boolText(fn, ...)
    if type(fn) ~= "function" then
        return "missing"
    end
    local ok, v = call(fn, ...)
    if not ok then
        return "error"
    end
    return tostring(v)
end

-- S1 ---------------------------------------------------------------------------------------------------------------
Probe:Register("S1", "Club Finder enabled? (C_ClubFinder.IsEnabled / ShouldShowClubFinder / GetClubFinderDisableReason)",
    function()
        local cf = C_ClubFinder or {}
        local parts = {
            "IsEnabled=" .. boolText(cf.IsEnabled),
            "ShouldShowClubFinder=" .. boolText(cf.ShouldShowClubFinder),
            "GetClubFinderDisableReason=" .. boolText(cf.GetClubFinderDisableReason),
            "IsCommunityFinderEnabled=" .. boolText(cf.IsCommunityFinderEnabled),
            "C_ClubFinder=" .. (C_ClubFinder and "present" or "missing"),
        }
        return "info", table.concat(parts, "; ")
    end)

-- S7 ---------------------------------------------------------------------------------------------------------------
local function s7Sync()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    add(probeApi("GetGuildInfo(player)", GetGuildInfo, "string<guild/rank>", "player"))
    add("IsInGuild=" .. boolText(IsInGuild))
    add("IsGuildLeader=" .. boolText(IsGuildLeader))
    add("C_GuildInfo.IsGuildOfficer=" .. boolText(C_GuildInfo and C_GuildInfo.IsGuildOfficer))
    add("GetNumGuildMembers=" .. (type(GetNumGuildMembers) == "function"
        and (function()
            local ok, total, online = call(GetNumGuildMembers)
            return ok and (type(total) .. "/" .. type(online) .. " total=" .. tostring(total) .. " online=" .. tostring(online)) or "error"
        end)() or "missing"))
    add("GetGuildRosterInfo=" .. (type(GetGuildRosterInfo) == "function" and "present" or "missing"))
    add("GetGuildRosterLastOnline=" .. (type(GetGuildRosterLastOnline) == "function" and "present" or "missing"))
    add("C_GuildInfo.GuildRoster=" .. (C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" and "present" or "missing"))
    add("GuildRoster(global)=" .. (type(GuildRoster) == "function" and "present" or "missing"))

    -- C_Club
    local clubId
    if C_Club and type(C_Club.GetGuildClubId) == "function" then
        local ok, id = call(C_Club.GetGuildClubId)
        add("C_Club.GetGuildClubId: " .. (ok and (type(id) .. (id and "(set)" or "")) or "error"))
        if ok then clubId = id end
    else
        add("C_Club.GetGuildClubId: missing")
    end
    add("C_Club.GetClubMembers=" .. (C_Club and type(C_Club.GetClubMembers) == "function" and "present" or "missing"))
    add("C_Club.GetMemberInfo=" .. (C_Club and type(C_Club.GetMemberInfo) == "function" and "present" or "missing"))
    if clubId and C_Club and type(C_Club.GetClubMembers) == "function" then
        local ok, members = call(C_Club.GetClubMembers, clubId)
        if ok and type(members) == "table" then
            add("GetClubMembers: table count=" .. #members .. " elementType=" .. type(members[1]))
            if members[1] and type(C_Club.GetMemberInfo) == "function" then
                local ok2, info = call(C_Club.GetMemberInfo, clubId, members[1])
                if ok2 and type(info) == "table" then
                    add("GetMemberInfo fields: " .. describe(info))
                    local lo = {}
                    for k in pairs(info) do
                        if tostring(k):find("^lastOnline") then lo[#lo + 1] = k end
                    end
                    table.sort(lo)
                    add("lastOnline* fields: " .. (#lo > 0 and table.concat(lo, ",") or "none"))
                else
                    add("GetMemberInfo: " .. (ok2 and type(info) or "error"))
                end
            end
        else
            add("GetClubMembers: " .. (ok and type(members) or "error"))
        end
    else
        add("GetClubMembers/GetMemberInfo: not run (no guild club id)")
    end

    -- Other globals
    add("GetMaxPlayerLevel=" .. boolText(GetMaxPlayerLevel))
    add(probeApi("GetAverageItemLevel", GetAverageItemLevel))
    add(probeApi("UnitFactionGroup(player)", UnitFactionGroup, "string<faction>", "player"))
    add(probeApi("GetNormalizedRealmName", GetNormalizedRealmName, "string<realm>"))
    add("C_ClassInfo=" .. (C_ClassInfo and "present" or "missing"))
    add("GetNumClasses=" .. boolText(GetNumClasses))
    local classInfo = "missing"
    if C_CreatureInfo and type(C_CreatureInfo.GetClassInfo) == "function" then
        local ok, ci = call(C_CreatureInfo.GetClassInfo, 1)
        classInfo = ok and describe(ci, "string<class>") or "error"
    end
    add("C_CreatureInfo.GetClassInfo(1)=" .. classInfo)
    return lines
end

local rosterFrame
Probe:Register("S7", "Guild globals (GetGuildInfo, roster, GetMaxPlayerLevel, GetAverageItemLevel, C_Club)", function()
    local lines = s7Sync()
    local base = table.concat(lines, "; ")

    -- Roster is asynchronous: request it and wait for GUILD_ROSTER_UPDATE (timeout 10 s).
    local requested = false
    if C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" then
        requested = call(C_GuildInfo.GuildRoster) and "C_GuildInfo.GuildRoster" or false
    elseif type(GuildRoster) == "function" then
        requested = call(GuildRoster) and "GuildRoster" or false
    end
    if not requested or not (IsInGuild and select(2, call(IsInGuild))) then
        return "info", base .. "; roster: not requested (not in a guild or no API)"
    end

    local done = false
    local started = GetTime and select(2, call(GetTime)) or 0
    local function finish(text)
        if done then return end
        done = true
        if rosterFrame then rosterFrame:UnregisterEvent("GUILD_ROSTER_UPDATE") end
        local entry = Probe:Record("S7", "info", base .. "; " .. text)
        Probe.Print(string.format("S7 [info] %s", entry.details))
    end
    rosterFrame = rosterFrame or CreateFrame("Frame")
    rosterFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
    rosterFrame:SetScript("OnEvent", function()
        local _, total = call(GetNumGuildMembers)
        local text = "GUILD_ROSTER_UPDATE after " .. string.format("%.1f", (GetTime and (GetTime() - started) or 0))
            .. "s via " .. requested .. ", total=" .. tostring(total)
        if type(total) == "number" and total > 0 and type(GetGuildRosterInfo) == "function" then
            local r = { call(GetGuildRosterInfo, 1) }
            local types = {}
            for i = 2, #r do types[#types + 1] = type(r[i]) end
            text = text .. "; GetGuildRosterInfo(1) returns " .. (#r - 1) .. " values: " .. table.concat(types, ",")
            if type(GetGuildRosterLastOnline) == "function" then
                local lr = { call(GetGuildRosterLastOnline, 1) }
                local lt = {}
                for i = 2, #lr do lt[#lt + 1] = type(lr[i]) end
                text = text .. "; GetGuildRosterLastOnline(1) returns " .. (#lr - 1) .. " values: " .. table.concat(lt, ",")
            end
        end
        finish(text)
    end)
    if C_Timer and C_Timer.After then
        C_Timer.After(10, function() finish("no GUILD_ROSTER_UPDATE within 10s (requested via " .. requested .. ")") end)
    end
    return "todo", "roster requested, waiting for GUILD_ROSTER_UPDATE (up to 10s); result is recorded when it arrives. Base: " .. base
end)

-- S11 --------------------------------------------------------------------------------------------------------------
local function lockdownSnapshot(label)
    local parts = { "label=" .. label }
    local ci = C_ChatInfo or {}
    parts[#parts + 1] = "InChatMessagingLockdown=" .. boolText(ci.InChatMessagingLockdown)
    parts[#parts + 1] = "AreOutgoingAddonChatMessagesRestricted=" .. boolText(ci.AreOutgoingAddonChatMessagesRestricted)
    local inInstance = "missing"
    if type(IsInInstance) == "function" then
        local ok, a, b = call(IsInInstance)
        inInstance = ok and (tostring(a) .. "/" .. tostring(b)) or "error"
    end
    parts[#parts + 1] = "IsInInstance=" .. inInstance
    parts[#parts + 1] = "InCombatLockdown=" .. boolText(InCombatLockdown)

    local ra = C_RestrictedActions
    if ra and type(ra.GetAddOnRestrictionState) == "function" and type(Enum) == "table"
        and type(Enum.AddOnRestrictionType) == "table" then
        local names = {}
        for name in pairs(Enum.AddOnRestrictionType) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            parts[#parts + 1] = "Restriction." .. name .. "=" .. boolText(ra.GetAddOnRestrictionState, Enum.AddOnRestrictionType[name])
        end
    else
        parts[#parts + 1] = "GetAddOnRestrictionState/Enum.AddOnRestrictionType=missing"
    end
    return table.concat(parts, "; ")
end

--- Stores a labelled snapshot in AzGF_ProbeDB.snapshots and returns its text.
function Probe:Snapshot(label)
    label = (label and label ~= "") and label or "unlabelled"
    local text = lockdownSnapshot(label)
    local d = db()
    d.snapshots = d.snapshots or {}
    d.snapshots[#d.snapshots + 1] = { label = label, text = text, time = date("%Y-%m-%d %H:%M:%S") }
    return text
end

Probe:Register("S11", "Behaviour during InChatMessagingLockdown (instances, encounters, PvP)", function(self)
    local text = self:Snapshot("check-run")
    local n = #db().snapshots
    return "info", text .. "; snapshots stored so far: " .. n .. " (use /agfp snapshot <label>)"
end)

--- Called by Probe:ExportText to append every snapshot.
function Probe:SnapshotLines()
    local lines = {}
    for i, s in ipairs(db().snapshots or {}) do
        lines[#lines + 1] = string.format("S11 snapshot %d | %s | %s", i, s.time, s.text)
    end
    return lines
end
