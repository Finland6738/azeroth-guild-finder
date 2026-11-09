-- Browse: the Find a Guild page (SPEC-05 §1, mockup 01-browse). Lua 5.1.
--
-- What the player sees: on the right page a search box (3 letters, normalized, 250 ms after the last key), the count
-- "24 of 142 guilds" and the fixed "Sorted A-Z"; under it the guild cards, one every 188 px, scrolled with the mouse wheel
-- or the bar; a status bar. On the left page the filters (UI/FilterPanel.lua, rules in UI/FilterModel.lua). A click on a
-- card opens its page (M2.7).
-- All rules (order, search, states, texts of a card, which rows are visible) live in UI/BrowseModel.lua and are tested
-- without frames; this file creates the frames and copies what the model says into them.
--
-- Virtual scrolling: the list may hold 500 guilds but only a fixed pool of row frames exists (Model.PoolSize: 6 for the
-- 638 px view). Each row frame is bound to the guild whose index it shows ((index - 1) % 6 + 1 is its slot), moved when
-- the view scrolls and rebound only when its guild changes. Nothing is created while scrolling.
--
-- What the later steps use:
--   Browse:SetFilter(fn, activeCount, resetFn, prepareFn)   the hook of the filters (M2.6, UI/FilterPanel.lua):
--                                                fn(summary, info) -> true keeps a listing (nil: nothing is filtered);
--                                                activeCount feeds the "No guild matches your filters" state and its
--                                                button; resetFn() clears the filters and calls Browse:SetFilter again;
--                                                prepareFn() runs before each rebuild of the list.
--   Browse:RefreshNow()   Browse:Selected() -> the listings now shown (A -> Z)    Browse.left = the left page frame
--   Browse:OpenGuild(k)   pushes the guild page of M2.7 ("GuildPage") on the Find a Guild tab
-- The list reacts to CATALOG_UPDATED on the Bus, at most once every Model.THROTTLE seconds, and only while it is shown.
local ADDON_NAME, ns = ...
ns = ns or {}
local Browse = {}
ns.Browse, ns.modules = Browse, ns.modules or {}
ns.modules.Browse = Browse

local L, Skin, W, Main, Model = ns.L, ns.Skin, ns.Widgets, ns.Main, ns.BrowseModel
local type, ipairs, pairs = type, ipairs, pairs
local floor, min, max, sin, cos = math.floor, math.min, math.max, math.sin, math.cos

Browse.PAGE = "FindGuild"            -- the tab id (UI/Nav.lua)
Browse.GUILD_PAGE = "GuildPage"      -- the page M2.7 registers
Browse.WHEEL_STEP = 64               -- px per notch of the mouse wheel
Browse.POLL = 5                      -- seconds between two looks at the sync state while the page is shown

local M = Skin.METRICS
local CARD_H, STEP, GAP = Model.CARD_H, Model.STEP, Model.GAP
local VIEW_W = M.windowW - M.leftPageW + 6 - 54            -- the content area of the right page
local VIEW_H = M.windowH - (16 + M.headerH + 12) - (M.statusH + 16)
local BAR_W = 10
local CARD_W = VIEW_W - BAR_W - 8
local POOL = Model.PoolSize(VIEW_H, STEP)
local TOP_H = 126                         -- the upper part of a card; the info band is under it
local BANNER_W = 380
local TEXT_X = 116                        -- left edge of the texts, right of the emblem
local COL = { 16, 262, 508 }              -- left edges of the three columns of the info band
local COL_W = 232

Browse.VIEW_H, Browse.VIEW_W, Browse.CARD_W, Browse.POOL_SIZE = VIEW_H, VIEW_W, CARD_W, POOL
Browse.rowsCreated = 0
Browse.pool = Model.NewPool(POOL)
Browse.rows = {}                          -- slot -> row frame
Browse.data = {}                          -- the listings shown, A -> Z
Browse.total = 0
Browse.offset = 0
Browse.search = ""
Browse.dirty = true

