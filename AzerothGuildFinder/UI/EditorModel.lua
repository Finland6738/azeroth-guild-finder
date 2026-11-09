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
	if closed or clean.want then items[#items + 1] = item("looking", "ok", 4, L)
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
-- Preview
---------------------------------------------------------------------------------------------------------------------
-- The display fields of the card others will see (BrowseModel.Card with no player: nothing is checked against anybody).
function Model.Preview(fields, key, now, L)
	local sum = Model.Clean(fields, key) or { k = key or Model.PLACEHOLDER_KEY, rev = 1 }
	sum.upd = now
	return ns.BrowseModel.Card(sum, nil, nil, { now = now, L = L })
end

if ns.addon then ns.addon.EditorModel = Model end
