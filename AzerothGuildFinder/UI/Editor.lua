-- Editor: the listing editor's shell (SPEC-06 §2, mockups 03 and 08, M3.2). Lua 5.1.
--
-- What the Guild Master sees: on the left page a stepper of seven sections, each with its status (green check, red cross,
-- "optional"), "n / 7 ready", the line "Draft saved automatically", the main button (Publish listing, or Save changes for a
-- listing that is already out), the reason when it is off, and Discard changes and Delist. On the right page the title bar
-- has the step, Back and Next; the content has the page of the step on the left and, on the right, the live preview of the
-- card others will see, the "Before publishing" checklist (every item links to its step) and the guild name, which is read
-- from the game. The last step ("Preview & publish") shows the full card and the checklist across the page.
-- Every rule (the checklist, the reasons Publish is off, stepper, preview) is in UI/EditorModel.lua and is tested without
-- frames; saving, publishing and delisting are OwnListing's (Data/OwnListing.lua: Guild Master check, 5-minute limit).
--
-- The work in progress is the draft: every change is saved at once through OwnListing:SaveDraft (nothing is sent), so closing
-- the window loses nothing; "Discard changes" goes back to the last published version.
--
-- What the later steps use (M3.3 Identity and About, M3.4 Activity, M3.5 Recruitment, Requirements and Contact, M3.6 emblem):
--   Editor.RegisterStep(id, def)   id = "identity" | "about" | "activity" | "recruitment" | "requirements" | "contact"
--       def = { Build = function(page, editor), OnShow = function(page, editor), OnHide = function(page, editor),
--               Refresh = function(page, editor) }
--       `page` is a frame the size of the step area (430 x 640 px at 100 %), built once the first time the step is shown;
--       OnShow runs every time it is shown (fill the widgets from editor:Get(...)); Refresh runs when the fields were
--       replaced from outside (Discard changes, a publication) while the page exists. Until a step registers, its page
--       says that it arrives in a later version. The checklist, the stepper and the preview never need to change.
--   Editor:Get(name) / Editor:Set(name, value) / Editor:Patch({ name = value, ... })
--       the fields of SPEC-03 §2-§3 (sub, desc, lang1, lang, tags, pace, days, t0, t1, rec, apps, want, newb, minL, minI, emb,
--       bg, disc, cont, note); a change is saved as the draft and redraws the preview, the checklist and the stepper.
--   Editor:Fields()   a copy of all of them        Editor:View()   the last checklist view (EditorModel.View)
--   Editor:GoTo(i) / Next() / Back() / Step()      navigation        Editor:Open(step)   opens the window on the editor
--   Editor:Publish() / Discard() / Delist()        what the buttons do (Discard and Delist ask first: Editor:Ask(kind))
-- The page is the tab "CreateListing" (a Guild Master without a listing) and, for editing a listed listing from My Guild
-- (M3.8), the pushable page "ListingEditor". Only the Guild Master gets to use it: for anybody else the page is covered
-- by a note and every action is refused by OwnListing.
local ADDON_NAME, ns = ...
ns = ns or {}
local Editor = {}
ns.Editor, ns.modules = Editor, ns.modules or {}
ns.modules.Editor = Editor

local L, Skin, W, Main, Model, Browse, BM = ns.L, ns.Skin, ns.Widgets, ns.Main, ns.EditorModel, ns.Browse, ns.BrowseModel
local OwnListing = ns.OwnListing
local type, pairs, ipairs, tostring, xpcall = type, pairs, ipairs, tostring, xpcall
local max = math.max

Editor.PAGE = "CreateListing"         -- the tab id (UI/Nav.lua)
Editor.EDIT_PAGE = "ListingEditor"    -- the same editor pushed on My Guild (M3.8)
Editor.POLL = 1                       -- seconds between two looks at the clock while shown (the 5-minute limit, "2 min ago")

local VIEW_W, VIEW_H = Browse.VIEW_W, Browse.VIEW_H
local LW = 260                        -- width of the left page's area
local COL_W, GAP = 290, 18            -- the right column (preview, checklist, guild name) and the gap before it
local STEP_W = VIEW_W - COL_W - GAP
local STEP_H, STEP_GAP = 42, 4
local ROW_H, HINT_H = 24, 32

Editor.fields = {}                    -- the working copy of the listing's fields
Editor.defs = {}                      -- step id -> definition (RegisterStep)
Editor.pages = {}                     -- step id -> { frame, def, placeholder } once built
Editor.stepper = Model.NewStepper()

local function clock() return ns.Compat.ServerTime() end
local function after(seconds, fn) return ns.Compat.After(seconds, fn) end

