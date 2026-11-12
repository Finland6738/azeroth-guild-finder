-- Inbox: the applications an officer or the Guild Master received (SPEC-07 §3-§4, SPEC-01 §6). Lua 5.1.
--
-- M4.2 needs only a minimal store: Net/Delivery.lua hands it every valid APPLY and APPWD that reaches this character
-- and answers with the state it keeps. M4.3 adds the APPSYNC over OFFICER, the 30-day history, the cleanup when the
-- officer role is lost; M4.4 the panel. Until then this module only keeps the records, safely:
--
--   Inbox:Receive(rec)            a new application (already validated, state "received") -> stored record, isNew
--                                 (or nil, "full"). An id already known keeps its stored state (a repeated APPLY
--                                 after a lost APPACK is answered with what the officer has). An older open
--                                 application of the same character is closed as withdrawn: APP-02 allows one.
--   Inbox:Withdraw(k, id, who)    APPWD: an open record becomes withdrawn; an unknown id leaves a withdrawn tombstone
--                                 (`tomb = true`) so a late copy and the officers' sync (M4.3) know it is over.
--   Inbox:Get(k, id), Inbox:List(k), Inbox:Count(k)
--
-- Storage: AzerothGuildFinderCharDB.officerInbox[guildKey] = { recs = { [id] = record } } (per character, SPEC-01 §6),
-- record = the fields of SPEC-03 §8 plus `upd` (time of the last change). At most Config.LIMITS.APPLICATIONS_PER_INBOX
-- records per guild: when full the oldest closed record goes; with every record open a new one is refused.
-- Bus: INBOX_CHANGED(k, id, state, oldState) for every new or changed record.
local ADDON_NAME, ns = ...
ns = ns or {}
local Inbox = {}
ns.Inbox, ns.modules = Inbox, ns.modules or {}
ns.modules.Inbox = Inbox

local type, pairs = type, pairs

local function limit()
	local L = ns.Config and ns.Config.LIMITS
	return (L and L.APPLICATIONS_PER_INBOX) or 200
end
local function now() return ns.Compat.ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

-- The applicant's name without the realm, lower case: two records of the same character have the same one.
function Inbox.BaseName(who)
	if type(who) ~= "string" or who == "" then return nil end
	return (who:match("^[^%-]+") or who):lower()
end

-- In memory when there is no saved character table (a test without Config).
local memory = {}

-- The records table of guild k ({ [id] = record }); `create` makes it when missing.
function Inbox:Records(k, create)
	if type(k) ~= "string" then return nil end
	local char = ns.Config and ns.Config.db and ns.Config.db.char
	local root
	if type(char) == "table" then
		if type(char.officerInbox) ~= "table" then
			if not create then return nil end
			char.officerInbox = {}
		end
		root = char.officerInbox
	else
		root = memory
	end
	local box = root[k]
	if type(box) ~= "table" or type(box.recs) ~= "table" then
		if not create then return nil end
		box = { recs = {} }
		root[k] = box
	end
	return box.recs
end

function Inbox:Get(k, id)
	local recs = self:Records(k)
	local rec = recs and recs[id]
	return type(rec) == "table" and rec or nil
end

-- The records of guild k as a list, oldest first.
function Inbox:List(k)
	local out = {}
	for _, rec in pairs(self:Records(k) or {}) do
		if type(rec) == "table" then out[#out + 1] = rec end
	end
	table.sort(out, function(a, b)
		local ta, tb = a.at or 0, b.at or 0
		if ta ~= tb then return ta < tb end
		return tostring(a.id) < tostring(b.id)
	end)
	return out
end

function Inbox:Count(k, onlyOpen)
	local n = 0
	for _, rec in pairs(self:Records(k) or {}) do
		if type(rec) == "table" and (not onlyOpen or ns.Applications.IsOpen(rec)) then n = n + 1 end
	end
	return n
end

-- Makes room for one more record: drops the oldest closed one when the guild has LIMIT records. false: all open.
local function makeRoom(recs)
	local n, oldest = 0, nil
	for _, rec in pairs(recs) do
		n = n + 1
		if not ns.Applications.IsOpen(rec) and (not oldest or (rec.upd or 0) < (oldest.upd or 0)) then oldest = rec end
	end
	if n < limit() then return true end
	if not oldest then return false end
	recs[oldest.id] = nil
	return true
end

local function move(rec, to, at)
	local old = rec.state
	if ns.Applications.Transition(rec, to, at) then
		emit("INBOX_CHANGED", rec.k, rec.id, rec.state, old)
		return true
	end
	return false
end

-- A validated application (state "received"). Returns the stored record and true when it is new, the stored record
-- and false when the id was known, or nil and "full".
function Inbox:Receive(rec)
	local recs = self:Records(rec.k, true)
	local known = recs[rec.id]
	if type(known) == "table" then return known, false end
	if not makeRoom(recs) then return nil, "full" end
	local at, base = now(), Inbox.BaseName(rec.who)
	-- APP-02: one open application per character. An older open one was withdrawn and the APPWD did not reach us.
	for _, other in pairs(recs) do
		if ns.Applications.IsOpen(other) and Inbox.BaseName(other.who) == base and (other.at or 0) <= (rec.at or 0) then
			move(other, "withdrawn", at)
		end
	end
	rec.upd = rec.upd or at
	recs[rec.id] = rec
	emit("INBOX_CHANGED", rec.k, rec.id, rec.state, nil)
	return rec, true
end

-- APPWD from `who` for id. Returns the stored record (its state is the answer), or nil and "full".
function Inbox:Withdraw(k, id, who)
	local recs = self:Records(k, true)
	local rec = recs[id]
	local at = now()
	if type(rec) == "table" then
		if ns.Applications.IsOpen(rec) then move(rec, "withdrawn", at) end
		return rec
	end
	if not makeRoom(recs) then return nil, "full" end
	-- withdrawn before this officer received it: stateRev 3 is at least the applicant's own (sent 1, received 2,
	-- withdrawn 3) so the tombstone wins the officers' sync (M4.3) against a copy that is still "received".
	rec = { id = id, k = k, who = who, state = "withdrawn", stateRev = 3, at = at, upd = at, tomb = true }
	recs[id] = rec
	emit("INBOX_CHANGED", k, id, rec.state, nil)
	return rec
end

function Inbox:Reset() memory = {} end

function Inbox:DebugLines()
	local k = ns.Role and ns.Role:GuildKey()
	if not k or not self:Records(k) then return { "Inbox: empty" } end
	return { ("Inbox: %d record(s) for your guild, %d open"):format(self:Count(k), self:Count(k, true)) }
end

if ns.addon then
	ns.addon.Inbox = Inbox
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Inbox", function() return Inbox:DebugLines() end) end
end
