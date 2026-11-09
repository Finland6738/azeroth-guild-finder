-- EmblemDesigner: the Albion-style emblem designer of the Identity step (SPEC-08 §2.3, mockup 07, M3.6). Lua 5.1.
--
--   local d = EmblemDesigner.Build(parent, opts)   a panel over the whole of `parent` (the 430 x 640 step page), hidden
--       opts.onChange(emb)     a new design (t = 2) every time a piece or a colour is picked, Random or Reset is pressed
--       opts.onClose()         Done was pressed
--       opts.reset()           -> the emblem Reset goes back to (Emblems.Reset of the published one and the tabard)
--   d:Open(emb)  d:Close()  d:Set(emb) (redraw without calling onChange)  d:Get()  d:Pick(field, value)  d:Random([rng])
--   d:Reset()  d:Page(n)  d:CycleBorder(delta)
--
-- Sections as in Albion's designer, built from the pieces of Data/TabardParts.lua: Background (a colour), Border (a style,
-- with ◀ ▶, and a colour), Emblem (a grid of 16 per page, with ◀ ▶, and a colour), then a big live preview with Random and
-- Reset. Every rule (pages, Random, Reset) is in Data/Emblems.lua. The game's emblems are offered only when this client can
-- load them (Emblem.GameEmblemsLoad); the addon's own symbols are always there.
local ADDON_NAME, ns = ...
ns = ns or {}
local Designer = {}
ns.EmblemDesigner, ns.modules = Designer, ns.modules or {}
ns.modules.EmblemDesigner = Designer

local L, Skin, W = ns.L, ns.Skin, ns.Widgets
local type, ipairs, pairs = type, ipairs, pairs

local function Emblems() return ns.Emblems end
local function Parts() return ns.TabardParts end

local WIDTH = 430
local SWATCH, SWATCH_GAP = 24, 4
local TILE, TILE_GAP, COLS = 44, 6, 8
local PREVIEW = 150

---------------------------------------------------------------------------------------------------------------------
-- Small controls
---------------------------------------------------------------------------------------------------------------------
local function hexOf(c) return Emblems().Hex(c) end

local function paintSwatch(s)
	s.ring:SetShown(s.selected)
end

local function buildSwatches(parent, colors, onPick)
	local row = { swatches = {} }
	for i, c in ipairs(colors) do
		local s = CreateFrame("Button", nil, parent)
		s:SetSize(SWATCH, SWATCH)
		s:RegisterForClicks("LeftButtonUp")
		s.color = c
		s.ring = W.NineSlice(s, "card_edge", { corner = 8, layer = "BACKGROUND", outset = 3 })
		s.ring:SetHex("#b8820f")
		s.fill = W.NineSlice(s, "card", { corner = 6, layer = "ARTWORK" })
		s.fill:SetHex(hexOf(c))
		s.edge = W.NineSlice(s, "card_edge", { corner = 6, layer = "OVERLAY" })
		s.edge:SetHex("#1d1208", 0.55)
		s:SetScript("OnClick", function(self) onPick(self.color) end)
		W.SetTooltip(s, L["EMB_COLOR_N"]:format(i, #colors))
		row.swatches[i] = s
		paintSwatch(s)
	end
	function row:Select(color)
		for _, s in ipairs(self.swatches) do
			s.selected = s.color == color
			paintSwatch(s)
		end
	end
	return row
end

local function layoutSwatches(row, parent, y)
	for i, s in ipairs(row.swatches) do
		s:ClearAllPoints()
		s:SetPoint("TOPLEFT", parent, "TOPLEFT", 3 + (i - 1) * (SWATCH + SWATCH_GAP), -y)
	end
end

-- ◀ text ▶ on a steel pill (the border style, the emblem page).
local function buildStepper(parent, width, tipBack, tipNext, onStep)
	local st = CreateFrame("Frame", nil, parent)
	st:SetSize(width, 32)
	st.bg = W.NineSlice(st, "pill", { corner = 16, layer = "BACKGROUND" })
	st.bg:SetHex("#3a4047")
	st.rim = W.NineSlice(st, "pill_rim", { corner = 16, layer = "BACKGROUND", sublevel = 1 })
	st.rim:SetHex("#111111")
	local function arrow(dir, tip)
		local b = CreateFrame("Button", nil, st)
		b:SetSize(24, 24)
		b:RegisterForClicks("LeftButtonUp")
		b.disc = W.Texture(b, "disc_shiny", "ARTWORK", "gold")
		b.disc:SetAllPoints(b)
		b.glyph = W.Texture(b, "glyph_back", "OVERLAY", "#2b1a05")
		b.glyph:SetSize(14, 14)
		b.glyph:SetPoint("CENTER", b, "CENTER", dir > 0 and 1 or -1, 0)
		if dir > 0 then b.glyph:SetTexCoord(1, 0, 0, 1) end
		b:SetScript("OnClick", function() onStep(dir) end)
		W.SetTooltip(b, tip)
		return b
	end
	st.back = arrow(-1, tipBack)
	st.back:SetPoint("LEFT", st, "LEFT", 4, 0)
	st.next = arrow(1, tipNext)
	st.next:SetPoint("RIGHT", st, "RIGHT", -4, 0)
	st.text = W.Text(st, "label", "#f0f3f6", "CENTER")
	st.text:SetPoint("LEFT", st.back, "RIGHT", 4, 0)
	st.text:SetPoint("RIGHT", st.next, "LEFT", -4, 0)
	return st
end

local function sectionHead(parent, text, y, stepper)
	local plate = W.Plate(parent, { text = text, width = stepper and (WIDTH - stepper:GetWidth() - 10) or WIDTH })
	plate:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	if stepper then stepper:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(y + 1)) end
	return plate
end

-- One tile of the emblem grid: the piece on dark steel, gold when chosen.
local function buildTile(parent, onPick)
	local t = CreateFrame("Button", nil, parent)
	t:SetSize(TILE, TILE)
	t:RegisterForClicks("LeftButtonUp")
	t.bg = W.NineSlice(t, "card", { corner = 8, layer = "BACKGROUND" })
	t.bg:SetHex("#3c4248")
	t.edge = W.NineSlice(t, "card_edge", { corner = 8, layer = "BORDER" })
	t.piece = t:CreateTexture(nil, "ARTWORK")
	t.piece:SetPoint("TOPLEFT", t, "TOPLEFT", 6, -6)
	t.piece:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -6, 6)
	t.missing = W.Text(t, "caption", "#e9edf1", "CENTER")
	t.missing:SetAllPoints(t)
	t:SetScript("OnClick", function(self) if self.index then onPick(self.index) end end)
	W.SetTooltip(t, function()
		local own = t.index and Parts().OWN_EMBLEMS[t.index]
		if own then return L["EMB_SYM_" .. own.key] end
		return L["EMB_GAME_N"]:format((t.index or 0) + 1)
	end)
	return t
