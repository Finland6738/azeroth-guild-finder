-- GuildPage: the page of one guild, for a visitor (SPEC-05 §3, mockup 02-guild-page). Lua 5.1.
--
-- Opened from a card of Find a Guild (Browse:OpenGuild pushes "GuildPage" with { k = guildKey } on the Find a Guild tab);
-- Back (the button of the title bar, or Backspace) returns to the list with its filters and its place.
--
--   Left page   the emblem (UI/Emblem.lua, 150 px), name, subtitle, tags (languages, faction, commitment); the Discord copy
--               field (the fixed prefix https://discord.gg/ plus the code: a click selects it all, Ctrl+C copies); the contact
--               characters with a Whisper button; "Listed since ... · Updated ..." at the bottom. Under the tags the Apply
--               button (UI/Apply.lua, M4.1) with its state and one line that explains it (SPEC-05 §4).
--   Right page  the banner by client fileID, the gold "Looking for" card over it, About, Activity (days and times in the
--               visitor's time zone, UTC smaller), Members (aggregates only), Requirements checked against the visitor,
--               How applying works. The page scrolls with the mouse wheel when it is taller than the window.
--
-- My Guild (UI/MyGuild.lua, M3.8) reuses the same drawing for the player's own guild, read-only: `GuildPage.Build(host)` builds the
-- frames into any host that has `left` and `content` frames, `GuildPage:Show(host, k, own)` points the page at a guild and
-- `GuildPage:Hide(host)` lets go of it. In "own" mode the guild's members are not visitors: nothing is checked against the
-- player (no "you are 32", no "they need your class") and the "How applying works" card is left out.
--
-- The page is drawn from the summary alone and completes when the detail arrives (SPEC-05 §3): About, Discord and the
-- contacts say "Loading details..." while Sync:RequestDetail waits (20 s), then "Details unavailable right now (...)". The
-- Bus tells when the detail lands (CATALOG_UPDATED k "detail") or does not (DETAIL_UNAVAILABLE k).
-- Every rule (what is shown, the times, the requirement checks, the sizes) is in UI/GuildPageModel.lua and is tested
-- without frames; this file creates frames and copies what the model says into them.
local ADDON_NAME, ns = ...
ns = ns or {}
local GuildPage = {}
ns.GuildPage, ns.modules = GuildPage, ns.modules or {}
ns.modules.GuildPage = GuildPage

local L, Skin, W, Main, Model, Browse = ns.L, ns.Skin, ns.Widgets, ns.Main, ns.GuildPageModel, ns.Browse
local type, ipairs, pairs, tostring = type, ipairs, pairs, tostring
local floor, max, min = math.floor, math.max, math.min

GuildPage.PAGE = "GuildPage"
GuildPage.WHEEL_STEP = 64
GuildPage.REFRESH_DELAY = 0.3      -- seconds a burst of catalog changes waits before the page is redrawn
GuildPage.unavailable = {}         -- k -> true once the detail request ended without an answer (memory only)

local VIEW_W, VIEW_H = Browse.VIEW_W, Browse.VIEW_H
GuildPage.VIEW_H = VIEW_H
local BAR_W = 10
local IW = VIEW_W - BAR_W - 8                 -- width of the page's content
local LW = 260                                -- width of the left page's area (312 - 30 - 22)
local GAP = 14
local COL_L = floor((IW - GAP) * 1.1 / 2.1)  -- the two columns of the lower part
local COL_R = IW - GAP - COL_L
local LOOK_X = 18
local LOOK_W = IW - 2 * LOOK_X
local BANNER_H = 150
local LOOK_Y = BANNER_H - 58
local CARD_TOP, CARD_BOTTOM = 42, 14          -- the title area and the bottom padding of a W.Card

local function after(seconds, fn) return ns.Compat.After(seconds, fn) end
local function clock() return ns.Compat.ServerTime() end

---------------------------------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------------------------------
-- Everything that takes the mouse must also pass the wheel on, or the page stops scrolling under it.
local function wheel(frame)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) GuildPage:ScrollBy(-delta * GuildPage.WHEEL_STEP) end)
	return frame
end

-- A wrapped text: sets it and returns how tall it came out.
local function setWrapped(fs, text, width)
	fs:SetWidth(width)
	fs:SetWordWrap(true)
	fs:SetText(text or "")
	local h = (text and text ~= "") and fs:GetStringHeight() or 0
	h = (type(h) == "number" and h > 0) and h or 0
	fs:SetHeight(max(h, 1))
	return h
end

-- A pool of frames made by make(i) the first time, shown for the first n and hidden after.
local function pooled(pool, n, make)
	for i = 1, n do
		if not pool[i] then pool[i] = make(i) end
		pool[i]:Show()
	end
	for i = n + 1, #pool do pool[i]:Hide() end
	return pool
end

