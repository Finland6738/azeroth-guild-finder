-- Notify: the floating notification icon of the Guild Master and the officers (SPEC-07 §6, mockup 05). Lua 5.1.
--   a round metal button with the guild emblem and a red badge (the pending applications); it pulses once when an
--   application arrives; left click opens the quick list (the last 5 with Invite and Decline and "Open all applications");
--   drag moves it (the position is saved per character, "Lock position" stops it); right click opens a small menu;
--   a chat line "New application from Elarin (Mage 32). [Open]" and an optional sound come with every new application;
--   /gf notify shows or hides it. All the decisions (who sees it, what the badge says, what the list holds) are in
--   UI/NotifyModel.lua; Invite and Decline are the ones of the panel (Data/Decisions.lua).
local ADDON_NAME, ns = ...
ns = ns or {}
local Notify = {}
ns.Notify, ns.modules = Notify, ns.modules or {}
ns.modules.Notify = Notify

local L, W, Model = ns.L, ns.Widgets, ns.NotifyModel
local AppsModel = ns.AppsModel
local type, ipairs, pcall, tostring = type, ipairs, pcall, tostring

Notify.NAME = "AzerothGuildFinderNotify"
Notify.POLL = 60                 -- seconds between two checks of the count (an application can expire)
Notify.PULSE = 1.4               -- seconds the glow lasts
Notify.ROW_H, Notify.ROW_STEP = 54, 60
Notify.LIST_W = 380
Notify.SOUND_FALLBACK = 8960     -- READY_CHECK in the sound kit table; the client ignores an unknown id

local function clock() return ns.Compat.ServerTime() end
local function after(seconds, fn) return ns.Compat.After(seconds, fn) end
local function say(text) if ns.addon and ns.addon.Print then ns.addon:Print(text) end end

---------------------------------------------------------------------------------------------------------------------
-- State read by the model
---------------------------------------------------------------------------------------------------------------------
-- The guild key when this character may use the icon (Guild Master or officer), else nil.
function Notify:Key()
	local role = ns.Role and ns.Role:Get() or "none"
	if not AppsModel.CanSee(role) then return nil, role end
	return ns.Role:GuildKey(), role
end

function Notify:Recs()
	local key = self:Key()
	return key and ns.Inbox:List(key) or {}
end

function Notify:Pending()
	local key = self:Key()
	if not key then return 0 end
	return AppsModel.Counters(ns.Inbox:List(key), clock()).pending
end

function Notify:Locked()
	return ns.Config ~= nil and ns.Config:Get("char.ui.notifyLocked") == true
end

function Notify:Available()
	local key, role = self:Key()
	local listed = ns.Main and ns.Main.HasListing and ns.Main.HasListing() or false
	return key ~= nil and listed, role
end

-- Should the icon be on screen now?
function Notify:ShouldShow()
	local key, role = self:Key()
	local listed = ns.Main and ns.Main.HasListing and ns.Main.HasListing() or false
	return Model.Visible({ role = role, key = key, listed = listed, enabled = AppsModel.GetOption("notifyIcon"),
		onlyWhenPending = AppsModel.GetOption("onlyWhenPending"), pending = self:Pending() })
end

---------------------------------------------------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------------------------------------------------
local function disc(parent, media, layer, token, inset)
	local t = W.Texture(parent, media, layer, token)
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
	t:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
	return t
end

