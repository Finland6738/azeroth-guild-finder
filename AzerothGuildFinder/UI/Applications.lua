-- Applications: the "Applications" tab of the Guild Master and the officers (SPEC-07 §5, mockup 04, M4.4). Lua 5.1.
--
--   Left page   the guild's emblem and name with "You are an officer", two counters (Pending, Accepted · 30 days), the
--               Pending (n) / History switch, the three notification options (read by the icon of M4.5) and a note that the
--               list is shared with the officers.
--   Right page  Pending: one card per application (class icon in its ring, the name in the class colour, the roles, level,
--               race, item level, how long ago, the status tag, Whisper, Decline, Invite); History: one line per closed
--               application with "by <officer> · date". Scrolled by the mouse wheel, one pool of row frames.
--   Invite      the game's guild invite through Data/Decisions.lua; the application becomes accepted only when the invite
--               went out without an error, otherwise the panel says why ("is offline"); with the invite API missing or
--               blocked the row falls back to "/ginvite Name" in the chat box and "Mark as invited".
--   Decline     asks first; the state changes, the other officers get it from the sync and the applicant at its next contact.
-- Everything that decides is in UI/ApplicationsModel.lua and Data/Decisions.lua. The tab exists only for the Guild Master and
-- the officers of a listed guild (Nav.TabsFor); the panel checks the role again every time it draws and before it acts.
local ADDON_NAME, ns = ...
ns = ns or {}
local Panel = {}
ns.AppsPanel, ns.modules = Panel, ns.modules or {}
ns.modules.AppsPanel = Panel

local L, Skin, W, Main, Model = ns.L, ns.Skin, ns.Widgets, ns.Main, ns.AppsModel
local type, ipairs, pairs, tostring, pcall = type, ipairs, pairs, tostring, pcall
local max, min = math.max, math.min

Panel.PAGE = "Applications"
Panel.PEND_VIEW, Panel.PEND_STEP, Panel.PEND_H = 6, 96, 86     -- pending cards in view, their pitch and height
Panel.HIST_VIEW, Panel.HIST_STEP = 14, 40                       -- history lines in view and their height
Panel.POLL = 60                                                 -- seconds between two redraws while the tab shows ("2 h ago")
local LW = 260   -- width of the left page's area

local function clock() return ns.Compat.ServerTime() end
local function after(seconds, fn) return ns.Compat.After(seconds, fn) end

-- The guild key of the player when this character may use the panel (Guild Master or officer), else nil.
function Panel:Key()
	local role = ns.Role and ns.Role:Get() or "none"
	if not Model.CanSee(role) then return nil, role end
	return ns.Role:GuildKey(), role
end

---------------------------------------------------------------------------------------------------------------------
-- State read by the model
---------------------------------------------------------------------------------------------------------------------
local function seenAt()
	local v = ns.Config and ns.Config:Get("char.ui.appsSeenAt")
	return type(v) == "number" and v or nil
end

function Panel:Context()
	local key, role = self:Key()
	local D = ns.Decisions
	local busy, manual = {}, {}
	local recs = key and ns.Inbox:List(key) or {}
	if D then
		for _, rec in ipairs(recs) do
			if D:IsBusy(rec.id) then busy[rec.id] = true end
			if D:IsManual(rec.id) then manual[rec.id] = true end
		end
	end
	return { role = role, key = key, recs = recs, now = clock(), tab = self.tab or "pending", seenAt = self.seenAtStart,
		busy = busy, manual = manual }
end

function Panel:View() return Model.View(self:Context(), L) end

-- Pending applications of the player's guild now (the tab's badge, the minimap tooltip).
function Panel:PendingCount()
	local key = self:Key()
	if not key then return 0 end
	return Model.Counters(ns.Inbox:List(key), clock()).pending
end

function Panel:UpdateBadge()
	if Main.SetBadge then Main:SetBadge(Panel.PAGE, self:PendingCount()) end
