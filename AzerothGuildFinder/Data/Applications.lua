-- Applications: the applicant's side of an application (SPEC-07 §1–§2 and §7, SPEC-03 §8, ADR 0005). Lua 5.1.
--
-- Rules (SPEC-07 §1):
--   APP-01  only a character without a guild can apply
--   APP-02  at most ONE open application per character (sent or received); withdraw it to apply elsewhere
--   APP-03  Apply needs `apps = true` on the listing and the level and item level requirements met
--   APP-04  one click: name, class, race, level and item level are read from the client; the roles are optional and only
--           those the class can play (Data/Enums.lua CLASS_ROLES); no free text
--   APP-05  an open application expires 14 days after it was sent
--   APP-06  after a decline the same guild can be applied to again only 7 days later
--
-- States (SPEC-07 §2): sent -> received -> accepted | declined; sent | received -> withdrawn | expired. The final states
-- (accepted, declined, withdrawn, expired) never move again. Every change raises `stateRev` by one; the officers' copies
-- (M4.3) keep the record with the highest stateRev, and on a tie the final state in the order accepted > declined >
-- withdrawn > expired (Applications.Newer).
--
-- Everything that decides is a pure function of its arguments (the record, the list, `now`): the tests run it without a
-- client. The module methods below them only read the client (through Compat, Role, Catalog, Transport) and the saved
-- data, and call the pure functions.
--
-- Storage: AzerothGuildFinderCharDB.application = { recs = { record, ... } } (per character, oldest first). A record:
--   id (8 hex), k (guildKey), who ("Name-Realm"), cls, race, lvl, ilvl?, roles? (mask 1..15, only valid roles), at (sent,
--   epoch), state, stateRev, upd (time of the last state change), by? (who decided; the applicant never learns it),
--   wd? (true: a withdrawal still to be delivered to an officer, "Withdrawing..."), unseen? (true: a change the player has
--   not looked at yet, the dot on the My Application tab).
-- Final records are kept 30 days after their last change (the cooldown needs the declines), at most MAX_RECORDS in all.
--
-- Network (M4.2): nothing is sent here. Each record that needs a message is in `Applications:Outbox()` (APPLY for a sent
-- application, APPPING for a received one, APPWD for a withdrawal not yet confirmed) and every new need is announced on
-- the Bus as APPLICATION_OUTBOX(kind, id). An answer from an officer comes back through `Applications:OnAck(id, state)`.
-- Every change of a record is announced as APPLICATION_CHANGED(id, state, oldState).
local ADDON_NAME, ns = ...
ns = ns or {}
local A = {}
ns.Applications, ns.modules = A, ns.modules or {}
ns.modules.Applications = A

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, max, min = math.floor, math.max, math.min
local sort, remove = table.sort, table.remove

local DAY = 86400
A.EXPIRY = 14 * DAY        -- APP-05
A.COOLDOWN = 7 * DAY       -- APP-06
A.HISTORY = 30 * DAY       -- SPEC-07 §2: final states stay 30 days
A.MAX_RECORDS = 20
A.TICK = 3600              -- seconds between two looks for expiry while an application is open

A.STATES = { "sent", "received", "accepted", "declined", "withdrawn", "expired" }
A.OPEN = { sent = true, received = true }
A.FINAL = { accepted = 4, declined = 3, withdrawn = 2, expired = 1 }   -- also the tie order of Newer
A.TRANSITIONS = {
	sent = { received = true, withdrawn = true, expired = true },
	received = { accepted = true, declined = true, withdrawn = true, expired = true },
}

local VALID_STATE = {}
for _, s in ipairs(A.STATES) do VALID_STATE[s] = true end

---------------------------------------------------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------------------------------------------------
function A.IsState(s) return type(s) == "string" and VALID_STATE[s] == true end
function A.IsOpen(rec) return type(rec) == "table" and A.OPEN[rec.state] == true end
function A.IsFinal(state) return A.FINAL[state] ~= nil end

-- true when a record may go from state `from` to state `to` (SPEC-07 §2).
function A.CanMove(from, to)
	local t = A.TRANSITIONS[from]
	return t ~= nil and t[to] == true
end