local CONTENT = {}
for _, name in ipairs(Model.CONTENT) do CONTENT[name] = true end

-- `false` clears a field, except `apps` (applications through the addon): there `false` is a real value, "off" (a listing
-- that says nothing about applications counts as open, GuildPageModel). Editor.CLEAR clears any field, `apps` included.
local KEEP_FALSE = { apps = true }
Editor.CLEAR = {}

---------------------------------------------------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------------------------------------------------
-- Registers the page of a step (see the header). Returns false for an id that is not one of the six pluggable steps.
function Editor.RegisterStep(id, def)
	local index = Model.StepIndex(id)
	if not index or index >= Model.PUBLISH or type(def) ~= "table" then return false end
	Editor.defs[id] = def
	local page = Editor.pages[id]
	if page and page.placeholder then   -- the placeholder was already built: the real page replaces it when shown
		if page == Editor.shownPage then Editor:HidePage() end
		page.frame:Hide()
		Editor.pages[id] = nil
		if Editor.host and Editor.host.shown and Editor.stepper.index == index then Editor:ShowStep() end
	end
	return true
end

-- The page that shows while a step has none of its own.
local function buildPlaceholder(frame, id)
	local card = W.Card(frame, { kind = "plain", title = L["ED_STEP_" .. id], height = 120 })
	card:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	card:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	local text = W.Text(card.body, "body", "ink2")
	text:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
	text:SetPoint("TOPRIGHT", card.body, "TOPRIGHT", 0, 0)
	text:SetWordWrap(true)
	text:SetText(L["ED_SOON_" .. id] .. "\n" .. L["ED_SOON"])
	frame.soon = text
end

function Editor:EnsurePage(id)
	local page = self.pages[id]
	if page then return page end
	local def = self.defs[id]
	local frame = CreateFrame("Frame", nil, self.host.stepArea)
	frame:SetAllPoints(self.host.stepArea)
	frame:Hide()
	page = { frame = frame, def = def or {}, placeholder = def == nil, id = id }
	if def then
		if def.Build then xpcall(def.Build, geterrorhandler(), frame, self) end
	else
		buildPlaceholder(frame, id)
	end
	self.pages[id] = page
	return page
end

function Editor:HidePage()
	local page = self.shownPage
	if not page then return end
	self.shownPage = nil
	if page.def.OnHide then xpcall(page.def.OnHide, geterrorhandler(), page.frame, self) end
	page.frame:Hide()
end

-- Shows the page of the current step: a step page and the right column, or the publish page across the content.
function Editor:ShowStep()
	local host = self.host
	if not host then return end
	self:HidePage()
	local index = self.stepper.index
	if index == Model.PUBLISH then
		host.stepArea:Hide(); host.column:Hide(); host.publishArea:Show()
	else
		host.publishArea:Hide(); host.stepArea:Show(); host.column:Show()
		local page = self:EnsurePage(Model.StepId(index))
		self.shownPage = page
		page.frame:Show()
		if page.def.OnShow then xpcall(page.def.OnShow, geterrorhandler(), page.frame, self) end
	end
	Main:SetTitle(Model.StepLabel(index, L))
	self:Draw()
end

function Editor:Step() return self.stepper.index end
function Editor:StepTitle() return Model.StepLabel(self.stepper.index, L) end

-- Goes to step i (1..7). Returns true when the step changed.
function Editor:GoTo(i)
	if not self.stepper:Go(i) then return false end
	self:ShowStep()
	return true
end
function Editor:Next() if self.stepper:Next() then self:ShowStep() return true end return false end
function Editor:Back() if self.stepper:Back() then self:ShowStep() return true end return false end

---------------------------------------------------------------------------------------------------------------------
-- Fields and the draft
---------------------------------------------------------------------------------------------------------------------
function Editor:Fields() return Model.Strip(self.fields) end
function Editor:Get(name) return Model.Strip({ [name] = self.fields[name] })[name] end

-- Reads the working copy again: the draft, else the last published version (also a withdrawn one), else nothing.
function Editor:Load()
	self.fields = Model.Strip(OwnListing:Draft() or OwnListing:Get() or {})
	self.failed = nil
end

-- Called after the fields changed: saves the draft (nothing is sent), then redraws.
function Editor:Changed()
	local ok, why = OwnListing:SaveDraft(self.fields)
	if ok then
		self.savedAt, self.failed = clock(), nil
	else
		local first = self.failed ~= why
		self.failed = why
		if first then W.Snackbar.Show(OwnListing:Explain(why), { key = "editor-save" }) end
	end
	self:Draw()
end

