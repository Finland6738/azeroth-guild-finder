-- Widgets, part 4: controls the player operates. Lua 5.1.
--
--   W.Chip(parent, opts)          filter chip. opts: text, selected, tooltip, icon (Media name, drawn before the text),
--                                 onToggle(selected, chip)
--       chip:SetSelected(bool, silent)  chip:GetSelected()  chip:SetLabel(text)
--       chip:SetEnabled(bool, reason)   a disabled chip is dimmed, ignores clicks and says `reason` in its tooltip
--   W.ChipGroup(parent, items, opts)   wrapping rows of chips. items: { { key, text, tooltip, icon }, ... }
--       opts: width, multi (default true), max (most chips selected at once), onChange(keys), onLimit(max)
--       group:GetSelected() (keys in item order)  group:SetSelected(keys, silent)  group:Clear(silent)  group.chips[key]
--       group:SetEnabled(key, bool, reason)
--   W.Switch(parent, opts)        on/off switch, with a label row when `label` is given. opts: checked, label, width, onChange(checked)
--       sw:GetChecked()  sw:SetChecked(bool, silent)  sw:Toggle()
--   W.Segmented(parent, items, opts)   one choice out of a few. items: { { key, text, tooltip }, ... }
--       opts: selected, width, onChange(key)      seg:GetSelected()  seg:SetSelected(key, silent)  seg.segments[key]
--   W.DayToggles(parent, opts)    seven small day squares (Monday first). opts: width, labels ({ "M", ... }), names (tooltips),
--                                 mask, onChange(mask)     days:GetMask()  days:SetMask(mask, silent)  days.buttons[1..7]
--   W.Select(parent, opts)        a field that opens a list of choices. opts: width, glyph (Media name), items
--                                 ({ { key, text }, ... }), multi (default false), emptyText (shown when nothing is chosen),
--                                 summary(keys) -> text (default: the labels, joined), onChange(keys), tooltip
--       sel:GetSelected() (keys in item order)  sel:SetSelected(keys, silent)  sel:SetItems(items)  sel:Open()  sel:Close()
--       sel:IsOpen()  sel:SetEnabled(bool)   a single choice closes the list; a multiple choice stays open until a click outside
--   W.Field(parent, opts)         text field (a pill with an EditBox in it). opts: placeholder, text, glyph, maxLetters,
--                                 width, onChange(text, userInput), onEnter(text), clearButton (default true)
--       field.edit (the EditBox)  field:GetText()  field:SetText(text, silent)  field:Clear()  field:SetFocus()
--   W.CopyField(parent, opts)     read-only mono field with a "select all" button (addons cannot reach the clipboard:
--                                 the text is selected and the player presses Ctrl+C). opts: text, width, label, hint
--       field:SetValue(text)  field:GetValue()  field:SelectAll()
-- "silent" means: change the state without calling the callback.
local ADDON_NAME, ns = ...
ns = ns or {}
local W = ns.Widgets
local Skin = ns.Skin
local L = ns.L
local type, ipairs, pairs, tonumber, tostring = type, ipairs, pairs, tonumber, tostring
local min, max = math.min, math.max

---------------------------------------------------------------------------------------------------------------------
-- Chip
---------------------------------------------------------------------------------------------------------------------
local CHIP_OFF = { fill = "#fff5e1", fillAlpha = 0.45, edge = "#b98a53", text = "#4a2c12" }
local CHIP_ON = { fill = "#5a3315", fillAlpha = 1, edge = "#3d210b", text = "#ffeac2" }

local function paintChip(chip)
	local c = chip.selected and CHIP_ON or CHIP_OFF
	chip.bg:SetHex(c.fill, c.fillAlpha)
	chip.edge:SetHex(c.edge, 1)
	W.TextColor(chip.text, c.text)
	chip.check:SetShown(chip.selected)
end

