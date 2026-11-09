-- Sync: the catalog over the hidden channel (SPEC-02 §3, §5, §6). Lua 5.1.
--
--   ANN / DEL         channel announcements and withdrawals -> Catalog (meta = { sender, dist }); contacts (c = 1) and
--                     the last ANN per guild (for the §5 suppression) are remembered in memory only.
--   CATREQ            on CHANNEL_READY, after 5-15 s, unless a full sync is younger than 10 min: the digest of the
--                     local catalog as flat { h, rev, srev, ... } triples, split in parts of DIGEST_PART listings.
--   CATACK / CAT      every peer with something for the requester schedules an answer (0.5-5 s, sooner with more to
--                     send); the first one sends CATACK{to, nonce, n} on the channel and the others cancel. Peers that
--                     answer at nearly the same moment see each other's CATACK during CONFIRM seconds: only the best
--                     (most to send, then the lowest name hash) goes on. The winner whispers CAT batches of BATCH
--                     summaries A -> Z (one CAT reply per minute, NET-02).
--   rounds            a round that brought something new is followed by another CATREQ (another peer may know more);
--                     a round that brings nothing, a "nothing new" CATACK (n = 0, only from a peer that finished a full
--                     sync itself) or a silent follow-up round ends the sync. A first round without any answer is
--                     retried after BACKOFF seconds, MAX_RETRIES times; then the client relies on the ANN.
--   DETREQ / DETACK / DET   the same election for one detail (Sync:RequestDetail); DETAIL_UNAVAILABLE after 20 s.
--   listen-only       when the channel refuses our messages, requests go by whisper to a peer heard on the channel and
--                     that peer answers directly (no election).
--
-- Peer names live in memory only (contacts, recent channel senders for the whisper fallback) and are never printed
-- or saved. Bus events: CATALOG_SYNCED(result), DETAIL_UNAVAILABLE(k).
local ADDON_NAME, ns = ...
ns = ns or {}
local Sync = {}
ns.Sync, ns.modules = Sync, ns.modules or {}
ns.modules.Sync = Sync

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, max, min, log, random = math.floor, math.max, math.min, math.log, math.random
local sort = table.sort

---------------------------------------------------------------------------------------------------------------------
-- Constants (SPEC-02 §5-§6). Every number is read on use, so tests may change them.
---------------------------------------------------------------------------------------------------------------------
Sync.START_DELAY = { 5, 15 }   -- after CHANNEL_READY, before the first CATREQ
Sync.FRESH = 600               -- a full sync younger than this is not repeated at CHANNEL_READY
Sync.REPLY_DELAY = { 0.5, 5 }  -- an answer is scheduled in this window
Sync.CONFIRM = 1.0             -- after our own CATACK/DETACK: time to see a competing one before sending
Sync.SILENCE = 20              -- the requester's wait for any answer
Sync.STALL = 10                -- the requester's wait between two CAT batches
Sync.BACKOFF = 60              -- wait before repeating an unanswered first round
Sync.MAX_RETRIES = 3
Sync.BATCH = 10                -- summaries per CAT message
Sync.DIGEST_PART = 64          -- listings per CATREQ part
Sync.MAX_PARTS = 16            -- a CATREQ with more parts is ignored (500 listings need 8)
Sync.MAX_ROUNDS = 8            -- rounds of one sync
Sync.ROUND_GAP = { 1, 3 }      -- pause between two rounds
Sync.CAT_EVERY = 60            -- NET-02: one CAT reply per minute
Sync.DET_PER_MINUTE = 3        -- NET-02: three DET replies per minute
Sync.DETAIL_TIMEOUT = 20
Sync.PARTS_TTL = 60            -- an incomplete CATREQ is forgotten after this
Sync.ANSWER_TTL = 120          -- a finished or cancelled answer is forgotten after this
Sync.AUTHORITY = 1800          -- a peer whose full sync is younger than this may answer "nothing new"
Sync.UPTODATE_ACKERS = 3       -- about how many peers volunteer a "nothing new" answer
Sync.W_SLACK = 5               -- acks whose waits differ by less than this are compared by what they send
Sync.MANY = 100                -- an answer with this many summaries (or more) gets the shortest delay
Sync.MIN_PEERS = 32            -- the peer estimate used to spread the answer timers is never lower than this
Sync.PEER_WINDOW = 1800        -- channel senders heard in this time count as peers
Sync.MAX_CONTACTS = 10         -- contacts remembered per guild
Sync.MAX_RECENT = 10           -- channel senders remembered for the whisper fallback

---------------------------------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------------------------------
local function newStats()
	return {
		ann = 0, annRejected = 0, del = 0, testIgnored = 0,
		requestsSent = 0, rounds = 0, syncs = 0, received = 0, changed = 0, duplicateCats = 0, retries = 0, gaveUp = 0,
		requestsHeard = 0, acksSent = 0, cancelled = 0, yielded = 0, catReplies = 0, catsSent = 0, detReplies = 0,
		detailsRequested = 0, detailsReceived = 0, unavailable = 0,
	}
end

