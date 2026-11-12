-- M3.8: My Guild (UI/MyGuild.lua, UI/MyGuildModel.lua) and the role -> panels matrix of SPEC-00 §5.
-- Part 1 is pure Lua: every role against every state of the listing, checked against a table written out by hand from
-- SPEC-00 §5 (not computed from the code under test). Part 2 runs the page on the mock client: the read-only view of a member
-- and an officer, the Guild Master's Edit listing and Delist (with its question), the empty states, the wait for the copy and
-- the window following the role and the catalog while it is open. The mock player is "Testchar", Horde, on "Test Realm".

local GUILD = "Iron Wolves"
local KEY = "TestRealm|Horde|" .. GUILD
local DAY = 86400

local function A() return AzerothGuildFinder end
local function main() return A().Main end
local function Cat() return A().Catalog end
local function OL() return A().OwnListing end
local function host() return main().hosts.MyGuild end
local function snack() return A().Widgets.Snackbar.Current() end
local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end

---------------------------------------------------------------------------------------------------------------------
-- Part 1: the matrix, pure Lua
---------------------------------------------------------------------------------------------------------------------
-- SPEC-00 §5, one row per role and state. tabs = the rail without Settings; page = My Guild is there; kind; then the
-- controls. States: none (no entry), waiting (the copy may still come), listed, inactive (14 days without an ANN, still
-- listed), hidden (30 days, no longer shown), delisted.
local L1, L2 = { "FindGuild", "MyApplication" }, { "MyGuild" }
local WITH_APPS = { "MyGuild", "Applications" }
local EDITOR = { "CreateListing" }

local MATRIX = {
	-- role, state, tabs, page, kind, edit, delist, readOnly, applications, copyMessage
	{ "none", "none", L1, false }, { "none", "waiting", L1, false }, { "none", "listed", L1, false },
	{ "none", "inactive", L1, false }, { "none", "hidden", L1, false }, { "none", "delisted", L1, false },

	{ "member", "none", L2, true, "none", false, false, false, false, true },
	{ "member", "waiting", L2, true, "loading", false, false, false, false, false },
	{ "member", "listed", L2, true, "listing", false, false, true, false, false },
	{ "member", "inactive", L2, true, "listing", false, false, true, false, false },
	{ "member", "hidden", L2, true, "none", false, false, false, false, true },
	{ "member", "delisted", L2, true, "none", false, false, false, false, true },

	{ "officer", "none", L2, true, "none", false, false, false, false, true },
	{ "officer", "waiting", L2, true, "loading", false, false, false, false, false },
	{ "officer", "listed", WITH_APPS, true, "listing", false, false, true, true, false },
	{ "officer", "inactive", WITH_APPS, true, "listing", false, false, true, true, false },
	{ "officer", "hidden", L2, true, "none", false, false, false, false, true },
	{ "officer", "delisted", L2, true, "none", false, false, false, false, true },

	{ "gm", "none", EDITOR, false }, { "gm", "waiting", EDITOR, false },
	{ "gm", "listed", WITH_APPS, true, "listing", true, true, false, true, false },
	{ "gm", "inactive", WITH_APPS, true, "listing", true, true, false, true, false },
	{ "gm", "hidden", EDITOR, false }, { "gm", "delisted", EDITOR, false },
}

