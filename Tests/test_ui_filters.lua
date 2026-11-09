-- M2.6: the filters on the left page of Find a Guild (UI/FilterPanel.lua) on the mock client: the controls, what each one
-- does to the list, the active count and the reset, the roles of the player's class, the saved state per character.
-- The rules themselves are in test_filter_model.lua. The mock player is a Horde Warrior, level 60, item level 0.

local function main() return AzerothGuildFinder.Main end
local function browse() return AzerothGuildFinder.Browse end
local function catalog() return AzerothGuildFinder.Catalog end
local function panel() return AzerothGuildFinder.FilterPanel.panel end
local function ctl() return AzerothGuildFinder.FilterPanel.Controller() end
local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end
local function key(name) return "TestRealm|Horde|" .. name end

local MON, TUE, FRI, SAT, SUN = 1, 2, 16, 32, 64
local WARRIOR, MAGE = 1, 8

local function put(name, extra)
	local t = { k = key(name), rev = 1, upd = GetServerTime() - 86400, first = 1766000000, own = "a1b2c3d4", sub = "Friendly",
		lang = 1, lang1 = 1, tags = { 1 }, pace = 2, days = MON, t0 = 720, t1 = 780, rec = 1, apps = true, want = { [0] = 8 },
		newb = false, minL = 20, st = { m = 100, a7 = 10 } }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return catalog():PutSummary(t)
end

-- Four guilds that differ in everything the filters look at (times in UTC; the zone of the computer is forced to UTC).
local function guilds()
	AzerothGuildFinder.BrowseModel.LocalOffset = function() return 0 end
	Mock.player.level = 50
	put("Alpha", { rec = 1, want = { [WARRIOR] = 1 }, lang = 16, lang1 = 5, pace = 1, tags = { 1 }, days = MON + TUE,
		newb = true, minL = 20, st = { m = 100, a7 = 40 }, t0 = 1200, t1 = 1380 })
	put("Bravo", { rec = 0, want = { [0] = 8 }, lang = 1, lang1 = 1, pace = 2, tags = { 5 }, days = SAT + SUN,
		newb = false, minL = 55, st = { m = 100, a7 = 5 }, t0 = 600, t1 = 660 })
	put("Charlie", { rec = 2, want = { [WARRIOR] = 4 }, lang = 3, lang1 = 1, pace = 3, tags = { 1, 2 }, days = FRI,
		newb = true, minL = 10, st = { m = 100, a7 = 12 }, t0 = 1380, t1 = 120 })
	put("Delta", { rec = 1, want = { [MAGE] = 8 }, lang = 4, lang1 = 3, pace = 2, tags = { 13 }, days = SUN,
		newb = false, minL = "nil", st = { m = 100, a7 = 30 }, t0 = 0, t1 = 0 })
end

local function open()
	main():Show()
	return main().hosts.FindGuild
end

local function shown()
	local out = {}
	for _, s in ipairs(browse():Selected()) do out[#out + 1] = s.k:match("[^|]+$") end
	return out
end

-- every filter off, the list shows the four guilds
local function allOff()
	ctl():Reset()
	deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })
end

-- Opens the list of a select (when closed), scrolls to the row with this text and clicks it.
local function choose(select, text)
	if not select:IsOpen() then click(select) end
	local found
	for _, direction in ipairs({ -1, 1 }) do   -- down first, then back up
		for _ = 1, 40 do
			for _, row in ipairs(select.popup.rows) do
				if row:IsShown() and row.text:GetText() == text then found = row end
			end
			if found then break end
			Mock.RunScript(select.popup, "OnMouseWheel", direction)
		end
		if found then break end
	end
	notNil(found, "a row '" .. text .. "'")
	click(found)
end

