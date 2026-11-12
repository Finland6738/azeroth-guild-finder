-- M4.1: the applicant's flow on the mock client: the Apply button of the cards and of the guild page in every state of
-- SPEC-05 §4 (with its reason on the button and in the tooltip), the confirmation with the optional roles of the class,
-- and the My Application tab (status, the road, Withdraw with its question, View guild, the empty state, the dot).
-- The mock player is "Testchar", a Horde Warrior of level 60 on "Test Realm", without a guild: the window opens on Find a
-- Guild. Nothing is sent on the network in M4.1.

local DAY = 86400
local function A() return AzerothGuildFinder end
local function main() return A().Main end
local function Apps() return A().Applications end
local function key(name) return "TestRealm|Horde|" .. name end
local function snack() return A().Widgets.Snackbar.Current() end
local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end

local function summary(name, extra)
	local t = { k = key(name), rev = 3, upd = GetServerTime() - 3600, first = 1760000000, own = "a1b2c3d4", sub = "Friendly guild",
		lang = 1, lang1 = 1, tags = { 1 }, pace = 1, days = 31, t0 = 1140, t1 = 1350, rec = 1, apps = true, want = { [0] = 15 },
		newb = true, minL = 20 }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end
local function put(name, extra) assert(A().Catalog:PutSummary(summary(name, extra))) end

local function openList()
	main():Show()
	A().FilterPanel.Controller():Reset()
	return main().hosts.FindGuild
end

-- The card of guild `name` in the list (it must be in view).
local function card(name)
	for _, row in pairs(A().Browse.rows) do
		if row:IsShown() and row.card and row.card.name == name then return row end
	end
	error("no card for " .. name)
end

local function openPage(name)
	main():Show()
	A().Browse:OpenGuild(key(name))
	return main().hosts.GuildPage
end

local function tooltipOf(btn)
	Mock.RunScript(btn, "OnEnter")
	local lines = {}
	for i, line in ipairs(GameTooltip._lines or {}) do lines[i] = type(line) == "table" and line.text or line end
	local title = GameTooltip:GetText()
	Mock.RunScript(btn, "OnLeave")
	return title, lines
end

local function dialog() return A().Apply.dialog and A().Apply.dialog.box end

