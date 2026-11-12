-- MyGuild: the "My Guild" tab (SPEC-06 §1, SPEC-00 §5, mockup 06, M3.8). Lua 5.1.
--
-- What each role sees (the rules are in UI/MyGuildModel.lua and are tested without frames):
--   member   the guild's page read-only (the same page the visitors see, UI/GuildPage.lua in "own" mode), a note that only
--            the Guild Master can edit the listing
--   officer  the same, plus a line with the number of pending applications (it opens the Applications tab)
--   GM       the same with Edit listing (opens the editor on the listing, pushed on this tab) and Delist (asks first), plus
--            the same Applications line
-- A guild without a listing shows an empty state ("Your guild has no listing yet", with a message to copy for the Guild
-- Master); a member who has just logged in and whose copy may still be on its way sees "Waiting for your guild's listing..."
-- for up to OwnListing.ARRIVAL_WAIT seconds. A Guild Master without a listing has no My Guild at all: the window gives
-- that role the Create Listing tab (Nav.TabsFor).
--
-- The guild's page lives in a sub-host (two frames that are children of the host's `left` and `content`), so that the empty
-- state can take its place and give it back without GuildPage knowing.
local ADDON_NAME, ns = ...
ns = ns or {}
local MyGuild = {}
ns.MyGuild, ns.modules = MyGuild, ns.modules or {}
ns.modules.MyGuild = MyGuild

local L, Skin, W, Main, Model, GuildPage = ns.L, ns.Skin, ns.Widgets, ns.Main, ns.MyGuildModel, ns.GuildPage
local type, ipairs, xpcall = type, ipairs, xpcall
local cos, sin = math.cos, math.sin

MyGuild.PAGE = "MyGuild"
MyGuild.POLL = 5            -- seconds between two looks while "waiting for the listing" shows
local LW = 260              -- width of the left page's area

local function after(seconds, fn) return ns.Compat.After(seconds, fn) end

-- The guild key of the player and the name in it, or nil without a guild.
local function ownKey()
	local key = ns.Role and ns.Role:GuildKey()
	if not key then return nil end
	local _, _, name = ns.Listing.ParseKey(key)
	return key, name
end

