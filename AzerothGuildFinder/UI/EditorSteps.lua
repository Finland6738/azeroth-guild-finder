-- EditorSteps: the pages of the first two steps of the listing editor (SPEC-06 §2, mockup 03, M3.3). Lua 5.1.
--
--   1 Identity   the guild name (read from the game, locked), the subtitle (0/60), the emblem (M3.6: "Guild tabard" copies the
--                guild tabard, the default when there is one; "Custom emblem" opens the designer, UI/EmblemDesigner.lua; a tabard
--                that changed since it was copied, GUILDTABARD_UPDATE, is offered with "Update emblem"), the banner gallery (the
--                verified banners of Assets.BANNERS, by index; "Default" clears the choice).
--   2 About      the description (0/500 characters, 0/12 lines), the main language (menu) and the other languages (multiple
--                choice; the main one is always part of the mask).
--   3 Activity   the commitment (segmented button, required, explained), up to 3 activities as numbered chips (the order
--                picked is the order of importance), play days and a time window typed in the Guild Master's local time and
--                stored as UTC (EditorModel.Schedule / SchedulePatch, on top of BrowseModel.ToLocal, the visitors' conversion).
--   4 Recruitment  the status (Open to all / Selected classes / Closed), the "Looking for" grid (one row per class of the guild's
--                faction and the roles it can play, plus "Any class"; a click makes the `want` map of SPEC-03), New player
--                friendly and Accept applications.
--   5 Requirements the minimum level (a slider, 1 = none), an optional minimum item level, a note (0/120).
--   6 Contact    the Discord invite code (a pasted link becomes its code, a bad input is explained) and up to 3 characters
--                picked from the guild roster.
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

	local emblemCard = Identity.BuildEmblem(page, editor, sub)

	local banners = Model.Banners()
	local rows = math.max(1, math.ceil((#banners + 1) / 3))
	local card = W.Card(page, { kind = "plain", title = L["ED_BANNER_LABEL"], height = 42 + 8 + rows * 66 + (#banners == 0 and 36 or 30) })
	card:SetPoint("TOPLEFT", emblemCard, "BOTTOMLEFT", 0, -GAP)
	card:SetPoint("TOPRIGHT", emblemCard, "BOTTOMRIGHT", 0, -GAP)
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
end

-- The emblem card: the emblem as it will be published (96 px), Guild tabard / Custom emblem, what is going on, one action.
local EMB_SIZE, EMB_X = 96, 112

function Identity.BuildEmblem(page, editor, anchor)
	local card = W.Card(page, { kind = "plain", title = L["ED_EMBLEM_LABEL"], height = 42 + EMB_SIZE + 18 })
	card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -GAP)
	card:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -GAP)
	page.emblem = ns.Emblem.Create(card.body, EMB_SIZE)
	page.emblem:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
	page.embMode = W.Segmented(card.body, {
		{ key = 1, text = L["ED_EMB_TABARD"], tooltip = L["ED_EMB_TABARD_TIP"] },
		{ key = 2, text = L["ED_EMB_CUSTOM"], tooltip = L["ED_EMB_CUSTOM_TIP"] },
	}, { width = INNER_W - EMB_X, onChange = function(key) Identity.OnMode(page, editor, key) end })
	page.embMode:SetPoint("TOPLEFT", card.body, "TOPLEFT", EMB_X, 0)
	-- "Custom emblem" that is already chosen (a guild without a tabard) still opens the designer
	page.embMode.segments[2]:HookScript("OnClick", function()
		if not page.designer:IsShown() then Identity.OnMode(page, editor, 2) end
	end)
	page.embStatus = W.Text(card.body, "caption", "ink2")
	page.embStatus:SetPoint("TOPLEFT", card.body, "TOPLEFT", EMB_X, -42)
	page.embStatus:SetWidth(INNER_W - EMB_X)
	page.embStatus:SetHeight(32)
	page.embStatus:SetWordWrap(true)
	page.embStatus:SetJustifyV("TOP")
	page.embAction = W.Button(card.body, { text = L["ED_EMB_DESIGN"], kind = "tonal", size = "sm",
		onClick = function() Identity.OnAction(page, editor) end })
	page.embAction:SetPoint("TOPLEFT", card.body, "TOPLEFT", EMB_X, -78)
	page.designer = ns.EmblemDesigner.Build(page, {
		onChange = function(emb) Identity.OnDesign(page, editor, emb) end,
		onClose = function() Identity.Fill(page, editor) end,
		reset = function() return ns.Emblems.Reset(Identity.Published(), page.tabard) end,
		name = guildName,
	})
	Identity.page, Identity.editor = page, editor
	return card
end

-- The emblem of the published version (nil when nothing is published).
function Identity.Published()
	local copy = ns.OwnListing and ns.OwnListing:Get()
	return copy and not copy.del and copy.emb or nil
end

function Identity.ReadTabard(page)
	page.tabard, page.tabardState = ns.Emblem.ReadTabard()
end

-- "Guild tabard": copy the tabard (when the game has it); "Custom emblem": the last design, or a new one, in the designer.
function Identity.OnMode(page, editor, key)
	if page.filling then return end
	Identity.ReadTabard(page)
	if key == 1 then
		if page.tabardState == "ok" then
			editor:Set("emb", page.tabard)
			page.designer:Hide()
		end
		Identity.FillEmblem(page, editor)
	else
		local current = editor:Get("emb")
		local start = page.lastCustom or (current and current.t == 2 and current) or ns.Emblems.Reset(Identity.Published(), page.tabard)
		editor:Set("emb", ns.Emblems.ToCustom(start))
		page.designer:Open(editor:Get("emb"))
		Identity.FillEmblem(page, editor)
	end
end

-- The one button under the status: take the tabard again after it changed, or open the designer.
function Identity.OnAction(page, editor)
	if page.embActionKind == "update" then
		Identity.ReadTabard(page)
		if page.tabardState == "ok" then editor:Set("emb", page.tabard) end
		Identity.FillEmblem(page, editor)
	else
		Identity.OnMode(page, editor, 2)
	end
end

function Identity.OnDesign(page, editor, emb)
	page.lastCustom = emb
	editor:Set("emb", emb)
	Identity.FillEmblem(page, editor)
end

function Identity.FillEmblem(page, editor)
	Identity.ReadTabard(page)
	local state, tabard = page.tabardState, page.tabard
	local current = editor:Get("emb")
	if current == nil and state == "ok" then   -- the tabard is the default emblem (SPEC-08 2.2)
		editor:Set("emb", tabard)
		current = editor:Get("emb")
	end
	local mode = current and current.t or (state == "ok" and 1 or 2)
	page.filling = true
	page.embMode:SetSelected(mode, true)
	page.filling = false
	page.embMode.segments[1]:SetAlpha(state == "ok" and 1 or 0.5)
	page.emblem:SetEmblem(current, guildName())
	local text, action
	if mode == 1 then
		if state == "ok" and current and not ns.Emblems.Equal(current, tabard) then
			text, action = L["ED_EMB_TABARD_CHANGED"], "update"
		elseif state == "ok" then
			text = L["ED_EMB_TABARD_OK"]
		elseif state == "pending" then
			text = L["ED_EMB_TABARD_PENDING"]
		else
			text, action = L["ED_EMB_TABARD_GONE"], "design"
		end
	else
		action = "design"
		if state == "pending" and not current then text = L["ED_EMB_TABARD_PENDING"]
		elseif state ~= "ok" and not current then text = L["ED_EMB_NO_TABARD"]
		else text = L["ED_EMB_CUSTOM_NOTE"] end
	end
	page.embStatus:SetText(text)
	page.embActionKind = action
	page.embAction:SetShown(action ~= nil)
	if action then page.embAction:SetLabel(action == "update" and L["ED_EMB_UPDATE"] or L["ED_EMB_DESIGN"]) end
	if page.designer:IsShown() and current and not ns.Emblems.Equal(page.designer:Get(), ns.Emblems.ToCustom(current)) then
		page.designer:Set(current)
	end
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
	Identity.FillEmblem(page, editor)
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

---------------------------------------------------------------------------------------------------------------------
-- Recruitment
---------------------------------------------------------------------------------------------------------------------
local Recruitment = {}
local NAME_W, ROLE_W = 134, 66            -- the class column and each of the four role columns of the grid
local GRID_HEAD, GRID_ROW, CELL = 44, 26, 22

-- The faction of the guild: from its key, else the character's.
function Steps.Faction()
	local _, key = ns.Role.Compute()
	return Model.FactionOf(key) or (ns.Compat and ns.Compat.Player.Faction())
end

local function buildCell(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(CELL, CELL)
	b:RegisterForClicks("LeftButtonUp")
	b.bg = W.NineSlice(b, "card", { corner = 6, layer = "BACKGROUND" })
	b.edge = W.NineSlice(b, "card_edge", { corner = 6, layer = "BACKGROUND", sublevel = 1 })
	b.hover = W.NineSlice(b, "card", { corner = 6, layer = "ARTWORK" })
	b.hover:SetColor(1, 1, 1, 0.2)
	b.hover:Hide()
	b.check = W.Texture(b, "glyph_check", "OVERLAY", nil)
	b.check:SetVertexColor(1, 0.92, 0.76, 1)
	b.check:SetSize(14, 14)
	b.check:SetPoint("CENTER", b, "CENTER", 0, 0)
	b:SetScript("OnEnter", function(self) if self.state ~= "blocked" and not self.locked then self.hover:Show() end end)
	b:SetScript("OnLeave", function(self) self.hover:Hide() end)
	b:SetScript("OnClick", function(self) onClick(self) end)
	W.SetTooltip(b, function(self)
		if self.state == "blocked" then return L["FILTER_ROLE_CANT"]:format(self.className or "") end
	end)
	return b
end

-- "on" (ticked), "off" or "blocked" (the class cannot play the role: dimmed, no click); `locked` while recruitment is closed.
local function paintCell(b, state, locked)
	b.state, b.locked = state, locked
	if state == "on" then
		b.bg:SetHex("#5a3315", 1)
		b.edge:SetHex("#3d210b", 1)
	elseif state == "blocked" then
		b.bg:SetHex("#b98a53", 0.25)
		b.edge:SetHex("#b98a53", 0.3)
	else
		b.bg:SetHex("#fff5e1", 0.45)
		b.edge:SetHex("#b98a53", 1)
	end
	b.check:SetShown(state == "on")
	b:SetAlpha(locked and 0.5 or 1)
	if locked or state == "blocked" then b.hover:Hide() end
end

-- One row of the grid: the class (a button: a click ticks or clears every role it can play) and four cells.
local function buildRow(grid, entry, editor, page)
	local row = CreateFrame("Frame", nil, grid.body)
	row:SetSize(INNER_W, GRID_ROW)
	row.id, row.file, row.cells = entry.id, entry.file, {}
	local name = CreateFrame("Button", nil, row)
	name:SetSize(NAME_W, GRID_ROW)
	name:SetPoint("LEFT", row, "LEFT", 0, 0)
	name:RegisterForClicks("LeftButtonUp")
	if entry.id == 0 then
		name.icon = W.Texture(name, "disc", "ARTWORK", "gold2")
		name.icon:SetSize(16, 16)
		name.icon:SetPoint("LEFT", name, "LEFT", 6, 0)
	else
		name.icon = W.ClassIcon(name, { class = entry.file, size = 20 })
		name.icon:SetPoint("LEFT", name, "LEFT", 5, 0)
	end
	name.text = W.Text(name, "body", "ink")
	name.text:SetPoint("LEFT", name, "LEFT", 32, 0)
	name.text:SetPoint("RIGHT", name, "RIGHT", -4, 0)
	name.text:SetWordWrap(false)
	name.text:SetText(entry.id == 0 and L["ED_LOOK_ANY"] or (entry.name or entry.file))
	name:SetScript("OnClick", function() Recruitment.OnClass(page, editor, entry.id) end)
	W.SetTooltip(name, entry.id == 0 and L["ED_LOOK_ANY_TIP"] or L["ED_LOOK_ROW_TIP"])
	row.name = name
	for j, role in ipairs(E.ROLES) do
		local cell = buildCell(row, function() Recruitment.OnCell(page, editor, entry.id, role.bit) end)
		cell:SetPoint("LEFT", row, "LEFT", NAME_W + (j - 1) * ROLE_W + (ROLE_W - CELL) / 2, 0)
		cell.bit, cell.className = role.bit, entry.name
		row.cells[role.bit] = cell
	end
	return row
end

function Recruitment.Build(page, editor)
	local status = W.Card(page, { kind = "plain", title = L["ED_REC_LABEL"], height = 118 })
	status:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	status:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
	local items = {}
	for _, key in ipairs(Model.STATUS_ORDER) do items[#items + 1] = { key = key, text = L["ED_REC_" .. key] } end
	page.status = W.Segmented(status.body, items, { width = INNER_W, onChange = function(key) Recruitment.OnStatus(page, editor, key) end })
	page.status:SetPoint("TOPLEFT", status.body, "TOPLEFT", 0, 0)
	page.statusNote = caption(status.body, "", 44, 18)

	local grid = W.Card(page, { kind = "plain", title = L["ED_LOOK_LABEL"], height = 42 + GRID_HEAD + 9 * GRID_ROW + 30 + 14 })
	grid:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -GAP)
	grid:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, -GAP)
	page.lookCount = W.Text(grid, "caption", "ink2", "RIGHT")
	page.lookCount:SetPoint("TOPRIGHT", grid, "TOPRIGHT", -16, -16)
	local head = W.Text(grid.body, "caption", "ink3")
	head:SetPoint("BOTTOMLEFT", grid.body, "TOPLEFT", 0, -GRID_HEAD + 6)
	head:SetText(L["ED_LOOK_CLASS"])
	page.roleBadges = {}
	for j, role in ipairs(E.ROLES) do
		local x = NAME_W + (j - 1) * ROLE_W
		local badge = W.RoleBadge(grid.body, { role = role.key, size = 20 })
		badge:SetPoint("TOPLEFT", grid.body, "TOPLEFT", x + (ROLE_W - 20) / 2, 0)
		local label = W.Text(grid.body, "caption", "ink2", "CENTER")
		label:SetPoint("TOPLEFT", grid.body, "TOPLEFT", x, -22)
		label:SetWidth(ROLE_W)
		label:SetText(E.RoleLabel(role.bit))
		page.roleBadges[j] = badge
	end
	page.rows = { [0] = buildRow(grid, { id = 0 }, editor, page) }
	for _, entry in ipairs(Model.GridClasses(nil)) do page.rows[entry.id] = buildRow(grid, entry, editor, page) end
	page.gridBody = grid.body
	page.legend = caption(grid.body, "", GRID_HEAD + 9 * GRID_ROW + 2, 28)

	local opts = W.Card(page, { kind = "plain", height = 120 })
	opts:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -GAP)
	opts:SetPoint("TOPRIGHT", grid, "BOTTOMRIGHT", 0, -GAP)
	page.newb = W.Switch(opts.body, { label = L["ED_NEWB"], width = INNER_W,
		onChange = function(checked) if not page.filling then editor:Set("newb", checked and true or nil) end end })
	page.newb:SetPoint("TOPLEFT", opts.body, "TOPLEFT", 0, 0)
	W.SetTooltip(page.newb, L["ED_NEWB_TIP"])
	page.apps = W.Switch(opts.body, { label = L["ED_APPS"], width = INNER_W,
		onChange = function(checked) if not page.filling then editor:Set("apps", checked and true or false) end end })
	page.apps:SetPoint("TOPLEFT", opts.body, "TOPLEFT", 0, -42)
	caption(opts.body, L["ED_APPS_NOTE"], 74, 18)
end

function Recruitment.OnStatus(page, editor, key)
	if page.filling then return end
	local fields, faction = editor:Fields(), Steps.Faction()
	local patch = Model.StatusPatch(fields, key, faction)
	if not patch then return end
	local have = next(Model.Want(fields, faction)) ~= nil
	if key == E.RECRUITING.CLOSED then
		if have then page.lastWant = Model.Want(fields, faction) end   -- a click back on "Selected classes" gets the grid back
	elseif key == E.RECRUITING.SOME and not have and page.lastWant then
		patch.want = page.lastWant
	end
	editor:Patch(patch)
	Recruitment.Fill(page, editor)
end

-- A cell was clicked: tick or clear one role of one class (class 0 is "Any class").
function Recruitment.OnCell(page, editor, classID, bit)
	if page.filling then return end
	local fields, faction = editor:Fields(), Steps.Faction()
	if Model.Status(fields) == E.RECRUITING.CLOSED then return end
	local want, result = Model.ToggleRole(Model.Want(fields, faction), classID, bit, faction)
	if result == "added" or result == "removed" then
		page.lastWant = nil
		editor:Patch(Model.WantPatch(fields, want))
	end
	Recruitment.Fill(page, editor)
end

function Recruitment.OnClass(page, editor, classID)
	if page.filling then return end
	local fields, faction = editor:Fields(), Steps.Faction()
	if Model.Status(fields) == E.RECRUITING.CLOSED then return end
	local want, result = Model.ToggleClass(Model.Want(fields, faction), classID, faction)
	if result == "added" or result == "removed" then
		page.lastWant = nil
		editor:Patch(Model.WantPatch(fields, want))
	end
	Recruitment.Fill(page, editor)
end

function Recruitment.Fill(page, editor)
	local fields, faction = editor:Fields(), Steps.Faction()
	local rec = Model.Status(fields)
	local want = Model.Want(fields, faction)
	local closed = rec == E.RECRUITING.CLOSED
	page.filling = true
	page.status:SetSelected(rec, true)
	page.statusNote:SetText(rec ~= nil and L["ED_REC_NOTE_" .. rec] or L["ED_REC_PICK"])

	-- the rows: Any class, then the classes of this faction; the others are hidden
	local visible = { [0] = true }
	local order = { 0 }
	for _, entry in ipairs(Model.GridClasses(faction)) do visible[entry.id] = true; order[#order + 1] = entry.id end
	for id, row in pairs(page.rows) do if not visible[id] then row:Hide() end end
	for n, id in ipairs(order) do
		local row = page.rows[id]
		if row then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", page.gridBody, "TOPLEFT", 0, -(GRID_HEAD + (n - 1) * GRID_ROW))
			row:Show()
			for bit, cell in pairs(row.cells) do paintCell(cell, Model.Cell(want, id, bit), closed) end
			row.name:SetAlpha(closed and 0.5 or 1)
		end
	end
	page.lookCount:SetText(L["ED_LOOK_COUNT"]:format(Model.WantCount(want)))
	local factionText = L["ED_FACTION_" .. tostring(faction)] or L["ED_FACTION_UNKNOWN"]
	page.legend:SetText(closed and L["ED_LOOK_CLOSED"] or L["ED_LOOK_LEGEND"]:format(factionText))
	page.newb:SetChecked(fields.newb == true, true)
	page.apps:SetChecked(fields.apps ~= false, true)
	page.filling = false
end

function Recruitment.OnHide(page) page.lastWant = nil end

Recruitment.OnShow = Recruitment.Fill
Recruitment.Refresh = Recruitment.Fill

---------------------------------------------------------------------------------------------------------------------
-- Requirements
---------------------------------------------------------------------------------------------------------------------
local Requirements = {}

function Requirements.Build(page, editor)
	local level = W.Card(page, { kind = "plain", title = L["ED_REQ_LEVEL_LABEL"], height = 124 })
	level:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	level:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
	page.levelValue = W.Text(level, "titleS", "ink", "RIGHT")
	page.levelValue:SetPoint("TOPRIGHT", level, "TOPRIGHT", -16, -14)
	local track = CreateFrame("Frame", nil, level.body)
	track:SetSize(INNER_W, 8)
	track:SetPoint("TOPLEFT", level.body, "TOPLEFT", 0, -11)
	track.bg = W.NineSlice(track, "card", { corner = 4, layer = "BACKGROUND" })
	track.bg:SetHex("#b98a53", 0.45)
	local bar = CreateFrame("Slider", nil, level.body)
	bar:SetOrientation("HORIZONTAL")
	bar:SetSize(INNER_W, 26)
	bar:SetPoint("TOPLEFT", level.body, "TOPLEFT", 0, 0)
	bar:SetMinMaxValues(1, Model.MaxLevel())
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	bar:SetThumbTexture(W.Media("disc_shiny"))
	bar.thumb = bar:GetThumbTexture()
	bar.thumb:SetSize(24, 24)
	bar.thumb:SetVertexColor(Skin.Hex("#8c6844"))
	bar:SetScript("OnValueChanged", function(_, value) Requirements.OnLevel(page, editor, value) end)
	page.level = bar
	local low = W.Text(level.body, "caption", "ink3")
	low:SetPoint("TOPLEFT", level.body, "TOPLEFT", 0, -30)
	low:SetText("1")
	page.levelMax = W.Text(level.body, "caption", "ink3", "RIGHT")
	page.levelMax:SetPoint("TOPRIGHT", level.body, "TOPRIGHT", 0, -30)
	caption(level.body, L["ED_REQ_LEVEL_HINT"], 50, 18)

	local ilvl = W.Card(page, { kind = "plain", title = L["ED_REQ_ILVL_LABEL"], height = 176 })
	ilvl:SetPoint("TOPLEFT", level, "BOTTOMLEFT", 0, -GAP)
	ilvl:SetPoint("TOPRIGHT", level, "BOTTOMRIGHT", 0, -GAP)
	page.ilvlSwitch = W.Switch(ilvl.body, { label = L["ED_REQ_ILVL_SWITCH"], width = INNER_W,
		onChange = function(checked) Requirements.OnIlvlSwitch(page, editor, checked) end })
	page.ilvlSwitch:SetPoint("TOPLEFT", ilvl.body, "TOPLEFT", 0, 0)
	page.ilvl = W.Field(ilvl.body, { width = 210, placeholder = L["ED_REQ_ILVL_PLACEHOLDER"], maxLetters = 3,
		onChange = function(text, user) if user then Requirements.OnIlvl(page, editor, text) end end })
	page.ilvl:SetPoint("TOPLEFT", ilvl.body, "TOPLEFT", 0, -42)
	page.ilvlHint = caption(ilvl.body, "", 88, 32)

	local note = W.Card(page, { kind = "plain", title = L["ED_NOTE_LABEL"], height = 134 })
	note:SetPoint("TOPLEFT", ilvl, "BOTTOMLEFT", 0, -GAP)
	note:SetPoint("TOPRIGHT", ilvl, "BOTTOMRIGHT", 0, -GAP)
	page.note = W.Field(note.body, { width = INNER_W, placeholder = L["ED_NOTE_PLACEHOLDER"], maxLetters = Model.NoteMax(),
		onChange = function(text, user) if user then Requirements.OnNote(page, editor, text) end end })
	page.note:SetPoint("TOPLEFT", note.body, "TOPLEFT", 0, 0)
	page.noteCount = W.Text(note.body, "caption", "ink2", "RIGHT")
	page.noteCount:SetPoint("TOPRIGHT", note.body, "TOPRIGHT", 0, -46)
	caption(note.body, L["ED_NOTE_HINT"], 46, 32):SetWidth(INNER_W - 70)
end

-- The slider moved: level 1 is "no minimum" and clears the field.
function Requirements.OnLevel(page, editor, value)
	if page.filling then return end
	local patch = Model.LevelPatch(value)
	if patch then editor:Patch(patch) end
	Requirements.Fill(page, editor)
end

function Requirements.OnIlvlSwitch(page, editor, checked)
	if page.filling then return end
	page.ilvlOn = checked
	if not checked then
		page.filling = true
		page.ilvl:SetText("", true)
		page.filling = false
		editor:Patch(Model.ItemLevelPatch(0))
	end
	Requirements.Fill(page, editor)
	if checked then page.ilvl:SetFocus() end
end

-- Digits only; nothing or 0 clears the field, 1 to 999 is saved.
function Requirements.OnIlvl(page, editor, text)
	if page.filling then return end
	local digits = text:gsub("%D", "")
	if digits ~= text then
		page.filling = true
		page.ilvl:SetText(digits, true)
		page.filling = false
	end
	local n = Model.ParseItemLevel(digits)
	editor:Patch(Model.ItemLevelPatch(n))
	Requirements.Fill(page, editor)
end

function Requirements.OnNote(page, editor, text)
	if page.filling then return end
	local clamped, changed = Model.Clamp(text, Model.NoteMax())
	if changed then
		page.filling = true
		page.note:SetText(clamped, true)
		page.filling = false
	end
	editor:Set("note", clamped ~= "" and clamped or nil)
	Requirements.Fill(page, editor)
end

function Requirements.Fill(page, editor)
	local fields = editor:Fields()
	local req = Model.Requirements(fields)
	local top = Model.MaxLevel()
	page.filling = true
	page.level:SetMinMaxValues(1, top)
	page.level:SetValue(req.level)
	page.levelMax:SetText(tostring(top))
	page.levelValue:SetText(req.hasLevel and L["REQ_LEVEL"]:format(req.level) or L["ED_REQ_LEVEL_NONE"])
	local on = page.ilvlOn == true or req.hasItemLevel
	page.ilvlSwitch:SetChecked(on, true)
	page.ilvl:SetShown(on)
	page.ilvlHint:SetShown(true)
	if req.hasItemLevel then
		if page.ilvl:GetText() ~= tostring(req.itemLevel) then page.ilvl:SetText(tostring(req.itemLevel), true) end
		page.ilvlHint:SetText(L["ED_REQ_ILVL_HINT"])
		W.TextColor(page.ilvlHint, "ink2")
	elseif on then
		page.ilvlHint:SetText(L["ED_REQ_ILVL_EMPTY"])
		W.TextColor(page.ilvlHint, "warn")
	else
		page.ilvlHint:SetText(L["ED_REQ_ILVL_HINT"])
		W.TextColor(page.ilvlHint, "ink2")
	end
	local text = editor:Get("note") or ""
	if page.note:GetText() ~= text then page.note:SetText(text, true) end
	local stats = Model.TextStats(text, Model.NoteMax())
	page.noteCount:SetText(L["ED_COUNT"]:format(stats.chars, stats.max))
	W.TextColor(page.noteCount, counterColor(stats))
	page.filling = false
end

-- Shown again or replaced from outside (Discard changes): the item level switch follows what is stored.
function Requirements.OnShow(page, editor)
	page.ilvlOn = Model.Requirements(editor:Fields()).hasItemLevel
	Requirements.Fill(page, editor)
end
Requirements.Refresh = Requirements.OnShow

---------------------------------------------------------------------------------------------------------------------
-- Contact
---------------------------------------------------------------------------------------------------------------------
local Contact = {}
local SEL_ROW, SUG_ROW = 30, 26
local FIELD_Y, MSG_Y, SUG_Y = 98, 142, 164

-- The member's name in the colour of the class.
local function classColored(fs, file)
	local r, g, b = ns.Assets.ClassColor(file)
	fs:SetTextColor(r, g, b, 1)
end

local function buildContactRow(parent, editor, page)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(INNER_W, SEL_ROW - 2)
	row:EnableMouse(true)
	row.bg = W.NineSlice(row, "card", { corner = 8, layer = "BACKGROUND" })
	row.bg:SetHex("#fff4de", 0.7)
	row.edge = W.NineSlice(row, "card_edge", { corner = 8, layer = "BACKGROUND", sublevel = 1 })
	row.edge:SetHex("#a06e3c", 0.45)
	row.icon = W.ClassIcon(row, { size = 20 })
	row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.text = W.Text(row, "body", "ink")
	row.text:SetPoint("LEFT", row, "LEFT", 36, 0)
	row.text:SetWidth(170)
	row.text:SetWordWrap(false)
	row.note = W.Text(row, "caption", "ink2", "RIGHT")
	row.note:SetPoint("RIGHT", row, "RIGHT", -38, 0)
	row.note:SetWidth(150)
	row.remove = W.IconButton(row, { glyph = "glyph_close", size = 24, tooltip = L["ED_CONT_REMOVE"],
		onClick = function() Contact.OnRemove(page, editor, row.contact) end })
	row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	return row
end

local function buildSuggestion(parent, editor, page)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(INNER_W, SUG_ROW)
	row:RegisterForClicks("LeftButtonUp")
	row.hover = W.Texture(row, "solid", "BACKGROUND", "gold", 0.25)
	row.hover:SetAllPoints(row)
	row.hover:Hide()
	row.icon = W.ClassIcon(row, { size = 18 })
	row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.text = W.Text(row, "body", "ink")
	row.text:SetPoint("LEFT", row, "LEFT", 34, 0)
	row.text:SetWidth(200)
	row.text:SetWordWrap(false)
	row.note = W.Text(row, "caption", "ink2", "RIGHT")
	row.note:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row:SetScript("OnEnter", function(self) self.hover:Show() end)
	row:SetScript("OnLeave", function(self) self.hover:Hide() end)
	row:SetScript("OnClick", function(self) Contact.OnPick(page, editor, self.contact) end)
	return row
end

function Contact.Build(page, editor)
	local disc = W.Card(page, { kind = "plain", title = L["ED_DISC_LABEL"], height = 134 })
	disc:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	disc:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
	local prefix = W.Text(disc.body, "mono", "ink2")
	prefix:SetPoint("LEFT", disc.body, "TOPLEFT", 0, -Skin.METRICS.fieldH / 2)
	prefix:SetText(Model.DISCORD_PREFIX)
	local pw = math.ceil(W.TextWidth(Model.DISCORD_PREFIX, "mono")) + 8
	page.disc = W.Field(disc.body, { width = INNER_W - pw, placeholder = L["ED_DISC_PLACEHOLDER"], maxLetters = Model.DISCORD_TYPED_MAX,
		onChange = function(text, user) if user then Contact.OnDisc(page, editor, text) end end })
	page.disc:SetPoint("TOPLEFT", disc.body, "TOPLEFT", pw, 0)
	page.discHint = caption(disc.body, "", 46, 36)

	local cont = W.Card(page, { kind = "plain", title = L["ED_CONT_LABEL"] .. " " .. L["ED_CONT_RANGE"], height = 42 + SUG_Y + 5 * SUG_ROW + 14 })
	cont:SetPoint("TOPLEFT", disc, "BOTTOMLEFT", 0, -GAP)
	cont:SetPoint("TOPRIGHT", disc, "BOTTOMRIGHT", 0, -GAP)
	page.contCount = W.Text(cont, "label", "ink2", "RIGHT")
	page.contCount:SetPoint("TOPRIGHT", cont, "TOPRIGHT", -16, -14)
	page.contNone = caption(cont.body, L["ED_CONT_NONE"], 6, 44)
	page.contRows = {}
	for i = 1, Model.CONTACTS_MAX do
		local row = buildContactRow(cont.body, editor, page)
		row:SetPoint("TOPLEFT", cont.body, "TOPLEFT", 0, -((i - 1) * SEL_ROW))
		page.contRows[i] = row
	end
	page.search = W.Field(cont.body, { width = INNER_W, placeholder = L["ED_CONT_PLACEHOLDER"], maxLetters = 48,
		onChange = function(text, user) if user then Contact.OnSearch(page, editor, text) end end,
		onEnter = function(text) Contact.OnEnter(page, editor, text) end })
	page.search:SetPoint("TOPLEFT", cont.body, "TOPLEFT", 0, -FIELD_Y)
	page.contMsg = caption(cont.body, "", MSG_Y, 18)
	page.sugRows = {}
	for i = 1, Model.SUGGESTIONS do
		local row = buildSuggestion(cont.body, editor, page)
		row:SetPoint("TOPLEFT", cont.body, "TOPLEFT", 0, -(SUG_Y + (i - 1) * SUG_ROW))
		page.sugRows[i] = row
	end
	page.query = ""

	-- the roster arrives (or changes) after the page was shown
	page.events = CreateFrame("Frame", nil, page)
	page.events:RegisterEvent("GUILD_ROSTER_UPDATE")
	page.events:SetScript("OnEvent", function()
		if page:IsShown() then Contact.ReadRoster(page); Contact.Fill(page, editor) end
	end)
end

function Contact.ReadRoster(page)
	page.roster = Model.Roster()
end

-- What was typed in the Discord box: a link becomes its code, anything unusable is explained and kept as typed (the checklist
-- shows it red until it is fixed).
function Contact.OnDisc(page, editor, text)
	if page.filling then return end
	local check = Model.DiscordCheck(text)
	if check.state == "ok" then
		if check.replace then
			page.filling = true
			page.disc:SetText(check.replace, true)
			page.filling = false
		end
		editor:Set("disc", check.code)
	elseif check.state == "empty" then
		editor:Set("disc", nil)
	else
		editor:Set("disc", text)
	end
	Contact.DiscordHint(page, check)
end

function Contact.DiscordHint(page, check)
	if check.state == "ok" then
		page.discHint:SetText(L["ED_DISC_OK"]:format(check.code))
		W.TextColor(page.discHint, "ok")
	elseif check.state == "bad" then
		page.discHint:SetText(L["ED_DISC_BAD_" .. check.reason])
		W.TextColor(page.discHint, "bad")
	else
		page.discHint:SetText(L["ED_DISC_HINT"])
		W.TextColor(page.discHint, "ink2")
	end
end

function Contact.OnSearch(page, editor, text)
	page.query = text or ""
	Contact.Fill(page, editor)
end

function Contact.OnPick(page, editor, name)
	local list, result = Model.AddContact(Model.Contacts(editor:Fields()), name, page.roster)
	if result == "added" then
		editor:Set("cont", list)
		page.query = ""
		page.filling = true
		page.search:SetText("", true)
		page.filling = false
	elseif result == "unknown" or result == "noroster" then
		W.Snackbar.Show(L["ED_CONT_UNKNOWN"], { key = "editor-contact" })
	elseif result == "repeat" then
		W.Snackbar.Show(L["ED_CONT_REPEAT"], { key = "editor-contact" })
	elseif result == "full" then
		W.Snackbar.Show(L["ED_CONT_FULL"], { key = "editor-contact" })
	end
	Contact.Fill(page, editor)
	return result
end

-- Enter in the search box: the member who is typed in full, else the first one offered.
function Contact.OnEnter(page, editor, text)
	local chosen = Model.Contacts(editor:Fields())
	local exact = Model.FindMember(page.roster, text or "")
	if exact then return Contact.OnPick(page, editor, exact.name) end
	local first = Model.Suggest(page.roster, text, chosen, 1)[1]
	if first then return Contact.OnPick(page, editor, first.name) end
	return Contact.OnPick(page, editor, text)
end

function Contact.OnRemove(page, editor, name)
	local list = Model.RemoveContact(Model.Contacts(editor:Fields()), name)
	editor:Set("cont", #list > 0 and list or nil)
	Contact.Fill(page, editor)
end

function Contact.Fill(page, editor)
	local fields = editor:Fields()
	local roster = page.roster or {}
	-- Discord
	local typed = editor:Get("disc") or ""
	local check = Model.DiscordCheck(typed)
	local shown = check.replace or typed
	page.filling = true
	if page.disc:GetText() ~= shown then page.disc:SetText(shown, true) end
	page.filling = false
	Contact.DiscordHint(page, check)
	-- the chosen characters
	local list = Model.Contacts(fields)
	local states = Model.ContactStates(list, roster)
	for i, row in ipairs(page.contRows) do
		local c = states[i]
		row:SetShown(c ~= nil)
		if c then
			row.contact = c.name
			row.text:SetText(Model.BaseName(c.name))
			if c.member and c.member.file then
				row.icon:SetClass(c.member.file)
				row.icon:Show()
				classColored(row.text, c.member.file)
			else
				row.icon:SetClass(nil)
				row.icon:Hide()
				W.TextColor(row.text, "ink")
			end
			if c.inGuild == false then
				row.note:SetText(L["ED_CONT_GONE"])
				W.TextColor(row.note, "bad")
				W.SetTooltip(row, L["ED_CONT_GONE_TIP"])
			else
				row.note:SetText(c.member and c.member.level and L["ED_CONT_LEVEL"]:format(c.member.level) or "")
				W.TextColor(row.note, "ink2")
			end
		end
	end
	page.contNone:SetShown(#list == 0)
	page.contCount:SetText(L["ED_CONT_COUNT"]:format(#list, Model.CONTACTS_MAX))
	W.TextColor(page.contCount, #list >= Model.CONTACTS_MAX and "warn" or "ink2")
	-- the search and what it offers
	local full = #list >= Model.CONTACTS_MAX
	page.search:SetShown(not full)
	local offered = full and {} or Model.Suggest(roster, page.query, list)
	for i, row in ipairs(page.sugRows) do
		local m = offered[i]
		row:SetShown(m ~= nil)
		if m then
			row.contact = m.name
			row.text:SetText(m.base)
			if m.file then row.icon:SetClass(m.file); row.icon:Show(); classColored(row.text, m.file)
			else row.icon:SetClass(nil); row.icon:Hide(); W.TextColor(row.text, "ink") end
			local bits = {}
			if m.level then bits[#bits + 1] = L["ED_CONT_LEVEL"]:format(m.level) end
			if m.online then bits[#bits + 1] = L["ED_CONT_ONLINE"] end
			row.note:SetText(table.concat(bits, " · "))
		end
	end
	local msg, kind
	if full then msg, kind = L["ED_CONT_FULL"], "warn"
	elseif #roster == 0 then msg, kind = L["ED_CONT_LOADING"], "ink2"
	elseif #offered == 0 then msg, kind = page.query == "" and L["ED_CONT_NO_ONLINE"] or L["ED_CONT_NO_MATCH"], "ink2"
	else msg, kind = page.query == "" and L["ED_CONT_ONLINE"] or L["ED_CONT_MATCHES"], "ink3" end
	page.contMsg:SetText(msg)
	W.TextColor(page.contMsg, kind)
end

function Contact.OnShow(page, editor)
	Contact.ReadRoster(page)
	Contact.Fill(page, editor)
	if ns.Compat and ns.Compat.Guild and ns.Compat.Guild.RequestRoster then ns.Compat.Guild.RequestRoster() end
end

function Contact.OnHide(page)
	page.query = ""
	page.search:SetText("", true)
end

Contact.Refresh = Contact.Fill

Steps.Identity, Steps.About, Steps.Activity = Identity, About, Activity
Steps.Recruitment, Steps.Requirements, Steps.Contact = Recruitment, Requirements, Contact
Editor.RegisterStep("identity", Identity)
-- The guild tabard arrived or changed (GUILDTABARD_UPDATE, UI/Emblem.lua): the Identity page says so while it is shown.
if ns.Bus then
	ns.Bus:On("TABARD_UPDATED", function()
		local page = Identity.page
		if page and page:IsShown() and Identity.editor then Identity.FillEmblem(page, Identity.editor) end
	end)
end
Editor.RegisterStep("about", About)
Editor.RegisterStep("activity", Activity)
Editor.RegisterStep("recruitment", Recruitment)
Editor.RegisterStep("requirements", Requirements)
Editor.RegisterStep("contact", Contact)

if ns.addon then ns.addon.EditorSteps = Steps end
