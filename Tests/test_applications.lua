-- M4.1: the application model (Data/Applications.lua) and the texts of the applicant's screens (UI/ApplyModel.lua).
-- Part 1 is pure Lua: the state diagram of SPEC-07 §2 checked pair by pair against a table written out by hand, the rules
-- APP-01…APP-06 (one open application per character, 14-day expiry, 7-day cooldown after a decline), the roles a class may
-- tick (SPEC-03 §5), the officers' conflict rule, the repair of saved data. Part 2 runs the module on the mock client: what
-- is read from the client, what is saved (per character, not per account), the Bus hooks for the network of M4.2 and the
-- expiry while the game runs. The mock player is "Testchar" on "Test Realm", a Horde Orc Warrior of level 60, no guild.

local DAY = 86400
local function A() return AzerothGuildFinder end
local function Apps() return A().Applications end
local function key(name) return "TestRealm|Horde|" .. name end
local NOW = 1767225600
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })

local function rec(extra)
	local r = { id = "0a1b2c3d", k = key("Aurora"), who = "Testchar-TestRealm", cls = 1, race = 2, lvl = 60, at = NOW,
		state = "sent", stateRev = 1, upd = NOW }
	for k, v in pairs(extra or {}) do if v == "nil" then r[k] = nil else r[k] = v end end
	return r
end

---------------------------------------------------------------------------------------------------------------------
-- Part 1: pure rules
---------------------------------------------------------------------------------------------------------------------
-- SPEC-07 §2, written out: every allowed step. Everything else is refused.
local ALLOWED = {
	["sent>received"] = true, ["sent>withdrawn"] = true, ["sent>expired"] = true,
	["received>accepted"] = true, ["received>declined"] = true, ["received>withdrawn"] = true, ["received>expired"] = true,
}
local STATES = { "sent", "received", "accepted", "declined", "withdrawn", "expired" }

describe("the state diagram (SPEC-07 §2)", function()
	it("has exactly the six states, two of them open", function()
		deepEq(Apps().STATES, STATES)
		for _, s in ipairs(STATES) do
			eq(Apps().IsOpen({ state = s }), s == "sent" or s == "received", s)
			eq(Apps().IsFinal(s), not (s == "sent" or s == "received"), s)
		end
		falsy(Apps().IsState("pending"))
		falsy(Apps().IsState(nil))
	end)

	it("allows exactly the steps of the diagram, every pair checked", function()
		local n = 0
		for _, from in ipairs(STATES) do
			for _, to in ipairs(STATES) do
				local allowed = ALLOWED[from .. ">" .. to] == true
				eq(Apps().CanMove(from, to), allowed, from .. " > " .. to)
				local r = rec({ state = from, stateRev = 3 })
				local ok = Apps().Transition(r, to, NOW + 10)
				eq(ok, allowed, "Transition " .. from .. " > " .. to)
				if allowed then
					n = n + 1
					eq(r.state, to); eq(r.stateRev, 4); eq(r.upd, NOW + 10)
				else
					eq(r.state, from); eq(r.stateRev, 3); eq(r.upd, NOW)
				end
			end
		end
		eq(n, 7)
	end)

	it("says why a step is refused", function()
		local Ap = Apps()
		eq(select(2, Ap.Transition(rec(), "pending", NOW)), "state")
		eq(select(2, Ap.Transition(rec(), "sent", NOW)), "same")
		eq(select(2, Ap.Transition(rec({ state = "declined" }), "accepted", NOW)), "final")
		eq(select(2, Ap.Transition(rec(), "accepted", NOW)), "invalid")
	end)

	it("every change raises stateRev by one and records who decided", function()
		local r = rec()
		truthy(Apps().Transition(r, "received", NOW + 1))
		truthy(Apps().Transition(r, "declined", NOW + 2, "Lyryn"))
		eq(r.stateRev, 3)
		eq(r.by, "Lyryn")
		eq(r.upd, NOW + 2)
	end)
end)

