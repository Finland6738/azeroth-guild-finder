-- M3.3: the Identity and About steps of the listing editor. First the rules without frames (EditorModel: the limits of
-- SPEC-03 for the subtitle and the description, line counting, the cleaning of typed text, the language fields, the banner
-- list), then the two pages on the mock client (UI/EditorSteps.lua): what is typed is cut, counted and saved as the draft,
-- and the checklist and the stepper follow.
-- The mock player is "Testchar", Horde, on "Test Realm"; the guild is "Iron Wolves".

local GUILD = "Iron Wolves"
local KEY = "TestRealm|Horde|" .. GUILD

local function A() return AzerothGuildFinder end
local function M() return A().EditorModel end
local function editor() return A().Editor end
local function OL() return A().OwnListing end
local function main() return A().Main end
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })

local function ctx(extra)
	local t = { L = L, key = KEY, leader = true, canEdit = true, status = "none", wait = 0, changed = true }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end
local function states(view)
	local out = {}
	for _, it in ipairs(view.items) do out[it.id] = it.state end
	return out
end
local function chars(n, c) return string.rep(c or "a", n) end
local function lines(n) local t = {} for i = 1, n do t[i] = "line " .. i end return table.concat(t, "\n") end
local function len(s) return A().Normalize.Utf8Len(s) end

describe("the subtitle (60 characters, one line)", function()
	it("is kept as typed up to 60 characters", function()
		local text, changed = M().Clamp(chars(60), 60)
		eq(len(text), 60)
		falsy(changed)
	end)

	it("is cut at 60 characters, counting UTF-8 characters and not bytes", function()
		local text, changed = M().Clamp(chars(70, "é"), 60)
		eq(len(text), 60)
		truthy(changed)
		eq(M().Clamp(chars(60, "é"), 60), chars(60, "é"))
	end)

	it("loses its line breaks and control characters, and keeps a space typed at the end", function()
		eq(M().Clamp("Friendly\nraiders\1", 60), "Friendlyraiders")
		eq(M().Clamp("Friendly ", 60), "Friendly ")
	end)

	it("counts what will be published: a pipe is doubled (SPEC-03 §6)", function()
		eq(M().TextStats("a|b", 60).chars, 4)
		local cut = M().Clamp(chars(59) .. "||||", 60)
		truthy(M().TextStats(cut, 60).chars <= 60)
	end)

	it("the counter says 0 for nothing and never goes above the limit once cut", function()
		eq(M().TextStats("", 60).chars, 0)
		eq(M().TextStats(nil, 60).chars, 0)
		local stats = M().TextStats(M().Clamp(chars(200), 60), 60)
		eq(stats.chars, 60)
		falsy(stats.over)
		truthy(M().TextStats(chars(61), 60).over)
	end)
end)

