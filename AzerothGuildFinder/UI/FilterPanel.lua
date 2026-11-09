-- FilterPanel: the filters on the left page of Find a Guild (SPEC-05 §2, mockup 01-browse). Lua 5.1.
--
-- Only frames live here: every rule (what a filter keeps, how many are active, the saved state) is in UI/FilterModel.lua and
-- is tested without a client. The panel creates the controls once, copies the state into them (Panel:Sync) and writes
-- every change back through the controller, which saves it per character (`char.ui.filters`) and tells the list.
--
--   FilterPanel.Build(host)        called by UI/Browse.lua when the page is built; fills host.left
--   FilterPanel.Controller()       the controller of the filters (created at the first use)
--   FilterPanel.panel              { frame, plate, switches, roles, langs, paces, acts, days, from, to, minActive }
--   FilterPanel.Sync()             copies the state into the controls (a different character, a reset)
-- The window of the list is told through Browse:SetFilter(fn, activeCount, resetFn, prepareFn) after every change.
local ADDON_NAME, ns = ...
ns = ns or {}
local Panel = {}
ns.FilterPanel, ns.modules = Panel, ns.modules or {}
ns.modules.FilterPanel = Panel

local L, W, Skin = ns.L, ns.Widgets, ns.Skin
local FM = ns.FilterModel
local ipairs, type = ipairs, type

local WIDTH = 260
Panel.WIDTH = WIDTH
Panel.panel = nil
Panel.controller = nil

local function Enums() return ns.Enums end

---------------------------------------------------------------------------------------------------------------------
-- Controller (state, saving, notification)
---------------------------------------------------------------------------------------------------------------------
function Panel.Controller()
	if Panel.controller then return Panel.controller end
	local Config, BM = ns.Config, ns.BrowseModel
	Panel.controller = FM.NewController({
		load = function() return Config and Config.Get and Config:Get("char.ui.filters") or nil end,
		save = function(state) if Config and Config.Set then Config:Set("char.ui.filters", state) end end,
		player = function() return BM.Player() end,
		offset = function() return BM.LocalOffset(ns.Compat.ServerTime()) end,
		onChange = function() Panel.Changed() end,
	})
	return Panel.controller
end

-- Tells the list: the filter function (nil when nothing is active), the count, the reset and the per-rebuild preparation.
function Panel.Publish()
	local c, Browse = Panel.Controller(), ns.Browse
	if not Browse then return end
	local count = c:Count()
	local fn
	if count > 0 then
		fn = function(sum, info)
			local pred = c:Predicate()
			return pred == nil or pred(sum, info) == true
		end
	end
	Browse:SetFilter(fn, count, function() c:Reset() end, function() c:Refresh() end)
end

function Panel.Changed()
	Panel.Sync()
	Panel.Publish()
end

---------------------------------------------------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------------------------------------------------
local function label(parent, text, y, caption)
	local fs = W.Text(parent, "label", "ink")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -y)
	fs:SetText(text)
	if caption then
		local c = W.Text(parent, "caption", "ink2")
		c:SetPoint("LEFT", fs, "RIGHT", 6, 0)
		c:SetText(caption)
		fs.caption = c
	end
	return fs
end

local function languageItems()
	local items = {}
	for i, lang in ipairs(Enums().LANGUAGES) do items[i] = { key = i, text = L["LANG_" .. lang.key] } end
	return items
end

local function activityItems()
	local items = {}
	for i, act in ipairs(Enums().ACTIVITIES) do items[i] = { key = act.id, text = L["ACTIVITY_" .. act.id] } end
	return items
end