-- Moves `rec` to `to` at `now`: state, stateRev + 1, upd, and `by` when given. Returns true, or false and the reason
-- ("state": not a state, "same": already there, "final": the record is closed, "invalid": not a step of the diagram).
function A.Transition(rec, to, now, by)
	if not A.IsState(to) then return false, "state" end
	if rec.state == to then return false, "same" end
	if A.IsFinal(rec.state) then return false, "final" end
	if not A.CanMove(rec.state, to) then return false, "invalid" end
	rec.state = to
	rec.stateRev = (tonumber(rec.stateRev) or 0) + 1
	rec.upd = now
	if by ~= nil then rec.by = by end
	return true
end

function A.ExpiresAt(rec) return (rec.at or 0) + A.EXPIRY end

-- APP-05: an open application whose 14 days are over.
function A.IsExpired(rec, now)
	return A.IsOpen(rec) and type(now) == "number" and now >= A.ExpiresAt(rec)
end

-- The roles `classID` can play, as a list of role bits in role order (all four for a class the table does not know).
function A.RolesFor(classID)
	local E = ns.Enums
	return E.RoleList(E.ValidRoles(classID))
end

-- APP-04: the ticked roles kept only when the class can play them; nil when none is left (the roles are optional).
function A.CleanRoles(classID, mask)
	if type(mask) ~= "number" then return nil end
	local E = ns.Enums
	local clean = E.MaskAnd(floor(mask) % 16, E.ValidRoles(classID))
	return clean > 0 and clean or nil
end

-- A new record. player = { name, realm, classID, raceID, level, ilvl }; roles: a mask (optional).
function A.NewRecord(id, k, player, roles, now)
	local rec = {
		id = id, k = k, who = player.realm and (player.name .. "-" .. player.realm) or player.name,
		cls = player.classID, race = player.raceID, lvl = player.level,
		roles = A.CleanRoles(player.classID, roles),
		at = now, state = "sent", stateRev = 1, upd = now,
	}
	if type(player.ilvl) == "number" and player.ilvl > 0 then rec.ilvl = floor(player.ilvl) end
	return rec
end

-- The open record of a list (APP-02 keeps it to one), or nil. With `now`, a record past its 14 days does not count (it is
-- expired even before Sweep has written it down).
function A.OpenOf(recs, now)
	for i = #recs, 1, -1 do
		local rec = recs[i]
		if A.IsOpen(rec) and not (now and A.IsExpired(rec, now)) then return rec end
	end
	return nil
end

-- APP-06: the time until which guild `k` cannot be applied to again (the latest decline plus 7 days), or nil.
function A.CooldownUntil(recs, k, now)
	local untilAt
	for _, rec in ipairs(recs) do
		if rec.k == k and rec.state == "declined" then
			local t = (rec.upd or rec.at or 0) + A.COOLDOWN
			if t > now and (not untilAt or t > untilAt) then untilAt = t end
		end
	end
	return untilAt
end

-- Can the player apply to the listing `sum` now? ctx = { k, sum (the summary, nil when unknown), role ("none" without a
-- guild), player (BrowseModel.Player(): level, ilvl), recs, now, listenOnly, readOnly }.
-- Returns ok, reason, info. Reasons, in the order they are checked (the first that holds wins):
--   "nolisting"    the guild has no listing here
--   "closed"       apps = false: applications through the addon are closed (APP-03)
--   "inguild"      the character is in a guild (APP-01)
--   "applied"      the open application is to this guild           info = the record
--   "elsewhere"    the open application is to another guild (APP-02) info = the record
--   "cooldown"     a decline from this guild less than 7 days ago (APP-06)  info = { untilAt = time }
--   "requirements" a level or item level requirement is known to fail (APP-03)  info = BrowseModel.Requirements
--   "listenonly"   the client cannot send addon messages (SPEC-01 §8)
--   "readonly"     the saved data belongs to a newer addon version and is never rewritten (ADR 0011)
function A.Decide(ctx)
	local sum = ctx.sum
	if type(sum) ~= "table" then return false, "nolisting" end
	if sum.apps ~= true then return false, "closed" end
	if ctx.role ~= nil and ctx.role ~= "none" then return false, "inguild" end
	local open = A.OpenOf(ctx.recs or {}, ctx.now)
	if open and open.k == ctx.k then return false, "applied", open end
	if open then return false, "elsewhere", open end
	local untilAt = A.CooldownUntil(ctx.recs or {}, ctx.k, ctx.now or 0)
	if untilAt then return false, "cooldown", { untilAt = untilAt } end
	local req = ns.BrowseModel.Requirements(sum, ctx.player)
	if req.ok == false then return false, "requirements", req end
	if ctx.listenOnly then return false, "listenonly" end
	if ctx.readOnly then return false, "readonly" end
	return true, "ok"