-- The context the model decides from: the role, the catalog's status of our guild, the wait for the copy.
function MyGuild:Context()
	local role = ns.Role and ns.Role:Get() or "none"
	local key = ownKey()
	return {
		role = role, key = key,
		status = key and ns.Catalog and ns.Catalog:Status(key) or nil,
		waiting = ns.OwnListing ~= nil and ns.OwnListing:Waiting() or false,
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
-- The left page of the empty and waiting states: the guild's name, its emblem as a ghost, and the role.
local function buildEmptyLeft(host)
	local f = CreateFrame("Frame", nil, host.left)
	f:SetAllPoints(host.left)
	f:Hide()
	f.emblem = ns.Emblem.Create(f, 150)
	f.emblem:SetPoint("TOP", f, "TOP", 0, 0)
	f.emblem:SetAlpha(0.6)
	f.name = W.Text(f, "headline", "#3a200c", "CENTER")
	f.name:SetWidth(LW)
	f.name:SetWordWrap(true)
	f.name:SetMaxLines(2)
	f.name:SetPoint("TOP", f.emblem, "BOTTOM", 0, -10)
	f.role = W.Text(f, "overline", "ink3", "CENTER")
	f.role:SetWidth(LW)
	f.role:SetPoint("TOP", f.name, "BOTTOM", 0, -6)
	host.emptyLeft = f
end

-- The right page of the empty and waiting states.
local function buildEmptyContent(host)
	local f = CreateFrame("Frame", nil, host.content)
	f:SetAllPoints(host.content)
	f:Hide()
	local box = CreateFrame("Frame", nil, f)
	box:SetSize(460, 300)
	box:SetPoint("CENTER", f, "CENTER", 0, 20)
	f.box = box

	-- the spinner of the waiting state (its OnUpdate runs only while it shows)
	box.ring = W.Texture(box, "disc_ring", "ARTWORK", "line2")
	box.ring:SetSize(40, 40)
	box.ring:SetPoint("TOP", box, "TOP", 0, 0)
	box.dot = W.Texture(box, "disc", "OVERLAY", "gold2")
	box.dot:SetSize(9, 9)
	box.spin = CreateFrame("Frame", nil, box)
	local angle = 0
	box.spin:SetScript("OnUpdate", function(_, dt)
		angle = (angle - dt * 5) % 6.2832
		box.dot:ClearAllPoints()
		box.dot:SetPoint("CENTER", box.ring, "CENTER", 16 * cos(angle), 16 * sin(angle))
	end)

	box.title = W.Text(box, "titleL", "ink", "CENTER")
	box.title:SetWidth(440)
	box.title:SetWordWrap(true)
	box.title:SetPoint("TOP", box, "TOP", 0, -56)
	box.body = W.Text(box, "bodyL", "ink2", "CENTER")
	box.body:SetWidth(420)
	box.body:SetWordWrap(true)
	box.body:SetPoint("TOP", box.title, "BOTTOM", 0, -10)

	-- a message for the Guild Master, ready to select and copy
	box.copy = W.CopyField(box, { width = 420, text = L["MG_MESSAGE"], hint = L["MG_COPY_HINT"] })
	box.copy:SetPoint("TOP", box.body, "BOTTOM", 0, -22)
	box.copyHint = W.Text(box, "caption", "ink3", "CENTER")
	box.copyHint:SetWidth(420)
	box.copyHint:SetWordWrap(true)
	box.copyHint:SetText(L["MG_COPY_HINT"])
	box.copyHint:SetPoint("TOP", box.copy, "BOTTOM", 0, -8)
	host.emptyContent = f
end

-- The Guild Master's two buttons, the note for everybody else and the Applications placeholder, over the guild page's footer.
local function buildExtras(host)
	local left = host.left
	-- the Applications line: how many wait, and a click opens the Applications tab (M4.4)
	host.apps = CreateFrame("Button", nil, left)
	host.apps:SetSize(LW, 52)
	host.apps:RegisterForClicks("LeftButtonUp")
	host.apps:SetScript("OnClick", function() Main:Select("Applications") end)
	host.apps.title = W.Text(host.apps, "overline", "ink3")
	host.apps.title:SetPoint("TOPLEFT", host.apps, "TOPLEFT", 0, 0)
	host.apps.title:SetText(L["MG_APPS_TITLE"]:upper())
	host.apps.text = W.Text(host.apps, "caption", "ink2")
	host.apps.text:SetPoint("TOPLEFT", host.apps.title, "BOTTOMLEFT", 0, -3)
	host.apps.text:SetWidth(LW)
	host.apps.text:SetWordWrap(true)
	host.apps.text:SetText(L["MG_APPS_NONE"])
	host.apps:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 96)
	host.apps:Hide()

	host.note = W.Text(left, "caption", "ink2")
	host.note:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 44)
	host.note:SetWidth(LW)
	host.note:SetWordWrap(true)
	host.note:SetText(L["MG_ONLY_GM"])
	host.note:Hide()

	host.edit = W.Button(left, { text = L["MG_EDIT"], kind = "primary", size = "md", width = 150, tooltip = L["MG_EDIT_TIP"],
		onClick = function() MyGuild:Edit() end })
	host.edit:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 42)
	host.edit:Hide()
	host.delist = W.Button(left, { text = L["ED_DELIST"], kind = "tonal", size = "md", width = 100,
		onClick = function() MyGuild:Ask() end })
	host.delist:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, 42)
	host.delist:Hide()

	-- the question before Delist, over the buttons
	local c = CreateFrame("Frame", nil, left)
	c:SetSize(LW + 12, 130)
	c:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", -6, 34)
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
	c.text:SetText(L["ED_DELIST_CONFIRM"])
	c.yes = W.Button(c, { text = L["ED_DELIST"], kind = "primary", size = "sm", onClick = function() MyGuild:Answer(true) end })
	c.yes:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 14, 14)
	c.no = W.Button(c, { text = L["ED_CANCEL"], kind = "tonal", size = "sm", onClick = function() MyGuild:Answer(false) end })
	c.no:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 14)
	c:Hide()
	host.confirm = c
