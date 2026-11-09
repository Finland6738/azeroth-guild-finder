-- BrowseModel: the logic of the Find a Guild list as plain Lua, no frames (SPEC-05 §1, SPEC-03 §7). UI/Browse.lua draws
-- what this module says; the tests run it without a client. Lua 5.1.
--
--   Model.Query(text)                    -> { raw, key, state }  state "empty" | "short" (1-2 letters) | "active" (3+)
--   Model.Predicate(query, filter)       -> function(sum, info) for Catalog:List, or nil when nothing narrows the list.
--                                           `filter(sum, info)` is the hook of the filters (M2.6): true keeps a listing.
--   Model.Build(catalog, query, filter)  -> { list = summaries A -> Z, total, shown }
--   Model.State(ctx)                     -> { kind, hint, reset }: what the list area shows (loading, nopeers, empty,
--                                           nomatch, list) and the hint under the search box
--   Model.StateText(state, query, L)     -> the message of a state (nil for "list")
--   Model.CountText / Model.StatusLine   -> "24 of 142 guilds"; "142 guilds known · synced 2 min ago"
--   Model.Card(sum, info, player, ...)   -> the display fields of one listing (texts, wanted classes, requirement checks)
--   Model.ToLocal(days, t0, t1, offset)  -> the play days and times of a listing (UTC) in another time zone
--   Model.Window / ScrollMax / Pool      -> virtual scrolling: which rows are visible and which pooled frame shows them
--   Model.NewCoalescer(after, delay, fn) -> throttle: many requests, one call after `delay` seconds
--   Model.NewDebouncer(after, delay, fn) -> debounce: one call `delay` seconds after the last one (the search box)
--
-- Ordering is the catalog's (Catalog:List: Normalize.Compare, always A -> Z, ADR 0009); the list never has another order.
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.BrowseModel, ns.modules = Model, ns.modules or {}
ns.modules.BrowseModel = Model

local type, pairs, ipairs, tostring, tonumber, select, unpack, next = type, pairs, ipairs, tostring, tonumber, select, unpack, next
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local find, upper = string.find, string.upper
local sort, concat = table.sort, table.concat

Model.CARD_H = 176          -- px, one guild card
Model.GAP = 12              -- px between two cards
Model.STEP = Model.CARD_H + Model.GAP
Model.DEBOUNCE = 0.25       -- seconds the search waits after the last key (SPEC-05 §1)
Model.THROTTLE = 0.3        -- seconds the list waits after a catalog change before it is rebuilt
Model.MAX_LANGS = 4         -- language tags on a card
Model.MAX_CLASSES = 4       -- class icons on a card, then "+N"
Model.MAX_ACTIVITIES = 3
Model.SYNC_STALE = 3600     -- a sync older than this is shown in the status bar without the green dot

local function Normalize() return ns.Normalize end
local function Listing() return ns.Listing end
local function Enums() return ns.Enums end

