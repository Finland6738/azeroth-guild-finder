-- Emblems: the rules of a guild emblem, without frames (SPEC-08 §2, ADR 0007). Lua 5.1, pure: the tests run all of it.
--
-- An emblem in a listing (`emb`, SPEC-03 §2) is a small table of numbers:
--   { t = 1 | 2,            1 = copied from the guild tabard, 2 = designed in Guild Finder (drawn the same way)
--     e = index,            emblem: an index of Data/TabardParts.lua (the game's emblems 0.., the addon's symbols 1000..)
--     b = index,            border style (TabardParts.BORDERS); no `b` = no border
--     g = index,            background style (reserved: the field is always the addon's shield, tinted `gc`)
--     gc, bc, ec = 0xRRGGBB  background, border and emblem colour }
--
--   Emblems.Sanitize(raw [, issues]) -> emb | nil    what is published and what is accepted from the network (Listing uses it)
--   Emblems.Encode(emb) / Decode(raw)                 the editor's emblem -> the wire table, and back (both Sanitize)
--   Emblems.Equal(a, b)                               same emblem (every field)
--   Emblems.Layers(emb, size, name)                   what to draw, in pixels, for a frame of `size` (every client the same)
--   Emblems.FromTabardInfo(info)                      C_GuildInfo.GetGuildTabardInfo's table -> emb (t = 1) | nil, why
--   Emblems.Random(rng [, emblems])  Emblems.Reset(published, tabard)  Emblems.ToCustom(emb)   the designer's buttons
--   Emblems.Initial(name)                             the letter of the fallback shield
local ADDON_NAME, ns = ...
ns = ns or {}
local Emblems = {}
ns.Emblems, ns.modules = Emblems, ns.modules or {}
ns.modules.Emblems = Emblems

local type, ipairs, rawget, tostring = type, ipairs, rawget, tostring
local floor, abs, huge, random = math.floor, math.abs, math.huge, math.random
local upper, byte = string.upper, string.byte

local function Parts() return ns.TabardParts end

Emblems.TABARD, Emblems.CUSTOM = 1, 2
Emblems.MAX_COLOR = 0xFFFFFF
Emblems.SIZES = { 48, 64, 96, 150 }      -- the four sizes the renderer is drawn for (cards, mini preview, page, designer)

---------------------------------------------------------------------------------------------------------------------
-- Numbers and colours
---------------------------------------------------------------------------------------------------------------------
local function isInt(v) return type(v) == "number" and v == v and v ~= huge and v ~= -huge and v == floor(v) end
local function isIndex(v) return isInt(v) and v >= 0 and v <= Parts().MAX_INDEX end
local function isColor(v) return isInt(v) and v >= 0 and v <= Emblems.MAX_COLOR end
Emblems.IsIndex, Emblems.IsColor = isIndex, isColor

-- 0xRRGGBB -> r, g, b in 0..1 (each exactly byte / 255, so every client computes the same floats).
function Emblems.RGB(c)
	if not isColor(c) then return nil end
	return floor(c / 65536) / 255, floor(c / 256) % 256 / 255, c % 256 / 255
end

-- r, g, b (0..1 floats, or 0..255 bytes when any is above 1) -> 0xRRGGBB; nil for anything that is not three numbers.
function Emblems.ColorInt(r, g, b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
	if r ~= r or g ~= g or b ~= b then return nil end
	local scale = (r > 1 or g > 1 or b > 1) and 1 or 255
	local function to(x)
		x = floor(x * scale + 0.5)
		if x < 0 then return 0 elseif x > 255 then return 255 end
		return x
	end
	return to(r) * 65536 + to(g) * 256 + to(b)
end

-- "#rrggbb" of a colour (the designer's swatches, debug lines).
function Emblems.Hex(c)
	if not isColor(c) then return nil end
	return ("#%06x"):format(c)
end

-- Relative luminance 0..1 (sRGB weights, no gamma: enough to keep an emblem readable on its background).
function Emblems.Luma(c)
	local r, g, b = Emblems.RGB(c)
	if not r then return 0 end
	return 0.299 * r + 0.587 * g + 0.114 * b
end
Emblems.MIN_CONTRAST = 0.25

---------------------------------------------------------------------------------------------------------------------
-- Validation, encode, decode
---------------------------------------------------------------------------------------------------------------------
local PIECES, COLORS = { "e", "b", "g" }, { "ec", "bc", "gc" }
Emblems.FIELDS = { "t", "e", "b", "g", "ec", "bc", "gc" }

local function issue(issues, why) if issues then issues[#issues + 1] = "emb: " .. why end end

-- A NEW table with only the known fields that passed; nil when the whole emblem is refused (not a table, unknown type, no
-- piece). Fields are read with rawget, so a table with a metatable cannot run code here. Never raises.
function Emblems.Sanitize(v, issues)
	if type(v) ~= "table" then issue(issues, "not a table") return nil end
	local t = rawget(v, "t")
	if t ~= 1 and t ~= 2 then issue(issues, "invalid type") return nil end
	local out, pieces = { t = t }, 0
	for _, f in ipairs(PIECES) do
		local x = rawget(v, f)
		if x ~= nil then
			if isIndex(x) then out[f] = x pieces = pieces + 1 else issue(issues, f .. " invalid") end
		end
	end
	for _, f in ipairs(COLORS) do
		local x = rawget(v, f)
		if x ~= nil then
			if isColor(x) then out[f] = x else issue(issues, f .. " invalid") end
		end
	end
	if pieces == 0 then issue(issues, "no texture piece") return nil end
	return out
end

-- The editor's emblem as it is published (the same rules as on receipt: what is sent is what others keep).
function Emblems.Encode(emb) return Emblems.Sanitize(emb) end
-- A received emblem, ready for Layers (nil: draw the neutral shield).
function Emblems.Decode(raw) return Emblems.Sanitize(raw) end

function Emblems.Equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for _, f in ipairs(Emblems.FIELDS) do
		if a[f] ~= b[f] then return false end
	end
	return true
end

local function copy(emb)
	local out = {}
	for _, f in ipairs(Emblems.FIELDS) do out[f] = emb[f] end
	return out
end
Emblems.Copy = copy

---------------------------------------------------------------------------------------------------------------------
-- The fallback letter
---------------------------------------------------------------------------------------------------------------------
-- The first character of the guild name (a whole UTF-8 character; ASCII letters upper-cased); "?" without a name.
function Emblems.Initial(name)
	if type(name) ~= "string" then return "?" end
	name = name:gsub("^[%s%c]+", "")
	local b = byte(name, 1)
	if not b then return "?" end
	if b < 0x80 then return upper(name:sub(1, 1)) end
	local n = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
	if n == 1 then return "?" end
	for i = 2, n do
		local c = byte(name, i)
		if not c or c < 0x80 or c > 0xBF then return "?" end
	end
	return name:sub(1, n)
end

---------------------------------------------------------------------------------------------------------------------
-- Rendering parameters
---------------------------------------------------------------------------------------------------------------------
-- The largest of SIZES that is not above `size` (48 for anything smaller): it picks the frame drawn for small sizes.
function Emblems.Tier(size)
	local tier = Emblems.SIZES[1]
	for _, s in ipairs(Emblems.SIZES) do
		if size >= s then tier = s end
	end
	return tier
end

local function round(x) return floor(x + 0.5) end

-- The emblem sits in the middle of the shield, a little above the centre (the shield narrows towards its point).
Emblems.EMBLEM_SCALE, Emblems.EMBLEM_CENTER_Y = 0.46, 0.484
Emblems.INITIAL_SCALE = 0.36

local function rgbOf(c, default)
	local r, g, b = Emblems.RGB(c)
	if r then return { r, g, b } end
	return { Emblems.RGB(default) }
end

-- The layers of an emblem `size` px square, bottom to top. Each layer: { id, rect = { x, y, w, h } (from the top left),
-- color = { r, g, b } (nil: untinted), and what to draw: media = <Media name> | file = <fileID> | path = <client path>
-- with coords = { left, right, top, bottom } }. A game piece has a `fallback` drawn when the client cannot load it:
-- the border falls back to the addon's own drawing of the style, the emblem to the guild's initial. The result depends only
-- on the arguments (and on TabardParts), so every client draws the same thing.
--   emb   a sanitized emblem, or nil / anything invalid for the neutral shield
--   name  the guild name (for the initial)
function Emblems.Layers(emb, size, name)
	size = (isInt(size) and size > 0) and size or Emblems.SIZES[1]
	emb = Emblems.Sanitize(emb)
	local P = Parts()
	local tier = Emblems.Tier(size)
	local full = { 0, 0, size, size }
	local out = { size = size, tier = tier, valid = emb ~= nil, layers = {} }
	local L = out.layers
	local neutral = P.NEUTRAL

	L[#L + 1] = { id = "field", media = "emblem_field", rect = full, color = rgbOf(emb and emb.gc, neutral.gc) }

	local border = emb and emb.b ~= nil and P.Border(emb.b) or nil
	if border then
		local color = rgbOf(emb.bc, 0xFFFFFF)
		local layer = { id = "border", rect = full, color = color, key = border.key }
		if border.file then
			layer.file, layer.fallback = border.file, { media = border.media }
		else
			layer.media = border.media
		end
		L[#L + 1] = layer
	end

	local w = round(size * Emblems.EMBLEM_SCALE)
	local rect = { round((size - w) / 2), round(size * Emblems.EMBLEM_CENTER_Y - w / 2), w, w }
	local ecolor = rgbOf(emb and emb.ec, neutral.ec)
	local piece = emb and emb.e ~= nil and P.Emblem(emb.e) or nil
	local initial = { id = "initial", text = Emblems.Initial(name), rect = rect, color = ecolor,
		fontPx = round(size * Emblems.INITIAL_SCALE) }
	if piece then
		local layer = { id = "emblem", rect = rect, color = ecolor, fallback = initial }
		if piece.file then layer.file = piece.file
		elseif piece.path then layer.path, layer.coords = piece.path, piece.coords
		else layer.media = piece.media end
		L[#L + 1] = layer
	else
		L[#L + 1] = initial
	end

	L[#L + 1] = { id = "gloss", media = "emblem_gloss", rect = full }
	L[#L + 1] = { id = "frame", media = tier <= 64 and "emblem_frame_small" or "emblem_frame", rect = full }
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The guild tabard
---------------------------------------------------------------------------------------------------------------------
-- A colour of the tabard info: a table with r, g, b (ColorMixin, 0..1) or a number 0xRRGGBB.
local function infoColor(c)
	if isColor(c) then return c end
	if type(c) ~= "table" then return nil end
	return Emblems.ColorInt(rawget(c, "r"), rawget(c, "g"), rawget(c, "b"))
end

-- The emblem of a guild tabard (t = 1), from GetGuildTabardInfo("player"): the colours, the emblem by its style index
-- (`emblemStyle`) or by its file (`emblemFileID`, through TabardParts), the border by `borderStyle` when the client gives
-- one, else TabardParts.TABARD_BORDER. The field names are the API's [verify in M0.7]. nil, why: "none" (no table),
-- "empty" (nothing usable in it).
function Emblems.FromTabardInfo(info)
	if type(info) ~= "table" then return nil, "none" end
	local P = Parts()
	local out = { t = Emblems.TABARD }
	out.gc = infoColor(rawget(info, "backgroundColor"))
	out.bc = infoColor(rawget(info, "borderColor"))
	out.ec = infoColor(rawget(info, "emblemColor"))
	local style = rawget(info, "emblemStyle")
	if isIndex(style) and style < P.OWN_BASE then out.e = style
	else out.e = P.EmblemIndexOfFile(rawget(info, "emblemFileID")) end
	local bstyle = rawget(info, "borderStyle")
	out.b = (isIndex(bstyle) and P.BORDERS[bstyle]) and bstyle or P.TABARD_BORDER
	if out.e == nil and out.gc == nil and out.ec == nil then return nil, "empty" end
	return Emblems.Sanitize(out), nil
end

---------------------------------------------------------------------------------------------------------------------
-- The designer's buttons
---------------------------------------------------------------------------------------------------------------------
-- A designed copy (t = 2) of any emblem; the default design for nothing.
function Emblems.ToCustom(emb)
	local clean = Emblems.Sanitize(emb)
	if not clean then return copy(Parts().DEFAULT) end
	clean.t = Emblems.CUSTOM
	return clean
end

-- Reset: back to the published design (when it was a designed one), else to the guild tabard's pieces, else the default.
function Emblems.Reset(published, tabard)
	local pub = Emblems.Sanitize(published)
	if pub and pub.t == Emblems.CUSTOM then return pub end
	local tab = Emblems.Sanitize(tabard)
	if tab then return Emblems.ToCustom(tab) end
	return copy(Parts().DEFAULT)
end

-- The colours of `palette` far enough from `against` in luminance (all but `against` itself when none is).
local function readable(palette, against)
	local list, lb = {}, Emblems.Luma(against)
	for _, c in ipairs(palette) do
		if abs(Emblems.Luma(c) - lb) >= Emblems.MIN_CONTRAST then list[#list + 1] = c end
	end
	if #list == 0 then
		for _, c in ipairs(palette) do if c ~= against then list[#list + 1] = c end end
	end
	if #list == 0 then list = palette end
	return list
end
Emblems.Readable = readable

-- Random: a design from the catalogue. `rng(n)` returns an integer 1..n (math.random by default; the tests pass a seeded
-- one); `emblems` is the list of emblem indices to pick from (TabardParts.EmblemList by default: the designer passes the
-- list without the game's emblems when the client cannot load them). The emblem and the border are always readable on the
-- background (MIN_CONTRAST).
function Emblems.Random(rng, emblems)
	rng = rng or function(n) return random(n) end
	local P = Parts()
	local function pick(list) return list[rng(#list)] end
	emblems = (type(emblems) == "table" and #emblems > 0) and emblems or P.EmblemList()
	local gc = pick(P.COLORS.background)
	return {
		t = Emblems.CUSTOM,
		e = pick(emblems),
		b = rng(P.BORDER_COUNT) - 1,
		gc = gc,
		bc = pick(readable(P.COLORS.border, gc)),
		ec = pick(readable(P.COLORS.emblem, gc)),
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Pages of the designer's emblem grid
---------------------------------------------------------------------------------------------------------------------
Emblems.PAGE_SIZE = 16      -- 8 x 2 tiles

-- The number of pages of `list`, and the indices on page `page` (1-based, clamped).
function Emblems.Page(list, page, pageSize)
	pageSize = pageSize or Emblems.PAGE_SIZE
	local pages = math.max(1, math.ceil(#list / pageSize))
	page = math.min(pages, math.max(1, isInt(page) and page or 1))
	local items = {}
	for i = (page - 1) * pageSize + 1, math.min(#list, page * pageSize) do items[#items + 1] = list[i] end
	return items, page, pages
end

-- The page of `list` that holds emblem `index` (1 when it is not there).
function Emblems.PageOf(list, index, pageSize)
	pageSize = pageSize or Emblems.PAGE_SIZE
	for i, v in ipairs(list) do
		if v == index then return floor((i - 1) / pageSize) + 1 end
	end
	return 1
end

if ns.addon then ns.addon.Emblems = Emblems end