describe("APP-05: expiry after 14 days", function()
	it("an open application expires exactly 14 days after it was sent", function()
		local Ap = Apps()
		eq(Ap.EXPIRY, 14 * DAY)
		eq(Ap.ExpiresAt(rec()), NOW + 14 * DAY)
		falsy(Ap.IsExpired(rec(), NOW + 14 * DAY - 1))
		truthy(Ap.IsExpired(rec(), NOW + 14 * DAY))
		truthy(Ap.IsExpired(rec({ state = "received" }), NOW + 20 * DAY))
	end)

	it("a closed application never expires", function()
		for _, s in ipairs({ "accepted", "declined", "withdrawn", "expired" }) do
			falsy(Apps().IsExpired(rec({ state = s }), NOW + 100 * DAY), s)
		end
	end)
end)

describe("APP-06: 7 days after a decline", function()
	it("the same guild is blocked until 7 days after the decline, then free", function()
		local Ap = Apps()
		local recs = { rec({ state = "declined", stateRev = 3, upd = NOW + DAY }) }
		eq(Ap.CooldownUntil(recs, key("Aurora"), NOW + 2 * DAY), NOW + 8 * DAY)
		eq(Ap.CooldownUntil(recs, key("Aurora"), NOW + 8 * DAY - 1), NOW + 8 * DAY)
		isNil(Ap.CooldownUntil(recs, key("Aurora"), NOW + 8 * DAY))
	end)

	it("only a decline counts, and only for that guild", function()
		local Ap = Apps()
		for _, s in ipairs({ "withdrawn", "expired", "accepted" }) do
			isNil(Ap.CooldownUntil({ rec({ state = s }) }, key("Aurora"), NOW + 1), s)
		end
		isNil(Ap.CooldownUntil({ rec({ state = "declined" }) }, key("Other"), NOW + 1))
	end)

	it("the latest decline decides", function()
		local recs = { rec({ id = "00000001", state = "declined", upd = NOW }), rec({ id = "00000002", state = "declined", upd = NOW + 3 * DAY }) }
		eq(Apps().CooldownUntil(recs, key("Aurora"), NOW + 4 * DAY), NOW + 10 * DAY)
	end)
end)

-- SPEC-03 §5, written out: the roles each class may tick.
local CLASS_ROLES = {
	[1] = { 1, 4 },          -- Warrior: Tank, Melee
	[2] = { 1, 2, 4 },       -- Paladin
	[3] = { 8 },             -- Hunter
	[4] = { 4 },             -- Rogue
	[5] = { 2, 8 },          -- Priest
	[7] = { 2, 4, 8 },       -- Shaman
	[8] = { 8 },             -- Mage
	[9] = { 8 },             -- Warlock
	[11] = { 1, 2, 4, 8 },   -- Druid
}

describe("APP-04: the optional roles", function()
	it("each class is offered only the roles it can play", function()
		for classID, roles in pairs(CLASS_ROLES) do deepEq(Apps().RolesFor(classID), roles, "class " .. classID) end
	end)

	it("a class the table does not know is offered every role", function()
		deepEq(Apps().RolesFor(99), { 1, 2, 4, 8 })
	end)

	it("roles a class cannot play are dropped; none ticked is nil", function()
		local Ap = Apps()
		eq(Ap.CleanRoles(1, 15), 5)
		eq(Ap.CleanRoles(1, 1), 1)
		isNil(Ap.CleanRoles(8, 1 + 2 + 4))
		eq(Ap.CleanRoles(8, 8), 8)
		eq(Ap.CleanRoles(11, 15), 15)
		eq(Ap.CleanRoles(5, 2 + 4), 2)
		isNil(Ap.CleanRoles(1, 0))
		isNil(Ap.CleanRoles(1, nil))
		isNil(Ap.CleanRoles(1, "tank"))
		eq(Ap.CleanRoles(1, 17), 1, "out of range wraps to the four bits")
	end)

	it("every class, every mask: the result is always a subset of the class roles", function()
		local E = A().Enums
		for classID in pairs(CLASS_ROLES) do
			for mask = 0, 15 do
				local r = Apps().CleanRoles(classID, mask)
				if r then eq(E.MaskAnd(r, E.ValidRoles(classID)), r) ; truthy(r >= 1 and r <= 15) end
			end
		end
	end)
end)

