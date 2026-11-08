-- Widgets, part 5: things that show information. Lua 5.1.
--
--   W.Card(parent, opts)       surface. opts: kind ("plain" | "elevated" | "gold"), title, glyph, width, height
--       card.body (the frame for the content, below the title)  card:SetTitle(text)
--   W.Tag(parent, opts)        small label. opts: text, kind ("default" | "ok" | "bad" | "gold" | "casual" | "soft" | "hard")
--       tag:SetText(text)  tag:SetKind(kind)
--   W.Badge(parent, opts)      red count bubble (hidden at 0, "99+" above 99). badge:SetCount(n)
--   W.FormatCount(n)           the text of a badge: "" for 0 or less, "7", "99+"
--   W.RoleBadge(parent, opts)  round role badge with a tooltip. opts: role ("tank" | "healer" | "melee" | "ranged"), size (22)
--   W.ClassIcon(parent, opts)  the game's class icon in a ring of the class colour. opts: class ("WARRIOR"), size (26)
--       icon:SetClass(file)
--   W.Divider(parent, width)   a thin line that fades out at both ends
--   W.Plate(parent, opts)      the brown "plate" that heads a section of the left page. opts: text, width
-- Colours of tags come from Skin.TAGS; the class colour is the client's RAID_CLASS_COLORS (Assets.ClassColor).
local ADDON_NAME, ns = ...
ns = ns or {}
local W = ns.Widgets
local Skin = ns.Skin
local L = ns.L
local type, tostring = type, tostring
local max = math.max

---------------------------------------------------------------------------------------------------------------------
-- Card
---------------------------------------------------------------------------------------------------------------------
local CARDS = {
	plain = { fill = "#fff4de", fillAlpha = 0.55, edge = "#a06e3c", edgeAlpha = 0.45 },
	elevated = { fill = "#fbe9c5", fillAlpha = 1, edge = "#a06e3c", edgeAlpha = 0.4, shadow = true },
	gold = { fill = "#fbe8b4", fillAlpha = 1, edge = "#d6a23a", edgeAlpha = 1, shadow = true },
}

function W.Card(parent, opts)
	opts = opts or {}
	local style = CARDS[opts.kind] or CARDS.plain
	local card = CreateFrame("Frame", nil, parent)
	card:SetSize(opts.width or 280, opts.height or 100)
	card.kind = CARDS[opts.kind] and opts.kind or "plain"
	if style.shadow then
		card.shadow = W.NineSlice(card, "shadow", { corner = 32, outset = 20, layer = "BACKGROUND", sublevel = -2 })
		card.shadow:SetColor(0.2, 0.1, 0, 0.35)
	end
	card.bg = W.NineSlice(card, "card", { corner = 12, layer = "BACKGROUND" })
	card.bg:SetHex(style.fill, style.fillAlpha)
	card.edge = W.NineSlice(card, "card_edge", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	card.edge:SetHex(style.edge, style.edgeAlpha)
	if card.kind == "gold" then
		card.inner = W.NineSlice(card, "card_edge", { corner = 10, layer = "BACKGROUND", sublevel = 1, outset = -3 })
		card.inner:SetColor(1, 1, 1, 0.5)
	end

	local top = 14
	if opts.title or opts.glyph then
		local x = 16
		if opts.glyph then
			card.glyph = W.Texture(card, opts.glyph, "ARTWORK", "ink3")
			card.glyph:SetSize(20, 20)
			card.glyph:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -12)
			x = 44
		end
		card.title = W.Text(card, "titleS", "ink")
		card.title:SetPoint("TOPLEFT", card, "TOPLEFT", x, -14)
		card.title:SetPoint("RIGHT", card, "RIGHT", -16, 0)
		card.title:SetText(opts.title or "")
		top = 42
	end
	card.body = CreateFrame("Frame", nil, card)
	card.body:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -top)
	card.body:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 14)
	function card:SetTitle(text) if self.title then self.title:SetText(text or "") end end
	return card
end

---------------------------------------------------------------------------------------------------------------------
-- Tag
---------------------------------------------------------------------------------------------------------------------
function W.Tag(parent, opts)
	opts = opts or {}
	local tag = CreateFrame("Frame", nil, parent)
	tag:SetHeight(Skin.METRICS.tagH)
	tag.bg = W.NineSlice(tag, "card", { corner = 4, layer = "BACKGROUND" })
	tag.text = W.Text(tag, "overline", "ink", "CENTER")
	tag.text:SetPoint("CENTER", tag, "CENTER", 0, 0)
	function tag:SetKind(kind)
		local c = Skin.TAGS[kind] or Skin.TAGS.default
		self.kind = Skin.TAGS[kind] and kind or "default"
		self.bg:SetHex(c.bg)
		W.TextColor(self.text, c.text)
	end
	function tag:SetText(text)
		self.text:SetText(text or "")
		self:SetWidth(W.TextWidth(text or "", "overline") + 16)
	end
	function tag:GetText() return self.text:GetText() end
	tag:SetKind(opts.kind)
	tag:SetText(opts.text)
	return tag
