-- InboxSync: the officers' copies of the applications kept in step (SPEC-07 §4, SPEC-02 §3, §7). Lua 5.1.
--
-- Every Guild Master or officer has its own inbox (Data/Inbox.lua, per character). They talk with APPSYNC on the
-- OFFICER distribution (NORMAL priority), which the server delivers only to the ranks that read officer chat:
--
--   change   a record this client changed (an APPLY received, an APPWD, a decision of the panel) goes out by itself
--            BATCH_DELAY seconds later, with the other changes of that moment: APPSYNC{k, recs = { record, ... }}.
--   login    LOGIN_DELAY seconds after the client entered the world (and when the character becomes an officer):
--            APPSYNC{k, q = 1, ids = { [id] = version }}, the compact list of SPEC-07 §4 (Inbox.Version: a number,
--            so a decision taken at the same stateRev is told apart too).
--   reply    whoever hears a list answers APPSYNC{k, to = asker, ids = { [id] = version }} with only the ids where
--            its copy differs (0: it has none). The asker gathers the replies for COLLECT seconds, then sends the
--            records the others lack or have older (APPSYNC{k, recs}: once, on OFFICER, every officer hears them) and
--            asks each record it lacks from ONE officer, the one with the newest copy (APPSYNC{k, to, want = {id..}});
--            that officer sends them. Two officers online never send the same records twice.
--   merge    every record that arrives is checked field by field (Inbox.Sanitize, INT-06) and merged (Inbox:Merge):
--            the newer copy wins on both sides; when ours is newer it is sent back, so the two copies end equal.
--   limits   at most PER_MSG records per message and one such message per PACE seconds, SEND_MAX messages per
--            SEND_WINDOW seconds from this module (the rest waits), a list of the same sender answered at most once per
--            ANSWER_GAP seconds and a request once per WANT_GAP; a record sent back waits ANSWER_DELAY seconds and is
--            dropped when another officer sends a copy as new meanwhile; Transport adds
--            NET-03 / NET-04. A message with more than MAX_IDS ids or MAX_RECS records is not read further.
--   role     only the Guild Master and the officers of the guild in the message take part (Core/Role.lua): a character
--            that lost the role stops at once, and CLEANUP_DELAY seconds after its next login its box is deleted
--            (SPEC-07 §4), as is the box of any other guild.
--   fallback if spike S5 (M0.4) shows that OFFICER does not work for addon messages, DIST becomes "GUILD" (SPEC-02 §7):
--            the messages then reach every member, the members ignore them (not a contact), and a GUILD message
--            counts only when the roster says its sender's rank reads officer chat. OFFICER messages are always taken.
--
-- Names stay in memory only (the answer limits) and are never printed. Bus: INBOX_SYNC(what) after a list was sent
-- ("digest") or a message was merged ("merged").
local ADDON_NAME, ns = ...
ns = ns or {}
local InboxSync = {}
ns.InboxSync, ns.modules = InboxSync, ns.modules or {}
ns.modules.InboxSync = InboxSync

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor, min, random = math.floor, math.min, math.random

---------------------------------------------------------------------------------------------------------------------
-- Constants (read on use: tests may change them)
---------------------------------------------------------------------------------------------------------------------
InboxSync.AUTO = true                -- the list at login and the changes go out by themselves (tests switch it)
InboxSync.DIST = "OFFICER"           -- "GUILD": the fallback of SPEC-02 §7 if spike S5 fails
InboxSync.LOGIN_DELAY = { 5, 15 }    -- after entering the world: the guild and the roster are known by then
InboxSync.BATCH_DELAY = 2            -- the changes of a moment travel together
InboxSync.ANSWER_DELAY = { 1, 4 }    -- an answer waits this long; another officer's answer may make it void
InboxSync.PER_MSG = 10               -- records per message
InboxSync.SEND_MAX = 10              -- messages per SEND_WINDOW seconds
InboxSync.SEND_WINDOW = 60
InboxSync.PACE = 1.5                 -- seconds between two messages of records: another officer's answer is heard first
InboxSync.ANSWER_GAP = 60            -- a sender's list answered at most once in this time
InboxSync.WANT_GAP = 10              -- a sender's request answered at most once in this time
InboxSync.COLLECT = 5                -- the replies to our list are gathered this long before asking
InboxSync.CLEANUP_DELAY = 60         -- after the login: the role is known for sure
InboxSync.TICK = 3600                -- the expiry and the history are looked at every hour
InboxSync.MAX_IDS = 400
InboxSync.MAX_RECS = 50

