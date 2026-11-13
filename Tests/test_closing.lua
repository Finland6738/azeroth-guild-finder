-- M4.6: the closing cases of an application (SPEC-07 §2): the applicant joins the guild (PLAYER_GUILD_UPDATE through the role)
-- -> accepted; the guild's listing is withdrawn -> declined, with no 7-day cooldown; an applicant seen in the roster by an
-- officer -> accepted; expiry on both sides at 14 days; and the whole flow in the network simulator (officer online, officer
-- coming online later, two officers in sync). Part 1: the applicant on the mock client. Part 2: one client as an officer or
-- the Guild Master. Part 3: the simulator, with the virtual clock (days pass in a few thousand frames).
-- The mock player is "Testchar", Horde Orc Warrior 60 on "Test Realm".

local DAY = 86400
local GUILD = "Aurora"
local KEY = "TestRealm|Horde|" .. GUILD

local function A() return AzerothGuildFinder end
local function Apps() return A().Applications end
local function Inbox() return A().Inbox end
local function D() return A().Decisions end
local function out() return table.concat(Mock.PlainOutput(), "\n") end
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })

local function summary(rev)
	return { k = KEY, rev = rev or 3, upd = GetServerTime() - 3600, first = 1760000000, own = "a1b2c3d4", sub = "Friendly",
		lang = 1, lang1 = 1, tags = { 1 }, pace = 1, days = 31, t0 = 1140, t1 = 1350, rec = 1, apps = true, want = { [0] = 15 },
		newb = true, minL = 20 }
end
local function put(rev) assert(A().Catalog:PutSummary(summary(rev))) end

