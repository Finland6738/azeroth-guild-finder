-- Widgets, part 3: buttons. Lua 5.1.
--
--   W.Button(parent, opts)      glossy pill. opts: text, kind ("primary" | "discord" | "tonal" | "ghost" | "metal"),
--                               size ("sm" 30 | "md" 36 | "lg" 44), glyph (Media name), width (px, else from the text),
--                               tooltip, onClick(button, mouseButton), enabled (default true), reason (why it is off)
--       btn:SetLabel(text)  btn:SetKind(kind)  btn:SetEnabled(enabled, reason)  btn:SetOnClick(fn)  btn:GetLabel()
--       btn:SetGlyph(name)  btn.reasonText (FontString at the right of the button, shown while it is off with a reason)
--   W.IconButton(parent, opts)  round, glyph only. opts: glyph, size (36), tooltip (required: SPEC-04 §5.5), onClick
--   W.CloseButton(parent, onClick)  the round gold button with a steel ring at the corner of the window (42 px)
--
-- Red is the one main action of a screen, blue is only Discord, parchment (tonal) is secondary, grey is disabled and the
-- reason is written next to it (SPEC-04 §5.3).
local ADDON_NAME, ns = ...
ns = ns or {}
local W = ns.Widgets
local Skin = ns.Skin
local type = type

local function applyKind(btn)
	local k = Skin.KINDS[btn.enabledState and btn.kind or "disabled"] or Skin.KINDS.tonal
	if k.fill then btn.fill:SetHex(k.fill) end
	btn.fill:SetShown(k.fill ~= nil)
	btn.rim:SetShown(k.rim ~= nil)
	if k.rim then btn.rim:SetHex(k.rim) end
	btn.gloss:SetShown(k.gloss)
	W.TextColor(btn.text, k.text)
	if btn.glyphTexture then
		local r, g, b = Skin.Hex(k.text)
		btn.glyphTexture:SetVertexColor(r, g, b, 1)
	end
end

local function layout(btn)
	local m = Skin.METRICS
	btn.text:ClearAllPoints()
	btn.text:SetPoint("CENTER", btn, "CENTER", btn.glyphTexture and 12 or 0, 0)
	if btn.glyphTexture then
		btn.glyphTexture:ClearAllPoints()
		btn.glyphTexture:SetPoint("RIGHT", btn.text, "LEFT", -6, 0)
	end
	if not btn.fixedWidth then
		local extra = btn.glyphTexture and 26 or 0
		btn:SetWidth(W.TextWidth(btn.text:GetText(), btn.styleKey) + 2 * m.buttonPad[btn.sizeKey] + extra)
	end
end