-- Sets one field (a name of SPEC-03 §2-§3; nil clears it). Returns false for another name.
function Editor:Set(name, value)
	if value == nil then value = Editor.CLEAR end
	return self:Patch({ [name] = value })
end

-- Sets several fields at once; one draft save and one redraw. `false` clears a field (see KEEP_FALSE), Editor.CLEAR always does.
function Editor:Patch(values)
	if type(values) ~= "table" then return false end
	local new = Model.Strip(self.fields)
	for name, value in pairs(values) do
		if not CONTENT[name] then return false end
		if value == Editor.CLEAR or (value == false and not KEEP_FALSE[name]) then new[name] = nil
		else new[name] = Model.Strip({ [name] = value })[name] end
	end
	if self:SameRaw(new) then return true end
	self.fields = new
	self:Changed()
	return true
end

-- Model.Same compares what would be published; the working copy also keeps what is typed (a Discord link, an invalid code).
function Editor:SameRaw(new)
	local a, b = Model.Strip(new), Model.Strip(self.fields)
	local function eq(x, y)
		if type(x) ~= type(y) then return false end
		if type(x) ~= "table" then return x == y end
		for k, v in pairs(x) do if not eq(v, y[k]) then return false end end
		for k in pairs(y) do if x[k] == nil then return false end end
		return true
	end
	return eq(a, b)
end

---------------------------------------------------------------------------------------------------------------------
-- Rules (EditorModel) applied to the current state
---------------------------------------------------------------------------------------------------------------------
function Editor:Context()
	local key, why = OwnListing:CanEdit()
	local _, guildKey = ns.Role.Compute()
	local status = OwnListing:Status()
	local ctx = {
		L = L, key = guildKey, canEdit = key ~= nil, why = why, wait = OwnListing:PublishWait(), status = status, now = clock(),
		leader = key ~= nil or (why ~= "not-leader" and why ~= "no-guild"),
	}
	if status == "listed" then ctx.changed = not Model.Same(self.fields, OwnListing:Get()) end
	return ctx
end

function Editor:Evaluate()
	local ctx = self:Context()
	self.ctx = ctx
	self.view = Model.View(self.fields, ctx)
	self.action = Model.Action(self.view, ctx)
	return self.view, self.action
end

function Editor:View() if not self.view then self:Evaluate() end return self.view end

---------------------------------------------------------------------------------------------------------------------
-- The buttons
---------------------------------------------------------------------------------------------------------------------
-- Publish listing / Save changes. Returns ok, reason ("published", or what OwnListing or the checklist refused).
function Editor:Publish()
	local _, action = self:Evaluate()
	if not action.enabled then
		if action.reason then W.Snackbar.Show(action.reason, { key = "editor" }) end
		if action.kind == "incomplete" and action.step then self:GoTo(action.step) end
		return false, action.kind
	end
	local ok, why, wait = OwnListing:Publish(self:Fields())
	W.Snackbar.Show(OwnListing:Explain(why, wait), { key = "editor" })
	if ok then self:Load(); self.savedAt = nil end
	self:RefreshPages()
	self:Draw()
	return ok, why
end

-- Delist (after the confirmation): OwnListing withdraws the listing; the editor stays, filled with the last version.
function Editor:Delist()
	local ok, why = OwnListing:Delist()
	W.Snackbar.Show(OwnListing:Explain(why), { key = "editor" })
	if ok then self:Load() end
	self:RefreshPages()
	self:Draw()
	return ok, why
end

-- Discard changes (after the confirmation): the draft goes, the last published version is back.
function Editor:Discard()
	local ok, why = OwnListing:DiscardDraft()
	if not ok then
		W.Snackbar.Show(OwnListing:Explain(why), { key = "editor" })
		return false, why
	end
	self:Load()
	self.savedAt = nil
	W.Snackbar.Show(L["ED_DISCARDED"], { key = "editor" })
	self:RefreshPages()
	self:Draw()
	return true
end

-- Discard and Delist ask first. kind = "discard" | "delist".
function Editor:Ask(kind)
	local host = self.host
	if not host or (kind ~= "discard" and kind ~= "delist") then return false end
	host.confirmKind = kind
	local text = L["ED_DELIST_CONFIRM"]
	if kind == "discard" then text = OwnListing:Get() and L["ED_DISCARD_CONFIRM"] or L["ED_DISCARD_CONFIRM_NEW"] end
	host.confirm.text:SetText(text)
	host.confirm.yes:SetLabel(kind == "discard" and L["ED_DISCARD"] or L["ED_DELIST"])
	host.confirm:Show()
	return true
end

