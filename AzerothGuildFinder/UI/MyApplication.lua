-- MyApplication: the "My Application" tab of a character without a guild (SPEC-07 §7, mockup 06 D). Lua 5.1.
--
--   Left page   the brand plate, the player's character ("Elarin · Mage 32") and the rule in one line ("Want another guild?
--               Withdraw first: one open application at a time.")
--   Right page  the guild's emblem and name, "Applied 2 h ago"; a status card (title and explanation, coloured by state);
--               the road SENT > RECEIVED > ACCEPTED / DECLINED; the roles ticked; "Expires in 12 days"; the buttons View guild
--               (the guild page, pushed on this tab) and Withdraw (asks first). Without an application: "You haven't applied
--               to any guild" and a button to Find a Guild.
-- The tab shows the open application, or else the latest one (its result: accepted, declined, withdrawn, expired), until
-- it leaves the history (30 days). A change the player did not make (the expiry, an officer's answer) puts a dot on the
-- tab (a badge of 1) until the tab is opened. The texts are decided in UI/ApplyModel.lua.
local ADDON_NAME, ns = ...
ns = ns or {}
local MyApplication = {}
ns.MyApplication, ns.modules = MyApplication, ns.modules or {}
ns.modules.MyApplication = MyApplication

local L, Skin, W, Main, Model = ns.L, ns.Skin, ns.Widgets, ns.Main, ns.ApplyModel
local type, ipairs, max = type, ipairs, math.max

MyApplication.PAGE = "MyApplication"
local LW = 260

local function clock() return ns.Compat.ServerTime() end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local CARD_TINT = {
	ok = { fill = "#e3f1d8", edge = "#2e7d32", title = "#2e6b2a" },
	gold = { fill = "#fbefcf", edge = "#b8820f", title = "#7a5410" },
	bad = { fill = "#f8ddd6", edge = "#b3261e", title = "#8c1d18" },
	default = { fill = "#f3e6cc", edge = "#a06e3c", title = "#5a3a1c" },
}

local function buildLeft(host)
	local left = host.left
	host.plate = W.Plate(left, { text = L["TAB_MyApplication"], width = LW })
	host.plate:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
	host.who = W.Text(left, "titleS", "ink")
	host.who:SetPoint("TOPLEFT", host.plate, "BOTTOMLEFT", 2, -14)
	host.who:SetWidth(LW)
	host.who:SetWordWrap(false)
	host.rule = W.Text(left, "caption", "ink2")
	host.rule:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 0)
	host.rule:SetWidth(LW)
	host.rule:SetWordWrap(true)
	host.rule:SetJustifyV("BOTTOM")
end

local function buildApplication(host)
	local content = host.content
	local f = CreateFrame("Frame", nil, content)
	f:SetAllPoints(content)
	host.app = f

	f.emblem = ns.Emblem.Create(f, 64)
	f.emblem:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.name = W.Text(f, "titleL", "ink")
	f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 80, -8)
	f.name:SetWidth(420)
	f.name:SetWordWrap(false)
	f.applied = W.Text(f, "caption", "ink2")
	f.applied:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)

	local card = W.Card(f, { kind = "plain", title = "", height = 110 })
	card:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -88)
	card:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -88)
	card.text = W.Text(card.body, "body", "ink")
	card.text:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
	card.text:SetPoint("TOPRIGHT", card.body, "TOPRIGHT", 0, 0)
	card.text:SetWordWrap(true)
	f.card = card

	f.steps = {}
	f.arrows = {}
	for i = 1, 3 do
		f.steps[i] = W.Tag(f, { text = "", kind = "default" })
		if i < 3 then
			f.arrows[i] = W.Text(f, "body", "ink3")
			f.arrows[i]:SetText(">")
		end
	end
	f.rolesLabel = W.Text(f, "label", "ink")
	f.rolesLabel:SetText(L["MA_ROLES"])
	f.roleBadges = {}
	f.rolesNone = W.Text(f, "caption", "ink3")
	f.rolesNone:SetText(L["MA_ROLES_NONE"])
	f.expires = W.Text(f, "caption", "ink2")
	f.again = W.Text(f, "caption", "ink2")

	f.view = W.Button(f, { text = L["MA_VIEW_GUILD"], kind = "tonal", size = "md", onClick = function() MyApplication:ViewGuild() end })
	f.withdraw = W.Button(f, { text = L["MA_WITHDRAW"], kind = "tonal", size = "md", onClick = function() MyApplication:Ask() end })

	-- the question before Withdraw
	local c = CreateFrame("Frame", nil, f)
	c:SetSize(420, 116)
	c:SetFrameLevel(f:GetFrameLevel() + 20)
	c:EnableMouse(true)
	c.bg = W.NineSlice(c, "card", { corner = 12, layer = "BACKGROUND" })
	c.bg:SetHex("#fbe9c5")
	c.edge = W.NineSlice(c, "card_edge", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	c.edge:SetHex("#b8820f")
	c.text = W.Text(c, "body", "ink")
	c.text:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -14)
	c.text:SetWidth(392)
	c.text:SetWordWrap(true)
	c.yes = W.Button(c, { text = L["MA_WITHDRAW"], kind = "primary", size = "sm", onClick = function() MyApplication:Answer(true) end })
	c.yes:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 14, 14)
	c.no = W.Button(c, { text = L["ED_CANCEL"], kind = "tonal", size = "sm", onClick = function() MyApplication:Answer(false) end })
	c.no:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 14)
	c:Hide()
	f.confirm = c
