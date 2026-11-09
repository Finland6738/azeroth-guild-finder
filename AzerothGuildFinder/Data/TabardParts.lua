-- TabardParts: the catalogue of the pieces an emblem is built from (SPEC-08 §2, ADR 0007). Lua 5.1, numbers only.
--
-- !! PROVISIONAL, pending M0.7 !!
-- The real list of the game's tabard pieces comes from the in-game probe (`/agfp tabard`, then `/agfp export tabard`, check S8
-- of docs/spike/README.md), which has not been run yet. Until then this file holds what the specification, the spike notes and
-- the probe already name, and every entry is marked `verify`. M0.7 updates THIS FILE ONLY (the block "M0.7: update here"
-- below): the fileIDs of the emblems and borders, the real counts and the real colour lists. Nothing else in the addon
-- hard-codes a piece: the renderer, the designer, Random and the validation all read these tables.
--
-- What travels in a listing is never a fileID but an INDEX into these lists (`emb.e`, `emb.b`, SPEC-08 §2.2), like the banner
-- index `bg`: indices are stable, never reused, and an index this version does not know is drawn with the fallback (no
-- border, or the guild's initial instead of the emblem). Colours travel as 24-bit RGB (0xRRGGBB) and are drawn as they are,
-- so a colour that is not in a palette below (a guild tabard's own) is still drawn exactly.
--
-- Nothing here is a copy of a game file: the game's pieces are referenced by path or fileID and drawn by the client from its
-- own archives; the pieces marked `media` are the addon's own textures (tools/make_media.py, ADR 0020). Albion Online's art is
-- not used at all, only the idea of its designer. The tabard's Save() is never called anywhere in the addon.
local ADDON_NAME, ns = ...
ns = ns or {}
local Parts = {}
ns.TabardParts, ns.modules = Parts, ns.modules or {}
ns.modules.TabardParts = Parts

---------------------------------------------------------------------------------------------------------------------
-- M0.7: update here
---------------------------------------------------------------------------------------------------------------------
Parts.PROVISIONAL = true      -- set to false (and write the date in VERIFIED) once the probe results are in
Parts.VERIFIED = nil          -- "YYYY-MM-DD" of the in-game check

-- Emblems of the game: index i (0-based, the same number as the game's `emblemStyle` of GetGuildTabardInfo) is drawn either
-- from its own fileID (Parts.EMBLEM_FILES[i], filled by M0.7) or from cell i of the guild window's emblem sheet, the way the
-- game's own SetLargeGuildTabardTextures does (a 1024 x 1024 sheet of 64 px cells, 16 per row). Whether the sheet exists on
-- Forever is check S9 [verify]; when the client cannot load it the designer offers only the addon's own symbols.
Parts.EMBLEM_SHEET = { path = "Interface\\GuildFrame\\GuildEmblemsLG_01", columns = 16, cell = 64 / 1024, verify = true }
Parts.EMBLEM_COUNT = 160      -- indices 0..159 [verify]: a guess until the probe counts the emblem variation
Parts.EMBLEM_FILES = {}       -- [index] = fileID, from the probe's emblem variation (UE); wins over the sheet

-- Border styles: index (0-based, the game's border style order once known). `media` is the addon's own drawing of the style,
-- used while `file` (the game's border texture, from the probe's border variation UB) is unknown or does not load.
Parts.BORDERS = {
	[0] = { key = "solid", media = "emblem_border_0" },
	[1] = { key = "thin", media = "emblem_border_1" },
	[2] = { key = "double", media = "emblem_border_2" },
	[3] = { key = "studded", media = "emblem_border_3" },
	[4] = { key = "bold", media = "emblem_border_4" },
	[5] = { key = "notched", media = "emblem_border_5" },
}
Parts.BORDER_COUNT = 6
Parts.TABARD_BORDER = 0       -- the style used for a guild tabard while the probe has not told how to read the tabard's own

-- Colour palettes of the designer (0xRRGGBB). Provisional: the colours of the mockup (07-emblem-designer); M0.7 may replace
-- them with the tabard vendor's lists. Changing a palette never changes a published emblem (the RGB travels).
Parts.COLORS = {
	background = { 0x141C2C, 0x4A1414, 0x1F3A58, 0x1D3A22, 0x3A2450, 0x5A3A14, 0x14090A, 0xF1ECE0, 0xC9A06A, 0x8A1D1D,
		0x2A64BD, 0x2E7D32, 0x6B6B6B, 0xD07A2A },
	border = { 0xE3B43D, 0xD7DDE4, 0x1B1B1B, 0x8A1D1D, 0xF1ECE0, 0x5A3A14, 0x2A64BD, 0x2E7D32 },
	emblem = { 0xE3B43D, 0xFFFFFF, 0x1B1B1B, 0xB3171D, 0x9BD1FF, 0x7AD67A, 0xC49BFF, 0xF08A24 },
}

---------------------------------------------------------------------------------------------------------------------
-- The addon's own symbols (stable, not provisional)
---------------------------------------------------------------------------------------------------------------------
-- Drawn by tools/make_media.py, so they work on any client; they come after the game's emblems in the designer and keep the
-- designer usable when the game's sheet cannot be loaded. Their indices start at OWN_BASE, far above any game emblem.
Parts.OWN_BASE = 1000
Parts.OWN_EMBLEMS = {
	[1000] = { key = "star", media = "emblem_sym_star" },
	[1001] = { key = "star8", media = "emblem_sym_star8" },
	[1002] = { key = "sun", media = "emblem_sym_sun" },
	[1003] = { key = "cross", media = "emblem_sym_cross" },
	[1004] = { key = "crescent", media = "emblem_sym_crescent" },
	[1005] = { key = "sword", media = "emblem_sym_sword" },
	[1006] = { key = "crown", media = "emblem_sym_crown" },
	[1007] = { key = "tower", media = "emblem_sym_tower" },
}
Parts.OWN_COUNT = 8

-- The highest index a listing may carry for `e`, `b` and `g` (validation; larger numbers are refused, not clamped).
Parts.MAX_INDEX = 1023

-- The emblem a new design starts from, and the neutral shield of a listing without a valid emblem (gold initial).
Parts.DEFAULT = { t = 2, e = 1006, b = 0, gc = 0x1F3A58, bc = 0xD7DDE4, ec = 0xE3B43D }
Parts.NEUTRAL = { gc = 0x2B3547, ec = 0xE3B43D }

---------------------------------------------------------------------------------------------------------------------
-- Lookups (pure)
---------------------------------------------------------------------------------------------------------------------
local type, pairs, floor = type, pairs, math.floor

local function isIndex(i) return type(i) == "number" and i == floor(i) and i >= 0 and i <= Parts.MAX_INDEX end

-- How to draw emblem `index`: { file = fileID } | { path, coords = { l, r, t, b } } | { media = name } | nil (unknown).
function Parts.Emblem(index)
	if not isIndex(index) then return nil end
	local own = Parts.OWN_EMBLEMS[index]
	if own then return { media = own.media, own = true, key = own.key } end
	if index >= Parts.EMBLEM_COUNT then return nil end
	local file = Parts.EMBLEM_FILES[index]
	if type(file) == "number" and file > 0 then return { file = file } end
	local sheet = Parts.EMBLEM_SHEET
	local col, row = index % sheet.columns, floor(index / sheet.columns)
	local c = sheet.cell
	return { path = sheet.path, coords = { col * c, (col + 1) * c, row * c, (row + 1) * c } }
end

-- How to draw border style `index`: { file = fileID, media = own } | { media = own } | nil (unknown).
function Parts.Border(index)
	if not isIndex(index) then return nil end
	local entry = Parts.BORDERS[index]
	if type(entry) ~= "table" then return nil end
	return { file = type(entry.file) == "number" and entry.file or nil, media = entry.media, key = entry.key }
end

-- The emblem index of a game fileID (a tabard read before M0.7 may name the emblem only by its file); nil when unknown.
function Parts.EmblemIndexOfFile(file)
	if type(file) ~= "number" then return nil end
	for index, f in pairs(Parts.EMBLEM_FILES) do
		if f == file then return index end
	end
	return nil
end

-- Every emblem index the designer offers, in order: the game's (0..EMBLEM_COUNT-1, unless `gameLoads` is false), then ours.
function Parts.EmblemList(gameLoads)
	local list = {}
	if gameLoads ~= false then
		for i = 0, Parts.EMBLEM_COUNT - 1 do list[#list + 1] = i end
	end
	for i = Parts.OWN_BASE, Parts.OWN_BASE + Parts.OWN_COUNT - 1 do list[#list + 1] = i end
	return list
end

if ns.addon then ns.addon.TabardParts = Parts end
