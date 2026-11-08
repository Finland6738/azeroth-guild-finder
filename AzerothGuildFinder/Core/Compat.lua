-- Compat: the only door to the game API (SPEC-01 §1, §7). Every call is guarded: a missing, failing or restricted API
-- turns one feature off, never the addon. Lua 5.1.
-- Every name used here is in the Forever API dump, except the legacy globals marked [verify] (GetGuildRosterLastOnline,
-- ChatFrame_RemoveChannel, GetChannelList, ChatFrame_AddMessageEventFilter). The M0 probe has not run yet, so every [verify] API must degrade cleanly.
local ADDON_NAME, ns = ...
ns = ns or {}
local Compat = {}
ns.Compat, ns.modules = Compat, ns.modules or {}
ns.modules.Compat = Compat

local AVAILABLE, MISSING, ERROR, RESTRICTED = "available", "missing", "error", "restricted"
Compat.AVAILABLE, Compat.MISSING, Compat.ERROR, Compat.RESTRICTED = AVAILABLE, MISSING, ERROR, RESTRICTED

local type, pcall, select, pairs, ipairs, tostring, tonumber, unpack = type, pcall, select, pairs, ipairs, tostring, tonumber, unpack
local floor = math.floor

---------------------------------------------------------------------------------------------------------------------
-- Resolve, secret values, guarded calls
---------------------------------------------------------------------------------------------------------------------

-- "C_Club.GetGuildClubId" -> the value in the global table, or nil. Never raises.
function Compat.Resolve(path)
	if type(path) ~= "string" or path == "" then return nil end
	local value = _G
	for part in path:gmatch("[^.]+") do
		if type(value) ~= "table" then return nil end
		local ok, nextValue = pcall(function() return value[part] end)
		if not ok then return nil end
		value = nextValue
	end
	return value
end
local Resolve = Compat.Resolve

-- A secret value can be passed around but not read, compared or used in arithmetic: never look inside one.
-- The client functions are looked up on every call (they may appear late, tests replace them).
function Compat.IsSecret(value)
	if value == nil then return false end
	if issecretvalue and issecretvalue(value) then return true end
	if canaccessvalue and not canaccessvalue(value) then return true end
	if type(value) == "table" and issecrettable and issecrettable(value) then return true end
	return false
end
local IsSecret = Compat.IsSecret

-- The value, or nil when the client hides it.
function Compat.Readable(value)
	if IsSecret(value) then return nil end
	return value
end

local function restrictedMessage(message)
	message = tostring(message):lower()
	return message:find("restrict", 1, true) or message:find("secret", 1, true) or message:find("forbidden", 1, true)
		or message:find("blocked", 1, true) or message:find("lockdown", 1, true)
end

-- Runs fn(...) under pcall. Returns state, detail, count, values-table. A secret result is dropped (nil) and the
-- state becomes restricted; an error that talks about restrictions is restricted, any other error is error.
local function run(fn, ...)
	if type(fn) ~= "function" then return MISSING, "not a function", 0, {} end
	local packed = { pcall(fn, ...) }
	local n = #packed
	if not packed[1] then
		local message = tostring(packed[2])
		return restrictedMessage(message) and RESTRICTED or ERROR, message:sub(1, 120), 0, {}
	end
	local state, values, count = AVAILABLE, {}, n - 1
	for i = 1, count do
		local v = packed[i + 1]
		if IsSecret(v) then state, v = RESTRICTED, nil end
		values[i] = v
	end
	return state, state == RESTRICTED and "secret value" or nil, count, values
end

