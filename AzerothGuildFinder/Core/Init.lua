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
	{ name = "reset", help = L["HELP_RESET"], handler = function(self) self:ResetWindow() end },
	{ name = "scale", help = L["HELP_SCALE"], handler = function(self, input) self:OnScaleCommand(input) end },
	{ name = "debug", help = L["HELP_DEBUG"], handler = function(self, input) self:OnDebugCommand(input) end },
	{ name = "help", help = L["HELP_HELP"], handler = function(self) self:PrintHelp() end },
}

-- /gf debug sections: modules add a function returning text lines (never player or guild names).
AGF.debugSections = {}
function AGF:AddDebugSection(title, linesFn)
	for _, s in ipairs(self.debugSections) do
		if s.title == title then s.linesFn = linesFn return end
	end
	self.debugSections[#self.debugSections + 1] = { title = title, linesFn = linesFn }
end

function AGF:PrintDebug()
	local version = ns.Compat and select(2, ns.Compat.Call("C_AddOns.GetAddOnMetadata", ADDON_NAME, "Version"))
	self:Print("Debug - version " .. tostring(version or "?"))
	for _, section in ipairs(self.debugSections) do
		local ok, lines = pcall(section.linesFn)
		if not ok then lines = { "error: " .. tostring(lines):sub(1, 120) } end
		self:Print(section.title .. ":")
		for _, line in ipairs(lines or {}) do self:Print(line) end
	end
end

-- /gf debug [ping|announce|gallery|seed]: the diagnostics, the channel check, a test listing, the widget gallery, or fake
-- listings for the list (the last three in development builds only).
function AGF:OnDebugCommand(input)
	local sub = tostring(input or ""):lower():match("^%s*%S+%s+(%S+)")
	if sub == "ping" then
		if ns.Ping then return ns.Ping:Command() end
		return self:Print(L["COMING_SOON"])
	end
	if sub == "gallery" then
		if ns.Gallery then return ns.Gallery:Open() end
		return self:Print(L["COMING_SOON"])
	end
	if sub == "seed" then
		local argument = tostring(input or ""):match("^%s*%S+%s+%S+%s+(%S+)")
		if ns.Seed then return ns.Seed:Command(argument) end
		return self:Print(L["COMING_SOON"])
	end
	if sub == "announce" then
		if ns.Sync then return ns.Sync:DebugAnnounce() end
		return self:Print(L["COMING_SOON"])
	end
	self:PrintDebug()
end

-- Opens or closes the main window (UI/Main.lua): the same call serves /gf, the key binding, the Addon Compartment
-- and the minimap button.
function AGF:Toggle()
	if ns.Main then return ns.Main:Toggle() end
	self:Print(L["COMING_SOON"])
end

function AGF:ResetWindow()
	if not ns.Main then return self:Print(L["COMING_SOON"]) end
	ns.Main:ResetPosition()
	self:Print(L["RESET_DONE"])
end

-- /gf scale [60-140]
function AGF:OnScaleCommand(input)
	if not ns.Main then return self:Print(L["COMING_SOON"]) end
	local _, value = self:GetArgs(input or "", 2)
	ns.Main:ScaleCommand(value)
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
	if ns.Config then ns.Config:Load() end   -- ADDON_LOADED: SavedVariables are available now
	self:RegisterChatCommand("gf", "OnSlashCommand")
	self:RegisterChatCommand("guildfinder", "OnSlashCommand")
	if not self:IsForever() then
		self:Print(L["WARN_NOT_FOREVER"])  -- OnInitialize runs once per session
	end
end

function AGF:OnEnable()
	if ns.Compat then ns.Compat:Probe() end   -- PLAYER_LOGIN: the capability table for /gf debug and later modules
	if ns.Entry then ns.Entry:Register() end  -- the minimap button
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
	if ns.Entry then
		ns.Entry.FillTooltip(GameTooltip)
	else
		GameTooltip:SetText(L["ADDON_TITLE"])
	end
	GameTooltip:Show()
end

function AzerothGuildFinder_OnAddonCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end