end

---------------------------------------------------------------------------------------------------------------------
-- Frames: the left page
---------------------------------------------------------------------------------------------------------------------
local function counter(parent, width)
	local card = W.Card(parent, { kind = "plain", width = width, height = 66 })
	card.number = W.Text(card, "headline", "ink", "CENTER")
	card.number:SetPoint("TOP", card, "TOP", 0, -8)
	card.number:SetWidth(width - 12)
	card.label = W.Text(card, "caption", "ink2", "CENTER")
	card.label:SetPoint("BOTTOM", card, "BOTTOM", 0, 8)
	card.label:SetWidth(width - 12)
	return card
end

-- The three notification switches; the same ones are in the Settings page (Main.lua builds them with this function too).
function Panel.BuildOptions(parent, width, anchor, startY)
	local switches = {}
	local y = startY or 0
	for _, option in ipairs(Model.OPTIONS) do
		local sw = W.Switch(parent, { label = L[option.label], width = width, checked = Model.GetOption(option.key),
			onChange = function(value, s)
				if not Model.SetOption(option.key, value) then s:SetChecked(not value, true) end
			end })
		sw:SetPoint("TOPLEFT", anchor or parent, anchor and "BOTTOMLEFT" or "TOPLEFT", 0, anchor and -y or -y)
		W.SetTooltip(sw, { title = L[option.label], lines = { L[option.help] } })
		switches[option.key] = sw
		anchor, y = sw, 6
	end
	function switches.Refresh()
		for _, option in ipairs(Model.OPTIONS) do switches[option.key]:SetChecked(Model.GetOption(option.key), true) end
	end
	return switches, anchor
end

local function buildLeft(host)
	local left = host.left
	host.plate = W.Plate(left, { text = L["TAB_Applications"], width = LW })
	host.plate:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)

	host.emblem = ns.Emblem.Create(left, 56)
	host.emblem:SetPoint("TOPLEFT", host.plate, "BOTTOMLEFT", 0, -14)
	host.guild = W.Text(left, "headline", "inkDeep")
	host.guild:SetPoint("TOPLEFT", host.emblem, "TOPRIGHT", 12, -2)
	host.guild:SetWidth(LW - 70)
	host.guild:SetWordWrap(false)
	host.roleLine = W.Text(left, "overline", "ink3")
	host.roleLine:SetPoint("TOPLEFT", host.guild, "BOTTOMLEFT", 0, -4)
	host.roleLine:SetWidth(LW - 70)

	local half = (LW - 10) / 2
	host.cPending = counter(left, half)
	host.cPending:SetPoint("TOPLEFT", host.emblem, "BOTTOMLEFT", 0, -16)
	host.cPending.label:SetText(L["APPS_COUNT_PENDING"])
	host.cAccepted = counter(left, half)
	host.cAccepted:SetPoint("LEFT", host.cPending, "RIGHT", 10, 0)
	host.cAccepted.label:SetText(L["APPS_COUNT_ACCEPTED"])

	host.showLabel = W.Text(left, "label", "ink")
	host.showLabel:SetPoint("TOPLEFT", host.cPending, "BOTTOMLEFT", 0, -16)
	host.showLabel:SetText(L["APPS_SHOW"])
	-- built wide enough for "Pending (99+)"; the real label is set on every draw
	host.seg = W.Segmented(left, {
		{ key = "pending", text = L["APPS_TAB_PENDING"]:format(99) },
		{ key = "history", text = L["APPS_TAB_HISTORY"] },
	}, { selected = "pending", onChange = function(key) Panel:SetTab(key) end })
	host.seg:SetPoint("TOPLEFT", host.showLabel, "BOTTOMLEFT", 0, -6)

	host.divider = W.Divider(left, LW)
	host.divider:SetPoint("TOPLEFT", host.seg, "BOTTOMLEFT", 0, -16)
	host.options, host.optionsLast = Panel.BuildOptions(left, LW, host.divider, 12)

	-- "Shared with officers"
	local card = W.Card(left, { kind = "plain", title = L["APPS_SHARED"], glyph = "glyph_shield", width = LW, height = 118 })
	card:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 0)
	card.text = W.Text(card.body, "caption", "ink2")
	card.text:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
	card.text:SetPoint("TOPRIGHT", card.body, "TOPRIGHT", 0, 0)
	card.text:SetWordWrap(true)
	card.text:SetText(L["APPS_SHARED_BODY"])
	host.shared = card