local function railOf(tabs)
	local out = { "Settings" }
	for _, t in ipairs(tabs) do out[#out + 1] = t end
	return out
end

describe("the role -> panels matrix of SPEC-00 §5", function()
	local rows
	local function find(role, state)
		for _, r in ipairs(rows) do if r.role == role and r.state == state then return r end end
	end

	it("has a row for every role and every state, and nothing else", function()
		rows = A().MyGuildModel.Matrix()
		eq(#rows, #MATRIX)
		eq(#rows, #A().MyGuildModel.ROLES * #A().MyGuildModel.STATES)
		for _, spec in ipairs(MATRIX) do truthy(find(spec[1], spec[2]), spec[1] .. " " .. spec[2]) end
	end)

	it("every role sees exactly its panels in every state (the rail, Settings first)", function()
		rows = A().MyGuildModel.Matrix()
		for _, spec in ipairs(MATRIX) do
			deepEq(find(spec[1], spec[2]).tabs, railOf(spec[3]), spec[1] .. " / " .. spec[2])
		end
	end)

	it("every role gets exactly the controls of its panel in every state", function()
		rows = A().MyGuildModel.Matrix()
		for _, spec in ipairs(MATRIX) do
			local v = find(spec[1], spec[2]).view
			local name = spec[1] .. " / " .. spec[2]
			eq(v.page, spec[4], name .. " page")
			if spec[4] then
				eq(v.kind, spec[5], name .. " kind")
				eq(v.edit, spec[6], name .. " edit")
				eq(v.delist, spec[7], name .. " delist")
				eq(v.readOnly, spec[8], name .. " readOnly")
				eq(v.applications, spec[9], name .. " applications")
				eq(v.copyMessage, spec[10], name .. " copyMessage")
			else
				falsy(v.edit or v.delist or v.readOnly or v.applications or v.copyMessage, name .. " has no controls")
				isNil(v.kind, name)
			end
		end
	end)

	it("the page exists exactly when the rail has a My Guild tab", function()
		rows = A().MyGuildModel.Matrix()
		for _, r in ipairs(rows) do
			local has = false
			for _, t in ipairs(r.tabs) do if t == "MyGuild" then has = true end end
			eq(r.view.page, has, r.role .. " / " .. r.state)
		end
	end)

	it("only the Guild Master can edit or delist, and only with a listing", function()
		for _, r in ipairs(A().MyGuildModel.Matrix()) do
			if r.view.edit or r.view.delist then
				eq(r.role, "gm")
				eq(r.view.kind, "listing")
			end
			if r.role ~= "gm" and r.view.page and r.view.kind == "listing" then truthy(r.view.readOnly) end
		end
	end)

	it("Applications are for the Guild Master and the officers, and never without a listing", function()
		for _, r in ipairs(A().MyGuildModel.Matrix()) do
			local tab = false
			for _, t in ipairs(r.tabs) do if t == "Applications" then tab = true end end
			eq(tab, (r.role == "gm" or r.role == "officer") and (r.state == "listed" or r.state == "inactive"), r.role .. " / " .. r.state)
			eq(r.view.applications, tab)
		end
	end)

	it("nobody in a guild sees the search, and nobody without a guild sees My Guild", function()
		for _, r in ipairs(A().MyGuildModel.Matrix()) do
			for _, t in ipairs(r.tabs) do
				if r.role == "none" then ne(t, "MyGuild") else ne(t, "FindGuild"); ne(t, "MyApplication") end
			end
		end
	end)

	it("an unknown role has no page and the search tabs", function()
		local v = A().MyGuildModel.View({ role = "nonsense", status = "listed" })
		falsy(v.page)
		deepEq(A().Nav.TabsFor("nonsense", true), { "Settings", "FindGuild", "MyApplication" })
	end)

	it("Kind: a listing wins over the wait, the wait over the empty state", function()
		local M = A().MyGuildModel
		eq(M.Kind({ role = "member", status = "listed", waiting = true }), "listing")
		eq(M.Kind({ role = "member", status = nil, waiting = true }), "loading")
		eq(M.Kind({ role = "member", status = "delisted", waiting = true }), "loading")
		eq(M.Kind({ role = "member", status = nil, waiting = false }), "none")
		eq(M.HasListing("listed"), true)
		eq(M.HasListing("inactive"), true)
		eq(M.HasListing("hidden"), false)
		eq(M.HasListing("delisted"), false)
		eq(M.HasListing(nil), false)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 2: the page on the mock client
---------------------------------------------------------------------------------------------------------------------
local function summary(extra)
	local t = { k = KEY, rev = 4, upd = GetServerTime() - 3600, first = 1760000000, own = "0badc0de", sub = "Friendly raiders",
		lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 31, t0 = 1140, t1 = 1380, rec = 1, apps = true,
		want = { [1] = 4, [5] = 2 }, newb = true, minL = 30,
		st = { m = 149, a7 = 31, u7lo = 19, u7hi = 24, max = 12, cls = { [1] = 18, [8] = 14 } }, srev = GetServerTime() - 1800 }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

local function putListing(extra)
	assert(Cat():PutSummary(summary(extra)))
	assert(Cat():PutDetail({ k = KEY, rev = (extra and extra.rev) or 4, desc = "We raid on weekends and chat in voice.",
		disc = "wolves1", cont = { "Thrall", "Jaina" }, note = "Voice required" }))
end

-- The catalog's state of our guild: none, listed, inactive, hidden or delisted.
local function setCatalog(state)
	if state == "none" or state == "waiting" then return end
	putListing()
	local entry = Cat():Get(KEY)
	if state == "inactive" then entry.annAt = GetServerTime() - 15 * DAY
	elseif state == "hidden" then entry.annAt = GetServerTime() - 31 * DAY
	elseif state == "delisted" then assert(Cat():Delist(KEY, 9, { trusted = true })) end
end

local RANK = { member = 3, officer = 1, gm = 0 }
local function setRole(role)
	if role == "none" then Mock.guild.Leave(); return end
	Mock.guild.Set{ name = GUILD, myRank = RANK[role], members = { { name = "Thrall", rank = 0 }, { name = "Jaina", rank = 1 },
		{ name = "Garrosh", rank = 3 } } }
end

-- A member who has asked for the copy long enough ago to stop waiting for it.
local function stopWaiting() Mock.Advance(OL().ARRIVAL_WAIT + A().MyGuild.POLL + 1) end

local function pageShown(h) return h.page.left:IsShown() and h.page.content:IsShown() end

describe("a member", function()
	it("sees the guild's page read-only: no Edit, no Delist, the note, no Applications, and no tab to search", function()
		setRole("member")
		putListing()
		main():Show()
		deepEq(main().book:Tabs(), { "Settings", "MyGuild" })
		eq(main():CurrentPage(), "MyGuild")
		local h = host()
		eq(main().title:GetText(), GUILD)
		truthy(pageShown(h))
		falsy(h.emptyContent:IsShown())
		falsy(h.edit:IsShown())
		falsy(h.delist:IsShown())
		truthy(h.note:IsShown())
		eq(h.note:GetText(), "Only the Guild Master can edit the listing.")
		falsy(h.apps:IsShown())
		eq(h.page.name:GetText(), GUILD)
		eq(h.page.sub:GetText(), "Friendly raiders")
		eq(main().statusText:GetText(), "Member · This is how players without a guild see your guild.")
		eq(#Mock.errors, 0)
	end)

	it("the page shows the guild's description, Discord code and contacts from the copy, and no Apply button", function()
		setRole("member")
		putListing()
		main():Show()
		local h = host()
		eq(h.page.copy:GetValue(), "https://discord.gg/wolves1")
		eq(h.page.about.text:GetText(), "We raid on weekends and chat in voice.")
		local n = 0
		for _, row in ipairs(h.page.contactRows) do if row:IsShown() then n = n + 1 end end
		eq(n, 2)
	end)

	it("nothing is checked against the member: no 'you are' in the requirements, no 'needs your class' tag, no how-it-works card", function()
		setRole("member")
		putListing({ minL = 30 })
		main():Show()
		local h = host().page
		falsy(h.how:IsShown())
		falsy(h.look.you:IsShown())
		for _, row in ipairs(h.reqs.rows) do
			if row:IsShown() then eq(row.you:GetText() or "", "") end
		end
	end)

	it("an empty catalog shows the empty state once the wait for the copy is over", function()
		setRole("member")
		main():Show()
		stopWaiting()
		local h = host()
		falsy(pageShown(h))
		truthy(h.emptyContent:IsShown())
		truthy(h.emptyLeft:IsShown())
		eq(h.emptyContent.box.title:GetText(), "Your guild has no listing yet")
		eq(h.emptyContent.box.body:GetText(),
			"Ask your Guild Master to publish one with Guild Finder. Applications will appear here once the guild is listed.")
		truthy(h.emptyContent.box.copy:IsShown())
		eq(h.emptyContent.box.copy:GetValue(), "Please list our guild on Guild Finder (/gf).")
		falsy(h.emptyContent.box.ring:IsShown(), "no spinner")
		eq(h.emptyLeft.name:GetText(), GUILD)
		eq(h.emptyLeft.role:GetText(), "MEMBER")
		falsy(h.edit:IsShown() or h.delist:IsShown() or h.note:IsShown() or h.apps:IsShown())
	end)

	it("waits for the copy first: the spinner, no message to copy, and it turns into the empty state by itself", function()
		setRole("member")
		main():Show()
		local h = host()
		truthy(OL():Waiting())
		truthy(h.emptyContent:IsShown())
		eq(h.emptyContent.box.title:GetText(), "Waiting for your guild's listing...")
		truthy(h.emptyContent.box.ring:IsShown())
		falsy(h.emptyContent.box.copy:IsShown())
		Mock.Advance(OL().ARRIVAL_WAIT + A().MyGuild.POLL)
		falsy(OL():Waiting())
		eq(h.emptyContent.box.title:GetText(), "Your guild has no listing yet")
		truthy(h.emptyContent.box.copy:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("the listing arriving while it waits replaces the wait with the guild's page", function()
		setRole("member")
		main():Show()
		local h = host()
		truthy(h.emptyContent:IsShown())
		putListing()
		Mock.Advance(1)
		truthy(pageShown(h))
		falsy(h.emptyContent:IsShown())
		eq(h.page.name:GetText(), GUILD)
	end)

	it("a listing withdrawn while the page is open gives the empty state", function()
		setRole("member")
		putListing()
		main():Show()
		stopWaiting()
		local h = host()
		truthy(pageShown(h))
		assert(Cat():Delist(KEY, 9, { trusted = true }))
		Mock.Advance(1)
		falsy(pageShown(h))
		truthy(h.emptyContent:IsShown())
		eq(h.emptyContent.box.title:GetText(), "Your guild has no listing yet")
	end)

	it("a guild copy that arrived says it is withdrawn, not waiting", function()
		setRole("member")
		main():Show()
		putListing()
		assert(Cat():Delist(KEY, 9, { trusted = true }))
		OL():OnMessage({ t = "GLIST", k = KEY, rev = 9, upd = 1767000009, first = 1766000000, own = "0badc0de", del = true,
			sub = "Friendly raiders", lang = 1, lang1 = 1, tags = { 1 }, pace = 2, days = 31, t0 = 0, t1 = 0, rec = 1, apps = true,
			want = { [0] = 8 }, newb = true, minL = 1, desc = "x" }, "Thrall", "GUILD")
		falsy(OL():Waiting(), "a copy is here")
		Mock.Advance(1)
		eq(host().emptyContent.box.title:GetText(), "Your guild has no listing yet")
	end)
end)

describe("an officer", function()
	it("sees the same read-only page, with the Applications placeholder and the Applications tab", function()
		setRole("officer")
		putListing()
		main():Show()
		deepEq(main().book:Tabs(), { "Settings", "MyGuild", "Applications" })
		local h = host()
		truthy(pageShown(h))
		falsy(h.edit:IsShown())
		falsy(h.delist:IsShown())
		truthy(h.note:IsShown())
		truthy(h.apps:IsShown())
		eq(h.apps.title:GetText(), "APPLICATIONS")
		eq(main().statusText:GetText(), "Officer · This is how players without a guild see your guild.")
		main():Select("Applications")
		eq(main():CurrentPage(), "Applications")
		eq(#Mock.errors, 0)
	end)

	it("without a listing: the empty state and no Applications tab", function()
		setRole("officer")
		main():Show()
		stopWaiting()
		deepEq(main().book:Tabs(), { "Settings", "MyGuild" })
		local h = host()
		truthy(h.emptyContent:IsShown())
		eq(h.emptyLeft.role:GetText(), "OFFICER")
		falsy(h.apps:IsShown())
	end)

	it("cannot reach Edit or Delist whatever the page says: the model has none and the editor refuses", function()
		setRole("officer")
		putListing()
		main():Show()
		local h = host()
		eq(A().MyGuild:Edit(), false)
		eq(A().MyGuild:Ask(), false)
		falsy(h.confirm:IsShown())
		eq(main():CurrentPage(), "MyGuild")
		local ok, why = OL():Delist()
		eq(ok, false)
		eq(why, "not-leader")
	end)
end)

describe("the Guild Master", function()
	local function listed()
		setRole("gm")
		A().Editor:Open()   -- Create Listing
		A().Editor:Patch({ sub = "Friendly raiders", desc = "We raid on weekends and we like to chat in voice.", lang1 = 1, lang = 1,
			tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380, rec = 1, apps = true, want = { [0] = 15 }, newb = true,
			minL = 30, emb = { t = 2, e = 0 }, disc = "wolves1", cont = { "Thrall" } })
		eq(OL():Publish(A().Editor:Fields()), true)
		main():Show()
		eq(main():CurrentPage(), "MyGuild")
		return host()
	end

	it("without a listing has only Create Listing, no My Guild", function()
		setRole("gm")
		main():Show()
		deepEq(main().book:Tabs(), { "Settings", "CreateListing" })
		eq(main():CurrentTab(), "CreateListing")
		falsy(main().book:Has("MyGuild"))
	end)

	it("with a listing sees My Guild with Edit listing and Delist, the Applications placeholder and no read-only note", function()
		local h = listed()
		deepEq(main().book:Tabs(), { "Settings", "MyGuild", "Applications" })
		truthy(pageShown(h))
		truthy(h.edit:IsShown())
		eq(h.edit:GetLabel(), "Edit listing")
		truthy(h.delist:IsShown())
		eq(h.delist:GetLabel(), "Delist")
		falsy(h.note:IsShown())
		truthy(h.apps:IsShown())
		eq(main().statusText:GetText(), "Guild Master · This is how players without a guild see your guild.")
		eq(#Mock.errors, 0)
	end)

	it("Edit listing opens the editor on the published listing, pushed on My Guild; Back returns", function()
		local h = listed()
		click(h.edit)
		eq(main():CurrentTab(), "MyGuild")
		eq(main():CurrentPage(), "ListingEditor")
		truthy(main().backButton:IsShown())
		eq(A().Editor:Get("sub"), "Friendly raiders")
		falsy(main().hosts.ListingEditor.blocked:IsShown())
		main():Back()
		eq(main():CurrentPage(), "MyGuild")
		truthy(pageShown(host()))
		eq(#Mock.errors, 0)
	end)

	it("Delist asks first: Cancel keeps the listing", function()
		local h = listed()
		click(h.delist)
		truthy(h.confirm:IsShown())
		eq(h.confirm.text:GetText(), "Remove your guild from Guild Finder? Pending applications will be closed.")
		eq(h.confirm.yes:GetLabel(), "Delist")
		eq(OL():Status(), "listed")
		click(h.confirm.no)
		falsy(h.confirm:IsShown())
		eq(OL():Status(), "listed")
		eq(Cat():Status(KEY), "listed")
		truthy(pageShown(h))
	end)

	it("Delist, confirmed, withdraws the listing and the window gives the Guild Master Create Listing back", function()
		local h = listed()
		click(h.delist)
		click(h.confirm.yes)
		eq(OL():Status(), "delisted")
		eq(snack(), "Your guild was removed from Guild Finder.")
		deepEq(main().book:Tabs(), { "Settings", "CreateListing" })
		eq(main():CurrentTab(), "CreateListing")
		falsy(h.shown, "My Guild is gone")
		eq(#Mock.errors, 0)
	end)

	it("closing the window leaves nothing of the question behind", function()
		local h = listed()
		click(h.delist)
		truthy(h.confirm:IsShown())
		main():Hide()
		falsy(h.confirm:IsShown())
		main():Show()
		falsy(h.confirm:IsShown())
	end)
end)

describe("the window follows the role and the catalog while it is open", function()
	it("a member promoted to Guild Master loses My Guild and gets Create Listing", function()
		setRole("member")
		main():Show()
		eq(main():CurrentTab(), "MyGuild")
		Mock.guild.SetMyRank(0)
		deepEq(main().book:Tabs(), { "Settings", "CreateListing" })
		eq(main():CurrentTab(), "CreateListing")
	end)

	it("an officer who leaves the guild gets the search tabs", function()
		setRole("officer")
		putListing()
		main():Show()
		Mock.guild.Leave()
		deepEq(main().book:Tabs(), { "Settings", "FindGuild", "MyApplication" })
		eq(main():CurrentTab(), "FindGuild")
		falsy(host() and host().shown)
	end)

	it("a listing appearing adds the Applications tab to an officer's rail", function()
		setRole("officer")
		main():Show()
		stopWaiting()
		deepEq(main().book:Tabs(), { "Settings", "MyGuild" })
		putListing()
		Mock.Advance(1)
		deepEq(main().book:Tabs(), { "Settings", "MyGuild", "Applications" })
		eq(main():CurrentTab(), "MyGuild")
		truthy(host().apps:IsShown())
	end)

	it("a listing going quiet for 14 days still shows the page (marked as possibly inactive)", function()
		setRole("member")
		putListing()
		Cat():Get(KEY).annAt = GetServerTime() - 15 * DAY
		main():Show()
		truthy(pageShown(host()))
		local seen = false
		for _, tag in ipairs(host().page.tags) do if tag:IsShown() and tag:GetText() == "May be inactive" then seen = true end end
		truthy(seen)
	end)
end)

describe("every role and every state on the real page", function()
	local STATE_LIST = { "none", "waiting", "listed", "inactive", "hidden", "delisted" }

	-- What the mock window shows for a role in a state, read from its frames.
	local function observe(role, state)
		setRole(role)
		setCatalog(state)
		if state ~= "waiting" then stopWaiting() end
		main():Show()
		local seen = { tabs = main().book:Tabs() }
		local h = main().hosts.MyGuild
		if main().book:Has("MyGuild") then
			main():Select("MyGuild")
			h = host()
			seen.page = pageShown(h)
			seen.empty = h.emptyContent:IsShown()
			seen.spinner = seen.empty and h.emptyContent.box.ring:IsShown()
			seen.copy = seen.empty and h.emptyContent.box.copy:IsShown()
			seen.edit, seen.delist, seen.note, seen.apps = h.edit:IsShown(), h.delist:IsShown(), h.note:IsShown(), h.apps:IsShown()
		end
		return seen
	end

	for _, spec in ipairs(MATRIX) do
		local role, state = spec[1], spec[2]
		it(role .. " / " .. state, function()
			local seen = observe(role, state)
			deepEq(seen.tabs, railOf(spec[3]))
			if spec[4] then
				local kind = spec[5]
				eq(seen.page, kind == "listing", "the guild's page")
				eq(seen.empty, kind ~= "listing", "the empty or waiting state")
				eq(seen.spinner, kind == "loading", "the spinner")
				eq(seen.copy, kind == "none", "the message to copy")
				eq(seen.edit, spec[6], "Edit listing")
				eq(seen.delist, spec[7], "Delist")
				eq(seen.note, spec[8], "the read-only note")
				eq(seen.apps, spec[9], "the Applications placeholder")
			else
				isNil(seen.page, "no My Guild page")
			end
			eq(#Mock.errors, 0)
		end)
	end
	local _ = STATE_LIST
end)

describe("OwnListing:Waiting", function()
	it("is true for a member right after the login and ends by itself", function()
		setRole("member")
		truthy(OL():Waiting())
		Mock.Advance(OL().ARRIVAL_WAIT - 1)
		truthy(OL():Waiting())
		Mock.Advance(2)
		falsy(OL():Waiting())
	end)

	it("is never true for the Guild Master or for a player without a guild", function()
		setRole("gm")
		falsy(OL():Waiting())
		Mock.guild.Leave()
		falsy(OL():Waiting())
	end)

	it("a copy that is here ends it, and a new guild starts it again", function()
		setRole("member")
		truthy(OL():Waiting())
		OL():OnMessage({ t = "GLIST", k = KEY, rev = 2, upd = 1767000002, first = 1766000000, own = "0badc0de", sub = "Friendly raiders",
			lang = 1, lang1 = 1, tags = { 1 }, pace = 2, days = 31, t0 = 0, t1 = 0, rec = 1, apps = true, want = { [0] = 8 },
			newb = true, minL = 1, desc = "x" }, "Thrall", "GUILD")
		falsy(OL():Waiting())
		Mock.guild.Leave()
		Mock.guild.Set{ name = "Other Guild", myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		truthy(OL():Waiting())
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The exit criterion of milestone M3 in the simulator: a Guild Master publishes, a client without a guild sees the listing
-- within 2 minutes with the emblem and the statistics, and the members show it in My Guild.
---------------------------------------------------------------------------------------------------------------------
describe("simulator: the exit criterion of M3 (the in-game check is still the owner's)", function()
	it("a published listing reaches a client without a guild within 2 minutes, with the emblem and the statistics; the members' My Guild shows it", function()
		-- 1 = Guild Master, 2 and 3 = members, 4 = no guild; the roster also has 2 members without the addon
		local sim = Sim.new{ clients = 4, sync = false, seed = 53, latency = { 0.05, 0.3 }, setup = function(M, i)
			if i == 4 then return end
			local members = {}
			for j = 1, 3 do
				if j ~= i then members[#members + 1] = { name = Sim.nameOf(j), rank = j == 1 and 0 or 3 } end
			end
			for j = 1, 2 do
				members[#members + 1] = { name = "Offline" .. string.char(96 + j), rank = 3, online = false, lastOnline = { 0, 0, 1, 0 } }
			end
			M.guild.Set{ name = GUILD, realm = "Test Realm", myRank = i == 1 and 0 or 3, members = members }
		end }
		local gm, m2, out = sim:client(1), sim:client(2), sim:client(4)
		local listing = { sub = "Friendly raiders", desc = "We raid on weekends and we like to chat in voice.", lang1 = 1, lang = 1,
			tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380, rec = 1, apps = true, want = { [0] = 15 }, newb = true,
			minL = 30, emb = { t = 2, e = 0 }, disc = "wolves1", cont = { "Thrall" } }
		eq(gm:addon().OwnListing:Publish(listing), true)
		local seen, took = sim:advanceUntil(function()
			local entry = out:addon().Catalog:Get(KEY)
			return entry ~= nil and entry.sum.emb ~= nil and entry.sum.st ~= nil
		end, 120)
		T.log(("a client without a guild saw the listing, with its emblem and statistics, after %.1f simulated seconds (limit 120)"):format(took))
		truthy(seen, "within 2 minutes")
		local entry = out:addon().Catalog:Get(KEY)
		deepEq(entry.sum.emb, { t = 2, e = 0 })
		eq(entry.sum.st.m, 5, "members from the roster")
		eq(select(2, out:addon().Catalog:Get(KEY)), "listed")
		-- the member's window: My Guild with the guild's page, read-only
		sim:advance(10)
		local main = m2:addon().Main
		main:Show()
		eq(main:CurrentTab(), "MyGuild")
		local h = main.hosts.MyGuild
		truthy(h.page.left:IsShown() and h.page.content:IsShown())
		eq(h.page.name:GetText(), GUILD)
		falsy(h.edit:IsShown() or h.delist:IsShown())
		truthy(h.note:IsShown())
		-- the Guild Master's window: the same page with Edit listing and Delist
		local gmMain = gm:addon().Main
		gmMain:Show()
		eq(gmMain:CurrentTab(), "MyGuild")
		truthy(gmMain.hosts.MyGuild.edit:IsShown() and gmMain.hosts.MyGuild.delist:IsShown())
	end)
end)
