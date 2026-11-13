-- The network simulator (M1.8): N complete addon instances connected by a virtual channel, whisper, guild and officer
-- routing, on one shared clock. Loaded by Tests/lib/harness.lua; test files see it as the global `Sim`.
--
-- Every client is a full copy of the game as the harness builds it (Tests/lib/harness.lua, H.newWorld): its own game
-- environment, its own mock client (clock, timers, chat, guild, SavedVariables) and its own copy of the addon, so a
-- client knows nothing about the others except what arrives as CHAT_MSG_ADDON. A Lua error in any client fails the test.
--
--   local sim = Sim.new{ clients = 10, latency = { 0.05, 0.3 }, loss = 0.02, seed = 7 }
--   local a = sim:client(1)
--   a:slash("/gf debug ping")
--   sim:advance(10)                    -- seconds of simulated time; every client runs frame by frame
--   deepEq(a:output()[#a:output()], "...")
--   local st = sim:stats()             -- messages and bytes sent per client and per minute
--
-- Sim.new options (all optional):
--   clients   number of clients (default 2)
--   latency   seconds a message takes: a number, or { min, max } drawn uniformly per delivery (default 0.1)
--   loss      probability that one delivery is lost (0..1), or function(from, to, entry) -> true to lose it (default 0)
--   seed      seed of the simulator and of math.random inside the clients (default 1)
--   step      length of a frame in seconds (default 0.1, the mock client's own frame); bigger is faster, coarser
--             (sim:setStep(seconds) changes it later, for a run of days)
--   echo      the sender also receives its own CHANNEL / GUILD / OFFICER message, as the client does (default true)
--   ready     wait until every client has joined the channel (default true), at most readyTimeout seconds (60)
--   realm     the realm of every character (default "Test Realm")
--   guild     function(i) -> name | { name =, rank =, officerRanks = } | nil: the guild of client i (default: none)
--   setup     function(Mock, i, client) called after the mock client is built, before the addon loads
--   restrict  { [i] = { listenOnly =, lockdown =, restricted = } } restrictions from the start (see Client:restrict)
--   sync      the catalog sync starts by itself at CHANNEL_READY, as in the game (default true; false for tests that
--             count the traffic of something else)
--   onSend    function(client, entry) called for every message a client sends (before it is routed)
--   onDeliver function(client, entry) called for every message handed to a client
-- Time starts at 0 when the clients exist; sim:resetStats() starts a fresh measurement (after the clients settle).
local H, T = ...

local Sim = {}
Sim.__index = Sim
local Client = {}
Client.__index = Client

local DISTS = { "CHANNEL", "WHISPER", "GUILD", "OFFICER" }

local function letters(i)
	local out = ""
	i = i - 1
	repeat
		out = string.char(97 + i % 26) .. out
		i = math.floor(i / 26) - 1
	until i < 0
	return out
end

local function newCounters()
	local c = {}
	for _, d in ipairs(DISTS) do c[d] = { msgs = 0, bytes = 0 } end
	return c
end

---------------------------------------------------------------------------------------------------------------------
-- Clients
---------------------------------------------------------------------------------------------------------------------

-- The character name of client i: "Simaa" for 1, "Simab" for 2, ...
function Sim.nameOf(i) return "Sim" .. letters(i) end

-- Full name as the client puts it in CHAT_MSG_ADDON: Name-Realm (realm without spaces).
function Client:fullName() return self.name .. "-" .. self.realmKey end

function Client:slash(line) return self.Mock.Slash(line) end
function Client:output() return self.Mock.PlainOutput() end
function Client:clearOutput() self.Mock.ClearOutput() end
function Client:addon() return self.E.AzerothGuildFinder end
function Client:reload() self.Mock.Reload() end
function Client:isReady() return self:addon().Channel:IsReady() end

-- The channel number of `name` in this client, nil when it is not in it.
function Client:channelId(name)
	local lname = name:lower()
	for id, channel in pairs(self.Mock.chat.channels) do
		if channel.name:lower() == lname then return id end
	end
	return nil
end

-- Restrictions of this client's sending: listenOnly (the channel refuses addon messages: Transport goes listen-only),
-- lockdown (chat messaging lockdown) and restricted (outgoing addon messages restricted). Each field is a boolean;
-- fields left out are unchanged. It still receives everything.
function Client:restrict(r)
	local chat = self.Mock.chat
	if r.listenOnly ~= nil then chat.channelsRejectAddon = r.listenOnly end
	if r.lockdown ~= nil then chat.lockdown = r.lockdown end
	if r.restricted ~= nil then chat.restricted = r.restricted end
end

-- Puts the character in a guild (rank 0 = Guild Master, 1 = officer, 3 = member by default).
function Client:setGuild(name, rank, officerRanks)
	self.Mock.guild.Set{ name = name, realm = self.sim.realmKey, myRank = rank or 3, officerRanks = officerRanks or 1 }
end
function Client:leaveGuild() self.Mock.guild.Leave() end

-- An offline client receives nothing and what it sends is lost (a late joiner starts offline, then comes online).
function Client:setOnline(online) self.online = online and true or false end

-- Statistics of this client since the last sim:resetStats(): what it sent and received, in total, per distribution
-- and per minute, and its busiest minute on the channel (fixed one-minute buckets of simulated time).
function Client:stats()
	local sim = self.sim
	local minutes = math.max((sim.time - sim.statsFrom) / 60, 1e-9)
	local sent, recv = { msgs = 0, bytes = 0 }, { msgs = 0, bytes = 0 }
	for _, d in ipairs(DISTS) do
		sent.msgs, sent.bytes = sent.msgs + self.sent[d].msgs, sent.bytes + self.sent[d].bytes
		recv.msgs, recv.bytes = recv.msgs + self.recv[d].msgs, recv.bytes + self.recv[d].bytes
	end
	local peakMsgs, peakBytes = 0, 0
	for _, b in pairs(self.channelMinutes) do
		if b.msgs > peakMsgs then peakMsgs = b.msgs end
		if b.bytes > peakBytes then peakBytes = b.bytes end
	end
	return {
		sent = sent, received = recv, byDist = self.sent, receivedByDist = self.recv,
		msgsPerMinute = sent.msgs / minutes, bytesPerMinute = sent.bytes / minutes,
		channelPeakMinute = { msgs = peakMsgs, bytes = peakBytes },
	}
end

local function resetClientStats(c)
	c.sent, c.recv, c.channelMinutes = newCounters(), newCounters(), {}
end

---------------------------------------------------------------------------------------------------------------------
-- The network
---------------------------------------------------------------------------------------------------------------------
local function draw(sim)
	-- 31-bit linear congruential generator: deterministic and independent of math.random (the clients use that one)
	sim.rngState = (sim.rngState * 1103515245 + 12345) % 2147483648
	return sim.rngState / 2147483648
end

local function latencyOf(sim)
	local l = sim.latency
	if type(l) == "table" then return l[1] + (l[2] - l[1]) * draw(sim) end
	return l
end

local function lostDelivery(sim, from, to, entry)
	local loss = sim.loss
	if type(loss) == "function" then return loss(from, to, entry) and true or false end
	return loss > 0 and draw(sim) < loss
end

-- Messages from one client to another arrive in the order they were sent (the server keeps a sender's stream in
-- order; the chunks of an AceComm multipart message depend on it): a delivery is never due before the previous one
-- of the same pair.
local function schedule(sim, to, entry, from, info)
	local due = sim.time + latencyOf(sim)
	local slot = math.max(math.ceil(due / sim.step - 1e-9), sim.slot + 1)
	local pair = from.index .. ">" .. to.index
	local previous = sim.lastSlot[pair]
	if previous and previous > slot then slot = previous end
	sim.lastSlot[pair] = slot
	local bucket = sim.inflight[slot]
	if not bucket then bucket = {} sim.inflight[slot] = bucket end
	bucket[#bucket + 1] = { to = to, from = from, entry = entry, info = info }
end

local function receivers(sim, from, entry)
	local out = {}
	local kind = entry.chatType
	if kind == "CHANNEL" then
		local channel = from.Mock.chat.channels[tonumber(entry.target)]
		if not channel then return out end
		for _, c in ipairs(sim.clients) do
			local id = c:channelId(channel.name)
			if id and (c ~= from or sim.echo) then out[#out + 1] = { c, { 0, id, channel.name } } end
		end
	elseif kind == "WHISPER" then
		local target = tostring(entry.target):lower():gsub("%-.*$", "")
		for _, c in ipairs(sim.clients) do
			if c ~= from and c.name:lower() == target then out[1] = { c } break end
		end
	elseif kind == "GUILD" or kind == "OFFICER" then
		local guild = from.E.GetGuildInfo("player")
		if guild then
			for _, c in ipairs(sim.clients) do
				if (c ~= from or sim.echo) and c.E.GetGuildInfo("player") == guild
					and (kind == "GUILD" or c.E.C_GuildInfo.IsGuildOfficer()) then
					out[#out + 1] = { c }
				end
			end
		end
	end
	return out
end

local function route(sim, from, entry)
	local size = #entry.message + #entry.prefix
	local kind = entry.chatType
	local counters = from.sent[kind]
	if counters then
		counters.msgs, counters.bytes = counters.msgs + 1, counters.bytes + size
		if kind == "CHANNEL" then
			local minute = math.floor((sim.time - sim.statsFrom) / 60)
			local b = from.channelMinutes[minute]
			if not b then b = { msgs = 0, bytes = 0 } from.channelMinutes[minute] = b end
			b.msgs, b.bytes = b.msgs + 1, b.bytes + size
		end
	end
	if sim.onSend then sim.onSend(from, entry) end
	if not from.online then sim.lost = sim.lost + 1 return end
	for _, r in ipairs(receivers(sim, from, entry)) do
		local to = r[1]
		if to ~= from and (not to.online or lostDelivery(sim, from, to, entry)) then
			sim.lost = sim.lost + 1
		else
			schedule(sim, to, entry, from, r[2])
		end
	end
end

local function deliver(sim, item)
	local to, entry = item.to, item.entry
	if not to.online then sim.lost = sim.lost + 1 return end
	local counters = to.recv[entry.chatType]
	if counters then
		counters.msgs, counters.bytes = counters.msgs + 1, counters.bytes + #entry.message + #entry.prefix
	end
	sim.delivered = sim.delivered + 1
	if sim.onDeliver then sim.onDeliver(to, entry) end
	to.Mock.chat.Receive(entry.prefix, entry.message, entry.chatType, item.from:fullName(), "", item.info)
end

-- One frame: deliver what is due, let every client run a frame, route what they sent.
local function frame(sim)
	sim.slot = sim.slot + 1
	sim.time = sim.slot * sim.step
	local due = sim.inflight[sim.slot]
	if due then
		sim.inflight[sim.slot] = nil
		for _, item in ipairs(due) do deliver(sim, item) end
	end
	for _, c in ipairs(sim.clients) do
		c.Mock.Advance(sim.step, sim.step)
		local sent = c.Mock.chat.sent
		for i = c.cursor + 1, #sent do route(sim, c, sent[i]) end
		c.cursor = #sent
	end
end

-- Runs `seconds` of simulated time.
function Sim:advance(seconds)
	local target = self.slot + math.floor(seconds / self.step + 0.5)
	while self.slot < target do frame(self) end
end

-- Changes the length of a frame (days of simulated time need a coarse step): what is in flight keeps its due time and the
-- clock goes on from the same moment. Use it between two `advance` calls.
function Sim:setStep(step)
	local old, slots, inflight = self.step, {}, {}
	for slot in pairs(self.inflight) do slots[#slots + 1] = slot end
	table.sort(slots)
	self.slot = math.floor(self.time / step + 1e-9)
	self.time = self.slot * step
	for _, slot in ipairs(slots) do
		local to = math.max(math.ceil(slot * old / step - 1e-9), self.slot + 1)
		local bucket = inflight[to]
		if not bucket then bucket = {} inflight[to] = bucket end
		for _, item in ipairs(self.inflight[slot]) do bucket[#bucket + 1] = item end
	end
	self.inflight, self.lastSlot, self.step = inflight, {}, step
end

-- Runs until fn() is true (checked every frame), at most `limit` seconds. Returns true when fn() became true, and the
-- simulated seconds that passed.
function Sim:advanceUntil(fn, limit)
	local start, target = self.time, self.slot + math.floor((limit or 60) / self.step + 0.5)
	while self.slot < target do
		if fn() then return true, self.time - start end
		frame(self)
	end
	return fn() and true or false, self.time - start
end

function Sim:client(i) return self.clients[i] end
function Sim:count() return #self.clients end

function Sim:setLoss(loss) self.loss = loss end
function Sim:setLatency(latency) self.latency = latency end

-- Waits until every online client has joined the channel. Returns true, or false when the time ran out.
function Sim:settle(limit)
	return (self:advanceUntil(function()
		for _, c in ipairs(self.clients) do
			if c.online and not c:isReady() then return false end
		end
		return true
	end, limit or 60))
end

-- Starts a fresh measurement: counters and the minute buckets begin now.
function Sim:resetStats()
	self.statsFrom, self.delivered, self.lost = self.time, 0, 0
	for _, c in ipairs(self.clients) do resetClientStats(c) end
end

-- The measurement since the start or the last resetStats():
--   { elapsed, delivered, lost, sent = { msgs, bytes }, perClient = { [i] = Client:stats() },
--     avg = { msgsPerMinute, bytesPerMinute }, max = { msgsPerMinute, bytesPerMinute, channelPeakMsgs, channelPeakBytes } }
function Sim:stats()
	local out = {
		elapsed = self.time - self.statsFrom, delivered = self.delivered, lost = self.lost,
		sent = { msgs = 0, bytes = 0 }, perClient = {},
		avg = { msgsPerMinute = 0, bytesPerMinute = 0 },
		max = { msgsPerMinute = 0, bytesPerMinute = 0, channelPeakMsgs = 0, channelPeakBytes = 0 },
	}
	for i, c in ipairs(self.clients) do
		local s = c:stats()
		out.perClient[i] = s
		out.sent.msgs, out.sent.bytes = out.sent.msgs + s.sent.msgs, out.sent.bytes + s.sent.bytes
		out.avg.msgsPerMinute, out.avg.bytesPerMinute = out.avg.msgsPerMinute + s.msgsPerMinute, out.avg.bytesPerMinute + s.bytesPerMinute
		out.max.msgsPerMinute = math.max(out.max.msgsPerMinute, s.msgsPerMinute)
		out.max.bytesPerMinute = math.max(out.max.bytesPerMinute, s.bytesPerMinute)
		out.max.channelPeakMsgs = math.max(out.max.channelPeakMsgs, s.channelPeakMinute.msgs)
		out.max.channelPeakBytes = math.max(out.max.channelPeakBytes, s.channelPeakMinute.bytes)
	end
	local n = math.max(#self.clients, 1)
	out.avg.msgsPerMinute, out.avg.bytesPerMinute = out.avg.msgsPerMinute / n, out.avg.bytesPerMinute / n
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------------------------------------------------
local function bootClient(sim, i, opts)
	local world = H.newWorld()
	H.worlds[#H.worlds + 1] = world
	world.autoSync = sim.sync
	local c = setmetatable({
		sim = sim, index = i, world = world, E = world.E, Mock = world.Mock, name = Sim.nameOf(i), realmKey = sim.realmKey,
		online = true, cursor = 0,
	}, Client)
	resetClientStats(c)
	world.boot{ setups = { function(Mock)
		Mock.player.name = c.name
		Mock.player.realm = sim.realm
		Mock.player.guid = ("Player-1-%08X"):format(0xA000 + i)
		local g = opts.guild and opts.guild(i)
		if g then
			if type(g) == "string" then g = { name = g } end
			Mock.guild.Set{ name = g.name, realm = sim.realm, myRank = g.rank or 3, officerRanks = g.officerRanks or 1 }
		end
		local r = opts.restrict and opts.restrict[i]
		if r then c:restrict(r) end
		if opts.setup then opts.setup(Mock, i, c) end
	end } }
	return c
end

function Sim.new(opts)
	opts = opts or {}
	local sim = setmetatable({
		time = 0, slot = 0, step = opts.step or 0.1, latency = opts.latency or 0.1, loss = opts.loss or 0,
		echo = opts.echo ~= false, realm = opts.realm or "Test Realm", clients = {}, inflight = {}, lastSlot = {},
		rngState = (opts.seed or 1) % 2147483648, statsFrom = 0, delivered = 0, lost = 0,
		onSend = opts.onSend, onDeliver = opts.onDeliver, sync = opts.sync ~= false,
	}, Sim)
	sim.realmKey = sim.realm:gsub("[%s%-']", "")
	math.randomseed(opts.seed or 1)
	for i = 1, opts.clients or 2 do
		sim.clients[i] = bootClient(sim, i, opts)
	end
	if opts.ready ~= false then
		if not sim:settle(opts.readyTimeout or 60) then
			error("Sim.new: the clients did not join the channel in " .. (opts.readyTimeout or 60) .. " simulated seconds", 2)
		end
	end
	sim:resetStats()
	return sim
end

return Sim
