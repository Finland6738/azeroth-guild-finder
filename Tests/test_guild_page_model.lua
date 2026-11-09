-- M2.7: the logic of the guild page (UI/GuildPageModel.lua) without frames: the page built from the summary alone and then
-- completed by the detail, the requirement checks against the visitor, days and times in the visitor's time zone, the
-- "Looking for" card and "they need your class", the members numbers, the Discord link and the contacts, dates, and the
-- layout arithmetic. The mock player is Horde on "Test Realm".

local function M() return AzerothGuildFinder.GuildPageModel end
local function C() return AzerothGuildFinder.Catalog end
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })
local function key(name) return "TestRealm|Horde|" .. name end
local NOW = 1790000000

local function summary(name, extra)
	local t = { k = key(name), rev = 5, upd = NOW - 2 * 86400, first = 1760000000, own = "a1b2c3d4", sub = "Small-scale PvP",
		lang = 1 + 16, lang1 = 5, tags = { 6, 1, 5 }, pace = 2, days = 31, t0 = 1140, t1 = 1350, rec = 1, apps = true,
		want = { [5] = 2, [8] = 8, [1] = 1, [11] = 1 + 2 + 4 }, newb = true, minL = 20,
		st = { m = 149, a7 = 31, u7lo = 19, u7hi = 24, max = 12, cls = { [1] = 18, [8] = 14, [5] = 11 } }, srev = NOW - 3 * 3600 }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

local function detail(name, extra)
	local t = { k = key(name), rev = 5, desc = "Competitive guild.", disc = "aurora-it", cont = { "Lyryn", "Kaelthar" }, note = "Voice chat for raids" }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

-- The view for a listing put in the real catalog: the same path the page takes.
local function view(name, opts)
	opts = opts or {}
	local entry, status = C():Get(key(name))
	return M().View({ k = key(name), entry = entry, status = status, player = opts.player or { level = 32, classID = 8, class = "MAGE", ilvl = 0 },
		now = NOW, offset = opts.offset or 0, heard = opts.heard, unavailable = opts.unavailable, L = L })
end

local function put(name, extra) assert(C():PutSummary(summary(name, extra))) end
local function putDetail(name, extra) assert(C():PutDetail(detail(name, extra))) end

