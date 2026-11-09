-- EditorModel: the rules of the listing editor as plain Lua, no frames (SPEC-06 §2, M3.2). UI/Editor.lua draws what this
-- module says; the tests run it without a client. Lua 5.1.
--
--   Model.STEPS / Model.COUNT              the seven steps (identity, about, activity, recruitment, requirements, contact, publish)
--   Model.NewStepper(count, start)         the stepper: Go(i), Next(), Back(), CanNext(), CanBack(), index
--   Model.Strip(fields)                    a deep copy holding only the fields the editor owns (no k, rev, upd, first, own, ...)
--   Model.Clean(fields, key)               the record those fields become when published (Listing.SanitizeFull)
--   Model.Same(a, b)                       true when two sets of fields publish the same listing
--   Model.View(fields, ctx)                the checklist: { items, steps, ready, complete, first, clean }
--   Model.Action(view, ctx)                the main button: { mode, label, enabled, reason, kind, step }
--   Model.Preview(fields, key, now, L)     the display fields of the listing card (BrowseModel.Card), for the live preview
--   Model.Clamp / TextStats                typed text cut to SPEC-03's limits (subtitle 60, description 500 and 12 lines), the counters
--   Model.MainLanguage / Secondary / SetMain / SetSecondary   the language fields (`lang1`, the mask `lang`)
--   Model.Banners()                        the verified banners, for the gallery
--   Model.Tags / ToggleTag / TagNumber     the activities in the order picked (max 3), toggling one, its number
--   Model.Schedule / SchedulePatch         days and time window: stored as UTC, edited in the Guild Master's local time
--   Model.Status / StatusPatch / Grid* / Cell / ToggleRole / WantPatch   recruitment: the status and the class x role grid -> `want` (M3.5)
--   Model.ClampLevel / LevelPatch / ParseItemLevel / ItemLevelPatch / Requirements   requirements: minimum level, optional item level (M3.5)
--   Model.DiscordCheck / Roster / Suggest / AddContact / RemoveContact / ContactStates   contact: the Discord code, up to 3 roster characters (M3.5)
--   Model.ReadyText / DraftText / FixText  texts
--
-- The checklist (SPEC-06 §2, "Before publishing"), in this order, each item with the step that fixes it:
--   leader     you are the Guild Master                             (no step: Core/Role and IsGuildLeader say)
--   sub        subtitle                                            1 Identity
--   desc       description of at least 30 characters               2 About
--   lang       main language                                       2 About
--   pace       commitment                                          3 Activity
--   tags       1 to 3 activities                                   3 Activity
--   emblem     tabard or designed emblem                           1 Identity
--   looking    "Looking for" set, or recruitment closed            4 Recruitment
--   discord    a valid code, only when something is typed in       6 Contact
-- An item is "ok", "todo" (required, nothing there yet), "bad" (there but not valid) or "optional" (nothing to check).
-- Publish is possible when no item is "todo" or "bad", the character may edit (Guild Master, IsGuildLeader() read again)
-- and the 5-minute limit has passed; "Save changes" (a listed listing) also needs a change.
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.EditorModel, ns.modules = Model, ns.modules or {}
ns.modules.EditorModel = Model

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor = math.floor

Model.STEPS = {
	{ id = "identity" }, { id = "about" }, { id = "activity" }, { id = "recruitment" }, { id = "requirements" },
	{ id = "contact" }, { id = "publish" },
}
Model.COUNT = #Model.STEPS
Model.PUBLISH = Model.COUNT              -- the last step is the shell's own: preview, checklist, Publish
Model.DESC_MIN = 30                      -- SPEC-06 §2: description of at least 30 characters
Model.MAX_TAGS = 3
Model.PLACEHOLDER_KEY = "Realm|Horde|Guild"   -- a valid key for sanitizing when the guild is not known

-- The fields the editor owns (SPEC-03 §2-§3). Everything else of a stored record (k, rev, upd, first, own, del, st, srev)
-- belongs to OwnListing.
Model.CONTENT = { "sub", "lang", "lang1", "tags", "pace", "days", "t0", "t1", "rec", "apps", "want", "newb", "minL", "minI",
	"emb", "bg", "desc", "disc", "cont", "note" }

for i, step in ipairs(Model.STEPS) do step.index = i end

local function Listing() return ns.Listing end
local function Normalize() return ns.Normalize end

-- Index of a step id, or nil.
function Model.StepIndex(id)
	for i, step in ipairs(Model.STEPS) do if step.id == id then return i end end
	return nil
end

function Model.StepId(index) local s = Model.STEPS[index]; return s and s.id end

function Model.StepLabel(index, L)
	local id = Model.StepId(index)
	return id and L["ED_STEP_" .. id] or ""
end

---------------------------------------------------------------------------------------------------------------------
-- Stepper
---------------------------------------------------------------------------------------------------------------------
local Stepper = {}
Stepper.__index = Stepper

