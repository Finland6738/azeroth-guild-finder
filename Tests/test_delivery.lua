-- M4.2: delivery of applications to the guild's contacts (SPEC-07 §3, SPEC-02 §3-§5, Net/Delivery.lua, Data/Inbox.lua).
-- Part 1 is pure Lua: the INT-06 checks of an APPLY, the backoff, the messages. Part 2 runs one client: the applicant's
-- side (contacts from ANN c = 1 for 30 minutes, APPLY / APPPING / APPWD by whisper, the 15 s wait, retries on every
-- contact with a backoff, withdraw before and after receipt, forged answers, the "cannot send" explanation) and the
-- officer's side (APPLY to the store, APPACK, APPPING, APPWD, malformed and forged messages, reply limits). Part 3 runs
-- the network simulator: an application reaches an officer who comes online hours later, and a decision taken while the
-- applicant was away is learned at the next contact.
-- The mock player is "Testchar", Horde Orc Warrior 60 on "Test Realm", no guild.

local DAY = 86400
local GUILD = "Aurora"
local KEY = "TestRealm|Horde|" .. GUILD
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })

local function A() return AzerothGuildFinder end
local function D() return A().Delivery end
local function Apps() return A().Applications end
local function Inbox() return A().Inbox end

local function summary(extra)
	local t = { k = KEY, rev = 3, upd = 1767000000, first = 1760000000, own = "a1b2c3d4", sub = "Friendly",
		lang = 1, lang1 = 1, tags = { 1 }, pace = 1, days = 31, t0 = 1140, t1 = 1350, rec = 1, apps = true, want = { [0] = 15 },
		newb = true, minL = 20 }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