end

-- The officers' conflict rule (SPEC-07 §4): the record with the higher stateRev; on a tie the final state that ranks
-- higher (accepted > declined > withdrawn > expired); on a full tie the first one.
function A.Newer(a, b)
	if not b then return a end
	if not a then return b end
	local ra, rb = tonumber(a.stateRev) or 0, tonumber(b.stateRev) or 0
	if ra ~= rb then return ra > rb and a or b end
	local fa, fb = A.FINAL[a.state] or 0, A.FINAL[b.state] or 0
	if fb > fa then return b end
	return a
end

-- An answer of an officer (APPACK{id, state}, M4.2) applied to the applicant's record. A decision that reaches a record
-- that is still "sent" passes through "received" (the officer had it; the acknowledgement was lost), so stateRev rises by
-- two. A confirmation of a withdrawal clears `wd`. Returns true when the record changed, or false and the reason.
function A.ApplyAck(rec, state, now)
	if not A.IsState(state) then return false, "state" end
	if rec.state == "withdrawn" then
		if rec.wd and state == "withdrawn" then rec.wd = nil; return true end
		return false, "final"
	end
	if rec.state == state then return false, "same" end
	if rec.state == "sent" and (state == "accepted" or state == "declined") then
		local ok, why = A.Transition(rec, "received", now)
		if not ok then return false, why end
	end
	if state == "sent" then return false, "invalid" end
	return A.Transition(rec, state, now)
end

