-- Diagnostics box (M5.4): `/gf debug` opens the report (Core/Diagnostics.lua) in a read-only multi-line edit box with a
-- "Select all" button. Addons cannot reach the clipboard: the text is selected and the player presses Ctrl+C, then pastes
-- it into the bug report form. Esc closes it. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.DiagnosticsBox, ns.modules = Box, ns.modules or {}
ns.modules.DiagnosticsBox = Box

local L, W, Skin = ns.L, ns.Widgets, ns.Skin
Box.NAME = "AzerothGuildFinderDiagnosticsBox"
Box.WIDTH, Box.HEIGHT = 640, 460

local function build()
	local f = CreateFrame("Frame", Box.NAME, UIParent)
	f:SetSize(Box.WIDTH, Box.HEIGHT)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
	f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
	f.bg = W.NineSlice(f, "card", { corner = 12, layer = "BACKGROUND" })
	f.bg:SetHex("#f3e2bd")

	f.title = W.Text(f, "title", "ink")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -16)
	f.title:SetText(L["DIAG_TITLE"])
	f.hint = W.Text(f, "caption", "ink2", "LEFT")
	f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -20, 0)
	f.hint:SetText(L["DIAG_HINT"])

	local inner = CreateFrame("Frame", nil, f)
	inner:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -72)
	inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 64)
	inner.bg = W.NineSlice(inner, "field", { corner = 12, layer = "BACKGROUND" })
	inner.bg:SetHex("#fff4dd")
	inner.ring = W.NineSlice(inner, "field_ring", { corner = 12, layer = "BACKGROUND", sublevel = 1 })
	inner.ring:SetHex("#4a525a")

	local scroll = CreateFrame("ScrollFrame", nil, inner)
	scroll:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -10, 8)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local y = (self:GetVerticalScroll() or 0) - delta * 40
		self:SetVerticalScroll(math.max(0, math.min(range, y)))
	end)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(Skin.Font("mono"))
	edit:SetTextColor(Skin.Color("ink"))
	edit:SetWidth(Box.WIDTH - 60)
	edit:SetTextInsets(0, 0, 0, 0)
	scroll:SetScrollChild(edit)
	f.scroll, f.edit = scroll, edit

	-- read-only: typing is undone at once and the text stays selected
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= f.text then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	f.selectAll = W.Button(f, { text = L["DIAG_SELECT"], kind = "primary",
		onClick = function() Box:SelectAll() end })
	f.selectAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 18)
	f.close = W.Button(f, { text = L["DIAG_CLOSE"], kind = "tonal", onClick = function() Box:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 18)

	if type(UISpecialFrames) == "table" then
		local found = false
		for _, name in ipairs(UISpecialFrames) do if name == Box.NAME then found = true end end
		if not found then table.insert(UISpecialFrames, Box.NAME) end
	end
	f:Hide()
	return f
end

function Box:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

-- Opens the box with a fresh report, selected, ready for Ctrl+C. Returns the text.
function Box:Open()
	local f = self:Frame()
	local text = ns.Diagnostics.Report()
	f.text = text
	f.edit:SetText(text)
	f.edit:SetCursorPosition(0)
	f.scroll:SetVerticalScroll(0)
	f:Show()
	self:SelectAll()
	return text
end

function Box:SelectAll()
	local f = self.frame
	if not f then return end
	f.edit:SetFocus()
	f.edit:HighlightText()
	if W.Snackbar then W.Snackbar.Show(L["COPY_HINT"], { key = "diagbox" }) end
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:GetText() return self.frame and self.frame.text or nil end
if ns.addon then ns.addon.DiagnosticsBox = Box end
