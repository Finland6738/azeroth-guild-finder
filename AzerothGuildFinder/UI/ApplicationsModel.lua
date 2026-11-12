-- ApplicationsModel: what the Applications panel of the Guild Master and the officers shows (SPEC-07 §5, mockup 04), as plain
-- Lua with no frames. UI/Applications.lua copies what this module says; the tests run it without a client.
--
--   Model.CanSee(role)                    only the Guild Master and the officers see the panel (SPEC-00 §5, APP-07)
--   Model.Split(recs, now)                -> pending (newest first), history (last change first): the stored records
--   Model.Counters(recs, now)             -> { pending, accepted, declined, withdrawn, expired, history }
--   Model.Row(rec, ctx, L)                -> one application as a row (pending card or history line), see below
--   Model.View(ctx, L)                    -> the whole panel: tabs with their counts, the counters, the rows, the empty state
--        ctx = { role, key, recs, now, tab ("pending" | "history"), seenAt (time the panel was last left), busy = { [id] = true }
--        (an invite being watched), manual = { [id] = true } (the /ginvite fallback was offered), listed (the guild has a listing) }
--   Model.Page(total, offset, size)       -> { offset, first, last, max }: the window of rows in view, clamped
--   Model.ExpiresText / Model.DateLong    the small texts
--   Model.Options / GetOption / SetOption the notification options (account settings, read by M4.5's icon)
-- A row: { id, kind ("pending" | "history"), name, who (to whisper), cls (class file "MAGE"), classLabel, level, race,
-- classLine ("Mage · Level 32 · Troll"), ilvlText, ageText, status = { text, kind }, new, roles = { { key, label } },
-- inviting, actions = { invite = { enabled, label, tip }, decline = { enabled }, whisper = { enabled } } (pending),
-- byText ("by Lyryn · 5 Nov 2026") (history) }.
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.AppsModel, ns.modules = Model, ns.modules or {}
ns.modules.AppsModel = Model

local type, ipairs, pcall, tostring, tonumber = type, ipairs, pcall, tostring, tonumber
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local sort = table.sort

Model.TABS = { "pending", "history" }
Model.RECENT = 2 * 86400     -- an application younger than this is "RECEIVED"; an older one shows how long it still has
Model.URGENT_DAYS = 3        -- this many days or fewer left: the expiry tag turns amber

local function A() return ns.Applications end

function Model.CanSee(role) return role == "gm" or role == "officer" end

---------------------------------------------------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------------------------------------------------
-- The state of a record as shown: an open record past its 14 days is expired even before the sweep has written it.
local function shownState(rec, now)
	if A().IsExpired(rec, now) then return "expired" end
	return rec.state
end

local function pendingOf(rec, now) return A().IsOpen(rec) and not A().IsExpired(rec, now) end

-- pending: the open records, newest application first; history: the closed ones (and open ones past their 14 days), the
-- last change first.
function Model.Split(recs, now)
	local pending, history = {}, {}
	for _, rec in ipairs(recs or {}) do
		if type(rec) == "table" then
			if pendingOf(rec, now) then pending[#pending + 1] = rec else history[#history + 1] = rec end
		end
	end
	sort(pending, function(a, b)
		if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
		return tostring(a.id) < tostring(b.id)
	end)
	sort(history, function(a, b)
		local ta, tb = a.upd or a.at or 0, b.upd or b.at or 0
		if ta ~= tb then return ta > tb end
		return tostring(a.id) < tostring(b.id)
	end)
	return pending, history
end

function Model.Counters(recs, now)
	local c = { pending = 0, accepted = 0, declined = 0, withdrawn = 0, expired = 0, history = 0 }
	for _, rec in ipairs(recs or {}) do
		if type(rec) == "table" then
			local st = shownState(rec, now)
			if pendingOf(rec, now) then
				c.pending = c.pending + 1
			else
				c.history = c.history + 1
				if c[st] then c[st] = c[st] + 1 end
			end
		end
	end
	return c
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
-- "5 Nov 2026" in this computer's zone; nil for something that is not a time.
function Model.DateLong(stamp, L)
	if type(stamp) ~= "number" or stamp <= 0 or type(date) ~= "function" then return nil end
	local ok, t = pcall(date, "*t", stamp)
	if not ok or type(t) ~= "table" or not t.month then return nil end
	return L["DATE_FORMAT"]:format(t.day, L["MONTH_" .. t.month], t.year)
end

-- "EXPIRES IN 11 DAYS" and its kind ("default", or "gold" when little is left); nil when the record is not open.
function Model.ExpiresText(rec, now, L)
	local days = max(0, ceil((A().ExpiresAt(rec) - now) / 86400))
	local text = days <= 1 and L["APPS_TAG_EXPIRES_1"] or L["APPS_TAG_EXPIRES"]:format(days)
	return text, days <= Model.URGENT_DAYS and "gold" or "default"
end

local function nameOf(who)
	if type(who) ~= "string" or who == "" then return "?" end
	return who:match("^[^%-]+") or who
end

local function raceText(rec, L)
	local id = rec.race
	if type(id) ~= "number" then return nil end
	local name = ns.Compat and ns.Compat.RaceName and ns.Compat.RaceName(id)
	if name then return name end
	if id >= 1 and id <= 8 and id == floor(id) then return L["RACE_" .. id] end   -- the eight races of the original game
	return L["APPS_RACE_UNKNOWN"]:format(id)
end

local STATUS_KIND = { received = "ok", accepted = "ok", declined = "bad", withdrawn = "default", expired = "default", sent = "gold" }

---------------------------------------------------------------------------------------------------------------------
-- A row
---------------------------------------------------------------------------------------------------------------------
function Model.Row(rec, ctx, L)
	local now = ctx.now or 0
	local st = shownState(rec, now)
	local open = pendingOf(rec, now)
	local row = { id = rec.id, kind = open and "pending" or "history", name = nameOf(rec.who), who = rec.who, state = st }
	local class = rec.cls and ns.Enums.CLASS_ROLES[rec.cls]
	row.cls = class and class.key or nil
	row.classLabel = class and L["CLASS_" .. class.key] or nil
	row.level = rec.lvl
	row.race = raceText(rec, L)
	if row.classLabel and row.level then
		row.classLine = L["APPS_CLASS_LINE"]:format(row.classLabel, row.level, row.race or "?")
		row.historyLine = L["APPS_HISTORY_LINE"]:format(row.name, row.classLabel, row.level)
	else
		row.classLine = L["APPS_UNKNOWN_DETAILS"]
		row.historyLine = row.name
	end
	row.ilvlText = rec.ilvl and L["APPS_ILVL"]:format(rec.ilvl) or L["APPS_ILVL_NONE"]
	row.ageText = ns.BrowseModel.AgeText(max(0, now - (rec.at or now)), L)
	row.roles = {}
	for _, bit in ipairs(ns.Enums.RoleList(rec.roles or 0)) do
		local key = ns.ApplyModel.ROLE_KEYS[bit]
		row.roles[#row.roles + 1] = { key = key, label = L["ROLE_" .. key] }
	end
	row.inviting = ctx.busy and ctx.busy[rec.id] == true or false
	row.manual = ctx.manual and ctx.manual[rec.id] == true or false

	if open then
		local age = now - (rec.at or now)
		if row.inviting then
			row.status = { text = L["APPS_TAG_INVITING"], kind = "gold" }
		elseif age >= Model.RECENT then
			local text, kind = Model.ExpiresText(rec, now, L)
			row.status = { text = text, kind = kind }
		else
			row.status = { text = L["APPS_TAG_RECEIVED"], kind = "ok" }
		end
		row.new = ctx.seenAt ~= nil and max(rec.upd or 0, rec.at or 0) > ctx.seenAt
		local canAct = ctx.canAct ~= false and not row.inviting
		row.actions = {
			invite = { enabled = canAct, label = row.manual and L["APPS_MARK_INVITED"] or L["APPS_INVITE"],
				tip = row.manual and L["APPS_MARK_INVITED_TIP"] or L["APPS_INVITE_TIP"] },
			decline = { enabled = canAct },
			whisper = { enabled = type(rec.who) == "string" and rec.who ~= "" },
		}
	else
		row.status = { text = L["APPS_TAG_" .. st], kind = STATUS_KIND[st] or "default" }
		local when = Model.DateLong(rec.upd or rec.at, L)
		if st == "withdrawn" then
			row.byText = when and L["APPS_BY_PLAYER"]:format(when) or L["APPS_BY_PLAYER_NODATE"]
		elseif st == "expired" then
			row.byText = when and L["APPS_EXPIRED_ON"]:format(when) or L["APPS_TAG_expired"]
		elseif rec.by and when then
			row.byText = L["APPS_BY"]:format(nameOf(rec.by), when)
		else
			row.byText = when or ""
		end
		row.actions = { whisper = { enabled = type(rec.who) == "string" and rec.who ~= "" } }
	end
	return row
end

---------------------------------------------------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------------------------------------------------
-- The empty state of a tab.
local function emptyState(tab, L)
	if tab == "history" then return { title = L["APPS_EMPTY_HISTORY"], body = L["APPS_EMPTY_HISTORY_BODY"] } end
	return { title = L["APPS_EMPTY_PENDING"], body = L["APPS_EMPTY_PENDING_BODY"] }
end

function Model.View(ctx, L)
	local role = ctx.role or "none"
	local view = { tab = ctx.tab == "history" and "history" or "pending" }
	view.visible = Model.CanSee(role) and type(ctx.key) == "string"
	view.counters = Model.Counters(view.visible and ctx.recs or {}, ctx.now)
	view.pendingCount = view.counters.pending
	view.pendingLabel = L["APPS_TAB_PENDING"]:format(view.pendingCount)
	view.historyLabel = L["APPS_TAB_HISTORY"]
	view.title = view.tab == "history" and L["APPS_TITLE_HISTORY"] or L["APPS_TITLE_PENDING"]
	view.caption = L["APPS_EXPIRY_NOTE"]
	view.rows = {}
	if not view.visible then
		view.total = 0
		view.empty = { title = L["APPS_NOT_OFFICER"], body = L["APPS_NOT_OFFICER_BODY"] }
		return view
	end
	local pending, history = Model.Split(ctx.recs, ctx.now)
	local list = view.tab == "history" and history or pending
	local rctx = { now = ctx.now, seenAt = ctx.seenAt, busy = ctx.busy, manual = ctx.manual, canAct = Model.CanSee(role) }
	for _, rec in ipairs(list) do view.rows[#view.rows + 1] = Model.Row(rec, rctx, L) end
	view.total = #view.rows
	if view.total == 0 then view.empty = emptyState(view.tab, L) end
	view.newCount = 0
	for _, row in ipairs(view.rows) do if row.new then view.newCount = view.newCount + 1 end end
	return view
end

-- The window of `size` rows over `total`, starting at row `offset` (0-based, clamped). first/last are 1-based and 0 when
-- there is nothing.
function Model.Page(total, offset, size)
	total, size = max(0, floor(tonumber(total) or 0)), max(1, floor(tonumber(size) or 1))
	local top = max(0, total - size)
	offset = min(top, max(0, floor(tonumber(offset) or 0)))
	if total == 0 then return { offset = 0, first = 0, last = 0, max = 0 } end
	return { offset = offset, first = offset + 1, last = min(total, offset + size), max = top }
end

---------------------------------------------------------------------------------------------------------------------
-- Notification options (the floating icon of M4.5 reads them; SPEC-07 §6)
---------------------------------------------------------------------------------------------------------------------
Model.OPTIONS = {
	{ key = "notifyIcon", label = "APPS_OPT_ICON", help = "APPS_OPT_ICON_HELP" },
	{ key = "onlyWhenPending", label = "APPS_OPT_PENDING", help = "APPS_OPT_PENDING_HELP" },
	{ key = "sound", label = "APPS_OPT_SOUND", help = "APPS_OPT_SOUND_HELP" },
}

local OPTION_KEYS = {}
for _, o in ipairs(Model.OPTIONS) do OPTION_KEYS[o.key] = true end

function Model.GetOption(key)
	if not OPTION_KEYS[key] then return nil end
	local v = ns.Config and ns.Config:Get("account.settings." .. key)
	if v == nil then
		local d = ns.Config and ns.Config.defaults and ns.Config.defaults.account.settings
		v = d and d[key]
	end
	return v == true
end

-- Saves an option (a boolean) and tells the Bus. Returns true when it was saved.
function Model.SetOption(key, value)
	if not OPTION_KEYS[key] or type(value) ~= "boolean" or not ns.Config then return false end
	local ok = ns.Config:Set("account.settings." .. key, value)
	if ok == false then return false end
	if ns.Bus then ns.Bus:Emit("NOTIFY_OPTIONS_CHANGED", key, value) end
	return true
end

if ns.addon then ns.addon.AppsModel = Model end