-- The answer to the question: true does it, false only closes it. Returns what Discard or Delist returned.
function Editor:Answer(yes)
	local host = self.host
	if not host then return false end
	local kind = host.confirmKind
	host.confirmKind = nil
	host.confirm:Hide()
	if not yes then return false end
	if kind == "discard" then return self:Discard() end
	if kind == "delist" then return self:Delist() end
	return false
end

-- A step page whose fields were replaced from outside redraws itself.
function Editor:RefreshPages()
	for _, page in pairs(self.pages) do
		if page.def.Refresh then xpcall(page.def.Refresh, geterrorhandler(), page.frame, self) end
	end
end

-- Development builds: sample values so that the checklist and Publish can be tried before the steps exist.
Editor.SAMPLE = {
	sub = "A sample listing from a development build", desc = "This listing was filled in with sample values by a development build of the addon.",
	lang1 = 1, lang = 1, tags = { 1, 2 }, pace = 2, days = 31, t0 = 1140, t1 = 1380, rec = 1, apps = true, want = { [0] = 15 },
	newb = true, minL = 1, emb = { t = 2, e = 0 },
}

function Editor:FillSample()
	if not (ns.Config and ns.Config.DEV) then return false end
	self:Patch(Editor.SAMPLE)
	self:RefreshPages()
	W.Snackbar.Show(L["ED_SAMPLE_DONE"], { key = "editor" })
	return true
end

-- Opens the window on the editor: the Create Listing tab, or (a Guild Master with a listing) the editor pushed on My Guild.
function Editor:Open(step)
	if type(step) == "number" then self.stepper:Go(step) end
	Main:RefreshTabs(false)
	if Main.book:Has(Editor.PAGE) then
		Main:Open(Editor.PAGE)
	else
		Main:Show()
		if Main.book:Has("MyGuild") then
			Main.book:Select("MyGuild")
			if Main:CurrentPage() ~= Editor.EDIT_PAGE then Main:Push(Editor.EDIT_PAGE) end
		end
	end
	if self.host and self.host.shown then self:ShowStep() end
end

-- /gf debug editor (development builds): the editor on a listing that is out, until My Guild (M3.8) has its Edit button.
function Editor:DebugOpen()
	if not (ns.Config and ns.Config.DEV) then
		if ns.addon and ns.addon.Print then ns.addon:Print(L["ED_DEBUG_DEV_ONLY"]) end
		return false
	end
	self:Open()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Frames: the left page
---------------------------------------------------------------------------------------------------------------------
local function createStepButton(host, index)
	local b = CreateFrame("Button", nil, host.left)
	b:SetSize(LW, STEP_H)
	b:RegisterForClicks("LeftButtonUp")
	b.index = index
	b.bg = W.NineSlice(b, "card", { corner = 10, layer = "BACKGROUND" })
	b.edge = W.NineSlice(b, "card_edge", { corner = 10, layer = "BACKGROUND", sublevel = 1 })
	b.disc = W.Texture(b, "disc", "ARTWORK", nil)
	b.disc:SetSize(24, 24)
	b.disc:SetPoint("LEFT", b, "LEFT", 12, 0)
	b.num = W.Text(b, "overline", "white", "CENTER")
	b.num:SetPoint("CENTER", b.disc, "CENTER", 0, 0)
	b.num:SetText(tostring(index))
	b.label = W.Text(b, "titleS", "#4b2e14")
	b.label:SetPoint("LEFT", b, "LEFT", 46, 0)
	b.label:SetText(Model.StepLabel(index, L))
	b.mark = W.Texture(b, "glyph_check", "OVERLAY", nil)
	b.mark:SetSize(18, 18)
	b.mark:SetPoint("RIGHT", b, "RIGHT", -12, 0)
	b.note = W.Text(b, "caption", "ink3", "RIGHT")
	b.note:SetPoint("RIGHT", b, "RIGHT", -12, 0)
	b:SetScript("OnClick", function() Editor:GoTo(index) end)
	b:SetScript("OnEnter", function(self) if not self.active then self.bg:SetHex("#fff4de", 0.55) end end)
	b:SetScript("OnLeave", function(self) if not self.active then self.bg:SetHex("#fff4de", 0) end end)
	return b
end

local function paintStep(b, status, active)
	b.active = active
	b.status = status
	b.bg:SetHex(active and "#fbe5b5" or "#fff4de", active and 1 or 0)
	b.edge:SetHex(active and "#b8820f" or "#a06e3c", active and 1 or 0)
	W.TintHex(b.disc, active and "#7a4a22" or (status == "ok" and "#2e7d32" or "#d6b98c"))
	W.TextColor(b.num, (active or status == "ok") and "white" or "#6a4526")
	local mark = (status == "ok" and "glyph_check") or (status == "bad" and "glyph_close") or nil
	b.mark:SetShown(mark ~= nil)
	if mark then
		b.mark:SetTexture(W.Media(mark))
		W.TintHex(b.mark, status == "ok" and "#2e7d32" or "#b3261e")
	end
	b.note:SetText(status == "optional" and L["ED_OPTIONAL"] or "")