function Notify:Create()
	if self.frame then return self.frame end
	local size = Model.SIZE
	local f = CreateFrame("Button", Notify.NAME, UIParent)
	f:SetSize(size, size)
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:Hide()
	f.shadow = W.Texture(f, "disc", "BACKGROUND", nil)
	f.shadow:SetVertexColor(0, 0, 0, 0.5)
	f.shadow:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 1)
	f.shadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -6)
	f.glow = W.Texture(f, "disc", "BACKGROUND", "gold", 0.55)
	f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -12, 12)
	f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 12, -12)
	f.glow:Hide()
	f.gold = disc(f, "disc", "BACKGROUND", "gold", 0)
	f.iron = disc(f, "disc_shiny", "ARTWORK", "iron", 3)
	f.ring = W.Texture(f, "disc_ring", "ARTWORK", nil)
	f.ring:SetVertexColor(0.17, 0.11, 0.02, 1)
	f.ring:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
	f.ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
	f.emblem = ns.Emblem.Create(f, 40)
	f.emblem:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.hover = disc(f, "disc", "OVERLAY", nil, 3)
	f.hover:SetVertexColor(1, 1, 1, 0.16)
	f.hover:Hide()
	f.badge = W.Badge(f, { count = 0 })
	f.badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", 6, 4)
	f.badge:SetFrameLevel(f:GetFrameLevel() + 5)

	f:SetScript("OnDragStart", function(self)
		if Notify:Locked() then return end
		Notify:CloseAll()
		Notify.dragging = true
		self:StartMoving()
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if Notify.dragging then Notify:SavePosition() end
		Notify.dragging = false
		Notify.justDragged = true
		after(0.2, function() Notify.justDragged = false end)
	end)
	f:SetScript("OnClick", function(_, button)
		if Notify.justDragged then return end
		if button == "RightButton" then Notify:ToggleMenu() else Notify:ToggleList() end
	end)
	f:SetScript("OnEnter", function(self) self.hover:Show() end)
	f:SetScript("OnLeave", function(self) self.hover:Hide() end)
	f:SetScript("OnUpdate", function(self, dt) Notify:OnUpdate(dt) end)
	W.SetTooltip(f, function() return Notify:Tooltip() end)
	self.frame = f
	self:ApplyPosition()
	return f
end

function Notify:Tooltip()
	local n = self:Pending()
	return { title = L["NOTIFY_TIP_TITLE"], lines = { n > 0 and L["NOTIFY_TIP_PENDING"]:format(n) or L["NOTIFY_TIP_NONE"],
		L["NOTIFY_TIP_LEFT"], L["NOTIFY_TIP_RIGHT"] } }
end

---------------------------------------------------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------------------------------------------------
function Notify:ApplyPosition()
	local f = self.frame
	if not f then return end
	local pos = ns.Config and ns.Config:Get("char.ui.notifyPos")
	pos = Model.Clamp(pos, Model.SIZE, UIParent:GetWidth(), UIParent:GetHeight())
	local point, relPoint, x, y = Model.FromSaved(pos)
	f:ClearAllPoints()
	f:SetPoint(point, UIParent, relPoint, x, y)
end

function Notify:SavePosition()
	local f = self.frame
	if not f or not ns.Config then return end
	local point, _, relPoint, x, y = f:GetPoint(1)
	local saved = Model.ToSaved(point, relPoint, x, y)
	if saved then ns.Config:Set("char.ui.notifyPos", saved) end
	return saved
end

function Notify:ResetPosition()
	if ns.Config then ns.Config:Set("char.ui.notifyPos", nil) end
	self:ApplyPosition()
end

function Notify:SetLocked(locked)
	if ns.Config then ns.Config:Set("char.ui.notifyLocked", locked and true or false) end
	return self:Locked()
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
function Notify:OnUpdate(dt)
	local t = self.pulseT
	if not t then return end
	t = t + (dt or 0)
	local f = self.frame
	if t >= Notify.PULSE then
		self.pulseT = nil
		if f then f.glow:Hide() end
		return
	end
	local phase = t / Notify.PULSE
	if f then f.glow:SetAlpha(0.7 * (1 - phase)) end
	self.pulseT = t
end

-- One pulse of the glow: a new application.
function Notify:Pulse()
	local f = self.frame
	if not f or not f:IsShown() then return false end
	self.pulseT = 0
	f.glow:SetAlpha(0.7)
	f.glow:Show()
	return true