local function clampIndex(i, count)
	i = tonumber(i)
	if not i or i ~= i then return 1 end
	i = floor(i)
	if i < 1 then return 1 end
	if i > count then return count end
	return i
end

-- A stepper over `count` steps (default Model.COUNT) starting at `start` (default 1).
function Model.NewStepper(count, start)
	count = count or Model.COUNT
	return setmetatable({ count = count, index = clampIndex(start or 1, count) }, Stepper)
end

function Stepper:CanBack() return self.index > 1 end
function Stepper:CanNext() return self.index < self.count end

-- Moves to step i (a number 1..count). Returns true when the step changed; anything else is ignored.
function Stepper:Go(i)
	if type(i) ~= "number" or i ~= i or i < 1 or i > self.count or i ~= floor(i) then return false end
	if i == self.index then return false end
	self.index = i
	return true
end

function Stepper:Next() return self:CanNext() and self:Go(self.index + 1) end
function Stepper:Back() return self:CanBack() and self:Go(self.index - 1) end

---------------------------------------------------------------------------------------------------------------------
-- Fields
---------------------------------------------------------------------------------------------------------------------
local function copy(v, depth)
	local t = type(v)
	if t == "string" or t == "number" or t == "boolean" then return v end
	if t ~= "table" or (depth or 0) > 4 then return nil end
	local out = {}
	for k, value in pairs(v) do
		local kt = type(k)
		if kt == "string" or kt == "number" then out[k] = copy(value, (depth or 0) + 1) end
	end
	return out
end

-- A deep copy of the fields the editor owns; anything else is left out.
function Model.Strip(fields)
	local out = {}
	if type(fields) ~= "table" then return out end
	for _, name in ipairs(Model.CONTENT) do
		if fields[name] ~= nil then out[name] = copy(fields[name]) end
	end
	return out
end

-- The record that publishing these fields would produce (sanitized exactly as OwnListing does), or nil.
function Model.Clean(fields, key)
	local raw = Model.Strip(fields)
	raw.k, raw.rev = key or Model.PLACEHOLDER_KEY, 1
	local rec = Listing().SanitizeFull(raw)
	return rec
end

local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- The content of a clean record (no meta fields), for comparing.
local function content(rec)
	return Model.Strip(rec or {})
end

-- true when both sets of fields would publish the same listing (a typed Discord link and its code count as the same).
function Model.Same(a, b)
	return same(content(Model.Clean(a)), content(Model.Clean(b)))
end

---------------------------------------------------------------------------------------------------------------------
-- The checklist
---------------------------------------------------------------------------------------------------------------------
local function item(id, state, step, L, hint)
	return { id = id, state = state, step = step, text = L["ED_CHK_" .. id], hint = hint }
end

local function utf8Len(s) return s and Normalize().Utf8Len(s) or 0 end