end

local function build(host)
	MyGuild.host = host
	-- the guild's page: two frames of its own, so that the empty state can replace them
	local sub = { id = "MyGuild.page" }
	sub.left = CreateFrame("Frame", nil, host.left)
	sub.left:SetAllPoints(host.left)
	sub.content = CreateFrame("Frame", nil, host.content)
	sub.content:SetAllPoints(host.content)
	sub.left:Hide(); sub.content:Hide()
	host.page = sub
	GuildPage.Build(sub)
	buildEmptyLeft(host)
	buildEmptyContent(host)
	buildExtras(host)
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
function MyGuild:IsShown() return self.host ~= nil and self.host.shown == true end

-- Shows or hides the guild's page and the frames that go with it.
local function setListing(host, shown, key)
	local sub = host.page
	if shown then
		if not sub.shown or host.pageKey ~= key then
			sub.shown, host.pageKey = true, key
			sub.left:Show(); sub.content:Show()
			GuildPage:Show(sub, key, true)
		else
			GuildPage.host, GuildPage.k, GuildPage.own = sub, key, true
			GuildPage:Refresh()
		end
	elseif sub.shown then
		GuildPage:Hide(sub)
		sub.left:Hide(); sub.content:Hide()
		host.pageKey = nil
	end
end

function MyGuild:Refresh()
	local host = self.host
	if not host or not host.shown then return end
	local ctx = self:Context()
	local view = Model.View(ctx)
	self.view, self.ctx = view, ctx
	local _, name = ownKey()
	local listing = view.page and view.kind == "listing"
	setListing(host, listing, ctx.key)

	host.emptyLeft:SetShown(view.page and not listing)
	host.emptyContent:SetShown(view.page and not listing)
	host.edit:SetShown(listing and view.edit)
	host.delist:SetShown(listing and view.delist)
	host.note:SetShown(listing and view.readOnly)
	host.apps:SetShown(listing and view.applications)
	if listing and view.applications then
		local n = ns.AppsPanel and ns.AppsPanel:PendingCount() or 0
		host.apps.text:SetText(n == 0 and L["MG_APPS_NONE"] or (n == 1 and L["MG_APPS_ONE"] or L["MG_APPS_N"]:format(n)))
	end
	if not (listing and view.delist) then host.confirm:Hide() end

	if listing then
		self:StopPoll()
		Main:SetStatus(L["MG_STATUS"]:format(L[view.roleLabelKey]), "ok")
	elseif view.page then
		local box = host.emptyContent.box
		local loading = view.kind == "loading"
		host.emptyLeft.name:SetText(name or "")
		host.emptyLeft.emblem:SetEmblem(nil, name)
		host.emptyLeft.role:SetText(L[view.roleLabelKey]:upper())
		box.ring:SetShown(loading)
		box.dot:SetShown(loading)
		box.spin:SetShown(loading)
		box.title:SetText(loading and L["MG_LOADING_TITLE"] or L["MG_NONE_TITLE"])
		box.body:SetText(loading and L["MG_LOADING_BODY"] or L["MG_NONE_BODY"])
		box.title:ClearAllPoints()
		box.title:SetPoint("TOP", box, "TOP", 0, loading and -56 or 0)
		box.copy:SetShown(view.copyMessage)
		box.copyHint:SetShown(view.copyMessage)
		if loading then self:StartPoll() else self:StopPoll() end
		Main:SetStatus("", nil)
	else
		self:StopPoll()
		Main:SetStatus("", nil)
	end
