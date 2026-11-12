-- Main: the book-shaped window (SPEC-04 §2, ADR 0008). Lua 5.1.
--
-- The window is 1116 x 768 px at 100 %: a left page (312 px: the brand and the context of the tab), a right page (title
-- bar with Back, the content, a status bar) and, outside the book, the metal side rail with one tab per entry of
-- Nav.TabsFor(role): Settings first, then the tabs of the player's role. A gold round button closes it, Esc closes it
-- (UISpecialFrames), it is dragged by its pages, scaled 60 %..140 % and remembers where it was left.
--
-- What the later steps use:
--   Main:RegisterPage(id, def)   def = { title = "text" | function(params) -> text, Build = function(host),
--                                OnShow = function(host, params, entry), OnHide = function(host, entry) }
--       `id` is a tab id (the root page of that tab) or the id of a page pushed on a tab. Build runs once, the first
--       time the page is shown. `host` has three frames that are the page's own and are shown only while it is current:
--       host.left (the left page below the brand), host.header (the right side of the title bar: search box, buttons),
--       host.content (the right page between the title bar and the status bar), plus host.id, host.entry, host.params.
--       A page that wants its state back after Back writes it into `entry.state` in OnHide (filters, scroll position).
--   Main:Push(id, params) / Main:Back() / Main:Select(tab) / Main:Open(tab)    navigation
--   Main:SetTitle(text)  Main:SetStatus(text, level)  Main:SetBadge(tabId, count)    the shell's own texts
--   Main:Show() Hide() Toggle() IsShown()   Main:SetScale(0.6..1.4)   Main:ResetPosition()
-- Tabs without a registered page show a short "coming soon" page, so the window is complete from the start.
-- The window listens to ROLE_CHANGED on the Bus: it starts over on the first tab of the new role (SPEC-00 §5).
local ADDON_NAME, ns = ...
ns = ns or {}
local Main = {}
ns.Main, ns.modules = Main, ns.modules or {}
ns.modules.Main = Main

local L, Skin, Nav, W = ns.L, ns.Skin, ns.Nav, ns.Widgets
local type, pairs, ipairs, tostring, pcall = type, pairs, ipairs, tostring, pcall
local min, max = math.min, math.max

Main.NAME = "AzerothGuildFinderMainFrame"
Main.pages = {}        -- id -> definition (RegisterPage)
Main.hosts = {}        -- id -> host, once built
Main.badges = {}       -- tab id -> count
Main.pendingProvider = nil   -- function() -> number of pending applications (M4 sets it)

---------------------------------------------------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------------------------------------------------
function Main:RegisterPage(id, def)
	if type(id) ~= "string" or type(def) ~= "table" then return false end
	self.pages[id] = def
	return true
end

-- The text of a "coming soon" page and the Settings page are defined at the end of this file.
function Main:PageDef(id)
	return self.pages[id] or self.placeholder
end

local function pageTitle(def, entry, tabId)
	local title = def.title
	if type(title) == "function" then title = title(entry and entry.params) end
	if type(title) ~= "string" or title == "" then
		title = Nav.TABS[tabId] and L[Nav.TABS[tabId].labelKey] or ""
	end
	return title
end

-- Builds the three frames of a page once.
function Main:EnsureHost(id)
	local host = self.hosts[id]
	if host then return host end
	host = { id = id }
	host.left = CreateFrame("Frame", nil, self.leftArea)
	host.left:SetAllPoints(self.leftArea)
	host.header = CreateFrame("Frame", nil, self.headerArea)
	host.header:SetAllPoints(self.headerArea)
	host.content = CreateFrame("Frame", nil, self.contentArea)
	host.content:SetAllPoints(self.contentArea)
	for _, f in ipairs({ host.left, host.header, host.content }) do f:Hide() end
	self.hosts[id] = host
	local def = self:PageDef(id)
	if def.Build then xpcall(def.Build, geterrorhandler(), host) end
	return host
end

