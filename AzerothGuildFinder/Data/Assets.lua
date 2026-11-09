-- Assets: the registry of the game's own art that the addon uses (SPEC-08 §1, ADR 0007). Nothing from the client is
-- copied into the addon: each entry names a path (or an atlas) that the client already has. `verify` marks entries
-- that nobody has seen in the real client yet; the M0 texture gallery (check S9) and the M2 in-game checklist settle
-- them, and the entry is then edited here with the date. fileIDs are added as they are read in game. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Assets = {}
ns.Assets, ns.modules = Assets, ns.modules or {}
ns.modules.Assets = Assets

local type = type

-- Class icons: the texture Interface\Icons\ClassIcon_<Class> or the atlas classicon-<class>; which of the two exists
-- on Forever is open, so both are listed and the atlas wins when the client knows it (Assets.ClassIcon).
Assets.CLASSES = {
	WARRIOR = { name = "Warrior" }, PALADIN = { name = "Paladin" }, HUNTER = { name = "Hunter" },
	ROGUE = { name = "Rogue" }, PRIEST = { name = "Priest" }, SHAMAN = { name = "Shaman" },
	MAGE = { name = "Mage" }, WARLOCK = { name = "Warlock" }, DRUID = { name = "Druid" },
}
for file, entry in pairs(Assets.CLASSES) do
	entry.path = "Interface\\Icons\\ClassIcon_" .. entry.name
	entry.atlas = "classicon-" .. file:lower()
	entry.verify = true
end

-- Class colours when the client's RAID_CLASS_COLORS is not there (the same values as the mockups).
Assets.CLASS_COLORS = {
	WARRIOR = { 0.776, 0.608, 0.427 }, PALADIN = { 0.957, 0.549, 0.729 }, HUNTER = { 0.667, 0.827, 0.447 },
	ROGUE = { 1.000, 0.957, 0.408 }, PRIEST = { 0.961, 0.961, 0.961 }, SHAMAN = { 0.000, 0.439, 0.867 },
	MAGE = { 0.247, 0.780, 0.922 }, WARLOCK = { 0.529, 0.533, 0.933 }, DRUID = { 1.000, 0.486, 0.039 },
}

-- r, g, b of a class file name ("WARRIOR"); a neutral grey for an unknown class. The client's own table wins.
function Assets.ClassColor(file)
	local game = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[file]
	if type(game) == "table" and type(game.r) == "number" then return game.r, game.g, game.b end
	local c = Assets.CLASS_COLORS[file]
	if c then return c[1], c[2], c[3] end
	return 0.6, 0.6, 0.6
end

-- { atlas = "classicon-warrior" } when the client has that atlas, else { path = "Interface\\Icons\\ClassIcon_Warrior" };
-- nil for an unknown class.
function Assets.ClassIcon(file)
	local entry = Assets.CLASSES[file]
	if not entry then return nil end
	local getAtlas = ns.Compat and ns.Compat.Resolve and ns.Compat.Resolve("C_Texture.GetAtlasInfo")
	if type(getAtlas) == "function" then
		local ok, info = pcall(getAtlas, entry.atlas)
		if ok and info then return { atlas = entry.atlas } end
	end
	return { path = entry.path }
end

-- Banners: the art behind a guild card (SPEC-08 §3). A listing's `bg` is an index into this list; each entry is the
-- fileID of an image the client already has (loading screens, achievement and guild window backgrounds), never a path
-- into this addon and never a copy. The list is empty until the fileIDs are read in the real client (the M2 checklist
-- records them here, each with `verify` removed once seen): a card whose banner is unknown is drawn without one.
Assets.BANNERS = {}   -- [index] = { file = <fileID>, verify = true }

-- The fileID of banner `index`, or nil when it is not in the list.
function Assets.Banner(index)
	local entry = type(index) == "number" and Assets.BANNERS[index]
	return type(entry) == "table" and type(entry.file) == "number" and entry.file or nil
end

if ns.addon then ns.addon.Assets = Assets end
