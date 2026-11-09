-- M2.6: the rules of the filters of Find a Guild (UI/FilterModel.lua) without frames: each filter of SPEC-05 §2, their
-- combinations, the count and the reset, the saved state (sanitized, per character) and play times across midnight and
-- across time zones. The mock player is a level 60 Warrior; the tests that need another one pass it in the context.

local function F() return AzerothGuildFinder.FilterModel end
local E = function() return AzerothGuildFinder.Enums end
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })

local MON, TUE, WED, THU, FRI, SAT, SUN = 1, 2, 4, 8, 16, 32, 64
local TANK, HEALER, MELEE, RANGED = 1, 2, 4, 8
local WARRIOR, MAGE, PRIEST, DRUID = 1, 8, 5, 11
local function hm(h, m) return h * 60 + (m or 0) end

-- A complete listing; `extra` overrides, and the string "nil" removes a field.
local function sum(name, extra)
	local t = { k = "TestRealm|Horde|" .. name, rev = 1, upd = 1766100000, first = 1766000000, own = "a1b2c3d4",
		sub = "Friendly", lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 31,
		t0 = hm(20), t1 = hm(23), rec = 1, apps = true, want = { [0] = RANGED }, newb = true, minL = 20, st = { m = 149, a7 = 31 } }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

local MAGE_PLAYER = { classID = MAGE, level = 32, ilvl = 40 }
local WARRIOR_PLAYER = { classID = WARRIOR, level = 60, ilvl = 0 }

-- The state with only `fields` on (everything else off), the player and the zone given.
local function state(fields)
	local s = F().Reset()
	for k, v in pairs(fields or {}) do s[k] = v end
	return s
end

local function keeps(fields, listing, player, offset)
	return F().Matches(state(fields), listing, {}, { player = player or MAGE_PLAYER, offset = offset or 0 })
end