local function setHostShown(host, shown)
	host.left:SetShown(shown)
	host.header:SetShown(shown)
	host.content:SetShown(shown)
	host.shown = shown
end

-- Shows the current page of the current tab and hides the one that was showing.
function Main:Render()
	if not self.frame then return end
	local entry = self.book:Page()
	if not entry then return end
	local id = entry.page
	for pid, host in pairs(self.hosts) do
		if host.shown and (pid ~= id or host.entry ~= entry) then
			local def = self:PageDef(pid)
			if def.OnHide then xpcall(def.OnHide, geterrorhandler(), host, host.entry) end
			setHostShown(host, false)
		end
	end
	local host = self:EnsureHost(id)
	local def = self:PageDef(id)
	if not host.shown then
		host.entry, host.params = entry, entry.params
		setHostShown(host, true)
		if def.OnShow then xpcall(def.OnShow, geterrorhandler(), host, entry.params, entry) end
	end
	self.title:SetText(pageTitle(def, entry, self.book:Current()))
	local back = self.book:CanGoBack()
	self.backButton:SetShown(back)
	-- the title moves to the right of the Back button instead of sitting under it
	self.title:ClearAllPoints()
	if back then self.title:SetPoint("LEFT", self.backButton, "RIGHT", 6, 0)
	else self.title:SetPoint("LEFT", self.bar, "LEFT", 0, 0) end
	self:UpdateRail()
end