local function tooltipFor(btn)
	local lines = {}
	local title = btn.tooltipTitle
	if not btn.enabledState and btn.reason then
		lines[#lines + 1] = { text = btn.reason, color = "gold" }
		title = title or btn:GetLabel()
	end
	if not title then return nil end
	return { title = title, lines = lines }
end

function W.Button(parent, opts)
	opts = opts or {}
	local m = Skin.METRICS
	local sizeKey = (opts.size == "sm" or opts.size == "lg") and opts.size or "md"
	local h = m.buttonH[sizeKey]
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(h)
	btn.sizeKey = sizeKey
	btn.styleKey = sizeKey == "sm" and "buttonSm" or (sizeKey == "lg" and "buttonLg" or "button")
	btn.kind = Skin.KINDS[opts.kind] and opts.kind or "tonal"
	btn.enabledState = true
	btn.onClick = opts.onClick
	btn.fixedWidth = opts.width ~= nil
	if opts.width then btn:SetWidth(opts.width) end
	btn:RegisterForClicks("LeftButtonUp")

	btn.shadow = W.NineSlice(btn, "shadow", { corner = 32, outset = 14, layer = "BACKGROUND", sublevel = -2 })
	btn.shadow:SetColor(0.2, 0.1, 0, 0.35)
	btn.fill = W.NineSlice(btn, "pill", { corner = h / 2, layer = "BACKGROUND", sublevel = 0 })
	btn.gloss = W.NineSlice(btn, "pill_gloss", { corner = h / 2, layer = "BACKGROUND", sublevel = 1 })
	btn.gloss:SetColor(1, 1, 1, 0.55)
	btn.rim = W.NineSlice(btn, "pill_rim", { corner = h / 2, layer = "BACKGROUND", sublevel = 2 })
	btn.hover = W.NineSlice(btn, "pill", { corner = h / 2, layer = "ARTWORK", sublevel = 1 })
	btn.hover:SetColor(1, 1, 1, 0.16)
	btn.hover:Hide()
	btn.press = W.NineSlice(btn, "pill", { corner = h / 2, layer = "ARTWORK", sublevel = 2 })
	btn.press:SetColor(0, 0, 0, 0.18)
	btn.press:Hide()

	btn.text = W.Text(btn, btn.styleKey, "ink", "CENTER")
	btn.text:SetText(opts.text or "")
	if opts.glyph then
		btn.glyphTexture = W.Texture(btn, opts.glyph, "OVERLAY")
		btn.glyphTexture:SetSize(18, 18)
	end

	-- state
	function btn:GetLabel() return self.text:GetText() end
	function btn:SetLabel(text) self.text:SetText(text or ""); layout(self) end
	function btn:SetKind(kind)
		if Skin.KINDS[kind] then self.kind = kind; applyKind(self) end
	end
	function btn:SetOnClick(fn) self.onClick = fn end
	function btn:SetGlyph(name)
		if not self.glyphTexture then self.glyphTexture = W.Texture(self, name, "OVERLAY"); self.glyphTexture:SetSize(18, 18)
		else self.glyphTexture:SetTexture(W.Media(name)) end
		layout(self); applyKind(self)
	end
	local nativeSetEnabled = btn.SetEnabled
	function btn:SetEnabled(enabled, reason)
		enabled = enabled and true or false
		nativeSetEnabled(self, enabled)
		self.enabledState = enabled
		self.reason = (not enabled) and reason or nil
		self.reasonText:SetText(self.reason or "")
		self.reasonText:SetShown(self.reason ~= nil)
		self.hover:Hide(); self.press:Hide()
		applyKind(self)
	end
	function btn:Enable() self:SetEnabled(true) end
	function btn:Disable() self:SetEnabled(false, self.reason) end

	btn.reasonText = W.Text(btn, "caption", "ink2")
	btn.reasonText:SetPoint("LEFT", btn, "RIGHT", 10, 0)
	btn.reasonText:Hide()

	btn.tooltipTitle = opts.tooltip
	W.SetTooltip(btn, function() return tooltipFor(btn) end)

	btn:SetScript("OnEnter", function(self) if self.enabledState then self.hover:Show() end end)
	btn:SetScript("OnLeave", function(self) self.hover:Hide(); self.press:Hide() end)
	btn:SetScript("OnMouseDown", function(self) if self.enabledState then self.press:Show() end end)
	btn:SetScript("OnMouseUp", function(self) self.press:Hide() end)
	btn:SetScript("OnClick", function(self, mouseButton)
		if self.enabledState and self.onClick then self.onClick(self, mouseButton) end
	end)

	applyKind(btn)
	layout(btn)
	if opts.enabled == false then btn:SetEnabled(false, opts.reason) end
	return btn
end

---------------------------------------------------------------------------------------------------------------------
-- Icon button
---------------------------------------------------------------------------------------------------------------------
function W.IconButton(parent, opts)
	opts = opts or {}
	local size = opts.size or 36
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size, size)
	btn.hover = W.Texture(btn, "disc", "BACKGROUND", "ink2", 0.12)
	btn.hover:SetAllPoints(btn)
	btn.hover:Hide()
	btn.glyph = W.Texture(btn, opts.glyph or "glyph_gear", "ARTWORK", "ink2")
	btn.glyph:SetSize(size * 0.55, size * 0.55)
	btn.glyph:SetPoint("CENTER")
	btn.onClick = opts.onClick
	btn:RegisterForClicks("LeftButtonUp")
	W.SetTooltip(btn, opts.tooltip)
	btn:SetScript("OnEnter", function(self) self.hover:Show() end)
	btn:SetScript("OnLeave", function(self) self.hover:Hide() end)
	btn:SetScript("OnClick", function(self, mouseButton) if self.onClick then self.onClick(self, mouseButton) end end)
	function btn:SetOnClick(fn) self.onClick = fn end
	return btn
end

---------------------------------------------------------------------------------------------------------------------
-- Close button: a steel ring around a gold disc with a dark cross
---------------------------------------------------------------------------------------------------------------------
function W.CloseButton(parent, onClick, tooltip)
	local size = Skin.METRICS.closeSize
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size, size)
	btn:RegisterForClicks("LeftButtonUp")
	local shadow = W.Texture(btn, "disc", "BACKGROUND", nil)
	shadow:SetVertexColor(0, 0, 0, 0.4)
	shadow:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 1); shadow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -5)
	local steel = W.Texture(btn, "disc_shiny", "BACKGROUND", "steel")
	steel:SetAllPoints(btn)
	local gold = W.Texture(btn, "disc_shiny", "ARTWORK", "gold")
	gold:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, -5); gold:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
	local ring = W.Texture(btn, "disc_ring", "ARTWORK", nil)
	ring:SetVertexColor(0.23, 0.16, 0.06, 1)
	ring:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, -5); ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
	local x = W.Texture(btn, "glyph_close", "OVERLAY", nil)
	x:SetVertexColor(0.17, 0.10, 0.02, 1)
	x:SetSize(22, 22); x:SetPoint("CENTER")
	local glow = W.Texture(btn, "disc", "OVERLAY", nil)
	glow:SetVertexColor(1, 1, 1, 0.22)
	glow:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, -5); glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
	glow:Hide()
	btn.glow = glow
	btn.onClick = onClick
	if tooltip then W.SetTooltip(btn, tooltip) end
	btn:SetScript("OnEnter", function(self) self.glow:Show() end)
	btn:SetScript("OnLeave", function(self) self.glow:Hide() end)
	btn:SetScript("OnClick", function(self, mouseButton) if self.onClick then self.onClick(self, mouseButton) end end)
	return btn
end
