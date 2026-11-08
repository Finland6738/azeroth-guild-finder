-- Catalog sync over the simulated network (M2.3, SPEC-02 §5-§6): convergence within the traffic budget, suppression,
-- loss, listen-only clients, details. Every scenario is seeded: the same run gives the same numbers.
local CURVE = false   -- true prints the convergence curve every 30 s
local REALM_KEY = "TestRealm|Horde|"
local HOUR = 3600

-- Deterministic pseudo-random numbers for building scenarios (independent of the clients' math.random).
local function lcg(seed)
	local x = seed
	return function()
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
end

local function guildName(i) return ("Guild %03d"):format(i) end
local function keyOf(i) return REALM_KEY .. guildName(i) end

-- A complete summary of guild i at content revision rev and statistics revision srev.
local function summary(i, rev, srev)
	return { k = keyOf(i), rev = rev, upd = 1767000000 + rev, first = 1766000000, own = ("%08x"):format(0x10000000 + i),
		sub = "Guild number " .. i, lang = 1, lang1 = 1, tags = { 1 + i % 13 }, pace = 1 + i % 3, days = 21,
		t0 = 1140, t1 = 1380, rec = 1, apps = true, want = { [0] = 8 }, newb = true, minL = 10,
		st = { m = 10 + i, a7 = 5 }, srev = srev }
end

local function detail(i, rev)
	return { k = keyOf(i), rev = rev, desc = "About guild " .. i, disc = "guild" .. i, note = "Be nice" }
end

local function catalogOf(c) return c:addon().Catalog end
local function syncOf(c) return c:addon().Sync end

-- Puts a summary in a client's catalog as if it had been heard before this session.
local function seed(c, sum) return catalogOf(c):PutSummary(sum, { annAt = c.E.GetServerTime() - HOUR }) end

-- The newest version of every guild: truth[k] = { rev, srev }.
local function truthOf(guilds, newest)
	local truth = {}
	for i = 1, guilds do truth[keyOf(i)] = newest[i] end
	return truth
end

-- How many listings a client has exactly at the newest version.
local function upToDate(c, truth)
	local n = 0
	local cat = catalogOf(c)
	for k, want in pairs(truth) do
		local entry = cat:Get(k)
		if entry and entry.sum.rev == want.rev and (entry.sum.srev or 0) == want.srev then n = n + 1 end
	end
	return n
end

local function converged(sim, truth, total)
	for i = 1, sim:count() do
		local c = sim:client(i)
		if c.online and upToDate(c, truth) < total then return false end
	end
	return true
end

-- Runs until every online client has the newest version of every listing, checking every `every` seconds.
local function runUntilConverged(sim, truth, total, limit, every)
	local start = sim.time
	while sim.time - start < limit do
		sim:advance(every or 5)
		if CURVE and math.floor(sim.time - start + 0.5) % 30 == 0 then
			local done, missing = 0, 0
			for i = 1, sim:count() do
				local u = upToDate(sim:client(i), truth)
				if u == total then done = done + 1 end
				missing = missing + total - u
			end
			T.log(("t=%d complete=%d missing=%d"):format(sim.time - start, done, missing))
		end
		if converged(sim, truth, total) then return true, sim.time - start end
	end
	return false, sim.time - start
end

-- Counts what every client sent, by message type and distribution (decoded from the wire with the client's codec).
local function tapSent(sim)
	local counts = { byType = {}, catSenders = {} }
	for i = 1, sim:count() do
		local c = sim:client(i)
		c:addon().Bus:On("NET_MESSAGE", function(msg, sender, dist)
			local key = dist .. ":" .. msg.t
			counts.byType[key] = (counts.byType[key] or 0) + 1
			if msg.t == "CAT" then
				local to = c.name
				counts.catSenders[to] = counts.catSenders[to] or {}
				counts.catSenders[to][sender] = true
			end
		end)
	end
	return counts
end

local function size(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Gives client c the whole catalog of `guilds` guilds (at rev 2) and a full sync that just finished.
local function veteran(c, guilds, withDetails)
	for g = 1, guilds do
		seed(c, summary(g, 2, 1767200000))
		if withDetails then catalogOf(c):PutDetail(detail(g, 2)) end
	end
	c:addon().Config.db.account.syncAt["TestRealm|Horde"] = c.E.GetServerTime()
end

-- NET-01 measured on the wire: every channel message a client hands to the client API is put back together from its
-- AceComm chunks and decoded with that client's codec. Per client and per minute of simulated time it counts the
-- channel messages and the payload bytes of those that are not replies (the Transport.REPLY types). Returns the
-- onSend hook for Sim.new and a function giving the worst minute of any client.
local function net01Probe()
	local partial, minutes = {}, {}
	local function onSend(c, entry)
		if entry.chatType ~= "CHANNEL" or entry.prefix ~= "AzGF" then return end
		local text, first = entry.message, entry.message:byte(1)
		local whole
		if first == 1 then
			partial[c] = text:sub(2)
		elseif first == 2 then
			partial[c] = (partial[c] or "") .. text:sub(2)
		elseif first == 3 then
			whole, partial[c] = (partial[c] or "") .. text:sub(2), nil
		elseif first == 4 then
			whole = text:sub(2)
		else
			whole = text
		end
		if not whole then return end
		local A = c:addon()
		local msg = A.Codec:Decode(whole)
		local minute = math.floor((c.sim.time - c.sim.statsFrom) / 60)
		minutes[c] = minutes[c] or {}
		local m = minutes[c][minute]
		if not m then m = { msgs = 0, bytes = 0 } minutes[c][minute] = m end
		m.msgs = m.msgs + 1
		if msg and not A.Transport.REPLY[msg.t] then m.bytes = m.bytes + #whole end
	end
	local function worst()
		local w = { msgs = 0, bytes = 0 }
		for _, byMinute in pairs(minutes) do
			for _, m in pairs(byMinute) do
				if m.msgs > w.msgs then w.msgs = m.msgs end
				if m.bytes > w.bytes then w.bytes = m.bytes end
			end
		end
		return w
	end
	return onSend, worst
end

describe("Convergence (milestone M2 exit criterion)", function()
	it("50 clients and 100 guilds converge in under 5 simulated minutes within NET-01", function()
		local CLIENTS, GUILDS, VETERANS = 50, 100, 5
		local rand = lcg(2026)
		local onSend, worstMinute = net01Probe()
		local sim = Sim.new{ clients = CLIENTS, latency = { 0.05, 0.3 }, seed = 23, ready = false, onSend = onSend }
		-- Every guild has a newest version. Five clients have been online for a while and know all of it; the other
		-- 45 log in together, each with a quarter of the catalog and a tenth of it out of date.
		local newest = {}
		local t0 = sim:client(1).E.GetServerTime()
		for g = 1, GUILDS do newest[g] = { rev = 2 + math.floor(rand() * 3), srev = t0 - HOUR * math.floor(rand() * 5) } end
		for i = 1, VETERANS do
			local c = sim:client(i)
			for g = 1, GUILDS do seed(c, summary(g, newest[g].rev, newest[g].srev)) end
			c:addon().Config.db.account.syncAt["TestRealm|Horde"] = t0
		end
		for i = VETERANS + 1, CLIENTS do
			local c = sim:client(i)
			for g = 1, GUILDS do
				local r = rand()
				if r < 0.25 then
					seed(c, summary(g, newest[g].rev, newest[g].srev))
				elseif r < 0.35 then
					seed(c, summary(g, newest[g].rev - 1, newest[g].srev - HOUR))   -- an older version
				end
			end
		end
		-- Meanwhile ten guilds publish a new revision: a member announces it on the channel (§5).
		for j = 1, 10 do
			local c, g = sim:client(VETERANS + j), VETERANS + j
			newest[g] = { rev = newest[g].rev + 1, srev = t0 }
			c.E.C_Timer.After(20 + 10 * j, function()
				syncOf(c):Announce(summary(g, newest[g].rev, newest[g].srev), { contact = j % 2 == 0 })
			end)
		end
		local truth = truthOf(GUILDS, newest)
		sim:resetStats()
		local ok, took = runUntilConverged(sim, truth, GUILDS, 420, 5)
		local st, worst = sim:stats(), worstMinute()
		local budget = sim:client(1):addon().Transport.CHANNEL_BUDGET
		local acks, replies, dup = 0, 0, 0
		for i = 1, CLIENTS do
			local s = syncOf(sim:client(i)).state.stats
			acks, replies, dup = acks + s.acksSent, replies + s.catReplies, dup + s.duplicateCats
		end
		T.log(("50 clients, 100 guilds: converged %s after %d s; worst client minute on the channel: %d messages, %d bytes"
			.. " of requests and announcements (budget %d); %d CAT replies, %d acks, %d duplicate batches; all clients"
			.. " together %d messages, %d bytes"):format(tostring(ok), took, worst.msgs, worst.bytes, budget, replies, acks,
			dup, st.sent.msgs, st.sent.bytes))
		truthy(ok, "converged")
		truthy(took < 300, "in under 5 minutes: " .. took)
		truthy(worst.bytes <= budget, "NET-01 bytes: " .. worst.bytes)
		truthy(worst.msgs <= math.floor(60 / sim:client(1):addon().Transport.CHANNEL_GAP), "NET-01 gap: " .. worst.msgs)
		truthy(dup <= replies / 10, "no duplicate CAT storms: " .. dup)
		for i = 1, CLIENTS do eq(#sim:client(i).Mock.errors, 0) end
	end)
end)

describe("A late joiner", function()
	it("gets the whole catalog from exactly one responder", function()
		local GUILDS = 100
		local sim = Sim.new{ clients = 20, latency = { 0.05, 0.3 }, seed = 7, ready = false,
			setup = function(_, i, c) if i == 20 then c:setOnline(false) end end }
		for i = 1, 19 do veteran(sim:client(i), GUILDS) end
		sim:advance(30)
		sim:resetStats()
		local late = sim:client(20)
		late:setOnline(true)
		late:reload()
		local result, senders, batches = nil, {}, 0
		late:addon().Bus:On("CATALOG_SYNCED", function(r) result = r end)
		late:addon().Bus:On("NET_MESSAGE", function(msg, sender)
			if msg.t == "CAT" then senders[sender], batches = true, batches + 1 end		end)
		sim:advanceUntil(function() return result ~= nil end, 120)
		notNil(result, "the sync finished")
		truthy(result.full)
		eq(catalogOf(late):Count(), GUILDS)
		eq(size(senders), 1, "one responder")
		eq(batches, 10, "100 summaries in 10 batches")
		local st = sim:stats()
		local catReplies, acks = 0, 0
		for i = 1, 19 do
			local s = syncOf(sim:client(i)).state.stats
			catReplies, acks = catReplies + s.catReplies, acks + s.acksSent
		end
		eq(catReplies, 1, "one CAT reply in the whole network")
		truthy(acks <= 3, "few acks: " .. acks)
		T.log(("late joiner: complete after %.1f s, %d round(s), %d ack(s), %d message(s) on the wire"):format(
			result.took, result.rounds, acks, st.sent.msgs))
	end)

	it("does not ask again within 10 minutes of a full sync", function()
		local sim = Sim.new{ clients = 3, seed = 4 }
		for i = 1, 2 do veteran(sim:client(i), 20) end
		local c = sim:client(3)
		sim:advance(60)
		eq(catalogOf(c):Count(), 20)
		truthy(syncOf(c).state.stats.requestsSent >= 1)
		c:reload()
		sim:advance(60)
		eq(syncOf(c).state.stats.requestsSent, 0, "a reload within 10 minutes: no CATREQ")
	end)
end)

describe("Retries", function()
	it("a client alone asks four times (the first try and three retries), then relies on the ANN", function()
		local sim = Sim.new{ clients = 1, seed = 2 }
		local c = sim:client(1)
		local result
		c:addon().Bus:On("CATALOG_SYNCED", function(r) result = r end)
		sim:advance(15 + 4 * 20 + 3 * 60 + 5)
		notNil(result)
		eq(result.full, false)
		eq(result.why, "no answer")
		eq(syncOf(c).state.stats.retries, 3)
		eq(c:stats().byDist.CHANNEL.msgs, 4)
		isNil(syncOf(c):LastFullSync())
	end)

	it("a big digest goes in several parts and is put back together", function()
		local sim = Sim.new{ clients = 2, seed = 9, ready = false }
		for i = 1, 2 do syncOf(sim:client(i)).DIGEST_PART = 16 end
		veteran(sim:client(1), 60)
		for g = 1, 40 do seed(sim:client(2), summary(g, 1, 1767000000)) end
		local first, parts = nil, {}
		sim:client(1):addon().Bus:On("NET_MESSAGE", function(msg)
			if msg.t == "CATREQ" and (first == nil or first == msg.nonce) then
				first = msg.nonce
				parts[#parts + 1] = msg.p .. "/" .. msg.n
			end
		end)
		sim:advance(90)
		deepEq(parts, { "1/3", "2/3", "3/3" }, "40 listings in parts of 16")
		eq(catalogOf(sim:client(2)):Count(), 60)
		eq(catalogOf(sim:client(2)):Get(keyOf(1)).sum.rev, 2)
	end)
end)

describe("Message loss", function()
	it("20 clients and 60 guilds converge with 10 % of the deliveries lost", function()
		local CLIENTS, GUILDS = 20, 60
		local rand = lcg(77)
		local sim = Sim.new{ clients = CLIENTS, latency = { 0.05, 0.3 }, loss = 0.1, seed = 31, ready = false }
		local newest = {}
		for g = 1, GUILDS do newest[g] = { rev = 2, srev = 1767200000 } end
		for i = 1, 2 do veteran(sim:client(i), GUILDS) end
		for i = 3, CLIENTS do
			for g = 1, GUILDS do
				if rand() < 0.3 then seed(sim:client(i), summary(g, 2, 1767200000)) end
			end
		end
		local ok, took = runUntilConverged(sim, truthOf(GUILDS, newest), GUILDS, 600, 5)
		T.log(("10 %% loss: converged %s after %d s, %d deliveries lost"):format(tostring(ok), took, sim:stats().lost))
		for i = 1, CLIENTS do
			local s = syncOf(sim:client(i)).state
			local u = upToDate(sim:client(i), truthOf(GUILDS, newest))
			if u < GUILDS then T.log(i, u, s.lastResult and s.lastResult.why, s.lastResult and s.lastResult.rounds, s.req and "running") end
		end
		truthy(ok, "converged")
		truthy(took < 360, "in under 6 minutes (lost requests wait for their retries): " .. took)
		truthy(sim:stats().lost > 0)
	end)
end)

describe("A listen-only client", function()
	it("hears the channel and gets the catalog by whisper", function()
		local sim = Sim.new{ clients = 6, seed = 5, ready = false, restrict = { [6] = { listenOnly = true } } }
		for i = 1, 5 do veteran(sim:client(i), 30) end
		local deaf = sim:client(6)
		sim:advance(20)
		-- the veterans do not need a sync: the channel is quiet until a guild announces itself
		syncOf(sim:client(2)):Announce(summary(1, 3, 1767300000), { contact = true })
		sim:advance(60)
		eq(catalogOf(deaf):Count(), 30)
		eq(catalogOf(deaf):Get(keyOf(1)).sum.rev, 3, "the ANN itself arrived")
		eq(deaf:stats().byDist.CHANNEL.msgs, 0, "nothing of its own on the channel")
		truthy(deaf:stats().byDist.WHISPER.msgs >= 1, "the request went by whisper")
		truthy(deaf:addon().Transport:IsListenOnly())
		notNil(syncOf(deaf):LastFullSync())
	end)
end)

describe("Announcements", function()
	it("an ANN reaches every client; contacts are remembered; a DEL withdraws it", function()
		local sim = Sim.new{ clients = 4, seed = 6, sync = false }
		local gm = sim:client(1)
		syncOf(gm):Announce(summary(1, 1, 1767000000), { contact = true })
		syncOf(sim:client(2)):Announce(summary(2, 1, 1767000000))
		sim:advance(5)
		for i = 1, 4 do
			eq(catalogOf(sim:client(i)):Status(keyOf(1)), "listed", "client " .. i)
			eq(catalogOf(sim:client(i)):Status(keyOf(2)), "listed", "client " .. i)
		end
		deepEq(syncOf(sim:client(3)):Contacts(keyOf(1)), { gm.name })
		deepEq(syncOf(sim:client(3)):Contacts(keyOf(2)), {}, "not a contact")
		eq(syncOf(sim:client(3)):LastAnnounce(keyOf(1)).rev, 1)
		truthy(syncOf(sim:client(3)):Suppressed(keyOf(1), 1, 1767000000, 0), "§5: an equal ANN suppresses ours")
		falsy(syncOf(sim:client(3)):Suppressed(keyOf(1), 2, 1767000000, 0), "a newer rev is not suppressed")
		gm:addon().Transport:Send("CHANNEL", { t = "DEL", k = keyOf(1), rev = 1 })
		sim:advance(5)
		for i = 2, 4 do eq(catalogOf(sim:client(i)):Status(keyOf(1)), "delisted", "client " .. i) end
	end)

	it("/gf debug announce sends a test listing that development builds keep and release builds ignore", function()
		local sim = Sim.new{ clients = 3, seed = 8, sync = false }
		local release = sim:client(3)
		release:addon().Config.DEV = false
		local dev = sim:client(1)
		dev:slash("/gf debug announce")
		sim:advance(5)
		local out = dev:output()
		contains(out[#out], "announced on the channel")
		local sum = syncOf(dev):TestListing()
		eq(catalogOf(sim:client(2)):Get(sum.k).sum.test, true, "another development build keeps it")
		isNil(catalogOf(release):Get(sum.k), "a release build ignores it")
		eq(syncOf(release).state.stats.testIgnored, 1)
		release:slash("/gf debug announce")
		out = release:output()
		contains(out[#out], "only works in development builds")
		-- another development build can fetch the detail of the test listing
		local got
		sim:client(2):addon().Bus:On("CATALOG_UPDATED", function(k, what) if k == sum.k and what == "detail" then got = true end end)
		truthy(syncOf(sim:client(2)):RequestDetail(sum.k))
		sim:advance(10)
		truthy(got)
	end)
end)

describe("Details", function()
	it("one peer answers a DETREQ and the detail lands in the catalog", function()
		local sim = Sim.new{ clients = 8, seed = 12, latency = { 0.05, 0.3 }, sync = false }
		for i = 1, 7 do veteran(sim:client(i), 5, true) end
		local c = sim:client(8)
		for g = 1, 5 do seed(c, summary(g, 2, 1767200000)) end
		local counts = tapSent(sim)
		local ok, why = syncOf(c):RequestDetail(keyOf(3))
		truthy(ok)
		eq(why, "requested")
		eq(select(2, syncOf(c):RequestDetail(keyOf(3))), "pending")
		sim:advance(10)
		local entry = catalogOf(c):Get(keyOf(3))
		notNil(entry.det)
		eq(entry.det.desc, "About guild 3")
		eq(counts.byType["WHISPER:DET"], 1, "exactly one DET")
		eq(select(2, syncOf(c):RequestDetail(keyOf(3))), "cached")
	end)

	it("reports DETAIL_UNAVAILABLE when nobody has the detail", function()
		local sim = Sim.new{ clients = 4, seed = 13, sync = false }
		for i = 1, 4 do veteran(sim:client(i), 5) end
		local c = sim:client(4)
		local unavailable
		c:addon().Bus:On("DETAIL_UNAVAILABLE", function(k) unavailable = k end)
		syncOf(c):RequestDetail(keyOf(2))
		sim:advance(19)
		isNil(unavailable)
		sim:advance(2)
		eq(unavailable, keyOf(2))
		eq(select(2, syncOf(c):RequestDetail(keyOf(9))), "unknown")
	end)
end)