end

function Notify:Refresh()
	local show = self:ShouldShow()
	if show then
		local f = self:Create()
		local count = self:Pending()
		self.count = count
		f.badge:SetCount(count)
		local key = self:Key()
		local entry = key and ns.Catalog and ns.Catalog:Get(key)
		local name
		if key then name = select(3, ns.Listing.ParseKey(key)) end
		f.emblem:SetEmblem(entry and entry.sum and entry.sum.emb or nil, name)
		f:Show()
		self:EnsurePoll()
		if self.list and self.list:IsShown() then self:RefreshList() end
	else
		self.count = 0
		self:CloseAll()
		if self.frame then self.frame:Hide() end
	end
	return show
end

function Notify:IsShown() return self.frame ~= nil and self.frame:IsShown() end

---------------------------------------------------------------------------------------------------------------------
-- The quick list
---------------------------------------------------------------------------------------------------------------------
local function listRow(list, index)
	local f = CreateFrame("Frame", nil, list)
	f:SetHeight(Notify.ROW_H)
	f:SetPoint("TOPLEFT", list, "TOPLEFT", 14, -(48 + (index - 1) * Notify.ROW_STEP))
	f:SetPoint("TOPRIGHT", list, "TOPRIGHT", -14, -(48 + (index - 1) * Notify.ROW_STEP))
	f.bg = W.NineSlice(f, "card", { corner = 12, layer = "BACKGROUND" })
	f.bg:SetHex("#f9e8c6")
	f.edge = W.NineSlice(f, "card_edge", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	f.edge:SetHex("#a06e3c", 0.45)
	f.icon = W.ClassIcon(f, { size = 30 })
	f.icon:SetPoint("LEFT", f, "LEFT", 10, 0)
	f.name = W.Text(f, "titleM", "ink")
	f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -9)
	f.name:SetWidth(130)
	f.name:SetWordWrap(false)
	f.meta = W.Text(f, "caption", "ink2")
	f.meta:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -2)
	f.meta:SetWidth(130)
	f.meta:SetWordWrap(false)
	f.invite = W.Button(f, { text = L["APPS_INVITE"], kind = "primary", size = "sm", onClick = function() Notify:Invite(f.id) end })
	f.invite:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.decline = W.Button(f, { text = L["APPS_DECLINE"], kind = "tonal", size = "sm", onClick = function() Notify:AskDecline(f.id) end })
	f.decline:SetPoint("RIGHT", f.invite, "LEFT", -6, 0)
	f:Hide()
	return f
end

function Notify:CreateList()
	if self.list then return self.list end
	local list = CreateFrame("Frame", Notify.NAME .. "List", UIParent)
	list:SetSize(Notify.LIST_W, 120)
	list:SetFrameStrata("DIALOG")
	list:EnableMouse(true)
	list:Hide()
	list.shadow = W.NineSlice(list, "shadow", { corner = 32, outset = 22, layer = "BACKGROUND", sublevel = -2 })
	list.shadow:SetColor(0, 0, 0, 0.55)
	list.rim = W.NineSlice(list, "card", { corner = 14, layer = "BACKGROUND", outset = 2 })
	list.rim:SetHex("#8a939b")
	list.bg = W.NineSlice(list, "card", { corner = 14, layer = "BACKGROUND", sublevel = 1 })
	list.bg:SetTint("parchHi")
	list.title = W.Text(list, "titleM", "ink")
	list.title:SetPoint("TOPLEFT", list, "TOPLEFT", 16, -14)
	list.guild = W.Text(list, "caption", "ink2", "RIGHT")
	list.guild:SetPoint("TOPRIGHT", list, "TOPRIGHT", -44, -17)
	list.close = W.CloseButton(list, function() Notify:CloseList() end)
	list.close:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -8)
	list.rows = {}
	for i = 1, Model.QUICK_MAX do list.rows[i] = listRow(list, i) end
	list.empty = W.Text(list, "body", "ink2", "CENTER")
	list.more = W.Text(list, "caption", "ink2")
	list.confirm = W.Text(list, "body", "ink")
	list.confirm:Hide()
	list.yes = W.Button(list, { text = L["NOTIFY_DECLINE_YES"], kind = "primary", size = "sm", onClick = function() Notify:Answer(true) end })
	list.no = W.Button(list, { text = L["NOTIFY_DECLINE_NO"], kind = "tonal", size = "sm", onClick = function() Notify:Answer(false) end })
	list.yes:Hide(); list.no:Hide()
	list.open = W.Button(list, { text = L["NOTIFY_OPEN_ALL"], kind = "ghost", size = "md", onClick = function() Notify:OpenPanel() end })
	list:SetScript("OnHide", function() Notify.declining = nil end)
	if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = Notify.NAME .. "List" end
	self.list = list
	return list