end

local function buildEmpty(host)
	local f = CreateFrame("Frame", nil, host.content)
	f:SetAllPoints(host.content)
	f.title = W.Text(f, "titleL", "ink", "CENTER")
	f.title:SetPoint("TOP", f, "TOP", 0, -180)
	f.title:SetWidth(460)
	f.body = W.Text(f, "body", "ink2", "CENTER")
	f.body:SetPoint("TOP", f.title, "BOTTOM", 0, -10)
	f.body:SetWidth(460)
	f.body:SetWordWrap(true)
	f.find = W.Button(f, { text = L["MA_FIND"], kind = "primary", size = "md",
		onClick = function() Main:Select("FindGuild") end })
	f.find:SetPoint("TOP", f.body, "BOTTOM", 0, -20)
	f:Hide()
	host.empty = f
end

local function build(host)
	MyApplication.host = host
	buildLeft(host)
	buildApplication(host)
	buildEmpty(host)
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
function MyApplication:IsShown() return self.host ~= nil and self.host.shown == true end

local function whoText()
	local p = ns.Applications.ReadPlayer()
	local E = ns.Enums
	local c = p.classID and E.CLASS_ROLES[p.classID]
	local class = c and L["CLASS_" .. c.key] or ""
	if not p.name then return "" end
	return L["MA_WHO"]:format(p.name, class, p.level or 0)
end

-- The view of the latest application (nil: none), for the page and the tests.
function MyApplication:View()
	local rec = ns.Applications:Latest()
	local listed = false
	if rec and ns.Catalog then
		local _, status = ns.Catalog:Get(rec.k)
		listed = status == "listed" or status == "inactive"
	end
	return Model.MyApplication(rec, { now = clock(), listed = listed }, L), rec
end