describe("a new record", function()
	it("carries what the client says and nothing typed by the player", function()
		local r = Apps().NewRecord("deadbeef", key("Aurora"), { name = "Elarin", realm = "TestRealm", classID = 8, raceID = 1,
			level = 32, ilvl = 87.6 }, 1 + 8, NOW)
		deepEq(r, { id = "deadbeef", k = key("Aurora"), who = "Elarin-TestRealm", cls = 8, race = 1, lvl = 32, ilvl = 87,
			roles = 8, at = NOW, state = "sent", stateRev = 1, upd = NOW })
	end)

	it("an item level of 0 or unknown is left out, and no roles means no field", function()
		local r = Apps().NewRecord("deadbeef", key("Aurora"), { name = "Elarin", realm = "TestRealm", classID = 8, level = 32, ilvl = 0 }, nil, NOW)
		isNil(r.ilvl)
		isNil(r.roles)
	end)
end)

describe("APP-01…APP-03: Decide", function()
	local function ctx(extra)
		local c = { k = key("Aurora"), sum = { k = key("Aurora"), apps = true, minL = 20 }, role = "none",
			player = { level = 60, ilvl = 100 }, recs = {}, now = NOW }
		for k, v in pairs(extra or {}) do c[k] = v end
		return c
	end
	local function reason(c) local ok, why = Apps().Decide(c) return ok, why end

	it("allows a player without a guild, without an open application, meeting the requirements", function()
		local ok, why = reason(ctx())
		truthy(ok); eq(why, "ok")
	end)

	it("no listing, closed applications, a guild (APP-01, APP-03)", function()
		eq(select(2, reason(ctx({ sum = false }))), "nolisting")
		eq(select(2, reason(ctx({ sum = { apps = false } }))), "closed")
		eq(select(2, reason(ctx({ sum = { minL = 1 } }))), "closed", "apps missing is not open")
		for _, role in ipairs({ "member", "officer", "gm" }) do eq(select(2, reason(ctx({ role = role }))), "inguild", role) end
	end)

	it("APP-02: one open application per character, here or elsewhere", function()
		local here = rec()
		local ok, why, info = Apps().Decide(ctx({ recs = { here } }))
		falsy(ok); eq(why, "applied"); eq(info, here)
		local other = rec({ k = key("Other") })
		ok, why, info = Apps().Decide(ctx({ recs = { other } }))
		falsy(ok); eq(why, "elsewhere"); eq(info, other)
		eq(select(2, reason(ctx({ recs = { rec({ state = "received" }) } }))), "applied")
	end)

	it("an open application past its 14 days no longer blocks, even before it is written down as expired", function()
		local old = rec({ k = key("Other"), at = NOW - 14 * DAY })
		eq(select(2, reason(ctx({ recs = { old } }))), "ok")
		eq(old.state, "sent", "Decide changes nothing")
		eq(select(2, reason(ctx({ recs = { rec({ k = key("Other"), at = NOW - 14 * DAY + 1 }) } }))), "elsewhere")
	end)

	it("a closed application does not block (withdrawn, expired, accepted elsewhere)", function()
		for _, s in ipairs({ "withdrawn", "expired", "accepted" }) do
			eq(select(2, reason(ctx({ recs = { rec({ state = s }) } }))), "ok", s)
		end
	end)

	it("APP-06: a recent decline of this guild", function()
		local ok, why, info = Apps().Decide(ctx({ recs = { rec({ state = "declined", upd = NOW - DAY }) } }))
		eq(why, "cooldown"); eq(info.untilAt, NOW + 6 * DAY)
		eq(select(2, reason(ctx({ recs = { rec({ state = "declined", upd = NOW - 7 * DAY }) } }))), "ok")
	end)

	it("APP-03: requirements known to fail; an unknown item level does not block", function()
		local ok, why, info = Apps().Decide(ctx({ sum = { apps = true, minL = 70 } }))
		eq(why, "requirements"); eq(info.levelOk, false)
		eq(select(2, reason(ctx({ sum = { apps = true, minI = 120 } }))), "requirements")
		eq(select(2, reason(ctx({ sum = { apps = true, minI = 120 }, player = { level = 60 } }))), "ok")
	end)

	it("listen-only and read-only saved data", function()
		eq(select(2, reason(ctx({ listenOnly = true }))), "listenonly")
		eq(select(2, reason(ctx({ readOnly = true }))), "readonly")
	end)

	it("checks in a fixed order: the first reason that holds wins", function()
		local all = ctx({ role = "member", recs = { rec({ k = key("Other") }) }, sum = { apps = true, minL = 70 }, listenOnly = true })
		eq(select(2, reason(all)), "inguild")
		all.role = "none"
		eq(select(2, reason(all)), "elsewhere")
		all.recs = { rec({ state = "declined", upd = NOW }) }
		eq(select(2, reason(all)), "cooldown")
		all.recs = {}
		eq(select(2, reason(all)), "requirements")
		all.sum = { apps = true }
		eq(select(2, reason(all)), "listenonly")
		all.sum.apps = false
		eq(select(2, reason(all)), "closed")
	end)
end)