local function roleBadges(owner, parent, roles, size, x, y)
	owner.roleBadges = owner.roleBadges or {}
	pooled(owner.roleBadges, #roles, function() return wheel(W.RoleBadge(parent, { size = size })) end)
	for i, r in ipairs(roles) do
		local b = owner.roleBadges[i]
		b:SetRole(r.key)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (size + 4), -y)
	end
	return #roles > 0 and (#roles * size + (#roles - 1) * 4) or 0
end

local function sizeCard(card, bodyHeight)
	card:SetHeight(CARD_TOP + bodyHeight + CARD_BOTTOM)
end

---------------------------------------------------------------------------------------------------------------------
-- Left page
---------------------------------------------------------------------------------------------------------------------
local function buildLeft(host)
	local left = host.left
	host.emblem = ns.Emblem.Create(left, 150)
	host.name = W.Text(left, "headline", "inkDeep", "CENTER")
	host.name:SetWidth(LW)
	host.name:SetWordWrap(true)
	host.name:SetMaxLines(2)
	host.sub = W.Text(left, "body", "ink2", "CENTER")
	host.sub:SetWidth(LW)
	host.sub:SetWordWrap(true)
	host.sub:SetMaxLines(3)
	host.tagHolder = CreateFrame("Frame", nil, left)
	host.tagHolder:SetSize(LW, 22)
	host.tags = {}
	host.appsNote = W.Text(left, "caption", "ink2", "CENTER")
	host.appsNote:SetText(L["GP_APPS_CLOSED"])
	host.apply = W.Button(left, { text = L["APPLY"], kind = "primary", size = "lg", width = LW })
	host.applyNote = W.Text(left, "caption", "ink2", "CENTER")
	host.divider = W.Divider(left, LW)
	host.contactTitle = W.Text(left, "overline", "ink3")
	host.contactTitle:SetText(L["GP_CONTACT"]:upper())
	host.copy = W.CopyField(left, { width = LW, text = "" })
	host.detailMsg = W.Text(left, "caption", "ink2")
	host.detailMsg:SetWidth(LW)
	host.detailMsg:SetWordWrap(true)
	host.contactRows = {}
	host.footer = W.Text(left, "caption", "ink3")
	host.footer:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 0)
	host.footer:SetWidth(LW)
	host.footer:SetWordWrap(true)
	host.footer:SetJustifyV("BOTTOM")
end

local function createContactRow(host, i)
	local row = CreateFrame("Frame", nil, host.left)
	row:SetSize(LW, 34)
	row.dot = W.Texture(row, "disc", "ARTWORK", "ok")
	row.dot:SetSize(9, 9)
	row.dot:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.dotArea = CreateFrame("Frame", nil, row)
	row.dotArea:SetSize(16, 24)
	row.dotArea:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.dotArea:EnableMouse(true)
	W.SetTooltip(row.dotArea, function() return row.online and L["GP_ONLINE_TIP"] or L["GP_OFFLINE_TIP"] end)
	row.name = W.Text(row, "titleS", "ink")
	row.name:SetPoint("LEFT", row, "LEFT", 20, 0)
	row.name:SetWidth(LW - 20 - 100)
	row.name:SetWordWrap(false)
	row.button = W.Button(row, { text = L["GP_WHISPER"], kind = "tonal", size = "sm",
		onClick = function() GuildPage:Whisper(row.contact) end })
	row.button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	return row
end

function GuildPage:Whisper(name)
	if type(name) ~= "string" then return end
	if not ns.Compat.Chat.OpenWhisper(name) then
		W.Snackbar.Show(L["GP_WHISPER_FAIL"]:format(name), { key = "whisper" })
	end
end

