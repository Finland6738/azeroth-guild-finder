-- Skin: the design tokens of SPEC-04 §5 and ADR 0008 (colours, sizes, type scale, media paths) and the font objects.
-- The tokens are the ones of docs/specs/mockups/html/agf.css; a change there is a change here. Pixel sizes are at 100 %
-- window scale. Lua 5.1; the pure helpers (Hex, Color, Style) need no client.
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
	ink = "#3b2412", ink2 = "#6a4526", ink3 = "#8c6844", inkInv = "#fbe9cc",
	-- parchment
	parchHi = "#fbe3bd", parch = "#f6d6a6", parchLo = "#eec58d", pageLeft = "#e9c897", line = "#dcb07a", line2 = "#b98a53",
	-- metal
	steelHi = "#eef2f6", steel = "#9aa4ae", steelLo = "#4c545c", iron = "#2a2e33", iron2 = "#1a1d21",
	gold = "#f2bf3c", gold2 = "#b8820f",
	-- actions
	redHi = "#e9555a", red = "#b81f25", redLo = "#7d0f13", redTxt = "#ffdc7a",
	blueHi = "#5d9bea", blue = "#2a64bd", blueLo = "#163d7c",
	-- states
	ok = "#2e7d32", okBg = "#e2efd3", warn = "#a8700a", bad = "#b3261e", badBg = "#f6dccf",
	-- surfaces used by widgets
	snackbar = "#2d241b", snackbarText = "#f7ead2", tooltipBg = "#1f1a15", white = "#ffffff",
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
	disabled = { fill = "#7a7a7a", rim = "#3c3c3c", text = "#e3e3e3", gloss = false },
}

-- Colours of the tag kinds: background and text.
Skin.TAGS = {
	default = { bg = "#d9b98c", text = "#5b391a" },
	ok = { bg = "#e2efd3", text = "#2e7d32" },
	bad = { bg = "#f6dccf", text = "#b3261e" },
	gold = { bg = "#f8e2a6", text = "#7a5208" },
	casual = { bg = "#dcebd0", text = "#2e6b2e" },
	soft = { bg = "#f6e1a8", text = "#7a5208" },
	hard = { bg = "#f3c9bd", text = "#8e1b12" },
}

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
			local px = max(Skin.MIN_FONT_PX, s.px)
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
