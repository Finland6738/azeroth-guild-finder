-- Own listing and guild sync (M3.1, SPEC-06 §3-§5, SPEC-02 §5, §7, ADR 0021): draft, publish, rev ordering, the Guild
-- Master check against the roster (INT-02), delist, Guild Master change, the publish limit, GLREQ, and a small
-- simulator scenario in which the members receive the Guild Master's listing.
-- The mock player is "Testchar", Horde, on "Test Realm": the guild key is "TestRealm|Horde|<guild>".
local GUILD = "Iron Wolves"
local KEY = "TestRealm|Horde|" .. GUILD
local OWN = "0badc0de"

local function OL() return AzerothGuildFinder.OwnListing end
local function Cat() return AzerothGuildFinder.Catalog end
local function Bus() return AzerothGuildFinder.Bus end

-- A complete listing (summary and detail fields) as the editor would hand it over.
local function fields(extra)
	local t = { sub = "Friendly raiders", lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380,
		rec = 1, apps = true, want = { [0] = 8 }, newb = true, minL = 30, desc = "We raid on weekends.", disc = "wolves1",
		cont = { "Thrall" }, note = "Voice required" }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

-- A GLIST as the Guild Master's client sends it.
local function glist(rev, extra)
	local t = fields({ t = "GLIST", k = KEY, rev = rev, upd = 1767000000 + rev, first = 1766000000, own = OWN })
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

-- The player is a member (rank 3) of GUILD whose Guild Master is Thrall; `leader` overrides the Guild Master's name.
local function asMember(leader)
	Mock.guild.Set{ name = GUILD, myRank = 3, members = {
		{ name = leader or "Thrall", rank = 0 }, { name = "Jaina", rank = 1 }, { name = "Garrosh", rank = 3 } } }
end

local function asLeader()
	Mock.guild.Set{ name = GUILD, myRank = 0, members = { { name = "Jaina", rank = 1 }, { name = "Garrosh", rank = 3 } } }
end