local function timeItems()
	local items = { { key = "any", text = L["FILTER_ANY"] } }
	for _, m in ipairs(FM.TimeChoices()) do items[#items + 1] = { key = m, text = FM.TimeLabel(m) } end
	return items
end

-- "Italian, English" for one or two choices, "3 selected" for more; nil (the empty text) for none.
local function summarize(items)
	return function(keys)
		if #keys == 0 then return nil end
		if #keys > 2 then return L["FILTER_N_SELECTED"]:format(#keys) end
		local names = {}
		for _, key in ipairs(keys) do
			for _, item in ipairs(items) do if item.key == key then names[#names + 1] = item.text end end
		end
		return table.concat(names, ", ")
	end
end

local function maskKeys(mask, count)
	return FM.ListOf(mask, count)
end

local function keysToMask(keys)
	return FM.MaskOf(keys, 1)
end

-- Creates the controls on `parent` (a frame of WIDTH x 644) and returns the panel table.
function Panel.Create(parent)
	local c = Panel.Controller()
	local E = Enums()
	local p = { frame = parent, switches = {} }
	local y = 0

	-- the plate: "Filters · 4 active" and the reset button
	p.plate = W.Plate(parent, { text = L["BROWSE_FILTERS"], width = WIDTH })
	p.plate:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	p.resetButton = W.IconButton(parent, { glyph = "glyph_close", size = 26, tooltip = L["BROWSE_FILTERS_RESET_TIP"],
		onClick = function() c:Reset() end })
	p.resetButton:SetPoint("RIGHT", p.plate, "RIGHT", -4, 0)
	p.resetButton.glyph:SetVertexColor(Skin.Hex("#fff4df"))
	y = 44

	-- switches
	local switchSpecs = {
		{ id = "recruiting", text = L["FILTER_RECRUITING"] },
		{ id = "myClass", text = L["FILTER_MY_CLASS"] },
		{ id = "reqs", text = L["FILTER_REQS"] },
		{ id = "newb", text = L["FILTER_NEWB"] },
	}
	for _, spec in ipairs(switchSpecs) do
		local sw = W.Switch(parent, { label = spec.text, width = WIDTH, checked = c:Get(spec.id),
			onChange = function(checked) c:Set(spec.id, checked) end })
		sw:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
		p.switches[spec.id] = sw
		y = y + 30
	end
	y = y + 8

	-- role
	label(parent, L["FILTER_ROLE"], y)
	y = y + 18
	local roleItems = {}
	for i, r in ipairs(E.ROLES) do roleItems[i] = { key = r.bit, text = L["ROLE_" .. r.key], icon = W.ROLE_MEDIA[r.key] } end
	p.roles = W.ChipGroup(parent, roleItems, { width = WIDTH,
		onChange = function(keys) c:Set("roles", Panel.RoleMask(keys)) end })
	p.roles:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	y = y + p.roles:GetHeight() + 8

	-- language
	label(parent, L["FILTER_LANG"], y)
	y = y + 18
	local langs = languageItems()
	p.langs = W.Select(parent, { width = WIDTH, height = 36, multi = true, items = langs, maxRows = #langs,
		emptyText = L["FILTER_LANG_ANY"], summary = summarize(langs),
		onChange = function(keys) c:Set("langs", keysToMask(keys)) end })
	p.langs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	y = y + 36 + 8

	-- commitment
	label(parent, L["FILTER_PACE"], y)
	y = y + 18
	local paceItems = {}
	for i = 1, E.PACE_COUNT do paceItems[i] = { key = i, text = L["PACE_" .. i], tooltip = { title = L["PACE_" .. i], lines = { L["PACE_" .. i .. "_TIP"] } } } end
	p.paces = W.ChipGroup(parent, paceItems, { width = WIDTH,
		onChange = function(keys) c:Set("paces", keysToMask(keys)) end })
	p.paces:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	y = y + p.paces:GetHeight() + 8

	-- activity
	label(parent, L["FILTER_ACTIVITY"], y)
	y = y + 18
	local acts = activityItems()
	p.acts = W.Select(parent, { width = WIDTH, height = 36, multi = true, items = acts, maxRows = 9,
		emptyText = L["FILTER_ACTIVITY_ANY"], summary = summarize(acts),
		onChange = function(keys) c:Set("acts", keysToMask(keys)) end })
	p.acts:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	y = y + 36 + 8

	-- play days and time, in the player's time
	label(parent, L["FILTER_DAYS_TIME"], y, L["FILTER_YOUR_TIME"])
	y = y + 18
	local letters, names = {}, {}
	for i = 1, 7 do letters[i], names[i] = L["DAY_LETTER_" .. i], L["DAY_LONG_" .. i] end
	p.days = W.DayToggles(parent, { width = WIDTH, labels = letters, names = names,
		onChange = function(mask) c:Set("days", mask) end })
	p.days:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	y = y + 32 + 6

	local function timeSelect(x, tip, which)
		local items = timeItems()
		local sel = W.Select(parent, { width = 112, height = 34, corner = 8, items = items, maxRows = 8, tooltip = tip,
			openAt = function()
				local key = c:Get(which)
				local at = 1
				for i, item in ipairs(items) do if item.key == (key == nil and 20 * 60 or key) then at = i end end
				return at - 2
			end,
			onChange = function(keys)
				local v = keys[1]
				if v == "any" then v = nil end
				local from, to = c:Get("timeFrom"), c:Get("timeTo")
				if which == "timeFrom" then from = v else to = v end
				c:SetTime(from, to)
			end })
		sel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
		return sel
	end
	p.from = timeSelect(0, L["FILTER_TIME_FROM_TIP"], "timeFrom")
	local dash = W.Text(parent, "bodyL", "ink2", "CENTER")
	dash:SetPoint("TOPLEFT", parent, "TOPLEFT", 112, -y - 8)
	dash:SetWidth(36)
	dash:SetText("-")
	p.to = timeSelect(148, L["FILTER_TIME_TO_TIP"], "timeTo")
	y = y + 34 + 8

	-- minimum active members
	local row = W.Text(parent, "body", "ink")
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -(y + 7))
	row:SetText(L["FILTER_MIN_ACTIVE"])
	local steps = {}
	for i, n in ipairs(FM.MIN_ACTIVE_STEPS) do steps[i] = { key = n, text = n == 0 and L["FILTER_ANY"] or tostring(n) } end
	p.minActive = W.Select(parent, { width = 84, height = 34, corner = 8, items = steps, maxRows = #steps,
		onChange = function(keys) c:Set("minActive", keys[1] or 0) end })
	p.minActive:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
	y = y + 34

	p.height = y
	return p
end

-- The role mask the chips stand for (the keys are the role bits).
function Panel.RoleMask(keys)
	local mask = 0
	for _, bit in ipairs(keys) do mask = mask + bit end
	return mask
end

---------------------------------------------------------------------------------------------------------------------
-- State -> controls
---------------------------------------------------------------------------------------------------------------------
function Panel.Sync()
	local p, c = Panel.panel, Panel.controller
	if not p or not c then return end
	local E = Enums()
	local state = c:State()
	for id, sw in pairs(p.switches) do sw:SetChecked(state[id], true) end

	-- the class of the player: its name in the label, and the roles it cannot play are switched off
	local player = c:Player() or {}
	local className = player.classID and E.ClassLabel(player.classID) or nil
	p.switches.myClass.label:SetText(className and L["FILTER_MY_CLASS_NAMED"]:format(className) or L["FILTER_MY_CLASS"])
	local valid = player.classID and E.ValidRoles(player.classID) or E.ROLE_MASK
	for _, r in ipairs(E.ROLES) do
		local ok = E.HasRole(valid, r.bit)
		p.roles:SetEnabled(r.bit, ok, className and L["FILTER_ROLE_CANT"]:format(className) or L["FILTER_ROLE_CANT_ANY"])
	end
	p.roles:SetSelected(Panel.RoleKeys(state.roles), true)

	p.langs:SetSelected(maskKeys(state.langs, E.LANGUAGE_COUNT), true)
	p.paces:SetSelected(maskKeys(state.paces, E.PACE_COUNT), true)
	p.acts:SetSelected(maskKeys(state.acts, E.ACTIVITY_COUNT), true)
	p.days:SetMask(state.days, true)
	p.from:SetSelected(state.timeFrom == nil and "any" or state.timeFrom, true)
	p.to:SetSelected(state.timeTo == nil and "any" or state.timeTo, true)
	p.minActive:SetSelected(state.minActive, true)
	p.plate:SetText(FM.PlateText(c:Count(), L))
end

-- The role bits set in a mask, in role order (the keys of the chips).
function Panel.RoleKeys(mask)
	local keys = {}
	for _, r in ipairs(Enums().ROLES) do
		if Enums().HasRole(mask, r.bit) then keys[#keys + 1] = r.bit end
	end
	return keys
end

---------------------------------------------------------------------------------------------------------------------
-- Entry from the page
---------------------------------------------------------------------------------------------------------------------
function Panel.Build(host)
	Panel.Controller()
	local p = Panel.Create(host.left)
	Panel.panel = p
	host.plate = p.plate
	Panel.Sync()
	Panel.Publish()
	return p
end

if ns.addon then ns.addon.FilterPanel = Panel end
