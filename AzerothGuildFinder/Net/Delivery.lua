-- Delivery: applications between the applicant and the guild's contacts, by whisper (SPEC-07 §3, SPEC-02 §3-§4). Lua 5.1.
--
-- Applicant side (the records of Data/Applications.lua):
--   contacts   the Guild Master and the officers heard in an ANN with c = 1 (Net/Sync.lua remembers them in memory)
--              count for CONTACT_TTL seconds (30 minutes, SPEC-07 §3.1), most recent first.
--   jobs       every record of Applications:Outbox() is a job: APPLY for a "sent" record, APPPING for a "received" one,
--              APPWD for a withdrawal not yet confirmed. A job whispers to one contact at a time (ALERT priority) and
--              waits ACK_TIMEOUT seconds (15 s, §3.2) for APPACK{id, state}; then it tries the next contact (at once
--              when the whisper itself failed, e.g. the client says the contact is offline).
--   retries    a job goes out when it is created (Apply, Withdraw) and every time a contact of its guild is heard
--              (CONTACT_SEEN from Sync). A contact that did not answer waits BACKOFF[1] seconds before it is tried
--              again for the same record, twice as long after every silence, at most BACKOFF[2]. A "received"
--              record pings (APPPING) at most once every PING_GAP seconds after an answer, to learn the decision.
--   answers    an APPACK is taken only from a contact this client whispered about that id (anything else is forged
--              or stale) and goes to Applications:OnAck. For a withdrawal any final state confirms it (the
--              officer has closed the record either way).
--   limits     at most SEND_MAX whispers per SEND_WINDOW seconds from this module; Transport adds NET-03 / NET-04.
--   cannot send   when the game refuses our whispers with a code of BLOCKING (or the channel: listen-only, or every
--              addon message: read-only), CannotSend() says why and My Application explains it (SPEC-01 §8); the first
--              whisper that goes out clears it.
--
-- Officer side (the Guild Master and officers of the guild named in the message, Core/Role.lua):
--   APPLY      every field is checked (INT-06, Delivery.ParseApply): the id, the guild key (ours), the applicant (the
--              name must be the whisper's sender), class, race, level, item level, roles (only those of the class),
--              the time (not in the future, not older than 14 days). A valid one goes to the store (Delivery.store,
--              Data/Inbox.lua by default; M4.3 replaces it) and is answered APPACK{id, state}.
--   APPPING    answered with the stored state when the id is known and the sender is its applicant; else silence.
--   APPWD      the stored record becomes withdrawn (an unknown id leaves a tombstone) and is answered "withdrawn"
--              (or its final state).
--   replies    at most REPLY_MAX per sender per REPLY_WINDOW seconds, one per (sender, id, state) per REPLY_GAP.
--
-- Names stay in memory only (jobs, rate limits) and are never printed. Bus events: DELIVERY_CHANGED() when what
-- CannotSend() says changed, APPLICATION_DELIVERED(id, state) when an APPACK was taken.
local ADDON_NAME, ns = ...
ns = ns or {}
local Delivery = {}
ns.Delivery, ns.modules = Delivery, ns.modules or {}
ns.modules.Delivery = Delivery

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, min = math.floor, math.min

---------------------------------------------------------------------------------------------------------------------
-- Constants (every number is read on use, so tests may change them)
---------------------------------------------------------------------------------------------------------------------
Delivery.CONTACT_TTL = 1800      -- SPEC-07 §3.1: a contact heard in the last 30 minutes
Delivery.ACK_TIMEOUT = 15        -- SPEC-07 §3.2: no APPACK in 15 s -> the next contact
Delivery.BACKOFF = { 60, 1800 }  -- a silent contact waits 60 s, doubled after every silence, at most 30 minutes
Delivery.PING_GAP = 1200         -- a "received" record asks for news at most every 20 minutes
Delivery.SEND_MAX = 6            -- applicant: whispers per SEND_WINDOW
Delivery.SEND_WINDOW = 60
Delivery.REPLY_MAX = 6           -- officer: answers per sender per REPLY_WINDOW
Delivery.REPLY_WINDOW = 60
Delivery.REPLY_GAP = 5           -- the same answer to the same sender at most once in this time
Delivery.SKEW = 300              -- an application time this far in the future is still taken (clock differences)
Delivery.MAX_NAME = 64

local KINDS = { APPLY = true, APPPING = true, APPWD = true }
-- Refusals of a whisper that say this character cannot whisper at all (Transport reports the client's code by name; an
-- unknown code comes as its number). TargetOffline, a throttle that ran out of retries, an expiry or a full queue are
-- about one message or one contact, not about the character.
Delivery.BLOCKING = { GeneralError = true, InvalidChatType = true, NotInGroup = true, TargetRequiresGuild = true,
	InvalidChannel = true }

---------------------------------------------------------------------------------------------------------------------
-- State (memory only)
---------------------------------------------------------------------------------------------------------------------
local state
local function newStats()
	return {
		sent = 0, acked = 0, timeouts = 0, refused = 0, ackIgnored = 0, deferred = 0,
		received = 0, rejected = 0, rejectedBy = {}, replies = 0, repliesLimited = 0, notMine = 0, stored = 0,
	}
end
local function resetState()
	state = {
		jobs = {},          -- [id] = { id, k, kind, inflight = { target, gen }, tried = { [base] = { fails, nextAt } },
		                    --          targets = { [base] = true }, lastAckAt }
		sendLog = {},       -- Now() times of the applicant's whispers in the last SEND_WINDOW
		replyLog = {},      -- [base] = { Now() times }
		replyLast = {},     -- [base#id#state] = Now()
		blocked = nil,      -- why the last whisper was refused (nil: none, or a whisper went out since)
		lastCannot = nil,
		gen = 0,
		stats = newStats(),
	}
	Delivery.state = state
end
resetState()

local function C() return ns.Compat end
local function now() return C().Now() end
local function clock() return C().ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

-- "Name" or "Name-Realm" -> "name" (characters are told apart by the name alone, as in Net/Sync.lua).
local function baseName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return (name:match("^[^%-]+") or name):lower()
end
Delivery.BaseName = baseName
local function isSelf(sender)
	local mine = C().Player.Name()
	return mine ~= nil and baseName(sender) == mine:lower()
end

local function store() return Delivery.store or ns.Inbox end

---------------------------------------------------------------------------------------------------------------------
-- Pure checks (INT-06)
---------------------------------------------------------------------------------------------------------------------
local function isInt(v, lo, hi)
	return type(v) == "number" and v == floor(v) and v >= lo and (hi == nil or v <= hi)
end

function Delivery.IsId(id) return type(id) == "string" and id:find("^[0-9a-f]+$") ~= nil and #id == 8 end

-- A character name as it travels: letters of any language, an optional "-Realm"; no spaces, controls or "|".
function Delivery.IsName(who)
	if type(who) ~= "string" or who == "" or #who > Delivery.MAX_NAME then return false end
	if who:find("[%z\1-\32\127|]") then return false end
	return true
end

-- The APPLY `msg` whispered by `sender`, checked field by field (SPEC-03 §8, INT-06) at server time `at`. Returns
-- the record to store (state "received", stateRev 2: the applicant's own record moves sent 1 -> received 2), or nil
-- and the reason: "id", "key", "who", "sender", "class", "race", "level", "time", "old".
function Delivery.ParseApply(msg, sender, at)
	local A, E = ns.Applications, ns.Enums
	if not Delivery.IsId(msg.id) then return nil, "id" end
	if not ns.Listing.ParseKey(msg.k) then return nil, "key" end
	if not Delivery.IsName(msg.who) then return nil, "who" end
	if baseName(msg.who) ~= baseName(sender) then return nil, "sender" end   -- one cannot apply for someone else
	if not isInt(msg.cls, 1, 255) or not E.CLASS_ROLES[msg.cls] then return nil, "class" end
	if not isInt(msg.race, 1, 255) then return nil, "race" end
	local maxLevel = C().Player.MaxLevel and C().Player.MaxLevel()
	if not isInt(msg.lvl, 1, type(maxLevel) == "number" and maxLevel > 0 and maxLevel or 255) then return nil, "level" end
	if not isInt(msg.at, 1) or msg.at > at + Delivery.SKEW then return nil, "time" end
	if msg.at + A.EXPIRY <= at then return nil, "old" end
	local rec = {
		id = msg.id, k = msg.k, who = msg.who, cls = msg.cls, race = msg.race, lvl = msg.lvl, at = msg.at,
		state = "received", stateRev = 2, upd = at,
	}
	if isInt(msg.ilvl, 1, 9999) then rec.ilvl = msg.ilvl end
	if isInt(msg.roles, 1, 15) then rec.roles = A.CleanRoles(msg.cls, msg.roles) end
	return rec
end

-- The message of a job for record `rec` (APPLY carries the record, APPPING and APPWD only the id).
function Delivery.MessageFor(kind, rec)
	if kind == "APPLY" then
		return { t = "APPLY", id = rec.id, k = rec.k, who = rec.who, cls = rec.cls, race = rec.race, lvl = rec.lvl,
			ilvl = rec.ilvl, roles = rec.roles, at = rec.at }
	end
	return { t = kind, id = rec.id }
end

-- The wait after `fails` silences of one contact: BACKOFF[1] doubled every time, at most BACKOFF[2].
function Delivery.Backoff(fails)
	if fails <= 0 then return 0 end
	return min(Delivery.BACKOFF[1] * 2 ^ (fails - 1), Delivery.BACKOFF[2])
end

---------------------------------------------------------------------------------------------------------------------
-- Applicant side
---------------------------------------------------------------------------------------------------------------------
local function prune(log, t, window)
	local keep = 1
	for i = 1, #log do
		if t - log[i] < window then log[keep] = log[i] keep = keep + 1 end
	end
	for i = #log, keep, -1 do log[i] = nil end
end

local function setBlocked(reason)
	if state.blocked == reason then return end
	state.blocked = reason
	Delivery:CheckCannotSend()
end

-- Why the applicant's messages cannot go out now: "restricted" (no addon message at all), "listenonly" (the channel
-- refuses ours), "whisper" (the game refused our last whisper), or nil.
function Delivery:CannotSend()
	local T = ns.Transport
	if T and T.IsReadOnly and T:IsReadOnly() then return "restricted" end
	if state.blocked then return "whisper" end
	if T and T.IsListenOnly and (T:IsListenOnly()) then return "listenonly" end
	return nil
end

function Delivery:CheckCannotSend()
	local why = self:CannotSend()
	if why ~= state.lastCannot then
		state.lastCannot = why
		emit("DELIVERY_CHANGED", why)
	end
end

-- The contacts of guild k to whisper now for `job`: heard in the last CONTACT_TTL seconds, most recent first, not
-- ourselves, not waiting for their backoff.
local function nextContact(job, t)
	if not ns.Sync then return nil end
	for _, name in ipairs(ns.Sync:Contacts(job.k, Delivery.CONTACT_TTL)) do
		local base = baseName(name)
		if base and not isSelf(name) then
			local tr = job.tried[base]
			if not tr or tr.nextAt <= t then return name, base end
		end
	end
	return nil
end

local pump   -- forward

local function finishInflight(job)
	if job.inflight then
		state.gen = state.gen + 1   -- the pending ACK timer is void
		job.inflight = nil
	end
end

local function onSilence(job, base, t)
	local tr = job.tried[base] or { fails = 0, nextAt = 0 }
	tr.fails = tr.fails + 1
	tr.nextAt = t + Delivery.Backoff(tr.fails)
	job.tried[base] = tr
end

local function send(job, rec, target, base)
	local t = now()
	prune(state.sendLog, t, Delivery.SEND_WINDOW)
	if #state.sendLog >= Delivery.SEND_MAX then
		state.stats.deferred = state.stats.deferred + 1
		-- try again when the oldest whisper of the window leaves it
		local wait = Delivery.SEND_WINDOW - (t - state.sendLog[1]) + 0.1
		if not state.deferArmed then
			state.deferArmed = true
			C().After(wait, function() state.deferArmed = false pump() end)
		end
		return false
	end
	state.sendLog[#state.sendLog + 1] = t
	state.gen = state.gen + 1
	local gen = state.gen
	job.inflight = { target = target, base = base, gen = gen, at = t }
	job.targets[base] = true
	local id, kind = job.id, job.kind
	local item = ns.Transport:Send("WHISPER", Delivery.MessageFor(kind, rec), {
		target = target, prio = "ALERT", key = "APP:" .. id,
		onSent = function()
			state.stats.sent = state.stats.sent + 1
			if state.blocked then setBlocked(nil) end
		end,
		onFail = function(reason)
			if reason == "replaced" or reason == "cancelled" then return end
			state.stats.refused = state.stats.refused + 1
			local blocking = Delivery.BLOCKING[reason] or tonumber(reason) ~= nil
			if blocking then setBlocked(tostring(reason)) end
			-- the message did not go: that contact counts as silent now, not in 15 s
			local j = state.jobs[id]
			if j and j.inflight and j.inflight.gen == gen then
				j.inflight = nil
				onSilence(j, base, now())
				if not blocking then pump() end
			end
		end,
	})
	if not item then
		job.inflight = nil
		return false
	end
	C().After(Delivery.ACK_TIMEOUT, function()
		local j = state.jobs[id]
		if not j or not j.inflight or j.inflight.gen ~= gen then return end
		state.stats.timeouts = state.stats.timeouts + 1
		j.inflight = nil
		onSilence(j, base, now())
		pump()
	end)
	return true
end

-- Brings the jobs in line with the outbox and sends what may go now. Returns the number of whispers queued.
pump = function()
	local A = ns.Applications
	if not A or not ns.Transport then return 0 end
	local t, sent = now(), 0
	local wanted = {}
	for _, need in ipairs(A:Outbox()) do
		if KINDS[need.kind] then
			wanted[need.id] = true
			local job = state.jobs[need.id]
			if not job then
				job = { id = need.id, k = need.k, kind = need.kind, tried = {}, targets = {} }
				state.jobs[need.id] = job
			elseif job.kind ~= need.kind then
				-- APPLY answered "received" -> APPPING; a withdrawal -> APPWD: a new message, every contact may be tried
				job.kind, job.tried = need.kind, {}
				finishInflight(job)
			end
			local due = not job.inflight
			if due and job.kind == "APPPING" and job.lastAckAt and t - job.lastAckAt < Delivery.PING_GAP then due = false end
			if due then
				local target, base = nextContact(job, t)
				local rec = target and A:Get(job.id)
				if rec and send(job, rec, target, base) then sent = sent + 1 end
			end
		end
	end
	for id, job in pairs(state.jobs) do
		if not wanted[id] then
			finishInflight(job)
			-- keep it a while: an APPACK still on its way is recognised by `targets`
			if not job.doneAt then job.doneAt = t end
			if t - job.doneAt > 600 then state.jobs[id] = nil end
		end
	end
	return sent
end

function Delivery:Pump() return pump() end

local function onAck(msg, sender)
	local A = ns.Applications
	local job, base = state.jobs[msg.id], baseName(sender)
	if not job or not base or not job.targets[base] or not A.IsState(msg.state) then
		state.stats.ackIgnored = state.stats.ackIgnored + 1
		return false
	end
	local rec = A:Get(msg.id)
	if not rec then
		state.stats.ackIgnored = state.stats.ackIgnored + 1
		return false
	end
	state.stats.acked = state.stats.acked + 1
	if job.inflight and job.inflight.base == base then finishInflight(job) end
	job.tried[base] = nil
	job.lastAckAt = now()
	local ackState = msg.state
	-- a withdrawal is confirmed by any final state: the officer's record is closed either way
	if rec.state == "withdrawn" and rec.wd and A.IsFinal(ackState) then ackState = "withdrawn" end
	A:OnAck(msg.id, ackState)
	emit("APPLICATION_DELIVERED", msg.id, msg.state)
	pump()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Officer side
---------------------------------------------------------------------------------------------------------------------
-- true when this character is a contact of guild k: the Guild Master or an officer of exactly that guild.
local function contactOf(k)
	local Role = ns.Role
	if not Role then return false end
	local role = Role:Get()
	return (role == "gm" or role == "officer") and Role:GuildKey() == k
end

local function reject(reason)
	local s = state.stats
	s.rejected = s.rejected + 1
	s.rejectedBy[reason] = (s.rejectedBy[reason] or 0) + 1
	return false, reason
end

local function reply(sender, id, st)
	local t, base = now(), baseName(sender)
	local log = state.replyLog[base]
	if not log then log = {} state.replyLog[base] = log end
	prune(log, t, Delivery.REPLY_WINDOW)
	local key = base .. "#" .. id .. "#" .. st
	local last = state.replyLast[key]
	if #log >= Delivery.REPLY_MAX or (last and t - last < Delivery.REPLY_GAP) then
		state.stats.repliesLimited = state.stats.repliesLimited + 1
		return false
	end
	log[#log + 1] = t
	state.replyLast[key] = t
	state.stats.replies = state.stats.replies + 1
	ns.Transport:Send("WHISPER", { t = "APPACK", id = id, state = st }, { target = sender, prio = "ALERT" })
	return true
end

local function onApply(msg, sender)
	if not contactOf(msg.k) then
		state.stats.notMine = state.stats.notMine + 1
		return false, "notmine"
	end
	state.stats.received = state.stats.received + 1
	local rec, why = Delivery.ParseApply(msg, sender, clock())
	if not rec then return reject(why) end
	local stored, isNew = store():Receive(rec)
	if not stored then return reject(isNew or "store") end
	if isNew then state.stats.stored = state.stats.stored + 1 end
	-- the same id from another character: never answered (the id belongs to its applicant)
	if baseName(stored.who) ~= baseName(sender) then return reject("sender") end
	reply(sender, stored.id, stored.state)
	return true
end

local function myKey()
	local Role = ns.Role
	local k = Role and Role:GuildKey()
	if k and contactOf(k) then return k end
	return nil
end

local function onPing(msg, sender)
	local k = myKey()
	if not k then
		state.stats.notMine = state.stats.notMine + 1
		return false, "notmine"
	end
	if not Delivery.IsId(msg.id) then return reject("id") end
	local rec = store():Get(k, msg.id)
	if not rec then return false, "unknown" end   -- maybe another officer has it (M4.3 syncs them)
	if baseName(rec.who) ~= baseName(sender) then return reject("sender") end
	reply(sender, rec.id, rec.state)
	return true
end

local function onWithdraw(msg, sender)
	local k = myKey()
	if not k then
		state.stats.notMine = state.stats.notMine + 1
		return false, "notmine"
	end
	if not Delivery.IsId(msg.id) then return reject("id") end
	if not Delivery.IsName(sender) then return reject("who") end
	local known = store():Get(k, msg.id)
	if known and baseName(known.who) ~= baseName(sender) then return reject("sender") end
	local rec, why = store():Withdraw(k, msg.id, sender)
	if not rec then return reject(why or "store") end
	reply(sender, rec.id, rec.state)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving and wiring
---------------------------------------------------------------------------------------------------------------------
function Delivery:OnMessage(msg, sender, dist)
	local t = msg.t
	if t ~= "APPLY" and t ~= "APPACK" and t ~= "APPPING" and t ~= "APPWD" then return end
	-- these four travel only by whisper (SPEC-02 §3); a copy on a channel is somebody else's mistake or a forgery
	if dist ~= "WHISPER" then return reject("dist") end
	if not Delivery.IsName(sender) or isSelf(sender) then return reject("sender") end
	if t == "APPACK" then return onAck(msg, sender) end
	if t == "APPLY" then return onApply(msg, sender) end
	if t == "APPPING" then return onPing(msg, sender) end
	return onWithdraw(msg, sender)
end

function Delivery:Reset() resetState() end

function Delivery:DebugLines()
	local s = state.stats
	local jobs = 0
	for _, job in pairs(state.jobs) do if not job.doneAt then jobs = jobs + 1 end end
	local reasons = {}
	for r, n in pairs(s.rejectedBy) do reasons[#reasons + 1] = r .. " " .. n end
	table.sort(reasons)
	return {
		("Delivery: %d waiting, sent %d, answered %d, silent %d, refused %d, deferred %d, ignored answers %d%s"):format(
			jobs, s.sent, s.acked, s.timeouts, s.refused, s.deferred, s.ackIgnored,
			self:CannotSend() and (", cannot send (" .. self:CannotSend() .. ")") or ""),
		("  as a contact: received %d (new %d), rejected %d%s, answers %d (limited %d), not for us %d"):format(
			s.received, s.stored, s.rejected, #reasons > 0 and (" (" .. table.concat(reasons, ", ") .. ")") or "",
			s.replies, s.repliesLimited, s.notMine),
	}
end

if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(msg, sender, dist) Delivery:OnMessage(msg, sender, dist) end)
	ns.Bus:On("APPLICATION_OUTBOX", function() pump() end)
	ns.Bus:On("CONTACT_SEEN", function() pump() end)
	ns.Bus:On("TRANSPORT_LISTEN_ONLY", function() Delivery:CheckCannotSend() end)
	ns.Bus:On("TRANSPORT_READ_ONLY", function() Delivery:CheckCannotSend() end)
end
if ns.addon then
	ns.addon.Delivery = Delivery
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Delivery", function() return Delivery:DebugLines() end) end
end
