-- Nav: the navigation of the main window as plain Lua, no frames (SPEC-04 §2, SPEC-00 §5). It decides which tabs
-- a role sees, keeps one page stack per tab ("Back" and the filters you left behind), and does the arithmetic of the
-- window's scale and saved position. UI/Main.lua draws what this module says; the tests run it without a client.
--
--   Nav.TabsFor(role, hasListing)   -> { "Settings", <the panels of the role> }   (Settings is always first)
--   Nav.NewStack(root)              -> a page stack: Push, Back, Top, Depth, CanGoBack, Reset, Replace, SaveState
--   Nav.NewBook()                   -> the tabs and one stack per tab: SetTabs, Select, Push, Back, Current, Page
--   Nav.ClampScale / FitScale       -> window scale 60 %..140 %, and the largest scale that fits the screen
--   Nav.PosToSaved / SavedToPos     -> a window position that survives a change of scale
--
-- Tab ids are the panel names of Core/Role (FindGuild, MyApplication, MyGuild, CreateListing, Applications) plus
-- "Settings". The root page of a tab has the id of the tab; pages pushed on top of it (a guild page) have their own.
local ADDON_NAME, ns = ...
ns = ns or {}
local Nav = {}
ns.Nav, ns.modules = Nav, ns.modules or {}
ns.modules.Nav = Nav

local type, ipairs, pairs, setmetatable, tostring = type, ipairs, pairs, setmetatable, tostring
local floor, min, max = math.floor, math.min, math.max

Nav.SETTINGS = "Settings"
Nav.SCALE_MIN, Nav.SCALE_MAX, Nav.SCALE_DEFAULT = 0.6, 1.4, 1.0
Nav.MAX_DEPTH = 12

-- Every tab the window can show: the label key (Locale) and the glyph of Media/. Order here is not display order.
Nav.TABS = {
	Settings = { labelKey = "TAB_Settings", glyph = "glyph_gear" },
	FindGuild = { labelKey = "TAB_FindGuild", glyph = "glyph_search" },
	MyApplication = { labelKey = "TAB_MyApplication", glyph = "glyph_doc" },
	MyGuild = { labelKey = "TAB_MyGuild", glyph = "glyph_shield" },
	CreateListing = { labelKey = "TAB_CreateListing", glyph = "glyph_plus" },
	Applications = { labelKey = "TAB_Applications", glyph = "glyph_inbox" },
}