end

local function buildLeft(host)
	local left = host.left
	host.plate = W.Plate(left, { text = L["ED_SECTIONS"], width = LW })
	host.plate:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
	host.ready = W.Text(left, "caption", "#fff4df", "RIGHT")
	host.ready:SetPoint("RIGHT", host.plate, "RIGHT", -12, 0)
	host.stepButtons = {}
	for i = 1, Model.COUNT do
		local b = createStepButton(host, i)
		b:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -(44 + (i - 1) * (STEP_H + STEP_GAP)))
		host.stepButtons[i] = b
	end

	-- from the bottom: Discard and Delist, the reason, the main button, the draft line
	host.discard = W.Button(left, { text = L["ED_DISCARD"], kind = "ghost", size = "sm", onClick = function() Editor:Ask("discard") end })
	host.discard:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", -6, 0)
	host.delist = W.Button(left, { text = L["ED_DELIST"], kind = "tonal", size = "sm", onClick = function() Editor:Ask("delist") end })
	host.delist:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, 0)
	host.reason = W.Text(left, "caption", "warn", "CENTER")
	host.reason:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 38)
	host.reason:SetWidth(LW)
	host.reason:SetHeight(32)
	host.reason:SetWordWrap(true)
	host.reason:SetJustifyV("MIDDLE")
	host.publish = W.Button(left, { text = L["ED_PUBLISH"], kind = "primary", size = "lg", width = LW, onClick = function() Editor:Publish() end })
	host.publish:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 74)
	host.draft = W.Text(left, "caption", "ink2")
	host.draft:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 126)
	host.draft:SetWidth(LW)
	host.draft:SetWordWrap(false)

	-- the question before Discard and Delist, over the buttons
	local c = CreateFrame("Frame", nil, left)
	c:SetSize(LW + 12, 150)
	c:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", -6, -6)
	c:SetFrameLevel(left:GetFrameLevel() + 20)
	c:EnableMouse(true)
	c.bg = W.NineSlice(c, "card", { corner = 12, layer = "BACKGROUND" })
	c.bg:SetHex("#fbe9c5")
	c.edge = W.NineSlice(c, "card_edge", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	c.edge:SetHex("#b8820f")
	c.text = W.Text(c, "body", "ink")
	c.text:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -14)
	c.text:SetWidth(LW - 16)
	c.text:SetWordWrap(true)
	c.yes = W.Button(c, { text = L["ED_DELIST"], kind = "primary", size = "sm", onClick = function() Editor:Answer(true) end })
	c.yes:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 14, 14)
	c.no = W.Button(c, { text = L["ED_CANCEL"], kind = "tonal", size = "sm", onClick = function() Editor:Answer(false) end })
	c.no:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 14)
	c:Hide()
	host.confirm = c
end

---------------------------------------------------------------------------------------------------------------------
-- Frames: the title bar
---------------------------------------------------------------------------------------------------------------------
local function buildHeader(host)
	local h = host.header
	host.next = W.Button(h, { text = L["ED_NEXT"], kind = "tonal", size = "md", onClick = function() Editor:Next() end })
	host.next:SetPoint("RIGHT", h, "RIGHT", 0, 0)
	host.back = W.Button(h, { text = L["BTN_BACK"], kind = "ghost", glyph = "glyph_back", size = "md", onClick = function() Editor:Back() end })
	host.back:SetPoint("RIGHT", host.next, "LEFT", -8, 0)
	host.stepText = W.Text(h, "overline", "ink3", "RIGHT")
	host.stepText:SetPoint("RIGHT", host.back, "LEFT", -14, 0)
end

---------------------------------------------------------------------------------------------------------------------
-- Frames: preview, checklist, guild name
---------------------------------------------------------------------------------------------------------------------
-- The small card of the right column: the same display fields as a card of the list (BrowseModel.Card).
local function createMini(parent)
	local card = W.Card(parent, { kind = "elevated", width = COL_W, height = 122 })
	card.emblem = ns.Emblem.Create(card, 58)
	card.emblem:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -12)
	card.name = W.Text(card, "titleM", "ink")
	card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 82, -12)
	card.name:SetWidth(COL_W - 94)
	card.name:SetWordWrap(false)
	card.sub = W.Text(card, "caption", "ink2")
	card.sub:SetPoint("TOPLEFT", card, "TOPLEFT", 82, -34)
	card.sub:SetWidth(COL_W - 94)
	card.sub:SetHeight(30)
	card.sub:SetWordWrap(true)
	card.sub:SetMaxLines(2)
	card.sub:SetJustifyV("TOP")
	card.tags = {}
	card.acts = W.Text(card, "caption", "ink")
	card.acts:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -96)
	card.acts:SetWidth(COL_W - 24 - 104)
	card.acts:SetWordWrap(false)
	-- the guild's statistics as the list shows them ("31 active / 149"), from the roster (Data/Stats.lua)
	card.members = W.Text(card, "caption", "ink2", "RIGHT")
	card.members:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -96)
	card.members:SetWidth(100)
	card.members:SetWordWrap(false)
	return card
