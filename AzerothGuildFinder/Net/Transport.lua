-- Transport: the queue between the codec and the wire (SPEC-02 §1, §3, §4, SPEC-01 §7-§8). Lua 5.1.
--
--   Transport:Send(dist, msg, opts)   dist = CHANNEL | WHISPER | GUILD | OFFICER, msg = { t = "ANN", ... fields ... },
--                                     opts = { target, prio = ALERT|NORMAL|BULK, key, reply, ttl, onSent, onFail }
--   Receive: AceComm (prefix AzGF) -> Transport:OnReceive -> Codec:Decode -> Bus NET_MESSAGE(msg, sender, dist).
--
-- Rules (SPEC-02 §4, all numbers are fields of Transport and are read on every use):
--   NET-01  CHANNEL: one message per CHANNEL_GAP and CHANNEL_BUDGET bytes per BUDGET_WINDOW seconds, explicit replies
--           (CATACK, DETACK, ...) excluded from the byte budget;
--   NET-02  at most one CAT and three DET per minute (Transport.RATE);
--   NET-03  nothing is handed to the client during a chat lockdown or an addon restriction: the messages wait, the
--           latest one per `key` wins, BULK ones older than BULK_TTL are dropped;
--   NET-04  a throttle result retries after 4 x CHANNEL_GAP, at most MAX_RETRIES times.
-- InvalidChannel (7) on CHANNEL switches to listen-only mode: queued and new CHANNEL messages are dropped, WHISPER and
-- GUILD go on, one CHANNEL message per LISTEN_RETRY seconds probes whether the channel works again.
--
-- Two layers: our own queue (limits, lockdown, keys, expiry; one pass every TICK seconds while it holds something) and
-- ChatThrottleLib (bandwidth, ordering, priorities). Messages longer than 255 bytes are split with the AceComm-3.0 wire
-- format (so AceComm reassembles them on the other side) but handed to ChatThrottleLib directly: AceComm's send callback
-- loses the result code, and the result code is what tells InvalidChannel from a throttle.
--
-- Bus events: NET_MESSAGE(msg, sender, dist), PROTOCOL_NEWER() once per session, TRANSPORT_LISTEN_ONLY(active, reason),
-- TRANSPORT_READ_ONLY(active). Sender names go to the Bus and nowhere else: never printed, never stored here.
local ADDON_NAME, ns = ...
ns = ns or {}
local Transport = {}
ns.Transport, ns.modules = Transport, ns.modules or {}
ns.modules.Transport = Transport

local type, pairs, ipairs, pcall, tostring, tonumber, select = type, pairs, ipairs, pcall, tostring, tonumber, select
local sub, match = string.sub, string.match
local tinsert, tremove, sort = table.insert, table.remove, table.sort

---------------------------------------------------------------------------------------------------------------------
-- Constants (SPEC-02 §1 and §4)
---------------------------------------------------------------------------------------------------------------------
Transport.CHANNEL_GAP = 1.2       -- seconds between two CHANNEL messages
Transport.CHANNEL_BUDGET = 2048   -- bytes per BUDGET_WINDOW in the channel, replies excluded
Transport.BUDGET_WINDOW = 60
Transport.BULK_TTL = 600          -- a BULK message waiting longer than this is dropped
Transport.MAX_RETRIES = 3         -- after a throttle result, each one 4 x CHANNEL_GAP later
Transport.RETRY_FACTOR = 4
Transport.LISTEN_RETRY = 3600     -- listen-only: one probe per hour of the session
Transport.TICK = 0.2              -- pass interval of the queue while it holds messages
Transport.QUEUE_MAX = 200         -- pending messages (all distributions together)
Transport.LOCKDOWN_RECHECK = 1    -- seconds to wait after the client refused a message with "lockdown"
Transport.RATE = { CAT = { 1, 60 }, DET = { 3, 60 } }   -- type -> { count, seconds }

Transport.DISTS = { CHANNEL = true, WHISPER = true, GUILD = true, OFFICER = true }
local RANK = { ALERT = 1, NORMAL = 2, BULK = 3 }

