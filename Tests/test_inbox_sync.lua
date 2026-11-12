-- M4.3: the officers' inbox and its sync (SPEC-07 §2 and §4, SPEC-02 §3 and §7, Data/Inbox.lua, Net/InboxSync.lua).
-- Part 1 is pure Lua: the version that decides a conflict (final states first, then stateRev, then the order of the
-- final states), the INT-06 checks of a synced record, the merge. Part 2 runs one client as an officer: the changes
-- and the list at login over OFFICER, the answers and requests, the 30-day history and the 14-day expiry, the limit,
-- the role lost, malformed messages, damaged saved data and the GUILD fallback. Part 3 runs the network simulator: two
-- officers and the Guild Master converge on the same inbox after offline periods.
-- The mock player is "Testchar", Horde Orc Warrior 60 on "Test Realm".

local DAY = 86400
local GUILD = "Aurora"
local KEY = "TestRealm|Horde|" .. GUILD
local OTHER = "TestRealm|Horde|Iron Wolves"

local function A() return AzerothGuildFinder end
local function S() return A().InboxSync end
local function Inbox() return A().Inbox end
local function Apps() return A().Applications end
local function V(rec) return Inbox().Version(rec) end

-- A record as another officer sends it (no guild key: the message has it).
local function wire(extra)
	local t = GetServerTime()
	local r = { id = "0a1b2c3d", state = "received", stateRev = 2, at = t - 3600, upd = t - 3500, who = "Elarin-TestRealm",
		cls = 8, race = 5, lvl = 32, ilvl = 41, roles = 8 }
	for k, v in pairs(extra or {}) do if v == "nil" then r[k] = nil else r[k] = v end end
	return r
end
-- The same record as this client stores it.
local function stored(extra)
	local r = wire(extra)
	r.k = KEY
	return r
end

local function asOfficer(rank)
	Mock.guild.Set{ name = GUILD, myRank = rank or 1, members = { { name = "Thrall", rank = 0 }, { name = "Jaina", rank = 1 },
		{ name = "Garrosh", rank = 3 } } }
	A().Role:Refresh()
end

