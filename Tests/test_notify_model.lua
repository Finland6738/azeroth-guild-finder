-- M4.5: the view model of the notification icon (UI/NotifyModel.lua, SPEC-07 §6) as pure Lua: who sees the icon (role,
-- listing, options), the badge text, the pulse rule, the quick list of the last 5, which arrivals speak, the chat line and
-- its link, the right-click menu and the saved position.

local DAY = 86400
local KEY = "TestRealm|Horde|Aurora"
local NOW = 1767225600

local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })
local function M() return AzerothGuildFinder.NotifyModel end

local function rec(id, extra)
	local r = { id = id, k = KEY, state = "received", stateRev = 2, at = NOW - 2 * 3600, upd = NOW - 2 * 3600,
		who = "Elarin-TestRealm", cls = 8, race = 8, lvl = 32, roles = 8 }
	for k, v in pairs(extra or {}) do if v == "nil" then r[k] = nil else r[k] = v end end
	return r
end

local function ctx(extra)
	local c = { role = "officer", key = KEY, listed = true, enabled = true, onlyWhenPending = false, pending = 0 }
	for k, v in pairs(extra or {}) do c[k] = v end
	return c
end

describe("who sees the icon", function()
	it("the Guild Master and the officers of a listed guild do", function()
		eq(M().Visible(ctx{ role = "gm" }), true)
		eq(M().Visible(ctx{ role = "officer" }), true)
	end)

	it("a member and a character without a guild never do, whatever the options say", function()
		deepEq({ M().Visible(ctx{ role = "member", pending = 3 }) }, { false, "role" })
		deepEq({ M().Visible(ctx{ role = "none", key = false, pending = 3 }) }, { false, "role" })
		deepEq({ M().Visible(ctx{ role = "officer", key = false }) }, { false, "role" })
	end)

	it("a guild without a listing has no icon", function()
		deepEq({ M().Visible(ctx{ listed = false, pending = 2 }) }, { false, "listing" })
	end)

	it("the option turns it off", function()
		deepEq({ M().Visible(ctx{ enabled = false, pending = 2 }) }, { false, "off" })
	end)

	it("'only when something is pending' hides it at zero and shows it from one", function()
		deepEq({ M().Visible(ctx{ onlyWhenPending = true, pending = 0 }) }, { false, "idle" })
		eq(M().Visible(ctx{ onlyWhenPending = true, pending = 1 }), true)
		eq(M().Visible(ctx{ onlyWhenPending = false, pending = 0 }), true)
	end)
end)

describe("the badge", function()
	it("is empty at zero, the number, then 99+", function()
		eq(M().Badge(0), "")
		eq(M().Badge(-2), "")
		eq(M().Badge(nil), "")
		eq(M().Badge(1), "1")
		eq(M().Badge(99), "99")
		eq(M().Badge(100), "99+")
	end)

	it("pulses only when the count goes up", function()
		eq(M().Pulse(0, 1), true)
		eq(M().Pulse(3, 4), true)
		eq(M().Pulse(3, 3), false)
		eq(M().Pulse(3, 2), false)
		eq(M().Pulse(nil, 2), false)
	end)
end)

