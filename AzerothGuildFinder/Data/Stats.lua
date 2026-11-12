-- Stats: the guild's aggregate statistics and the anonymous GTOK tokens (SPEC-03 §4, SPEC-02 §3, ADR 0006). Lua 5.1.
--
--   statistics   from the guild roster (the server's source): m = members, a7 = active characters (online now, or last
--                online less than ACTIVE_HOURS ago), max = active characters at the highest level, cls = the class mix
--                of the active characters { [classID] = n }, and the unique players range u7lo..u7hi from the tokens.
--                Only numbers travel (D12). srev = the server time of the computation rounded down to the hour.
--   GTOK         every account has a token per guild, hash(accountSecret, guildKey): different for every guild, so an
--                account cannot be followed from one guild to another. Over GUILD only, at login (want = 1: the other
--                members online answer with their own token after REPLY_DELAY) and every RESEND seconds, with n = the
--                NUMBER of this account's characters in the guild active in the last 7 days (never which ones).
--                Received tokens are kept TOKEN_TTL seconds (7 days) in AzerothGuildFinderDB.tokens.
--   range        covered = sum of n; uncovered = max(0, a7 - covered); u7lo = distinct tokens + (uncovered > 0 and 1
--                or 0), u7hi = distinct tokens + uncovered; both are capped at a7 (a unique player has at least one
--                active character, so stale tokens never push the range above the roster).
--   opt-out      settings.shareAltCount = false: no GTOK is sent (neither at login nor as an answer) and this account's
--                own token is not counted here either, so every member computes the same range. Tokens of the others
--                are still received.
--
-- The pure parts (FromRoster, UniqueRange, Token, Srev) take plain values and are tested without a client. Names never
-- leave this file: this account's characters are remembered as hashes of their names, only locally, to count n.
local ADDON_NAME, ns = ...
ns = ns or {}
local Stats = {}
ns.Stats, ns.modules = Stats, ns.modules or {}
ns.modules.Stats = Stats

local type, pairs, ipairs, tonumber, tostring, next = type, pairs, ipairs, tonumber, tostring, next
local floor, max, min, random = math.floor, math.max, math.min, math.random

---------------------------------------------------------------------------------------------------------------------
-- Constants (read on use, so tests may change them)
---------------------------------------------------------------------------------------------------------------------
Stats.ACTIVE_HOURS = 168          -- a7: last online less than 7 days (168 hours) ago, or online now
Stats.TOKEN_TTL = 7 * 86400       -- tokens heard, and this account's characters, are forgotten after 7 days
Stats.RESEND = 86400              -- our own GTOK again every 24 hours
Stats.LOGIN_DELAY = { 5, 15 }     -- after login (the guild known): our GTOK with want = 1
Stats.REPLY_DELAY = { 1, 20 }     -- SPEC-03 §4: the answer to a want = 1
Stats.REPLY_GAP = 60              -- at most one answer per this time; wants heard meanwhile share it
Stats.MAX_N = 50                  -- n of a GTOK: 1..MAX_N characters of one account in one guild
Stats.MAX_TOKENS = 1000           -- tokens kept per guild (a guild has at most 1000 members)
Stats.MAX_GUILDS = 20             -- guild keys kept in the token store (the characters of one account)
Stats.CACHE = 60                  -- seconds a computed result is reused unless the roster or the tokens changed
Stats.AUTO = true                 -- false: no GTOK by itself (the single-client tests switch it off)

local TOKEN_PATTERN = "^%x%x%x%x%x%x%x%x$"

---------------------------------------------------------------------------------------------------------------------
-- State (memory only)
---------------------------------------------------------------------------------------------------------------------
local function newCounters()
	return { sent = 0, heard = 0, invalid = 0, replies = 0, optedOut = 0, computed = 0 }
end

local state
local function resetState()
	state = {
		cache = nil,          -- { key, at, st, srev }
		sendGen = 0,          -- the scheduled GTOK (login / every RESEND)
		sendKey = nil,        -- the guild the schedule is for
		replyPending = false, replyAt = nil,
		lastSentAt = nil,
		counters = newCounters(),
	}
	Stats.state = state
end
resetState()

