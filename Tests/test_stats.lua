-- M3.7: statistics and announcements (Data/Stats.lua, Data/OwnListing.lua, SPEC-03 §4, SPEC-02 §5, ADR 0006): the pure
-- math (roster aggregates, the unique players range with partial addon coverage, tokens, srev), the GTOK store with its
-- 7-day expiry, want answers and the opt-out setting, the periodic ANN with its jitter, the suppression rule and the
-- contact flag, the statistics in every ANN, in the editor's preview, on the guild page and in Settings, and two short
-- simulator scenarios. The mock player is "Testchar", Horde, on "Test Realm", a level 60 Warrior (max level 60).
local GUILD = "Iron Wolves"
local KEY = "TestRealm|Horde|" .. GUILD
local SECRET = "0123456789abcdef0123456789abcdef"

local function A() return AzerothGuildFinder end
local function S() return A().Stats end
local function OL() return A().OwnListing end
local function Cat() return A().Catalog end
local function Sync() return A().Sync end

local function fields(extra)
	local t = { sub = "Friendly raiders", lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380,
		rec = 1, apps = true, want = { [0] = 8 }, newb = true, minL = 30, desc = "We raid on weekends.", disc = "wolves1",
		cont = { "Thrall" }, note = "Voice required" }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

-- The player's guild: 2 more members online, 1 last seen 2 days ago (level 40 Mage), 1 last seen 10 days ago.
local function inGuild(rank)
	Mock.guild.Set{ name = GUILD, myRank = rank or 0, members = {
		{ name = "Jaina", rank = 1, class = "MAGE", level = 60 },
		{ name = "Garrosh", rank = 3, class = "WARRIOR", level = 58 },
		{ name = "Thrall", rank = 3, class = "MAGE", level = 40, online = false, lastOnline = { 0, 0, 2, 0 } },
		{ name = "Rexxar", rank = 3, class = "HUNTER", level = 60, online = false, lastOnline = { 0, 0, 10, 0 } },
	} }
	A().Config.db.account.accountSecret = SECRET
end

local sent
local function capture()
	sent = {}
	A().Transport.Send = function(_, dist, msg, opts)
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

local function gtok(token, n, want) return { t = "GTOK", token = token, n = n, want = want } end
local function hear(tok, n, sender, want) return S():OnMessage(gtok(tok, n, want), sender or "Jaina", "GUILD") end

