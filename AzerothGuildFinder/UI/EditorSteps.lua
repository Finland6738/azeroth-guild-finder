-- EditorSteps: the pages of the first two steps of the listing editor (SPEC-06 §2, mockup 03, M3.3). Lua 5.1.
--
--   1 Identity   the guild name (read from the game, locked), the subtitle (0/60), the banner gallery (the verified banners of
--                Assets.BANNERS, by index; "Default" clears the choice). The emblem arrives with M3.6.
--   2 About      the description (0/500 characters, 0/12 lines), the main language (menu) and the other languages (multiple
--                choice; the main one is always part of the mask).
--   3 Activity   the commitment (segmented button, required, explained), up to 3 activities as numbered chips (the order
--                picked is the order of importance), play days and a time window typed in the Guild Master's local time and
--                stored as UTC (EditorModel.Schedule / SchedulePatch, on top of BrowseModel.ToLocal, the visitors' conversion).
-- The pages only read and write fields through the editor (Editor:Get / Set / Patch) and register with Editor.RegisterStep;
-- every limit and every counter comes from EditorModel (Clamp, TextStats, SetMain, SetSecondary), which the tests run without
-- frames. Text is cut as it is typed, so what the Guild Master sees is what is published.
local ADDON_NAME, ns = ...
ns = ns or {}
local Steps = {}
ns.EditorSteps, ns.modules = Steps, ns.modules or {}
ns.modules.EditorSteps = Steps

local L, Skin, W, Model, Editor, E = ns.L, ns.Skin, ns.Widgets, ns.EditorModel, ns.Editor, ns.Enums
local ipairs = ipairs

local PAGE_W = 430
local INNER_W = PAGE_W - 32          -- inside a card
local GAP = 12

local function counterColor(stats, min)
	if stats.over then return "bad" end
	if min and stats.chars < min then return "warn" end
	return "ink2"
end

-- A label above a control, in a card's body.
local function label(parent, text, y)
	local t = W.Text(parent, "titleS", "ink2")
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	t:SetText(text)
	return t
end

local function caption(parent, text, y, height)
	local t = W.Text(parent, "caption", "ink2")
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	t:SetWidth(INNER_W)
	t:SetHeight(height or 28)
	t:SetWordWrap(true)
	t:SetJustifyV("TOP")
	t:SetText(text)
	return t
end

local function guildName()
	local _, key = ns.Role.Compute()
	local _, _, name = ns.Listing.ParseKey(key or "")
	return name
end

---------------------------------------------------------------------------------------------------------------------
-- Identity
---------------------------------------------------------------------------------------------------------------------
local Identity = {}

local function buildTile(parent, entry, w, h, onPick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	b:RegisterForClicks("LeftButtonUp")
	b.index = entry and entry.index or nil
	b.bg = W.NineSlice(b, "card", { corner = 8, layer = "BACKGROUND" })
	b.bg:SetHex("#e8d3a8")
	if entry then
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
		b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
		b.tex:SetTexture(entry.file)
		b.tex:SetTexCoord(0, 1, 0.2, 0.8)
	else
		b.text = W.Text(b, "caption", "ink2", "CENTER")
		b.text:SetAllPoints(b)
		b.text:SetText(L["ED_BANNER_DEFAULT"])
	end
	b.edge = W.NineSlice(b, "card_edge", { corner = 8, layer = "OVERLAY" })
	b.edge:SetHex("#a06e3c", 0.5)
	b:SetScript("OnClick", function(self) if onPick then onPick(self.index or false) end end)
	W.SetTooltip(b, function() return entry and L["ED_BANNER_N"]:format(entry.index) or L["ED_BANNER_DEFAULT_TIP"] end)
	return b
end

function Identity.Build(page, editor)
	local name = W.Card(page, { kind = "plain", title = L["ED_GUILD_NAME_LABEL"], height = 96 })
	name:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	name:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
	page.lock = CreateFrame("Frame", nil, name.body)
	page.lock:SetSize(INNER_W, Skin.METRICS.fieldH)
	page.lock:SetPoint("TOPLEFT", name.body, "TOPLEFT", 0, 0)
	page.lock:EnableMouse(true)
	page.lock.bg = W.NineSlice(page.lock, "field", { corner = Skin.METRICS.fieldH / 2, layer = "BACKGROUND" })
	page.lock.bg:SetHex("#e6d4ae")
	page.lock.icon = W.Texture(page.lock, "glyph_shield", "ARTWORK", "ink3")
	page.lock.icon:SetSize(18, 18)
	page.lock.icon:SetPoint("LEFT", page.lock, "LEFT", 14, 0)
	page.name = W.Text(page.lock, "bodyL", "ink2")
	page.name:SetPoint("LEFT", page.lock, "LEFT", 38, 0)
	page.name:SetPoint("RIGHT", page.lock, "RIGHT", -14, 0)
	page.name:SetWordWrap(false)
	W.SetTooltip(page.lock, L["ED_GUILD_NAME_TIP"])

	local sub = W.Card(page, { kind = "plain", title = L["ED_SUB_LABEL"], height = 134 })
	sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -GAP)
	sub:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -GAP)
	page.sub = W.Field(sub.body, { width = INNER_W, placeholder = L["ED_SUB_PLACEHOLDER"], maxLetters = Model.SubMax(),
		onChange = function(text, user)
			if not user then return end
			Identity.OnSub(page, editor, text)
		end })
	page.sub:SetPoint("TOPLEFT", sub.body, "TOPLEFT", 0, 0)
	page.subCount = W.Text(sub.body, "caption", "ink2", "RIGHT")
	page.subCount:SetPoint("TOPRIGHT", sub.body, "TOPRIGHT", 0, -46)
	caption(sub.body, L["ED_SUB_HINT"], 46, 32):SetWidth(INNER_W - 70)

	local banners = Model.Banners()
	local rows = math.max(1, math.ceil((#banners + 1) / 3))
	local card = W.Card(page, { kind = "plain", title = L["ED_BANNER_LABEL"], height = 42 + 8 + rows * 66 + (#banners == 0 and 36 or 30) })
	card:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -GAP)
	card:SetPoint("TOPRIGHT", sub, "BOTTOMRIGHT", 0, -GAP)
	local tw = math.floor((INNER_W - 2 * 8) / 3)
	page.tiles = {}
	local list = { false }
	for _, entry in ipairs(banners) do list[#list + 1] = entry end
	for n, entry in ipairs(list) do
		local tile = buildTile(card.body, entry or nil, tw, 58, function(index)
			editor:Set("bg", index)
			Identity.Fill(page, editor)
		end)
		tile:SetPoint("TOPLEFT", card.body, "TOPLEFT", ((n - 1) % 3) * (tw + 8), -math.floor((n - 1) / 3) * 66)
		page.tiles[#page.tiles + 1] = tile
	end
	page.bannerNote = caption(card.body, #banners == 0 and L["ED_BANNER_NONE"] or L["ED_BANNER_HINT"], rows * 66 + 2, 32)
	page.emblemNote = W.Text(page, "caption", "ink3")
	page.emblemNote:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 4, -GAP)
	page.emblemNote:SetWidth(PAGE_W - 8)
	page.emblemNote:SetWordWrap(true)
	page.emblemNote:SetText(L["ED_EMBLEM_LATER"])
end

-- A typed subtitle: cut to 60 characters on one line, saved at once.
function Identity.OnSub(page, editor, text)
	local clamped, changed = Model.Clamp(text, Model.SubMax())
	if changed then page.sub:SetText(clamped, true) end
	editor:Set("sub", clamped ~= "" and clamped or false)
	Identity.Counter(page, editor)
end

function Identity.Counter(page, editor)
	local stats = Model.TextStats(editor:Get("sub"), Model.SubMax())
	page.subCount:SetText(L["ED_COUNT"]:format(stats.chars, stats.max))
	W.TextColor(page.subCount, counterColor(stats))
end

function Identity.Fill(page, editor)
	page.name:SetText(guildName() or L["ED_GUILD_NAME_UNKNOWN"])
	local sub = editor:Get("sub") or ""
	if page.sub:GetText() ~= sub then page.sub:SetText(sub, true) end
	Identity.Counter(page, editor)
	local chosen = editor:Get("bg")
	for _, tile in ipairs(page.tiles) do
		local on = (tile.index or false) == (chosen or false)
		tile.edge:SetHex(on and "#b8820f" or "#a06e3c", on and 1 or 0.5)
		tile.selected = on
	end
end

Identity.OnShow = Identity.Fill
Identity.Refresh = Identity.Fill

---------------------------------------------------------------------------------------------------------------------
-- About
---------------------------------------------------------------------------------------------------------------------
local About = {}
local DESC_H = 190

function About.Build(page, editor)
	local desc = W.Card(page, { kind = "plain", title = L["ED_DESC_LABEL"], height = 42 + DESC_H + 64 })
	desc:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	desc:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
	local box = CreateFrame("Frame", nil, desc.body)
	box:SetSize(INNER_W, DESC_H)
	box:SetPoint("TOPLEFT", desc.body, "TOPLEFT", 0, 0)
	box:EnableMouse(true)
	box.bg = W.NineSlice(box, "field", { corner = 12, layer = "BACKGROUND" })
	box.bg:SetHex("#fff4dd")
	box.ring = W.NineSlice(box, "field_ring", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	box.ring:SetHex("#4a525a")
	local edit = CreateFrame("EditBox", nil, box)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(Skin.Font("bodyL"))
	edit:SetTextColor(Skin.Color("ink"))
	edit:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
	edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 10)
	edit:SetTextInsets(0, 0, 0, 0)
	page.desc = edit
	box:SetScript("OnMouseDown", function() edit:SetFocus() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnEditFocusGained", function() box.ring:SetHex("#b8820f") end)
	edit:SetScript("OnEditFocusLost", function() box.ring:SetHex("#4a525a") end)
	edit:SetScript("OnTextChanged", function(self, user)
		if not user or page.filling then return end
		About.OnDesc(page, editor, self:GetText())
	end)
	page.descPlaceholder = W.Text(box, "bodyL", "ink3")
	page.descPlaceholder:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
	page.descPlaceholder:SetText(L["ED_DESC_PLACEHOLDER"])

	page.descCount = W.Text(desc.body, "caption", "ink2", "RIGHT")
	page.descCount:SetPoint("TOPRIGHT", desc.body, "TOPRIGHT", 0, -(DESC_H + 6))
	page.descLines = W.Text(desc.body, "caption", "ink2", "LEFT")
	page.descLines:SetPoint("TOPLEFT", desc.body, "TOPLEFT", 0, -(DESC_H + 6))
	page.descHint = caption(desc.body, "", DESC_H + 24, 30)

	local langs = W.Card(page, { kind = "plain", title = L["ED_LANG_LABEL"], height = 190 })
	langs:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -GAP)
	langs:SetPoint("TOPRIGHT", desc, "BOTTOMRIGHT", 0, -GAP)
	local items = {}
	for i = 1, E.LANGUAGE_COUNT do items[i] = { key = i, text = E.LanguageLabel(i) } end
	label(langs.body, L["ED_LANG_MAIN"], 0)
	page.main = W.Select(langs.body, { width = INNER_W, items = items, emptyText = L["ED_LANG_MAIN_PICK"], maxRows = 9,
		onChange = function(keys) About.OnMain(page, editor, keys[1]) end })
	page.main:SetPoint("TOPLEFT", langs.body, "TOPLEFT", 0, -22)
	label(langs.body, L["ED_LANG_OTHER"], 66)
	page.other = W.Select(langs.body, { width = INNER_W, multi = true, items = items, emptyText = L["ED_LANG_OTHER_NONE"], maxRows = 8,
		onChange = function(keys) About.OnOther(page, editor, keys) end })
	page.other:SetPoint("TOPLEFT", langs.body, "TOPLEFT", 0, -88)
	caption(langs.body, L["ED_LANG_HINT"], 132, 32)
end

-- A typed description: cut to 500 characters and 12 lines, saved at once.
function About.OnDesc(page, editor, text)
	local clamped, changed = Model.Clamp(text, Model.DescMax(), Model.DescLines())
	if changed then
		page.filling = true
		page.desc:SetText(clamped)
		page.filling = false
	end
	editor:Set("desc", clamped ~= "" and clamped or false)
	About.Counters(page, editor)
end

function About.Counters(page, editor)
	local text = editor:Get("desc") or ""
	local stats = Model.TextStats(text, Model.DescMax(), Model.DescLines())
	page.descPlaceholder:SetShown(text == "")
	page.descCount:SetText(L["ED_COUNT"]:format(stats.chars, stats.max))
	W.TextColor(page.descCount, counterColor(stats, Model.DESC_MIN))
	page.descLines:SetText(L["ED_LINES"]:format(stats.lines, stats.maxLines))
	W.TextColor(page.descLines, stats.lines >= stats.maxLines and "warn" or "ink2")
	page.descHint:SetText(stats.chars < Model.DESC_MIN and L["ED_DESC_MIN"]:format(Model.DESC_MIN) or "")
end

-- The main language changed: the secondary ones stay, minus the one that became main.
function About.OnMain(page, editor, index)
	local patch = index and Model.SetMain(editor:Fields(), index)
	if patch then editor:Patch(patch) end
	About.Languages(page, editor)
end

function About.OnOther(page, editor, keys)
	local patch = Model.SetSecondary(editor:Fields(), keys)
	if patch then editor:Patch(patch) end
	About.Languages(page, editor)
end

-- The menus from the fields: the second one lists every language but the main one, and waits for a main language.
function About.Languages(page, editor)
	local fields = editor:Fields()
	local main = Model.MainLanguage(fields)
	page.main:SetSelected(main and { main } or {}, true)
	local items = {}
	for i = 1, E.LANGUAGE_COUNT do
		if i ~= main then items[#items + 1] = { key = i, text = E.LanguageLabel(i) } end
	end
	page.other:SetItems(items)
	page.other:SetSelected(Model.Secondary(fields), true)
	page.other:SetEnabled(main ~= nil)
end

function About.Fill(page, editor)
	local text = editor:Get("desc") or ""
	if page.desc:GetText() ~= text then
		page.filling = true
		page.desc:SetText(text)
		page.filling = false
	end
	About.Counters(page, editor)
	About.Languages(page, editor)
end

About.OnShow = About.Fill
About.Refresh = About.Fill

---------------------------------------------------------------------------------------------------------------------
-- Activity
---------------------------------------------------------------------------------------------------------------------
local Activity = {}

-- Minutes of the Guild Master's time zone from UTC now. Tests replace it with Steps.offset.
function Steps.LocalOffset()
	if Steps.offset then return Steps.offset() end
	local at = ns.Compat and ns.Compat.ServerTime and ns.Compat.ServerTime() or nil
	return ns.BrowseModel.LocalOffset(at)
end

function Activity.Build(page, editor)
	local pace = W.Card(page, { kind = "plain", title = L["ED_PACE_LABEL"] .. " " .. L["ED_PACE_REQUIRED"], height = 132 })
	pace:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	pace:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
	local items = {}
	for v = 1, E.PACE_COUNT do items[v] = { key = v, text = E.PaceLabel(v), tooltip = E.PaceTip(v) } end
	page.pace = W.Segmented(pace.body, items, { width = INNER_W, onChange = function(key) Activity.OnPace(page, editor, key) end })
	page.pace:SetPoint("TOPLEFT", pace.body, "TOPLEFT", 0, 0)
	page.paceNote = caption(pace.body, "", 46, 40)

	local acts = W.Card(page, { kind = "plain", title = L["ED_ACT_LABEL"] .. " " .. L["ED_ACT_RANGE"], height = 100 })
	acts:SetPoint("TOPLEFT", pace, "BOTTOMLEFT", 0, -GAP)
	acts:SetPoint("TOPRIGHT", pace, "BOTTOMRIGHT", 0, -GAP)
	page.actCount = W.Text(acts, "label", "ink2", "RIGHT")
	page.actCount:SetPoint("TOPRIGHT", acts, "TOPRIGHT", -16, -12)
	page.chips = {}
	local x, y, rowH = 0, 0, Skin.METRICS.chipH
	for _, act in ipairs(E.ACTIVITIES) do
		local id = act.id
		local chip = W.Chip(acts.body, { text = E.ActivityLabel(id), onToggle = function() Activity.OnTag(page, editor, id) end })
		chip.activity, chip.name = id, E.ActivityLabel(id)
		local w = chip:GetWidth()
		if x > 0 and x + w > INNER_W then x, y = 0, y + rowH + 6 end
		chip:SetPoint("TOPLEFT", acts.body, "TOPLEFT", x, -y)
		x = x + w + 6
		page.chips[id] = chip
	end
	local hintY = y + rowH + 8
	page.actHint = caption(acts.body, L["ED_ACT_HINT"], hintY, 32)
	acts:SetHeight(42 + hintY + 34 + 6)

	local when = W.Card(page, { kind = "plain", title = L["ED_WHEN_LABEL"] .. " " .. L["ED_WHEN_ZONE"], height = 148 })
	when:SetPoint("TOPLEFT", acts, "BOTTOMLEFT", 0, -GAP)
	when:SetPoint("TOPRIGHT", acts, "BOTTOMRIGHT", 0, -GAP)
	local letters, names = {}, {}
	for d = 1, 7 do letters[d], names[d] = L["DAY_LETTER_" .. d], L["DAY_LONG_" .. d] end
	page.days = W.DayToggles(when.body, { width = INNER_W, labels = letters, names = names,
		onChange = function(mask) Activity.OnWhen(page, editor, { days = mask }) end })
	page.days:SetPoint("TOPLEFT", when.body, "TOPLEFT", 0, 0)
	page.from = W.Select(when.body, { width = 104, items = Model.TimeChoices(), emptyText = L["ED_WHEN_PICK"], maxRows = 8,
		tooltip = L["ED_WHEN_FROM"], onChange = function(keys) Activity.OnWhen(page, editor, { from = keys[1] }) end })
	page.from:SetPoint("TOPLEFT", when.body, "TOPLEFT", 0, -42)
	local dash = W.Text(when.body, "bodyL", "ink2", "CENTER")
	dash:SetPoint("LEFT", page.from, "RIGHT", 0, 0)
	dash:SetWidth(24)
	dash:SetText("–")
	page.to = W.Select(when.body, { width = 104, items = Model.TimeChoices(), emptyText = L["ED_WHEN_PICK"], maxRows = 8,
		tooltip = L["ED_WHEN_TO"], onChange = function(keys) Activity.OnWhen(page, editor, { to = keys[1] }) end })
	page.to:SetPoint("LEFT", dash, "RIGHT", 0, 0)
	page.allDay = W.Switch(when.body, { label = L["ED_WHEN_ALL_DAY"], width = 130,
		onChange = function(checked) Activity.OnWhen(page, editor, { allDay = checked }) end })
	page.allDay:SetPoint("TOPRIGHT", when.body, "TOPRIGHT", 0, -44)
	page.whenHelp = caption(when.body, "", 84, 32)
end

function Activity.OnPace(page, editor, key)
	editor:Set("pace", key)
	Activity.Fill(page, editor)
end

-- A chip was clicked: pick or remove the activity. A fourth one is refused (the chips are greyed out, this is the safety net).
function Activity.OnTag(page, editor, id)
	if page.filling then return end
	local tags, result = Model.ToggleTag(Model.Tags(editor:Fields()), id)
	if result == "full" then
		W.Snackbar.Show(L["ED_ACT_FULL"], { key = "editor-tags" })
	elseif result ~= "invalid" then
		editor:Set("tags", #tags > 0 and tags or false)
	end
	Activity.Fill(page, editor)
end

-- The local schedule shown: what is stored (UTC converted to local time), or the half-picked window not stored yet.
local function currentSchedule(page, editor)
	local s = Model.Schedule(editor:Fields(), Steps.LocalOffset())
	if not s.hasTime then s.from, s.to = page.pendingFrom, page.pendingTo end
	return s
end

-- `change` = { days } | { from } | { to } | { allDay }: applied to the local schedule, then stored as UTC.
function Activity.OnWhen(page, editor, change)
	if page.filling then return end
	local s = currentSchedule(page, editor)
	if change.days ~= nil then s.days = change.days end
	if change.from ~= nil then s.from, s.allDay = change.from, false end
	if change.to ~= nil then s.to, s.allDay = change.to, false end
	if change.allDay ~= nil then s.allDay, s.from, s.to = change.allDay, nil, nil end
	if s.from == s.to then s.to = nil end   -- the same minute twice would mean "all day": the All day switch says that
	if s.allDay or (s.from and s.to) then
		page.pendingFrom, page.pendingTo = nil, nil
	else
		page.pendingFrom, page.pendingTo = s.from, s.to
	end
	editor:Patch(Model.SchedulePatch(s, Steps.LocalOffset()))
	Activity.Fill(page, editor)
end

function Activity.Fill(page, editor)
	local fields = editor:Fields()
	local clean = Model.Clean(fields) or {}
	page.filling = true
	-- commitment
	page.pace:SetSelected(clean.pace, true)
	page.paceNote:SetText(clean.pace and E.PaceTip(clean.pace) or L["ED_PACE_PICK"])
	-- activities
	local tags = Model.Tags(fields)
	local full = #tags >= E.MAX_TAGS
	for id, chip in pairs(page.chips) do
		local n = Model.TagNumber(tags, id)
		chip:SetSelected(n ~= nil, true)
		chip:SetLabel(n and L["ED_ACT_NUMBERED"]:format(n, chip.name) or chip.name)
		chip:SetEnabled(n ~= nil or not full, L["ED_ACT_FULL"])
	end
	page.actCount:SetText(L["ED_ACT_COUNT"]:format(#tags, E.MAX_TAGS))
	W.TextColor(page.actCount, full and "warn" or "ink2")
	page.actHint:SetText(#tags == 0 and L["ED_ACT_NONE"] or L["ED_ACT_HINT"])
	-- days and time
	local s = currentSchedule(page, editor)
	page.days:SetMask(s.days, true)
	page.allDay:SetChecked(s.allDay, true)
	page.from:SetItems(Model.TimeChoices(s.to))
	page.to:SetItems(Model.TimeChoices(s.from))
	page.from:SetSelected(s.from and { s.from } or {}, true)
	page.to:SetSelected(s.to and { s.to } or {}, true)
	page.from:SetEnabled(not s.allDay)
	page.to:SetEnabled(not s.allDay)
	if s.allDay then
		page.whenHelp:SetText(L["ED_WHEN_HELP"])
		W.TextColor(page.whenHelp, "ink2")
	elseif s.from and s.to then
		page.whenHelp:SetText(L["ED_WHEN_HELP_UTC"]:format(
			ns.BrowseModel.FormatMinutes(clean.t0) .. "–" .. ns.BrowseModel.FormatMinutes(clean.t1)))
		W.TextColor(page.whenHelp, "ink2")
	elseif s.from or s.to then
		page.whenHelp:SetText(L["ED_WHEN_ONE"])
		W.TextColor(page.whenHelp, "warn")
	else
		page.whenHelp:SetText(L["ED_WHEN_HELP"])
		W.TextColor(page.whenHelp, "ink2")
	end
	page.filling = false
end

function Activity.OnHide(page) page.pendingFrom, page.pendingTo = nil, nil end

Activity.OnShow = Activity.Fill
Activity.Refresh = Activity.Fill

Steps.Identity, Steps.About, Steps.Activity = Identity, About, Activity
Editor.RegisterStep("identity", Identity)
Editor.RegisterStep("about", About)
Editor.RegisterStep("activity", Activity)

if ns.addon then ns.addon.EditorSteps = Steps end