describe("the quick list", function()
	it("holds the last 5 pending, newest first, with the rest counted", function()
		local recs = {}
		for i = 1, 7 do recs[i] = rec(("%08d"):format(i), { who = "P" .. i .. "-TestRealm", at = NOW - (8 - i) * 3600 }) end
		local view = M().Quick({ recs = recs, now = NOW, guild = "Aurora" }, L)
		eq(#view.rows, 5)
		eq(view.total, 7)
		eq(view.more, 2)
		eq(view.moreText, "and 2 more")
		eq(view.rows[1].name, "P7")
		eq(view.rows[5].name, "P3")
		eq(view.guild, "Aurora")
		eq(view.empty, nil)
	end)

	it("leaves out what is decided or expired and shows an empty state", function()
		local recs = { rec("00000001", { state = "declined" }), rec("00000002", { at = NOW - 15 * DAY, upd = NOW - 15 * DAY }),
			rec("00000003", { state = "accepted" }) }
		local view = M().Quick({ recs = recs, now = NOW }, L)
		eq(#view.rows, 0)
		eq(view.empty, "No pending applications.")
		eq(view.more, 0)
	end)

	it("a row has the name, the class line, Invite and Decline", function()
		local view = M().Quick({ recs = { rec("00000001") }, now = NOW }, L)
		local row = view.rows[1]
		eq(row.name, "Elarin")
		eq(row.line, "Mage 32 · 2 h ago")
		eq(row.actions.invite.enabled, true)
		eq(row.actions.decline.enabled, true)
	end)

	it("an invite being sent cannot be pressed again", function()
		local view = M().Quick({ recs = { rec("00000001") }, now = NOW, busy = { ["00000001"] = true } }, L)
		eq(view.rows[1].actions.invite.enabled, false)
		eq(view.rows[1].actions.decline.enabled, false)
	end)
end)

describe("which arrivals speak", function()
	it("a new open application of the own guild says it in chat", function()
		eq(M().Alert(KEY, "1", "received", nil, nil, KEY), "chat")
	end)

	it("a copy that comes from another officer's sync or a sweep moves the badge in silence", function()
		eq(M().Alert(KEY, "1", "received", nil, "sync", KEY), "silent")
		eq(M().Alert(KEY, "1", "received", nil, "sweep", KEY), "silent")
	end)

	it("a change of an existing record, a closed one or another guild's is nothing", function()
		eq(M().Alert(KEY, "1", "declined", "received", nil, KEY), nil)
		eq(M().Alert(KEY, "1", "declined", nil, nil, KEY), nil)
		eq(M().Alert("TestRealm|Horde|Other", "1", "received", nil, nil, KEY), nil)
		eq(M().Alert(KEY, "1", "received", nil, nil, nil), nil)
	end)
end)

describe("the chat line", function()
	it("names the applicant, the class and the level and ends with the Open link", function()
		local full, text, link = M().ChatLine(rec("00000001"), L)
		eq(text, "New application from Elarin (Mage 32).")
		contains(link, "|Haddon:AzerothGuildFinder:applications|h")
		contains(link, "[Open]")
		eq(full, text .. " " .. link)
	end)

	it("copes with a record without class or level", function()
		local _, text = M().ChatLine(rec("00000001", { cls = "nil", lvl = "nil" }), L)
		eq(text, "New application from Elarin.")
	end)

	it("recognises only its own link", function()
		eq(M().ParseLink(M().LINK), true)
		eq(M().ParseLink("addon:Other:thing"), false)
		eq(M().ParseLink(nil), false)
	end)
end)

describe("the right-click menu", function()
	it("has the four entries of mockup 05 with the state of each switch", function()
		local items = M().Menu({ locked = true, onlyWhenPending = false, sound = true }, L)
		eq(#items, 5)
		eq(items[1].kind, "title")
		eq(items[2].key, "lock")
		eq(items[2].checked, true)
		eq(items[3].key, "onlyWhenPending")
		eq(items[3].checked, false)
		eq(items[4].key, "sound")
		eq(items[4].checked, true)
		eq(items[5].key, "hide")
		eq(items[5].hint, "/gf notify")
	end)
end)

describe("the saved position", function()
	it("round-trips and refuses a damaged one", function()
		local saved = M().ToSaved("TOPLEFT", "BOTTOMLEFT", 10, -20)
		deepEq({ M().FromSaved(saved) }, { "TOPLEFT", "BOTTOMLEFT", 10, -20 })
		eq(M().ToSaved(nil, nil, 1, 1), nil)
		eq(M().FromSaved({ point = 3 }), nil)
		eq(M().FromSaved(nil), nil)
	end)

	it("a position off the screen is pulled back and a damaged one becomes the default", function()
		local pos = M().Clamp({ point = "CENTER", relPoint = "CENTER", x = 99999, y = -99999 }, 60, 1920, 1080)
		-- the whole icon (60 px, the badge 6 px out at the right and 4 at the top, 8 px margin) is kept on the screen
		eq(pos.x, 916)
		eq(pos.y, -502)
		local top = M().Clamp({ point = "CENTER", relPoint = "CENTER", x = -99999, y = 99999 }, 60, 1920, 1080)
		eq(top.x, -922)
		eq(top.y, 1080 / 2 - 8 - 30 - 4)
		local ok = { point = "CENTER", relPoint = "CENTER", x = 100, y = 50 }
		eq(M().Clamp(ok, 60, 1920, 1080), ok)
		eq(M().Clamp("junk", 60, 1920, 1080), M().DEFAULT_POS)
	end)
end)