describe("the Apply button of a card", function()
	it("an open listing: a red Apply that asks to confirm", function()
		put("Aurora")
		openList()
		local b = card("Aurora").apply
		truthy(b:IsShown())
		eq(b:GetLabel(), "Apply")
		truthy(b:IsEnabled())
		eq(b.kind, "primary")
		local title, lines = tooltipOf(b)
		eq(title, "Apply to Aurora")
		contains(lines[1], "officers")
		click(b)
		truthy(A().Apply:IsAsking())
		eq(dialog().question:GetText(), "Apply to Aurora with Testchar (Warrior 60)?")
		eq(#Apps():Records(), 0, "nothing is saved before the confirmation")
		eq(#Mock.errors, 0)
	end)

	it("the confirmation offers only the Warrior's roles, none ticked, and saves what is ticked", function()
		put("Aurora")
		openList()
		click(card("Aurora").apply)
		local group = dialog().roles
		local keys = {}
		for k in pairs(group.chips) do keys[#keys + 1] = k end
		table.sort(keys)
		deepEq(keys, { 1, 4 })
		deepEq(group:GetSelected(), {})
		eq(group.chips[1]:GetLabel(), "Tank")
		eq(group.chips[4]:GetLabel(), "Melee DPS")
		click(group.chips[1])
		click(dialog().yes)
		falsy(A().Apply:IsAsking())
		local rec = Apps():Current()
		truthy(rec)
		eq(rec.roles, 1)
		eq(snack(), "Saved. It will be delivered when an officer of Aurora comes online.")
	end)

	it("no role ticked is fine: the application has no roles", function()
		put("Aurora")
		openList()
		click(card("Aurora").apply)
		click(dialog().yes)
		isNil(Apps():Current().roles)
	end)

	it("a Mage is offered Ranged DPS only, a Druid all four roles", function()
		Mock.player.classFile, Mock.player.classId = "MAGE", 8
		put("Aurora")
		openList()
		click(card("Aurora").apply)
		local n = 0
		for k in pairs(dialog().roles.chips) do n = n + 1; eq(k, 8) end
		eq(n, 1)
		eq(dialog().question:GetText(), "Apply to Aurora with Testchar (Mage 60)?")
		click(dialog().no)
		Mock.player.classFile, Mock.player.classId = "DRUID", 11
		click(card("Aurora").apply)
		n = 0
		for _ in pairs(dialog().roles.chips) do n = n + 1 end
		eq(n, 4)
	end)

	it("Cancel saves nothing and the button stays Apply", function()
		put("Aurora")
		openList()
		click(card("Aurora").apply)
		click(dialog().no)
		falsy(A().Apply:IsAsking())
		eq(#Apps():Records(), 0)
		eq(card("Aurora").apply:GetLabel(), "Apply")
	end)

	it("after applying: 'Applied · Waiting for an officer' here, 'You already applied to Aurora' on the others", function()
		put("Aurora"); put("Iron Wolves")
		openList()
		click(card("Aurora").apply)
		click(dialog().yes)
		local here, other = card("Aurora").apply, card("Iron Wolves").apply
		eq(here:GetLabel(), "Applied · Waiting for an officer")
		truthy(here:IsEnabled(), "it leads to My Application")
		eq(here.kind, "tonal")
		eq(other:GetLabel(), "You already applied to Aurora")
		falsy(other:IsEnabled())
		local _, lines = tooltipOf(other)
		eq(lines[1], "Withdraw it first: one open application at a time.")
		click(here)
		eq(main():CurrentTab(), "MyApplication")
	end)

	it("an officer's acknowledgement turns it into 'Applied · Received'", function()
		put("Aurora")
		openList()
		local _, rec = Apps():Apply(key("Aurora"))
		Apps():OnAck(rec.id, "received")
		eq(card("Aurora").apply:GetLabel(), "Applied · Received")
	end)

	it("requirements not met: grey, with the requirement in the tooltip", function()
		Mock.player.level = 30
		put("Veterans", { minL = 40 })
		openList()
		local b = card("Veterans").apply
		eq(b:GetLabel(), "Requirements not met")
		falsy(b:IsEnabled())
		local _, lines = tooltipOf(b)
		eq(lines[1], "Requirements not met: level 40")
		click(b)
		falsy(A().Apply:IsAsking())
	end)

	it("applications closed by the Guild Master: no button on the card", function()
		put("Closed", { apps = false })
		openList()
		falsy(card("Closed").apply:IsShown())
	end)

	it("a decline in the last 7 days: 'You can apply again on <day>', then Apply again", function()
		put("Aurora")
		local _, rec = Apps():Apply(key("Aurora"))
		Apps():OnAck(rec.id, "declined")
		openList()
		local b = card("Aurora").apply
		eq(b:GetLabel(), "You can apply again on " .. A().ApplyModel.ShortDate(GetServerTime() + 7 * DAY, A().L or
			LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")))
		falsy(b:IsEnabled())
		Mock.Advance(7 * DAY, 600)
		A().Browse:RefreshNow()
		eq(card("Aurora").apply:GetLabel(), "Apply")
	end)

	it("listen-only: 'Your character can't send addon messages yet'", function()
		put("Aurora")
		A().Transport.IsListenOnly = function() return true, "InvalidChannel" end
		openList()
		local b = card("Aurora").apply
		eq(b:GetLabel(), "Your character can't send addon messages yet")
		falsy(b:IsEnabled())
	end)

	it("a long reason is cut on the card and given in full in the tooltip", function()
		put("A Guild With A Rather Long Name Indeed"); put("Aurora")
		openList()
		local _, rec = Apps():Apply(key("A Guild With A Rather Long Name Indeed"))
		local b = card("Aurora").apply
		truthy(b:GetWidth() <= A().Browse.APPLY_MAX_W)
		eq(b:GetLabel(), "You already applied to A Guild With A Rather Long Name Indeed")
		eq((tooltipOf(b)), "You already applied to A Guild With A Rather Long Name Indeed")
	end)

	it("the editor's live preview card has no Apply button", function()
		local preview = A().Browse.CreateCard(UIParent)
		A().Browse.BindCard(preview, A().BrowseModel.Card(summary("Aurora"), { status = "listed" }, {}, { now = GetServerTime(),
			L = LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder") }))
		falsy(preview.apply:IsShown())
	end)
end)

describe("the Apply button of the guild page", function()
	it("'Apply to Aurora' with a line under it, and the same confirmation", function()
		put("Aurora")
		local h = openPage("Aurora")
		truthy(h.apply:IsShown())
		eq(h.apply:GetLabel(), "Apply to Aurora")
		eq(h.applyNote:GetText(), "One click: officers are notified in game. One open application at a time.")
		click(h.apply)
		truthy(A().Apply:IsAsking())
		click(dialog().yes)
		eq(h.apply:GetLabel(), "Applied · Waiting for an officer")
		eq(h.applyNote:GetText(), "Your application is open. Follow it in the My Application tab.")
	end)

	it("closed: no button, and the note sends to the contacts", function()
		put("Closed", { apps = false })
		local h = openPage("Closed")
		falsy(h.apply:IsShown())
		truthy(h.appsNote:IsShown())
		eq(h.appsNote:GetText(), "Applications via addon are closed. Use the contacts below.")
	end)

	it("every refusal writes its reason under the button", function()
		Mock.player.level = 30
		put("Veterans", { minL = 40, minI = 150 })
		local h = openPage("Veterans")
		eq(h.apply:GetLabel(), "Requirements not met")
		eq(h.applyNote:GetText(), "Requirements not met: level 40, item level 150")
	end)

	it("the own guild's page in My Guild has no Apply button", function()
		put("Iron Wolves")
		Mock.guild.Set{ name = "Iron Wolves", myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		A().Role:Refresh()
		main():Show()
		falsy(main().hosts.MyGuild.page.apply:IsShown())
		eq(A().Apply.View(key("Iron Wolves"), "page").state, "inguild")
	end)
end)

describe("the My Application tab", function()
	local function tab()
		main():Show()
		main():Select("MyApplication")
		return main().hosts.MyApplication
	end

	it("without an application: the empty state and a way to Find a Guild", function()
		local h = tab()
		truthy(h.empty:IsShown())
		falsy(h.app:IsShown())
		eq(h.empty.title:GetText(), "You haven't applied to any guild")
		eq(h.who:GetText(), "Testchar · Warrior 60")
		click(h.empty.find)
		eq(main():CurrentTab(), "FindGuild")
	end)

	it("an open application: the guild, the status, the road, the roles, the expiry, View guild and Withdraw", function()
		put("Aurora")
		Apps():Apply(key("Aurora"), 1 + 4)
		Mock.Advance(2 * 3600, 60)
		local h = tab()
		local f = h.app
		truthy(f:IsShown())
		eq(f.name:GetText(), "Aurora")
		eq(f.applied:GetText(), "Applied 2 h ago")
		eq(f.card.title:GetText(), "Waiting for an officer to come online")
		contains(f.card.text:GetText(), "Aurora")
		eq(f.steps[1]:GetText(), "SENT"); eq(f.steps[1].kind, "ok")
		eq(f.steps[2].kind, "default")
		eq(f.steps[3]:GetText(), "ACCEPTED / DECLINED")
		truthy(f.roleBadges[1]:IsShown()); eq(f.roleBadges[1].role, "tank")
		eq(f.roleBadges[2].role, "melee")
		eq(f.expires:GetText(), "Expires in 14 days without a decision.")
		truthy(f.view:IsShown())
		truthy(f.withdraw:IsShown())
		eq(h.rule:GetText(), "Want another guild? Withdraw first: one open application at a time.")
		eq(main().statusText:GetText(), "Waiting for an officer to come online")
	end)

	it("View guild opens the guild page on this tab; Back returns", function()
		put("Aurora")
		Apps():Apply(key("Aurora"))
		local h = tab()
		click(h.app.view)
		eq(main():CurrentPage(), "GuildPage")
		eq(main():CurrentTab(), "MyApplication")
		eq(main().hosts.GuildPage.name:GetText(), "Aurora")
		main():Back()
		eq(main():CurrentPage(), "MyApplication")
	end)

	it("Withdraw asks first; yes withdraws and the player can apply elsewhere at once", function()
		put("Aurora"); put("Iron Wolves")
		Apps():Apply(key("Aurora"))
		local h = tab()
		click(h.app.withdraw)
		truthy(h.app.confirm:IsShown())
		eq(h.app.confirm.text:GetText(), "Withdraw your application to Aurora? You can apply to another guild right away.")
		click(h.app.confirm.no)
		falsy(h.app.confirm:IsShown())
		eq(Apps():Current().state, "sent")
		click(h.app.withdraw)
		click(h.app.confirm.yes)
		isNil(Apps():Current())
		eq(h.app.card.title:GetText(), "Withdrawing...")
		falsy(h.app.withdraw:IsShown())
		eq(snack(), "Application withdrawn. You can apply to another guild.")
		eq(A().Apply.View(key("Iron Wolves"), "card").state, "ok")
		eq(A().Apply.View(key("Aurora"), "card").state, "ok", "a withdrawal has no cooldown")
	end)

	it("follows the state: received, accepted; a listing gone hides View guild", function()
		put("Aurora")
		local _, rec = Apps():Apply(key("Aurora"))
		local h = tab()
		Apps():OnAck(rec.id, "received")
		eq(h.app.card.title:GetText(), "Received by the guild")
		eq(h.app.steps[2].kind, "ok")
		Apps():OnAck(rec.id, "accepted")
		eq(h.app.card.title:GetText(), "Accepted: check your guild invite")
		eq(h.app.steps[3]:GetText(), "ACCEPTED")
		falsy(h.app.withdraw:IsShown())
		assert(A().Catalog:Delist(key("Aurora"), 9, { trusted = true }))
		falsy(h.app.view:IsShown())
	end)

	it("a change the player did not make puts a dot on the tab until it is opened", function()
		put("Aurora")
		local _, rec = Apps():Apply(key("Aurora"))
		main():Show()
		eq(main().badges.MyApplication or 0, 0, "applying is the player's own doing")
		Apps():OnAck(rec.id, "declined")
		eq(main().badges.MyApplication, 1)
		local h = tab()
		eq(main().badges.MyApplication, 0)
		eq(h.app.card.title:GetText(), "Declined")
		contains(h.app.again:GetText(), "You can apply again on")
		eq(Apps():Unseen(), 0)
	end)

	it("never an error, whatever the state", function()
		put("Aurora")
		for _, state in ipairs({ "received", "accepted", "declined", "withdrawn", "expired" }) do
			local _, rec = Apps():Apply(key("Aurora"))
			if not rec then Mock.Advance(7 * DAY, 3600); _, rec = Apps():Apply(key("Aurora")) end
			if state == "withdrawn" then Apps():Withdraw()
			elseif state == "expired" then Mock.Advance(14 * DAY + 3600, 3600)
			else Apps():OnAck(rec.id, state) end
			tab()
		end
		eq(#Mock.errors, 0)
	end)
end)