local function bindLeft(host, view)
	local left = host.left
	local items = {}   -- { frame, height, anchor }: placed one under the other
	local function add(frame, h, anchor) items[#items + 1] = { frame = frame, h = h or 0, anchor = anchor or "TOPLEFT" } end

	host.name:SetText(view.name)
	host.emblem:SetEmblem(view.emb, view.name)
	local nameH = host.name:GetStringHeight()
	nameH = (type(nameH) == "number" and nameH > 0) and nameH or 30
	host.name:SetHeight(nameH)

	if view.gone then
		host.sub:SetText("")
		host.tagHolder:Hide(); host.appsNote:Hide(); host.divider:Hide(); host.contactTitle:Hide(); host.copy:Hide()
		host.apply:Hide(); host.applyNote:Hide()
		host.detailMsg:Hide(); host.footer:SetText("")
		for _, row in ipairs(host.contactRows) do row:Hide() end
		add(host.emblem, 150, "TOP"); add(host.name, nameH, "TOP")
	else
		local subH = setWrapped(host.sub, view.sub or "", LW)
		-- tags (centred rows)
		host.tagHolder:Show()
		pooled(host.tags, #view.tags, function() return W.Tag(host.tagHolder, { text = "", kind = "default" }) end)
		local widths = {}
		for i, spec in ipairs(view.tags) do
			local tag = host.tags[i]
			tag:SetKind(spec.kind)
			tag:SetText(spec.text)
			widths[i] = tag:GetWidth()
			if spec.pace then
				tag:EnableMouse(true)
				W.SetTooltip(tag, { title = L["PACE_" .. spec.pace], lines = { L["PACE_" .. spec.pace .. "_TIP"] } })
				wheel(tag)
			else
				tag:EnableMouse(false)
				W.SetTooltip(tag, nil)
			end
		end
		local pos, tagsH = Model.Flow(widths, LW, 6, 22, 6, "center")
		for i, tag in ipairs(host.tags) do
			if pos[i] then
				tag:ClearAllPoints()
				tag:SetPoint("TOPLEFT", host.tagHolder, "TOPLEFT", pos[i].x, -pos[i].y)
			end
		end
		host.tagHolder:SetHeight(max(tagsH, 1))

		host.appsNote:SetShown(view.appsClosed)
		local noteH = 0
		if view.appsClosed then noteH = setWrapped(host.appsNote, L["GP_APPS_CLOSED"], LW) end
		host.divider:Show(); host.contactTitle:Show()

		-- Apply (a visitor only: the own guild's page in My Guild has none). Closed applications hide it (the note says so).
		local applyH, applyNoteH = 0, 0
		local apply = (not GuildPage.own) and ns.Apply and ns.Apply.Bind(host.apply, view.k, "page", LW) or nil
		GuildPage.applyView = apply
		if apply and apply.shown then
			applyH = host.apply:GetHeight()
			applyNoteH = setWrapped(host.applyNote, apply.note or "", LW)
		else
			host.apply:Hide()
		end
		host.applyNote:SetShown(applyNoteH > 0)

		add(host.emblem, 150, "TOP")
		add(host.name, nameH, "TOP")
		add(host.sub, subH, "TOP")
		add(host.tagHolder, tagsH, "TOP")
		add(host.apply, applyH, "TOP")
		add(host.applyNote, applyNoteH, "TOP")
		add(host.appsNote, noteH, "TOP")
		add(host.divider, 1)
		add(host.contactTitle, 14)

		-- Discord and contacts: they need the detail
		local contacts = view.contacts
		for _, row in ipairs(host.contactRows) do row:Hide() end
		if view.detail ~= "ready" then
			host.copy:Hide()
			add(host.detailMsg, setWrapped(host.detailMsg, view.detail == "loading" and L["GP_LOADING"] or L["GP_UNAVAILABLE"], LW))
		else
			local message
			if view.discord then
				host.copy:SetValue(view.discord)
				add(host.copy, 38)
			else
				message = L["GP_NO_DISCORD"]
			end
			host.copy:SetShown(view.discord ~= nil)
			if #contacts == 0 then message = message and (message .. " " .. L["GP_NO_CONTACTS"]) or L["GP_NO_CONTACTS"] end
			if message then add(host.detailMsg, setWrapped(host.detailMsg, message, LW)) end
			pooled(host.contactRows, #contacts, function(i) return createContactRow(host, i) end)
			for i, c in ipairs(contacts) do
				local row = host.contactRows[i]
				row.contact, row.online = c.name, c.online
				row.name:SetText(c.name)
				W.TintHex(row.dot, c.online and "#43a047" or "#9e9e9e")
				row.button.tooltipTitle = L["GP_WHISPER_TIP"]:format(c.name)
				add(row, 34)
			end
			host.detailMsg:SetShown(message ~= nil)
		end
		host.footer:SetText(view.footer or "")
	end

	local heights = {}
	for i, it in ipairs(items) do heights[i] = it.h end
	local ys = Model.Stack(heights, 8)
	for i, it in ipairs(items) do
		it.frame:ClearAllPoints()
		if it.anchor == "TOP" then it.frame:SetPoint("TOP", left, "TOP", 0, -ys[i])
		else it.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -ys[i]) end
		it.frame:SetShown(it.h > 0)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Right page: the pieces
---------------------------------------------------------------------------------------------------------------------
local function buildBanner(host)
	local banner = CreateFrame("Frame", nil, host.inner)
	banner:SetSize(IW, BANNER_H)
	banner:SetPoint("TOPLEFT", host.inner, "TOPLEFT", 0, 0)
	banner.fill = W.Texture(banner, "solid", "BACKGROUND", "#3a2a1a", 0.92)
	banner.fill:SetAllPoints(banner)
	banner.art = banner:CreateTexture(nil, "ARTWORK")
	banner.art:SetAllPoints(banner)
	banner.art:SetTexCoord(0, 1, 0.21, 0.79)
	banner.art:Hide()
	banner.edge = W.NineSlice(banner, "card_edge", { corner = 12, layer = "OVERLAY" })
	banner.edge:SetHex("#6e4c2c", 1)
	host.banner = banner
end

local function buildLooking(host)
	local card = W.Card(host.inner, { kind = "gold", title = L["GP_LOOKING"], glyph = "glyph_search", width = LOOK_W, height = 140 })
	card:SetFrameLevel(host.inner:GetFrameLevel() + 3)
	card:SetPoint("TOPLEFT", host.inner, "TOPLEFT", LOOK_X, -LOOK_Y)
	card.status = W.Tag(card, { text = "", kind = "ok" })
	card.you = W.Tag(card, { text = "", kind = "ok" })
	card.you:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -10)
	card.items = {}
	card.none = W.Text(card.body, "body", "ink2")
	card.none:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
	card.legend = CreateFrame("Frame", nil, card.body)
	card.legend:SetHeight(24)
	card.legend:SetPoint("BOTTOMLEFT", card.body, "BOTTOMLEFT", 0, 0)
	card.legend:SetPoint("BOTTOMRIGHT", card.body, "BOTTOMRIGHT", 0, 0)
	card.legendBadges, card.legendTexts = {}, {}
	host.look = card
end

local function createLookItem(card)
	local item = CreateFrame("Frame", nil, card.body)
	item:SetHeight(52)
	item.bg = W.NineSlice(item, "card", { corner = 10, layer = "BACKGROUND" })
	item.bg:SetHex("#ffffff", 0.55)
	item.edge = W.NineSlice(item, "card_edge", { corner = 10, layer = "BACKGROUND", sublevel = 1 })
	item.edge:SetHex("#b8820f", 0.45)
	item.icon = wheel(W.ClassIcon(item, { class = "WARRIOR", size = 40 }))
	item.icon:SetPoint("TOPLEFT", item, "TOPLEFT", 8, -6)
	item.name = W.Text(item, "titleS", "ink")
	item.name:SetWordWrap(false)
	return item
end

local function bindLooking(host, view, y)
	local card, look = host.look, view.looking
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", host.inner, "TOPLEFT", LOOK_X, -LOOK_Y)

	-- the status tag after the title, the "they need your class" tag at the right
	local titleW = W.TextWidth(L["GP_LOOKING"], "titleS")
	card.status:SetShown(look.status ~= nil)
	if look.status then
		card.status:SetKind(look.status.kind)
		card.status:SetText(look.status.text:upper())
		card.status:ClearAllPoints()
		card.status:SetPoint("TOPLEFT", card, "TOPLEFT", 44 + titleW + 12, -10)
	end
	card.you:SetShown(look.wantsYou ~= nil)
	if look.wantsYou then
		card.you:SetKind("ok")
		card.you:SetText(look.wantsYou.text)
	end

	-- the classes: boxes in rows that wrap
	local entries = {}
	for _, c in ipairs(look.classes) do entries[#entries + 1] = { class = c, roles = c.roles, name = c.name } end
	if look.any then entries[#entries + 1] = { any = true, roles = look.any.roles, name = L["LF_ANY_CLASS"] } end
	local bodyW = LOOK_W - 32
	pooled(card.items, #entries, function() return createLookItem(card) end)
	local widths = {}
	for i, e in ipairs(entries) do
		local item = card.items[i]
		local nameW = W.TextWidth(e.name, "titleS")
		local rolesW = #e.roles * 20 + max(0, #e.roles - 1) * 4
		local textW = max(nameW, rolesW)
		local lead = e.any and 12 or 58
		widths[i] = lead + textW + 12
		item:SetWidth(widths[i])
		item.name:SetText(e.name)
		item.name:ClearAllPoints()
		if e.any then
			item.icon:Hide()
			item.name:SetPoint("TOPLEFT", item, "TOPLEFT", lead, -8)
		else
			item.icon:Show()
			item.icon:SetClass(e.class.file)
			item.name:SetPoint("TOPLEFT", item, "TOPLEFT", lead, -8)
		end
		roleBadges(item, item, e.roles, 20, lead, 26)
	end
	local pos, itemsH = Model.Flow(widths, bodyW, 10, 52, 8)
	for i = 1, #entries do
		card.items[i]:ClearAllPoints()
		card.items[i]:SetPoint("TOPLEFT", card.body, "TOPLEFT", pos[i].x, -pos[i].y)
	end
	card.none:SetShown(look.none)
	if look.none then card.none:SetText(L["WANT_NONE"]); itemsH = 20 end

	-- the legend of the four role icons
	local x = 0
	for i, r in ipairs(look.legend) do
		local badge = card.legendBadges[i]
		if not badge then
			badge = wheel(W.RoleBadge(card.legend, { size = 18 }))
			card.legendBadges[i] = badge
			card.legendTexts[i] = W.Text(card.legend, "caption", "ink2")
		end
		badge:SetRole(r.key)
		badge:ClearAllPoints()
		badge:SetPoint("LEFT", card.legend, "LEFT", x, 0)
		local text = card.legendTexts[i]
		text:SetText(r.label)
		text:ClearAllPoints()
		text:SetPoint("LEFT", badge, "RIGHT", 6, 0)
		x = x + 18 + 6 + W.TextWidth(r.label, "caption") + 16
	end

	local bodyH = itemsH + (itemsH > 0 and 10 or 0) + 24
	sizeCard(card, bodyH)
	return card:GetHeight()
end

-- About: the description, or why there is none yet.
local function buildAbout(host)
	local card = W.Card(host.inner, { kind = "plain", title = L["GP_ABOUT"], glyph = "glyph_doc", width = COL_L, height = 100 })
	card.text = W.Text(card.body, "body", "ink")
	card.text:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
	host.about = card
end

local function bindAbout(host, view)
	local card = host.about
	local text, color
	if view.detail == "ready" then
		if view.desc and view.desc ~= "" then text, color = view.desc, "ink"
		else text, color = L["GP_NO_DESC"], "ink3" end
	else
		text, color = view.detail == "loading" and L["GP_LOADING"] or L["GP_UNAVAILABLE"], "ink3"
	end
	W.TextColor(card.text, color)
	local h = setWrapped(card.text, text, COL_L - 32)
	sizeCard(card, max(h, 16))
	return card:GetHeight()
end

local function buildActivity(host)
	local card = W.Card(host.inner, { kind = "plain", title = L["GP_ACTIVITY"], glyph = "glyph_gear", width = COL_L, height = 180 })
	card.pace = W.Tag(card.body, { text = "", kind = "casual" })
	card.pace:EnableMouse(true)
	wheel(card.pace)
	card.acts = {}
	card.days = W.DayBadges(card.body, { labels = { L["DAY_LETTER_1"], L["DAY_LETTER_2"], L["DAY_LETTER_3"], L["DAY_LETTER_4"],
		L["DAY_LETTER_5"], L["DAY_LETTER_6"], L["DAY_LETTER_7"] },
		names = { L["DAY_LONG_1"], L["DAY_LONG_2"], L["DAY_LONG_3"], L["DAY_LONG_4"], L["DAY_LONG_5"], L["DAY_LONG_6"], L["DAY_LONG_7"] } })
	for _, cell in ipairs(card.days.cells) do wheel(cell) end
	card.timeRow = CreateFrame("Frame", nil, card.body)
	card.timeRow:SetHeight(20)
	card.time = W.Text(card.timeRow, "monoM", "ink")
	card.time:SetPoint("LEFT", card.timeRow, "LEFT", 0, 0)
	card.yourTime = W.Text(card.timeRow, "caption", "ink3")
	card.yourTime:SetText(L["GP_YOUR_TIME"])
	card.yourTime:SetPoint("LEFT", card.time, "RIGHT", 8, 0)
	card.utc = W.Text(card.timeRow, "mono", "ink3")
	card.utc:SetPoint("LEFT", card.yourTime, "RIGHT", 10, 0)
	host.activity = card
end

local function bindActivity(host, view)
	local card, act = host.activity, view.activity
	local bodyW = COL_L - 32
	if act.pace then
		card.pace:SetKind(act.pace.kind)
		card.pace:SetText(act.pace.text:upper())
		W.SetTooltip(card.pace, { title = act.pace.text, lines = { act.pace.tip } })
	end
	card.pace:SetShown(act.pace ~= nil)

	pooled(card.acts, #act.acts, function() return W.Tag(card.body, { text = "", kind = "default" }) end)
	local widths = {}
	for i, a in ipairs(act.acts) do
		local tag = card.acts[i]
		tag:SetText(a.n .. "  " .. a.text)
		widths[i] = tag:GetWidth()
	end
	local pos, actsH = Model.Flow(widths, bodyW, 6, 22, 6)

	local timeH = act.timeText and 20 or 0
	local daysH = act.daysMask > 0 and 28 or 0
	local ys, total = Model.Stack({ act.pace and 22 or 0, actsH, daysH, timeH }, 10)
	card.pace:ClearAllPoints()
	card.pace:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -ys[1])
	for i = 1, #act.acts do
		card.acts[i]:ClearAllPoints()
		card.acts[i]:SetPoint("TOPLEFT", card.body, "TOPLEFT", pos[i].x, -(ys[2] + pos[i].y))
	end
	card.days:SetMask(act.daysMask)
	card.days:SetShown(daysH > 0)
	card.days:ClearAllPoints()
	card.days:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -ys[3])
	card.timeRow:SetShown(timeH > 0)
	card.timeRow:SetWidth(bodyW)
	card.timeRow:ClearAllPoints()
	card.timeRow:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -ys[4])
	card.time:SetText(act.timeText or "")
	card.yourTime:SetShown(act.timeText ~= nil and not act.allDay)
	card.utc:SetText(act.utcText or "")
	card.utc:SetShown(act.utcText ~= nil)
	sizeCard(card, total)
	return card:GetHeight()
end

local function statCell(parent, style, label, x, y, w)
	local cell = CreateFrame("Frame", nil, parent)
	cell:SetSize(w, 56)
	cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	cell.n = W.Text(cell, style, "ink")
	cell.n:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
	cell.l = W.Text(cell, "caption", "ink2")
	cell.l:SetPoint("TOPLEFT", cell.n, "BOTTOMLEFT", 0, -1)
	cell.l:SetWidth(w)
	cell.l:SetWordWrap(true)
	cell.l:SetText(label)
	return cell
end

local function buildMembers(host)
	local card = W.Card(host.inner, { kind = "plain", title = L["GP_MEMBERS"], glyph = "glyph_shield", width = COL_R, height = 230 })
	card.updated = W.Text(card, "caption", "ink3", "RIGHT")
	card.updated:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -17)
	local w = floor((COL_R - 32 - 12) / 2)
	card.unknown = W.Text(card.body, "body", "ink3")
	card.unknown:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
	card.unknown:SetText(L["MEMBERS_UNKNOWN"])
	card.cells = {
		active = statCell(card.body, "headline", L["MEMBERS_ACTIVE"], 0, 0, w),
		unique = statCell(card.body, "headline", L["MEMBERS_UNIQUE"], w + 12, 0, w),
		total = statCell(card.body, "titleL", L["MEMBERS_TOTAL"], 0, 68, w),
		max = statCell(card.body, "titleL", L["MEMBERS_MAX"], w + 12, 68, w),
	}
	card.cells.unique:EnableMouse(true)
	wheel(card.cells.unique)
	W.SetTooltip(card.cells.unique, { title = L["MEMBERS_UNIQUE"], lines = { L["MEMBERS_UNIQUE_TIP"] } })
	card.bar = CreateFrame("Frame", nil, card.body)
	card.bar:SetHeight(10)
	card.bar:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -134)
	card.bar:SetPoint("TOPRIGHT", card.body, "TOPRIGHT", 0, -134)
	card.bar.back = W.Texture(card.bar, "solid", "BACKGROUND", "#2a1a0a", 0.35)
	card.bar.back:SetAllPoints(card.bar)
	card.segments = {}
	card.mix = W.Text(card.body, "caption", "ink3")
	card.mix:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -150)
	card.mix:SetText(L["MEMBERS_MIX"])
	host.members = card
