-- Mock client, part 3: frames, widgets, events, scripts, chat frames, tooltips and slash commands.
--
-- Imitates: CreateFrame and the widget methods the addon and Ace3 use, RegisterEvent / SetScript / Show / Hide,
-- UIParent, GameTooltip, DEFAULT_CHAT_FRAME, SlashCmdList, CreateFont (font objects, Mock.missingFonts), UISpecialFrames, stateful
-- text/colour/font/focus methods, EditBox text events (Mock.TypeInto) and inert animation groups (LibDBIcon).
-- Dump files: ../WoW-Addons/docs/api/UI-Widgets-Frames/ (widget API), the event names come from api.json when it is
-- next to the repository (see Mock.validEvents), otherwise every event name is accepted.
--
-- Widgets are one generic object: stateful where tests care (shown, parent, scripts, events, text, points, size),
-- inert otherwise. A method the mock does not have is nil, so calling it raises "attempt to call method ... (a nil
-- value)": add the method (and say which dump entry it follows) instead of working around it in the addon.
local Mock, H = ...
local W = Mock.world

-- When Python found the dump, the harness gives the list of valid event names: RegisterEvent and Mock.Fire reject
-- anything else, as the client does ("Attempt to register unknown event").
local validEvents = H.validEvents
Mock.validEvents = validEvents

local frames = {}                  -- creation order, for event dispatch and OnUpdate
Mock.frames = frames

local Widget = {}
Widget.__index = Widget

