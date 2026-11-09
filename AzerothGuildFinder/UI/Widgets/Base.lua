-- Widgets, part 1: the shared helpers every widget uses. Lua 5.1.
--
-- The widget set (SPEC-04 §5, ADR 0008, mockup 00-design-system) is split over five files, loaded in this order:
--   Base.lua      this file: textures, nine-slices, text, tooltips on hover
--   Overlay.lua   tooltip content and the snackbar
--   Buttons.lua   pill buttons, icon buttons, the gold close button
--   Inputs.lua    chips, chip groups, switches, segmented controls, fields, copy fields
--   Display.lua   cards, tags, badges, role badges, class icons, dividers
-- Every constructor is W.Name(parent, opts) and returns a frame with a few methods of its own (SetText, SetSelected,
-- ...); opts are plain tables, every string in them is already translated by the caller. Pages never create raw textures
-- for the common shapes: they use these, so the look stays in one place. Colours and sizes come from UI/Skin.lua.
local ADDON_NAME, ns = ...
ns = ns or {}
local W = {}
ns.Widgets, ns.modules = W, ns.modules or {}
ns.modules.Widgets = W

local Skin = ns.Skin
local type, ipairs, pairs, tostring, select = type, ipairs, pairs, tostring, select
local min, max = math.min, math.max

---------------------------------------------------------------------------------------------------------------------
-- Textures
---------------------------------------------------------------------------------------------------------------------
-- The path of a Media/ texture.
function W.Media(name) return Skin.Media(name) end

-- A texture of Media/ (tinted with the colour token or "#rrggbb" `color`, alpha `alpha`) on `parent`.
function W.Texture(parent, media, layer, color, alpha)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(W.Media(media))
	if color then
		if type(color) == "string" and color:sub(1, 1) == "#" then W.TintHex(t, color, alpha)
		else t:SetVertexColor(Skin.Color(color, alpha)) end
	end
	return t
end

-- Paints a texture with a colour token (SetVertexColor keeps the shading of the texture).
function W.Tint(texture, color, alpha)
	texture:SetVertexColor(Skin.Color(color, alpha))
end

-- Sets the colour of a texture from a "#rrggbb" string.
function W.TintHex(texture, hex, alpha)
	local r, g, b = Skin.Hex(hex)
	if r then texture:SetVertexColor(r, g, b, alpha or 1) end
end

---------------------------------------------------------------------------------------------------------------------
-- Nine-slice: nine textures from a 64 px mask of Media/ (corner margin 16 px of the 64), stretched over `parent`.
-- Built from plain textures so that it works with every client; no SetTextureSliceMargins needed.
--   local s = W.NineSlice(frame, "card", { corner = 12, layer = "BACKGROUND", color = "parch", alpha = 0.55 })
--   s:SetColor(r, g, b, a)   s:SetTint(token, alpha)   s:SetCorner(px)   s:SetShown(bool)   s:SetOutset(px)
-- `corner` is the size on screen of one corner; for a pill the caller passes half the height.
---------------------------------------------------------------------------------------------------------------------
local NineSlice = {}
NineSlice.__index = NineSlice

local SLICE_MARGIN = 0.25   -- 16 of 64 texels

local PARTS = {
	-- name, texcoord left, right, top, bottom
	{ "tl", 0, SLICE_MARGIN, 0, SLICE_MARGIN }, { "t", SLICE_MARGIN, 1 - SLICE_MARGIN, 0, SLICE_MARGIN },
	{ "tr", 1 - SLICE_MARGIN, 1, 0, SLICE_MARGIN },
	{ "l", 0, SLICE_MARGIN, SLICE_MARGIN, 1 - SLICE_MARGIN }, { "c", SLICE_MARGIN, 1 - SLICE_MARGIN, SLICE_MARGIN, 1 - SLICE_MARGIN },
	{ "r", 1 - SLICE_MARGIN, 1, SLICE_MARGIN, 1 - SLICE_MARGIN },
	{ "bl", 0, SLICE_MARGIN, 1 - SLICE_MARGIN, 1 }, { "b", SLICE_MARGIN, 1 - SLICE_MARGIN, 1 - SLICE_MARGIN, 1 },
	{ "br", 1 - SLICE_MARGIN, 1, 1 - SLICE_MARGIN, 1 },
}

function W.NineSlice(parent, media, opts)
	opts = opts or {}
	local s = setmetatable({ parent = parent, media = media, parts = {}, corner = opts.corner or 12, outset = opts.outset or 0 }, NineSlice)
	local layer, sub = opts.layer or "BACKGROUND", opts.sublevel or 0
	for _, p in ipairs(PARTS) do
		local t = parent:CreateTexture(nil, layer, nil, sub)
		t:SetTexture(W.Media(media))
		t:SetTexCoord(p[2], p[3], p[4], p[5])
		s.parts[p[1]] = t
	end
	s:Layout()
	if opts.color then s:SetTint(opts.color, opts.alpha) end
	return s
end

