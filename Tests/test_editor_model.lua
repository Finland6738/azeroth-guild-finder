-- M3.2: the rules of the listing editor (UI/EditorModel.lua) without frames: every item of the "Before publishing"
-- checklist, the status of the seven steps, the reasons the main button is off (Guild Master, incomplete, nothing changed,
-- the 5-minute limit), the stepper, which fields the editor owns and what the live preview shows.
-- The mock player is "Testchar", Horde, on "Test Realm"; the guild key is "TestRealm|Horde|Iron Wolves".

local KEY = "TestRealm|Horde|Iron Wolves"
local function M() return AzerothGuildFinder.EditorModel end
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })

-- A listing that satisfies every item.
local function full(extra)
	local t = { sub = "Friendly raiders", desc = "We raid on weekends and we like to chat in voice.", lang1 = 1, lang = 1, tags = { 1, 2 },
		pace = 2, days = 21, t0 = 1140, t1 = 1380, rec = 1, apps = true, want = { [0] = 15 }, newb = true, minL = 30,
		emb = { t = 2, e = 0 }, disc = "wolves1", cont = { "Thrall" }, note = "Voice required" }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

local function ctx(extra)
	local t = { L = L, key = KEY, leader = true, canEdit = true, status = "none", wait = 0, changed = true }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

local function item(view, id)
	for _, it in ipairs(view.items) do if it.id == id then return it end end
end

local function states(view)
	local out = {}
	for _, it in ipairs(view.items) do out[it.id] = it.state end
	return out
end