function Nav.IsTab(id) return type(id) == "string" and Nav.TABS[id] ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- Role -> tabs
---------------------------------------------------------------------------------------------------------------------
-- The tab ids shown to `role` ("none"|"member"|"officer"|"gm"), Settings first, then the panels of SPEC-00 §5 in their
-- order. `hasListing`: the guild has a published listing (decides Applications for the GM and officers, Create Listing
-- for the GM). An unknown role is treated as having no guild.
function Nav.TabsFor(role, hasListing)
	local tabs = { Nav.SETTINGS }
	local Role = ns.Role
	local panels = Role and Role.PanelsFor and Role.PanelsFor(role, hasListing and true or false) or {}
	for _, panel in ipairs(panels) do
		if Nav.TABS[panel] then tabs[#tabs + 1] = panel end
	end
	return tabs
end

-- The tab the window opens on: the first tab of the role, or Settings when it has none.
function Nav.DefaultTab(tabs)
	return tabs[2] or tabs[1] or Nav.SETTINGS
end

---------------------------------------------------------------------------------------------------------------------
-- Page stack
---------------------------------------------------------------------------------------------------------------------
local Stack = {}
Stack.__index = Stack

-- A stack with `root` (a page id) at the bottom. Each entry is { page, params, state }: `state` is a table the page
-- fills when it is left (filters, scroll position) and finds again when Back returns to it.
function Nav.NewStack(root)
	return setmetatable({ entries = { { page = root, state = {} } } }, Stack)
end

function Stack:Top() return self.entries[#self.entries] end
function Stack:Root() return self.entries[1] end
function Stack:Depth() return #self.entries end
function Stack:CanGoBack() return #self.entries > 1 end

function Stack:Pages()
	local out = {}
	for i, e in ipairs(self.entries) do out[i] = e.page end
	return out
end

-- Puts a page on top. Past MAX_DEPTH the oldest page above the root is dropped. Returns the new entry.
function Stack:Push(page, params)
	local entry = { page = page, params = params, state = {} }
	self.entries[#self.entries + 1] = entry
	if #self.entries > Nav.MAX_DEPTH then table.remove(self.entries, 2) end
	return entry
end

-- Takes the top page off. Returns the page that was left and the one now on top, or nil at the root.
function Stack:Back()
	if #self.entries <= 1 then return nil end
	local left = table.remove(self.entries)
	return left, self:Top()
end

function Stack:Replace(page, params)
	local entry = { page = page, params = params, state = {} }
	self.entries[#self.entries] = entry
	return entry
end

-- Back to a single page (the given one, or the current root).
function Stack:Reset(root, params)
	local page = root or self.entries[1].page
	self.entries = { { page = page, params = params, state = {} } }
	return self.entries[1]
end

-- Stores `state` (a table) on the top entry: what the page wants back after Back.
function Stack:SaveState(state)
	self:Top().state = state or {}
end

function Stack:GetState() return self:Top().state end

---------------------------------------------------------------------------------------------------------------------
-- Book: tabs and one stack each
---------------------------------------------------------------------------------------------------------------------
local Book = {}
Book.__index = Book

-- `onChange(kind)` is called after every change; kind is "tabs", "select", "push", "back" or "home".
function Nav.NewBook(onChange)
	return setmetatable({ tabs = {}, stacks = {}, current = nil, onChange = onChange }, Book)
end

function Book:Notify(kind)
	if self.onChange then self.onChange(kind) end
end

local function sameList(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end

-- Sets the tabs (ids, Settings first). Tabs that stay keep their stack, new ones start at their root, tabs that
-- are gone lose theirs. The current tab stays when it is still there, else the default tab is selected. `reset`
-- (a change of role): every stack starts again and the default tab is selected. Returns true when anything changed.
function Book:SetTabs(tabs, reset)
	local clean = {}
	for _, id in ipairs(tabs or {}) do
		if Nav.IsTab(id) then clean[#clean + 1] = id end
	end
	if #clean == 0 then clean[1] = Nav.SETTINGS end
	local sameTabs = sameList(clean, self.tabs)
	if sameTabs and not reset then return false end

	local stacks = {}
	for _, id in ipairs(clean) do
		stacks[id] = (not reset and self.stacks[id]) or Nav.NewStack(id)
	end
	local keep = not reset and self.current ~= nil and stacks[self.current] ~= nil
	self.tabs, self.stacks = clean, stacks
	self.current = keep and self.current or Nav.DefaultTab(clean)
	self:Notify("tabs")
	return true
end

function Book:Tabs() return self.tabs end
function Book:Current() return self.current end
function Book:Has(id) return self.stacks[id] ~= nil end
function Book:Stack() return self.current and self.stacks[self.current] end
function Book:Page() local s = self:Stack(); return s and s:Top() end
function Book:CanGoBack() local s = self:Stack(); return s ~= nil and s:CanGoBack() end

-- Selects a tab; false when the role does not have it.
function Book:Select(id)
	if not self.stacks[id] then return false end
	if self.current == id then return true end
	self.current = id
	self:Notify("select")
	return true
end

-- Opens a page on top of the current tab.
function Book:Push(page, params)
	local s = self:Stack()
	if not s then return nil end
	local entry = s:Push(page, params)
	self:Notify("push")
	return entry
end

function Book:Back()
	local s = self:Stack()
	if not s then return false end
	local left = s:Back()
	if not left then return false end
	self:Notify("back")
	return true
end

-- Back to the root page of the current tab.
function Book:Home()
	local s = self:Stack()
	if not s or not s:CanGoBack() then return false end
	s:Reset()
	self:Notify("home")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Scale and position
---------------------------------------------------------------------------------------------------------------------
local function isNumber(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- 60 %..140 % in whole percent (0.6..1.4); anything that is not a number gives 100 %.
function Nav.ClampScale(value)
	if not isNumber(value) then return Nav.SCALE_DEFAULT end
	local percent = floor(value * 100 + 0.5)
	return max(Nav.SCALE_MIN * 100, min(Nav.SCALE_MAX * 100, percent)) / 100
end

-- "100%" for a scale.
function Nav.ScaleLabel(scale) return ("%d%%"):format(floor(Nav.ClampScale(scale) * 100 + 0.5)) end

-- A percentage typed by the user ("80", "80%", " 120 ") -> a scale, or nil when it is not a number or outside 60..140.
function Nav.ParseScale(text)
	local n = tostring(text or ""):match("^%s*(%d+)%s*%%?%s*$")
	n = n and tonumber(n)
	if not n or n < Nav.SCALE_MIN * 100 or n > Nav.SCALE_MAX * 100 then return nil end
	return n / 100
end

local FIT_MARGIN = 16   -- px of the parent kept free around the window (the close button and the rail stick out)

-- The scale to use: the wanted one, but never so big that the book, its rail and the close button leave the screen.
-- Sizes are those of the parent (UIParent) in its own units; a window that already fits is not changed.
function Nav.FitScale(wanted, parentW, parentH, windowW, windowH, railW)
	local scale = Nav.ClampScale(wanted)
	if not (isNumber(parentW) and isNumber(parentH) and parentW > 0 and parentH > 0) then return scale end
	local totalW = (windowW or 1116) + (railW or 92) + 12
	local totalH = (windowH or 768) + 12
	local fit = min((parentW - FIT_MARGIN) / totalW, (parentH - FIT_MARGIN) / totalH)
	if fit < scale then return max(0.25, floor(fit * 100) / 100) end
	return scale
end

-- A position measured in the window's own units becomes one in parent units (and back), so the same place on the
-- screen is kept when the scale changes. pos = { point, relPoint, x, y } (Config.IsPos).
function Nav.PosToSaved(point, relPoint, x, y, scale)
	scale = Nav.ClampScale(scale)
	return { point = point, relPoint = relPoint or point, x = (x or 0) * scale, y = (y or 0) * scale }
end

function Nav.SavedToPos(pos, scale)
	scale = Nav.ClampScale(scale)
	return pos.point, pos.relPoint or pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale
end

-- The default place: the centre of the screen, a little to the left so that the rail has room.
Nav.DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = -46, y = 0 }

if ns.addon then ns.addon.Nav = Nav end
