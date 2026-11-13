-- M5.1: the Settings page (UI/SettingsModel.lua, UI/SettingsPage.lua): one definition of the options, the defaults of the
-- wiki (Commands and Settings), persistence across a reload, the effect of each option, reset positions, the page of the
-- window and the panel in the game's Settings window (with its fallback when the client has no Settings API).

local function A() return AzerothGuildFinder end
local function M() return A().SettingsModel end
local function main() return A().Main end
local function cfg(path) return A().Config:Get(path) end
local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end
local function minimapButton() return _G["LibDBIcon10_AzerothGuildFinder"] end
local function minimapShown() local b = minimapButton() return b ~= nil and b:IsShown() end
local function Loc() return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder") end

local KEYS = { "uiScale", "minimapButton", "shareAltCount", "notifyIcon", "onlyWhenPending", "sound" }

-- The wiki table is the contract.
local WIKI_DEFAULTS = { minimapButton = true, notifyIcon = true, onlyWhenPending = false, sound = true, shareAltCount = true, uiScale = 1.0 }

describe("the options", function()
	it("are the six of SPEC-04 §4, each with a label and a help text in the locale", function()
		local seen = {}
		for _, option in ipairs(M().OPTIONS) do
			seen[#seen + 1] = option.key
			truthy(Loc()[option.label] ~= option.label, option.key .. " label")
			truthy(Loc()[option.help] ~= option.help, option.key .. " help")
		end
		table.sort(seen)
		local expected = { unpack(KEYS) }
		table.sort(expected)
		deepEq(seen, expected)
	end)

	it("have the defaults of the wiki, on a fresh install", function()
		for key, value in pairs(WIKI_DEFAULTS) do
			eq(M().Default(key), value, key)
			eq(M().Get(key), value, key)
			truthy(M().IsDefault(key))
		end
	end)

	it("keep the wiki's defaults in Config too, so a repaired value falls back to them", function()
		for key, value in pairs(WIKI_DEFAULTS) do eq(A().Config.defaults.account.settings[key], value, key) end
	end)

	it("an unknown option is refused", function()
		eq(M().Set("nope", true), false)
		isNil(M().Get("nope"))
	end)

	it("a value of the wrong type is refused and nothing changes", function()
		local ok, why = M().Set("sound", "yes")
		eq(ok, false); eq(why, "type")
		eq(M().Set("uiScale", true), false)
		eq(M().Get("sound"), true)
		eq(M().Get("uiScale"), 1)
	end)

	it("a size outside 60 to 140 % is brought inside", function()
		truthy(M().Set("uiScale", 3))
		eq(M().Get("uiScale"), 1.4)
		truthy(M().Set("uiScale", 0.1))
		eq(M().Get("uiScale"), 0.6)
	end)
end)

describe("persistence", function()
	it("every option survives a reload", function()
		truthy(M().Set("minimapButton", false))
		truthy(M().Set("notifyIcon", false))
		truthy(M().Set("onlyWhenPending", true))
		truthy(M().Set("sound", false))
		truthy(M().Set("shareAltCount", false))
		truthy(M().Set("uiScale", 0.8))
		Mock.Reload()
		eq(M().Get("minimapButton"), false)
		eq(M().Get("notifyIcon"), false)
		eq(M().Get("onlyWhenPending"), true)
		eq(M().Get("sound"), false)
		eq(M().Get("shareAltCount"), false)
		eq(M().Get("uiScale"), 0.8)
		for _, key in ipairs(KEYS) do falsy(M().IsDefault(key), key) end
		eq(#Mock.errors, 0)
	end)

	it("the minimap button stays hidden after a reload, and shown again when the option is turned back on", function()
		truthy(M().Set("minimapButton", false))
		Mock.Reload()
		falsy(minimapShown())
		truthy(M().Set("minimapButton", true))
		truthy(minimapShown())
		Mock.Reload()
		truthy(minimapShown())
	end)

	it("the account option decides for a character whose own flag is stale", function()
		AzerothGuildFinderCharDB = { minimap = { hide = true } }
		Mock.Reload()
		truthy(M().Get("minimapButton"))
		truthy(minimapShown())
	end)

	it("a damaged value is repaired to the default", function()
		AzerothGuildFinderDB = { settings = { sound = "loud", uiScale = 9, shareAltCount = 3 } }
		Mock.Reload()
		eq(M().Get("sound"), true)
		eq(M().Get("uiScale"), 1)
		eq(M().Get("shareAltCount"), true)
	end)

	it("a saved newer schema is read-only: the change is refused and nothing is written", function()
		AzerothGuildFinderDB = { schemaVersion = 99, settings = { sound = true } }
		Mock.Reload()
		local ok, why = M().Set("sound", false)
		eq(ok, false); eq(why, "read-only")
	end)
end)

describe("applying an option", function()
	it("the minimap button: hides and shows it and saves both flags", function()
		truthy(minimapShown())
		M().Set("minimapButton", false)
		falsy(minimapShown())
		eq(cfg("account.settings.minimapButton"), false)
		eq(cfg("char.minimap.hide"), true)
		M().Set("minimapButton", true)
		truthy(minimapShown())
		eq(cfg("char.minimap.hide"), false)
	end)

	it("the size: scales the window and is what /gf scale reports", function()
		main():Show()
		M().Set("uiScale", 1.2)
		eq(main().frame:GetScale(), 1.2)
		Mock.Slash("/gf scale")
		contains(table.concat(Mock.PlainOutput(), "\n"), "120%")
	end)

	it("the anonymous alt count: turns the sharing of the Stats module off and on", function()
		truthy(A().Stats:Sharing())
		M().Set("shareAltCount", false)
		falsy(A().Stats:Sharing())
		M().Set("shareAltCount", true)
		truthy(A().Stats:Sharing())
	end)

	it("the notification options: read by the icon's model and announced on the Bus", function()
		local heard = {}
		A().Bus:On("NOTIFY_OPTIONS_CHANGED", function(key, value) heard[#heard + 1] = key .. "=" .. tostring(value) end)
		M().Set("notifyIcon", false)
		M().Set("onlyWhenPending", true)
		M().Set("sound", false)
		deepEq(heard, { "notifyIcon=false", "onlyWhenPending=true", "sound=false" })
		falsy(A().AppsModel.GetOption("notifyIcon"))
		truthy(A().AppsModel.GetOption("onlyWhenPending"))
		falsy(A().AppsModel.GetOption("sound"))
	end)

	it("every change is announced as SETTINGS_CHANGED, once, and setting the same value again is silent", function()
		local heard = {}
		A().Bus:On("SETTINGS_CHANGED", function(key, value) heard[#heard + 1] = key .. "=" .. tostring(value) end)
		M().Set("sound", false)
		M().Set("sound", false)
		M().Set("uiScale", 0.8)
		deepEq(heard, { "sound=false", "uiScale=0.8" })
	end)

	it("a change made elsewhere (the Applications tab) shows on the page", function()
		main():Open("Settings")
		local h = main().hosts.Settings
		truthy(h.notifySwitches.sound:GetChecked())
		A().AppsModel.SetOption("sound", false)
		falsy(h.notifySwitches.sound:GetChecked())
	end)
end)

describe("reset positions", function()
	it("puts the window and the notification icon back and says so", function()
		A().Config:Set("char.ui.mainPos", { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -10 })
		A().Config:Set("char.ui.notifyPos", { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -10 })
		truthy(M().ResetPositions())
		isNil(cfg("char.ui.mainPos"))
		isNil(cfg("char.ui.notifyPos"))
	end)

	it("leaves the options alone", function()
		M().Set("uiScale", 0.8)
		M().Set("sound", false)
		M().ResetPositions()
		eq(M().Get("uiScale"), 0.8)
		eq(M().Get("sound"), false)
	end)

	it("ResetAll also restores every default", function()
		M().Set("uiScale", 0.8)
		M().Set("minimapButton", false)
		M().Set("shareAltCount", false)
		M().Set("onlyWhenPending", true)
		M().ResetAll()
		for key, value in pairs(WIKI_DEFAULTS) do eq(M().Get(key), value, key) end
		truthy(minimapShown())
	end)

	it("the button of the page does it and shows the confirmation", function()
		main():Open("Settings")
		A().Config:Set("char.ui.mainPos", { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -10 })
		click(main().hosts.Settings.resetButton)
		isNil(cfg("char.ui.mainPos"))
		eq(A().Widgets.Snackbar.Current(), "Window position reset.")
	end)
end)

describe("the Settings page of the window", function()
	it("has a control for every option, and the switches write and apply", function()
		main():Open("Settings")
		local c = main().hosts.Settings.settings.controls
		for _, key in ipairs(KEYS) do truthy(c[key], key) end
		click(c.minimapButton)
		eq(cfg("account.settings.minimapButton"), false)
		falsy(minimapShown())
		click(c.shareAltCount)
		falsy(A().Stats:Sharing())
		click(c.uiScale.segments[0.6])
		eq(M().Get("uiScale"), 0.6)
		eq(#Mock.errors, 0)
	end)

	it("shows the saved values when opened", function()
		M().Set("minimapButton", false)
		M().Set("uiScale", 1.4)
		main():Open("Settings")
		local c = main().hosts.Settings.settings.controls
		falsy(c.minimapButton:GetChecked())
		eq(c.uiScale:GetSelected(), 1.4)
	end)

	it("shows Notifications to the Guild Master and the officers only", function()
		main():Open("Settings")
		falsy(main().hosts.Settings.notify:IsShown())
		Mock.guild.Set{ name = "Aurora", myRank = 1 }
		A().Role:Refresh()
		main():Open("Settings")
		truthy(main().hosts.Settings.notify:IsShown())
		truthy(main().hosts.Settings.privacy:IsShown())
	end)
end)

describe("the panel in the game's Settings window", function()
	local registered

	local function fakeApi(opts)
		opts = opts or {}
		registered = { opened = {} }
		return {
			RegisterCanvasLayoutCategory = function(frame, name)
				if opts.fail then error("boom") end
				registered.frame, registered.name = frame, name
				return { GetID = function() return 77 end }
			end,
			RegisterAddOnCategory = function(category) registered.category = category end,
			OpenToCategory = function(id) registered.opened[#registered.opened + 1] = id end,
		}
	end

	local function fresh()
		M().category, M().api, M().panelStatus = nil, nil, nil
	end

	it("is not there on a client without the API: nothing breaks and /gf debug says so", function()
		eq(M().panelStatus, "unavailable")
		fresh()
		local ok, why = A().SettingsPage.RegisterPanel()
		eq(ok, false); eq(why, "unavailable")
		falsy(M().OpenPanel())
		Mock.Slash("/gf debug")
		contains(table.concat(Mock.PlainOutput(), "\n"), "game panel: unavailable")
		eq(#Mock.errors, 0)
	end)

	it("is not there when the API is only half present", function()
		fresh()
		local ok = M().RegisterPanel(function() error("must not be built") end, { RegisterCanvasLayoutCategory = function() end })
		eq(ok, false)
		eq(M().panelStatus, "unavailable")
	end)

	it("a registration that raises is swallowed", function()
		fresh()
		local ok, why = M().RegisterPanel(function(name) return { name = name } end, fakeApi({ fail = true }))
		eq(ok, false); eq(why, "failed")
		eq(M().panelStatus, "failed")
	end)

	it("registers a canvas category named after the addon, once", function()
		fresh()
		local api = fakeApi()
		truthy(M().RegisterPanel(function(name) return { name = name } end, api))
		eq(registered.name, "Azeroth Guild Finder")
		truthy(registered.category)
		local frame = registered.frame
		truthy(M().RegisterPanel(function() error("twice") end, api))
		eq(registered.frame, frame)
	end)

	it("is registered at login when the client has the API, and /gf debug says so", function()
		fresh()
		_G.Settings = fakeApi()
		local ok = A().SettingsPage.RegisterPanel()
		_G.Settings = nil
		truthy(ok)
		eq(registered.frame:GetName(), "AzerothGuildFinderSettingsPanel")
		eq(M().panelStatus, "registered")
		Mock.Slash("/gf debug")
		contains(table.concat(Mock.PlainOutput(), "\n"), "game panel: registered")
	end)

	it("draws the same options as the page of the window, and they act the same", function()
		fresh()
		_G.Settings = fakeApi()
		A().SettingsPage.RegisterPanel()
		_G.Settings = nil
		local frame = registered.frame
		Mock.RunScript(frame, "OnShow")
		local c = frame.view.controls
		for _, key in ipairs(KEYS) do truthy(c[key], key) end
		main():Open("Settings")
		for _, key in ipairs(KEYS) do truthy(main().hosts.Settings.settings.controls[key], key) end
		click(c.minimapButton)
		falsy(minimapShown())
		falsy(main().hosts.Settings.settings.controls.minimapButton:GetChecked())   -- the other view follows
		eq(#Mock.errors, 0)
	end)

	it("its Defaults button restores every option", function()
		fresh()
		_G.Settings = fakeApi()
		A().SettingsPage.RegisterPanel()
		_G.Settings = nil
		local frame = registered.frame
		Mock.RunScript(frame, "OnShow")
		M().Set("uiScale", 0.6)
		M().Set("sound", false)
		frame.OnDefault()
		eq(M().Get("uiScale"), 1)
		eq(M().Get("sound"), true)
		truthy(frame.view.controls.sound:GetChecked())
	end)

	it("OpenPanel asks the game to open the category by its id", function()
		fresh()
		truthy(M().RegisterPanel(function(name) return { name = name } end, fakeApi()))
		truthy(M().OpenPanel())
		deepEq(registered.opened, { 77 })
	end)
end)