describe("the checklist", function()
	it("has the items of SPEC-06 in order, each with the step that fixes it", function()
		local view = M().View(full(), ctx())
		local ids, steps = {}, {}
		for i, it in ipairs(view.items) do ids[i] = it.id; steps[i] = it.step or 0 end
		deepEq(ids, { "leader", "sub", "desc", "lang", "pace", "tags", "emblem", "looking", "discord" })
		deepEq(steps, { 0, 1, 2, 2, 3, 3, 1, 4, 6 })
	end)

	it("a full listing is green everywhere and complete", function()
		local view = M().View(full(), ctx())
		eq(view.complete, true)
		isNil(view.first)
		for _, it in ipairs(view.items) do eq(it.state, "ok", it.id) end
	end)

	it("an empty listing: every required item waits, the Discord code is optional", function()
		local view = M().View({}, ctx())
		eq(view.complete, false)
		deepEq(states(view), { leader = "ok", sub = "todo", desc = "todo", lang = "todo", pace = "todo", tags = "todo", emblem = "todo",
			looking = "todo", discord = "optional" })
		eq(view.first.id, "sub", "the first problem is the first item with a step")
	end)

	it("leader: red when this character is not the Guild Master", function()
		local view = M().View(full(), ctx({ leader = false, canEdit = false, why = "not-leader" }))
		eq(item(view, "leader").state, "bad")
		isNil(item(view, "leader").step)
		eq(view.complete, false)
		isNil(view.first, "there is no step to send the player to")
	end)

	it("subtitle: required, blank text does not count", function()
		eq(item(M().View(full({ sub = "nil" }), ctx()), "sub").state, "todo")
		eq(item(M().View(full({ sub = "   " }), ctx()), "sub").state, "todo")
		eq(item(M().View(full({ sub = "x" }), ctx()), "sub").state, "ok")
	end)

	it("description: at least 30 characters, counted as UTF-8 characters, with a hint while short", function()
		local short = item(M().View(full({ desc = "Too short" }), ctx()), "desc")
		eq(short.state, "bad")
		eq(short.hint, "9 of 30 characters")
		eq(item(M().View(full({ desc = "nil" }), ctx()), "desc").state, "todo")
		eq(item(M().View(full({ desc = ("a"):rep(29) }), ctx()), "desc").state, "bad")
		eq(item(M().View(full({ desc = ("a"):rep(30) }), ctx()), "desc").state, "ok")
		eq(item(M().View(full({ desc = ("é"):rep(30) }), ctx()), "desc").state, "ok", "30 characters, 60 bytes")
		eq(item(M().View(full({ desc = ("é"):rep(29) }), ctx()), "desc").state, "bad")
		eq(item(M().View(full({ desc = ("a "):rep(15) .. "   " }), ctx()), "desc").state, "bad", "trailing blanks are trimmed: 29 characters")
		eq(item(M().View(full(), ctx()), "desc").text, "Description: at least 30 characters")
	end)

	it("main language: needed", function()
		eq(item(M().View(full({ lang1 = "nil", lang = "nil" }), ctx()), "lang").state, "todo")
		eq(item(M().View(full({ lang1 = 99, lang = "nil" }), ctx()), "lang").state, "todo", "an unknown language is not one")
		eq(item(M().View(full({ lang1 = 99 }), ctx()), "lang").state, "ok", "with a mask, the main language falls back to its lowest bit, as when published")
		eq(item(M().View(full({ lang1 = 5, lang = 16 }), ctx()), "lang").state, "ok")
	end)

	it("commitment: Casual, Softcore or Hardcore", function()
		eq(item(M().View(full({ pace = "nil" }), ctx()), "pace").state, "todo")
		eq(item(M().View(full({ pace = 4 }), ctx()), "pace").state, "todo")
		for pace = 1, 3 do eq(item(M().View(full({ pace = pace }), ctx()), "pace").state, "ok") end
	end)

	it("activities: one to three valid ones, nothing else", function()
		eq(item(M().View(full({ tags = "nil" }), ctx()), "tags").state, "todo")
		eq(item(M().View(full({ tags = {} }), ctx()), "tags").state, "todo")
		eq(item(M().View(full({ tags = { 1 } }), ctx()), "tags").state, "ok")
		eq(item(M().View(full({ tags = { 1, 2, 3 } }), ctx()), "tags").state, "ok")
		local many = item(M().View(full({ tags = { 1, 2, 3, 4 } }), ctx()), "tags")
		eq(many.state, "bad", "a fourth one is refused, not silently dropped")
		eq(many.hint, "Pick between 1 and 3 activities.")
		eq(item(M().View(full({ tags = { 1, 1 } }), ctx()), "tags").state, "bad", "the same activity twice")
		eq(item(M().View(full({ tags = { 1, 999 } }), ctx()), "tags").state, "bad", "an unknown activity")
		eq(item(M().View(full({ tags = { 999 } }), ctx()), "tags").state, "bad")
	end)

	it("emblem: a tabard or a designed one", function()
		eq(item(M().View(full({ emb = "nil" }), ctx()), "emblem").state, "todo")
		eq(item(M().View(full({ emb = { t = 1, e = 123 } }), ctx()), "emblem").state, "ok")
		eq(item(M().View(full({ emb = { t = 1, e = 12345 } }), ctx()), "emblem").state, "todo", "an index above TabardParts.MAX_INDEX")
		eq(item(M().View(full({ emb = { t = 2, e = 1, b = 2, g = 3, ec = 255 } }), ctx()), "emblem").state, "ok")
		eq(item(M().View(full({ emb = { t = 3, e = 1 } }), ctx()), "emblem").state, "todo", "unknown type")
		eq(item(M().View(full({ emb = { t = 1 } }), ctx()), "emblem").state, "todo", "no texture piece")
	end)

	it("looking for: classes chosen, or recruitment closed", function()
		eq(item(M().View(full({ want = "nil" }), ctx()), "looking").state, "todo")
		eq(item(M().View(full({ want = "nil" }), ctx()), "looking").hint, "Choose classes and roles, or set recruitment to Closed.")
		eq(item(M().View(full({ want = {} }), ctx()), "looking").state, "todo")
		eq(item(M().View(full({ want = { [5] = 0 } }), ctx()), "looking").state, "todo", "a class with no role is nothing")
		eq(item(M().View(full({ want = "nil", rec = 0 }), ctx()), "looking").state, "ok", "closed needs no classes")
		eq(item(M().View(full({ want = { [5] = 2 }, rec = 2 }), ctx()), "looking").state, "ok")
		eq(item(M().View(full({ want = { [0] = 1 }, rec = 1 }), ctx()), "looking").state, "ok", "any class")
		eq(item(M().View(full({ want = "nil", rec = 2 }), ctx()), "looking").state, "todo", "selected classes only, none chosen")
	end)

	it("Discord: optional when empty, valid codes and links pass, anything else is red with a hint", function()
		eq(item(M().View(full({ disc = "nil" }), ctx()), "discord").state, "optional")
		eq(item(M().View(full({ disc = "" }), ctx()), "discord").state, "optional")
		eq(item(M().View(full({ disc = "   " }), ctx()), "discord").state, "optional")
		eq(item(M().View(full({ disc = "aurora-it" }), ctx()), "discord").state, "ok")
		eq(item(M().View(full({ disc = "https://discord.gg/aurora-it" }), ctx()), "discord").state, "ok")
		eq(item(M().View(full({ disc = "discord.com/invite/abc123" }), ctx()), "discord").state, "ok")
		local bad = item(M().View(full({ disc = "not a code!" }), ctx()), "discord")
		eq(bad.state, "bad")
		eq(bad.hint, "Paste the invite link or only its code, for example aurora-it.")
		eq(item(M().View(full({ disc = "x" }), ctx()), "discord").state, "bad", "one character is too short")
		eq(item(M().View(full({ disc = "https://example.com/aurora" }), ctx()), "discord").state, "bad")
		eq(M().View(full({ disc = "!!" }), ctx()).complete, false, "an invalid code blocks publishing")
	end)

	it("one problem at a time: fixing it makes the list complete", function()
		local fields = full({ sub = "nil" })
		eq(M().View(fields, ctx()).complete, false)
		fields.sub = "Friendly raiders"
		eq(M().View(fields, ctx()).complete, true)
	end)
end)