end

function Notify:ListView()
	local key = self:Key()
	local _, _, guild
	if key then _, _, guild = ns.Listing.ParseKey(key) end
	local busy = {}
	if key and ns.Decisions then
		for _, rec in ipairs(ns.Inbox:List(key)) do if ns.Decisions:IsBusy(rec.id) then busy[rec.id] = true end end
	end
	return Model.Quick({ recs = self:Recs(), now = clock(), busy = busy, guild = guild }, L)
end

local function paintName(fs, cls)
	local r, g, b = ns.Assets.ClassColor(cls)
	fs:SetTextColor(r, g, b)
end

function Notify:RefreshList()
	local list = self.list
	if not list then return end
	local view = self:ListView()
	self.view = view
	list.title:SetText(view.title)
	list.guild:SetText(view.guild or "")
	for i, f in ipairs(list.rows) do
		local row = view.rows[i]
		if row then
			f.id = row.id
			f.icon:SetClass(row.cls)
			f.icon:SetShown(row.cls ~= nil)
			f.name:SetText(row.name)
			paintName(f.name, row.cls)
			f.meta:SetText(row.line or "")
			f.invite:SetLabel(row.actions.invite.label)
			f.invite:SetEnabled(row.actions.invite.enabled)
			f.decline:SetEnabled(row.actions.decline.enabled)
			f:Show()
		else
			f.id = nil
			f:Hide()
		end
	end
	local shown = #view.rows
	local y = 48 + shown * Notify.ROW_STEP
	list.empty:ClearAllPoints()
	list.more:ClearAllPoints()
	list.empty:SetShown(view.empty ~= nil)
	if view.empty then
		list.empty:SetPoint("TOP", list, "TOP", 0, -56)
		list.empty:SetText(view.empty)
		y = 90
	end
	list.more:SetShown(view.moreText ~= nil)
	if view.moreText then
		list.more:SetPoint("TOPLEFT", list, "TOPLEFT", 18, -(y + 2))
		list.more:SetText(view.moreText)
	end
	local asking = self.declining ~= nil
	list.confirm:SetShown(asking)
	list.yes:SetShown(asking)
	list.no:SetShown(asking)
	list.open:ClearAllPoints()
	if asking then
		list.confirm:ClearAllPoints()
		list.confirm:SetPoint("TOPLEFT", list, "TOPLEFT", 18, -(y + 8))
		list.confirm:SetText(L["NOTIFY_DECLINE_ASK"]:format(self:NameOf(self.declining)))
		list.no:ClearAllPoints()
		list.no:SetPoint("TOPRIGHT", list, "TOPRIGHT", -16, -(y + 28))
		list.yes:ClearAllPoints()
		list.yes:SetPoint("RIGHT", list.no, "LEFT", -8, 0)
		list.open:SetPoint("TOPRIGHT", list, "TOPRIGHT", -12, -(y + 66))
		list:SetHeight(y + 108)
	else
		list.open:SetPoint("TOPRIGHT", list, "TOPRIGHT", -12, -(y + 14))
		list:SetHeight(y + 58)
	end