-- Explicit title for the current page (a guild page sets the guild's name once it is known).
function Main:SetTitle(text)
	if self.title then self.title:SetText(text or "") end
end

function Main:Push(id, params) return self.book:Push(id, params) end
function Main:Back() return self.book:Back() end
function Main:Select(tab) return self.book:Select(tab) end
function Main:CurrentTab() return self.book:Current() end
function Main:CurrentPage() local e = self.book:Page(); return e and e.page end

---------------------------------------------------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------------------------------------------------
-- True when the player's guild has a listing in the catalog.
function Main.HasListing()
	local Role, Catalog = ns.Role, ns.Catalog
	local key = Role and Role:GuildKey()
	if not key or not Catalog then return false end
	return ns.MyGuildModel.HasListing(Catalog:Status(key))
end

-- Recomputes the tabs of the role. `reset`: the role changed, start again on its first tab.
function Main:RefreshTabs(reset)
	local role = ns.Role and ns.Role:Get() or "none"
	return self.book:SetTabs(Nav.TabsFor(role, Main.HasListing()), reset)
end

function Main:GetPendingCount()
	if type(self.pendingProvider) ~= "function" then return 0 end
	local ok, n = pcall(self.pendingProvider)
	return (ok and type(n) == "number") and n or 0
end

function Main:SetBadge(tabId, count)
	self.badges[tabId] = count
	self:UpdateRail()
end

Main.book = Nav.NewBook(function(kind) Main:OnBookChanged(kind) end)

function Main:OnBookChanged(kind)
	if not self.frame then return end
	if kind == "tabs" then self:LayoutRail() end
	if self.frame:IsShown() then self:Render() end
end

---------------------------------------------------------------------------------------------------------------------
-- The side rail
---------------------------------------------------------------------------------------------------------------------
local TAB_BG = { off = "#30353b", on = "#5a4018" }
local TAB_EDGE = { off = "#5c646d", on = "#f2bf3c" }
local TAB_TEXT = { off = "#cfd6dc", on = "#fff3d1" }

local function createTabButton(self, index)
	local m = Skin.METRICS
	local b = CreateFrame("Button", nil, self.rail)
	b:SetSize(m.railTabW, m.railTabH)
	b:RegisterForClicks("LeftButtonUp")
	b.glow = W.NineSlice(b, "shadow", { corner = 32, outset = 14, layer = "BACKGROUND", sublevel = -2 })
	b.glow:SetColor(0.95, 0.75, 0.24, 0.5)
	b.shadow = W.NineSlice(b, "shadow", { corner = 32, outset = 10, layer = "BACKGROUND", sublevel = -3 })
	b.shadow:SetColor(0, 0, 0, 0.5)
	b.bg = W.NineSlice(b, "card", { corner = 12, layer = "BACKGROUND" })
	b.edge = W.NineSlice(b, "card_edge", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	b.iconBg = W.Texture(b, "pill", "ARTWORK", nil)
	b.iconBg:SetVertexColor(0.95, 0.75, 0.24, 0.25)
	b.iconBg:SetSize(42, 32)
	b.iconBg:SetPoint("TOP", b, "TOP", 4, -9)
	b.icon = W.Texture(b, "glyph_gear", "OVERLAY", nil)
	b.icon:SetSize(24, 24)
	b.icon:SetPoint("CENTER", b.iconBg, "CENTER", 0, 0)
	b.label = W.Text(b, "rail", "white", "CENTER")
	b.label:SetPoint("BOTTOM", b, "BOTTOM", 4, 9)
	b.label:SetWidth(m.railTabW - 10)
	b.label:SetHeight(28)
	b.label:SetJustifyV("TOP")
	b.badge = W.Badge(b, { count = 0 })
	b.badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -4)
	b:SetScript("OnClick", function(btn) Main:Select(btn.id) end)
	b:SetScript("OnEnter", function(btn) if not btn.active then btn.bg:SetHex("#3c434a") end end)
	b:SetScript("OnLeave", function(btn) btn.bg:SetHex(btn.active and TAB_BG.on or TAB_BG.off) end)
	self.tabButtons[index] = b
	return b
end

-- Lays the tab buttons out one under the other with no empty places (the role decides how many there are).
function Main:LayoutRail()
	if not self.rail then return end
	local m = Skin.METRICS
	local tabs = self.book:Tabs()
	local y = 0
	for i, id in ipairs(tabs) do
		local b = self.tabButtons[i] or createTabButton(self, i)
		local info = Nav.TABS[id]
		b.id = id
		b.icon:SetTexture(W.Media(info.glyph))
		b.label:SetText(L[info.labelKey])
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", self.rail, "TOPLEFT", 0, -y)
		b:Show()
		y = y + m.railTabH + m.railGap
	end
	for i = #tabs + 1, #self.tabButtons do
		self.tabButtons[i].id = nil
		self.tabButtons[i]:Hide()
	end
	self:UpdateRail()
end

-- Paints the active tab (gold, wider, sticking out) and the badges.
function Main:UpdateRail()
	if not self.rail then return end
	local m = Skin.METRICS
	local current = self.book:Current()
	for _, b in ipairs(self.tabButtons) do
		if b.id then
			local active = b.id == current
			b.active = active
			b:SetWidth(active and m.railW or m.railTabW)
			b.bg:SetHex(active and TAB_BG.on or TAB_BG.off)
			b.edge:SetHex(active and TAB_EDGE.on or TAB_EDGE.off)
			b.glow:SetShown(active)
			b.iconBg:SetShown(active)
			b.icon:SetVertexColor(Skin.Hex(active and "#f2bf3c" or "#cfd6dc"))
			W.TextColor(b.label, active and TAB_TEXT.on or TAB_TEXT.off)
			b.badge:SetCount(self.badges[b.id] or 0)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Scale and position
---------------------------------------------------------------------------------------------------------------------
function Main:GetScale()
	if self.scale then return self.scale end
	local saved = ns.Config and ns.Config:Get("account.settings.uiScale")
	return Nav.ClampScale(saved)
end

-- The scale really used: the chosen one, reduced when the book would not fit on the screen.
function Main:EffectiveScale()
	local m = Skin.METRICS
	return Nav.FitScale(self:GetScale(), UIParent:GetWidth(), UIParent:GetHeight(), m.windowW, m.windowH, m.railW)
end

function Main:ApplyPosition()
	if not self.frame then return end
	local pos = ns.Config and ns.Config:Get("char.ui.mainPos")
	if not (ns.Config and ns.Config.IsPos(pos)) then pos = Nav.DEFAULT_POS end
	local point, relPoint, x, y = Nav.SavedToPos(pos, self.effective or self:GetScale())
	self.frame:ClearAllPoints()
	self.frame:SetPoint(point, UIParent, relPoint, x, y)
end

function Main:ApplyScale()
	if not self.frame then return end
	self.effective = self:EffectiveScale()
	self.frame:SetScale(self.effective)
	if W.Snackbar.Frame() then W.Snackbar.Frame():SetScale(self.effective) end
	self:ApplyPosition()
end

-- Sets the scale (a fraction, 0.6..1.4: anything else is clamped), saves it and applies it. Returns the scale kept.
function Main:SetScale(value)
	local scale = Nav.ClampScale(value)
	self.scale = scale
	if ns.Config then ns.Config:Set("account.settings.uiScale", scale) end
	self:ApplyScale()
	if self.scaleControl then self.scaleControl:SetSelected(scale, true) end
	return scale
end

function Main:SavePosition()
	local point, _, relPoint, x, y = self.frame:GetPoint(1)
	if not point or not ns.Config then return end
	ns.Config:Set("char.ui.mainPos", Nav.PosToSaved(point, relPoint, x, y, self.effective or self:GetScale()))
end

function Main:ResetPosition()
	if ns.Config then ns.Config:Set("char.ui.mainPos", nil) end
	self:ApplyPosition()
end

---------------------------------------------------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------------------------------------------------
local function page(parent, tint, corner)
	local f = CreateFrame("Frame", nil, parent)
	f.bg = W.NineSlice(f, "card", { corner = corner or 10, layer = "BACKGROUND" })
	f.bg:SetHex(tint)
	f.grain = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.grain:SetTexture(W.Media("parchment"), "REPEAT", "REPEAT")
	f.grain:SetHorizTile(true)
	f.grain:SetVertTile(true)
	f.grain:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
	f.grain:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
	return f
end

function Main:Create()
	if self.frame then return self.frame end
	local m = Skin.METRICS
	Skin.CreateFonts()
	local f = CreateFrame("Frame", Main.NAME, UIParent)
	self.frame = f
	f:SetSize(m.windowW, m.windowH)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	if f.SetClampRectInsets then f:SetClampRectInsets(0, -m.railW, 0, 0) end   -- the rail may reach the screen edge
	f:EnableMouse(true)
	f:Hide()
	local base = f:GetFrameLevel()

	f.shadow = W.NineSlice(f, "shadow", { corner = 32, outset = 30, layer = "BACKGROUND", sublevel = -4 })
	f.shadow:SetColor(0, 0, 0, 0.6)

	-- the rail sits under the book: its left edge hides behind the right page
	self.rail = CreateFrame("Frame", nil, f)
	self.rail:SetFrameLevel(base + 1)
	self.rail:SetSize(m.railW, m.windowH - m.railTop)
	self.rail:SetPoint("TOPLEFT", f, "TOPRIGHT", -8, -m.railTop)
	self.tabButtons = {}

	self.leftPage = page(f, Skin.COLORS.pageLeft)
	self.leftPage:SetFrameLevel(base + 2)
	self.leftPage:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	self.leftPage:SetSize(m.leftPageW, m.windowH)
	self.rightPage = page(f, Skin.COLORS.parch)
	self.rightPage:SetFrameLevel(base + 3)
	self.rightPage:SetPoint("TOPLEFT", self.leftPage, "TOPRIGHT", -6, 0)
	self.rightPage:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	self.rightPage.edge = W.NineSlice(self.rightPage, "card_edge", { corner = 10, layer = "BACKGROUND", sublevel = 2 })
	self.rightPage.edge:SetHex("#96643a", 0.5)
	self.rightPage.gutter = self.rightPage:CreateTexture(nil, "BACKGROUND", nil, 3)
	self.rightPage.gutter:SetTexture(W.Media("shade_h"))
	self.rightPage.gutter:SetPoint("TOPLEFT", self.rightPage, "TOPLEFT", 3, -3)
	self.rightPage.gutter:SetPoint("BOTTOMLEFT", self.rightPage, "BOTTOMLEFT", 3, 3)
	self.rightPage.gutter:SetWidth(22)

	-- left page: the brand, then the area of the current page
	self.brand = W.Text(self.leftPage, "display", "#5a3a1c")
	self.brand:SetPoint("TOPLEFT", self.leftPage, "TOPLEFT", 30, -26)
	self.brand:SetText(L["BRAND_TITLE"])
	self.brandSub = W.Text(self.leftPage, "overline", "ink3")
	self.brandSub:SetPoint("TOPLEFT", self.brand, "BOTTOMLEFT", 2, -2)
	self.brandSub:SetText(L["BRAND_SUB"])
	self.leftArea = CreateFrame("Frame", nil, self.leftPage)
	self.leftArea:SetPoint("TOPLEFT", self.leftPage, "TOPLEFT", 30, -104)
	self.leftArea:SetPoint("BOTTOMRIGHT", self.leftPage, "BOTTOMRIGHT", -22, 20)

	-- right page: title bar, content, status bar
	local bar = CreateFrame("Frame", nil, self.rightPage)
	bar:SetPoint("TOPLEFT", self.rightPage, "TOPLEFT", 28, -16)
	bar:SetPoint("TOPRIGHT", self.rightPage, "TOPRIGHT", -26, -16)
	bar:SetHeight(m.headerH)
	self.bar = bar
	bar.line = bar:CreateTexture(nil, "ARTWORK")
	bar.line:SetTexture(W.Media("solid"))
	bar.line:SetVertexColor(Skin.Color("line"))
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bar.line:SetHeight(1)
	self.backButton = W.Button(bar, { text = L["BTN_BACK"], kind = "ghost", glyph = "glyph_back", size = "sm",
		tooltip = L["BTN_BACK_TIP"], onClick = function() Main:Back() end })
	self.backButton:SetPoint("LEFT", bar, "LEFT", -6, 0)
	self.backButton:Hide()
	self.title = W.Text(bar, "titleL", "#6a4523")
	self.title:SetPoint("LEFT", bar, "LEFT", 0, 0)
	self.headerArea = CreateFrame("Frame", nil, bar)
	self.headerArea:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
	self.headerArea:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	self.headerArea:SetWidth(420)
	self.contentArea = CreateFrame("Frame", nil, self.rightPage)
	self.contentArea:SetPoint("TOPLEFT", self.rightPage, "TOPLEFT", 28, -(16 + m.headerH + 12))
	self.contentArea:SetPoint("BOTTOMRIGHT", self.rightPage, "BOTTOMRIGHT", -26, m.statusH + 16)

	local status = CreateFrame("Frame", nil, self.rightPage)
	status:SetPoint("BOTTOMLEFT", self.rightPage, "BOTTOMLEFT", 28, 14)
	status:SetPoint("BOTTOMRIGHT", self.rightPage, "BOTTOMRIGHT", -26, 14)
	status:SetHeight(m.statusH)
	status.line = status:CreateTexture(nil, "ARTWORK")
	status.line:SetTexture(W.Media("solid"))
	status.line:SetVertexColor(Skin.Color("line"))
	status.line:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
	status.line:SetPoint("TOPRIGHT", status, "TOPRIGHT", 0, 0)
	status.line:SetHeight(1)
	status.dot = W.Texture(status, "disc", "ARTWORK", nil)
	status.dot:SetSize(8, 8)
	status.dot:SetPoint("LEFT", status, "LEFT", 0, -3)
	self.statusText = W.Text(status, "caption", "ink2")
	self.statusText:SetPoint("LEFT", status.dot, "RIGHT", 8, 0)
	self.statusText:SetPoint("RIGHT", status, "RIGHT", 0, 0)
	self.statusDot = status.dot
	self.status = status
	self:SetStatus("", nil)

	-- dragging: the title bars of both pages and the brand carry the window (the pages' own widgets keep their clicks)
	for _, area in ipairs({ self.leftPage, bar }) do
		area:EnableMouse(true)
		area:RegisterForDrag("LeftButton")
		area:SetScript("OnDragStart", function() f:StartMoving() end)
		area:SetScript("OnDragStop", function() f:StopMovingOrSizing(); Main:SavePosition() end)
	end
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
	f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing(); Main:SavePosition() end)

	-- close: the round gold button at the corner (Esc does the same through UISpecialFrames)
	self.closeButton = W.CloseButton(f, function() Main:Hide() end, L["BTN_CLOSE"])
	self.closeButton:SetFrameLevel(base + 8)
	self.closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 12, 12)
	if type(UISpecialFrames) == "table" then
		local found = false
		for _, name in ipairs(UISpecialFrames) do if name == Main.NAME then found = true end end
		if not found then table.insert(UISpecialFrames, Main.NAME) end
	end

	-- Backspace goes back one page; every other key reaches the game as usual
	f:EnableKeyboard(true)
	f:SetPropagateKeyboardInput(true)
	f:SetScript("OnKeyDown", function(frame, key)
		if key == "BACKSPACE" and Main.book:CanGoBack() then
			frame:SetPropagateKeyboardInput(false)
			Main:Back()
		else
			frame:SetPropagateKeyboardInput(true)
		end
	end)

	f:SetScript("OnShow", function() Main:Render() end)
	f:SetScript("OnHide", function()
		local entry = Main.book:Page()
		local host = entry and Main.hosts[entry.page]
		if host and host.shown then
			local def = Main:PageDef(entry.page)
			if def.OnHide then xpcall(def.OnHide, geterrorhandler(), host, host.entry) end
			setHostShown(host, false)
		end
		W.HideTooltip()
	end)
	f:RegisterEvent("UI_SCALE_CHANGED")
	f:RegisterEvent("DISPLAY_SIZE_CHANGED")
	f:SetScript("OnEvent", function() Main:ApplyScale() end)

	W.Snackbar.SetAnchor(f)
	self.scale = nil
	self:ApplyScale()
	self:LayoutRail()
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- Status bar
---------------------------------------------------------------------------------------------------------------------
local STATUS_DOT = { ok = "#43a047", warn = "#d98a0b", off = "#9e9e9e" }