local state
local function resetState()
	state = {
		req = nil,          -- this client's catalog sync (requester side)
		answers = {},       -- [requester#nonce] = an answer being prepared for a peer's CATREQ / DETREQ
		parts = {},         -- [requester#nonce] = { n, got, have = {}, cat = {}, at, dist }
		details = {},       -- [k] = { nonce, at, gen } pending detail requests
		contacts = {},      -- [k] = { [sender] = last seen }      memory only
		lastAnn = {},       -- [k] = { rev, srev, at }
		peers = {},         -- [name hash] = last seen on the channel
		recent = {},        -- { { name =, at = } } newest first   memory only
		nonces = {},        -- [nonce] = true for the CATREQs of this client in the last ANSWER_TTL seconds
		catFreeAt = nil,    -- Now() time when this client may start its next CAT reply (NET-02)
		detLog = {},
		startGen = 0, gen = 0, lastResult = nil,
		stats = newStats(),
	}
	Sync.state = state
end
resetState()

local function C() return ns.Compat end
local function now() return C().Now() end
local function clock() return C().ServerTime() end
local function rnd(a, b) return a + (b - a) * random() end
local function after(seconds, fn) return C().After(seconds, fn) end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function hash(s) return ns.Normalize.Hash32(s) end

local function isDev() return ns.Config ~= nil and ns.Config.DEV == true end
Sync.IsDev = isDev

-- A sender as AceComm gives it: "Name" (own realm) or "Name-Realm". Peers are told apart by the name alone.
local function baseName(sender)
	if type(sender) ~= "string" or sender == "" then return nil end
	return (sender:match("^[^%-]+") or sender):lower()
end
local function myName() local n = C().Player.Name() return n and n:lower() or nil end
local function isSelf(sender) local mine = myName() return mine ~= nil and baseName(sender) == mine end
local function peerHash(sender) return hash(baseName(sender) or "") end
local function myHash() return hash(myName() or "") end

local function bucketKey()
	local P = C().Player
	local realm, faction = P.Realm(), P.Faction()
	if not realm or not faction then return nil end
	return realm .. "|" .. faction
end

local function syncTable()
	local db = ns.Config and ns.Config.db and ns.Config.db.account
	if db and type(db.syncAt) == "table" then return db.syncAt end
end

-- When the last full sync of this realm and faction finished (server time), or nil.
function Sync:LastFullSync()
	local t, key = syncTable(), bucketKey()
	local v = t and key and t[key]
	if type(v) == "number" and v == v and v <= clock() then return v end
	return nil
end

local function markFullSync()
	local t, key = syncTable(), bucketKey()
	if t and key and not (ns.Config.IsReadOnly and ns.Config:IsReadOnly("account")) then t[key] = clock() end
end

local function authoritative()
	local at = Sync:LastFullSync()
	return at ~= nil and clock() - at <= Sync.AUTHORITY
end

---------------------------------------------------------------------------------------------------------------------
-- Peers (memory only)
---------------------------------------------------------------------------------------------------------------------
local function notePeer(sender)
	if isSelf(sender) then return end
	local t = now()
	state.peers[peerHash(sender)] = t
	local recent = state.recent
	for i = #recent, 1, -1 do
		if recent[i].name == sender then table.remove(recent, i) end
	end
	table.insert(recent, 1, { name = sender, at = t })
	while #recent > Sync.MAX_RECENT do recent[#recent] = nil end
end

-- The number of distinct peers heard on the channel in the last PEER_WINDOW seconds (at least 1).
function Sync:PeerCount()
	local t, n = now(), 0
	for h, at in pairs(state.peers) do
		if t - at <= Sync.PEER_WINDOW then n = n + 1 else state.peers[h] = nil end
	end
	return max(n, 1)
end

-- The distinct peers heard in the last PEER_WINDOW seconds, 0 when nobody (PeerCount never says less than 1: it is
-- an estimate for spreading timers; the list uses this to tell "nobody is around").
function Sync:HeardPeers()
	local t, n = now(), 0
	for _, at in pairs(state.peers) do
		if t - at <= Sync.PEER_WINDOW then n = n + 1 end
	end
	return n
end

-- A peer to whisper a request to (listen-only): the most recent channel sender, or a contact of guild k.
local function whisperTarget(k)
	if k and state.contacts[k] then
		local best, bestAt
		for name, at in pairs(state.contacts[k]) do
			if not bestAt or at > bestAt then best, bestAt = name, at end
		end
		if best then return best end
	end
	local first = state.recent[1]
	return first and first.name or nil
end

local function listenOnly()
	return ns.Transport and ns.Transport:IsListenOnly() and true or false
end

---------------------------------------------------------------------------------------------------------------------
-- Answer timing: a short exponential spread (Nonnenmacher-Biersack) so that among N peers few fire within the
-- network latency of the first one.
---------------------------------------------------------------------------------------------------------------------
local function spread(span)
	local n = max(Sync:PeerCount(), Sync.MIN_PEERS) + 1   -- a quiet channel hides how many peers listen
	local u = random()
	if u < 1e-9 then u = 1e-9 end
	local x = 1 + log(u) / log(max(n, 2))
	if x < 0 then x = 0 end
	return span * x
end

-- true when ack a beats ack b (acks as { n = summaries, h = name hash, w = seconds before sending }): the one that
-- can send sooner (by more than W_SLACK seconds), then more to send, then the lower name hash.
local function beats(a, b)
	local aw, bw = a.w or 0, b.w or 0
	if aw - bw > Sync.W_SLACK or bw - aw > Sync.W_SLACK then return aw < bw end
	if a.n ~= b.n then return a.n > b.n end
	return a.h < b.h
end

---------------------------------------------------------------------------------------------------------------------
-- ANN and DEL
---------------------------------------------------------------------------------------------------------------------
local ACCEPTED = { added = true, updated = true, stats = true, takeover = true, relisted = true, unchanged = true, older = true }

local function rememberContact(k, sender)
	local list = state.contacts[k]
	if not list then list = {} state.contacts[k] = list end
	list[sender] = now()
	local n, oldest, oldestAt = 0, nil, nil
	for name, at in pairs(list) do
		n = n + 1
		if not oldestAt or at < oldestAt then oldest, oldestAt = name, at end
	end
	if n > Sync.MAX_CONTACTS then list[oldest] = nil end
end

-- The contacts (GM and officers) heard announcing guild k, most recent first, at most maxAge seconds ago.
function Sync:Contacts(k, maxAge)
	local out = {}
	local t = now()
	for name, at in pairs(state.contacts[k] or {}) do
		if not maxAge or t - at <= maxAge then out[#out + 1] = { name = name, at = at } end
	end
	sort(out, function(a, b) return a.at > b.at end)
	local names = {}
	for i, c in ipairs(out) do names[i] = c.name end
	return names
end

-- The last ANN heard for guild k: { rev, srev, at } (at = Now()), or nil.
function Sync:LastAnnounce(k) return state.lastAnn[k] end

-- §5 suppression: true when an ANN of guild k with rev and srev equal or higher arrived after `since` (Now() time),
-- so this client skips its own periodic ANN for one turn.
function Sync:Suppressed(k, rev, srev, since)
	local a = state.lastAnn[k]
	return a ~= nil and a.at > (since or 0) and a.rev >= (rev or 0) and a.srev >= (srev or 0)
end

local function onAnn(msg, sender)
	if msg.test and not isDev() then
		state.stats.testIgnored = state.stats.testIgnored + 1
		return
	end
	local ok, why = ns.Catalog:PutSummary(msg, { sender = sender, dist = "CHANNEL" })
	if ACCEPTED[why] then
		state.stats.ann = state.stats.ann + 1
		local a = state.lastAnn[msg.k]
		local srev = tonumber(msg.srev) or 0
		if not a or msg.rev > a.rev or (msg.rev == a.rev and srev >= a.srev) then
			state.lastAnn[msg.k] = { rev = msg.rev, srev = srev, at = now() }
		else
			a.at = now()
		end
		if msg.c == 1 and not isSelf(sender) then rememberContact(msg.k, sender) end
	else
		state.stats.annRejected = state.stats.annRejected + 1
	end
	return ok, why
end

local function onDel(msg, sender)
	local ok = ns.Catalog:Delist(msg.k, msg.rev, { sender = sender, dist = "CHANNEL" })
	if ok then state.stats.del = state.stats.del + 1 end
end

-- Announces summary `sum` on the channel (BULK, the latest per guild waits in the queue). opts.contact sets c = 1,
-- opts.test marks a development test listing. The listing goes in the local catalog too. Returns the Transport item
-- or nil plus a reason.
function Sync:Announce(sum, opts)
	opts = opts or {}
	if type(sum) ~= "table" or type(sum.k) ~= "string" then return nil, "shape" end
	local msg = {}
	for field, value in pairs(sum) do msg[field] = value end
	msg.t = "ANN"
	msg.c = opts.contact and 1 or nil
	msg.test = opts.test and true or nil
	ns.Catalog:PutSummary(msg, { sender = C().Player.Name(), dist = "CHANNEL" })
	return ns.Transport:Send("CHANNEL", msg, { key = "ANN:" .. sum.k, onFail = opts.onFail })
end

-- Withdraws guild k up to revision rev: a DEL on the channel (NORMAL, the latest per guild waits in the queue) and
-- the tombstone in the local catalog. Only Data/OwnListing.lua calls it, for the player's own guild after it checked
-- the Guild Master itself (the local catalog trusts it, INT-05 applies on the other clients). Returns the Transport
-- item or nil plus a reason.
function Sync:Withdraw(k, rev, opts)
	opts = opts or {}
	if type(k) ~= "string" or type(rev) ~= "number" then return nil, "shape" end
	ns.Catalog:Delist(k, rev, { trusted = true })
	return ns.Transport:Send("CHANNEL", { t = "DEL", k = k, rev = rev }, { key = "DEL:" .. k, onFail = opts.onFail })
end

---------------------------------------------------------------------------------------------------------------------
-- Requester: CATREQ rounds
---------------------------------------------------------------------------------------------------------------------
local sendRound   -- forward

local function digestParts()
	local digest = ns.Catalog:Digest()
	local parts, cur = {}, nil
	local size = max(1, floor(Sync.DIGEST_PART))
	for _, e in ipairs(digest) do
		if not cur or #cur >= 3 * size then cur = {} parts[#parts + 1] = cur end
		cur[#cur + 1] = e.h
		cur[#cur + 1] = e.rev
		cur[#cur + 1] = e.srev
	end
	if #parts == 0 then parts[1] = {} end
	return parts
end

local function finish(full, why)
	local req = state.req
	if not req then return end
	state.req = nil
	if full then
		markFullSync()
		state.stats.syncs = state.stats.syncs + 1
	else
		state.stats.gaveUp = state.stats.gaveUp + 1
	end
	local result = { full = full, why = why, rounds = req.rounds, received = req.received, changed = req.changed,
		took = now() - req.startedAt, responders = req.responderCount }
	state.lastResult = result
	emit("CATALOG_SYNCED", result)
end

-- Arms the requester's timer: fn runs after `seconds` unless the round moved on.
local function arm(req, seconds, fn)
	req.timerGen = (req.timerGen or 0) + 1
	local gen, nonce = req.timerGen, req.nonce
	after(seconds, function()
		if state.req == req and req.nonce == nonce and req.timerGen == gen then fn() end
	end)
end

local function disarm(req) req.timerGen = (req.timerGen or 0) + 1 end

-- Sends the next CATREQ after `seconds`; a later call (or a round sent meanwhile) replaces this one.
local function resend(req, seconds)
	req.sendGen = (req.sendGen or 0) + 1
	local gen = req.sendGen
	after(seconds, function()
		if state.req == req and req.sendGen == gen then sendRound() end
	end)
end

local function endRound(req, upToDate)
	if upToDate then return finish(true, "up to date") end
	if req.roundGot == 0 then
		-- a peer promised summaries that never came (lost, or it stepped back): ask again soon
		if req.retries >= Sync.MAX_RETRIES then return finish(false, "no answer") end
		req.retries = req.retries + 1
		state.stats.retries = state.stats.retries + 1
		req.nonce = nil
		disarm(req)
		return resend(req, rnd(Sync.ROUND_GAP[1], Sync.ROUND_GAP[2]))
	end
	if req.roundChanged == 0 then return finish(true, "nothing new") end
	if req.rounds >= Sync.MAX_ROUNDS then return finish(true, "rounds") end
	req.followUp = true
	req.nonce = nil   -- late batches of this round are still merged, but no longer drive it
	disarm(req)
	resend(req, rnd(Sync.ROUND_GAP[1], Sync.ROUND_GAP[2]))
end

local function onSilence(req)
	if req.best or req.roundGot > 0 then return endRound(req, false) end
	if req.followUp then
		-- the previous round brought news and nobody answers this one: nobody knows more, unless the request or the
		-- answers were lost, so ask once more before concluding
		if req.silentOnce then return finish(true, "no answer") end
		req.silentOnce = true
		req.nonce = nil
		return resend(req, rnd(Sync.ROUND_GAP[1], Sync.ROUND_GAP[2]))
	end
	if req.retries >= Sync.MAX_RETRIES then return finish(false, "no answer") end
	req.retries = req.retries + 1
	state.stats.retries = state.stats.retries + 1
	req.nonce = nil
	resend(req, Sync.BACKOFF)
end

sendRound = function()
	local req = state.req
	if not req then return end
	req.sendGen = (req.sendGen or 0) + 1   -- cancels any other pending send
	req.best, req.roundGot, req.roundChanged, req.batches = nil, 0, 0, {}
	local whisper = listenOnly() and whisperTarget() or nil
	if listenOnly() and not whisper then
		-- no peer heard yet: wait for one (an ANN or any channel message), then try again
		req.nonce, req.waitingForPeer = nil, true
		arm(req, Sync.SILENCE, function() onSilence(req) end)
		return
	end
	req.rounds = req.rounds + 1
	state.stats.rounds = state.stats.rounds + 1
	req.nonce = random(1, 2147483647)
	local remember = req.nonce
	state.nonces[remember] = true
	after(Sync.ANSWER_TTL, function() state.nonces[remember] = nil end)
	local parts = digestParts()
	req.waitingForPeer = nil
	req.target = whisper
	local nonce, sentParts, failed = req.nonce, 0, false
	for i, cat in ipairs(parts) do
		local msg = { t = "CATREQ", nonce = nonce, cat = cat, p = #parts > 1 and i or nil, n = #parts > 1 and #parts or nil }
		local opts = {
			onSent = function()
				sentParts = sentParts + 1
				if sentParts == #parts and state.req == req and req.nonce == nonce then
					arm(req, Sync.SILENCE, function() onSilence(req) end)
				end
			end,
			onFail = function(reason)
				if failed or state.req ~= req or req.nonce ~= nonce then return end
				failed = true
				if (reason == "InvalidChannel" or reason == "listenonly") and not whisper then
					req.rounds = req.rounds - 1   -- the channel refused it: the same round again, by whisper
					state.stats.rounds = state.stats.rounds - 1
					disarm(req)
					resend(req, 0.5)
				else
					arm(req, Sync.SILENCE, function() onSilence(req) end)
				end
			end,
		}
		if whisper then opts.target = whisper end
		local item, why = ns.Transport:Send(whisper and "WHISPER" or "CHANNEL", msg, opts)
		if not item then
			if why ~= "listenonly" then
				failed = true
				arm(req, Sync.SILENCE, function() onSilence(req) end)
			end
			return
		end
	end
	state.stats.requestsSent = state.stats.requestsSent + 1
end

-- Starts a catalog sync now (CHANNEL_READY does it by itself). Returns false when one is running.
function Sync:Request()
	if state.req then return false end
	state.req = { rounds = 0, retries = 0, received = 0, changed = 0, responders = {}, responderCount = 0,
		startedAt = now() }
	sendRound()
	return true
end

function Sync:IsSyncing() return state.req ~= nil end

local function noteResponder(req, sender)
	local h = peerHash(sender)
	if not req.responders[h] then
		req.responders[h] = true
		req.responderCount = req.responderCount + 1
	end
end

local function onAckForMe(msg, sender)
	local req = state.req
	if not req or msg.nonce ~= req.nonce then return end
	local n = tonumber(msg.n) or 0
	local ack = { n = n, h = peerHash(sender), w = tonumber(msg.w) or 0, sender = sender }
	if req.best and not beats(ack, req.best) then return end
	req.best = ack
	if n == 0 then
		-- "nothing new": wait a moment for a better answer from someone who has something
		arm(req, Sync.CONFIRM + 1, function()
			if req.best and req.best.n == 0 and req.roundGot == 0 then endRound(req, true) end
		end)
	else
		arm(req, Sync.CONFIRM + (tonumber(msg.w) or 0) + Sync.STALL, function() onSilence(req) end)
	end
end

local function onCat(msg, sender)
	if not state.nonces[msg.nonce] then return end   -- only answers to our own requests
	local dev = isDev()
	local ages = type(msg.age) == "table" and msg.age or {}
	local t = clock()
	local got, changed = 0, 0
	for i, item in ipairs(msg.items) do
		if type(item) == "table" and (dev or not item.test) then
			local age = tonumber(ages[i])
			local meta = { sender = sender, dist = "WHISPER" }
			if age and age >= 0 then meta.annAt = t - age end
			local ok = ns.Catalog:PutSummary(item, meta)
			got = got + 1
			if ok then changed = changed + 1 end
		elseif type(item) == "table" then
			state.stats.testIgnored = state.stats.testIgnored + 1
		end
	end
	state.stats.received, state.stats.changed = state.stats.received + got, state.stats.changed + changed
	local req = state.req
	if not req then return end
	req.received, req.changed = req.received + got, req.changed + changed
	noteResponder(req, sender)
	if msg.nonce ~= req.nonce then return end   -- a late batch of an earlier round: merged, nothing more
	local h = peerHash(sender)
	if not req.best then req.best = { n = tonumber(msg.n) or #msg.items, h = h, w = 0, sender = sender } end
	req.roundGot, req.roundChanged = req.roundGot + got, req.roundChanged + changed
	if req.best.h ~= h then
		state.stats.duplicateCats = state.stats.duplicateCats + 1
	else
		req.batches[tonumber(msg.i) or 1] = true
		local all = true
		for i = 1, tonumber(msg.of) or 1 do
			if not req.batches[i] then all = false break end
		end
		if all then return endRound(req, false) end
	end
	arm(req, Sync.STALL, function() onSilence(req) end)
end

---------------------------------------------------------------------------------------------------------------------
-- Responder: CATREQ / DETREQ elections
---------------------------------------------------------------------------------------------------------------------
local function answerKey(sender, nonce) return (baseName(sender) or "?") .. "#" .. tostring(nonce) end

local function forgetLater(key, a)
	after(Sync.ANSWER_TTL, function() if state.answers[key] == a then state.answers[key] = nil end end)
end

-- Seconds before this client could start one more CAT reply (NET-02: one per minute): the replies already
-- scheduled, plus one minute for every reply it has promised (an ack sent or on its way) and not scheduled yet.
local function catBusyFor(except)
	local w = max(0, (state.catFreeAt or 0) - now())
	for _, a in pairs(state.answers) do
		if a ~= except and a.kind == "CAT" and a.n > 0 and (a.phase == "acking" or a.phase == "confirming") then
			w = w + Sync.CAT_EVERY
		end
	end
	return w
end

local function detSlotsUsed()
	local t, keep = now(), {}
	for _, at in ipairs(state.detLog) do if t - at < 60 then keep[#keep + 1] = at end end
	state.detLog = keep
	return #keep
end

local function sendCat(a)
	a.phase = "sending"
	state.stats.catReplies = state.stats.catReplies + 1
	local items, total = a.items, #a.items
	local of = max(1, math.ceil(total / Sync.BATCH))
	local t = clock()
	for i = 1, of do
		local batch, ages = {}, {}
		for j = (i - 1) * Sync.BATCH + 1, min(i * Sync.BATCH, total) do
			local sum = items[j]
			batch[#batch + 1] = sum
			local entry = ns.Catalog:Get(sum.k)
			ages[#ages + 1] = entry and max(0, t - (entry.annAt or t)) or 0
		end
		if #batch > 0 then
			ns.Transport:Send("WHISPER", { t = "CAT", nonce = a.nonce, items = batch, age = ages, i = i, of = of, n = total },
				{ target = a.to, rateGroup = "CAT:" .. a.key })
			state.stats.catsSent = state.stats.catsSent + 1
		end
	end
end

local function sendDet(a)
	a.phase = "sending"
	state.detLog[#state.detLog + 1] = now()
	state.stats.detReplies = state.stats.detReplies + 1
	local msg = {}
	for field, value in pairs(a.det) do msg[field] = value end
	msg.t, msg.nonce = "DET", a.nonce
	ns.Transport:Send("WHISPER", msg, { target = a.to })
end

local function deliver(a)
	if a.rival and beats(a.rival, { n = a.n, h = myHash(), w = a.w }) then
		a.phase = "cancelled"
		state.stats.yielded = state.stats.yielded + 1
		return
	end
	if a.kind == "CAT" then
		if a.n == 0 then a.phase = "done" return end
		-- the reply takes the next free minute; the Transport counts it from the moment its first batch leaves
		local t = now()
		local start = max(t, state.catFreeAt or 0)
		state.catFreeAt = start + Sync.CAT_EVERY + 1
		a.phase = "scheduled"
		if start <= t then return sendCat(a) end
		after(start - t, function() if a.phase == "scheduled" then sendCat(a) end end)
	else
		sendDet(a)
	end
end

-- Our ack is out: wait CONFIRM seconds for a better competing ack, then send.
local function onOwnAckSent(a)
	if a.phase ~= "acking" then return end
	a.phase = "confirming"
	state.stats.acksSent = state.stats.acksSent + 1
	after(Sync.CONFIRM, function()
		if a.phase == "confirming" then deliver(a) end
	end)
end

local function fireAck(a)
	if a.phase ~= "waiting" then return end
	a.phase = "acking"
	local msg
	if a.kind == "CAT" then
		local w = floor(catBusyFor(a) + 0.5)
		a.w = w
		msg = { t = "CATACK", to = a.to, nonce = a.nonce, n = a.n, w = w > 0 and w or nil }
	else
		msg = { t = "DETACK", to = a.to, nonce = a.nonce, r = a.n }
	end
	if a.direct then
		-- a whispered request: no election, the ack goes back by whisper and the answer follows
		ns.Transport:Send("WHISPER", msg, { target = a.to })
		a.phase = "confirming"
		state.stats.acksSent = state.stats.acksSent + 1
		return deliver(a)
	end
	a.ackItem = ns.Transport:Send("CHANNEL", msg, {
		onSent = function() onOwnAckSent(a) end,
		onFail = function() if a.phase == "acking" then a.phase = "cancelled" end end,
	})
	if not a.ackItem then a.phase = "cancelled" end
end

-- Someone else acked the same request: cancel ours, or step back when theirs is better.
local function onCompetingAck(msg, sender, kind)
	local key = answerKey(msg.to, msg.nonce)
	local a = state.answers[key]
	if not a or a.kind ~= kind then return end
	local theirs = { n = tonumber(kind == "CAT" and msg.n or msg.r) or 0, h = peerHash(sender), w = tonumber(msg.w) or 0 }
	if not a.rival or beats(theirs, a.rival) then a.rival = theirs end
	if a.phase == "waiting" then
		-- "nothing new" is wrong when we have something; a peer that sends much later loses to us: answer now
		local mineW = a.kind == "CAT" and catBusyFor(a) or 0
		if (theirs.n == 0 and a.n > 0) or theirs.w - mineW > Sync.W_SLACK then return fireAck(a) end
		a.phase = "cancelled"
		state.stats.cancelled = state.stats.cancelled + 1
	elseif a.phase == "acking" then
		if a.ackItem and ns.Transport:Cancel(a.ackItem) then
			a.phase = "cancelled"
			state.stats.cancelled = state.stats.cancelled + 1
		end
	elseif a.phase == "confirming" then
		if beats(theirs, { n = a.n, h = myHash(), w = a.w }) then
			a.phase = "cancelled"
			state.stats.yielded = state.stats.yielded + 1
		end
	end
end

local function schedule(a, delay)
	state.answers[a.key] = a
	forgetLater(a.key, a)
	if a.direct then return fireAck(a) end
	after(delay, function() fireAck(a) end)
end

-- A whole CATREQ (all parts) from `sender`: work out what it lacks and maybe answer.
local function onDigest(sender, nonce, digest, dist)
	state.stats.requestsHeard = state.stats.requestsHeard + 1
	local key = answerKey(sender, nonce)
	if state.answers[key] then return end
	local direct = dist == "WHISPER"
	if not direct and listenOnly() then return end   -- we could not ack on the channel
	local items = ns.Catalog:Newer(digest)
	if not isDev() then
		local keep = {}
		for _, s in ipairs(items) do if not s.test then keep[#keep + 1] = s end end
		items = keep
	end
	local n = #items
	local a = { kind = "CAT", key = key, to = sender, nonce = nonce, items = items, n = n, phase = "waiting", direct = direct }
	if direct then return schedule(a, 0) end
	local lo, hi = Sync.REPLY_DELAY[1], Sync.REPLY_DELAY[2]
	local delay
	if n > 0 then
		-- more to send and a fresher catalog answer sooner; a peer that must wait for NET-02 answers later
		local share = min(n, Sync.MANY) / Sync.MANY
		local fresh = authoritative() and 0.5 or 1
		local w = catBusyFor()
		if w > 0 then
			-- after every free peer (they answer now, we only later), the least busy first
			delay = hi - 1.5 + 0.5 * min(w, 120) / 120 + spread(0.2)
		else
			delay = lo + 2.0 * (1 - share) * fresh + spread(hi - lo - 3.5)
		end
	else
		-- "nothing new": only a peer that finished a full sync, and only a few of them, after everybody else
		if not authoritative() then return end
		if random() > Sync.UPTODATE_ACKERS / max(Sync:PeerCount(), Sync.MIN_PEERS) then return end
		delay = hi - 0.8 + spread(0.8)
	end
	schedule(a, min(delay, hi))
end

local function onCatReq(msg, sender, dist)
	if isSelf(sender) then return end
	if type(msg.cat) ~= "table" then return end
	local n, p = tonumber(msg.n) or 1, tonumber(msg.p) or 1
	if n < 1 or n > Sync.MAX_PARTS or p < 1 or p > n or n ~= floor(n) or p ~= floor(p) then return end
	local key = answerKey(sender, msg.nonce)
	local digest
	if n == 1 then
		digest = {}
	else
		local parts = state.parts[key]
		if not parts then
			parts = { n = n, got = 0, have = {}, cat = {}, at = now() }
			state.parts[key] = parts
			after(Sync.PARTS_TTL, function() if state.parts[key] == parts then state.parts[key] = nil end end)
		end
		if parts.n ~= n or parts.have[p] then return end
		parts.have[p], parts.got = msg.cat, parts.got + 1
		if parts.got < n then return end
		state.parts[key] = nil
		digest = {}
		for i = 1, n do
			local cat = parts.have[i]
			for j = 1, #cat - 2, 3 do
				digest[#digest + 1] = { h = cat[j], rev = cat[j + 1], srev = cat[j + 2] }
			end
		end
		return onDigest(sender, msg.nonce, digest, dist)
	end
	local cat = msg.cat
	for j = 1, #cat - 2, 3 do digest[#digest + 1] = { h = cat[j], rev = cat[j + 1], srev = cat[j + 2] } end
	return onDigest(sender, msg.nonce, digest, dist)
end

local function onDetReq(msg, sender, dist)
	if isSelf(sender) then return end
	local key = answerKey(sender, msg.nonce)
	if state.answers[key] then return end
	local direct = dist == "WHISPER"
	if not direct and listenOnly() then return end
	local entry, status = ns.Catalog:Get(msg.k)
	local det = entry and entry.det
	if not det or status == "delisted" or (entry.sum.test and not isDev()) then return end
	local have = tonumber(msg.d) or 0
	if det.rev <= have or det.rev > msg.rev then return end
	if detSlotsUsed() >= Sync.DET_PER_MINUTE then return end
	local a = { kind = "DET", key = key, to = sender, nonce = msg.nonce, det = det, n = det.rev, phase = "waiting",
		direct = direct }
	local lo, hi = Sync.REPLY_DELAY[1], Sync.REPLY_DELAY[2]
	local base = det.rev == msg.rev and lo or lo + 1.5
	schedule(a, min(base + spread(hi - 1.5 - lo), hi))
end

---------------------------------------------------------------------------------------------------------------------
-- Details
---------------------------------------------------------------------------------------------------------------------

-- Asks the network for the detail of guild k. Returns true plus "cached" (nothing to do), "pending" (already asked)
-- or "requested", or false plus a reason ("unknown", "send: ..."). The detail lands in the catalog (CATALOG_UPDATED
-- k "detail"); after DETAIL_TIMEOUT seconds without it the Bus gets DETAIL_UNAVAILABLE(k).
function Sync:RequestDetail(k)
	local entry = ns.Catalog:Get(k)
	if not entry then return false, "unknown" end
	if entry.det and entry.det.rev >= entry.sum.rev then return true, "cached" end
	if state.details[k] then return true, "pending" end
	local nonce = random(1, 2147483647)
	local pending = { nonce = nonce, at = now() }
	state.details[k] = pending
	state.stats.detailsRequested = state.stats.detailsRequested + 1
	local msg = { t = "DETREQ", k = k, rev = entry.sum.rev, d = entry.det and entry.det.rev or 0, nonce = nonce }
	local function viaWhisper()
		local target = whisperTarget(k)
		if not target then return false end
		return ns.Transport:Send("WHISPER", msg, { target = target }) ~= nil
	end
	if listenOnly() then
		viaWhisper()
	else
		ns.Transport:Send("CHANNEL", msg, { onFail = function(reason)
			if state.details[k] == pending and (reason == "InvalidChannel" or reason == "listenonly") then viaWhisper() end
		end })
	end
	after(Sync.DETAIL_TIMEOUT, function()
		if state.details[k] == pending then
			state.details[k] = nil
			state.stats.unavailable = state.stats.unavailable + 1
			emit("DETAIL_UNAVAILABLE", k)
		end
	end)
	return true, "requested"   -- a request that could not leave is reported by the timeout too
end

local function onDet(msg, sender)
	local pending = state.details[msg.k]
	if not pending or msg.nonce ~= pending.nonce then return end
	local ok, why = ns.Catalog:PutDetail(msg, { sender = sender, dist = "WHISPER" })
	if ok or why == "unchanged" then
		state.details[msg.k] = nil
		state.stats.detailsReceived = state.stats.detailsReceived + 1
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------------------------------------------------
function Sync:OnMessage(msg, sender, dist)
	local t = msg.t
	if dist == "CHANNEL" then
		notePeer(sender)
		local req = state.req
		if req and req.waitingForPeer and not isSelf(sender) then
			req.waitingForPeer = nil
			disarm(req)
			resend(req, rnd(1, 3))
		end
		if t == "ANN" then return onAnn(msg, sender) end
		if t == "DEL" then return onDel(msg, sender) end
		if t == "CATREQ" then return onCatReq(msg, sender, dist) end
		if t == "DETREQ" then return onDetReq(msg, sender, dist) end
		if t == "CATACK" or t == "DETACK" then
			if isSelf(sender) then return end
			local mine = myName()
			if mine and baseName(msg.to) == mine then
				if t == "CATACK" then onAckForMe(msg, sender) end
				return
			end
			return onCompetingAck(msg, sender, t == "CATACK" and "CAT" or "DET")
		end
	elseif dist == "WHISPER" then
		if t == "CAT" then return onCat(msg, sender) end
		if t == "DET" then return onDet(msg, sender) end
		if t == "CATACK" then return onAckForMe(msg, sender) end
		if t == "CATREQ" then return onCatReq(msg, sender, dist) end
		if t == "DETREQ" then return onDetReq(msg, sender, dist) end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
Sync.AUTO = true   -- false: no automatic sync at CHANNEL_READY (the single-client tests switch it off)

-- CHANNEL_READY: after START_DELAY, a sync unless one finished less than FRESH seconds ago.
function Sync:OnChannelReady()
	if not Sync.AUTO then return end
	state.startGen = state.startGen + 1
	local gen = state.startGen
	after(rnd(Sync.START_DELAY[1], Sync.START_DELAY[2]), function()
		if gen ~= state.startGen or state.req then return end
		local last = Sync:LastFullSync()
		if last and clock() - last < Sync.FRESH then return end
		Sync:Request()
	end)
end

function Sync:Reset() resetState() end

---------------------------------------------------------------------------------------------------------------------
-- /gf debug announce (development builds)
---------------------------------------------------------------------------------------------------------------------
local function say(text) if ns.addon and ns.addon.Print then ns.addon:Print(text) end end

-- The test listing of this character: "AGF Test <name>" on its realm and faction, ownerId derived from the account
-- secret (stable across reloads, so other clients accept the next announcement, INT-03), rev = server time.
function Sync:TestListing()
	local P = C().Player
	local realm, faction, name = P.Realm(), P.Faction(), P.Name()
	if not realm or not faction or not name then return nil end
	local secret = ns.Config and ns.Config.db and ns.Config.db.account and ns.Config.db.account.accountSecret or ""
	local t = clock()
	local k = realm .. "|" .. faction .. "|AGF Test " .. name
	local sum = { k = k, rev = t, upd = t, first = t, own = ns.Normalize.Hash32Hex("test:" .. secret .. ":" .. name),
		sub = "Test listing from /gf debug announce", lang = 1, lang1 = 1, tags = { 11 }, pace = 1, days = 127,
		t0 = 0, t1 = 0, rec = 1, apps = false, newb = true, minL = 1, st = { m = 1, a7 = 1 }, srev = t - t % 3600,
		test = true }
	local det = { k = k, rev = t, desc = "A test listing sent by a development build. Release builds never show it." }
	return sum, det
end

function Sync:DebugAnnounce()
	local L = ns.L
	if not isDev() then return say(L["ANNOUNCE_DEV_ONLY"]) end
	local sum, det = Sync:TestListing()
	if not sum then return say(L["ANNOUNCE_FAILED"]:format("no realm or faction")) end
	local item, why = Sync:Announce(sum, { test = true, onFail = function(reason)
		say(L["ANNOUNCE_FAILED"]:format(tostring(reason)))
	end })
	if not item then return say(L["ANNOUNCE_FAILED"]:format(tostring(why))) end
	ns.Catalog:PutDetail(det)
	say(L["ANNOUNCE_SENT"]:format(sum.k:match("[^|]+$")))
end

---------------------------------------------------------------------------------------------------------------------
-- /gf debug
---------------------------------------------------------------------------------------------------------------------
function Sync:DebugLines()
	local s = state.stats
	local last = Sync:LastFullSync()
	local r = state.lastResult
	return {
		("Sync: %s, last full sync %s, peers heard %d%s"):format(state.req and ("round " .. state.req.rounds) or "idle",
			last and (("%d min ago"):format(floor((clock() - last) / 60))) or "never", Sync:PeerCount(),
			isDev() and ", development build" or ""),
		("  requests %d (rounds %d, retries %d), received %d summaries (%d new), duplicate batches %d%s"):format(
			s.requestsSent, s.rounds, s.retries, s.received, s.changed, s.duplicateCats,
			r and (", last: " .. (r.full and "complete" or "gave up") .. " (" .. tostring(r.why) .. ")") or ""),
		("  answers: heard %d, acks %d, cancelled %d, stepped back %d, CAT replies %d (%d batches), DET %d"):format(
			s.requestsHeard, s.acksSent, s.cancelled, s.yielded, s.catReplies, s.catsSent, s.detReplies),
		("  ANN %d (rejected %d), DEL %d, test listings ignored %d, details asked %d (got %d, unavailable %d)"):format(
			s.ann, s.annRejected, s.del, s.testIgnored, s.detailsRequested, s.detailsReceived, s.unavailable),
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------------------------------------
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(msg, sender, dist) Sync:OnMessage(msg, sender, dist) end)
	ns.Bus:On("CHANNEL_READY", function() Sync:OnChannelReady() end)
end
if ns.addon then
	ns.addon.Sync = Sync
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Sync", function() return Sync:DebugLines() end) end
end