end

-- The list opens below the icon when the icon is in the upper half of the screen, above it otherwise.
function Notify:PlaceList()
	local f, list = self.frame, self.list
	if not f or not list then return end
	local _, cy = f:GetCenter()
	local upper = (cy or 0) > UIParent:GetHeight() / 2
	list:ClearAllPoints()
	if upper then list:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 8, -10) else list:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 8, 10) end
end

function Notify:ShowList()
	if not self:IsShown() then return false end
	self:CloseMenu()
	local list = self:CreateList()
	self.declining = nil
	self:RefreshList()
	self:PlaceList()
	list:Show()
	return true
end

function Notify:CloseList()
	if self.list then self.list:Hide() end
	self.declining = nil
end

function Notify:ToggleList()
	if self.list and self.list:IsShown() then self:CloseList() else self:ShowList() end
end

function Notify:CloseAll() self:CloseList() self:CloseMenu() end

---------------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------------
function Notify:NameOf(id)
	local key = self:Key()
	local rec = key and ns.Inbox:Get(key, id)
	if not rec or type(rec.who) ~= "string" then return "?" end
	return rec.who:match("^[^%-]+") or rec.who
end

local function explain(why)
	if why == "role" then return L["APPS_ERR_ROLE"] end
	if why == "busy" then return L["APPS_ERR_BUSY"] end
	return L["APPS_ERR_CHANGED"]
end

function Notify:Invite(id)
	local key = self:Key()
	if not key then return false, "role" end
	local D = ns.Decisions
	local ok, why
	if D:IsManual(id) then ok, why = D:MarkInvited(key, id) else ok, why = D:Invite(key, id) end
	if not ok then say(explain(why)) end
	if self.list and self.list:IsShown() then self:RefreshList() end
	return ok, why
end

function Notify:AskDecline(id)
	local key = self:Key()
	local rec = key and ns.Inbox:Get(key, id)
	if not rec or not ns.Applications.IsOpen(rec) then return false end
	self.declining = id
	self:RefreshList()
	return true
end

function Notify:Answer(yes)
	local id = self.declining
	self.declining = nil
	if not yes or not id then self:RefreshList() return false end
	local key = self:Key()
	if not key then return false, "role" end
	local name = self:NameOf(id)
	local ok, why = ns.Decisions:Decline(key, id)
	say(ok and L["APPS_DECLINED_SNACK"]:format(name) or explain(why))
	self:Refresh()
	return ok, why
end

-- What the game answered to an invite: the words go to the chat when the window is not there to show them.
function Notify:OnResult(k, id, result, detail)
	if result == "declined" then return end
	if ns.Main and ns.Main:IsShown() then return end
	local name = self:NameOf(id)
	if result == "accepted" then say(L["APPS_INVITED_SNACK"]:format(name))
	elseif result == "offline" then say(L["APPS_OFFLINE_SNACK"]:format(name))
	elseif result == "refused" then say(L["APPS_REFUSED_SNACK"]:format(name, tostring(detail or "")))
	elseif result == "manual" then say(L[detail == "chat" and "APPS_MANUAL_CHAT" or "APPS_MANUAL_HAND"]:format(name))
	elseif result == "changed" then say(L["APPS_ERR_CHANGED"]) end
end

