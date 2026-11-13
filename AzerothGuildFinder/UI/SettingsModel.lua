-- Settings model (M5.1, SPEC-04 §4): the one definition of the options, shared by the Settings page of the window and the
-- panel in the game's own Settings window. No frames here; Lua 5.1.
--   Model.GROUPS, Model.OPTIONS      what is shown, in order: { key, kind = "toggle" | "scale", group, label, help, default }
--   Model.Default(key) Get(key) Set(key, value) -> true | false, reason      read and change (every change is applied)
--   Model.IsDefault(key) ResetPositions() ResetAll()                          reset (positions: window and notification icon)
--   Model.GroupVisible(group, role)   the Notifications group is for the Guild Master and the officers only
--   Model.RegisterPanel(makeFrame, api) Model.OpenPanel()                     the panel in Settings (needs Settings.RegisterCanvasLayoutCategory)
-- Values live in AzerothGuildFinderDB.settings (account wide), defaults come from Config.defaults. Applying a change is
-- done by the module that owns the effect (minimap button, window, notification icon, anonymous alt count); this file only
-- calls them, so the page, the panel, the slash commands and the minimap menu cannot disagree. A change is announced on
-- the Bus as SETTINGS_CHANGED(key, value) so every open view redraws.
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.SettingsModel, ns.modules = Model, ns.modules or {}
ns.modules.SettingsModel = Model

local type, ipairs, pcall = type, ipairs, pcall

Model.PANEL_NAME = "Azeroth Guild Finder"

Model.GROUPS = {
	{ key = "window", title = "SETTINGS_WINDOW", glyph = "glyph_gear" },
	{ key = "privacy", title = "SETTINGS_PRIVACY", glyph = "glyph_shield" },
	{ key = "notifications", title = "SETTINGS_NOTIFY", glyph = "glyph_inbox", note = "SETTINGS_NOTIFY_NOTE", officers = true },
}

Model.OPTIONS = {
	{ key = "uiScale", kind = "scale", group = "window", label = "SETTINGS_SCALE", help = "SETTINGS_SCALE_HELP" },
	{ key = "minimapButton", kind = "toggle", group = "window", label = "SETTINGS_MINIMAP", help = "SETTINGS_MINIMAP_HELP" },
	{ key = "shareAltCount", kind = "toggle", group = "privacy", label = "SETTINGS_SHARE_ALTS", help = "SETTINGS_SHARE_ALTS_HELP", showHelp = true },
	{ key = "notifyIcon", kind = "toggle", group = "notifications", label = "APPS_OPT_ICON", help = "APPS_OPT_ICON_HELP" },
	{ key = "onlyWhenPending", kind = "toggle", group = "notifications", label = "APPS_OPT_PENDING", help = "APPS_OPT_PENDING_HELP" },
	{ key = "sound", kind = "toggle", group = "notifications", label = "APPS_OPT_SOUND", help = "APPS_OPT_SOUND_HELP" },
}

local BY_KEY = {}
for _, option in ipairs(Model.OPTIONS) do BY_KEY[option.key] = option end

function Model.Option(key) return BY_KEY[key] end