describe("the steps", function()
	it("each step takes the worst state of its items", function()
		local v = M().View(full({ desc = "short" }), ctx())
		eq(v.steps[1].status, "ok")
		eq(v.steps[2].status, "bad")
		eq(v.steps[3].status, "ok")
		eq(v.steps[4].status, "ok")
		eq(v.steps[5].status, "ok", "Requirements has nothing required")
		eq(v.steps[6].status, "ok")
		eq(v.steps[7].status, "todo", "Preview & publish is ready only when everything is")
		eq(v.ready, 5, "steps 1, 3, 4, 5 and 6 are ready")
	end)

	it("a step with a missing item is todo, an invalid Discord code makes Contact red, an empty one optional", function()
		local v = M().View(full({ sub = "nil", disc = "no way!" }), ctx())
		eq(v.steps[1].status, "todo")
		eq(v.steps[6].status, "bad")
		local e = M().View(full({ disc = "nil" }), ctx())
		eq(e.steps[6].status, "optional")
		eq(e.steps[7].status, "ok")
	end)

	it("counts the ready steps: all seven for a full listing, optional Contact included", function()
		eq(M().View(full(), ctx()).ready, 7)
		eq(M().View(full({ disc = "nil" }), ctx()).ready, 7)
		eq(M().View({}, ctx()).ready, 2, "Requirements (nothing to check) and Contact (optional)")
	end)

	it("the last step is ready only when the Guild Master check passes too", function()
		eq(M().View(full(), ctx({ leader = false })).steps[7].status, "todo")
	end)

	it("seven steps with the ids of SPEC-06 and the last one is the shell's own", function()
		eq(M().COUNT, 7)
		eq(M().PUBLISH, 7)
		local ids = {}
		for i, s in ipairs(M().STEPS) do ids[i] = s.id end
		deepEq(ids, { "identity", "about", "activity", "recruitment", "requirements", "contact", "publish" })
		eq(M().StepIndex("recruitment"), 4)
		isNil(M().StepIndex("nothing"))
		eq(M().StepLabel(7, L), "Preview & publish")
		eq(M().ReadyText(3, L), "3 / 7 ready")
		eq(M().StepText(4, L), "Step 4 of 7")
	end)
end)