-- Default priority per message type (SPEC-02 §4); types the table does not list go NORMAL.
Transport.PRIORITY = {
	APPLY = "ALERT", APPACK = "ALERT", APPWD = "ALERT", CATACK = "ALERT", DETACK = "ALERT", PING = "ALERT", PONG = "ALERT",
	DET = "NORMAL", GLIST = "NORMAL", APPSYNC = "NORMAL", DEL = "NORMAL",
	ANN = "BULK", CAT = "BULK", CATREQ = "BULK", GTOK = "BULK",
}
-- Answers to an explicit request: they do not count against the channel byte budget.
Transport.REPLY = { CATACK = true, DETACK = true, CAT = true, DET = true, APPACK = true }

-- Retail codes; the client's own Enum.SendAddonMessageResult wins when it exists (M0 S6 reads the real values).
local CODES = {
	Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4, NotInGroup = 5,
	TargetRequiresGuild = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9, AddOnMessageLockdown = 11,
	TargetOffline = 12,
}
local function codes()
	local enum = ns.Compat and ns.Compat.Resolve("Enum.SendAddonMessageResult")
	if type(enum) ~= "table" then return CODES end
	local merged = {}
	for name, code in pairs(CODES) do merged[name] = type(enum[name]) == "number" and enum[name] or code end
	return merged
end

local function codeName(code)
	for name, value in pairs(codes()) do
		if value == code then return name end
	end
	return tostring(code)
end

-- AceComm-3.0 multipart markers.
local MSG_MULTI_FIRST, MSG_MULTI_NEXT, MSG_MULTI_LAST, MSG_ESCAPE = "\001", "\002", "\003", "\004"
-- The client limit is 255 bytes of text; the mock (and the old rule) counts the prefix too. Until M0 measures it the
-- chunks stay below 255 minus the prefix: a few bytes lost per chunk, no risk of InvalidMessage.
Transport.WIRE_LIMIT = 255
local function maxWire() return Transport.WIRE_LIMIT - #(Transport.PREFIX or "") end

---------------------------------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------------------------------
local function newStats()
	return {
		sent = 0, sentBytes = 0, failed = 0, throttled = 0, retried = 0, coalesced = 0,
		dropped = 0, droppedBy = {},                       -- send side: reason -> count
		received = 0, rxDropped = 0, rxReasons = {}, rxNewer = 0,
		encodeFailed = 0, callbackErrors = 0,
	}
end

Transport.channelId = function() return nil end   -- replaced by the Channel module (M1.8): the id of AzGuildFinder

local state
local function resetState()
	state = {
		queue = {}, seq = 0, keys = {},            -- pending items sorted by (rank, seq); key -> item
		inflight = 0, ticker = nil,
		lastChannelAt = nil, channelLog = {}, typeLog = {}, holdUntil = {},
		held = nil, readOnly = false,                -- why nothing is handed to the client right now
		listenOnly = false, listenReason = nil, listenSince = nil, probing = false,
		newerNotified = false,
		stats = newStats(),
	}
	Transport.state = state
end
resetState()

local function compat() return ns.Compat end
local function now() return compat().Now() end

local function callUser(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then
		state.stats.callbackErrors = state.stats.callbackErrors + 1
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) end
	end
end

local function emit(event, ...)
	if ns.Bus then ns.Bus:Emit(event, ...) end
end

---------------------------------------------------------------------------------------------------------------------
-- The wire: ChatThrottleLib with the AceComm framing
---------------------------------------------------------------------------------------------------------------------