end

local function bindMini(card, display)
	card.name:SetText(display.name)
	card.emblem:SetEmblem(display.emb, display.name)
	card.sub:SetText(display.sub or "")
	local specs = {}
	for i, code in ipairs(display.langs) do
		if i > 2 then break end
		specs[#specs + 1] = { code, "default" }
	end
	if display.paceText then specs[#specs + 1] = { display.paceText, display.paceKind } end
	local x = 82
	for i, spec in ipairs(specs) do
		local tag = card.tags[i]
		if not tag then tag = W.Tag(card, { text = "", kind = "default" }); card.tags[i] = tag end
		tag:SetKind(spec[2])
		tag:SetText(spec[1])
		tag:ClearAllPoints()
		tag:SetPoint("TOPLEFT", card, "TOPLEFT", x, -68)
		tag:Show()
		x = x + tag:GetWidth() + 4
	end
	for i = #specs + 1, #card.tags do card.tags[i]:Hide() end
	card.acts:SetText(display.activitiesText or "")
	if display.active then
		card.members:SetText((display.members and L["INFO_ACTIVE_OF"] or L["INFO_ACTIVE"]):format(display.active, display.members))
	else
		card.members:SetText(L["INFO_MEMBERS_UNKNOWN"])
	end
end

local STATE_ICON = {
	ok = { "glyph_check", "#2e7d32" }, bad = { "glyph_close", "#b3261e" }, todo = { "disc_ring", "#8c6844" },
	optional = { "disc_ring", "#b98a53" },
}

-- The "Before publishing" card: one row per item, a click goes to the step that fixes it.
local function createChecklist(parent, width)
	local card = W.Card(parent, { kind = "elevated", title = L["ED_CHK_TITLE"], glyph = "glyph_check", width = width, height = 100 })
	card.rows = {}
	card.rowWidth = width - 32
	return card
end

local function createRow(card, i)
	local row = CreateFrame("Button", nil, card.body)
	row:RegisterForClicks("LeftButtonUp")
	row.icon = W.Texture(row, "glyph_check", "OVERLAY", nil)
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
	row.text = W.Text(row, "body", "ink")
	row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 26, -3)
	row.text:SetWidth(card.rowWidth - 26)
	row.text:SetWordWrap(false)
	row.hint = W.Text(row, "caption", "ink2")
	row.hint:SetPoint("TOPLEFT", row, "TOPLEFT", 26, -ROW_H)
	row.hint:SetWidth(card.rowWidth - 26)
	row.hint:SetHeight(HINT_H - 4)
	row.hint:SetWordWrap(true)
	row.hint:SetJustifyV("TOP")
	row:SetScript("OnClick", function(self) if self.step then Editor:GoTo(self.step) end end)
	W.SetTooltip(row, function(self)
		if row.step then return L["ED_GO_TO_STEP"]:format(Model.StepLabel(row.step, L)) end
	end)
	return row
end

local function bindChecklist(card, items)
	local y = 0
	for i, it in ipairs(items) do
		local row = card.rows[i]
		if not row then row = createRow(card, i); card.rows[i] = row end
		local icon = STATE_ICON[it.state] or STATE_ICON.todo
		row.step, row.item = it.step, it
		row.icon:SetTexture(W.Media(icon[1]))
		W.TintHex(row.icon, icon[2])
		row.text:SetText(it.text)
		W.TextColor(row.text, it.state == "bad" and "bad" or ((it.state == "todo" or it.state == "optional") and "ink2" or "ink"))
		local hinted = it.hint ~= nil and (it.state == "bad" or it.state == "todo")
		row.hint:SetText(hinted and it.hint or "")
		row.hint:SetShown(hinted)
		local h = ROW_H + (hinted and HINT_H or 0)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -y)
		row:SetSize(card.rowWidth, h)
		row:EnableMouse(it.step ~= nil)
		row:Show()
		y = y + h
	end
	for i = #items + 1, #card.rows do card.rows[i]:Hide() end
	card:SetHeight(42 + y + 14)
	return card:GetHeight()
