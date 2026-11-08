-- Sample tests of the addon as it is today (M1.1): loading, slash commands, /reload with SavedVariables.
-- Copy this shape for new tests. `Mock` is the fake client; the game's globals (AzerothGuildFinder, LibStub, ...) are
-- plain globals here too. Read them inside the test, not at the top of the file: every test boots a fresh client.

describe("loading", function()
	it("loads every TOC file in order without a Lua error", function()
		eq(#Mock.errors, 0)
		local order = {}
		for i, name in ipairs(Mock.loadedFiles) do order[name] = i end
		local libStub = order["AzerothGuildFinder/Libs/Ace3/LibStub/LibStub.lua"]
		local aceAddon = order["AzerothGuildFinder/Libs/Ace3/AceAddon-3.0/AceAddon-3.0.lua"]
		local locale = order["AzerothGuildFinder/Locale/enUS.lua"]
		local init = order["AzerothGuildFinder/Core/Init.lua"]
		truthy(libStub and aceAddon and locale and init, "all four files were loaded")
		truthy(libStub < aceAddon and aceAddon < locale and locale < init, "TOC order is kept")
	end)

	it("creates the addon object and fires OnInitialize", function()
		local AGF = LibStub("AceAddon-3.0"):GetAddon("AzerothGuildFinder")
		eq(AGF, AzerothGuildFinder)
		truthy(AGF:IsEnabled(), "enabled after PLAYER_LOGIN")
	end)

	it("recognises Forever and stays quiet", function()
		truthy(AzerothGuildFinder:IsForever())
		eq(#Mock.output, 0, "nothing printed at login")
	end)

	it("warns when the client is not Forever", function()
		-- the setup runs after the mock client is built and before the addon's files load
		T.boot(function() WOW_PROJECT_ID = WOW_PROJECT_MAINLINE end)
		falsy(AzerothGuildFinder:IsForever())
		contains(table.concat(Mock.PlainOutput(), "\n"), "built for WoW Forever")
	end)
end)

describe("slash commands", function()
	it("/gf help prints the commands", function()
		truthy(Mock.Slash("/gf help"))
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Commands:")
		for _, command in ipairs({ "/gf notify", "/gf reset", "/gf debug", "/gf help" }) do
			contains(text, command)
		end
	end)

	it("/guildfinder is an alias of /gf", function()
		truthy(Mock.Slash("/guildfinder help"))
		contains(table.concat(Mock.PlainOutput(), "\n"), "Commands:")
	end)

	it("an unknown command is reported and the help follows", function()
		Mock.Slash("/gf frobnicate")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Unknown command 'frobnicate'")
		contains(text, "Commands:")
	end)

	it("a command with no handler yet says so", function()
		Mock.Slash("/gf notify")
		contains(table.concat(Mock.PlainOutput(), "\n"), "coming soon")
	end)
end)

describe("/reload", function()
	it("passes SavedVariables from one run to the next", function()
		AzerothGuildFinderDB = { counter = 1, nested = { "a", "b" } }
		AzerothGuildFinderCharDB = { seen = true }
		Mock.Reload()
		-- Config merges its defaults around the test values; the values themselves are kept
		eq(AzerothGuildFinderDB.counter, 1)
		deepEq(AzerothGuildFinderDB.nested, { "a", "b" })
		eq(AzerothGuildFinderCharDB.seen, true)
		AzerothGuildFinderDB.counter = AzerothGuildFinderDB.counter + 1
		Mock.Reload()
		eq(AzerothGuildFinderDB.counter, 2)
	end)

	it("rebuilds the Lua state: values that are not saved are gone", function()
		AzerothGuildFinderDB = { kept = "yes" }
		SomeRuntimeValue = "lost"
		local before = AzerothGuildFinder
		Mock.Reload()
		isNil(SomeRuntimeValue)
		ne(AzerothGuildFinder, before, "a new addon object")
		eq(AzerothGuildFinderDB.kept, "yes")
		eq(#Mock.errors, 0)
	end)

	it("keeps the world: clock, player and guild", function()
		Mock.guild.Set({ name = "Keepers", myRank = 2 })
		Mock.Advance(30)
		local now = GetTime()
		Mock.Reload()
		eq(GetTime(), now)
		eq(GetGuildInfo("player"), "Keepers")
	end)

	it("fires PLAYER_LOGOUT first and PLAYER_ENTERING_WORLD with isReloadingUi after", function()
		local seen = {}
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("PLAYER_LOGOUT")
		frame:SetScript("OnEvent", function(_, event) seen[#seen + 1] = event end)
		AzerothGuildFinderDB = {}
		Mock.Reload()
		deepEq(seen, { "PLAYER_LOGOUT" })
		local reloading
		local f2 = CreateFrame("Frame")
		f2:RegisterEvent("PLAYER_ENTERING_WORLD")
		f2:SetScript("OnEvent", function(_, _, isInitialLogin, isReloadingUi) reloading = isReloadingUi end)
		Mock.Fire("PLAYER_ENTERING_WORLD", false, true)
		eq(reloading, true)
	end)

	it("refuses SavedVariables the client could not store", function()
		AzerothGuildFinderDB = { handler = function() end }
		local err = raises(function() Mock.Reload() end)
		contains(err, "cannot be saved")
	end)
end)