describe("the officers' conflict rule (SPEC-07 §4, for M4.3)", function()
	it("the higher stateRev wins", function()
		local a, b = rec({ state = "received", stateRev = 2 }), rec({ state = "declined", stateRev = 3 })
		eq(Apps().Newer(a, b), b)
		eq(Apps().Newer(b, a), b)
	end)

	it("on a tie the final state wins, accepted > declined > withdrawn > expired", function()
		local order = { "accepted", "declined", "withdrawn", "expired" }
		for i = 1, #order do
			for j = i + 1, #order do
				local hi, lo = rec({ state = order[i], stateRev = 3 }), rec({ state = order[j], stateRev = 3 })
				eq(Apps().Newer(lo, hi), hi, order[i] .. " over " .. order[j])
				eq(Apps().Newer(hi, lo), hi)
			end
		end
		local open, final = rec({ state = "received", stateRev = 3 }), rec({ state = "expired", stateRev = 3 })
		eq(Apps().Newer(open, final), final)
	end)

	it("nil on one side gives the other", function()
		local r = rec()
		eq(Apps().Newer(nil, r), r)
		eq(Apps().Newer(r, nil), r)
	end)
end)

describe("an officer's answer (APPACK, for M4.2)", function()
	it("received, then a decision", function()
		local r = rec()
		truthy(Apps().ApplyAck(r, "received", NOW + 1))
		eq(r.state, "received"); eq(r.stateRev, 2)
		truthy(Apps().ApplyAck(r, "accepted", NOW + 2))
		eq(r.state, "accepted"); eq(r.stateRev, 3)
	end)

	it("a decision reaching a record still 'sent' passes through received", function()
		local r = rec()
		truthy(Apps().ApplyAck(r, "declined", NOW + 1))
		eq(r.state, "declined"); eq(r.stateRev, 3)
	end)

	it("the same state, a closed record, 'sent' or nonsense change nothing", function()
		local r = rec({ state = "received", stateRev = 2 })
		eq(select(2, Apps().ApplyAck(r, "received", NOW)), "same")
		eq(select(2, Apps().ApplyAck(r, "sent", NOW)), "invalid")
		eq(select(2, Apps().ApplyAck(r, "maybe", NOW)), "state")
		local d = rec({ state = "declined", stateRev = 3 })
		eq(select(2, Apps().ApplyAck(d, "accepted", NOW)), "final")
		eq(d.state, "declined")
	end)

	it("a confirmed withdrawal clears 'Withdrawing...'; another answer to a withdrawn record is ignored", function()
		local r = rec({ state = "withdrawn", stateRev = 2, wd = true })
		eq(select(2, Apps().ApplyAck(r, "received", NOW)), "final")
		truthy(r.wd)
		truthy(Apps().ApplyAck(r, "withdrawn", NOW))
		isNil(r.wd)
		eq(r.stateRev, 2)
	end)
end)