end

local function buildColumn(host)
	local col = CreateFrame("Frame", nil, host.content)
	col:SetSize(COL_W, VIEW_H)
	col:SetPoint("TOPRIGHT", host.content, "TOPRIGHT", 0, 0)
	host.column = col
	host.previewLabel = W.Text(col, "overline", "ink3")
	host.previewLabel:SetPoint("TOPLEFT", col, "TOPLEFT", 2, 0)
	host.previewLabel:SetText(L["ED_PREVIEW"]:upper())
	host.mini = createMini(col)
	host.mini:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -22)
	host.checklist = createChecklist(col, COL_W)
	host.nameCard = W.Card(col, { kind = "plain", width = COL_W, height = 84 })
	host.nameLabel = W.Text(host.nameCard, "titleS", "ink")
	host.nameLabel:SetPoint("TOPLEFT", host.nameCard, "TOPLEFT", 14, -12)
	host.nameLabel:SetWidth(COL_W - 28)
	host.nameLabel:SetWordWrap(false)
	host.nameNote = W.Text(host.nameCard, "caption", "ink2")
	host.nameNote:SetPoint("TOPLEFT", host.nameCard, "TOPLEFT", 14, -32)
	host.nameNote:SetWidth(COL_W - 28)
	host.nameNote:SetHeight(44)
	host.nameNote:SetWordWrap(true)
	host.nameNote:SetJustifyV("TOP")
	host.nameNote:SetText(L["ED_GUILD_NAME_TIP"])
end

-- The last step: the full card of the list, then the checklist across the page.
local function buildPublishArea(host)
	local area = CreateFrame("Frame", nil, host.content)
	area:SetAllPoints(host.content)
	area:Hide()
	host.publishArea = area
	host.card = Browse.CreateCard(area)
	host.card:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
	host.checklist2 = createChecklist(area, Browse.CARD_W)
	host.checklist2:SetPoint("TOPLEFT", host.card, "BOTTOMLEFT", 0, -14)
	host.publishNote = W.Text(area, "body", "ink2")
	host.publishNote:SetPoint("TOPLEFT", host.checklist2, "BOTTOMLEFT", 4, -12)
	host.publishNote:SetWidth(Browse.CARD_W - 8)
	host.publishNote:SetWordWrap(true)
	if ns.Config and ns.Config.DEV then
		host.sample = W.Button(area, { text = L["ED_SAMPLE"], kind = "tonal", size = "sm", tooltip = L["ED_SAMPLE_TIP"],
			onClick = function() Editor:FillSample() end })
		host.sample:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -(VIEW_W - Browse.CARD_W), 0)
	end
end

local function buildContent(host)
	host.stepArea = CreateFrame("Frame", nil, host.content)
	host.stepArea:SetSize(STEP_W, VIEW_H)
	host.stepArea:SetPoint("TOPLEFT", host.content, "TOPLEFT", 0, 0)
	buildColumn(host)
	buildPublishArea(host)

	-- anybody but the Guild Master: a note over the whole page
	local b = W.Card(host.content, { kind = "gold", width = 440, height = 90 })
	b:SetPoint("CENTER", host.content, "CENTER", 0, 20)
	b:SetFrameLevel(host.content:GetFrameLevel() + 30)
	b:EnableMouse(true)
	b.text = W.Text(b.body, "bodyL", "ink", "CENTER")
	b.text:SetAllPoints(b.body)
	b.text:SetWordWrap(true)
	b.text:SetText(L["ED_NOT_GM"])
	b:Hide()
	host.blocked = b
end

local function build(host)
	Editor.host = host
	buildLeft(host)
	buildHeader(host)
	buildContent(host)
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
function Editor:IsShown() return self.host ~= nil and self.host.shown == true end

local function layoutColumn(host, checklistH)
	host.checklist:ClearAllPoints()
	host.checklist:SetPoint("TOPLEFT", host.mini, "BOTTOMLEFT", 0, -12)
	host.nameCard:ClearAllPoints()
	host.nameCard:SetPoint("TOPLEFT", host.checklist, "BOTTOMLEFT", 0, -12)
end