local function after(seconds, fn) return ns.Compat.After(seconds, fn) end
local function clock() return ns.Compat.ServerTime() end

---------------------------------------------------------------------------------------------------------------------
-- Sync state, read from the network layer (memory only)
---------------------------------------------------------------------------------------------------------------------
local function syncInfo()
	local Sync = ns.Sync
	if not Sync then return false, 0, nil end
	return Sync:IsSyncing(), Sync:HeardPeers(), Sync:LastFullSync()
end

---------------------------------------------------------------------------------------------------------------------
-- One card (a pooled row frame)
---------------------------------------------------------------------------------------------------------------------
local function text(parent, style, color, x, y, width)
	local fs = W.Text(parent, style, color)
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	if width then fs:SetWidth(width) end
	fs:SetWordWrap(false)
	return fs
end

local function createEmblemPlaceholder(row)
	local emb = CreateFrame("Frame", nil, row)
	emb:SetSize(84, 84)
	emb:SetPoint("TOPLEFT", row, "TOPLEFT", 16, -16)
	emb.shadow = W.NineSlice(emb, "shadow", { corner = 32, outset = 10, layer = "BACKGROUND", sublevel = -1 })
	emb.shadow:SetColor(0.1, 0.05, 0, 0.35)
	emb.rim = W.NineSlice(emb, "card", { corner = 16, layer = "BACKGROUND" })
	emb.rim:SetHex("#9aa4ae")
	emb.inner = W.NineSlice(emb, "card", { corner = 12, layer = "BACKGROUND", sublevel = 1, outset = -5 })
	emb.inner:SetHex("#2b3547")
	emb.glyph = W.Texture(emb, "glyph_shield", "ARTWORK", "gold")
	emb.glyph:SetSize(46, 46)
	emb.glyph:SetPoint("CENTER", emb, "CENTER", 0, 0)
	return emb
end