-- An ANN of the guild heard on the channel; c = 1 when `contact`.
local function hearAnn(sender, contact, extra)
	local msg = summary(extra)
	msg.t, msg.v, msg.c = "ANN", 1, contact and 1 or nil
	A().Sync:OnMessage(msg, sender, "CHANNEL")
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
local function sentOf(t)
	local out = {}
	for _, s in ipairs(sent) do if s.msg.t == t then out[#out + 1] = s end end
	return out
end

local function whisper(msg, sender) return D():OnMessage(msg, sender, "WHISPER") end
local function ack(id, state, sender) return whisper({ t = "APPACK", v = 1, id = id, state = state }, sender or "Jaina-TestRealm") end

-- The applicant applies to GUILD (the listing in the catalog first).
local function apply(roles)
	A().Catalog:PutSummary(summary())   -- "unchanged" when an ANN brought it already
	local ok, rec = Apps():Apply(KEY, roles)
	assert(ok, tostring(rec))
	return rec
end

---------------------------------------------------------------------------------------------------------------------
-- Part 1: pure checks
---------------------------------------------------------------------------------------------------------------------
local NOW = 1767225600
local function applyMsg(extra)
	local m = { t = "APPLY", v = 1, id = "0a1b2c3d", k = KEY, who = "Elarin-TestRealm", cls = 8, race = 5, lvl = 32,
		ilvl = 41, roles = 8, at = NOW - 60 }
	for k, v in pairs(extra or {}) do if v == "nil" then m[k] = nil else m[k] = v end end
	return m
end

describe("checking an APPLY (INT-06)", function()
	it("a complete application becomes a received record, stateRev 2", function()
		local rec = D().ParseApply(applyMsg(), "Elarin-TestRealm", NOW)
		notNil(rec)
		eq(rec.state, "received"); eq(rec.stateRev, 2); eq(rec.upd, NOW)
		eq(rec.who, "Elarin-TestRealm"); eq(rec.cls, 8); eq(rec.race, 5); eq(rec.lvl, 32); eq(rec.ilvl, 41)
		eq(rec.roles, 8); eq(rec.at, NOW - 60)
		-- the sender may come without the realm (same realm): the name decides
		notNil(D().ParseApply(applyMsg(), "elarin", NOW))
	end)

	it("refuses every malformed or forged field, with its reason", function()
		local cases = {
			{ { id = "XYZ12345" }, "id" }, { { id = "0A1B2C3D" }, "id" }, { { id = "0a1b2c3" }, "id" }, { { id = 5 }, "id" },
			{ { k = "nonsense" }, "key" }, { { k = "TestRealm|Elves|Aurora" }, "key" },
			{ { who = "nil" }, "who" }, { { who = "" }, "who" }, { { who = "Ela|cffff0000rin" }, "who" },
			{ { who = "Ela rin" }, "who" }, { { who = string.rep("a", 65) }, "who" }, { { who = "Thrall-TestRealm" }, "sender" },
			{ { cls = 99 }, "class" }, { { cls = 0 }, "class" }, { { cls = 2.5 }, "class" }, { { cls = "8" }, "class" },
			{ { race = 0 }, "race" }, { { race = "nil" }, "race" },
			{ { lvl = 0 }, "level" }, { { lvl = 61 }, "level" }, { { lvl = 32.5 }, "level" },
			{ { at = "nil" }, "time" }, { { at = NOW + 3600 }, "time" }, { { at = -5 }, "time" },
			{ { at = NOW - 14 * DAY }, "old" },
		}
		for i, c in ipairs(cases) do
			local rec, why = D().ParseApply(applyMsg(c[1]), "Elarin-TestRealm", NOW)
			isNil(rec, "case " .. i)
			eq(why, c[2], "case " .. i)
		end
	end)

	it("drops what is optional and wrong: item level, roles not of the class", function()
		local rec = D().ParseApply(applyMsg({ ilvl = -3, roles = 1 + 8 }), "Elarin-TestRealm", NOW)
		isNil(rec.ilvl)
		eq(rec.roles, 8, "a Mage cannot tank")
		rec = D().ParseApply(applyMsg({ ilvl = "x", roles = 99 }), "Elarin-TestRealm", NOW)
		isNil(rec.ilvl); isNil(rec.roles)
		-- fields the message does not define never reach the record
		rec = D().ParseApply(applyMsg({ by = "Thrall", state = "accepted", stateRev = 9, wd = true }), "Elarin", NOW)
		eq(rec.state, "received"); eq(rec.stateRev, 2); isNil(rec.by); isNil(rec.wd)
	end)

	it("the backoff doubles from 60 s to at most 30 minutes", function()
		eq(D().Backoff(0), 0); eq(D().Backoff(1), 60); eq(D().Backoff(2), 120); eq(D().Backoff(3), 240)
		eq(D().Backoff(6), 1800); eq(D().Backoff(20), 1800)
	end)

	it("APPLY carries the record, APPPING and APPWD only the id", function()
		local rec = { id = "0a1b2c3d", k = KEY, who = "A-B", cls = 1, race = 2, lvl = 3, at = 4, state = "sent", stateRev = 1,
			unseen = true, wd = true }
		deepEq(D().MessageFor("APPLY", rec), { t = "APPLY", id = "0a1b2c3d", k = KEY, who = "A-B", cls = 1, race = 2, lvl = 3, at = 4 })
		deepEq(D().MessageFor("APPPING", rec), { t = "APPPING", id = "0a1b2c3d" })
		deepEq(D().MessageFor("APPWD", rec), { t = "APPWD", id = "0a1b2c3d" })
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 2a: the applicant's side on one client
---------------------------------------------------------------------------------------------------------------------
describe("the applicant: contacts and APPLY", function()
	it("with no contact heard the application stays sent and nothing goes out", function()
		capture()
		local rec = apply()
		eq(#sent, 0)
		eq(rec.state, "sent")
		hearAnn("Garrosh-TestRealm", false)   -- a member's ANN (no c = 1) is not a contact
		eq(#sent, 0)
		eq(#A().Sync:Contacts(KEY), 0)
	end)

	it("APPLY goes by whisper to the contact heard most recently, ALERT, with the record", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		Mock.Advance(30, 10)
		hearAnn("Thrall-TestRealm", true)
		local rec = apply(2 + 4)
		local a = sentOf("APPLY")
		eq(#a, 1)
		eq(a[1].dist, "WHISPER"); eq(a[1].opts.target, "Thrall-TestRealm"); eq(a[1].opts.prio, "ALERT")
		local m = a[1].msg
		eq(m.id, rec.id); eq(m.k, KEY); eq(m.who, "Testchar-TestRealm"); eq(m.cls, 1); eq(m.race, 2); eq(m.lvl, 60)
		eq(m.roles, 4, "a Warrior cannot heal"); eq(m.at, rec.at)
		-- waiting for the answer: nothing else goes out
		hearAnn("Thrall-TestRealm", true)
		eq(#sentOf("APPLY"), 1)
	end)

	it("a contact counts for 30 minutes only", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		Mock.Advance(1801, 60)
		apply()
		eq(#sent, 0)
		hearAnn("Jaina-TestRealm", true)
		eq(#sentOf("APPLY"), 1, "heard again: it goes out")
	end)

	it("APPACK received: the record is received, the chat line, no APPPING right after", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		local rec = apply()
		Mock.ClearOutput()
		truthy(ack(rec.id, "received"))
		eq(rec.state, "received"); eq(rec.stateRev, 2)
		truthy(table.concat(Mock.PlainOutput(), "\n"):find("Your application to Aurora was received by an officer.", 1, true))
		Mock.Advance(60, 10)
		hearAnn("Jaina-TestRealm", true)
		eq(#sentOf("APPPING"), 0, "an answer a minute ago: no need to ask")
		Mock.Advance(D().PING_GAP, 60)
		hearAnn("Jaina-TestRealm", true)
		local p = sentOf("APPPING")
		eq(#p, 1); deepEq(p[1].msg, { t = "APPPING", id = rec.id })
		truthy(ack(rec.id, "accepted"))
		eq(rec.state, "accepted")
	end)

	it("no APPACK in 15 s: the next contact; when every contact is silent it waits", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		Mock.Advance(1, 1)
		hearAnn("Thrall-TestRealm", true)
		apply()
		eq(sent[1].opts.target, "Thrall-TestRealm")
		Mock.Advance(14, 1)
		eq(#sent, 1)
		Mock.Advance(1.5, 0.5)
		eq(#sent, 2, "15 s of silence: the next contact")
		eq(sent[2].opts.target, "Jaina-TestRealm")
		Mock.Advance(16, 1)
		eq(#sent, 2, "every contact is silent: wait")
		eq(D().state.stats.timeouts, 2)
	end)

	it("a contact the game says is offline is skipped at once; a throttle is not a refusal of the character", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		Mock.Advance(1, 1)
		hearAnn("Thrall-TestRealm", true)
		apply()
		sent[1].opts.onFail("TargetOffline")
		eq(#sent, 2, "no 15 s wait")
		eq(sent[2].opts.target, "Jaina-TestRealm")
		sent[2].opts.onFail("AddonMessageThrottle")
		isNil(D():CannotSend())
		eq(#sent, 2, "both silent now")
	end)

	it("a silent contact is tried again on its next appearance after 60 s, then 120 s", function()
		capture()
		hearAnn("Thrall-TestRealm", true)
		local rec = apply()                       -- t = 0
		Mock.Advance(16, 1)                       -- silent at 15: waits until 75
		hearAnn("Thrall-TestRealm", true)
		Mock.Advance(30, 10)
		hearAnn("Thrall-TestRealm", true)         -- t = 46
		eq(#sent, 1, "inside the 60 s backoff")
		Mock.Advance(34, 1)
		hearAnn("Thrall-TestRealm", true)         -- t = 80
		eq(#sent, 2, "backoff over: tried again on the next appearance")
		Mock.Advance(16, 1)                       -- silent again at 95: waits until 215
		Mock.Advance(104, 4)
		hearAnn("Thrall-TestRealm", true)         -- t = 200
		eq(#sent, 2, "the second silence doubles the wait")
		Mock.Advance(20, 10)
		hearAnn("Thrall-TestRealm", true)         -- t = 220
		eq(#sent, 3)
		truthy(ack(rec.id, "received", "Thrall-TestRealm"))
		eq(rec.state, "received")
		eq(D().state.stats.timeouts, 2)
	end)

	it("an application saved with nobody online goes out when a contact appears hours later", function()
		capture()
		local rec = apply()
		Mock.Advance(5 * 3600, 600)
		eq(#sent, 0)
		eq(rec.state, "sent")
		hearAnn("Jaina-TestRealm", true)
		eq(#sentOf("APPLY"), 1)
		truthy(ack(rec.id, "received"))
		eq(rec.state, "received")
	end)

	it("an answer from someone it did not whisper, for another id or with a bad state is ignored", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		local rec = apply()
		falsy(ack(rec.id, "accepted", "Mallory-TestRealm"), "a stranger")
		falsy(ack("ffffffff", "received"), "an id we do not have")
		falsy(ack(rec.id, "approved"), "not a state")
		falsy(D():OnMessage({ t = "APPACK", v = 1, id = rec.id, state = "accepted" }, "Jaina-TestRealm", "CHANNEL"),
			"an answer on the channel")
		eq(rec.state, "sent")
		eq(D().state.stats.ackIgnored, 3)
		-- a late but genuine answer (after the 15 s) is still taken: the contact was whispered
		Mock.Advance(20, 5)
		truthy(ack(rec.id, "received"))
		eq(rec.state, "received")
	end)

	it("respects the whisper limit: at most SEND_MAX per minute", function()
		capture()
		D().SEND_MAX = 2
		for i = 1, 5 do hearAnn("Officer" .. string.char(96 + i) .. "-TestRealm", true) end
		apply()
		Mock.Advance(16, 1)       -- silence: second contact
		Mock.Advance(16, 1)       -- silence: the third must wait for the minute
		eq(#sent, 2)
		eq(D().state.stats.deferred, 1)
		Mock.Advance(30, 1)
		eq(#sent, 3, "the window moved on")
	end)
end)

describe("the applicant: withdrawing", function()
	it("withdrawn before any officer had it: APPWD, and the confirmation clears 'Withdrawing...'", function()
		capture()
		local rec = apply()
		truthy(Apps():Withdraw())
		eq(#sent, 0, "nobody to tell yet")
		hearAnn("Jaina-TestRealm", true)
		local w = sentOf("APPWD")
		eq(#w, 1); eq(sentOf("APPLY")[1], nil, "the application itself never goes out")
		deepEq(w[1].msg, { t = "APPWD", id = rec.id })
		truthy(rec.wd)
		truthy(ack(rec.id, "withdrawn"))
		isNil(rec.wd); eq(rec.state, "withdrawn")
		hearAnn("Jaina-TestRealm", true)
		eq(#sent, 1, "done: nothing more")
	end)

	it("withdrawn after receipt: APPWD; an officer's final state confirms it too", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		local rec = apply()
		truthy(ack(rec.id, "received"))
		truthy(Apps():Withdraw())
		local w = sentOf("APPWD")
		eq(#w, 1, "a contact is around: at once")
		eq(w[1].opts.target, "Jaina-TestRealm")
		truthy(ack(rec.id, "declined"))   -- the officer had already declined it
		isNil(rec.wd); eq(rec.state, "withdrawn")
	end)

	it("a withdrawn application and a new one go out side by side, each to its guild", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		local first = apply()
		truthy(ack(first.id, "received"))
		truthy(Apps():Withdraw())
		truthy(ack(first.id, "withdrawn"))
		local other = "TestRealm|Horde|Iron Wolves"
		local sum = summary({ k = other })
		assert(A().Catalog:PutSummary(sum))
		local ok, second = Apps():Apply(other)
		truthy(ok)
		eq(#sentOf("APPLY"), 1, "no contact of Iron Wolves yet")
		local msg = summary({ k = other })
		msg.t, msg.v, msg.c = "ANN", 1, 1
		A().Sync:OnMessage(msg, "Garrosh-TestRealm", "CHANNEL")
		local a = sentOf("APPLY")
		eq(#a, 2); eq(a[2].msg.id, second.id); eq(a[2].opts.target, "Garrosh-TestRealm")
	end)
end)

describe("the applicant: when nothing can go out (SPEC-01 §8)", function()
	it("a refused whisper: CannotSend says so and My Application explains it; a whisper that goes clears it", function()
		capture()
		hearAnn("Jaina-TestRealm", true)
		local rec = apply()
		isNil(D():CannotSend())
		local changed = {}
		A().Bus:On("DELIVERY_CHANGED", function(why) changed[#changed + 1] = why or "none" end)
		sent[1].opts.onFail("GeneralError")
		eq(D():CannotSend(), "whisper")
		local v = A().MyApplication:View()
		eq(v.cannotSend, "whisper")
		truthy(v.body:find(L["MA_CANT_SEND"], 1, true))
		truthy(v.body:find("Waiting", 1, true) == nil and v.body:find("Aurora", 1, true))
		-- an offline target is not a refusal of this character
		D().state.blocked = nil
		D():CheckCannotSend()
		sent[1].opts.onFail("TargetOffline")
		isNil(D():CannotSend())
		sent[1].opts.onFail("GeneralError")
		sent[1].opts.onSent()
		isNil(D():CannotSend())
		deepEq(changed, { "whisper", "none", "whisper", "none" })
		-- a received application has nothing to send: no explanation
		truthy(ack(rec.id, "received"))
		sent[1].opts.onFail("GeneralError")
		isNil(A().MyApplication:View().cannotSend)
	end)

	it("listen-only and read-only are explained too", function()
		apply()
		A().Transport.IsListenOnly = function() return true, "InvalidChannel" end
		eq(D():CannotSend(), "listenonly")
		eq(A().MyApplication:View().cannotSend, "listenonly")
		A().Transport.IsReadOnly = function() return true end
		eq(D():CannotSend(), "restricted")
	end)

	it("with the real transport a refused whisper reaches CannotSend", function()
		Mock.Advance(6)   -- ChatThrottleLib clamps hard for five seconds after start-up
		hearAnn("Jaina-TestRealm", true)
		Mock.chat.forceResult = Enum.SendAddonMessageResult.GeneralError
		apply()
		Mock.Advance(2, 0.2)
		eq(D():CannotSend(), "whisper")
		Mock.chat.forceResult = nil
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 2b: the officer's side on one client
---------------------------------------------------------------------------------------------------------------------
local function asOfficer(rank)
	Mock.guild.Set{ name = GUILD, myRank = rank or 1, members = { { name = "Thrall", rank = 0 }, { name = "Garrosh", rank = 3 } } }
	A().Role:Refresh()
end
local function freshApply(extra)
	local m = applyMsg(extra)
	m.at = GetServerTime() - 60
	if extra and extra.at then m.at = extra.at end
	return m
end
local function answers()
	local out = {}
	for _, s in ipairs(sentOf("APPACK")) do out[#out + 1] = { s.opts.target, s.msg.id, s.msg.state } end
	return out
end

describe("the officer: receiving", function()
	it("a valid APPLY is stored as received and answered with APPACK", function()
		asOfficer()
		capture()
		local seen = {}
		A().Bus:On("INBOX_CHANGED", function(...) seen[#seen + 1] = { ... } end)
		truthy(whisper(freshApply(), "Elarin-TestRealm"))
		local rec = Inbox():Get(KEY, "0a1b2c3d")
		notNil(rec)
		eq(rec.state, "received"); eq(rec.who, "Elarin-TestRealm"); eq(rec.lvl, 32)
		deepEq(answers(), { { "Elarin-TestRealm", "0a1b2c3d", "received" } })
		eq(sentOf("APPACK")[1].opts.prio, "ALERT")
		deepEq(seen, { { KEY, "0a1b2c3d", "received" } })
		-- saved per character
		eq(AzerothGuildFinderCharDB.officerInbox[KEY].recs["0a1b2c3d"].state, "received")
	end)

	it("the Guild Master receives too; a member, a character of another guild or without a guild does not", function()
		asOfficer(0)
		capture()
		truthy(whisper(freshApply(), "Elarin"))
		eq(#answers(), 1)
		asOfficer(3)
		sent = {}
		falsy(whisper(freshApply({ id = "11111111" }), "Elarin"))
		eq(#sent, 0)
		Mock.guild.Set{ name = "Iron Wolves", myRank = 0 }
		A().Role:Refresh()
		falsy(whisper(freshApply({ id = "22222222" }), "Elarin"))
		Mock.guild.Leave()
		A().Role:Refresh()
		falsy(whisper(freshApply({ id = "33333333" }), "Elarin"))
		eq(#sent, 0)
		eq(D().state.stats.notMine, 3)
	end)

	it("a malformed or forged APPLY is dropped silently", function()
		asOfficer()
		capture()
		falsy(whisper(freshApply({ who = "Thrall-TestRealm" }), "Elarin-TestRealm"), "for someone else")
		falsy(whisper(freshApply({ cls = 42 }), "Elarin-TestRealm"))
		falsy(whisper(freshApply({ at = GetServerTime() + DAY }), "Elarin-TestRealm"))
		falsy(whisper(freshApply({ id = "not hex!" }), "Elarin-TestRealm"))
		falsy(D():OnMessage(freshApply(), "Elarin-TestRealm", "CHANNEL"), "only by whisper")
		falsy(D():OnMessage(freshApply(), "Elarin-TestRealm", "GUILD"))
		falsy(whisper(freshApply({ who = "Testchar-TestRealm" }), "Testchar-TestRealm"), "our own")
		falsy(whisper(freshApply(), "Bad|Name"))
		eq(#sent, 0)
		eq(Inbox():Count(KEY), 0)
		local text = table.concat(D():DebugLines(), "\n")
		truthy(text:find("rejected 8", 1, true))
		falsy(text:find("Elarin", 1, true))
	end)

	it("the whole way through the client: a whispered payload in, an APPACK payload out", function()
		asOfficer()
		Mock.Advance(6)
		local payload = A().Codec:Encode("APPLY", freshApply())
		truthy(Mock.chat.Receive("AzGF", payload, "WHISPER", "Elarin-TestRealm"))
		Mock.Advance(1, 0.2)
		local out = Mock.chat.SentWithPrefix("AzGF")
		eq(#out, 1)
		eq(out[1].chatType, "WHISPER"); eq(out[1].target, "Elarin")   -- the client names a same-realm sender without it
		local msg = A().Codec:Decode(out[1].message)
		eq(msg.t, "APPACK"); eq(msg.id, "0a1b2c3d"); eq(msg.state, "received")
	end)

	it("a repeated APPLY is answered with the state the officer has", function()
		asOfficer()
		capture()
		whisper(freshApply(), "Elarin")
		local rec = Inbox():Get(KEY, "0a1b2c3d")
		truthy(Apps().Transition(rec, "declined", GetServerTime(), "Testchar"))
		Mock.Advance(10, 5)
		whisper(freshApply(), "Elarin")
		eq(answers()[2][3], "declined")
		eq(Inbox():Count(KEY), 1)
		-- the same id sent by another character is never answered
		falsy(whisper(freshApply({ who = "Mallory" }), "Mallory"))
		eq(#answers(), 2)
	end)

	it("a newer application of the same character closes the older open one (APP-02)", function()
		asOfficer()
		capture()
		whisper(freshApply(), "Elarin")
		Mock.Advance(60, 10)
		whisper(freshApply({ id = "0a1b2c3e", at = GetServerTime() }), "Elarin")
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "withdrawn")
		eq(Inbox():Get(KEY, "0a1b2c3e").state, "received")
		eq(Inbox():Count(KEY, true), 1)
	end)

	it("APPPING: the known state to its applicant, silence otherwise", function()
		asOfficer()
		capture()
		whisper(freshApply(), "Elarin")
		Mock.Advance(10, 5)
		truthy(whisper({ t = "APPPING", v = 1, id = "0a1b2c3d" }, "Elarin-TestRealm"))
		eq(#answers(), 2)
		falsy(whisper({ t = "APPPING", v = 1, id = "0a1b2c3d" }, "Mallory-TestRealm"), "not its applicant")
		falsy(whisper({ t = "APPPING", v = 1, id = "99999999" }, "Elarin-TestRealm"), "unknown")
		falsy(whisper({ t = "APPPING", v = 1, id = "XX" }, "Elarin-TestRealm"))
		eq(#answers(), 2)
	end)

	it("APPWD after receipt withdraws the record; before receipt it leaves a tombstone", function()
		asOfficer()
		capture()
		whisper(freshApply(), "Elarin")
		truthy(whisper({ t = "APPWD", v = 1, id = "0a1b2c3d" }, "Elarin"))
		local rec = Inbox():Get(KEY, "0a1b2c3d")
		eq(rec.state, "withdrawn"); eq(rec.stateRev, 3)
		eq(answers()[2][3], "withdrawn")
		falsy(whisper({ t = "APPWD", v = 1, id = "0a1b2c3d" }, "Mallory"), "only its applicant")
		-- never received: a tombstone, answered withdrawn
		truthy(whisper({ t = "APPWD", v = 1, id = "77777777" }, "Bran-TestRealm"))
		local tomb = Inbox():Get(KEY, "77777777")
		eq(tomb.state, "withdrawn"); truthy(tomb.tomb); eq(tomb.stateRev, 3)
		eq(answers()[3][3], "withdrawn")
		-- a late copy of that application stays withdrawn
		Mock.Advance(10, 5)
		whisper(freshApply({ id = "77777777", who = "Bran-TestRealm" }), "Bran-TestRealm")
		eq(Inbox():Get(KEY, "77777777").state, "withdrawn")
		eq(answers()[4][3], "withdrawn")
	end)

	it("answers are limited per sender: one per answer in 5 s, six a minute", function()
		asOfficer()
		capture()
		whisper(freshApply(), "Elarin")
		for _ = 1, 5 do whisper({ t = "APPPING", v = 1, id = "0a1b2c3d" }, "Elarin") end
		eq(#answers(), 1, "the same answer within 5 s")
		for i = 1, 10 do
			Mock.Advance(5, 5)
			whisper({ t = "APPPING", v = 1, id = "0a1b2c3d" }, "Elarin")
		end
		eq(#answers(), 6, "six a minute")
		truthy(D().state.stats.repliesLimited >= 8)
	end)

	it("the store keeps at most the inbox limit: the oldest closed record goes, a full open inbox refuses", function()
		asOfficer()
		capture()
		A().Config.LIMITS.APPLICATIONS_PER_INBOX = 3
		local t = GetServerTime()
		whisper(freshApply({ id = "00000001", who = "Aa", at = t - 50 }), "Aa")
		whisper({ t = "APPWD", v = 1, id = "00000001" }, "Aa")
		whisper(freshApply({ id = "00000002", who = "Bb", at = t - 40 }), "Bb")
		whisper(freshApply({ id = "00000003", who = "Cc", at = t - 30 }), "Cc")
		whisper(freshApply({ id = "00000004", who = "Dd", at = t - 20 }), "Dd")
		isNil(Inbox():Get(KEY, "00000001"), "the closed one made room")
		eq(Inbox():Count(KEY), 3)
		falsy(whisper(freshApply({ id = "00000005", who = "Ee", at = t - 10 }), "Ee"))
		isNil(Inbox():Get(KEY, "00000005"))
		A().Config.LIMITS.APPLICATIONS_PER_INBOX = 200
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 3: the simulator
---------------------------------------------------------------------------------------------------------------------
local LISTING = { sub = "Friendly raiders", lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380,
	rec = 1, apps = true, want = { [0] = 8 }, newb = true, minL = 10, desc = "We raid on weekends.", disc = "aurora1",
	cont = { "Simaa" } }

-- Client 1 = Guild Master, client 2 = the applicant (no guild), client 3 = an officer; the roster of the guild names the
-- Guild Master (the GLIST check, INT-02). Steps of 1 s: hours of simulated time stay fast.
local function guildSim(seed)
	local sim = Sim.new{ clients = 3, seed = seed or 3, latency = { 0.1, 0.4 }, step = 1, sync = false,
		setup = function(M, i)
			if i == 2 then return end
			local members = {}
			for _, j in ipairs({ 1, 3 }) do
				if j ~= i then members[#members + 1] = { name = Sim.nameOf(j), rank = j == 1 and 0 or 1 } end
			end
			M.guild.Set{ name = GUILD, realm = "Test Realm", myRank = i == 1 and 0 or 1, members = members }
		end }
	for i = 1, 3 do sim:client(i):addon().Role:Refresh() end
	return sim
end

-- The periodic ANN runs by itself in the game; the simulator without the catalog sync switches it off at every boot.
local function announcing(c)
	local ol = c:addon().OwnListing
	ol.AUTO = true
	ol:StartAnnouncing()
end

local function said(c, text)
	for _, line in ipairs(c:output()) do if line:find(text, 1, true) then return true end end
	return false
end

describe("simulator", function()
	it("an application reaches an officer who comes online hours later", function()
		local sim = guildSim(5)
		local gm, applicant, officer = sim:client(1), sim:client(2), sim:client(3)
		eq(gm:addon().OwnListing:Publish(LISTING), true)
		sim:advance(40)   -- the GLIST reaches the officer (roster check), the listing reaches the applicant
		notNil(officer:addon().OwnListing:Get(), "the officer keeps the guild copy (saved per character)")
		local ap = applicant:addon()
		notNil(ap.Catalog:Get(KEY), "the listing reached the applicant")
		eq(ap.Sync:Contacts(KEY)[1] ~= nil, true, "c = 1 heard")
		-- both log off before the applicant applies
		gm:setOnline(false)
		officer:setOnline(false)
		sim:advance(60)
		local ok, rec = ap.Applications:Apply(KEY, 4)
		truthy(ok)
		sim:advance(40)
		eq(rec.state, "sent", "the contacts heard a minute ago are gone: no APPACK")
		truthy(ap.Delivery.state.stats.timeouts >= 1)
		-- three hours without any contact: the contacts expire, nothing is retried
		sim:resetStats()
		sim:advance(3 * 3600)
		eq(rec.state, "sent")
		eq(sim:stats().perClient[2].byDist.WHISPER.msgs, 0, "no contact heard: no whisper")
		eq(#ap.Sync:Contacts(KEY, ap.Delivery.CONTACT_TTL), 0)
		-- the officer logs in; its periodic ANN (c = 1) tells the applicant, which sends the APPLY
		officer:setOnline(true)
		officer:reload()
		announcing(officer)
		local start = sim.time
		truthy(sim:advanceUntil(function() return rec.state == "received" end, 45 * 60),
			"delivered within one periodic ANN turn of the officer")
		T.log(("the officer came online after 3 h; the application was received %d s later"):format(sim.time - start))
		local stored = officer:addon().Inbox:Get(KEY, rec.id)
		notNil(stored)
		eq(stored.state, "received"); eq(stored.who, applicant:fullName()); eq(stored.roles, 4); eq(stored.lvl, rec.lvl)
		truthy(said(applicant, "Your application to Aurora was received by an officer."))
		local st = sim:stats()
		eq(st.perClient[2].byDist.WHISPER.msgs, 1, "one APPLY")
		eq(st.perClient[3].byDist.WHISPER.msgs, 1, "one APPACK")
		isNil(gm:addon().Inbox:Get(KEY, rec.id), "the Guild Master is still offline")
	end)

	it("a decision taken while the applicant was away is learned at the next contact; a withdrawal reaches the officer", function()
		local sim = guildSim(9)
		local gm, applicant, officer = sim:client(1), sim:client(2), sim:client(3)
		eq(gm:addon().OwnListing:Publish(LISTING), true)
		for _, c in ipairs({ gm, officer }) do
			c:addon().OwnListing.ANN_PERIOD = { 300, 300 }
			announcing(c)
		end
		sim:advance(60)
		local ap = applicant:addon()
		local ok, rec = ap.Applications:Apply(KEY)
		truthy(ok)
		sim:advance(5)
		eq(rec.state, "received", "a contact online: received in seconds")
		local stored = gm:addon().Inbox:Get(KEY, rec.id)
		notNil(stored)
		-- the applicant logs off; the Guild Master declines meanwhile
		applicant:setOnline(false)
		truthy(gm:addon().Applications.Transition(stored, "declined", gm.E.GetServerTime(), gm.name))
		sim:advance(2 * 3600)
		applicant:setOnline(true)
		applicant:reload()
		local rec2 = applicant:addon().Applications:Get(rec.id)
		eq(rec2.state, "received")
		truthy(sim:advanceUntil(function() return rec2.state == "declined" end, 15 * 60), "APPPING at the next contact")
		truthy(said(applicant, "Your application to Aurora was declined."))
		-- a new application to the same guild waits for the cooldown; withdraw-after-receipt on another one
		local ap2 = applicant:addon()
		eq(select(2, ap2.Applications:Apply(KEY)), "cooldown")
		ap2.Applications.COOLDOWN = 0
		local ok3, rec3 = ap2.Applications:Apply(KEY)
		truthy(ok3)
		truthy(sim:advanceUntil(function() return rec3.state == "received" end, 15 * 60))
		truthy(ap2.Applications:Withdraw())
		truthy(sim:advanceUntil(function() return not rec3.wd end, 15 * 60))
		-- the contact that had it, or the one that got the APPWD first (a tombstone the officers' sync spreads, M4.3)
		local states = {}
		for _, c in ipairs({ gm, officer }) do
			local r = c:addon().Inbox:Get(KEY, rec3.id)
			if r then states[#states + 1] = r.state end
		end
		truthy(table.concat(states, ","):find("withdrawn", 1, true), table.concat(states, ","))
		eq(#applicant.Mock.errors + #gm.Mock.errors + #officer.Mock.errors, 0)
	end)
end)
