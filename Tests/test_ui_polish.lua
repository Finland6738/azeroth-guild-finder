-- M5.2: visual polish and accessibility, as far as it can be checked without the game: no text under 12 px at 100 %,
-- the WCAG contrast of every text/background pair of the design tokens, a tooltip on every control that has no label,
-- Esc and Backspace, and the window staying on the screen at 1280 x 720 and at every scale. What the window looks like
-- is the in-game checklist (docs/checklists/M5.md).

local function A() return AzerothGuildFinder end
local function Skin() return A().Skin end
local function Nav() return A().Nav end
local function main() return A().Main end
local function W() return A().Widgets end

local function setRole(role)
	if role == "none" then Mock.guild.Leave()
	else Mock.guild.Set{ name = "Test Guild", myRank = (role == "gm" and 0) or (role == "officer" and 1) or 3 } end
end

-- The addon files of the interface, by name.
local function uiFiles()
	local names = {}
	for _, name in ipairs(Mock.loadedFiles) do
		if name:match("^AzerothGuildFinder/UI/") and not name:match("/Libs/") then names[#names + 1] = name end
	end
	return names
end

local function lines(source)
	local out = {}
	for line in (source .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
	return out
end

---------------------------------------------------------------------------------------------------------------------
describe("font sizes: nothing under 12 px at 100 %", function()
	it("the minimum is 12 and every style of the type scale reaches it", function()
		eq(Skin().MIN_FONT_PX, 12)
		local count = 0
		for style, s in pairs(Skin().STYLES) do
			count = count + 1
			truthy(s.px * 1.0 >= 12, style .. " is " .. tostring(s.px) .. " px")
			truthy(Skin().FontPx(style) >= 12, style)
		end
		truthy(count >= 10, "the scale was not emptied")
	end)

	it("the font objects are made at 12 px or more, bundled or on the client's own font", function()
		for _, broken in ipairs({ false, true }) do
			Skin().fonts, Skin().fontSource = {}, {}
			Mock.missingFonts = {}
			if broken then
				for style in pairs(Skin().STYLES) do Mock.missingFonts[Skin().FontFile(style)] = true end
			end
			Skin().CreateFonts()
			for style, object in pairs(Skin().fonts) do
				local _, size = object:GetFont()
				truthy(size and size >= 12, style .. " is " .. tostring(size) .. (broken and " (fallback)" or ""))
			end
		end
	end)

	it("a size below the minimum is raised, a missing one too", function()
		eq(Skin().ClampPx(8), 12)
		eq(Skin().ClampPx(nil), 12)
		eq(Skin().ClampPx("x"), 12)
		eq(Skin().ClampPx(13.5), 13.5)
		isNil(Skin().FontPx("nope"))
	end)

	it("the initial inside a small emblem is not under 12 px either", function()
		local e = A().Emblem.Create(UIParent, 24)
		e:SetEmblem(nil, "Zed")
		local _, size = e.initial:GetFont()
		truthy(size == nil or size >= 12, "initial of a 24 px emblem: " .. tostring(size))
	end)

	it("no file of the interface sets a font size itself: sizes come from the type scale (Skin) and the emblem clamps its own", function()
		for _, name in ipairs(uiFiles()) do
			if not name:match("/Skin%.lua$") and not name:match("/Emblem%.lua$") then
				for n, line in ipairs(lines(Mock.ReadSource(name))) do
					falsy(line:match("SetFont%(") or line:match("CreateFont%("), name .. ":" .. n .. " sets a font by hand: " .. line)
				end
			end
		end
		local emblem = Mock.ReadSource("AzerothGuildFinder/UI/Emblem.lua")
		truthy(emblem:find("SetFont(initialFont(), Skin.ClampPx(", 1, true), "the emblem initial goes through Skin.ClampPx")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("contrast (WCAG 2.1) of the design tokens", function()
	it("computes the standard values", function()
		near(Skin().Contrast("#000000", "#ffffff"), 21, 0.001)
		near(Skin().Contrast("#ffffff", "#000000"), 21, 0.001, "order does not matter")
		near(Skin().Contrast("#777777", "#777777"), 1, 0.001)
		near(Skin().Contrast("#767676", "#ffffff"), 4.54, 0.01, "the well-known AA grey")
		isNil(Skin().Contrast("nope", "#ffffff"))
		isNil(Skin().Luminance(5))
		eq(Skin().Blend("#000000", "#ffffff", 0.5), "#808080")
		eq(Skin().Blend("#ff0000", "#0000ff", 1), "#ff0000")
		isNil(Skin().Blend("nope", "#fff", 1))
	end)

	it("the main ink reaches 7:1 and the secondary ink 4.5:1 on the parchment (SPEC-04 5.3)", function()
		for _, page in ipairs({ "parchHi", "parch", "pageLeft" }) do
			truthy(Skin().Contrast("ink", page) >= 7, "ink on " .. page)
			truthy(Skin().Contrast("ink2", page) >= 4.5, "ink2 on " .. page)
		end
	end)

	it("every text/background pair the windows draw reaches its ratio", function()
		local pairsList = Skin().TextPairs()
		truthy(#pairsList > 100, "the list was not emptied: " .. #pairsList)
		local failing = {}
		for _, p in ipairs(pairsList) do
			local ratio = Skin().Contrast(p.fg, p.bg)
			if not ratio then failing[#failing + 1] = p.name .. ": unknown colour"
			elseif ratio < p.min then failing[#failing + 1] = ("%s: %s on %s is %.2f, needs %s"):format(p.name, tostring(p.fg), tostring(p.bg), ratio, tostring(p.min)) end
		end
		eq(#failing, 0, table.concat(failing, "\n"))
	end)

	it("covers every kind of button, tag and rail tab", function()
		local names = {}
		for _, p in ipairs(Skin().TextPairs()) do names[p.name] = true end
		for kind, k in pairs(Skin().KINDS) do
			if k.fill then truthy(names["button " .. kind], kind) else truthy(names["ghost button on parch"], kind) end
		end
		for kind in pairs(Skin().TAGS) do truthy(names["tag " .. kind], kind) end
		truthy(names["rail tab on"] and names["rail tab off"])
		truthy(names["ink2 on card plain on pageLeft"] and names["ink on card gold on parch"], "cards over both pages")
	end)

	it("text colours are tokens: no \"#rrggbb\" literal in a text call of the interface", function()
		for _, name in ipairs(uiFiles()) do
			if not name:match("/Base%.lua$") then
				for n, line in ipairs(lines(Mock.ReadSource(name))) do
					local text = line:match("W%.Text%(") or line:match("TextColor%(") or line:match("SetTextColor%(")
					if text and line:match('"#%x%x%x%x%x%x"') then
						fail(name .. ":" .. n .. " paints text with a literal colour (use a token, and list its pair in Skin.TextPairs): " .. line)
					end
				end
			end
		end
	end)

	it("every colour token used for text is one of the audited ones", function()
		local audited = {}
		for _, p in ipairs(Skin().TextPairs()) do audited[p.fg] = true end
		for _, name in ipairs(uiFiles()) do
			local source = Mock.ReadSource(name)
			for token in source:gmatch('W%.Text%([^,\n]+,%s*"[%w]+",%s*"([%a][%w]*)"') do
				truthy(Skin().COLORS[token], name .. ": unknown text colour " .. token)
				truthy(audited[token], name .. ": text colour " .. token .. " is not in Skin.TextPairs")
			end
			for token in source:gmatch('W%.TextColor%([^,\n]+,%s*"([%a][%w]*)"') do
				truthy(Skin().COLORS[token], name .. ": unknown text colour " .. token)
				truthy(audited[token], name .. ": text colour " .. token .. " is not in Skin.TextPairs")
			end
		end
	end)

	it("tooltip lines in a state colour are drawn in the light variant on the dark tooltip", function()
		W().ShowTooltip(UIParent, { title = "T", lines = { { text = "x", color = "bad" } } })
		local r, g, b = Skin().Color("badLight")
		eq(Skin().ON_DARK.bad, "badLight")
		truthy(Skin().Contrast(Skin().COLORS.badLight, "tooltipBg") >= 4.5)
		truthy(r > g and r > b)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Tooltips on every control that has no label
---------------------------------------------------------------------------------------------------------------------
-- A button made to carry text has a FontString of its own (or in a child that is not a button), even while it is empty.
local function hasText(frame, depth)
	depth = depth or 0
	if depth > 6 then return false end
	if (frame._text or "") ~= "" then return true end
	for _, region in ipairs(frame._regions or {}) do
		if region._type == "FontString" then return true end
	end
	for _, child in ipairs(frame._children or {}) do
		if child._type ~= "Button" and child._type ~= "FontString" and hasText(child, depth + 1) then return true end
	end
	return false
end

-- Every Button the addon made that shows no text, with the reason when it is exempt.
local function unlabelled()
	local out = {}
	for _, f in ipairs(Mock.frames) do
		if f._type == "Button" and not (f._name and f._name:match("^LibDBIcon")) and not hasText(f) then out[#out + 1] = f end
	end
	return out
end

local function path(f)
	local parts = {}
	while f do
		parts[#parts + 1] = (f._name or f._type or "?") .. (f._id and ("#" .. f._id) or "")
		f = f._parent
	end
	return table.concat(parts, " < ")
end

local function visitEverything()
	for _, role in ipairs({ "none", "member", "officer", "gm" }) do
		setRole(role)
		main():Show()
		for _, tab in ipairs(main().book:Tabs()) do main():Select(tab) end
		main():Hide()
	end
end

describe("tooltips on the controls without a label", function()
	it("every icon-only button of every tab of every role has one", function()
		visitEverything()
		local list = unlabelled()
		truthy(#list >= 3, "the audit finds the icon buttons (the close button, the clear buttons...): " .. #list)
		local missing = {}
		for _, f in ipairs(list) do
			if f.agfTooltip == nil then missing[#missing + 1] = path(f) end
		end
		eq(#missing, 0, "icon-only buttons without a tooltip:\n" .. table.concat(missing, "\n"))
	end)

	it("the notification icon, its menu and its list have them too", function()
		setRole("gm")
		local Notify = A().Notify
		Notify:Create(); Notify:CreateList(); Notify:CreateMenu()
		local missing = {}
		for _, f in ipairs(unlabelled()) do
			if f.agfTooltip == nil and f._name ~= "AzerothGuildFinderMainFrame" then missing[#missing + 1] = path(f) end
		end
		eq(#missing, 0, table.concat(missing, "\n"))
	end)

	it("the tooltips say something: a title, in the locale", function()
		visitEverything()
		for _, f in ipairs(unlabelled()) do
			if f.agfTooltip ~= nil then
				local content = W().TooltipContent(f.agfTooltip)
				truthy(content and type(content.title) == "string" and content.title ~= "", "empty tooltip: " .. path(f))
				falsy(content.title:match("^[A-Z0-9_]+$") and content.title:find("_", 1, true), "tooltip is a locale key: " .. content.title)
			end
		end
	end)

	it("the audit sees a bare icon button: one without a tooltip is reported", function()
		local bare = CreateFrame("Button", nil, UIParent)
		local found = false
		for _, f in ipairs(unlabelled()) do if f == bare then found = true end end
		truthy(found)
		isNil(bare.agfTooltip)
	end)

	it("the icon button and the close button show their tooltip on hover", function()
		local b = W().IconButton(UIParent, { glyph = "glyph_gear", tooltip = "Gear" })
		Mock.RunScript(b, "OnEnter")
		eq(GameTooltip._lines ~= nil and GameTooltip:IsShown(), true)
		Mock.RunScript(b, "OnLeave")
		falsy(GameTooltip:IsShown())
		local c = W().CloseButton(UIParent, function() end, "Close")
		eq(W().TooltipContent(c.agfTooltip).title, "Close")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Keyboard
---------------------------------------------------------------------------------------------------------------------
-- What the game does on Esc: closes the windows in UISpecialFrames (CloseSpecialWindows), the last opened first.
local function pressEsc()
	local closed = false
	for i = #UISpecialFrames, 1, -1 do
		local f = _G[UISpecialFrames[i]]
		if f and f:IsShown() then f:Hide(); closed = true end
	end
	return closed
end

local function pushPage()
	main():Show()
	main():Select("Settings")
	main():RegisterPage("PolishPage", { title = "Polish", Build = function() end })
	main():Push("PolishPage")
end

describe("Esc and Backspace", function()
	it("Esc closes the window, through UISpecialFrames, once", function()
		main():Show()
		local count = 0
		for _, name in ipairs(UISpecialFrames) do if name == "AzerothGuildFinderMainFrame" then count = count + 1 end end
		eq(count, 1)
		truthy(main():IsShown())
		truthy(pressEsc())
		falsy(main():IsShown())
		falsy(pressEsc(), "nothing left to close")
	end)

	it("Esc does not close the window twice-registered after it was rebuilt or reopened", function()
		for _ = 1, 3 do main():Show(); main():Hide() end
		local count = 0
		for _, name in ipairs(UISpecialFrames) do if name == "AzerothGuildFinderMainFrame" then count = count + 1 end end
		eq(count, 1)
	end)

	it("Nav.KeyAction: Backspace goes back only when it can and nobody is typing", function()
		eq(Nav().KeyAction("BACKSPACE", true, false), "back")
		isNil(Nav().KeyAction("BACKSPACE", false, false), "nowhere to go back to")
		isNil(Nav().KeyAction("BACKSPACE", true, true), "a text box has the keyboard")
		isNil(Nav().KeyAction("ESCAPE", true, false))
		isNil(Nav().KeyAction("A", true, false))
		isNil(Nav().KeyAction(nil, true, false))
	end)

	it("Backspace goes back on a pushed page", function()
		pushPage()
		eq(main():CurrentPage(), "PolishPage")
		Mock.RunScript(main().frame, "OnKeyDown", "BACKSPACE")
		eq(main():CurrentPage(), "Settings")
		falsy(main().frame._propagate, "Backspace was used")
	end)

	it("Backspace does nothing while an edit box has the keyboard, and the key reaches the box", function()
		pushPage()
		local edit = CreateFrame("EditBox", nil, main().frame)
		edit:SetFocus()
		truthy(GetCurrentKeyBoardFocus() == edit)
		Mock.RunScript(main().frame, "OnKeyDown", "BACKSPACE")
		eq(main():CurrentPage(), "PolishPage", "still on the page")
		truthy(main().frame._propagate, "the key goes on to the edit box")
		edit:ClearFocus()
		isNil(GetCurrentKeyBoardFocus())
		Mock.RunScript(main().frame, "OnKeyDown", "BACKSPACE")
		eq(main():CurrentPage(), "Settings", "back once the box lets go")
	end)

	it("Esc in a field gives the keyboard back instead of closing anything", function()
		local field = W().Field(UIParent, { width = 200, placeholder = "x" })
		field.edit:SetFocus()
		Mock.RunScript(field.edit, "OnEscapePressed")
		falsy(field.edit:HasFocus())
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Position and scale at small resolutions
---------------------------------------------------------------------------------------------------------------------
local BOX = { w = 1116, h = 768, right = 84, top = 12 }

-- The rectangle (left, bottom, right, top) of the box in parent units, worked out the long way, anchor by anchor.
local function rectOf(point, relPoint, x, y, scale, parentW, parentH)
	local fx = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
	local fy = { BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, TOPLEFT = 1, TOP = 1, TOPRIGHT = 1 }
	local ax, ay = fx[relPoint] * parentW + x, fy[relPoint] * parentH + y
	local w, h = BOX.w * scale, BOX.h * scale
	local left, bottom = ax - fx[point] * w, ay - fy[point] * h
	return left, bottom, left + w + BOX.right * scale, bottom + h + BOX.top * scale
end

local ANCHOR_NAMES = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local SCREENS = { { 1280, 720 }, { 1366, 768 }, { 1024, 768 }, { 1920, 1080 }, { 800, 600 }, { 2560, 1440 } }
local EXTREME = { { 0, 0 }, { 5000, 0 }, { -5000, 0 }, { 0, 5000 }, { 0, -5000 }, { 5000, 5000 }, { -5000, -5000 }, { 37, -81 } }

describe("Nav.ClampPos", function()
	it("leaves a window that is on the screen where it is", function()
		local x, y, moved = Nav().ClampPos({ point = "CENTER", relPoint = "CENTER", x = -46, y = 0 }, 1, 1920, 1080, BOX)
		eq(x, -46); eq(y, 0); falsy(moved)
	end)

	it("pulls a window back that left on each side", function()
		for _, offset in ipairs({ { 5000, 0 }, { -5000, 0 }, { 0, 5000 }, { 0, -5000 } }) do
			local x, y, moved = Nav().ClampPos({ point = "CENTER", relPoint = "CENTER", x = offset[1], y = offset[2] }, 1, 1920, 1080, BOX)
			truthy(moved)
			local l, b, r, t = rectOf("CENTER", "CENTER", x, y, 1, 1920, 1080)
			truthy(l >= 0 and b >= 0 and r <= 1920 and t <= 1080, ("%d,%d -> %.0f %.0f %.0f %.0f"):format(offset[1], offset[2], l, b, r, t))
		end
	end)

	it("keeps the whole box on the screen for every anchor, screen, scale and extreme position", function()
		local bad = {}
		for _, screen in ipairs(SCREENS) do
			for percent = 60, 140, 4 do
				local scale = Nav().FitScale(percent / 100, screen[1], screen[2], 1116, 768, 92)
				for _, anchor in ipairs(ANCHOR_NAMES) do
					for _, e in ipairs(EXTREME) do
						local pos = { point = anchor, relPoint = anchor, x = e[1], y = e[2] }
						local x, y = Nav().ClampPos(pos, scale, screen[1], screen[2], BOX)
						local l, b, r, t = rectOf(anchor, anchor, x, y, scale, screen[1], screen[2])
						if l < -0.001 or b < -0.001 or r > screen[1] + 0.001 or t > screen[2] + 0.001 then
							bad[#bad + 1] = ("%dx%d scale %.2f %s %d,%d: %.0f %.0f %.0f %.0f"):format(screen[1], screen[2], scale, anchor, e[1], e[2], l, b, r, t)
						end
					end
				end
			end
		end
		eq(#bad, 0, table.concat(bad, "\n", 1, math.min(#bad, 10)))
	end)

	it("a relative point other than the window's own point is handled", function()
		local x, y = Nav().ClampPos({ point = "TOPLEFT", relPoint = "BOTTOMRIGHT", x = 100, y = 100 }, 0.85, 1280, 720, BOX)
		local l, b, r, t = rectOf("TOPLEFT", "BOTTOMRIGHT", x, y, 0.85, 1280, 720)
		truthy(l >= 0 and b >= 0 and r <= 1280 and t <= 720)
	end)

	it("a box bigger than the screen keeps its top left corner", function()
		local x, y = Nav().ClampPos({ point = "TOPLEFT", relPoint = "TOPLEFT", x = 300, y = -300 }, 1.4, 640, 480, BOX)
		local l, _, _, t = rectOf("TOPLEFT", "TOPLEFT", x, y, 1.4, 640, 480)
		near(l, Nav().CLAMP_MARGIN, 0.001)
		near(t, 480 - Nav().CLAMP_MARGIN, 0.001, "the top edge against the margin")
	end)

	it("answers with the position unchanged for sizes or anchors it cannot use", function()
		local pos = { point = "CENTER", relPoint = "CENTER", x = 9000, y = 9000 }
		local x, y, moved = Nav().ClampPos(pos, 1, nil, nil, BOX)
		eq(x, 9000); eq(y, 9000); falsy(moved)
		x, y, moved = Nav().ClampPos(pos, 1, 0, 0, BOX)
		eq(x, 9000); falsy(moved)
		x, y, moved = Nav().ClampPos({ point = "NOWHERE", x = 5, y = 6 }, 1, 1920, 1080, BOX)
		eq(x, 5); eq(y, 6); falsy(moved)
		x, y, moved = Nav().ClampPos(pos, 1, 1920, 1080, nil)
		eq(x, 9000); falsy(moved)
	end)

	it("the scale handed in is clamped like everywhere else", function()
		local x1 = Nav().ClampPos({ point = "CENTER", relPoint = "CENTER", x = 5000, y = 0 }, 99, 1920, 1080, BOX)
		local x2 = Nav().ClampPos({ point = "CENTER", relPoint = "CENTER", x = 5000, y = 0 }, 1.4, 1920, 1080, BOX)
		eq(x1, x2)
	end)
end)

describe("the window at 1280 x 720 and at every scale", function()
	local function screen(w, h) UIParent:SetSize(w, h) end

	-- The box of the open window in parent units, from the point the window really got.
	local function openRect()
		local f = main().frame
		local point, _, relPoint, x, y = f:GetPoint(1)
		local scale = main().effective
		local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
		local l, b, r, t = rectOf(point, relPoint, x * scale, y * scale, scale, pw, ph)
		return l, b, r, t
	end

	it("at every scale from 60 to 140 % the book, the rail and the close button fit 1280 x 720", function()
		screen(1280, 720)
		main():Show()
		local bad = {}
		for percent = 60, 140, 2 do
			main():SetScale(percent / 100)
			local l, b, r, t = openRect()
			if l < 0 or b < 0 or r > 1280 or t > 720 then bad[#bad + 1] = ("%d%%: %.0f %.0f %.0f %.0f"):format(percent, l, b, r, t) end
		end
		eq(#bad, 0, table.concat(bad, "\n"))
		-- the scale chosen is kept even where a smaller one is used
		main():SetScale(1.4)
		eq(main():GetScale(), 1.4)
		truthy(main().effective < 1.4)
		eq(A().Config:Get("account.settings.uiScale"), 1.4)
	end)

	it("a position saved on a big screen is pulled back on a small one and not forgotten", function()
		screen(2560, 1440)
		local saved = { point = "CENTER", relPoint = "CENTER", x = 500, y = -300 }
		A().Config:Set("char.ui.mainPos", saved)
		main():Show()
		local l, b, r, t = openRect()
		truthy(l >= 0 and b >= 0 and r <= 2560 and t <= 1440)
		screen(1280, 720)
		Mock.Fire("DISPLAY_SIZE_CHANGED")
		l, b, r, t = openRect()
		truthy(l >= 0 and b >= 0 and r <= 1280 and t <= 720, ("%.0f %.0f %.0f %.0f"):format(l, b, r, t))
		deepEq(A().Config:Get("char.ui.mainPos"), saved, "the saved place is kept")
		screen(2560, 1440)
		Mock.Fire("DISPLAY_SIZE_CHANGED")
		local point, _, _, x, y = main().frame:GetPoint(1)
		eq(point, "CENTER")
		near(x * main().effective, 500, 0.01)
		near(y * main().effective, -300, 0.01)
	end)

	it("a saved position far outside any screen opens on the screen", function()
		screen(1280, 720)
		for _, e in ipairs(EXTREME) do
			A().Config:Set("char.ui.mainPos", { point = "TOPLEFT", relPoint = "TOPLEFT", x = e[1], y = e[2] })
			main():Hide(); main():Show()
			main():ApplyScale()
			local l, b, r, t = openRect()
			truthy(l >= -0.001 and b >= -0.001 and r <= 1280.001 and t <= 720.001, ("%d,%d: %.0f %.0f %.0f %.0f"):format(e[1], e[2], l, b, r, t))
		end
	end)

	it("the default place is on the screen too", function()
		for _, s in ipairs(SCREENS) do
			screen(s[1], s[2])
			A().Config:Set("char.ui.mainPos", nil)
			main():Show()
			main():ApplyScale()
			local l, b, r, t = openRect()
			truthy(l >= 0 and b >= 0 and r <= s[1] and t <= s[2], ("%dx%d: %.0f %.0f %.0f %.0f"):format(s[1], s[2], l, b, r, t))
		end
	end)

	it("dragging and saving keeps working: the saved place is what the window has", function()
		screen(1920, 1080)
		main():Show()
		main().frame:ClearAllPoints()
		main().frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -60)
		main():SavePosition()
		local pos = A().Config:Get("char.ui.mainPos")
		eq(pos.point, "TOPLEFT")
		near(pos.x, 40 * main().effective, 0.01)
		near(pos.y, -60 * main().effective, 0.01)
	end)

	it("the notification icon is pulled back on screen as well", function()
		setRole("gm")
		screen(1280, 720)
		A().Config:Set("char.ui.notifyPos", { point = "CENTER", relPoint = "CENTER", x = 99999, y = -99999 })
		local Notify = A().Notify
		Notify:Create()
		local _, _, _, x, y = Notify.frame:GetPoint(1)
		truthy(math.abs(x) <= 640 and math.abs(y) <= 360, ("%s %s"):format(tostring(x), tostring(y)))
	end)
end)
