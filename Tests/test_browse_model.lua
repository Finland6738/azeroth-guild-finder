-- M2.5: the logic of the Find a Guild list (UI/BrowseModel.lua) without frames: ordering and search (SPEC-03 §7), the
-- states and their messages (SPEC-05 §1), the texts of a card, days and times across time zones, virtual scrolling
-- arithmetic and the recycling of the row pool, throttle and debounce.
-- The mock player is Horde on "Test Realm", so the catalog accepts keys "TestRealm|Horde|<name>".

local function M() return AzerothGuildFinder.BrowseModel end
local function C() return AzerothGuildFinder.Catalog end
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })
local function key(name) return "TestRealm|Horde|" .. name end

local function summary(name, extra)
	local t = { k = key(name), rev = 1, upd = GetServerTime() - 3 * 86400, first = 1766000000, own = "a1b2c3d4", sub = "Friendly",
		lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 31, t0 = 1200, t1 = 1380, rec = 1, apps = true,
		want = { [0] = 8 }, newb = true, minL = 20 }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

local function put(name, extra, meta) return C():PutSummary(summary(name, extra), meta) end

local function names(list)
	local out = {}
	for i, s in ipairs(list) do out[i] = s.k:match("[^|]+$") end
	return out
end

local function build(text, filter) return M().Build(C(), M().Query(text), filter) end

-- Deterministic shuffle.
local function shuffled(list, seed)
	local copy = {}
	for i, v in ipairs(list) do copy[i] = v end
	local x = seed
	for i = #copy, 2, -1 do
		x = (x * 1103515245 + 12345) % 2147483648
		local j = x % i + 1
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

describe("the search text", function()
	it("is normalized like names: accents, case, spaces and symbols do not count", function()
		local q = M().Query("  Ördine-Del_Drago 7 ")
		eq(q.key, "ordinedeldrago")
		eq(q.state, "active")
		eq(q.raw, "  Ördine-Del_Drago 7 ")
	end)

	it("needs 3 letters after normalization", function()
		eq(M().Query("").state, "empty")
		eq(M().Query(nil).state, "empty")
		eq(M().Query("  12 --").state, "empty", "no letters at all")
		eq(M().Query("or").state, "short")
		eq(M().Query("o r").state, "short", "spaces are not letters")
		eq(M().Query("ord").state, "active")
		eq(M().Query("é-ö-a").state, "active", "three letters under the marks")
	end)
end)