describe("the description (500 characters, 12 lines)", function()
	it("takes 500 characters and cuts the 501st", function()
		local text, changed = M().Clamp(chars(500), 500, 12)
		eq(len(text), 500)
		falsy(changed)
		text, changed = M().Clamp(chars(900), 500, 12)
		eq(len(text), 500)
		truthy(changed)
	end)

	it("counts the line breaks as characters, like the cleaning of SPEC-03 does", function()
		local text = lines(12)
		eq(M().TextStats(text, 500, 12).chars, len(text))
		local cut = M().Clamp(chars(499) .. "\nb", 500, 12)
		eq(len(cut), 500)
	end)

	it("takes 12 lines and drops the 13th", function()
		local text, changed = M().Clamp(lines(12), 500, 12)
		eq(text, lines(12))
		falsy(changed)
		text, changed = M().Clamp(lines(15), 500, 12)
		eq(text, lines(12))
		truthy(changed)
	end)

	it("counts lines: 0 for nothing, one more than the line breaks, empty lines included", function()
		eq(M().TextStats("", 500, 12).lines, 0)
		eq(M().TextStats("one", 500, 12).lines, 1)
		eq(M().TextStats("one\ntwo", 500, 12).lines, 2)
		eq(M().TextStats("one\n\n\nfour", 500, 12).lines, 4)
		eq(M().TextStats("one\r\ntwo", 500, 12).lines, 2, "Windows line breaks count once")
		eq(M().TextStats(lines(13), 500, 12).lines, 13)
		truthy(M().TextStats(lines(13), 500, 12).over)
		falsy(M().TextStats(lines(12), 500, 12).over)
	end)

	it("a line break typed on the last line is refused, the text stays as it was", function()
		local text = M().Clamp(lines(12) .. "\n", 500, 12)
		eq(text, lines(12))
	end)

	it("normalises Windows line breaks and removes control characters", function()
		eq(M().Clamp("a\r\nb\1\2c", 500, 12), "a\nbc")
	end)

	it("matches what Listing publishes: the same text cleaned gives the same length", function()
		local raw = "Raids  \n\n We like |colours|  "
		local clean = A().Listing.CleanText(raw, 500, true)
		eq(M().TextStats(raw, 500, 12).chars, len(clean))
	end)

	it("a stripped text that is not a string gives nothing", function()
		eq(M().Clamp(nil, 500, 12), "")
		eq(M().TextStats(42, 500, 12).chars, 0)
	end)
end)

describe("the languages", function()
	it("a main language alone: the mask is its bit", function()
		deepEq(M().SetMain({}, 5), { lang1 = 5, lang = 16 })
	end)

	it("secondary languages need a main one", function()
		isNil(M().SetSecondary({}, { 2 }))
		deepEq(M().SetSecondary({ lang1 = 1, lang = 1 }, { 2, 5 }), { lang1 = 1, lang = 1 + 2 + 16 })
	end)

	it("the main language is always part of the mask, also when it is listed as secondary or left out", function()
		deepEq(M().SetSecondary({ lang1 = 1, lang = 1 }, { 1, 2 }), { lang1 = 1, lang = 3 })
		deepEq(M().SetSecondary({ lang1 = 1, lang = 1 }, {}), { lang1 = 1, lang = 1 })
	end)

	it("lists the secondary languages without the main one", function()
		deepEq(M().Secondary({ lang1 = 5, lang = 1 + 2 + 16 }), { 1, 2 })
		deepEq(M().Secondary({ lang1 = 5, lang = 16 }), {})
		deepEq(M().Secondary({}), {})
		eq(M().MainLanguage({ lang1 = 5, lang = 16 }), 5)
		isNil(M().MainLanguage({}))
	end)

	it("changing the main language keeps the secondary ones and moves the old main one out of the way", function()
		local f = { lang1 = 1, lang = 1 + 2 + 16 }   -- English, German, Italian
		deepEq(M().SetMain(f, 4), { lang1 = 4, lang = 8 + 2 + 16 }, "the old main language is not kept unless it was chosen as secondary")
		deepEq(M().SetMain(f, 2), { lang1 = 2, lang = 2 + 16 }, "a secondary language that becomes the main one is not counted twice")
	end)

	it("refuses a language that does not exist and ignores bad entries in the list", function()
		isNil(M().SetMain({}, 0))
		isNil(M().SetMain({}, 10))
		isNil(M().SetMain({}, "x"))
		deepEq(M().SetSecondary({ lang1 = 1, lang = 1 }, { 0, 99, "x", 2, 2 }), { lang1 = 1, lang = 3 })
		isNil(M().SetSecondary({ lang1 = 1, lang = 1 }, "no"))
	end)

	it("all nine languages fit in the mask", function()
		local all = {}
		for i = 1, 9 do all[i] = i end
		eq(M().SetSecondary({ lang1 = 1, lang = 1 }, all).lang, 511)
	end)
end)