end

---------------------------------------------------------------------------------------------------------------------
-- Frames: the right page
---------------------------------------------------------------------------------------------------------------------
local function wheel(frame)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) Panel:ScrollBy(-delta) end)
end

local function pendingRow(host, index)
	local f = CreateFrame("Frame", nil, host.list)
	f:SetHeight(Panel.PEND_H)
	f:SetPoint("TOPLEFT", host.list, "TOPLEFT", 0, -(index - 1) * Panel.PEND_STEP)
	f:SetPoint("TOPRIGHT", host.list, "TOPRIGHT", 0, -(index - 1) * Panel.PEND_STEP)
	f.shadow = W.NineSlice(f, "shadow", { corner = 32, outset = 14, layer = "BACKGROUND", sublevel = -2 })
	f.shadow:SetColor(0.2, 0.1, 0, 0.3)
	f.bg = W.NineSlice(f, "card", { corner = 12, layer = "BACKGROUND" })
	f.bg:SetHex("#f9e8c6")
	f.edge = W.NineSlice(f, "card_edge", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	f.edge:SetHex("#a06e3c", 0.45)

	f.icon = W.ClassIcon(f, { size = 40 })
	f.icon:SetPoint("LEFT", f, "LEFT", 20, 0)
	f.name = W.Text(f, "titleM", "ink")
	f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 78, -14)
	f.name:SetWordWrap(false)
	f.new = W.Tag(f, { text = L["APPS_TAG_NEW"], kind = "gold" })
	f.badges = {}
	f.meta = W.Text(f, "body", "ink2")
	f.meta:SetPoint("TOPLEFT", f, "TOPLEFT", 78, -42)
	f.meta:SetWordWrap(false)
	f.tag = W.Tag(f, { text = "", kind = "ok" })
	f.tag:SetPoint("LEFT", f.meta, "RIGHT", 12, 0)

	f.invite = W.Button(f, { text = L["APPS_INVITE"], kind = "primary", size = "sm",
		onClick = function() Panel:Invite(f.id) end })
	f.invite:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	f.decline = W.Button(f, { text = L["APPS_DECLINE"], kind = "tonal", size = "sm", tooltip = L["APPS_DECLINE_TIP"],
		onClick = function() Panel:AskDecline(f.id) end })
	f.decline:SetPoint("RIGHT", f.invite, "LEFT", -8, 0)
	f.whisper = W.Button(f, { text = L["APPS_WHISPER"], kind = "ghost", size = "sm", tooltip = L["APPS_WHISPER_TIP"],
		onClick = function() Panel:Whisper(f.id) end })
	f.whisper:SetPoint("RIGHT", f.decline, "LEFT", -4, 0)
	f.invite.tooltipTitle = L["APPS_INVITE"]
	for _, w in ipairs({ f, f.invite, f.decline, f.whisper, f.icon }) do wheel(w) end
	f:Hide()
	return f
end