end

---------------------------------------------------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------------------------------------------------
local Panel = {}

function Panel:Get() return Emblems().Copy(self.emb) end

-- Shows `emb` (any emblem: it is turned into a design) without calling onChange.
function Panel:Set(emb)
	self.emb = Emblems().ToCustom(emb)
	self.page = Emblems().PageOf(self.list, self.emb.e)
	self:Draw()
end

function Panel:Open(emb)
	self.list = ns.Emblem.Available()
	self:Set(emb)
	self:Show()
end

function Panel:Close()
	self:Hide()
	if self.opts.onClose then self.opts.onClose() end
end

function Panel:Changed()
	self:Draw()
	if self.opts.onChange then self.opts.onChange(self:Get()) end
end

-- field: "gc" | "bc" | "ec" (a colour) | "e" (an emblem index) | "b" (a border style).
function Panel:Pick(field, value)
	if self.emb[field] == value then return end
	self.emb[field] = value
	self:Changed()
end

function Panel:CycleBorder(delta)
	local n = Parts().BORDER_COUNT
	local b = self.emb.b or 0
	self.emb.b = (b + delta) % n
	self:Changed()
end

function Panel:Page(n)
	local _, page = Emblems().Page(self.list, n)
	self.page = page
	self:Draw()
end

function Panel:Random(rng)
	self.emb = Emblems().Random(rng, self.list)
	self.page = Emblems().PageOf(self.list, self.emb.e)
	self:Changed()
end

function Panel:Reset()
	local target = self.opts.reset and self.opts.reset() or Emblems().Reset(nil, nil)
	self.emb = Emblems().ToCustom(target)
	self.page = Emblems().PageOf(self.list, self.emb.e)
	self:Changed()
end

function Panel:Draw()
	local emb, P = self.emb, Parts()
	self.bgRow:Select(emb.gc)
	self.borderRow:Select(emb.bc)
	self.emblemRow:Select(emb.ec)
	local border = P.BORDERS[emb.b or 0]
	self.borderStep.text:SetText(L["EMB_BORDER_STYLE"]:format((emb.b or 0) + 1, P.BORDER_COUNT,
		border and L["EMB_BORDER_" .. border.key] or "?"))
	local items, page, pages = Emblems().Page(self.list, self.page)
	self.page = page
	self.emblemStep.text:SetText(L["EMB_PAGE"]:format(page, pages))
	local er, eg, eb = Emblems().RGB(emb.ec or P.NEUTRAL.ec)
	for i, tile in ipairs(self.tiles) do
		local index = items[i]
		tile.index = index
		if index then
			local ok = ns.Emblem.ApplyPiece(tile.piece, P.Emblem(index))
			tile.piece:SetShown(ok)
			tile.missing:SetText(ok and "" or "?")
			local on = index == emb.e
			if on then tile.piece:SetVertexColor(er, eg, eb, 1) else tile.piece:SetVertexColor(0.94, 0.94, 0.94, 1) end
			tile.edge:SetHex(on and "#f2bf3c" or "#8e979f", 1)
			tile.selected = on
			tile:Show()
		else
			tile:Hide()
		end
	end
	self.preview:SetEmblem(emb, self.opts.name and self.opts.name() or nil)
