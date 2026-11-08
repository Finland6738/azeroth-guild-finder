-- Gallery: one of every widget on one page, for the in-game look-and-feel check (docs/checklists/M2.md). Development
-- builds only: /gf debug gallery opens it on the current tab; release builds refuse. Nothing here is saved or sent.
-- Use it with /gf scale 60 and /gf scale 140 to see that every widget stays readable at both ends of the range.
local ADDON_NAME, ns = ...
ns = ns or {}
local Gallery = {}
ns.Gallery, ns.modules = Gallery, ns.modules or {}
ns.modules.Gallery = Gallery

local L, W, Main = ns.L, ns.Widgets, ns.Main
local ipairs = ipairs

Gallery.PAGE = "Gallery"

-- Places `frames` in a row starting at (x, y) under `parent`, `gap` px apart. Returns the x after the last one.
local function row(parent, x, y, gap, frames)
	for _, f in ipairs(frames) do
		f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
		x = x + f:GetWidth() + gap
	end
	return x
end

local function build(host)
	-- left page: small things
	local left = host.left
	host.plate = W.Plate(left, { text = L["GALLERY_BADGES"], width = 260 })
	host.plate:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
	local tags = {}
	for _, kind in ipairs({ "default", "ok", "bad", "gold", "casual", "soft", "hard" }) do
		tags[#tags + 1] = W.Tag(left, { text = L["GALLERY_SAMPLE"], kind = kind })
	end
	-- two rows of tags
	row(left, 0, 52, 6, { tags[1], tags[2], tags[3] })
	row(left, 0, 80, 6, { tags[4], tags[5], tags[6], tags[7] })
	row(left, 0, 116, 14, { W.Badge(left, { count = 3 }), W.Badge(left, { count = 42 }), W.Badge(left, { count = 120 }) })
	local roles = {}
	for _, role in ipairs({ "tank", "healer", "melee", "ranged" }) do roles[#roles + 1] = W.RoleBadge(left, { role = role, size = 28 }) end
	row(left, 0, 150, 10, roles)
	local classes = {}
	for _, file in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
		classes[#classes + 1] = W.ClassIcon(left, { class = file, size = 26 })
	end
	row(left, 4, 200, 14, { classes[1], classes[2], classes[3], classes[4], classes[5] })
	row(left, 4, 240, 14, { classes[6], classes[7], classes[8], classes[9] })
	local big = W.ClassIcon(left, { class = "DRUID", size = 40 })
	local small = W.ClassIcon(left, { class = "DRUID", size = 20 })
	row(left, 4, 284, 18, { big, small })
	local y = 340
	for _, kind in ipairs({ "plain", "elevated", "gold" }) do
		local card = W.Card(left, { kind = kind, title = L["GALLERY_CARDS"] .. " - " .. kind, width = 250, height = 74 })
		card:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -y)
		y = y + 88
	end

	-- right page: controls
	local c = host.content
	local buttons = W.Card(c, { kind = "plain", title = L["GALLERY_BUTTONS"], width = 740, height = 150 })
	buttons:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
	local body = buttons.body
	row(body, 0, 0, 12, {
		W.Button(body, { text = L["GALLERY_PRIMARY"], kind = "primary", size = "lg" }),
		W.Button(body, { text = L["GALLERY_PRIMARY"], kind = "primary" }),
		W.Button(body, { text = L["GALLERY_DISCORD"], kind = "discord", glyph = "glyph_copy" }),
		W.Button(body, { text = L["GALLERY_TONAL"], kind = "tonal" }),
		W.Button(body, { text = L["GALLERY_GHOST"], kind = "ghost" }),
	})
	local reasoned = W.Button(body, { text = L["GALLERY_DISABLED"], kind = "primary", enabled = false, reason = L["GALLERY_REASON"] })
	local withGlyph = W.Button(body, { text = L["BTN_BACK"], kind = "tonal", glyph = "glyph_back", size = "sm" })
	local snack = W.Button(body, { text = L["GALLERY_SNACK"], kind = "metal", size = "sm",
		onClick = function() W.Snackbar.Show(L["GALLERY_SNACK_TEXT"], { action = { text = L["BTN_CLOSE"], onClick = function() end } }) end })
	row(body, 0, 56, 12, { reasoned })
	local icon = W.IconButton(body, { glyph = "glyph_gear", tooltip = L["TAB_Settings"] })
	row(body, 400, 56, 12, { withGlyph, snack, icon })

	local choices = W.Card(c, { kind = "plain", title = L["GALLERY_CHOICES"], width = 740, height = 230 })
	choices:SetPoint("TOPLEFT", buttons, "BOTTOMLEFT", 0, -14)
	local cb = choices.body
	local items = {}
	for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 7 }) do items[#items + 1] = { key = id, text = L["ACTIVITY_" .. id] } end
	local group = W.ChipGroup(cb, items, { width = 700, max = 3 })
	group:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
	group:SetSelected({ 1, 2 }, true)
	local seg = W.Segmented(cb, { { key = 1, text = L["PACE_1"] }, { key = 2, text = L["PACE_2"] }, { key = 3, text = L["PACE_3"] } },
		{ selected = 2 })
	seg:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, -84)
	local s1 = W.Switch(cb, { label = L["GALLERY_SAMPLE"], width = 300, checked = true })
	s1:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, -134)
	local s2 = W.Switch(cb, { label = L["GALLERY_SAMPLE"], width = 300 })
	s2:SetPoint("TOPLEFT", cb, "TOPLEFT", 360, -134)

	local fields = W.Card(c, { kind = "plain", title = L["GALLERY_FIELDS"], width = 740, height = 150 })
	fields:SetPoint("TOPLEFT", choices, "BOTTOMLEFT", 0, -14)
	local fb = fields.body
	local search = W.Field(fb, { placeholder = L["GALLERY_SEARCH"], glyph = "glyph_search", width = 340 })
	search:SetPoint("TOPLEFT", fb, "TOPLEFT", 0, 0)
	local copy = W.CopyField(fb, { text = "https://discord.gg/example", width = 340 })
	copy:SetPoint("TOPLEFT", fb, "TOPLEFT", 360, 0)
	local mono = W.Text(fb, "mono", "ink2")
	mono:SetPoint("TOPLEFT", fb, "TOPLEFT", 0, -56)
	mono:SetText("20:00-23:30  /gf scale 100")
	host.group, host.copy, host.search = group, copy, search
end

-- Opens the gallery on the current tab. Returns false (and says why) in a release build.
function Gallery:Open()
	if not (ns.Config and ns.Config.DEV) then
		ns.addon:Print(L["GALLERY_DEV_ONLY"])
		return false
	end
	Main:RegisterPage(Gallery.PAGE, { title = L["GALLERY_TITLE"], Build = build })
	Main:Show()
	if Main:CurrentPage() ~= Gallery.PAGE then Main:Push(Gallery.PAGE) end
	return true
end

if ns.addon then ns.addon.Gallery = Gallery end
