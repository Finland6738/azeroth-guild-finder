-- Widgets, part 2: what floats above the window: the hover tooltip and the snackbar. Lua 5.1.
--
--   W.ShowTooltip(owner, source)   W.HideTooltip()          the game's GameTooltip, filled from a string or a table
--   W.Snackbar.Show(text, opts)    W.Snackbar.Dismiss()      one short message at the bottom of the window
--
-- A tooltip source is a string (one line), or { title = "...", lines = { "...", { text = "...", color = "bad" } } }, or
-- a function returning one of those. A snackbar waits its turn behind the one that is showing (five at most; a message
-- with the same `key` replaces the waiting one), disappears after `seconds` (4 by default) and may have one action.
local ADDON_NAME, ns = ...
ns = ns or {}
local W = ns.Widgets
local Skin = ns.Skin
local type, ipairs, table = type, ipairs, table

---------------------------------------------------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------------------------------------------------
-- Normalises a tooltip source to { title, lines }, or nil when there is nothing to show.
function W.TooltipContent(source)
	if type(source) == "function" then source = source() end
	if type(source) == "string" then return { title = source, lines = {} } end
	if type(source) ~= "table" then return nil end
	return { title = source.title, lines = source.lines or {} }
end

function W.ShowTooltip(owner, source, anchor)
	local content = W.TooltipContent(source)
	if not content or not content.title or not GameTooltip then return false end
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:SetText(content.title, 1, 0.93, 0.76)
	for _, line in ipairs(content.lines) do
		if type(line) == "table" then
			local r, g, b = Skin.Color(Skin.ON_DARK[line.color] or line.color or "white")
			GameTooltip:AddLine(line.text, r, g, b, true)
		else
			GameTooltip:AddLine(line, 0.95, 0.9, 0.81, true)
		end
	end
	GameTooltip:Show()
	return true
end

function W.HideTooltip()
	if GameTooltip then GameTooltip:Hide() end
end

---------------------------------------------------------------------------------------------------------------------
-- Snackbar
---------------------------------------------------------------------------------------------------------------------
local Snackbar = {}
W.Snackbar = Snackbar
Snackbar.MAX_QUEUE = 5
Snackbar.DEFAULT_SECONDS = 4
Snackbar.NAME = "AzerothGuildFinderSnackbar"

local queue = {}          -- waiting messages: { text, seconds, action, key }
local current = nil       -- the message on screen
local token = 0           -- bumped for every message shown; a timer only acts for its own token
local frame, anchorFrame

local function after(seconds, fn)
	if ns.Compat and ns.Compat.After then return ns.Compat.After(seconds, fn) end
	if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) return true end
	return false
end

-- The frame the snackbar sits at the bottom of (the main window); without one, the middle of the screen.
function Snackbar.SetAnchor(f)
	anchorFrame = f
	if frame then Snackbar.Place() end
end

function Snackbar.Place()
	if not frame then return end
	frame:ClearAllPoints()
	frame:SetScale(anchorFrame and anchorFrame:GetScale() or 1)
	if anchorFrame then frame:SetPoint("BOTTOM", anchorFrame, "BOTTOM", 0, 18)
	else frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120) end
end

local function build()
	frame = CreateFrame("Frame", Snackbar.NAME, UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetHeight(44)
	frame:EnableMouse(true)
	frame:Hide()
	frame.bg = W.NineSlice(frame, "card", { corner = 8, layer = "BACKGROUND" })
	frame.bg:SetTint("snackbar", 0.96)
	frame.shadow = W.NineSlice(frame, "shadow", { corner = 32, outset = 24, layer = "BACKGROUND", sublevel = -2 })
	frame.shadow:SetColor(0, 0, 0, 0.55)
	frame.text = W.Text(frame, "body", "snackbarText")
	frame.text:SetPoint("LEFT", frame, "LEFT", 16, 0)
	frame.action = CreateFrame("Button", nil, frame)
	frame.action:SetHeight(30)
	frame.action:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
	frame.action.text = W.Text(frame.action, "label", "gold", "CENTER")
	frame.action.text:SetAllPoints(frame.action)
	frame.action:SetScript("OnClick", function()
		local message = current
		Snackbar.Dismiss()
		if message and message.action and message.action.onClick then message.action.onClick() end
	end)
	frame:SetScript("OnMouseUp", function() Snackbar.Dismiss() end)
	Snackbar.Place()
end

local function display(message)
	if not frame then build() end
	current = message
	token = token + 1
	local mine = token
	frame.text:SetText(message.text)
	local textWidth = frame.text:GetStringWidth()
	if message.action then
		frame.action.text:SetText(message.action.text or "")
		local actionWidth = frame.action.text:GetStringWidth() + 24
		frame.action:SetWidth(actionWidth)
		frame.action:Show()
		frame:SetWidth(16 + textWidth + 16 + actionWidth + 8)
	else
		frame.action:Hide()
		frame:SetWidth(16 + textWidth + 16)
	end
	frame:Show()
	after(message.seconds, function()
		if token == mine and current then Snackbar.Dismiss() end
	end)
end

-- Shows `text`, or queues it behind the message on screen. opts: seconds, key, action = { text, onClick }.
-- Returns true when it is on screen or waiting; empty text is ignored.
function Snackbar.Show(text, opts)
	if type(text) ~= "string" or text == "" then return false end
	opts = opts or {}
	local message = { text = text, seconds = opts.seconds or Snackbar.DEFAULT_SECONDS, action = opts.action, key = opts.key }
	if current and message.key and current.key == message.key then
		display(message)   -- same message again: refresh it in place
		return true
	end
	if current then
		for i, waiting in ipairs(queue) do
			if message.key and waiting.key == message.key then queue[i] = message return true end
		end
		if #queue >= Snackbar.MAX_QUEUE then table.remove(queue, 1) end
		queue[#queue + 1] = message
		return true
	end
	display(message)
	return true
end

-- Hides the message on screen and shows the next one, if any.
function Snackbar.Dismiss()
	if not current then return end
	current = nil
	token = token + 1
	if frame then frame:Hide() end
	local nextMessage = table.remove(queue, 1)
	if nextMessage then display(nextMessage) end
end

function Snackbar.IsShown() return current ~= nil end
function Snackbar.Current() return current and current.text end
function Snackbar.Pending() return #queue end
function Snackbar.Frame() return frame end

-- Forgets everything (tests, a role change does not call this).
function Snackbar.Reset()
	queue, current = {}, nil
	token = token + 1
	if frame then frame:Hide() end
end
