-- Inbox: the applications an officer or the Guild Master received (SPEC-07 §3-§4, SPEC-01 §6). Lua 5.1.
--
-- Net/Delivery.lua (M4.2) hands it every valid APPLY and APPWD that reaches this character and answers with the state it
-- keeps; Net/InboxSync.lua (M4.3) keeps the copies of the guild's officers in step over APPSYNC; the panel (M4.4) reads
-- it and takes the decisions.
--
--   Inbox:Receive(rec)            a new application (already validated, state "received") -> stored record, isNew
--                                 (or nil, "full"). An id already known keeps its stored state (a repeated APPLY
--                                 after a lost APPACK is answered with what the officer has). An older open
--                                 application of the same character is closed as withdrawn: APP-02 allows one.
--   Inbox:Withdraw(k, id, who)    APPWD: an open record becomes withdrawn; an unknown id leaves a withdrawn tombstone
--                                 (`tomb = true`) so a late copy and the officers' sync know it is over.
--   Inbox:Decide(k, id, state, by)  Invite / Decline of the panel (M4.4): a received record becomes accepted / declined.
--   Inbox:Merge(k, rec)           a record from another officer (APPSYNC, already checked by Inbox.Sanitize): kept when
--                                 it wins (Inbox.Version), else ours stays -> stored, "new" | "newer" | "older" | "same".
--   Inbox:Sweep(now)              APP-05 (open records past 14 days become expired) and the 30-day history.
--   Inbox:Cleanup(keepKey)        deletes every guild's box but keepKey's (the officer role was lost, SPEC-07 §4).
--   Inbox:Get(k, id), Inbox:List(k), Inbox:Count(k, onlyOpen), Inbox:Digest(k)
--
-- Conflicts (SPEC-07 §4): every record has a version, Inbox.Version(rec), a number that orders two copies of the same
-- application the same way on every client. A final state wins over an open one (final states never move, SPEC-07 §2);
-- then the higher stateRev; then the final state that ranks higher (accepted > declined > withdrawn > expired); then a
-- complete record over a tombstone; then a hash of `upd` and `by`, so even two different decisions taken at the same
-- time end the same everywhere. A change that every officer makes by itself (the expiry, APP-02) uses times that come
-- from the record, so every copy ends identical without a message.
--
-- Storage: AzerothGuildFinderCharDB.officerInbox[guildKey] = { recs = { [id] = record } } (per character, SPEC-01 §6),
-- record = the fields of SPEC-03 §8 plus `upd` (time of the last change), `by` (who decided) and `tomb`. Damaged saved
-- records are dropped once per load. At most Config.LIMITS.APPLICATIONS_PER_INBOX records per guild: when full the
-- oldest closed record goes; with every record open a new one is refused.
-- Bus: INBOX_CHANGED(k, id, state, oldState, source) for every new, changed or dropped (state nil) record; source is nil
-- for a change made here (an APPLY, an APPWD, a decision: the sync sends it to the other officers), "sync" for a record
-- learned from another officer, "sweep" for the expiry and the history, "rule" for APP-02 applied to a synced record.
-- INBOX_CLEARED(k) when a box was deleted.
local ADDON_NAME, ns = ...
ns = ns or {}
local Inbox = {}
ns.Inbox, ns.modules = Inbox, ns.modules or {}
ns.modules.Inbox = Inbox

local type, pairs, tostring, tonumber = type, pairs, tostring, tonumber
local floor, max = math.floor, math.max

Inbox.MAX_REV = 15      -- a stateRev above this is damaged or forged (the real ones are 2 and 3)
Inbox.SKEW = 300        -- a time this far in the future is still taken (clock differences between clients)
Inbox.TIE_BITS = 8388608   -- 2^23: room for the tie-break hash in a version

local function limit()
	local L = ns.Config and ns.Config.LIMITS
	return (L and L.APPLICATIONS_PER_INBOX) or 200
end
local function now() return ns.Compat.ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function A() return ns.Applications end

-- The applicant's name without the realm, lower case: two records of the same character have the same one.
function Inbox.BaseName(who)
	if type(who) ~= "string" or who == "" then return nil end
	return (who:match("^[^%-]+") or who):lower()
end

---------------------------------------------------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------------------------------------------------
local function isInt(v, lo, hi)
	return type(v) == "number" and v == floor(v) and v >= lo and (hi == nil or v <= hi)
end

