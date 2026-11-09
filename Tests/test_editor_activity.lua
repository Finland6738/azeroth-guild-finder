-- M3.4: the Activity step of the listing editor. First the rules without frames (EditorModel: the activities in the order
-- picked, at most 3, renumbering; the schedule typed in local time and stored as UTC, round trip with the visitors'
-- conversion BrowseModel.ToLocal, across DST and midnight), then the page on the mock client (UI/EditorSteps.lua) and the
-- checklist.
-- The mock player is "Testchar", Horde, on "Test Realm"; the guild is "Iron Wolves".

local GUILD = "Iron Wolves"
local KEY = "TestRealm|Horde|" .. GUILD

local function A() return AzerothGuildFinder end
local function M() return A().EditorModel end
local function B() return A().BrowseModel end
local function editor() return A().Editor end
local function OL() return A().OwnListing end
local function main() return A().Main end
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })

local MON, TUE, WED, THU, FRI, SAT, SUN = 1, 2, 4, 8, 16, 32, 64

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
local function hm(h, m) return h * 60 + (m or 0) end

describe("the activities (at most 3, in the order picked)", function()
	local function pickAll(...)
		local tags = {}
		for _, id in ipairs({ ... }) do tags = M().ToggleTag(tags, id) end
		return tags
	end

	it("keeps the order picked, not the order of the list", function()
		deepEq(pickAll(6, 1, 5), { 6, 1, 5 })
		eq(M().TagNumber({ 6, 1, 5 }, 6), 1)
		eq(M().TagNumber({ 6, 1, 5 }, 1), 2)
		eq(M().TagNumber({ 6, 1, 5 }, 5), 3)
		isNil(M().TagNumber({ 6, 1, 5 }, 2))
	end)

	it("a fourth one cannot be picked and the list stays as it was", function()
		local tags, result = M().ToggleTag({ 6, 1, 5 }, 2)
		eq(result, "full")
		deepEq(tags, { 6, 1, 5 })
	end)

	it("removing one renumbers the rest and makes room again", function()
		local tags, result = M().ToggleTag({ 6, 1, 5 }, 6)
		eq(result, "removed")
		deepEq(tags, { 1, 5 })
		eq(M().TagNumber(tags, 1), 1)
		eq(M().TagNumber(tags, 5), 2)
		tags, result = M().ToggleTag(tags, 13)
		eq(result, "added")
		deepEq(tags, { 1, 5, 13 })
	end)

	it("does not change the list it is given, and refuses what is not an activity", function()
		local tags = { 2 }
		local out = M().ToggleTag(tags, 3)
		deepEq(tags, { 2 })
		deepEq(out, { 2, 3 })
		local same, result = M().ToggleTag({ 2 }, 14)
		eq(result, "invalid")
		deepEq(same, { 2 })
		_, result = M().ToggleTag({ 2 }, "x")
		eq(result, "invalid")
	end)

	it("reads the activities of the fields as they will be published", function()
		deepEq(M().Tags({ tags = { 6, 1, 5 } }), { 6, 1, 5 })
		deepEq(M().Tags({ tags = { 6, 6, 99, 1, 5, 2 } }), { 6, 1, 5 })
		deepEq(M().Tags({}), {})
	end)
end)