end

---------------------------------------------------------------------------------------------------------------------
-- Badge
---------------------------------------------------------------------------------------------------------------------
-- "" for nothing to show, otherwise the count; above 99 it reads "99+".
function W.FormatCount(n)
	if type(n) ~= "number" or n ~= n or n < 1 then return "" end
	if n > 99 then return "99+" end
	return tostring(math.floor(n))
end

function W.Badge(parent, opts)
	opts = opts or {}
	local h = Skin.METRICS.badgeH
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetHeight(h)
	badge.rim = W.NineSlice(badge, "pill", { corner = h / 2, layer = "BACKGROUND", outset = 2 })
	badge.rim:SetHex("#2a0808")
	badge.bg = W.NineSlice(badge, "pill", { corner = h / 2, layer = "BACKGROUND", sublevel = 1 })
	badge.bg:SetHex("#d32f2f")
	badge.text = W.Text(badge, "overline", "white", "CENTER")
	badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
	function badge:SetCount(n)
		local text = W.FormatCount(n)
		self.count = n
		self.text:SetText(text)
		self:SetWidth(max(h, W.TextWidth(text, "overline") + 12))
		self:SetShown(text ~= "")
	end
	badge:SetCount(opts.count)
	return badge
end

---------------------------------------------------------------------------------------------------------------------
-- Role badge
---------------------------------------------------------------------------------------------------------------------
W.ROLE_MEDIA = { tank = "role_tank", healer = "role_healer", melee = "role_melee", ranged = "role_ranged" }

function W.RoleBadge(parent, opts)
	opts = opts or {}
	local size = opts.size or 22
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints(f)
	function f:SetRole(role)
		self.role = role
		local media = W.ROLE_MEDIA[role]
		self.icon:SetShown(media ~= nil)
		if media then self.icon:SetTexture(W.Media(media)) end
	end
	f:EnableMouse(true)
	W.SetTooltip(f, function()
		if f.role and L then return L["ROLE_" .. f.role] end
	end)
	f:SetRole(opts.role)
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- Class icon
---------------------------------------------------------------------------------------------------------------------
function W.ClassIcon(parent, opts)
	opts = opts or {}
	local size = opts.size or 26
	local ring = size >= 36 and 3.5 or (size <= 20 and 2 or 3)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.ringTexture = W.NineSlice(f, "card", { corner = 6, layer = "BACKGROUND", outset = ring })
	f.back = W.NineSlice(f, "card", { corner = 5, layer = "BACKGROUND", sublevel = 1, outset = max(ring - 1.5, 1) })
	f.back:SetHex("#1a120a")
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints(f)
	function f:SetClass(file)
		self.class = file
		self.ringTexture:SetColor(ns.Assets.ClassColor(file))
		local source = ns.Assets.ClassIcon(file)
		self.icon:SetShown(source ~= nil)
		if source and source.atlas then self.icon:SetAtlas(source.atlas)
		elseif source then self.icon:SetTexture(source.path); self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	end
	f:EnableMouse(true)
	W.SetTooltip(f, function()
		if f.class and L then return L["CLASS_" .. f.class] end
	end)
	f:SetClass(opts.class)
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- Divider and plate
---------------------------------------------------------------------------------------------------------------------
function W.Divider(parent, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width or 200, 1)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetTexture(W.Media("solid"))
	f.line:SetVertexColor(Skin.Color("line2", 0.8))
	f.line:SetAllPoints(f)
	return f
end

function W.Plate(parent, opts)
	opts = opts or {}
	local plate = CreateFrame("Frame", nil, parent)
	plate:SetSize(opts.width or 256, 34)
	plate.shadow = W.NineSlice(plate, "shadow", { corner = 32, outset = 12, layer = "BACKGROUND", sublevel = -2 })
	plate.shadow:SetColor(0.2, 0.1, 0, 0.35)
	plate.edge = W.NineSlice(plate, "card", { corner = 4, layer = "BACKGROUND", outset = 2 })
	plate.edge:SetHex("#6e4c2c")
	plate.bg = W.NineSlice(plate, "card", { corner = 4, layer = "BACKGROUND", sublevel = 1 })
	plate.bg:SetHex("#a07a52")
	plate.text = W.Text(plate, "titleS", "#fff4df")
	plate.text:SetPoint("LEFT", plate, "LEFT", 12, 0)
	plate.text:SetTextColor(Skin.Hex("#fff4df"))
	plate.text:SetText(opts.text or "")
	function plate:SetText(text) self.text:SetText(text or "") end
	return plate
end

if ns.addon then ns.addon.Widgets = W end
