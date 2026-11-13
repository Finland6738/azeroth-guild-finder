-- Skin: the design tokens of SPEC-04 §5 and ADR 0008 (colours, sizes, type scale, media paths) and the font objects.
-- The tokens are the ones of docs/specs/mockups/html/agf.css; a change there is a change here. Pixel sizes are at 100 %
-- window scale. Lua 5.1; the pure helpers (Hex, Color, Luminance, Contrast, Blend, TextPairs) need no client.
-- Text colours are always tokens (never a "#rrggbb" literal in a W.Text / TextColor call): Skin.TextPairs() lists every
-- text-on-background pair the windows draw and Tests/test_ui_polish.lua checks them against WCAG 2.1 (4.5:1; 7:1 for the
-- main ink), so a new pair must be added there.
local ADDON_NAME, ns = ...
ns = ns or {}
local Skin = {}
ns.Skin, ns.modules = Skin, ns.modules or {}
ns.modules.Skin = Skin

local type, tonumber, tostring, pairs, ipairs = type, tonumber, tostring, pairs, ipairs
local floor, min, max = math.floor, math.min, math.max

---------------------------------------------------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------------------------------------------------
-- "#f6d6a6" or "f6d6a6" -> r, g, b (0..1); nil for anything else.
function Skin.Hex(value)
	if type(value) ~= "string" then return nil end
	local hex = value:match("^#?(%x%x%x%x%x%x)$")
	if not hex then return nil end
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- r, g, b (0..1) -> "rrggbb" for |cffRRGGBB escapes.
function Skin.ToHex(r, g, b)
	local function byte(v) return floor(min(1, max(0, v or 0)) * 255 + 0.5) end
	return ("%02x%02x%02x"):format(byte(r), byte(g), byte(b))
end

Skin.COLORS = {
	-- ink
	ink = "#3b2412", ink2 = "#6a4526", ink3 = "#6a4f34", inkInv = "#fbe9cc",
	inkDeep = "#3a200c", brand = "#5a3a1c",   -- headlines of the left page, the window title
	-- parchment
	parchHi = "#fbe3bd", parch = "#f6d6a6", parchLo = "#eec58d", pageLeft = "#e9c897", line = "#dcb07a", line2 = "#b98a53",
	-- metal
	steelHi = "#eef2f6", steel = "#9aa4ae", steelLo = "#4c545c", iron = "#2a2e33", iron2 = "#1a1d21",
	gold = "#f2bf3c", gold2 = "#b8820f",
	-- actions
	redHi = "#e9555a", red = "#b81f25", redLo = "#7d0f13", redTxt = "#ffdc7a",
	blueHi = "#5d9bea", blue = "#2a64bd", blueLo = "#163d7c",
	-- states
	ok = "#246227", okBg = "#e2efd3", warn = "#764e07", bad = "#a5231c", badBg = "#f6dccf",
	-- surfaces used by widgets
	snackbar = "#2d241b", snackbarText = "#f7ead2", tooltipBg = "#1f1a15", white = "#ffffff",
	plateFill = "#8d6540", plateRim = "#6e4c2c", plateText = "#fff4df",   -- the brown plate of a left-page section
	onIron = "#f0f3f6", ironTile = "#3c4248", popup = "#fbe9c5",                            -- text on the dark steel tiles of the emblem designer
	badLight = "#ff9a8f", okLight = "#9bd69e",                         -- ok / bad lines of a tooltip (dark background)
	linkInk = "#1b3d73", fieldBlue = "#fffaf0",                          -- Discord / copy field text and its background
}

-- r, g, b, a of a named colour (alpha 1 unless given); white for an unknown name.
function Skin.Color(name, alpha)
	local r, g, b = Skin.Hex(Skin.COLORS[name])
	if not r then return 1, 1, 1, alpha or 1 end
	return r, g, b, alpha or 1
end

-- The colour of a button kind: fill, rim, text and whether the glossy layer shows (SPEC-04 §5.3: red = the one main
-- action, blue = Discord only, parchment = secondary, grey = disabled).
Skin.KINDS = {
	primary = { fill = "#b81f25", rim = "#4a080b", text = "#ffdc7a", gloss = true },
	discord = { fill = "#2a64bd", rim = "#0d244a", text = "#f2f7ff", gloss = true },
	tonal = { fill = "#e8c28f", rim = "#7a5430", text = "#4a2c12", gloss = true },
	metal = { fill = "#3a4047", rim = "#111111", text = "#e9edf1", gloss = true },
	ghost = { fill = nil, rim = nil, text = "#6a3e14", gloss = false },
	disabled = { fill = "#6a6a6a", rim = "#3c3c3c", text = "#f2f2f2", gloss = false },
}

