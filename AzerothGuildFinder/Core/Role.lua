-- Role: what the character is in its guild (SPEC-00 §5, ADR 0004) and which panels it may see. Lua 5.1.
-- The role comes only from the client, through Compat. It is recomputed on the guild events and ROLE_CHANGED is
-- emitted on the Bus only when the role or the guild key changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Role = {}
ns.Role, ns.modules = Role, ns.modules or {}
ns.modules.Role = Role

Role.NONE, Role.MEMBER, Role.OFFICER, Role.GM = "none", "member", "officer", "gm"

-- Panel names (the UI maps them to tabs).
Role.PANELS = {
	FIND = "FindGuild", APPLICATION = "MyApplication", GUILD = "MyGuild", CREATE = "CreateListing", APPLICATIONS = "Applications",
}

Role.EVENTS = { "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILD_RANKS_UPDATE", "PLAYER_ENTERING_WORLD" }

local current = { role = "none", guildKey = nil }
local computed = false

-- Reads the client: role, guildKey (nil without a guild or when the realm, faction or guild name is unknown).
function Role.Compute()
	local Compat = ns.Compat
	local role, key = "none", nil
	if Compat and Compat.Guild.InGuild() then
		if Compat.Guild.IsGuildLeader() then role = "gm"
		elseif Compat.Guild.IsOfficer() then role = "officer"
		else role = "member" end
		local realm, faction, name = Compat.Player.Realm(), Compat.Player.Faction(), Compat.Guild.GuildName()
		if realm and faction and name then key = realm .. "|" .. faction .. "|" .. name end
	end
	return role, key
end

-- Recomputes; emits ROLE_CHANGED only on a change. Returns true when something changed.
function Role:Refresh()
	local role, key = Role.Compute()
	local oldRole, oldKey = current.role, current.guildKey
	local changed = role ~= oldRole or key ~= oldKey
	current.role, current.guildKey, computed = role, key, true
	if changed and ns.Bus then ns.Bus:Emit("ROLE_CHANGED", role, key, oldRole, oldKey) end
	return changed
end

function Role:Get()
	if not computed then Role:Refresh() end
	return current.role
end

function Role:GuildKey()
	if not computed then Role:Refresh() end
	return current.guildKey
end

-- The panels visible to `role` (SPEC-00 §5), in tab order. `hasListing`: the guild has a published listing.
-- Officers and the GM see Applications only when there is a listing; a member never does.
function Role.PanelsFor(role, hasListing)
	local P = Role.PANELS
	if role == "member" then return { P.GUILD } end
	if role == "officer" then
		if hasListing then return { P.GUILD, P.APPLICATIONS } end
		return { P.GUILD }
	end
	if role == "gm" then
		if hasListing then return { P.GUILD, P.APPLICATIONS } end
		return { P.CREATE }
	end
	return { P.FIND, P.APPLICATION }
end

function Role:Panels(hasListing)
	return Role.PanelsFor(Role:Get(), hasListing and true or false)
end

function Role:DebugLines()
	return { "Role: " .. Role:Get() .. ", in a guild: " .. (Role:GuildKey() and "yes" or "no") }
end

if ns.addon then
	ns.addon.Role = Role
	for _, event in ipairs(Role.EVENTS) do
		ns.addon:RegisterEvent(event, function() Role:Refresh() end)
	end
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Role", function() return Role:DebugLines() end) end
end
