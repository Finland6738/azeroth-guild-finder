-- Entry: the ways to open the window (SPEC-04 §3). Lua 5.1.
--   /gf and /guildfinder       Core/Init.lua (AGF:Toggle)
--   key binding                Bindings.xml "Toggle Guild Finder" -> AzerothGuildFinder_ToggleBinding (Core/Init.lua)
--   Addon Compartment          the TOC functions -> AzerothGuildFinder_OnAddonCompartmentClick (Core/Init.lua)
--   minimap button             this file: a LibDataBroker launcher shown by LibDBIcon
-- The minimap button: left click opens or closes the window, right click opens Settings, drag moves it around the
-- minimap (LibDBIcon saves the angle in AzerothGuildFinderCharDB.minimap). The tooltip lists the clicks and, for the
-- Guild Master and officers, the pending applications (Main.pendingProvider, set by the applications step).
local ADDON_NAME, ns = ...
ns = ns or {}
local Entry = {}
ns.Entry, ns.modules = Entry, ns.modules or {}
ns.modules.Entry = Entry

local L = ns.L
local LDB_NAME = "AzerothGuildFinder"
local ICON = "Interface\\Icons\\INV_Misc_Note_01"

Entry.LDB_NAME = LDB_NAME

-- The tooltip of the minimap button and of the Addon Compartment entry: fills `tooltip` (a GameTooltip).
function Entry.FillTooltip(tooltip)
	tooltip:AddLine(L["ADDON_TITLE"], 1, 0.93, 0.76)
	tooltip:AddLine(L["MINIMAP_LEFT"], 0.9, 0.9, 0.9)
	tooltip:AddLine(L["MINIMAP_RIGHT"], 0.9, 0.9, 0.9)
	local pending = ns.Main and ns.Main:GetPendingCount() or 0
	local role = ns.Role and ns.Role:Get()
	if pending > 0 and (role == "gm" or role == "officer") then
		tooltip:AddLine(L["MINIMAP_PENDING"]:format(pending), 0.95, 0.75, 0.24)
	end
end

local function onClick(_, button)
	if not ns.Main then return end
	if button == "RightButton" then ns.Main:Open("Settings") else ns.Main:Toggle() end
end

-- Registers the launcher. Safe to call again; returns true when the button is registered. A missing library turns the
-- minimap button off and nothing else.
function Entry:Register()
	if self.registered then return true end
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	local config = ns.Config
	if not (ldb and icon and config and config.db and config.db.char) then return false end
	self.object = ldb:NewDataObject(LDB_NAME, {
		type = "launcher", text = L["ADDON_TITLE"], icon = ICON,
		OnClick = onClick,
		OnTooltipShow = Entry.FillTooltip,
	})
	if not self.object then return false end
	local db = config.db.char.minimap
	db.hide = config:Get("account.settings.minimapButton") == false   -- the account setting decides for every character
	icon:Register(LDB_NAME, self.object, db)
	self.icon, self.registered = icon, true
	return true
end

-- Shows or hides the minimap button and remembers the choice (the Settings page calls this).
function Entry:SetMinimapShown(shown)
	local config = ns.Config
	if config then
		config:Set("account.settings.minimapButton", shown and true or false)
		config:Set("char.minimap.hide", not shown)
	end
	if self.icon then
		if shown then self.icon:Show(LDB_NAME) else self.icon:Hide(LDB_NAME) end
	end
end

function Entry:IsMinimapShown()
	local button = self.icon and self.icon:GetMinimapButton(LDB_NAME)
	return button ~= nil and button:IsShown()
end

if ns.addon then ns.addon.Entry = Entry end