-- The fields of the application itself: the same in every copy of an id (they come from the applicant's APPLY).
Inbox.APP_FIELDS = { "who", "cls", "race", "lvl", "ilvl", "roles", "at" }

-- The version of a record (see the header). Two copies with the same version are the same record.
function Inbox.Version(rec)
	local final = A().FINAL[rec.state]
	local rev = tonumber(rec.stateRev) or 0
	if rev > Inbox.MAX_REV then rev = Inbox.MAX_REV end
	local hi = (((final and 1 or 0) * 16 + rev) * 8 + (final or 0)) * 2 + (rec.tomb and 0 or 1)
	local tie = ns.Normalize.Hash32(tostring(rec.upd or 0) .. "#" .. tostring(rec.by or "")) % Inbox.TIE_BITS
	return hi * Inbox.TIE_BITS + tie
end

-- The copy that wins of two copies of the same application (a when they are equal).
function Inbox.Wins(a, b)
	if not b then return a end
	if not a then return b end
	return Inbox.Version(b) > Inbox.Version(a) and b or a
end

-- Copies the application's fields from `from` into the tombstone `into` (a withdrawal that arrived before the
-- application, completed by another officer's copy). Returns true when `into` changed.
function Inbox.Fill(into, from)
	if not into.tomb or from.tomb or from.cls == nil then return false end
	for _, f in ipairs(Inbox.APP_FIELDS) do into[f] = from[f] end
	into.tomb = nil
	return true
end

-- A record checked field by field (INT-06), from another officer's APPSYNC (with `at`, the server time: times in the
-- future and history already over are refused) or from the saved data (`at` nil). Returns a clean copy for guild k, or
-- nil and the reason: "shape", "id", "state", "rev", "time", "who", "class", "race", "level", "tomb", "old".
-- Optional fields that are wrong are dropped (item level, roles not of the class, by).
function Inbox.Sanitize(raw, k, at)
	local Apps, D = A(), ns.Delivery
	if type(raw) ~= "table" then return nil, "shape" end
	if type(raw.id) ~= "string" or #raw.id ~= 8 or not raw.id:find("^[0-9a-f]+$") then return nil, "id" end
	-- an officer never has a "sent" record: the applicant's copy is sent until an officer has it
	if not Apps.IsState(raw.state) or raw.state == "sent" then return nil, "state" end
	if not isInt(raw.stateRev, 2, Inbox.MAX_REV) then return nil, "rev" end
	local skew = at and (at + Inbox.SKEW) or nil
	if not isInt(raw.at, 1, skew) or not isInt(raw.upd, 1, skew) then return nil, "time" end
	if not D.IsName(raw.who) then return nil, "who" end
	local rec = { id = raw.id, k = k, state = raw.state, stateRev = raw.stateRev, at = raw.at, upd = raw.upd, who = raw.who }
	if raw.tomb == true then
		if raw.state ~= "withdrawn" then return nil, "tomb" end
		rec.tomb = true
	else
		if not isInt(raw.cls, 1, 255) or not ns.Enums.CLASS_ROLES[raw.cls] then return nil, "class" end
		if not isInt(raw.race, 1, 255) then return nil, "race" end
		if not isInt(raw.lvl, 1, 255) then return nil, "level" end
		rec.cls, rec.race, rec.lvl = raw.cls, raw.race, raw.lvl
		if isInt(raw.ilvl, 1, 9999) then rec.ilvl = raw.ilvl end
		if isInt(raw.roles, 1, 15) then rec.roles = Apps.CleanRoles(raw.cls, raw.roles) end
	end
	if raw.by ~= nil and D.IsName(raw.by) then rec.by = raw.by end
	if rec.upd < rec.at then rec.upd = rec.at end
	-- a closed record whose 30 days of history are over is not taken back
	if at and Apps.IsFinal(rec.state) and rec.upd + Apps.HISTORY <= at then return nil, "old" end
	return rec
end