-- Replaces Transport:Send with a recorder: sent[i] = { dist, msg, opts }.
local sent
local function capture()
	sent = {}
	AzerothGuildFinder.Transport.Send = function(_, dist, msg, opts)
		sent[#sent + 1] = { dist = dist, msg = msg, opts = opts }
		return { dist = dist }
	end
end
local function sentOf(t, dist)
	local out = {}
	for _, s in ipairs(sent) do
		if s.msg.t == t and (not dist or s.dist == dist) then out[#out + 1] = s end
	end
	return out
end

local function receive(msg, sender, dist)
	return OL():OnMessage(msg, sender, dist or "GUILD")
end

local function changes()
	local seen = {}
	Bus():On("OWN_LISTING_CHANGED", function(what, k) seen[#seen + 1] = { what, k } end)
	return seen
end

describe("draft and publish (Guild Master)", function()
	it("keeps a draft per guild and refuses it to anybody but the Guild Master", function()
		asLeader()
		local ok = OL():SaveDraft(fields({ sub = "Work in progress", rev = 99, own = "ffffffff" }))
		eq(ok, true)
		local d = OL():Draft()
		eq(d.sub, "Work in progress")
		eq(d.k, KEY)
		isNil(d.rev) isNil(d.own)
		eq(AzerothGuildFinderCharDB.ownListing.draft.sub, "Work in progress")
		Mock.guild.SetMyRank(1)
		local why
		ok, why = OL():SaveDraft(fields())
		eq(ok, false) eq(why, "not-leader")
		Mock.guild.Set{ name = "Other Guild", myRank = 0 }
		isNil(OL():Draft(), "a draft belongs to its guild")
	end)

	it("publishes: rev 1, upd, first and a new ownerId; GLIST over GUILD, ANN on the channel, detail in the catalog", function()
		asLeader()
		capture()
		local seen = changes()
		OL():SaveDraft(fields())
		local ok, why = OL():Publish()
		eq(ok, true) eq(why, "published")
		local copy = OL():Get()
		eq(copy.rev, 1)
		eq(copy.upd, GetServerTime())
		eq(copy.first, GetServerTime())
		matches(copy.own, "^%x%x%x%x%x%x%x%x$")
		isNil(copy.del)
		isNil(OL():Draft(), "the draft becomes the published version")
		eq(OL():Status(), "listed")
		local g = sentOf("GLIST", "GUILD")
		eq(#g, 1)
		eq(g[1].msg.k, KEY) eq(g[1].msg.rev, 1) eq(g[1].msg.desc, "We raid on weekends.")
		local a = sentOf("ANN", "CHANNEL")
		eq(#a, 1)
		eq(a[1].msg.c, 1, "the Guild Master is a contact")
		isNil(a[1].msg.desc, "the detail never travels in an ANN")
		local entry, status = Cat():Get(KEY)
		eq(status, "listed")
		eq(entry.sum.rev, 1)
		eq(entry.det.disc, "wolves1", "the Guild Master can answer DETREQ")
		deepEq(seen[#seen], { "published", KEY })
	end)

	it("keeps first and own and raises rev on every publication", function()
		asLeader()
		capture()
		OL():Publish(fields())
		local first = OL():Get()
		Mock.Advance(OL().PUBLISH_GAP + 1)
		OL():Publish(fields({ sub = "Now recruiting healers" }))
		local second = OL():Get()
		eq(second.rev, 2)
		eq(second.first, first.first)
		eq(second.own, first.own)
		eq(second.sub, "Now recruiting healers")
		eq(Cat():Get(KEY).sum.sub, "Now recruiting healers")
	end)

	it("refuses an incomplete listing", function()
		asLeader()
		capture()
		local ok, why = OL():Publish(fields({ tags = {} }))
		eq(ok, false) eq(why, "incomplete")
		eq(#sent, 0)
		isNil(OL():Get())
	end)

	it("allows one publication every 5 minutes, also after /reload; drafts have no limit", function()
		asLeader()
		capture()
		eq(OL():Publish(fields()), true)
		local ok, why, wait = OL():Publish(fields({ sub = "Too soon" }))
		eq(ok, false) eq(why, "rate")
		eq(wait, OL().PUBLISH_GAP)
		eq(OL():SaveDraft(fields({ sub = "Draft 1" })), true)
		eq(OL():SaveDraft(fields({ sub = "Draft 2" })), true)
		matches(OL():Explain(why, wait), "5:00")
		Mock.Advance(120)
		Mock.Reload()
		capture()
		ok, why, wait = OL():Publish()
		eq(why, "rate")
		truthy(wait <= OL().PUBLISH_GAP - 119 and wait >= OL().PUBLISH_GAP - 122, "wait " .. tostring(wait))
		eq(OL():Draft().sub, "Draft 2", "the draft survives /reload")
		Mock.Advance(wait + 1)
		ok = OL():Publish()
		eq(ok, true)
		eq(OL():Get().sub, "Draft 2")
		eq(OL():Get().rev, 2)
	end)

	it("asks IsGuildLeader() again before saving: a demoted Guild Master saves nothing", function()
		asLeader()
		capture()
		OL():SaveDraft(fields())
		Mock.guild.members[1].rank = 0   -- Jaina takes the guild; the role of this client is not refreshed yet
		Mock.guild.myRank = 3
		local ok, why = OL():Publish()
		eq(ok, false) eq(why, "not-leader")
		eq(#sent, 0)
		isNil(OL():Get())
		matches(OL():Explain(why), "no longer the Guild Master")
		ok, why = OL():Delist()
		eq(why, "not-leader")
	end)
end)

describe("GLIST: the Guild Master check against the roster (INT-02)", function()
	it("accepts the Guild Master's listing and puts it in the catalog", function()
		asMember()
		capture()
		local seen = changes()
		local ok, why = receive(glist(3), "Thrall-TestRealm")
		eq(ok, true) eq(why, "accepted")
		local copy = OL():Get()
		eq(copy.rev, 3) eq(copy.own, OWN) eq(copy.desc, "We raid on weekends.")
		eq(AzerothGuildFinderCharDB.ownListing.published.rev, 3)
		local entry = Cat():Get(KEY)
		eq(entry.sum.rev, 3)
		eq(entry.det.rev, 3)
		deepEq(seen[#seen], { "received", KEY })
		eq(OL().state.stats.accepted, 1)
	end)

	it("refuses a listing from anybody else, an officer included", function()
		asMember()
		capture()
		local ok, why = receive(glist(3), "Jaina-TestRealm")
		eq(ok, false) eq(why, "not-leader")
		ok, why = receive(glist(4), "Garrosh")
		eq(why, "not-leader")
		isNil(OL():Get())
		isNil(Cat():Get(KEY))
		eq(OL().state.stats.refused, 2)
	end)

	it("ignores a GLIST that does not come over GUILD, and the listing of another guild", function()
		asMember()
		capture()
		isNil(receive(glist(3), "Thrall", "CHANNEL"))
		isNil(receive(glist(3), "Thrall", "WHISPER"))
		isNil(OL():Get())
		local ok, why = receive(glist(3, { k = "TestRealm|Horde|Other Guild" }), "Thrall")
		eq(ok, false) eq(why, "foreign")
	end)

	it("orders copies by rev, then upd (INT-01): an older or equal GLIST changes nothing", function()
		asMember()
		capture()
		receive(glist(5), "Thrall")
		local ok, why = receive(glist(4, { sub = "Old text" }), "Thrall")
		eq(ok, false) eq(why, "older")
		ok, why = receive(glist(5), "Thrall")
		eq(ok, false) eq(why, "unchanged")
		ok = receive(glist(5, { upd = 1767000099, sub = "Same rev, later edit" }), "Thrall")
		eq(ok, true)
		eq(OL():Get().sub, "Same rev, later edit")
		ok = receive(glist(6, { sub = "Newest" }), "Thrall")
		eq(ok, true)
		eq(OL():Get().sub, "Newest")
		eq(Cat():Get(KEY).sum.sub, "Newest")
	end)

	it("waits for the roster when it is not loaded yet, then checks the sender", function()
		asMember()
		capture()
		local members = Mock.guild.members
		Mock.guild.members = {}   -- the roster shows only this character: no Guild Master known yet
		local ok, why = receive(glist(2), "Thrall")
		eq(ok, false) eq(why, "roster")
		isNil(OL():Get())
		Mock.guild.members = members
		Mock.Advance(0.5)   -- GuildRoster() -> GUILD_ROSTER_UPDATE on a later frame
		eq(OL():Get().rev, 2)
		isNil(OL().state.pending)
	end)

	it("drops a waiting GLIST from somebody who turns out not to be the Guild Master", function()
		asMember()
		capture()
		local members = Mock.guild.members
		Mock.guild.members = {}
		receive(glist(2), "Garrosh")
		Mock.guild.members = members
		Mock.Fire("GUILD_ROSTER_UPDATE")
		isNil(OL():Get())
		eq(OL().state.stats.refused, 1)
	end)

	it("ignores its own GLIST sent back by the server", function()
		asLeader()
		capture()
		OL():Publish(fields())
		local ok, why = receive(glist(9), "Testchar")
		eq(ok, false) eq(why, "self")
		eq(OL():Get().rev, 1)
	end)
end)

describe("delist", function()
	it("is a revision of its own: GLIST with del, DEL on the channel, the catalog keeps a tombstone", function()
		asLeader()
		capture()
		OL():Publish(fields())
		local seen = changes()
		local ok, why = OL():Delist()
		eq(ok, true) eq(why, "delisted")
		local copy = OL():Get()
		eq(copy.rev, 2) eq(copy.del, true)
		eq(copy.sub, "Friendly raiders", "the content stays for a one-click republish")
		eq(OL():Status(), "delisted")
		local g = sentOf("GLIST", "GUILD")
		eq(g[#g].msg.del, true) eq(g[#g].msg.rev, 2)
		local d = sentOf("DEL", "CHANNEL")
		eq(#d, 1) eq(d[1].msg.k, KEY) eq(d[1].msg.rev, 2)
		local _, status = Cat():Get(KEY)
		eq(status, "delisted")
		deepEq(seen[#seen], { "delisted", KEY })
		ok, why = OL():Delist()
		eq(ok, false) eq(why, "not-listed")
	end)

	it("is not rate limited, and publishing again relists with a higher rev", function()
		asLeader()
		capture()
		OL():Publish(fields())
		eq(OL():Delist(), true)
		eq((OL():Publish()), false, "the publish limit still counts from the last publication")
		Mock.Advance(OL().PUBLISH_GAP + 1)
		local ok = OL():Publish()
		eq(ok, true)
		local copy = OL():Get()
		eq(copy.rev, 3) isNil(copy.del)
		local _, status = Cat():Get(KEY)
		eq(status, "listed")
	end)

	it("reaches the members: their copy and their catalog are withdrawn", function()
		asMember()
		capture()
		receive(glist(3), "Thrall")
		local ok, why = receive(glist(4, { del = true }), "Thrall")
		eq(ok, true) eq(why, "delisted")
		eq(OL():Status(), "delisted")
		local entry, status = Cat():Get(KEY)
		eq(status, "delisted")
		eq(entry.delRev, 4)
		-- a late ANN of the withdrawn revision cannot bring it back
		Cat():PutSummary(glist(3, { t = "ANN" }), { dist = "CHANNEL", sender = "Somebody" })
		eq(select(2, Cat():Get(KEY)), "delisted")
	end)

	it("a member relays the DEL only if it announced the guild itself", function()
		asMember()
		capture()
		receive(glist(3), "Thrall")
		Mock.Advance(31)   -- no ANN of rev 3 heard: this member relays it on the channel
		eq(#sentOf("ANN", "CHANNEL"), 1)
		receive(glist(4, { del = true }), "Thrall")
		Mock.Advance(31)
		local d = sentOf("DEL", "CHANNEL")
		eq(#d, 1) eq(d[1].msg.rev, 4)
		OL():Reset()   -- a member that never announced it
		capture()
		receive(glist(6), "Thrall")
		receive(glist(7, { del = true }), "Thrall")
		Mock.Advance(31)
		eq(#sentOf("DEL"), 0)
	end)
end)

describe("relay on the channel (SPEC-02 §5)", function()
	it("is suppressed when the ANN of that revision was already heard", function()
		asMember()
		capture()
		AzerothGuildFinder.Sync:OnMessage(glist(3, { t = "ANN", c = 1 }), "Thrall", "CHANNEL")
		receive(glist(3), "Thrall")
		Mock.Advance(31)
		eq(#sentOf("ANN"), 0)
		eq(OL().state.stats.relaysSuppressed, 1)
	end)

	it("an officer relays with the contact flag", function()
		Mock.guild.Set{ name = GUILD, myRank = 1, members = { { name = "Thrall", rank = 0 } } }
		capture()
		receive(glist(3), "Thrall")
		Mock.Advance(31)
		local a = sentOf("ANN", "CHANNEL")
		eq(#a, 1) eq(a[1].msg.c, 1) eq(a[1].msg.rev, 3)
	end)
end)

describe("Guild Master change (SPEC-06 §5)", function()
	it("refuses the old Guild Master as soon as the roster names a new one", function()
		asMember()
		capture()
		receive(glist(3), "Thrall")
		Mock.guild.members[1].rank = 1   -- Thrall steps down
		Mock.guild.members[2].rank = 0   -- Jaina leads
		Mock.Fire("GUILD_RANKS_UPDATE")
		local ok, why = receive(glist(4, { sub = "Old leader" }), "Thrall")
		eq(ok, false) eq(why, "not-leader")
		ok = receive(glist(4, { sub = "New leader" }), "Jaina")
		eq(ok, true)
		eq(OL():Get().sub, "New leader")
		eq(OL():Get().own, OWN)
	end)

	it("the new Guild Master edits the guild copy: same ownerId and first, the next rev", function()
		asMember()
		capture()
		receive(glist(3), "Thrall")
		Mock.guild.members[1].rank = 1
		Mock.guild.SetMyRank(0)
		eq(AzerothGuildFinder.Role:Get(), "gm")
		local ok = OL():Publish(fields({ sub = "Under new management" }))
		eq(ok, true)
		local copy = OL():Get()
		eq(copy.rev, 4) eq(copy.own, OWN) eq(copy.first, 1766000000)
		eq(Cat():Get(KEY).sum.own, OWN, "other clients keep accepting it (INT-03)")
	end)

	it("a new Guild Master without a guild copy starts from the public catalog", function()
		asLeader()
		capture()
		Cat():PutSummary(glist(7, { t = "ANN" }), { dist = "CHANNEL", sender = "Thrall" })
		local ok = OL():Publish(fields())
		eq(ok, true)
		eq(OL():Get().rev, 8) eq(OL():Get().own, OWN)
	end)

	it("the old Guild Master keeps the copy read-only", function()
		asLeader()
		capture()
		OL():Publish(fields())
		Mock.guild.members[1].rank = 0
		Mock.guild.SetMyRank(1)
		eq(OL():Get().rev, 1)
		local ok, why = OL():SaveDraft(fields())
		eq(why, "not-leader")
	end)
end)

describe("GLREQ", function()
	it("a member asks once at login; the Guild Master answers with one GLIST for everybody", function()
		asMember()
		capture()
		eq(OL():Request(), true)
		local r = sentOf("GLREQ", "GUILD")
		eq(#r, 1) eq(r[1].msg.rev, 0)
		local ok, why = OL():Request()
		eq(ok, false) eq(why, "rate")
		-- the Guild Master's side
		Mock.guild.Set{ name = GUILD, myRank = 0, members = { { name = "Garrosh", rank = 3 } } }
		OL():Reset()
		capture()
		eq(OL():Publish(fields()), true)
		sent = {}
		receive({ t = "GLREQ", rev = 0 }, "Garrosh")
		receive({ t = "GLREQ", rev = 0 }, "Jaina")
		receive({ t = "GLREQ", rev = 1 }, "Vol'jin")   -- already up to date: no answer needed for it
		Mock.Advance(OL().REPLY_DELAY + 0.5)
		eq(#sentOf("GLIST", "GUILD"), 1)
		receive({ t = "GLREQ", rev = 0 }, "Rexxar")
		Mock.Advance(OL().REPLY_DELAY + 0.5)
		eq(#sentOf("GLIST", "GUILD"), 1, "one answer per REPLY_GAP")
		Mock.Advance(OL().REPLY_GAP)
		eq(#sentOf("GLIST", "GUILD"), 2)
	end)

	it("only the Guild Master answers", function()
		asMember()
		capture()
		receive(glist(3), "Thrall")
		sent = {}
		receive({ t = "GLREQ", rev = 0 }, "Garrosh")
		Mock.Advance(40)
		eq(#sentOf("GLIST"), 0)
	end)

	it("is skipped when another member asked for the same or an older revision first", function()
		asMember()
		OL().AUTO = true
		capture()
		eq(OL():ScheduleRequest(), true)
		receive({ t = "GLREQ", rev = 0 }, "Garrosh")
		Mock.Advance(OL().REQUEST_DELAY[2] + 1)
		eq(#sentOf("GLREQ"), 0)
		eq(OL().state.stats.requestsSuppressed, 1)
	end)

	it("a GLREQ still in the queue is withdrawn when another member asks the same first", function()
		asMember()
		local T = AzerothGuildFinder.Transport
		eq(OL():Request(), true)
		eq(T:Pending("GUILD"), 1)
		receive({ t = "GLREQ", rev = 0 }, "Garrosh")
		eq(T:Pending("GUILD"), 0)
		eq(OL().state.stats.requestsSent, 0)
		eq(OL().state.stats.requestsSuppressed, 1)
	end)

	it("is sent when the public catalog shows a newer revision than the guild copy", function()
		asMember()
		OL().AUTO = true
		capture()
		receive(glist(3), "Thrall")
		Mock.Advance(31)
		sent = {}
		AzerothGuildFinder.Sync:OnMessage(glist(5, { t = "ANN" }), "Thrall", "CHANNEL")
		Mock.Advance(OL().REQUEST_DELAY[2] + 1)
		local r = sentOf("GLREQ", "GUILD")
		eq(#r, 1) eq(r[1].msg.rev, 3)
	end)
end)

describe("/gf debug publish and delist", function()
	it("publish and withdraw the listing in development builds, through the normal rules", function()
		asLeader()
		capture()
		Mock.ClearOutput()
		Mock.Slash("/gf debug publish")
		eq(OL():Get().sub, OL().SAMPLE.sub)
		local out = Mock.PlainOutput()
		matches(out[#out], "Listing published")
		Mock.Slash("/gf debug publish")
		out = Mock.PlainOutput()
		matches(out[#out], "You can publish again in 5:00")
		Mock.Slash("/gf debug delist")
		eq(OL():Status(), "delisted")
		matches(Mock.PlainOutput()[#Mock.PlainOutput()], "removed from Guild Finder")
	end)

	it("are refused by release builds", function()
		asLeader()
		capture()
		AzerothGuildFinder.Config.DEV = false
		Mock.Slash("/gf debug publish")
		matches(Mock.PlainOutput()[#Mock.PlainOutput()], "only work in development builds")
		isNil(OL():Get())
		eq(#sent, 0)
	end)

	it("show the guild copy in /gf debug without names", function()
		asMember()
		capture()
		receive(glist(3), "Thrall")
		Mock.ClearOutput()
		Mock.Slash("/gf debug")
		local text = table.concat(Mock.PlainOutput(), " / ")
		matches(text, "Own listing: guild copy rev 3 %(listed%)")
		eq(text:find("Thrall", 1, true), nil)
		eq(text:find(GUILD, 1, true), nil)
	end)
end)

describe("simulator: a guild with the addon", function()
	it("members receive the Guild Master's listing and refuse a forged one; a guildless client sees it", function()
		-- 1 = Guild Master, 2 and 3 = members, 4 = no guild. Each member's roster names client 1 as the Guild Master.
		local sim = Sim.new{ clients = 4, sync = false, seed = 31, setup = function(M, i)
			if i == 4 then return end
			local others = {}
			for j = 1, 3 do
				if j ~= i then others[#others + 1] = { name = Sim.nameOf(j), rank = j == 1 and 0 or 3 } end
			end
			M.guild.Set{ name = GUILD, realm = "Test Realm", myRank = i == 1 and 0 or 3, members = others }
		end }
		local gm, m2, m3, out = sim:client(1), sim:client(2), sim:client(3), sim:client(4)
		local ok = gm:addon().OwnListing:Publish(fields())
		eq(ok, true)
		sim:advance(5)
		for _, c in ipairs({ m2, m3 }) do
			local copy = c:addon().OwnListing:Get()
			notNil(copy, c.name)
			eq(copy.rev, 1) eq(copy.desc, "We raid on weekends.")
			eq(c:addon().Catalog:Get(KEY).det.rev, 1)
		end
		local entry = out:addon().Catalog:Get(KEY)
		notNil(entry, "the ANN reached the client without a guild")
		eq(entry.sum.rev, 1)
		-- member 3 forges a GLIST: member 2 refuses it
		local forged = fields({ t = "GLIST", k = KEY, rev = 50, upd = 1, first = 1, own = "deadbeef", sub = "Forged" })
		m3:addon().Transport:Send("GUILD", forged)
		sim:advance(3)
		eq(m2:addon().OwnListing:Get().rev, 1)
		eq(m2:addon().OwnListing.state.stats.refused, 1)
		-- the members heard the Guild Master's ANN: nobody repeats it on the channel
		sim:advance(30)
		eq(m2:addon().OwnListing.state.stats.relays + m3:addon().OwnListing.state.stats.relays, 0)
		-- a member who missed it asks with GLREQ and gets the copy
		m3:addon().Config.db.char.ownListing.published = nil
		eq(m3:addon().OwnListing:Request(), true)
		sim:advance(5)
		eq(m3:addon().OwnListing:Get().rev, 1)
		-- the Guild Master withdraws it: the members and the guildless client follow
		eq(gm:addon().OwnListing:Delist(), true)
		sim:advance(5)
		eq(m2:addon().OwnListing:Status(), "delisted")
		eq(select(2, out:addon().Catalog:Get(KEY)), "delisted")
	end)
end)