local function historyRow(host, index)
	local f = CreateFrame("Frame", nil, host.histCard)
	f:SetHeight(Panel.HIST_STEP)
	f:SetPoint("TOPLEFT", host.histCard, "TOPLEFT", 10, -6 - (index - 1) * Panel.HIST_STEP)
	f:SetPoint("TOPRIGHT", host.histCard, "TOPRIGHT", -10, -6 - (index - 1) * Panel.HIST_STEP)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetTexture(W.Media("solid"))
	f.line:SetVertexColor(Skin.Color("line", 0.7))
	f.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	f.line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.line:SetHeight(1)
	f.icon = W.ClassIcon(f, { size = 22 })
	f.icon:SetPoint("LEFT", f, "LEFT", 6, 0)
	f.text = W.Text(f, "body", "ink")
	f.text:SetPoint("LEFT", f, "LEFT", 44, 0)
	f.text:SetWidth(250)
	f.text:SetWordWrap(false)
	f.tag = W.Tag(f, { text = "", kind = "ok" })
	f.tag:SetPoint("LEFT", f, "LEFT", 304, 0)
	f.by = W.Text(f, "caption", "ink2")
	f.by:SetPoint("LEFT", f, "LEFT", 456, 0)
	f.by:SetWidth(260)
	f.by:SetWordWrap(false)
	f.whisper = W.Button(f, { text = L["APPS_WHISPER"], kind = "ghost", size = "sm", tooltip = L["APPS_WHISPER_TIP"],
		onClick = function() Panel:Whisper(f.id) end })
	f.whisper:SetPoint("RIGHT", f, "RIGHT", -2, 0)
	for _, w in ipairs({ f, f.whisper, f.icon }) do wheel(w) end
	f:Hide()
	return f
end

local function buildContent(host)
	local content = host.content
	host.list = CreateFrame("Frame", nil, content)
	host.list:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	host.list:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
	wheel(host.list)
	wheel(content)
	host.pendRows, host.histRows = {}, {}
	for i = 1, Panel.PEND_VIEW do host.pendRows[i] = pendingRow(host, i) end
	host.histCard = W.Card(host.list, { kind = "plain", height = Panel.HIST_VIEW * Panel.HIST_STEP + 12 })
	host.histCard:SetPoint("TOPLEFT", host.list, "TOPLEFT", 0, 0)
	host.histCard:SetPoint("TOPRIGHT", host.list, "TOPRIGHT", 0, 0)
	for i = 1, Panel.HIST_VIEW do host.histRows[i] = historyRow(host, i) end
	wheel(host.histCard)

	host.foot = W.Text(content, "caption", "ink3", "CENTER")
	host.foot:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
	host.foot:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

	-- the empty state
	local e = CreateFrame("Frame", nil, content)
	e:SetAllPoints(content)
	e.title = W.Text(e, "titleL", "ink", "CENTER")
	e.title:SetPoint("TOP", e, "TOP", 0, -170)
	e.title:SetWidth(520)
	e.body = W.Text(e, "body", "ink2", "CENTER")
	e.body:SetPoint("TOP", e.title, "BOTTOM", 0, -10)
	e.body:SetWidth(520)
	e.body:SetWordWrap(true)
	e:Hide()
	host.empty = e

	-- the caption in the title bar, at the right
	host.expiry = W.Text(host.header, "caption", "ink2", "RIGHT")
	host.expiry:SetPoint("RIGHT", host.header, "RIGHT", 0, 0)

	-- the question before Decline
	local c = CreateFrame("Frame", nil, content)
	c:SetSize(460, 130)
	c:SetPoint("CENTER", content, "CENTER", 0, 20)
	c:SetFrameLevel(content:GetFrameLevel() + 30)
	c:EnableMouse(true)
	c.bg = W.NineSlice(c, "card", { corner = 12, layer = "BACKGROUND" })
	c.bg:SetHex("#fbe9c5")
	c.edge = W.NineSlice(c, "card_edge", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	c.edge:SetHex("#b8820f")
	c.text = W.Text(c, "body", "ink")
	c.text:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -16)
	c.text:SetWidth(428)
	c.text:SetWordWrap(true)
	c.yes = W.Button(c, { text = L["APPS_DECLINE"], kind = "primary", size = "sm", onClick = function() Panel:Answer(true) end })
	c.yes:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 16, 16)
	c.no = W.Button(c, { text = L["ED_CANCEL"], kind = "tonal", size = "sm", onClick = function() Panel:Answer(false) end })
	c.no:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -16, 16)
	c:Hide()
	host.confirm = c