local function layoutRoles(f, view, y)
	f.rolesLabel:ClearAllPoints()
	f.rolesLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
	local n = #view.roles
	for i = 1, max(n, #f.roleBadges) do
		if i <= n then
			if not f.roleBadges[i] then f.roleBadges[i] = W.RoleBadge(f, { size = 24 }) end
			local b = f.roleBadges[i]
			b:SetRole(view.roles[i].key)
			b:ClearAllPoints()
			b:SetPoint("LEFT", f.rolesLabel, "RIGHT", 10 + (i - 1) * 30, 0)
			W.SetTooltip(b, view.roles[i].label)
			b:Show()
		elseif f.roleBadges[i] then
			f.roleBadges[i]:Hide()
		end
	end
	f.rolesNone:ClearAllPoints()
	f.rolesNone:SetPoint("LEFT", f.rolesLabel, "RIGHT", 10, 0)
	f.rolesNone:SetShown(n == 0)
end

function MyApplication:Refresh()
	local host = self.host
	if not host or not host.shown or self.refreshing then return end
	self.refreshing = true   -- reading the application may expire it, which announces a change: no second drawing inside
	local ok, view, rec = pcall(self.View, self)
	self.refreshing = false
	if not ok then return geterrorhandler()(view) end
	self.view, self.rec = view, rec
	host.who:SetText(whoText())
	host.empty:SetShown(view.empty == true)
	host.app:SetShown(not view.empty)
	if view.empty then
		host.rule:SetText(L["MA_HINT_EMPTY"])
		host.empty.title:SetText(view.title)
		host.empty.body:SetText(view.body)
		host.app.confirm:Hide()
		Main:SetStatus("", nil)
		return view
	end
	local f = host.app
	host.rule:SetText(view.hint)
	local entry = ns.Catalog and ns.Catalog:Get(view.k)
	f.emblem:SetEmblem(entry and entry.sum and entry.sum.emb or nil, view.name)
	f.name:SetText(view.name)
	f.applied:SetText(view.appliedText)

	local tint = CARD_TINT[view.kind] or CARD_TINT.default
	f.card:SetTitle(view.title)
	f.card.bg:SetHex(tint.fill, 1)
	f.card.edge:SetHex(tint.edge, 1)
	W.TextColor(f.card.title, tint.title)
	f.card.text:SetText(view.body)
	local bodyH = f.card.text:GetStringHeight()
	bodyH = (type(bodyH) == "number" and bodyH > 0) and bodyH or 18
	f.card:SetHeight(42 + bodyH + 16)

	-- the road
	local y = 88 + f.card:GetHeight() + 14
	local x = 0
	for i, step in ipairs(view.steps) do
		local tag = f.steps[i]
		tag:SetText(step.text)
		tag:SetKind(step.on and (step.bad and "bad" or "ok") or "default")
		tag:ClearAllPoints()
		tag:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
		x = x + tag:GetWidth() + 6
		if f.arrows[i] then
			f.arrows[i]:ClearAllPoints()
			f.arrows[i]:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(y + 3))
			x = x + 16
		end
	end
	y = y + 22 + 16
	layoutRoles(f, view, y)
	y = y + 30
	f.expires:ClearAllPoints()
	f.expires:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
	f.expires:SetText(view.expiresText or "")
	f.expires:SetShown(view.expiresText ~= nil)
	f.again:ClearAllPoints()
	f.again:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
	f.again:SetText(view.again or "")
	f.again:SetShown(view.again ~= nil)
	y = y + 30

	f.view:ClearAllPoints()
	f.view:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
	f.view:SetShown(view.viewGuild)
	f.withdraw:ClearAllPoints()
	if view.viewGuild then f.withdraw:SetPoint("LEFT", f.view, "RIGHT", 10, 0)
	else f.withdraw:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y) end
	f.withdraw:SetShown(view.withdraw)
	f.confirm:ClearAllPoints()
	f.confirm:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(y + 46))
	if not view.withdraw then f.confirm:Hide() end
	Main:SetStatus(view.title, view.open and "ok" or "off")
	return view
end

-- The dot on the tab: a badge of 1 while a change is unseen.
function MyApplication:UpdateBadge()
	if not Main.SetBadge then return end
	Main:SetBadge(MyApplication.PAGE, ns.Applications:Unseen() > 0 and 1 or 0)
end

---------------------------------------------------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------------------------------------------------
function MyApplication:ViewGuild()
	local view = self.view
	if not (view and view.viewGuild) then return false end
	Main:Push("GuildPage", { k = view.k })
	return true
end

function MyApplication:Ask()
	local host, view = self.host, self.view
	if not host or not (view and view.withdraw) then return false end
	host.app.confirm.text:SetText(L["MA_WITHDRAW_CONFIRM"]:format(view.name))
	host.app.confirm:Show()
	return true
end

-- true withdraws (the player may apply elsewhere at once), false only closes the question.
function MyApplication:Answer(yes)
	local host = self.host
	if not host then return false end
	host.app.confirm:Hide()
	if not yes then return false end
	local ok = ns.Applications:Withdraw()
	if ok then W.Snackbar.Show(L["MA_WITHDRAWN_SNACK"], { key = "apply" }) end
	self:Refresh()
	return ok
end

---------------------------------------------------------------------------------------------------------------------
-- The page of the window
---------------------------------------------------------------------------------------------------------------------
Main:RegisterPage(MyApplication.PAGE, {
	Build = build,
	OnShow = function(host)
		MyApplication.host = host
		host.app.confirm:Hide()
		ns.Applications:MarkSeen()
		MyApplication:UpdateBadge()
		MyApplication:Refresh()
	end,
	OnHide = function(host)
		host.app.confirm:Hide()
		host.shown = false
		W.HideTooltip()
	end,
})

if ns.Bus then
	ns.Bus:On("APPLICATION_CHANGED", function()
		if MyApplication:IsShown() then
			ns.Applications:MarkSeen()
			MyApplication:Refresh()
		end
		MyApplication:UpdateBadge()
	end)
	ns.Bus:On("APPLICATION_SEEN", function() MyApplication:UpdateBadge() end)
	ns.Bus:On("CATALOG_UPDATED", function() if MyApplication:IsShown() then MyApplication:Refresh() end end)
	ns.Bus:On("ROLE_CHANGED", function() MyApplication:UpdateBadge() end)
end
if ns.addon then ns.addon.MyApplication = MyApplication end