-- The line at the bottom of the right page. level: "ok" (green dot), "warn" (amber) or "off" (grey); nil hides the dot.
function Main:SetStatus(text, level)
	if not self.statusText then return end
	self.statusText:SetText(text or "")
	local hex = level and STATUS_DOT[level]
	self.statusDot:SetShown(hex ~= nil)
	if hex then W.TintHex(self.statusDot, hex) end
	self.statusLevel = level
end

---------------------------------------------------------------------------------------------------------------------
-- Show, hide, toggle
---------------------------------------------------------------------------------------------------------------------
function Main:IsShown() return self.frame ~= nil and self.frame:IsShown() end

function Main:Show()
	self:RefreshTabs(false)
	self:Create()
	self.frame:Show()
end

function Main:Hide()
	if self.frame then self.frame:Hide() end
end

function Main:Toggle()
	if self:IsShown() then self:Hide() else self:Show() end
end

-- Opens the window on a tab (the minimap's right click opens Settings).
function Main:Open(tab)
	self:RefreshTabs(false)
	if tab then self.book:Select(tab) end
	self:Show()
end

---------------------------------------------------------------------------------------------------------------------
-- Pages the shell brings itself: "coming soon" and Settings (the full Settings page is M5.1)
---------------------------------------------------------------------------------------------------------------------
Main.placeholder = {
	Build = function(host)
		host.plate = W.Plate(host.left, { text = "", width = 260 })
		host.plate:SetPoint("TOPLEFT", host.left, "TOPLEFT", 0, 0)
		host.card = W.Card(host.content, { kind = "plain", title = "", height = 110 })
		host.card:SetPoint("TOPLEFT", host.content, "TOPLEFT", 0, 0)
		host.card:SetPoint("TOPRIGHT", host.content, "TOPRIGHT", 0, 0)
		host.text = W.Text(host.card.body, "body", "ink2")
		host.text:SetPoint("TOPLEFT", host.card.body, "TOPLEFT", 0, 0)
		host.text:SetPoint("TOPRIGHT", host.card.body, "TOPRIGHT", 0, 0)
		host.text:SetWordWrap(true)
		host.text:SetText(L["PAGE_SOON"])
	end,
	OnShow = function(host)
		local label = Main.book:Current() and Nav.TABS[Main.book:Current()] and L[Nav.TABS[Main.book:Current()].labelKey] or ""
		host.plate:SetText(label)
		host.card:SetTitle(label)
	end,
}

local SCALES = { 0.6, 0.8, 1.0, 1.2, 1.4 }

Main:RegisterPage(Nav.SETTINGS, {
	Build = function(host)
		host.plate = W.Plate(host.left, { text = L["SETTINGS_WINDOW"], width = 260 })
		host.plate:SetPoint("TOPLEFT", host.left, "TOPLEFT", 0, 0)
		host.note = W.Text(host.left, "caption", "ink2")
		host.note:SetPoint("TOPLEFT", host.plate, "BOTTOMLEFT", 2, -12)
		host.note:SetWidth(250)
		host.note:SetWordWrap(true)
		host.note:SetText(L["SETTINGS_NOTE"])

		local card = W.Card(host.content, { kind = "plain", title = L["SETTINGS_WINDOW"], glyph = "glyph_gear", height = 168 })
		card:SetPoint("TOPLEFT", host.content, "TOPLEFT", 0, 0)
		card:SetPoint("TOPRIGHT", host.content, "TOPRIGHT", 0, 0)
		local label = W.Text(card.body, "label", "ink")
		label:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
		label:SetText(L["SETTINGS_SCALE"])
		local items = {}
		for _, s in ipairs(SCALES) do items[#items + 1] = { key = s, text = Nav.ScaleLabel(s) } end
		Main.scaleControl = W.Segmented(card.body, items, { selected = Main:GetScale(), onChange = function(key) Main:SetScale(key) end })
		Main.scaleControl:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
		local help = W.Text(card.body, "caption", "ink3")
		help:SetPoint("TOPLEFT", Main.scaleControl, "BOTTOMLEFT", 0, -8)
		help:SetText(L["SETTINGS_SCALE_HELP"])
		local reset = W.Button(card.body, { text = L["SETTINGS_RESET_POS"], kind = "tonal", size = "sm",
			onClick = function() Main:ResetPosition(); W.Snackbar.Show(L["RESET_DONE"], { key = "reset" }) end })
		reset:SetPoint("TOPRIGHT", card.body, "TOPRIGHT", 0, 0)
		host.resetButton = reset
		host.card = card

		-- Privacy: the anonymous alt count of SPEC-03 §4 (Data/Stats.lua). The full Settings page is M5.1.
		local privacy = W.Card(host.content, { kind = "plain", title = L["SETTINGS_PRIVACY"], glyph = "glyph_shield", height = 124 })
		privacy:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -16)
		privacy:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -16)
		local share = W.Switch(privacy.body, { label = L["SETTINGS_SHARE_ALTS"], width = 420,
			checked = not ns.Stats or ns.Stats:Sharing(),
			onChange = function(value, sw)
				local ok = ns.Stats and ns.Stats:SetSharing(value)
				if not ok then sw:SetChecked(not value, true) end
			end })
		share:SetPoint("TOPLEFT", privacy.body, "TOPLEFT", 0, 0)
		local shareHelp = W.Text(privacy.body, "caption", "ink3")
		shareHelp:SetPoint("TOPLEFT", share, "BOTTOMLEFT", 0, -6)
		shareHelp:SetPoint("RIGHT", privacy.body, "RIGHT", 0, 0)
		shareHelp:SetWordWrap(true)
		shareHelp:SetText(L["SETTINGS_SHARE_ALTS_HELP"])
		host.shareSwitch, host.privacy = share, privacy

		-- Notifications: how the Guild Master and the officers hear about applications (SPEC-07 §6; the icon is M4.5). The
		-- same three switches are on the Applications tab.
		local notify = W.Card(host.content, { kind = "plain", title = L["SETTINGS_NOTIFY"], glyph = "glyph_inbox", height = 214 })
		notify:SetPoint("TOPLEFT", privacy, "BOTTOMLEFT", 0, -16)
		notify:SetPoint("TOPRIGHT", privacy, "BOTTOMRIGHT", 0, -16)
		local notifyNote = W.Text(notify.body, "caption", "ink3")
		notifyNote:SetPoint("TOPLEFT", notify.body, "TOPLEFT", 0, 0)
		notifyNote:SetPoint("RIGHT", notify.body, "RIGHT", 0, 0)
		notifyNote:SetWordWrap(true)
		notifyNote:SetText(L["SETTINGS_NOTIFY_NOTE"])
		if ns.AppsPanel then host.notifySwitches = ns.AppsPanel.BuildOptions(notify.body, 420, notifyNote, 8) end
		host.notify = notify
	end,
	OnShow = function(host)
		Main.scaleControl:SetSelected(Main:GetScale(), true)
		if ns.Stats then host.shareSwitch:SetChecked(ns.Stats:Sharing(), true) end
		-- only the Guild Master and the officers have notifications (SPEC-00 §5)
		local role = ns.Role and ns.Role:Get() or "none"
		host.notify:SetShown(host.notifySwitches ~= nil and ns.AppsModel ~= nil and ns.AppsModel.CanSee(role))
		if host.notifySwitches then host.notifySwitches.Refresh() end
	end,
})

