-- The network simulator (M1.8): N complete clients on a virtual network. How to write a test: CONTRIBUTING §4.
local function lastLine(c) local o = c:output() return o[#o] or "" end
local function last(c) return c:addon().Ping.state.last end

-- Counts the NET_MESSAGE events of every client, by message type and distribution: counts[i][dist .. ":" .. t].
local function tap(sim)
	local counts = {}
	for i = 1, sim:count() do
		counts[i] = {}
		sim:client(i):addon().Bus:On("NET_MESSAGE", function(msg, _, dist)
			local key = dist .. ":" .. msg.t
			counts[i][key] = (counts[i][key] or 0) + 1
		end)
	end
	return counts
end

describe("The simulator itself", function()
	it("boots independent clients that join the channel by themselves", function()
		local sim = Sim.new{ clients = 4 }
		eq(sim:count(), 4)
		for i = 1, 4 do
			local c = sim:client(i)
			truthy(c:isReady(), "client " .. i)
			eq(c.name, Sim.nameOf(i))
			eq(c.Mock.player.name, c.name)
		end
		ne(sim:client(1).E, sim:client(2).E)
		ne(sim:client(1):addon(), sim:client(2):addon())
		ne(sim:client(1).E.AzerothGuildFinderDB, sim:client(2).E.AzerothGuildFinderDB, "separate SavedVariables")
		local a, b = sim:client(1).E.AzerothGuildFinderDB, sim:client(2).E.AzerothGuildFinderDB
		a.marker = 1
		eq(b.marker, nil)
	end)

	it("keeps each client's clock and the shared clock in step", function()
		local sim = Sim.new{ clients = 3, ready = false }
		sim:advance(12.5)
		near(sim.time, 12.5, 1e-6)
		local t1 = sim:client(1).E.GetTime()
		near(sim:client(2).E.GetTime(), t1, 1e-6)
		near(sim:client(3).E.GetTime(), t1, 1e-6)
		eq(#Mock.errors, 0)
	end)

	it("advanceUntil stops as soon as the condition holds and reports the time", function()
		local sim = Sim.new{ clients = 2, ready = false }
		local ok, took = sim:advanceUntil(function() return sim:client(1):isReady() end, 30)
		truthy(ok)
		truthy(took > 4 and took < 8, "joined after the start delay: " .. took)
		local ok2 = sim:advanceUntil(function() return false end, 2)
		falsy(ok2)
	end)

	it("a reloaded client keeps the world and joins again by itself", function()
		local sim = Sim.new{ clients = 2 }
		local c = sim:client(1)
		c:reload()
		sim:advance(7)
		truthy(c:isReady())
		eq(#c.Mock.errors, 0)
	end)

	it("is deterministic: the same seed gives the same traffic", function()
		local function run()
			local sim = Sim.new{ clients = 6, seed = 5, latency = { 0.05, 0.4 }, loss = 0.1 }
			sim:client(1):slash("/gf debug ping")
			sim:client(4):slash("/gf debug ping")
			sim:advance(40)
			local st = sim:stats()
			return st.sent.msgs, st.sent.bytes, st.delivered, st.lost, last(sim:client(1)).answers
		end
		local a1, a2, a3, a4, a5 = run()
		local b1, b2, b3, b4, b5 = run()
		deepEq({ a1, a2, a3, a4, a5 }, { b1, b2, b3, b4, b5 })
	end)
end)

describe("Pings between clients", function()
	it("every client sees every other client's ping", function()
		local sim = Sim.new{ clients = 6 }
		for i = 1, 6 do
			local c = sim:client(i)
			c:clearOutput()
			c:slash("/gf debug ping")
			sim:advance(12)   -- 5 s to collect, then the 10 s between two pings of a client are over for the next one
			eq(last(c).answers, 5, "client " .. i)
			contains(lastLine(c), "5 peer(s) answered")
		end
	end)

	it("measures the round trip from the latency", function()
		local sim = Sim.new{ clients = 3, latency = 0.5 }
		local a = sim:client(1)
		a:slash("/gf debug ping")
		sim:advance(8)
		local r = last(a)
		eq(r.answers, 2)
		truthy(r.min >= 1.0 and r.max <= 1.4, ("round trip %.2f..%.2f s"):format(r.min, r.max))
	end)

	it("never prints a name", function()
		local sim = Sim.new{ clients = 4 }
		local a = sim:client(1)
		a:slash("/gf debug ping")
		sim:advance(8)
		for _, line in ipairs(a:output()) do
			for i = 1, 4 do falsy(line:find(Sim.nameOf(i), 1, true), line) end
		end
	end)

	it("a client alone on the channel gets no answer", function()
		local sim = Sim.new{ clients = 1 }
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		eq(last(sim:client(1)).answers, 0)
		contains(lastLine(sim:client(1)), "No peer answered")
	end)

	it("with 50 clients one ping gets 49 answers", function()
		local sim = Sim.new{ clients = 50, latency = { 0.05, 0.25 } }
		local a = sim:client(1)
		a:slash("/gf debug ping")
		sim:advance(10)
		eq(last(a).answers, 49)
		for i = 1, 50 do eq(#sim:client(i).Mock.errors, 0) end
	end)
end)

describe("Loss", function()
	it("a client that loses everything on its way in does not answer", function()
		local sim = Sim.new{ clients = 5 }
		sim:setLoss(function(_, to) return to.index == 3 end)
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		eq(last(sim:client(1)).answers, 3, "4 peers, one of them deaf")
		eq(sim:stats().lost, 1)
	end)

	it("lost answers are not counted, and what arrives still counts", function()
		local sim = Sim.new{ clients = 5 }
		sim:setLoss(function(from) return from.index == 2 end)   -- everything client 2 sends is lost
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		eq(last(sim:client(1)).answers, 3)
	end)

	it("random loss loses part of the traffic and the ping still reports what it got", function()
		local sim = Sim.new{ clients = 20, seed = 11, loss = 0.4 }
		sim:client(1):slash("/gf debug ping")
		sim:advance(10)
		local answers = last(sim:client(1)).answers
		truthy(answers > 0 and answers < 19, "answers: " .. answers)
		local st = sim:stats()
		truthy(st.lost > 0 and st.delivered > 0)
	end)

	it("a client that is offline receives nothing and its messages are lost", function()
		local sim = Sim.new{ clients = 4 }
		sim:client(3):setOnline(false)
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		eq(last(sim:client(1)).answers, 2)
		eq(sim:client(3):stats().received.msgs, 0)
	end)
end)

describe("Restrictions", function()
	it("a listen-only client receives the channel but sends nothing on it", function()
		local sim = Sim.new{ clients = 4 }
		local counts = tap(sim)
		local deaf = sim:client(3)
		deaf:restrict{ listenOnly = true }
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		truthy(counts[3]["CHANNEL:PING"] and counts[3]["CHANNEL:PING"] >= 1, "it hears the ping")
		eq(last(sim:client(1)).answers, 3, "and answers it by whisper, which is not restricted")
		deaf:slash("/gf debug ping")
		sim:advance(4)
		contains(lastLine(deaf), "could not be sent (InvalidChannel)")
		eq(deaf:stats().byDist.CHANNEL.msgs, 0, "nothing of its own on the channel")
		truthy(deaf:addon().Transport:IsListenOnly())
		eq(counts[1]["CHANNEL:PING"], 1, "only the echo of client 1's own ping")
	end)

	it("a client in chat lockdown holds its ping until the lockdown ends", function()
		local sim = Sim.new{ clients = 3 }
		local a = sim:client(2)
		a:restrict{ lockdown = true }
		a:slash("/gf debug ping")
		sim:advance(3)
		eq(a:stats().byDist.CHANNEL.msgs, 0)
		a:restrict{ lockdown = false }
		sim:advance(9)
		eq(last(a).answers, 2)
	end)

	it("restrictions can be set when the clients are created", function()
		local sim = Sim.new{ clients = 3, restrict = { [2] = { listenOnly = true } } }
		sim:client(2):slash("/gf debug ping")
		sim:advance(4)
		contains(lastLine(sim:client(2)), "InvalidChannel")
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		eq(last(sim:client(1)).answers, 2)
	end)
end)

describe("Routing", function()
	local function ann(k) return { t = "GLREQ", rev = 1 } end

	it("sends a whisper only to its target", function()
		local sim = Sim.new{ clients = 4 }
		local counts = tap(sim)
		sim:client(1):addon().Transport:Send("WHISPER", ann(), { target = sim:client(3):fullName() })
		sim:advance(3)
		eq(counts[3]["WHISPER:GLREQ"], 1)
		eq(counts[1]["WHISPER:GLREQ"], nil)
		eq(counts[2]["WHISPER:GLREQ"], nil)
		eq(counts[4]["WHISPER:GLREQ"], nil)
	end)

	it("sends GUILD messages to the members of the guild and OFFICER messages to its officers", function()
		local sim = Sim.new{ clients = 6, guild = function(i)
			if i <= 4 then return { name = "Alpha", rank = ({ 0, 1, 3, 3 })[i] } end
			return { name = "Beta", rank = 0 }
		end }
		local counts = tap(sim)
		local gm = sim:client(1):addon().Transport
		gm:Send("GUILD", ann())
		gm:Send("OFFICER", { t = "APPSYNC" })
		sim:advance(3)
		eq(counts[1]["GUILD:GLREQ"], 1, "echo")
		eq(counts[2]["GUILD:GLREQ"], 1)
		eq(counts[3]["GUILD:GLREQ"], 1)
		eq(counts[4]["GUILD:GLREQ"], 1)
		eq(counts[5]["GUILD:GLREQ"], nil, "another guild")
		eq(counts[2]["OFFICER:APPSYNC"], 1, "an officer")
		eq(counts[3]["OFFICER:APPSYNC"], nil, "a plain member")
		eq(counts[6]["OFFICER:APPSYNC"], nil)
	end)

	it("a message on the channel reaches every client on it, including the sender's echo", function()
		local sim = Sim.new{ clients = 5 }
		local counts = tap(sim)
		sim:client(2):addon().Transport:Send("CHANNEL", { t = "DEL", k = "g", rev = 1 })
		sim:advance(3)
		for i = 1, 5 do eq(counts[i]["CHANNEL:DEL"], 1, "client " .. i) end
	end)

	it("without echo the sender does not hear itself", function()
		local sim = Sim.new{ clients = 3, echo = false }
		local counts = tap(sim)
		sim:client(1):addon().Transport:Send("CHANNEL", { t = "DEL", k = "g", rev = 1 })
		sim:advance(3)
		eq(counts[1]["CHANNEL:DEL"], nil)
		eq(counts[2]["CHANNEL:DEL"], 1)
	end)

	it("delivers after the configured latency and not before", function()
		local sim = Sim.new{ clients = 2, latency = 2 }
		local counts = tap(sim)
		sim:client(1):addon().Transport:Send("CHANNEL", { t = "DEL", k = "g", rev = 1 })
		sim:advance(1.5)
		eq(counts[2]["CHANNEL:DEL"], nil)
		sim:advance(1.5)
		eq(counts[2]["CHANNEL:DEL"], 1)
	end)

	it("the sender reaches the Bus as the client names it (AceComm drops our own realm) and never appears in /gf debug", function()
		local sim = Sim.new{ clients = 2 }
		local seen
		sim:client(2):addon().Bus:On("NET_MESSAGE", function(_, sender) seen = sender end)
		sim:client(1):addon().Transport:Send("CHANNEL", { t = "DEL", k = "g", rev = 1 })
		sim:advance(3)
		eq(seen, Sim.nameOf(1), "same realm: no realm suffix")
		eq(sim:client(1):fullName(), Sim.nameOf(1) .. "-TestRealm", "what the simulated client puts on the wire")
		sim:client(2):slash("/gf debug")
		for _, line in ipairs(sim:client(2):output()) do falsy(line:find(Sim.nameOf(1), 1, true), line) end
	end)
end)

describe("Traffic statistics", function()
	it("counts the messages and bytes each client sent, per distribution", function()
		local sim = Sim.new{ clients = 4 }
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		local st = sim:stats()
		eq(st.perClient[1].byDist.CHANNEL.msgs, 1, "the PING")
		eq(st.perClient[1].byDist.WHISPER.msgs, 0)
		for i = 2, 4 do
			eq(st.perClient[i].byDist.WHISPER.msgs, 1, "a PONG from client " .. i)
			eq(st.perClient[i].byDist.CHANNEL.msgs, 0)
		end
		eq(st.sent.msgs, 4)
		truthy(st.sent.bytes > 4 * #"AzGF", "bytes include the prefix")
		eq(st.perClient[1].received.msgs, 1 + 3, "its own echo and three PONGs")
		eq(st.delivered, 1 + 3 + 3, "echo, 3 channel copies, 3 whispers")
	end)

	it("gives per-minute figures and the busiest channel minute", function()
		local sim = Sim.new{ clients = 2 }
		local a = sim:client(1):addon().Transport
		for i = 1, 3 do a:Send("CHANNEL", { t = "DEL", k = "g" .. i, rev = 1 }) end
		sim:advance(30)
		local first = sim:stats()
		eq(first.perClient[1].channelPeakMinute.msgs, 3)
		near(first.perClient[1].msgsPerMinute, 3 / (first.elapsed / 60), 1e-6)
		sim:advance(60)
		local st = sim:stats()
		eq(st.perClient[1].channelPeakMinute.msgs, 3, "the peak stays")
		truthy(st.perClient[1].msgsPerMinute < first.perClient[1].msgsPerMinute, "the average falls as time passes")
		eq(st.perClient[2].sent.msgs, 0)
		eq(st.max.channelPeakMsgs, 3)
	end)

	it("resetStats starts a fresh measurement", function()
		local sim = Sim.new{ clients = 3 }
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		truthy(sim:stats().sent.msgs > 0)
		sim:resetStats()
		eq(sim:stats().sent.msgs, 0)
		eq(sim:stats().delivered, 0)
		near(sim:stats().elapsed, 0, 1e-9)
	end)

	it("onSend and onDeliver see every message", function()
		local sent, delivered = 0, 0
		local sim = Sim.new{ clients = 3, onSend = function() sent = sent + 1 end, onDeliver = function() delivered = delivered + 1 end }
		sim:resetStats()
		sent, delivered = 0, 0
		sim:client(1):slash("/gf debug ping")
		sim:advance(8)
		eq(sent, 3)
		eq(delivered, 1 + 2 + 2)
	end)

	it("50 clients stay far below the channel budget when only a few of them talk", function()
		local sim = Sim.new{ clients = 50 }
		for i = 1, 5 do
			sim:client(i):addon().Transport:Send("CHANNEL", { t = "DEL", k = "g" .. i, rev = 1 })
		end
		sim:advance(120)
		local st = sim:stats()
		truthy(st.max.channelPeakBytes <= sim:client(1):addon().Transport.CHANNEL_BUDGET)
		eq(st.perClient[1].byDist.CHANNEL.msgs, 1)
		eq(st.perClient[50].received.msgs, 5)
	end)
end)