describe("why the main button is off", function()
	local function action(fields, extra, viewExtra)
		local c = ctx(extra)
		return M().Action(M().View(fields, ctx(viewExtra or extra)), c)
	end

	it("on: a complete listing, the Guild Master, the limit passed", function()
		local a = action(full())
		eq(a.enabled, true)
		eq(a.mode, "publish")
		eq(a.label, "Publish listing")
		isNil(a.reason)
	end)

	it("off for anybody but the Guild Master, with OwnListing's sentence", function()
		local a = action(full(), { canEdit = false, why = "not-leader", leader = false })
		eq(a.enabled, false)
		eq(a.kind, "role")
		eq(a.reason, "You are no longer the Guild Master: the change was not saved.")
		a = action(full(), { canEdit = false, why = "readonly" })
		eq(a.kind, "role")
		eq(a.reason, "Your saved data comes from a newer version of the addon: nothing can be saved.")
		a = action(full(), { canEdit = false, why = "no-guild", leader = false })
		eq(a.reason, "You are not in a guild.")
	end)

	it("off while an item is not green, naming the step to fix and pointing at it", function()
		local a = action(full({ sub = "nil" }))
		eq(a.enabled, false)
		eq(a.kind, "incomplete")
		eq(a.step, 1)
		eq(a.reason, "Fix \"Identity\" to publish")
		a = action(full({ disc = "bad code!!" }))
		eq(a.step, 6)
		eq(a.reason, "Fix \"Contact\" to publish")
		a = action(full({ pace = "nil", desc = "short" }))
		eq(a.step, 2, "the first item in checklist order wins")
		a = action({})
		eq(a.kind, "incomplete")
	end)

	it("off for five minutes after a publication, with the time left", function()
		local a = action(full(), { wait = 125 })
		eq(a.enabled, false)
		eq(a.kind, "rate")
		eq(a.reason, "You can publish again in 2:05 (one published change every 5 minutes).")
		eq(action(full(), { wait = 0 }).enabled, true)
		eq(action(full(), { wait = 0.4 }).kind, "rate", "a fraction of a second is still waiting")
	end)

	it("a listed listing says Save changes, and needs a change", function()
		local a = action(full(), { status = "listed", changed = false })
		eq(a.mode, "save")
		eq(a.label, "Save changes")
		eq(a.enabled, false)
		eq(a.kind, "unchanged")
		eq(a.reason, "Nothing has changed since the last published version.")
		a = action(full(), { status = "listed", changed = true })
		eq(a.enabled, true)
		eq(a.label, "Save changes")
	end)

	it("a withdrawn listing publishes again with one click, changed or not", function()
		local a = action(full(), { status = "delisted", changed = false })
		eq(a.mode, "publish")
		eq(a.enabled, true)
	end)

	it("the reasons come in order: role, incomplete, unchanged, rate", function()
		eq(action(full({ sub = "nil" }), { canEdit = false, why = "not-leader", wait = 100, status = "listed", changed = false }).kind, "role")
		eq(action(full({ sub = "nil" }), { wait = 100, status = "listed", changed = false }).kind, "incomplete")
		eq(action(full(), { wait = 100, status = "listed", changed = false }).kind, "unchanged")
		eq(action(full(), { wait = 100, status = "listed", changed = true }).kind, "rate")
	end)
end)