---------------------------------------------------------------------------------------------------------------------
-- State (memory only)
---------------------------------------------------------------------------------------------------------------------
local state
local function newStats()
	return {
		sent = 0, sentRecs = 0, digests = 0, replies = 0, wants = 0, refused = 0, deferred = 0,
		received = 0, merged = { new = 0, newer = 0, older = 0, same = 0, full = 0 }, rejected = 0, rejectedBy = {},
		notMine = 0, answered = 0, answersLimited = 0, suppressed = 0, cleaned = 0, expired = 0, dropped = 0,
	}
end
local function resetState()
	state = {
		started = false,
		lastRecsAt = nil,    -- Now() of the last message of records
		dirty = {},          -- [k] = { [id] = due Now() }: records to send
		control = {},        -- messages waiting for the budget (lists, requests)
		sendLog = {},        -- Now() of the messages of the last SEND_WINDOW
		answered = {},       -- [base .. "#q" | "#w"] = Now() of the last answer to that sender
		collect = nil,       -- the replies to our list being gathered: { k, cand = { [id] = { v, base, name } } }
		requested = {},      -- [id] = the version asked for (asked once)
		timerAt = nil,       -- Now() the pump timer fires
		gen = 0,
		stats = newStats(),
	}
	InboxSync.state = state
end
resetState()

local function C() return ns.Compat end
local function now() return C().Now() end
local function clock() return C().ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function baseName(name) return ns.Delivery.BaseName(name) end
local function isSelf(sender)
	local mine = C().Player.Name()
	return mine ~= nil and baseName(sender) == mine:lower()
end
local function randomIn(range) return range[1] + random() * (range[2] - range[1]) end

-- The guild key when this character is the Guild Master or an officer of it, else nil.
local function myKey()
	local Role = ns.Role
	if not Role then return nil end
	local role, k = Role:Get(), Role:GuildKey()
	if (role == "gm" or role == "officer") and k then return k end
	return nil
end
InboxSync.MyKey = myKey

local function isInt(v, lo, hi)
	return type(v) == "number" and v == floor(v) and v >= lo and (hi == nil or v <= hi)
end

---------------------------------------------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------------------------------------------
local pump   -- forward

local function prune(log, t, window)
	local keep = 1
	for i = 1, #log do
		if t - log[i] < window then log[keep] = log[i] keep = keep + 1 end
	end
	for i = #log, keep, -1 do log[i] = nil end
end

-- Runs pump at Now() = `at` (the earliest wanted time wins).
local function armPump(at)
	if state.timerAt and state.timerAt <= at then return end
	state.gen = state.gen + 1
	local gen = state.gen
	state.timerAt = at
	C().After(math.max(0, at - now()) + 0.01, function()
		if state.gen ~= gen then return end
		state.timerAt = nil
		pump()
	end)
end

local function hasBudget(t)
	prune(state.sendLog, t, InboxSync.SEND_WINDOW)
	return #state.sendLog < InboxSync.SEND_MAX
end