local function createRow(parent, slot)
	local row = W.Card(parent, { kind = "plain", width = CARD_W, height = CARD_H })
	row.slot = slot
	row:EnableMouse(true)
	row:EnableMouseWheel(true)

	-- banner: the client's own image by fileID, melting into the parchment from the left
	row.banner = row:CreateTexture(nil, "ARTWORK", nil, 0)
	row.banner:SetPoint("TOPRIGHT", row, "TOPRIGHT", -3, -3)
	row.banner:SetSize(BANNER_W, TOP_H - 3)
	row.banner:SetTexCoord(0, 1, 0.21, 0.79)
	row.fade = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.fade:SetTexture(W.Media("fade_h"))
	row.fade:SetVertexColor(Skin.Hex("#fbe7c5"))
	row.fade:SetPoint("TOPRIGHT", row, "TOPRIGHT", -3, -3)
	row.fade:SetSize(BANNER_W, TOP_H - 3)
	row.banner:Hide(); row.fade:Hide()

	-- the info band
	row.band = W.Texture(row, "solid", "ARTWORK", "ink2", 0.09)
	row.band:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -TOP_H)
	row.band:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
	row.bandLine = W.Texture(row, "solid", "ARTWORK", "line2", 0.7)
	row.bandLine:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -TOP_H)
	row.bandLine:SetPoint("TOPRIGHT", row, "TOPRIGHT", -3, -TOP_H)
	row.bandLine:SetHeight(1)

	row.emblem = createEmblemPlaceholder(row)
	row.name = text(row, "titleL", "ink", TEXT_X, 16, 440)
	row.sub = text(row, "body", "ink2", TEXT_X, 44, 440)
	row.sub:SetWordWrap(true)
	row.sub:SetMaxLines(2)
	row.sub:SetHeight(34)
	row.sub:SetJustifyV("TOP")
	row.tags = {}

	-- info band: members | days and time | wanted classes, then activities | requirement | age
	local y1, y2 = TOP_H + 9, TOP_H + 30
	row.members = text(row, "body", "ink", COL[1], y1, COL_W)
	row.activities = text(row, "body", "ink", COL[1], y2, COL_W)
	row.days = text(row, "body", "ink", COL[2], y1)
	row.time = W.Text(row, "mono", "ink2")
	row.time:SetPoint("LEFT", row.days, "RIGHT", 8, 0)
	row.reqIcon = W.Texture(row, "glyph_check", "OVERLAY", nil)
	row.reqIcon:SetSize(14, 14)
	row.reqIcon:SetPoint("TOPLEFT", row, "TOPLEFT", COL[2], -(y2 + 1))
	row.req = text(row, "body", "ink", COL[2], y2, COL_W)
	row.want = text(row, "caption", "ink2", COL[3], y1 + 1)
	row.want:SetWordWrap(false)
	row.classIcons = {}
	for i = 1, Model.MAX_CLASSES do
		local icon = W.ClassIcon(row, { class = "WARRIOR", size = 20 })
		icon:SetPoint("LEFT", i == 1 and row.want or row.classIcons[i - 1], "RIGHT", i == 1 and 10 or 9, 0)
		icon:EnableMouseWheel(true)
		icon:Hide()
		row.classIcons[i] = icon
	end
	row.more = W.Text(row, "caption", "ink3")
	row.updated = text(row, "caption", "ink3", COL[3], y2 + 1, COL_W)

	-- hover: a gold edge; the tooltip has the short description and the requirement
	row:SetScript("OnEnter", function(self) self.edge:SetHex("#d6a23a", 1) end)
	row:SetScript("OnLeave", function(self) self.edge:SetHex("#a06e3c", 0.45) end)
	row:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.card then Browse:OpenGuild(self.card.k) end
	end)
	row:SetScript("OnMouseWheel", function(_, delta) Browse:ScrollBy(-delta * Browse.WHEEL_STEP) end)
	W.SetTooltip(row, function() return row.tooltip end)
	Browse.rowsCreated = Browse.rowsCreated + 1
	return row
end

-- The tag at position i of a row (created when needed).
local function tagAt(row, i)
	local tag = row.tags[i]
	if not tag then
		tag = W.Tag(row, { text = "", kind = "default" })
		row.tags[i] = tag
	end
	return tag
end

