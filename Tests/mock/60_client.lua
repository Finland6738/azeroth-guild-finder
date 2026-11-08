-- Mock client, part 7: the player, the client build and the addon manager.
--
-- Imitates: Ambiguate, UnitName, UnitFullName, UnitGUID, UnitLevel, UnitClass, UnitRace, UnitFactionGroup, UnitIsUnit, GetRealmName,
-- GetNormalizedRealmName, GetLocale, GetBuildInfo, WOW_PROJECT_ID / WOW_PROJECT_CAMELOT, IsLoggedIn, GetAddOnMetadata,
-- C_AddOns.GetAddOnMetadata / IsAddOnLoaded, GetMaxPlayerLevel, GetAverageItemLevel.
-- Dump files: ../WoW-Addons/docs/api/ (Player-Character, AddOns-Scripting); api.json "meta" gives the build
-- (1.60.1, interface 16001). The numeric value of WOW_PROJECT_CAMELOT is not in the dump: use the constant, never a
-- number. GetMaxPlayerLevel and GetAverageItemLevel are "to verify" in the spec.
--
-- Configure with Mock.player (kept across Mock.Reload): name, realm (display name, may contain spaces), faction
-- ("Horde" or "Alliance"), level, classFile ("WARRIOR"), locale, maxLevel, loggedIn.
local Mock, H = ...
local W = Mock.world

W.player = W.player or {
	name = "Testchar", realm = "Test Realm", faction = "Horde", level = 60, classFile = "WARRIOR", classId = 1,
	race = "Orc", raceFile = "Orc", raceId = 2,
	locale = "enUS", maxLevel = 60, loggedIn = false, guid = "Player-1-0000A001",
}
local player = W.player
Mock.player = player

WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_CAMELOT = 99
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT

local CLASS_NAMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

local function isPlayer(unit) return unit == "player" or unit == nil end

function GetLocale() return player.locale end
function GetRealmName() return player.realm end
function GetNormalizedRealmName() return (player.realm:gsub("[%s%-']", "")) end
function GetBuildInfo() return "1.60.1", "70170", "Oct  1 2026", 16001, "1.60.1", "Release" end
function GetCurrentRegion() return 3 end   -- EU
function GetCurrentRegionName() return "EU" end

-- Ambiguate(fullName, context): "none" and "mail" drop the realm of the player's own realm, "short" drops every
-- realm, "all" keeps the name as it is.
function Ambiguate(fullName, context)
	local name, realm = fullName:match("^([^%-]+)%-(.+)$")
	if not name then return fullName end
	if context == "all" then return fullName end
	if context == "short" or realm == GetNormalizedRealmName() then return name end
	return fullName
end

function UnitName(unit)
	if isPlayer(unit) then return player.name, nil end
end
function UnitFullName(unit)
	if isPlayer(unit) then return player.name, GetNormalizedRealmName() end
end
function UnitGUID(unit) if isPlayer(unit) then return player.guid end end
function UnitLevel(unit) if isPlayer(unit) then return player.level end end
function UnitIsUnit(a, b) return isPlayer(a) and isPlayer(b) and a == b end
function UnitExists(unit) return isPlayer(unit) end
function UnitClass(unit)
	if isPlayer(unit) then return CLASS_NAMES[player.classFile] or player.classFile, player.classFile, player.classId end
end
function UnitRace(unit)
	if isPlayer(unit) then return player.race, player.raceFile, player.raceId end
end
function UnitFactionGroup(unit)
	if isPlayer(unit) then return player.faction, player.faction end   -- englishFaction, localizedFaction
end
function UnitAffectingCombat() return false end
function GetMaxPlayerLevel() return player.maxLevel end
function GetAverageItemLevel() return 0, 0, 0 end

function IsLoggedIn() return player.loggedIn end

-- AddOn metadata comes from the TOC the harness parsed.
local function getMetadata(name, field)
	if name == H.addonName then return H.tocFields[field] end
end
GetAddOnMetadata = getMetadata
C_AddOns = {
	GetAddOnMetadata = getMetadata,
	IsAddOnLoaded = function(name) return name == H.addonName or name == nil end,
}
function IsAddOnLoaded(name) return C_AddOns.IsAddOnLoaded(name) end