function W.Chip(parent, opts)
	opts = opts or {}
	local h = Skin.METRICS.chipH
	local chip = CreateFrame("Button", nil, parent)
	chip:SetHeight(h)
	chip:RegisterForClicks("LeftButtonUp")
	chip.bg = W.NineSlice(chip, "card", { corner = 8, layer = "BACKGROUND" })
	chip.edge = W.NineSlice(chip, "card_edge", { corner = 8, layer = "BACKGROUND", sublevel = 1 })
	chip.hover = W.NineSlice(chip, "card", { corner = 8, layer = "ARTWORK" })
	chip.hover:SetColor(1, 1, 1, 0.2)
	chip.hover:Hide()
	chip.check = W.Texture(chip, "glyph_check", "OVERLAY", nil)
	chip.check:SetVertexColor(1, 0.92, 0.76, 1)
	chip.check:SetSize(14, 14)
	chip.check:SetPoint("LEFT", chip, "LEFT", 9, 0)
	local textX = 27
	if opts.icon then
		chip.icon = W.Texture(chip, opts.icon, "OVERLAY", nil)
		chip.icon:SetSize(18, 18)
		chip.icon:SetPoint("LEFT", chip, "LEFT", 27, 0)
		textX = 49
	end
	chip.text = W.Text(chip, "label", "ink")
	chip.text:SetPoint("LEFT", chip, "LEFT", textX, 0)
	chip.selected = opts.selected and true or false
	chip.enabledState = true
	chip.onToggle = opts.onToggle

	function chip:SetLabel(text)
		self.text:SetText(text or "")
		self:SetWidth(textX + W.TextWidth(text or "", "label") + 13)
	end
	function chip:GetLabel() return self.text:GetText() end
	function chip:GetSelected() return self.selected end
	function chip:SetSelected(value, silent)
		value = value and true or false
		if self.selected == value then return end
		self.selected = value
		paintChip(self)
		if not silent and self.onToggle then self.onToggle(value, self) end
	end
	function chip:SetEnabled(value, reason)
		self.enabledState = value ~= false
		self.reason = (not self.enabledState) and reason or nil
		self:SetAlpha(self.enabledState and 1 or 0.45)
		if not self.enabledState then self.hover:Hide() end
	end
	function chip:IsChipEnabled() return self.enabledState end
	chip:SetScript("OnClick", function(self) if self.enabledState then self:SetSelected(not self.selected) end end)
	chip:SetScript("OnEnter", function(self) if self.enabledState then self.hover:Show() end end)
	chip:SetScript("OnLeave", function(self) self.hover:Hide() end)
	W.SetTooltip(chip, function()
		local base = chip.baseTooltip
		if type(base) == "function" then base = base() end
		if chip.reason then
			local title = type(base) == "table" and base.title or base or chip:GetLabel()
			return { title = title, lines = { { text = chip.reason, color = "gold" } } }
		end
		return base
	end)
	chip.baseTooltip = opts.tooltip
	chip:SetLabel(opts.text)
	paintChip(chip)
	return chip
end

