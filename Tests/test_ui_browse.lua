-- M2.5: the Find a Guild page (UI/Browse.lua) on the mock client: the states, the search, the cards, the virtual scroll
-- with 500 listings, the reaction to catalog changes, and /gf debug seed (Data/Seed.lua). The mock player is Horde on
-- "Test Realm", a level 60 Warrior with no guild, so the window opens on Find a Guild.

local function main() return AzerothGuildFinder.Main end
local function browse() return AzerothGuildFinder.Browse end
local function catalog() return AzerothGuildFinder.Catalog end
local function host() return main().hosts.FindGuild end
local function sync() return AzerothGuildFinder.Sync end
local function key(name) return "TestRealm|Horde|" .. name end

local function listing(name, extra)
	local t = { k = key(name), rev = 1, upd = GetServerTime() - 86400, first = 1766000000, own = "a1b2c3d4", sub = "Friendly raiders",
		lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 31, t0 = 1200, t1 = 1380, rec = 1, apps = true,
		want = { [0] = 8 }, newb = true, minL = 20, st = { m = 149, a7 = 31 } }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

local function put(name, extra) return catalog():PutSummary(listing(name, extra)) end

-- A character that never chose has "Recruiting only" on (SPEC-05 §2); these tests are about the list, so they start with
-- every filter off. The filters themselves are tested in test_ui_filters.lua and test_filter_model.lua.
local function open()
	main():Show()
	AzerothGuildFinder.FilterPanel.Controller():Reset()
	return host()
end