describe("the stepper", function()
	it("starts at step 1, goes forward and back, and stops at the ends", function()
		local s = M().NewStepper()
		eq(s.index, 1)
		eq(s:CanBack(), false)
		eq(s:CanNext(), true)
		eq(s:Back(), false)
		eq(s:Next(), true)
		eq(s.index, 2)
		for _ = 1, 10 do s:Next() end
		eq(s.index, 7)
		eq(s:CanNext(), false)
		eq(s:Next(), false)
		eq(s.index, 7)
		eq(s:Back(), true)
		eq(s.index, 6)
	end)

	it("jumps to a step, ignores steps that do not exist and reports whether it moved", function()
		local s = M().NewStepper()
		eq(s:Go(4), true)
		eq(s.index, 4)
		eq(s:Go(4), false, "already there")
		eq(s:Go(0), false)
		eq(s:Go(8), false)
		eq(s:Go(2.5), false)
		eq(s:Go("3"), false)
		eq(s:Go(nil), false)
		eq(s:Go(0 / 0), false)
		eq(s.index, 4)
	end)

	it("a starting step outside the range is clamped", function()
		eq(M().NewStepper(7, 0).index, 1)
		eq(M().NewStepper(7, 99).index, 7)
		eq(M().NewStepper(7, "x").index, 1)
		eq(M().NewStepper(3, 3).index, 3)
	end)
end)

describe("the fields the editor owns", function()
	it("Strip keeps only content fields and copies deeply", function()
		local src = full({ k = KEY, rev = 9, upd = 1, first = 2, own = "0badc0de", del = true, st = { m = 5 }, srev = 3, test = true })
		local out = M().Strip(src)
		for _, meta in ipairs({ "k", "rev", "upd", "first", "own", "del", "st", "srev", "test" }) do isNil(out[meta], meta) end
		deepEq(out.tags, { 1, 2 })
		out.tags[1] = 99
		eq(src.tags[1], 1, "a copy")
		deepEq(M().Strip(nil), {})
		deepEq(M().Strip("text"), {})
	end)

	it("Strip drops functions and cycles that are not data", function()
		local t = { sub = "x", tags = { 1, 2, fn = function() end } }
		local out = M().Strip(t)
		isNil(out.tags.fn)
	end)

	it("Same: what would be published decides, not how it was typed", function()
		eq(M().Same(full(), full()), true)
		eq(M().Same(full({ disc = "https://discord.gg/wolves1" }), full({ disc = "wolves1" })), true, "link and code")
		eq(M().Same(full(), full({ sub = "Other" })), false)
		eq(M().Same(full(), full({ tags = { 2, 1 } })), false, "the order of activities is part of the listing")
		eq(M().Same(full({ lang = "nil" }), full({ lang = 1 })), true, "the language mask follows the main language")
		eq(M().Same({}, {}), true)
	end)

	it("Clean gives the record that would be published", function()
		local rec = M().Clean(full({ disc = "https://discord.gg/wolves1", sub = "  Friendly raiders  " }), KEY)
		eq(rec.k, KEY)
		eq(rec.disc, "wolves1")
		eq(rec.sub, "Friendly raiders")
		eq(rec.lang1, 1)
		notNil(M().Clean({}, nil), "without a guild key a placeholder is used")
	end)
end)

describe("the preview", function()
	it("shows what the list will show: name, subtitle, languages, commitment, activities, wanted classes", function()
		local card = M().Preview(full({ tags = { 6, 1 }, pace = 3, want = { [5] = 2, [8] = 8 } }), KEY, 1790000000, L)
		eq(card.name, "Iron Wolves")
		eq(card.sub, "Friendly raiders")
		deepEq(card.langs, { "EN" })
		eq(card.paceText, "HARDCORE")
		eq(card.activitiesText, "World PvP · Raids")
		eq(#card.classes, 2)
		eq(card.updatedText, "Updated today")
	end)

	it("works for an empty draft", function()
		local card = M().Preview({}, KEY, 1790000000, L)
		eq(card.name, "Iron Wolves")
		isNil(card.sub)
		eq(card.activitiesText, "")
		deepEq(card.langs, {})
	end)
end)

describe("the draft line", function()
	it("says the draft is saved automatically, how long ago, or that saving failed", function()
		eq(M().DraftText({}, L), "Draft saved automatically")
		eq(M().DraftText({ savedAt = 1000, now = 1000 }, L), "Draft saved automatically · just now")
		eq(M().DraftText({ savedAt = 1000, now = 1000 + 125 }, L), "Draft saved automatically · 2 min ago")
		eq(M().DraftText({ savedAt = 1000, now = 1100, failed = "not-leader" }, L), "The draft could not be saved")
	end)
end)