---------------------------------------------------------------------------------------------------------------------
-- Chip group
---------------------------------------------------------------------------------------------------------------------
function W.ChipGroup(parent, items, opts)
	opts = opts or {}
	local gap = 6
	local group = CreateFrame("Frame", nil, parent)
	local width = opts.width or 280
	group:SetWidth(width)
	group.chips, group.order = {}, {}
	group.multi = opts.multi ~= false
	group.max = opts.max
	group.onChange = opts.onChange
	group.onLimit = opts.onLimit
	group.silent = false

	local function selectedKeys()
		local keys = {}
		for _, key in ipairs(group.order) do
			if group.chips[key].selected then keys[#keys + 1] = key end
		end
		return keys
	end

	local function changed()
		if not group.silent and group.onChange then group.onChange(selectedKeys()) end
	end

	local x, y, rowH = 0, 0, Skin.METRICS.chipH
	for _, item in ipairs(items) do
		local chip = W.Chip(group, { text = item.text, tooltip = item.tooltip, icon = item.icon })
		local w = chip:GetWidth()
		if x > 0 and x + w > width then x, y = 0, y + rowH + gap end
		chip:SetPoint("TOPLEFT", group, "TOPLEFT", x, -y)
		x = x + w + gap
		chip.key = item.key
		chip.onToggle = function(selected, self)
			if selected and not group.multi then
				group.silent = true
				for _, other in pairs(group.chips) do if other ~= self then other:SetSelected(false) end end
				group.silent = false
			elseif selected and group.max and #selectedKeys() > group.max then
				self:SetSelected(false, true)
				if group.onLimit then group.onLimit(group.max) end
				return
			end
			changed()
		end
		group.chips[item.key] = chip
		group.order[#group.order + 1] = item.key
	end
	group:SetHeight(y + rowH)

	function group:GetSelected() return selectedKeys() end
	function group:SetSelected(keys, silent)
		local want = {}
		for _, key in ipairs(keys or {}) do want[key] = true end
		self.silent = true
		for _, key in ipairs(self.order) do self.chips[key]:SetSelected(want[key]) end
		self.silent = false
		if not silent then changed() end
	end
	function group:Clear(silent) self:SetSelected({}, silent) end
	function group:SetEnabled(key, value, reason)
		if self.chips[key] then self.chips[key]:SetEnabled(value, reason) end
	end
	return group
end

---------------------------------------------------------------------------------------------------------------------
-- Switch
---------------------------------------------------------------------------------------------------------------------
local SWITCH_OFF, SWITCH_ON = "#b8925f", "#276b2c"

local function paintSwitch(sw)
	local m = Skin.METRICS
	sw.track:SetHex(sw.checked and SWITCH_ON or SWITCH_OFF)
	sw.knob:ClearAllPoints()
	if sw.checked then
		sw.knob:SetSize(20, 20)
		sw.knob:SetPoint("RIGHT", sw.trackFrame, "RIGHT", -3, 0)
		sw.knob:SetVertexColor(1, 0.97, 0.88, 1)
	else
		sw.knob:SetSize(14, 14)
		sw.knob:SetPoint("LEFT", sw.trackFrame, "LEFT", 6, 0)
		sw.knob:SetVertexColor(0.78, 0.82, 0.86, 1)
	end
end

function W.Switch(parent, opts)
	opts = opts or {}
	local m = Skin.METRICS
	local sw = CreateFrame("Button", nil, parent)
	sw:SetSize(opts.label and (opts.width or 280) or m.switchW, max(m.switchH, opts.label and 30 or 0))
	sw:RegisterForClicks("LeftButtonUp")
	sw.checked = opts.checked and true or false
	sw.onChange = opts.onChange

	local track = CreateFrame("Frame", nil, sw)
	track:SetSize(m.switchW, m.switchH)
	track:SetPoint("RIGHT", sw, "RIGHT", 0, 0)
	sw.trackFrame = track
	sw.track = W.NineSlice(track, "pill", { corner = m.switchH / 2, layer = "BACKGROUND" })
	sw.trackRim = W.NineSlice(track, "pill_rim", { corner = m.switchH / 2, layer = "BACKGROUND", sublevel = 1 })
	sw.trackRim:SetColor(0.2, 0.12, 0.05, 0.85)
	sw.knob = track:CreateTexture(nil, "ARTWORK")
	sw.knob:SetTexture(W.Media("disc_shiny"))
	if opts.label then
		sw.label = W.Text(sw, "body", "ink")
		sw.label:SetPoint("LEFT", sw, "LEFT", 0, 0)
		sw.label:SetPoint("RIGHT", track, "LEFT", -10, 0)
		sw.label:SetText(opts.label)
	end

	function sw:GetChecked() return self.checked end
	function sw:SetChecked(value, silent)
		value = value and true or false
		if value == self.checked then return end
		self.checked = value
		paintSwitch(self)
		if not silent and self.onChange then self.onChange(value, self) end
	end
	function sw:Toggle() self:SetChecked(not self.checked) end
	sw:SetScript("OnClick", function(self) self:Toggle() end)
	paintSwitch(sw)
	return sw
end

---------------------------------------------------------------------------------------------------------------------
-- Segmented control
---------------------------------------------------------------------------------------------------------------------
function W.Segmented(parent, items, opts)
	opts = opts or {}
	local h, pad = 36, 3
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetHeight(h)
	seg.segments, seg.order = {}, {}
	seg.onChange = opts.onChange
	seg.bg = W.NineSlice(seg, "field", { corner = h / 2, layer = "BACKGROUND" })
	seg.bg:SetHex("#fff4dd")
	seg.ring = W.NineSlice(seg, "field_ring", { corner = h / 2, layer = "BACKGROUND", sublevel = 1 })
	seg.ring:SetHex("#4a525a")

	local widths, total = {}, 0
	for i, item in ipairs(items) do
		widths[i] = max(56, W.TextWidth(item.text, "label") + 28)
		total = total + widths[i]
	end
	local width = opts.width or (total + 2 * pad)
	local inner = width - 2 * pad
	seg:SetWidth(width)
	local x = pad
	for i, item in ipairs(items) do
		local w = opts.width and (inner / #items) or widths[i]
		local b = CreateFrame("Button", nil, seg)
		b:SetSize(w, h - 2 * pad)
		b:SetPoint("LEFT", seg, "LEFT", x, 0)
		b:RegisterForClicks("LeftButtonUp")
		b.bg = W.NineSlice(b, "pill", { corner = (h - 2 * pad) / 2, layer = "ARTWORK" })
		b.bg:SetHex("#5a3315")
		b.bg:Hide()
		b.text = W.Text(b, "label", "ink", "CENTER")
		b.text:SetAllPoints(b)
		b.text:SetText(item.text)
		b.key = item.key
		if item.tooltip then W.SetTooltip(b, item.tooltip) end
		b:SetScript("OnClick", function(self) seg:SetSelected(self.key) end)
		seg.segments[item.key] = b
		seg.order[#seg.order + 1] = item.key
		x = x + w
	end

	function seg:GetSelected() return self.selected end
	function seg:SetSelected(key, silent)
		if (key ~= nil and not self.segments[key]) or key == self.selected then return end   -- nil clears the choice
		self.selected = key
		for k, b in pairs(self.segments) do
			local on = k == key
			b.bg:SetShown(on)
			W.TextColor(b.text, on and "#ffeac2" or "#4a2c12")
		end
		if not silent and self.onChange then self.onChange(key, self) end
	end
	if opts.selected then seg:SetSelected(opts.selected, true) end
	return seg
end

---------------------------------------------------------------------------------------------------------------------
-- Day toggles: seven small squares, Monday first
---------------------------------------------------------------------------------------------------------------------
function W.DayToggles(parent, opts)
	opts = opts or {}
	local size, count = 32, 7
	local width = opts.width or 260
	local gap = (width - count * size) / (count - 1)
	local days = CreateFrame("Frame", nil, parent)
	days:SetSize(width, size)
	days.buttons = {}
	days.mask = 0
	days.onChange = opts.onChange

	local function paint(button)
		local c = button.on and CHIP_ON or CHIP_OFF
		button.bg:SetHex(c.fill, c.fillAlpha)
		button.edge:SetHex(c.edge, 1)
		W.TextColor(button.text, c.text)
	end

	for i = 1, count do
		local b = CreateFrame("Button", nil, days)
		b:SetSize(size, size)
		b:SetPoint("TOPLEFT", days, "TOPLEFT", (i - 1) * (size + gap), 0)
		b:RegisterForClicks("LeftButtonUp")
		b.bg = W.NineSlice(b, "card", { corner = 8, layer = "BACKGROUND" })
		b.edge = W.NineSlice(b, "card_edge", { corner = 8, layer = "BACKGROUND", sublevel = 1 })
		b.hover = W.NineSlice(b, "card", { corner = 8, layer = "ARTWORK" })
		b.hover:SetColor(1, 1, 1, 0.2)
		b.hover:Hide()
		b.text = W.Text(b, "label", "ink", "CENTER")
		b.text:SetAllPoints(b)
		b.text:SetText(opts.labels and opts.labels[i] or tostring(i))
		b.day, b.on = i, false
		if opts.names and opts.names[i] then W.SetTooltip(b, opts.names[i]) end
		b:SetScript("OnEnter", function(self) self.hover:Show() end)
		b:SetScript("OnLeave", function(self) self.hover:Hide() end)
		b:SetScript("OnClick", function(self)
			local mask = days.mask
			days:SetMask(self.on and mask - 2 ^ (i - 1) or mask + 2 ^ (i - 1))
		end)
		days.buttons[i] = b
		paint(b)
	end

	function days:GetMask() return self.mask end
	function days:SetMask(mask, silent)
		mask = math.floor(tonumber(mask) or 0)
		if mask < 0 or mask > 127 then mask = 0 end
		self.mask = mask
		for i, b in ipairs(self.buttons) do
			b.on = math.floor(mask / 2 ^ (i - 1)) % 2 == 1
			paint(b)
		end
		if not silent and self.onChange then self.onChange(mask) end
	end
	days:SetMask(opts.mask or 0, true)
	return days
end

---------------------------------------------------------------------------------------------------------------------
-- Select: a field that opens a list of choices (the list scrolls with the mouse wheel when it is long)
---------------------------------------------------------------------------------------------------------------------
local SELECT_ROW_H, SELECT_PAD = 26, 4
local selectCatcher   -- one invisible full-screen button that closes the open list on any click outside it
local openSelect

local function closeOpenSelect() if openSelect then openSelect:Close() end end

local function selectedKeys(sel)
	local keys = {}
	for _, item in ipairs(sel.items) do
		if sel.chosen[item.key] then keys[#keys + 1] = item.key end
	end
	return keys
end

local function selectText(sel)
	local keys = selectedKeys(sel)
	local text
	if sel.summary then
		text = sel.summary(keys)
	elseif #keys > 0 then
		local labels = {}
		for _, item in ipairs(sel.items) do
			if sel.chosen[item.key] then labels[#labels + 1] = item.text end
		end
		text = table.concat(labels, ", ")
	end
	if text == nil or text == "" then
		sel.text:SetText(sel.emptyText or "")
		W.TextColor(sel.text, "ink3")
	else
		sel.text:SetText(text)
		W.TextColor(sel.text, "ink")
	end
end

local function refreshPopup(sel)
	local pop = sel.popup
	if not pop then return end
	local total = #sel.items
	local visible = min(total, sel.maxRows)
	sel.offset = max(0, min(sel.offset, total - visible))
	local scrolls = total > visible
	for i = 1, visible do
		local row = pop.rows[i]
		if not row then
			row = CreateFrame("Button", nil, pop)
			row:SetHeight(SELECT_ROW_H)
			row:RegisterForClicks("LeftButtonUp")
			row:SetPoint("TOPLEFT", pop, "TOPLEFT", SELECT_PAD, -(SELECT_PAD + (i - 1) * SELECT_ROW_H))
			row:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -SELECT_PAD - (scrolls and 8 or 0), -(SELECT_PAD + (i - 1) * SELECT_ROW_H))
			row.hover = W.Texture(row, "solid", "BACKGROUND", "gold", 0.25)
			row.hover:SetAllPoints(row)
			row.hover:Hide()
			row.check = W.Texture(row, "glyph_check", "OVERLAY", "ink")
			row.check:SetSize(14, 14)
			row.check:SetPoint("LEFT", row, "LEFT", 6, 0)
			row.text = W.Text(row, "body", "ink")
			row.text:SetPoint("LEFT", row, "LEFT", 26, 0)
			row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
			row.text:SetWordWrap(false)
			row:SetScript("OnEnter", function(self) self.hover:Show() end)
			row:SetScript("OnLeave", function(self) self.hover:Hide() end)
			row:SetScript("OnClick", function(self) sel:Choose(self.key) end)
			pop.rows[i] = row
		end
		local item = sel.items[sel.offset + i]
		row.key = item.key
		row.text:SetText(item.text)
		row.check:SetShown(sel.chosen[item.key] == true)
		W.TextColor(row.text, sel.chosen[item.key] and "gold2" or "ink")
		row:Show()
	end
	for i = visible + 1, #pop.rows do pop.rows[i]:Hide() end
	pop:SetSize(sel:GetWidth(), visible * SELECT_ROW_H + 2 * SELECT_PAD)
	pop.more:SetShown(scrolls)
	if scrolls then
		local room = visible * SELECT_ROW_H
		local thumb = max(18, room * visible / total)
		pop.more:SetHeight(thumb)
		pop.more:ClearAllPoints()
		pop.more:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -4, -(SELECT_PAD + (room - thumb) * (sel.offset / (total - visible))))
	end
end

local function buildPopup(sel)
	local pop = CreateFrame("Frame", nil, sel)
	pop:SetFrameStrata("FULLSCREEN_DIALOG")
	pop:SetFrameLevel(20)
	pop:EnableMouse(true)
	pop:EnableMouseWheel(true)
	pop.shadow = W.NineSlice(pop, "shadow", { corner = 32, outset = 14, layer = "BACKGROUND", sublevel = -2 })
	pop.shadow:SetColor(0.2, 0.1, 0, 0.45)
	pop.bg = W.NineSlice(pop, "card", { corner = 10, layer = "BACKGROUND" })
	pop.bg:SetHex("#fbe9c5", 1)
	pop.edge = W.NineSlice(pop, "card_edge", { corner = 10, layer = "BACKGROUND", sublevel = 1 })
	pop.edge:SetHex("#a06e3c", 0.9)
	pop.more = W.Texture(pop, "pill", "OVERLAY", nil)
	pop.more:SetVertexColor(Skin.Hex("#8c6844"))
	pop.more:SetWidth(4)
	pop.rows = {}
	pop:SetScript("OnMouseWheel", function(_, delta)
		sel.offset = sel.offset - delta * 3
		refreshPopup(sel)
	end)
	pop:Hide()
	return pop
end

-- The invisible full-screen button behind an open list (nil until a list was opened); tests click it.
function W.SelectBackdrop() return selectCatcher end

function W.Select(parent, opts)
	opts = opts or {}
	local h = opts.height or Skin.METRICS.fieldH
	local corner = opts.corner or h / 2
	local sel = CreateFrame("Button", nil, parent)
	sel:SetSize(opts.width or 240, h)
	sel:RegisterForClicks("LeftButtonUp")
	sel.bg = W.NineSlice(sel, "field", { corner = corner, layer = "BACKGROUND" })
	sel.bg:SetHex("#fff4dd")
	sel.ring = W.NineSlice(sel, "field_ring", { corner = corner, layer = "BACKGROUND", sublevel = 1 })
	sel.ring:SetHex("#4a525a")
	sel.items, sel.chosen, sel.offset = {}, {}, 0
	sel.multi = opts.multi == true
	sel.maxRows = opts.maxRows or 8
	sel.summary, sel.emptyText, sel.onChange = opts.summary, opts.emptyText, opts.onChange
	sel.enabledState = true

	local left = 14
	if opts.glyph then
		sel.icon = W.Texture(sel, opts.glyph, "ARTWORK", "ink2")
		sel.icon:SetSize(18, 18)
		sel.icon:SetPoint("LEFT", sel, "LEFT", 14, 0)
		left = 38
	end
	sel.caret = W.Texture(sel, "glyph_back", "ARTWORK", "ink")
	sel.caret:SetSize(14, 14)
	sel.caret:SetPoint("RIGHT", sel, "RIGHT", -12, 0)
	if sel.caret.SetRotation then sel.caret:SetRotation(math.pi / 2) end   -- the arrow of glyph_back points left: now down
	sel.text = W.Text(sel, "body", "ink")
	sel.text:SetPoint("LEFT", sel, "LEFT", left, 0)
	sel.text:SetPoint("RIGHT", sel, "RIGHT", -32, 0)
	sel.text:SetWordWrap(false)

	function sel:SetItems(items)
		self.items = items or {}
		local valid = {}
		for _, item in ipairs(self.items) do valid[item.key] = true end
		for key in pairs(self.chosen) do if not valid[key] then self.chosen[key] = nil end end
		selectText(self)
		refreshPopup(self)
	end
	function sel:GetSelected() return selectedKeys(self) end
	function sel:SetSelected(keys, silent)
		if type(keys) ~= "table" then keys = keys ~= nil and { keys } or {} end
		local valid, chosen = {}, {}
		for _, item in ipairs(self.items) do valid[item.key] = true end
		for _, key in ipairs(keys) do
			if valid[key] then
				chosen[key] = true
				if not self.multi then break end
			end
		end
		self.chosen = chosen
		selectText(self)
		refreshPopup(self)
		if not silent and self.onChange then self.onChange(selectedKeys(self)) end
	end
	-- A row was clicked: toggles it (multiple choice) or takes it and closes the list.
	function sel:Choose(key)
		if self.multi then
			self.chosen[key] = (not self.chosen[key]) or nil
		else
			self.chosen = { [key] = true }
		end
		selectText(self)
		refreshPopup(self)
		if not self.multi then self:Close() end
		if self.onChange then self.onChange(selectedKeys(self)) end
	end
	function sel:IsOpen() return self.popup ~= nil and self.popup:IsShown() end
	-- `first`: the 1-based index of the choice the list starts at (a long list opens near the current value).
	function sel:Open(first)
		if not self.enabledState or #self.items == 0 then return end
		closeOpenSelect()
		if not selectCatcher then
			selectCatcher = CreateFrame("Button", nil, UIParent)
			selectCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
			selectCatcher:SetFrameLevel(1)
			selectCatcher:SetAllPoints(UIParent)
			selectCatcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			selectCatcher:SetScript("OnClick", closeOpenSelect)
			selectCatcher:Hide()
		end
		self.popup = self.popup or buildPopup(self)
		self.offset = max(0, (first or 1) - 1)
		refreshPopup(self)
		self.popup:ClearAllPoints()
		self.popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -3)
		selectCatcher:Show()
		self.popup:Show()
		openSelect = self
		self.ring:SetHex("#b8820f")
	end
	function sel:Close()
		if self.popup then self.popup:Hide() end
		if openSelect == self then
			openSelect = nil
			if selectCatcher then selectCatcher:Hide() end
		end
		self.ring:SetHex("#4a525a")
	end
	function sel:SetEnabled(value)
		self.enabledState = value ~= false
		self:SetAlpha(self.enabledState and 1 or 0.5)
		if not self.enabledState then self:Close() end
	end
	sel:SetScript("OnClick", function(self)
		if self:IsOpen() then self:Close() else self:Open(self.openAt and self.openAt()) end
	end)
	sel:SetScript("OnHide", function(self) self:Close() end)
	if opts.tooltip then W.SetTooltip(sel, opts.tooltip) end
	sel.openAt = opts.openAt
	sel:SetItems(opts.items)
	return sel
end

---------------------------------------------------------------------------------------------------------------------
-- Field
---------------------------------------------------------------------------------------------------------------------
local function fieldFrame(parent, width, radius)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width or 240, Skin.METRICS.fieldH)
	f.bg = W.NineSlice(f, "field", { corner = radius, layer = "BACKGROUND" })
	f.ring = W.NineSlice(f, "field_ring", { corner = radius, layer = "BACKGROUND", sublevel = 1 })
	return f
end

function W.Field(parent, opts)
	opts = opts or {}
	local h = Skin.METRICS.fieldH
	local field = fieldFrame(parent, opts.width, h / 2)
	field.bg:SetHex("#fff4dd")
	field.ring:SetHex("#4a525a")
	field.onChange, field.onEnter = opts.onChange, opts.onEnter
	field.silent = false

	local leftPad = 14
	if opts.glyph then
		field.icon = W.Texture(field, opts.glyph, "ARTWORK", "ink2")
		field.icon:SetSize(18, 18)
		field.icon:SetPoint("LEFT", field, "LEFT", 14, 0)
		leftPad = 38
	end

	local edit = CreateFrame("EditBox", nil, field)
	field.edit = edit
	edit:SetAutoFocus(false)
	edit:SetFontObject(Skin.Font("bodyL"))
	edit:SetTextColor(Skin.Color("ink"))
	edit:SetPoint("LEFT", field, "LEFT", leftPad, 0)
	edit:SetPoint("RIGHT", field, "RIGHT", opts.clearButton == false and -14 or -36, 0)
	edit:SetHeight(h - 6)
	if opts.maxLetters then edit:SetMaxLetters(opts.maxLetters) end

	field.placeholder = W.Text(field, "bodyL", "ink3")
	field.placeholder:SetPoint("LEFT", edit, "LEFT", 0, 0)
	field.placeholder:SetText(opts.placeholder or "")

	if opts.clearButton ~= false then
		field.clear = W.IconButton(field, { glyph = "glyph_close", size = 24, tooltip = L and L["FIELD_CLEAR"] or "Clear",
			onClick = function() field:Clear(); field:SetFocus() end })
		field.clear:SetPoint("RIGHT", field, "RIGHT", -8, 0)
		field.clear:Hide()
	end

	local function refresh()
		local empty = edit:GetText() == ""
		field.placeholder:SetShown(empty)
		if field.clear then field.clear:SetShown(not empty) end
	end
	function field:GetText() return self.edit:GetText() end
	function field:SetText(text, silent)
		self.silent = true   -- the client fires OnTextChanged itself (or not, when nothing changed): report once, below
		self.edit:SetText(text or "")
		self.silent = false
		refresh()
		if not silent and self.onChange then self.onChange(self.edit:GetText(), false) end
	end
	function field:Clear(silent) self:SetText("", silent) end
	function field:SetFocus() self.edit:SetFocus() end
	function field:ClearFocus() self.edit:ClearFocus() end
	function field:HasFocus() return self.edit.HasFocus and self.edit:HasFocus() end
	function field:SetPlaceholder(text) self.placeholder:SetText(text or "") end

	edit:SetScript("OnTextChanged", function(self, userInput)
		refresh()
		if not field.silent and field.onChange then field.onChange(self:GetText(), userInput and true or false) end
	end)
	edit:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if field.onEnter then field.onEnter(self:GetText()) end
	end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnEditFocusGained", function() field.ring:SetHex("#b8820f") end)
	edit:SetScript("OnEditFocusLost", function() field.ring:SetHex("#4a525a") end)

	if opts.text and opts.text ~= "" then field:SetText(opts.text, true) else refresh() end
	return field
end

---------------------------------------------------------------------------------------------------------------------
-- Copy field
---------------------------------------------------------------------------------------------------------------------
function W.CopyField(parent, opts)
	opts = opts or {}
	local field = fieldFrame(parent, opts.width, 8)
	field.bg:SetHex("#fffaf0")
	field.ring:SetHex("#2a64bd")
	field.value = opts.text or ""

	local edit = CreateFrame("EditBox", nil, field)
	field.edit = edit
	edit:SetAutoFocus(false)
	edit:SetFontObject(Skin.Font("mono"))
	edit:SetTextColor(Skin.Hex("#1b3d73"))
	edit:SetPoint("LEFT", field, "LEFT", 12, 0)
	edit:SetPoint("RIGHT", field, "RIGHT", -40, 0)
	edit:SetHeight(Skin.METRICS.fieldH - 6)
	edit:SetText(field.value)
	edit:SetCursorPosition(0)

	function field:SelectAll()
		self.edit:SetFocus()
		self.edit:HighlightText()
	end
	function field:SetValue(text)
		self.value = text or ""
		self.edit:SetText(self.value)
		self.edit:SetCursorPosition(0)
	end
	function field:GetValue() return self.value end

	-- read-only: whatever the player types is undone at once, and the text stays selected
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= field.value then
			self:SetText(field.value)
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

	field.button = W.IconButton(field, { glyph = "glyph_copy", size = 28, tooltip = L and L["COPY_SELECT_TIP"] or "Select all",
		onClick = function()
			field:SelectAll()
			if W.Snackbar then W.Snackbar.Show(opts.hint or (L and L["COPY_HINT"]) or "Selected: press Ctrl+C to copy.", { key = "copyfield" }) end
		end })
	field.button:SetPoint("RIGHT", field, "RIGHT", -6, 0)
	return field
end