---------------------------------------------------------------------------------------------------------------------
-- Commands and diagnostics
---------------------------------------------------------------------------------------------------------------------
-- /gf scale [60-140]: shows or sets the window size (the Settings page has the same control).
function Main:ScaleCommand(argument)
	local addon = ns.addon
	if argument == nil or argument == "" then
		addon:Print(L["SCALE_CURRENT"]:format(Nav.ScaleLabel(self:GetScale())))
		return
	end
	local scale = Nav.ParseScale(argument)
	if not scale then
		addon:Print(L["SCALE_BAD"]:format(tostring(argument):sub(1, 20)))
		return
	end
	addon:Print(L["SCALE_SET"]:format(Nav.ScaleLabel(self:SetScale(scale))))
end

function Main:DebugLines()
	local lines = {}
	lines[#lines + 1] = ("Window: %s, scale %s (in use %s), tabs %s, current %s, page depth %d"):format(
		self.frame and (self.frame:IsShown() and "open" or "closed") or "not built yet",
		Nav.ScaleLabel(self:GetScale()), self.effective and Nav.ScaleLabel(self.effective) or "-",
		table.concat(self.book:Tabs(), ","), tostring(self.book:Current()),
		self.book:Stack() and self.book:Stack():Depth() or 0)
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------------------------------------
if ns.Bus then
	-- a new role or guild: the tabs change and the window starts again on the first tab of the new role
	ns.Bus:On("ROLE_CHANGED", function() Main:RefreshTabs(true) end)
	-- a listing appearing or disappearing can add or remove a tab (Applications, Create Listing)
	ns.Bus:On("CATALOG_UPDATED", function()
		if Main:IsShown() then Main:RefreshTabs(false) end
	end)
end
if ns.addon then ns.addon.Main = Main end