end

local function bindMembers(host, view)
	local card, m = host.members, view.members
	card.unknown:SetShown(not m.known)
	card.updated:SetText(m.known and m.updatedText or "")
	for _, cell in pairs(card.cells) do cell:SetShown(m.known) end
	local mixShown = m.known and #m.mix > 0
	card.bar:SetShown(mixShown)
	card.mix:SetShown(mixShown)
	if not m.known then
		sizeCard(card, 20)
		return card:GetHeight()
	end
	card.cells.active.n:SetText(tostring(m.active))
	card.cells.unique.n:SetText(m.unique or "–")
	card.cells.total.n:SetText(m.total and tostring(m.total) or "–")
	card.cells.max.n:SetText(m.maxLevel and tostring(m.maxLevel) or "–")
	local barW = COL_R - 32
	pooled(card.segments, #m.mix, function() return card.bar:CreateTexture(nil, "ARTWORK") end)
	local x = 0
	for i, seg in ipairs(m.mix) do
		local t = card.segments[i]
		t:SetTexture(W.Media("solid"))
		t:SetVertexColor(ns.Assets.ClassColor(seg.file))
		local w = (i == #m.mix) and (barW - x) or floor(seg.fraction * barW + 0.5)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", card.bar, "TOPLEFT", x, 0)
		t:SetSize(max(w, 1), 10)
		x = x + w
	end
	sizeCard(card, mixShown and 168 or 124)
	return card:GetHeight()
end

local function buildRequirements(host)
	local card = W.Card(host.inner, { kind = "plain", title = L["GP_REQUIREMENTS"], glyph = "glyph_check", width = COL_R, height = 130 })
	card.rows = {}
	host.reqs = card
end

local function createReqRow(card)
	local row = CreateFrame("Frame", nil, card.body)
	row.icon = W.Texture(row, "glyph_check", "ARTWORK", nil)
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
	row.dash = W.Text(row, "body", "ink3")
	row.dash:SetPoint("TOPLEFT", row, "TOPLEFT", 4, 0)
	row.dash:SetText("–")
	row.text = W.Text(row, "body", "ink")
	row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 24, 0)
	row.you = W.Text(row, "caption", "ink2")
	return row
end

local function bindRequirements(host, view)
	local card, req = host.reqs, view.requirements
	local rows = {}
	for _, item in ipairs(req.items) do rows[#rows + 1] = item end
	if req.note and req.note ~= "" then rows[#rows + 1] = { id = "note", note = true, text = L["REQ_NOTE"]:format(req.note) } end
	pooled(card.rows, #rows, function() return createReqRow(card) end)
	local width = COL_R - 32
	local heights, kept = {}, {}
	for i, item in ipairs(rows) do
		local row = card.rows[i]
		local mark = item.ok
		row.icon:SetShown(mark ~= nil)
		row.dash:SetShown(mark == nil and not item.note)
		if mark ~= nil then
			row.icon:SetTexture(W.Media(mark and "glyph_check" or "glyph_close"))
			W.TintHex(row.icon, mark and "#2e7d32" or "#b3261e")
		end
		W.TextColor(row.text, item.muted and "ink3" or (mark == false and "bad" or (item.note and "ink2" or "ink")))
		row.you:ClearAllPoints()
		local h
		if item.note then
			row.you:SetText("")
			h = setWrapped(row.text, item.text, width - 24)
		else
			row.text:SetWidth(0)
			row.text:SetWordWrap(false)
			row.text:SetText(item.text)
			row.you:SetText(item.you or "")
			row.you:SetPoint("LEFT", row.text, "RIGHT", 6, 0)
			h = 18
		end
		heights[i] = max(h, 18) + 4
		row:SetSize(width, heights[i])
	end
	local ys, total = Model.Stack(heights, 2)
	for i = 1, #rows do
		card.rows[i]:ClearAllPoints()
		card.rows[i]:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -ys[i])
	end
	sizeCard(card, max(total, 20))
	return card:GetHeight()
end

local function buildHow(host)
	local card = W.Card(host.inner, { kind = "plain", title = L["HOW_TITLE"], glyph = "glyph_doc", width = IW, height = 90 })
	card.text = W.Text(card.body, "caption", "ink2")
	card.text:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, 0)
	host.how = card
end

local function bindHow(host)
	local card = host.how
	local h = setWrapped(card.text, L["HOW_BODY"], IW - 32)
	sizeCard(card, max(h, 16))
	return card:GetHeight()
end

---------------------------------------------------------------------------------------------------------------------
-- Right page: scrolling and the whole
---------------------------------------------------------------------------------------------------------------------
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
		if not GuildPage.settingBar then GuildPage:SetOffset(value) end
	end)
	bar:Hide()
	host.bar = bar
end

local function buildRight(host)
	local view = CreateFrame("Frame", nil, host.content)
	view:SetPoint("TOPLEFT", host.content, "TOPLEFT", 0, 0)
	view:SetSize(IW, VIEW_H)
	view:SetClipsChildren(true)
	wheel(view)
	host.view = view
	host.inner = CreateFrame("Frame", nil, view)
	host.inner:SetSize(IW, VIEW_H)
	host.inner:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
	buildBanner(host)
	buildLooking(host)
	buildAbout(host)
	buildActivity(host)
	buildMembers(host)
	buildRequirements(host)
	buildHow(host)
	buildScrollBar(host)
	host.goneText = W.Text(host.content, "bodyL", "ink2", "CENTER")
	host.goneText:SetPoint("CENTER", host.content, "CENTER", 0, 20)
	host.goneText:SetWidth(440)
	host.goneText:SetWordWrap(true)
	host.goneText:SetText(L["GP_GONE"])
	host.goneText:Hide()
end

local function bindRight(host, view)
	host.goneText:SetShown(view.gone == true)
	host.view:SetShown(not view.gone)
	if view.gone then
		host.bar:Hide()
		return
	end
	local file = ns.Assets.Banner(view.bg)
	if file then host.banner.art:SetTexture(file) end
	host.banner.art:SetShown(file ~= nil)

	local lookH = bindLooking(host, view)
	local aboutH, actH = bindAbout(host, view), bindActivity(host, view)
	local memH, reqH = bindMembers(host, view), bindRequirements(host, view)
	local own = GuildPage.own == true
	local howH = own and 0 or bindHow(host)
	host.how:SetShown(not own)
	local y0 = LOOK_Y + lookH + GAP
	local ly, ry, colsH = Model.Columns({ aboutH, actH }, { memH, reqH }, GAP)
	local function put(card, x, y)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", host.inner, "TOPLEFT", x, -y)
	end
	put(host.about, 0, y0 + ly[1]); put(host.activity, 0, y0 + ly[2])
	put(host.members, COL_L + GAP, y0 + ry[1]); put(host.reqs, COL_L + GAP, y0 + ry[2])
	local howY = y0 + colsH + GAP
	put(host.how, 0, howY)
	GuildPage.contentH = own and (y0 + colsH + 4) or (howY + howH + 4)
	host.inner:SetHeight(GuildPage.contentH)
end

---------------------------------------------------------------------------------------------------------------------
-- Scrolling
---------------------------------------------------------------------------------------------------------------------
function GuildPage:SetOffset(value, quiet)
	local host = self.host
	if not host or not host.inner then return end
	local contentH = self.contentH or VIEW_H
	self.offset = Model.ClampScroll(value, contentH, VIEW_H)
	host.inner:ClearAllPoints()
	host.inner:SetPoint("TOPLEFT", host.view, "TOPLEFT", 0, self.offset)
	local maxOffset = Model.ScrollMax(contentH, VIEW_H)
	self.settingBar = true
	host.bar:SetMinMaxValues(0, maxOffset)
	host.bar:SetValue(self.offset)
	self.settingBar = false
	host.bar.thumb:SetHeight(max(28, VIEW_H * (VIEW_H / max(contentH, VIEW_H))))
	host.bar:SetShown(maxOffset > 0 and not (self.view and self.view.gone))
end

function GuildPage:ScrollBy(delta) self:SetOffset((self.offset or 0) + delta) end

---------------------------------------------------------------------------------------------------------------------
-- Data and drawing
---------------------------------------------------------------------------------------------------------------------
function GuildPage:IsShown() return self.host ~= nil and self.host.shown == true end

local function heardContacts(k)
	local Sync = ns.Sync
	if not (Sync and Sync.Contacts) then return {} end
	return Sync:Contacts(k, Model.ONLINE_WINDOW)
end

-- Builds the view from the catalog and the client and draws it. `resetScroll`: back to the top (a page just opened).
function GuildPage:Refresh(resetScroll)
	local host, k = self.host, self.k
	if not host or not k or not ns.Catalog then return end
	local entry, status = ns.Catalog:Get(k)
	-- our own guild: the roster's statistics right away, when they are newer than the last ANN's (Data/Stats.lua)
	if entry and entry.sum and ns.Stats then
		local sum = ns.Stats:Overlay(entry.sum)
		if sum ~= entry.sum then
			local copy = {}
			for f, v in pairs(entry) do copy[f] = v end
			copy.sum, entry = sum, copy
		end
	end
	local view = Model.View({ k = k, entry = entry, status = status, player = (not self.own) and ns.BrowseModel.Player() or nil, now = clock(),
		heard = heardContacts(k), unavailable = self.unavailable[k], L = L })
	self.view = view
	bindLeft(host, view)
	bindRight(host, view)
	self:SetOffset(resetScroll and 0 or self.offset or 0)
	return view
end

-- Asks the network for the detail when the listing has none (or an older one). A listing that only exists on this computer
-- (the development seed) has nobody to ask: it ends as "unavailable" at once.
function GuildPage:RequestDetail()
	local k = self.k
	local entry = ns.Catalog and ns.Catalog:Get(k)
	if not entry or (entry.det and entry.det.rev >= entry.sum.rev) then return end
	if entry.localOnly then
		if not entry.det then self.unavailable[k] = true end
		return
	end
	if ns.Sync and ns.Sync.RequestDetail then ns.Sync:RequestDetail(k) end
end

-- A change in the catalog: a detail that arrived, or a listing that went away, is drawn at once; statistics and edits
-- (frequent) after a short wait.
function GuildPage:OnCatalogChanged(k, what)
	if not self:IsShown() or (k ~= nil and k ~= self.k) then return end
	if what == "detail" or what == "delisted" or what == "removed" or k == nil then
		self.coalescer:Cancel()
		self:Refresh()
	else
		self.coalescer:Request()
	end
end

function GuildPage:OnDetailUnavailable(k)
	self.unavailable[k] = true
	if self:IsShown() and k == self.k then self:Refresh() end
end

---------------------------------------------------------------------------------------------------------------------
-- The page of the window
---------------------------------------------------------------------------------------------------------------------
local function title(params)
	local _, _, name = ns.Listing.ParseKey(params and params.k)
	return name or ""
end

-- Builds the frames of the page into `host` (any table with `left` and `content` frames). Once per host.
function GuildPage.Build(host)
	GuildPage.host = host
	GuildPage.coalescer = ns.BrowseModel.NewCoalescer(after, GuildPage.REFRESH_DELAY, function()
		if GuildPage:IsShown() then GuildPage:Refresh() end
	end)
	buildLeft(host)
	buildRight(host)
end

-- Points the page at guild `k` on `host` (the caller has set host.shown) and draws it. own: the player's own guild (My Guild).
function GuildPage:Show(host, k, own)
	self.host, self.k, self.own = host, k, own == true
	self.unavailable[k or ""] = nil
	self.offset = 0
	self:RequestDetail()
	self:Refresh(true)
end

-- The page leaves the screen (the caller has hidden its frames).
function GuildPage:Hide(host)
	host.shown = false
	if self.coalescer then self.coalescer:Cancel() end
	W.HideTooltip()
end

Main:RegisterPage(GuildPage.PAGE, {
	title = title,
	Build = GuildPage.Build,
	OnShow = function(host, params)
		GuildPage:Show(host, params and params.k, false)
		Main:SetStatus("", nil)
	end,
	OnHide = function(host) GuildPage:Hide(host) end,
})

if ns.Bus then
	ns.Bus:On("CATALOG_UPDATED", function(k, what) GuildPage:OnCatalogChanged(k, what) end)
	ns.Bus:On("DETAIL_UNAVAILABLE", function(k) GuildPage:OnDetailUnavailable(k) end)
	ns.Bus:On("STATS_CHANGED", function(k) GuildPage:OnCatalogChanged(k, "stats") end)
	-- an application saved, withdrawn or answered changes the Apply button
	ns.Bus:On("APPLICATION_CHANGED", function() if GuildPage:IsShown() then GuildPage:Refresh() end end)
end
if ns.addon then ns.addon.GuildPage = GuildPage end
