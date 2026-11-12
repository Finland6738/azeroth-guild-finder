-- M4.4: the view model of the Applications panel (UI/ApplicationsModel.lua, SPEC-07 §5), as pure Lua: who sees the panel, the
-- split into Pending and History, the counters, every field of a row, the empty states, the window of rows and the
-- notification options. The records are the ones of Data/Inbox.lua (the officer's copy of an application).
-- The mock player is "Testchar", Horde Orc Warrior 60 on "Test Realm".

local DAY = 86400
local KEY = "TestRealm|Horde|Aurora"
local NOW = 1767225600   -- a fixed "now"; the records are written relative to it

local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })
local function M() return AzerothGuildFinder.AppsModel end

local function rec(id, extra)
	local r = { id = id, k = KEY, state = "received", stateRev = 2, at = NOW - 2 * 3600, upd = NOW - 2 * 3600,
		who = "Elarin-TestRealm", cls = 8, race = 8, lvl = 32, roles = 8 }
	for k, v in pairs(extra or {}) do if v == "nil" then r[k] = nil else r[k] = v end end
	return r
end

local function view(recs, extra)
	local ctx = { role = "gm", key = KEY, recs = recs, now = NOW, tab = "pending" }
	for k, v in pairs(extra or {}) do ctx[k] = v end
	return M().View(ctx, L)
end

