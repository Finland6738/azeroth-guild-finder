-- Enums: the closed lists of the data model (SPEC-03 §5, ADR 0012), in one file. Lua 5.1 (no bit operators: masks use arithmetic).
-- The ids written here travel on the network and are stored: an index is never reused or renumbered.
local ADDON_NAME, ns = ...
ns = ns or {}
local E = {}
ns.Enums, ns.modules = E, ns.modules or {}
ns.modules.Enums = E

local type, pairs, ipairs, floor = type, pairs, ipairs, math.floor

---------------------------------------------------------------------------------------------------------------------
-- Languages: one bit each; `lang1` (the main one) is the index, `lang` the mask of all of them.
---------------------------------------------------------------------------------------------------------------------
E.LANGUAGES = {   -- index = position; label key LANG_<key>
	{ key = "en" }, { key = "de" }, { key = "fr" }, { key = "es" }, { key = "it" },
	{ key = "pt" }, { key = "ru" }, { key = "pl" }, { key = "other" },
}
E.LANGUAGE_COUNT = #E.LANGUAGES
E.LANGUAGE_MASK = 2 ^ E.LANGUAGE_COUNT - 1   -- 511

-- The bit value of language index i (1 -> 1, 2 -> 2, 3 -> 4, ...); nil for an invalid index.
function E.LanguageBit(i)
	if type(i) ~= "number" or i ~= floor(i) or i < 1 or i > E.LANGUAGE_COUNT then return nil end
	return 2 ^ (i - 1)
end

---------------------------------------------------------------------------------------------------------------------
-- Activities (`tags`, 1 to 3 per guild, in order of importance). Index stable forever; label key ACTIVITY_<id>.
-- `verify`: to be confirmed against the content really present on Forever before release (the entry disappears if absent).
---------------------------------------------------------------------------------------------------------------------
E.ACTIVITIES = {
	{ id = 1, key = "raids" }, { id = 2, key = "dungeons" }, { id = 3, key = "leveling" },
	{ id = 4, key = "questing" }, { id = 5, key = "battlegrounds" }, { id = 6, key = "worldpvp" },
	{ id = 7, key = "professions" }, { id = 8, key = "trading" }, { id = 9, key = "collecting" },
	{ id = 10, key = "roleplay" }, { id = 11, key = "social" }, { id = 12, key = "events" },
	{ id = 13, key = "housing", verify = true },
}
E.ACTIVITY_COUNT = #E.ACTIVITIES
E.MAX_TAGS = 3

function E.IsActivity(id)
	return type(id) == "number" and id == floor(id) and id >= 1 and id <= E.ACTIVITY_COUNT
end

---------------------------------------------------------------------------------------------------------------------
-- Commitment (`pace`, required): the guild's commitment, not permadeath. Label keys PACE_<id>, tooltip PACE_<id>_TIP.
---------------------------------------------------------------------------------------------------------------------
E.PACE = { CASUAL = 1, SOFTCORE = 2, HARDCORE = 3 }
E.PACE_COUNT = 3

function E.IsPace(v)
	return type(v) == "number" and v == floor(v) and v >= 1 and v <= E.PACE_COUNT
end

---------------------------------------------------------------------------------------------------------------------
-- Recruiting state (`rec`): closed / open / only some classes or roles.
---------------------------------------------------------------------------------------------------------------------
E.RECRUITING = { CLOSED = 0, OPEN = 1, SOME = 2 }

---------------------------------------------------------------------------------------------------------------------
-- Roles: bit masks (Tank 1, Healer 2, Melee DPS 4, Ranged DPS 8). Label keys ROLE_<key>.
---------------------------------------------------------------------------------------------------------------------
E.ROLES = {
	{ bit = 1, key = "tank" }, { bit = 2, key = "healer" }, { bit = 4, key = "melee" }, { bit = 8, key = "ranged" },
}
E.ROLE = { TANK = 1, HEALER = 2, MELEE = 4, RANGED = 8 }
E.ROLE_MASK = 15

-- Intersection of two masks (0..15), without bit operators.
function E.MaskAnd(a, b)
	local r, bit = 0, 1
	for _ = 1, 4 do
		if floor(a / bit) % 2 == 1 and floor(b / bit) % 2 == 1 then r = r + bit end
		bit = bit * 2
	end
	return r
end

-- true when the role bit `bit` is set in `mask`.
function E.HasRole(mask, bit)
	return type(mask) == "number" and type(bit) == "number" and floor(mask / bit) % 2 == 1
end

