-- M4.4: Invite and Decline (Data/Decisions.lua, SPEC-07 §5). Part 1 is pure Lua: what the game's messages say about an invite.
-- Part 2 runs one client as an officer: Decline, Invite in every answer the game can give (it went out, the player is
-- offline, no permission, already in a guild, nothing said), the fallback when the invite API is missing or blocked, the
-- role check and a decision overtaken by another officer. Part 3 runs the network simulator: an officer's decision reaches
-- the other officers by the sync and the applicant at its next contact.
-- The mock player is "Testchar", Horde Orc Warrior 60 on "Test Realm".

local DAY = 86400
local GUILD = "Aurora"
local KEY = "TestRealm|Horde|" .. GUILD

local function A() return AzerothGuildFinder end
local function D() return A().Decisions end
local function Inbox() return A().Inbox end

---------------------------------------------------------------------------------------------------------------------
-- Part 1: the game's messages
---------------------------------------------------------------------------------------------------------------------
describe("Decisions.Classify: what a message says about the invite of a player", function()
	local function c(text, name, source) return (D().Classify(text, name, source)) end

	it("the game's 'invited' message is ok, from the chat", function()
		eq(c("You have invited Elarin to join your guild.", "Elarin-TestRealm", "system"), "ok")
		eq(c("You have invited elarin to join your guild.", "Elarin", "system"), "ok", "names compare without case and realm")
	end)

	it("the player is offline", function()
		eq(c("No player named 'Elarin' is currently playing.", "Elarin-TestRealm", "error"), "offline")
		eq(c("No player named 'Elarin' is currently playing.", "Elarin", "system"), "offline")
		eq(c("\"Elarin\" not found.", "Elarin", "error"), "offline")
	end)

	it("the game refuses: already in a guild, already invited, no permission, internal error", function()
		eq(c("Elarin is already in a guild.", "Elarin", "error"), "refused")
		eq(c("Elarin has already been invited to a guild.", "Elarin", "system"), "refused")
		eq(c("You don't have permission to do that.", "Elarin", "error"), "refused")
		eq(c("Internal guild error.", "Elarin", "system"), "refused")
	end)

	it("a message about another player is not about this invite", function()
		isNil(c("You have invited Nym to join your guild.", "Elarin", "system"))
		isNil(c("No player named 'Nym' is currently playing.", "Elarin", "system"))
		-- from an error source a message nobody knows is a refusal (accepted only if the invite started without an error)
		eq(c("No player named 'Nym' is currently playing.", "Elarin", "error"), "refused")
	end)

	it("an unknown error message is a refusal, an unknown chat line is ignored; garbage is nothing", function()
		local kind, text = D().Classify("You are too far away.", "Elarin", "error")
		eq(kind, "refused")
		eq(text, "You are too far away.")
		isNil(c("Thrall has come online.", "Elarin", "system"))
		isNil(c("", "Elarin", "error"))
		isNil(c(nil, "Elarin", "error"))
		isNil(c(42, "Elarin", "error"))
	end)

	it("the client's own global strings win over the English ones", function()
		_G.ERR_GUILD_INVITE_S = "Hai invitato %s nella gilda."
		eq(c("Hai invitato Elarin nella gilda.", "Elarin", "system"), "ok")
		_G.ERR_GUILD_INVITE_S = nil
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 2: one client as an officer
---------------------------------------------------------------------------------------------------------------------
local function asRole(rank)
	Mock.guild.Set{ name = GUILD, myRank = rank, members = { { name = "Thrall", rank = 0 }, { name = "Garrosh", rank = 3 } } }
	A().Role:Refresh()
end
local function asOfficer() asRole(1) end

local function receive(id, extra)
	local t = GetServerTime()
	local r = { id = id or "0a1b2c3d", k = KEY, state = "received", stateRev = 2, at = t - 3600, upd = t - 3600,
		who = "Elarin-TestRealm", cls = 8, race = 5, lvl = 32, ilvl = 41, roles = 8 }
	for k, v in pairs(extra or {}) do r[k] = v end
	local stored = assert(Inbox():Receive(r))
	return stored
end

-- The results announced on the Bus: { { id, result, detail }, ... }
local results
local function listen()
	results = {}
	A().Bus:On("DECISION_RESULT", function(_, id, result, detail) results[#results + 1] = { id, result, detail } end)
end

local typed
local function stubChat()
	typed = nil
	_G.ChatFrame_OpenChat = function(text) typed = text end
end
local function unstubChat() _G.ChatFrame_OpenChat = nil end

describe("Decline", function()
	it("a received application becomes declined, with the officer's name, and the Bus says so", function()
		asOfficer(); listen()
		receive()
		local changes = {}
		A().Bus:On("INBOX_CHANGED", function(k, id, st, old, source) changes[#changes + 1] = { id, st, old, source } end)
		local ok = D():Decline(KEY, "0a1b2c3d")
		eq(ok, true)
		local rec = Inbox():Get(KEY, "0a1b2c3d")
		eq(rec.state, "declined")
		eq(rec.stateRev, 3)
		eq(rec.by, "Testchar")
		deepEq(results, { { "0a1b2c3d", "declined", nil } })
		deepEq(changes, { { "0a1b2c3d", "declined", "received", nil } }, "a local change (source nil): the sync sends it to the officers")
	end)

	it("the Guild Master can decline too", function()
		asRole(0)
		receive()
		eq(D():Decline(KEY, "0a1b2c3d"), true)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "declined")
	end)

	it("a member, a character without a guild or an officer of another guild cannot", function()
		asOfficer()
		receive()
		asRole(3)
		deepEq({ D():Decline(KEY, "0a1b2c3d") }, { false, "role" })
		Mock.guild.Leave(); A().Role:Refresh()
		deepEq({ D():Decline(KEY, "0a1b2c3d") }, { false, "role" })
		Mock.guild.Set{ name = "Iron Wolves", myRank = 1, members = { { name = "Thrall", rank = 0 } } }; A().Role:Refresh()
		deepEq({ D():Decline(KEY, "0a1b2c3d") }, { false, "role" })
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received", "nothing changed")
	end)

	it("an unknown id, a closed record and an expired one cannot be declined", function()
		asOfficer()
		receive("0a1b2c3d", { state = "accepted", stateRev = 3 })
		receive("0a1b2c3e", { at = GetServerTime() - 15 * DAY, upd = GetServerTime() - 15 * DAY })
		deepEq({ D():Decline(KEY, "ffffffff") }, { false, "unknown" })
		deepEq({ D():Decline(KEY, "0a1b2c3d") }, { false, "state" })
		deepEq({ D():Decline(KEY, "0a1b2c3e") }, { false, "state" })
		eq(Inbox():Get(KEY, "0a1b2c3e").state, "expired", "the check swept it")
	end)
end)

describe("Invite: the game's own call", function()
	it("the invite goes out and the game says so: accepted at once", function()
		asOfficer(); listen()
		receive()
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "accepted" })
		deepEq(Mock.guild.invites, { "Elarin-TestRealm" })
		local rec = Inbox():Get(KEY, "0a1b2c3d")
		eq(rec.state, "accepted")
		eq(rec.by, "Testchar")
		deepEq(results, { { "0a1b2c3d", "accepted", nil } })
		eq(D():IsBusy("0a1b2c3d"), false)
		eq(#Mock.errors, 0)
	end)

	it("the game says nothing: the application waits 3 seconds, then counts as sent", function()
		asOfficer(); listen()
		Mock.guild.inviteReply = "silent"
		receive()
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "pending" })
		eq(D():IsBusy("0a1b2c3d"), true)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received", "not yet: an error could still come")
		deepEq({ D():Decline(KEY, "0a1b2c3d") }, { false, "busy" })
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { false, "busy" })
		Mock.Advance(2)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received")
		Mock.Advance(1.5)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "accepted")
		eq(D():IsBusy("0a1b2c3d"), false)
		deepEq(results, { { "0a1b2c3d", "accepted", nil } })
	end)

	it("the player is offline: the game says so, nothing changes, and the officer can try again", function()
		asOfficer(); listen()
		Mock.guild.inviteReply = "offline"
		receive()
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "offline" })
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received")
		eq(results[1][2], "offline")
		eq(D():IsBusy("0a1b2c3d"), false)
		Mock.Advance(10)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received", "the quiet timer has nothing to accept")
		Mock.guild.inviteReply = "ok"
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "accepted" })
	end)

	it("no permission and already in a guild are refusals with the game's words", function()
		asOfficer(); listen()
		receive()
		Mock.guild.inviteReply = "denied"
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "refused" })
		deepEq(results[1], { "0a1b2c3d", "refused", "You don't have permission to do that." })
		Mock.guild.inviteReply = "inguild"
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "refused" })
		deepEq(results[2], { "0a1b2c3d", "refused", "Elarin is already in a guild." })
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received")
		Mock.Advance(10)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received")
	end)

	it("an error about something else in the next 3 seconds also stops it: accepted only without an error", function()
		asOfficer(); listen()
		Mock.guild.inviteReply = "silent"
		receive()
		D():Invite(KEY, "0a1b2c3d")
		Mock.Fire("UI_ERROR_MESSAGE", 1, "You are too far away.")
		eq(results[1][2], "refused")
		Mock.Advance(5)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received")
	end)

	it("the invite of another application's player does not settle this one", function()
		asOfficer(); listen()
		Mock.guild.inviteReply = "silent"
		receive()
		D():Invite(KEY, "0a1b2c3d")
		Mock.Fire("CHAT_MSG_SYSTEM", "No player named 'Nym' is currently playing.")
		Mock.Fire("CHAT_MSG_SYSTEM", "Thrall has come online.")
		eq(#results, 0)
		eq(D():IsBusy("0a1b2c3d"), true)
	end)

	it("another officer decided first while the invite was watched: changed, and the decision stays", function()
		asOfficer(); listen()
		Mock.guild.inviteReply = "silent"
		receive()
		D():Invite(KEY, "0a1b2c3d")
		-- the other officer's decline arrives through the sync (a record that wins)
		local theirs = { id = "0a1b2c3d", k = KEY, state = "declined", stateRev = 3, at = GetServerTime() - 3600,
			upd = GetServerTime(), who = "Elarin-TestRealm", cls = 8, race = 5, lvl = 32, by = "Thrall" }
		Inbox():Merge(KEY, theirs)
		Mock.Advance(4)
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "declined")
		eq(results[#results][2], "changed")
	end)

	it("the Guild Master invites too; a member, an unknown id or an expired record cannot", function()
		asRole(0); listen()
		receive()
		eq(select(2, D():Invite(KEY, "0a1b2c3d")), "accepted")
		eq(#Mock.guild.invites, 1)
		asRole(3)
		receive("0a1b2c3e", { who = "Nym-TestRealm" })
		deepEq({ D():Invite(KEY, "0a1b2c3e") }, { false, "role" })
		asOfficer()
		deepEq({ D():Invite(KEY, "ffffffff") }, { false, "unknown" })
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { false, "state" })
		receive("0a1b2c3f", { who = "Old-TestRealm", at = GetServerTime() - 15 * DAY, upd = GetServerTime() - 15 * DAY })
		deepEq({ D():Invite(KEY, "0a1b2c3f") }, { false, "state" })
		eq(#Mock.guild.invites, 0, "nothing more went out (the list restarts with each Mock.guild.Set)")
	end)

	it("a name the client cannot take is refused before anything is sent", function()
		asOfficer()
		receive("0a1b2c3d", { who = "Bad Name" })
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { false, "name" })
		eq(#Mock.guild.invites, 0)
		eq(D():IsBusy("0a1b2c3d"), false)
	end)
end)

describe("Invite: the fallback", function()
	it("a blocked call (ADDON_ACTION_FORBIDDEN) opens '/ginvite Name ' in the chat box and offers 'Mark as invited'", function()
		asOfficer(); listen(); stubChat()
		Mock.guild.inviteReply = "blocked"
		receive()
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "manual" })
		eq(typed, "/ginvite Elarin-TestRealm ")
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received", "nothing is accepted: the invite did not go out")
		eq(D():IsManual("0a1b2c3d"), true)
		eq(D():IsBusy("0a1b2c3d"), false)
		eq(D():Mode(), "manual", "the rest of the session goes straight to the fallback")
		deepEq(results, { { "0a1b2c3d", "manual", "chat" } })
		unstubChat()
	end)

	it("once blocked the game's call is not tried again", function()
		asOfficer(); stubChat()
		Mock.guild.inviteReply = "blocked"
		receive("0a1b2c3d"); receive("0a1b2c3e", { who = "Nym-TestRealm" })
		D():Invite(KEY, "0a1b2c3d")
		typed = nil
		Mock.guild.inviteReply = "ok"   -- would go out if the call were tried
		deepEq({ D():Invite(KEY, "0a1b2c3e") }, { true, "manual" })
		eq(typed, "/ginvite Nym-TestRealm ")
		eq(#Mock.guild.invites, 0)
		unstubChat()
	end)

	it("'Mark as invited' accepts, with the officer's name", function()
		asOfficer(); listen(); stubChat()
		Mock.guild.inviteReply = "blocked"
		receive()
		D():Invite(KEY, "0a1b2c3d")
		eq(D():MarkInvited(KEY, "0a1b2c3d"), true)
		local rec = Inbox():Get(KEY, "0a1b2c3d")
		eq(rec.state, "accepted")
		eq(rec.by, "Testchar")
		eq(D():IsManual("0a1b2c3d"), false)
		eq(results[#results][2], "accepted")
		deepEq({ D():MarkInvited(KEY, "0a1b2c3d") }, { false, "state" })
		unstubChat()
	end)

	it("the game's 'invited' message after the officer pressed Enter accepts by itself, for 90 seconds", function()
		asOfficer(); listen(); stubChat()
		Mock.guild.inviteReply = "blocked"
		receive("0a1b2c3d"); receive("0a1b2c3e", { who = "Nym-TestRealm" })
		D():Invite(KEY, "0a1b2c3d")
		D():Invite(KEY, "0a1b2c3e")
		Mock.Fire("CHAT_MSG_SYSTEM", "You have invited Nym to join your guild.")
		eq(Inbox():Get(KEY, "0a1b2c3e").state, "accepted")
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received", "the message was about Nym")
		Mock.Advance(95)
		Mock.Fire("CHAT_MSG_SYSTEM", "You have invited Elarin to join your guild.")
		eq(Inbox():Get(KEY, "0a1b2c3d").state, "received", "too late: Mark as invited is still there")
		eq(D():IsManual("0a1b2c3d"), true)
		unstubChat()
	end)

	it("a missing C_GuildInfo.Invite goes straight to the fallback", function()
		asOfficer(); stubChat()
		local saved = _G.C_GuildInfo.Invite
		_G.C_GuildInfo.Invite = nil
		receive()
		eq(D():Mode(), "manual")
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "manual" })
		eq(typed, "/ginvite Elarin-TestRealm ")
		_G.C_GuildInfo.Invite = saved
		unstubChat()
	end)

	it("a restricted call (the client refuses it with an error) goes to the fallback", function()
		asOfficer(); stubChat(); listen()
		local saved = _G.C_GuildInfo.Invite
		_G.C_GuildInfo.Invite = function() error("This action is forbidden: restricted by the client") end
		receive()
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "manual" })
		eq(D():Mode(), "manual")
		_G.C_GuildInfo.Invite = saved
		unstubChat()
	end)

	it("when even the chat box cannot be opened the panel is told to ask the officer to invite by hand", function()
		asOfficer(); listen()
		_G.ChatFrame_OpenChat = nil
		Mock.guild.inviteReply = "blocked"
		receive()
		deepEq({ D():Invite(KEY, "0a1b2c3d") }, { true, "manual" })
		deepEq(results[#results], { "0a1b2c3d", "manual", "hand" })
		eq(D():IsManual("0a1b2c3d"), true, "Mark as invited still works")
	end)

	it("a record that closes in the meantime drops the fallback", function()
		asOfficer(); stubChat()
		Mock.guild.inviteReply = "blocked"
		receive()
		D():Invite(KEY, "0a1b2c3d")
		eq(D():IsManual("0a1b2c3d"), true)
		Inbox():Withdraw(KEY, "0a1b2c3d", "Elarin-TestRealm")   -- the applicant withdrew
		eq(D():IsManual("0a1b2c3d"), false)
		unstubChat()
	end)
end)

describe("Decisions: the debug line never prints a name", function()
	it("shows counters and the mode", function()
		asOfficer(); stubChat()
		receive()
		D():Invite(KEY, "0a1b2c3d")
		local line = D():DebugLines()[1]
		contains(line, "Decisions: invite by the game's call")
		contains(line, "tried 1")
		eq(line:find("Elarin", 1, true), nil)
		unstubChat()
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Part 3: the simulator
---------------------------------------------------------------------------------------------------------------------
local LISTING = { sub = "Friendly raiders", lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380,
	rec = 1, apps = true, want = { [0] = 8 }, newb = true, minL = 10, desc = "We raid on weekends.", disc = "aurora1",
	cont = { "Simaa" } }

-- Client 1 = Guild Master, client 2 = the applicant (no guild), client 3 = an officer.
local function guildSim(seed)
	local sim = Sim.new{ clients = 3, seed = seed or 3, latency = { 0.1, 0.4 }, step = 1, sync = false,
		setup = function(M, i)
			M.world.inboxSync = true   -- the officers' inbox sync runs (it is off in a simulator without the catalog sync)
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

-- Both officers online, one application received by one of them and synced to the other; returns the sim, the three clients,
-- the applicant's record and the officer clients in order { holder, other }.
local function scenario(seed)
	local sim = guildSim(seed)
	local gm, applicant, officer = sim:client(1), sim:client(2), sim:client(3)
	assert(gm:addon().OwnListing:Publish(LISTING))
	for _, c in ipairs({ gm, officer }) do announcing(c) end
	sim:advance(60)
	local ap = applicant:addon()
	local ok, rec = ap.Applications:Apply(KEY, 4)
	assert(ok, tostring(rec))
	assert(sim:advanceUntil(function() return rec.state == "received" end, 120), "received")
	sim:advance(30)   -- the officers' sync
	local holder, other = gm, officer
	if not gm:addon().Inbox:Get(KEY, rec.id) then holder, other = officer, gm end
	return sim, gm, applicant, officer, rec, holder, other
end

describe("simulator", function()
	it("a decline reaches the other officer by the sync and the applicant at its next contact", function()
		local sim, gm, applicant, officer, rec, holder, other = scenario(11)
		notNil(holder:addon().Inbox:Get(KEY, rec.id))
		notNil(other:addon().Inbox:Get(KEY, rec.id), "the other officer has the application too")
		eq(holder:addon().Decisions:Decline(KEY, rec.id), true)
		eq(holder:addon().Inbox:Get(KEY, rec.id).state, "declined")
		sim:advance(20)
		local theirs = other:addon().Inbox:Get(KEY, rec.id)
		eq(theirs.state, "declined", "the other officer sees the decision within seconds")
		eq(theirs.by, holder.name, "and who took it")
		eq(rec.state, "received", "the applicant does not know yet")
		truthy(sim:advanceUntil(function() return rec.state == "declined" end, 45 * 60), "the applicant learns it at its next contact")
		truthy(said(applicant, "Your application to Aurora was declined."))
		eq(select(2, applicant:addon().Applications:Apply(KEY)), "cooldown", "APP-06: a decline blocks a new application for 7 days")
		eq(#applicant.Mock.errors + #gm.Mock.errors + #officer.Mock.errors, 0)
	end)

	it("an invite that went out is accepted, synced, and the applicant is told to check the guild invite", function()
		local sim, gm, applicant, officer, rec, holder, other = scenario(12)
		local ok, how = holder:addon().Decisions:Invite(KEY, rec.id)
		truthy(ok)
		eq(how, "accepted", "the mock game says 'You have invited ...'")
		eq(#holder.Mock.guild.invites, 1)
		eq(holder.Mock.guild.invites[1], applicant:fullName())
		sim:advance(20)
		eq(other:addon().Inbox:Get(KEY, rec.id).state, "accepted")
		truthy(sim:advanceUntil(function() return rec.state == "accepted" end, 45 * 60))
		truthy(said(applicant, "Your application to Aurora was accepted: check your guild invite."))
		eq(#applicant.Mock.errors + #gm.Mock.errors + #officer.Mock.errors, 0)
	end)

	it("an invite the game refused (the player is offline) changes nothing anywhere", function()
		local sim, gm, applicant, officer, rec, holder, other = scenario(13)
		holder.Mock.guild.inviteReply = "offline"
		local ok, how = holder:addon().Decisions:Invite(KEY, rec.id)
		truthy(ok)
		eq(how, "offline")
		sim:advance(60)
		eq(holder:addon().Inbox:Get(KEY, rec.id).state, "received")
		eq(other:addon().Inbox:Get(KEY, rec.id).state, "received")
		eq(rec.state, "received")
	end)

	it("an officer who was away learns the decision at login, and a decision taken against his own stays one", function()
		local sim, gm, applicant, officer, rec, holder, other = scenario(14)
		other:setOnline(false)
		eq(holder:addon().Decisions:Decline(KEY, rec.id), true)
		sim:advance(120)
		eq(other:addon().Inbox:Get(KEY, rec.id).state, "received", "away: it has not heard")
		other:setOnline(true)
		other:reload()
		truthy(sim:advanceUntil(function() return other:addon().Inbox:Get(KEY, rec.id).state == "declined" end, 120),
			"it catches up after its login")
	end)
end)