describe("the banner list", function()
	it("is empty until banners are verified, and then follows the registry by index", function()
		deepEq(M().Banners(), {})
		local B = A().Assets.BANNERS
		B[3] = { file = 300 }; B[1] = { file = 100 }; B[2] = { verify = true }; B[4] = { file = "x" }
		local list = M().Banners()
		eq(#list, 2)
		eq(list[1].index, 1) eq(list[1].file, 100)
		eq(list[2].index, 3) eq(list[2].file, 300)
		B[1], B[2], B[3], B[4] = nil, nil, nil, nil
	end)
end)

describe("the checklist and the steps", function()
	local function full(extra)
		local t = { sub = "Friendly raiders", desc = chars(40), lang1 = 1, lang = 1, tags = { 1 }, pace = 2, rec = 1, want = { [0] = 15 },
			emb = { t = 2, e = 0 } }
		for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
		return t
	end

	it("the subtitle is required: empty or only spaces is not done", function()
		eq(states(M().View(full({ sub = "nil" }), ctx())).sub, "todo")
		eq(states(M().View(full({ sub = "   " }), ctx())).sub, "todo")
		eq(states(M().View(full(), ctx())).sub, "ok")
	end)

	it("the description needs 30 characters, and the typed limits cannot take it above what is published", function()
		eq(states(M().View(full({ desc = "nil" }), ctx())).desc, "todo")
		eq(states(M().View(full({ desc = chars(29) }), ctx())).desc, "bad")
		eq(states(M().View(full({ desc = chars(30) }), ctx())).desc, "ok")
		eq(states(M().View(full({ desc = (M().Clamp(chars(900), 500, 12)) }), ctx())).desc, "ok")
	end)

	it("the main language is required, secondary languages are not", function()
		eq(states(M().View(full({ lang1 = "nil", lang = "nil" }), ctx())).lang, "todo")
		eq(states(M().View(full({ lang1 = 5, lang = 16 + 1 + 2 }), ctx())).lang, "ok")
	end)

	it("Identity is green with subtitle and emblem, About with description and main language", function()
		local view = M().View(full(), ctx())
		eq(view.steps[1].status, "ok")
		eq(view.steps[2].status, "ok")
		view = M().View(full({ sub = "nil" }), ctx())
		eq(view.steps[1].status, "todo")
		eq(view.first.step, 1)
		view = M().View(full({ desc = chars(10), lang1 = "nil", lang = "nil" }), ctx())
		eq(view.steps[2].status, "bad")
		eq(view.first.step, 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The pages
---------------------------------------------------------------------------------------------------------------------
local function open(step)
	Mock.guild.Set{ name = GUILD, myRank = 0, members = { { name = "Jaina", rank = 1 } } }
	main():Show()
	editor():GoTo(step)
	return editor().pages[step == 1 and "identity" or "about"].frame
end
local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end
local function pick(sel, key) sel:Choose(key) end

describe("the Identity page", function()
	it("is the registered page of step 1 and shows the guild name from the game, locked", function()
		local page = open(1)
		falsy(editor().pages.identity.placeholder)
		eq(page.name:GetText(), GUILD)
		eq(page.lock.edit, nil, "there is no box to type into")
		eq(main().title:GetText(), "Identity")
		eq(#Mock.errors, 0)
	end)

	it("typing the subtitle saves the draft, moves the counter and turns the step green with the emblem", function()
		local page = open(1)
		eq(page.subCount:GetText(), "0 / 60")
		Mock.TypeInto(page.sub.edit, "Friendly raiders")
		eq(editor():Get("sub"), "Friendly raiders")
		eq(OL():Draft().sub, "Friendly raiders")
		eq(page.subCount:GetText(), "16 / 60")
		local view = editor():View()
		eq(view.steps[1].status, "todo", "the emblem is still missing")
		editor():Set("emb", { t = 2, e = 0 })
		eq(editor():View().steps[1].status, "ok")
		eq(#Mock.errors, 0)
	end)

	it("a subtitle longer than 60 characters is cut in the box, and a pasted line break disappears", function()
		local page = open(1)
		Mock.TypeInto(page.sub.edit, chars(75))
		eq(len(editor():Get("sub")), 60)
		eq(page.sub:GetText(), chars(60))
		eq(page.subCount:GetText(), "60 / 60")
		Mock.TypeInto(page.sub.edit, "one\ntwo")
		eq(editor():Get("sub"), "onetwo")
	end)

	it("emptying the subtitle clears it from the draft and the preview", function()
		local page = open(1)
		Mock.TypeInto(page.sub.edit, "Friendly raiders")
		Mock.TypeInto(page.sub.edit, "")
		isNil(editor():Get("sub"))
		eq(main().hosts[main():CurrentPage()].mini.sub:GetText(), "")
	end)

	it("the live preview follows the subtitle", function()
		local page = open(1)
		Mock.TypeInto(page.sub.edit, "We raid on weekends")
		eq(main().hosts[main():CurrentPage()].mini.sub:GetText(), "We raid on weekends")
	end)

	it("without verified banners the gallery has only the default tile and says why", function()
		local page = open(1)
		eq(#page.tiles, 1)
		eq(page.bannerNote:GetText(), L["ED_BANNER_NONE"])
		isNil(editor():Get("bg"))
	end)

	it("with banners the gallery lists them, a click chooses one, the default tile clears it", function()
		local B = A().Assets.BANNERS
		B[2] = { file = 222 }; B[5] = { file = 555 }
		local page = open(1)
		eq(#page.tiles, 3)
		eq(page.tiles[1].index, nil)
		eq(page.tiles[2].index, 2)
		eq(page.tiles[3].index, 5)
		click(page.tiles[3])
		eq(editor():Get("bg"), 5)
		eq(OL():Draft().bg, 5)
		truthy(page.tiles[3].selected)
		falsy(page.tiles[1].selected)
		click(page.tiles[2])
		eq(editor():Get("bg"), 2)
		click(page.tiles[1])
		isNil(editor():Get("bg"))
		truthy(page.tiles[1].selected)
		B[2], B[5] = nil, nil
		eq(#Mock.errors, 0)
	end)

	it("comes back filled after leaving the step and after Discard changes", function()
		local page = open(1)
		Mock.TypeInto(page.sub.edit, "Friendly raiders")
		editor():GoTo(2)
		editor():GoTo(1)
		eq(page.sub:GetText(), "Friendly raiders")
		editor():Discard()
		eq(page.sub:GetText(), "")
		eq(page.subCount:GetText(), "0 / 60")
	end)
end)

describe("the About page", function()
	it("is the registered page of step 2", function()
		local page = open(2)
		falsy(editor().pages.about.placeholder)
		eq(main().title:GetText(), "About")
		eq(page.descCount:GetText(), "0 / 500")
		eq(page.descLines:GetText(), "0 / 12 lines")
		eq(#Mock.errors, 0)
	end)

	it("typing the description saves the draft and moves both counters", function()
		local page = open(2)
		Mock.TypeInto(page.desc, "We raid on weekends.\nVoice required.")
		eq(editor():Get("desc"), "We raid on weekends.\nVoice required.")
		eq(OL():Draft().desc, "We raid on weekends.\nVoice required.")
		eq(page.descCount:GetText(), "36 / 500")
		eq(page.descLines:GetText(), "2 / 12 lines")
		eq(page.descHint:GetText(), "", "36 characters are enough: no hint")
	end)

	it("the hint about the 30 characters shows below 30 and goes at 30", function()
		local page = open(2)
		Mock.TypeInto(page.desc, chars(29))
		eq(page.descHint:GetText(), "Write at least 30 characters to publish.")
		eq(editor():View().steps[2].status, "bad")
		Mock.TypeInto(page.desc, chars(30))
		eq(page.descHint:GetText(), "")
	end)

	it("more than 500 characters is cut in the box", function()
		local page = open(2)
		Mock.TypeInto(page.desc, chars(650))
		eq(len(editor():Get("desc")), 500)
		eq(len(page.desc:GetText()), 500)
		eq(page.descCount:GetText(), "500 / 500")
	end)

	it("more than 12 lines is cut in the box", function()
		local page = open(2)
		Mock.TypeInto(page.desc, lines(14))
		eq(editor():Get("desc"), lines(12))
		eq(page.desc:GetText(), lines(12))
		eq(page.descLines:GetText(), "12 / 12 lines")
	end)

	it("the placeholder shows only while the description is empty", function()
		local page = open(2)
		truthy(page.descPlaceholder:IsShown())
		Mock.TypeInto(page.desc, "x")
		falsy(page.descPlaceholder:IsShown())
		Mock.TypeInto(page.desc, "")
		truthy(page.descPlaceholder:IsShown())
	end)

	it("choosing the main language saves lang1 and lang, and turns the item green", function()
		local page = open(2)
		eq(editor():View().steps[2].status, "todo")
		pick(page.main, 5)
		eq(editor():Get("lang1"), 5)
		eq(editor():Get("lang"), 16)
		eq(OL():Draft().lang1, 5)
		local s = states(editor():View())
		eq(s.lang, "ok")
		eq(#Mock.errors, 0)
	end)

	it("the other languages wait for a main one, then take any but the main one", function()
		local page = open(2)
		falsy(page.other.enabledState)
		pick(page.main, 1)
		truthy(page.other.enabledState)
		local keys = {}
		for _, item in ipairs(page.other.items) do keys[#keys + 1] = item.key end
		eq(#keys, 8)
		for _, k in ipairs(keys) do truthy(k ~= 1, "the main language is not listed again") end
		pick(page.other, 2)
		pick(page.other, 5)
		eq(editor():Get("lang1"), 1)
		eq(editor():Get("lang"), 1 + 2 + 16)
		pick(page.other, 2)
		eq(editor():Get("lang"), 1 + 16)
		eq(OL():Draft().lang, 17)
	end)

	it("changing the main language keeps the others and drops the old main one", function()
		local page = open(2)
		pick(page.main, 1)
		pick(page.other, 2)
		pick(page.other, 5)
		pick(page.main, 2)
		eq(editor():Get("lang1"), 2)
		eq(editor():Get("lang"), 2 + 16, "German became the main language, English is gone, Italian stays")
		local keys = page.other:GetSelected()
		deepEq(keys, { 5 })
		for _, item in ipairs(page.other.items) do truthy(item.key ~= 2) end
	end)

	it("the preview shows the main language first", function()
		local page = open(2)
		pick(page.main, 5)
		pick(page.other, 1)
		local tags = main().hosts[main():CurrentPage()].mini.tags
		eq(tags[1]:IsShown(), true)
	end)

	it("comes back filled after leaving the step", function()
		local page = open(2)
		pick(page.main, 5)
		Mock.TypeInto(page.desc, "We raid on weekends and chat in voice.")
		editor():GoTo(3)
		editor():GoTo(2)
		eq(page.desc:GetText(), "We raid on weekends and chat in voice.")
		deepEq(page.main:GetSelected(), { 5 })
		editor():Discard()
		eq(page.desc:GetText(), "")
		deepEq(page.main:GetSelected(), {})
		falsy(page.other.enabledState)
	end)

	it("the step status on the left follows: green with a description of 30 characters and a main language", function()
		local page = open(2)
		pick(page.main, 5)
		Mock.TypeInto(page.desc, chars(30))
		eq(editor():View().steps[2].status, "ok")
		local h = main().hosts[main():CurrentPage()]
		truthy(h.stepButtons[2].status == "ok")
	end)
end)