-- The chunks of `text` in the AceComm-3.0 wire format (chunk size: see maxWire).
function Transport.Frame(text)
	local MAX_WIRE = maxWire()
	local len = #text
	local forceMultipart = false
	if match(text, "^[\001-\009]") then
		if len + 1 > MAX_WIRE then forceMultipart = true else text, len = MSG_ESCAPE .. text, len + 1 end
	end
	if not forceMultipart and len <= MAX_WIRE then return { text } end
	local size = MAX_WIRE - 1
	local chunks = { MSG_MULTI_FIRST .. sub(text, 1, size) }
	local pos = 1 + size
	while pos + size <= len do
		chunks[#chunks + 1] = MSG_MULTI_NEXT .. sub(text, pos, pos + size - 1)
		pos = pos + size
	end
	chunks[#chunks + 1] = MSG_MULTI_LAST .. sub(text, pos)
	return chunks
end

-- Default wire: wire(prio, text, dist, target, done). `done(result)` is called once: the result code of the client
-- (0 = accepted), the first refusal of a multipart message, or a string when the message never reached the client.
-- The test suite and the network simulator replace this function.
function Transport.wire(prio, text, dist, target, done)
	local CTL = compat().Resolve("ChatThrottleLib")
	if type(CTL) ~= "table" or type(CTL.SendAddonMessage) ~= "function" then return done("nolib") end
	local chunks = Transport.Frame(text)
	local reported, count = false, 0
	local function onChunk(_, didSend, sendResult)
		if reported then return end
		count = count + 1
		local result = sendResult
		if type(result) ~= "number" then
			-- an old ChatThrottleLib reports nothing (taken as sent), a newer one a boolean or the code
			if didSend == false then result = CODES.GeneralError else result = CODES.Success end
		end
		if result ~= CODES.Success then
			reported = true
			return done(result)
		end
		if count >= #chunks then
			reported = true
			return done(CODES.Success)
		end
	end
	local queueName = Transport.PREFIX .. "\t" .. dist
	for _, chunk in ipairs(chunks) do
		local ok, err = pcall(CTL.SendAddonMessage, CTL, prio, Transport.PREFIX, chunk, dist, target, queueName, onChunk, #chunk)
		if not ok then
			if not reported then reported = true; done("error: " .. tostring(err):sub(1, 80)) end
			return
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Queue helpers
---------------------------------------------------------------------------------------------------------------------
local function before(a, b)
	if a.rank ~= b.rank then return a.rank < b.rank end
	return a.seq < b.seq
end

local function insertSorted(item)
	local queue = state.queue
	local at = #queue + 1
	for i = 1, #queue do
		if before(item, queue[i]) then at = i break end
	end
	tinsert(queue, at, item)
	if item.key then state.keys[item.key] = item end
end

local function removeFromQueue(item)
	local queue = state.queue
	for i = 1, #queue do
		if queue[i] == item then
			tremove(queue, i)
			if item.key and state.keys[item.key] == item then state.keys[item.key] = nil end
			return true
		end
	end
	return false
end

local function stopTicker()
	if state.ticker then state.ticker:Cancel() state.ticker = nil end
end

local pass   -- forward

local function ensureTicker()
	if state.ticker or #state.queue == 0 then return end
	state.ticker = compat().NewTicker(Transport.TICK, function() pass() end)
end

-- A message that leaves the transport without having been sent (or after a final refusal).
local function settle(item, reason)
	if item.probe then
		state.probing = false   -- the next CHANNEL message may probe again (listenSince is unchanged)
		item.probe = false
	end
	local s = state.stats
	if reason == "replaced" then
		s.coalesced = s.coalesced + 1
	elseif reason ~= "cancelled" then
		s.dropped = s.dropped + 1
		s.droppedBy[reason] = (s.droppedBy[reason] or 0) + 1
	end
	callUser(item.onFail, reason)
end

local function drop(item, reason)
	removeFromQueue(item)
	settle(item, reason)
end

-- Writes down what was spent so a refusal can give it back.
local function prune(log, t, window)
	local keep = 1
	for i = 1, #log do
		local e = log[i]
		if not e.dead and t - e.time < window then log[keep] = e keep = keep + 1 end
	end
	for i = #log, keep, -1 do log[i] = nil end
end

local function budgetUsed(t)
	prune(state.channelLog, t, Transport.BUDGET_WINDOW)
	local used = 0
	for _, e in ipairs(state.channelLog) do used = used + e.bytes end
	return used
end

local function rateFits(msgType, t)
	local rate = Transport.RATE[msgType]
	if not rate then return true end
	local log = state.typeLog[msgType]
	if not log then return true end
	prune(log, t, rate[2])
	return #log < rate[1]
end

---------------------------------------------------------------------------------------------------------------------
-- Listen-only mode and read-only state
---------------------------------------------------------------------------------------------------------------------
function Transport:IsListenOnly() return state.listenOnly, state.listenReason end
function Transport:IsReadOnly() return state.readOnly end

local function enterListenOnly(reason)
	if state.listenOnly then
		state.listenSince, state.probing = now(), false   -- the probe failed: wait another hour
		return
	end
	state.listenOnly, state.listenReason, state.listenSince, state.probing = true, reason, now(), false
	local doomed = {}
	for _, item in ipairs(state.queue) do
		if item.dist == "CHANNEL" then doomed[#doomed + 1] = item end
	end
	for _, item in ipairs(doomed) do drop(item, "listenonly") end
	emit("TRANSPORT_LISTEN_ONLY", true, reason)
end

-- Leaves listen-only mode (a probe went through, or the Channel module joined a working channel).
function Transport:ClearListenOnly()
	if not state.listenOnly then return false end
	state.listenOnly, state.listenReason, state.listenSince, state.probing = false, nil, nil, false
	emit("TRANSPORT_LISTEN_ONLY", false)
	return true
end

-- Allows the next CHANNEL message to probe now instead of waiting for the hour to pass.
function Transport:RetryChannel()
	if state.listenOnly then state.listenSince = now() - Transport.LISTEN_RETRY end
end

-- true when a CHANNEL message may be queued now; sets `probe` for the one that tests a listen-only channel.
local function channelAccepts()
	if not state.listenOnly then return true, false end
	if state.probing or now() - state.listenSince < Transport.LISTEN_RETRY then return false end
	state.probing = true
	return true, true
end

local function setGate(held, readOnly)
	state.held = held
	if state.readOnly ~= readOnly then
		state.readOnly = readOnly
		emit("TRANSPORT_READ_ONLY", readOnly)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------------------------------------------

-- Queues `msg` ({ t = type, ...fields }). Returns the pending item (a handle for Cancel), or nil plus a reason:
-- "dist", "shape", "target", "prio", "encode: ...", "size", "listenonly", "full".
function Transport:Send(dist, msg, opts)
	opts = type(opts) == "table" and opts or {}
	if not Transport.DISTS[dist] then return nil, "dist" end
	if type(msg) ~= "table" then return nil, "shape" end
	if dist == "WHISPER" and (type(opts.target) ~= "string" or opts.target == "") then return nil, "target" end
	local prio = opts.prio or Transport.PRIORITY[msg.t] or "NORMAL"
	if not RANK[prio] then return nil, "prio" end
	local Codec = ns.Codec
	if not Codec then return nil, "encode: nocodec" end
	local payload, err = Codec:Encode(msg.t, msg)
	if not payload then
		state.stats.encodeFailed = state.stats.encodeFailed + 1
		return nil, "encode: " .. tostring(err)
	end
	if #payload > Codec.MAX_PAYLOAD then return nil, "size" end

	local probe = false
	if dist == "CHANNEL" then
		local ok
		ok, probe = channelAccepts()
		if not ok then
			local s = state.stats
			s.dropped = s.dropped + 1
			s.droppedBy.listenonly = (s.droppedBy.listenonly or 0) + 1
			callUser(opts.onFail, "listenonly")
			return nil, "listenonly"
		end
	end

	state.seq = state.seq + 1
	local item = {
		seq = state.seq, dist = dist, target = dist == "WHISPER" and opts.target or nil, t = msg.t, payload = payload,
		size = #payload, prio = prio, rank = RANK[prio], key = type(opts.key) == "string" and opts.key or nil,
		reply = opts.reply == nil and Transport.REPLY[msg.t] or opts.reply and true or false,
		bornAt = now(), ttl = tonumber(opts.ttl) or (prio == "BULK" and Transport.BULK_TTL or nil),
		attempts = 0, notBefore = 0, onSent = opts.onSent, onFail = opts.onFail, probe = probe,
	}

	local old = item.key and state.keys[item.key]
	if old then drop(old, "replaced") end   -- only the latest message per key is kept

	local queue = state.queue
	if #queue >= Transport.QUEUE_MAX then
		-- the queue is sorted by priority then age: drop the oldest message of the lowest priority present
		local victim = queue[#queue]
		for i = #queue, 1, -1 do
			if queue[i].rank ~= victim.rank then break end
			victim = queue[i]
		end
		if victim.rank >= item.rank then
			drop(victim, "overflow")
		else
			settle(item, "overflow")
			return nil, "full"
		end
	end

	insertSorted(item)
	ensureTicker()
	return item
end

-- Withdraws a message that is still waiting. Returns true when it was.
function Transport:Cancel(item)
	if type(item) ~= "table" or not removeFromQueue(item) then return false end
	settle(item, "cancelled")
	return true
end

function Transport:Pending(dist)
	if not dist then return #state.queue end
	local n = 0
	for _, item in ipairs(state.queue) do if item.dist == dist then n = n + 1 end end
	return n
end

local function expire(t)
	local doomed
	for _, item in ipairs(state.queue) do
		if item.ttl and t - item.bornAt >= item.ttl then
			doomed = doomed or {}
			doomed[#doomed + 1] = item
		end
	end
	for _, item in ipairs(doomed or {}) do drop(item, "expired") end
end

-- The first message that may go now, in priority order; nil when none may.
local function pick(t)
	local channelReady
	local function channelOpen()
		if channelReady == nil then
			local id = Transport.channelId()
			local gap = state.lastChannelAt == nil or t - state.lastChannelAt >= Transport.CHANNEL_GAP - 1e-9
			channelReady = (type(id) == "number" and id > 0) and gap or false
		end
		return channelReady
	end
	local budgetBlocked = false
	for _, item in ipairs(state.queue) do
		local ok = item.notBefore <= t and (state.holdUntil[item.dist] or 0) <= t
		if ok and item.dist == "CHANNEL" then
			ok = channelOpen()
			if ok and not item.reply then
				if budgetBlocked then
					ok = false
				else
					local used = budgetUsed(t)
					if used > 0 and used + item.size > Transport.CHANNEL_BUDGET then budgetBlocked, ok = true, false end
				end
			end
		end
		if ok and not rateFits(item.t, t) then ok = false end
		if ok then return item end
	end
	return nil
end

local function giveBack(item)
	if item.budgetEntry then item.budgetEntry.dead = true item.budgetEntry = nil end
	if item.typeEntry then item.typeEntry.dead = true item.typeEntry = nil end
end

local function onResult(item, result)
	state.inflight = state.inflight - 1
	local t, s, c = now(), state.stats, codes()
	if result == c.Success then
		s.sent, s.sentBytes = s.sent + 1, s.sentBytes + item.size
		if item.probe then
			item.probe = false
			state.probing = false
			Transport:ClearListenOnly()
		end
		callUser(item.onSent)
		return
	end

	giveBack(item)
	if item.dist == "CHANNEL" and result == c.InvalidChannel then
		s.failed = s.failed + 1
		enterListenOnly("InvalidChannel")
		settle(item, "InvalidChannel")
		return
	end

	local requeueAt
	if result == c.ChannelThrottle or result == c.AddonMessageThrottle then
		s.throttled = s.throttled + 1
		if item.attempts - 1 < Transport.MAX_RETRIES then
			requeueAt = t + Transport.RETRY_FACTOR * Transport.CHANNEL_GAP
			s.retried = s.retried + 1
		end
	elseif result == c.AddOnMessageLockdown then
		item.attempts = item.attempts - 1   -- the client refused before trying: not a try
		requeueAt = t + Transport.LOCKDOWN_RECHECK
	end

	if requeueAt then
		item.notBefore = requeueAt
		state.holdUntil[item.dist] = requeueAt
		insertSorted(item)
		ensureTicker()
		return
	end
	s.failed = s.failed + 1
	settle(item, type(result) == "number" and codeName(result) or tostring(result))
end

local function dispatch(item, t)
	removeFromQueue(item)
	item.attempts = item.attempts + 1
	local target = item.target
	if item.dist == "CHANNEL" then
		target = Transport.channelId()
		state.lastChannelAt = t
		if not item.reply then
			item.budgetEntry = { time = t, bytes = item.size }
			state.channelLog[#state.channelLog + 1] = item.budgetEntry
		end
	end
	if Transport.RATE[item.t] then
		item.typeEntry = { time = t }
		local log = state.typeLog[item.t]
		if not log then log = {} state.typeLog[item.t] = log end
		log[#log + 1] = item.typeEntry
	end
	state.inflight = state.inflight + 1
	local answered = false
	Transport.wire(item.prio, item.payload, item.dist, target, function(result)
		if answered then return end
		answered = true
		onResult(item, result)
	end)
end

-- One pass of the queue: expiry, the client gate (lockdown, restrictions), then everything that may go.
pass = function()
	local t = now()
	expire(t)
	local Chat = compat().Chat
	local held = (Chat.InChatLockdown() and "lockdown") or Chat.RestrictionAny() or nil
	local readOnly = Chat.OutgoingAddonRestricted()
	setGate(held, readOnly)
	if not held and not readOnly then
		for _ = 1, Transport.QUEUE_MAX do
			local item = pick(t)
			if not item then break end
			dispatch(item, t)
			t = now()
		end
	end
	if #state.queue == 0 then stopTicker() end
end
Transport.Pass = function() pass() end   -- the ticker does this; tests and the simulator may call it directly

function Transport:Reset()
	stopTicker()
	resetState()
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------------------------------------------------

-- Called by AceComm with a whole (reassembled) payload. Returns true when a message went to the Bus.
function Transport:OnReceive(text, dist, sender)
	local s = state.stats
	s.received = s.received + 1
	local Codec = ns.Codec
	local msg, reason
	if not Transport.DISTS[dist] then
		msg, reason = nil, "dist"
	elseif not Codec then
		msg, reason = nil, "nocodec"
	else
		msg, reason = Codec:Decode(text)
	end
	if not msg then
		if reason == "newer" then
			s.rxNewer = s.rxNewer + 1
			if Codec:ConsumeNewer() and not state.newerNotified then
				state.newerNotified = true
				emit("PROTOCOL_NEWER")
			end
		else
			s.rxDropped = s.rxDropped + 1
			s.rxReasons[reason] = (s.rxReasons[reason] or 0) + 1
		end
		return false, reason
	end
	emit("NET_MESSAGE", msg, sender, dist)
	return true
end

-- Registers the prefix and the AceComm callback (once). Returns false when AceComm is not there.
function Transport:Register()
	if Transport.registered then return true end
	local AceComm = LibStub and LibStub("AceComm-3.0", true)
	if not AceComm then return false end
	AceComm.RegisterComm(Transport, Transport.PREFIX, function(_, text, dist, sender)
		Transport:OnReceive(text, dist, sender)
	end)
	Transport.registered = true
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Statistics and /gf debug
---------------------------------------------------------------------------------------------------------------------
local function copyCounts(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

-- queued, sent, dropped, throttled, listen-only reason (and the rest) as a plain table.
function Transport:Stats()
	local s = state.stats
	local by = { CHANNEL = 0, WHISPER = 0, GUILD = 0, OFFICER = 0 }
	for _, item in ipairs(state.queue) do by[item.dist] = by[item.dist] + 1 end
	return {
		queued = #state.queue, queuedBy = by, inflight = state.inflight,
		sent = s.sent, sentBytes = s.sentBytes, failed = s.failed, throttled = s.throttled, retried = s.retried,
		coalesced = s.coalesced, dropped = s.dropped, droppedBy = copyCounts(s.droppedBy),
		received = s.received, rxDropped = s.rxDropped, rxReasons = copyCounts(s.rxReasons), rxNewer = s.rxNewer,
		encodeFailed = s.encodeFailed, callbackErrors = s.callbackErrors,
		listenOnly = state.listenOnly, listenReason = state.listenReason, readOnly = state.readOnly, held = state.held,
	}
end

local function countsText(t)
	local parts = {}
	for k, v in pairs(t) do parts[#parts + 1] = k .. " " .. v end
	sort(parts)
	return #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
end

function Transport:DebugLines()
	local st = self:Stats()
	local mode = st.listenOnly and ("listen-only (" .. tostring(st.listenReason) .. ")") or "normal"
	if st.readOnly then mode = mode .. ", read-only" end
	if st.held then mode = mode .. ", held (" .. tostring(st.held) .. ")" end
	return {
		("Transport: %s, channel id %s, registered %s"):format(mode, tostring(Transport.channelId()), Transport.registered and "yes" or "no"),
		("  queued %d (channel %d, whisper %d, guild %d, officer %d), in flight %d"):format(st.queued, st.queuedBy.CHANNEL,
			st.queuedBy.WHISPER, st.queuedBy.GUILD, st.queuedBy.OFFICER, st.inflight),
		("  sent %d (%d bytes), failed %d, throttled %d, retried %d, replaced by key %d, dropped %d%s"):format(st.sent,
			st.sentBytes, st.failed, st.throttled, st.retried, st.coalesced, st.dropped, countsText(st.droppedBy)),
		("  received %d, rejected %d%s, newer protocol %d"):format(st.received, st.rxDropped, countsText(st.rxReasons), st.rxNewer),
	}
end

Transport.PREFIX = ns.Codec and ns.Codec.PREFIX or "AzGF"
Transport:Register()

if ns.addon then
	ns.addon.Transport = Transport
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Transport", function() return Transport:DebugLines() end) end
end
