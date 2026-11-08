-- Transport (M1.7): the send queue with its limits (NET-01..NET-04), lockdown and read-only hold, keyed coalescing,
-- BULK expiry, retries, listen-only mode and the receive path. Most tests replace the wire with a recorder so every
-- timing is exact; the last groups run through the real ChatThrottleLib and the mock client.
local function Tr() return AzerothGuildFinder.Transport end
local function Bus() return AzerothGuildFinder.Bus end
local function Codec() return AzerothGuildFinder.Codec end
-- the game is not built yet when this file loads: look the codes up when a test runs
local R = setmetatable({}, { __index = function(_, name) return Enum.SendAddonMessageResult[name] end })

local function ann(k, rev, pad)
	return { t = "ANN", k = k or "g1", rev = rev or 1, note = pad and string.rep("abcdefgh", pad) or nil }
end
local function det(k) return { t = "DET", k = k or "g1", rev = 1 } end
local function cat() return { t = "CAT", nonce = 1, items = {} } end

-- Replaces the wire with a recorder. `results` (optional) are the codes of the next sends, "hold" keeps a send
-- unanswered (call W.answer(n, code) later); anything left over answers Success.
local function fakeWire(results)
	local W = { calls = {}, results = results or {}, open = {} }
	Tr().wire = function(prio, text, dist, target, done)
		local call = { prio = prio, text = text, dist = dist, target = target, time = GetTime(), bytes = #text }
		W.calls[#W.calls + 1] = call
		local r = table.remove(W.results, 1)
		if r == "hold" then W.open[#W.calls] = done return end
		done(r == nil and R.Success or r)
	end
	function W.answer(n, code) W.open[n](code) W.open[n] = nil end
	function W.msg(n) return (Codec():Decode(W.calls[n].text)) end
	function W.types()
		local out = {}
		for i = 1, #W.calls do out[i] = W.msg(i).t end
		return out
	end
	return W
end

local function withChannel(id)
	Tr().channelId = function() return id or 1 end
end

local function listen(event)
	local seen = {}
	Bus():On(event, function(...) seen[#seen + 1] = { ... } end)
	return seen
end

describe("Send validation", function()
	it("rejects a bad distribution, shape, priority and whisper target", function()
		local t = Tr()
		local item, why = t:Send("RAID", ann())
		eq(item, nil); eq(why, "dist")
		item, why = t:Send("GUILD", "text")
		eq(item, nil); eq(why, "shape")
		item, why = t:Send("GUILD", ann(), { prio = "URGENT" })
		eq(item, nil); eq(why, "prio")
		item, why = t:Send("WHISPER", cat())
		eq(item, nil); eq(why, "target")
		item, why = t:Send("WHISPER", cat(), { target = "" })
		eq(why, "target")
		eq(t:Pending(), 0)
	end)

	it("rejects what the codec rejects and counts it", function()
		local t = Tr()
		local item, why = t:Send("GUILD", { t = "NOPE" })
		eq(item, nil); matches(why, "^encode: ")
		item, why = t:Send("GUILD", { t = "ANN", k = 5, rev = 1 })
		matches(why, "^encode: ")
		eq(t:Stats().encodeFailed, 2)
	end)

	it("rejects a payload above the codec limit", function()
		local noise, seed = {}, 3
		for i = 1, 9000 do seed = (seed * 1103515245 + 12345) % 2147483648; noise[i] = string.char(seed % 256) end
		local item, why = Tr():Send("GUILD", { t = "DET", k = "k", rev = 1, desc = table.concat(noise) })
		eq(item, nil)
		truthy(why == "size" or why:find("^encode: "), why)
	end)

	it("takes its default priority from the message type", function()
		local t = Tr()
		eq(t:Send("GUILD", { t = "APPLY", id = "a", k = "k" }).prio, "ALERT")
		eq(t:Send("GUILD", det()).prio, "NORMAL")
		eq(t:Send("GUILD", ann()).prio, "BULK")
		eq(t:Send("GUILD", { t = "GLREQ", rev = 1 }).prio, "NORMAL")
		eq(t:Send("GUILD", ann(), { prio = "ALERT" }).prio, "ALERT")
	end)

	it("hands the message to the wire with its priority, distribution and target", function()
		local W = fakeWire()
		withChannel(4)
		Tr():Send("WHISPER", { t = "APPLY", id = "a", k = "k" }, { target = "Someone-Realm" })
		Tr():Send("GUILD", { t = "GLIST", k = "k", rev = 1 })
		Tr():Send("OFFICER", { t = "APPSYNC" })
		Tr():Send("CHANNEL", ann())
		Mock.Advance(2)
		eq(#W.calls, 4)
		eq(W.calls[1].dist, "WHISPER"); eq(W.calls[1].target, "Someone-Realm"); eq(W.calls[1].prio, "ALERT")
		eq(W.calls[2].dist, "GUILD"); eq(W.calls[2].target, nil); eq(W.calls[2].prio, "NORMAL")
		eq(W.calls[3].dist, "OFFICER")
		eq(W.calls[4].dist, "CHANNEL"); eq(W.calls[4].target, 4); eq(W.calls[4].prio, "BULK")
		eq(W.msg(4).t, "ANN")
	end)

	it("calls onSent once the wire says it went out", function()
		fakeWire()
		local sent, failed = 0, 0
		Tr():Send("GUILD", ann(), { onSent = function() sent = sent + 1 end, onFail = function() failed = failed + 1 end })
		eq(sent, 0)
		Mock.Advance(1)
		eq(sent, 1); eq(failed, 0)
		eq(Tr():Stats().sent, 1)
		truthy(Tr():Stats().sentBytes > 0)
	end)

	it("a failing callback goes to the error handler, not into the queue", function()
		fakeWire()
		Tr():Send("GUILD", ann("a"), { onSent = function() error("boom") end })
		Tr():Send("GUILD", ann("b"))
		Mock.Advance(1)
		eq(Tr():Stats().sent, 2)
		eq(Tr():Stats().callbackErrors, 1)
		eq(#Mock.errors, 1)
		contains(Mock.errors[1].message, "boom")
		for i = #Mock.errors, 1, -1 do Mock.errors[i] = nil end
	end)

	it("Cancel withdraws a waiting message", function()
		local W = fakeWire()
		Mock.chat.lockdown = true
		local reason
		local item = Tr():Send("GUILD", ann(), { onFail = function(r) reason = r end })
		truthy(Tr():Cancel(item))
		falsy(Tr():Cancel(item))
		eq(reason, "cancelled")
		eq(Tr():Pending(), 0)
		Mock.chat.lockdown = false
		Mock.Advance(1)
		eq(#W.calls, 0)
		eq(Tr():Stats().dropped, 0)
	end)

	it("stops its timer when the queue is empty", function()
		fakeWire()
		local base = Mock.PendingTimers()
		Tr():Send("GUILD", ann())
		eq(Mock.PendingTimers(), base + 1)
		Mock.Advance(1)
		eq(Mock.PendingTimers(), base)
	end)
end)

describe("NET-01: channel gap and byte budget", function()
	it("sends at most one CHANNEL message per gap", function()
		local W = fakeWire()
		withChannel()
		for i = 1, 4 do Tr():Send("CHANNEL", ann("g" .. i)) end
		Mock.Advance(10)
		eq(#W.calls, 4)
		for i = 2, 4 do
			local d = W.calls[i].time - W.calls[i - 1].time
			truthy(d >= 1.2 - 1e-6, "gap " .. d)
			truthy(d < 1.2 + 0.25, "gap " .. d)
		end
	end)

	it("reads the gap as a setting", function()
		local W = fakeWire()
		withChannel()
		Tr().CHANNEL_GAP = 3
		Tr():Send("CHANNEL", ann("a")); Tr():Send("CHANNEL", ann("b"))
		Mock.Advance(10)
		truthy(W.calls[2].time - W.calls[1].time >= 3 - 1e-6)
	end)

	it("does not apply the gap to GUILD, WHISPER and OFFICER", function()
		local W = fakeWire()
		for i = 1, 5 do Tr():Send("GUILD", ann("g" .. i)) end
		Mock.Advance(0.5)
		eq(#W.calls, 5)
	end)

	it("keeps CHANNEL messages queued until a channel id exists", function()
		local W = fakeWire()
		Tr():Send("CHANNEL", ann())
		Mock.Advance(5)
		eq(#W.calls, 0)
		eq(Tr():Pending("CHANNEL"), 1)
		withChannel(2)
		Mock.Advance(1)
		eq(#W.calls, 1)
		eq(W.calls[1].target, 2)
	end)

	it("holds the channel byte budget over a rolling minute", function()
		local W = fakeWire()
		withChannel()
		local size = Tr():Send("CHANNEL", ann("a", 1, 5)).size
		Tr().CHANNEL_BUDGET = size * 2 + 1   -- room for two
		Tr():Send("CHANNEL", ann("b", 1, 5)); Tr():Send("CHANNEL", ann("c", 1, 5))
		Mock.Advance(20)
		eq(#W.calls, 2)
		eq(Tr():Pending("CHANNEL"), 1)
		Mock.Advance(45)   -- the first message is now older than a minute
		eq(#W.calls, 3)
		truthy(W.calls[3].time - W.calls[1].time >= 60 - 1e-6)
	end)

	it("does not count explicit replies against the budget", function()
		local W = fakeWire()
		withChannel()
		local size = Tr():Send("CHANNEL", ann("a", 1, 5)).size
		Tr().CHANNEL_BUDGET = size + 1
		Tr():Send("CHANNEL", ann("b", 1, 5))
		Tr():Send("CHANNEL", { t = "CATACK", to = "Someone-Realm", nonce = 1 })
		Tr():Send("CHANNEL", { t = "DETACK", to = "Someone-Realm", nonce = 2 })
		Mock.Advance(10)
		deepEq(W.types(), { "CATACK", "DETACK", "ANN" })   -- ALERT first; the second ANN waits for the budget
		eq(Tr():Pending("CHANNEL"), 1)
	end)

	it("lets a reply pass a budget-blocked message but not the other way round", function()
		local W = fakeWire()
		withChannel()
		local size = Tr():Send("CHANNEL", ann("a", 1, 5)).size
		Tr().CHANNEL_BUDGET = size + 1
		Tr():Send("CHANNEL", ann("b", 1, 5))
		Mock.Advance(3)
		eq(#W.calls, 1)
		Tr():Send("CHANNEL", ann("c", 1, 5), { prio = "NORMAL" })   -- blocked by the budget
		Tr():Send("CHANNEL", { t = "CATACK", to = "x", nonce = 1 }) -- a reply goes anyway
		Mock.Advance(3)
		deepEq(W.types(), { "ANN", "CATACK" })
		eq(Tr():Pending("CHANNEL"), 2)
	end)

	it("sends a message larger than the whole budget when nothing else was sent", function()
		local W = fakeWire()
		withChannel()
		Tr().CHANNEL_BUDGET = 10
		Tr():Send("CHANNEL", ann("a", 1, 5)); Tr():Send("CHANNEL", ann("b", 1, 5))
		Mock.Advance(5)
		eq(#W.calls, 1)
		Mock.Advance(61)
		eq(#W.calls, 2)
	end)

	it("stays inside gap and budget under load", function()
		local W = fakeWire()
		withChannel()
		Tr().CHANNEL_BUDGET = 1024
		for i = 1, 100 do Tr():Send("CHANNEL", ann("g" .. i, i, 10)) end   -- ~130 bytes each, all BULK
		Mock.Advance(300, 0.2)
		local n = #W.calls
		truthy(n > 20 and n < 100, "sent " .. n)
		for i = 1, n do
			local t0, bytes = W.calls[i].time, 0
			for j = 1, i do
				if t0 - W.calls[j].time < 60 then bytes = bytes + W.calls[j].bytes end
			end
			truthy(bytes <= Tr().CHANNEL_BUDGET, ("window of message %d holds %d bytes"):format(i, bytes))
			if i > 1 then truthy(t0 - W.calls[i - 1].time >= 1.2 - 1e-6) end
		end
		-- the rest waits at most the BULK lifetime, then goes
		Mock.Advance(400, 0.2)
		local st = Tr():Stats()
		eq(Tr():Pending(), 0)
		eq(st.sent + (st.droppedBy.expired or 0), 100)
		truthy((st.droppedBy.expired or 0) > 0)
	end)
end)

describe("NET-02: CAT and DET replies", function()
	it("sends one CAT per minute", function()
		local W = fakeWire()
		for i = 1, 3 do Tr():Send("WHISPER", cat(), { target = "P" .. i }) end
		Mock.Advance(5)
		eq(#W.calls, 1)
		Mock.Advance(56)
		eq(#W.calls, 2)
		truthy(W.calls[2].time - W.calls[1].time >= 60 - 1e-6)
		Mock.Advance(60)
		eq(#W.calls, 3)
	end)

	it("sends three DET per minute", function()
		local W = fakeWire()
		for i = 1, 5 do Tr():Send("WHISPER", det("g" .. i), { target = "P" .. i }) end
		Mock.Advance(5)
		eq(#W.calls, 3)
		Mock.Advance(56)
		eq(#W.calls, 5)
	end)

	it("keeps the CAT and DET budgets apart, and other types are free", function()
		local W = fakeWire()
		Tr():Send("WHISPER", cat(), { target = "A" })
		Tr():Send("WHISPER", cat(), { target = "B" })
		Tr():Send("WHISPER", det(), { target = "A" })
		for i = 1, 4 do Tr():Send("WHISPER", { t = "APPACK", id = "x" .. i, state = "sent" }, { target = "A" }) end
		Mock.Advance(2)
		eq(#W.calls, 6)   -- 1 CAT + 1 DET + 4 APPACK; the second CAT waits
		eq(Tr():Pending(), 1)
	end)

	it("gives the allowance back when the send fails", function()
		local W = fakeWire({ R.TargetOffline })
		local reason
		Tr():Send("WHISPER", cat(), { target = "A", onFail = function(r) reason = r end })
		Tr():Send("WHISPER", cat(), { target = "B" })
		Mock.Advance(2)
		eq(reason, "TargetOffline")
		eq(#W.calls, 2)   -- the failed one did not use up the minute
	end)
end)

describe("NET-03: lockdown, restrictions, keys and expiry", function()
	it("holds every message during a chat lockdown and releases them afterwards", function()
		local W = fakeWire()
		withChannel()
		Mock.chat.lockdown = true
		Tr():Send("GUILD", { t = "GLIST", k = "k", rev = 1 })
		Tr():Send("CHANNEL", ann())
		Tr():Send("WHISPER", { t = "APPLY", id = "a", k = "k" }, { target = "P" })
		Mock.Advance(30)
		eq(#W.calls, 0)
		eq(Tr():Pending(), 3)
		eq(Tr():Stats().held, "lockdown")
		Mock.chat.lockdown = false
		Mock.Advance(2)
		eq(#W.calls, 3)
		eq(Tr():Pending(), 0)
		eq(Tr():Stats().held, nil)
		deepEq(W.types(), { "APPLY", "GLIST", "ANN" })   -- by priority
	end)

	it("holds during an active addon restriction (combat, encounter...)", function()
		local W = fakeWire()
		Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1 }
		local active = true
		C_RestrictedActions = { GetAddOnRestrictionState = function(kind) return (kind == 1 and active) and 1 or 0 end }
		Tr():Send("GUILD", ann())
		Mock.Advance(5)
		eq(#W.calls, 0)
		eq(Tr():Stats().held, "Encounter")
		active = false
		Mock.Advance(1)
		eq(#W.calls, 1)
	end)

	it("reports the read-only state, holds, and releases", function()
		local W = fakeWire()
		local events = listen("TRANSPORT_READ_ONLY")
		Mock.chat.restricted = true
		Tr():Send("GUILD", ann())
		Mock.Advance(3)
		eq(#W.calls, 0)
		truthy(Tr():IsReadOnly())
		eq(#events, 1); eq(events[1][1], true)
		Mock.chat.restricted = false
		Mock.Advance(1)
		falsy(Tr():IsReadOnly())
		eq(#W.calls, 1)
		eq(#events, 2); eq(events[2][1], false)
	end)

	it("keeps only the latest message per key", function()
		local W = fakeWire()
		Mock.chat.lockdown = true
		local replaced = {}
		local function opts() return { key = "ANN|g1", onFail = function(r) replaced[#replaced + 1] = r end } end
		Tr():Send("GUILD", ann("g1", 1), opts())
		Tr():Send("GUILD", ann("g1", 2), opts())
		Tr():Send("GUILD", ann("g1", 3), opts())
		Tr():Send("GUILD", ann("g2", 1), { key = "ANN|g2" })
		eq(Tr():Pending(), 2)
		deepEq(replaced, { "replaced", "replaced" })
		eq(Tr():Stats().coalesced, 2)
		eq(Tr():Stats().dropped, 0)
		Mock.chat.lockdown = false
		Mock.Advance(1)
		eq(#W.calls, 2)
		local revs = {}
		for i = 1, 2 do local m = W.msg(i); revs[m.k] = m.rev end
		deepEq(revs, { g1 = 3, g2 = 1 })
	end)

	it("a message already handed to the wire does not block a new one with its key", function()
		local W = fakeWire({ "hold" })
		Tr():Send("GUILD", ann("g1", 1), { key = "K" })
		Mock.Advance(1)
		eq(#W.calls, 1)
		Tr():Send("GUILD", ann("g1", 2), { key = "K" })
		Mock.Advance(1)
		eq(#W.calls, 2)
		eq(Tr():Stats().coalesced, 0)
	end)

	it("drops BULK messages older than ten minutes, keeps the others", function()
		local W = fakeWire()
		Mock.chat.lockdown = true
		local why = {}
		Tr():Send("GUILD", ann("a"), { onFail = function(r) why[#why + 1] = r end })                       -- BULK
		Tr():Send("GUILD", det("b"), { onFail = function(r) why[#why + 1] = r end })                       -- NORMAL
		Mock.Advance(599)
		eq(Tr():Pending(), 2)
		Mock.Advance(2)
		eq(Tr():Pending(), 1)
		deepEq(why, { "expired" })
		eq(Tr():Stats().droppedBy.expired, 1)
		Mock.chat.lockdown = false
		Mock.Advance(1)
		deepEq(W.types(), { "DET" })
	end)

	it("lets the caller set a lifetime for any message", function()
		fakeWire()
		Mock.chat.lockdown = true
		Tr():Send("GUILD", det(), { ttl = 30 })
		Mock.Advance(29)
		eq(Tr():Pending(), 1)
		Mock.Advance(2)
		eq(Tr():Pending(), 0)
	end)

	it("treats a lockdown refusal of the client as a wait, not a failure or a try", function()
		local W = fakeWire({ R.AddOnMessageLockdown, R.AddOnMessageLockdown })
		local sent = 0
		Tr():Send("GUILD", ann(), { onSent = function() sent = sent + 1 end })
		Mock.Advance(1)
		eq(#W.calls, 1)
		eq(sent, 0)
		eq(Tr():Pending(), 1)
		Mock.Advance(5)
		eq(#W.calls, 3)
		eq(sent, 1)
		eq(Tr():Stats().failed, 0)
		eq(Tr():Stats().retried, 0)
	end)

	it("is bounded: a full queue drops the oldest message of the lowest priority", function()
		fakeWire()
		Mock.chat.lockdown = true
		Tr().QUEUE_MAX = 3
		local why = {}
		local function opts(n) return { onFail = function(r) why[#why + 1] = n .. ":" .. r end } end
		Tr():Send("GUILD", ann("a"), opts("a"))
		Tr():Send("GUILD", ann("b"), opts("b"))
		Tr():Send("GUILD", det("c"), opts("c"))
		Tr():Send("GUILD", ann("d"), opts("d"))       -- evicts a (oldest BULK)
		deepEq(why, { "a:overflow" })
		local item, reason = Tr():Send("GUILD", ann("e"), { prio = "BULK" })   -- evicts b
		truthy(item)
		deepEq(why, { "a:overflow", "b:overflow" })
		Tr():Send("GUILD", { t = "APPLY", id = "a", k = "k" }, opts("apply"))  -- ALERT evicts d
		deepEq(why, { "a:overflow", "b:overflow", "d:overflow" })
		-- a BULK message cannot evict higher priorities: with nothing but ALERT queued it is refused
		Tr():Send("GUILD", { t = "APPLY", id = "b", k = "k" })
		Tr():Send("GUILD", { t = "APPLY", id = "c", k = "k" })
		local refused, why2 = Tr():Send("GUILD", ann("f"), opts("f"))
		eq(refused, nil); eq(why2, "full")
		eq(Tr():Pending(), 3)
	end)
end)

describe("NET-04: throttle results", function()
	it("retries after four gaps and reports success", function()
		local W = fakeWire({ R.ChannelThrottle })
		withChannel()
		local sent = 0
		Tr():Send("CHANNEL", ann(), { onSent = function() sent = sent + 1 end })
		Mock.Advance(10)
		eq(#W.calls, 2)
		truthy(W.calls[2].time - W.calls[1].time >= 4 * 1.2 - 1e-6)
		eq(sent, 1)
		local st = Tr():Stats()
		eq(st.throttled, 1); eq(st.retried, 1); eq(st.failed, 0); eq(st.sent, 1)
	end)

	it("gives up after three retries", function()
		local W = fakeWire({ R.ChannelThrottle, R.ChannelThrottle, R.ChannelThrottle, R.ChannelThrottle })
		withChannel()
		local sent, reason = 0, nil
		Tr():Send("CHANNEL", ann(), { onSent = function() sent = sent + 1 end, onFail = function(r) reason = r end })
		Mock.Advance(60)
		eq(#W.calls, 4)   -- the first try and three retries
		eq(sent, 0)
		eq(reason, "ChannelThrottle")
		local st = Tr():Stats()
		eq(st.throttled, 4); eq(st.retried, 3); eq(st.failed, 1)
		eq(Tr():Pending(), 0)
	end)

	it("also waits for the whole channel, and a throttle retry does not use the budget twice", function()
		local W = fakeWire({ R.ChannelThrottle })
		withChannel()
		local size = Tr():Send("CHANNEL", ann("a", 1, 5)).size
		Tr().CHANNEL_BUDGET = size * 2 + 1
		Tr():Send("CHANNEL", ann("b", 1, 5))
		Mock.Advance(3)
		eq(#W.calls, 1)   -- b waits: the channel is held after the throttle
		Mock.Advance(10)
		eq(#W.calls, 3)
		truthy(W.calls[2].time - W.calls[1].time >= 4.8 - 1e-6)
	end)

	it("does not retry other errors", function()
		local W = fakeWire({ R.GeneralError })
		local reason
		Tr():Send("GUILD", ann(), { onFail = function(r) reason = r end })
		Mock.Advance(20)
		eq(#W.calls, 1)
		eq(reason, "GeneralError")
		eq(Tr():Stats().failed, 1)
		eq(Tr():Stats().droppedBy.GeneralError, 1)
	end)

	it("reports a wire that never reached the client", function()
		local reason
		Tr().wire = function(_, _, _, _, done) done("nolib") end
		Tr():Send("GUILD", ann(), { onFail = function(r) reason = r end })
		Mock.Advance(1)
		eq(reason, "nolib")
	end)
end)

describe("Listen-only mode", function()
	it("switches on InvalidChannel, drops CHANNEL traffic and keeps the other distributions", function()
		local W = fakeWire({ R.InvalidChannel })
		withChannel()
		local events = listen("TRANSPORT_LISTEN_ONLY")
		local why = {}
		local function opts(n) return { onFail = function(r) why[#why + 1] = n .. ":" .. r end } end
		Tr():Send("CHANNEL", ann("a"), opts("a"))
		Tr():Send("CHANNEL", ann("b"), opts("b"))
		Tr():Send("CHANNEL", ann("c"), opts("c"))
		Mock.Advance(2)
		eq(#W.calls, 1)
		local active, reason = Tr():IsListenOnly()
		truthy(active); eq(reason, "InvalidChannel")
		deepEq(why, { "b:listenonly", "c:listenonly", "a:InvalidChannel" })
		eq(#events, 1); eq(events[1][1], true); eq(events[1][2], "InvalidChannel")
		local st = Tr():Stats()
		truthy(st.listenOnly); eq(st.listenReason, "InvalidChannel")
		eq(st.failed, 1); eq(st.droppedBy.listenonly, 2)
		eq(Tr():Pending(), 0)

		local item, why2 = Tr():Send("CHANNEL", ann("d"), opts("d"))
		eq(item, nil); eq(why2, "listenonly")
		eq(why[#why], "d:listenonly")
		Tr():Send("WHISPER", cat(), { target = "P" })
		Tr():Send("GUILD", ann("e"))
		Mock.Advance(2)
		deepEq(W.types(), { "ANN", "CAT", "ANN" })
		eq(W.calls[2].dist, "WHISPER"); eq(W.calls[3].dist, "GUILD")
		eq(#events, 1)
	end)

	it("is not triggered by InvalidChannel on other distributions", function()
		fakeWire({ R.InvalidChannel })
		Tr():Send("GUILD", ann())
		Mock.Advance(1)
		falsy(Tr():IsListenOnly())
	end)

	it("lets one message probe after an hour and leaves the mode when it goes through", function()
		local W = fakeWire({ R.InvalidChannel })
		withChannel()
		local events = listen("TRANSPORT_LISTEN_ONLY")
		Tr():Send("CHANNEL", ann("a"))
		Mock.Advance(2)
		truthy(Tr():IsListenOnly())
		Mock.Advance(3590, 1)
		eq(Tr():Send("CHANNEL", ann("early")), nil)
		Mock.Advance(15, 1)
		local probe = Tr():Send("CHANNEL", ann("probe"))
		truthy(probe)
		local second, why = Tr():Send("CHANNEL", ann("second"))
		eq(second, nil); eq(why, "listenonly")   -- one probe at a time
		Mock.Advance(3)
		eq(#W.calls, 2)
		falsy(Tr():IsListenOnly())
		eq(#events, 2); eq(events[2][1], false)
		truthy(Tr():Send("CHANNEL", ann("normal")))
	end)

	it("stays in the mode when the probe fails, and waits another hour", function()
		local W = fakeWire({ R.InvalidChannel, R.InvalidChannel })
		withChannel()
		local events = listen("TRANSPORT_LISTEN_ONLY")
		Tr():Send("CHANNEL", ann("a"))
		Mock.Advance(2)
		Mock.Advance(3700, 1)
		truthy(Tr():Send("CHANNEL", ann("probe")))
		Mock.Advance(3)
		eq(#W.calls, 2)
		truthy(Tr():IsListenOnly())
		eq(#events, 1)   -- no second event: nothing changed
		local item = Tr():Send("CHANNEL", ann("again"))
		eq(item, nil)
		Mock.Advance(3601, 1)
		truthy(Tr():Send("CHANNEL", ann("probe2")))
	end)

	it("lets the next message probe again when the probe never got sent", function()
		fakeWire({ R.InvalidChannel })
		withChannel()
		Tr():Send("CHANNEL", ann("a"))
		Mock.Advance(2)
		Mock.Advance(3700, 1)
		local probe = Tr():Send("CHANNEL", ann("probe"))
		truthy(probe)
		truthy(Tr():Cancel(probe))
		truthy(Tr():Send("CHANNEL", ann("probe again")))
	end)

	it("RetryChannel and ClearListenOnly leave the wait short", function()
		fakeWire({ R.InvalidChannel })
		withChannel()
		Tr():Send("CHANNEL", ann("a"))
		Mock.Advance(2)
		eq(Tr():Send("CHANNEL", ann("b")), nil)
		Tr():RetryChannel()
		truthy(Tr():Send("CHANNEL", ann("c")))
		Mock.Advance(2)
		falsy(Tr():IsListenOnly())

		Tr().wire = function(_, _, _, _, done) done(R.InvalidChannel) end
		Tr():Send("CHANNEL", ann("d"))
		Mock.Advance(3)
		truthy(Tr():IsListenOnly())
		truthy(Tr():ClearListenOnly())
		falsy(Tr():ClearListenOnly())
		truthy(Tr():Send("CHANNEL", ann("e")))
	end)
end)

describe("Receive path", function()
	local function payload(t, fields) return Codec():Encode(t, fields) end

	it("decodes a message from AceComm and puts it on the Bus with the sender and the distribution", function()
		local seen = listen("NET_MESSAGE")
		truthy(Mock.chat.Receive("AzGF", payload("GLREQ", { rev = 4 }), "GUILD", "Sender-Realm"))
		eq(#seen, 1)
		local msg, sender, dist = seen[1][1], seen[1][2], seen[1][3]
		eq(msg.t, "GLREQ"); eq(msg.rev, 4); eq(dist, "GUILD")
		eq(sender, "Sender-Realm")   -- as AceComm gives it (Ambiguate)
		eq(Tr():Stats().received, 1)
		eq(Tr():Stats().rxDropped, 0)
	end)

	it("ignores other prefixes", function()
		local seen = listen("NET_MESSAGE")
		C_ChatInfo.RegisterAddonMessagePrefix("Other")
		Mock.chat.Receive("Other", payload("GLREQ", { rev = 4 }), "GUILD", "S-R")
		eq(#seen, 0)
		eq(Tr():Stats().received, 0)
	end)

	it("drops invalid, oversized and unknown messages, counts them and says nothing", function()
		local seen = listen("NET_MESSAGE")
		Mock.ClearOutput()
		Mock.chat.Receive("AzGF", "###", "GUILD", "S-R")
		Mock.chat.Receive("AzGF", string.rep("A", Codec().MAX_PAYLOAD + 4), "GUILD", "S-R")
		Mock.chat.Receive("AzGF", C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR({ v = 1, t = "WHAT" })), "GUILD", "S-R")
		Mock.chat.Receive("AzGF", C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR({ v = 1, t = "ANN" })), "CHANNEL", "S-R")
		Mock.chat.Receive("AzGF", "", "GUILD", "S-R")
		eq(#seen, 0)
		local st = Tr():Stats()
		eq(st.received, 5); eq(st.rxDropped, 5)
		eq(st.rxReasons.base64, 1); eq(st.rxReasons.size, 2); eq(st.rxReasons.type, 1); eq(st.rxReasons.invalid, 1)
		eq(#Mock.PlainOutput(), 0)
		eq(#Mock.errors, 0)
	end)

	it("drops a distribution the addon never uses", function()
		local seen = listen("NET_MESSAGE")
		Mock.chat.Receive("AzGF", payload("GLREQ", { rev = 1 }), "PARTY", "S-R")
		eq(#seen, 0)
		eq(Tr():Stats().rxReasons.dist, 1)
	end)

	it("announces a newer protocol once per session and does not deliver it", function()
		local seen, newer = listen("NET_MESSAGE"), listen("PROTOCOL_NEWER")
		local future = C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR({ v = 2, t = "ANN", k = "x", rev = 1 }))
		Mock.chat.Receive("AzGF", future, "CHANNEL", "S-R")
		Mock.chat.Receive("AzGF", future, "CHANNEL", "S-R")
		eq(#seen, 0)
		eq(#newer, 1)
		eq(Tr():Stats().rxNewer, 2)
		eq(Tr():Stats().rxDropped, 0)
		Mock.chat.Receive("AzGF", payload("GLREQ", { rev = 1 }), "GUILD", "S-R")
		eq(#seen, 1)
	end)

	it("a listener that raises does not stop the transport", function()
		Bus():On("NET_MESSAGE", function() error("listener") end)
		local seen = listen("NET_MESSAGE")
		Mock.chat.Receive("AzGF", payload("GLREQ", { rev = 1 }), "GUILD", "S-R")
		eq(#seen, 1)
		eq(Bus().errorCount, 1)
	end)

	it("never writes the sender anywhere it can be read", function()
		Mock.chat.Receive("AzGF", payload("GLREQ", { rev = 1 }), "GUILD", "Hidden-Realm")
		Mock.chat.Receive("AzGF", "###", "GUILD", "Hidden-Realm")
		Mock.ClearOutput()
		Mock.Slash("/gf debug")
		local text = table.concat(Mock.PlainOutput(), "\n")
		truthy(not text:find("Hidden", 1, true))
		truthy(not table.concat(Tr():DebugLines(), "\n"):find("Hidden", 1, true))
		eq(#Mock.errors, 0)
	end)
end)

describe("Through ChatThrottleLib and the mock client", function()
	local function warm() Mock.Advance(6) end   -- ChatThrottleLib clamps hard for five seconds after start-up

	it("sends GUILD, WHISPER and CHANNEL messages with the AzGF prefix", function()
		Mock.guild.Set({ name = "G" })
		Mock.chat.channels[3] = { name = "AzGuildFinder" }
		withChannel(3)
		warm()
		local sent = {}
		Tr():Send("GUILD", { t = "GLREQ", rev = 1 }, { onSent = function() sent[#sent + 1] = "guild" end })
		Tr():Send("WHISPER", cat(), { target = "Friend-Realm", onSent = function() sent[#sent + 1] = "whisper" end })
		Tr():Send("CHANNEL", ann(), { onSent = function() sent[#sent + 1] = "channel" end })
		Mock.Advance(3)
		local out = Mock.chat.SentWithPrefix("AzGF")
		eq(#out, 3)
		local byType = {}
		for _, e in ipairs(out) do byType[e.chatType] = e end
		eq(byType.GUILD.target, nil)
		eq(byType.WHISPER.target, "Friend-Realm")
		eq(byType.CHANNEL.target, 3)
		eq(#sent, 3)
		eq(Tr():Stats().sent, 3)
		eq(Codec():Decode(byType.CHANNEL.message).t, "ANN")
	end)

	it("switches to listen-only when the client answers InvalidChannel", function()
		Mock.guild.Set({ name = "G" })
		Mock.chat.channelsRejectAddon = true
		withChannel(3)
		warm()
		Tr():Send("CHANNEL", ann())
		Mock.Advance(3)
		local active, reason = Tr():IsListenOnly()
		truthy(active); eq(reason, "InvalidChannel")
		eq(#Mock.chat.sent, 0)
		Tr():Send("GUILD", ann())
		Mock.Advance(3)
		eq(#Mock.chat.sent, 1)
	end)

	it("retries a channel throttle result and delivers", function()
		Mock.chat.channels[1] = { name = "AzGuildFinder" }
		withChannel(1)
		warm()
		Mock.chat.QueueResults(R.ChannelThrottle)
		Tr():Send("CHANNEL", ann())
		Mock.Advance(10)
		eq(#Mock.chat.attempts, 2)
		eq(#Mock.chat.sent, 1)
		eq(Tr():Stats().throttled, 1)
		eq(Tr():Stats().sent, 1)
	end)

	it("treats the client's own lockdown result as a wait", function()
		Mock.guild.Set({ name = "G" })
		warm()
		Mock.chat.QueueResults(R.AddOnMessageLockdown)
		local sent = 0
		Tr():Send("GUILD", ann(), { onSent = function() sent = sent + 1 end })
		Mock.Advance(0.5)
		eq(#Mock.chat.sent, 0)
		eq(Tr():Pending(), 1)
		Mock.Advance(3)
		eq(#Mock.chat.sent, 1)
		eq(sent, 1)
		eq(Tr():Stats().failed, 0)
	end)

	it("splits a long message like AceComm and AceComm puts it back together", function()
		Mock.guild.Set({ name = "G" })
		warm()
		local noise, seed = {}, 11
		for i = 1, 700 do seed = (seed * 1103515245 + 12345) % 2147483648; noise[i] = string.char(32 + seed % 90) end
		local desc = table.concat(noise)
		local sentOk = false
		Tr():Send("GUILD", { t = "GLIST", k = "k", rev = 2, desc = desc }, { onSent = function() sentOk = true end })
		Mock.Advance(5)
		local out = Mock.chat.SentWithPrefix("AzGF")
		truthy(#out >= 3, "chunks " .. #out)
		eq(out[1].message:sub(1, 1), "\1")
		eq(out[#out].message:sub(1, 1), "\3")
		for i = 2, #out - 1 do eq(out[i].message:sub(1, 1), "\2") end
		for _, e in ipairs(out) do truthy(#e.message <= 255) end
		truthy(sentOk)
		eq(Tr():Stats().sent, 1)   -- one message, however many chunks

		local seen = listen("NET_MESSAGE")
		for _, e in ipairs(out) do Mock.chat.Receive("AzGF", e.message, "GUILD", "Other-Realm") end
		eq(#seen, 1)
		eq(seen[1][1].desc, desc)
		eq(seen[1][1].rev, 2)
	end)

	it("Frame uses the AceComm-3.0 wire format with chunks that leave room for the prefix", function()
		local L = 255 - #Tr().PREFIX
		eq(L, 251)
		eq(#Tr().Frame(string.rep("x", L)), 1)
		local chunks = Tr().Frame(string.rep("x", L + 1))
		eq(#chunks, 2)
		eq(chunks[1], "" .. string.rep("x", L - 1))
		eq(chunks[2], "xx")
		chunks = Tr().Frame(string.rep("y", 600))
		eq(#chunks, 3)
		eq(#chunks[1], L); eq(#chunks[2], L); eq(chunks[3], "" .. string.rep("y", 100))
		eq(Tr().Frame("abc")[1], "abc")
		eq(#Tr().Frame("" .. string.rep("z", L))[1], L)   -- the escape byte does not fit: multipart instead
		eq(Tr().Frame("" .. string.rep("z", L))[1]:sub(1, 1), "")
	end)

	it("reports an error of the library as a failure", function()
		Mock.guild.Set({ name = "G" })
		local reason
		ChatThrottleLib = nil
		Tr():Send("GUILD", ann(), { onFail = function(r) reason = r end })
		Mock.Advance(1)
		eq(reason, "nolib")
		eq(#Mock.errors, 0)
	end)
end)

describe("Statistics and /gf debug", function()
	it("has the Transport section with the counters", function()
		fakeWire()
		withChannel()
		Mock.chat.lockdown = true
		Tr():Send("GUILD", ann("a"), { key = "k" })
		Tr():Send("GUILD", ann("a"), { key = "k" })
		Tr():Send("CHANNEL", det())
		local st = Tr():Stats()
		eq(st.queued, 2); eq(st.queuedBy.GUILD, 1); eq(st.queuedBy.CHANNEL, 1); eq(st.coalesced, 1)
		Mock.Advance(1)
		Mock.ClearOutput()
		truthy(Mock.Slash("/gf debug"))
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Transport:")
		contains(text, "queued 2")
		contains(text, "held (lockdown)")
		contains(text, "replaced by key 1")
		eq(#Mock.errors, 0)
	end)

	it("shows the listen-only reason", function()
		fakeWire({ R.InvalidChannel })
		withChannel()
		Tr():Send("CHANNEL", ann())
		Mock.Advance(2)
		contains(table.concat(Tr():DebugLines(), "\n"), "listen-only (InvalidChannel)")
	end)

	it("registers the AzGF prefix", function()
		truthy(C_ChatInfo.IsAddonMessagePrefixRegistered("AzGF"))
		truthy(Tr().registered)
		eq(Tr().PREFIX, "AzGF")
	end)

	it("Reset forgets the queue, the keys and the listen-only state", function()
		fakeWire({ R.InvalidChannel })
		withChannel()
		Mock.chat.lockdown = true
		Tr():Send("GUILD", ann(), { key = "k" })
		Tr():Send("CHANNEL", ann("c"))
		Tr():Reset()
		eq(Tr():Pending(), 0)
		falsy(Tr():IsListenOnly())
		eq(Tr():Stats().sent, 0)
	end)
end)
