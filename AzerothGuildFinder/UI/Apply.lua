-- Apply: the Apply button of the guild cards and of the guild page, and the confirmation before an application is saved
-- (SPEC-05 §4, SPEC-07 §1, ADR 0005). Lua 5.1.
--
--   Apply.View(k, place)        -> the button for guild k (ApplyModel.Button over Applications:Check); place "card" | "page"
--   Apply.Bind(btn, k, place, maxWidth)   copies that view into a W.Button (label, colour, enabled, tooltip, click)
--   Apply:Ask(k)                opens the confirmation: "Apply to <Guild> with Name (Mage 32)?", the roles of the class to
--                               tick (optional), Apply and Cancel
--   Apply:Confirm() / Apply:Cancel()   the two answers (the buttons call them)
-- Every rule is in Data/Applications.lua and UI/ApplyModel.lua; this file only draws. The confirmation lies over the whole
-- book (a dim layer that takes the clicks) and goes away with the window.
local ADDON_NAME, ns = ...
ns = ns or {}
local Apply = {}
ns.Apply, ns.modules = Apply, ns.modules or {}
ns.modules.Apply = Apply

local L, Skin, W, Model = ns.L, ns.Skin, ns.Widgets, ns.ApplyModel
local type, ipairs, max = type, ipairs, math.max

Apply.DIALOG_W = 440
Apply.MY_APPLICATION = "MyApplication"

local function guildName(k)
	local _, _, name = ns.Listing.ParseKey(k)
	return name or k or ""
end

---------------------------------------------------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------------------------------------------------
function Apply.View(k, place)
	local A = ns.Applications
	local ok, reason, info = A:Check(k)
	local ctx = A:Context(k)
	return Model.Button(ok and "ok" or reason, info, { name = guildName(k), place = place, sum = ctx.sum, player = ctx.player }, L)
end

-- What the button does: Apply asks first; "Applied" opens the My Application tab.
function Apply.Click(k, view)
	if not view or not view.enabled then return false end
	if view.link then
		if ns.Main then ns.Main:Select(view.link) end
		return true
	end
	return Apply:Ask(k)
end

-- Copies the view of guild k into `btn` (a W.Button). maxWidth: a card has a limited room, a long reason is cut there and
-- read in full in the tooltip. Returns the view.
function Apply.Bind(btn, k, place, maxWidth)
	local view = Apply.View(k, place)
	btn.applyK, btn.applyView = k, view
	btn:SetShown(view.shown)
	if not view.shown then return view end
	btn:SetKind(view.kind)
	btn:SetLabel(view.label or "")
	btn:SetEnabled(view.enabled)
	if maxWidth then
		-- a long reason is cut on the button (the tooltip has it in full)
		btn.text:SetWordWrap(false)
		btn.text:SetWidth(maxWidth - 24)
		if btn:GetWidth() > maxWidth then btn:SetWidth(maxWidth) end
	end
	if not btn.applyHooked then
		btn.applyHooked = true
		btn:SetOnClick(function(b) Apply.Click(b.applyK, b.applyView) end)
		W.SetTooltip(btn, function() return btn.applyView and btn.applyView.tooltip end)
	end
	return view
end

---------------------------------------------------------------------------------------------------------------------
-- The confirmation
---------------------------------------------------------------------------------------------------------------------
local function build()
	local main = ns.Main
	local parent = main and main.frame or UIParent
	local layer = CreateFrame("Frame", nil, parent)
	layer:SetAllPoints(parent)
	layer:SetFrameStrata("DIALOG")
	layer:EnableMouse(true)
	layer:EnableMouseWheel(true)
	layer:SetScript("OnMouseWheel", function() end)
	layer.dim = W.Texture(layer, "solid", "BACKGROUND", "#1a0e04", 0.45)
	layer.dim:SetAllPoints(layer)
	-- the window closing (Esc, the close button) closes the question too: it does not come back by itself
	layer:SetScript("OnHide", function(self)
		Apply.k = nil
		if self:IsShown() then self:Hide() end
	end)
	layer:Hide()

	local box = CreateFrame("Frame", nil, layer)
	box:SetWidth(Apply.DIALOG_W)
	box:SetPoint("CENTER", layer, "CENTER", 0, 20)
	box.shadow = W.NineSlice(box, "shadow", { corner = 32, outset = 24, layer = "BACKGROUND", sublevel = -2 })
	box.shadow:SetColor(0, 0, 0, 0.55)
	box.bg = W.NineSlice(box, "card", { corner = 14, layer = "BACKGROUND" })
	box.bg:SetHex("#fbe9c5")
	box.edge = W.NineSlice(box, "card_edge", { corner = 14, layer = "BACKGROUND", sublevel = 1 })
	box.edge:SetHex("#b8820f")
	layer.box = box

	local inner = Apply.DIALOG_W - 48
	box.title = W.Text(box, "titleL", "ink2")
	box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 24, -22)
	box.title:SetWidth(inner)
	box.title:SetWordWrap(false)
	box.question = W.Text(box, "body", "ink")
	box.question:SetWidth(inner)
	box.question:SetWordWrap(true)
	box.rolesLabel = W.Text(box, "label", "ink")
	box.rolesHint = W.Text(box, "caption", "ink3")
	box.rolesHint:SetWidth(inner)
	box.rolesHint:SetWordWrap(true)
	box.privacy = W.Text(box, "caption", "ink2")
	box.privacy:SetWidth(inner)
	box.privacy:SetWordWrap(true)
	box.yes = W.Button(box, { text = L["APPLY"], kind = "primary", size = "md", onClick = function() Apply:Confirm() end })
	box.yes:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -24, 20)
	box.no = W.Button(box, { text = L["ED_CANCEL"], kind = "tonal", size = "md", onClick = function() Apply:Cancel() end })
	box.no:SetPoint("RIGHT", box.yes, "LEFT", -10, 0)
	return layer