local function C() return ns.Compat end
local function now() return C().Now() end
local function clock() return C().ServerTime() end
local function rnd(range) return range[1] + (range[2] - range[1]) * random() end
local function after(seconds, fn) return C().After(seconds, fn) end
local function emit(...) if ns.Bus then ns.Bus:Emit(...) end end

local function baseName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return (name:match("^[^%-]+") or name):lower()
end
local function isSelf(sender)
	local mine = baseName(C().Player.Name())
	return mine ~= nil and baseName(sender) == mine
end
local function hashHex(s) return ns.Normalize.Hash32Hex(s) end

local function guildKey()
	if not ns.Role then return nil end
	local _, key = ns.Role.Compute()
	return key
end

---------------------------------------------------------------------------------------------------------------------
-- Pure math
---------------------------------------------------------------------------------------------------------------------
local function isInt(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end

-- classFile ("WARRIOR") -> classID, from the client's class list, else the static table of Data/Enums.lua.
function Stats.ClassMap()
	local map = {}
	local list = ns.Compat and ns.Compat.Classes and ns.Compat.Classes()
	for _, c in ipairs(list or {}) do
		if c.file then map[c.file] = c.id end
	end
	for id, c in pairs(ns.Enums and ns.Enums.CLASS_ROLES or {}) do
		if map[c.key] == nil then map[c.key] = id end
	end
	return map
end

-- true when a roster row counts as an active character: online now, or last online less than `hours` ago.
function Stats.IsActive(row, hours)
	if type(row) ~= "table" then return false end
	if row.online then return true end
	local h = tonumber(row.lastOnlineHours)
	return h ~= nil and h >= 0 and h < (hours or Stats.ACTIVE_HOURS)
end

-- The aggregates of a roster: rows = { { level, classFile | classID, online, lastOnlineHours } }, maxLevel = the
-- highest level (nil: unknown, then `max` is left out), classMap = classFile -> classID. Returns { m, a7, max, cls }.
function Stats.FromRoster(rows, maxLevel, classMap, hours)
	classMap = classMap or {}
	local st, cls, classes = { m = 0, a7 = 0 }, {}, 0
	local atMax = 0
	for _, row in ipairs(rows or {}) do
		st.m = st.m + 1
		if Stats.IsActive(row, hours) then
			st.a7 = st.a7 + 1
			if maxLevel and row.level == maxLevel then atMax = atMax + 1 end
			local id = row.classID
			if type(id) ~= "number" then id = classMap[row.classFile] end
			if type(id) == "number" then
				if not cls[id] then classes = classes + 1 cls[id] = 0 end
				cls[id] = cls[id] + 1
			end
		end
	end
	if maxLevel then st.max = atMax end
	if classes > 0 then st.cls = cls end
	return st
end

-- The unique players range from a7 and the tokens { [token] = n } (SPEC-03 §4). Returns lo, hi.
function Stats.UniqueRange(a7, tokens)
	a7 = tonumber(a7) or 0
	local distinct, covered = 0, 0
	for _, n in pairs(tokens or {}) do
		if type(n) == "number" and n >= 1 then
			distinct = distinct + 1
			covered = covered + floor(n)
		end
	end
	local uncovered = max(0, a7 - covered)
	local lo = distinct + (uncovered > 0 and 1 or 0)
	local hi = distinct + uncovered
	return min(lo, a7), min(hi, a7)
end

-- The token of an account for a guild: 8 hex digits, different for every guild, never the secret itself.
function Stats.Token(secret, key)
	return hashHex("gtok:" .. tostring(secret or "") .. ":" .. tostring(key or ""))
end

-- srev: server time rounded down to the hour (SPEC-03 §2).
function Stats.Srev(t)
	t = floor(tonumber(t) or 0)
	return t - t % 3600
end

---------------------------------------------------------------------------------------------------------------------
-- Saved data: AzerothGuildFinderDB.tokens = { mine = { [k] = { [nameHash] = at } }, heard = { [k] = { [token] = { n, at } } } }
---------------------------------------------------------------------------------------------------------------------
local function account()
	local db = ns.Config and ns.Config.db and ns.Config.db.account
	return type(db) == "table" and db or nil
end
local function readOnly() return ns.Config ~= nil and ns.Config.IsReadOnly ~= nil and ns.Config:IsReadOnly("account") end

local function store()
	local db = account()
	if not db then return nil end
	if type(db.tokens) ~= "table" then db.tokens = {} end
	local t = db.tokens
	if type(t.mine) ~= "table" then t.mine = {} end
	if type(t.heard) ~= "table" then t.heard = {} end
	return t
end

local function secret()
	local db = account()
	return db and type(db.accountSecret) == "string" and db.accountSecret or ""
end

-- Drops expired and malformed entries of one guild table; returns the number left.
local function pruneGuild(list, isEntry, t)
	local n = 0
	for id, v in pairs(list) do
		local at = isEntry(id, v)
		if not at or t - at >= Stats.TOKEN_TTL or at > t + 3600 then list[id] = nil else n = n + 1 end
	end
	return n
end

local function heardEntry(token, v)
	if type(token) ~= "string" or not token:match(TOKEN_PATTERN) or type(v) ~= "table" then return nil end
	if not isInt(v.n, 1, Stats.MAX_N) or type(v.at) ~= "number" then return nil end
	return v.at
end
local function mineEntry(h, at)
	if type(h) ~= "string" or not h:match(TOKEN_PATTERN) or type(at) ~= "number" then return nil end
	return at
end

-- Forgets everything older than TOKEN_TTL, malformed entries and the guilds left empty.
function Stats:Prune()
	local s = store()
	if not s or readOnly() then return end
	local t = clock()
	for _, part in ipairs({ { s.heard, heardEntry }, { s.mine, mineEntry } }) do
		local tbl, fn = part[1], part[2]
		for k, list in pairs(tbl) do
			if type(k) ~= "string" or type(list) ~= "table" or pruneGuild(list, fn, t) == 0 then tbl[k] = nil end
		end
	end
end

-- Is this account sharing its anonymous alt count (settings.shareAltCount, on by default)?
function Stats:Sharing()
	local db = account()
	local settings = db and db.settings
	return not (type(settings) == "table" and settings.shareAltCount == false)
end

-- Turns sharing on or off. Turning it on sends our token soon (want = 0). Returns true, or false plus "nodb"/"readonly".
function Stats:SetSharing(on)
	local db = account()
	if not db or type(db.settings) ~= "table" then return false, "nodb" end
	if readOnly() then return false, "readonly" end
	db.settings.shareAltCount = on and true or false
	self:Invalidate()
	if on and Stats.AUTO then self:Schedule(rnd(Stats.LOGIN_DELAY), false) end
	emit("STATS_CHANGED", guildKey())
	return true
end

-- Records the character playing now as one of this account's characters in its guild (and in no other guild).
function Stats:NoteSelf()
	local s = store()
	if not s or readOnly() then return end
	local name = baseName(C().Player.Name())
	if not name then return end
	local me, key = hashHex(name), guildKey()
	for k, list in pairs(s.mine) do
		if k ~= key and type(list) == "table" then
			list[me] = nil
			if next(list) == nil then s.mine[k] = nil end
		end
	end
	if not key then return end
	if type(s.mine[key]) ~= "table" then s.mine[key] = {} end
	s.mine[key][me] = clock()
end

-- The names of the roster as hashes, or nil while the roster is not readable.
local function rosterRows()
	local G = C().Guild
	if not G.InGuild() then return nil end
	local total = min(tonumber((G.RosterCount())) or 0, G.MAX_ROSTER or 1000)
	local rows = {}
	for i = 1, total do
		local row = G.RosterRow(i)
		if row then rows[#rows + 1] = row end
	end
	if #rows == 0 then return nil end
	return rows
end

-- n: this account's characters in guild k seen in the last 7 days (at least the one playing now). When the roster is
-- given, characters that are no longer in it do not count.
function Stats:OwnCount(key, rows)
	local s = store()
	key = key or guildKey()
	if not key then return 0 end
	local t, n = clock(), 0
	local inRoster
	if rows then
		inRoster = {}
		for _, row in ipairs(rows) do
			local b = baseName(row.name)
			if b then inRoster[hashHex(b)] = true end
		end
	end
	local me = baseName(C().Player.Name())
	me = me and hashHex(me)
	local counted = false
	for h, at in pairs(s and type(s.mine[key]) == "table" and s.mine[key] or {}) do
		if mineEntry(h, at) and t - at < Stats.TOKEN_TTL and (not inRoster or inRoster[h]) then
			n = n + 1
			if h == me then counted = true end
		end
	end
	if me and not counted then n = n + 1 end
	return min(n, Stats.MAX_N)
end

-- The tokens counted for guild k: { [token] = n }, the ones heard in the last 7 days plus our own when sharing.
function Stats:Tokens(key, rows)
	key = key or guildKey()
	local out = {}
	if not key then return out end
	local s = store()
	local t = clock()
	for token, v in pairs(s and type(s.heard[key]) == "table" and s.heard[key] or {}) do
		local at = heardEntry(token, v)
		if at and t - at < Stats.TOKEN_TTL then out[token] = v.n end
	end
	if self:Sharing() then out[Stats.Token(secret(), key)] = self:OwnCount(key, rows) end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The statistics of the player's guild
---------------------------------------------------------------------------------------------------------------------
function Stats:Invalidate() state.cache = nil end

-- Computes the statistics of the player's guild now. Returns st, srev, or nil plus "no-guild" or "roster".
function Stats:Compute()
	local key = guildKey()
	if not key then return nil, "no-guild" end
	local rows = rosterRows()
	if not rows then return nil, "roster" end
	local st = Stats.FromRoster(rows, C().Player.MaxLevel(), Stats.ClassMap())
	local total = tonumber((C().Guild.RosterCount()))
	if total and total > st.m then st.m = min(total, C().Guild.MAX_ROSTER or 1000) end
	st.u7lo, st.u7hi = Stats.UniqueRange(st.a7, self:Tokens(key, rows))
	state.counters.computed = state.counters.computed + 1
	return st, Stats.Srev(clock()), key
end

-- The statistics of the player's guild, reused for CACHE seconds. Returns st (a copy), srev, key; or nil plus a reason.
function Stats:Current()
	local key = guildKey()
	local c = state.cache
	if not (c and c.key == key and now() - c.at < Stats.CACHE) then
		local st, srev = self:Compute()
		if not st then return nil, srev end
		c = { key = key, at = now(), st = st, srev = srev }
		state.cache = c
	end
	local copy = {}
	for f, v in pairs(c.st) do
		if type(v) == "table" then
			local t = {}
			for id, n in pairs(v) do t[id] = n end
			copy[f] = t
		else
			copy[f] = v
		end
	end
	return copy, c.srev, c.key
end

-- A summary of the player's own guild with the local statistics when they are newer than its own (or it has none);
-- any other summary is returned unchanged. For the guild page: a member sees the roster's numbers at once.
function Stats:Overlay(sum)
	if type(sum) ~= "table" or not sum.k or sum.k ~= guildKey() then return sum end
	local st, srev = self:Current()
	if not st or (type(sum.st) == "table" and (tonumber(sum.srev) or 0) >= srev) then return sum end
	local out = {}
	for f, v in pairs(sum) do out[f] = v end
	out.st, out.srev = st, srev
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- GTOK
---------------------------------------------------------------------------------------------------------------------

-- Sends our token over GUILD now. want: ask the members online for theirs. Returns true, or false plus "no-guild" or
-- "optout".
function Stats:SendToken(want)
	local key = guildKey()
	if not key then return false, "no-guild" end
	if not self:Sharing() then
		state.counters.optedOut = state.counters.optedOut + 1
		return false, "optout"
	end
	self:NoteSelf()
	local msg = { t = "GTOK", token = Stats.Token(secret(), key), n = self:OwnCount(key, rosterRows()) }
	if want then msg.want = 1 end
	local item, why = ns.Transport:Send("GUILD", msg, { key = "GTOK" })
	if not item then return false, why end
	state.lastSentAt = now()
	state.counters.sent = state.counters.sent + 1
	return true
end

-- Our GTOK after `delay` seconds, then every RESEND seconds; a later call replaces it.
function Stats:Schedule(delay, want)
	state.sendGen = state.sendGen + 1
	local gen = state.sendGen
	state.sendKey = guildKey()
	after(delay, function()
		if gen ~= state.sendGen then return end
		if guildKey() ~= state.sendKey then return end
		Stats:SendToken(want)
		Stats:Schedule(Stats.RESEND, false)
	end)
end

function Stats:Stop() state.sendGen = state.sendGen + 1 state.sendKey = nil end

-- A want = 1: one answer after REPLY_DELAY, at most one per REPLY_GAP (wants heard meanwhile share it).
local function scheduleReply()
	if state.replyPending then return end
	state.replyPending = true
	local wait = rnd(Stats.REPLY_DELAY)
	if state.replyAt then wait = max(wait, state.replyAt + Stats.REPLY_GAP - now()) end
	after(wait, function()
		state.replyPending = false
		if not Stats:Sharing() then return end
		state.replyAt = now()
		if Stats:SendToken(false) then state.counters.replies = state.counters.replies + 1 end
	end)
end

local function onToken(msg, sender)
	if isSelf(sender) then return false, "self" end   -- the server sends our own GUILD messages back
	local key = guildKey()
	if not key then return false, "no-guild" end
	local tok, n = msg.token, msg.n
	if type(tok) ~= "string" or not tok:match(TOKEN_PATTERN) or not isInt(n, 1, Stats.MAX_N) then
		state.counters.invalid = state.counters.invalid + 1
		return false, "invalid"
	end
	tok = tok:lower()
	local s = store()
	if s and not readOnly() then
		if type(s.heard[key]) ~= "table" then
			local guilds = 0
			for _ in pairs(s.heard) do guilds = guilds + 1 end
			if guilds >= Stats.MAX_GUILDS then Stats:Prune() end
			s.heard[key] = {}
		end
		local list = s.heard[key]
		if not list[tok] then
			local count = 0
			for _ in pairs(list) do count = count + 1 end
			if count >= Stats.MAX_TOKENS then Stats:Prune() end
		end
		list[tok] = { n = n, at = clock() }
	end
	state.counters.heard = state.counters.heard + 1
	Stats:Invalidate()
	if msg.want == 1 and Stats:Sharing() then scheduleReply() end
	emit("STATS_CHANGED", key)
	return true
end

function Stats:OnMessage(msg, sender, dist)
	if dist ~= "GUILD" or msg.t ~= "GTOK" then return end   -- tokens travel over GUILD only
	return onToken(msg, sender)
end

-- ROLE_CHANGED: a new guild (or the login) -> remember this character, then our GTOK with want = 1.
function Stats:OnRoleChanged(role, key, oldRole, oldKey)
	self:Invalidate()
	if key == oldKey then return end
	self:NoteSelf()
	if not key then return self:Stop() end
	self:Prune()
	if Stats.AUTO then self:Schedule(rnd(Stats.LOGIN_DELAY), true) end
end

function Stats:Reset() resetState() end

---------------------------------------------------------------------------------------------------------------------
-- /gf debug (numbers only, no names)
---------------------------------------------------------------------------------------------------------------------
function Stats:DebugLines()
	local c = state.counters
	local st, srev = self:Current()
	local key = guildKey()
	local tokens = 0
	for _ in pairs(key and self:Tokens(key) or {}) do tokens = tokens + 1 end
	local line
	if st then
		line = ("Stats: %d members, %d active, %s at max level, unique %d-%d, %d classes, computed %d min ago"):format(
			st.m, st.a7, st.max and tostring(st.max) or "?", st.u7lo or 0, st.u7hi or 0,
			(function() local n = 0 for _ in pairs(st.cls or {}) do n = n + 1 end return n end)(),
			floor((clock() - (srev or clock())) / 60))
	else
		line = "Stats: none (" .. tostring(srev) .. ")"
	end
	return {
		line,
		("  tokens counted %d, own characters %d, sharing %s; GTOK sent %d (answers %d, opted out %d), heard %d (invalid %d)"):format(
			tokens, key and self:OwnCount(key) or 0, self:Sharing() and "on" or "off", c.sent, c.replies, c.optedOut,
			c.heard, c.invalid),
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------------------------------------
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(msg, sender, dist) Stats:OnMessage(msg, sender, dist) end)
	ns.Bus:On("ROLE_CHANGED", function(...) Stats:OnRoleChanged(...) end)
end
if ns.addon then
	ns.addon.Stats = Stats
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Stats", function() return Stats:DebugLines() end) end
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if AceEvent then
		AceEvent:Embed(Stats)
		Stats:RegisterEvent("GUILD_ROSTER_UPDATE", function() Stats:Invalidate() end)
	end
end
