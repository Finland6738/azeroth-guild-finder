-- Addon object, Forever check and slash commands. Later modules attach themselves to the shared namespace.
local ADDON_NAME, ns = ...
ns = ns or {}

-- Public namespace for later modules (Compat, Config, Net, Data, UI).
ns.modules = ns.modules or {}

local AGF = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
ns.addon, ns.L = AGF, L
_G.AzerothGuildFinder = AGF

local FOREVER_MIN_INTERFACE, FOREVER_MAX_INTERFACE = 16001, 19999

-- True on WoW Forever: the project id constant when the client has it, else the Interface number.
function AGF:IsForever()
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CAMELOT ~= nil then
		return WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
	end
	local build = select(4, GetBuildInfo())
	return type(build) == "number" and build >= FOREVER_MIN_INTERFACE and build <= FOREVER_MAX_INTERFACE
end

function AGF:Print(msg)
	self:Printf("|cffd4af37%s|r %s", L["ADDON_TITLE"], msg)
end

-- Commands planned for the first version; handlers are replaced by the modules that implement them.
AGF.commands = {
	{ name = "notify", help = L["HELP_NOTIFY"] },
	{ name = "reset", help = L["HELP_RESET"] },
	{ name = "debug", help = L["HELP_DEBUG"] },
	{ name = "help", help = L["HELP_HELP"], handler = function(self) self:PrintHelp() end },
}

function AGF:Toggle()
	self:Print(L["COMING_SOON"])
end

function AGF:PrintHelp()
	self:Print(L["HELP_HEADER"])
	self:Print("/gf - " .. L["HELP_TOGGLE"])
	for _, c in ipairs(self.commands) do
		self:Print("/gf " .. c.name .. " - " .. c.help)
	end
end

function AGF:OnSlashCommand(input)
	local cmd = (self:GetArgs(input or "", 1) or ""):lower()
	if cmd == "" then
		return self:Toggle()
	end
	for _, c in ipairs(self.commands) do
		if c.name == cmd then
			if c.handler then
				return c.handler(self, input)
			end
			return self:Print(L["COMING_SOON"])
		end
	end
	self:Print(L["UNKNOWN_COMMAND"]:format(cmd))
	self:PrintHelp()
end

function AGF:OnInitialize()
	self:RegisterChatCommand("gf", "OnSlashCommand")
	self:RegisterChatCommand("guildfinder", "OnSlashCommand")
	if not self:IsForever() then
		self:Print(L["WARN_NOT_FOREVER"])  -- OnInitialize runs once per session
	end
end

-- Key binding and AddOn Compartment entry points (globals named in the TOC and Bindings.xml).
BINDING_HEADER_AZGUILDFINDER = L["ADDON_TITLE"]
BINDING_NAME_AZGUILDFINDER_TOGGLE = L["BINDING_TOGGLE"]

function AzerothGuildFinder_ToggleBinding()
	AGF:Toggle()
end

function AzerothGuildFinder_OnAddonCompartmentClick()
	AGF:Toggle()
end

function AzerothGuildFinder_OnAddonCompartmentEnter(_, menuButtonFrame)
	if not GameTooltip then return end
	GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
	GameTooltip:SetText(L["ADDON_TITLE"])
	GameTooltip:Show()
end

function AzerothGuildFinder_OnAddonCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end