-- Replaces Transport:Send with a recorder: sent[i] = { dist, msg, opts }.
local sent
local function capture()
	sent = {}
	A().Transport.Send = function(_, dist, msg, opts)
		sent[#sent + 1] = { dist = dist, msg = msg, opts = opts or {} }
		return { dist = dist }
	end
end
local function syncs(pred)
	local out = {}
	for _, s in ipairs(sent) do
		if s.msg.t == "APPSYNC" and (not pred or pred(s.msg)) then out[#out + 1] = s end
	end
	return out
end
local function recIds(list)
	local ids = {}
	for _, s in ipairs(list) do
		for _, r in ipairs(s.msg.recs or {}) do ids[#ids + 1] = r.id end
	end
	table.sort(ids)
	return ids
end

local function hear(msg, sender, dist)
	msg.t, msg.v = "APPSYNC", 1
	if msg.k == nil then msg.k = KEY end
	return S():OnMessage(msg, sender or "Jaina-TestRealm", dist or "OFFICER")
end

---------------------------------------------------------------------------------------------------------------------
-- Part 1: pure rules
---------------------------------------------------------------------------------------------------------------------
describe("the conflict rule (SPEC-07 §4)", function()
	it("a final state wins over an open one, even with a lower stateRev", function()
		truthy(V(stored{ state = "withdrawn", stateRev = 2 }) > V(stored{ state = "received", stateRev = 2 }))
		truthy(V(stored{ state = "expired", stateRev = 3 }) > V(stored{ state = "received", stateRev = 9 }))
	end)

	it("among final states the higher stateRev wins, then accepted > declined > withdrawn > expired", function()
		truthy(V(stored{ state = "expired", stateRev = 4 }) > V(stored{ state = "accepted", stateRev = 3 }))
		local order = { "expired", "withdrawn", "declined", "accepted" }
		for i = 2, #order do
			truthy(V(stored{ state = order[i], stateRev = 3 }) > V(stored{ state = order[i - 1], stateRev = 3 }), order[i])
		end
		-- the same with Applications.Newer, the rule of M4.1, wherever it can say
		local a, b = stored{ state = "accepted", stateRev = 3 }, stored{ state = "declined", stateRev = 3 }
		eq(Apps().Newer(a, b), Inbox().Wins(a, b))
		eq(Apps().Newer(b, a), Inbox().Wins(b, a))
	end)

	it("a complete record wins over a tombstone of the same state; a tie ends the same way on every client", function()
		local tomb = stored{ state = "withdrawn", stateRev = 3, tomb = true, cls = "nil", race = "nil", lvl = "nil" }
		local full = stored{ state = "withdrawn", stateRev = 3 }
		truthy(V(full) > V(tomb))
		local byA = stored{ state = "declined", stateRev = 3, by = "Jaina", upd = 1000 }
		local byB = stored{ state = "declined", stateRev = 3, by = "Thrall", upd = 1000 }
		ne(V(byA), V(byB), "two decisions are told apart")
		eq(Inbox().Wins(byA, byB), Inbox().Wins(byB, byA))
		eq(V(stored{}), V(stored{}), "the same record, the same version")
		truthy(V(stored{ state = "accepted", stateRev = 15 }) < 4294967296, "fits the 32-bit integer of the list")
	end)
end)

describe("checking a synced record (INT-06)", function()
	it("keeps a complete record and drops what is optional and wrong", function()
		local t = GetServerTime()
		local rec = Inbox().Sanitize(wire{ ilvl = -4, roles = 1, by = "two words", evil = "x" }, KEY, t)
		notNil(rec)
		eq(rec.k, KEY); eq(rec.cls, 8); eq(rec.lvl, 32)
		isNil(rec.ilvl); isNil(rec.roles, "Tank is not a Mage role"); isNil(rec.by); isNil(rec.evil)
		eq(Inbox().Sanitize(wire{ by = "Jaina-TestRealm" }, KEY, t).by, "Jaina-TestRealm")
		eq(Inbox().Sanitize(wire{ roles = 9 }, KEY, t).roles, 8, "roles of the class only")
		local tomb = Inbox().Sanitize(wire{ state = "withdrawn", stateRev = 3, tomb = true, cls = "nil", race = "nil",
			lvl = "nil" }, KEY, t)
		notNil(tomb)
		eq(tomb.tomb, true)
		local early = Inbox().Sanitize(wire{ at = t - 100, upd = t - 200 }, KEY, t)
		eq(early.upd, t - 100, "a change before the application is moved to it")
	end)

	it("refuses every malformed or forged field, with its reason", function()
		local t = GetServerTime()
		local cases = {
			{ "x", "shape" },
			{ wire{ id = "XYZ" }, "id" }, { wire{ id = "0A1B2C3D" }, "id" }, { wire{ id = 12345678 }, "id" },
			{ wire{ id = "0a1b2c3" }, "id" }, { wire{ id = "nil" }, "id" },
			{ wire{ state = "sent", stateRev = 2 }, "state" }, { wire{ state = "won" }, "state" }, { wire{ state = "nil" }, "state" },
			{ wire{ stateRev = 1 }, "rev" }, { wire{ stateRev = 16 }, "rev" }, { wire{ stateRev = 2.5 }, "rev" },
			{ wire{ stateRev = "2" }, "rev" },
			{ wire{ at = t + 1000 }, "time" }, { wire{ upd = t + 1000 }, "time" }, { wire{ at = 0 }, "time" },
			{ wire{ at = "yesterday" }, "time" }, { wire{ upd = "nil" }, "time" },
			{ wire{ who = "Two Words" }, "who" }, { wire{ who = "|cffff0000Red" }, "who" }, { wire{ who = "nil" }, "who" },
			{ wire{ who = string.rep("a", 65) }, "who" },
			{ wire{ cls = 99 }, "class" }, { wire{ cls = "nil" }, "class" }, { wire{ race = 0 }, "race" },
			{ wire{ race = 256 }, "race" }, { wire{ lvl = 0 }, "level" }, { wire{ lvl = 300 }, "level" },
			{ wire{ tomb = true }, "tomb" },
			{ wire{ state = "declined", stateRev = 3, upd = t - 31 * DAY, at = t - 40 * DAY }, "old" },
		}
		for i, c in ipairs(cases) do
			local rec, why = Inbox().Sanitize(c[1], KEY, t)
			isNil(rec, "case " .. i)
			eq(why, c[2], "case " .. i)
		end
	end)
end)

describe("merging another officer's copy", function()
	it("new, newer, older, same", function()
		asOfficer()
		local t = GetServerTime()
		local function m(extra) return Inbox():Merge(KEY, Inbox().Sanitize(wire(extra), KEY, t)) end
		eq(select(2, m{}), "new")
		eq(select(2, m{}), "same")
		eq(select(2, m{ state = "declined", stateRev = 3, by = "Jaina" }), "newer")
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "declined")
		eq(select(2, m{}), "older", "an open copy never undoes a decision")
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "declined")
		eq(select(2, m{ state = "accepted", stateRev = 3, by = "Thrall" }), "newer", "accepted > declined at the same stateRev")
		eq(Inbox():Get(KEY, "0a1b2c3d").by, "Thrall")
	end)

	it("a tombstone and the complete record end as one complete withdrawn record, whichever came first", function()
		asOfficer()
		local t = GetServerTime()
		-- here: the APPWD before the application (a tombstone); there: the application, then the withdrawal
		Inbox():Withdraw(KEY, "0a1b2c3d", "Elarin-TestRealm")
		eq(Inbox():Get(KEY, "0a1b2c3d").tomb, true)
		local rec, what = Inbox():Merge(KEY, Inbox().Sanitize(wire{ state = "withdrawn", stateRev = 3 }, KEY, t))
		eq(what, "newer"); isNil(rec.tomb); eq(rec.cls, 8)
		-- the other way round: ours complete and received, theirs a tombstone
		Inbox():Receive(stored{ id = "11111111" })
		rec, what = Inbox():Merge(KEY, Inbox().Sanitize(wire{ id = "11111111", state = "withdrawn", stateRev = 3, tomb = true,
			cls = "nil", race = "nil", lvl = "nil", at = t, upd = t }, KEY, t))
		eq(what, "older", "completed with our fields: the sender should learn them")
		eq(rec.state, "withdrawn"); isNil(rec.tomb); eq(rec.lvl, 32); eq(rec.at, t - 3600)
	end)

	it("APP-02: of two open applications of one character the older closes, at the newer one's time", function()
		asOfficer()
		local t = GetServerTime()
		Inbox():Receive(stored{ id = "11111111", at = t - 7200, upd = t - 7000 })
		Inbox():Merge(KEY, Inbox().Sanitize(wire{ id = "22222222", at = t - 600, upd = t - 500 }, KEY, t))
		local old = Inbox():Get(KEY, "11111111")
		eq(old.state, "withdrawn"); eq(old.stateRev, 3); eq(old.upd, t - 600)
		eq(Inbox():Get(KEY, "22222222").state, "received")
		-- an older one arriving later is closed at once
		Inbox():Merge(KEY, Inbox().Sanitize(wire{ id = "33333333", at = t - 9000, upd = t - 8000 }, KEY, t))
		eq(Inbox():Get(KEY, "33333333").state, "withdrawn")
		eq(Inbox():Get(KEY, "22222222").state, "received")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 2: one client, an officer of Aurora
---------------------------------------------------------------------------------------------------------------------
local function setup()
	asOfficer()
	capture()
	S().AUTO = true
end

describe("sending", function()
	it("a change goes out over OFFICER, NORMAL, with the other changes of that moment", function()
		setup()
		Inbox():Receive(stored{ id = "11111111", who = "Aa" })
		Inbox():Receive(stored{ id = "22222222", who = "Bb" })
		eq(#syncs(), 0, "not at once")
		Mock.Advance(3, 0.5)
		local out = syncs()
		eq(#out, 1)
		eq(out[1].dist, "OFFICER"); eq(out[1].opts.prio, "NORMAL"); eq(out[1].msg.k, KEY)
		deepEq(recIds(out), { "11111111", "22222222" })
		isNil(out[1].msg.recs[1].k, "the key travels once, in the message")
		sent = {}
		truthy(Inbox():Decide(KEY, "11111111", "declined", "Testchar"))
		Mock.Advance(3, 0.5)
		out = syncs()
		eq(#out, 1)
		eq(out[1].msg.recs[1].state, "declined"); eq(out[1].msg.recs[1].stateRev, 3); eq(out[1].msg.recs[1].by, "Testchar")
	end)

	it("a record learned from another officer is not sent again; ours newer is sent back", function()
		setup()
		hear{ recs = { wire{ id = "11111111" } } }
		Mock.Advance(6, 0.5)
		eq(#syncs(), 0)
		truthy(Inbox():Decide(KEY, "11111111", "declined", "Testchar"))
		Mock.Advance(3, 0.5)
		sent = {}
		hear{ recs = { wire{ id = "11111111" } } }   -- a late, older copy
		Mock.Advance(6, 0.5)
		deepEq(recIds(syncs()), { "11111111" })
		eq(syncs()[1].msg.recs[1].state, "declined")
	end)

	it("at most PER_MSG records a message and SEND_MAX messages a minute; the rest waits", function()
		setup()
		for i = 1, 25 do Inbox():Receive(stored{ id = ("%08x"):format(i), who = "P" .. string.char(96 + i) }) end
		S().SEND_MAX = 2
		Mock.Advance(3, 0.5)
		eq(#syncs(), 1, "one message of records per PACE")
		Mock.Advance(5, 0.5)
		eq(#syncs(), 2)
		eq(#syncs()[1].msg.recs, 10)
		Mock.Advance(30, 1)
		eq(#syncs(), 2, "SEND_MAX a minute")
		Mock.Advance(30, 1)
		eq(#syncs(), 3)
		eq(#recIds(syncs()), 25)
	end)

	it("at login the compact list goes out over OFFICER", function()
		asOfficer()
		Inbox():Receive(stored{ id = "11111111" })
		Mock.world.inboxSync = true
		Mock.Reload()
		capture()
		Mock.Advance(16, 0.5)
		local lists = syncs(function(m) return m.q == 1 end)
		eq(#lists, 1)
		eq(lists[1].dist, "OFFICER")
		deepEq(lists[1].msg.ids, { ["11111111"] = V(Inbox():Get(KEY, "11111111")) })
	end)

	it("nothing goes out from a character that is not an officer, or with AUTO off", function()
		Mock.guild.Set{ name = GUILD, myRank = 3 }
		A().Role:Refresh()
		capture()
		S().AUTO = true
		falsy(S():SendDigest())
		Mock.world.inboxSync = true
		Mock.Reload()
		capture()
		Mock.Advance(20, 1)
		eq(#syncs(), 0)
		asOfficer()
		Mock.world.inboxSync = false
		Mock.Reload()
		capture()
		Inbox():Receive(stored{ id = "11111111" })
		Mock.Advance(20, 1)
		eq(#syncs(), 0)
	end)
end)

describe("answering", function()
	it("a list: a reply with our version of every id where the copies differ, 0 for one we lack; no records yet", function()
		setup()
		Inbox():Receive(stored{ id = "11111111", who = "Aa" })
		Inbox():Receive(stored{ id = "22222222", who = "Bb" })
		Inbox():Decide(KEY, "22222222", "declined", "Testchar")
		Inbox():Receive(stored{ id = "33333333", who = "Cc" })
		Mock.Advance(10, 0.5)
		sent = {}
		local same = V(Inbox():Get(KEY, "11111111"))
		hear({ q = 1, ids = { ["11111111"] = same, ["22222222"] = V(stored{ id = "22222222" }), ["44444444"] = 12345 } },
			"Jaina-TestRealm")
		Mock.Advance(6, 0.5)
		local replies = syncs(function(m) return m.ids end)
		eq(#replies, 1)
		eq(replies[1].msg.to, "Jaina-TestRealm"); isNil(replies[1].msg.q)
		deepEq(replies[1].msg.ids, { ["22222222"] = V(Inbox():Get(KEY, "22222222")),
			["33333333"] = V(Inbox():Get(KEY, "33333333")), ["44444444"] = 0 })
		eq(#syncs(function(m) return m.recs end), 0, "the asker decides who sends what")
		-- the same sender again within a minute: no answer
		sent = {}
		hear({ q = 1, ids = {} }, "Jaina-TestRealm")
		Mock.Advance(6, 0.5)
		eq(#syncs(), 0)
		eq(S().state.stats.answersLimited, 1)
	end)

	it("the replies to our list: each missing record asked from one officer, the best copy; what they lack sent once", function()
		setup()
		Inbox():Receive(stored{ id = "bbbbbbbb", who = "Bb" })
		Mock.Advance(10, 0.5)
		S().ANSWER_DELAY = { 1, 1 }
		truthy(S():SendDigest())
		sent = {}
		local declined = V(stored{ id = "aaaaaaaa", state = "declined", stateRev = 3 })
		local received = V(stored{ id = "aaaaaaaa" })
		local same = V(stored{ id = "cccccccc" })
		hear({ to = "Testchar-TestRealm", ids = { aaaaaaaa = received, bbbbbbbb = 0, cccccccc = same } }, "Jaina-TestRealm")
		hear({ to = "Testchar-TestRealm", ids = { aaaaaaaa = declined, bbbbbbbb = 0, cccccccc = same } }, "Thrall-TestRealm")
		hear({ to = "Somebody-TestRealm", ids = { dddddddd = same } }, "Garrosh-TestRealm")   -- not for us
		Mock.Advance(3, 0.5)
		local recs = syncs(function(m) return m.recs end)
		deepEq(recIds(recs), { "bbbbbbbb" }, "both lack it: sent once")
		eq(#syncs(function(m) return m.want end), 0, "the replies are gathered first")
		Mock.Advance(4, 0.5)
		local wants = syncs(function(m) return m.want end)
		local byName = {}
		for _, w in ipairs(wants) do byName[w.msg.to] = w.msg.want end
		deepEq(byName["Thrall-TestRealm"] and byName["Thrall-TestRealm"][1], "aaaaaaaa", "the decision from the one that has it")
		local total = 0
		for _, list in pairs(byName) do total = total + #list end
		eq(total, 2, "aaaaaaaa and cccccccc, each from one officer")
		isNil(byName["Garrosh-TestRealm"])
	end)

	it("a request addressed to us is answered with those records; one for somebody else is not", function()
		setup()
		Inbox():Receive(stored{ id = "11111111" })
		Mock.Advance(3, 0.5)
		sent = {}
		hear{ to = "Somebody-TestRealm", want = { "11111111" } }
		Mock.Advance(6, 0.5)
		eq(#syncs(), 0)
		hear{ to = "Testchar-TestRealm", want = { "11111111", "99999999" } }
		Mock.Advance(6, 0.5)
		deepEq(recIds(syncs()), { "11111111" })
	end)

	it("a record sent back is dropped when another officer sends a copy as new first", function()
		setup()
		Inbox():Receive(stored{ id = "11111111" })
		Inbox():Decide(KEY, "11111111", "declined", "Testchar")
		Mock.Advance(3, 0.5)
		sent = {}
		S().ANSWER_DELAY = { 3, 3 }
		hear{ recs = { wire{ id = "11111111" } } }   -- a copy still received: our decision goes back
		Mock.Advance(1, 0.5)
		hear({ recs = { Inbox().Wire(Inbox():Get(KEY, "11111111")) } }, "Thrall-TestRealm")
		Mock.Advance(6, 0.5)
		eq(#syncs(), 0)
		eq(S().state.stats.suppressed, 1)
	end)
end)

describe("history, expiry and the limit", function()
	it("a closed record stays 30 days after its last change; an open one expires at 14 days, the same everywhere", function()
		asOfficer()
		local t = GetServerTime()
		Inbox():Merge(KEY, Inbox().Sanitize(wire{ id = "11111111", who = "Aa", state = "declined", stateRev = 3,
			at = t - 29 * DAY, upd = t - 29 * DAY }, KEY, t))
		Inbox():Receive(stored{ id = "22222222", who = "Bb", at = t - 13 * DAY, upd = t - 13 * DAY })
		local seen = {}
		A().Bus:On("INBOX_CHANGED", function(k, id, st, old, source) seen[#seen + 1] = { id, st or "gone", source } end)
		Mock.Advance(DAY - 3700, 600)
		notNil(Inbox():Get(KEY, "11111111"), "29 days and 23 hours")
		eq(Inbox():Get(KEY, "22222222").state, "received")
		Mock.Advance(2 * 3600, 600)
		isNil(Inbox():Get(KEY, "11111111"), "30 days: gone")
		local exp = Inbox():Get(KEY, "22222222")
		eq(exp.state, "expired"); eq(exp.stateRev, 3); eq(exp.upd, t + DAY, "at the moment it expired, not when it was seen")
		table.sort(seen, function(x, y) return x[1] < y[1] end)
		deepEq(seen, { { "11111111", "gone", "sweep" }, { "22222222", "expired", "sweep" } })
		-- the expired record goes 30 days later
		Mock.Advance(30 * DAY, 3600)
		eq(Inbox():Count(KEY), 0)
	end)

	it("keeps at most the inbox limit: the oldest closed record makes room, a full open inbox takes nothing more", function()
		setup()
		A().Config.LIMITS.APPLICATIONS_PER_INBOX = 3
		local t = GetServerTime()
		local function m(id, who, extra)
			local w = wire(extra)
			w.id, w.who = id, who
			return Inbox():Merge(KEY, Inbox().Sanitize(w, KEY, t))
		end
		m("00000001", "Aa", { state = "declined", stateRev = 3, upd = t - 900 })
		m("00000002", "Bb", { state = "declined", stateRev = 3, upd = t - 800 })
		m("00000003", "Cc")
		eq(Inbox():Count(KEY), 3)
		eq(select(2, m("00000000", "Zz", { state = "declined", stateRev = 3, upd = t - 2000 })), "full",
			"a closed record older than every one we keep is not taken (it would be dropped again)")
		eq(select(2, m("00000004", "Dd")), "new")
		isNil(Inbox():Get(KEY, "00000001"), "the oldest closed one made room")
		eq(select(2, m("00000005", "Ee")), "new")
		isNil(Inbox():Get(KEY, "00000002"))
		eq(select(2, m("00000006", "Ff")), "full", "three open records: nothing more")
		eq(Inbox():Count(KEY), 3)
		-- a list naming records we have no room for: nothing is asked
		Mock.Advance(3, 0.5)
		sent = {}
		hear({ q = 1, ids = { ["00000007"] = 1, ["00000003"] = V(Inbox():Get(KEY, "00000003")),
			["00000004"] = V(Inbox():Get(KEY, "00000004")), ["00000005"] = V(Inbox():Get(KEY, "00000005")) } })
		Mock.Advance(6, 0.5)
		eq(#syncs(), 0)
		A().Config.LIMITS.APPLICATIONS_PER_INBOX = 200
	end)
end)

describe("the officer role lost (SPEC-07 §4)", function()
	it("stops at once and deletes the box at the next login; an officer keeps its own guild's box only", function()
		setup()
		Inbox():Receive(stored{ id = "11111111" })
		Inbox():Records(OTHER, true)["22222222"] = stored{ id = "22222222", k = OTHER }
		Mock.Advance(3, 0.5)
		-- still an officer: a login keeps this guild's box and deletes the other guild's
		Mock.Reload()
		Mock.Advance(61, 1)
		notNil(Inbox():Get(KEY, "11111111"))
		isNil(Inbox():Records(OTHER))
		eq(S().state.stats.cleaned, 1)
		-- demoted: nothing is taken or sent any more, the box stays until the next login
		capture()
		S().AUTO = true
		Mock.guild.SetMyRank(3)
		A().Role:Refresh()
		eq(A().Role:Get(), "member")
		falsy(hear{ recs = { wire{ id = "33333333" } } })
		isNil(Inbox():Get(KEY, "33333333"))
		eq(S().state.stats.notMine, 1)
		Mock.Advance(70, 1)
		notNil(Inbox():Get(KEY, "11111111"), "deleted at the next login, not before")
		eq(#syncs(), 0)
		Mock.Reload()
		Mock.Advance(30, 1)
		notNil(Inbox():Get(KEY, "11111111"), "the role is looked at a minute after the login")
		Mock.Advance(31, 1)
		isNil(Inbox():Records(KEY))
		eq(#Inbox():Keys(), 0)
		eq(#AzerothGuildFinderCharDB.officerInbox == 0 and next(AzerothGuildFinderCharDB.officerInbox) == nil, true)
	end)

	it("a character that left the guild deletes it too", function()
		setup()
		Inbox():Receive(stored{ id = "11111111" })
		Mock.guild.Leave()
		Mock.Reload()
		Mock.Advance(61, 1)
		eq(#Inbox():Keys(), 0)
	end)
end)

describe("malformed sync", function()
	it("is dropped with its reason and never breaks anything", function()
		setup()
		Inbox():Receive(stored{ id = "11111111" })
		Mock.Advance(3, 0.5)
		sent = {}
		local before = V(Inbox():Get(KEY, "11111111"))
		local good = { recs = { wire{ id = "22222222", who = "Bb" } } }
		eq(select(2, hear(good, "Jaina-TestRealm", "GUILD")), "dist", "GUILD while the protocol uses OFFICER")
		eq(select(2, hear({ recs = good.recs }, "Jaina-TestRealm", "WHISPER")), "dist")
		eq(select(2, hear({ recs = good.recs }, "Jaina-TestRealm", "CHANNEL")), "dist")
		eq(select(2, hear({ recs = good.recs }, "Two Words")), "sender")
		eq(select(2, hear({ recs = good.recs }, "Testchar-TestRealm")), "self", "our own echo")
		eq(select(2, hear({ k = OTHER, recs = good.recs })), "notmine")
		eq(select(2, hear({ k = 7, recs = good.recs })), "notmine")
		isNil(Inbox():Get(KEY, "22222222"))
		falsy(hear{ recs = "x" })
		falsy(hear{ q = 1, ids = "x" }, "ids not a table")
		falsy(hear({ q = 1, ids = { ["XYZ"] = 1 } }, "Thrall"))
		falsy(hear({ q = 1, ids = { ["11111111"] = -1 } }, "Garrosh"))
		falsy(hear({ q = 1, ids = { ["11111111"] = "1" } }, "Aa"))
		local many = {}
		for i = 1, S().MAX_IDS + 1 do many[("%08x"):format(i)] = 1 end
		falsy(hear({ q = 1, ids = many }, "Bb"))
		falsy(hear{ to = "Two Words", want = { "11111111" } })
		falsy(hear{ to = "Testchar", want = "11111111" })
		falsy(hear{ to = "Testchar", want = { "nope" } })
		falsy(hear{ to = "Testchar", want = { x = "11111111" } })
		-- a good message with bad records inside: the good ones count, the bad ones are counted
		truthy(hear{ recs = { wire{ id = "33333333", who = "Cc" }, wire{ id = "BAD" }, "x", wire{ id = "44444444", cls = 99 },
			wire{ id = "11111111", state = "accepted", stateRev = 3, at = GetServerTime() + 9999 } } })
		notNil(Inbox():Get(KEY, "33333333"))
		isNil(Inbox():Get(KEY, "44444444"))
		eq(V(Inbox():Get(KEY, "11111111")), before, "a forged decision with a time in the future changed nothing")
		local by = S().state.stats.rejectedBy
		eq(by.dist, 3); eq(by.sender, 1); eq(by.recs, 1); eq(by.ids, 4); eq(by.toomany, 1); eq(by.to, 1); eq(by.want, 3)
		eq(by.id, 1); eq(by.shape, 1); eq(by.class, 1); eq(by.time, 1)
		Mock.Advance(6, 0.5)
		eq(#syncs(), 0, "nothing was answered")
		eq(#Mock.errors, 0)
	end)

	it("a payload that is not a message, through the real transport, is dropped", function()
		asOfficer()
		local T = A().Transport
		falsy(T:OnReceive("garbage", "OFFICER", "Jaina-TestRealm"))
		local payload = A().Codec:Encode("APPSYNC", { k = KEY, recs = { { id = "nope" } } })
		truthy(T:OnReceive(payload, "OFFICER", "Jaina-TestRealm"))
		eq(Inbox():Count(KEY), 0)
		eq(S().state.stats.rejectedBy.id, 1)
		eq(#Mock.errors, 0)
	end)

	it("damaged saved boxes are repaired at load", function()
		asOfficer()
		local t = GetServerTime()
		AzerothGuildFinderCharDB.officerInbox = {
			[KEY] = { recs = { ["11111111"] = stored{ id = "11111111" }, ["22222222"] = { id = "22222222", state = "won" },
				["33333333"] = stored{ id = "44444444" }, x = 5 }, junk = true },
			["not a key"] = { recs = {} },
			[OTHER] = "x",
		}
		Mock.Reload()
		eq(Inbox():Count(KEY), 1)
		notNil(Inbox():Get(KEY, "11111111"))
		eq(#Inbox():Keys(), 1)
		eq(Inbox().fixes, 5)
		isNil(AzerothGuildFinderCharDB.officerInbox[KEY].junk)
		eq(Inbox():Get(KEY, "11111111").at, t - 3600)
	end)
end)

describe("the GUILD fallback (SPEC-02 §7, spike S5)", function()
	it("sends on GUILD; a GUILD message counts only from a rank that reads officer chat; OFFICER still counts", function()
		setup()
		S().DIST = "GUILD"
		A().Compat.Guild.RequestRoster()   -- the roster says who reads officer chat
		Mock.Advance(1, 0.5)
		Inbox():Receive(stored{ id = "11111111" })
		Mock.Advance(3, 0.5)
		eq(syncs()[1].dist, "GUILD")
		truthy(hear({ recs = { wire{ id = "22222222", who = "Bb" } } }, "Thrall-TestRealm", "GUILD"), "the Guild Master")
		truthy(hear({ recs = { wire{ id = "33333333", who = "Cc" } } }, "Jaina", "GUILD"), "an officer rank")
		eq(select(2, hear({ recs = { wire{ id = "44444444", who = "Dd" } } }, "Garrosh-TestRealm", "GUILD")), "rank",
			"a plain member")
		eq(select(2, hear({ recs = { wire{ id = "55555555", who = "Ee" } } }, "Stranger", "GUILD")), "rank", "not in the roster")
		truthy(hear({ recs = { wire{ id = "66666666", who = "Ff" } } }, "Jaina", "OFFICER"))
		eq(Inbox():Count(KEY), 4)
		-- a plain member that hears the GUILD messages ignores them
		Mock.guild.SetMyRank(3)
		A().Role:Refresh()
		eq(select(2, hear({ recs = { wire{ id = "77777777", who = "Gg" } } }, "Thrall", "GUILD")), "notmine")
		S().DIST = "OFFICER"
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 3: the simulator
---------------------------------------------------------------------------------------------------------------------
-- Client 1 = the Guild Master, 2 and 3 = officers, 4 = a plain member. Steps of 1 s.
local function officersSim(seed)
	local ranks = { 0, 1, 1, 3 }
	local sim = Sim.new{ clients = 4, seed = seed, latency = { 0.1, 0.4 }, step = 1, sync = false,
		setup = function(M, i)
			M.world.inboxSync = true
			local members = {}
			for j = 1, 4 do
				if j ~= i then members[#members + 1] = { name = Sim.nameOf(j), rank = ranks[j] } end
			end
			M.guild.Set{ name = GUILD, realm = "Test Realm", myRank = ranks[i], members = members }
		end }
	for i = 1, 4 do sim:client(i):addon().Role:Refresh() end
	return sim
end

-- What a client keeps, as text: equal texts are equal inboxes.
local function snapshot(c)
	local out = {}
	for _, r in ipairs(c:addon().Inbox:List(KEY)) do
		out[#out + 1] = table.concat({ r.id, r.state, r.stateRev, r.at, r.upd, tostring(r.by), tostring(r.tomb), tostring(r.who),
			tostring(r.cls), tostring(r.lvl), tostring(r.roles) }, " ")
	end
	return table.concat(out, "\n")
end

-- An application as Delivery stores it on client c.
local function received(c, id, who, minutesAgo)
	local t = c.E.GetServerTime()
	local rec = { id = id, k = KEY, who = who .. "-TestRealm", cls = 8, race = 5, lvl = 30, roles = 8, at = t - minutesAgo * 60,
		state = "received", stateRev = 2, upd = t }
	return c:addon().Inbox:Receive(rec)
end

local function login(c)
	c:setOnline(true)
	c:reload()
	c:addon().Role:Refresh()
end

describe("simulator", function()
	it("two officers and the Guild Master converge on the same inbox after offline periods", function()
		local sim = officersSim(11)
		local gm, a, b, member = sim:client(1), sim:client(2), sim:client(3), sim:client(4)
		sim:advance(20)   -- the lists at login, all empty
		-- B is away; A receives two applications and declines one; the Guild Master learns it at once
		b:setOnline(false)
		received(a, "aaaa0001", "Elarin", 30)
		received(a, "aaaa0002", "Brom", 20)
		sim:advance(5)
		truthy(a:addon().Inbox:Decide(KEY, "aaaa0001", "declined", a.name))
		sim:advance(5)
		eq(snapshot(gm), snapshot(a), "the Guild Master was online: the changes reached it")
		eq(gm:addon().Inbox:Get(KEY, "aaaa0001").state, "declined")
		-- A and the Guild Master log off; B logs in alone: a late copy of the first application (accepted by B, a
		-- conflict with A's decline), the withdrawal of the second (a tombstone: B never had it), a third application
		gm:setOnline(false)
		a:setOnline(false)
		sim:advance(3600)
		login(b)
		sim:advance(30)
		eq(b:addon().Inbox:Count(KEY), 0, "nobody online to answer")
		received(b, "aaaa0001", "Elarin", 30)
		truthy(b:addon().Inbox:Decide(KEY, "aaaa0001", "accepted", b.name))
		b:addon().Inbox:Withdraw(KEY, "aaaa0002", "Brom-TestRealm")
		received(b, "bbbb0003", "Cyra", 5)
		sim:advance(10)
		-- B logs off; A logs in, then B again while A is online
		b:setOnline(false)
		sim:advance(2 * 3600)
		login(a)
		sim:advance(30)
		local start = sim.time
		login(b)
		truthy(sim:advanceUntil(function() return snapshot(a) == snapshot(b) end, 120), "A and B converge")
		T.log(("A and B converged %d s after B's login"):format(sim.time - start))
		local inbox = a:addon().Inbox
		eq(inbox:Get(KEY, "aaaa0001").state, "accepted", "accepted > declined at the same stateRev")
		eq(inbox:Get(KEY, "aaaa0001").by, b.name)
		local wd = inbox:Get(KEY, "aaaa0002")
		eq(wd.state, "withdrawn"); isNil(wd.tomb, "the tombstone was completed with A's copy"); eq(wd.who, "Brom-TestRealm")
		eq(inbox:Get(KEY, "bbbb0003").state, "received")
		eq(inbox:Count(KEY), 3)
		-- the Guild Master comes back last and catches up
		login(gm)
		truthy(sim:advanceUntil(function() return snapshot(gm) == snapshot(a) and snapshot(gm) == snapshot(b) end, 120),
			"all three converge")
		sim:advance(60)
		eq(snapshot(gm), snapshot(a)); eq(snapshot(a), snapshot(b))
		-- the member never hears an APPSYNC and keeps no box
		eq(member.recv.OFFICER.msgs, 0)
		eq(#member:addon().Inbox:Keys(), 0)
		for i = 1, 4 do eq(#sim:client(i).Mock.errors, 0) end
		for i = 1, 3 do eq(sim:client(i):addon().InboxSync.state.stats.refused, 0) end
	end)

	it("the traffic stays within the module's budget while a full inbox is copied", function()
		local sim = officersSim(5)
		local a, b = sim:client(2), sim:client(3)
		sim:advance(20)
		b:setOnline(false)
		for i = 1, 60 do received(a, ("cc%06x"):format(i), "P" .. ("%03d"):format(i), 60) end
		sim:advance(120)
		-- every APPSYNC handed to the transport, per client and minute
		local perMinute, worst = {}, 0
		local function count(c)
			local T0 = c:addon().Transport
			local send = T0.Send
			T0.Send = function(self, dist, msg, opts)
				if msg.t == "APPSYNC" then
					local key = c.index .. ":" .. math.floor(sim.time / 60)
					perMinute[key] = (perMinute[key] or 0) + 1
					if perMinute[key] > worst then worst = perMinute[key] end
				end
				return send(self, dist, msg, opts)
			end
		end
		local before = a:addon().InboxSync.state.stats.sentRecs + sim:client(1):addon().InboxSync.state.stats.sentRecs
		count(a); count(sim:client(1))
		local start = sim.time
		login(b)
		count(b)
		truthy(sim:advanceUntil(function() return snapshot(a) == snapshot(b) end, 600), "B catches up")
		eq(b:addon().Inbox:Count(KEY), 60)
		local copies = a:addon().InboxSync.state.stats.sentRecs + sim:client(1):addon().InboxSync.state.stats.sentRecs - before
		T.log(("60 records copied to B in %d s: %d record copies sent by A and the Guild Master, at most %d APPSYNC a minute from one client"):format(
			sim.time - start, copies, worst))
		truthy(worst <= a:addon().InboxSync.SEND_MAX, "SEND_MAX messages a minute")
		truthy(copies <= 66, "each record from one officer only")
		truthy(a:addon().InboxSync.state.stats.sentRecs - 60 > 0 and sim:client(1):addon().InboxSync.state.stats.sentRecs > 0,
			"the work is shared by the two officers that had the records")
	end)
end)