describe("who sees the panel (APP-07, SPEC-00 §5)", function()
	it("only the Guild Master and the officers", function()
		eq(M().CanSee("gm"), true)
		eq(M().CanSee("officer"), true)
		eq(M().CanSee("member"), false)
		eq(M().CanSee("none"), false)
		eq(M().CanSee(nil), false)
		eq(M().CanSee("nonsense"), false)
	end)

	it("a member or a character without a guild gets no rows and no counters, whatever the inbox holds", function()
		local recs = { rec("00000001"), rec("00000002", { state = "accepted", stateRev = 3, by = "Lyryn" }) }
		for _, role in ipairs({ "member", "none", "nonsense" }) do
			local v = view(recs, { role = role })
			eq(v.visible, false, role)
			eq(#v.rows, 0)
			eq(v.pendingCount, 0)
			eq(v.counters.accepted, 0)
			eq(v.empty.title, "Only the Guild Master and the officers see applications")
		end
	end)

	it("an officer without a guild key sees nothing either", function()
		eq(M().View({ role = "officer", recs = { rec("00000001") }, now = NOW }, L).visible, false)
	end)

	it("the Guild Master and an officer see the same rows", function()
		local recs = { rec("00000001") }
		for _, role in ipairs({ "gm", "officer" }) do
			local v = view(recs, { role = role })
			eq(v.visible, true)
			eq(#v.rows, 1)
			eq(v.rows[1].actions.invite.enabled, true)
		end
	end)
end)

describe("Pending and History", function()
	it("an open application is pending, newest first; a closed one is history, the last change first", function()
		local recs = {
			rec("00000001", { at = NOW - 3 * DAY, upd = NOW - 3 * DAY }),
			rec("00000002", { at = NOW - 3600, upd = NOW - 3600 }),
			rec("00000003", { at = NOW - DAY, upd = NOW - DAY }),
			rec("00000004", { state = "accepted", stateRev = 3, at = NOW - 9 * DAY, upd = NOW - 5 * DAY, by = "Lyryn" }),
			rec("00000005", { state = "declined", stateRev = 3, at = NOW - 9 * DAY, upd = NOW - 2 * DAY, by = "Kaelthar" }),
		}
		local pending, history = M().Split(recs, NOW)
		local ids = {}
		for _, r in ipairs(pending) do ids[#ids + 1] = r.id end
		deepEq(ids, { "00000002", "00000003", "00000001" })
		ids = {}
		for _, r in ipairs(history) do ids[#ids + 1] = r.id end
		deepEq(ids, { "00000005", "00000004" })
	end)

	it("an open application past its 14 days is history as expired, even before the sweep has written it", function()
		local old = rec("00000001", { at = NOW - 15 * DAY, upd = NOW - 15 * DAY })
		local v = view({ old })
		eq(v.pendingCount, 0)
		eq(#v.rows, 0)
		local h = view({ old }, { tab = "history" })
		eq(#h.rows, 1)
		eq(h.rows[1].status.text, "EXPIRED")
		eq(h.rows[1].kind, "history")
		eq(h.counters.expired, 1)
	end)

	it("exactly 14 days is expired, 13 days 23 hours is still pending", function()
		eq(view({ rec("00000001", { at = NOW - 14 * DAY }) }).pendingCount, 0)
		eq(view({ rec("00000001", { at = NOW - 14 * DAY + 3600 }) }).pendingCount, 1)
	end)

	it("the counters: pending, and every closed state apart", function()
		local recs = {
			rec("00000001"), rec("00000002"), rec("00000003"),
			rec("00000004", { state = "accepted", stateRev = 3 }), rec("00000005", { state = "accepted", stateRev = 3 }),
			rec("00000006", { state = "declined", stateRev = 3 }), rec("00000007", { state = "withdrawn", stateRev = 3 }),
			rec("00000008", { state = "expired", stateRev = 3 }),
		}
		local c = M().Counters(recs, NOW)
		deepEq(c, { pending = 3, accepted = 2, declined = 1, withdrawn = 1, expired = 1, history = 5 })
		deepEq(M().Counters({}, NOW), { pending = 0, accepted = 0, declined = 0, withdrawn = 0, expired = 0, history = 0 })
		deepEq(M().Counters(nil, NOW), { pending = 0, accepted = 0, declined = 0, withdrawn = 0, expired = 0, history = 0 })
	end)

	it("the tab labels carry the count; the title and the empty state follow the tab", function()
		local recs = { rec("00000001"), rec("00000002") }
		local v = view(recs)
		eq(v.pendingLabel, "Pending (2)")
		eq(v.historyLabel, "History")
		eq(v.title, "Pending applications")
		eq(v.caption, "Applications expire after 14 days")
		eq(v.empty, nil)
		local e = view({})
		eq(e.empty.title, "No pending applications")
		eq(e.pendingLabel, "Pending (0)")
		local h = view({}, { tab = "history" })
		eq(h.title, "Recent history")
		eq(h.empty.title, "Nothing in the history yet")
		eq(view(recs, { tab = "nonsense" }).tab, "pending")
	end)
end)

describe("a pending row", function()
	it("class, level, race, item level, roles and how long ago, as in mockup 04", function()
		local v = view({ rec("00000001", { ilvl = 41, roles = 8 }) })
		local r = v.rows[1]
		eq(r.kind, "pending")
		eq(r.name, "Elarin")
		eq(r.who, "Elarin-TestRealm")
		eq(r.cls, "MAGE")
		eq(r.classLabel, "Mage")
		eq(r.classLine, "Mage · Level 32 · Troll")
		eq(r.ilvlText, "iLvl 41")
		eq(r.ageText, "2 h ago")
		deepEq(r.roles, { { key = "ranged", label = "Ranged DPS" } })
		eq(r.status.text, "RECEIVED")
		eq(r.status.kind, "ok")
	end)

	it("no item level reads 'iLvl —'; no roles ticked is an empty list; an unknown race shows its number", function()
		local r = view({ rec("00000001", { ilvl = "nil", roles = "nil", race = 99 }) }).rows[1]
		eq(r.ilvlText, "iLvl —")
		deepEq(r.roles, {})
		eq(r.classLine, "Mage · Level 32 · Race 99")
	end)

	it("several roles are listed in role order", function()
		local r = view({ rec("00000001", { cls = 11, roles = 1 + 2 + 8 }) }).rows[1]
		local keys = {}
		for _, role in ipairs(r.roles) do keys[#keys + 1] = role.key end
		deepEq(keys, { "tank", "healer", "ranged" })
	end)

	it("the race name comes from the client when it knows it", function()
		_G.C_CreatureInfo = _G.C_CreatureInfo or {}
		_G.C_CreatureInfo.GetRaceInfo = function(id) return { raceName = "Trollo", clientFileString = "Troll", raceID = id } end
		eq(view({ rec("00000001") }).rows[1].classLine, "Mage · Level 32 · Trollo")
		_G.C_CreatureInfo.GetRaceInfo = nil
	end)

	it("the status: RECEIVED while young, then how long it still has, amber when little is left", function()
		local function tag(ageDays)
			local at = NOW - ageDays * DAY
			local r = view({ rec("00000001", { at = at, upd = at }) }).rows[1]
			return r.status.text, r.status.kind
		end
		deepEq({ tag(1) }, { "RECEIVED", "ok" })
		deepEq({ tag(3) }, { "EXPIRES IN 11 DAYS", "default" })
		deepEq({ tag(10) }, { "EXPIRES IN 4 DAYS", "default" })
		deepEq({ tag(11) }, { "EXPIRES IN 3 DAYS", "gold" })
		deepEq({ tag(13) }, { "EXPIRES IN 1 DAY", "gold" })
		deepEq({ tag(13.5) }, { "EXPIRES IN 1 DAY", "gold" })
	end)

	it("an application the officer has not seen is NEW; without a last visit nothing is", function()
		local recs = { rec("00000001", { at = NOW - 7200, upd = NOW - 7200 }), rec("00000002", { at = NOW - 5 * DAY, upd = NOW - 5 * DAY }) }
		local v = view(recs, { seenAt = NOW - DAY })
		eq(v.rows[1].new, true)
		eq(v.rows[2].new, false)
		eq(v.newCount, 1)
		local never = view(recs)
		eq(never.rows[1].new, false)
		eq(never.newCount, 0)
	end)

	it("Invite, Decline and Whisper are there; an invite being sent turns Invite and Decline off", function()
		local r = view({ rec("00000001") }).rows[1]
		eq(r.actions.invite.enabled, true)
		eq(r.actions.invite.label, "Invite")
		contains(r.actions.invite.tip, "normal guild invite")
		eq(r.actions.decline.enabled, true)
		eq(r.actions.whisper.enabled, true)
		local busy = view({ rec("00000001") }, { busy = { ["00000001"] = true } }).rows[1]
		eq(busy.inviting, true)
		eq(busy.status.text, "INVITING...")
		eq(busy.actions.invite.enabled, false)
		eq(busy.actions.decline.enabled, false)
		eq(busy.actions.whisper.enabled, true)
	end)

	it("after the fallback the button says Mark as invited", function()
		local r = view({ rec("00000001") }, { manual = { ["00000001"] = true } }).rows[1]
		eq(r.manual, true)
		eq(r.actions.invite.label, "Mark as invited")
		contains(r.actions.invite.tip, "Press Enter")
		eq(r.actions.invite.enabled, true)
	end)
end)

describe("a history row", function()
	-- noon of a day, in this computer's zone, so that the date reads the same everywhere
	local function day(d, m) return time({ year = 2026, month = m or 11, day = d, hour = 12 }) end

	it("accepted and declined say who decided and when", function()
		local recs = {
			rec("00000001", { state = "accepted", stateRev = 3, upd = day(5), by = "Lyryn", cls = 7, lvl = 41 }),
			rec("00000002", { state = "declined", stateRev = 3, upd = day(3), by = "Kaelthar", cls = 4, lvl = 12 }),
		}
		local rows = view(recs, { tab = "history", now = day(6) }).rows
		eq(rows[1].kind, "history")
		eq(rows[1].historyLine, "Elarin · Shaman 41")
		eq(rows[1].status.text, "ACCEPTED"); eq(rows[1].status.kind, "ok")
		eq(rows[1].byText, "by Lyryn · 5 Nov 2026")
		eq(rows[2].status.text, "DECLINED"); eq(rows[2].status.kind, "bad")
		eq(rows[2].byText, "by Kaelthar · 3 Nov 2026")
		eq(rows[1].actions.invite, nil)
		eq(rows[1].actions.whisper.enabled, true)
	end)

	it("withdrawn says by the player; expired says after 14 days", function()
		local recs = {
			rec("00000001", { state = "withdrawn", stateRev = 3, upd = day(1), cls = 5, lvl = 25 }),
			rec("00000002", { state = "expired", stateRev = 3, upd = day(2) }),
		}
		local rows = view(recs, { tab = "history", now = day(6) }).rows
		eq(rows[2].status.text, "WITHDRAWN"); eq(rows[2].status.kind, "default")
		eq(rows[2].byText, "by the player · 1 Nov 2026")
		eq(rows[1].status.text, "EXPIRED")
		eq(rows[1].byText, "after 14 days · 2 Nov 2026")
	end)

	it("an accepted record without an officer's name shows only the date", function()
		local rows = view({ rec("00000001", { state = "accepted", stateRev = 3, upd = day(5), by = "nil" }) }, { tab = "history", now = day(6) }).rows
		eq(rows[1].byText, "5 Nov 2026")
	end)

	it("a tombstone (withdrawn before it reached the officer) has a name and no details", function()
		local tomb = { id = "00000009", k = KEY, who = "Nym-TestRealm", state = "withdrawn", stateRev = 3, at = NOW - DAY, upd = NOW - DAY, tomb = true }
		local r = view({ tomb }, { tab = "history" }).rows[1]
		eq(r.name, "Nym")
		eq(r.cls, nil)
		eq(r.historyLine, "Nym")
		eq(r.classLine, "Details unknown: withdrawn before it reached you")
		eq(r.status.text, "WITHDRAWN")
		deepEq(r.roles, {})
	end)
end)

describe("the window of rows", function()
	it("clamps the offset and says which rows are in view", function()
		deepEq(M().Page(23, 0, 6), { offset = 0, first = 1, last = 6, max = 17 })
		deepEq(M().Page(23, 7, 6), { offset = 7, first = 8, last = 13, max = 17 })
		deepEq(M().Page(23, 99, 6), { offset = 17, first = 18, last = 23, max = 17 })
		deepEq(M().Page(23, -4, 6), { offset = 0, first = 1, last = 6, max = 17 })
		deepEq(M().Page(3, 2, 6), { offset = 0, first = 1, last = 3, max = 0 })
		deepEq(M().Page(0, 5, 6), { offset = 0, first = 0, last = 0, max = 0 })
		deepEq(M().Page("x", "y", nil), { offset = 0, first = 0, last = 0, max = 0 })
	end)
end)

describe("the notification options (read by the icon of M4.5)", function()
	it("are the three of SPEC-07 §6, on by default except 'only when pending'", function()
		local keys = {}
		for _, o in ipairs(M().OPTIONS) do keys[#keys + 1] = o.key end
		deepEq(keys, { "notifyIcon", "onlyWhenPending", "sound" })
		eq(M().GetOption("notifyIcon"), true)
		eq(M().GetOption("onlyWhenPending"), false)
		eq(M().GetOption("sound"), true)
		isNil(M().GetOption("nonsense"))
	end)

	it("a change is saved on the account, announced on the Bus, and kept", function()
		local heard = {}
		AzerothGuildFinder.Bus:On("NOTIFY_OPTIONS_CHANGED", function(key, value) heard[#heard + 1] = key .. "=" .. tostring(value) end)
		eq(M().SetOption("sound", false), true)
		eq(M().GetOption("sound"), false)
		eq(AzerothGuildFinder.Config:Get("account.settings.sound"), false)
		eq(M().SetOption("onlyWhenPending", true), true)
		eq(M().GetOption("onlyWhenPending"), true)
		deepEq(heard, { "sound=false", "onlyWhenPending=true" })
	end)

	it("an unknown key or a value that is not a boolean is refused and changes nothing", function()
		eq(M().SetOption("nonsense", true), false)
		eq(M().SetOption("sound", "no"), false)
		eq(M().SetOption("sound", nil), false)
		eq(M().GetOption("sound"), true)
	end)
end)