describe("the outbox (what M4.2 sends)", function()
	it("APPLY for sent, APPPING for received, APPWD for a withdrawal not yet confirmed, nothing for the rest", function()
		local recs = {
			rec({ id = "00000001", state = "declined" }), rec({ id = "00000002", state = "withdrawn", wd = true }),
			rec({ id = "00000003", state = "withdrawn" }), rec({ id = "00000004", state = "expired" }),
			rec({ id = "00000005", state = "sent" }), rec({ id = "00000006", state = "received" }),
		}
		deepEq(Apps().OutboxOf(recs), {
			{ kind = "APPWD", id = "00000002", k = key("Aurora") },
			{ kind = "APPLY", id = "00000005", k = key("Aurora") },
			{ kind = "APPPING", id = "00000006", k = key("Aurora") },
		})
	end)
end)

describe("history and repair of saved data", function()
	it("closed records leave 30 days after their last change; the open one stays", function()
		local recs = { rec({ id = "00000001", state = "declined", upd = NOW }), rec({ id = "00000002", state = "expired", upd = NOW + 5 * DAY }),
			rec({ id = "00000003", state = "sent", at = NOW + 6 * DAY, upd = NOW + 6 * DAY }) }
		eq(Apps().Prune(recs, NOW + 30 * DAY - 1), 0)
		eq(Apps().Prune(recs, NOW + 30 * DAY), 1)
		eq(#recs, 2)
		eq(Apps().Prune(recs, NOW + 100 * DAY), 1)
		eq(recs[1].id, "00000003")
	end)

	it("at most MAX_RECORDS, the oldest closed ones go first", function()
		local recs = {}
		for i = 1, Apps().MAX_RECORDS + 4 do recs[i] = rec({ id = ("%08x"):format(i), state = "withdrawn", at = NOW + i }) end
		recs[1].state = "sent"
		Apps().Prune(recs, NOW + 100)
		eq(#recs, Apps().MAX_RECORDS)
		eq(recs[1].id, "00000001", "the open one stays")
		eq(recs[2].id, "00000006")
	end)

	it("Sanitize drops unusable records and wrong optional fields", function()
		local S = Apps().Sanitize
		isNil(S(nil)); isNil(S("x"))
		isNil(S(rec({ id = "xyz" })))
		isNil(S(rec({ k = "nonsense" })))
		isNil(S(rec({ state = "pending" })))
		isNil(S(rec({ stateRev = 0 })))
		isNil(S(rec({ at = "today" })))
		local r = S(rec({ cls = 1, roles = 2 + 4, ilvl = -3, lvl = 1.5, who = 7, wd = true, unseen = true, extra = "x" }))
		eq(r.roles, 4, "Healer is not a Warrior role")
		isNil(r.ilvl); isNil(r.lvl); isNil(r.who); isNil(r.wd, "wd only on a withdrawn record"); isNil(r.extra)
		truthy(r.unseen)
	end)

	it("SanitizeList: sorted, duplicates dropped, a second open record closed", function()
		local list = { rec({ id = "00000002", at = NOW + 10, upd = NOW + 10 }), "junk", rec({ id = "00000001", at = NOW }),
			rec({ id = "00000002", at = NOW + 20 }) }
		local out, fixes = Apps().SanitizeList(list, NOW + 30)
		eq(#out, 2)
		eq(out[1].id, "00000001"); eq(out[1].state, "withdrawn")
		eq(out[2].id, "00000002"); eq(out[2].state, "sent")
		eq(fixes, 3)
		local empty, f2 = Apps().SanitizeList("broken", NOW)
		eq(#empty, 0); eq(f2, 1)
	end)
end)

describe("the texts of the Apply button (SPEC-05 §4)", function()
	local function button(reason, info, place, sum)
		return A().ApplyModel.Button(reason, info, { name = "Aurora", place = place or "card", sum = sum or { apps = true } }, L)
	end

	it("every state of SPEC-05 §4 has its label, colour and reason", function()
		local b = button("ok")
		truthy(b.shown); truthy(b.enabled); eq(b.kind, "primary"); eq(b.label, "Apply")
		eq(button("ok", nil, "page").label, "Apply to Aurora")
		b = button("applied", rec())
		eq(b.label, "Applied · Waiting for an officer"); eq(b.link, "MyApplication"); truthy(b.enabled); eq(b.kind, "tonal")
		eq(button("applied", rec({ state = "received" })).label, "Applied · Received")
		b = button("elsewhere", rec({ k = key("Iron Wolves") }))
		eq(b.label, "You already applied to Iron Wolves"); falsy(b.enabled)
		eq(b.tooltip.lines[1], "Withdraw it first: one open application at a time.")
		b = button("requirements", { levelOk = false, ilvlOk = true }, "card", { apps = true, minL = 40 })
		eq(b.label, "Requirements not met"); falsy(b.enabled)
		eq(b.tooltip.lines[1], "Requirements not met: level 40")
		eq(button("requirements", { levelOk = false, ilvlOk = false }, "card", { minL = 40, minI = 120 }).note,
			"Requirements not met: level 40, item level 120")
		b = button("closed")
		falsy(b.shown); eq(b.note, "Applications via addon are closed. Use the contacts below.")
		falsy(button("nolisting").shown)
		b = button("listenonly")
		eq(b.label, "Your character can't send addon messages yet"); falsy(b.enabled)
		eq(button("inguild").label, "You are already in a guild")
		eq(button("readonly").label, "Saved data is read-only")
	end)

	it("a cooldown names the day it ends: 'You can apply again on 15 Nov'", function()
		local at = os.time({ year = 2026, month = 11, day = 15, hour = 12 })
		local b = button("cooldown", { untilAt = at })
		eq(b.label, "You can apply again on 15 Nov"); falsy(b.enabled)
		eq(A().ApplyModel.ShortDate(nil, L), nil)
	end)
end)

describe("the confirmation and My Application texts", function()
	it("asks 'Apply to <Guild> with Name (Class level)?' and offers the class roles", function()
		local v = A().ApplyModel.Confirm({ name = "Aurora", player = { name = "Elarin", classID = 8, level = 32 } }, L)
		eq(v.question, "Apply to Aurora with Elarin (Mage 32)?")
		eq(#v.roles, 1); eq(v.roles[1].key, "ranged"); eq(v.roles[1].label, "Ranged DPS")
		v = A().ApplyModel.Confirm({ name = "Aurora", player = { name = "Bran", classID = 11, level = 60 } }, L)
		eq(#v.roles, 4)
		eq(A().ApplyModel.RolesMask({ 1, 8 }), 9)
		isNil(A().ApplyModel.RolesMask({}))
		eq(A().ApplyModel.RolesMask({ 1, 1, 3 }), 1, "repeats and nonsense are ignored")
	end)

	it("My Application explains every state", function()
		local M = A().ApplyModel
		local expect = {
			sent = "Waiting for an officer to come online", received = "Received by the guild",
			accepted = "Accepted: check your guild invite", declined = "Declined", withdrawn = "Withdrawn", expired = "Expired",
		}
		for state, title in pairs(expect) do
			local v = M.MyApplication(rec({ state = state }), { now = NOW + 3600, listed = true }, L)
			eq(v.title, title, state)
			eq(v.withdraw, state == "sent" or state == "received", state)
			truthy(v.body:find("Aurora", 1, true), state)
			eq(v.appliedText, "Applied 1 h ago")
		end
		eq(M.MyApplication(rec({ state = "withdrawn", wd = true }), { now = NOW }, L).title, "Withdrawing...")
		local v = M.MyApplication(nil, { now = NOW }, L)
		truthy(v.empty); eq(v.title, "You haven't applied to any guild")
	end)

	it("the road, the expiry and the cooldown line", function()
		local M = A().ApplyModel
		local v = M.MyApplication(rec({ state = "received", roles = 5 }), { now = NOW + 2 * DAY, listed = false }, L)
		eq(v.steps[1].on, true); eq(v.steps[2].on, true); eq(v.steps[3].on, false)
		eq(v.steps[3].text, "ACCEPTED / DECLINED")
		eq(v.expiresText, "Expires in 12 days without a decision.")
		eq(#v.roles, 2); eq(v.roles[1].key, "tank"); eq(v.roles[2].key, "melee")
		falsy(v.viewGuild, "no listing: nothing to view")
		v = M.MyApplication(rec({ state = "declined", upd = NOW }), { now = NOW + DAY, listed = true }, L)
		eq(v.steps[3].text, "DECLINED"); truthy(v.steps[3].bad)
		truthy(v.again:find("You can apply again on", 1, true))
		isNil(v.expiresText)
		eq(M.MyApplication(rec(), { now = NOW + 14 * DAY - 100 }, L).expiresText, "Expires within a day without a decision.")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 2: the module on the mock client
---------------------------------------------------------------------------------------------------------------------
local function summary(name, extra)
	local t = { k = key(name), rev = 3, upd = GetServerTime() - 3600, first = 1760000000, own = "a1b2c3d4", sub = "Friendly",
		lang = 1, lang1 = 1, tags = { 1 }, pace = 1, days = 31, t0 = 1140, t1 = 1350, rec = 1, apps = true, want = { [0] = 15 },
		newb = true, minL = 20 }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end
local function put(name, extra) assert(A().Catalog:PutSummary(summary(name, extra))) end

local function listen(event)
	local seen = {}
	A().Bus:On(event, function(...) seen[#seen + 1] = { ... } end)
	return seen
end

describe("applying on the client", function()
	it("saves a sent application with the character read from the client, and announces it", function()
		put("Aurora")
		local changed, outbox = listen("APPLICATION_CHANGED"), listen("APPLICATION_OUTBOX")
		local ok, r = Apps():Apply(key("Aurora"), 1 + 2 + 4)
		truthy(ok)
		eq(r.state, "sent"); eq(r.stateRev, 1)
		eq(r.who, "Testchar-TestRealm"); eq(r.cls, 1); eq(r.race, 2); eq(r.lvl, 60)
		eq(r.roles, 5, "a Warrior cannot heal")
		eq(r.at, GetServerTime())
		truthy(r.id:find("^%x%x%x%x%x%x%x%x$"))
		deepEq(changed, { { r.id, "sent" } })
		deepEq(outbox, { { "APPLY", r.id } })
		deepEq(Apps():Outbox(), { { kind = "APPLY", id = r.id, k = key("Aurora") } })
		eq(Apps():Current(), r)
		eq(#Mock.chat.sent, 0, "nothing goes on the network in M4.1")
	end)

	it("APP-02: a second application is refused, here and elsewhere", function()
		put("Aurora"); put("Iron Wolves")
		truthy(Apps():Apply(key("Aurora")))
		local ok, why = Apps():Apply(key("Aurora"))
		falsy(ok); eq(why, "applied")
		ok, why = Apps():Apply(key("Iron Wolves"))
		falsy(ok); eq(why, "elsewhere")
		eq(#Apps():Records(), 1)
	end)

	it("withdrawing frees the character at once and leaves 'Withdrawing...' to deliver", function()
		put("Aurora"); put("Iron Wolves")
		local _, r = Apps():Apply(key("Aurora"))
		local outbox = listen("APPLICATION_OUTBOX")
		truthy(Apps():Withdraw())
		eq(r.state, "withdrawn"); eq(r.stateRev, 2); truthy(r.wd)
		deepEq(outbox, { { "APPWD", r.id } })
		isNil(Apps():Current())
		truthy(Apps():Apply(key("Iron Wolves")))
		eq(select(2, Apps():Withdraw("ffffffff")), "none", "only the open one, by its id")
		falsy(Apps():Withdraw(r.id))
	end)

	it("refuses what the rules refuse: closed, unknown guild, a guild, listen-only", function()
		put("Closed", { apps = false })
		eq(select(2, Apps():Apply(key("Closed"))), "closed")
		eq(select(2, Apps():Apply(key("Nobody"))), "nolisting")
		put("Aurora")
		A().Transport.IsListenOnly = function() return true, "InvalidChannel" end
		eq(select(2, Apps():Apply(key("Aurora"))), "listenonly")
		A().Transport.IsListenOnly = function() return false end
		Mock.guild.Set{ name = "Iron Wolves", myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		A().Role:Refresh()
		eq(select(2, Apps():Apply(key("Aurora"))), "inguild")
		eq(#Apps():Records(), 0)
	end)

	it("is saved per character: kept after /reload, absent for another character, nothing in the account data", function()
		put("Aurora")
		local _, r = Apps():Apply(key("Aurora"), 4)
		Mock.Reload()
		local again = Apps():Current()
		truthy(again); eq(again.id, r.id); eq(again.roles, 4)
		eq(AzerothGuildFinderCharDB.application.recs[1].id, r.id)
		isNil(AzerothGuildFinderDB.application)
		-- another character of the same account: a fresh character table, the same account table
		_G.AzerothGuildFinderCharDB = nil
		A().Config:Load()
		isNil(Apps():Current())
		eq(#Apps():Records(), 0)
	end)

	it("damaged saved data is repaired on load", function()
		put("Aurora")
		truthy(Apps():Apply(key("Aurora")))
		AzerothGuildFinderCharDB.application.recs[2] = { id = "nonsense" }
		AzerothGuildFinderCharDB.application.junk = 5
		Mock.Reload()
		eq(#Apps():Records(), 1)
		isNil(AzerothGuildFinderCharDB.application.junk)
		eq(Apps().fixes, 1)
	end)
end)

describe("expiry while the game runs", function()
	it("an application expires after 14 days: the chat line, the dot, the Bus", function()
		put("Aurora")
		local _, r = Apps():Apply(key("Aurora"))
		local changed = listen("APPLICATION_CHANGED")
		Mock.ClearOutput()
		Mock.Advance(14 * DAY - 10, 590)
		eq(r.state, "sent")
		Mock.Advance(3700, 100)
		eq(r.state, "expired")
		eq(r.stateRev, 2)
		deepEq(changed, { { r.id, "expired", "sent" } })
		truthy(r.unseen)
		eq(Apps():Unseen(), 1)
		local found = false
		for _, line in ipairs(Mock.PlainOutput()) do
			if line:find("Your application to Aurora expired after 14 days without a decision.", 1, true) then found = true end
		end
		truthy(found, "chat line")
		truthy(Apps():MarkSeen())
		eq(Apps():Unseen(), 0)
		falsy(Apps():MarkSeen())
	end)

	it("an application past its 14 days is expired at login", function()
		put("Aurora")
		local _, r = Apps():Apply(key("Aurora"))
		Mock.Reload()
		Mock.SetServerTime(GetServerTime() + 15 * DAY)
		eq(Apps():Latest().state, "expired")
		isNil(Apps():Current())
		eq(Apps():Latest().id, r.id)
	end)
end)

describe("an officer's answer arriving (the hook of M4.2)", function()
	it("received then declined: the chat lines, the cooldown on that guild", function()
		put("Aurora")
		local _, r = Apps():Apply(key("Aurora"))
		Mock.ClearOutput()
		truthy(Apps():OnAck(r.id, "received"))
		truthy(Apps():OnAck(r.id, "declined"))
		eq(r.state, "declined"); eq(r.stateRev, 3)
		local out = table.concat(Mock.PlainOutput(), "\n")
		truthy(out:find("Your application to Aurora was received by an officer.", 1, true))
		truthy(out:find("Your application to Aurora was declined.", 1, true))
		local ok, why = Apps():Check(key("Aurora"))
		falsy(ok); eq(why, "cooldown")
		Mock.Advance(7 * DAY, 600)
		local ok2, why2 = Apps():Check(key("Aurora"))
		eq(why2, "ok")
	end)

	it("an unknown id or a step that is not allowed changes nothing", function()
		put("Aurora")
		local _, r = Apps():Apply(key("Aurora"))
		eq(select(2, Apps():OnAck("ffffffff", "received")), "unknown")
		eq(select(2, Apps():OnAck(r.id, "sent")), "same")
		truthy(Apps():Withdraw())
		eq(select(2, Apps():OnAck(r.id, "accepted")), "final")
		eq(r.state, "withdrawn")
		eq(r.stateRev, 2)
	end)

	it("/gf debug has an Applications line without names", function()
		put("Aurora")
		truthy(Apps():Apply(key("Aurora")))
		local text = table.concat(Apps():DebugLines(), "\n")
		truthy(text:find("open: sent", 1, true))
		falsy(text:find("Aurora", 1, true))
		falsy(text:find("Testchar", 1, true))
	end)
end)