end

local function build(host)
	Panel.host = host
	buildLeft(host)
	buildContent(host)
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
function Panel:IsShown() return self.host ~= nil and self.host.shown == true end

-- The name in the colour of its class, darkened for the parchment (the white of a Priest reads grey, as in the mockup).
local function paintName(fs, cls)
	local r, g, b = ns.Assets.ClassColor(cls)
	fs:SetTextColor(r * 0.62, g * 0.62, b * 0.62, 1)
end

local function bindPending(f, row, index)
	f.id = row.id
	f.icon:SetClass(row.cls)
	f.name:SetText(row.name)
	paintName(f.name, row.cls)
	f.edge:SetHex(row.new and "#f2bf3c" or "#a06e3c", row.new and 1 or 0.45)
	f.new:ClearAllPoints()
	f.new:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
	f.new:SetShown(row.new == true)
	local anchor = row.new and f.new or f.name
	for i = 1, max(#row.roles, #f.badges) do
		if i <= #row.roles then
			if not f.badges[i] then f.badges[i] = W.RoleBadge(f, { size = 20 }) end
			local b = f.badges[i]
			b:SetRole(row.roles[i].key)
			b:ClearAllPoints()
			b:SetPoint("LEFT", i == 1 and anchor or f.badges[i - 1], "RIGHT", i == 1 and 10 or 4, 0)
			b:Show()
		elseif f.badges[i] then
			f.badges[i]:Hide()
		end
	end
	f.meta:SetText(row.classLine .. "  ·  " .. row.ilvlText .. "  ·  " .. row.ageText)
	f.tag:SetText(row.status.text)
	f.tag:SetKind(row.status.kind)
	f.invite:SetLabel(row.actions.invite.label)
	f.invite:SetEnabled(row.actions.invite.enabled)
	f.invite.tooltipTitle = row.actions.invite.label
	W.SetTooltip(f.invite, { title = row.actions.invite.label, lines = { row.actions.invite.tip } })
	f.decline:SetEnabled(row.actions.decline.enabled)
	f.whisper:SetEnabled(row.actions.whisper.enabled)
	f:Show()
end

local function bindHistory(f, row)
	f.id = row.id
	f.icon:SetClass(row.cls)
	f.icon:SetShown(row.cls ~= nil)
	f.text:SetText(row.historyLine)
	f.tag:SetText(row.status.text)
	f.tag:SetKind(row.status.kind)
	f.by:SetText(row.byText or "")
	f.whisper:SetEnabled(row.actions.whisper.enabled)
	f:Show()
end

function Panel:Refresh()
	local host = self.host
	if not host or not host.shown or self.refreshing then return end
	self.refreshing = true
	local ok, view = pcall(self.View, self)
	self.refreshing = false
	if not ok then return geterrorhandler()(view) end
	self.view = view
	local key = self:Key()
	local _, _, guildName
	if key then _, _, guildName = ns.Listing.ParseKey(key) end
	local entry = key and ns.Catalog and ns.Catalog:Get(key)
	host.emblem:SetEmblem(entry and entry.sum and entry.sum.emb or nil, guildName)
	host.guild:SetText(guildName or "")
	local role = ns.Role and ns.Role:Get() or "none"
	host.roleLine:SetText(role == "gm" and L["APPS_ROLE_GM"] or (role == "officer" and L["APPS_ROLE_OFFICER"] or ""))
	host.cPending.number:SetText(tostring(view.counters.pending))
	host.cAccepted.number:SetText(tostring(view.counters.accepted))
	host.seg.segments.pending.text:SetText(view.pendingLabel)
	host.seg.segments.history.text:SetText(view.historyLabel)
	host.seg:SetSelected(view.tab, true)
	host.expiry:SetText(view.caption)
	Main:SetTitle(view.title)
	host.shared:SetShown(view.visible)

	local history = view.tab == "history"
	local size = history and Panel.HIST_VIEW or Panel.PEND_VIEW
	local page = Model.Page(view.total, self.offset or 0, size)
	self.offset = page.offset
	self.page = page
	host.empty:SetShown(view.empty ~= nil)
	if view.empty then
		host.empty.title:SetText(view.empty.title)
		host.empty.body:SetText(view.empty.body)
	end
	host.histCard:SetShown(history and view.total > 0)
	for i = 1, Panel.PEND_VIEW do
		local row = (not history) and view.rows[page.offset + i] or nil
		if row then bindPending(host.pendRows[i], row, i) else host.pendRows[i]:Hide() end
	end
	for i = 1, Panel.HIST_VIEW do
		local row = history and view.rows[page.offset + i] or nil
		if row then bindHistory(host.histRows[i], row) else host.histRows[i]:Hide() end
	end
	if view.total > size then
		host.foot:SetText(L["APPS_SCROLL"]:format(page.first, page.last, view.total))
	else
		host.foot:SetText("")
	end
	if not view.visible then host.confirm:Hide() end
	host.options.Refresh()
	if view.visible then
		local c = view.counters
		Main:SetStatus(L["APPS_STATUS"]:format(c.pending), c.pending > 0 and "ok" or "off")
	else
		Main:SetStatus("", nil)
	end
	self:UpdateBadge()
	return view
end

function Panel:SetTab(tab)
	if tab ~= "pending" and tab ~= "history" then return false end
	self.tab = tab
	self.offset = 0
	if self.host then self.host.confirm:Hide() end
	self:Refresh()
	return true
end

function Panel:ScrollBy(rows)
	if not self.view then return end
	local step = (self.view.tab == "history") and 3 or 1
	self.offset = max(0, (self.offset or 0) + rows * step)
	self:Refresh()
end

function Panel:StartPoll()
	if self.polling then return end
	self.polling = true
	self.pollGen = (self.pollGen or 0) + 1
	local gen = self.pollGen
	local function tick()
		if gen ~= self.pollGen or not self.polling then return end
		if not self:IsShown() then self.polling = false return end
		self:Refresh()
		if gen == self.pollGen and self.polling then after(Panel.POLL, tick) end
	end
	after(Panel.POLL, tick)
end

function Panel:StopPoll()
	self.polling = false
	self.pollGen = (self.pollGen or 0) + 1
end

---------------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------------
local function say(text) W.Snackbar.Show(text, { key = "apps" }) end

local function nameOfRec(id)
	local key = Panel:Key()
	local rec = key and ns.Inbox:Get(key, id)
	if not rec or type(rec.who) ~= "string" then return "?" end
	return rec.who:match("^[^%-]+") or rec.who
end

-- The words for a failed attempt (Decisions returns false and why).
local function explain(why)
	if why == "role" then return L["APPS_ERR_ROLE"] end
	if why == "busy" then return L["APPS_ERR_BUSY"] end
	return L["APPS_ERR_CHANGED"]
end

-- Invite: the game's invite (or the fallback's "Mark as invited"). The words come back on the Bus (DECISION_RESULT).
function Panel:Invite(id)
	local key = self:Key()
	if not key then return false, "role" end
	local D = ns.Decisions
	if D:IsManual(id) then
		local ok, why = D:MarkInvited(key, id)
		if not ok then say(explain(why)) end
		self:Refresh()
		return ok, why
	end
	local ok, why = D:Invite(key, id)
	if not ok then say(explain(why)) end
	self:Refresh()
	return ok, why
