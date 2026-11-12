-- M4.4: the Applications tab on the mock client (UI/Applications.lua): who has it, the cards of the pending applications and
-- the lines of the history, the counters and the badge, Invite (the game's invite, the offline answer, the fallback), Decline
-- with its question, Whisper, scrolling, the notification options in the panel and in Settings, the line in My Guild and the
-- panel following the role while it is open. The view model is tested without frames in test_apps_model.lua and the decisions
-- in test_decisions.lua.
-- The mock player is "Testchar", Horde Orc Warrior 60 on "Test Realm".

local GUILD = "Aurora"
local KEY = "TestRealm|Horde|" .. GUILD
local DAY = 86400

local function A() return AzerothGuildFinder end
local function main() return A().Main end
local function panel() return A().AppsPanel end
local function host() return panel().host end
local function Inbox() return A().Inbox end
local function snack() return A().Widgets.Snackbar.Current() end
local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end

local function putListing()
	local t = GetServerTime()
	assert(A().Catalog:PutSummary({ k = KEY, rev = 4, upd = t - 3600, first = 1760000000, own = "0badc0de", sub = "Friendly raiders",
		lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 31, t0 = 1140, t1 = 1380, rec = 1, apps = true,
		want = { [1] = 4, [5] = 2 }, newb = true, minL = 30 }))
	assert(A().Catalog:PutDetail({ k = KEY, rev = 4, desc = "We raid on weekends.", disc = "wolves1", cont = { "Thrall" }, note = "x" }))
end

local RANK = { member = 3, officer = 1, gm = 0 }
local function setRole(role)
	if role == "none" then Mock.guild.Leave(); return end
	Mock.guild.Set{ name = GUILD, myRank = RANK[role], members = { { name = "Thrall", rank = 0 }, { name = "Jaina", rank = 1 } } }
	A().Role:Refresh()
end

local function receive(id, extra)
	local t = GetServerTime()
	local r = { id = id, k = KEY, state = "received", stateRev = 2, at = t - 2 * 3600, upd = t - 2 * 3600,
		who = "Elarin-TestRealm", cls = 8, race = 8, lvl = 32, ilvl = 41, roles = 8 }
	for k, v in pairs(extra or {}) do if v == "nil" then r[k] = nil else r[k] = v end end
	return assert(Inbox():Receive(r))
end

-- The three applications of mockup 04: Elarin (Mage, 2 h ago), Mirelle (Priest, yesterday), Brogan (Warrior, 3 days ago).
local function mockupThree()
	local t = GetServerTime()
	receive("00000001", { who = "Elarin-TestRealm", cls = 8, race = 8, lvl = 32, ilvl = "nil", roles = 8, at = t - 2 * 3600, upd = t - 2 * 3600 })
	receive("00000002", { who = "Mirelle-TestRealm", cls = 5, race = 5, lvl = 60, ilvl = 58, roles = 2, at = t - DAY - 3600, upd = t - DAY - 3600 })
	receive("00000003", { who = "Brogan-TestRealm", cls = 1, race = 2, lvl = 17, ilvl = "nil", roles = "nil", at = t - 3 * DAY, upd = t - 3 * DAY })
end

local function openPanel(role)
	setRole(role or "officer")
	putListing()
	main():Show()
	main():Select("Applications")
	return host()
end

local function row(i) return host().pendRows[i] end
local function histRow(i) return host().histRows[i] end
local function shownRows()
	local n = 0
	for _, f in ipairs(host().pendRows) do if f:IsShown() then n = n + 1 end end
	return n
end

local typed
local function stubChat()
	typed = nil
	_G.ChatFrame_OpenChat = function(text) typed = text end
end


describe("who has the Applications tab (APP-07)", function()
	it("the Guild Master and the officers of a listed guild have it; a member and a character without a guild do not", function()
		putListing()
		setRole("officer"); main():Show()
		deepEq(main().book:Tabs(), { "Settings", "MyGuild", "Applications" })
		setRole("gm")
		deepEq(main().book:Tabs(), { "Settings", "MyGuild", "Applications" })
		setRole("member")
		deepEq(main().book:Tabs(), { "Settings", "MyGuild" })
		setRole("none")
		deepEq(main().book:Tabs(), { "Settings", "FindGuild", "MyApplication" })
	end)

	it("a Guild Master whose guild has no listing has no Applications tab", function()
		setRole("gm"); main():Show()
		deepEq(main().book:Tabs(), { "Settings", "CreateListing" })
	end)

	it("the panel itself shows nothing to a member even if its page were reached", function()
		openPanel("officer")
		receive("00000001")
		setRole("member")
		local view = panel():Refresh() or panel():View()
		eq(view.visible, false)
		eq(#view.rows, 0)
		eq(panel():PendingCount(), 0, "no badge for a member")
		eq(main():GetPendingCount(), 0)
		deepEq({ panel():Invite("00000001") }, { false, "role" })
		eq(Inbox():Get(KEY, "00000001").state, "received")
	end)
end)

describe("the pending cards", function()
	it("show the three applications of mockup 04: class, name, roles, level, race, item level, time, status", function()
		openPanel("officer")
		mockupThree()
		panel():Refresh()
		eq(shownRows(), 3)
		eq(row(1).name:GetText(), "Elarin")
		eq(row(1).meta:GetText(), "Mage · Level 32 · Troll  ·  iLvl —  ·  2 h ago")
		eq(row(1).tag:GetText(), "RECEIVED")
		eq(row(1).icon.class, "MAGE")
		eq(row(2).name:GetText(), "Mirelle")
		eq(row(2).meta:GetText(), "Priest · Level 60 · Undead  ·  iLvl 58  ·  yesterday")
		eq(row(2).icon.class, "PRIEST")
		eq(row(3).name:GetText(), "Brogan")
		eq(row(3).meta:GetText(), "Warrior · Level 17 · Orc  ·  iLvl —  ·  3 days ago")
		eq(row(3).tag:GetText(), "EXPIRES IN 11 DAYS")
		eq(row(1).badges[1].role, "ranged")
		eq(row(2).badges[1].role, "healer")
		eq(row(3).badges[1] == nil or not row(3).badges[1]:IsShown(), true, "no roles ticked: no badge")
		for i = 1, 3 do
			eq(row(i).invite:GetLabel(), "Invite")
			truthy(row(i).invite:IsEnabled())
			truthy(row(i).decline:IsEnabled())
			truthy(row(i).whisper:IsEnabled())
		end
		eq(#Mock.errors, 0)
	end)

	it("the left page: the guild, the counters, the tabs with the count and the three options", function()
		openPanel("gm")
		mockupThree()
		receive("00000009", { state = "accepted", stateRev = 3, by = "Lyryn", who = "Tharok-TestRealm", cls = 7, lvl = 41 })
		panel():Refresh()
		local h = host()
		eq(h.guild:GetText(), GUILD)
		eq(h.roleLine:GetText(), "YOU ARE THE GUILD MASTER")
		eq(h.cPending.number:GetText(), "3")
		eq(h.cAccepted.number:GetText(), "1")
		eq(h.cPending.label:GetText(), "Pending")
		eq(h.cAccepted.label:GetText(), "Accepted · 30 days")
		eq(h.seg.segments.pending.text:GetText(), "Pending (3)")
		eq(h.seg.segments.history.text:GetText(), "History")
		eq(h.seg:GetSelected(), "pending")
		eq(main().title:GetText(), "Pending applications")
		eq(main().statusText:GetText(), "3 pending · shared with the officers of your guild")
		eq(h.expiry:GetText(), "Applications expire after 14 days")
		setRole("officer")
		A().Bus:Emit("ROLE_CHANGED")
		main():Select("Applications")
		panel():Refresh()
		eq(host().roleLine:GetText(), "YOU ARE AN OFFICER")
	end)

	it("the rail badge and the minimap number follow the pending count", function()
		openPanel("officer")
		eq(main().badges.Applications or 0, 0)
		mockupThree()
		eq(main().badges.Applications, 3)
		eq(main():GetPendingCount(), 3)
		Inbox():Decide(KEY, "00000001", "declined", "Testchar")
		eq(main().badges.Applications, 2)
		eq(main():GetPendingCount(), 2)
	end)

	it("an empty list says what to expect", function()
		openPanel("officer")
		panel():Refresh()
		eq(shownRows(), 0)
		truthy(host().empty:IsShown())
		eq(host().empty.title:GetText(), "No pending applications")
		eq(host().foot:GetText(), "")
	end)

	it("an application the officer has not seen since the last visit carries the NEW tag and a gold edge", function()
		openPanel("officer")
		main():Select("Settings")   -- leaving the tab saves the visit: the last visit is set after it
		A().Config:Set("char.ui.appsSeenAt", GetServerTime() - DAY)
		mockupThree()   -- the first is 2 h old (new), the others older than the last visit
		main():Select("Applications")
		panel():Refresh()
		truthy(row(1).new:IsShown())
		falsy(row(2).new:IsShown())
		falsy(row(3).new:IsShown())
	end)

	it("leaving the tab remembers the visit: nothing is new the next time", function()
		openPanel("officer")
		A().Config:Set("char.ui.appsSeenAt", GetServerTime() - DAY)
		mockupThree()
		main():Select("Settings")
		local seen = A().Config:Get("char.ui.appsSeenAt")
		truthy(seen >= GetServerTime() - 2)
		main():Select("Applications")
		falsy(row(1).new:IsShown())
	end)
end)

describe("the history", function()
	it("one line per closed application: class, name and level, the status and who decided", function()
		openPanel("officer")
		local t = GetServerTime()
		receive("00000001", { who = "Tharok-TestRealm", cls = 7, lvl = 41, state = "accepted", stateRev = 3, by = "Lyryn", upd = t - 5 * DAY, at = t - 8 * DAY })
		receive("00000002", { who = "Velis-TestRealm", cls = 4, lvl = 12, state = "declined", stateRev = 3, by = "Kaelthar", upd = t - 3 * DAY, at = t - 8 * DAY })
		receive("00000003", { who = "Nym-TestRealm", cls = 11, lvl = 25, state = "withdrawn", stateRev = 3, upd = t - 2 * DAY, at = t - 8 * DAY })
		receive("00000004")   -- pending: not here
		click(host().seg.segments.history)
		eq(host().seg:GetSelected(), "history")
		eq(main().title:GetText(), "Recent history")
		truthy(host().histCard:IsShown())
		eq(histRow(1).text:GetText(), "Nym · Druid 25")
		eq(histRow(1).tag:GetText(), "WITHDRAWN")
		eq(histRow(1).by:GetText():sub(1, 14), "by the player ")
		eq(histRow(2).text:GetText(), "Velis · Rogue 12")
		eq(histRow(2).tag:GetText(), "DECLINED")
		eq(histRow(2).by:GetText():sub(1, 11), "by Kaelthar")
		eq(histRow(3).text:GetText(), "Tharok · Shaman 41")
		eq(histRow(3).tag:GetText(), "ACCEPTED")
		eq(histRow(3).by:GetText():sub(1, 8), "by Lyryn")
		falsy(histRow(4):IsShown())
		falsy(row(1):IsShown(), "no pending card on this tab")
		click(host().seg.segments.pending)
		truthy(row(1):IsShown())
		falsy(host().histCard:IsShown())
	end)

	it("an empty history says so", function()
		openPanel("officer")
		panel():SetTab("history")
		truthy(host().empty:IsShown())
		eq(host().empty.title:GetText(), "Nothing in the history yet")
	end)
end)

describe("Invite", function()
	it("the game's invite goes out: the card leaves Pending for the history, the counters follow", function()
		openPanel("officer")
		mockupThree()
		panel():Refresh()
		click(row(1).invite)
		eq(snack(), "Guild invite sent to Elarin.")
		eq(Inbox():Get(KEY, "00000001").state, "accepted")
		eq(Inbox():Get(KEY, "00000001").by, "Testchar")
		deepEq(Mock.guild.invites, { "Elarin-TestRealm" })
		eq(shownRows(), 2)
		eq(row(1).name:GetText(), "Mirelle")
		eq(host().cPending.number:GetText(), "2")
		eq(host().cAccepted.number:GetText(), "1")
		eq(host().seg.segments.pending.text:GetText(), "Pending (2)")
		eq(main().badges.Applications, 2)
		eq(#Mock.errors, 0)
	end)

	it("the player is offline: the panel says so and the card stays", function()
		openPanel("officer")
		mockupThree()
		Mock.guild.inviteReply = "offline"
		panel():Refresh()
		click(row(1).invite)
		eq(snack(), "Elarin is offline. Try again later.")
		eq(Inbox():Get(KEY, "00000001").state, "received")
		eq(shownRows(), 3)
		truthy(row(1).invite:IsEnabled(), "the officer can try again")
		Mock.guild.inviteReply = "ok"
		click(row(1).invite)
		eq(Inbox():Get(KEY, "00000001").state, "accepted")
	end)

	it("the game refuses with its own words", function()
		openPanel("officer")
		mockupThree()
		Mock.guild.inviteReply = "inguild"
		panel():Refresh()
		click(row(2).invite)
		eq(snack(), "The game did not send the invite to Mirelle: Mirelle is already in a guild.")
		eq(Inbox():Get(KEY, "00000002").state, "received")
	end)

	it("while the game is quiet the card says INVITING... and cannot be pressed twice", function()
		openPanel("officer")
		mockupThree()
		Mock.guild.inviteReply = "silent"
		panel():Refresh()
		click(row(1).invite)
		eq(row(1).tag:GetText(), "INVITING...")
		falsy(row(1).invite:IsEnabled())
		falsy(row(1).decline:IsEnabled())
		Mock.Advance(4)
		eq(Inbox():Get(KEY, "00000001").state, "accepted")
		eq(shownRows(), 2)
		eq(snack(), "Guild invite sent to Elarin.")
	end)

	it("with the invite blocked the card falls back to /ginvite and 'Mark as invited'", function()
		openPanel("officer")
		mockupThree()
		stubChat()
		Mock.guild.inviteReply = "blocked"
		panel():Refresh()
		click(row(1).invite)
		eq(typed, "/ginvite Elarin-TestRealm ")
		eq(snack(), "Press Enter to send the invite to Elarin, then press Mark as invited.")
		eq(Inbox():Get(KEY, "00000001").state, "received")
		eq(row(1).invite:GetLabel(), "Mark as invited")
		truthy(row(1).invite:IsEnabled())
		click(row(1).invite)
		eq(Inbox():Get(KEY, "00000001").state, "accepted")
		eq(shownRows(), 2)
		_G.ChatFrame_OpenChat = nil
	end)

	it("with no chat box either the officer is told to invite by hand", function()
		openPanel("officer")
		mockupThree()
		_G.ChatFrame_OpenChat = nil
		Mock.guild.inviteReply = "blocked"
		panel():Refresh()
		click(row(1).invite)
		contains(snack(), "Invite Elarin yourself")
		eq(row(1).invite:GetLabel(), "Mark as invited")
	end)

	it("an application another officer closed meanwhile says it changed", function()
		openPanel("officer")
		mockupThree()
		panel():Refresh()
		local id = row(1).id
		-- the card is still drawn when the other officer's decision arrives and the click comes first
		Inbox():Merge(KEY, { id = id, k = KEY, state = "declined", stateRev = 3, at = GetServerTime() - 7200, upd = GetServerTime(),
			who = "Elarin-TestRealm", cls = 8, race = 8, lvl = 32, by = "Jaina" })
		panel():Invite(id)
		eq(snack(), "This application changed meanwhile: another officer decided, or it expired.")
		eq(#Mock.guild.invites, 0)
	end)
end)

describe("Decline", function()
	it("asks first; Cancel keeps the application", function()
		openPanel("officer")
		mockupThree()
		panel():Refresh()
		click(row(2).decline)
		truthy(host().confirm:IsShown())
		eq(host().confirm.text:GetText(), "Decline the application of Mirelle? The player learns it the next time they meet an officer of the guild online.")
		click(host().confirm.no)
		falsy(host().confirm:IsShown())
		eq(Inbox():Get(KEY, "00000002").state, "received")
		eq(shownRows(), 3)
	end)

	it("the answer declines: the state changes, the card goes to the history, the counters follow", function()
		openPanel("officer")
		mockupThree()
		panel():Refresh()
		click(row(2).decline)
		click(host().confirm.yes)
		falsy(host().confirm:IsShown())
		local rec = Inbox():Get(KEY, "00000002")
		eq(rec.state, "declined")
		eq(rec.by, "Testchar")
		eq(snack(), "Application of Mirelle declined. The other officers see it too.")
		eq(shownRows(), 2)
		eq(host().cPending.number:GetText(), "2")
		eq(main().badges.Applications, 2)
		panel():SetTab("history")
		eq(histRow(1).text:GetText(), "Mirelle · Priest 60")
		eq(histRow(1).tag:GetText(), "DECLINED")
		eq(histRow(1).by:GetText():find("by Testchar", 1, true), 1)
	end)

	it("the question closes when the tab changes or the window closes", function()
		openPanel("officer")
		mockupThree()
		panel():Refresh()
		click(row(1).decline)
		truthy(host().confirm:IsShown())
		panel():SetTab("history")
		falsy(host().confirm:IsShown())
		panel():SetTab("pending")
		click(row(1).decline)
		main():Hide()
		main():Show()
		falsy(host().confirm:IsShown())
	end)

	it("a question about an application that closed meanwhile does not decline anything", function()
		openPanel("officer")
		mockupThree()
		panel():Refresh()
		click(row(1).decline)
		Inbox():Withdraw(KEY, "00000001", "Elarin-TestRealm")
		click(host().confirm.yes)
		eq(Inbox():Get(KEY, "00000001").state, "withdrawn")
		eq(snack(), "This application changed meanwhile: another officer decided, or it expired.")
	end)
end)

describe("Whisper", function()
	it("opens the chat box with /w Name-Realm", function()
		openPanel("officer")
		mockupThree()
		stubChat()
		panel():Refresh()
		click(row(2).whisper)
		eq(typed, "/w Mirelle-TestRealm ")
		panel():SetTab("history")
		_G.ChatFrame_OpenChat = nil
	end)

	it("says so when the chat box cannot be opened", function()
		openPanel("officer")
		mockupThree()
		_G.ChatFrame_OpenChat = nil
		panel():Refresh()
		click(row(1).whisper)
		eq(snack(), "The chat box could not be opened for this name.")
	end)
end)

describe("a long list", function()
	local function many(n)
		local t = GetServerTime()
		for i = 1, n do
			receive(("%08x"):format(i), { who = ("Player%02d-TestRealm"):format(i), at = t - i * 600, upd = t - i * 600 })
		end
	end

	it("shows six cards and scrolls with the wheel, one card at a time", function()
		openPanel("officer")
		many(10)
		panel():Refresh()
		eq(shownRows(), 6)
		eq(row(1).name:GetText(), "Player01")
		eq(host().foot:GetText(), "1–6 of 10 · scroll for more")
		Mock.RunScript(host().list, "OnMouseWheel", -1)
		eq(row(1).name:GetText(), "Player02")
		eq(row(6).name:GetText(), "Player07")
		eq(host().foot:GetText(), "2–7 of 10 · scroll for more")
		for _ = 1, 9 do Mock.RunScript(host().list, "OnMouseWheel", -1) end
		eq(row(1).name:GetText(), "Player05")
		eq(row(6).name:GetText(), "Player10")
		Mock.RunScript(host().list, "OnMouseWheel", 1)
		eq(row(1).name:GetText(), "Player04")
		for _ = 1, 9 do Mock.RunScript(host().list, "OnMouseWheel", 1) end
		eq(row(1).name:GetText(), "Player01")
	end)

	it("the list returns to the top when the tab is shown again", function()
		openPanel("officer")
		many(10)
		panel():Refresh()
		Mock.RunScript(host().list, "OnMouseWheel", -1)
		main():Select("Settings")
		main():Select("Applications")
		eq(row(1).name:GetText(), "Player01")
	end)

	it("a decision when the list is scrolled to the end keeps the window valid", function()
		openPanel("officer")
		many(7)
		panel():Refresh()
		Mock.RunScript(host().list, "OnMouseWheel", -1)
		eq(row(6).name:GetText(), "Player07")
		click(row(6).decline)
		click(host().confirm.yes)
		eq(shownRows(), 6)
		eq(row(1).name:GetText(), "Player01")
	end)

	it("the history scrolls three lines at a time", function()
		openPanel("officer")
		local t = GetServerTime()
		for i = 1, 20 do
			receive(("%08x"):format(i), { who = ("Old%02d-TestRealm"):format(i), state = "declined", stateRev = 3, by = "Jaina",
				at = t - 9 * DAY, upd = t - i * 3600 })
		end
		panel():SetTab("history")
		eq(histRow(1).text:GetText(), "Old01 · Mage 32")
		eq(host().foot:GetText(), "1–14 of 20 · scroll for more")
		Mock.RunScript(host().list, "OnMouseWheel", -1)
		eq(histRow(1).text:GetText(), "Old04 · Mage 32")
		eq(host().foot:GetText(), "4–17 of 20 · scroll for more")
	end)
end)

describe("the notification options", function()
	it("are on the left page with the saved values; a switch saves and tells the Bus", function()
		openPanel("officer")
		local heard = {}
		A().Bus:On("NOTIFY_OPTIONS_CHANGED", function(key, value) heard[#heard + 1] = key .. "=" .. tostring(value) end)
		local sw = host().options
		eq(sw.notifyIcon.label:GetText(), "Notification icon on screen")
		eq(sw.onlyWhenPending.label:GetText(), "Only when something is pending")
		eq(sw.sound.label:GetText(), "Sound on new application")
		eq(sw.notifyIcon:GetChecked(), true)
		eq(sw.onlyWhenPending:GetChecked(), false)
		eq(sw.sound:GetChecked(), true)
		click(sw.sound)
		eq(A().Config:Get("account.settings.sound"), false)
		click(sw.onlyWhenPending)
		eq(A().Config:Get("account.settings.onlyWhenPending"), true)
		deepEq(heard, { "sound=false", "onlyWhenPending=true" })
	end)

	it("Settings has the same switches for an officer, in step with the panel, and none for a member", function()
		openPanel("officer")
		main():Select("Settings")
		local h = main().hosts.Settings
		truthy(h.notify:IsShown())
		eq(h.notifySwitches.sound:GetChecked(), true)
		click(h.notifySwitches.sound)
		eq(A().Config:Get("account.settings.sound"), false)
		main():Select("Applications")
		eq(host().options.sound:GetChecked(), false, "the panel shows the new value")
		click(host().options.notifyIcon)
		main():Select("Settings")
		eq(h.notifySwitches.notifyIcon:GetChecked(), false)
		setRole("member")
		main():Hide()
		main():Show()
		main():Select("Settings")
		falsy(h.notify:IsShown(), "a member has no notifications")
		eq(#Mock.errors, 0)
	end)
end)

describe("My Guild", function()
	it("tells an officer how many applications wait, and opens the tab", function()
		setRole("officer")
		putListing()
		main():Show()
		local h = main().hosts.MyGuild
		eq(h.apps.text:GetText(), "No application is waiting. Open the Applications tab.")
		receive("00000001")
		eq(h.apps.text:GetText(), "1 application is waiting. Open the Applications tab.")
		receive("00000002", { who = "Mirelle-TestRealm" })
		eq(h.apps.text:GetText(), "2 applications are waiting. Open the Applications tab.")
		click(h.apps)
		eq(main():CurrentPage(), "Applications")
	end)
end)

describe("the panel follows the role while it is open", function()
	it("an officer who loses the rank starts over on My Guild and loses the badge", function()
		openPanel("officer")
		mockupThree()
		eq(main().badges.Applications, 3)
		setRole("member")
		eq(main():CurrentTab(), "MyGuild")
		eq(main().badges.Applications or 0, 0)
		eq(#Mock.errors, 0)
	end)

	it("a change of the inbox while the tab is open redraws it", function()
		openPanel("officer")
		eq(shownRows(), 0)
		receive("00000001")
		eq(shownRows(), 1)
		Inbox():Withdraw(KEY, "00000001", "Elarin-TestRealm")
		eq(shownRows(), 0)
	end)

	it("the text of the time moves on by itself while the tab stays open", function()
		openPanel("officer")
		receive("00000001", { at = GetServerTime() - 30, upd = GetServerTime() - 30 })
		panel():Refresh()
		eq(row(1).meta:GetText():find("just now", 1, true) ~= nil, true)
		Mock.Advance(3 * 3600 + 30)
		eq(row(1).meta:GetText():find("3 h ago", 1, true) ~= nil, true)
	end)
end)