local function newWidget(objectType, name, parent)
	local w = setmetatable({
		_type = objectType, _name = name, _parent = parent, _shown = true, _alpha = 1, _scale = 1,
		_scripts = {}, _hooks = {}, _events = {}, _points = {}, _children = {}, _regions = {},
		_width = 0, _height = 0, _level = 1, _strata = "MEDIUM", _text = "", _enabled = true,
	}, Widget)
	if parent and parent._children then
		parent._children[#parent._children + 1] = w
	end
	return w
end

-- Names and counts of widget types: the generic object answers to all of them.
local OBJECT_TYPES = {
	Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, Slider = true, StatusBar = true,
	GameTooltip = true, Cooldown = true, Model = true, TabardModel = true, DressUpModel = true, ColorSelect = true,
	MessageFrame = true, ScrollingMessageFrame = true, SimpleHTML = true, Minimap = true, Texture = true,
	FontString = true, Line = true,
}

function Widget:GetName() return self._name end
function Widget:GetObjectType() return self._type end
function Widget:IsObjectType(t) return self._type == t or (t == "Frame" and self._type ~= "Texture" and self._type ~= "FontString") end
function Widget:GetParent() return self._parent end
function Widget:SetParent(p) self._parent = p end

function Widget:Show()
	if not self._shown then
		self._shown = true
		if self._scripts.OnShow then Mock.safecall(self._scripts.OnShow, self) end
	end
end
function Widget:Hide()
	if self._shown then
		self._shown = false
		if self._scripts.OnHide then Mock.safecall(self._scripts.OnHide, self) end
	end
end
function Widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible()
	local w = self
	while w do
		if not w._shown then return false end
		w = w._parent
	end
	return true
end

function Widget:SetSize(w, h) self._width, self._height = w, h end
function Widget:GetSize() return self._width, self._height end
function Widget:SetWidth(w) self._width = w end
function Widget:SetHeight(h) self._height = h end
function Widget:GetWidth() return self._width end
function Widget:GetHeight() return self._height end
function Widget:SetAlpha(a) self._alpha = a end
function Widget:GetAlpha() return self._alpha end
function Widget:GetEffectiveAlpha() return self._alpha end
function Widget:SetScale(s) self._scale = s end
function Widget:GetScale() return self._scale end
function Widget:GetEffectiveScale() return self._scale end
function Widget:SetFrameStrata(s) self._strata = s end
function Widget:GetFrameStrata() return self._strata end
function Widget:SetFrameLevel(l) self._level = l end
function Widget:GetFrameLevel() return self._level end
function Widget:SetID(id) self._id = id end
function Widget:GetID() return self._id or 0 end

function Widget:SetPoint(point, relativeTo, relativePoint, x, y)
	if type(relativeTo) == "number" then relativeTo, relativePoint, x, y = nil, nil, relativeTo, relativePoint end
	self._points[#self._points + 1] = { point, relativeTo or self._parent, relativePoint or point, x or 0, y or 0 }
end
function Widget:ClearAllPoints() for i = #self._points, 1, -1 do self._points[i] = nil end end
function Widget:GetNumPoints() return #self._points end
function Widget:GetPoint(i)
	local p = self._points[i or 1]
	if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Widget:SetAllPoints(rel) self:ClearAllPoints(); self:SetPoint("TOPLEFT", rel); self:SetPoint("BOTTOMRIGHT", rel) end
function Widget:GetCenter() return 512, 384 end
function Widget:GetLeft() return 0 end
function Widget:GetRight() return self._width end
function Widget:GetTop() return self._height end
function Widget:GetBottom() return 0 end
function Widget:GetRect() return 0, 0, self._width, self._height end

function Widget:SetScript(name, fn) self._scripts[name] = fn end
function Widget:GetScript(name) return self._scripts[name] end
function Widget:HasScript() return true end
function Widget:HookScript(name, fn)
	local hooks = self._hooks[name] or {}
	self._hooks[name] = hooks
	hooks[#hooks + 1] = fn
end

-- Events. Order of dispatch is frame creation order, then registration is a set.
local function checkEvent(event, where)
	if type(event) ~= "string" then error(where .. ": bad argument #1 (string expected)", 3) end
	if validEvents and not validEvents[event] then
		error(where .. ': Attempt to register unknown event "' .. event .. '"', 3)
	end
end
function Widget:RegisterEvent(event) checkEvent(event, "Frame:RegisterEvent()"); self._events[event] = true end
function Widget:RegisterUnitEvent(event) checkEvent(event, "Frame:RegisterUnitEvent()"); self._events[event] = true end
function Widget:UnregisterEvent(event) self._events[event] = nil end
function Widget:UnregisterAllEvents() self._events = {} end
function Widget:RegisterAllEvents() self._allEvents = true end
function Widget:IsEventRegistered(event) return self._events[event] == true or self._allEvents == true end

local function runScript(widget, name, ...)
	local fn = widget._scripts[name]
	if fn then Mock.safecall(fn, widget, ...) end
	local hooks = widget._hooks[name]
	if hooks then
		for _, hook in ipairs({ unpack(hooks) }) do Mock.safecall(hook, widget, ...) end
	end
end
Mock.RunScript = runScript

-- Fires a game event on every frame registered for it, in creation order. Checks the name against the dump.
function Mock.Fire(event, ...)
	if validEvents and not validEvents[event] then
		error('Mock.Fire: "' .. tostring(event) .. '" is not an event of the Forever client (dump)', 2)
	end
	for _, frame in ipairs({ unpack(frames) }) do
		if frame._events[event] or frame._allEvents then
			runScript(frame, "OnEvent", event, ...)
		end
	end
end

-- Mouse and widget behaviour used by tests.
function Widget:EnableMouse(v) self._mouse = v end
function Widget:EnableMouseWheel(v) self._wheel = v and true or false end   -- dump: SimpleScriptRegionAPI.EnableMouseWheel
function Widget:IsMouseWheelEnabled() return self._wheel == true end
-- Slider thumb (dump: SimpleSliderAPI.SetThumbTexture / GetThumbTexture): a texture the slider owns.
function Widget:SetThumbTexture(t) self._thumbTexture = self._thumbTexture or newWidget("Texture", nil, self); self._thumbTexture._texture = t end
function Widget:GetThumbTexture() self._thumbTexture = self._thumbTexture or newWidget("Texture", nil, self); return self._thumbTexture end
function Widget:IsMouseEnabled() return self._mouse == true end
function Widget:Click(button)
	if self._enabled then runScript(self, "OnClick", button or "LeftButton", false) end
end
function Widget:Enable() self._enabled = true end
function Widget:Disable() self._enabled = false end
function Widget:IsEnabled() return self._enabled end
function Widget:SetEnabled(v) self._enabled = v and true or false end
function Widget:SetText(t)
	t = t or ""
	local changed = self._text ~= t
	self._text = t
	if changed and self._type == "EditBox" and self._scripts.OnTextChanged then
		Mock.safecall(self._scripts.OnTextChanged, self, false)
	end
end
function Widget:GetText() return self._text end
function Widget:GetStringWidth() return #(self._text or "") * 6 end
function Widget:GetStringHeight() return 12 end
function Widget:GetFontString() return self._fontString end
function Widget:SetNormalFontObject() end
function Widget:SetChecked(v) self._checked = v and true or false end
function Widget:GetChecked() return self._checked == true end
function Widget:SetValue(v) self._value = v end
function Widget:GetValue() return self._value or 0 end
function Widget:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Widget:GetMinMaxValues() return self._min or 0, self._max or 1 end
-- SetTexture answers false for a file the client cannot load (Mock.missingTextures[path or fileID] = true), true otherwise.
function Widget:SetTexture(t)
	if t ~= nil and Mock.missingTextures and Mock.missingTextures[t] then self._texture = nil return false end
	self._texture = t
	return true
end
function Widget:GetTexture() return self._texture end
function Widget:SetColorTexture(r, g, b, a) self._texture = { r, g, b, a } end
function Widget:SetNormalTexture(t) self._normalTexture = t end
function Widget:GetNormalTexture() return self._normalTexture or newWidget("Texture", nil, self) end
function Widget:SetHighlightTexture(t) self._highlightTexture = t end
function Widget:GetHighlightTexture() return self._highlightTexture or newWidget("Texture", nil, self) end
function Widget:SetPushedTexture(t) self._pushedTexture = t end
function Widget:GetPushedTexture() return self._pushedTexture or newWidget("Texture", nil, self) end

function Widget:CreateTexture(name, layer)
	local t = newWidget("Texture", name, self)
	t._layer = layer
	self._regions[#self._regions + 1] = t
	if name then _G[name] = t end
	return t
end
function Widget:CreateFontString(name, layer)
	local f = newWidget("FontString", name, self)
	f._layer = layer
	self._regions[#self._regions + 1] = f
	if name then _G[name] = f end
	return f
end
function Widget:GetChildren() return unpack(self._children) end
function Widget:GetNumChildren() return #self._children end
function Widget:GetRegions() return unpack(self._regions) end
function Widget:GetNumRegions() return #self._regions end

-- Setters and getters the addon and the libraries call that only matter to the renderer: accepted, forgotten.
for _, name in ipairs({
	"SetMovable", "SetResizable", "SetClampedToScreen", "SetToplevel", "RegisterForDrag", "RegisterForClicks",
	"StartMoving", "StopMovingOrSizing", "SetUserPlaced", "Raise", "Lower", "SetFixedFrameStrata", "SetFixedFrameLevel",
	"EnableKeyboard", "SetHitRectInsets", "SetBackdrop", "SetBackdropColor",
	"SetBackdropBorderColor", "SetJustifyV", "SetWordWrap",
	"SetShadowColor", "SetShadowOffset", "SetNonSpaceWrap", "SetMaxLines",
	"SetBlendMode", "SetDesaturated", "SetDrawLayer", "SetGradient", "SetMaskTexture", "SetRotation",
	"SetMaxLetters", "SetMultiLine", "SetNumeric",
	"SetOrientation", "SetValueStep", "SetObeyStepOnDrag", "SetStatusBarTexture", "SetStatusBarColor",
	"SetDisabledTexture", "SetDisabledFontObject", "SetHighlightFontObject", "SetPushedTextOffset",
	"SetCheckedTexture", "SetDisabledCheckedTexture", "SetHighlightLocked", "LockHighlight", "UnlockHighlight",
	"SetMouseClickEnabled", "SetMouseMotionEnabled", "SetIgnoreParentScale", "SetIgnoreParentAlpha", "SetFlattensRenderLayers",
	"SetClipsChildren", "SetClampRectInsets", "SetTextInsets", "SetHorizTile", "SetVertTile", "SetSubTexCoord", "SetDontSavePosition", "SetTitle", "SetPassThroughButtons", "SetScrollChild", "SetVerticalScroll",
	"SetHorizontalScroll", "SetInsertMode", "SetFading", "SetFadeDuration", "SetTimeVisible", "SetSpacing",
	"SetMaxResize", "SetMinResize", "SetResizeBounds", "SetFlashing", "SetSubTexCoord", "SetModel", "SetUnit",
}) do
	Widget[name] = function() end
end

-- Text, colour, font and focus state that tests look at (dump: UI-Widgets-Frames, FontString, Texture, EditBox).
function Widget:SetFontObject(font) self._fontObject = font end
function Widget:GetFontObject() return self._fontObject end
function Widget:SetFont(path, size, flags)
	if Mock.missingFonts and Mock.missingFonts[path] then return false end
	self._font = { path, size, flags }
	return true
end
function Widget:GetFont() if self._font then return self._font[1], self._font[2], self._font[3] end end
function Widget:SetJustifyH(j) self._justifyH = j end
function Widget:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a or 1 } end
function Widget:GetTextColor() local c = self._textColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Widget:SetTexCoord(...) self._texCoord = { ... } end
function Widget:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a or 1 } end
function Widget:GetVertexColor() local c = self._vertex or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Widget:SetAtlas(atlas) self._atlas = atlas end
function Widget:SetPropagateKeyboardInput(v) self._propagate = v and true or false end
function Widget:SetAutoFocus(v) self._autoFocus = v end

-- EditBox: SetText fires OnTextChanged(self, false) like the client when the text changes; Mock.TypeInto simulates the player.
function Widget:HasFocus() return self._focused == true end
function Widget:SetFocus()
	if not self._focused then
		self._focused = true
		Mock.keyboardFocus = self
		runScript(self, "OnEditFocusGained")
	end
end
function Widget:ClearFocus()
	if self._focused then
		self._focused = false
		if Mock.keyboardFocus == self then Mock.keyboardFocus = nil end
		runScript(self, "OnEditFocusLost")
	end
end
-- dump: the edit box that has the keyboard, nil when none (what Backspace handling asks before it steals the key)
function GetCurrentKeyBoardFocus() return Mock.keyboardFocus end
function Widget:HighlightText() self._highlighted = true end
function Widget:SetCursorPosition(n) self._cursor = n end
function Widget:GetCursorPosition() return self._cursor or 0 end

function Mock.TypeInto(edit, text)
	edit._text = text
	runScript(edit, "OnTextChanged", true)
end

-- Fonts: CreateFont(name) gives a font object that remembers SetFont; Mock.missingFonts[path] = true makes SetFont fail.
Mock.missingFonts = {}
Mock.missingTextures = {}      -- path or fileID -> true: Texture:SetTexture answers false (a piece the client does not have)
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
function CreateFont(name)
	local font = setmetatable({ _name = name }, { __index = Widget })
	if name then _G[name] = font end
	return font
end

-- Animations (LibDBIcon fades its button): the groups and animations are inert objects that accept every call.
local function inert()
	return setmetatable({}, { __index = function(self, key)
		if key == "CreateAnimation" then return function() return inert() end end
		return function() return self end
	end })
end
function Widget:CreateAnimationGroup() return inert() end

-- GameTooltip: records what the addon puts in it (Mock.tooltips can be inspected through the widget fields).
function Widget:SetOwner(owner, anchor) self._owner, self._anchor, self._lines = owner, anchor, {} end
function Widget:GetOwner() return self._owner end
function Widget:ClearLines() self._lines = {} end
function Widget:AddLine(text) self._lines = self._lines or {}; self._lines[#self._lines + 1] = text end
function Widget:AddDoubleLine(l, r) self:AddLine(l .. " " .. r) end
function Widget:NumLines() return self._lines and #self._lines or 0 end
function Widget:SetHyperlink() end
function Widget:IsOwned(owner) return self._owner == owner end

-- Chat frames: AddMessage keeps the line, like print().
function Widget:AddMessage(text) W.output[#W.output + 1] = tostring(text) end

local nameless = 0
function CreateFrame(objectType, name, parent, template)
	if type(objectType) ~= "string" or not OBJECT_TYPES[objectType] then
		error("CreateFrame(): Unknown frame type '" .. tostring(objectType) .. "'", 2)
	end
	if name ~= nil and type(name) ~= "string" then
		error("CreateFrame(): bad argument #2 (string expected)", 2)
	end
	if name and rawget(_G, name) ~= nil and type(_G[name]) == "table" and getmetatable(_G[name]) == Widget then
		error('CreateFrame(): a frame named "' .. name .. '" already exists', 2)
	end
	local w = newWidget(objectType, name, parent or UIParent)
	w._template = template
	if objectType == "Button" or objectType == "CheckButton" then
		w._fontString = newWidget("FontString", nil, w)
	end
	if name then _G[name] = w else nameless = nameless + 1 end
	frames[#frames + 1] = w
	return w
end

UIParent = newWidget("Frame", "UIParent", nil)
UIParent._width, UIParent._height = 1920, 1080
frames[#frames + 1] = UIParent
WorldFrame = newWidget("Frame", "WorldFrame", nil)
Minimap = CreateFrame("Minimap", "Minimap", UIParent)
Minimap:SetSize(140, 140)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip:Hide()
DEFAULT_CHAT_FRAME = CreateFrame("ScrollingMessageFrame", "ChatFrame1", UIParent)
ChatFrame1 = DEFAULT_CHAT_FRAME
function GetNumChatWindows() return 1 end

-- Used by OnUpdate dispatch (30_timers.lua).
function Mock.RunOnUpdate(dt)
	for _, frame in ipairs({ unpack(frames) }) do
		if (frame._scripts.OnUpdate or frame._hooks.OnUpdate) and frame:IsVisible() then
			runScript(frame, "OnUpdate", dt)
		end
	end
end

-- Slash commands: SlashCmdList and SLASH_<NAME><n> globals, as registered by the addon (AceConsole does the same).
SlashCmdList = {}

-- Types a command in the chat box: Mock.Slash("/gf help"). Returns true when a handler ran.
function Mock.Slash(line)
	local command, rest = line:match("^(/%S+)%s*(.*)$")
	if not command then
		error("Mock.Slash: expected a line starting with '/', got " .. tostring(line), 2)
	end
	command = command:lower()
	for key, handler in pairs(SlashCmdList) do
		local i = 1
		while true do
			local alias = rawget(_G, "SLASH_" .. key .. i)
			if not alias then break end
			if alias:lower() == command then
				Mock.safecall(handler, rest, DEFAULT_CHAT_FRAME)
				return true
			end
			i = i + 1
		end
	end
	return false
end