end

-- While "waiting for the listing" shows: look again every POLL seconds (the wait ends by itself).
function MyGuild:StartPoll()
	if self.polling then return end
	self.polling = true
	self.pollGen = (self.pollGen or 0) + 1
	local gen = self.pollGen
	local function tick()
		if gen ~= self.pollGen then return end
		if not self:IsShown() then self.polling = false return end
		self:Refresh()
		if gen == self.pollGen and self.polling then after(MyGuild.POLL, tick) end
	end
	after(MyGuild.POLL, tick)
end

function MyGuild:StopPoll()
	self.polling = false
	self.pollGen = (self.pollGen or 0) + 1
end

---------------------------------------------------------------------------------------------------------------------
-- The Guild Master's buttons
---------------------------------------------------------------------------------------------------------------------
-- Edit listing: the editor pushed on this tab, on the published version. Only the Guild Master (the editor refuses anybody else).
function MyGuild:Edit()
	local view = self.view
	if not (view and view.edit) then return false end
	if ns.Editor then ns.Editor:Open() end
	return true
end

-- Delist asks first.
function MyGuild:Ask()
	local host = self.host
	local view = self.view
	if not host or not (view and view.delist) then return false end
	host.confirm:Show()
	return true
end

-- The answer: true withdraws the listing (OwnListing checks that the character is still the Guild Master), false only closes
-- the question. The window then follows the catalog: without a listing the Guild Master gets Create Listing back.
function MyGuild:Answer(yes)
	local host = self.host
	if not host then return false end
	host.confirm:Hide()
	if not yes then return false end
	local ok, why = ns.OwnListing:Delist()
	W.Snackbar.Show(ns.OwnListing:Explain(why), { key = "myguild" })
	self:Refresh()
	return ok, why
end

---------------------------------------------------------------------------------------------------------------------
-- The page of the window
---------------------------------------------------------------------------------------------------------------------
Main:RegisterPage(MyGuild.PAGE, {
	title = function()
		local _, name = ownKey()
		return name or ""
	end,
	Build = build,
	OnShow = function(host)
		MyGuild.host = host
		host.confirm:Hide()
		MyGuild:Refresh()
	end,
	OnHide = function(host)
		MyGuild:StopPoll()
		host.confirm:Hide()
		if host.page.shown then
			GuildPage:Hide(host.page)
			host.page.left:Hide(); host.page.content:Hide()
			host.pageKey = nil
		end
		host.shown = false
		W.HideTooltip()
	end,
})

if ns.Bus then
	-- anything that changes what the page holds redraws it: the catalog (a listing came or went), our own copy, the role
	ns.Bus:On("CATALOG_UPDATED", function(k)
		if MyGuild:IsShown() and (k == nil or k == ownKey()) then MyGuild:Refresh() end
	end)
	ns.Bus:On("OWN_LISTING_CHANGED", function() if MyGuild:IsShown() then MyGuild:Refresh() end end)
	ns.Bus:On("ROLE_CHANGED", function() if MyGuild:IsShown() then MyGuild:Refresh() end end)
	ns.Bus:On("INBOX_CHANGED", function() if MyGuild:IsShown() then MyGuild:Refresh() end end)
end

function MyGuild:DebugLines()
	local ctx = self:Context()
	local view = Model.View(ctx)
	return { ("My Guild: role %s, catalog %s, waiting for the copy %s -> %s%s"):format(ctx.role, tostring(ctx.status),
		ctx.waiting and "yes" or "no", view.page and view.kind or "no My Guild tab",
		(view.edit and ", Edit and Delist" or "") .. (view.applications and ", Applications line" or "")) }
end

if ns.addon then
	ns.addon.MyGuild = MyGuild
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("My Guild", function() return MyGuild:DebugLines() end) end
end