-- Colours of the tag kinds: background and text.
Skin.TAGS = {
	default = { bg = "#d9b98c", text = "#5b391a" },
	ok = { bg = "#e2efd3", text = "#246227" },
	bad = { bg = "#f6dccf", text = "#a5231c" },
	gold = { bg = "#f8e2a6", text = "#7a5208" },
	casual = { bg = "#dcebd0", text = "#2e6b2e" },
	soft = { bg = "#f6e1a8", text = "#7a5208" },
	hard = { bg = "#f3c9bd", text = "#8e1b12" },
}

-- Cards (W.Card): fill, edge and whether a shadow shows.
Skin.CARDS = {
	plain = { fill = "#fff4de", fillAlpha = 0.55, edge = "#a06e3c", edgeAlpha = 0.45 },
	elevated = { fill = "#fbe9c5", fillAlpha = 1, edge = "#a06e3c", edgeAlpha = 0.4, shadow = true },
	gold = { fill = "#fbe8b4", fillAlpha = 1, edge = "#d6a23a", edgeAlpha = 1, shadow = true },
}

-- The side rail (Main): tab fill, edge and label colour, off and on.
Skin.RAIL = {
	bg = { off = "#30353b", on = "#5a4018" }, edge = { off = "#5c646d", on = "#f2bf3c" }, text = { off = "#cfd6dc", on = "#fff3d1" },
}

-- Segmented controls, the editor's step discs, the day squares and the count badge.
Skin.SEGMENT = { onFill = "#5a3315", onText = "#ffeac2", offFill = "#fff4dd", offText = "ink" }
Skin.STEP = { activeFill = "#7a4a22", idleFill = "#d6b98c", activeCard = "#fbe5b5" }
Skin.DAYS = { onFill = "#5a3315", onText = "#ffeac2", offFill = "#fff5e1", offFillAlpha = 0.45, offText = "ink3" }
Skin.BADGE = { fill = "#d32f2f", text = "white" }

-- Tooltip lines are drawn on the game's dark tooltip: the state colours of the parchment are swapped for light ones.
Skin.ON_DARK = { bad = "badLight", ok = "okLight", warn = "gold" }

---------------------------------------------------------------------------------------------------------------------
-- Contrast (WCAG 2.1): the pure arithmetic and the list of every text-on-background pair the windows draw
---------------------------------------------------------------------------------------------------------------------
local function hexOf(value)
	if type(value) ~= "string" then return nil end
	if Skin.COLORS[value] then return Skin.COLORS[value] end
	if value:match("^#%x%x%x%x%x%x$") then return value end
	return nil
end