---------------------------------------------------------------------------------------------------------------------
describe("pure math", function()
	it("the unique players range with full, partial and no addon coverage", function()
		local R = S().UniqueRange
		-- every active character covered: exact
		eq(select(1, R(5, { aaaaaaaa = 2, bbbbbbbb = 2, cccccccc = 1 })), 3)
		eq(select(2, R(5, { aaaaaaaa = 2, bbbbbbbb = 2, cccccccc = 1 })), 3)
		-- partial: 3 of 10 active characters covered by 2 accounts -> 7 uncovered: 3..9
		local lo, hi = R(10, { aaaaaaaa = 2, bbbbbbbb = 1 })
		eq(lo, 3) eq(hi, 9)
		-- a single uncovered character: exact again
		lo, hi = R(4, { aaaaaaaa = 2, bbbbbbbb = 1 })
		eq(lo, 3) eq(hi, 3)
		-- nobody uses the addon: 1..a7
		lo, hi = R(31, {})
		eq(lo, 1) eq(hi, 31)
		-- nobody active
		lo, hi = R(0, {})
		eq(lo, 0) eq(hi, 0)
		-- the SPEC-03 example shape: 19 accounts cover 26 of 31 -> 20..24
		local tokens = {}
		for i = 1, 19 do tokens[("%08x"):format(i)] = i <= 7 and 2 or 1 end
		lo, hi = R(31, tokens)
		eq(lo, 20) eq(hi, 24)
	end)

	it("never goes above the active characters (stale tokens) and ignores bad counts", function()
		local lo, hi = S().UniqueRange(2, { aaaaaaaa = 1, bbbbbbbb = 1, cccccccc = 1, dddddddd = 1 })
		eq(lo, 2) eq(hi, 2)
		lo, hi = S().UniqueRange(3, { aaaaaaaa = 0, bbbbbbbb = "x", cccccccc = 1 })
		eq(lo, 2) eq(hi, 3)
	end)

	it("aggregates a roster: active in the last 7 days, max level among the active, class mix of the active", function()
		local rows = {
			{ online = true, level = 60, classFile = "WARRIOR" },
			{ online = false, lastOnlineHours = 23, level = 60, classFile = "MAGE" },
			{ online = false, lastOnlineHours = 167, level = 12, classID = 8 },
			{ online = false, lastOnlineHours = 168, level = 60, classFile = "ROGUE" },   -- 7 days: not active
			{ online = false, level = 60, classFile = "PRIEST" },                          -- unknown: not active
			{ online = true, level = 60, classFile = "UNKNOWNCLASS" },
		}
		local st = S().FromRoster(rows, 60, S().ClassMap())
		eq(st.m, 6) eq(st.a7, 4) eq(st.max, 3)
		deepEq(st.cls, { [1] = 1, [8] = 2 })
		local noMax = S().FromRoster(rows, nil, S().ClassMap())
		isNil(noMax.max, "an unknown max level leaves max out")
		local empty = S().FromRoster({}, 60, {})
		eq(empty.m, 0) eq(empty.a7, 0) eq(empty.max, 0) isNil(empty.cls)
	end)

	it("tokens are 8 hex digits, one per account and guild, and never carry the secret", function()
		local t1 = S().Token(SECRET, KEY)
		matches(t1, "^%x%x%x%x%x%x%x%x$")
		eq(S().Token(SECRET, KEY), t1, "stable")
		ne(S().Token(SECRET, "TestRealm|Horde|Other"), t1, "another guild cannot link the account")
		ne(S().Token("fedcba9876543210fedcba9876543210", KEY), t1, "another account")
		eq(t1:find(SECRET:sub(1, 8), 1, true), nil)
	end)

	it("srev is the server time rounded down to the hour", function()
		eq(S().Srev(1767229199), 1767225600)
		eq(S().Srev(1767229200), 1767229200)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("statistics of the player's guild", function()
	it("come from the roster plus this account's own token", function()
		inGuild(3)
		local st, srev, key = S():Current()
		eq(key, KEY)
		eq(srev, S().Srev(GetServerTime()))
		eq(st.m, 5) eq(st.a7, 4) eq(st.max, 2)
		deepEq(st.cls, { [1] = 2, [8] = 2 })
		-- our own token covers 1 of 4 active characters: 3 uncovered -> 2..4
		eq(st.u7lo, 2) eq(st.u7hi, 4)
	end)

	it("narrow with every GTOK heard and become exact with full coverage", function()
		inGuild(3)
		hear("aaaaaaaa", 1, "Jaina")
		local st = S():Current()
		eq(st.u7lo, 3) eq(st.u7hi, 4)
		hear("bbbbbbbb", 2, "Garrosh")   -- Garrosh's account also plays Thrall
		st = S():Current()
		eq(st.u7lo, 3) eq(st.u7hi, 3)
		-- the same token again (24 h later) replaces, it does not add
		hear("bbbbbbbb", 2, "Garrosh")
		eq(S():Current().u7hi, 3)
	end)

	it("are nil without a guild or before the roster is readable", function()
		local st, why = S():Compute()
		isNil(st) eq(why, "no-guild")
	end)

	it("count this account's characters seen in the guild in the last 7 days and still in the roster", function()
		inGuild(3)
		local tokens = A().Config.db.account.tokens
		local h = function(name) return A().Normalize.Hash32Hex(name:lower()) end
		S():NoteSelf()
		eq(S():OwnCount(KEY), 1)
		tokens.mine[KEY][h("Garrosh")] = GetServerTime() - 3 * 86400     -- an alt of this account, 3 days ago
		tokens.mine[KEY][h("Rexxar")] = GetServerTime() - 8 * 86400      -- 8 days ago: expired
		tokens.mine[KEY][h("Somebody")] = GetServerTime() - 3600         -- not in the roster any more
		local rows = {}
		for i = 1, 5 do rows[i] = A().Compat.Guild.RosterRow(i) end
		eq(S():OwnCount(KEY, rows), 2)
		eq(S():OwnCount(KEY), 3, "without the roster only the expiry applies")
		-- a character remembered in one guild only: joining another moves it
		Mock.guild.Set{ name = "Other Guild", myRank = 3 }
		S():NoteSelf()
		isNil(tokens.mine[KEY][h("Testchar")])
		notNil(tokens.mine["TestRealm|Horde|Other Guild"][h("Testchar")])
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("GTOK", function()
	it("is sent over GUILD with the token and the number, never a name", function()
		inGuild(3)
		capture()
		eq(S():SendToken(true), true)
		local g = sentOf("GTOK", "GUILD")
		eq(#g, 1)
		eq(g[1].msg.token, S().Token(SECRET, KEY))
		eq(g[1].msg.n, 1)
		eq(g[1].msg.want, 1)
		for field, value in pairs(g[1].msg) do
			local ok = field == "t" or field == "token" or field == "n" or field == "want"
			truthy(ok, "unexpected field " .. tostring(field))
			if type(value) == "string" then eq(value:find("Testchar", 1, true), nil) end
		end
	end)

	it("goes out at login with want = 1 and again every 24 hours", function()
		inGuild(3)
		capture()
		S().AUTO = true
		S():OnRoleChanged("member", KEY, "none", nil)
		Mock.Advance(16)
		local g = sentOf("GTOK", "GUILD")
		eq(#g, 1) eq(g[1].msg.want, 1)
		Mock.Advance(S().RESEND)
		g = sentOf("GTOK", "GUILD")
		eq(#g, 2) isNil(g[2].msg.want)
	end)

	it("answers a want once, after 1-20 s, and wants heard meanwhile share the answer", function()
		inGuild(3)
		capture()
		hear("aaaaaaaa", 1, "Jaina", 1)
		hear("bbbbbbbb", 1, "Garrosh", 1)
		eq(#sentOf("GTOK"), 0, "not at once")
		Mock.Advance(20.5)
		local g = sentOf("GTOK", "GUILD")
		eq(#g, 1) isNil(g[1].msg.want)
		eq(S().state.counters.replies, 1)
		-- another want a moment later waits for the 60-second gap
		hear("cccccccc", 1, "Thrall", 1)
		Mock.Advance(25)
		eq(#sentOf("GTOK"), 1)
		Mock.Advance(40)
		eq(#sentOf("GTOK"), 2)
	end)

	it("is refused when malformed, from another channel, or our own echo", function()
		inGuild(3)
		eq(select(2, S():OnMessage(gtok("xyz", 1), "Jaina", "GUILD")), "invalid")
		eq(select(2, S():OnMessage(gtok("aaaaaaaa", 0), "Jaina", "GUILD")), "invalid")
		eq(select(2, S():OnMessage(gtok("aaaaaaaa", 51), "Jaina", "GUILD")), "invalid")
		eq(select(2, S():OnMessage(gtok("aaaaaaaa", 1.5), "Jaina", "GUILD")), "invalid")
		isNil(S():OnMessage(gtok("aaaaaaaa", 1), "Jaina", "CHANNEL"), "tokens travel over GUILD only")
		eq(select(2, S():OnMessage(gtok("aaaaaaaa", 1), "Testchar-TestRealm", "GUILD")), "self")
		isNil(A().Config.db.account.tokens.heard[KEY])
	end)

	it("keeps tokens 7 days, also across /reload, then forgets them", function()
		inGuild(3)
		hear("aaaaaaaa", 2, "Jaina")
		Mock.Reload()
		local heard = AzerothGuildFinderDB.tokens.heard[KEY]
		eq(heard.aaaaaaaa.n, 2)
		eq(A().Stats:Current().u7lo, 3)   -- 2 + our 1 cover 3 of 4 active: one uncovered
		heard.aaaaaaaa.at = GetServerTime() - 7 * 86400 + 60
		A().Stats:Invalidate()
		eq(A().Stats:Current().u7hi, 3, "still counted one minute before the 7 days")
		heard.aaaaaaaa.at = GetServerTime() - 7 * 86400
		A().Stats:Invalidate()
		local st = A().Stats:Current()
		eq(st.u7lo, 2) eq(st.u7hi, 4)
		A().Stats:Prune()
		isNil(AzerothGuildFinderDB.tokens.heard[KEY], "an expired guild leaves the store")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("opt-out", function()
	it("sends no GTOK, answers no want and leaves our own token out of the range", function()
		inGuild(3)
		capture()
		eq(S():SetSharing(false), true)
		eq(AzerothGuildFinderDB.settings.shareAltCount, false)
		falsy(S():Sharing())
		local ok, why = S():SendToken(true)
		eq(ok, false) eq(why, "optout")
		hear("aaaaaaaa", 1, "Jaina", 1)
		Mock.Advance(90)
		eq(#sentOf("GTOK"), 0)
		-- tokens of the others still count; ours does not: 1 covered of 4 -> 2..4
		local st = S():Current()
		eq(st.u7lo, 2) eq(st.u7hi, 4)
		-- turning it back on sends our token soon
		S().AUTO = true
		eq(S():SetSharing(true), true)
		Mock.Advance(16)
		eq(#sentOf("GTOK"), 1)
		eq(S():Current().u7lo, 3)
	end)

	it("is the Privacy switch of the Settings page", function()
		inGuild(3)
		A().Main:Open("Settings")
		local sw = A().Main.hosts.Settings.shareSwitch
		truthy(sw:GetChecked())
		Mock.RunScript(sw, "OnClick", "LeftButton")
		falsy(sw:GetChecked())
		eq(AzerothGuildFinderDB.settings.shareAltCount, false)
		eq(sw.label:GetText(), "Share anonymous alt count with my guild")
		Mock.RunScript(sw, "OnClick", "LeftButton")
		eq(AzerothGuildFinderDB.settings.shareAltCount, true)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("announcements", function()
	it("every ANN carries the statistics; the guild copy does not", function()
		inGuild(0)
		capture()
		eq(OL():Publish(fields()), true)
		local a = sentOf("ANN", "CHANNEL")
		eq(#a, 1)
		eq(a[1].msg.st.a7, 4) eq(a[1].msg.st.m, 5)
		eq(a[1].msg.srev, S().Srev(GetServerTime()))
		isNil(OL():Get().st)
		isNil(sentOf("GLIST", "GUILD")[1].msg.st)
		eq(Cat():Get(KEY).sum.st.u7hi, 4)
	end)

	it("the periodic turn waits 30 +/- 10 minutes, drawn again every time", function()
		inGuild(0)
		local seen, distinct = {}, 0
		for _ = 1, 40 do
			local d = OL():StartAnnouncing()
			truthy(d >= 1200 and d <= 2400, "delay " .. d)
			local bucket = math.floor(d / 60)
			if not seen[bucket] then seen[bucket] = true distinct = distinct + 1 end
		end
		truthy(distinct >= 10, "jitter: " .. distinct .. " different minutes in 40 draws")
		OL():StopAnnouncing()
	end)

	it("announces each turn with c = 1 from the Guild Master and re-arms itself", function()
		inGuild(0)
		capture()
		OL():Publish(fields())
		sent = {}
		OL().ANN_PERIOD = { 100, 100 }
		OL():StartAnnouncing()
		Mock.Advance(101)
		local a = sentOf("ANN", "CHANNEL")
		eq(#a, 1) eq(a[1].msg.c, 1) notNil(a[1].msg.st)
		Mock.Advance(100)
		eq(#sentOf("ANN", "CHANNEL"), 2)
		eq(OL().state.stats.periodic, 2)
	end)

	it("a member announces without the contact flag, an officer with it", function()
		inGuild(0)
		capture()
		OL():Publish(fields())
		local copy = OL():Get()
		Mock.guild.SetMyRank(3)
		sent = {}
		eq(OL():AnnounceTurn(0), true)
		isNil(sentOf("ANN")[1].msg.c)
		Mock.guild.SetMyRank(1)
		Sync().state.lastAnn = {}
		eq(OL():AnnounceTurn(0), true)
		eq(sentOf("ANN")[2].msg.c, 1)
		eq(copy.rev, OL():Get().rev)
	end)

	it("is skipped after an ANN of the same guild with an equal or newer rev and srev, not after an older one", function()
		inGuild(3)
		capture()
		-- the member's guild copy (as a GLIST would leave it)
		local rec = fields({ k = KEY, rev = 4, upd = 1767000000, first = 1766000000, own = "0badc0de" })
		AzerothGuildFinderCharDB.ownListing.published = A().Listing.SanitizeFull(rec)
		local srev = S().Srev(GetServerTime())
		local since = GetTime()
		local ann = fields({ t = "ANN", k = KEY, rev = 4, upd = 1767000000, first = 1766000000, own = "0badc0de", srev = srev - 3600,
			st = { m = 5, a7 = 4 } })
		for f in pairs({ desc = 1, disc = 1, cont = 1, note = 1 }) do ann[f] = nil end
		Mock.Advance(1)
		Sync():OnMessage(ann, "Jaina", "CHANNEL")
		local ok, why = OL():AnnounceTurn(since)
		eq(ok, true, "older statistics do not suppress: ours are newer")
		ann.srev = srev
		Mock.Advance(1)
		Sync():OnMessage(ann, "Jaina", "CHANNEL")
		ok, why = OL():AnnounceTurn(since)
		eq(ok, false) eq(why, "suppressed")
		-- the ANN was before this turn was armed: it does not count
		ok = OL():AnnounceTurn(GetTime())
		eq(ok, true)
		eq(OL().state.stats.periodicSuppressed, 1)
	end)

	it("our own ANN coming back from the channel never suppresses our next turn", function()
		inGuild(0)
		capture()
		OL():Publish(fields())
		local since = GetTime()
		local own = sentOf("ANN")[1].msg
		Mock.Advance(1)
		Sync():OnMessage(own, "Testchar-TestRealm", "CHANNEL")
		isNil(Sync():LastAnnounce(KEY))
		eq(OL():AnnounceTurn(since), true)
	end)

	it("skips a turn without a listed guild copy", function()
		inGuild(3)
		capture()
		local ok, why = OL():AnnounceTurn(0)
		eq(ok, false) eq(why, "not-listed")
		eq(#sent, 0)
	end)

	it("starts with the guild and stops without one", function()
		inGuild(3)
		OL().AUTO = true
		OL():OnRoleChanged("member", KEY, "none", nil)
		notNil(OL().state.annNextAt)
		local at = OL().state.annNextAt
		OL():OnRoleChanged("officer", KEY, "member", KEY)
		eq(OL().state.annNextAt, at, "a promotion does not restart the timer")
		OL():OnRoleChanged("none", nil, "officer", KEY)
		isNil(OL().state.annNextAt)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("display", function()
	it("the editor's preview shows the guild's statistics", function()
		inGuild(0)
		A().Main:Show()
		local mini = A().Main.hosts.CreateListing.mini
		eq(mini.members:GetText(), "4 active / 5")
		local L = LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")
		local card = A().EditorModel.Preview({}, KEY, GetServerTime(), L, { m = 9, a7 = 3 })
		eq(card.active, 3) eq(card.members, 9)
		isNil(A().EditorModel.Preview({}, KEY, GetServerTime(), L).active)
	end)

	it("the guild page of our own guild shows the roster's numbers before any ANN carried them", function()
		inGuild(3)
		local sum = fields({ k = KEY, rev = 4, upd = GetServerTime() - 60, first = 1766000000, own = "0badc0de" })
		for f in pairs({ desc = 1, disc = 1, cont = 1, note = 1 }) do sum[f] = nil end
		assert(Cat():PutSummary(sum))
		A().Main:Show()
		A().Browse:OpenGuild(KEY)
		local h = A().Main.hosts.GuildPage
		eq(h.members.cells.active.n:GetText(), "4")
		eq(h.members.cells.unique.n:GetText(), "2–4")
		eq(h.members.cells.total.n:GetText(), "5")
		isNil(Cat():Get(KEY).sum.st, "the catalog itself is not changed")
		-- a GTOK arrives while the page is open: the range narrows
		hear("aaaaaaaa", 3, "Jaina")
		Mock.Advance(1)
		eq(h.members.cells.unique.n:GetText(), "2")
	end)

	it("another guild's page shows only what its ANN carried", function()
		inGuild(3)
		local other = "TestRealm|Horde|Other Guild"
		eq(S():Overlay({ k = other, rev = 1 }).st, nil)
	end)

	it("/gf debug prints numbers only", function()
		inGuild(3)
		hear("aaaaaaaa", 1, "Jaina")
		Mock.ClearOutput()
		Mock.Slash("/gf debug")
		local text = table.concat(Mock.PlainOutput(), " / ")
		matches(text, "Stats: 5 members, 4 active, 2 at max level, unique 3%-4")
		matches(text, "tokens counted 2, own characters 1, sharing on")
		matches(text, "periodic ANN 0")
		for _, name in ipairs({ "Jaina", "Testchar", GUILD, "aaaaaaaa", S().Token(SECRET, KEY) }) do
			eq(text:find(name, 1, true), nil, name)
		end
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Simulator scenarios (short: a few simulated minutes)
---------------------------------------------------------------------------------------------------------------------
-- Clients 1..n in GUILD (1 = Guild Master), each roster names the others plus `extra` members without the addon.
local function guildSim(n, extra, opts)
	opts = opts or {}
	local sim = Sim.new{ clients = n + (opts.outsider and 1 or 0), sync = false, seed = opts.seed or 37, latency = { 0.05, 0.3 },
		setup = function(M, i)
			if i > n then return end
			local members = {}
			for j = 1, n do
				if j ~= i then members[#members + 1] = { name = Sim.nameOf(j), rank = j == 1 and 0 or 3 } end
			end
			for j = 1, extra or 0 do
				members[#members + 1] = { name = "Offline" .. string.char(96 + j), rank = 3, online = false, lastOnline = { 0, 0, 1, 0 } }
			end
			M.guild.Set{ name = GUILD, realm = "Test Realm", myRank = i == 1 and 0 or 3, members = members }
		end }
	for i = 1, n do
		local c = sim:client(i)
		c:addon().Config.db.account.accountSecret = ("%x"):format(i):rep(32):sub(1, 32)
	end
	return sim
end

describe("simulator", function()
	it("tokens over GUILD give every member the same range; an opted-out member and members without the addon widen it", function()
		-- 4 clients with the addon + 3 roster members without it (active yesterday): a7 = 7
		local sim = guildSim(4, 3)
		sim:client(4):addon().Stats:SetSharing(false)
		eq(sim:client(1):addon().Stats:SendToken(true), true)
		sim:advance(25)   -- the answers come within 1-20 s
		for i = 1, 4 do
			local st = sim:client(i):addon().Stats:Current()
			eq(st.a7, 7, "client " .. i)
			-- 3 sharing accounts (n = 1 each) cover 3 of 7: 4 uncovered -> 4..7
			eq(st.u7lo, 4, "client " .. i) eq(st.u7hi, 7, "client " .. i)
		end
		eq(sim:client(4):addon().Stats.state.counters.sent, 0, "the opted-out member sent nothing")
		local stats = sim:stats()
		eq(stats.perClient[4].byDist.GUILD.msgs, 0)
		eq(stats.perClient[1].byDist.CHANNEL.msgs, 0, "tokens never go on the channel")
	end)

	it("periodic ANN: suppression keeps one guild to about one ANN per turn; outsiders see the statistics", function()
		local sim = guildSim(5, 0, { outsider = true, seed = 41 })
		local count = 0
		for i = 1, 5 do
			local ol = sim:client(i):addon().OwnListing
			ol.ANN_PERIOD = { 20, 40 }
			ol.AUTO = true
		end
		eq(sim:client(1):addon().OwnListing:Publish(fields()), true)
		sim:advance(5)
		for i = 1, 5 do sim:client(i):addon().OwnListing:StartAnnouncing() end
		sim:advance(300)
		local periodic, suppressed = 0, 0
		for i = 1, 5 do
			local s = sim:client(i):addon().OwnListing.state.stats
			periodic, suppressed = periodic + s.periodic, suppressed + s.periodicSuppressed
		end
		-- 5 members x about 10 turns each = about 50 turns; without suppression 50 ANN
		truthy(periodic + suppressed >= 35, "turns: " .. (periodic + suppressed))
		truthy(periodic <= 20, "periodic ANN sent: " .. periodic)
		truthy(suppressed >= 20, "suppressed: " .. suppressed)
		-- the client without a guild has the listing with the statistics of the roster
		local entry = sim:client(6):addon().Catalog:Get(KEY)
		notNil(entry)
		eq(entry.sum.st.a7, 5) eq(entry.sum.st.m, 5)
		truthy(sim:client(6):addon().Sync:Contacts(KEY)[1] ~= nil, "the Guild Master's c = 1 is heard")
	end)
end)