local function trimmed(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- The items of the checklist for `fields`. ctx: leader (true when this character may edit), L.
function Model.Items(fields, ctx)
	local L = ctx.L
	local E = ns.Enums
	local raw = Model.Strip(fields)
	local clean = Model.Clean(fields, ctx.key) or {}
	local items = {}

	items[#items + 1] = item("leader", ctx.leader and "ok" or "bad", nil, L)

	items[#items + 1] = item("sub", clean.sub and "ok" or "todo", 1, L)

	local descLen = utf8Len(clean.desc)
	local desc
	if descLen >= Model.DESC_MIN then desc = item("desc", "ok", 2, L)
	elseif descLen > 0 then desc = item("desc", "bad", 2, L, L["ED_HINT_DESC"]:format(descLen, Model.DESC_MIN))
	else desc = item("desc", "todo", 2, L) end
	desc.text = L["ED_CHK_desc"]:format(Model.DESC_MIN)
	items[#items + 1] = desc

	items[#items + 1] = item("lang", clean.lang1 and "ok" or "todo", 2, L)
	items[#items + 1] = item("pace", clean.pace and "ok" or "todo", 3, L)

	local kept = clean.tags and #clean.tags or 0
	local typed = type(raw.tags) == "table" and #raw.tags or 0
	if kept == 0 then
		items[#items + 1] = item("tags", typed > 0 and "bad" or "todo", 3, L, typed > 0 and L["ED_HINT_TAGS"] or nil)
	elseif kept ~= typed or kept > (E and E.MAX_TAGS or Model.MAX_TAGS) then
		items[#items + 1] = item("tags", "bad", 3, L, L["ED_HINT_TAGS"])
	else
		items[#items + 1] = item("tags", "ok", 3, L)
	end

	items[#items + 1] = item("emblem", clean.emb and "ok" or "todo", 1, L)

	local closed = raw.rec == (E and E.RECRUITING.CLOSED or 0)
	local _, faction = Listing().ParseKey(ctx.key or "")   -- a class the guild's faction cannot play is no use to it
	local usable = clean.want ~= nil and next(Model.WantFor(clean.want, faction)) ~= nil
	if closed or usable then items[#items + 1] = item("looking", "ok", 4, L)
	else items[#items + 1] = item("looking", "todo", 4, L, L["ED_HINT_LOOKING"]) end

	local disc = raw.disc
	if disc == nil or (type(disc) == "string" and trimmed(disc) == "") then
		items[#items + 1] = item("discord", "optional", 6, L)
	elseif type(disc) == "string" and Listing().ExtractDiscordCode(disc) then
		items[#items + 1] = item("discord", "ok", 6, L)
	else
		items[#items + 1] = item("discord", "bad", 6, L, L["ED_HINT_DISCORD"])
	end
	return items, clean
end

-- The status of one step from the states of its items: "bad", "todo", "ok" or "optional" (only optional items).
local function combine(states)
	local seen = {}
	for _, s in ipairs(states) do seen[s] = true end
	if seen.bad then return "bad" end
	if seen.todo then return "todo" end
	if seen.ok then return "ok" end
	if seen.optional then return "optional" end
	return "ok"   -- a step with nothing to check (Requirements): its fields are all optional
end

-- The whole view: items, the status of the seven steps, how many are ready, whether every required item is green and the
-- first problem (the item to send the Guild Master to). ctx: leader, key, L.
function Model.View(fields, ctx)
	local items, clean = Model.Items(fields, ctx)
	local view = { items = items, clean = clean, steps = {}, complete = true }
	for _, it in ipairs(items) do
		if it.state == "todo" or it.state == "bad" then
			view.complete = false
			if not view.first and it.step then view.first = it end
		end
	end
	local ready = 0
	for i, step in ipairs(Model.STEPS) do
		local status
		if i == Model.PUBLISH then
			status = view.complete and "ok" or "todo"
		else
			local states = {}
			for _, it in ipairs(items) do if it.step == i then states[#states + 1] = it.state end end
			status = combine(states)
		end
		view.steps[i] = { id = step.id, index = i, status = status }
		if status == "ok" or status == "optional" then ready = ready + 1 end
	end
	view.ready = ready
	return view
end

---------------------------------------------------------------------------------------------------------------------
-- The main button
---------------------------------------------------------------------------------------------------------------------
-- "publish" (no listing, or a withdrawn one) or "save" (a listed listing), whether it can be pressed now and why not.
-- ctx: canEdit (OwnListing:CanEdit() gave a key), why (the reason when not), wait (seconds before the next publication),
-- status ("none" | "listed" | "delisted"), changed (the fields differ from the published version), L.
-- kind of the reason: "role", "incomplete", "unchanged" or "rate". `step` is where to send the player ("incomplete").
function Model.Action(view, ctx)
	local L = ctx.L
	local mode = ctx.status == "listed" and "save" or "publish"
	local action = { mode = mode, label = L[mode == "save" and "ED_SAVE" or "ED_PUBLISH"], enabled = false }
	if not ctx.canEdit then
		action.kind = "role"
		action.reason = ns.OwnListing:Explain(ctx.why or "not-leader")
	elseif not view.complete then
		action.kind = "incomplete"
		action.step = view.first and view.first.step or nil
		action.reason = action.step and L["ED_FIX"]:format(Model.StepLabel(action.step, L)) or L["OWN_INCOMPLETE"]
	elseif mode == "save" and not ctx.changed then
		action.kind = "unchanged"
		action.reason = L["ED_UNCHANGED"]
	elseif (tonumber(ctx.wait) or 0) > 0 then
		action.kind = "rate"
		action.reason = ns.OwnListing:Explain("rate", ctx.wait)
	else
		action.enabled = true
	end
	return action
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
function Model.ReadyText(ready, L) return L["ED_READY"]:format(ready, Model.COUNT) end

-- "Step 3 of 7".
function Model.StepText(index, L) return L["ED_STEP_OF"]:format(index, Model.COUNT) end

-- The line under the steps: "Draft saved automatically · 2 min ago", or what went wrong.
-- ctx: savedAt (server time of the last save or nil), now, failed (a reason of SaveDraft or nil).
function Model.DraftText(ctx, L)
	if ctx.failed then return L["ED_DRAFT_FAILED"] end
	if not ctx.savedAt then return L["ED_DRAFT_AUTO"] end
	local age = (ctx.now or ctx.savedAt) - ctx.savedAt
	return L["ED_DRAFT_SAVED"]:format(ns.BrowseModel.AgeText(age, L))
end

---------------------------------------------------------------------------------------------------------------------
-- Typed text, languages, banners (M3.3: the Identity and About steps)
---------------------------------------------------------------------------------------------------------------------
local huge, floor2 = math.huge, math.floor

local function limits() return Listing().LIMITS end
function Model.SubMax() return limits().SUB end
function Model.DescMax() return limits().DESC end
function Model.DescLines() return limits().DESC_LINES end

-- Length of `text` as it will be published (SPEC-03 §6: controls removed, "|" doubled, trimmed), in UTF-8 characters.
local function cleanLen(text, multi)
	return utf8Len(Listing().CleanText(text, huge, multi, huge) or "")
end

-- The text as it is typed, cut to what SPEC-03 allows: `max` characters (counted after the cleaning of §6) and, for a
-- multi-line field, `maxLines` lines. Nothing is trimmed, so a space typed at the end stays. Returns the text and whether
-- anything was cut or removed. A single-line field (maxLines nil) also loses its line breaks.
function Model.Clamp(text, max, maxLines)
	if type(text) ~= "string" then return "", text ~= nil end
	local multi = maxLines ~= nil
	local s = Listing().StripControls(text, multi)
	if multi then
		local lines, n = {}, 0
		for line in (s .. "\n"):gmatch("(.-)\n") do
			n = n + 1
			if n > maxLines then break end
			lines[n] = line
		end
		s = table.concat(lines, "\n")
	end
	local len = cleanLen(s, multi)
	while len > max do
		local keep = utf8Len(s) - (len - max)
		if keep < 0 then keep = 0 end
		s = Normalize().Utf8Sub(s, 1, keep)
		len = cleanLen(s, multi)
	end
	return s, s ~= text
end

-- What the counters show: { chars, lines, max, maxLines, over }. `lines` is 0 for an empty text.
function Model.TextStats(text, max, maxLines)
	text = type(text) == "string" and text or ""
	local multi = maxLines ~= nil
	local s = Listing().StripControls(text, multi)
	local lines = 0
	if s ~= "" then
		lines = 1
		for _ in s:gmatch("\n") do lines = lines + 1 end
		if not multi then lines = 1 end
	end
	local chars = cleanLen(text, multi)
	return { chars = chars, lines = lines, max = max, maxLines = maxLines,
		over = chars > max or (maxLines ~= nil and lines > maxLines) }
end

local function hasBit(mask, i) return floor2(mask / ns.Enums.LanguageBit(i)) % 2 == 1 end

local function maskOf(main, others)
	local E = ns.Enums
	local mask = E.LanguageBit(main)
	for _, i in ipairs(others) do
		if i ~= main and E.LanguageBit(i) and not hasBit(mask, i) then mask = mask + E.LanguageBit(i) end
	end
	return mask
end

-- The main language (an index of Enums.LANGUAGES) of these fields, or nil.
function Model.MainLanguage(fields)
	local clean = Model.Clean(fields) or {}
	return clean.lang1
end

-- The secondary languages (every language of the mask but the main one), ascending.
function Model.Secondary(fields)
	local clean = Model.Clean(fields) or {}
	local out = {}
	if clean.lang1 and clean.lang then
		for i = 1, ns.Enums.LANGUAGE_COUNT do
			if i ~= clean.lang1 and hasBit(clean.lang, i) then out[#out + 1] = i end
		end
	end
	return out
end

-- The fields to patch when language i becomes the main one: the secondary ones stay, except i itself. nil for a bad index.
function Model.SetMain(fields, i)
	if not ns.Enums.LanguageBit(i) then return nil end
	return { lang1 = i, lang = maskOf(i, Model.Secondary(fields)) }
end

-- The fields to patch when the secondary languages become `list` (indexes; the main one, bad and repeated ones are
-- ignored). nil while there is no main language: a secondary language needs one.
function Model.SetSecondary(fields, list)
	local main = Model.MainLanguage(fields)
	if not main or type(list) ~= "table" then return nil end
	return { lang1 = main, lang = maskOf(main, list) }
end

-- The verified banners (Assets.BANNERS) as a list of { index, file }, by index. Empty until the fileIDs are confirmed.
function Model.Banners()
	local out = {}
	local list = ns.Assets and ns.Assets.BANNERS or {}
	for index, entry in pairs(list) do
		if type(index) == "number" and type(entry) == "table" and type(entry.file) == "number" then
			out[#out + 1] = { index = index, file = entry.file }
		end
	end
	table.sort(out, function(a, b) return a.index < b.index end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Activity (M3.4): activities in order, days and time window
---------------------------------------------------------------------------------------------------------------------
Model.TIME_STEP = 30   -- minutes between the choices of the time menus

-- The activities of these fields as they will be published: valid, unique, in the order picked, at most three.
function Model.Tags(fields)
	local clean = Model.Clean(fields) or {}
	local out = {}
	for i, id in ipairs(clean.tags or {}) do out[i] = id end
	return out
end

-- The position (1..3) of activity `id` in `tags`, or nil.
function Model.TagNumber(tags, id)
	for i, v in ipairs(tags or {}) do if v == id then return i end end
	return nil
end

-- Picks or removes activity `id`. Returns the new list and what happened: "added", "removed", "full" (a fourth one cannot be
-- picked: the list is unchanged) or "invalid" (not an activity: unchanged). Removing one renumbers the rest; the order picked
-- is the order of importance.
function Model.ToggleTag(tags, id)
	local out = {}
	for i, v in ipairs(tags or {}) do out[i] = v end
	if not ns.Enums.IsActivity(id) then return out, "invalid" end
	local at = Model.TagNumber(out, id)
	if at then
		table.remove(out, at)
		return out, "removed"
	end
	if #out >= (ns.Enums.MAX_TAGS or Model.MAX_TAGS) then return out, "full" end
	out[#out + 1] = id
	return out, "added"
end

-- The days and the time window of these fields in a zone `offset` minutes from UTC (the stored values are UTC; the
-- conversion is BrowseModel.ToLocal, the one the visitor's list and filters use).
-- Returns { days = mask (0 = none), hasTime, allDay, from, to } (from and to are local minutes 0..1439, nil without times).
function Model.Schedule(fields, offset)
	local clean = Model.Clean(fields) or {}
	local out = { days = 0, hasTime = false, allDay = false }
	if clean.t0 == nil or clean.t1 == nil then
		out.days = clean.days or 0
		return out
	end
	out.hasTime = true
	if clean.t0 == clean.t1 then
		out.allDay, out.days = true, clean.days or 0
		return out
	end
	local days, from, to = ns.BrowseModel.ToLocal(clean.days or 0, clean.t0, clean.t1, offset)
	out.days, out.from, out.to = days or 0, from, to
	return out
end

-- The fields to patch for a local schedule { days, allDay, from, to } in a zone `offset` minutes from UTC: `days` and
-- `t0`/`t1` in UTC (the days move with the start when it falls on another UTC day); `false` clears a field. A window with
-- no end or no start stores no times; a window whose start equals its end is the whole day.
function Model.SchedulePatch(sched, offset)
	sched = sched or {}
	local days = tonumber(sched.days) or 0
	if days < 0 or days > 127 or days ~= floor(days) then days = 0 end
	local patch = { days = days > 0 and days or false, t0 = false, t1 = false }
	if sched.allDay then
		patch.t0, patch.t1 = 0, 0
	elseif sched.from and sched.to then
		local from, to = floor(sched.from) % 1440, floor(sched.to) % 1440
		if from == to then
			patch.t0, patch.t1 = 0, 0
		else
			local d, t0, t1 = ns.BrowseModel.ToLocal(days, from, to, -(tonumber(offset) or 0))
			patch.days = d > 0 and d or false
			patch.t0, patch.t1 = t0, t1
		end
	end
	return patch
end

-- The choices of a time menu: { { key = minutes, text = "20:00" }, ... } every TIME_STEP minutes, optionally without `skip`.
function Model.TimeChoices(skip)
	local out = {}
	for m = 0, 1439, Model.TIME_STEP do
		if m ~= skip then out[#out + 1] = { key = m, text = ns.BrowseModel.FormatMinutes(m) } end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Recruitment (M3.5): status and the "Looking for" grid
---------------------------------------------------------------------------------------------------------------------
Model.ANY_CLASS = 0                       -- the key of `want` that means any class
Model.STATUS_ORDER = { 1, 2, 0 }          -- Open to all, Selected classes, Closed (the order of the segmented button)
Model.ANY_ROLES = 15                      -- every role: what "Open to all" asks for

-- The faction of a guild key ("Realm|Horde|Name"), or nil.
function Model.FactionOf(key)
	local _, faction = Listing().ParseKey(key or "")
	return faction
end

-- The recruitment status of these fields as published (0 closed, 1 open, 2 selected classes), or nil when not chosen.
function Model.Status(fields)
	local clean = Model.Clean(fields) or {}
	return clean.rec
end

-- `want` reduced to what `faction` can recruit: the classes that faction plays (and class 0), with only the roles each can
-- play. A table `{ [classID] = mask }`, empty when nothing is left. An unknown faction removes no class.
function Model.WantFor(want, faction)
	local E = ns.Enums
	local out = {}
	if type(want) ~= "table" then return out end
	for id, mask in pairs(want) do
		if type(id) == "number" and type(mask) == "number" and (id == 0 or (E.CLASS_ROLES[id] and E.ClassInFaction(id, faction))) then
			local m = E.FilterRoles(id, mask)
			if m > 0 then out[id] = m end
		end
	end
	return out
end

-- The `want` map of these fields for the grid: what Model.Clean keeps, for this faction.
function Model.Want(fields, faction)
	local clean = Model.Clean(fields) or {}
	return Model.WantFor(clean.want, faction)
end

-- The rows of the grid, in the order of the class ids: { id, file, name, valid = mask of the roles the class can play }.
-- Only the classes this faction plays and the table of Data/Enums knows (it names the icon). Not including "Any class".
function Model.GridClasses(faction)
	local E = ns.Enums
	local out = {}
	for _, id in ipairs(E.ClassesForFaction(faction)) do
		local c = E.CLASS_ROLES[id]
		if c then out[#out + 1] = { id = id, file = c.key, name = E.ClassLabel(id), valid = c.roles } end
	end
	return out
end

-- The state of one cell: "on", "off" or "blocked" (the class cannot play the role; class 0 can play every role).
function Model.Cell(want, classID, bit)
	local E = ns.Enums
	if classID ~= 0 and E.MaskAnd(E.ValidRoles(classID), bit) == 0 then return "blocked" end
	return E.HasRole(type(want) == "table" and want[classID] or 0, bit) and "on" or "off"
end

-- Clicks one cell. Returns the new `want` (the old one is not changed) and what happened: "added", "removed", "blocked"
-- (the class cannot play that role), "class" (a class the faction does not play, or unknown) or "invalid".
function Model.ToggleRole(want, classID, bit, faction)
	local E = ns.Enums
	local out = Model.WantFor(want, faction)
	if type(classID) ~= "number" or type(bit) ~= "number" or not E.RoleLabel(bit) then return out, "invalid" end
	if classID ~= 0 and not (E.CLASS_ROLES[classID] and E.ClassInFaction(classID, faction)) then return out, "class" end
	local state = Model.Cell(out, classID, bit)
	if state == "blocked" then return out, "blocked" end
	local mask = out[classID] or 0
	if state == "on" then mask = mask - bit else mask = mask + bit end
	out[classID] = mask > 0 and mask or nil
	return out, state == "on" and "removed" or "added"
end

-- Every role of a class on or off at once (a click on the class name): on when a role it can play is missing, else off.
-- Returns the new map and "added", "removed" or "class" (not a class of this faction).
function Model.ToggleClass(want, classID, faction)
	local E = ns.Enums
	local out = Model.WantFor(want, faction)
	if type(classID) ~= "number" then return out, "class" end
	if classID ~= 0 and not (E.CLASS_ROLES[classID] and E.ClassInFaction(classID, faction)) then return out, "class" end
	local valid = classID == 0 and Model.ANY_ROLES or E.ValidRoles(classID)
	if (out[classID] or 0) == valid then
		out[classID] = nil
		return out, "removed"
	end
	out[classID] = valid
	return out, "added"
end

-- How many classes the map names (Any class counts as one).
function Model.WantCount(want)
	local n = 0
	for _, mask in pairs(type(want) == "table" and want or {}) do if type(mask) == "number" and mask > 0 then n = n + 1 end end
	return n
end

-- The fields to patch when the grid became `want`: the map (or `false` when empty) and, when no status was chosen yet, the
-- status "selected classes".
function Model.WantPatch(fields, want)
	local E = ns.Enums
	local patch = { want = next(want or {}) and want or false }
	if patch.want and Model.Status(fields) == nil then patch.rec = E.RECRUITING.SOME end
	return patch
end

-- The fields to patch when the status becomes `rec` (0 closed, 1 open, 2 selected classes): Closed clears the grid (a closed
-- guild looks for nobody); Open asks for any class and any role when the grid is empty. nil for another value.
function Model.StatusPatch(fields, rec, faction)
	local E = ns.Enums
	if rec ~= E.RECRUITING.CLOSED and rec ~= E.RECRUITING.OPEN and rec ~= E.RECRUITING.SOME then return nil end
	local patch = { rec = rec }
	if rec == E.RECRUITING.CLOSED then
		patch.want = false
	elseif rec == E.RECRUITING.OPEN and next(Model.Want(fields, faction)) == nil then
		patch.want = { [Model.ANY_CLASS] = Model.ANY_ROLES }
	end
	return patch
end

---------------------------------------------------------------------------------------------------------------------
-- Requirements (M3.5): minimum level, optional item level, note
---------------------------------------------------------------------------------------------------------------------
Model.ITEM_LEVEL_MAX = 999

function Model.NoteMax() return limits().NOTE end

-- The highest level of the game (SPEC-03 `minL` goes from 1 to it).
function Model.MaxLevel()
	local v = ns.Compat and ns.Compat.Player and ns.Compat.Player.MaxLevel and ns.Compat.Player.MaxLevel()
	if type(v) == "number" and v >= 1 and v == floor(v) then return v end
	return limits().FALLBACK_MAX_LEVEL
end

-- A level taken to an integer between 1 and the maximum; nil when it is not a number.
function Model.ClampLevel(v)
	v = tonumber(v)
	if not v or v ~= v then return nil end
	v = floor(v + 0.5)
	if v < 1 then return 1 end
	local top = Model.MaxLevel()
	if v > top then return top end
	return v
end

-- The fields to patch for a minimum level: level 1 means "no minimum" and clears the field. nil when `v` is no number.
function Model.LevelPatch(v)
	local level = Model.ClampLevel(v)
	if not level then return nil end
	return { minL = level > 1 and level or false }
end

-- What was typed in the item level box: the integer 0..999 and what happened. Returns nil, "empty" for nothing, nil,
-- "invalid" for anything that is not digits, and n, "cut" when it was above 999.
function Model.ParseItemLevel(text)
	if type(text) ~= "string" then return nil, "invalid" end
	local s = trimmed(text)
	if s == "" then return nil, "empty" end
	if not s:match("^%d+$") then return nil, "invalid" end
	local n = tonumber(s)
	if n > Model.ITEM_LEVEL_MAX then return Model.ITEM_LEVEL_MAX, "cut" end
	return n, "ok"
end

-- The fields to patch for a minimum item level: 0 or nothing clears the field.
function Model.ItemLevelPatch(n)
	n = tonumber(n)
	if not n or n ~= n or n < 1 then return { minI = false } end
	if n > Model.ITEM_LEVEL_MAX then n = Model.ITEM_LEVEL_MAX end
	return { minI = floor(n) }
end

-- The requirements of these fields as published: { level (1 = none), hasLevel, itemLevel (0 = none), hasItemLevel, note }.
function Model.Requirements(fields)
	local clean = Model.Clean(fields) or {}
	local level, ilvl = clean.minL or 1, clean.minI or 0
	return { level = level, hasLevel = level > 1, itemLevel = ilvl, hasItemLevel = ilvl > 0, note = clean.note or "" }
end

---------------------------------------------------------------------------------------------------------------------
-- Contact (M3.5): the Discord invite code and up to 3 characters of the guild roster
---------------------------------------------------------------------------------------------------------------------
Model.CONTACTS_MAX = 3
Model.SUGGESTIONS = 5
Model.DISCORD_PREFIX = "https://discord.gg/"
Model.DISCORD_TYPED_MAX = 120   -- a pasted link is longer than a code

-- What was typed in the Discord box, explained. Returns { state, code, reason, replace }:
--   state "empty"  nothing typed (the Discord code is optional)
--   state "ok"     `code` is the invite code; `replace` is the text the box should show instead (the code) when it is not
--                  already what was typed (a pasted link)
--   state "bad"    `reason` says why: "link" (another website), "short" or "long" (the code has 2 to 32 characters) or
--                  "chars" (only letters, digits and hyphens)
function Model.DiscordCheck(text)
	local LS = Listing()
	if type(text) ~= "string" then return { state = "bad", reason = "chars" } end
	local code, why = LS.ExtractDiscordCode(text)
	if code then
		return { state = "ok", code = code, replace = text ~= code and code or nil }
	end
	if why == "empty" then return { state = "empty" } end
	-- find out what is wrong with it, to say so
	local s = trimmed(LS.StripControls(text, false))
	local rest = s:gsub("^[Hh][Tt][Tt][Pp][Ss]?://", ""):gsub("^[Ww][Ww][Ww]%.", "")
	local low = rest:lower()
	local candidate
	for _, prefix in ipairs({ "discord.gg/", "discord.com/invite/", "discordapp.com/invite/" }) do
		if low:sub(1, #prefix) == prefix then candidate = rest:sub(#prefix + 1):match("^([^/?#%s]*)") break end
	end
	if not candidate then
		if rest:find("[/.:]") then return { state = "bad", reason = "link" } end
		candidate = rest
	end
	if candidate:find("[^A-Za-z0-9%-]") then return { state = "bad", reason = "chars" } end
	if #candidate < LS.LIMITS.DISCORD_MIN then return { state = "bad", reason = "short" } end
	if #candidate > LS.LIMITS.DISCORD_MAX then return { state = "bad", reason = "long" } end
	return { state = "bad", reason = "chars" }
end

-- The link a code stands for, as players see it.
function Model.DiscordLink(code) return Model.DISCORD_PREFIX .. tostring(code or "") end

-- "Name-Realm" -> "Name" (the roster gives either form).
function Model.BaseName(name)
	if type(name) ~= "string" then return "" end
	return (name:match("^([^%-]+)") or name)
end

local function nameKey(name) return Model.BaseName(name):lower() end

-- The members of the guild roster: { { name, base, file, level, online, key } }, as the client lists them (at most
-- Compat.Guild.MAX_ROSTER). Empty while the roster is not loaded or there is no guild.
function Model.Roster()
	local out = {}
	local compat = ns.Compat
	local guild = compat and compat.Guild
	if not guild or not guild.InGuild() then return out end
	local E = ns.Enums
	local total = tonumber((guild.RosterCount())) or 0
	total = math.min(total, guild.MAX_ROSTER or 1000)
	for i = 1, total do
		local row = guild.RosterRow(i)
		if row and type(row.name) == "string" and row.name ~= "" then
			local file = row.classFile or (row.classID and E.CLASS_ROLES[row.classID] and E.CLASS_ROLES[row.classID].key) or nil
			local base = Model.BaseName(row.name)
			out[#out + 1] = { name = row.name, base = base, file = file, level = row.level, online = row.online == true,
				key = Normalize().SortKey(base) }
		end
	end
	return out
end

-- The member called `name` (the full name, or the name without the realm; case does not matter), or nil.
function Model.FindMember(roster, name)
	if type(name) ~= "string" or name == "" then return nil end
	local want, full = nameKey(name), name:lower()
	local found
	for _, m in ipairs(roster or {}) do
		if m.name:lower() == full then return m end
		if not found and m.base:lower() == want then found = m end
	end
	return found
end

-- The contacts of these fields as they will be published: valid, unique, at most 3, in the order picked.
function Model.Contacts(fields)
	local clean = Model.Clean(fields) or {}
	local out = {}
	for i, name in ipairs(clean.cont or {}) do out[i] = name end
	return out
end

local function hasName(list, name)
	local key = nameKey(name)
	for _, v in ipairs(list) do if nameKey(v) == key then return true end end
	return false
end

-- Adds the roster member called `name`. Returns the new list (the old one is not changed) and what happened: "added",
-- "full" (3 already), "repeat" (already there), "unknown" (not in the roster: contacts are picked from it), "empty" (no
-- name) or "noroster" (the roster is not loaded, so nothing can be picked). The name stored is the roster's.
function Model.AddContact(list, name, roster)
	local out = {}
	for i, v in ipairs(list or {}) do out[i] = v end
	if type(name) ~= "string" or trimmed(name) == "" then return out, "empty" end
	if not roster or #roster == 0 then return out, "noroster" end
	local member = Model.FindMember(roster, trimmed(name))
	if not member then return out, "unknown" end
	if hasName(out, member.name) then return out, "repeat" end
	if #out >= Model.CONTACTS_MAX then return out, "full" end
	out[#out + 1] = member.name
	return out, "added"
end

-- Removes the contact called `name`. Returns the new list and whether something was removed.
function Model.RemoveContact(list, name)
	local out, removed, key = {}, false, nameKey(name)
	for _, v in ipairs(list or {}) do
		if not removed and nameKey(v) == key then removed = true else out[#out + 1] = v end
	end
	return out, removed
end

-- The members to offer for what was typed, at most `limit` (default 5): the ones already chosen are left out; a name that
-- starts with the text comes before one that only contains it; online first, then by name. Without text: the members that
-- are online. `query` is folded like a search (accents, case, anything but letters).
function Model.Suggest(roster, query, chosen, limit)
	limit = limit or Model.SUGGESTIONS
	local q = Normalize().SortKey(query or "")
	local picked = {}
	for _, name in ipairs(chosen or {}) do picked[nameKey(name)] = true end
	local scored = {}
	for _, m in ipairs(roster or {}) do
		if not picked[m.base:lower()] then
			local at
			if q == "" then at = m.online and 1 or nil else at = m.key:find(q, 1, true) end
			if at then scored[#scored + 1] = { member = m, prefix = at == 1 and 0 or 1, online = m.online and 0 or 1 } end
		end
	end
	table.sort(scored, function(a, b)
		if a.prefix ~= b.prefix then return a.prefix < b.prefix end
		if a.online ~= b.online then return a.online < b.online end
		if a.member.key ~= b.member.key then return a.member.key < b.member.key end
		return a.member.name < b.member.name
	end)
	local out = {}
	for i = 1, math.min(limit, #scored) do out[i] = scored[i].member end
	return out
end

-- The chosen contacts against the roster: { { name, member, inGuild } } and whether the roster is loaded. While it is not
-- loaded nobody is reported as gone (inGuild is nil).
function Model.ContactStates(list, roster)
	local ready = roster ~= nil and #roster > 0
	local out = {}
	for i, name in ipairs(list or {}) do
		local member = ready and Model.FindMember(roster, name) or nil
		local inGuild
		if ready then inGuild = member ~= nil end
		out[i] = { name = name, member = member, inGuild = inGuild }
	end
	return out, ready
end

-- The names of `list` that the roster no longer has (empty while the roster is not loaded).
function Model.GoneContacts(list, roster)
	local gone = {}
	for _, c in ipairs((Model.ContactStates(list, roster))) do
		if c.inGuild == false then gone[#gone + 1] = c.name end
	end
	return gone
end

---------------------------------------------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------------------------------------------
-- The display fields of the card others will see (BrowseModel.Card with no player: nothing is checked against anybody).
function Model.Preview(fields, key, now, L)
	local sum = Model.Clean(fields, key) or { k = key or Model.PLACEHOLDER_KEY, rev = 1 }
	sum.upd = now
	return ns.BrowseModel.Card(sum, nil, nil, { now = now, L = L })
end

if ns.addon then ns.addon.EditorModel = Model end