describe("the panel", function()
	it("is built with the page, on the left page, and fits the height of the page", function()
		local h = open()
		local p = panel()
		eq(p.frame, h.left)
		eq(AzerothGuildFinder.FilterPanel.WIDTH, 260)
		local m = AzerothGuildFinder.Skin.METRICS
		local available = m.windowH - 104 - 20
		truthy(p.height <= available, "the controls need " .. p.height .. " of " .. available .. " px")
		for _, id in ipairs({ "recruiting", "myClass", "reqs", "newb" }) do notNil(p.switches[id], id) end
		for _, name in ipairs({ "roles", "langs", "paces", "acts", "days", "from", "to", "minActive", "resetButton", "plate" }) do
			notNil(p[name], name)
		end
		eq(#Mock.errors, 0)
	end)

	it("labels the controls in English and names the player's class", function()
		open()
		local p = panel()
		eq(p.switches.recruiting.label:GetText(), "Recruiting only")
		eq(p.switches.myClass.label:GetText(), "Looking for my class (Warrior)")
		eq(p.switches.reqs.label:GetText(), "Requirements met")
		eq(p.switches.newb.label:GetText(), "New player friendly")
		eq(p.roles.chips[1]:GetLabel(), "Tank")
		eq(p.roles.chips[8]:GetLabel(), "Ranged DPS")
		eq(p.paces.chips[1]:GetLabel(), "Casual")
		eq(p.langs.text:GetText(), "Any language")
		eq(p.acts.text:GetText(), "Any activity")
		eq(p.minActive.text:GetText(), "Any")
		eq(p.days.buttons[1].text:GetText(), "M")
		eq(p.from.text:GetText(), "Any")
		eq(#p.acts.items, 13)
		eq(#p.langs.items, 9)
		eq(#p.from.items, 49)
	end)

	it("a character that never chose has only 'Recruiting only' on", function()
		guilds()
		local h = open()
		local p = panel()
		truthy(p.switches.recruiting:GetChecked())
		eq(h.plate.text:GetText(), "Filters · 1 active")
		deepEq(shown(), { "Alpha", "Charlie", "Delta" })
		eq(h.count:GetText(), "3 of 4 guilds")
	end)

	it("the roles the class cannot play are dimmed with the reason; the others work", function()
		open()
		local p = panel()
		falsy(p.roles.chips[2]:IsChipEnabled(), "Healer")
		falsy(p.roles.chips[8]:IsChipEnabled(), "Ranged")
		truthy(p.roles.chips[1]:IsChipEnabled())
		truthy(p.roles.chips[4]:IsChipEnabled())
		eq(AzerothGuildFinder.Widgets.TooltipContent(p.roles.chips[8].agfTooltip).lines[1].text, "Warrior cannot play this role")
		click(p.roles.chips[8])
		eq(ctl():Get("roles"), 0)
		click(p.roles.chips[1])
		eq(ctl():Get("roles"), 1)
	end)
end)

describe("each control filters the list", function()
	it("the four switches", function()
		guilds()
		open()
		local p = panel()
		allOff()
		click(p.switches.recruiting)
		deepEq(shown(), { "Alpha", "Charlie", "Delta" })
		click(p.switches.recruiting)
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })
		click(p.switches.myClass)
		deepEq(shown(), { "Alpha", "Bravo", "Charlie" }, "Warrior listed, or any class")
		click(p.switches.myClass)
		click(p.switches.reqs)
		deepEq(shown(), { "Alpha", "Charlie", "Delta" }, "Bravo wants level 55, the player is 50")
		click(p.switches.reqs)
		click(p.switches.newb)
		deepEq(shown(), { "Alpha", "Charlie" })
	end)

	it("role, language, commitment, activity", function()
		guilds()
		open()
		local p = panel()
		allOff()
		click(p.roles.chips[1])
		deepEq(shown(), { "Alpha" }, "Tank: only Alpha asks a Warrior to tank")
		click(p.roles.chips[4])
		deepEq(shown(), { "Alpha", "Charlie" }, "Tank or Melee")
		p.roles:Clear()
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })

		choose(p.langs, "German")
		deepEq(shown(), { "Charlie" })
		eq(p.langs.text:GetText(), "German")
		choose(p.langs, "Italian")
		deepEq(shown(), { "Alpha", "Charlie" })
		eq(p.langs.text:GetText(), "German, Italian")
		choose(p.langs, "French")
		eq(p.langs.text:GetText(), "3 selected")
		deepEq(shown(), { "Alpha", "Charlie", "Delta" })
		click(AzerothGuildFinder.Widgets.SelectBackdrop())
		ctl():Set("langs", 0)

		click(p.paces.chips[2])
		deepEq(shown(), { "Bravo", "Delta" })
		click(p.paces.chips[3])
		deepEq(shown(), { "Bravo", "Charlie", "Delta" })
		p.paces:Clear()

		choose(p.acts, "Housing")
		deepEq(shown(), { "Delta" })
		choose(p.acts, "Dungeons")
		deepEq(shown(), { "Charlie", "Delta" })
		click(AzerothGuildFinder.Widgets.SelectBackdrop())
		eq(ctl():Get("acts"), 2 + 4096)
	end)

	it("play days, play time and active members", function()
		guilds()
		open()
		local p = panel()
		allOff()
		click(p.days.buttons[6])
		deepEq(shown(), { "Bravo" }, "Saturday")
		click(p.days.buttons[7])
		deepEq(shown(), { "Bravo", "Delta" }, "Saturday or Sunday")
		p.days:SetMask(0)
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })

		-- 20:00 to 23:30 in the zone of the player (forced to UTC here); Charlie plays 23:00-02:00 and Delta all day
		choose(p.from, "20:00")
		eq(ctl():Get("timeFrom"), 1200)
		deepEq(shown(), { "Alpha", "Charlie", "Delta" }, "only a start: 20:00 to midnight")
		choose(p.to, "23:30")
		eq(ctl():Get("timeTo"), 1410)
		deepEq(shown(), { "Alpha", "Charlie", "Delta" })
		choose(p.to, "20:30")
		deepEq(shown(), { "Alpha", "Delta" }, "20:00-20:30 meets Alpha and the all-day Delta")
		choose(p.from, "Any")
		isNil(ctl():Get("timeFrom"))
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" }, "only an end: midnight to 20:30 meets everybody")
		choose(p.to, "09:30")
		deepEq(shown(), { "Charlie", "Delta" }, "midnight to 09:30: Charlie's 23:00-02:00 and the all-day Delta")
		choose(p.to, "Any")
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })
		eq(p.from.text:GetText(), "Any")

		choose(p.minActive, "25")
		deepEq(shown(), { "Alpha", "Delta" })
		choose(p.minActive, "50")
		deepEq(shown(), {})
		choose(p.minActive, "Any")
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })
	end)

	it("a long list of times opens near 20:00 and reaches midnight and 23:30", function()
		open()
		local p = panel()
		click(p.from)
		local first = p.from.popup.rows[1].text:GetText()
		matches(first, "^%d%d:%d%d$")
		truthy(first >= "18:00" and first <= "20:00", "starts near 20:00, got " .. first)
		click(p.from)
		click(p.from)
		for _ = 1, 30 do Mock.RunScript(p.from.popup, "OnMouseWheel", -1) end
		eq(p.from.popup.rows[8].text:GetText(), "23:30")
		click(AzerothGuildFinder.Widgets.SelectBackdrop())
	end)

	it("filters and the search work together; clearing the search leaves the filters", function()
		guilds()
		local h = open()
		allOff()
		click(panel().switches.newb)
		Mock.TypeInto(h.search.edit, "cha")
		Mock.Advance(1)
		deepEq(shown(), { "Charlie" })
		Mock.TypeInto(h.search.edit, "bra")
		Mock.Advance(1)
		deepEq(shown(), {}, "Bravo is not new player friendly")
		h.search:Clear()
		deepEq(shown(), { "Alpha", "Charlie" })
	end)

	it("every change brings the list back to its top", function()
		AzerothGuildFinder.Seed:Run(500)
		open()
		ctl():Reset()
		browse():SetOffset(5000)
		truthy(browse().offset > 0)
		click(panel().switches.newb)
		eq(browse().offset, 0)
	end)
