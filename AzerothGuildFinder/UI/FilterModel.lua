-- FilterModel: the filters of the Find a Guild list as plain Lua, no frames (SPEC-05 §2). UI/FilterPanel.lua draws the
-- controls and calls this module; the tests run it without a client. Lua 5.1 (no bit operators: masks use arithmetic).
--
-- The state of the filters (one table, saved per character in `char.ui.filters`; every field is a number or a boolean):
--   recruiting   boolean   only guilds that recruit (`rec ~= 0`); on for a character that never chose
--   myClass      boolean   the guild wants my class, or any class (`want[myClass]` or `want[0]`)
--   reqs         boolean   my level and item level meet the minimums the guild states
--   newb         boolean   new player friendly (`newb`)
--   roles        mask 0..15       Tank 1, Healer 2, Melee 4, Ranged 8: a role the guild wants in common (see Matches)
--   langs        mask 0..511      bit i-1 = Enums.LANGUAGES[i]: at least one language in common
--   paces        mask 0..7        bit pace-1: Casual 1, Softcore 2, Hardcore 4
--   acts         mask 0..8191     bit id-1 = Enums.ACTIVITIES: at least one activity in common
--   days         mask 0..127      Monday = bit 0 ... Sunday = bit 6, in the PLAYER's time: at least one day in common
--   timeFrom, timeTo   minutes 0..1439 or nil   play time in the PLAYER's time (see Model.TimeActive)
--   minActive    0 | 5 | 10 | 25 | 50   `st.a7 >= minActive`
-- "Reset" turns everything off (including `recruiting`), so a reset list shows every guild.
--
--   Model.Defaults()  Model.Reset()  Model.Sanitize(raw, player)   states (a new table each time)
--   Model.Count(state, player)     how many filters narrow the list (the "4 active" of the plate)
--   Model.Compile(state, ctx)      -> fn(sum, info) -> true keeps a listing; nil when no filter is active.
--                                     ctx: player (BrowseModel.Player()), offset (minutes of the player's zone from UTC)
--   Model.Windows / Model.Overlap  time windows around midnight
--   Model.NewController(opts)      the state with persistence and change notification (used by the panel)
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.FilterModel, ns.modules = Model, ns.modules or {}
ns.modules.FilterModel = Model

local type, ipairs, pairs, tonumber, pcall = type, ipairs, pairs, tonumber, pcall
local floor, min, max = math.floor, math.min, math.max

Model.MIN_ACTIVE_STEPS = { 0, 5, 10, 25, 50 }   -- the choices of "Min. active members"
Model.TIME_STEP = 30                            -- minutes between two choices of the time menus
Model.DAYS = 1 + 2 + 4 + 8 + 16 + 32 + 64

local function Enums() return ns.Enums end
local function Browse() return ns.BrowseModel end

---------------------------------------------------------------------------------------------------------------------
-- Masks
---------------------------------------------------------------------------------------------------------------------
-- true when bit number `n` (0 = lowest) is set in `mask`.
local function hasBit(mask, n) return floor(mask / 2 ^ n) % 2 == 1 end

-- true when the two masks share a set bit among the lowest `bits` bits.
local function share(a, b, bits)
	if a == 0 or b == 0 then return false end
	for n = 0, bits - 1 do
		if hasBit(a, n) and hasBit(b, n) then return true end
	end
	return false
end

-- A number as an integer inside 0..top (anything else: `default`).
local function intIn(v, top, default)
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return default end
	return max(0, min(top, floor(v)))
end

local function bool(v, default)
	if type(v) == "boolean" then return v end
	return default
end

Model.HasBit, Model.Share = hasBit, share

-- The bit of a day-of-week number 1 (Monday) .. 7 (Sunday) in a days mask, a language index or an activity id in theirs.
function Model.MaskOf(list, offset)
	local mask = 0
	for _, v in ipairs(list or {}) do mask = mask + 2 ^ (v - (offset or 1)) end
	return mask
end

-- The numbers 1.. of the set bits of a mask (language indexes, activity ids, day numbers).
function Model.ListOf(mask, count)
	local out = {}
	for i = 1, count do
		if hasBit(mask or 0, i - 1) then out[#out + 1] = i end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- States
---------------------------------------------------------------------------------------------------------------------
-- A character that never chose: only the guilds that recruit.
function Model.Defaults()
	return { recruiting = true, myClass = false, reqs = false, newb = false, roles = 0, langs = 0, paces = 0, acts = 0,
		days = 0, timeFrom = nil, timeTo = nil, minActive = 0 }
end

-- Everything off (the button "Reset all filters").
function Model.Reset()
	local s = Model.Defaults()
	s.recruiting = false
	return s
end

-- A state read from the saved data: unknown keys dropped, wrong types and out-of-range numbers replaced, the roles
-- reduced to those the player's class can play (SPEC-03 §5). `player` may be nil.
function Model.Sanitize(raw, player)
	raw = type(raw) == "table" and raw or {}
	local E = Enums()
	local d = Model.Defaults()
	local s = {
		recruiting = bool(raw.recruiting, d.recruiting), myClass = bool(raw.myClass, false), reqs = bool(raw.reqs, false),
		newb = bool(raw.newb, false),
		roles = intIn(raw.roles, E.ROLE_MASK, 0), langs = intIn(raw.langs, E.LANGUAGE_MASK, 0),
		paces = intIn(raw.paces, 2 ^ E.PACE_COUNT - 1, 0), acts = intIn(raw.acts, 2 ^ E.ACTIVITY_COUNT - 1, 0),
		days = intIn(raw.days, Model.DAYS, 0), minActive = 0,
	}
	if raw.timeFrom ~= nil then s.timeFrom = intIn(raw.timeFrom, 1439, nil) end
	if raw.timeTo ~= nil then s.timeTo = intIn(raw.timeTo, 1439, nil) end
	for _, step in ipairs(Model.MIN_ACTIVE_STEPS) do
		if raw.minActive == step then s.minActive = step end
	end
	if player and player.classID then s.roles = E.FilterRoles(player.classID, s.roles) end
	return s
end

---------------------------------------------------------------------------------------------------------------------
-- Time windows (minutes 0..1439; the end is exclusive; end < start wraps over midnight; start == end is the whole day)
---------------------------------------------------------------------------------------------------------------------
-- The window as up to two plain intervals inside one day: { {s, e}, ... } with s < e <= 1440.
function Model.Windows(s, e)
	if s == e then return { { 0, 1440 } } end
	if s < e then return { { s, e } } end
	return { { s, 1440 }, { 0, e } }
end

-- true when the two windows share at least one minute (windows that only touch do not overlap).
function Model.Overlap(s1, e1, s2, e2)
	for _, a in ipairs(Model.Windows(s1, e1)) do
		for _, b in ipairs(Model.Windows(s2, e2)) do
			if max(a[1], b[1]) < min(a[2], b[2]) then return true end
		end
	end
	return false
end

-- The window the filter asks for, or nil when it asks for nothing. With only a start the window runs to midnight, with
-- only an end it starts at midnight; equal bounds mean the whole day, which narrows nothing.
function Model.TimeWindow(state)
	local from, to = state.timeFrom, state.timeTo
	if from == nil and to == nil then return nil end
	from, to = from or 0, to or 0
	if from == to then return nil end
	return from, to
end

function Model.TimeActive(state) return Model.TimeWindow(state) ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- Which filters are on
---------------------------------------------------------------------------------------------------------------------
-- The ids of the active filters, in the order of the panel.
Model.ORDER = { "recruiting", "myClass", "reqs", "newb", "roles", "langs", "paces", "acts", "days", "time", "minActive" }

function Model.IsActive(state, id)
	if id == "time" then return Model.TimeActive(state) end
	local v = state[id]
	if type(v) == "boolean" then return v end
	return type(v) == "number" and v > 0
end

function Model.ActiveList(state)
	local out = {}
	for _, id in ipairs(Model.ORDER) do
		if Model.IsActive(state, id) then out[#out + 1] = id end
	end
	return out
end

function Model.Count(state) return #Model.ActiveList(state) end

function Model.IsReset(state) return Model.Count(state) == 0 end

---------------------------------------------------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------------------------------------------------
-- The roles a listing wants from the player: for the player's class and for any class, as one mask. With no known class
-- every wanted role counts.
local function wantedRoles(sum, classID)
	local want = sum.want
	if type(want) ~= "table" then return 0 end
	local mask = 0
	local E = Enums()
	for id, roles in pairs(want) do
		if type(roles) == "number" and (id == 0 or classID == nil or id == classID) then
			for _, r in ipairs(E.ROLES) do
				if E.HasRole(roles, r.bit) and not E.HasRole(mask, r.bit) then mask = mask + r.bit end
			end
		end
	end
	return mask
end

local function languagesOf(sum)
	local mask = type(sum.lang) == "number" and floor(sum.lang) or 0
	local E = Enums()
	local bit = type(sum.lang1) == "number" and E.LanguageBit(sum.lang1)
	if bit and not hasBit(mask, sum.lang1 - 1) then mask = mask + bit end
	return mask
end

local function activitiesOf(sum)
	local mask = 0
	for _, id in ipairs(type(sum.tags) == "table" and sum.tags or {}) do
		if type(id) == "number" and Enums().IsActivity(id) and not hasBit(mask, id - 1) then mask = mask + 2 ^ (id - 1) end
	end
	return mask
end

-- The filter as a function of one listing, or nil when nothing is active (then no function runs per listing).
-- Compile once per rebuild of the list: it reads the player and the zone only here.
function Model.Compile(state, ctx)
	ctx = ctx or {}
	local player = ctx.player or {}
	local offset = ctx.offset or 0
	local E, B = Enums(), Browse()
	local checks = {}
	local function add(fn) checks[#checks + 1] = fn end

	if state.recruiting then
		add(function(sum) return sum.rec ~= 0 end)
	end
	if state.myClass and player.classID then
		local id = player.classID
		add(function(sum) return type(sum.want) == "table" and (sum.want[id] ~= nil or sum.want[0] ~= nil) end)
	end
	if state.reqs then
		add(function(sum) return B.Requirements(sum, player).ok ~= false end)   -- unknown is not a failure
	end
	if state.newb then
		add(function(sum) return sum.newb == true end)
	end
	local roles = state.roles
	if player.classID then roles = E.FilterRoles(player.classID, roles) end
	if roles > 0 then
		add(function(sum) return share(roles, wantedRoles(sum, player.classID), 4) end)
	end
	if state.langs > 0 then
		local mask = state.langs
		add(function(sum) return share(mask, languagesOf(sum), E.LANGUAGE_COUNT) end)
	end
	if state.paces > 0 then
		local mask = state.paces
		add(function(sum) return type(sum.pace) == "number" and E.IsPace(sum.pace) and hasBit(mask, sum.pace - 1) end)
	end
	if state.acts > 0 then
		local mask = state.acts
		add(function(sum) return share(mask, activitiesOf(sum), E.ACTIVITY_COUNT) end)
	end

	-- days and times: the listing is declared in UTC and compared in the player's time zone
	local from, to = Model.TimeWindow(state)
	local days = state.days
	if days > 0 or from then
		add(function(sum)
			local ld, l0, l1 = B.ToLocal(sum.days, sum.t0, sum.t1, offset)
			if days > 0 and not (type(ld) == "number" and share(days, floor(ld), 7)) then return false end
			if from and not (l0 ~= nil and l1 ~= nil and Model.Overlap(from, to, l0, l1)) then return false end
			return true
		end)
	end
	if state.minActive > 0 then
		local need = state.minActive
		add(function(sum) return type(sum.st) == "table" and type(sum.st.a7) == "number" and sum.st.a7 >= need end)
	end

	if #checks == 0 then return nil end
	return function(sum, info)
		for i = 1, #checks do
			if not checks[i](sum, info) then return false end
		end
		return true
	end
end

-- One listing against a state (a convenience for tests and one-off checks).
function Model.Matches(state, sum, info, ctx)
	local fn = Model.Compile(state, ctx)
	return fn == nil or fn(sum, info) == true
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
-- "Filters", "Filters · 4 active".
function Model.PlateText(count, L)
	if count <= 0 then return L["BROWSE_FILTERS"] end
	return L["BROWSE_FILTERS_ACTIVE"]:format(count)
end

-- "20:30" for a minute of the day; a menu step's label.
function Model.TimeLabel(minutes) return Browse().FormatMinutes(minutes) end

-- The choices of a time menu: { { value = nil | minutes }, ... } every TIME_STEP minutes; nil is "Any".
function Model.TimeChoices()
	local out = {}
	for m = 0, 1439, Model.TIME_STEP do out[#out + 1] = m end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Controller: the state, saved on every change, with the notification of the panel and of the list
---------------------------------------------------------------------------------------------------------------------
-- opts: load() -> saved table or nil; save(table); player() -> BrowseModel.Player(); offset() -> minutes; onChange(controller).
local Controller = {}
Controller.__index = Controller

local function copyState(s)
	local out = {}
	for k, v in pairs(s) do out[k] = v end
	return out
end

function Model.NewController(opts)
	local c = setmetatable({ opts = opts or {}, compiled = false }, Controller)
	c.state = Model.Sanitize(c.opts.load and c.opts.load() or nil, c:Player())
	return c
end

function Controller:Player()
	local fn = self.opts.player
	if not fn then return nil end
	local ok, player = pcall(fn)
	return ok and player or nil
end

function Controller:Offset()
	local fn = self.opts.offset
	if not fn then return 0 end
	local ok, offset = pcall(fn)
	return ok and tonumber(offset) or 0
end

function Controller:Get(id) return self.state[id] end
function Controller:State() return copyState(self.state) end
function Controller:Count() return Model.Count(self.state) end
function Controller:IsActive(id) return Model.IsActive(self.state, id) end

-- Writes the state to the saved data (a copy: the saved table is never the one the panel edits).
function Controller:Save()
	if self.opts.save then self.opts.save(copyState(self.state)) end
end

function Controller:Changed()
	self.compiled = false
	self:Save()
	if self.opts.onChange then self.opts.onChange(self) end
end

-- Sets one field (booleans and masks as they are; the time bounds may be nil). The value goes through Sanitize, so a
-- wrong value never gets in. Returns true when the state changed.
function Controller:Set(id, value)
	local candidate = copyState(self.state)
	candidate[id] = value
	local clean = Model.Sanitize(candidate, self:Player())
	if clean[id] == self.state[id] then return false end
	self.state = clean
	self:Changed()
	return true
end

-- Both bounds of the play time at once (nil, nil: no time filter).
function Controller:SetTime(from, to)
	local candidate = copyState(self.state)
	candidate.timeFrom, candidate.timeTo = from, to
	local clean = Model.Sanitize(candidate, self:Player())
	if clean.timeFrom == self.state.timeFrom and clean.timeTo == self.state.timeTo then return false end
	self.state = clean
	self:Changed()
	return true
end

function Controller:Toggle(id) return self:Set(id, not self.state[id]) end

-- Turns every bit of `bit` (a number 1..n) in the mask field `id` on or off.
function Controller:SetBit(id, bit, on)
	local mask = self.state[id] or 0
	local has = hasBit(mask, bit - 1)
	if on and not has then mask = mask + 2 ^ (bit - 1) elseif not on and has then mask = mask - 2 ^ (bit - 1) end
	return self:Set(id, mask)
end

function Controller:Reset()
	self.state = Model.Reset()
	self:Changed()
	return true
end

-- The function the list calls for each listing (nil: no filter narrows it). Compiled again after every change and, with
-- Refresh(), when the list is rebuilt, so the level, item level and time zone are current.
function Controller:Predicate()
	if self.compiled == false then
		self.compiled = Model.Compile(self.state, { player = self:Player(), offset = self:Offset() }) or nil
	end
	return self.compiled
end

function Controller:Refresh() self.compiled = false end

if ns.addon then ns.addon.FilterModel = Model end