-- Relative luminance (0..1) of a token name or "#rrggbb"; nil when it is neither.
function Skin.Luminance(color)
	local r, g, b = Skin.Hex(hexOf(color))
	if not r then return nil end
	local function lin(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end

-- Contrast ratio (1..21) of two colours (tokens or "#rrggbb"); nil when one is unknown.
function Skin.Contrast(a, b)
	local la, lb = Skin.Luminance(a), Skin.Luminance(b)
	if not la or not lb then return nil end
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

-- "#rrggbb" of `fg` painted with `alpha` over `bg` (tokens or hex).
function Skin.Blend(fg, bg, alpha)
	local fr, fgg, fb = Skin.Hex(hexOf(fg))
	local br, bgg, bb = Skin.Hex(hexOf(bg))
	if not fr or not br then return nil end
	local a = alpha or 1
	return "#" .. Skin.ToHex(fr * a + br * (1 - a), fgg * a + bgg * (1 - a), fb * a + bb * (1 - a))
end

Skin.MIN_CONTRAST = 4.5         -- WCAG AA for normal text
Skin.MIN_CONTRAST_INK = 7       -- the main ink on parchment (SPEC-04 §5.3)

-- The text tokens drawn straight on the parchment (and on cards) and the contrast each must reach there.
Skin.INK_TEXT = { ink = 7, inkDeep = 7, ink2 = 4.5, ink3 = 4.5, brand = 4.5, ok = 4.5, warn = 4.5, bad = 4.5 }

-- The light surfaces: the two pages, the popup, the active step and every card kind painted over each page.
function Skin.Surfaces()
	local list = {
		{ name = "parchHi", hex = Skin.COLORS.parchHi }, { name = "parch", hex = Skin.COLORS.parch },
		{ name = "pageLeft", hex = Skin.COLORS.pageLeft }, { name = "popup", hex = Skin.COLORS.popup },
		{ name = "stepActive", hex = Skin.STEP.activeCard },
	}
	local kinds = {}
	for kind in pairs(Skin.CARDS) do kinds[#kinds + 1] = kind end
	table.sort(kinds)
	for _, kind in ipairs(kinds) do
		local c = Skin.CARDS[kind]
		for _, page in ipairs({ "parch", "pageLeft" }) do
			list[#list + 1] = { name = "card " .. kind .. " on " .. page, hex = Skin.Blend(c.fill, Skin.COLORS[page], c.fillAlpha) }
		end
	end
	return list
end

-- Every { name, fg, bg, min } the interface draws. fg and bg are tokens or hex; `min` is the ratio to reach.
function Skin.TextPairs()
	local pairsOut = {}
	local function add(name, fg, bg, min) pairsOut[#pairsOut + 1] = { name = name, fg = fg, bg = bg, min = min or Skin.MIN_CONTRAST } end

	local inks = {}
	for token in pairs(Skin.INK_TEXT) do inks[#inks + 1] = token end
	table.sort(inks)
	for _, surface in ipairs(Skin.Surfaces()) do
		for _, token in ipairs(inks) do add(token .. " on " .. surface.name, token, surface.hex, Skin.INK_TEXT[token]) end
		add("ghost button on " .. surface.name, Skin.KINDS.ghost.text, surface.hex)
	end

	local kinds = {}
	for kind in pairs(Skin.KINDS) do if Skin.KINDS[kind].fill then kinds[#kinds + 1] = kind end end
	table.sort(kinds)
	for _, kind in ipairs(kinds) do add("button " .. kind, Skin.KINDS[kind].text, Skin.KINDS[kind].fill) end

	local tags = {}
	for kind in pairs(Skin.TAGS) do tags[#tags + 1] = kind end
	table.sort(tags)
	for _, kind in ipairs(tags) do add("tag " .. kind, Skin.TAGS[kind].text, Skin.TAGS[kind].bg) end

	for _, state in ipairs({ "off", "on" }) do add("rail tab " .. state, Skin.RAIL.text[state], Skin.RAIL.bg[state]) end
	add("plate", "plateText", "plateFill")
	add("snackbar text", "snackbarText", "snackbar")
	add("snackbar action", "gold", "snackbar")
	for _, token in ipairs({ "white", "gold", "badLight", "okLight" }) do add("tooltip " .. token, token, "tooltipBg") end
	add("segment on", Skin.SEGMENT.onText, Skin.SEGMENT.onFill)
	add("segment off", Skin.SEGMENT.offText, Skin.SEGMENT.offFill)
	add("day on", Skin.DAYS.onText, Skin.DAYS.onFill)
	for _, page in ipairs({ "parch", "pageLeft" }) do
		add("day off on " .. page, Skin.DAYS.offText, Skin.Blend(Skin.DAYS.offFill, Skin.COLORS[page], Skin.DAYS.offFillAlpha))
	end
	add("step number active", "white", Skin.STEP.activeFill)
	add("step number done", "white", "ok")
	add("step number idle", "ink", Skin.STEP.idleFill)
	add("count badge", Skin.BADGE.text, Skin.BADGE.fill)
	add("emblem tile", "onIron", "ironTile")
	add("link field", "linkInk", "fieldBlue")
	return pairsOut
end

---------------------------------------------------------------------------------------------------------------------
-- Sizes (px at 100 %)
---------------------------------------------------------------------------------------------------------------------
Skin.METRICS = {
	windowW = 1116, windowH = 768, leftPageW = 312, railW = 92, railTabW = 84, railTabH = 76, railGap = 14, railTop = 46,
	closeSize = 42, headerH = 56, statusH = 30, pad = 26, grid = 8,
	buttonH = { sm = 30, md = 36, lg = 44 }, buttonPad = { sm = 14, md = 20, lg = 28 },
	fieldH = 38, chipH = 30, tagH = 22, badgeH = 20, switchW = 46, switchH = 26,
}

---------------------------------------------------------------------------------------------------------------------
-- Type scale: key = { file, px, weight } (SPEC-04 §5.2; minimum 12 px). Fonts: the bundled Roboto files in Media/Fonts/,
-- or the client's own font when a file is missing, so the window works before the fonts are added.
---------------------------------------------------------------------------------------------------------------------
Skin.MIN_FONT_PX = 12
Skin.STYLES = {
	display = { family = "Roboto", weight = "Black", px = 30 },
	headline = { family = "Roboto", weight = "Bold", px = 24 },
	titleL = { family = "Roboto", weight = "Bold", px = 20 },
	titleM = { family = "Roboto", weight = "Medium", px = 16 },
	titleS = { family = "Roboto", weight = "Medium", px = 14 },
	bodyL = { family = "Roboto", weight = "Regular", px = 15 },
	body = { family = "Roboto", weight = "Regular", px = 13.5 },
	label = { family = "Roboto", weight = "Medium", px = 12.5 },
	caption = { family = "Roboto", weight = "Regular", px = 12 },
	overline = { family = "Roboto", weight = "Bold", px = 12 },
	button = { family = "Roboto", weight = "Medium", px = 14 },
	buttonSm = { family = "Roboto", weight = "Medium", px = 13 },
	buttonLg = { family = "Roboto", weight = "Medium", px = 16 },
	rail = { family = "Roboto", weight = "Medium", px = 12 },
	mono = { family = "RobotoMono", weight = "Regular", px = 12.5 },
	monoM = { family = "RobotoMono", weight = "Medium", px = 12.5 },
}

-- The pixel size a style is drawn at (100 % window scale): never under MIN_FONT_PX. Text that is not a style (the initial
-- inside an emblem) goes through Skin.ClampPx.
function Skin.ClampPx(px) return max(Skin.MIN_FONT_PX, tonumber(px) or Skin.MIN_FONT_PX) end
function Skin.FontPx(style)
	local s = Skin.STYLES[style]
	return s and Skin.ClampPx(s.px) or nil
end

Skin.FONT_DIR = "Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Media\\Fonts\\"
Skin.MEDIA_DIR = "Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Media\\"

-- The path of a texture of Media/ ("pill" -> ...\Media\pill.tga).
function Skin.Media(name) return Skin.MEDIA_DIR .. name .. ".tga" end

-- File name of a style: Roboto-Bold.ttf, RobotoMono-Regular.ttf.
function Skin.FontFile(style)
	local s = Skin.STYLES[style]
	if not s then return nil end
	return Skin.FONT_DIR .. s.family .. "-" .. s.weight .. ".ttf"
end

Skin.fonts = {}          -- style -> font object (after Skin.CreateFonts)
Skin.fontSource = {}     -- style -> "bundled" | "fallback"

local function fallbackFont()
	return (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
end

-- Creates (once) the font objects AGF_<Style>, e.g. AGF_Headline. A bundled file that the client cannot load
-- (SetFont returns false) is replaced by the client's own font, and the style is listed as "fallback" in /gf debug.
function Skin.CreateFonts()
	if not CreateFont then return Skin.fonts end
	for style, s in pairs(Skin.STYLES) do
		if not Skin.fonts[style] then
			local name = "AGF_" .. style:sub(1, 1):upper() .. style:sub(2)
			local object = CreateFont(name)
			local px = Skin.ClampPx(s.px)
			local file = Skin.FontFile(style)
			local ok = object:SetFont(file, px, "")
			-- SetFont answers false for a file it cannot load; a client that answers nothing is checked with GetFont
			local current = object.GetFont and object:GetFont()
			local failed = ok == false or (not ok and not (type(current) == "string" and current:lower() == file:lower()))
			if failed then
				object:SetFont(fallbackFont(), px, "")
				Skin.fontSource[style] = "fallback"
			else
				Skin.fontSource[style] = "bundled"
			end
			Skin.fonts[style] = object
		end
	end
	return Skin.fonts
end

-- The font object of a style (created on demand); nil without a client.
function Skin.Font(style)
	if not Skin.fonts[style] then Skin.CreateFonts() end
	return Skin.fonts[style]
end

function Skin:DebugLines()
	local bundled, fallback = 0, 0
	for _, source in pairs(Skin.fontSource) do
		if source == "bundled" then bundled = bundled + 1 else fallback = fallback + 1 end
	end
	return { ("Fonts: %d styles from Media/Fonts, %d on the client's font"):format(bundled, fallback) }
end

if ns.addon and ns.addon.AddDebugSection then
	ns.addon:AddDebugSection("Interface", function()
		local lines = Skin:DebugLines()
		if ns.Main and ns.Main.DebugLines then
			for _, line in ipairs(ns.Main:DebugLines()) do lines[#lines + 1] = line end
		end
		return lines
	end)
end

if ns.addon then ns.addon.Skin = Skin end