end

function Panel:Whisper(id)
	local key = self:Key()
	local rec = key and ns.Inbox:Get(key, id)
	if not rec then return false end
	local ok = ns.Compat.Chat.OpenWhisper(rec.who)
	if not ok then say(L["APPS_WHISPER_FAILED"]) end
	return ok
end

function Panel:AskDecline(id)
	local host = self.host
	local key = self:Key()
	if not host or not key then return false end
	local rec = ns.Inbox:Get(key, id)
	if not rec or not ns.Applications.IsOpen(rec) then return false end
	self.declining = id
	host.confirm.text:SetText(L["APPS_DECLINE_CONFIRM"]:format(nameOfRec(id)))
	host.confirm:Show()
	return true
end

-- true declines the application the question was about; false only closes the question.
function Panel:Answer(yes)
	local host = self.host
	if not host then return false end
	host.confirm:Hide()
	local id = self.declining
	self.declining = nil
	if not yes or not id then return false end
	local key = self:Key()
	if not key then return false, "role" end
	local name = nameOfRec(id)
	local ok, why = ns.Decisions:Decline(key, id)
	if not ok then say(explain(why)) else say(L["APPS_DECLINED_SNACK"]:format(name)) end
	self:Refresh()
	return ok, why
end

-- What the game answered to an invite (Data/Decisions.lua): the words of the snackbar.
function Panel:OnResult(k, id, result, detail)
	if result == "declined" then return end   -- Answer() says it
	local name = nameOfRec(id)
	if result == "accepted" then say(L["APPS_INVITED_SNACK"]:format(name))
	elseif result == "offline" then say(L["APPS_OFFLINE_SNACK"]:format(name))
	elseif result == "refused" then say(L["APPS_REFUSED_SNACK"]:format(name, tostring(detail or "")))
	elseif result == "manual" then say(L[detail == "chat" and "APPS_MANUAL_CHAT" or "APPS_MANUAL_HAND"]:format(name))
	elseif result == "changed" then say(L["APPS_ERR_CHANGED"]) end
	if self:IsShown() then self:Refresh() end