-- The record as it travels in an APPSYNC (the guild key is the message's).
function Inbox.Wire(rec)
	return { id = rec.id, state = rec.state, stateRev = rec.stateRev, at = rec.at, upd = rec.upd, who = rec.who,
		cls = rec.cls, race = rec.race, lvl = rec.lvl, ilvl = rec.ilvl, roles = rec.roles, by = rec.by,
		tomb = rec.tomb or nil }
end

---------------------------------------------------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------------------------------------------------
-- In memory when there is no saved character table (a test without Config).
local memory = {}
local repairedFor   -- the character table the boxes were last repaired for (a /reload loads them again)
Inbox.fixes = 0

local function enforceLimit(recs)
	local list = {}
	for _, rec in pairs(recs) do list[#list + 1] = rec end
	local over = #list - limit()
	if over <= 0 then return 0 end
	table.sort(list, function(a, b) return (a.upd or 0) < (b.upd or 0) end)
	local dropped = 0
	for _, rec in ipairs(list) do
		if dropped >= over then break end
		if not A().IsOpen(rec) then recs[rec.id] = nil dropped = dropped + 1 end
	end
	return dropped
end

-- Drops what the saved data cannot be trusted with: boxes that are not tables or not of a guild key, records that do
-- not pass Inbox.Sanitize or are filed under another id; then the limit.
local function repair(root)
	local fixes = 0
	for k, box in pairs(root) do
		if type(k) ~= "string" or not ns.Listing.ParseKey(k) or type(box) ~= "table" or type(box.recs) ~= "table" then
			root[k] = nil
			fixes = fixes + 1
		else
			for key in pairs(box) do if key ~= "recs" then box[key] = nil end end
			local clean = {}
			for id, raw in pairs(box.recs) do
				local rec = Inbox.Sanitize(raw, k)
				if rec and rec.id == id then
					clean[id] = rec
				else
					fixes = fixes + 1
				end
			end
			fixes = fixes + enforceLimit(clean)
			box.recs = clean
		end
	end
	return fixes
end

-- The root table { [guildKey] = box }; nil when there is none and `create` is not set.
local function root(create)
	local char = ns.Config and ns.Config.db and ns.Config.db.char
	if type(char) ~= "table" then return memory end
	if type(char.officerInbox) ~= "table" then
		if not create then return nil end
		char.officerInbox = {}
	end
	if repairedFor ~= char then
		repairedFor = char
		Inbox.fixes = repair(char.officerInbox)
	end
	return char.officerInbox
end

-- The records table of guild k ({ [id] = record }); `create` makes it when missing.
function Inbox:Records(k, create)
	if type(k) ~= "string" then return nil end
	local r = root(create)
	if not r then return nil end
	local box = r[k]
	if type(box) ~= "table" or type(box.recs) ~= "table" then
		if not create then return nil end
		box = { recs = {} }
		r[k] = box
	end
	return box.recs
end

-- The guild keys that have a box.
function Inbox:Keys()
	local out = {}
	for k in pairs(root(false) or {}) do out[#out + 1] = k end
	table.sort(out)
	return out
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
		if type(rec) == "table" and (not onlyOpen or A().IsOpen(rec)) then n = n + 1 end
	end
	return n
end

-- The compact list of SPEC-07 §4: { [id] = version } of every record of guild k.
function Inbox:Digest(k)
	local out = {}
	for id, rec in pairs(self:Records(k) or {}) do out[id] = Inbox.Version(rec) end
	return out
end

-- true when one more record fits, or when a closed record older (by its last change) than `newer` can make room.
-- `newer` nil: any closed record. Drops it when `take` is set.
local function makeRoom(recs, newer, take)
	local n, oldest = 0, nil
	for _, rec in pairs(recs) do
		n = n + 1
		if not A().IsOpen(rec) and (not oldest or (rec.upd or 0) < (oldest.upd or 0)) then oldest = rec end
	end
	if n < limit() then return true end
	if not oldest then return false end
	if newer and A().IsFinal(newer.state) and (newer.upd or 0) <= (oldest.upd or 0) then return false end
	if take then recs[oldest.id] = nil emit("INBOX_CHANGED", oldest.k, oldest.id, nil, oldest.state, "limit") end
	return true
end
function Inbox:HasRoom(k, rec)
	local recs = self:Records(k)
	return not recs or makeRoom(recs, rec, false)
end

local function move(rec, to, at, source, by)
	local old = rec.state
	if A().Transition(rec, to, at, by) then
		emit("INBOX_CHANGED", rec.k, rec.id, rec.state, old, source)
		return true
	end
	return false
end

-- APP-02: the open records of the same character that are older than `rec` are closed as withdrawn, at the time of
-- `rec` (the same on every officer's client); an open `rec` older than an open one of the same character is closed.
local function oneOpen(recs, rec, source)
	if not A().IsOpen(rec) then return end
	local base = Inbox.BaseName(rec.who)
	for _, other in pairs(recs) do
		if other ~= rec and A().IsOpen(other) and Inbox.BaseName(other.who) == base then
			local older, newer = other, rec
			if (other.at or 0) > (rec.at or 0) or ((other.at or 0) == (rec.at or 0) and other.id > rec.id) then
				older, newer = rec, other
			end
			move(older, "withdrawn", max(older.upd or 0, newer.at or 0), source)
			if older == rec then return end
		end
	end
end

-- A validated application (state "received"). Returns the stored record and true when it is new, the stored record
-- and false when the id was known, or nil and "full".
function Inbox:Receive(rec)
	local recs = self:Records(rec.k, true)
	local known = recs[rec.id]
	if type(known) == "table" then return known, false end
	if not makeRoom(recs, nil, true) then return nil, "full" end
	rec.upd = rec.upd or now()
	recs[rec.id] = rec
	oneOpen(recs, rec, nil)
	emit("INBOX_CHANGED", rec.k, rec.id, rec.state, nil)
	return rec, true
end

-- APPWD from `who` for id. Returns the stored record (its state is the answer), or nil and "full".
function Inbox:Withdraw(k, id, who)
	local recs = self:Records(k, true)
	local rec = recs[id]
	local at = now()
	if type(rec) == "table" then
		if A().IsOpen(rec) then move(rec, "withdrawn", at) end
		return rec
	end
	if not makeRoom(recs, nil, true) then return nil, "full" end
	-- withdrawn before this officer received it: stateRev 3 is at least the applicant's own (sent 1, received 2,
	-- withdrawn 3) and a final state wins over the copies that are still "received" (Inbox.Version).
	rec = { id = id, k = k, who = who, state = "withdrawn", stateRev = 3, at = at, upd = at, tomb = true }
	recs[id] = rec
	emit("INBOX_CHANGED", k, id, rec.state, nil)
	return rec
end

-- Invite (accepted) or Decline (declined) of a received record, by the officer `by`. Returns true, or false and the
-- reason: "unknown", "state" (not accepted / declined), or the reason of Applications.Transition.
function Inbox:Decide(k, id, state, by)
	if state ~= "accepted" and state ~= "declined" then return false, "state" end
	local rec = self:Get(k, id)
	if not rec then return false, "unknown" end
	local old = rec.state
	local ok, why = A().Transition(rec, state, now(), by)
	if not ok then return false, why end
	emit("INBOX_CHANGED", k, id, rec.state, old)
	return true
end

-- A record of guild k from another officer, already checked by Inbox.Sanitize. Returns the stored record and what
-- happened: "new", "newer" (it replaced ours), "older" (ours wins: the sender should learn it), "same"; or nil, "full".
function Inbox:Merge(k, rec)
	local recs = self:Records(k, true)
	rec.k = k
	local known = recs[rec.id]
	if type(known) ~= "table" then
		if not makeRoom(recs, rec, true) then return nil, "full" end
		recs[rec.id] = rec
		emit("INBOX_CHANGED", k, rec.id, rec.state, nil, "sync")
		oneOpen(recs, rec, "rule")
		return rec, "new"
	end
	local vk, vr = Inbox.Version(known), Inbox.Version(rec)
	if vr > vk then
		Inbox.Fill(rec, known)
		recs[rec.id] = rec
		emit("INBOX_CHANGED", k, rec.id, rec.state, known.state, "sync")
		oneOpen(recs, rec, "rule")
		-- a tombstone completed with our fields is newer than what was sent: the sender should learn it
		return rec, Inbox.Version(rec) > vr and "older" or "newer"
	end
	if vr < vk then
		if Inbox.Fill(known, rec) then emit("INBOX_CHANGED", k, known.id, known.state, known.state, "sync") end
		return known, "older"
	end
	return known, "same"
end

-- APP-05 and the history (SPEC-07 §2): an open record past its 14 days becomes expired, at the moment it expired (the
-- same on every officer's client); a closed record whose last change is 30 days old is dropped. Returns expired,
-- dropped.
function Inbox:Sweep(at)
	at = at or now()
	local Apps = A()
	local expired, dropped = 0, 0
	for k, box in pairs(root(false) or {}) do
		for id, rec in pairs(box.recs) do
			if Apps.IsExpired(rec, at) then
				if move(rec, "expired", max(rec.upd or 0, Apps.ExpiresAt(rec)), "sweep") then expired = expired + 1 end
			end
			if not Apps.IsOpen(rec) and (rec.upd or 0) + Apps.HISTORY <= at then
				box.recs[id] = nil
				dropped = dropped + 1
				emit("INBOX_CHANGED", k, id, nil, rec.state, "sweep")
			end
		end
	end
	return expired, dropped
end

-- SPEC-07 §4: a character that is no longer the Guild Master or an officer deletes its box at the next login. Every
-- box but keepKey's goes (keepKey nil: all). Returns the number of boxes deleted.
function Inbox:Cleanup(keepKey)
	local r = root(false)
	if not r then return 0 end
	local n = 0
	for k in pairs(r) do
		if k ~= keepKey then
			r[k] = nil
			n = n + 1
			emit("INBOX_CLEARED", k)
		end
	end
	return n
end

function Inbox:Reset() memory = {} repairedFor = nil Inbox.fixes = 0 end

function Inbox:DebugLines()
	local k = ns.Role and ns.Role:GuildKey()
	local keys = #self:Keys()
	if not k or not self:Records(k) then return { ("Inbox: empty (%d box(es), repaired %d)"):format(keys, Inbox.fixes) } end
	return { ("Inbox: %d record(s) for your guild, %d open, %d box(es), repaired %d"):format(self:Count(k),
		self:Count(k, true), keys, Inbox.fixes) }
end

if ns.addon then
	ns.addon.Inbox = Inbox
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Inbox", function() return Inbox:DebugLines() end) end
end
