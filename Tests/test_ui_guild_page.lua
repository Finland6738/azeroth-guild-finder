-- M2.7: the guild page (UI/GuildPage.lua) on the mock client: opening from a card and Back, the page drawn from the summary
-- alone and completed when the detail arrives (or says it is unavailable), the Discord copy field, the contacts and Whisper,
-- the "Looking for" card, activity times in the visitor's zone, members, requirements checked against the player, the
-- listing disappearing while the page is open, and scrolling. The mock player is Horde on "Test Realm", a level 60 Warrior
-- with no guild, so the window opens on Find a Guild.

local function A() return AzerothGuildFinder end
local function main() return A().Main end
local function page() return A().GuildPage end
local function catalog() return A().Catalog end
local function host() return main().hosts.GuildPage end
local function key(name) return "TestRealm|Horde|" .. name end
local function snack() return A().Widgets.Snackbar.Current() end

local function summary(name, extra)
	local t = { k = key(name), rev = 5, upd = GetServerTime() - 2 * 86400, first = 1760000000, own = "a1b2c3d4", sub = "Small-scale PvP",
		lang = 1 + 16, lang1 = 5, tags = { 6, 1, 5 }, pace = 2, days = 31, t0 = 1140, t1 = 1350, rec = 1, apps = true,
		want = { [5] = 2, [8] = 8, [1] = 1, [11] = 1 + 2 + 4 }, newb = true, minL = 20,
		st = { m = 149, a7 = 31, u7lo = 19, u7hi = 24, max = 12, cls = { [1] = 18, [8] = 14, [5] = 11 } }, srev = GetServerTime() - 3 * 3600 }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

local function detail(name, extra)
	local t = { k = key(name), rev = 5, desc = "Competitive guild focused on small-scale PvP.", disc = "aurora-it",
		cont = { "Lyryn", "Kaelthar" }, note = "Discord voice chat for raids" }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

local function put(name, extra) assert(catalog():PutSummary(summary(name, extra))) end
local function putDetail(name, extra) assert(catalog():PutDetail(detail(name, extra))) end

-- Opens the window on the list and then the page of `name`, the way a click on a card does.
local function open(name)
	main():Show()
	A().Browse:OpenGuild(key(name))
	return host()
end

