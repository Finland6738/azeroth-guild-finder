-- Settings view (M5.1, SPEC-04 §4): draws the options of UI/SettingsModel.lua as cards of switches and a size control.
-- The same builder serves the Settings page of the window (UI/Main.lua) and the panel in the game's Settings window
-- (registered at login when the client has Settings.RegisterCanvasLayoutCategory), so the two always show the same options.
--   SettingsPage.Build(parent, { width = number | nil, rowWidth = 420 }) -> view
--     view.controls[key]   the Switch or Segmented of each option      view.resetButton   "Reset window position"
--     view.cards[group]    the card of each group                      view:Refresh()     re-reads every value, hides what is not for this role
--   SettingsPage.RegisterPanel()   adds the panel to the game's Settings window (once); false when the client has none
local ADDON_NAME, ns = ...
ns = ns or {}
local Page = {}
ns.SettingsPage, ns.modules = Page, ns.modules or {}
ns.modules.SettingsPage = Page

local L, Nav, W = ns.L, ns.Nav, ns.Widgets
local ipairs = ipairs

Page.PANEL_FRAME = "AzerothGuildFinderSettingsPanel"
Page.SCALES = { 0.6, 0.8, 1.0, 1.2, 1.4 }
Page.views = {}

local function Model() return ns.SettingsModel end

local function caption(parent, text, y, x)
	local t = W.Text(parent, "caption", "ink3")
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, -y)
	t:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	t:SetWordWrap(true)
	t:SetText(text)
	return t
end

local function buildScale(view, body, option, y)
	local label = W.Text(body, "label", "ink")
	label:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
	label:SetText(L[option.label])
	local items = {}
	for _, s in ipairs(Page.SCALES) do items[#items + 1] = { key = s, text = Nav.ScaleLabel(s) } end
	local seg = W.Segmented(body, items, { selected = Model().Get(option.key),
		onChange = function(key) Model().Set(option.key, key) end })
	seg:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(y + 26))
	caption(body, L[option.help], y + 70)
	view.controls[option.key] = seg
	return y + 100
end

local function buildToggle(view, body, option, y, rowWidth)
	local sw = W.Switch(body, { label = L[option.label], width = rowWidth, checked = Model().Get(option.key),
		onChange = function(value, s)
			if not Model().Set(option.key, value) then s:SetChecked(not value, true) end
		end })
	sw:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
	W.SetTooltip(sw, { title = L[option.label], lines = { L[option.help] } })
	view.controls[option.key] = sw
	if option.showHelp then
		caption(body, L[option.help], y + 36)
		return y + 76
	end
	return y + 36
end

function Page.Build(parent, opts)
	opts = opts or {}
	local rowWidth = opts.rowWidth or 420
	local view = { controls = {}, cards = {}, order = {} }
	local previous
	for _, group in ipairs(Model().GROUPS) do
		local card = W.Card(parent, { kind = "plain", title = L[group.title], glyph = group.glyph, width = opts.width or 280, height = 100 })
		if previous then
			card:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -16)
			if not opts.width then card:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -16) end
		else
			card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
			if not opts.width then card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0) end
		end
		local y = 0
		if group.note then
			caption(card.body, L[group.note], 0)
			y = 40
		end
		for _, option in ipairs(Model().OptionsOf(group.key)) do
			if option.kind == "scale" then
				y = buildScale(view, card.body, option, y)
			else
				y = buildToggle(view, card.body, option, y, rowWidth)
			end
		end
		if group.key == "window" then
			local reset = W.Button(card.body, { text = L["SETTINGS_RESET_POS"], kind = "tonal", size = "sm",
				tooltip = L["SETTINGS_RESET_POS_TIP"],
				onClick = function()
					Model().ResetPositions()
					W.Snackbar.Show(L["RESET_DONE"], { key = "reset" })
				end })
			reset:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -(y + 6))
			view.resetButton = reset
			y = y + 40
		end
		card:SetHeight(42 + y + 8)
		view.cards[group.key] = card
		view.order[#view.order + 1] = group.key
		previous = card
	end

	function view:Refresh(role)
		for _, option in ipairs(Model().OPTIONS) do
			local control, value = self.controls[option.key], Model().Get(option.key)
			if option.kind == "scale" then control:SetSelected(Nav.ClampScale(value), true) else control:SetChecked(value, true) end
		end
		for _, group in ipairs(Model().GROUPS) do
			self.cards[group.key]:SetShown(Model().GroupVisible(group.key, role))
		end
	end
	view:Refresh()
	Page.views[#Page.views + 1] = view
	return view
end

---------------------------------------------------------------------------------------------------------------------
-- The panel in the game's Settings window
---------------------------------------------------------------------------------------------------------------------
local function makePanelFrame()
	local frame = CreateFrame("Frame", Page.PANEL_FRAME)
	frame.name = Model().PANEL_NAME
	local built
	local function ensure()
		if built then return end
		built = true
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
		holder:SetSize(540, 640)
		frame.view = Page.Build(holder, { width = 540, rowWidth = 480 })
	end
	frame:SetScript("OnShow", function() ensure() frame.view:Refresh() end)
	-- the "Defaults" button of the game's Settings window; the options apply as they are changed, so there is nothing to commit
	frame.OnDefault = function() Model().ResetAll() if frame.view then frame.view:Refresh() end end
	frame.OnRefresh = function() if frame.view then frame.view:Refresh() end end
	frame.OnCommit = function() end
	return frame
end

function Page.RegisterPanel()
	local ok, why = Model().RegisterPanel(makePanelFrame)
	return ok, why
end

-- Open views redraw when an option changes anywhere (the Applications tab, the icon's menu, a slash command, the other view).
local function redraw()
	for _, view in ipairs(Page.views) do
		local card = view.cards.window
		if card and card:IsVisible() then view:Refresh() end
	end
end
if ns.Bus then
	ns.Bus:On("SETTINGS_CHANGED", redraw)
	ns.Bus:On("NOTIFY_OPTIONS_CHANGED", redraw)
	ns.Bus:On("ROLE_CHANGED", redraw)
end

if ns.addon then ns.addon.SettingsPage = Page end
