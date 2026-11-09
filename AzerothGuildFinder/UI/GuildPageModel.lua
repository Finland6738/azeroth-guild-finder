-- GuildPageModel: the logic of the guild page (SPEC-05 §3) as plain Lua, no frames. UI/GuildPage.lua draws what this
-- module says; the tests run it without a client. Lua 5.1.
--
-- The page is built from two parts of a listing that arrive at different times: the SUMMARY (always there, it is what the
-- list showed) and the DETAIL (description, Discord code, contacts, note; it has to be asked from other players). The view
-- never needs the detail to exist: everything that comes from the summary is complete at once, and the three things that
-- need the detail say "loading" or "unavailable" until it arrives.
--
--   Model.View(ctx)                 -> the whole page as data (see below)
--   Model.DetailState(entry, unavailable) -> "ready" | "loading" | "unavailable"
--   Model.DiscordUrl(code)          -> "https://discord.gg/<code>", or nil for a code that is not valid
--   Model.Contacts(det, heard)      -> { { name, online } }: the contact characters, online when a recent ANN came from them
--   Model.Looking(sum, player, L)   -> the "Looking for" card: status, classes with their roles, "they need your class"
--   Model.Activity(sum, offset, L)  -> commitment, activities, days and times in the visitor's time zone (and UTC)
--   Model.Members(sum, now, L)      -> the aggregate numbers, the unique-players range and the class mix
--   Model.Requirements(sum, det, player, L) -> each requirement checked against the visitor
--   Model.DateText / Model.Footer   -> "12 Oct 2026", "Listed since 12 Oct 2026 · Updated 2 days ago"
--   Model.Stack / Model.Flow / Model.Columns / Model.ScrollMax   -> the arithmetic of the layout
--
-- Times and requirements are NOT redone here: BrowseModel.ToLocal / LocalOffset / DaysText / TimeText / Requirements /
-- AgeText are the one implementation (the list, the filters and this page must agree).
--
-- ctx of Model.View: k, entry (Catalog:Get), status (its status), player (BrowseModel.Player()), now (server time),
-- offset (minutes of the visitor's zone from UTC; default: this computer's zone), heard (names from Sync:Contacts),
-- unavailable (the detail request ended without an answer), L (the locale table).
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.GuildPageModel, ns.modules = Model, ns.modules or {}
ns.modules.GuildPageModel = Model

local type, pairs, ipairs, tonumber, pcall = type, pairs, ipairs, tonumber, pcall
local floor, min, max = math.floor, math.min, math.max
local sort, concat = table.sort, table.concat
local lower = string.lower

Model.DISCORD_PREFIX = "https://discord.gg/"
Model.ONLINE_WINDOW = 3600     -- a contact that announced itself this recently (seconds) counts as online
Model.MAX_TAGS = 6

local function Browse() return ns.BrowseModel end
local function Enums() return ns.Enums end
local function Listing() return ns.Listing end

---------------------------------------------------------------------------------------------------------------------
-- Detail state, Discord, contacts
---------------------------------------------------------------------------------------------------------------------
-- "ready": a detail is there (an older one than the summary is shown while the newer one is asked for), "unavailable":
-- there is none and the request ended without an answer, "loading": there is none and the request is running.
function Model.DetailState(entry, unavailable)
	if entry and entry.det then return "ready" end
	return unavailable and "unavailable" or "loading"
end

-- The full invite link: the prefix is fixed, only the code travels (SPEC-03 §3, D13). nil when the code is not valid.
function Model.DiscordUrl(code)
	if type(code) ~= "string" or not Listing().IsValidDiscordCode(code) then return nil end
	return Model.DISCORD_PREFIX .. code
end

-- "Name-Realm" -> "name" (case folded): contact names are listed with or without the realm.
local function baseName(name)
	if type(name) ~= "string" then return nil end
	local base = name:match("^([^%-]+)") or name
	return lower(base)
end