-- Opens the Applications panel of the main window (the list's last line, the chat link).
function Notify:OpenPanel()
	self:CloseAll()
	if not ns.Main then return false end
	if not self:Key() then return false end
	ns.Main:Open("Applications")
	return true
end

-- The click on the "Open" link of the chat line (the hook below), or a direct call.
function Notify:OnLink(link)
	if not Model.ParseLink(link) then return false end
	return self:OpenPanel()
end

---------------------------------------------------------------------------------------------------------------------
-- The menu
---------------------------------------------------------------------------------------------------------------------
function Notify:MenuContext()
	return { locked = self:Locked(), onlyWhenPending = AppsModel.GetOption("onlyWhenPending"), sound = AppsModel.GetOption("sound") }
end

function Notify:Choose(key)
	if key == "lock" then
		local locked = self:SetLocked(not self:Locked())
		say(L[locked and "NOTIFY_LOCKED" or "NOTIFY_UNLOCKED"])
	elseif key == "onlyWhenPending" then
		AppsModel.SetOption("onlyWhenPending", not AppsModel.GetOption("onlyWhenPending"))
	elseif key == "sound" then
		AppsModel.SetOption("sound", not AppsModel.GetOption("sound"))
	elseif key == "hide" then
		self:SetShownByUser(false)
	else
		return false
	end
	self:CloseMenu()
	self:Refresh()
	return true
end

function Notify:CreateMenu()
	if self.menu then return self.menu end
	local m = CreateFrame("Frame", Notify.NAME .. "Menu", UIParent)
	m:SetFrameStrata("DIALOG")
	m:SetSize(270, 40)
	m:EnableMouse(true)
	m:Hide()
	m.bg = W.NineSlice(m, "card", { corner = 6, layer = "BACKGROUND" })
	m.bg:SetHex("#1f1a15")
	m.edge = W.NineSlice(m, "card_edge", { corner = 6, layer = "BACKGROUND", sublevel = 1 })
	m.edge:SetHex("#6b5a40")
	m.items = {}
	for i = 1, 5 do
		local b = CreateFrame("Button", nil, m)
		b:SetHeight(34)
		b:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -6 - (i - 1) * 34)
		b:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -6 - (i - 1) * 34)
		b:RegisterForClicks("LeftButtonUp")
		b.hover = W.Texture(b, "solid", "BACKGROUND", "gold", 0.15)
		b.hover:SetAllPoints(b)
		b.hover:Hide()
		b.check = W.Texture(b, "glyph_check", "ARTWORK", "gold")
		b.check:SetSize(16, 16)
		b.check:SetPoint("LEFT", b, "LEFT", 14, 0)
		b.text = W.Text(b, "body", "snackbarText")
		b.text:SetPoint("LEFT", b, "LEFT", 40, 0)
		b.hint = W.Text(b, "caption", "gold", "RIGHT")
		b.hint:SetPoint("RIGHT", b, "RIGHT", -14, 0)
		b:SetScript("OnEnter", function(self) if self.kind ~= "title" then self.hover:Show() end end)
		b:SetScript("OnLeave", function(self) self.hover:Hide() end)
		b:SetScript("OnClick", function(self) if self.key and self.kind ~= "title" then Notify:Choose(self.key) end end)
		m.items[i] = b
	end
	if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = Notify.NAME .. "Menu" end
	self.menu = m
	return m
end