---------------------------------------------------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------------------------------------------------
-- The search text normalized like names (SPEC-03 §7). "empty": nothing (letters) typed; "short": fewer than 3 letters,
-- the list is not narrowed and the hint "Type at least 3 letters" shows; "active": the list is narrowed.
function Model.Query(text)
	local raw = type(text) == "string" and text or ""
	local key = Normalize().SearchKey(raw)
	local state = key == "" and "empty" or (#key < Normalize().MIN_QUERY and "short" or "active")
	return { raw = raw, key = key, state = state }
end

-- The sort key of a guild name, kept for the next search: a query then costs one string search per listing.
local nameKeys, nameKeyCount = {}, 0
local MAX_NAME_KEYS = 2000

function Model.NameKey(k)
	local cached = nameKeys[k]
	if cached then return cached end
	local _, _, name = Listing().ParseKey(k)
	local key = Normalize().SortKey(name or k)
	if nameKeyCount >= MAX_NAME_KEYS then nameKeys, nameKeyCount = {}, 0 end
	nameKeys[k] = key
	nameKeyCount = nameKeyCount + 1
	return key
end

-- The predicate for Catalog:List, or nil when neither the search nor the filters narrow the list.
function Model.Predicate(query, filter)
	local needle = query and query.state == "active" and query.key or nil
	if not needle and not filter then return nil end
	return function(sum, info)
		if needle and not find(Model.NameKey(sum.k), needle, 1, true) then return false end
		if filter and not filter(sum, info) then return false end
		return true
	end
end

-- The visible listings (A -> Z) and the numbers for the count: total = what the user may see without any search.
function Model.Build(catalog, query, filter)
	local total = catalog:Count()
	local list = catalog:List(Model.Predicate(query, filter))
	return { list = list, total = total, shown = #list }
end

---------------------------------------------------------------------------------------------------------------------
-- States of the list (SPEC-05 §1)
---------------------------------------------------------------------------------------------------------------------
-- ctx: total (listings the user may see), shown (after search and filters), query (Model.Query), filters (number of
-- active filters), syncing (a catalog request is running), peers (other Guild Finder users heard recently).
--   loading   nothing known yet and a sync is running: spinner
--   nopeers   nothing known, nobody answered and nobody is around
--   empty     nothing known although peers are around (nobody on this realm and faction has published yet)
--   nomatch   listings exist, none passes the search and filters
--   list      the cards
-- hint "short": the query has 1-2 letters (the list is not narrowed). reset: the "Reset filters" button shows.
function Model.State(ctx)
	local state = { kind = "list" }
	if ctx.query and ctx.query.state == "short" then state.hint = "short" end
	if (ctx.total or 0) == 0 then
		if ctx.syncing then state.kind = "loading"
		elseif (ctx.peers or 0) == 0 then state.kind = "nopeers"
		else state.kind = "empty" end
	elseif (ctx.shown or 0) == 0 then
		state.kind = "nomatch"
		state.reset = (ctx.filters or 0) > 0
	end
	return state
end

local STATE_KEYS = {
	loading = "BROWSE_LOADING", nopeers = "BROWSE_NOPEERS", empty = "BROWSE_EMPTY",
}

-- The message of a state, or nil for "list". `query` names the search in the "nomatch" message when no filter is active.
function Model.StateText(state, query, L)
	if state.kind == "nomatch" then
		if state.reset or not (query and query.state == "active") then return L["BROWSE_NOMATCH_FILTERS"] end
		return L["BROWSE_NOMATCH_QUERY"]:format((query.raw:gsub("|", "||")))   -- a pipe in the text is not a colour code
	end
	local key = STATE_KEYS[state.kind]
	return key and L[key] or nil
end

function Model.HintText(state, L)
	return state.hint == "short" and L["BROWSE_HINT_SHORT"] or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
-- "24 of 142 guilds", "142 guilds", "1 guild".
function Model.CountText(shown, total, L)
	if shown ~= total then return L[total == 1 and "BROWSE_COUNT_OF_1" or "BROWSE_COUNT_OF"]:format(shown, total) end
	return L[total == 1 and "BROWSE_COUNT_1" or "BROWSE_COUNT_N"]:format(total)
end

-- "2 min ago", "3 h ago", "yesterday", "4 days ago". `coarse`: a day-sized text for cards ("today" under 24 h).
function Model.AgeText(seconds, L, coarse)
	seconds = max(0, tonumber(seconds) or 0)
	local days = floor(seconds / 86400)
	if coarse then
		if days < 1 then return L["AGO_TODAY"] end
	elseif seconds < 60 then
		return L["AGO_NOW"]
	elseif seconds < 3600 then
		return L["AGO_MIN"]:format(floor(seconds / 60))
	elseif days < 1 then
		return L["AGO_HOUR"]:format(floor(seconds / 3600))
	end
	if days == 1 then return L["AGO_YESTERDAY"] end
	return L["AGO_DAYS"]:format(days)
end

-- The line of the status bar and the colour of its dot: "ok" synced recently, "warn" syncing now, "off" never synced.
-- ctx: total, syncing, lastSync (server time or nil), now.
function Model.StatusLine(ctx, L)
	local text = L[ctx.total == 1 and "BROWSE_STATUS_1" or "BROWSE_STATUS_N"]:format(ctx.total or 0)
	local level
	if ctx.syncing then
		text, level = text .. " · " .. L["BROWSE_STATUS_SYNCING"], "warn"
	elseif ctx.lastSync then
		local age = max(0, (ctx.now or ctx.lastSync) - ctx.lastSync)
		text = text .. " · " .. L["BROWSE_STATUS_SYNCED"]:format(Model.AgeText(age, L))
		level = age <= Model.SYNC_STALE and "ok" or "off"
	else
		text, level = text .. " · " .. L["BROWSE_STATUS_NEVER"], "off"
	end
	return text .. " · " .. L["BROWSE_STATUS_SCOPE"], level
end

---------------------------------------------------------------------------------------------------------------------
-- Days and times
---------------------------------------------------------------------------------------------------------------------
-- Minutes between UTC and this computer's time zone (east of Greenwich positive). The client's own clock
-- decides; a client without date() is taken as UTC.
function Model.LocalOffset(at)
	if type(date) ~= "function" or type(time) ~= "function" then return 0 end
	at = at or time()
	local ok, offset = pcall(function()
		local utc, here = date("!*t", at), date("*t", at)
		utc.isdst = here.isdst   -- both read with the same daylight-saving flag: the difference is the offset in force now
		return floor((time(here) - time(utc)) / 60 + 0.5)
	end)
	return ok and type(offset) == "number" and offset or 0
end

-- `days` is a 7-bit mask Monday..Sunday (bit 0 = Monday), t0/t1 minutes UTC (t0 == t1: all day). In a zone `offset`
-- minutes from UTC the start can fall on the day before or after: the days move with it and the times are wrapped to
-- 0..1439. Returns days, t0, t1 (nil stays nil; an all-day listing keeps its days).
function Model.ToLocal(days, t0, t1, offset)
	offset = tonumber(offset) or 0
	if t0 == nil or t1 == nil then return days, t0, t1 end
	if t0 == t1 then return days, t0, t1 end
	local shifted = t0 + offset
	local dayShift = floor(shifted / 1440)
	local l0, l1 = shifted % 1440, (t1 + offset) % 1440
	if days and dayShift ~= 0 then
		local out = 0
		for d = 0, 6 do
			if floor(days / 2 ^ d) % 2 == 1 then out = out + 2 ^ ((d + dayShift) % 7) end
		end
		days = out
	end
	return days, l0, l1
end

function Model.FormatMinutes(m)
	m = floor(tonumber(m) or 0) % 1440
	return ("%02d:%02d"):format(floor(m / 60), m % 60)
end

-- "Mon–Fri", "Wed, Sat, Sun", "Every day"; nil for no days. Three or more consecutive days collapse into a range.
function Model.DaysText(days, L)
	if type(days) ~= "number" or days <= 0 then return nil end
	if days >= 127 then return L["DAYS_EVERY"] end
	local on = {}
	for d = 1, 7 do on[d] = floor(days / 2 ^ (d - 1)) % 2 == 1 end
	local parts, d = {}, 1
	while d <= 7 do
		if on[d] then
			local e = d
			while e < 7 and on[e + 1] do e = e + 1 end
			if e - d >= 2 then
				parts[#parts + 1] = L["DAY_" .. d] .. "–" .. L["DAY_" .. e]
			else
				for i = d, e do parts[#parts + 1] = L["DAY_" .. i] end
			end
			d = e + 1
		else
			d = d + 1
		end
	end
	return concat(parts, ", ")
end

-- "20:00–23:30" or "All day"; nil without times.
function Model.TimeText(t0, t1, L)
	if t0 == nil or t1 == nil then return nil end
	if t0 == t1 then return L["TIME_ALL_DAY"] end
	return Model.FormatMinutes(t0) .. "–" .. Model.FormatMinutes(t1)
end

---------------------------------------------------------------------------------------------------------------------
-- The player and the checks against a listing
---------------------------------------------------------------------------------------------------------------------
-- What the cards need to know about the player: level, class (id and file name), average item level. Each is nil when the
-- client does not say.
function Model.Player()
	local P = ns.Compat and ns.Compat.Player
	local out = {}
	if not P then return out end
	out.level = P.Level and P.Level() or nil
	out.classID = P.ClassID and P.ClassID() or nil
	out.ilvl = P.AverageItemLevel and P.AverageItemLevel() or nil
	local c = out.classID and Enums().CLASS_ROLES[out.classID]
	out.class = c and c.key or nil
	return out
end

-- true when the listing wants the player's class (or any class), false when it lists classes and not this one, nil when
-- nothing is known (no `want`, or the player's class is unknown).
function Model.WantsClass(sum, player)
	if type(sum.want) ~= "table" or next(sum.want) == nil or not player or not player.classID then return nil end
	return (sum.want[0] ~= nil or sum.want[player.classID] ~= nil)
end

-- Level and item level against the listing's minimums: { levelOk, ilvlOk, ok } (nil = unknown, true when not required);
-- `ok` is false as soon as one requirement is known to fail.
function Model.Requirements(sum, player)
	local r = {}
	if sum.minL and sum.minL > 1 then
		if player and player.level then r.levelOk = player.level >= sum.minL end
	else
		r.levelOk = true
	end
	if sum.minI and sum.minI > 0 then
		if player and player.ilvl then r.ilvlOk = player.ilvl >= sum.minI end
	else
		r.ilvlOk = true
	end
	if r.levelOk == false or r.ilvlOk == false then r.ok = false
	elseif r.levelOk == nil or r.ilvlOk == nil then r.ok = nil
	else r.ok = true end
	return r
end

local function requirementText(sum, player, req, L)
	local parts = {}
	if sum.minL and sum.minL > 1 then
		if req.levelOk == false then parts[#parts + 1] = L["REQ_LEVEL_YOU"]:format(sum.minL, player.level)
		else parts[#parts + 1] = L["REQ_LEVEL"]:format(sum.minL) end
	end
	if sum.minI and sum.minI > 0 then
		if req.ilvlOk == false then parts[#parts + 1] = L["REQ_ILVL_YOU"]:format(sum.minI, floor(player.ilvl))
		else parts[#parts + 1] = L["REQ_ILVL"]:format(sum.minI) end
	end
	if #parts == 0 then return L["REQ_NONE"] end
	return concat(parts, " · ")
end

---------------------------------------------------------------------------------------------------------------------
-- One card
---------------------------------------------------------------------------------------------------------------------
local PACE_KINDS = { "casual", "soft", "hard" }

-- The display fields of a listing. sum: the summary; info: { status, annAt, ... } from Catalog:List; player: Model.Player();
-- opts: now (server time), offset (minutes from UTC, default this computer's zone), L (locale table).
-- Everything the frames show comes from here, so the layout code has no rules of its own.
function Model.Card(sum, info, player, opts)
	local L, E = opts.L, Enums()
	local _, _, name = Listing().ParseKey(sum.k)
	local card = { k = sum.k, name = name or sum.k, sub = sum.sub, inactive = info and info.status == "inactive" or false }

	-- languages: the main one first, then the others in list order
	local langs = {}
	if sum.lang1 then langs[1] = sum.lang1 end
	for i = 1, E.LANGUAGE_COUNT do
		if i ~= sum.lang1 and sum.lang and floor(sum.lang / E.LanguageBit(i)) % 2 == 1 then langs[#langs + 1] = i end
	end
	card.langs = {}
	for i, index in ipairs(langs) do
		if i > Model.MAX_LANGS then break end
		card.langs[i] = upper(E.LANGUAGES[index].key == "other" and L["LANG_SHORT_other"] or E.LANGUAGES[index].key)
	end
	card.langsMore = max(0, #langs - Model.MAX_LANGS)

	-- commitment, and the one tag about the player: requirements failed beats "looking for your class"
	if sum.pace then
		card.pace, card.paceKind = sum.pace, PACE_KINDS[sum.pace]
		card.paceText = upper(L["PACE_" .. sum.pace])
	end
	local req = Model.Requirements(sum, player)
	card.req = req
	card.reqText = requirementText(sum, player, req, L)
	card.wantsYou = Model.WantsClass(sum, player)
	if req.ok == false then card.tag = "reqfail" elseif card.wantsYou then card.tag = "wantsyou" end

	-- members: "31 active / 149"
	local st = sum.st
	if st and st.a7 then card.active, card.members = st.a7, st.m end

	-- when
	local days, t0, t1 = Model.ToLocal(sum.days, sum.t0, sum.t1, opts.offset == nil and Model.LocalOffset(opts.now) or opts.offset)
	card.daysText, card.timeText = Model.DaysText(days, L), Model.TimeText(t0, t1, L)

	-- wanted classes (never the "any class" entry; it has its own flag)
	local ids = {}
	if type(sum.want) == "table" then
		for id in pairs(sum.want) do
			if id == 0 then card.anyClass = true elseif E.CLASS_ROLES[id] then ids[#ids + 1] = id end
		end
	end
	sort(ids)
	card.classes = {}
	for i, id in ipairs(ids) do
		if i > Model.MAX_CLASSES then break end
		card.classes[i] = { id = id, file = E.CLASS_ROLES[id].key }
	end
	card.classesMore = max(0, #ids - Model.MAX_CLASSES)

	-- activities in the GM's order of importance
	local acts = {}
	for i, id in ipairs(sum.tags or {}) do
		if i > Model.MAX_ACTIVITIES then break end
		acts[#acts + 1] = L["ACTIVITY_" .. id]
	end
	card.activitiesText = concat(acts, " · ")

	-- age: of the last edit when the listing says it, else of the last announcement
	local stamp = sum.upd or (info and info.annAt)
	if stamp and opts.now then card.updatedText = L["UPDATED_AGO"]:format(Model.AgeText(opts.now - stamp, L, true)) end
	card.bg = sum.bg
	return card
end

---------------------------------------------------------------------------------------------------------------------
-- Virtual scrolling
---------------------------------------------------------------------------------------------------------------------
-- Height of the whole list: `count` cards, `step` px apart (the last gap is not counted).
function Model.ContentHeight(count, step, gap)
	if count <= 0 then return 0 end
	return count * step - (gap or 0)
end

-- The largest scroll offset (px from the top) for a view `viewH` px high.
function Model.ScrollMax(count, step, gap, viewH)
	return max(0, Model.ContentHeight(count, step, gap) - viewH)
end

function Model.ClampOffset(offset, count, step, gap, viewH)
	offset = tonumber(offset) or 0
	return max(0, min(offset, Model.ScrollMax(count, step, gap, viewH)))
end

-- The first and last index (1-based) whose card touches the view at scroll `offset`; 1, 0 (nothing) for an empty list.
function Model.Window(count, step, gap, viewH, offset)
	if count <= 0 then return 1, 0 end
	offset = Model.ClampOffset(offset, count, step, gap, viewH)
	local first = floor(offset / step) + 1
	local last = min(count, floor((offset + viewH - 1) / step) + 1)
	return min(first, count), max(last, min(first, count))
end

-- The size of the frame pool for a view: every card that can be visible at once, plus one on each side.
function Model.PoolSize(viewH, step)
	return ceil(viewH / step) + 2
end

-- A pool of `size` row slots. A listing index always goes to slot ((index - 1) % size) + 1, so a slow scroll rebinds only
-- the one frame that left the view. Pool:Assign(first, last) returns the list of { slot, index, rebind } to draw and the
-- slots to hide; a hidden slot keeps its index, so showing the same listing again binds nothing. The pool counts how many
-- times a slot was rebound (`binds`), which the tests use to prove the recycling. Reset() after the data changed.
local Pool = {}
Pool.__index = Pool

function Model.NewPool(size)
	return setmetatable({ size = size, slots = {}, binds = 0 }, Pool)
end

function Pool:SlotFor(index) return (index - 1) % self.size + 1 end

-- first..last must not span more than `size` indexes.
function Pool:Assign(first, last)
	local show, used = {}, {}
	if last >= first and last - first + 1 <= self.size then
		for index = first, last do
			local slot = self:SlotFor(index)
			used[slot] = true
			show[#show + 1] = { slot = slot, index = index, rebind = self.slots[slot] ~= index }
			if self.slots[slot] ~= index then
				self.slots[slot] = index
				self.binds = self.binds + 1
			end
		end
	end
	local hide = {}
	for slot = 1, self.size do
		if not used[slot] then hide[#hide + 1] = slot end   -- a hidden frame keeps its binding until Reset
	end
	return show, hide
end

function Pool:Reset() self.slots = {} end   -- the data changed: every visible row must be bound again

---------------------------------------------------------------------------------------------------------------------
-- Throttle
---------------------------------------------------------------------------------------------------------------------
local Coalescer = {}
Coalescer.__index = Coalescer

-- Many Request() calls become one fn() call `delay` seconds after the first one. `after(seconds, callback)` is the
-- clock (Compat.After); a clock that cannot schedule makes fn run at once.
function Model.NewCoalescer(after, delay, fn)
	return setmetatable({ after = after, delay = delay, fn = fn, waiting = false, calls = 0, runs = 0, gen = 0 }, Coalescer)
end

function Coalescer:Request()
	self.calls = self.calls + 1
	if self.waiting then return false end
	self.waiting = true
	local gen = self.gen
	local ok = self.after(self.delay, function()
		if gen ~= self.gen or not self.waiting then return end
		self.waiting = false
		self.runs = self.runs + 1
		self.fn()
	end)
	if not ok then
		self.waiting = false
		self.runs = self.runs + 1
		self.fn()
	end
	return true
end

function Coalescer:Pending() return self.waiting end

-- Forgets a waiting request (the page was hidden: it is rebuilt when shown).
function Coalescer:Cancel()
	self.waiting = false
	self.gen = self.gen + 1
end

---------------------------------------------------------------------------------------------------------------------
-- Debounce (the search box)
---------------------------------------------------------------------------------------------------------------------
local Debouncer = {}
Debouncer.__index = Debouncer

-- fn(...) runs `delay` seconds after the LAST Call, with the arguments of the last Call; Flush() runs it now.
function Model.NewDebouncer(after, delay, fn)
	return setmetatable({ after = after, delay = delay, fn = fn, token = 0, args = nil, runs = 0 }, Debouncer)
end

function Debouncer:Call(...)
	self.token = self.token + 1
	local token = self.token
	self.args = { n = select("#", ...), ... }
	local ok = self.after(self.delay, function()
		if token ~= self.token or not self.args then return end
		self:Flush()
	end)
	if not ok then self:Flush() end
end

function Debouncer:Pending() return self.args ~= nil end

function Debouncer:Flush()
	local args = self.args
	self.token = self.token + 1   -- a timer that is still on its way finds a newer token and does nothing
	self.args = nil
	if args then
		self.runs = self.runs + 1
		self.fn(unpack(args, 1, args.n))
	end
end

function Debouncer:Cancel()
	self.token = self.token + 1
	self.args = nil
end

if ns.addon then ns.addon.BrowseModel = Model end