-- The contact characters of the detail, in the GM's order. `heard`: names of contacts heard announcing the guild recently.
function Model.Contacts(det, heard)
	local out = {}
	if not det or type(det.cont) ~= "table" then return out end
	local online = {}
	for _, name in ipairs(heard or {}) do
		local b = baseName(name)
		if b then online[b] = true end
	end
	for _, name in ipairs(det.cont) do
		out[#out + 1] = { name = name, online = online[baseName(name)] == true }
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Looking for
---------------------------------------------------------------------------------------------------------------------
local ROLE_KEYS = { [1] = "tank", [2] = "healer", [4] = "melee", [8] = "ranged" }

-- The roles of a mask as { key, label, bit } in role order.
local function rolesOf(mask, L)
	local out = {}
	for _, bit in ipairs(Enums().RoleList(mask or 0)) do
		out[#out + 1] = { key = ROLE_KEYS[bit], bit = bit, label = L["ROLE_" .. ROLE_KEYS[bit]] }
	end
	return out
end

local function roleLabels(roles)
	local labels = {}
	for i, r in ipairs(roles) do labels[i] = r.label end
	return concat(labels, ", ")
end

local STATUS = {
	[1] = { key = "open", text = "LF_RECRUITING", kind = "ok" },
	[2] = { key = "some", text = "LF_RECRUITING_SOME", kind = "gold" },
	[0] = { key = "closed", text = "LF_CLOSED", kind = "bad" },
}

-- The roles of the visitor's class that the guild looks for (a mask 0..15): what is named for the class itself plus what is
-- named for any class, reduced to the roles the class can play. 0 when the class is not wanted, or nothing is known.
function Model.WantedRoles(sum, player)
	if type(sum.want) ~= "table" or not player or not player.classID then return 0 end
	local E = Enums()
	local mask = 0
	for _, id in ipairs({ player.classID, 0 }) do
		local m = sum.want[id]
		if type(m) == "number" then
			-- add the bits that are not there yet (no bit operators in Lua 5.1)
			mask = mask + (m - E.MaskAnd(mask, m))
		end
	end
	return E.MaskAnd(mask, E.ValidRoles(player.classID))
end

-- { status = { key, text, kind } | nil, classes = { { id, file, name, roles } }, any = { roles } | nil, none = bool,
--   legend = { roles }, wantsYou = { className, roles, text } | nil }
function Model.Looking(sum, player, L)
	local E = Enums()
	local out = { classes = {}, legend = rolesOf(15, L) }
	local s = STATUS[sum.rec]
	if s then out.status = { key = s.key, text = L[s.text], kind = s.kind } end

	local ids = {}
	if type(sum.want) == "table" then
		for id, mask in pairs(sum.want) do
			if id == 0 then
				out.any = { roles = rolesOf(mask, L) }
			elseif E.CLASS_ROLES[id] then
				ids[#ids + 1] = id
			end
		end
	end
	sort(ids)
	for _, id in ipairs(ids) do
		local file = E.CLASS_ROLES[id].key
		out.classes[#out.classes + 1] = { id = id, file = file, name = L["CLASS_" .. file], roles = rolesOf(sum.want[id], L) }
	end
	out.none = #out.classes == 0 and out.any == nil

	local wanted = Model.WantedRoles(sum, player)
	if wanted > 0 then
		local file = E.CLASS_ROLES[player.classID] and E.CLASS_ROLES[player.classID].key
		local roles = rolesOf(wanted, L)
		local className = file and L["CLASS_" .. file] or nil
		if className then
			out.wantsYou = { className = className, roles = roles,
				text = L["LF_NEED_YOU"]:format(className, roleLabels(roles)) }
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Activity
---------------------------------------------------------------------------------------------------------------------
local PACE_KINDS = { "casual", "soft", "hard" }

-- offset: minutes of the visitor's zone from UTC. Days and times are published in UTC and shown in the visitor's zone
-- (the days move with the start time, as in the list); the UTC times are given too, smaller.
function Model.Activity(sum, offset, L)
	local out = { acts = {} }
	if sum.pace then
		out.pace = { value = sum.pace, text = L["PACE_" .. sum.pace], tip = L["PACE_" .. sum.pace .. "_TIP"], kind = PACE_KINDS[sum.pace] }
	end
	for i, id in ipairs(sum.tags or {}) do
		out.acts[#out.acts + 1] = { n = i, id = id, text = L["ACTIVITY_" .. id] }
	end
	local B = Browse()
	local days, t0, t1 = B.ToLocal(sum.days, sum.t0, sum.t1, offset)
	out.daysMask = type(days) == "number" and days or 0
	out.daysText = B.DaysText(days, L)
	out.allDay = sum.t0 ~= nil and sum.t0 == sum.t1
	out.timeText = B.TimeText(t0, t1, L)
	out.utcText = (sum.t0 ~= nil and sum.t1 ~= nil and not out.allDay) and L["TIME_UTC"]:format(B.TimeText(sum.t0, sum.t1, L)) or nil
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Members
---------------------------------------------------------------------------------------------------------------------
-- The statistics are aggregates only (D12). `unique` is the text of the range: "14" when it is exact, "12–18" otherwise.
-- `mix` is the class distribution of the active characters, { { id, file, count, fraction } } by class id.
function Model.Members(sum, now, L)
	local st = sum.st
	if type(st) ~= "table" or st.a7 == nil then return { known = false } end
	local out = { known = true, active = st.a7, total = st.m, maxLevel = st.max, mix = {} }
	if st.u7lo and st.u7hi then
		out.uniqueLo, out.uniqueHi = st.u7lo, st.u7hi
		out.unique = st.u7lo == st.u7hi and tostring(st.u7lo) or (st.u7lo .. "–" .. st.u7hi)
	end
	if sum.srev and now then out.updatedText = L["MEMBERS_UPDATED"]:format(Browse().AgeText(max(0, now - sum.srev), L)) end
	if type(st.cls) == "table" then
		local ids, sumCount = {}, 0
		for id, n in pairs(st.cls) do
			if Enums().CLASS_ROLES[id] and type(n) == "number" and n > 0 then ids[#ids + 1] = id; sumCount = sumCount + n end
		end
		sort(ids)
		for _, id in ipairs(ids) do
			out.mix[#out.mix + 1] = { id = id, file = Enums().CLASS_ROLES[id].key, count = st.cls[id], fraction = st.cls[id] / sumCount }
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Requirements
---------------------------------------------------------------------------------------------------------------------
-- Each requirement against the visitor. An item: { id, ok, text, you, muted }. ok = true (met), false (not met), nil (the
-- client does not say). `none`: the guild states no requirement at all (the note aside). The note is the GM's own words.
function Model.Requirements(sum, det, player, L)
	local req = Browse().Requirements(sum, player)
	local items = {}
	if sum.minL and sum.minL > 1 then
		items[#items + 1] = { id = "level", ok = req.levelOk, text = L["REQ_LEVEL"]:format(sum.minL),
			you = player and player.level and L["REQ_YOU"]:format(player.level) or nil }
	else
		items[#items + 1] = { id = "level", muted = true, text = L["REQ_NO_LEVEL"] }
	end
	if sum.minI and sum.minI > 0 then
		items[#items + 1] = { id = "ilvl", ok = req.ilvlOk, text = L["REQ_ILVL"]:format(sum.minI),
			you = player and player.ilvl and L["REQ_YOU_ILVL"]:format(floor(player.ilvl)) or nil }
	else
		items[#items + 1] = { id = "ilvl", muted = true, text = L["REQ_NO_ILVL"] }
	end
	local out = { items = items, ok = req.ok, note = det and det.note or nil }
	out.none = items[1].muted and items[2].muted or false
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Dates
---------------------------------------------------------------------------------------------------------------------
-- "12 Oct 2026" in this computer's zone; nil for something that is not a time.
function Model.DateText(stamp, L)
	if type(stamp) ~= "number" or stamp <= 0 or type(date) ~= "function" then return nil end
	local ok, t = pcall(date, "*t", stamp)
	if not ok or type(t) ~= "table" or not t.month then return nil end
	return L["DATE_FORMAT"]:format(t.day, L["MONTH_" .. t.month], t.year)
end

-- "Listed since 12 Oct 2026 · Updated 2 days ago" (each half only when its date is known).
function Model.Footer(sum, now, L)
	local parts = {}
	local since = Model.DateText(sum.first, L)
	if since then parts[#parts + 1] = L["FOOTER_SINCE"]:format(since) end
	if sum.upd and now then
		parts[#parts + 1] = L["UPDATED_AGO"]:format(Browse().AgeText(max(0, now - sum.upd), L))
	end
	return concat(parts, " · ")
end

---------------------------------------------------------------------------------------------------------------------
-- Tags of the left page
---------------------------------------------------------------------------------------------------------------------
-- { { text, kind } }: the languages (full names, upper case), the faction, the commitment, "May be inactive". The first
-- language is the main one.
function Model.Tags(sum, faction, inactive, L)
	local E = Enums()
	local tags = {}
	local langs = {}
	if sum.lang1 then langs[1] = sum.lang1 end
	for i = 1, E.LANGUAGE_COUNT do
		if i ~= sum.lang1 and type(sum.lang) == "number" and floor(sum.lang / E.LanguageBit(i)) % 2 == 1 then langs[#langs + 1] = i end
	end
	for _, index in ipairs(langs) do
		local lang = E.LANGUAGES[index]
		if lang then tags[#tags + 1] = { text = L["LANG_" .. lang.key]:upper(), kind = "default" } end
	end
	if faction == "Horde" or faction == "Alliance" then
		tags[#tags + 1] = { text = L["FACTION_" .. faction]:upper(), kind = faction == "Horde" and "bad" or "default", faction = faction }
	end
	if sum.pace then tags[#tags + 1] = { text = L["PACE_" .. sum.pace]:upper(), kind = PACE_KINDS[sum.pace], pace = sum.pace } end
	if inactive then tags[#tags + 1] = { text = L["TAG_INACTIVE"], kind = "gold" } end
	return tags
end

---------------------------------------------------------------------------------------------------------------------
-- The whole page
---------------------------------------------------------------------------------------------------------------------
-- A listing that is gone (hidden, withdrawn or removed while the page is open) has no content: { gone = true, name }.
function Model.View(ctx)
	local L, entry = ctx.L, ctx.entry
	local _, faction, name = Listing().ParseKey(ctx.k)
	local view = { k = ctx.k, name = name or ctx.k }
	if not entry or not entry.sum or not (ctx.status == "listed" or ctx.status == "inactive") then
		view.gone = true
		return view
	end
	local sum, det = entry.sum, entry.det
	view.emb = sum.emb
	local B = Browse()
	local offset = ctx.offset
	if offset == nil then offset = B.LocalOffset(ctx.now) end

	view.sum, view.det = sum, det
	view.sub = sum.sub
	view.detail = Model.DetailState(entry, ctx.unavailable)
	view.tags = Model.Tags(sum, faction, ctx.status == "inactive", L)
	view.bg = sum.bg
	view.appsClosed = sum.apps == false
	view.looking = Model.Looking(sum, ctx.player, L)
	view.activity = Model.Activity(sum, offset, L)
	view.members = Model.Members(sum, ctx.now, L)
	view.requirements = Model.Requirements(sum, det, ctx.player, L)
	view.footer = Model.Footer(sum, ctx.now, L)
	view.desc = det and det.desc or nil
	view.discord = det and Model.DiscordUrl(det.disc) or nil
	view.contacts = Model.Contacts(det, ctx.heard)
	view.offset = offset
	return view
end

---------------------------------------------------------------------------------------------------------------------
-- Layout arithmetic (the frames only place what these say)
---------------------------------------------------------------------------------------------------------------------
-- Items one under the other. heights = { h1, h2, ... } (an entry may be 0: it takes no room and no gap). Returns the y of
-- the top of each item (0 at the top, growing downward) and the total height.
function Model.Stack(heights, gap)
	local ys, y, first = {}, 0, true
	for i, h in ipairs(heights) do
		if h > 0 then
			if not first then y = y + gap end
			ys[i] = y
			y = y + h
			first = false
		else
			ys[i] = y
		end
	end
	return ys, y
end

-- Boxes in rows that wrap: widths = { w1, ... }; the row is full when the next box does not fit in `maxW`. Returns
-- { { x, y, row } } per box and the total height. align "center" centres each row in maxW.
function Model.Flow(widths, maxW, gapX, rowH, gapY, align)
	local rows, row, x = {}, {}, 0
	for i, w in ipairs(widths) do
		if #row > 0 and x + w > maxW then
			rows[#rows + 1] = row
			row, x = {}, 0
		end
		row[#row + 1] = { i = i, x = x, w = w }
		x = x + w + gapX
	end
	if #row > 0 then rows[#rows + 1] = row end
	local out = {}
	for r, items in ipairs(rows) do
		local last = items[#items]
		local used = last.x + last.w
		local shift = align == "center" and max(0, floor((maxW - used) / 2)) or 0
		for _, item in ipairs(items) do
			out[item.i] = { x = item.x + shift, y = (r - 1) * (rowH + gapY), row = r }
		end
	end
	local height = #rows > 0 and (#rows * rowH + (#rows - 1) * gapY) or 0
	return out, height
end

-- The two columns of the lower part: each a list of card heights; returns the y of each card in its column and the height
-- of the taller column.
function Model.Columns(left, right, gap)
	local ly, lh = Model.Stack(left, gap)
	local ry, rh = Model.Stack(right, gap)
	return ly, ry, max(lh, rh)
end

function Model.ScrollMax(contentH, viewH) return max(0, (contentH or 0) - (viewH or 0)) end
function Model.ClampScroll(offset, contentH, viewH)
	return max(0, min(tonumber(offset) or 0, Model.ScrollMax(contentH, viewH)))
end

if ns.addon then ns.addon.GuildPageModel = Model end