describe("the schedule: local time in the editor, UTC in the listing", function()
	it("a window in a zone east of UTC is stored earlier (Rome in winter, +1 h)", function()
		local p = M().SchedulePatch({ days = MON + TUE, from = hm(20), to = hm(23, 30) }, 60)
		eq(p.t0, hm(19))
		eq(p.t1, hm(22, 30))
		eq(p.days, MON + TUE)
	end)

	it("the same local window is one hour earlier in UTC after the clocks go forward (Rome in summer, +2 h)", function()
		local winter = M().SchedulePatch({ days = MON, from = hm(20), to = hm(23, 30) }, 60)
		local summer = M().SchedulePatch({ days = MON, from = hm(20), to = hm(23, 30) }, 120)
		eq(winter.t0 - summer.t0, 60)
		eq(summer.t0, hm(18))
		eq(summer.t1, hm(21, 30))
	end)

	it("a zone west of UTC stores later (New York in summer, -4 h)", function()
		local p = M().SchedulePatch({ days = FRI, from = hm(21), to = hm(23) }, -240)
		eq(p.t0, hm(1))
		eq(p.t1, hm(3))
		eq(p.days, SAT, "01:00 UTC on Saturday is still Friday evening in New York")
	end)

	it("a window that starts after midnight UTC moves the days back", function()
		local p = M().SchedulePatch({ days = MON, from = hm(0, 30), to = hm(2) }, 120)
		eq(p.t0, hm(22, 30))
		eq(p.t1, 0)
		eq(p.days, SUN, "Monday 00:30 in Rome is Sunday 22:30 UTC")
	end)

	it("a window across local midnight stays one window (end before start)", function()
		local p = M().SchedulePatch({ days = SAT, from = hm(22), to = hm(1) }, 60)
		eq(p.t0, hm(21))
		eq(p.t1, 0)
		eq(p.days, SAT)
		local s = M().Schedule({ days = p.days, t0 = p.t0, t1 = p.t1 }, 60)
		eq(s.from, hm(22))
		eq(s.to, hm(1))
	end)

	it("round trip with the visitor conversion (BrowseModel.ToLocal), for many zones, days and windows", function()
		local offsets = { -480, -300, -240, 0, 60, 120, 330, 345, 540, 780 }
		local windows = { { 20, 23.5 }, { 0.5, 2 }, { 22, 1 }, { 6, 9 }, { 23, 23.5 }, { 12, 0 } }
		local masks = { MON, MON + FRI, SUN, 127, SAT + SUN }
		for _, off in ipairs(offsets) do
			for _, w in ipairs(windows) do
				for _, days in ipairs(masks) do
					local from, to = w[1] * 60, w[2] * 60
					local p = M().SchedulePatch({ days = days, from = from, to = to }, off)
					-- what a visitor in the same zone sees is exactly what the Guild Master typed
					local d, l0, l1 = B().ToLocal(p.days or 0, p.t0, p.t1, off)
					eq(d, days, ("days off=%d"):format(off))
					eq(l0, from)
					eq(l1, to)
					-- and the editor reads it back the same
					local s = M().Schedule({ days = p.days, t0 = p.t0, t1 = p.t1 }, off)
					eq(s.days, days)
					eq(s.from, from)
					eq(s.to, to)
					-- the stored values are valid minutes UTC
					truthy(p.t0 >= 0 and p.t0 <= 1439 and p.t1 >= 0 and p.t1 <= 1439)
				end
			end
		end
	end)

	it("a visitor in another zone sees the converted window (Rome 20:00-23:30 is 14:00-17:30 in New York in summer)", function()
		local p = M().SchedulePatch({ days = WED, from = hm(20), to = hm(23, 30) }, 120)
		local d, l0, l1 = B().ToLocal(p.days, p.t0, p.t1, -240)
		eq(d, WED)
		eq(l0, hm(14))
		eq(l1, hm(17, 30))
	end)

	it("all day keeps the days and stores the same minute twice", function()
		local p = M().SchedulePatch({ days = SAT + SUN, allDay = true }, 120)
		eq(p.t0, p.t1)
		eq(p.days, SAT + SUN)
		local s = M().Schedule({ days = p.days, t0 = p.t0, t1 = p.t1 }, 120)
		truthy(s.allDay)
		eq(s.days, SAT + SUN)
	end)

	it("a start equal to the end is the whole day, no days or no times clear the fields", function()
		local p = M().SchedulePatch({ days = MON, from = hm(10), to = hm(10) }, 60)
		eq(p.t0, p.t1)
		p = M().SchedulePatch({ days = 0 }, 60)
		eq(p.days, false)
		eq(p.t0, false)
		eq(p.t1, false)
		p = M().SchedulePatch({ days = MON, from = hm(20) }, 60)
		eq(p.t0, false, "a start without an end stores no times")
		eq(p.days, MON)
		p = M().SchedulePatch({ days = 999, from = 1, to = 2 }, 0)
		eq(p.days, false, "a bad mask is dropped")
	end)

	it("the days alone are stored as typed (no times, nothing to move)", function()
		local p = M().SchedulePatch({ days = MON + WED }, 300)
		eq(p.days, MON + WED)
		local s = M().Schedule({ days = MON + WED }, 300)
		eq(s.days, MON + WED)
		falsy(s.hasTime)
	end)

	it("the time menus offer every 30 minutes and can leave one out", function()
		local all = M().TimeChoices()
		eq(#all, 48)
		eq(all[1].key, 0)
		eq(all[1].text, "00:00")
		eq(all[48].text, "23:30")
		eq(#M().TimeChoices(hm(20)), 47)
	end)
end)

describe("the checklist and the Activity step", function()
	local function full(extra)
		local f = { sub = "Raiders", desc = string.rep("a", 40), lang1 = 1, lang = 1, emb = { t = 1 }, tags = { 1 }, pace = 2,
			rec = 0 }
		for k, v in pairs(extra or {}) do if v == "nil" then f[k] = nil else f[k] = v end end
		return f
	end

	it("the commitment is required: nothing is todo, any of the three is ok", function()
		eq(states(M().View(full({ pace = "nil" }), ctx())).pace, "todo")
		for v = 1, 3 do eq(states(M().View(full({ pace = v }), ctx())).pace, "ok") end
		eq(states(M().View(full({ pace = 9 }), ctx())).pace, "todo", "an unknown commitment is not published")
	end)

	it("1 to 3 activities are ok, none is todo, more than 3 is bad", function()
		eq(states(M().View(full({ tags = "nil" }), ctx())).tags, "todo")
		eq(states(M().View(full({ tags = { 4, 1, 3 } }), ctx())).tags, "ok")
		eq(states(M().View(full({ tags = { 1, 2, 3, 4 } }), ctx())).tags, "bad")
	end)

	it("step 3 is green with a commitment and an activity, and sends the Guild Master there when not", function()
		eq(M().View(full(), ctx()).steps[3].status, "ok")
		local view = M().View(full({ pace = "nil", tags = "nil" }), ctx())
		eq(view.steps[3].status, "todo")
		view = M().View(full({ pace = "nil", emb = "nil", sub = "nil", desc = "nil", lang1 = "nil", lang = "nil" }), ctx())
		eq(view.first.step, 1)
		view = M().View(full({ pace = "nil" }), ctx())
		eq(view.first.id, "pace")
		eq(view.first.step, 3)
	end)

	it("the days and the times are optional", function()
		eq(M().View(full(), ctx()).steps[3].status, "ok")
		eq(M().View(full({ days = MON, t0 = 60, t1 = 120 }), ctx()).steps[3].status, "ok")
	end)
end)

local function open(step)
	Mock.guild.Set{ name = GUILD, myRank = 0, members = { { name = "Jaina", rank = 1 } } }
	main():Show()
	editor():GoTo(step or 3)
	A().EditorSteps.offset = function() return 120 end
	return editor().pages.activity.frame
end
local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end
local function pick(sel, key) sel:Choose(key) end

describe("the Activity page", function()
	it("is the registered page of step 3", function()
		local page = open()
		falsy(editor().pages.activity.placeholder)
		eq(main().title:GetText(), "Activity")
		eq(page.actCount:GetText(), "0 / 3")
		eq(#Mock.errors, 0)
	end)

	it("the commitment: one choice, saved, explained, and the checklist follows", function()
		local page = open()
		eq(states(editor():View()).pace, "todo")
		eq(page.paceNote:GetText(), L["ED_PACE_PICK"])
		click(page.pace.segments[3])
		eq(editor():Get("pace"), 3)
		eq(OL():Draft().pace, 3)
		eq(page.paceNote:GetText(), L["PACE_3_TIP"])
		eq(states(editor():View()).pace, "ok")
		click(page.pace.segments[1])
		eq(editor():Get("pace"), 1)
		eq(page.pace:GetSelected(), 1)
		eq(#Mock.errors, 0)
	end)

	it("picking activities numbers them in the order picked", function()
		local page = open()
		click(page.chips[6])
		click(page.chips[1])
		deepEq(editor():Get("tags"), { 6, 1 })
		eq(page.chips[6]:GetLabel(), "1  World PvP")
		eq(page.chips[1]:GetLabel(), "2  Raids")
		eq(page.chips[2]:GetLabel(), "Dungeons")
		eq(page.actCount:GetText(), "2 / 3")
		deepEq(OL():Draft().tags, { 6, 1 })
		eq(states(editor():View()).tags, "ok")
	end)

	it("a fourth cannot be picked: the others are greyed out with the reason", function()
		local page = open()
		click(page.chips[6]); click(page.chips[1]); click(page.chips[5])
		eq(page.actCount:GetText(), "3 / 3")
		for id, chip in pairs(page.chips) do
			if id ~= 6 and id ~= 1 and id ~= 5 then
				falsy(chip:IsChipEnabled(), "chip " .. id)
				eq(chip.reason, L["ED_ACT_FULL"])
			else
				truthy(chip:IsChipEnabled())
			end
		end
		click(page.chips[2])
		deepEq(editor():Get("tags"), { 6, 1, 5 })
		falsy(page.chips[2].selected)
		-- the safety net: a toggle that gets through is refused with a message
		page.chips[2]:SetSelected(true)
		deepEq(editor():Get("tags"), { 6, 1, 5 })
		falsy(page.chips[2].selected)
		eq(#Mock.errors, 0)
	end)

	it("removing one renumbers the rest and opens the others again", function()
		local page = open()
		click(page.chips[6]); click(page.chips[1]); click(page.chips[5])
		click(page.chips[6])
		deepEq(editor():Get("tags"), { 1, 5 })
		eq(page.chips[1]:GetLabel(), "1  Raids")
		eq(page.chips[5]:GetLabel(), "2  Battlegrounds")
		eq(page.chips[6]:GetLabel(), "World PvP")
		truthy(page.chips[2]:IsChipEnabled())
		click(page.chips[2])
		deepEq(editor():Get("tags"), { 1, 5, 2 })
		click(page.chips[1]); click(page.chips[5]); click(page.chips[2])
		isNil(editor():Get("tags"))
		eq(states(editor():View()).tags, "todo")
	end)

	it("days and a window are typed in local time and saved as UTC", function()
		local page = open()
		page.days:SetMask(MON + TUE + WED)
		eq(editor():Get("days"), MON + TUE + WED)
		pick(page.from, hm(20))
		isNil(editor():Get("t0"), "half a window is not saved")
		eq(page.whenHelp:GetText(), L["ED_WHEN_ONE"])
		pick(page.to, hm(23, 30))
		eq(editor():Get("t0"), hm(18))
		eq(editor():Get("t1"), hm(21, 30))
		eq(OL():Draft().t0, hm(18))
		eq(page.whenHelp:GetText(), "Players see it in their own time zone · 18:00–21:30 UTC")
		deepEq(page.from:GetSelected(), { hm(20) })
		deepEq(page.to:GetSelected(), { hm(23, 30) })
		eq(page.days:GetMask(), MON + TUE + WED)
	end)

	it("a window after local midnight moves the days in UTC and the page still shows what was typed", function()
		local page = open()
		page.days:SetMask(MON)
		pick(page.from, hm(0, 30))
		pick(page.to, hm(2))
		eq(editor():Get("t0"), hm(22, 30))
		eq(editor():Get("days"), SUN)
		eq(page.days:GetMask(), MON)
		deepEq(page.from:GetSelected(), { hm(0, 30) })
	end)

	it("the start is not offered as the end, and All day stores the same minute twice", function()
		local page = open()
		pick(page.from, hm(20))
		for _, item in ipairs(page.to.items) do truthy(item.key ~= hm(20)) end
		page.allDay:SetChecked(true)
		eq(editor():Get("t0"), editor():Get("t1"))
		truthy(page.allDay:GetChecked())
		falsy(page.from.enabledState)
		page.allDay:SetChecked(false)
		isNil(editor():Get("t0"))
		isNil(editor():Get("t1"))
		truthy(page.from.enabledState)
	end)

	it("comes back filled after leaving the step and after Discard changes", function()
		local page = open()
		click(page.pace.segments[2]); click(page.chips[3])
		page.days:SetMask(SAT)
		pick(page.from, hm(18)); pick(page.to, hm(20))
		editor():GoTo(2)
		editor():GoTo(3)
		eq(page.pace:GetSelected(), 2)
		eq(page.chips[3]:GetLabel(), "1  Leveling")
		eq(page.days:GetMask(), SAT)
		deepEq(page.from:GetSelected(), { hm(18) })
		editor():Discard()
		isNil(page.pace:GetSelected())
		eq(page.chips[3]:GetLabel(), "Leveling")
		eq(page.days:GetMask(), 0)
		deepEq(page.from:GetSelected(), {})
		eq(page.actCount:GetText(), "0 / 3")
		eq(#Mock.errors, 0)
	end)

	it("the step turns green with a commitment and an activity", function()
		local page = open()
		eq(editor():View().steps[3].status, "todo")
		click(page.pace.segments[1])
		eq(editor():View().steps[3].status, "todo")
		click(page.chips[1])
		eq(editor():View().steps[3].status, "ok")
	end)

	it("the local offset is the one of BrowseModel (no second time-zone logic)", function()
		A().EditorSteps.offset = nil
		eq(A().EditorSteps.LocalOffset(), B().LocalOffset(A().Compat.ServerTime()))
	end)
end)