end

local function textHeight(fs)
	local h = fs:GetStringHeight()
	return (type(h) == "number" and h > 0) and h or 16
end

-- Opens the confirmation for guild k (only when Apply is allowed now). Returns true when it is shown.
function Apply:Ask(k)
	local A = ns.Applications
	if not A:Check(k) then return false end
	if not self.dialog then self.dialog = build() end
	local player = A.ReadPlayer()
	local view = Model.Confirm({ name = guildName(k), player = player }, L)
	local box = self.dialog.box
	self.k, self.confirmView = k, view
	box.title:SetText(view.title)
	box.question:SetText(view.question)
	box.rolesLabel:SetText(L["APPLY_ROLES"])
	box.rolesHint:SetText(view.rolesHint)
	box.privacy:SetText(view.privacy)
	box.yes:SetLabel(view.apply)
	box.no:SetLabel(view.cancel)

	-- the roles of the class, none ticked: one group per set of roles (a /reload may bring another character)
	if box.roles then box.roles:Hide() end
	local items, signature = {}, ""
	for _, r in ipairs(view.roles) do
		items[#items + 1] = { key = r.bit, text = r.label, icon = "role_" .. r.key }
		signature = signature .. r.bit .. ","
	end
	box.groups = box.groups or {}
	if not box.groups[signature] then box.groups[signature] = W.ChipGroup(box, items, { width = Apply.DIALOG_W - 48, multi = true }) end
	box.roles = box.groups[signature]
	box.roles:Clear(true)
	box.roles:Show()

	local y = 22 + 28 + 10
	box.question:ClearAllPoints()
	box.question:SetPoint("TOPLEFT", box, "TOPLEFT", 24, -y)
	y = y + textHeight(box.question) + 16
	box.rolesLabel:ClearAllPoints()
	box.rolesLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 24, -y)
	y = y + 22
	box.roles:ClearAllPoints()
	box.roles:SetPoint("TOPLEFT", box, "TOPLEFT", 24, -y)
	y = y + max(box.roles:GetHeight() or 0, 32) + 8
	box.rolesHint:ClearAllPoints()
	box.rolesHint:SetPoint("TOPLEFT", box, "TOPLEFT", 24, -y)
	y = y + textHeight(box.rolesHint) + 14
	box.privacy:ClearAllPoints()
	box.privacy:SetPoint("TOPLEFT", box, "TOPLEFT", 24, -y)
	y = y + textHeight(box.privacy) + 20 + 36 + 20
	box:SetHeight(y)
	self.dialog:Show()
	return true
end

function Apply:IsAsking() return self.dialog ~= nil and self.dialog:IsShown() end

-- The roles ticked in the confirmation, as a mask (nil: none).
function Apply:TickedRoles()
	local box = self.dialog and self.dialog.box
	if not (box and box.roles) then return nil end
	return Model.RolesMask(box.roles:GetSelected())
end

-- Apply: the application is saved as "sent" (Data/Applications.lua); the officers get it when one is online (M4.2).
function Apply:Confirm()
	if not self:IsAsking() or not self.k then return false end
	local k, roles = self.k, self:TickedRoles()
	self.dialog:Hide()
	self.k = nil
	local ok, rec = ns.Applications:Apply(k, roles)
	if ok then
		W.Snackbar.Show(L["APPLY_SAVED"]:format(guildName(k)), { key = "apply", seconds = 6,
			action = { text = L["APPLY_VIEW"], onClick = function() if ns.Main then ns.Main:Select(Apply.MY_APPLICATION) end end } })
	else
		W.Snackbar.Show(L["APPLY_FAILED"], { key = "apply" })
	end
	return ok, rec
end

function Apply:Cancel()
	if self.dialog then self.dialog:Hide() end
	self.k = nil
	return true
end

if ns.Bus then
	-- the window's role changed (the player joined a guild): an open question has no sense any more
	ns.Bus:On("ROLE_CHANGED", function() Apply:Cancel() end)
end
if ns.addon then ns.addon.Apply = Apply end