function NineSlice:Layout()
	local P, c, o, parent = self.parts, self.corner, self.outset, self.parent
	P.tl:ClearAllPoints(); P.tl:SetPoint("TOPLEFT", parent, "TOPLEFT", -o, o); P.tl:SetSize(c, c)
	P.tr:ClearAllPoints(); P.tr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", o, o); P.tr:SetSize(c, c)
	P.bl:ClearAllPoints(); P.bl:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -o, -o); P.bl:SetSize(c, c)
	P.br:ClearAllPoints(); P.br:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", o, -o); P.br:SetSize(c, c)
	P.t:ClearAllPoints(); P.t:SetPoint("TOPLEFT", P.tl, "TOPRIGHT"); P.t:SetPoint("BOTTOMRIGHT", P.tr, "BOTTOMLEFT")
	P.b:ClearAllPoints(); P.b:SetPoint("TOPLEFT", P.bl, "TOPRIGHT"); P.b:SetPoint("BOTTOMRIGHT", P.br, "BOTTOMLEFT")
	P.l:ClearAllPoints(); P.l:SetPoint("TOPLEFT", P.tl, "BOTTOMLEFT"); P.l:SetPoint("BOTTOMRIGHT", P.bl, "TOPRIGHT")
	P.r:ClearAllPoints(); P.r:SetPoint("TOPLEFT", P.tr, "BOTTOMLEFT"); P.r:SetPoint("BOTTOMRIGHT", P.br, "TOPRIGHT")
	P.c:ClearAllPoints(); P.c:SetPoint("TOPLEFT", P.tl, "BOTTOMRIGHT"); P.c:SetPoint("BOTTOMRIGHT", P.br, "TOPLEFT")
end

function NineSlice:SetCorner(px) self.corner = px; self:Layout() end
function NineSlice:SetOutset(px) self.outset = px; self:Layout() end

function NineSlice:SetColor(r, g, b, a)
	for _, t in pairs(self.parts) do t:SetVertexColor(r, g, b, a or 1) end
	self.r, self.g, self.b, self.a = r, g, b, a or 1
end

function NineSlice:SetTint(token, alpha) self:SetColor(Skin.Color(token, alpha)) end
function NineSlice:SetHex(hex, alpha)
	local r, g, b = Skin.Hex(hex)
	if r then self:SetColor(r, g, b, alpha) end
end

function NineSlice:SetShown(shown)
	for _, t in pairs(self.parts) do t:SetShown(shown) end
	self.shown = shown and true or false
end
function NineSlice:Show() self:SetShown(true) end
function NineSlice:Hide() self:SetShown(false) end

---------------------------------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------------------------------
-- A FontString in a style of the type scale (Skin.STYLES) and a colour token; left aligned unless `justify` is given.
function W.Text(parent, style, color, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	local font = Skin.Font(style or "body")
	if font then fs:SetFontObject(font) end
	W.TextColor(fs, color or "ink")
	fs:SetJustifyH(justify or "LEFT")
	fs.style = style or "body"
	return fs
end

-- Changes the colour of a FontString to a token or "#rrggbb".
function W.TextColor(fs, color, alpha)
	local r, g, b
	if type(color) == "string" and color:sub(1, 1) == "#" then r, g, b = Skin.Hex(color) else r, g, b = Skin.Color(color) end
	fs:SetTextColor(r or 1, g or 1, b or 1, alpha or 1)
end

-- Text with a colour token as a |cff escape: W.Colored("bad", "No") -> "|cffb3261eNo|r".
function W.Colored(token, text)
	return "|cff" .. Skin.ToHex(Skin.Color(token)) .. tostring(text) .. "|r"
end

---------------------------------------------------------------------------------------------------------------------
-- Hover tooltip: W.SetTooltip(frame, source). `source` is a string, { title, lines = {...} } or a function returning
-- either (called each time, so it can show live numbers). A frame can have one tooltip; setting it again replaces it.
-- Uses the game's GameTooltip; the content helpers are in Overlay.lua.
---------------------------------------------------------------------------------------------------------------------
function W.SetTooltip(frame, source)
	frame.agfTooltip = source
	if frame.agfTooltipHooked then return end
	frame.agfTooltipHooked = true
	frame:HookScript("OnEnter", function(self) W.ShowTooltip(self, self.agfTooltip) end)
	frame:HookScript("OnLeave", function() W.HideTooltip() end)
end

---------------------------------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------------------------------
-- A plain frame with a size (and an optional name for UISpecialFrames).
function W.Frame(parent, width, height, name)
	local f = CreateFrame("Frame", name, parent)
	if width and height then f:SetSize(width, height) end
	return f
end

-- Width of a string in a font style at 100 % (uses a hidden FontString).
local measurer
function W.TextWidth(text, style)
	if not measurer then
		local holder = CreateFrame("Frame", nil, UIParent)
		holder:Hide()
		measurer = holder:CreateFontString(nil, "OVERLAY")
	end
	local font = Skin.Font(style or "body")
	if font then measurer:SetFontObject(font) end
	measurer:SetText(text or "")
	return measurer:GetStringWidth()
end