-- The messages the records need (M4.2 sends them): { kind, id, k } in record order.
function A.OutboxOf(recs)
	local out = {}
	for _, rec in ipairs(recs) do
		if rec.state == "sent" then out[#out + 1] = { kind = "APPLY", id = rec.id, k = rec.k }
		elseif rec.state == "received" then out[#out + 1] = { kind = "APPPING", id = rec.id, k = rec.k }
		elseif rec.state == "withdrawn" and rec.wd then out[#out + 1] = { kind = "APPWD", id = rec.id, k = rec.k } end
	end
	return out
end

-- Drops final records older than HISTORY (from their last change) and keeps at most MAX_RECORDS, the open one always
-- among them. Returns the number dropped.
function A.Prune(recs, now)
	local dropped = 0
	for i = #recs, 1, -1 do
		local rec = recs[i]
		if not A.IsOpen(rec) and (rec.upd or rec.at or 0) + A.HISTORY <= now then
			remove(recs, i)
			dropped = dropped + 1
		end
	end
	while #recs > A.MAX_RECORDS do
		local index
		for i, rec in ipairs(recs) do
			if not A.IsOpen(rec) then index = i break end
		end
		if not index then break end
		remove(recs, index)
		dropped = dropped + 1
	end
	return dropped
end

local function isInt(v, lo, hi)
	return type(v) == "number" and v == floor(v) and v >= lo and (hi == nil or v <= hi)
end

-- A stored record checked field by field: nil when it cannot be used (no id, key, state or times), else the record with
-- the optional fields that are wrong dropped.
function A.Sanitize(rec)
	if type(rec) ~= "table" then return nil end
	if type(rec.id) ~= "string" or not rec.id:find("^%x%x%x%x%x%x%x%x$") then return nil end
	if type(rec.k) ~= "string" or not ns.Listing.ParseKey(rec.k) then return nil end
	if not A.IsState(rec.state) or not isInt(rec.stateRev, 1) or not isInt(rec.at, 0) then return nil end
	local out = { id = rec.id, k = rec.k, state = rec.state, stateRev = rec.stateRev, at = rec.at }
	out.upd = isInt(rec.upd, rec.at) and rec.upd or rec.at
	if type(rec.who) == "string" and #rec.who <= 64 then out.who = rec.who end
	if isInt(rec.cls, 1, 255) then out.cls = rec.cls end
	if isInt(rec.race, 1, 255) then out.race = rec.race end
	if isInt(rec.lvl, 1, 255) then out.lvl = rec.lvl end
	if isInt(rec.ilvl, 1, 9999) then out.ilvl = rec.ilvl end
	if isInt(rec.roles, 1, 15) then out.roles = A.CleanRoles(out.cls, rec.roles) end
	if type(rec.by) == "string" and #rec.by <= 64 then out.by = rec.by end
	if rec.wd == true and out.state == "withdrawn" then out.wd = true end
	if rec.unseen == true then out.unseen = true end
	return out
end

-- Repairs a stored list: bad records dropped, sorted by time sent, at most one open record (the newest; an older open one
-- is closed as withdrawn: it can only come from damaged data). Returns the clean list and the number of fixes.
function A.SanitizeList(list, now)
	local out, fixes = {}, 0
	if type(list) ~= "table" then return out, 1 end
	local seen = {}
	for _, raw in ipairs(list) do
		local rec = A.Sanitize(raw)
		if rec and not seen[rec.id] then
			seen[rec.id] = true
			out[#out + 1] = rec
		else
			fixes = fixes + 1
		end
	end
	sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.id < b.id end)
	local open = A.OpenOf(out)
	for _, rec in ipairs(out) do
		if rec ~= open and A.IsOpen(rec) then
			A.Transition(rec, "withdrawn", now)
			fixes = fixes + 1
		end
	end
	return out, fixes
end

---------------------------------------------------------------------------------------------------------------------
-- The player's own applications (saved per character)
---------------------------------------------------------------------------------------------------------------------
local function now() return ns.Compat.ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

local loadedFor   -- the character table the list was last repaired for (a /reload or a new test client loads again)
A.fixes = 0

-- The saved list, repaired once per load. A character that never applied has no `application` table (nil is the default
-- of SPEC-01 §6): it is created by the first application (`create`), until then an empty list stands in.
function A:Records(create)
	local Config = ns.Config
	local char = Config and Config.db and Config.db.char
	if type(char) ~= "table" then
		A.memory = A.memory or { recs = {} }
		return A.memory.recs
	end
	if type(char.application) ~= "table" then
		if not create then return {} end
		char.application = { recs = {} }
	end
	local store = char.application
	if loadedFor ~= char then
		loadedFor = char
		local fixes
		store.recs, fixes = A.SanitizeList(store.recs, now())
		A.fixes = fixes
		for k in pairs(store) do if k ~= "recs" then store[k] = nil end end
		A.Prune(store.recs, now())
	end
	return store.recs
end

-- Closes what is due: open applications past their 14 days become expired (with the chat line and the dot), old final
-- records are dropped. Returns the number expired.
function A:Sweep(at)
	at = at or now()
	local recs = self:Records()
	local expired = 0
	for _, rec in ipairs(recs) do
		if A.IsExpired(rec, at) then
			local old = rec.state
			if A.Transition(rec, "expired", at) then
				expired = expired + 1
				self:Changed(rec, old, true)
			end
		end
	end
	A.Prune(recs, at)
	return expired
end

function A:Current() self:Sweep() return A.OpenOf(self:Records()) end

-- The record My Application shows: the open one, else the most recent one (a result to read: accepted, declined...).
function A:Latest()
	self:Sweep()
	local recs = self:Records()
	return A.OpenOf(recs) or recs[#recs]
end

function A:Get(id)
	for _, rec in ipairs(self:Records()) do
		if rec.id == id then return rec end
	end
	return nil
end

function A:Outbox() self:Sweep() return A.OutboxOf(self:Records()) end

-- Records with a change the player has not looked at (the dot on the tab).
function A:Unseen()
	local n = 0
	for _, rec in ipairs(self:Records()) do if rec.unseen then n = n + 1 end end
	return n
end

function A:MarkSeen()
	local changed = false
	for _, rec in ipairs(self:Records()) do
		if rec.unseen then rec.unseen = nil; changed = true end
	end
	if changed then emit("APPLICATION_SEEN") end
	return changed
end

-- A record changed. `notify`: the change did not come from the player (an officer's answer, the expiry): the chat line
-- and the dot of SPEC-07 §7.
function A:Changed(rec, oldState, notify)
	if notify then
		rec.unseen = true
		local addon, L = ns.addon, ns.L
		if addon and L then
			local _, _, name = ns.Listing.ParseKey(rec.k)
			addon:Print(L["APP_CHAT_" .. rec.state]:format(name or rec.k))
		end
	end
	emit("APPLICATION_CHANGED", rec.id, rec.state, oldState)
	self:ArmTimer()
end

-- What the client says about the player (APP-04): name, realm, class, race, level, item level.
function A.ReadPlayer()
	local P = ns.Compat.Player
	return { name = P.Name(), realm = P.Realm(), classID = P.ClassID(), raceID = P.RaceID(), level = P.Level(),
		ilvl = P.AverageItemLevel() }
end

-- The context of A.Decide for guild k, read from the client and the catalog.
function A:Context(k)
	local entry, status = nil, nil
	if ns.Catalog and k then entry, status = ns.Catalog:Get(k) end
	local listed = entry and entry.sum and (status == "listed" or status == "inactive")
	local Transport = ns.Transport
	return {
		k = k, sum = listed and entry.sum or nil,
		role = ns.Role and ns.Role:Get() or "none",
		player = ns.BrowseModel and ns.BrowseModel.Player() or {},
		recs = self:Records(), now = now(),
		listenOnly = Transport ~= nil and Transport.IsListenOnly ~= nil and (Transport:IsListenOnly()) == true,
		readOnly = ns.Config ~= nil and ns.Config:IsReadOnly("char"),
	}
end

-- Can the player apply to guild k now? ok, reason, info (see A.Decide). It changes nothing (the buttons call it while
-- they are drawn): an application past its 14 days already counts as closed here.
function A:Check(k)
	return A.Decide(self:Context(k))
end

local function newId(recs, seed)
	local used = {}
	for _, rec in ipairs(recs) do used[rec.id] = true end
	local Normalize = ns.Normalize
	for attempt = 1, 50 do
		local id = Normalize.Hash32Hex(seed .. ":" .. attempt .. ":" .. math.random(0, 2147483646))
		if not used[id] then return id end
	end
	return nil
end

-- Apply (after the confirmation): a new record "sent", saved; the network sends it later (M4.2). roles: optional mask.
-- Returns true and the record, or false and the reason of A.Decide (or "player": the client did not say who we are).
function A:Apply(k, roles)
	self:Sweep()
	local ok, why = self:Check(k)
	if not ok then return false, why end
	local player = A.ReadPlayer()
	if type(player.name) ~= "string" or not player.classID or not player.level then return false, "player" end
	local recs = self:Records(true)
	local at = now()
	local id = newId(recs, tostring(player.name) .. tostring(k) .. at)
	if not id then return false, "player" end
	local rec = A.NewRecord(id, k, player, roles, at)
	recs[#recs + 1] = rec
	A.Prune(recs, at)
	self:Changed(rec, nil, false)
	emit("APPLICATION_OUTBOX", "APPLY", rec.id)
	return true, rec
end

-- Withdraw the open application (SPEC-07 §3.5). The player may apply elsewhere at once; the record shows "Withdrawing..."
-- until an officer confirms (`wd`). Returns true and the record, or false and "none".
function A:Withdraw(id)
	local rec = self:Current()
	if not rec or (id ~= nil and rec.id ~= id) then return false, "none" end
	local old = rec.state
	if not A.Transition(rec, "withdrawn", now()) then return false, "none" end
	rec.wd = true
	self:Changed(rec, old, false)
	emit("APPLICATION_OUTBOX", "APPWD", rec.id)
	return true, rec
end

-- An officer's answer (APPACK, delivered by M4.2). Returns true when the record changed.
function A:OnAck(id, state)
	local rec = self:Get(id)
	if not rec then return false, "unknown" end
	local old = rec.state
	local ok, why = A.ApplyAck(rec, state, now())
	if not ok then return false, why end
	self:Changed(rec, old, old ~= rec.state)
	return true
end

-- While an application is open, look again every TICK seconds (or at its expiry, if sooner).
function A:ArmTimer()
	local rec = A.OpenOf(self:Records())
	if not rec or not (ns.Compat and ns.Compat.After) then return false end
	local gen = (self.timerGen or 0) + 1
	self.timerGen = gen
	local wait = max(1, min(A.TICK, A.ExpiresAt(rec) - now() + 1))
	ns.Compat.After(wait, function()
		if self.timerGen ~= gen then return end
		self:Sweep()
		self:ArmTimer()
	end)
	return true
end

function A:DebugLines()
	local recs = self:Records()
	local open = A.OpenOf(recs)
	local lines = { ("Applications: %d record(s), open: %s, unseen %d, to send %d, repaired %d"):format(#recs,
		open and open.state or "none", self:Unseen(), #A.OutboxOf(recs), A.fixes) }
	return lines
end

if ns.addon then
	ns.addon.Applications = A
	-- Own AceEvent object: the addon object keeps one handler per event and Role already uses PLAYER_ENTERING_WORLD.
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if AceEvent then
		AceEvent:Embed(A)
		A:RegisterEvent("PLAYER_ENTERING_WORLD", function()
			A:Sweep()
			A:ArmTimer()
		end)
	end
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Applications", function() return A:DebugLines() end) end
end