-- The status line and the buttons that depend on the clock and on the saved data (also called every POLL seconds).
function Editor:DrawAction()
	local host = self.host
	if not host or not self.action then return end
	local a = self.action
	host.publish:SetLabel(a.label)
	host.publish:SetEnabled(a.enabled)
	host.publish.reason = (not a.enabled) and a.reason or nil
	host.reason:SetText(a.enabled and "" or (a.reason or ""))
	host.draft:SetText(Model.DraftText({ savedAt = self.savedAt, now = clock(), failed = self.failed }, L))
	W.TextColor(host.draft, self.failed and "bad" or "ink2")
	local can = self.ctx.canEdit
	host.discard:SetEnabled(can and OwnListing:Draft() ~= nil)
	host.delist:SetShown(self.ctx.status == "listed")
	host.delist:SetEnabled(can)
	host.blocked:SetShown(self.ctx.why == "not-leader" or self.ctx.why == "no-guild")
end

-- Everything on the page, from the working copy.
function Editor:Draw()
	local host = self.host
	if not host or not host.shown then return end
	local view = self:Evaluate()
	local index = self.stepper.index
	for i, b in ipairs(host.stepButtons) do paintStep(b, view.steps[i].status, i == index) end
	host.ready:SetText(Model.ReadyText(view.ready, L))
	host.stepText:SetText(Model.StepText(index, L):upper())
	host.back:SetEnabled(self.stepper:CanBack())
	host.next:SetEnabled(self.stepper:CanNext())

	local st, _, statsKey
	if ns.Stats then st, _, statsKey = ns.Stats:Current() end
	local display = Model.Preview(self.fields, self.ctx.key, self.ctx.now, L, statsKey == self.ctx.key and st or nil)
	local _, _, guildName = ns.Listing.ParseKey(self.ctx.key or "")
	if index == Model.PUBLISH then
		Browse.BindCard(host.card, display)
		bindChecklist(host.checklist2, view.items)
		host.publishNote:SetText(view.complete and L["ED_PUBLISH_READY"] or L["ED_PUBLISH_TODO"])
	else
		bindMini(host.mini, display)
		layoutColumn(host, bindChecklist(host.checklist, view.items))
		host.nameLabel:SetText(L["ED_GUILD_NAME"]:format(guildName or display.name))
	end
	self:DrawAction()
end

-- Every POLL seconds while shown: the 5-minute limit counts down, "2 min ago" moves on.
function Editor:StartPoll()
	self.pollGen = (self.pollGen or 0) + 1
	local gen = self.pollGen
	local function tick()
		if gen ~= self.pollGen or not self:IsShown() then return end
		self:Evaluate()
		self:DrawAction()
		after(Editor.POLL, tick)
	end
	after(Editor.POLL, tick)
end

function Editor:StopPoll() self.pollGen = (self.pollGen or 0) + 1 end

---------------------------------------------------------------------------------------------------------------------
-- The page of the window
---------------------------------------------------------------------------------------------------------------------
local pageDef = {
	title = function() return Editor:StepTitle() end,
	Build = build,
	OnShow = function(host)
		Editor.host = host
		Editor:Load()
		Editor.savedAt = nil
		host.confirm:Hide()
		host.confirmKind = nil
		Editor:ShowStep()
		Editor:StartPoll()
	end,
	OnHide = function(host, entry)
		Editor:StopPoll()
		Editor:HidePage()
		host.shown = false
		host.confirm:Hide()
		host.confirmKind = nil
	end,
}

Main:RegisterPage(Editor.PAGE, pageDef)
Main:RegisterPage(Editor.EDIT_PAGE, pageDef)

---------------------------------------------------------------------------------------------------------------------
-- Wiring and diagnostics
---------------------------------------------------------------------------------------------------------------------
-- A publication, a withdrawal or a GLIST from the Guild Master changed the published version: read it again. (Our own
-- draft saves also announce themselves, with "draft"; nothing to do then.)
function Editor:OnOwnListing(what)
	if what == "draft" or not self:IsShown() then return end
	self:Load()
	self:RefreshPages()
	self:Draw()
end

function Editor:DebugLines()
	local fields = 0
	for _ in pairs(self.fields) do fields = fields + 1 end
	local pages = 0
	for _ in pairs(self.pages) do pages = pages + 1 end
	return { ("Editor: %s, step %d of %d, %d fields in the working copy, %d step pages built, %d registered"):format(
		self:IsShown() and "open" or "closed", self.stepper.index, Model.COUNT, fields, pages,
		(function() local n = 0 for _ in pairs(self.defs) do n = n + 1 end return n end)()) }
end

if ns.Bus then
	ns.Bus:On("OWN_LISTING_CHANGED", function(what) Editor:OnOwnListing(what) end)
	ns.Bus:On("ROLE_CHANGED", function() if Editor:IsShown() then Editor:Draw() end end)
	ns.Bus:On("STATS_CHANGED", function() if Editor:IsShown() then Editor:Draw() end end)
end
if ns.addon then
	ns.addon.Editor = Editor
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Editor", function() return Editor:DebugLines() end) end
end