local function names(fields, listings, player, offset)
	local fn = F().Compile(state(fields), { player = player or MAGE_PLAYER, offset = offset or 0 })
	local out = {}
	for _, s in ipairs(listings) do
		if fn == nil or fn(s, {}) then out[#out + 1] = s.k:match("[^|]+$") end
	end
	return out
end

describe("states", function()
	it("a new character has only 'Recruiting' on; Reset turns everything off", function()
		local d = F().Defaults()
		truthy(d.recruiting)
		eq(F().Count(d), 1)
		deepEq(F().ActiveList(d), { "recruiting" })
		local r = F().Reset()
		falsy(r.recruiting)
		eq(F().Count(r), 0)
		truthy(F().IsReset(r))
		isNil(F().Compile(r, {}), "no function runs per listing when nothing is on")
	end)

	it("Sanitize keeps good values, replaces bad ones and drops unknown keys", function()
		local good = { recruiting = false, myClass = true, reqs = true, newb = true, roles = 3, langs = 17, paces = 5, acts = 8191,
			days = 127, timeFrom = 1200, timeTo = 60, minActive = 25 }
		local s = F().Sanitize(good)
		for k, v in pairs(good) do eq(s[k], v, k) end

		local bad = F().Sanitize({ recruiting = "yes", myClass = 1, roles = 99, langs = -4, paces = 1e9, acts = "x", days = 128.9,
			timeFrom = 2000, timeTo = "late", minActive = 7, junk = true, [3] = 1 })
		truthy(bad.recruiting, "a wrong type falls back to the default")
		falsy(bad.myClass)
		eq(bad.roles, 15, "numbers are clamped into their range")
		eq(bad.langs, 0)
		eq(bad.paces, 7)
		eq(bad.acts, 0)
		eq(bad.days, 127)
		eq(bad.timeFrom, 1439)
		isNil(bad.timeTo)
		eq(bad.minActive, 0, "only the offered steps are accepted")
		isNil(bad.junk)
		isNil(bad[3])
		deepEq(F().Sanitize(nil), F().Defaults())
		deepEq(F().Sanitize("garbage"), F().Defaults())
		local nan = F().Sanitize({ roles = 0 / 0, days = math.huge })
		eq(nan.roles, 0)
		eq(nan.days, 0)
	end)

	it("the roles a class cannot play are dropped (SPEC-03 §5)", function()
		eq(F().Sanitize({ roles = 15 }, { classID = MAGE }).roles, RANGED)
		eq(F().Sanitize({ roles = 15 }, { classID = WARRIOR }).roles, TANK + MELEE)
		eq(F().Sanitize({ roles = 15 }, { classID = DRUID }).roles, 15)
		eq(F().Sanitize({ roles = 15 }, {}).roles, 15, "an unknown class restricts nothing")
	end)

	it("counts what is on: one per filter, however many choices it holds", function()
		eq(F().Count(state({ roles = 15 })), 1)
		eq(F().Count(state({ langs = 511, acts = 5, days = 127 })), 3)
		eq(F().Count(state({ timeFrom = hm(20) })), 1, "a start alone is a filter")
		eq(F().Count(state({ timeFrom = hm(20), timeTo = hm(20) })), 0, "equal bounds mean the whole day: nothing narrows")
		eq(F().Count(state({ recruiting = true, myClass = true, reqs = true, newb = true, roles = 1, langs = 1, paces = 1,
			acts = 1, days = 1, timeFrom = 0, timeTo = 60, minActive = 5 })), 11)
		eq(F().PlateText(0, L), "Filters")
		eq(F().PlateText(4, L), "Filters · 4 active")
	end)

	it("mask helpers turn lists into masks and back", function()
		eq(F().MaskOf({ 1, 3 }), 5)
		deepEq(F().ListOf(5, 9), { 1, 3 })
		deepEq(F().ListOf(0, 9), {})
		truthy(F().Share(5, 4, 9))
		falsy(F().Share(5, 2, 9))
		falsy(F().Share(0, 511, 9))
	end)
end)

describe("each filter keeps what SPEC-05 §2 says", function()
	it("Recruiting only: rec ~= 0 (open and 'some classes' stay, closed goes)", function()
		eq(#names({ recruiting = true }, { sum("Open", { rec = 1 }), sum("Some", { rec = 2 }), sum("Closed", { rec = 0 }) }), 2)
		truthy(keeps({ recruiting = true }, sum("a", { rec = 2 })))
		falsy(keeps({ recruiting = true }, sum("a", { rec = 0 })))
		truthy(keeps({}, sum("a", { rec = 0 })), "off: everything stays")
	end)

	it("Looking for my class: want[myClass] or want[0]", function()
		truthy(keeps({ myClass = true }, sum("a", { want = { [0] = HEALER } })), "any class")
		truthy(keeps({ myClass = true }, sum("a", { want = { [MAGE] = RANGED } })))
		falsy(keeps({ myClass = true }, sum("a", { want = { [WARRIOR] = TANK } })))
		falsy(keeps({ myClass = true }, sum("a", { want = "nil" })), "a listing that names no class does not want mine")
		falsy(keeps({ myClass = true }, sum("a", { want = {} })))
		truthy(keeps({ myClass = true }, sum("a", { want = { [WARRIOR] = TANK } }), {}), "my class unknown: cannot filter, keeps")
	end)

	it("Role: a wanted role in common, for my class or for any class", function()
		local wantsHealerAny = sum("a", { want = { [0] = HEALER } })
		local wantsRangedMage = sum("b", { want = { [MAGE] = RANGED, [WARRIOR] = TANK } })
		local wantsTankWarrior = sum("c", { want = { [WARRIOR] = TANK } })
		-- a Priest can heal or shoot
		local priest = { classID = PRIEST, level = 60, ilvl = 0 }
		truthy(keeps({ roles = HEALER }, wantsHealerAny, priest))
		falsy(keeps({ roles = RANGED }, wantsHealerAny, priest))
		truthy(keeps({ roles = HEALER + RANGED }, wantsHealerAny, priest), "several roles: any of them")
		falsy(keeps({ roles = RANGED }, wantsRangedMage, priest), "ranged is wanted for Mage, not for Priest")
		truthy(keeps({ roles = RANGED }, wantsRangedMage, MAGE_PLAYER))
		falsy(keeps({ roles = RANGED }, wantsTankWarrior, MAGE_PLAYER))
		falsy(keeps({ roles = RANGED }, sum("d", { want = "nil" }), MAGE_PLAYER))
		-- the roles of my class only: a Mage cannot choose Tank, so the choice is ignored
		truthy(keeps({ roles = TANK }, wantsTankWarrior, MAGE_PLAYER), "an impossible role narrows nothing")
		-- with no class every wanted role counts
		truthy(keeps({ roles = TANK }, wantsTankWarrior, {}))
	end)

	it("Requirements met: level and item level; unknown does not exclude", function()
		local player = { classID = MAGE, level = 32, ilvl = 40 }
		truthy(keeps({ reqs = true }, sum("a", { minL = 30 }), player))
		falsy(keeps({ reqs = true }, sum("a", { minL = 40 }), player))
		falsy(keeps({ reqs = true }, sum("a", { minL = 20, minI = 50 }), player))
		truthy(keeps({ reqs = true }, sum("a", { minL = 20, minI = 40 }), player))
		truthy(keeps({ reqs = true }, sum("a", { minL = "nil", minI = "nil" }), player), "no requirements")
		truthy(keeps({ reqs = true }, sum("a", { minL = 40 }), { classID = MAGE }), "my level unknown: not a failure")
	end)

	it("New player friendly: newb", function()
		truthy(keeps({ newb = true }, sum("a", { newb = true })))
		falsy(keeps({ newb = true }, sum("a", { newb = false })))
		falsy(keeps({ newb = true }, sum("a", { newb = "nil" })))
	end)

	it("Language: at least one language in common, the main one counts", function()
		local en_it = sum("a", { lang = 1 + 16, lang1 = 5 })   -- English and Italian, main Italian
		truthy(keeps({ langs = 16 }, en_it))
		truthy(keeps({ langs = 1 }, en_it))
		falsy(keeps({ langs = 2 + 4 }, en_it), "German, French")
		truthy(keeps({ langs = 2 + 16 }, en_it), "any of the chosen")
		truthy(keeps({ langs = 16 }, sum("b", { lang = 0, lang1 = 5 })), "the main language alone is enough")
		falsy(keeps({ langs = 16 }, sum("c", { lang = "nil", lang1 = "nil" })))
		truthy(keeps({ langs = 256 }, sum("d", { lang = 256, lang1 = 9 })), "'Other'")
	end)

	it("Commitment: pace is one of those chosen", function()
		truthy(keeps({ paces = 1 }, sum("a", { pace = 1 })))
		falsy(keeps({ paces = 1 }, sum("a", { pace = 2 })))
		truthy(keeps({ paces = 2 + 4 }, sum("a", { pace = 3 })))
		falsy(keeps({ paces = 7 }, sum("a", { pace = "nil" })))
	end)

	it("Activity: at least one activity in common with the tags", function()
		truthy(keeps({ acts = 1 }, sum("a", { tags = { 1, 5 } })))
		truthy(keeps({ acts = 16 }, sum("a", { tags = { 1, 5 } })), "the second tag counts too")
		falsy(keeps({ acts = 2 + 4 }, sum("a", { tags = { 1, 5 } })))
		truthy(keeps({ acts = 4096 }, sum("a", { tags = { 13 } })), "Housing, the 13th")
		falsy(keeps({ acts = 1 }, sum("a", { tags = "nil" })))
		falsy(keeps({ acts = 1 }, sum("a", { tags = { 99, "x" } })), "invalid ids are ignored")
	end)

	it("Play days: at least one day in common", function()
		local weekend = sum("w", { days = SAT + SUN })
		truthy(keeps({ days = SAT }, weekend))
		truthy(keeps({ days = MON + SUN }, weekend))
		falsy(keeps({ days = MON + TUE + WED + THU + FRI }, weekend))
		falsy(keeps({ days = SAT }, sum("n", { days = "nil" })))
		truthy(keeps({ days = SAT }, sum("all", { days = 127 })))
	end)

	it("Active members: a7 at least the minimum", function()
		truthy(keeps({ minActive = 25 }, sum("a", { st = { m = 149, a7 = 31 } })))
		truthy(keeps({ minActive = 25 }, sum("a", { st = { m = 149, a7 = 25 } })), "equal passes")
		falsy(keeps({ minActive = 25 }, sum("a", { st = { m = 149, a7 = 24 } })))
		falsy(keeps({ minActive = 5 }, sum("a", { st = "nil" })), "no statistics: not known to have enough")
		truthy(keeps({ minActive = 0 }, sum("a", { st = "nil" })))
	end)
end)

describe("combinations", function()
	local list = {
		sum("Aurora", { rec = 1, want = { [MAGE] = RANGED }, pace = 2, langs = 1, tags = { 5, 6 }, days = SAT + SUN, st = { a7 = 31 } }),
		sum("Bastion", { rec = 0, want = { [MAGE] = RANGED }, pace = 2, tags = { 5 }, days = SAT, st = { a7 = 60 } }),
		sum("Cinder", { rec = 1, want = { [WARRIOR] = TANK }, pace = 3, tags = { 1 }, days = MON + TUE, st = { a7 = 8 } }),
		sum("Dawn", { rec = 2, want = { [0] = HEALER }, pace = 1, newb = false, tags = { 3 }, days = SAT, minL = 50, st = { a7 = 12 } }),
	}

	it("every filter must hold (AND)", function()
		deepEq(names({}, list), { "Aurora", "Bastion", "Cinder", "Dawn" })
		deepEq(names({ recruiting = true }, list), { "Aurora", "Cinder", "Dawn" })
		deepEq(names({ recruiting = true, myClass = true }, list), { "Aurora", "Dawn" })
		deepEq(names({ recruiting = true, myClass = true, reqs = true }, list), { "Aurora" }, "Dawn needs level 50")
		deepEq(names({ recruiting = true, myClass = true, newb = true }, list), { "Aurora" })
		deepEq(names({ acts = 16 + 32, days = SAT }, list), { "Aurora", "Bastion" })
		deepEq(names({ acts = 16, days = SAT, minActive = 50 }, list), { "Bastion" })
		deepEq(names({ paces = 1 + 4, recruiting = true }, list), { "Cinder", "Dawn" })
		deepEq(names({ paces = 2, myClass = true, minActive = 50 }, list), { "Bastion" })
		deepEq(names({ paces = 4, myClass = true }, list), {}, "nothing left")
	end)

	it("the order of the list is not touched", function()
		local fn = F().Compile(state({ recruiting = true }), { player = MAGE_PLAYER })
		local got = {}
		for _, s in ipairs(list) do if fn(s, {}) then got[#got + 1] = s end end
		eq(got[1].k, list[1].k)
		eq(got[#got].k, list[4].k)
	end)

	it("a filter and a search narrow the same list (Browse), and resetting brings everything back", function()
		local M = AzerothGuildFinder.BrowseModel
		local C = AzerothGuildFinder.Catalog
		for _, s in ipairs(list) do C:PutSummary(s) end
		local fn = F().Compile(state({ recruiting = true }), { player = MAGE_PLAYER })
		eq(#M.Build(C, M.Query(""), fn).list, 3)
		eq(#M.Build(C, M.Query("bas"), fn).list, 0, "Bastion is hidden by the filter")
		eq(#M.Build(C, M.Query("cin"), fn).list, 1)
		eq(#M.Build(C, M.Query("bas"), F().Compile(F().Reset(), {})).list, 1, "reset: Bastion is back")
		eq(M.Build(C, M.Query(""), fn).total, 4, "the total is not narrowed by filters")
	end)
end)

describe("play time", function()
	it("windows: one inside the day, two around midnight, the whole day", function()
		deepEq(F().Windows(hm(20), hm(23)), { { 1200, 1380 } })
		deepEq(F().Windows(hm(22), hm(2)), { { 1320, 1440 }, { 0, 120 } })
		deepEq(F().Windows(hm(5), hm(5)), { { 0, 1440 } })
	end)

	it("two windows overlap when they share a minute; touching is not overlapping", function()
		truthy(F().Overlap(hm(20), hm(23), hm(22), hm(1)))
		truthy(F().Overlap(hm(20), hm(23), hm(21), hm(22)), "one inside the other")
		falsy(F().Overlap(hm(20), hm(23), hm(23), hm(2)), "ends when the other starts")
		falsy(F().Overlap(hm(20), hm(23), hm(10), hm(12)))
		truthy(F().Overlap(hm(22), hm(2), hm(1), hm(3)), "both across midnight")
		truthy(F().Overlap(hm(22), hm(2), hm(23), hm(23, 30)), "the one across midnight contains the other")
		truthy(F().Overlap(hm(22), hm(2), hm(0, 30), hm(1)))
		falsy(F().Overlap(hm(22), hm(2), hm(3), hm(21)))
		truthy(F().Overlap(hm(7), hm(7), hm(12), hm(13)), "the whole day overlaps everything")
		truthy(F().Overlap(hm(12), hm(13), hm(7), hm(7)))
	end)

	it("the filter window: both bounds, only a start (to midnight), only an end (from midnight), equal (nothing)", function()
		local a, b = F().TimeWindow(state({ timeFrom = hm(20), timeTo = hm(23) }))
		eq(a, 1200); eq(b, 1380)
		a, b = F().TimeWindow(state({ timeFrom = hm(20) }))
		eq(a, 1200); eq(b, 0)
		a, b = F().TimeWindow(state({ timeTo = hm(2) }))
		eq(a, 0); eq(b, 120)
		isNil(F().TimeWindow(state({ timeFrom = hm(5), timeTo = hm(5) })))
		isNil(F().TimeWindow(state({})))
	end)

	it("a listing in UTC is compared in the player's zone (UTC+1: 20:00-23:00 UTC is 21:00-00:00)", function()
		local g = sum("a", { t0 = hm(20), t1 = hm(23) })
		truthy(keeps({ timeFrom = hm(23), timeTo = hm(2) }, g, nil, 60), "23:00-02:00 local meets 21:00-00:00")
		falsy(keeps({ timeFrom = hm(23), timeTo = hm(2) }, g, nil, 0), "in UTC it only touches 23:00")
		falsy(keeps({ timeFrom = hm(0, 30), timeTo = hm(2) }, g, nil, 60), "after it ends")
		truthy(keeps({ timeFrom = hm(20), timeTo = hm(21, 30) }, g, nil, 60))
		falsy(keeps({ timeFrom = hm(18), timeTo = hm(20, 30) }, g, nil, 60), "21:00 local is its start")
	end)

	it("west of Greenwich: 22:00-23:00 UTC is 17:00-18:00 at UTC-5", function()
		local g = sum("a", { t0 = hm(22), t1 = hm(23) })
		truthy(keeps({ timeFrom = hm(17, 30), timeTo = hm(19) }, g, nil, -300))
		falsy(keeps({ timeFrom = hm(17, 30), timeTo = hm(19) }, g, nil, 0))
		falsy(keeps({ timeFrom = hm(18), timeTo = hm(20) }, g, nil, -300), "starts when it ends")
	end)

	it("a listing across midnight in UTC and one that crosses it only after the conversion", function()
		local over = sum("over", { t0 = hm(23), t1 = hm(2) })
		truthy(keeps({ timeFrom = hm(1), timeTo = hm(3) }, over))
		truthy(keeps({ timeFrom = hm(23, 30), timeTo = hm(23, 45) }, over))
		falsy(keeps({ timeFrom = hm(3), timeTo = hm(22) }, over))
		truthy(keeps({ timeFrom = hm(3), timeTo = hm(22) }, over, nil, -60 * 3), "UTC-3: 20:00-23:00, and 22:00 is inside")
		-- 23:00-02:00 UTC at UTC+2 is 01:00-04:00: it no longer crosses midnight
		truthy(keeps({ timeFrom = hm(3), timeTo = hm(5) }, over, nil, 120))
		falsy(keeps({ timeFrom = hm(5), timeTo = hm(8) }, over, nil, 120))
		-- 20:00-23:00 UTC at UTC+5 is 01:00-04:00 the next day
		truthy(keeps({ timeFrom = hm(23), timeTo = hm(2) }, sum("x", { t0 = hm(20), t1 = hm(23) }), nil, 300))
	end)

	it("a window that wraps midnight in the filter meets one that wraps in the listing", function()
		local late = sum("late", { t0 = hm(22), t1 = hm(2) })
		truthy(keeps({ timeFrom = hm(23), timeTo = hm(1) }, late))
		truthy(keeps({ timeFrom = hm(1), timeTo = hm(23) }, late), "the filter 01:00-23:00 meets 01:00-02:00 and 22:00-23:00")
		falsy(keeps({ timeFrom = hm(2), timeTo = hm(22) }, late), "exactly the gap")
	end)

	it("a listing 'all day' (t0 == t1) meets every window; no times declared meets none", function()
		truthy(keeps({ timeFrom = hm(4), timeTo = hm(5) }, sum("a", { t0 = hm(8), t1 = hm(8) })))
		truthy(keeps({ timeFrom = hm(4), timeTo = hm(5) }, sum("a", { t0 = 0, t1 = 0 }), nil, 90))
		falsy(keeps({ timeFrom = hm(4), timeTo = hm(5) }, sum("a", { t0 = "nil", t1 = "nil" })))
	end)

	it("days move with the conversion: Monday 23:30 UTC is Tuesday 01:30 at UTC+2", function()
		local g = sum("a", { days = MON, t0 = hm(23, 30), t1 = hm(2) })
		truthy(keeps({ days = TUE }, g, nil, 120))
		falsy(keeps({ days = MON }, g, nil, 120))
		truthy(keeps({ days = MON }, g, nil, 0))
		-- and the other way: Monday 01:00 UTC is Sunday 22:00 at UTC-3
		local h = sum("b", { days = MON, t0 = hm(1), t1 = hm(4) })
		truthy(keeps({ days = SUN }, h, nil, -180))
		falsy(keeps({ days = MON }, h, nil, -180))
		-- an all-day listing keeps its days whatever the zone
		truthy(keeps({ days = MON }, sum("c", { days = MON, t0 = 0, t1 = 0 }), nil, 600))
	end)

	it("days and time are separate conditions: both must hold", function()
		local g = sum("a", { days = SAT, t0 = hm(20), t1 = hm(23) })
		truthy(keeps({ days = SAT, timeFrom = hm(21), timeTo = hm(22) }, g))
		falsy(keeps({ days = MON, timeFrom = hm(21), timeTo = hm(22) }, g))
		falsy(keeps({ days = SAT, timeFrom = hm(5), timeTo = hm(6) }, g))
	end)

	it("a time choice list: every 30 minutes, 48 entries, 'Any' is the caller's", function()
		local c = F().TimeChoices()
		eq(#c, 48)
		eq(c[1], 0); eq(c[2], 30); eq(c[48], 1410)
		eq(F().TimeLabel(1410), "23:30")
		eq(F().TimeLabel(0), "00:00")
	end)
end)

describe("the controller", function()
	local function make(saved, player)
		local store = { saved = saved, saves = 0, changes = 0 }
		store.c = F().NewController({
			load = function() return store.saved end,
			save = function(t) store.saved, store.saves = t, store.saves + 1 end,
			player = function() return player or WARRIOR_PLAYER end,
			offset = function() return store.offset or 0 end,
			onChange = function() store.changes = store.changes + 1 end,
		})
		return store
	end

	it("starts from the saved state, or from the defaults", function()
		eq(make(nil).c:Get("recruiting"), true)
		local s = make({ recruiting = false, langs = 3 })
		eq(s.c:Get("recruiting"), false)
		eq(s.c:Get("langs"), 3)
		eq(s.saves, 0, "loading writes nothing")
	end)

	it("every change is saved as a copy and announced once; a change that changes nothing is not", function()
		local s = make(nil)
		truthy(s.c:Set("newb", true))
		eq(s.saves, 1); eq(s.changes, 1)
		eq(s.saved.newb, true)
		s.saved.newb = false
		eq(s.c:Get("newb"), true, "the saved table is not the live one")
		falsy(s.c:Set("newb", true))
		eq(s.saves, 1); eq(s.changes, 1)
		truthy(s.c:Toggle("newb"))
		eq(s.c:Get("newb"), false)
	end)

	it("masks are changed bit by bit; a bad value never gets in", function()
		local s = make(nil)
		s.c:SetBit("langs", 5, true)
		s.c:SetBit("langs", 1, true)
		eq(s.c:Get("langs"), 17)
		s.c:SetBit("langs", 5, false)
		eq(s.c:Get("langs"), 1)
		s.c:SetBit("langs", 5, false)
		eq(s.c:Get("langs"), 1, "already off")
		s.c:Set("minActive", 7)
		eq(s.c:Get("minActive"), 0)
		s.c:Set("days", 9999)
		eq(s.c:Get("days"), 127)
		s.c:Set("roles", 15)
		eq(s.c:Get("roles"), TANK + MELEE, "a Warrior")
	end)

	it("the time is set as a pair, and cleared with nils", function()
		local s = make(nil)
		truthy(s.c:SetTime(hm(20), hm(23, 30)))
		eq(s.c:Get("timeFrom"), 1200); eq(s.c:Get("timeTo"), 1410)
		eq(s.saved.timeFrom, 1200)
		truthy(s.c:IsActive("time"))
		falsy(s.c:SetTime(hm(20), hm(23, 30)))
		truthy(s.c:SetTime(nil, nil))
		isNil(s.c:Get("timeFrom"))
		falsy(s.c:IsActive("time"))
		isNil(s.saved.timeFrom, "nil is not saved")
	end)

	it("Reset turns everything off and saves it", function()
		local s = make(nil)
		s.c:Set("myClass", true); s.c:Set("acts", 5); s.c:SetTime(0, 60)
		eq(s.c:Count(), 4)
		s.c:Reset()
		eq(s.c:Count(), 0)
		eq(s.saved.recruiting, false)
		eq(s.saved.acts, 0)
		isNil(s.saved.timeFrom)
		isNil(s.c:Predicate(), "no filter, no function")
	end)

	it("the predicate follows the state, the player and the zone, and is rebuilt on Refresh", function()
		local s = make(nil)
		s.c:Reset()
		s.c:Set("recruiting", true)
		local closed = sum("closed", { rec = 0 })
		falsy(s.c:Predicate()(closed, {}))
		s.c:Set("recruiting", false)
		isNil(s.c:Predicate())
		s.c:SetTime(hm(23), hm(2))
		local g = sum("g", { t0 = hm(20), t1 = hm(23) })
		falsy(s.c:Predicate()(g, {}), "UTC: touches only")
		s.offset = 60
		falsy(s.c:Predicate()(g, {}), "still the compiled one")
		s.c:Refresh()
		truthy(s.c:Predicate()(g, {}), "after the refresh the zone of the player counts")
	end)

	it("a persisted state that is damaged is repaired, not trusted", function()
		local s = make({ recruiting = "no", roles = "all", langs = -1, minActive = 12, timeFrom = {}, junk = 1 })
		eq(s.c:Get("recruiting"), true)
		eq(s.c:Get("roles"), 0)
		eq(s.c:Get("minActive"), 0)
		isNil(s.c:Get("timeFrom"))
		isNil(s.c:Get("junk"))
	end)

	it("works without a player and without storage", function()
		local c = F().NewController({})
		truthy(c:Get("recruiting"))
		c:Set("newb", true)
		eq(c:Count(), 2)
		truthy(c:Predicate()(sum("a"), {}))
	end)
end)
