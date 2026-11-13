-- M5.4: the diagnostics report of `/gf debug` (Core/Diagnostics.lua) and its copy box (UI/DiagnosticsBox.lua): the sections,
-- the absence of names, the error ring buffer and the box in the mock client.
local function A() return AzerothGuildFinder end
local function D() return A().Diagnostics end
local function B() return A().DiagnosticsBox end

local function report() return D().Report() end
local function sectionTitles(text)
	local titles = {}
	for title in text:gmatch("\n== ([^\n]-) ==") do titles[#titles + 1] = title end
	return titles
end
local function has(list, value) for _, v in ipairs(list) do if v == value then return true end end return false end

describe("the report", function()
	it("starts with the addon, client and interface versions", function()
		local text = report()
		contains(text, "Azeroth Guild Finder diagnostics")
		contains(text, "addon: ")
		contains(text, "client: ")
		contains(text, "interface: 16001")
		contains(text, "project id: ")
	end)

	it("has the capabilities, catalog, sync, listen-only, errors, role and settings sections", function()
		local titles = sectionTitles(report())
		for _, wanted in ipairs({ "Compat", "Catalog", "Sync", "Listen-only", "Last errors", "Role", "Settings" }) do
			truthy(has(titles, wanted), "missing section " .. wanted)
		end
		contains(report(), "Capabilities:")
	end)

	it("says why the addon only listens, or that it does not", function()
		contains(report(), "listen-only: no")
		local T = A().Transport
		T.state.listenOnly, T.state.listenReason = true, "InvalidChannel"
		contains(report(), "listen-only: yes, reason InvalidChannel")
	end)

	it("Format is plain data to text and needs no client", function()
		local text = D().Format({ header = { "h1", "h2" }, sections = { { title = "A", lines = { "a1", "a2" } }, { title = "B", lines = {} } } })
		eq(text, "h1\nh2\n\n== A ==\na1\na2\n\n== B ==")
	end)

	it("reports a failing section instead of raising", function()
		A():AddDebugSection("Broken", function() error("boom") end)
		local text = report()
		contains(text, "== Broken ==")
		contains(text, "error: ")
	end)
end)

describe("no names in the report", function()
	local NAMES = { "Jaina", "Garrosh", "Thrall", "Anna", "Night Watch", "Frostwolves" }

	it("holds no player or guild name from the roster or the catalog", function()
		Mock.guild.Set{ name = "Frostwolves", myRank = 0, members = { { name = "Jaina", rank = 1 }, { name = "Garrosh", rank = 3 } } }
		Mock.Fire("GUILD_ROSTER_UPDATE")
		local Cat = A().Catalog
		Cat:PutSummary({ k = "TestRealm|Horde|Night Watch", rev = 1, upd = 1767000000, first = 1766000000, own = "a1b2c3d4",
			sub = "Friendly raiders", lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380, rec = 1,
			apps = true, want = { [0] = 8 }, newb = true, minL = 30 }, { dist = "CHANNEL", sender = "Anna-TestRealm" })
		Cat:PutDetail({ k = "TestRealm|Horde|Night Watch", rev = 1, desc = "We raid.", disc = "abc123", cont = { "Thrall" }, note = "x" })
		Mock.Slash("/gf debug")
		local text = report()
		contains(text, "Listings: 1 listed")
		for _, name in ipairs(NAMES) do
			falsy(text:find(name, 1, true), "the report contains " .. name)
		end
		for _, line in ipairs(Mock.PlainOutput()) do
			for _, name in ipairs(NAMES) do falsy(line:find(name, 1, true), "the output contains " .. name) end
		end
	end)

	it("holds neither the character's name nor the realm", function()
		local text = report()
		local name = UnitName("player")
		truthy(name and name ~= "")
		falsy(text:find(name, 1, true), "the report contains the character name")
		local realm = GetRealmName and GetRealmName()
		if realm and realm ~= "" then falsy(text:find(realm, 1, true), "the report contains the realm") end
	end)
end)

describe("the error ring buffer", function()
	it("is empty at first and the report says so", function()
		eq(#D().Errors(), 0)
		contains(report(), "no addon errors recorded this session")
	end)

	it("keeps an error without the player's folders", function()
		D().Record("C:\\Games\\WoW\\_classic_\\Interface\\AddOns\\AzerothGuildFinder\\Net\\Sync.lua:12: attempt to index nil")
		eq(D().Errors()[1].text, "AzerothGuildFinder/Net/Sync.lua:12: attempt to index nil")
		D().Record("D:\\Users\\SomeOne\\Documents\\x.lua:3: bad")
		falsy(D().Errors()[2].text:find("SomeOne", 1, true))
		falsy(D().Errors()[2].text:find("D:", 1, true))
		D().Record("/ho" .. "me/someone/wow/Interface/AddOns/AzerothGuildFinder/UI/Main.lua:9: bad")
		falsy(D().Errors()[3].text:find("someone", 1, true))
		contains(report(), "Sync.lua:12")
		falsy(report():find("Games", 1, true))
	end)

	it("counts the same error repeated and keeps one line", function()
		for _ = 1, 5 do D().Record("AzerothGuildFinder/Data/Catalog.lua:1: boom") end
		eq(#D().Errors(), 1)
		eq(D().Errors()[1].count, 5)
		contains(report(), "x5 AzerothGuildFinder/Data/Catalog.lua:1: boom")
	end)

	it("keeps the latest ten, dropping the oldest", function()
		for i = 1, 14 do D().Record("AzerothGuildFinder: error number " .. i) end
		eq(#D().Errors(), D().MAX_ERRORS)
		eq(D().Errors()[1].text, "AzerothGuildFinder: error number 5")
		eq(D().Errors()[10].text, "AzerothGuildFinder: error number 14")
		eq(D().ErrorLines()[1], "AzerothGuildFinder: error number 14")   -- latest first
	end)

	it("cuts a long error and drops its newlines", function()
		D().Record("AzerothGuildFinder: " .. ("x"):rep(1000) .. "\nsecond line")
		local text = D().Errors()[1].text
		truthy(#text <= D().MAX_LENGTH)
		falsy(text:find("\n", 1, true))
		D().ClearErrors()
		D().Record("AzerothGuildFinder: first\nsecond")
		contains(D().Errors()[1].text, "first | second")
	end)

	it("catches only this addon's errors through the game's error handler and passes them on", function()
		local handler = geterrorhandler()
		handler("Interface\\AddOns\\AzerothGuildFinder\\Core\\Bus.lua:5: listener failed")
		handler("Interface\\AddOns\\SomeOtherAddon\\x.lua:5: not ours")
		eq(#D().Errors(), 1)
		eq(D().Errors()[1].text, "AzerothGuildFinder/Core/Bus.lua:5: listener failed")
		eq(#Mock.errors, 2, "both errors went on to the game's handler")
		Mock.ClearErrors()
	end)
end)

describe("the copy box", function()
	it("is hidden until /gf debug opens it with the report", function()
		falsy(B():IsShown())
		truthy(Mock.Slash("/gf debug"))
		truthy(B():IsShown())
		eq(B():GetText(), B().frame.edit:GetText())
		contains(B():GetText(), "Azeroth Guild Finder diagnostics")
		contains(B():GetText(), "== Compat ==")
	end)

	it("is read-only: typing is undone", function()
		Mock.Slash("/gf debug")
		local edit, original = B().frame.edit, B():GetText()
		edit:SetText("tampered")
		Mock.RunScript(edit, "OnTextChanged", true)
		eq(edit:GetText(), original)
	end)

	it("Select all selects the whole text", function()
		Mock.Slash("/gf debug")
		local selected
		B().frame.edit.HighlightText = function() selected = true end
		Mock.RunScript(B().frame.selectAll, "OnClick", "LeftButton")
		truthy(selected)
	end)

	it("closes with its button and is in UISpecialFrames for Esc", function()
		Mock.Slash("/gf debug")
		Mock.RunScript(B().frame.close, "OnClick", "LeftButton")
		falsy(B():IsShown())
		local found = false
		for _, name in ipairs(UISpecialFrames) do if name == B().NAME then found = true end end
		truthy(found)
	end)

	it("opening it again builds a fresh report", function()
		Mock.Slash("/gf debug")
		D().Record("AzerothGuildFinder: late error")
		Mock.Slash("/gf debug")
		contains(B():GetText(), "late error")
	end)

	it("every string of the box is in the locale", function()
		local L = LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")
		for _, key in ipairs({ "DIAG_TITLE", "DIAG_HINT", "DIAG_SELECT", "DIAG_CLOSE", "HELP_DEBUG" }) do
			truthy(L[key] ~= key, key)
		end
	end)
end)