local function visibleRows()
	local out = {}
	for slot, row in pairs(browse().rows) do
		if row:IsShown() then out[#out + 1] = row end
	end
	table.sort(out, function(a, b) return a.index < b.index end)
	return out
end

local function shownNames()
	local out = {}
	for _, row in ipairs(visibleRows()) do out[#out + 1] = row.name:GetText() end
	return out
end

local function type_(text)
	Mock.TypeInto(host().search.edit, text)
end

describe("the page", function()
	it("is the Find a Guild tab: built at the first opening, on the right page of the book", function()
		local h = open()
		eq(main():CurrentTab(), "FindGuild")
		notNil(h)
		eq(h.content:GetParent(), main().contentArea)
		truthy(h.search:IsShown())
		eq(h.sorted:GetText(), "Sorted A-Z")
		eq(#Mock.errors, 0)
	end)

	it("the left page holds the filters: the plate says how many are on (only 'Recruiting' at the first opening)", function()
		main():Show()
		local h = host()
		eq(h.plate.text:GetText(), "Filters · 1 active")
		eq(browse().left, h.left)
		eq(AzerothGuildFinder.FilterPanel.panel.frame, h.left)
	end)

	it("the search box is a field with the placeholder of the mockup", function()
		local h = open()
		eq(h.search.placeholder:GetText(), "Search guild name...")
		eq(h.search:GetText(), "")
	end)
end)

describe("states", function()
	it("an empty catalog with nobody around says so, without a count", function()
		local h = open()
		truthy(h.stateBox:IsShown())
		falsy(h.list:IsShown())
		eq(h.stateBox.message:GetText(), "No other Guild Finder users online right now. Listings will appear as they come online.")
		eq(h.count:GetText(), "")
		falsy(h.stateBox.reset:IsShown())
		falsy(h.stateBox.ring:IsShown(), "no spinner")
	end)

	it("an empty catalog while a sync runs shows the spinner and the wait message", function()
		sync().state.req = { rounds = 1 }
		local h = open()
		eq(h.stateBox.message:GetText(), "Looking for guilds... this can take a minute the first time")
		truthy(h.stateBox.ring:IsShown())
		truthy(h.stateBox.spin:IsShown())
	end)

	it("the spinner turns while it is shown", function()
		sync().state.req = { rounds = 1 }
		local h = open()
		local before = { h.stateBox.dot:GetPoint(1) }
		Mock.Advance(0.5)
		local after = { h.stateBox.dot:GetPoint(1) }
		ne(before[4], after[4], "the dot moved along the ring")
	end)

	it("an empty catalog with peers around is the empty realm", function()
		sync().state.peers[1234] = GetTime()
		local h = open()
		contains(h.stateBox.message:GetText(), "No guild has published a listing")
	end)

	it("a search with no match names the search and has no reset button", function()
		put("Night Watch")
		local h = open()
		type_("zzzz")
		Mock.Advance(0.3)
		truthy(h.stateBox:IsShown())
		eq(h.stateBox.message:GetText(), 'No guild name contains "zzzz"')
		falsy(h.stateBox.reset:IsShown())
		eq(h.count:GetText(), "0 of 1 guild")
	end)

	it("filters with no match show the message and the Reset filters button, which resets and brings the list back", function()
		put("Night Watch")
		put("Aurora", { own = "b1b2b3b4" })
		local h = open()
		local resets = 0
		local active = true
		browse():SetFilter(function() return not active end, 2, function() resets = resets + 1; active = false end)
		eq(h.stateBox.message:GetText(), "No guild matches your filters")
		truthy(h.stateBox.reset:IsShown())
		eq(h.stateBox.reset:GetLabel(), "Reset filters")
		Mock.RunScript(h.stateBox.reset, "OnClick", "LeftButton")
		eq(resets, 1)
		falsy(h.stateBox:IsShown())
		truthy(h.list:IsShown())
		eq(#visibleRows(), 2)
	end)

	it("the list shows when there is something to show; the state box goes away", function()
		put("Night Watch")
		local h = open()
		falsy(h.stateBox:IsShown())
		truthy(h.list:IsShown())
		eq(h.count:GetText(), "1 guild")
	end)

	it("the hint appears under the box for 1-2 letters and leaves the list alone", function()
		put("Night Watch"); put("Aurora", { own = "b1b2b3b4" })
		local h = open()
		eq(h.hint:GetText(), "")
		type_("au")
		Mock.Advance(0.3)
		eq(h.hint:GetText(), "Type at least 3 letters")
		eq(#visibleRows(), 2, "not narrowed")
		type_("aur")
		Mock.Advance(0.3)
		eq(h.hint:GetText(), "")
		eq(#visibleRows(), 1)
	end)
end)

describe("search", function()
	local function fill()
		for i, n in ipairs({ "Ördine del Drago", "Ordine Cremisi", "Night Watch", "Aurora" }) do put(n, { own = ("%08x"):format(i) }) end
	end

	it("waits 250 ms after the last key, then narrows the list and the count", function()
		fill()
		local h = open()
		eq(h.count:GetText(), "4 guilds")
		type_("ordin")
		Mock.Advance(0.2)
		eq(#visibleRows(), 4, "too early")
		type_("ordine")
		Mock.Advance(0.2)
		eq(#visibleRows(), 4, "the wait restarts with every key")
		Mock.Advance(0.1)
		eq(#visibleRows(), 2)
		eq(h.count:GetText(), "2 of 4 guilds")
		deepEq(shownNames(), { "Ordine Cremisi", "Ördine del Drago" })
	end)

	it("Enter applies it at once and the clear button brings everything back at once", function()
		fill()
		local h = open()
		type_("aurora")
		Mock.RunScript(h.search.edit, "OnEnterPressed")
		eq(#visibleRows(), 1)
		h.search:Clear()
		eq(#visibleRows(), 4, "an empty box needs no wait")
		eq(h.count:GetText(), "4 guilds")
	end)

	it("a new search starts at the top of the list", function()
		browse().offset = 0
		for i = 1, 40 do put("Guild " .. i .. " Ordine", { own = ("%08x"):format(i) }) end
		local h = open()
		browse():SetOffset(2000)
		truthy(browse().offset > 0)
		type_("ordine")
		Mock.Advance(0.3)
		eq(browse().offset, 0)
		eq(visibleRows()[1].index, 1)
	end)
end)

describe("cards", function()
	local function card(name, extra)
		put(name, extra)
		open()
		Mock.Advance(0.5)   -- a window that was already open rebuilds after the throttle
		return visibleRows()[1]
	end

	it("show the name, the subtitle, the tags and the info band of a listing", function()
		local row = card("Aurora", { lang1 = 5, lang = 1 + 16, pace = 2, days = 31, t0 = 1200, t1 = 1380, tags = { 6, 1, 5 },
			st = { m = 149, a7 = 31 }, minL = 20, want = { [5] = 2, [8] = 8 } })
		eq(row.name:GetText(), "Aurora")
		eq(row.sub:GetText(), "Friendly raiders")
		local tags = {}
		for _, t in ipairs(row.tags) do if t:IsShown() then tags[#tags + 1] = t:GetText() end end
		deepEq(tags, { "IT", "EN", "SOFTCORE" })
		eq(row.members:GetText(), "31 active / 149")
		eq(row.activities:GetText(), "World PvP · Raids · Battlegrounds")
		eq(row.days:GetText(), "Mon–Fri")
		eq(row.time:GetText(), "20:00–23:00")
		eq(row.req:GetText(), "Level 20+")
		eq(row.want:GetText(), "Looking for")
		eq(row.updated:GetText(), "Updated yesterday")
		truthy(row.classIcons[1]:IsShown() and row.classIcons[2]:IsShown())
		falsy(row.classIcons[3]:IsShown())
		eq(row.classIcons[1].class, "PRIEST")
		eq(row.classIcons[2].class, "MAGE")
	end)

	it("a level 60 player meets a level 20 requirement: check mark, no warning tag", function()
		local row = card("Aurora", { minL = 20, want = { [1] = 1 } })
		truthy(row.reqIcon:IsShown())
		eq(row.reqIcon:GetTexture():match("glyph_%a+"), "glyph_check")
	end)

	it("'looking for your class' appears for the player's class (a Warrior)", function()
		local row = card("Aurora", { want = { [1] = 1, [8] = 8 } })
		local found
		for _, t in ipairs(row.tags) do if t:IsShown() and t:GetText() == "Looking for your class" then found = t end end
		notNil(found)
		eq(found.kind, "ok")
	end)

	it("a listing 15 days after its last announcement says 'May be inactive'", function()
		put("Aurora")
		Mock.StepClock(15 * 86400)
		open()
		local texts = {}
		for _, t in ipairs(visibleRows()[1].tags) do if t:IsShown() then texts[#texts + 1] = t:GetText() end end
		contains(texts, "May be inactive")
	end)

	it("a listing 31 days after its last announcement is gone from the list", function()
		put("Aurora")
		Mock.StepClock(31 * 86400)
		open()
		eq(#visibleRows(), 0)
		eq(browse().state.kind, "nopeers")
	end)

	it("no class wanted and a listing without statistics read plainly", function()
		local row = card("Aurora", { want = "nil", st = "nil", minL = "nil", t0 = "nil", t1 = "nil" })
		eq(row.members:GetText(), "Members unknown")
		eq(row.want:GetText(), "No class preference given")
		eq(row.req:GetText(), "No requirements")
		falsy(row.reqIcon:IsShown())
		eq(row.time:GetText(), "")
	end)

	it("any class is written out, and more than four classes end with +N", function()
		local any = card("Aurora", { want = { [0] = 2 } })
		eq(any.want:GetText(), "Looking for any class")
		catalog():Clear()
		local many = card("Aurora", { want = { [1] = 1, [5] = 2, [8] = 8, [9] = 8, [11] = 4 } })
		eq(many.more:GetText(), "+1")
		truthy(many.more:IsShown())
		truthy(many.classIcons[4]:IsShown())
	end)

	it("the emblem is a placeholder (M3.6) and the banner is hidden while its fileID is unknown", function()
		local row = card("Aurora", { bg = 3 })
		notNil(row.emblem)
		falsy(row.banner:IsShown())
		falsy(row.fade:IsShown())
	end)

	it("the banner is the client's own image by fileID when the registry knows it", function()
		AzerothGuildFinder.Assets.BANNERS[3] = { file = 1234567 }
		local row = card("Aurora", { bg = 3 })
		truthy(row.banner:IsShown())
		eq(row.banner:GetTexture(), 1234567)
		truthy(row.fade:IsShown())
		AzerothGuildFinder.Assets.BANNERS[3] = nil
	end)

	it("a row has a tooltip with the description and the requirement", function()
		local row = card("Aurora", { minL = 20 })
		eq(row.tooltip.title, "Aurora")
		eq(row.tooltip.lines[1], "Friendly raiders")
		eq(row.tooltip.lines[2].text, "Level 20+")
		Mock.RunScript(row, "OnEnter")
		eq(GameTooltip:GetText(), "Aurora")
		eq(GameTooltip._lines[1], "Friendly raiders")
		truthy(GameTooltip:IsShown())
		Mock.RunScript(row, "OnLeave")
		falsy(GameTooltip:IsShown())
	end)

	it("a click on a card opens its guild page and Back returns to the list", function()
		local row = card("Aurora")
		Mock.RunScript(row, "OnMouseUp", "LeftButton")
		eq(main():CurrentPage(), "GuildPage")
		eq(AzerothGuildFinder.GuildPage.k, key("Aurora"))
		main():Back()
		eq(main():CurrentPage(), "FindGuild")
	end)
end)

describe("requirements of a low level player", function()
	before_boot(function(Mock) Mock.player.level = 30 end)

	it("failed requirements show the red tag, the 'you are' text and the cross", function()
		put("Aurora", { minL = 40, want = { [1] = 1 } })
		open()
		local row = visibleRows()[1]
		local found
		for _, t in ipairs(row.tags) do if t:IsShown() and t:GetText() == "Requirements not met" then found = t end end
		notNil(found)
		eq(found.kind, "bad")
		eq(row.req:GetText(), "Level 40+ (you are 30)")
		eq(row.reqIcon:GetTexture():match("glyph_%a+"), "glyph_close")
	end)
end)

describe("500 listings", function()
	local function seed(n)
		local added = AzerothGuildFinder.Seed:Run(n)
		eq(added, n)
		return added
	end

	it("scroll through a pool of six frames; each frame shows the listing of its slot", function()
		seed(500)
		local h = open()
		eq(h.count:GetText(), "500 guilds")
		eq(#browse().data, 500)
		eq(browse().rowsCreated, #visibleRows(), "only the visible rows exist")
		local pool = browse().POOL_SIZE
		eq(pool, 6)
		local sorted = AzerothGuildFinder.Catalog:List()
		for offset = 0, 500 * 188, 91 do
			browse():SetOffset(offset)
			local rows = visibleRows()
			truthy(#rows >= 1 and #rows <= pool, "rows in view " .. #rows)
			for _, row in ipairs(rows) do
				eq(row.card.k, sorted[row.index].k, "row " .. row.index .. " shows the listing at its index")
				eq(row.name:GetText(), sorted[row.index].k:match("[^|]+$"))
				eq(row.slot, (row.index - 1) % pool + 1)
			end
			eq(rows[1].index, math.floor(browse().offset / 188) + 1, "the first row is the card at the top of the view")
		end
		eq(browse().rowsCreated, pool, "no frame was created while scrolling")
		local n = 0
		for _ in pairs(browse().rows) do n = n + 1 end
		eq(n, pool)
	end)

	it("every listing is bound once on a slow scroll to the end, and the last card is reached", function()
		seed(500)
		open()
		browse().pool.binds = 0
		for offset = 0, 500 * 188, 37 do browse():SetOffset(offset) end
		truthy(browse().pool.binds <= 500 + 1 + browse().POOL_SIZE, "bound " .. browse().pool.binds)
		local rows = visibleRows()
		eq(rows[#rows].index, 500)
		eq(browse().offset, 500 * 188 - 12 - browse().VIEW_H)
	end)

	it("the wheel scrolls by steps, the bar follows, and the top and the bottom stop the scroll", function()
		seed(500)
		local h = open()
		Mock.RunScript(h.list, "OnMouseWheel", -1)
		eq(browse().offset, browse().WHEEL_STEP)
		eq(h.bar:GetValue(), browse().offset)
		Mock.RunScript(h.list, "OnMouseWheel", 1)
		Mock.RunScript(h.list, "OnMouseWheel", 1)
		eq(browse().offset, 0, "not above the first card")
		for _ = 1, 2000 do Mock.RunScript(h.list, "OnMouseWheel", -1) end
		eq(browse().offset, 500 * 188 - 12 - browse().VIEW_H, "not below the last card")
		truthy(h.bar:IsShown())
		local _, maxValue = h.bar:GetMinMaxValues()
		eq(maxValue, browse().offset)
	end)

	it("dragging the bar scrolls the list", function()
		seed(500)
		local h = open()
		h.bar:SetValue(5000)
		Mock.RunScript(h.bar, "OnValueChanged", 5000)
		eq(browse().offset, 5000)
		eq(visibleRows()[1].index, math.floor(5000 / 188) + 1)
	end)

	it("the bar and the wheel are not needed when the list fits", function()
		put("Night Watch"); put("Aurora", { own = "b1b2b3b4" })
		local h = open()
		falsy(h.bar:IsShown())
		browse():ScrollBy(500)
		eq(browse().offset, 0)
	end)

	it("a catalog change while scrolled keeps the place and rebinds the rows", function()
		seed(100)
		local h = open()
		browse():SetOffset(3000)
		local before = visibleRows()[1].name:GetText()
		catalog():PutSummary(listing("AAA First Guild", { own = "c1c2c3c4" }))
		Mock.Advance(0.5)
		eq(browse().total, 101)
		eq(browse().offset, 3000)
		ne(visibleRows()[1].name:GetText(), before, "everything shifted down by one listing, the frames show the new ones")
		eq(visibleRows()[1].card.k, catalog():List()[visibleRows()[1].index].k)
	end)

	it("the debug line tells the pool", function()
		seed(500)
		open()
		for offset = 0, 2000, 50 do browse():SetOffset(offset) end
		contains(browse():DebugLines()[1], "6 row frames for a pool of 6")
	end)
end)

describe("reaction to the catalog", function()
	it("many changes in a burst rebuild the list once, after the throttle", function()
		local h = open()
		local before = browse().coalescer.runs
		for i = 1, 40 do put("Guild " .. i, { own = ("%08x"):format(i) }) end
		eq(browse().coalescer.runs, before)
		eq(browse().total, 0, "not yet")
		Mock.Advance(0.2)
		eq(browse().total, 0)
		Mock.Advance(0.2)
		eq(browse().coalescer.runs, before + 1)
		eq(browse().total, 40)
		eq(h.count:GetText(), "40 guilds")
		truthy(browse().coalescer.calls >= 40)
	end)

	it("while the page is hidden nothing is rebuilt; it is rebuilt when shown again", function()
		open()
		main():Select("Settings")
		falsy(browse():IsShown())
		for i = 1, 10 do put("Guild " .. i, { own = ("%08x"):format(i) }) end
		Mock.Advance(1)
		eq(browse().total, 0, "no work for a hidden page")
		eq(browse().coalescer:Pending(), false)
		main():Select("FindGuild")
		eq(browse().total, 10)
		eq(#visibleRows(), 4)
	end)

	it("a withdrawn listing disappears at the next rebuild", function()
		put("Aurora")
		put("Night Watch", { own = "b1b2b3b4" })
		open()
		eq(#visibleRows(), 2)
		catalog():PutSummary(listing("Aurora", { rev = 2 }), { dist = "CHANNEL", sender = "Anna-TestRealm" })
		catalog():Delist(key("Aurora"), 2, { sender = "Anna-TestRealm" })
		Mock.Advance(0.5)
		deepEq(shownNames(), { "Night Watch" })
	end)

	it("the first sync that ends refreshes the list and the status bar", function()
		local h = open()
		eq(browse().state.kind, "nopeers")
		AzerothGuildFinder.Bus:Emit("CATALOG_SYNCED", { full = true })
		put("Aurora")
		Mock.Advance(0.5)
		eq(browse().state.kind, "list")
	end)
end)

describe("the status bar", function()
	it("says how many guilds are known and the scope", function()
		put("Aurora"); put("Night Watch", { own = "b1b2b3b4" })
		open()
		eq(main().statusText:GetText(), "2 guilds known · not synced yet · Only guilds of your faction and realm")
		eq(main().statusLevel, "off")
	end)

	it("shows 'syncing' with the amber dot while a request runs", function()
		put("Aurora")
		sync().state.req = { rounds = 1 }
		open()
		contains(main().statusText:GetText(), "syncing...")
		eq(main().statusLevel, "warn")
	end)

	it("shows the age of the last full sync with the green dot, and keeps counting", function()
		put("Aurora")
		AzerothGuildFinder.Config.db.account.syncAt = { ["TestRealm|Horde"] = GetServerTime() - 120 }
		open()
		contains(main().statusText:GetText(), "synced 2 min ago")
		eq(main().statusLevel, "ok")
		Mock.StepClock(600)
		Mock.Advance(browse().POLL + 0.5)
		contains(main().statusText:GetText(), "synced 12 min ago")
	end)

	it("a request that starts while the page is shown is noticed within a few seconds", function()
		local h = open()
		eq(browse().state.kind, "nopeers")
		sync().state.req = { rounds = 1 }
		Mock.Advance(browse().POLL + 0.5)
		eq(browse().state.kind, "loading")
		truthy(h.stateBox.ring:IsShown())
	end)

	it("is cleared when the page is left, and the polling stops", function()
		open()
		main():Select("Settings")
		eq(main().statusText:GetText(), "")
		local timers = Mock.PendingTimers()
		Mock.Advance(browse().POLL * 3)
		eq(Mock.PendingTimers() <= timers, true)
	end)
end)

describe("leaving and coming back", function()
	it("keeps the search and the scroll position per tab", function()
		for i = 1, 60 do put("Guild " .. i .. " Ordine", { own = ("%08x"):format(i) }) end
		put("Night Watch", { own = "ffffffff" })
		local h = open()
		type_("ordine")
		Mock.Advance(0.3)
		browse():SetOffset(700)
		main():Select("Settings")
		main():Select("FindGuild")
		eq(h.search:GetText(), "ordine")
		eq(browse().search, "ordine")
		eq(browse().offset, 700)
		eq(h.count:GetText(), "60 of 61 guilds")
	end)

	it("a search typed and not yet applied when the page is left is not lost", function()
		put("Night Watch"); put("Aurora", { own = "b1b2b3b4" })
		local h = open()
		type_("aurora")
		main():Select("Settings")
		Mock.Advance(1)
		main():Select("FindGuild")
		eq(#visibleRows(), 1)
	end)

	it("starts clean after a change of role (the stacks start again)", function()
		put("Night Watch"); put("Aurora", { own = "b1b2b3b4" })
		local h = open()
		type_("aurora")
		Mock.Advance(0.3)
		eq(#visibleRows(), 1)
		Mock.guild.Set{ name = "Test Guild", myRank = 3 }
		Mock.Fire("PLAYER_GUILD_UPDATE", "player")
		Mock.guild.Leave()
		Mock.Fire("PLAYER_GUILD_UPDATE", "player")
		main():Show()
		eq(main():CurrentTab(), "FindGuild")
		eq(h.search:GetText(), "")
		eq(#visibleRows(), 2)
	end)
end)

describe("/gf debug seed", function()
	local function printed() return table.concat(Mock.output and Mock.output() or {}, "\n") end

	it("adds fake listings to the local catalog and nothing else", function()
		local sent = #Mock.chat.sent
		local attempts = #Mock.chat.attempts
		Mock.Slash("/gf debug seed 30")
		eq(catalog():Count(), 30)
		eq(#Mock.chat.sent, sent, "nothing was sent")
		eq(#Mock.chat.attempts, attempts, "nothing was even tried")
		for _, sum in ipairs(catalog():List()) do
			local entry = catalog():Get(sum.k)
			truthy(entry.localOnly, "marked local only")
			truthy(sum.k:match("^TestRealm|Horde|"))
		end
	end)

	it("the seeded listings are never offered to other clients", function()
		Mock.Slash("/gf debug seed 40")
		eq(#catalog():Digest(), 0, "not in the digest")
		eq(#catalog():Newer({}), 0, "not in a CAT answer")
		put("Real Guild", { own = "b1b2b3b4" })
		eq(#catalog():Digest(), 1)
		eq(#catalog():Newer({}), 1)
		eq(catalog():Newer({})[1].k, key("Real Guild"))
	end)

	it("a default seed has 60 guilds; the count is limited to the catalog limit", function()
		Mock.Slash("/gf debug seed")
		eq(catalog():Count(), 60)
		catalog():Clear()
		Mock.Slash("/gf debug seed 9999")
		eq(catalog():Count(), 500)
	end)

	it("'clear' removes the seeded listings and keeps the real ones", function()
		put("Real Guild", { own = "b1b2b3b4" })
		Mock.Slash("/gf debug seed 25")
		eq(catalog():Count(), 26)
		Mock.Slash("/gf debug seed clear")
		eq(catalog():Count(), 1)
		truthy(catalog():Get(key("Real Guild")))
		eq(catalog():Get(key("Real Guild")).localOnly, nil)
	end)

	it("is the same list every time: deterministic names", function()
		Mock.Slash("/gf debug seed 20")
		local first = {}
		for _, s in ipairs(catalog():List()) do first[#first + 1] = s.k end
		catalog():Clear()
		Mock.Slash("/gf debug seed 20")
		local second = {}
		for _, s in ipairs(catalog():List()) do second[#second + 1] = s.k end
		deepEq(first, second)
	end)

	it("gives valid, complete listings that exercise accents, symbols and the three commitments", function()
		local seeds = AzerothGuildFinder.Seed.Make(120, { realm = "TestRealm", faction = "Horde", now = GetServerTime() })
		local accents, paces = false, {}
		local names = {}
		for _, item in ipairs(seeds) do
			local sum = AzerothGuildFinder.Listing.SanitizeSummary(item.sum)
			truthy(sum and AzerothGuildFinder.Listing.IsComplete(sum))
			falsy(names[sum.k], "unique name " .. sum.k)
			names[sum.k] = true
			paces[sum.pace] = true
			if sum.k:find("[\195]") then accents = true end
			truthy(item.annAt <= GetServerTime())
		end
		truthy(accents)
		truthy(paces[1] and paces[2] and paces[3])
	end)

	it("a bad argument is refused with a message", function()
		Mock.Slash("/gf debug seed lots")
		eq(catalog():Count(), 0)
	end)

	it("a release build refuses and adds nothing", function()
		AzerothGuildFinder.Config.DEV = false
		Mock.Slash("/gf debug seed 10")
		eq(catalog():Count(), 0)
		local n, why = AzerothGuildFinder.Seed:Run(10)
		isNil(n)
		eq(why, "release")
	end)

	it("the list shows the seeded guilds as soon as it is open", function()
		local h = open()
		eq(browse().state.kind, "nopeers")
		Mock.Slash("/gf debug seed 60")
		Mock.Advance(0.5)
		eq(browse().state.kind, "list")
		eq(h.count:GetText(), "60 guilds")
		eq(#visibleRows() >= 3, true)
	end)
end)