end

---------------------------------------------------------------------------------------------------------------------
-- The page of the window
---------------------------------------------------------------------------------------------------------------------
Main:RegisterPage(Panel.PAGE, {
	title = function() return L["APPS_TITLE_PENDING"] end,
	Build = build,
	OnShow = function(host)
		Panel.host = host
		host.confirm:Hide()
		Panel.seenAtStart = seenAt()
		Panel.offset = 0
		Panel:Refresh()
		Panel:StartPoll()
	end,
	OnHide = function(host)
		host.confirm:Hide()
		Panel:StopPoll()
		-- what the officer has now seen is no longer new
		if ns.Config and Panel:Key() then ns.Config:Set("char.ui.appsSeenAt", clock()) end
		host.shown = false
		W.HideTooltip()
	end,
})

-- The number on the rail and in the minimap tooltip.
Main.pendingProvider = function() return Panel:PendingCount() end

if ns.Bus then
	local function redraw()
		Panel:UpdateBadge()
		if Panel:IsShown() then Panel:Refresh() end
	end
	ns.Bus:On("INBOX_CHANGED", redraw)
	ns.Bus:On("INBOX_CLEARED", redraw)
	ns.Bus:On("ROLE_CHANGED", redraw)
	ns.Bus:On("DECISION_STARTED", redraw)
	ns.Bus:On("DECISION_RESULT", function(...) Panel:OnResult(...) end)
end

function Panel:DebugLines()
	local key, role = self:Key()
	local c = key and Model.Counters(ns.Inbox:List(key), clock()) or { pending = 0, history = 0 }
	return { ("Applications panel: role %s, %s, %d pending, %d in the history, tab %s"):format(role,
		key and "your guild" or "no panel", c.pending, c.history, self.tab or "pending") }
end

if ns.addon then
	ns.addon.AppsPanel = Panel
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Applications panel", function() return Panel:DebugLines() end) end
end
