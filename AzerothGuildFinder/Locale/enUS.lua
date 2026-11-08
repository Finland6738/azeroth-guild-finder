-- English strings (default locale). Every visible string goes through L["KEY"].
local L = LibStub("AceLocale-3.0"):NewLocale("AzerothGuildFinder", "enUS", true)
if not L then return end

L["ADDON_TITLE"] = "Azeroth Guild Finder"
L["BINDING_TOGGLE"] = "Toggle Guild Finder"

-- Forever check
L["WARN_NOT_FOREVER"] = "This addon is built for WoW Forever (Interface 16001); this client was not recognised, so some features may not work."

-- Slash commands
L["HELP_HEADER"] = "Commands:"
L["HELP_TOGGLE"] = "open or close Guild Finder"
L["HELP_NOTIFY"] = "show or hide the applications notification icon"
L["HELP_RESET"] = "reset window positions"
L["HELP_DEBUG"] = "diagnostics: what your client allows the addon to do"
L["HELP_HELP"] = "show this list"
L["COMING_SOON"] = "coming soon"
L["UNKNOWN_COMMAND"] = "Unknown command '%s'. Type /gf help."
