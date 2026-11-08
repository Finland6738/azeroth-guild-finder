-- Ping: the debug check of the channel, /gf debug ping (SPEC-02 §3, milestone M1 exit check). Lua 5.1.
--   PING{nonce}  sent on the channel; every peer that has the addon answers
--   PONG{nonce}  the answer, by whisper to the sender of the PING
-- The result is a count and the round-trip times: sender names are never printed and never kept (a PONG is counted
-- once per sender through a 32-bit hash that lives only until the result is printed).
local ADDON_NAME, ns = ...
ns = ns or {}
local Ping = {}
ns.Ping, ns.modules = Ping, ns.modules or {}
ns.modules.Ping = Ping

local type, tostring, floor = type, tostring, math.floor

Ping.WAIT = 5              -- seconds to collect the answers, counted from the moment the PING was sent
Ping.COOLDOWN = 10         -- seconds between two pings of this client
Ping.REPLY_COOLDOWN = 5    -- this client answers at most one PING in this time (a flood of pings costs the peers nothing)
Ping.SEND_TTL = 15         -- a PING that could not leave the queue in this time is dropped

local state
local function resetState()
	state = { pending = nil, lastStart = nil, lastReply = nil, sent = 0, answered = 0, ignored = 0, last = nil }
	Ping.state = state
end
resetState()

local function compat() return ns.Compat end
local function now() return compat().Now() end
local function say(text)
	if ns.addon and ns.addon.Print then ns.addon:Print(text) end
end

-- Own messages come back on the channel: never answer them.
local function isSelf(sender)
	local mine = compat().Player.Name()
	local theirs = type(sender) == "string" and sender:match("^[^%-]+")
	return mine ~= nil and theirs ~= nil and mine:lower() == theirs:lower()
end

local function finish()
	local p = state.pending
	if not p then return end
	state.pending = nil
	local n = #p.rtts
	local result = { answers = n, wait = Ping.WAIT, error = p.error }
	if n > 0 then
		local sum, min, max = 0, p.rtts[1], p.rtts[1]
		for _, v in ipairs(p.rtts) do
			sum = sum + v
			if v < min then min = v end
			if v > max then max = v end
		end
		result.min, result.avg, result.max = min, sum / n, max
	end
	state.last = result
	local L = ns.L
	if p.error then
		say(L["PING_FAILED"]:format(p.error))
	elseif n == 0 then
		say(L["PING_NONE"]:format(Ping.WAIT))
	else
		say(L["PING_RESULT"]:format(n, floor(result.min * 1000 + 0.5), floor(result.avg * 1000 + 0.5), floor(result.max * 1000 + 0.5)))
	end
	if ns.Bus then ns.Bus:Emit("PING_DONE", result) end
end

-- Sends a PING. Returns true, or false plus a reason: "busy", "cooldown", "channel" (not joined), "send: <why>".
function Ping:Start()
	local t = now()
	if state.pending then return false, "busy" end
	if state.lastStart and t - state.lastStart < Ping.COOLDOWN then return false, "cooldown" end
	if not (ns.Channel and ns.Channel:IsReady()) then return false, "channel" end
	local nonce = math.random(1, 2147483647)
	local p = { nonce = nonce, sentAt = nil, rtts = {}, seen = {} }
	local item, why = ns.Transport:Send("CHANNEL", { t = "PING", nonce = nonce }, {
		ttl = Ping.SEND_TTL,
		onSent = function()
			if state.pending ~= p then return end
			p.sentAt = now()
			compat().After(Ping.WAIT, function() if state.pending == p then finish() end end)
		end,
		onFail = function(reason)
			if state.pending ~= p then return end
			p.error = tostring(reason)
			finish()
		end,
	})
	if not item then return false, "send: " .. tostring(why) end
	state.pending, state.lastStart, state.sent = p, t, state.sent + 1
	return true
end

-- /gf debug ping
function Ping:Command()
	local L = ns.L
	local ok, why = Ping:Start()
	if ok then
		say(L["PING_SENT"]:format(Ping.WAIT))
	elseif why == "busy" then
		say(L["PING_BUSY"])
	elseif why == "cooldown" then
		say(L["PING_COOLDOWN"]:format(Ping.COOLDOWN))
	elseif why == "channel" then
		say(L["PING_NO_CHANNEL"])
	else
		say(L["PING_FAILED"]:format(why))
	end
end

-- Bus NET_MESSAGE(msg, sender, dist)
function Ping:OnMessage(msg, sender, dist)
	if msg.t == "PING" and dist == "CHANNEL" then
		local p = state.pending
		if (p and msg.nonce == p.nonce) or isSelf(sender) then return end
		local t = now()
		if state.lastReply and t - state.lastReply < Ping.REPLY_COOLDOWN then
			state.ignored = state.ignored + 1
			return
		end
		state.lastReply = t
		if ns.Transport:Send("WHISPER", { t = "PONG", nonce = msg.nonce }, { target = sender }) then
			state.answered = state.answered + 1
		end
	elseif msg.t == "PONG" and dist == "WHISPER" then
		local p = state.pending
		if not p or not p.sentAt or msg.nonce ~= p.nonce then return end
		local h = ns.Normalize.Hash32(sender)
		if p.seen[h] then return end
		p.seen[h] = true
		p.rtts[#p.rtts + 1] = now() - p.sentAt
	end
end

function Ping:Reset() resetState() end

function Ping:DebugLines()
	local last = state.last
	local text = "none yet"
	if last then
		text = last.error and ("failed (" .. last.error .. ")") or ("%d answer(s)"):format(last.answers)
	end
	return { ("Ping: sent %d, answered %d, ignored %d, last: %s"):format(state.sent, state.answered, state.ignored, text) }
end

if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(msg, sender, dist) Ping:OnMessage(msg, sender, dist) end)
end
if ns.addon then
	ns.addon.Ping = Ping
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Ping", function() return Ping:DebugLines() end) end
end