end)

describe("active count and reset", function()
	it("the plate counts the filters that are on; the button resets them all, even 'Recruiting only'", function()
		guilds()
		local h = open()
		local p = panel()
		eq(h.plate.text:GetText(), "Filters · 1 active")
		click(p.switches.myClass)
		click(p.switches.newb)
		click(p.paces.chips[2])
		choose(p.acts, "Raids")
		click(AzerothGuildFinder.Widgets.SelectBackdrop())
		eq(h.plate.text:GetText(), "Filters · 5 active")
		click(p.resetButton)
		eq(h.plate.text:GetText(), "Filters")
		falsy(p.switches.recruiting:GetChecked())
		falsy(p.switches.myClass:GetChecked())
		deepEq(p.paces:GetSelected(), {})
		deepEq(p.acts:GetSelected(), {})
		eq(p.acts.text:GetText(), "Any activity")
		eq(ctl():Count(), 0)
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })
		eq(AzerothGuildFinder.Widgets.TooltipContent(p.resetButton.agfTooltip).title, "Reset all filters")
	end)

	it("no match: the message and the button of the state reset the filters and the controls", function()
		guilds()
		local h = open()
		local p = panel()
		allOff()
		choose(p.minActive, "50")
		truthy(h.stateBox:IsShown())
		eq(h.stateBox.message:GetText(), "No guild matches your filters")
		truthy(h.stateBox.reset:IsShown())
		click(h.stateBox.reset)
		falsy(h.stateBox:IsShown())
		eq(p.minActive.text:GetText(), "Any")
		eq(h.plate.text:GetText(), "Filters")
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })
	end)

	it("a reset while the page is hidden is applied when it is shown", function()
		guilds()
		open()
		ctl():Set("newb", true)
		main():Hide()
		ctl():Reset()
		main():Show()
		deepEq(shown(), { "Alpha", "Bravo", "Charlie", "Delta" })
	end)
