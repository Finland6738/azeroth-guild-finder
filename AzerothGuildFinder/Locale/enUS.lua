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
L["HELP_DEBUG"] = "diagnostics: what your client allows the addon to do ('/gf debug ping' tests the channel)"
L["HELP_HELP"] = "show this list"
L["COMING_SOON"] = "coming soon"
L["UNKNOWN_COMMAND"] = "Unknown command '%s'. Type /gf help."

-- Channel and /gf debug ping
L["CHANNEL_LIMIT"] = "Could not join the hidden Guild Finder channel: you are already in the maximum of %d chat channels. Leave one with /leave and the addon joins by itself within a minute."
L["PING_SENT"] = "Ping sent on the channel, collecting answers for %d seconds..."
L["PING_NONE"] = "No peer answered within %d seconds. You may be the only player with the addon online, or the channel is not working (see /gf debug)."
L["PING_RESULT"] = "%d peer(s) answered. Round trip: shortest %d ms, average %d ms, longest %d ms."
L["PING_FAILED"] = "The ping could not be sent (%s)."
L["PING_BUSY"] = "A ping is already running."
L["PING_COOLDOWN"] = "Wait a little: one ping every %d seconds."
L["PING_NO_CHANNEL"] = "The channel is not joined yet (see /gf debug)."