-- Copies a card (Model.Card) into a row frame.
local function bindRow(row, card, index)
	row.index, row.card = index, card
	row.name:SetText(card.name)
	row.sub:SetText(card.sub or "")

	-- tags: languages, commitment, then the one note about the player, then "May be inactive"
	local specs = {}
	for _, code in ipairs(card.langs) do specs[#specs + 1] = { code, "default" } end
	if card.langsMore > 0 then specs[#specs + 1] = { "+" .. card.langsMore, "default" } end
	if card.paceText then specs[#specs + 1] = { card.paceText, card.paceKind } end
	if card.tag == "reqfail" then specs[#specs + 1] = { L["TAG_REQ_FAIL"], "bad" }
	elseif card.tag == "wantsyou" then specs[#specs + 1] = { L["TAG_WANTS_YOU"], "ok" } end
	if card.inactive then specs[#specs + 1] = { L["TAG_INACTIVE"], "gold" } end
	local x = TEXT_X
	for i, spec in ipairs(specs) do
		local tag = tagAt(row, i)
		tag:SetKind(spec[2])
		tag:SetText(spec[1])
		tag:ClearAllPoints()
		tag:SetPoint("TOPLEFT", row, "TOPLEFT", x, -92)
		tag:Show()
		x = x + tag:GetWidth() + 6
	end
	for i = #specs + 1, #row.tags do row.tags[i]:Hide() end

	-- banner (the art of the client by fileID; nothing is drawn when the fileID is not known)
	local file = ns.Assets.Banner(card.bg)
	if file then row.banner:SetTexture(file) end
	row.banner:SetShown(file ~= nil)
	row.fade:SetShown(file ~= nil)

	-- info band
	if card.active then
		row.members:SetText((card.members and L["INFO_ACTIVE_OF"] or L["INFO_ACTIVE"]):format(card.active, card.members))
	else
		row.members:SetText(L["INFO_MEMBERS_UNKNOWN"])
	end
	row.activities:SetText(card.activitiesText)
	row.days:SetText(card.daysText or "")
	row.time:SetText(card.timeText or "")
	row.time:ClearAllPoints()
	row.time:SetPoint("LEFT", row.days, "RIGHT", card.daysText and 8 or 0, 0)

	local req = card.req
	row.req:SetText(card.reqText)
	row.req:ClearAllPoints()
	if req.ok ~= nil and card.reqText ~= L["REQ_NONE"] then
		row.reqIcon:SetTexture(W.Media(req.ok and "glyph_check" or "glyph_close"))
		W.TintHex(row.reqIcon, req.ok and "#2e7d32" or "#b3261e")
		row.reqIcon:Show()
		row.req:SetPoint("LEFT", row.reqIcon, "RIGHT", 6, 0)
	else
		row.reqIcon:Hide()
		row.req:SetPoint("TOPLEFT", row, "TOPLEFT", COL[2], -(TOP_H + 30))
	end
	W.TextColor(row.req, req.ok == false and "bad" or "ink")

	for i, icon in ipairs(row.classIcons) do
		local c = card.classes[i]
		if c then icon:SetClass(c.file); icon:Show() else icon:Hide() end
	end
	row.want:SetText(#card.classes > 0 and L["WANT_LABEL"] or (card.anyClass and L["WANT_ANY"] or L["WANT_NONE"]))
	row.more:ClearAllPoints()
	if card.classesMore > 0 then
		row.more:SetPoint("LEFT", row.classIcons[#card.classes], "RIGHT", 9, 0)
		row.more:SetText("+" .. card.classesMore)
		row.more:Show()
	else
		row.more:Hide()
	end
	row.updated:SetText(card.updatedText or "")

	-- tooltip: the description of the summary, then the requirement
	local lines = {}
	if card.sub and card.sub ~= "" then lines[#lines + 1] = card.sub end
	lines[#lines + 1] = { text = card.reqText, color = req.ok == false and "bad" or "white" }
	row.tooltip = { title = card.name, lines = lines }
end

---------------------------------------------------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------------------------------------------------
local function buildLeft(host)
	Browse.left = host.left
	ns.FilterPanel.Build(host)   -- the filters (M2.6): they call Browse:SetFilter
end

local function buildHeader(host)
	local h = host.header
	local field = W.Field(h, { placeholder = L["BROWSE_SEARCH"], glyph = "glyph_search", width = 236, maxLetters = 40,
		onChange = function(value) Browse:OnSearchChanged(value) end,
		onEnter = function() Browse.debounce:Flush() end })
	field:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -9)
	host.hint = W.Text(h, "caption", "warn")
	host.hint:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 14, -1)
	host.count = W.Text(h, "titleS", "ink", "RIGHT")
	host.count:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -10)
	host.sorted = W.Text(h, "caption", "ink3", "RIGHT")
	host.sorted:SetPoint("TOPRIGHT", host.count, "BOTTOMRIGHT", 0, -2)
	host.sorted:SetText(L["BROWSE_SORTED"])
	host.search = field
end

local function buildScrollBar(host)
	local bar = CreateFrame("Slider", nil, host.content)
	bar:SetOrientation("VERTICAL")
	bar:SetPoint("TOPRIGHT", host.content, "TOPRIGHT", 0, -2)
	bar:SetPoint("BOTTOMRIGHT", host.content, "BOTTOMRIGHT", 0, 2)
	bar:SetWidth(BAR_W)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(false)
	bar.track = W.NineSlice(bar, "card", { corner = 5, layer = "BACKGROUND" })
	bar.track:SetHex("#b98a53", 0.35)
	bar:SetThumbTexture(W.Media("pill"))
	bar.thumb = bar:GetThumbTexture()
	bar.thumb:SetSize(BAR_W, 48)
	bar.thumb:SetVertexColor(Skin.Hex("#8c6844"))
	bar:SetScript("OnValueChanged", function(_, value)
		if not Browse.settingBar then Browse:SetOffset(value) end
	end)
	bar:Hide()
	host.bar = bar
end

local function buildStateBox(host)
	local box = CreateFrame("Frame", nil, host.content)
	box:SetSize(460, 190)
	box:SetPoint("CENTER", host.content, "CENTER", 0, 20)
	box:Hide()
	box.ring = W.Texture(box, "disc_ring", "ARTWORK", "line2")
	box.ring:SetSize(40, 40)
	box.ring:SetPoint("TOP", box, "TOP", 0, 0)
	box.dot = W.Texture(box, "disc", "OVERLAY", "gold2")
	box.dot:SetSize(9, 9)
	box.spin = CreateFrame("Frame", nil, box)   -- its OnUpdate runs only while the spinner shows
	local angle = 0
	box.spin:SetScript("OnUpdate", function(_, dt)
		angle = (angle - dt * 5) % 6.2832
		box.dot:ClearAllPoints()
		box.dot:SetPoint("CENTER", box.ring, "CENTER", 16 * cos(angle), 16 * sin(angle))
	end)
	box.message = W.Text(box, "bodyL", "ink2", "CENTER")
	box.message:SetWidth(440)
	box.message:SetWordWrap(true)
	box.reset = W.Button(box, { text = L["BROWSE_RESET"], kind = "primary", size = "md",
		onClick = function() Browse:ResetFilters() end })
	box.reset:SetPoint("TOP", box.message, "BOTTOM", 0, -16)
	box.reset:Hide()
	host.stateBox = box
end

local function buildContent(host)
	local list = CreateFrame("Frame", nil, host.content)
	list:SetPoint("TOPLEFT", host.content, "TOPLEFT", 0, 0)
	list:SetSize(CARD_W, VIEW_H)
	list:SetClipsChildren(true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta) Browse:ScrollBy(-delta * Browse.WHEEL_STEP) end)
	host.list = list
	buildScrollBar(host)
	buildStateBox(host)
end

local function build(host)
	Browse.host = host
	buildLeft(host)
	buildHeader(host)
	buildContent(host)
	Browse.debounce = Model.NewDebouncer(after, Model.DEBOUNCE, function(value) Browse:ApplySearch(value) end)
	Browse.coalescer = Model.NewCoalescer(after, Model.THROTTLE, function() Browse:OnCatalogChanged() end)
end

---------------------------------------------------------------------------------------------------------------------
-- Data, states and drawing
---------------------------------------------------------------------------------------------------------------------
function Browse:IsShown() return self.host ~= nil and self.host.shown == true end
function Browse:Selected() return self.data end

-- Rebuilds the list from the catalog (search and filters applied), decides the state and draws.
function Browse:Refresh()
	local host = self.host
	if not host or not ns.Catalog then return end
	self.dirty = false
	if self.prepareFilter then self.prepareFilter() end
	local query = Model.Query(self.search)
	local built = Model.Build(ns.Catalog, query, self.filter)
	local syncing, peers, lastSync = syncInfo()
	self.query, self.data, self.total = query, built.list, built.total
	self.state = Model.State({ total = built.total, shown = built.shown, query = query, filters = self.filters or 0,
		syncing = syncing, peers = peers })
	self.sig = self:Signature()
	self.player, self.now = Model.Player(), clock()
	self.zone = Model.LocalOffset(self.now)

	host.count:SetText(built.total > 0 and Model.CountText(built.shown, built.total, L) or "")
	host.hint:SetText(Model.HintText(self.state, L) or "")

	local msg = Model.StateText(self.state, query, L)
	local box, list = host.stateBox, host.list
	box:SetShown(msg ~= nil)
	list:SetShown(msg == nil)
	if msg then
		local loading = self.state.kind == "loading"
		box.ring:SetShown(loading)
		box.dot:SetShown(loading)
		box.spin:SetShown(loading)
		box.message:SetText(msg)
		box.message:ClearAllPoints()
		box.message:SetPoint("TOP", box, "TOP", 0, loading and -56 or -30)
		box.reset:SetShown(self.state.reset == true)
	end

	self.pool:Reset()
	self:SetOffset(self.offset, true)
	self:UpdateStatus()
end

-- What the status bar and the sync-dependent states depend on, as one value: when it changes the list is redrawn.
function Browse:Signature()
	local syncing, peers, lastSync = syncInfo()
	return (syncing and "1" or "0") .. (peers > 0 and "1" or "0") .. tostring(lastSync or 0)
end

function Browse:UpdateStatus()
	if not self:IsShown() then return end
	local syncing, _, lastSync = syncInfo()
	local textLine, level = Model.StatusLine({ total = self.total, syncing = syncing, lastSync = lastSync, now = clock() }, L)
	Main:SetStatus(textLine, level)
end

-- Draws the rows that are in view: binds, moves, shows and hides pooled frames.
function Browse:Layout()
	local host = self.host
	if not host then return end
	local count = #self.data
	local first, last = Model.Window(count, STEP, GAP, VIEW_H, self.offset)
	local show, hide = self.pool:Assign(first, last)
	for _, s in ipairs(show) do
		local row = self.rows[s.slot]
		if not row then
			row = createRow(host.list, s.slot)
			self.rows[s.slot] = row
		end
		if s.rebind then
			local sum = self.data[s.index]
			local entry, status = ns.Catalog:Get(sum.k)
			local info = { status = status, annAt = entry and entry.annAt }
			bindRow(row, Model.Card(sum, info, self.player, { now = self.now, offset = self.zone, L = L }), s.index)
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", host.list, "TOPLEFT", 0, -((s.index - 1) * STEP - self.offset))
		row:Show()
	end
	for _, slot in ipairs(hide) do
		local row = self.rows[slot]
		if row then row:Hide() end
	end
end

-- Scrolls to `value` px from the top (clamped) and redraws. `quiet`: do not move the bar's own value.
function Browse:SetOffset(value, quiet)
	local host = self.host
	if not host then return end
	local count = #self.data
	local maxOffset = Model.ScrollMax(count, STEP, GAP, VIEW_H)
	self.offset = Model.ClampOffset(value, count, STEP, GAP, VIEW_H)
	local bar = host.bar
	self.settingBar = true
	bar:SetMinMaxValues(0, maxOffset)
	bar:SetValue(self.offset)
	self.settingBar = false
	local content = Model.ContentHeight(count, STEP, GAP)
	bar.thumb:SetHeight(max(28, VIEW_H * (VIEW_H / max(content, VIEW_H))))
	bar:SetShown(maxOffset > 0 and self.state ~= nil and self.state.kind == "list")
	self:Layout()
end

function Browse:ScrollBy(delta) self:SetOffset(self.offset + delta) end
function Browse:ScrollToTop() self:SetOffset(0) end

---------------------------------------------------------------------------------------------------------------------
-- Search, filters, catalog changes
---------------------------------------------------------------------------------------------------------------------
-- The text of the search box changed: an empty box applies at once, anything else after the debounce.
function Browse:OnSearchChanged(value)
	if value == "" then
		self.debounce:Cancel()
		self:ApplySearch("")
	else
		self.debounce:Call(value)
	end
end

function Browse:ApplySearch(value)
	if value == self.search then return end
	self.search = value
	self.offset = 0
	if self:IsShown() then self:Refresh() else self.dirty = true end
end

-- The filters of M2.6 plug in here (see the header of this file).
-- `prepareFn` (optional) runs at the start of every rebuild of the list, before `fn` is called for the first listing.
function Browse:SetFilter(fn, activeCount, resetFn, prepareFn)
	self.filter, self.filters, self.resetFilters, self.prepareFilter = fn, activeCount or 0, resetFn, prepareFn
	self.offset = 0   -- a different list: back to its top
	self:RefreshNow()
end

function Browse:ResetFilters()
	if type(self.resetFilters) == "function" then self.resetFilters() end
	self:RefreshNow()
end

function Browse:RefreshNow()
	if self:IsShown() then self:Refresh() else self.dirty = true end
end

-- The Bus told that the catalog changed: rebuild at most once per THROTTLE seconds; not at all while hidden.
function Browse:OnCatalogChanged()
	if self:IsShown() then self:Refresh() else self.dirty = true end
end

function Browse:Touch()
	if self:IsShown() then self.coalescer:Request() else self.dirty = true end
end

-- Every POLL seconds while shown: the sync state (a request started, peers appeared, the clock of "synced 2 min ago").
function Browse:StartPoll()
	self.pollGen = (self.pollGen or 0) + 1
	local gen = self.pollGen
	local function tick()
		if gen ~= self.pollGen or not self:IsShown() then return end
		if self:Signature() ~= self.sig then self:Refresh() else self:UpdateStatus() end
		after(Browse.POLL, tick)
	end
	after(Browse.POLL, tick)
end

function Browse:StopPoll() self.pollGen = (self.pollGen or 0) + 1 end

---------------------------------------------------------------------------------------------------------------------
-- Opening a guild
---------------------------------------------------------------------------------------------------------------------
function Browse:OpenGuild(k)
	if Main.pages[Browse.GUILD_PAGE] then
		Main:Push(Browse.GUILD_PAGE, { k = k })
	else
		W.Snackbar.Show(L["BROWSE_GUILD_SOON"], { key = "guildsoon" })
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The page of the window
---------------------------------------------------------------------------------------------------------------------
Main:RegisterPage(Browse.PAGE, {
	Build = build,
	OnShow = function(host, _, entry)
		Browse.host = host
		local saved = entry and entry.state or {}
		-- a page that was left keeps what the player typed and where the list was (SPEC-04 §2: Back keeps the place)
		local search, offset = saved.search or "", saved.offset or 0
		if search ~= Browse.search or search ~= host.search:GetText() then
			Browse.debounce:Cancel()
			host.search:SetText(search, true)
			Browse.search = search
		end
		Browse.offset = offset
		Browse:Refresh()
		Browse:StartPoll()
	end,
	OnHide = function(host, entry)
		host.shown = false   -- first: what the debounce applies now only marks the list dirty, it is not redrawn
		Browse.debounce:Flush()
		if entry then entry.state = { search = Browse.search, offset = Browse.offset } end
		Browse.coalescer:Cancel()
		Browse.dirty = true
		Browse:StopPoll()
		Main:SetStatus("", nil)
	end,
})

---------------------------------------------------------------------------------------------------------------------
-- Wiring and diagnostics
---------------------------------------------------------------------------------------------------------------------
function Browse:DebugLines()
	local rows = 0
	for _ in pairs(self.rows) do rows = rows + 1 end
	return { ("List: %d shown of %d, %d row frames for a pool of %d (%d bound), scroll %d px, state %s"):format(
		#self.data, self.total, rows, POOL, self.pool.binds, floor(self.offset), self.state and self.state.kind or "-") }
end

if ns.Bus then
	ns.Bus:On("CATALOG_UPDATED", function() Browse:Touch() end)
	ns.Bus:On("CATALOG_SYNCED", function() Browse:Touch() end)
	ns.Bus:On("CHANNEL_READY", function() Browse:Touch() end)
end
if ns.addon then
	ns.addon.Browse = Browse
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("List", function() return Browse:DebugLines() end) end
end