end

function Designer.Build(parent, opts)
	local d = CreateFrame("Frame", nil, parent)
	d:SetAllPoints(parent)
	d:SetFrameLevel(parent:GetFrameLevel() + 20)
	d:EnableMouse(true)
	d.opts = opts or {}
	for k, fn in pairs(Panel) do d[k] = fn end
	d.bg = W.NineSlice(d, "card", { corner = 12, layer = "BACKGROUND", outset = 6 })
	d.bg:SetHex("#f6dcae")
	d.edge = W.NineSlice(d, "card_edge", { corner = 12, layer = "BACKGROUND", sublevel = 1, outset = 6 })
	d.edge:SetHex("#a06e3c", 0.6)

	d.title = W.Text(d, "titleL", "ink")
	d.title:SetPoint("TOPLEFT", d, "TOPLEFT", 2, -4)
	d.title:SetText(L["EMB_DESIGNER_TITLE"])
	d.done = W.Button(d, { text = L["EMB_DONE"], kind = "tonal", size = "sm", glyph = "glyph_check", onClick = function() d:Close() end })
	d.done:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)

	local P = Parts()
	sectionHead(d, L["EMB_BACKGROUND"], 42)
	d.bgRow = buildSwatches(d, P.COLORS.background, function(c) d:Pick("gc", c) end)
	layoutSwatches(d.bgRow, d, 84)

	d.borderStep = buildStepper(d, 210, L["EMB_BORDER_PREV"], L["EMB_BORDER_NEXT"], function(dir) d:CycleBorder(dir) end)
	sectionHead(d, L["EMB_BORDER"], 122, d.borderStep)
	d.borderRow = buildSwatches(d, P.COLORS.border, function(c) d:Pick("bc", c) end)
	layoutSwatches(d.borderRow, d, 164)

	d.emblemStep = buildStepper(d, 210, L["EMB_PAGE_PREV"], L["EMB_PAGE_NEXT"], function(dir) d:Page(d.page + dir) end)
	sectionHead(d, L["EMB_EMBLEM"], 202, d.emblemStep)
	d.tiles = {}
	for i = 1, Emblems().PAGE_SIZE do
		local tile = buildTile(d, function(index) d:Pick("e", index) end)
		tile:SetPoint("TOPLEFT", d, "TOPLEFT", ((i - 1) % COLS) * (TILE + TILE_GAP), -(244 + math.floor((i - 1) / COLS) * (TILE + TILE_GAP)))
		d.tiles[i] = tile
	end
	d.emblemRow = buildSwatches(d, P.COLORS.emblem, function(c) d:Pick("ec", c) end)
	layoutSwatches(d.emblemRow, d, 348)

	d.preview = ns.Emblem.Create(d, PREVIEW)
	d.preview:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -390)
	d.random = W.Button(d, { text = L["EMB_RANDOM"], kind = "tonal", size = "md", width = 200, onClick = function() d:Random() end })
	d.random:SetPoint("TOPLEFT", d, "TOPLEFT", 200, -398)
	d.reset = W.Button(d, { text = L["EMB_RESET"], kind = "tonal", size = "md", width = 200, tooltip = L["EMB_RESET_TIP"],
		onClick = function() d:Reset() end })
	d.reset:SetPoint("TOPLEFT", d, "TOPLEFT", 200, -444)
	d.note = W.Text(d, "caption", "ink2")
	d.note:SetPoint("TOPLEFT", d, "TOPLEFT", 200, -492)
	d.note:SetWidth(WIDTH - 200)
	d.note:SetHeight(64)
	d.note:SetWordWrap(true)
	d.note:SetJustifyV("TOP")
	d.note:SetText(L["EMB_PIECES_NOTE"])
	d.provisional = W.Text(d, "caption", "ink3")
	d.provisional:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -560)
	d.provisional:SetWidth(WIDTH)
	d.provisional:SetHeight(48)
	d.provisional:SetWordWrap(true)
	d.provisional:SetJustifyV("TOP")
	d.provisional:SetText(P.PROVISIONAL and L["EMB_PROVISIONAL"] or "")

	d.list = P.EmblemList(false)
	d.emb = Emblems().ToCustom(nil)
	d.page = 1
	d:Hide()
	return d
end

if ns.addon then ns.addon.EmblemDesigner = Designer end