local function texts(frames, getter)
	local out = {}
	for i, f in ipairs(frames) do if f:IsShown() then out[#out + 1] = getter(f) end end
	return out
end

local function shownTags(h)
	return texts(h.tags, function(t) return t:GetText() end)
end

local function icon(tex) return tex:GetTexture():match("glyph_%a+") end

local function contactRows(h)
	local out = {}
	for _, row in ipairs(h.contactRows) do if row:IsShown() then out[#out + 1] = row end end
	return out
end

describe("opening", function()
	it("a card opens the page on the Find a Guild tab, titled with the guild's name, and Back returns", function()
		put("Aurora")
		main():Show()
		A().Browse:OpenGuild(key("Aurora"))
		eq(main():CurrentTab(), "FindGuild")
		eq(main():CurrentPage(), "GuildPage")
		eq(main().title:GetText(), "Aurora")
		truthy(main().backButton:IsShown())
		truthy(host().content:IsShown())
		main():Back()
		eq(main():CurrentPage(), "FindGuild")
		falsy(host() and host().shown)
		eq(#Mock.errors, 0)
	end)

	it("Back keeps what was typed in the search box and the list's place", function()
		put("Aurora"); put("Borealis")
		main():Show()
		local list = main().hosts.FindGuild
		Mock.TypeInto(list.search.edit, "aur")
		A().Browse.debounce:Flush()
		main():Push("GuildPage", { k = key("Aurora") })
		main():Back()
		eq(list.search:GetText(), "aur")
		eq(A().Browse.search, "aur")
	end)

	it("the Apply button is not there until the applications exist", function()
		put("Aurora")
		putDetail("Aurora")
		local h = open("Aurora")
		local function scan(frame)
			if frame.GetLabel then
				local label = frame:GetLabel()
				falsy(label:find("Apply"), "no Apply button yet")
			end
			for _, child in ipairs(frame._children or {}) do scan(child) end
		end
		scan(h.left)
		scan(h.content)
	end)

	it("opening one guild after another shows the second, not the first", function()
		put("Aurora"); put("Borealis", { sub = "Quiet evenings" })
		open("Aurora")
		main():Back()
		local h = open("Borealis")
		eq(h.name:GetText(), "Borealis")
		eq(h.sub:GetText(), "Quiet evenings")
		eq(main().title:GetText(), "Borealis")
	end)
end)

describe("the summary alone", function()
	it("draws the left page: name, subtitle and tags; the Discord field and the contacts wait for the detail", function()
		put("Aurora")
		local h = open("Aurora")
		eq(h.name:GetText(), "Aurora")
		eq(h.sub:GetText(), "Small-scale PvP")
		local tags = shownTags(h)
		eq(tags[1], "ITALIAN"); eq(tags[2], "ENGLISH"); eq(tags[3], "HORDE"); eq(tags[4], "SOFTCORE")
		falsy(h.copy:IsShown())
		eq(#contactRows(h), 0)
		truthy(h.detailMsg:IsShown())
		eq(h.detailMsg:GetText(), "Loading details...")
		eq(h.contactTitle:GetText(), "CONTACT")
		eq(h.footer:GetText():match("^Listed since %d+ %a+ %d+ · Updated 2 days ago$") ~= nil, true)
		eq(#Mock.errors, 0)
	end)

	it("draws the right page: About says it is loading, everything from the summary is complete", function()
		put("Aurora", { minL = 20 })
		local h = open("Aurora")
		eq(h.about.text:GetText(), "Loading details...")
		-- looking for
		eq(h.look.status:GetText(), "RECRUITING")
		eq(h.look.items[1].name:GetText(), "Warrior")
		eq(h.look.items[3].name:GetText(), "Mage")
		eq(#texts(h.look.items, function(i) return i end), 4)
		-- members
		eq(h.members.cells.active.n:GetText(), "31")
		eq(h.members.cells.unique.n:GetText(), "19–24")
		eq(h.members.cells.total.n:GetText(), "149")
		eq(h.members.cells.max.n:GetText(), "12")
		eq(h.members.updated:GetText(), "updated 3 h ago")
		eq(#texts(h.members.segments, function(s) return s end), 3)
		-- activity
		eq(h.activity.pace:GetText(), "SOFTCORE")
		local acts = texts(h.activity.acts, function(t) return t:GetText() end)
		eq(acts[1], "1  World PvP"); eq(acts[3], "3  Battlegrounds")
		eq(h.activity.days:GetMask(), 31)
		-- requirements: the level only, the note needs the detail
		local rows = texts(h.reqs.rows, function(r) return r end)
		eq(#rows, 2)
		eq(rows[1].text:GetText(), "Level 20+")
		-- how applying works
		truthy(h.how.text:GetText():find("Apply sends your character"))
		eq(#Mock.errors, 0)
	end)

	it("asks the network for the detail once, and not when it is cached", function()
		put("Aurora")
		local asked = {}
		A().Sync.RequestDetail = function(_, k) asked[#asked + 1] = k return true, "requested" end
		open("Aurora")
		eq(#asked, 1); eq(asked[1], key("Aurora"))
		main():Back()
		putDetail("Aurora")
		open("Aurora")
		eq(#asked, 1)   -- a cached detail needs no request
	end)

	it("asks again when the cached detail is older than the summary", function()
		put("Aurora", { rev = 7 })
		putDetail("Aurora", { rev = 5 })
		local asked = 0
		A().Sync.RequestDetail = function() asked = asked + 1 return true, "requested" end
		local h = open("Aurora")
		eq(asked, 1)
		eq(h.about.text:GetText(), "Competitive guild focused on small-scale PvP.")   -- the old text meanwhile
	end)

	it("a listing that exists only on this computer has nobody to ask: unavailable at once", function()
		assert(catalog():PutSummary(summary("Fake"), { localOnly = true }))
		local asked = 0
		A().Sync.RequestDetail = function() asked = asked + 1 return true end
		local h = open("Fake")
		eq(asked, 0)
		eq(h.about.text:GetText(), "Details unavailable right now (no one who has them is online)")
	end)
end)

describe("when the detail arrives", function()
	it("completes the page that is open: description, Discord field, contacts, note", function()
		put("Aurora")
		local h = open("Aurora")
		falsy(h.copy:IsShown())
		putDetail("Aurora")
		eq(h.about.text:GetText(), "Competitive guild focused on small-scale PvP.")
		truthy(h.copy:IsShown())
		eq(h.copy:GetValue(), "https://discord.gg/aurora-it")
		eq(h.copy.edit:GetText(), "https://discord.gg/aurora-it")
		falsy(h.detailMsg:IsShown())
		local rows = contactRows(h)
		eq(#rows, 2)
		eq(rows[1].name:GetText(), "Lyryn")
		eq(rows[2].name:GetText(), "Kaelthar")
		local req = texts(h.reqs.rows, function(r) return r end)
		eq(#req, 3)
		eq(req[3].text:GetText(), "\"Discord voice chat for raids\"")
		eq(#Mock.errors, 0)
	end)

	it("a detail for another guild changes nothing", function()
		put("Aurora"); put("Borealis")
		local h = open("Aurora")
		putDetail("Borealis")
		eq(h.about.text:GetText(), "Loading details...")
		falsy(h.copy:IsShown())
	end)

	it("the Discord field selects all and says to press Ctrl+C", function()
		put("Aurora"); putDetail("Aurora")
		local h = open("Aurora")
		Mock.RunScript(h.copy.button, "OnClick", "LeftButton")
		eq(snack(), "Selected. Press Ctrl+C to copy.")
		-- what the player types is undone
		Mock.TypeInto(h.copy.edit, "x")
		eq(h.copy.edit:GetText(), "https://discord.gg/aurora-it")
	end)

	it("a guild without a Discord code or contacts says so", function()
		put("Aurora"); putDetail("Aurora", { disc = "nil", cont = "nil", note = "nil" })
		local h = open("Aurora")
		falsy(h.copy:IsShown())
		eq(#contactRows(h), 0)
		eq(h.detailMsg:GetText(), "No Discord link. No contact characters listed.")
		eq(#texts(h.reqs.rows, function(r) return r end), 2)   -- no note row
	end)

	it("a guild without a description says so", function()
		put("Aurora"); putDetail("Aurora", { desc = "nil" })
		eq(open("Aurora").about.text:GetText(), "This guild has not written a description.")
	end)

	it("a text with a pipe cannot make a colour code (the pipe is doubled by the catalog)", function()
		put("Aurora"); putDetail("Aurora", { desc = "Be |cffff0000red|r" })
		local h = open("Aurora")
		eq(h.about.text:GetText(), "Be ||cffff0000red||r")
	end)
end)

describe("details unavailable", function()
	it("after the wait the page says so and the other sections stay", function()
		put("Aurora")
		local h = open("Aurora")
		A().Bus:Emit("DETAIL_UNAVAILABLE", key("Aurora"))
		eq(h.about.text:GetText(), "Details unavailable right now (no one who has them is online)")
		eq(h.detailMsg:GetText(), "Details unavailable right now (no one who has them is online)")
		eq(h.members.cells.active.n:GetText(), "31")
		eq(h.look.items[1].name:GetText(), "Warrior")
	end)

	it("a late detail completes the page after all", function()
		put("Aurora")
		local h = open("Aurora")
		A().Bus:Emit("DETAIL_UNAVAILABLE", key("Aurora"))
		putDetail("Aurora")
		eq(h.about.text:GetText(), "Competitive guild focused on small-scale PvP.")
		truthy(h.copy:IsShown())
	end)

	it("the real request: no answer for 20 seconds gives 'unavailable', and opening the page again asks again", function()
		put("Aurora")
		local h = open("Aurora")
		eq(h.about.text:GetText(), "Loading details...")
		Mock.Advance(21)
		eq(h.about.text:GetText(), "Details unavailable right now (no one who has them is online)")
		main():Back()
		h = open("Aurora")
		eq(h.about.text:GetText(), "Loading details...")   -- the flag is cleared and a new request runs
	end)

	it("a flag for another guild is not shown on this page", function()
		put("Aurora"); put("Borealis")
		local h = open("Aurora")
		A().Bus:Emit("DETAIL_UNAVAILABLE", key("Borealis"))
		eq(h.about.text:GetText(), "Loading details...")
	end)
end)

describe("contacts", function()
	it("a contact heard announcing recently has a green dot", function()
		put("Aurora"); putDetail("Aurora")
		A().Sync.Contacts = function(_, k, maxAge) eq(maxAge, 3600) return { "Kaelthar-TestRealm" } end
		local h = open("Aurora")
		local rows = contactRows(h)
		falsy(rows[1].online)
		truthy(rows[2].online)
	end)

	it("Whisper opens the chat box on '/w Name '", function()
		put("Aurora"); putDetail("Aurora")
		local typed
		_G.ChatFrame_OpenChat = function(text) typed = text end
		local h = open("Aurora")
		Mock.RunScript(contactRows(h)[2].button, "OnClick", "LeftButton")
		eq(typed, "/w Kaelthar ")
		eq(#Mock.errors, 0)
	end)

	it("when the chat box cannot be opened the player is told what to type", function()
		put("Aurora"); putDetail("Aurora")
		_G.ChatFrame_OpenChat = nil
		local h = open("Aurora")
		Mock.RunScript(contactRows(h)[1].button, "OnClick", "LeftButton")
		eq(snack(), "The chat box could not be opened. Type /w Lyryn")
	end)

	it("the whisper button names the character in its tooltip", function()
		put("Aurora"); putDetail("Aurora")
		local h = open("Aurora")
		eq(contactRows(h)[1].button.tooltipTitle, "Open the chat box to whisper Lyryn")
	end)
end)

describe("looking for", function()
	it("a Mage that is wanted is told so, with the role", function()
		put("Aurora")
		Mock.player.classFile, Mock.player.classId = "MAGE", 8
		local h = open("Aurora")
		truthy(h.look.you:IsShown())
		eq(h.look.you:GetText(), "They need your class: Mage · Ranged DPS")
	end)

	it("a Rogue is not wanted: no line", function()
		put("Aurora")
		Mock.player.classFile, Mock.player.classId = "ROGUE", 4
		falsy(open("Aurora").look.you:IsShown())
	end)

	it("the status tag follows the recruiting state", function()
		put("Aurora", { rec = 2 }); put("Borealis", { rec = 0 })
		local h = open("Aurora")
		eq(h.look.status:GetText(), "RECRUITING: SELECTED CLASSES ONLY")
		eq(h.look.status.kind, "gold")
		main():Back()
		h = open("Borealis")
		eq(h.look.status:GetText(), "RECRUITING CLOSED")
		eq(h.look.status.kind, "bad")
	end)

	it("any class has its own box; no preference gives the plain sentence", function()
		put("Aurora", { want = { [0] = 2 } }); put("Borealis", { want = "nil" })
		local h = open("Aurora")
		eq(h.look.items[1].name:GetText(), "Any class")
		falsy(h.look.items[1].icon:IsShown())
		falsy(h.look.none:IsShown())
		main():Back()
		h = open("Borealis")
		truthy(h.look.none:IsShown())
		eq(h.look.none:GetText(), "No class preference given")
	end)

	it("the legend names the four roles", function()
		put("Aurora")
		local h = open("Aurora")
		eq(h.look.legendTexts[1]:GetText(), "Tank")
		eq(h.look.legendTexts[2]:GetText(), "Healer")
		eq(h.look.legendTexts[3]:GetText(), "Melee DPS")
		eq(h.look.legendTexts[4]:GetText(), "Ranged DPS")
	end)

	it("each class box shows its role badges", function()
		put("Aurora")
		local h = open("Aurora")
		local druid = h.look.items[4]
		eq(druid.name:GetText(), "Druid")
		eq(#texts(druid.roleBadges, function(b) return b end), 3)
		eq(druid.roleBadges[1].role, "tank")
	end)
end)

describe("activity in the visitor's time", function()
	it("shows the local times and the UTC times smaller", function()
		put("Aurora", { days = 31, t0 = 1140, t1 = 1350 })
		A().BrowseModel.LocalOffset = function() return 60 end
		local h = open("Aurora")
		eq(h.activity.time:GetText(), "20:00–23:30")
		eq(h.activity.utc:GetText(), "19:00–22:30 UTC")
		truthy(h.activity.yourTime:IsShown())
		eq(h.activity.yourTime:GetText(), "your time")
	end)

	it("the days move with the start time across midnight", function()
		put("Aurora", { days = 31, t0 = 1380, t1 = 120 })
		A().BrowseModel.LocalOffset = function() return 120 end
		local h = open("Aurora")
		eq(h.activity.days:GetMask(), 2 + 4 + 8 + 16 + 32)
		eq(h.activity.time:GetText(), "01:00–04:00")
	end)

	it("all day: no 'your time' and no UTC line", function()
		put("Aurora", { t0 = 0, t1 = 0 })
		local h = open("Aurora")
		eq(h.activity.time:GetText(), "All day")
		falsy(h.activity.yourTime:IsShown())
		falsy(h.activity.utc:IsShown())
	end)

	it("a guild with no days and no times shows no empty rows", function()
		put("Aurora", { days = "nil", t0 = "nil", t1 = "nil" })
		local h = open("Aurora")
		falsy(h.activity.days:IsShown())
		falsy(h.activity.timeRow:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("the commitment tag explains itself in a tooltip", function()
		put("Aurora", { pace = 3 })
		local h = open("Aurora")
		eq(h.activity.pace:GetText(), "HARDCORE")
		eq(h.activity.pace.kind, "hard")
		Mock.RunScript(h.activity.pace, "OnEnter")
		eq(GameTooltip:GetText(), "Hardcore")
		truthy(GameTooltip._lines[1]:find("not permadeath"))
	end)
end)

describe("members", function()
	it("an exact count is one number; the unique players have a tooltip that says it is an estimate", function()
		put("Aurora", { st = { m = 10, a7 = 8, u7lo = 6, u7hi = 6 } })
		local h = open("Aurora")
		eq(h.members.cells.unique.n:GetText(), "6")
		Mock.RunScript(h.members.cells.unique, "OnEnter")
		eq(GameTooltip._lines[1], "Estimated: counted exactly among members who use the addon")
	end)

	it("no statistics: one sentence and no numbers", function()
		put("Aurora", { st = "nil" })
		local h = open("Aurora")
		truthy(h.members.unknown:IsShown())
		falsy(h.members.cells.active:IsShown())
		falsy(h.members.bar:IsShown())
	end)

	it("a newer announcement with fresh statistics redraws the open page", function()
		put("Aurora")
		local h = open("Aurora")
		eq(h.members.cells.active.n:GetText(), "31")
		assert(catalog():PutSummary(summary("Aurora", { st = { m = 150, a7 = 40, u7lo = 20, u7hi = 20 }, srev = GetServerTime() - 60 })))
		Mock.Advance(page().REFRESH_DELAY + 0.1)
		eq(h.members.cells.active.n:GetText(), "40")
		eq(h.members.cells.unique.n:GetText(), "20")
	end)
end)

describe("requirements against the player", function()
	before_boot(function(Mock) Mock.player.level = 32 end)

	it("a level that is met has a green check and the player's level", function()
		put("Aurora", { minL = 20 })
		local h = open("Aurora")
		local row = h.reqs.rows[1]
		truthy(row.icon:IsShown())
		eq(icon(row.icon), "glyph_check")
		eq(row.text:GetText(), "Level 20+")
		eq(row.you:GetText(), "(you are 32)")
	end)

	it("a level that is not met has a red cross", function()
		put("Aurora", { minL = 40 })
		local row = open("Aurora").reqs.rows[1]
		eq(icon(row.icon), "glyph_close")
		eq(row.text:GetText(), "Level 40+")
	end)

	it("no level or item level requirement is written as such", function()
		put("Aurora", { minL = "nil" })
		local h = open("Aurora")
		eq(h.reqs.rows[1].text:GetText(), "No level requirement")
		eq(h.reqs.rows[2].text:GetText(), "No item level requirement")
		falsy(h.reqs.rows[1].icon:IsShown())
		truthy(h.reqs.rows[1].dash:IsShown())
	end)

	it("an item level is checked when the client gives one", function()
		put("Aurora", { minL = "nil", minI = 100 })
		_G.GetAverageItemLevel = function() return 120, 118.4, 100 end
		local row = open("Aurora").reqs.rows[2]
		eq(icon(row.icon), "glyph_check")
		eq(row.text:GetText(), "Item level 100+")
		eq(row.you:GetText(), "(you have 118)")
	end)

	it("an item level the client does not give is not a failure", function()
		put("Aurora", { minL = "nil", minI = 100 })
		_G.GetAverageItemLevel = nil
		local row = open("Aurora").reqs.rows[2]
		falsy(row.icon:IsShown())
		eq(row.text:GetText(), "Item level 100+")
	end)
end)

describe("applications closed", function()
	it("says to use the contacts instead", function()
		put("Aurora", { apps = false })
		local h = open("Aurora")
		truthy(h.appsNote:IsShown())
		eq(h.appsNote:GetText(), "Applications via addon are closed. Use the contacts below.")
	end)

	it("is not shown when applications are open (the Apply button arrives with M4)", function()
		put("Aurora", { apps = true })
		falsy(open("Aurora").appsNote:IsShown())
	end)
end)

describe("a listing that goes away", function()
	it("while the page is open, it says so and shows nothing else", function()
		local chan = { sender = "Gm-TestRealm", dist = "CHANNEL" }
		assert(catalog():PutSummary(summary("Aurora"), chan))
		local h = open("Aurora")
		falsy(h.goneText:IsShown())
		assert(catalog():Delist(key("Aurora"), 5, chan))
		truthy(h.goneText:IsShown())
		falsy(h.view:IsShown())
		eq(h.name:GetText(), "Aurora")
		falsy(h.copy:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("a key that is not in the catalog at all opens the same message", function()
		main():Show()
		main():Push("GuildPage", { k = key("Nobody") })
		truthy(host().goneText:IsShown())
		eq(main().title:GetText(), "Nobody")
	end)

	it("a page opened with nothing does not break", function()
		main():Show()
		main():Push("GuildPage", {})
		eq(#Mock.errors, 0)
	end)
end)

describe("scrolling", function()
	it("scrolls when the content is taller than the window, clamped at both ends", function()
		put("Aurora")
		local h = open("Aurora")
		page().contentH = 1000
		page():SetOffset(0)
		truthy(h.bar:IsShown())
		page():ScrollBy(page().WHEEL_STEP)
		eq(page().offset, 64)
		page():ScrollBy(5000)
		eq(page().offset, 1000 - page().VIEW_H)
		page():ScrollBy(-9000)
		eq(page().offset, 0)
	end)

	it("a page that fits has no bar and does not move", function()
		put("Aurora")
		local h = open("Aurora")
		page().contentH = 300
		page():ScrollBy(500)
		eq(page().offset, 0)
		falsy(h.bar:IsShown())
	end)

	it("the wheel over the page and over a card scrolls it, and a new page starts at the top", function()
		put("Aurora"); put("Borealis")
		local h = open("Aurora")
		page().contentH = 1000
		Mock.RunScript(h.view, "OnMouseWheel", -1)
		eq(page().offset, 64)
		Mock.RunScript(h.look.items[1].icon, "OnMouseWheel", -1)
		eq(page().offset, 128)
		main():Back()
		open("Borealis")
		eq(page().offset, 0)
	end)
end)

describe("robustness", function()
	it("every kind of listing renders without an error, at the smallest and the biggest window", function()
		put("Minimal", { sub = "nil", want = "nil", st = "nil", days = "nil", t0 = "nil", t1 = "nil", minL = "nil", srev = "nil", first = "nil", upd = "nil", bg = "nil" })
		put("Full", { sub = string.rep("x", 60), want = { [1] = 1, [2] = 7, [3] = 8, [4] = 4, [5] = 10, [7] = 14, [8] = 8, [9] = 8, [11] = 15, [0] = 15 },
			tags = { 1, 2, 3 }, lang = 511, lang1 = 1, minI = 200 })
		putDetail("Full", { desc = string.rep("A long line of text. ", 24), cont = { "One", "Two", "Three" } })
		for _, scale in ipairs({ 0.6, 1.4 }) do
			main():SetScale(scale)
			for _, name in ipairs({ "Minimal", "Full" }) do
				open(name)
				eq(#Mock.errors, 0, name)
				main():Back()
			end
		end
	end)

	it("a class the mock player has that nobody wants and a player with no class at all", function()
		put("Aurora")
		Mock.player.classId = nil
		open("Aurora")
		eq(#Mock.errors, 0)
	end)

	it("the page is registered for every role's Find a Guild tab only through the list (no tab of its own)", function()
		eq(A().Nav.IsTab("GuildPage"), false)
		notNil(main().pages.GuildPage)
	end)
end)

describe("the development seed", function()
	it("gives two listings out of three a fake detail, the third has none (so both states can be seen)", function()
		eq(A().Seed:Run(6), 6)
		local with, without = 0, 0
		for _, sum in ipairs(catalog():List()) do
			if catalog():Get(sum.k).det then with = with + 1 else without = without + 1 end
		end
		eq(with, 4); eq(without, 2)
	end)

	it("a seeded guild opens with its fake detail, and one without says it is unavailable", function()
		A().Seed:Run(6)
		local sums = catalog():List()
		local withDet, noDet
		for _, sum in ipairs(sums) do
			if catalog():Get(sum.k).det then withDet = withDet or sum.k else noDet = noDet or sum.k end
		end
		main():Show()
		main():Push("GuildPage", { k = withDet })
		local h = host()
		truthy(h.copy:IsShown())
		truthy(h.copy:GetValue():find("^https://discord.gg/seed%-%d+$"))
		eq(#contactRows(h), 2)
		main():Back()
		main():Push("GuildPage", { k = noDet })
		eq(host().about.text:GetText(), "Details unavailable right now (no one who has them is online)")
		eq(#Mock.errors, 0)
	end)

	it("renders every one of 60 seeded guilds without an error", function()
		A().Seed:Run(60)
		main():Show()
		for _, sum in ipairs(catalog():List()) do
			main():Push("GuildPage", { k = sum.k })
			main():Back()
		end
		eq(#Mock.errors, 0)
	end)
end)