local function send(msg)
	local t = now()
	state.sendLog[#state.sendLog + 1] = t
	local item = ns.Transport:Send(InboxSync.DIST, msg, {
		prio = "NORMAL",
		onSent = function() state.stats.sent = state.stats.sent + 1 end,
		onFail = function(reason)
			if reason == "replaced" or reason == "cancelled" then return end
			state.stats.refused = state.stats.refused + 1
			state.lastRefusal = tostring(reason)
		end,
	})
	return item ~= nil
end

-- Marks the record `id` of guild k to be sent at Now() + delay (an earlier due time stays).
local function markDirty(k, id, delay)
	local d = state.dirty[k]
	if not d then d = {} state.dirty[k] = d end
	local due = now() + (delay or 0)
	if not d[id] or d[id] > due then d[id] = due end
	armPump(d[id])
end

-- Sends what is due within the budget; arms itself again for what waits.
pump = function()
	if not ns.Transport then return 0 end
	local t, sent = now(), 0
	local k = myKey()
	for key in pairs(state.dirty) do
		if key ~= k then state.dirty[key] = nil end   -- not ours any more (the role changed)
	end
	if not k then state.control = {} return 0 end
	-- lists and requests first: they are small and they start the exchange
	while #state.control > 0 do
		local msg = state.control[1]
		if msg.k ~= k then
			table.remove(state.control, 1)
		elseif hasBudget(t) then
			table.remove(state.control, 1)
			if send(msg) then sent = sent + 1 end
		else
			break
		end
	end
	local d = state.dirty[k]
	local nextAt
	if d then
		local due = {}
		for id, at in pairs(d) do
			if at <= t then due[#due + 1] = id elseif not nextAt or at < nextAt then nextAt = at end
		end
		table.sort(due)
		local i = 1
		while i <= #due do
			if not hasBudget(t) then
				state.stats.deferred = state.stats.deferred + 1
				break
			end
			-- one message of records per PACE: the rest is looked at again then (it may have been heard meanwhile)
			if state.lastRecsAt and t - state.lastRecsAt < InboxSync.PACE then
				local at = state.lastRecsAt + InboxSync.PACE
				if not nextAt or at < nextAt then nextAt = at end
				break
			end
			local recs = {}
			while i <= #due and #recs < InboxSync.PER_MSG do
				local id = due[i]
				d[id] = nil
				local rec = ns.Inbox:Get(k, id)
				if rec then recs[#recs + 1] = ns.Inbox.Wire(rec) end
				i = i + 1
			end
			if #recs > 0 and send({ t = "APPSYNC", k = k, recs = recs }) then
				state.lastRecsAt = t
				sent = sent + 1
				state.stats.sentRecs = state.stats.sentRecs + #recs
			end
		end
		if next(d) == nil then state.dirty[k] = nil end
	end
	-- something still waits for the budget: when the oldest message leaves the window
	if #state.control > 0 or (state.dirty[k] and (not nextAt or #state.sendLog >= InboxSync.SEND_MAX)) then
		local free = state.sendLog[1] and (state.sendLog[1] + InboxSync.SEND_WINDOW) or t
		if nextAt then nextAt = math.max(nextAt, free) else nextAt = free end
	end
	if nextAt then armPump(nextAt) end
	return sent
end

function InboxSync:Pump() return pump() end

-- The compact list (SPEC-07 §4). Returns true when it was queued.
function InboxSync:SendDigest()
	local k = myKey()
	if not k or not ns.Transport then return false end
	local expired, dropped = ns.Inbox:Sweep()
	state.stats.expired, state.stats.dropped = state.stats.expired + expired, state.stats.dropped + dropped
	state.requested = {}
	state.control[#state.control + 1] = { t = "APPSYNC", k = k, q = 1, ids = ns.Inbox:Digest(k) }
	state.stats.digests = state.stats.digests + 1
	pump()
	emit("INBOX_SYNC", "digest")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------------------------------------------------
local function reject(reason)
	local s = state.stats
	s.rejected = s.rejected + 1
	s.rejectedBy[reason] = (s.rejectedBy[reason] or 0) + 1
	return false, reason
end

-- OFFICER is always taken; GUILD only under the fallback and from a rank that reads officer chat.
local function distOk(dist, sender)
	if dist == "OFFICER" then return true end
	if dist ~= "GUILD" or InboxSync.DIST ~= "GUILD" then return false, "dist" end
	local G = C().Guild
	local rank = G.MemberRankIndex(sender)
	if rank == nil then G.RequestRoster() end   -- not in the roster we know: ask for a fresh one for the next message
	if G.RankIsOfficer(rank) == true then return true end
	return false, "rank"
end

-- One answer per sender and kind per `gap` seconds.
local function mayAnswer(sender, kind, gap)
	local key, t = baseName(sender) .. "#" .. kind, now()
	local last = state.answered[key]
	if last and t - last < gap then
		state.stats.answersLimited = state.stats.answersLimited + 1
		return false
	end
	state.answered[key] = t
	state.stats.answered = state.stats.answered + 1
	return true
end

-- A list `ids` checked: a table of at most MAX_IDS entries, id -> a version. nil and the reason otherwise.
local function checkIds(ids)
	if type(ids) ~= "table" then return nil, "ids" end
	local n = 0
	for id, v in pairs(ids) do
		n = n + 1
		if n > InboxSync.MAX_IDS then return nil, "toomany" end
		if not ns.Delivery.IsId(id) or not isInt(v, 0, 4294967295) then return nil, "ids" end
	end
	return ids
end

local function checkWant(want)
	if type(want) ~= "table" then return nil, "want" end
	local n = 0
	for key, id in pairs(want) do
		n = n + 1
		if n > InboxSync.MAX_IDS then return nil, "toomany" end
		if not isInt(key, 1, InboxSync.MAX_IDS) or not ns.Delivery.IsId(id) then return nil, "want" end
	end
	return want
end

local function onRecords(k, recs)
	if type(recs) ~= "table" then return reject("recs") end
	local Inbox, t, merged = ns.Inbox, clock(), 0
	local d = state.dirty[k]
	for i = 1, min(#recs, InboxSync.MAX_RECS) do
		local rec, why = Inbox.Sanitize(recs[i], k, t)
		if not rec then
			reject(why)
		else
			local stored, what = Inbox:Merge(k, rec)
			what = stored and what or "full"
			state.stats.merged[what] = (state.stats.merged[what] or 0) + 1
			merged = merged + 1
			if what == "older" then
				-- ours is newer: the sender (and whoever has its copy) learns it
				markDirty(k, rec.id, randomIn(InboxSync.ANSWER_DELAY))
			elseif d and d[rec.id] and what ~= "full" then
				-- somebody sent a copy as new as ours: every officer online heard it
				d[rec.id] = nil
				state.stats.suppressed = state.stats.suppressed + 1
			end
		end
	end
	if merged > 0 then emit("INBOX_SYNC", "merged") end
	return true
end

-- A list from an officer that logged in: the reply says, for every id where our copies differ, the version we have
-- (0: none). The asker then sends what we lack and asks for what it lacks, each record from one officer only.
local function onDigest(k, ids, sender)
	local Inbox = ns.Inbox
	if not mayAnswer(sender, "q", InboxSync.ANSWER_GAP) then return true end
	local expired, dropped = Inbox:Sweep()
	state.stats.expired, state.stats.dropped = state.stats.expired + expired, state.stats.dropped + dropped
	local mine, diff, n = Inbox:Digest(k), {}, 0
	for id, v in pairs(mine) do
		if ids[id] ~= v then diff[id] = v n = n + 1 end
	end
	local room = Inbox:HasRoom(k)
	for id in pairs(ids) do
		if not mine[id] and room then diff[id] = 0 n = n + 1 end
	end
	if n > 0 then
		state.control[#state.control + 1] = { t = "APPSYNC", k = k, to = sender, ids = diff }
		state.stats.replies = state.stats.replies + 1
		pump()
	end
	return true
end

-- The wants gathered from the replies to our list: one request per officer, each id from the officer with the best
-- copy (on a tie a hash of the id and the name spreads the work among them).
local function sendWants(k)
	local col = state.collect
	state.collect = nil
	if not col or col.k ~= k or myKey() ~= k then return end
	local per, names = {}, {}
	for id, c in pairs(col.cand) do
		local list = per[c.base]
		if not list then list = {} per[c.base] = list names[c.base] = c.name end
		list[#list + 1] = id
		state.requested[id] = c.v
	end
	for base, list in pairs(per) do
		table.sort(list)
		state.control[#state.control + 1] = { t = "APPSYNC", k = k, to = names[base], want = list }
		state.stats.wants = state.stats.wants + 1
	end
	pump()
end

local function better(c, v, base, id)
	if not c or v > c.v then return true end
	if v < c.v then return false end
	local N = ns.Normalize
	return N.Hash32(id .. "#" .. base) < N.Hash32(id .. "#" .. c.base)
end

-- A reply to our list (`ids`: the sender's version of every id where its copy and ours differ; 0 = it has none).
local function onReply(k, ids, sender)
	local Inbox = ns.Inbox
	local mine, base = Inbox:Digest(k), baseName(sender)
	local col = state.collect
	if not col then
		col = { k = k, cand = {} }
		state.collect = col
		C().After(InboxSync.COLLECT, function() if state.collect == col then sendWants(k) end end)
	end
	local room = Inbox:HasRoom(k)
	local delay = randomIn(InboxSync.ANSWER_DELAY)
	for id, v in pairs(ids) do
		local have = mine[id] or 0
		if v > have and v > (state.requested[id] or 0) and (mine[id] or room) then
			if better(col.cand[id], v, base, id) then col.cand[id] = { v = v, base = base, name = sender } end
		elseif v < have then
			markDirty(k, id, delay)   -- the sender lacks ours or has it older: sent once, every officer hears it
		end
	end
	return true
end

local function onWant(k, want, sender)
	if not mayAnswer(sender, "w", InboxSync.WANT_GAP) then return true end
	for _, id in ipairs(want) do
		if ns.Inbox:Get(k, id) then markDirty(k, id, 0) end
	end
	return true
end

function InboxSync:OnMessage(msg, sender, dist)
	if msg.t ~= "APPSYNC" then return end
	state.stats.received = state.stats.received + 1
	local ok, why = distOk(dist, sender)
	if not ok then return reject(why) end
	if not ns.Delivery.IsName(sender) then return reject("sender") end
	if isSelf(sender) then return false, "self" end   -- the echo of our own message
	local k = myKey()
	if not k or msg.k ~= k then
		state.stats.notMine = state.stats.notMine + 1
		return false, "notmine"
	end
	if msg.recs ~= nil then
		local done, bad = onRecords(k, msg.recs)
		if not done then return false, bad end
	end
	if msg.ids ~= nil or msg.q ~= nil then
		local ids, bad = checkIds(msg.ids)
		if not ids then return reject(bad) end
		if msg.q ~= nil then
			onDigest(k, ids, sender)
		elseif not ns.Delivery.IsName(msg.to) then
			return reject("to")
		elseif isSelf(msg.to) then
			onReply(k, ids, sender)
		end
	end
	if msg.want ~= nil then
		if not ns.Delivery.IsName(msg.to) then return reject("to") end
		local want, bad = checkWant(msg.want)
		if not want then return reject(bad) end
		if isSelf(msg.to) then onWant(k, want, sender) end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
local function armDigest()
	if not InboxSync.AUTO or not myKey() then return false end
	state.digestGen = (state.digestGen or 0) + 1
	local gen = state.digestGen
	C().After(randomIn(InboxSync.LOGIN_DELAY), function()
		if state.digestGen ~= gen then return end
		InboxSync:SendDigest()
	end)
	return true
end

-- SPEC-07 §4: the box of a character that is not (or no longer) a contact goes, and every other guild's box.
function InboxSync:Cleanup()
	if ns.Role then ns.Role:Refresh() end
	local n = ns.Inbox:Cleanup(myKey())
	state.stats.cleaned = state.stats.cleaned + n
	return n
end

-- The hourly look at the expiry and the history, only while some box exists (no timer waits for nothing).
local function armTick()
	if state.tickArmed or #ns.Inbox:Keys() == 0 then return end
	state.tickArmed = true
	C().After(InboxSync.TICK, function()
		state.tickArmed = false
		local expired, dropped = ns.Inbox:Sweep()
		state.stats.expired, state.stats.dropped = state.stats.expired + expired, state.stats.dropped + dropped
		armTick()
	end)
end

-- Entering the world (once per load: a /reload is a new load).
function InboxSync:Start()
	if state.started then return false end
	state.started = true
	if #ns.Inbox:Keys() > 0 then C().After(InboxSync.CLEANUP_DELAY, function() InboxSync:Cleanup() end) end
	armTick()
	armDigest()
	return true
end

function InboxSync:OnInboxChanged(k, id, st, old, source)
	if st ~= nil then armTick() end
	if source ~= nil or not InboxSync.AUTO or myKey() ~= k or st == nil then return end
	markDirty(k, id, InboxSync.BATCH_DELAY)
end

function InboxSync:OnRoleChanged(role, k, oldRole, oldKey)
	local contact = (role == "gm" or role == "officer") and k ~= nil
	local was = (oldRole == "gm" or oldRole == "officer") and oldKey ~= nil
	if not contact then
		state.dirty, state.control = {}, {}
	elseif state.started and (not was or k ~= oldKey) then
		armDigest()
	end
end

function InboxSync:Reset() resetState() end

function InboxSync:DebugLines()
	local s = state.stats
	local reasons = {}
	for r, n in pairs(s.rejectedBy) do reasons[#reasons + 1] = r .. " " .. n end
	table.sort(reasons)
	local m = s.merged
	return {
		("InboxSync: over %s, sent %d (records %d, lists %d, replies %d, requests %d), refused %d%s, deferred %d"):format(
			InboxSync.DIST, s.sent, s.sentRecs, s.digests, s.replies, s.wants, s.refused,
			state.lastRefusal and (" (" .. state.lastRefusal .. ")") or "", s.deferred),
		("  received %d: new %d, newer %d, ours newer %d, same %d, full %d; rejected %d%s; not for us %d; answers %d (limited %d), suppressed %d"):format(
			s.received, m.new, m.newer, m.older, m.same, m.full, s.rejected,
			#reasons > 0 and (" (" .. table.concat(reasons, ", ") .. ")") or "", s.notMine, s.answered,
			s.answersLimited, s.suppressed),
		("  expired %d, history dropped %d, boxes deleted %d"):format(s.expired, s.dropped, s.cleaned),
	}
end

if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(msg, sender, dist) InboxSync:OnMessage(msg, sender, dist) end)
	ns.Bus:On("INBOX_CHANGED", function(...) InboxSync:OnInboxChanged(...) end)
	ns.Bus:On("ROLE_CHANGED", function(...) InboxSync:OnRoleChanged(...) end)
end
if ns.addon then
	ns.addon.InboxSync = InboxSync
	-- Own AceEvent object: the addon object keeps one handler per event and Role already uses PLAYER_ENTERING_WORLD.
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if AceEvent then
		AceEvent:Embed(InboxSync)
		InboxSync:RegisterEvent("PLAYER_ENTERING_WORLD", function() InboxSync:Start() end)
	end
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("InboxSync", function() return InboxSync:DebugLines() end) end
end