end)

describe("saved per character", function()
	it("every change is written to the character's saved variables", function()
		open()
		local p = panel()
		ctl():Reset()
		click(p.switches.newb)
		choose(p.langs, "Italian")
		click(AzerothGuildFinder.Widgets.SelectBackdrop())
		click(p.days.buttons[1])
		choose(p.from, "20:00")
		choose(p.minActive, "10")
		local saved = AzerothGuildFinderCharDB.ui.filters
		eq(saved.newb, true)
		eq(saved.recruiting, false)
		eq(saved.langs, 16)
		eq(saved.days, 1)
		eq(saved.timeFrom, 1200)
		isNil(saved.timeTo)
		eq(saved.minActive, 10)
		isNil(AzerothGuildFinderDB.settings.filters, "nothing about filters in the account data")
	end)

	it("after /reload the controls, the count and the list are as they were left", function()
		guilds()
		open()
		local p = panel()
		allOff()
		click(p.switches.myClass)
		click(p.paces.chips[2])
		click(p.roles.chips[1])
		click(p.days.buttons[1])
		Mock.Reload()
		guilds()
		local h = open()
		p = panel()
		truthy(p.switches.myClass:GetChecked())
		falsy(p.switches.recruiting:GetChecked(), "a saved 'off' stays off")
		deepEq(p.paces:GetSelected(), { 2 })
		deepEq(p.roles:GetSelected(), { 1 })
		eq(p.days:GetMask(), 1)
		eq(h.plate.text:GetText(), "Filters · 4 active")
		deepEq(shown(), {})
		ctl():Set("paces", 0)
		ctl():Set("roles", 0)
		ctl():Set("days", 0)
		deepEq(shown(), { "Alpha", "Bravo", "Charlie" })
	end)

	it("another character starts from its own state", function()
		open()
		ctl():Reset()
		click(panel().switches.newb)
		AzerothGuildFinderCharDB = nil
		Mock.Reload()
		open()
		eq(ctl():Count(), 1)
		truthy(panel().switches.recruiting:GetChecked())
		falsy(panel().switches.newb:GetChecked())
	end)

	it("damaged saved filters are repaired and the page opens", function()
		AzerothGuildFinderCharDB.ui.filters = { recruiting = "maybe", roles = 99, minActive = 3, langs = "x", timeFrom = 5000 }
		Mock.Reload()
		open()
		truthy(panel().switches.recruiting:GetChecked())
		eq(ctl():Get("roles"), 1 + 4, "Tank and Melee: what a Warrior can play")
		eq(ctl():Get("minActive"), 0)
		eq(ctl():Get("langs"), 0)
		eq(ctl():Get("timeFrom"), 1439)
		eq(#Mock.errors, 0)
	end)
end)