describe("summary and detail", function()
	it("a summary alone gives a complete page except for the three things that need the detail", function()
		put("Aurora")
		local v = view("Aurora")
		falsy(v.gone)
		eq(v.name, "Aurora")
		eq(v.sub, "Small-scale PvP")
		eq(v.detail, "loading")
		isNil(v.desc); isNil(v.discord); eq(#v.contacts, 0)
		-- everything that comes from the summary is there already
		eq(v.looking.status.text, "Recruiting")
		eq(#v.looking.classes, 4)
		eq(v.activity.pace.text, "Softcore")
		eq(#v.activity.acts, 3)
		eq(v.members.active, 31)
		eq(v.requirements.items[1].text, "Level 20+")
		isNil(v.requirements.note)
		notNil(v.footer)
	end)

	it("the detail completes the same view: description, Discord link, contacts and the note", function()
		put("Aurora")
		putDetail("Aurora")
		local v = view("Aurora")
		eq(v.detail, "ready")
		eq(v.desc, "Competitive guild.")
		eq(v.discord, "https://discord.gg/aurora-it")
		eq(#v.contacts, 2)
		eq(v.requirements.note, "Voice chat for raids")
		eq(v.looking.status.text, "Recruiting")   -- unchanged
	end)

	it("no detail and no answer: unavailable; a detail beats the flag", function()
		put("Aurora")
		eq(view("Aurora", { unavailable = true }).detail, "unavailable")
		putDetail("Aurora")
		eq(view("Aurora", { unavailable = true }).detail, "ready")
	end)

	it("a detail older than the summary is shown while the newer one is asked for", function()
		put("Aurora", { rev = 7 })
		putDetail("Aurora", { rev = 5, desc = "Old text" })
		local v = view("Aurora")
		eq(v.detail, "ready")
		eq(v.desc, "Old text")
	end)

	it("a listing that is gone has no content", function()
		local v = M().View({ k = key("Nobody"), entry = nil, status = nil, now = NOW, offset = 0, L = L })
		truthy(v.gone)
		eq(v.name, "Nobody")
		local chan = { sender = "Gm-TestRealm", dist = "CHANNEL" }
		assert(C():PutSummary(summary("Aurora"), chan))
		assert(C():Delist(key("Aurora"), 5, chan))
		local entry, status = C():Get(key("Aurora"))
		truthy(M().View({ k = key("Aurora"), entry = entry, status = status, now = NOW, offset = 0, L = L }).gone)
	end)

	it("a listing that may be inactive still has a page, with the tag", function()
		put("Old")
		local entry = C():Get(key("Old"))
		local v = M().View({ k = key("Old"), entry = entry, status = "inactive", now = NOW, offset = 0, L = L, player = {} })
		falsy(v.gone)
		local last = v.tags[#v.tags]
		eq(last.text, "May be inactive")
		eq(last.kind, "gold")
	end)

	it("applications closed by the guild are noted, open ones need nothing yet", function()
		put("Aurora", { apps = false })
		put("Borealis", { apps = true })
		truthy(view("Aurora").appsClosed)
		falsy(view("Borealis").appsClosed)
	end)
end)

describe("the Discord link and the contacts", function()
	it("is the fixed prefix and the code, and nothing for a bad code", function()
		eq(M().DiscordUrl("abc"), "https://discord.gg/abc")
		eq(M().DiscordUrl("aurora-it"), "https://discord.gg/aurora-it")
		isNil(M().DiscordUrl("a"))
		isNil(M().DiscordUrl("has space"))
		isNil(M().DiscordUrl("https://discord.gg/abc"))
		isNil(M().DiscordUrl(nil))
		isNil(M().DiscordUrl(42))
	end)

	it("contacts keep the guild master's order and are online when a recent announcement came from them", function()
		local det = { cont = { "Lyryn", "Kaelthar", "Mira" } }
		local list = M().Contacts(det, { "kaelthar-TestRealm", "Stranger-Other" })
		eq(#list, 3)
		eq(list[1].name, "Lyryn"); falsy(list[1].online)
		eq(list[2].name, "Kaelthar"); truthy(list[2].online)
		falsy(list[3].online)
	end)

	it("no detail, no contacts, no heard list", function()
		eq(#M().Contacts(nil, { "x" }), 0)
		eq(#M().Contacts({}, nil), 0)
		eq(#M().Contacts({ cont = { "A" } }, nil), 1)
	end)
end)

describe("requirements checked against the visitor", function()
	local function req(sum, player, det) return M().Requirements(sum, det, player, L) end

	it("a level that is met has a check and the player's level", function()
		local r = req({ minL = 20 }, { level = 32 })
		eq(r.items[1].ok, true)
		eq(r.items[1].text, "Level 20+")
		eq(r.items[1].you, "(you are 32)")
		eq(r.ok, true)   -- the item level is not required, so the whole is ok
	end)

	it("a level that is not met is false and the whole fails", function()
		local r = req({ minL = 40 }, { level = 32 })
		eq(r.items[1].ok, false)
		eq(r.ok, false)
	end)

	it("the exact minimum is met", function()
		eq(req({ minL = 32 }, { level = 32 }).items[1].ok, true)
	end)

	it("an item level is checked on the same terms, rounded down in the text", function()
		local ok = req({ minI = 100 }, { level = 60, ilvl = 112.7 })
		eq(ok.items[2].ok, true)
		eq(ok.items[2].you, "(you have 112)")
		eq(req({ minI = 100 }, { level = 60, ilvl = 80 }).items[2].ok, false)
	end)

	it("what the client does not say is unknown, never a failure", function()
		local r = req({ minL = 20, minI = 100 }, {})
		isNil(r.items[1].ok); isNil(r.items[2].ok); isNil(r.ok)
		isNil(r.items[1].you)
		isNil(req({ minL = 20 }, nil).ok)
	end)

	it("no requirement at all is said so, and is not a failure", function()
		local r = req({}, { level = 5 })
		truthy(r.none)
		eq(r.items[1].text, "No level requirement"); truthy(r.items[1].muted)
		eq(r.items[2].text, "No item level requirement")
		eq(r.ok, true)
		local one = req({ minL = 1 }, { level = 5 })
		truthy(one.none)   -- level 1 is not a requirement
	end)

	it("the guild master's note comes from the detail only", function()
		isNil(req({}, {}, nil).note)
		eq(req({}, {}, { note = "Be nice" }).note, "Be nice")
	end)

	it("agrees with the list: the same answer as BrowseModel.Requirements", function()
		local sums = { { minL = 40, minI = 50 }, { minL = 10 }, { minI = 200 }, {} }
		local players = { { level = 30, ilvl = 60 }, { level = 60, ilvl = 10 }, {} }
		for _, s in ipairs(sums) do
			for _, p in ipairs(players) do
				eq(req(s, p).ok, AzerothGuildFinder.BrowseModel.Requirements(s, p).ok)
			end
		end
	end)
end)

describe("days and times in the visitor's time zone", function()
	local function act(extra, offset) return M().Activity(summary("X", extra), offset, L) end

	it("UTC stays as it is at offset 0 and the UTC line is given too", function()
		local a = act({ days = 31, t0 = 1140, t1 = 1350 }, 0)
		eq(a.timeText, "19:00–22:30")
		eq(a.utcText, "19:00–22:30 UTC")
		eq(a.daysMask, 31)
		eq(a.daysText, "Mon–Fri")
		falsy(a.allDay)
	end)

	it("one hour east: the times move an hour and the UTC line does not", function()
		local a = act({ t0 = 1140, t1 = 1350 }, 60)
		eq(a.timeText, "20:00–23:30")
		eq(a.utcText, "19:00–22:30 UTC")
		eq(a.daysMask, 31)
	end)

	it("across midnight the days move with the start time (east)", function()
		-- Monday-Friday 23:00-02:00 UTC seen from UTC+2: starts at 01:00 the next day
		local a = act({ days = 31, t0 = 1380, t1 = 120 }, 120)
		eq(a.timeText, "01:00–04:00")
		eq(a.daysMask, 2 + 4 + 8 + 16 + 32)   -- Tue-Sat
	end)

	it("across midnight the days move back in the west, and Monday wraps to Sunday", function()
		local a = act({ days = 1, t0 = 60, t1 = 180 }, -120)   -- Monday 01:00 UTC is Sunday 23:00 at UTC-2
		eq(a.timeText, "23:00–01:00")
		eq(a.daysMask, 64)
		eq(a.daysText, "Sun")
	end)

	it("a half-hour zone", function()
		eq(act({ t0 = 1200, t1 = 1380 }, 330).timeText, "01:30–04:30")
	end)

	it("an all-day guild says so, has no UTC line and keeps its days", function()
		local a = act({ days = 127, t0 = 600, t1 = 600 }, 180)
		truthy(a.allDay)
		eq(a.timeText, "All day")
		isNil(a.utcText)
		eq(a.daysMask, 127)
		eq(a.daysText, "Every day")
	end)

	it("a guild without days or times shows none", function()
		local a = act({ days = "nil", t0 = "nil", t1 = "nil" }, 60)
		eq(a.daysMask, 0)
		isNil(a.timeText); isNil(a.utcText); isNil(a.daysText)
	end)

	it("agrees with the list: the same conversion as BrowseModel.ToLocal for every zone", function()
		local B = AzerothGuildFinder.BrowseModel
		for _, off in ipairs({ -720, -300, -90, 0, 45, 60, 330, 840 }) do
			local days, t0, t1 = B.ToLocal(21, 1300, 200, off)
			local a = act({ days = 21, t0 = 1300, t1 = 200 }, off)
			eq(a.daysMask, days)
			eq(a.timeText, B.TimeText(t0, t1, L))
		end
	end)

	it("the zone of this computer is used when none is given", function()
		put("Aurora")
		local entry, status = C():Get(key("Aurora"))
		local v = M().View({ k = key("Aurora"), entry = entry, status = status, now = NOW, L = L, player = {} })
		eq(v.offset, AzerothGuildFinder.BrowseModel.LocalOffset(NOW))
	end)

	it("the commitment and the activities come in the guild's order of importance", function()
		local a = act({ tags = { 6, 1, 5 }, pace = 3 }, 0)
		eq(a.pace.text, "Hardcore")
		eq(a.pace.kind, "hard")
		eq(a.pace.tip, "Demanding schedule, attendance required, preparation expected (consumables, gear). This is the guild's commitment, not permadeath.")
		eq(a.acts[1].text, "World PvP"); eq(a.acts[1].n, 1)
		eq(a.acts[2].text, "Raids")
		eq(a.acts[3].text, "Battlegrounds"); eq(a.acts[3].n, 3)
	end)
end)

describe("Looking for", function()
	local function look(extra, player) return M().Looking(summary("X", extra), player or { classID = 8 }, L) end

	it("the three recruiting states", function()
		eq(look({ rec = 1 }).status.text, "Recruiting"); eq(look({ rec = 1 }).status.kind, "ok")
		eq(look({ rec = 2 }).status.text, "Recruiting: selected classes only"); eq(look({ rec = 2 }).status.kind, "gold")
		eq(look({ rec = 0 }).status.text, "Recruiting closed"); eq(look({ rec = 0 }).status.kind, "bad")
		isNil(look({ rec = "nil" }).status)
	end)

	it("lists the classes by id, each with its roles", function()
		local l = look({})
		eq(#l.classes, 4)
		eq(l.classes[1].file, "WARRIOR")
		eq(l.classes[1].roles[1].key, "tank")
		eq(l.classes[2].file, "PRIEST")
		eq(l.classes[2].roles[1].label, "Healer")
		eq(l.classes[3].file, "MAGE")
		eq(l.classes[3].roles[1].key, "ranged")
		eq(l.classes[4].file, "DRUID")
		eq(#l.classes[4].roles, 3)
		eq(l.classes[4].roles[3].key, "melee")
		eq(#l.legend, 4)
		eq(l.legend[4].label, "Ranged DPS")
	end)

	it("any class has its own entry with the roles", function()
		local l = look({ want = { [0] = 2 } })
		eq(#l.classes, 0)
		eq(l.any.roles[1].label, "Healer")
		falsy(l.none)
	end)

	it("no class and no preference says so", function()
		truthy(look({ want = "nil" }).none)
	end)

	it("they need your class: the class and the roles it can play", function()
		local l = look({}, { classID = 8 })   -- Mage: Ranged DPS is wanted
		eq(l.wantsYou.className, "Mage")
		eq(l.wantsYou.text, "They need your class: Mage · Ranged DPS")
	end)

	it("a class that lists several roles keeps the ones it can play", function()
		-- Druid is wanted as Tank, Healer and Melee DPS; all four roles are possible for a Druid
		local l = look({}, { classID = 11 })
		eq(l.wantsYou.text, "They need your class: Druid · Tank, Healer, Melee DPS")
	end)

	it("any class counts for you when the role is one your class can play", function()
		local l = look({ want = { [0] = 2 } }, { classID = 2 })   -- Paladin can heal
		eq(l.wantsYou.text, "They need your class: Paladin · Healer")
		isNil(look({ want = { [0] = 2 } }, { classID = 8 }).wantsYou)   -- a Mage cannot
	end)

	it("the roles of the class and of any class are added without repeating", function()
		local l = look({ want = { [11] = 1 + 2, [0] = 2 + 4 } }, { classID = 11 })
		eq(l.wantsYou.text, "They need your class: Druid · Tank, Healer, Melee DPS")
	end)

	it("a class that is not wanted, or an unknown player, gets no line", function()
		isNil(look({}, { classID = 4 }).wantsYou)       -- Rogue is not listed
		isNil(look({}, { classID = nil }).wantsYou)
		isNil(look({ want = "nil" }, { classID = 8 }).wantsYou)
		isNil(M().Looking(summary("X"), nil, L).wantsYou)
	end)
end)

describe("members", function()
	it("aggregates, the range of unique players and the age of the numbers", function()
		local m = M().Members(summary("X"), NOW, L)
		truthy(m.known)
		eq(m.active, 31); eq(m.total, 149); eq(m.maxLevel, 12)
		eq(m.unique, "19–24")
		eq(m.updatedText, "updated 3 h ago")
	end)

	it("an exact count is one number", function()
		eq(M().Members(summary("X", { st = { m = 10, a7 = 8, u7lo = 6, u7hi = 6 } }), NOW, L).unique, "6")
	end)

	it("the class mix is by class id and its fractions add up to one", function()
		local m = M().Members(summary("X"), NOW, L)
		eq(#m.mix, 3)
		eq(m.mix[1].file, "WARRIOR"); eq(m.mix[2].file, "PRIEST"); eq(m.mix[3].file, "MAGE")
		local total = 0
		for _, seg in ipairs(m.mix) do total = total + seg.fraction end
		near(total, 1, 1e-9)
		near(m.mix[1].fraction, 18 / 43, 1e-9)
	end)

	it("no statistics: unknown, and missing parts are just missing", function()
		falsy(M().Members(summary("X", { st = "nil" }), NOW, L).known)
		local m = M().Members(summary("X", { st = { a7 = 5 } }), NOW, L)
		truthy(m.known)
		isNil(m.unique); isNil(m.total); eq(#m.mix, 0)
	end)

	it("an unknown class in the mix is left out", function()
		local m = M().Members(summary("X", { st = { m = 5, a7 = 5, cls = { [1] = 2, [99] = 3 } } }), NOW, L)
		eq(#m.mix, 1)
	end)
end)

describe("dates", function()
	it("'12 Oct 2026' and the footer with both halves", function()
		local stamp = os.time({ year = 2026, month = 10, day = 12, hour = 12 })
		eq(M().DateText(stamp, L), "12 Oct 2026")
		local f = M().Footer({ first = stamp, upd = NOW - 2 * 86400 }, NOW, L)
		eq(f, "Listed since 12 Oct 2026 · Updated 2 days ago")
	end)

	it("each half only when it is known", function()
		eq(M().Footer({ upd = NOW - 60 * 5 }, NOW, L), "Updated 5 min ago")
		eq(M().Footer({ first = os.time({ year = 2026, month = 1, day = 3, hour = 12 }) }, NOW, L), "Listed since 3 Jan 2026")
		eq(M().Footer({}, NOW, L), "")
	end)

	it("a value that is not a time gives nothing", function()
		isNil(M().DateText(nil, L)); isNil(M().DateText(0, L)); isNil(M().DateText("x", L))
	end)
end)

describe("tags of the left page", function()
	it("languages (main first), faction, commitment", function()
		local tags = M().Tags(summary("X", { lang = 1 + 16, lang1 = 5, pace = 3 }), "Horde", false, L)
		eq(tags[1].text, "ITALIAN")
		eq(tags[2].text, "ENGLISH")
		eq(tags[3].text, "HORDE"); eq(tags[3].kind, "bad")
		eq(tags[4].text, "HARDCORE"); eq(tags[4].kind, "hard"); eq(tags[4].pace, 3)
		eq(#tags, 4)
	end)

	it("the Alliance has its own tag", function()
		local tags = M().Tags(summary("X", { lang = 1, lang1 = 1 }), "Alliance", false, L)
		eq(tags[2].text, "ALLIANCE"); eq(tags[2].kind, "default")
	end)
end)

describe("layout arithmetic", function()
	it("Stack: heights with a gap; an empty item takes no room and no gap", function()
		local ys, total = M().Stack({ 10, 20, 0, 5 }, 4)
		eq(ys[1], 0); eq(ys[2], 14); eq(ys[3], 34); eq(ys[4], 38)
		eq(total, 43)
		local _, empty = M().Stack({}, 4)
		eq(empty, 0)
		local _, onlyGaps = M().Stack({ 0, 0 }, 4)
		eq(onlyGaps, 0)
	end)

	it("Flow wraps at the width and counts the rows", function()
		local pos, h = M().Flow({ 100, 100, 100 }, 250, 10, 20, 6)
		eq(pos[1].x, 0); eq(pos[1].y, 0)
		eq(pos[2].x, 110); eq(pos[2].y, 0)
		eq(pos[3].x, 0); eq(pos[3].y, 26)
		eq(h, 46)
		local _, none = M().Flow({}, 250, 10, 20, 6)
		eq(none, 0)
	end)

	it("Flow centres each row when asked", function()
		local pos = M().Flow({ 100, 100, 50 }, 250, 10, 20, 6, "center")
		eq(pos[1].x, 20); eq(pos[2].x, 130)    -- (250 - 210) / 2 = 20
		eq(pos[3].x, 100)                      -- (250 - 50) / 2
	end)

	it("a box wider than the line still gets a place", function()
		local pos, h = M().Flow({ 400 }, 250, 10, 20, 6)
		eq(pos[1].x, 0)
		eq(h, 20)
	end)

	it("Columns: each stack apart, the page is as tall as the taller one", function()
		local ly, ry, h = M().Columns({ 100, 50 }, { 60, 40, 30 }, 10)
		eq(ly[2], 110); eq(ry[3], 120)
		eq(h, 160)
	end)

	it("scrolling is clamped to the content", function()
		eq(M().ScrollMax(1000, 600), 400)
		eq(M().ScrollMax(500, 600), 0)
		eq(M().ClampScroll(-5, 1000, 600), 0)
		eq(M().ClampScroll(999, 1000, 600), 400)
		eq(M().ClampScroll("x", 1000, 600), 0)
	end)
end)