-- Compat.Call("C_Club.GetGuildClubId", ...) -> state, value1, value2, ...
function Compat.Call(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	return state, unpack(values, 1, count)
end

-- First value only when the call is available, else nil (plus the state as second result).
local function first(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	if state == AVAILABLE then return values[1], state end
	return nil, state
end

local function all(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	if state == AVAILABLE then return values, count, state end
	return nil, 0, state
end

---------------------------------------------------------------------------------------------------------------------
-- Guild
---------------------------------------------------------------------------------------------------------------------
local Guild = {}
Compat.Guild = Guild

-- Guild club id (the C_Club fallback); nil without a guild or when the API is missing.
local function guildClubId()
	local id = first("C_Club.GetGuildClubId")
	if type(id) == "number" or type(id) == "string" then return id end
	return nil
end

-- The members of the guild club, in the order the client gives them (the fallback roster).
local function clubMemberIds()
	local clubId = guildClubId()
	if not clubId then return nil, nil end
	local ids = first("C_Club.GetClubMembers", clubId)
	if type(ids) ~= "table" then return nil, clubId end
	return ids, clubId
end

function Guild.InGuild()
	local v, state = first("IsInGuild")
	if state == AVAILABLE then return v and true or false end
	return guildClubId() ~= nil   -- the fallback: a guild club exists
end

function Guild.GuildName()
	local name, state = first("GetGuildInfo", "player")
	if type(name) == "string" and name ~= "" then return name end
	local clubId = state ~= AVAILABLE and guildClubId() or nil
	if clubId then
		local info = first("C_Club.GetClubInfo", clubId)
		if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
	end
	return nil
end

-- guildName, rankName, rankIndex (0 = Guild Master), or nil.
function Guild.PlayerRank()
	local values, count = all("GetGuildInfo", "player")
	if values and type(values[1]) == "string" then return values[1], values[2], values[3] end
	return nil
end

function Guild.IsGuildLeader()
	local v, state = first("IsGuildLeader")
	if state == AVAILABLE then return v and true or false end
	local _, _, rankIndex = Guild.PlayerRank()
	return rankIndex == 0
end

-- Officer: the client says so, or the player leads the guild.
function Guild.IsOfficer()
	if Guild.IsGuildLeader() then return true end
	local v, state = first("C_GuildInfo.IsGuildOfficer")
	return state == AVAILABLE and v and true or false
end

-- Asks the server for a fresh roster (GUILD_ROSTER_UPDATE follows). Existence guarded.
function Guild.RequestRoster()
	local _, state = first("C_GuildInfo.GuildRoster")
	return state
end

-- total, online. Falls back to the guild club members; online is nil when only the club is known.
function Guild.RosterCount()
	local values, count, state = all("GetNumGuildMembers")
	if values and type(values[1]) == "number" then return values[1], values[2] end
	local ids = clubMemberIds()
	if ids then return #ids, nil end
	return 0, nil
end

-- Hours since the member was last online, from years, months, days, hours. Months count 30 days, years 365.
function Compat.LastOnlineHours(years, months, days, hours)
	years, months, days, hours = tonumber(years) or 0, tonumber(months) or 0, tonumber(days) or 0, tonumber(hours) or 0
	return years * 8760 + months * 720 + days * 24 + hours
end

-- Hours since member i was last online (nil while online or unknown).
function Guild.LastOnline(index)
	local values, count, state = all("GetGuildRosterLastOnline", index)   -- [verify] legacy global
	if values then
		if values[1] == nil and values[2] == nil and values[3] == nil and values[4] == nil then return nil end
		return Compat.LastOnlineHours(values[1], values[2], values[3], values[4])
	end
	local row = Guild.RosterRow(index)
	return row and row.lastOnlineHours or nil
end

-- One roster row: { name, rankIndex, level, classFile, classID, online, guid, lastOnlineHours } or nil.
-- GetGuildRosterInfo first; the C_Club members when it is missing or gives nothing.
function Guild.RosterRow(index)
	local values, count, state = all("GetGuildRosterInfo", index)
	if values and type(values[1]) == "string" then
		return {
			name = values[1], rankIndex = values[3], level = values[4], classFile = values[11], online = values[9] and true or false,
			guid = values[17], lastOnlineHours = (not values[9]) and Guild.LastOnline(index) or nil,
		}
	end
	if state == AVAILABLE then return nil end   -- the client answered: no such row
	local ids, clubId = clubMemberIds()
	local memberId = ids and ids[index]
	if memberId == nil then return nil end
	local info = first("C_Club.GetMemberInfo", clubId, memberId)
	if type(info) ~= "table" then return nil end
	local online = info.lastOnlineYear == nil and info.lastOnlineMonth == nil and info.lastOnlineDay == nil and info.lastOnlineHour == nil
	return {
		name = info.name, rankIndex = info.guildRankOrder and (info.guildRankOrder - 1) or nil, level = info.level, classID = info.classID,
		online = online, guid = info.guid,
		lastOnlineHours = (not online) and Compat.LastOnlineHours(info.lastOnlineYear, info.lastOnlineMonth, info.lastOnlineDay, info.lastOnlineHour) or nil,
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------------------------------------------------
local Player = {}
Compat.Player = Player

-- "Horde" or "Alliance" (English name), nil when unknown.
function Player.Faction()
	local v = first("UnitFactionGroup", "player")
	if v == "Horde" or v == "Alliance" then return v end
	return nil
end

-- The character name without the realm, nil when unknown.
function Player.Name()
	local v = first("UnitName", "player")
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

-- Normalized realm name (no spaces), falling back to GetRealmName without spaces.
function Player.Realm()
	local v = first("GetNormalizedRealmName")
	if type(v) ~= "string" or v == "" then
		v = first("GetRealmName")
		if type(v) == "string" then v = v:gsub("[%s%-']", "") end
	end
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

function Player.Level()
	local v = first("UnitLevel", "player")
	return type(v) == "number" and v or nil
end

function Player.ClassID()
	local values = all("UnitClass", "player")
	return values and type(values[3]) == "number" and values[3] or nil
end

function Player.RaceID()
	local values = all("UnitRace", "player")
	return values and type(values[3]) == "number" and values[3] or nil
end

-- Equipped average item level (second result of GetAverageItemLevel), or the overall one; nil when unknown.
function Player.AverageItemLevel()
	local values = all("GetAverageItemLevel")
	if not values then return nil end
	local v = values[2] or values[1]
	return type(v) == "number" and v or nil
end

function Player.MaxLevel()
	local v = first("GetMaxPlayerLevel")
	if type(v) ~= "number" then v = first("GetMaxLevelForPlayerExpansion") end
	return type(v) == "number" and v or nil
end

-- Playable classes the client knows: { { id, name, file }, ... } sorted by id, or nil when the API is missing or gives
-- nothing (C_CreatureInfo.GetClassInfo [verify on Forever]). Ids 1..GetNumClasses() are tried; gaps are skipped.
function Compat.Classes()
	local count = first("GetNumClasses")
	local limit = type(count) == "number" and count >= 1 and count <= 40 and count or 20
	local list = {}
	for id = 1, limit do
		local info = first("C_CreatureInfo.GetClassInfo", id)
		if type(info) == "table" and type(info.classID) == "number" then
			list[#list + 1] = { id = info.classID, name = type(info.className) == "string" and info.className or nil, file = type(info.classFile) == "string" and info.classFile or nil }
		end
	end
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- Chat restrictions (SPEC-01 §7)
---------------------------------------------------------------------------------------------------------------------
local Chat = {}
Compat.Chat = Chat

-- The addon restriction kinds of Enum.AddOnRestrictionType that matter (names as in the retail enum; one the client
-- does not have is skipped, not an error).
Compat.RESTRICTION_KINDS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }

-- true while the client blocks outgoing chat messages (the messages must wait in the queue).
function Chat.InChatLockdown()
	local v, state = first("C_ChatInfo.InChatMessagingLockdown")
	if state == AVAILABLE then return v and true or false end
	return state == RESTRICTED or state == ERROR   -- cannot tell: stay on the safe side
end

-- true when the addon is read only: outgoing addon chat messages are restricted.
function Chat.OutgoingAddonRestricted()
	local v, state = first("C_ChatInfo.AreOutgoingAddonChatMessagesRestricted")
	if state == AVAILABLE then return v and true or false end
	return state == RESTRICTED or state == ERROR
end

-- active, state for one kind ("Combat", ...). Missing enum or function: false, nil (nothing can be known and nothing
-- is restricted). An error or a secret state counts as active (safe side). Falls back to IsAddOnRestrictionActive.
function Chat.RestrictionActive(kind)
	local types = Resolve("Enum.AddOnRestrictionType")
	local value = type(types) == "table" and types[kind] or nil
	if value == nil then return false, nil end
	local state, callState = first("C_RestrictedActions.GetAddOnRestrictionState", value)
	if callState == AVAILABLE and type(state) == "number" then return state > 0, state end
	if callState == RESTRICTED or callState == ERROR then return true, nil end
	local active, activeState = first("C_RestrictedActions.IsAddOnRestrictionActive", value)
	if activeState == AVAILABLE then return active and true or false, nil end
	return activeState ~= MISSING, nil
end

-- The first active restriction kind, or nil.
function Chat.RestrictionAny()
	for _, kind in ipairs(Compat.RESTRICTION_KINDS) do
		if (Chat.RestrictionActive(kind)) then return kind end
	end
	return nil
end

-- Sending is allowed: no lockdown, no restriction, not read only.
function Chat.CanSend()
	return not Chat.InChatLockdown() and not Chat.OutgoingAddonRestricted() and Chat.RestrictionAny() == nil
end

---------------------------------------------------------------------------------------------------------------------
-- Time, encoding, channels
---------------------------------------------------------------------------------------------------------------------
function Compat.ServerTime()
	local v = first("GetServerTime")
	if type(v) == "number" then return v end
	return time()
end

-- Monotonic seconds with sub-second precision (GetTime); the wall clock when the client function is missing.
function Compat.Now()
	local v = first("GetTime")
	if type(v) == "number" then return v end
	return time()
end

-- C_Timer wrappers. After(seconds, fn) -> true when scheduled. NewTicker(seconds, fn) -> handle with :Cancel(), or nil
-- when timers are not available (the caller must cope: no timer, no sending).
function Compat.After(seconds, fn)
	local state = Compat.Call("C_Timer.After", seconds, fn)
	return state == AVAILABLE
end

function Compat.NewTicker(seconds, fn)
	local state, handle = Compat.Call("C_Timer.NewTicker", seconds, fn)
	if state == AVAILABLE and type(handle) == "table" then return handle end
	return nil
end

local function enum(name, key)
	local t = Resolve("Enum." .. name)
	return type(t) == "table" and t[key] or nil
end

-- Encoding wrappers: value, or nil plus an error text (never raise).
local function encoding(path, ...)
	local state, detail, count, values = run(Resolve("C_EncodingUtil." .. path), ...)
	if state == AVAILABLE and values[1] ~= nil then return values[1] end
	return nil, state == AVAILABLE and "no result" or (state .. (detail and (": " .. detail) or ""))
end

Compat.CBOR = {
	Encode = function(value) return encoding("SerializeCBOR", value) end,
	Decode = function(text) return encoding("DeserializeCBOR", text) end,
}
Compat.Compress = {
	Deflate = function(text) return encoding("CompressString", text, enum("CompressionMethod", "Deflate"), enum("CompressionLevel", "Default")) end,
	Inflate = function(text) return encoding("DecompressString", text, enum("CompressionMethod", "Deflate")) end,
}
Compat.Base64 = {
	Encode = function(text) return encoding("EncodeBase64", text) end,
	Decode = function(text) return encoding("DecodeBase64", text) end,
}

-- Channels (legacy globals, [verify] on Forever). JoinChannelByName answers later through CHAT_MSG_CHANNEL_NOTICE.
function Compat.JoinChannelByName(name, password)
	local _, state = first("JoinChannelByName", name, password)
	return state
end

-- channelId (0 when not joined), name; nil, nil when the API is missing.
function Compat.GetChannelName(nameOrId)
	local values = all("GetChannelName", nameOrId)
	if not values then return nil, nil end
	return values[1], values[2]
end

function Compat.LeaveChannelByName(name)
	local _, state = first("LeaveChannelByName", name)
	return state
end

-- The joined channels in list order: { { id = , name = , disabled = }, ... }; nil when the API is missing.
-- GetChannelList returns id, name, disabled for every channel (flat), so the values are read in threes.
function Compat.GetChannelList()
	local values, count = all("GetChannelList")
	if not values then return nil end
	local list = {}
	local i = 1
	while i <= count do
		local id, name = values[i], values[i + 1]
		if type(id) == "number" and type(name) == "string" then
			list[#list + 1] = { id = id, name = name, disabled = values[i + 2] and true or false }
			i = i + 3
		else
			i = i + 1
		end
	end
	return list
end

-- Takes the channel out of every chat window. Returns the number of windows it was applied to (0 when the API is missing).
function Compat.RemoveChannelFromChatFrames(name)
	if type(Resolve("ChatFrame_RemoveChannel")) ~= "function" then return 0 end
	local windows = Resolve("NUM_CHAT_WINDOWS")
	if type(windows) ~= "number" then windows = 10 end
	local done = 0
	for i = 1, windows do
		local frame = Resolve("ChatFrame" .. i)
		if frame ~= nil then
			if select(2, first("ChatFrame_RemoveChannel", frame, name)) == AVAILABLE then done = done + 1 end
		end
	end
	return done
end

-- Swaps two channel positions (the numbers of /1, /2 ...). Returns the state ("missing" when the API is not there).
function Compat.SwapChatChannels(index, otherIndex)
	local _, state = first("C_ChatInfo.SwapChatChannelsByChannelIndex", index, otherIndex)
	return state
end

-- Registers a chat message filter: fn(chatFrame, event, ...) returns true to hide the message. Returns the state.
function Compat.AddChatFilter(event, fn)
	local _, state = first("ChatFrame_AddMessageEventFilter", event, fn)
	return state
end

-- true while the player is in combat lockdown (UI changes are blocked); false when the function is missing.
function Compat.InCombat()
	local v = first("InCombatLockdown")
	return v and true or false
end

---------------------------------------------------------------------------------------------------------------------
-- Build and capability probe
---------------------------------------------------------------------------------------------------------------------
function Compat.BuildInfo()
	local values = all("GetBuildInfo")
	values = values or {}
	return {
		version = tostring(values[1] or "?"), build = tostring(values[2] or "?"), interface = tonumber(values[4]) or 0,
		projectID = WOW_PROJECT_ID, isForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT,
	}
end

-- Capability definitions: { id, group, path, call = true to call it, args = {...}, restrictedWhenTrue, note }.
-- Functions with side effects (join, leave, invite, roster request) are only checked for existence.
local CAPS = {
	{ "guild.IsInGuild", "guild", "IsInGuild", call = true },
	{ "guild.GetGuildInfo", "guild", "GetGuildInfo", call = true, args = { "player" } },
	{ "guild.IsGuildLeader", "guild", "IsGuildLeader", call = true },
	{ "guild.IsGuildOfficer", "guild", "C_GuildInfo.IsGuildOfficer", call = true },
	{ "guild.GetNumGuildMembers", "guild", "GetNumGuildMembers", call = true },
	{ "guild.GetGuildRosterInfo", "guild", "GetGuildRosterInfo" },
	{ "guild.GetGuildRosterLastOnline", "guild", "GetGuildRosterLastOnline", note = "[verify] legacy global" },
	{ "guild.GuildRoster", "guild", "C_GuildInfo.GuildRoster" },
	{ "guild.GetGuildTabardInfo", "guild", "C_GuildInfo.GetGuildTabardInfo" },
	{ "guild.Invite", "guild", "C_GuildInfo.Invite" },
	{ "club.GetGuildClubId", "club", "C_Club.GetGuildClubId", call = true },
	{ "club.GetClubMembers", "club", "C_Club.GetClubMembers" },
	{ "club.GetMemberInfo", "club", "C_Club.GetMemberInfo" },
	{ "club.GetClubInfo", "club", "C_Club.GetClubInfo" },
	{ "clubfinder.IsEnabled", "club", "C_ClubFinder.IsEnabled", call = true, note = "true would mean a server-side catalog exists" },
	{ "player.UnitFactionGroup", "player", "UnitFactionGroup", call = true, args = { "player" } },
	{ "player.UnitLevel", "player", "UnitLevel", call = true, args = { "player" } },
	{ "player.UnitClass", "player", "UnitClass", call = true, args = { "player" } },
	{ "player.UnitRace", "player", "UnitRace", call = true, args = { "player" } },
	{ "player.GetNormalizedRealmName", "player", "GetNormalizedRealmName", call = true },
	{ "player.GetAverageItemLevel", "player", "GetAverageItemLevel", call = true },
	{ "player.GetMaxPlayerLevel", "player", "GetMaxPlayerLevel", call = true },
	{ "chat.InChatMessagingLockdown", "chat", "C_ChatInfo.InChatMessagingLockdown", call = true, restrictedWhenTrue = true },
	{ "chat.AreOutgoingAddonChatMessagesRestricted", "chat", "C_ChatInfo.AreOutgoingAddonChatMessagesRestricted", call = true, restrictedWhenTrue = true },
	{ "chat.SendAddonMessage", "chat", "C_ChatInfo.SendAddonMessage" },
	{ "chat.RegisterAddonMessagePrefix", "chat", "C_ChatInfo.RegisterAddonMessagePrefix" },
	{ "channel.JoinChannelByName", "channel", "JoinChannelByName", note = "[verify] legacy global" },
	{ "channel.GetChannelName", "channel", "GetChannelName", note = "[verify] legacy global" },
	{ "channel.LeaveChannelByName", "channel", "LeaveChannelByName", note = "[verify] legacy global" },
	{ "channel.GetChannelList", "channel", "GetChannelList", note = "[verify] legacy global" },
	{ "channel.ChatFrame_RemoveChannel", "channel", "ChatFrame_RemoveChannel", note = "[verify] FrameXML global" },
	{ "channel.ChatFrame_AddMessageEventFilter", "channel", "ChatFrame_AddMessageEventFilter", note = "[verify] FrameXML global" },
	{ "channel.SwapChatChannelsByChannelIndex", "channel", "C_ChatInfo.SwapChatChannelsByChannelIndex" },
	{ "time.GetServerTime", "time", "GetServerTime", call = true },
	{ "time.GetTime", "time", "GetTime", call = true },
	{ "time.NewTicker", "time", "C_Timer.NewTicker" },
	{ "time.After", "time", "C_Timer.After" },
	{ "secret.issecretvalue", "secret", "issecretvalue" },
	{ "secret.canaccessvalue", "secret", "canaccessvalue" },
	{ "restriction.GetAddOnRestrictionState", "restriction", "C_RestrictedActions.GetAddOnRestrictionState" },
	{ "restriction.AddOnRestrictionType", "restriction", "Enum.AddOnRestrictionType", table = true },
	{ "encoding.SerializeCBOR", "encoding", "C_EncodingUtil.SerializeCBOR" },
	{ "encoding.DeserializeCBOR", "encoding", "C_EncodingUtil.DeserializeCBOR" },
	{ "encoding.CompressString", "encoding", "C_EncodingUtil.CompressString" },
	{ "encoding.DecompressString", "encoding", "C_EncodingUtil.DecompressString" },
	{ "encoding.EncodeBase64", "encoding", "C_EncodingUtil.EncodeBase64" },
	{ "encoding.DecodeBase64", "encoding", "C_EncodingUtil.DecodeBase64" },
}
Compat.CAPABILITY_DEFS = CAPS

local function probeOne(def)
	local path = def[3]
	local value = Resolve(path)
	if def.table then
		if type(value) == "table" then return AVAILABLE, nil end
		return MISSING, nil
	end
	if type(value) ~= "function" then return MISSING, nil end
	if not def.call then return AVAILABLE, def.note end
	local state, detail, count, values = run(value, unpack(def.args or {}))
	local result = values[1]
	if state == AVAILABLE then
		if def.restrictedWhenTrue and result == true then return RESTRICTED, "active now" end
		if type(result) == "boolean" then detail = "returns " .. tostring(result) elseif def.note then detail = def.note end
	end
	return state, detail
end

-- Fills Compat.caps ({ [id] = { id, group, state, detail } } and Compat.capOrder) from the client as it is now.
function Compat:Probe()
	self.caps, self.capOrder = {}, {}
	local function set(id, group, state, detail)
		self.caps[id] = { id = id, group = group, state = state, detail = detail }
		self.capOrder[#self.capOrder + 1] = id
	end
	for _, def in ipairs(CAPS) do
		local state, detail = probeOne(def)
		set(def[1], def[2], state, detail)
	end
	-- One entry per restriction kind: restricted while the client says the restriction is active.
	for _, kind in ipairs(self.RESTRICTION_KINDS) do
		local present = type(Resolve("Enum.AddOnRestrictionType")) == "table" and Resolve("Enum.AddOnRestrictionType")[kind] ~= nil
		local state, detail = MISSING, nil
		if present then
			local active, value = Chat.RestrictionActive(kind)
			state, detail = active and RESTRICTED or AVAILABLE, value and ("state " .. tostring(value)) or nil
		end
		set("restriction." .. kind, "restriction", state, detail)
	end
	-- A CBOR + Base64 round trip proves the encoding chain works as a whole.
	local encoded = Compat.CBOR.Encode({ a = 1 })
	local text = encoded and Compat.Base64.Encode(encoded)
	local decoded = text and Compat.CBOR.Decode(Compat.Base64.Decode(text) or "")
	set("encoding.roundTrip", "encoding", (type(decoded) == "table" and decoded.a == 1) and AVAILABLE or
		((self.caps["encoding.SerializeCBOR"].state == MISSING or self.caps["encoding.EncodeBase64"].state == MISSING) and MISSING or ERROR))
	self.probed = true
	return self.caps
end

function Compat:State(id)
	local c = self.caps and self.caps[id]
	return c and c.state or nil
end

function Compat:IsAvailable(id)
	return self:State(id) == AVAILABLE
end

-- Text lines for /gf debug. No player names, no guild names: the build, the project and each capability.
function Compat:DebugLines()
	if not self.probed then self:Probe() end
	local build = Compat.BuildInfo()
	local lines = {
		("Client: %s (build %s), interface %d, project id %s%s"):format(build.version, build.build, build.interface,
			tostring(build.projectID), build.isForever and " (Forever)" or ""),
	}
	local counts = { [AVAILABLE] = 0, [MISSING] = 0, [RESTRICTED] = 0, [ERROR] = 0 }
	local rows = {}
	for _, id in ipairs(self.capOrder) do
		local c = self.caps[id]
		counts[c.state] = (counts[c.state] or 0) + 1
		rows[#rows + 1] = ("  [%s] %s%s"):format(c.state, id, c.detail and (" - " .. c.detail) or "")
	end
	lines[#lines + 1] = ("Capabilities: %d available, %d missing, %d restricted, %d error"):format(
		counts[AVAILABLE], counts[MISSING], counts[RESTRICTED], counts[ERROR])
	for _, row in ipairs(rows) do lines[#lines + 1] = row end
	return lines
end

if ns.addon then ns.addon.Compat = Compat end   -- also reachable from tests and other addons
if ns.addon and ns.addon.AddDebugSection then
	ns.addon:AddDebugSection("Compat", function() return Compat:DebugLines() end)
end