describe("ordering", function()
	local NAMES = { "Zeta Legion", "Ördine del Drago", "alpha team", "Ordine Cremisi", "Æther", "[AD] GankEmAll", "Night Watch",
		"123", "!!!", "Los Lobos", "Éclair", "Aurora" }
	local EXPECTED = { "[AD] GankEmAll", "Æther", "alpha team", "Aurora", "Éclair", "Los Lobos", "Night Watch", "Ordine Cremisi",
		"Ördine del Drago", "Zeta Legion" }

	it("is always A to Z on the normalized name, symbols and digits last", function()
		for i, n in ipairs(NAMES) do put(n, { own = ("%08x"):format(i) }) end
		local got = names(build("").list)
		-- sort keys: adgankemall, aether, alphateam, aurora, eclair, loslobos, nightwatch, ordinecremisi, ordinedeldrago, zetalegion
		eq(#got, 12)
		deepEq({ unpack(got, 1, 10) }, EXPECTED)
		deepEq({ got[11], got[12] }, { "!!!", "123" }, "no letters: last, by the original name")
	end)

	it("does not depend on the order the listings arrived in", function()
		local first
		for seed = 1, 6 do
			C():Clear()
			for i, n in ipairs(shuffled(NAMES, seed)) do put(n, { own = ("%08x"):format(i) }) end
			local got = table.concat(names(build("").list), "|")
			first = first or got
			eq(got, first, "seed " .. seed)
		end
	end)

	it("keeps the order when the search or a filter narrows the list", function()
		for i, n in ipairs(NAMES) do put(n, { own = ("%08x"):format(i) }) end
		local all = names(build("").list)
		local narrowed = names(build("", function(s) return s.k:find("e") ~= nil end).list)
		local last = 0
		for _, n in ipairs(narrowed) do
			for i, a in ipairs(all) do
				if a == n then truthy(i > last, n); last = i end
			end
		end
	end)

	it("shows the original name, never the normalized one", function()
		put("Ördine del Drago")
		local card = M().Card(build("").list[1], nil, {}, { now = GetServerTime(), offset = 0, L = L })
		eq(card.name, "Ördine del Drago")
	end)
end)

describe("search", function()
	local function fill()
		for i, n in ipairs({ "Ördine del Drago", "Ordine Cremisi", "Night Watch", "Aurora", "Los Ordenados", "N1ght-Wolves" }) do
			put(n, { own = ("%08x"):format(i) })
		end
	end

	it("finds a substring of the normalized name", function()
		fill()
		deepEq(names(build("ordine").list), { "Ordine Cremisi", "Ördine del Drago" })
		deepEq(names(build("DRAGO").list), { "Ördine del Drago" })
		deepEq(names(build("rora").list), { "Aurora" })
	end)

	it("ignores spaces, hyphens, digits and accents in the query and in the name", function()
		fill()
		deepEq(names(build("night watch").list), { "Night Watch" })
		deepEq(names(build("night-watch").list), { "Night Watch" })
		deepEq(names(build("nightwatch").list), { "Night Watch" })
		deepEq(names(build("nÏght").list), { "Night Watch" }, "Ï folds to i: 'night' matches")
		deepEq(names(build("n ght wolves").list), { "N1ght-Wolves" }, "the digit in the name is dropped")
	end)

	it("below 3 letters the list is not narrowed", function()
		fill()
		eq(build("or").shown, 6)
		eq(build("").shown, 6)
	end)

	it("reports the numbers: shown and total", function()
		fill()
		local b = build("ordine")
		eq(b.shown, 2)
		eq(b.total, 6)
		eq(#b.list, 2)
	end)

	it("a search that matches nothing shows nothing and keeps the total", function()
		fill()
		local b = build("zzzz")
		eq(b.shown, 0)
		eq(b.total, 6)
	end)

	it("combines with the filter hook", function()
		fill()
		local only = function(s) return s.k:find("Ordine", 1, true) ~= nil end
		deepEq(names(build("ordine", only).list), { "Ordine Cremisi" })
		eq(build("", only).shown, 1)
	end)

	it("the predicate is nil when nothing narrows the list", function()
		isNil(M().Predicate(M().Query(""), nil))
		isNil(M().Predicate(M().Query("ab"), nil))
		notNil(M().Predicate(M().Query("abc"), nil))
		notNil(M().Predicate(M().Query(""), function() return true end))
	end)

	it("hidden and withdrawn listings are not in the list or in the total", function()
		put("Old One")
		put("Fresh One", { own = "b1b2b3b4" })
		Mock.StepClock(31 * 86400)
		put("Fresh One", { own = "b1b2b3b4" }, { dist = "CHANNEL", sender = "Anna-TestRealm" })
		deepEq(names(build("").list), { "Fresh One" })
		eq(build("").total, 1)
	end)
end)

describe("states of the list", function()
	local function state(extra)
		local ctx = { total = 0, shown = 0, query = M().Query(""), filters = 0, syncing = false, peers = 0 }
		for k, v in pairs(extra or {}) do ctx[k] = v end
		return M().State(ctx)
	end

	it("nothing known while a sync runs is loading, with the wait message", function()
		local s = state({ syncing = true, peers = 3 })
		eq(s.kind, "loading")
		eq(M().StateText(s, nil, L), "Looking for guilds... this can take a minute the first time")
	end)

	it("nothing known, no sync and nobody around says so", function()
		local s = state()
		eq(s.kind, "nopeers")
		eq(M().StateText(s, nil, L), "No other Guild Finder users online right now. Listings will appear as they come online.")
	end)

	it("nothing known with peers around is the empty realm", function()
		local s = state({ peers = 2 })
		eq(s.kind, "empty")
		contains(M().StateText(s, nil, L), "No guild has published")
	end)

	it("a sync that is running beats 'nobody around'", function()
		eq(state({ syncing = true, peers = 0 }).kind, "loading")
	end)

	it("listings but none passes the filters: the message and the reset button", function()
		local s = state({ total = 42, shown = 0, filters = 3 })
		eq(s.kind, "nomatch")
		truthy(s.reset)
		eq(M().StateText(s, nil, L), "No guild matches your filters")
	end)

	it("listings but none matches the search: names the search, no reset button", function()
		local q = M().Query("zzz")
		local s = state({ total = 42, shown = 0, query = q })
		eq(s.kind, "nomatch")
		falsy(s.reset)
		eq(M().StateText(s, q, L), 'No guild name contains "zzz"')
	end)

	it("a pipe typed in the search is shown as a pipe, not as a colour code", function()
		local q = M().Query("zz|cffff0000zz")
		eq(M().StateText(state({ total = 4, shown = 0, query = q }), q, L), 'No guild name contains "zz||cffff0000zz"')
	end)

	it("a search and filters together: the filter message wins", function()
		local q = M().Query("zzz")
		local s = state({ total = 42, shown = 0, query = q, filters = 1 })
		eq(M().StateText(s, q, L), "No guild matches your filters")
		truthy(s.reset)
	end)

	it("listings shown is the list", function()
		local s = state({ total = 42, shown = 7 })
		eq(s.kind, "list")
		isNil(M().StateText(s, nil, L))
		falsy(s.reset)
	end)

	it("the hint 'Type at least 3 letters' is for 1-2 letters only, whatever the state", function()
		eq(M().HintText(state({ query = M().Query("or"), total = 5, shown = 5 }), L), "Type at least 3 letters")
		isNil(M().HintText(state({ query = M().Query("ord"), total = 5, shown = 5 }), L))
		isNil(M().HintText(state({ query = M().Query(""), total = 5, shown = 5 }), L))
		eq(state({ query = M().Query("o"), total = 0, peers = 1 }).hint, "short")
	end)
end)

describe("texts", function()
	it("the count: '24 of 142 guilds', '142 guilds', '1 guild'", function()
		eq(M().CountText(24, 142, L), "24 of 142 guilds")
		eq(M().CountText(142, 142, L), "142 guilds")
		eq(M().CountText(1, 1, L), "1 guild")
		eq(M().CountText(0, 1, L), "0 of 1 guild")
		eq(M().CountText(0, 5, L), "0 of 5 guilds")
	end)

	it("ages: minutes, hours, yesterday, days; cards say today", function()
		eq(M().AgeText(5, L), "just now")
		eq(M().AgeText(120, L), "2 min ago")
		eq(M().AgeText(3 * 3600 + 5, L), "3 h ago")
		eq(M().AgeText(86400, L), "yesterday")
		eq(M().AgeText(5 * 86400, L), "5 days ago")
		eq(M().AgeText(-10, L), "just now", "a clock that went back")
		eq(M().AgeText(7200, L, true), "today")
		eq(M().AgeText(86400 * 2, L, true), "2 days ago")
		eq(M().AgeText(86400 * 1.5, L, true), "yesterday")
	end)

	it("the status bar: guilds known, the state of the sync, the scope", function()
		local text, level = M().StatusLine({ total = 142, syncing = false, lastSync = 1000, now = 1120 }, L)
		eq(text, "142 guilds known · synced 2 min ago · Only guilds of your faction and realm")
		eq(level, "ok")
		text, level = M().StatusLine({ total = 1, syncing = true, now = 5 }, L)
		eq(text, "1 guild known · syncing... · Only guilds of your faction and realm")
		eq(level, "warn")
		text, level = M().StatusLine({ total = 0, syncing = false, now = 5 }, L)
		contains(text, "not synced yet")
		eq(level, "off")
		text, level = M().StatusLine({ total = 3, syncing = false, lastSync = 0, now = 2 * 86400 }, L)
		contains(text, "synced 2 days ago")
		eq(level, "off", "an old sync is not green")
	end)

	it("days: ranges of three or more, lists, every day, none", function()
		eq(M().DaysText(31, L), "Mon–Fri")
		eq(M().DaysText(127, L), "Every day")
		eq(M().DaysText(2 ^ 2 + 2 ^ 5 + 2 ^ 6, L), "Wed, Sat, Sun")
		eq(M().DaysText(1 + 2, L), "Mon, Tue", "two days are listed")
		eq(M().DaysText(1 + 2 + 4 + 32, L), "Mon–Wed, Sat")
		eq(M().DaysText(64, L), "Sun")
		isNil(M().DaysText(0, L))
		isNil(M().DaysText(nil, L))
	end)

	it("times: 24 h, wrapped, all day when start equals end", function()
		eq(M().FormatMinutes(0), "00:00")
		eq(M().FormatMinutes(1439), "23:59")
		eq(M().FormatMinutes(1440 + 75), "01:15")
		eq(M().TimeText(1200, 1380, L), "20:00–23:00")
		eq(M().TimeText(1260, 60, L), "21:00–01:00", "across midnight")
		eq(M().TimeText(0, 0, L), "All day")
		eq(M().TimeText(600, 600, L), "All day")
		isNil(M().TimeText(nil, nil, L))
	end)
end)

describe("play days and times in the player's time zone", function()
	local MON, TUE, SUN = 1, 2, 64

	it("UTC stays UTC at offset 0", function()
		local d, a, b = M().ToLocal(31, 1200, 1380, 0)
		eq(d, 31); eq(a, 1200); eq(b, 1380)
	end)

	it("moves the times and keeps the days inside the same day", function()
		local d, a, b = M().ToLocal(31, 1200, 1380, 60)   -- 20:00-23:00 UTC is 21:00-00:00 at UTC+1
		eq(d, 31); eq(a, 1260); eq(b, 0)
	end)

	it("a start that falls on the next day moves the days forward (Sunday wraps to Monday)", function()
		local d, a, b = M().ToLocal(MON + SUN, 1380, 120, 120)   -- 23:00 UTC +2 h = 01:00 next day
		eq(d, TUE + MON, "Monday -> Tuesday, Sunday -> Monday")
		eq(a, 60); eq(b, 240)
	end)

	it("a start that falls on the previous day moves the days back (Monday wraps to Sunday)", function()
		local d, a, b = M().ToLocal(MON + TUE, 60, 180, -120)   -- 01:00 UTC -2 h = 23:00 the day before
		eq(d, SUN + MON, "Monday -> Sunday, Tuesday -> Monday")
		eq(a, 1380); eq(b, 60)
	end)

	it("all day stays all day with its days; missing times change nothing", function()
		local d, a, b = M().ToLocal(31, 0, 0, 300)
		eq(d, 31); eq(a, 0); eq(b, 0)
		d, a, b = M().ToLocal(31, nil, nil, 300)
		eq(d, 31); isNil(a); isNil(b)
		d = M().ToLocal(nil, 600, 700, 60)
		isNil(d)
	end)

	it("a half-hour zone (UTC+5:30) and a bad offset", function()
		local d, a, b = M().ToLocal(1, 1200, 1300, 330)
		eq(d, 2); eq(a, 90); eq(b, 190)
		d, a, b = M().ToLocal(1, 100, 200, "x")
		eq(a, 100)
	end)

	it("this computer's zone is a whole number of minutes (UTC on the mock)", function()
		eq(M().LocalOffset(GetServerTime()), 0)
	end)
end)

describe("a card", function()
	local function card(extra, player, opts)
		local o = { now = GetServerTime(), offset = 0, L = L }
		for k, v in pairs(opts or {}) do o[k] = v end
		local sum = AzerothGuildFinder.Listing.SanitizeSummary(summary("Night Watch", extra))
		return M().Card(sum, { status = "listed", annAt = GetServerTime() }, player or {}, o)
	end
	local MAGE = { level = 32, classID = 8, class = "MAGE", ilvl = 40 }

	it("has the name, the subtitle, the languages (main first), the commitment and the activities in order", function()
		local c = card({ lang1 = 5, lang = 1 + 16, tags = { 6, 1, 5 }, pace = 3 })
		eq(c.name, "Night Watch")
		eq(c.sub, "Friendly")
		deepEq(c.langs, { "IT", "EN" })
		eq(c.paceText, "HARDCORE")
		eq(c.paceKind, "hard")
		eq(c.activitiesText, "World PvP · Raids · Battlegrounds")
	end)

	it("the commitment tag kinds follow the three levels", function()
		eq(card({ pace = 1 }).paceKind, "casual")
		eq(card({ pace = 2 }).paceKind, "soft")
		eq(card({ pace = 3 }).paceKind, "hard")
	end)

	it("members: active over total, nothing when the statistics are missing", function()
		local c = card({ st = { m = 149, a7 = 31 } })
		eq(c.active, 31); eq(c.members, 149)
		isNil(card({ st = "nil" }).active)
	end)

	it("play days and times are shown in the zone given", function()
		local c = card({ days = 31, t0 = 1200, t1 = 1380 }, nil, { offset = 60 })
		eq(c.daysText, "Mon–Fri")
		eq(c.timeText, "21:00–00:00")
		eq(card({ t0 = 0, t1 = 0 }).timeText, "All day")
	end)

	it("wanted classes: up to four icons in class order, then +N; any class has its own flag", function()
		local c = card({ want = { [1] = 1, [5] = 2, [8] = 8, [9] = 8, [11] = 4 } })
		eq(#c.classes, 4)
		eq(c.classes[1].file, "WARRIOR"); eq(c.classes[4].file, "WARLOCK")
		eq(c.classesMore, 1)
		falsy(c.anyClass)
		local any = card({ want = { [0] = 2 } })
		eq(#any.classes, 0)
		truthy(any.anyClass)
		local none = card({ want = "nil" })
		eq(#none.classes, 0)
		falsy(none.anyClass)
	end)

	it("'looking for your class': the player's class or any class; unknown when nothing is known", function()
		truthy(card({ want = { [8] = 8 } }, MAGE).wantsYou)
		truthy(card({ want = { [0] = 8 } }, MAGE).wantsYou)
		eq(card({ want = { [1] = 1 } }, MAGE).wantsYou, false)
		isNil(card({ want = "nil" }, MAGE).wantsYou)
		isNil(card({ want = { [8] = 8 } }, {}).wantsYou, "the player's class is unknown")
		eq(card({ want = { [8] = 8 }, minL = 1 }, MAGE).tag, "wantsyou")
	end)

	it("requirements are checked for the player: level and item level", function()
		local ok = card({ minL = 20 }, MAGE)
		eq(ok.req.ok, true)
		eq(ok.reqText, "Level 20+")
		local low = card({ minL = 40 }, MAGE)
		eq(low.req.ok, false)
		eq(low.reqText, "Level 40+ (you are 32)")
		local gear = card({ minL = 20, minI = 100 }, MAGE)
		eq(gear.req.ok, false)
		eq(gear.reqText, "Level 20+ · Item level 100+ (you have 40)")
		eq(card({ minL = "nil", minI = "nil" }, MAGE).reqText, "No requirements")
		eq(card({ minL = 1 }, MAGE).reqText, "No requirements", "level 1 is no requirement")
		eq(card({ minL = 40 }, {}).req.ok, nil, "unknown player: no mark")
		eq(card({ minL = 40 }, {}).reqText, "Level 40+")
	end)

	it("the one tag about the player: failed requirements beat 'looking for your class'", function()
		eq(card({ want = { [8] = 8 }, minL = 40 }, MAGE).tag, "reqfail")
		eq(card({ want = { [8] = 8 }, minL = 20 }, MAGE).tag, "wantsyou")
		isNil(card({ want = { [1] = 1 }, minL = 20 }, MAGE).tag)
		isNil(card({ want = { [8] = 8 }, minL = 20 }, {}).tag)
	end)

	it("age from the last edit, else from the last announcement; inactive listings are flagged", function()
		eq(card({ upd = GetServerTime() - 5 * 86400 }).updatedText, "Updated 5 days ago")
		eq(card({ upd = GetServerTime() - 100 }).updatedText, "Updated today")
		local sum = AzerothGuildFinder.Listing.SanitizeSummary(summary("Night Watch", { upd = "nil" }))
		local c = M().Card(sum, { status = "inactive", annAt = GetServerTime() - 20 * 86400 }, {}, { now = GetServerTime(), offset = 0, L = L })
		eq(c.updatedText, "Updated 20 days ago")
		truthy(c.inactive)
		falsy(card({}).inactive)
	end)

	it("the banner is only the index; the client's fileID is looked up by the page", function()
		eq(card({ bg = 4 }).bg, 4)
		isNil(card({ bg = "nil" }).bg)
	end)
end)

describe("virtual scrolling arithmetic", function()
	local STEP, GAP, VIEW = 188, 12, 638

	it("content height and the largest offset", function()
		eq(M().ContentHeight(0, STEP, GAP), 0)
		eq(M().ContentHeight(1, STEP, GAP), 176)
		eq(M().ContentHeight(500, STEP, GAP), 500 * 188 - 12)
		eq(M().ScrollMax(2, STEP, GAP, VIEW), 0, "fits: nothing to scroll")
		eq(M().ScrollMax(500, STEP, GAP, VIEW), 500 * 188 - 12 - 638)
		eq(M().ClampOffset(-50, 500, STEP, GAP, VIEW), 0)
		eq(M().ClampOffset(1e9, 500, STEP, GAP, VIEW), M().ScrollMax(500, STEP, GAP, VIEW))
		eq(M().ClampOffset("x", 500, STEP, GAP, VIEW), 0)
	end)

	it("the visible window at the top, in the middle and at the end", function()
		local a, b = M().Window(500, STEP, GAP, VIEW, 0)
		eq(a, 1); eq(b, 4)
		a, b = M().Window(500, STEP, GAP, VIEW, 188)
		eq(a, 2); eq(b, 5)
		a, b = M().Window(500, STEP, GAP, VIEW, 190)
		eq(a, 2); eq(b, 5)
		a, b = M().Window(500, STEP, GAP, VIEW, 1e9)
		eq(b, 500)
		truthy(a >= 497)
		a, b = M().Window(2, STEP, GAP, VIEW, 0)
		eq(a, 1); eq(b, 2)
		a, b = M().Window(0, STEP, GAP, VIEW, 0)
		truthy(b < a, "empty: nothing visible")
	end)

	it("the pool is big enough for any window", function()
		local size = M().PoolSize(VIEW, STEP)
		eq(size, 6)
		for offset = 0, M().ScrollMax(500, STEP, GAP, VIEW), 7 do
			local a, b = M().Window(500, STEP, GAP, VIEW, offset)
			truthy(b - a + 1 <= size, "offset " .. offset)
		end
	end)

	it("recycles: 500 listings scrolled from top to bottom bind each listing once and never need more than the pool", function()
		local pool = M().NewPool(M().PoolSize(VIEW, STEP))
		local maxOffset = M().ScrollMax(500, STEP, GAP, VIEW)
		local seen = {}
		for offset = 0, maxOffset, 13 do
			local a, b = M().Window(500, STEP, GAP, VIEW, offset)
			local show = pool:Assign(a, b)
			local slots = {}
			for _, s in ipairs(show) do
				truthy(s.slot >= 1 and s.slot <= pool.size)
				falsy(slots[s.slot], "a slot shows one listing at a time")
				slots[s.slot] = true
				seen[s.index] = true
				eq(pool.slots[s.slot], s.index)
			end
			eq(#show, b - a + 1)
		end
		local count = 0
		for _ in pairs(seen) do count = count + 1 end
		eq(count, 500, "every listing was shown")
		truthy(pool.binds <= 500 + pool.size, "bound " .. pool.binds .. " times for 500 listings")
	end)

	it("scrolling by one pixel back and forth rebinds nothing", function()
		local pool = M().NewPool(6)
		pool:Assign(10, 13)
		local before = pool.binds
		for _ = 1, 20 do pool:Assign(10, 13); pool:Assign(10, 14); pool:Assign(10, 13) end
		eq(pool.binds, before + 1, "only listing 14, once: a frame that left the view keeps what it shows")
	end)

	it("a pool forgets its slots when reset and hides the ones not in use", function()
		local pool = M().NewPool(4)
		local show, hide = pool:Assign(1, 2)
		eq(#show, 2); deepEq(hide, { 3, 4 })
		pool:Reset()
		show = pool:Assign(1, 2)
		truthy(show[1].rebind and show[2].rebind)
		show, hide = pool:Assign(1, 0)
		eq(#show, 0); eq(#hide, 4)
	end)
end)

describe("throttle and debounce", function()
	local function after(s, f) return AzerothGuildFinder.Compat.After(s, f) end

	it("the throttle turns many requests into one call after the delay", function()
		local runs = 0
		local t = M().NewCoalescer(after, 0.3, function() runs = runs + 1 end)
		for _ = 1, 50 do t:Request() end
		truthy(t:Pending())
		eq(runs, 0)
		Mock.Advance(0.2)
		eq(runs, 0)
		Mock.Advance(0.3)
		eq(runs, 1)
		falsy(t:Pending())
		eq(t.calls, 50)
		t:Request()
		Mock.Advance(0.5)
		eq(runs, 2, "a later request starts a new round")
	end)

	it("a cancelled throttle does not run, and a new request after it does", function()
		local runs = 0
		local t = M().NewCoalescer(after, 0.3, function() runs = runs + 1 end)
		t:Request(); t:Cancel()
		Mock.Advance(1)
		eq(runs, 0)
		t:Request()
		Mock.Advance(1)
		eq(runs, 1)
	end)

	it("a throttle with a clock that cannot schedule runs at once", function()
		local runs = 0
		local t = M().NewCoalescer(function() return false end, 0.3, function() runs = runs + 1 end)
		t:Request()
		eq(runs, 1)
		falsy(t:Pending())
	end)

	it("the debounce runs once, after the last call, with the last arguments", function()
		local got = {}
		local d = M().NewDebouncer(after, 0.25, function(a, b) got[#got + 1] = a .. b end)
		d:Call("o", 1)
		Mock.Advance(0.2)
		d:Call("or", 2)
		Mock.Advance(0.2)
		eq(#got, 0, "0.2 s after the last call is too early")
		d:Call("ord", 3)
		Mock.Advance(0.3)
		deepEq(got, { "ord3" })
		falsy(d:Pending())
	end)

	it("Flush runs a pending debounce now, Cancel drops it", function()
		local got = {}
		local d = M().NewDebouncer(after, 0.25, function(a) got[#got + 1] = a end)
		d:Call("x")
		d:Flush()
		deepEq(got, { "x" })
		Mock.Advance(1)
		eq(#got, 1, "the timer that was on its way does nothing")
		d:Flush()
		eq(#got, 1, "nothing pending")
		d:Call("y"); d:Cancel()
		Mock.Advance(1)
		eq(#got, 1)
	end)
end)