function Notify:ShowMenu()
	if not self:IsShown() then return false end
	self:CloseList()
	local m = self:CreateMenu()
	local entries = Model.Menu(self:MenuContext(), L)
	for i, b in ipairs(m.items) do
		local e = entries[i]
		if e then
			b.key, b.kind = e.key, e.kind
			b.text:SetText(e.text)
			b.check:SetShown(e.kind == "check" and e.checked == true)
			b.hint:SetText(e.hint or "")
			b:Show()
		else
			b.key = nil
			b:Hide()
		end
	end
	m:SetHeight(12 + #entries * 34)
	m:ClearAllPoints()
	local _, cy = self.frame:GetCenter()
	if (cy or 0) > UIParent:GetHeight() / 2 then m:SetPoint("TOPRIGHT", self.frame, "BOTTOMLEFT", 0, 0)
	else m:SetPoint("BOTTOMRIGHT", self.frame, "TOPLEFT", 0, 0) end
	m:Show()
	return true
end

function Notify:CloseMenu() if self.menu then self.menu:Hide() end end

function Notify:ToggleMenu()
	if self.menu and self.menu:IsShown() then self:CloseMenu() else self:ShowMenu() end
end

---------------------------------------------------------------------------------------------------------------------
-- Show and hide by the player: /gf notify, the menu, Settings
---------------------------------------------------------------------------------------------------------------------
function Notify:SetShownByUser(shown)
	AppsModel.SetOption("notifyIcon", shown and true or false)
	self:Refresh()
	return shown
end

-- /gf notify: shows or hides the icon (the option "Notification icon on screen"), only for the Guild Master and the
-- officers of a listed guild.
function Notify:Command()
	if not self:Available() then
		say(L["NOTIFY_NOT_AVAILABLE"])
		return false
	end
	local show = not AppsModel.GetOption("notifyIcon")
	self:SetShownByUser(show)
	say(L[show and "NOTIFY_ON" or "NOTIFY_OFF"])
	return show
end

---------------------------------------------------------------------------------------------------------------------
-- A new application
---------------------------------------------------------------------------------------------------------------------
function Notify:PlaySound()
	if not AppsModel.GetOption("sound") then return false end
	local fn = _G.PlaySound
	if type(fn) ~= "function" then return false end
	local kit = _G.SOUNDKIT
	local id = (type(kit) == "table" and (kit.UI_BNET_TOAST or kit.IG_PLAYER_INVITE)) or Notify.SOUND_FALLBACK
	pcall(fn, id)
	return true
end

function Notify:OnInbox(k, id, state, oldState, source)
	local key = self:Key()
	local before = self.count or 0
	if key then
		local alert = Model.Alert(k, id, state, oldState, source, key)
		if alert == "chat" then
			local rec = ns.Inbox:Get(key, id)
			if rec then
				say((Model.ChatLine(rec, L)))
				self:PlaySound()
			end
		end
	end
	self:Refresh()
	if Model.Pulse(before, self.count or 0) then self:Pulse() end
end

local function onLink(link) Notify:OnLink(link) end

-- While the icon is on screen the count is looked at every minute (an application can expire without any event).
function Notify:EnsurePoll()
	if self.pollPending then return end
	self.pollPending = true
	after(Notify.POLL, function()
		Notify.pollPending = false
		Notify:Refresh()
	end)
end

-- Called once the game is running (Core/Init.lua OnEnable): the chat link and the hourly look at the count.
function Notify:Init()
	if not self.linkHooked and type(_G.SetItemRef) == "function" then
		self.linkHooked = true
		hooksecurefunc("SetItemRef", onLink)
	end
	self:Refresh()
end

if ns.Bus then
	ns.Bus:On("INBOX_CHANGED", function(...) Notify:OnInbox(...) end)
	ns.Bus:On("INBOX_CLEARED", function() Notify:Refresh() end)
	ns.Bus:On("ROLE_CHANGED", function() Notify:Refresh() end)
	ns.Bus:On("CATALOG_UPDATED", function() Notify:Refresh() end)
	ns.Bus:On("NOTIFY_OPTIONS_CHANGED", function() Notify:Refresh() end)
	ns.Bus:On("DECISION_STARTED", function() if Notify.list and Notify.list:IsShown() then Notify:RefreshList() end end)
	ns.Bus:On("DECISION_RESULT", function(...) Notify:OnResult(...) if Notify.list and Notify.list:IsShown() then Notify:RefreshList() end end)
end

function Notify:DebugLines()
	local key, role = self:Key()
	local show, why = self:ShouldShow()
	return { ("Notification icon: role %s, %s, %d pending, %s%s, %s"):format(role, key and "your guild" or "no icon", self:Pending(),
		show and "shown" or "hidden", show and "" or (" (" .. tostring(why) .. ")"), self:Locked() and "locked" or "movable") }
end

if ns.addon then
	ns.addon.Notify = Notify
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Notification icon", function() return Notify:DebugLines() end) end
end