local function listen(event)
	local seen = {}
	A().Bus:On(event, function(...) seen[#seen + 1] = { ... } end)
	return seen
end

---------------------------------------------------------------------------------------------------------------------
-- Part 1: the applicant
---------------------------------------------------------------------------------------------------------------------
describe("the applicant joins the guild", function()
	it("an application that was sent becomes accepted (through received), with a chat line and the dot", function()
		put()
		local _, r = Apps():Apply(KEY, 4)
		local changed = listen("APPLICATION_CHANGED")
		Mock.ClearOutput()
		Mock.guild.Set{ name = GUILD, myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		eq(r.state, "accepted"); eq(r.why, "joined"); eq(r.stateRev, 3, "sent 1, received 2, accepted 3")
		truthy(r.unseen)
		deepEq(changed, { { r.id, "accepted", "sent" } })
		truthy(out():find("You joined Aurora: your application was closed as accepted.", 1, true))
		isNil(Apps():Current())
		deepEq(Apps():Outbox(), {}, "nothing is left to send")
	end)

	it("a received application becomes accepted with one step", function()
		put()
		local _, r = Apps():Apply(KEY)
		truthy(Apps():OnAck(r.id, "received"))
		Mock.guild.Set{ name = GUILD, myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		eq(r.state, "accepted"); eq(r.stateRev, 3); eq(r.why, "joined")
	end)

	it("a different guild changes nothing here, and neither does leaving a guild", function()
		put()
		local _, r = Apps():Apply(KEY)
		Mock.guild.Set{ name = "Iron Wolves", myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		eq(r.state, "sent")
		Mock.guild.Leave()
		eq(r.state, "sent")
	end)

	it("a record that is already closed never moves", function()
		put()
		local _, r = Apps():Apply(KEY)
		truthy(Apps():Withdraw())
		Mock.guild.Set{ name = GUILD, myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		eq(r.state, "withdrawn"); isNil(r.why)
	end)

	it("a join that happened while the addon was not looking is found at the next login", function()
		put()
		local _, r = Apps():Apply(KEY)
		local real = Apps().CheckClosed
		Apps().CheckClosed = function() end
		Mock.guild.Set{ name = GUILD, myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		eq(r.state, "sent", "the events were missed")
		Apps().CheckClosed = real
		Mock.Fire("PLAYER_ENTERING_WORLD")
		eq(r.state, "accepted"); eq(r.why, "joined")
	end)

	it("the closed record survives /reload with its reason", function()
		put()
		local _, r = Apps():Apply(KEY)
		Mock.guild.Set{ name = GUILD, myRank = 3, members = { { name = "Thrall", rank = 0 } } }
		Mock.Reload()
		local again = Apps():Get(r.id)
		eq(again.state, "accepted"); eq(again.why, "joined")
	end)
end)

describe("the listing is withdrawn", function()
	it("an open application is declined, with a chat line, and starts no cooldown", function()
		put()
		local _, r = Apps():Apply(KEY)
		Mock.ClearOutput()
		truthy(A().Catalog:Delist(KEY, 3, { trusted = true }))
		eq(r.state, "declined"); eq(r.why, "delisted"); eq(r.stateRev, 3); truthy(r.unseen)
		truthy(out():find("Aurora was removed from Guild Finder: your application was closed.", 1, true))
		isNil(Apps().CooldownUntil(Apps():Records(), KEY, GetServerTime()), "not a refusal: no cooldown")
		-- the listing comes back with a higher revision: the player can apply at once
		put(4)
		local ok, why = Apps():Check(KEY)
		truthy(ok, tostring(why))
		truthy(Apps():Apply(KEY))
	end)

	it("a received application is declined with one step", function()
		put()
		local _, r = Apps():Apply(KEY)
		truthy(Apps():OnAck(r.id, "received"))
		A().Catalog:Delist(KEY, 3, { trusted = true })
		eq(r.state, "declined"); eq(r.stateRev, 3)
	end)

	it("an officer's decline still starts the 7-day cooldown (APP-06)", function()
		put()
		local _, r = Apps():Apply(KEY)
		truthy(Apps():OnAck(r.id, "declined"))
		isNil(r.why)
		eq(select(2, Apps():Check(KEY)), "cooldown")
	end)

	it("another guild's withdrawal closes nothing", function()
		put()
		local _, r = Apps():Apply(KEY)
		A().Catalog:PutSummary({ k = "TestRealm|Horde|Other", rev = 3, upd = GetServerTime(), first = 1760000000, own = "a1b2c3d5",
			sub = "x", lang = 1, lang1 = 1, tags = { 1 }, pace = 1, days = 31, t0 = 1140, t1 = 1350, rec = 1, apps = true,
			want = { [0] = 15 }, newb = true, minL = 20 })
		A().Catalog:Delist("TestRealm|Horde|Other", 3, { trusted = true })
		eq(r.state, "sent")
		eq(A().Catalog:Status(KEY), "listed")
	end)

	it("My Application says the guild was removed and offers no 'apply again on' date", function()
		local M = A().ApplyModel
		local NOW = GetServerTime()
		local r = { id = "0a1b2c3d", k = KEY, who = "Testchar-TestRealm", cls = 1, race = 2, lvl = 60, at = NOW, upd = NOW,
			state = "declined", stateRev = 3, why = "delisted" }
		local v = M.MyApplication(r, { now = NOW + 60, listed = false }, L)
		eq(v.title, "Guild removed from the list")
		truthy(v.body:find("This is not a refusal", 1, true))
		isNil(v.again)
		r.why = nil
		v = M.MyApplication(r, { now = NOW + 60, listed = true }, L)
		eq(v.title, "Declined")
		truthy(v.again)
		r.state, r.why = "accepted", "joined"
		v = M.MyApplication(r, { now = NOW + 60 }, L)
		eq(v.title, "Accepted: you joined")
	end)
end)

describe("the saved record keeps `why` only where it makes sense", function()
	local function rec(extra)
		local NOW = GetServerTime()
		local r = { id = "0a1b2c3d", k = KEY, who = "Testchar-TestRealm", cls = 1, race = 2, lvl = 60, at = NOW, state = "sent",
			stateRev = 1, upd = NOW }
		for k, v in pairs(extra) do r[k] = v end
		return r
	end
	it("joined only on an accepted record, delisted only on a declined one, nothing else", function()
		local S = Apps().Sanitize
		eq(S(rec({ state = "accepted", stateRev = 3, why = "joined" })).why, "joined")
		eq(S(rec({ state = "declined", stateRev = 3, why = "delisted" })).why, "delisted")
		isNil(S(rec({ state = "declined", stateRev = 3, why = "joined" })).why)
		isNil(S(rec({ state = "accepted", stateRev = 3, why = "delisted" })).why)
		isNil(S(rec({ state = "accepted", stateRev = 3, why = "whatever" })).why)
		isNil(S(rec({ why = "joined" })).why)
	end)

	it("the cooldown rule ignores a delisted decline and keeps the others", function()
		local C = Apps().CooldownUntil
		local NOW = GetServerTime()
		local plain = rec({ state = "declined", stateRev = 3 })
		local gone = rec({ state = "declined", stateRev = 3, why = "delisted" })
		eq(C({ plain }, KEY, NOW + 10), NOW + 7 * DAY)
		isNil(C({ gone }, KEY, NOW + 10))
		eq(C({ gone, plain }, KEY, NOW + 10), NOW + 7 * DAY)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 2: one client as an officer or the Guild Master
---------------------------------------------------------------------------------------------------------------------
local LISTING = { sub = "Friendly raiders", lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380,
	rec = 1, apps = true, want = { [0] = 8 }, newb = true, minL = 10, desc = "We raid on weekends.", disc = "aurora1",
	cont = { "Thrall" } }

local function asRole(rank, extra)
	local members = { { name = "Thrall", rank = 0 }, { name = "Garrosh", rank = 3 } }
	for _, m in ipairs(extra or {}) do members[#members + 1] = m end
	Mock.guild.Set{ name = GUILD, myRank = rank, members = members }
	A().Role:Refresh()
end

local function receive(id, extra)
	local t = GetServerTime()
	local r = { id = id, k = KEY, state = "received", stateRev = 2, at = t - 3600, upd = t - 3600,
		who = "Elarin-TestRealm", cls = 8, race = 5, lvl = 32, ilvl = 41, roles = 8 }
	for k, v in pairs(extra or {}) do r[k] = v end
	return assert(Inbox():Receive(r))
end

describe("the Guild Master delists", function()
	local function guildMaster()
		asRole(0)
		assert(A().OwnListing:Publish(LISTING))
		receive("00000001")
		receive("00000002", { who = "Mirelle-TestRealm", cls = 5 })
		receive("00000003", { who = "Nym-TestRealm", cls = 1 })
		Inbox():Withdraw(KEY, "00000003", "Nym-TestRealm")   -- already over
	end

	it("declines every pending application, by the Guild Master, and says so on the Bus", function()
		guildMaster()
		local closed = listen("APPLICATIONS_CLOSED")
		eq(Inbox():Count(KEY, true), 2)
		deepEq({ A().OwnListing:Delist() }, { true, "delisted" })
		for _, id in ipairs({ "00000001", "00000002" }) do
			local r = Inbox():Get(KEY, id)
			eq(r.state, "declined", id); eq(r.by, "Testchar", id); eq(r.stateRev, 3, id)
		end
		eq(Inbox():Get(KEY, "00000003").state, "withdrawn", "a closed record stays as it was")
		eq(Inbox():Count(KEY, true), 0)
		deepEq(closed, { { KEY, "declined", 2, "delisted" } })
		eq(D().state.stats.delisted, 2)
		truthy(D():DebugLines()[1]:find("closed by delisting 2", 1, true))
	end)

	it("every decline goes to the other officers as a change (the sync marks them dirty)", function()
		guildMaster()
		local changed = listen("INBOX_CHANGED")
		A().OwnListing:Delist()
		local n = 0
		for _, c in ipairs(changed) do
			if c[3] == "declined" and c[5] == nil then n = n + 1 end
		end
		eq(n, 2, "source nil: a local change, which InboxSync sends")
	end)

	it("the notification icon goes with the listing, and the panel has nothing pending", function()
		guildMaster()
		A().Notify:Refresh()
		local icon = A().Notify.frame
		truthy(icon and icon:IsShown())
		eq(icon.badge.text:GetText(), "2")
		A().OwnListing:Delist()
		falsy(icon:IsShown())
	end)

	it("an APPLY for the withdrawn guild is refused and not answered", function()
		guildMaster()
		local t = GetServerTime()
		local msg = { t = "APPLY", id = "00000009", k = KEY, who = "Mirelle-TestRealm", cls = 5, race = 1, lvl = 20, at = t - 60 }
		local before = #Mock.chat.sent
		A().OwnListing:Delist()
		before = #Mock.chat.sent
		local ok, why = A().Delivery:OnMessage(msg, "Mirelle-TestRealm", "WHISPER")
		falsy(ok); eq(why, "delisted")
		isNil(Inbox():Get(KEY, "00000009"))
		Mock.Advance(1, 0.1)
		eq(#Mock.chat.sent, before, "no APPACK went out")
	end)

	it("a copy that is still open and arrives from another officer afterwards is declined too", function()
		guildMaster()
		A().OwnListing:Delist()
		local t = GetServerTime()
		assert(Inbox():Merge(KEY, { id = "00000009", k = KEY, state = "received", stateRev = 2, at = t - 1800, upd = t - 1800,
			who = "Jaina-TestRealm", cls = 8, race = 5, lvl = 32 }))
		eq(Inbox():Get(KEY, "00000009").state, "declined")
		eq(Inbox():Count(KEY, true), 0)
	end)

	it("while the listing stands nothing is declined, and a member never declines anything", function()
		guildMaster()
		eq(D():OnListing("received", KEY), 0)
		eq(Inbox():Count(KEY, true), 2)
		asRole(3)
		eq(D():OnListing("delisted", KEY), 0)
		eq(Inbox():Count(KEY, true), 2, "a member's client does not touch the box")
	end)
end)

describe("an officer who sees the applicant in the roster", function()
	it("closes the record as accepted, with nobody as the decider, and leaves the others", function()
		asRole(1)
		receive("0a1b2c3d")
		receive("0a1b2c3e", { who = "Nym-TestRealm" })
		local closed = listen("APPLICATIONS_CLOSED")
		Mock.guild.Set{ name = GUILD, myRank = 1, members = { { name = "Thrall", rank = 0 }, { name = "Elarin", rank = 3 } } }
		local r = Inbox():Get(KEY, "0a1b2c3d")
		eq(r.state, "accepted"); isNil(r.by); eq(r.stateRev, 3)
		eq(Inbox():Get(KEY, "0a1b2c3e").state, "received")
		deepEq(closed, { { KEY, "accepted", 1, "joined" } })
	end)

	it("looks at the roster at most once a minute and once more after the gap", function()
		asRole(1)
		receive("0a1b2c3d")
		receive("0a1b2c3e", { who = "Nym-TestRealm" })
		Mock.guild.Set{ name = GUILD, myRank = 1, members = { { name = "Thrall", rank = 0 }, { name = "Elarin", rank = 3 } } }
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "accepted")
		Mock.guild.Set{ name = GUILD, myRank = 1, members = { { name = "Thrall", rank = 0 }, { name = "Nym", rank = 3 } } }
		eq(Inbox():Get(KEY, "0a1b2c3e").state, "received", "too soon: the event is remembered, not read")
		Mock.Advance(65, 1)
		eq(Inbox():Get(KEY, "0a1b2c3e").state, "accepted", "the look after the gap found him")
	end)

	it("a record past its 14 days is expired, not accepted, and a member does nothing", function()
		asRole(1)
		receive("0a1b2c3d", { at = GetServerTime() - 15 * DAY, upd = GetServerTime() - 15 * DAY })
		eq(D():CheckJoined(true), 0)
		asRole(3, { { name = "Elarin", rank = 3 } })
		eq(D():CheckJoined(true), 0)
	end)

	it("without a roster nothing is decided", function()
		asRole(1)
		receive("0a1b2c3d")
		local saved = _G.GetNumGuildMembers
		_G.GetNumGuildMembers = function() return 0, 0, 0 end
		eq(D():CheckJoined(true), 0)
		_G.GetNumGuildMembers = saved
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received")
	end)
end)

describe("expiry on the officer's side", function()
	it("at 14 days the record is expired at the moment it expired, and the badge goes with it", function()
		asRole(1)
		put()
		A().Notify:Refresh()
		local t = GetServerTime()
		receive("0a1b2c3d", { at = t, upd = t })
		A().Notify:Refresh()
		local icon = A().Notify.frame
		eq(icon.badge.text:GetText(), "1")
		Mock.Advance(14 * DAY - 3600, 3600)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received")
		Mock.Advance(2 * 3600, 600)
		Inbox():Sweep()
		local r = Inbox():Get(KEY, "0a1b2c3d")
		eq(r.state, "expired"); eq(r.upd, t + 14 * DAY, "the moment it expired, the same on every client")
		eq(Inbox():Count(KEY, true), 0)
		A().Notify:Refresh()
		falsy(icon:IsShown() and icon.badge:IsShown(), "no badge for nothing pending")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 3: the simulator (Client 1 = Guild Master, 2 = the applicant, 3 = an officer)
---------------------------------------------------------------------------------------------------------------------
local function guildSim(seed)
	local sim = Sim.new{ clients = 3, seed = seed or 3, latency = { 0.1, 0.4 }, step = 1, sync = false,
		setup = function(M, i)
			M.world.inboxSync = true
			if i == 2 then return end
			local members = {}
			for _, j in ipairs({ 1, 3 }) do
				if j ~= i then members[#members + 1] = { name = Sim.nameOf(j), rank = j == 1 and 0 or 1 } end
			end
			M.guild.Set{ name = GUILD, realm = "Test Realm", myRank = i == 1 and 0 or 1, members = members }
		end }
	for i = 1, 3 do sim:client(i):addon().Role:Refresh() end
	return sim
end

local function announcing(c)
	local ol = c:addon().OwnListing
	ol.ANN_PERIOD = { 300, 300 }
	ol.AUTO = true
	ol:StartAnnouncing()
end

local function said(c, text)
	for _, line in ipairs(c:output()) do if line:find(text, 1, true) then return true end end
	return false
end

local function noErrors(sim)
	local n = 0
	for i = 1, sim:count() do n = n + #sim:client(i).Mock.errors end
	eq(n, 0, "no Lua error in any client")
end

local function scenario(seed)
	local sim = guildSim(seed)
	local gm, applicant, officer = sim:client(1), sim:client(2), sim:client(3)
	assert(gm:addon().OwnListing:Publish(LISTING))
	for _, c in ipairs({ gm, officer }) do announcing(c) end
	sim:advance(60)
	local ok, rec = applicant:addon().Applications:Apply(KEY, 4)
	assert(ok, tostring(rec))
	assert(sim:advanceUntil(function() return rec.state == "received" end, 120), "received")
	sim:advance(30)   -- the officers' sync
	local holder, other = gm, officer
	if not gm:addon().Inbox:Get(KEY, rec.id) then holder, other = officer, gm end
	return sim, gm, applicant, officer, rec, holder, other
end

local function same(a, b, id)
	local ra, rb = a:addon().Inbox:Get(KEY, id), b:addon().Inbox:Get(KEY, id)
	notNil(ra); notNil(rb)
	eq(ra.state, rb.state)
	eq(a:addon().Inbox.Version(ra), a:addon().Inbox.Version(rb), "the same version on both officers")
end

describe("simulator: joining the guild", function()
	it("an applicant who joins by other means is accepted on his side and on both officers' sides", function()
		local sim, gm, applicant, officer, rec = scenario(31)
		eq(rec.state, "received")
		-- somebody invites him by hand: the officers' rosters list him, then he joins
		for _, c in ipairs({ gm, officer }) do
			local members = { { name = c == gm and officer.name or gm.name, rank = c == gm and 1 or 0 }, { name = applicant.name, rank = 3 } }
			c.Mock.guild.Set{ name = GUILD, realm = "Test Realm", myRank = c == gm and 0 or 1, members = members }
		end
		applicant.Mock.guild.Set{ name = GUILD, realm = "Test Realm", myRank = 3, members = { { name = gm.name, rank = 0 } } }
		eq(rec.state, "accepted", "PLAYER_GUILD_UPDATE closes it at once")
		eq(rec.why, "joined")
		truthy(said(applicant, "You joined Aurora"))
		sim:advance(90)
		for _, c in ipairs({ gm, officer }) do
			eq(c:addon().Inbox:Get(KEY, rec.id).state, "accepted", c.name)
			eq(c:addon().Inbox:Count(KEY, true), 0)
		end
		same(gm, officer, rec.id)
		noErrors(sim)
	end)
end)

describe("simulator: the guild is delisted", function()
	it("declines the applications on both officers and reaches the applicant through the DEL", function()
		local sim, gm, applicant, officer, rec = scenario(32)
		eq(rec.state, "received")
		deepEq({ gm:addon().OwnListing:Delist() }, { true, "delisted" })
		sim:advance(60)
		for _, c in ipairs({ gm, officer }) do
			eq(c:addon().Inbox:Get(KEY, rec.id).state, "declined", c.name)
			eq(c:addon().Inbox:Count(KEY, true), 0)
		end
		same(gm, officer, rec.id)
		eq(rec.state, "declined", "the DEL on the channel closed it on the applicant's side")
		eq(rec.why, "delisted")
		truthy(said(applicant, "Aurora was removed from Guild Finder"))
		local _, why = applicant:addon().Applications:Apply(KEY)
		eq(why, "nolisting", "nothing to apply to, and no cooldown in the way")
		noErrors(sim)
	end)

	it("an officer who was offline learns it at login and ends with the same inbox", function()
		local sim, gm, applicant, officer, rec = scenario(33)
		officer:setOnline(false)
		gm:addon().OwnListing:Delist()
		sim:advance(120)
		eq(officer:addon().Inbox:Get(KEY, rec.id).state, "received", "away: it has not heard")
		officer:setOnline(true)
		officer:reload()
		truthy(sim:advanceUntil(function()
			local r = officer:addon().Inbox:Get(KEY, rec.id)
			return r and r.state == "declined"
		end, 300), "it catches up after its login")
		sim:advance(60)
		same(gm, officer, rec.id)
		noErrors(sim)
	end)
end)

describe("simulator: expiry", function()
	it("an application nobody decided ends on both sides at 14 days, and the inboxes stay equal", function()
		local sim, gm, applicant, officer, rec = scenario(34)
		eq(rec.state, "received")
		local at = rec.at
		sim:setStep(600)
		sim:advance(14 * DAY - 2 * 3600)
		eq(rec.state, "received", "still open just before the 14 days")
		eq(gm:addon().Inbox:Count(KEY, true) + officer:addon().Inbox:Count(KEY, true) > 0, true)
		sim:advance(4 * 3600)
		eq(rec.state, "expired", "the applicant's timer ended it")
		truthy(said(applicant, "expired after 14 days"))
		for _, c in ipairs({ gm, officer }) do
			local r = c:addon().Inbox:Get(KEY, rec.id)
			notNil(r, c.name)
			eq(r.state, "expired", c.name)
			eq(r.upd, at + 14 * DAY, "the moment it expired, not the moment the sweep ran")
			eq(c:addon().Inbox:Count(KEY, true), 0)
		end
		same(gm, officer, rec.id)
		noErrors(sim)
	end)
end)

describe("simulator: the whole flow", function()
	it("an officer online: the application is received, declined by one officer, seen by the other, and learned by the applicant", function()
		local sim, gm, applicant, officer, rec, holder, other = scenario(35)
		eq(rec.state, "received")
		notNil(other:addon().Inbox:Get(KEY, rec.id))
		eq(holder:addon().Decisions:Decline(KEY, rec.id), true)
		sim:advance(20)
		same(gm, officer, rec.id)
		truthy(sim:advanceUntil(function() return rec.state == "declined" end, 45 * 60))
		eq(rec.why, nil, "an officer's decline is a refusal: the cooldown applies")
		eq(select(2, applicant:addon().Applications:Apply(KEY)), "cooldown")
		noErrors(sim)
	end)

	it("an officer coming online later receives the application, and a withdrawal then reaches both officers", function()
		local sim = guildSim(36)
		local gm, applicant, officer = sim:client(1), sim:client(2), sim:client(3)
		assert(gm:addon().OwnListing:Publish(LISTING))
		announcing(gm); announcing(officer)
		sim:advance(60)
		gm:setOnline(false); officer:setOnline(false)
		local ok, rec = applicant:addon().Applications:Apply(KEY)
		truthy(ok)
		sim:advance(3 * 3600)
		eq(rec.state, "sent", "nobody was there")
		officer:setOnline(true); officer:reload(); announcing(officer)
		truthy(sim:advanceUntil(function() return rec.state == "received" end, 2 * 3600), "delivered after the officer's login")
		gm:setOnline(true); gm:reload(); announcing(gm)
		truthy(sim:advanceUntil(function() return gm:addon().Inbox:Get(KEY, rec.id) ~= nil end, 300), "the Guild Master syncs at login")
		same(gm, officer, rec.id)
		truthy(applicant:addon().Applications:Withdraw())
		truthy(sim:advanceUntil(function() return not rec.wd end, 2 * 3600), "the withdrawal was confirmed")
		sim:advance(60)
		same(gm, officer, rec.id)
		eq(gm:addon().Inbox:Get(KEY, rec.id).state, "withdrawn")
		noErrors(sim)
	end)

	it("two officers in sync: every kind of closing ends with the same version on both", function()
		local sim, gm, applicant, officer, rec = scenario(37)
		-- the Guild Master invites by the panel while the officer declines at the same moment: one decision wins on both
		local a = gm:addon().Decisions
		local b = officer:addon().Decisions
		a:Invite(KEY, rec.id)
		b:Decline(KEY, rec.id)
		sim:advance(120)
		same(gm, officer, rec.id)
		eq(gm:addon().Inbox:Get(KEY, rec.id).state, officer:addon().Inbox:Get(KEY, rec.id).state)
		noErrors(sim)
	end)
end)