function Model.OptionsOf(group)
	local list = {}
	for _, option in ipairs(Model.OPTIONS) do if option.group == group then list[#list + 1] = option end end
	return list
end

local function settingsDefaults()
	local config = ns.Config
	return config and config.defaults and config.defaults.account and config.defaults.account.settings or {}
end

function Model.Default(key)
	if not BY_KEY[key] then return nil end
	return settingsDefaults()[key]
end

function Model.Get(key)
	if not BY_KEY[key] then return nil end
	local value = ns.Config and ns.Config.db and ns.Config.db.account and ns.Config:Get("account.settings." .. key)
	if value == nil then value = Model.Default(key) end
	return value
end

function Model.IsDefault(key)
	return BY_KEY[key] ~= nil and Model.Get(key) == Model.Default(key)
end

function Model.GroupVisible(group, role)
	for _, g in ipairs(Model.GROUPS) do
		if g.key == group then
			if not g.officers then return true end
			return ns.AppsModel ~= nil and ns.AppsModel.CanSee(role or (ns.Role and ns.Role:Get()) or "none")
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- Applying a change
---------------------------------------------------------------------------------------------------------------------
local function emit(key, value)
	if ns.Bus then ns.Bus:Emit("SETTINGS_CHANGED", key, value) end
end

local function plainSet(key, value)
	if not ns.Config then return false, "nodb" end
	local ok, why = ns.Config:Set("account.settings." .. key, value)
	if ok == false then return false, why or "refused" end
	return true
end

local APPLY = {}

function APPLY.minimapButton(value)
	if ns.Entry then ns.Entry:SetMinimapShown(value) return true end
	return plainSet("minimapButton", value)
end

function APPLY.uiScale(value)
	if ns.Main then ns.Main:SetScale(value) return true end
	return plainSet("uiScale", value)
end

function APPLY.shareAltCount(value)
	if ns.Stats then return ns.Stats:SetSharing(value) end
	return plainSet("shareAltCount", value)
end

local function appsOption(key)
	return function(value)
		if ns.AppsModel then return ns.AppsModel.SetOption(key, value) end
		return plainSet(key, value)
	end
end
APPLY.notifyIcon, APPLY.onlyWhenPending, APPLY.sound = appsOption("notifyIcon"), appsOption("onlyWhenPending"), appsOption("sound")

-- Saves and applies one option. Returns true, or false and why ("unknown", "type", "read-only", ...).
function Model.Set(key, value)
	local option = BY_KEY[key]
	if not option then return false, "unknown" end
	if option.kind == "toggle" then
		if type(value) ~= "boolean" then return false, "type" end
	else
		if type(value) ~= "number" then return false, "type" end
		value = ns.Nav and ns.Nav.ClampScale(value) or value
	end
	if ns.Config and ns.Config:IsReadOnly("account") then return false, "read-only" end
	if Model.Get(key) == value then return true end
	local ok, why = APPLY[key](value)
	if ok == false then return false, why or "refused" end
	emit(key, value)
	return true
end

-- Window and notification icon back to their first places (the window's size is left alone: it is an option).
function Model.ResetPositions()
	if ns.Main then ns.Main:ResetPosition() end
	if ns.Notify then ns.Notify:ResetPosition() end
	emit("positions", true)
	return true
end

-- Every option back to its default, and the positions too (the "Defaults" button of the game's Settings window).
function Model.ResetAll()
	for _, option in ipairs(Model.OPTIONS) do Model.Set(option.key, Model.Default(option.key)) end
	Model.ResetPositions()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The panel in the game's Settings window
---------------------------------------------------------------------------------------------------------------------
-- Registers a canvas category when the client has the API; `makeFrame(name)` is called only then and returns the canvas
-- frame. Never raises. Returns true, or false and why: "unavailable" (no Settings API) or "failed".
function Model.RegisterPanel(makeFrame, api)
	if Model.category then return true end
	api = api or (ns.Compat and ns.Compat.Resolve("Settings"))
	if type(api) ~= "table" or type(api.RegisterCanvasLayoutCategory) ~= "function"
		or type(api.RegisterAddOnCategory) ~= "function" then
		Model.panelStatus = "unavailable"
		return false, "unavailable"
	end
	local ok, category = pcall(function()
		local frame = makeFrame(Model.PANEL_NAME)
		local cat = api.RegisterCanvasLayoutCategory(frame, Model.PANEL_NAME)
		api.RegisterAddOnCategory(cat)
		return cat
	end)
	if not ok or not category then
		Model.panelStatus = "failed"
		return false, "failed"
	end
	Model.category, Model.api, Model.panelStatus = category, api, "registered"
	return true
end

-- Opens the game's Settings window on our panel. Returns false when there is none.
function Model.OpenPanel()
	local api, category = Model.api, Model.category
	if not (api and category and type(api.OpenToCategory) == "function") then return false end
	local id = category.GetID and category:GetID() or category.ID or category
	return pcall(api.OpenToCategory, id) and true or false
end

function Model.DebugLines()
	local lines = {}
	for _, option in ipairs(Model.OPTIONS) do
		lines[#lines + 1] = ("%s = %s%s"):format(option.key, tostring(Model.Get(option.key)), Model.IsDefault(option.key) and "" or " (changed)")
	end
	return { "Settings: " .. table.concat(lines, ", ") .. "; game panel: " .. tostring(Model.panelStatus or "not tried") }
end

if ns.addon then
	ns.addon.SettingsModel = Model
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Settings", function() return Model.DebugLines() end) end
end