-- The mask as a list of bits, in role order.
function E.RoleList(mask)
	local list = {}
	for _, r in ipairs(E.ROLES) do
		if E.HasRole(mask, r.bit) then list[#list + 1] = r.bit end
	end
	return list
end

-- A role mask as a number 1..15 (integer); nil otherwise.
function E.IsRoleMask(v)
	return type(v) == "number" and v == floor(v) and v >= 1 and v <= E.ROLE_MASK
end

---------------------------------------------------------------------------------------------------------------------
-- Classes: ids as in the client (C_CreatureInfo.GetClassInfo). The list is read from the client through Compat; the
-- static one below is the fallback and the source of the role table. A class the table does not know allows every
-- role (a client newer than this file must not lose data).
---------------------------------------------------------------------------------------------------------------------
-- classID -> { key, roles = valid role mask }. Combinations to be confirmed with Forever's content [verify].
E.CLASS_ROLES = {
	[1] = { key = "WARRIOR", roles = 1 + 4 },
	[2] = { key = "PALADIN", roles = 1 + 2 + 4 },
	[3] = { key = "HUNTER", roles = 8 },
	[4] = { key = "ROGUE", roles = 4 },
	[5] = { key = "PRIEST", roles = 2 + 8 },
	[7] = { key = "SHAMAN", roles = 2 + 4 + 8 },
	[8] = { key = "MAGE", roles = 8 },
	[9] = { key = "WARLOCK", roles = 8 },
	[11] = { key = "DRUID", roles = 1 + 2 + 4 + 8 },
}
E.FALLBACK_CLASSES = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }

-- Faction restriction [verify on Forever]: Paladin is Alliance only, Shaman Horde only (original game).
E.CLASS_FACTION = { [2] = "Alliance", [7] = "Horde" }
E.FACTIONS = { Alliance = true, Horde = true }

-- Valid role mask of a class (15 for an unknown class).
function E.ValidRoles(classID)
	local c = E.CLASS_ROLES[classID]
	return c and c.roles or E.ROLE_MASK
end

-- `mask` reduced to the roles `classID` can play; classID 0 means any class (only the mask range is applied).
function E.FilterRoles(classID, mask)
	if type(mask) ~= "number" then return 0 end
	mask = floor(mask) % 16
	if classID == 0 then return mask end
	return E.MaskAnd(mask, E.ValidRoles(classID))
end

-- The playable class ids, ascending: from the client through Compat, else the static list.
function E.ClassIds()
	local compat = ns.Compat
	local list = compat and compat.Classes and compat.Classes()
	local ids = {}
	if list then
		for _, c in ipairs(list) do ids[#ids + 1] = c.id end
	else
		for _, id in ipairs(E.FALLBACK_CLASSES) do ids[#ids + 1] = id end
	end
	return ids
end

-- true when this class can be played by `faction` ("Alliance" | "Horde"); an unknown faction restricts nothing.
function E.ClassInFaction(classID, faction)
	local only = E.CLASS_FACTION[classID]
	if not only or not E.FACTIONS[faction] then return true end
	return only == faction
end

-- The class ids offered to a faction (editor and filters), ascending.
function E.ClassesForFaction(faction)
	local out = {}
	for _, id in ipairs(E.ClassIds()) do
		if E.ClassInFaction(id, faction) then out[#out + 1] = id end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Labels (AceLocale keys; the key itself when the locale lacks it)
---------------------------------------------------------------------------------------------------------------------
local function L(key)
	local locale = ns.L
	if not locale then return key end
	local v = locale[key]
	return v or key
end

function E.LanguageLabel(i) local l = E.LANGUAGES[i] return l and L("LANG_" .. l.key) or nil end
function E.ActivityLabel(id) return E.IsActivity(id) and L("ACTIVITY_" .. id) or nil end
function E.PaceLabel(v) return E.IsPace(v) and L("PACE_" .. v) or nil end
function E.PaceTip(v) return E.IsPace(v) and L("PACE_" .. v .. "_TIP") or nil end
function E.RoleLabel(bit)
	for _, r in ipairs(E.ROLES) do
		if r.bit == bit then return L("ROLE_" .. r.key) end
	end
	return nil
end
-- Class name: the client's own (localized) name, else our label.
function E.ClassLabel(classID)
	local compat = ns.Compat
	local list = compat and compat.Classes and compat.Classes()
	if list then
		for _, c in ipairs(list) do
			if c.id == classID and c.name then return c.name end
		end
	end
	local c = E.CLASS_ROLES[classID]
	return c and L("CLASS_" .. c.key) or nil
end

if ns.addon then ns.addon.Enums = E end
