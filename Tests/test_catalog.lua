-- Catalog (M2.2): merge rules INT-01..INT-05, convergence, staleness, limits, persistence (SPEC-02 §8, SPEC-03 §1).
-- The mock player is Horde on "Test Realm", so the catalog accepts keys "TestRealm|Horde|<name>".
local function C() return AzerothGuildFinder.Catalog end
local DAY = 86400
local KEY = "TestRealm|Horde|Night Watch"
local function key(name) return "TestRealm|Horde|" .. name end

local function summary(extra)
	local t = { k = KEY, rev = 1, upd = 1767000000, first = 1766000000, own = "a1b2c3d4", sub = "Friendly raiders",
		lang = 1, lang1 = 1, tags = { 1, 2 }, pace = 2, days = 21, t0 = 1140, t1 = 1380, rec = 1, apps = true,
		want = { [0] = 8 }, newb = true, minL = 30 }
	for k, v in pairs(extra or {}) do if v == "nil" then t[k] = nil else t[k] = v end end
	return t
end

local function detail(extra)
	local t = { k = KEY, rev = 1, desc = "We raid on weekends.", disc = "abc123", cont = { "Thrall" }, note = "Voice required" }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

local function chan(sender) return { dist = "CHANNEL", sender = sender or "Anna-TestRealm" } end
local function put(extra, meta) return C():PutSummary(summary(extra), meta) end
local function sumOf(k) local e = C():Get(k or KEY) return e and e.sum end
local function skip(seconds) Mock.StepClock(seconds) end

local events
local function record()
	events = {}
	AzerothGuildFinder.Bus:On("CATALOG_UPDATED", function(k, what) events[#events + 1] = { k, what } end)
end

-- The whole listing set as text, to compare two clients.
local function snapshot()
	local out = {}
	for _, s in ipairs(C():List(nil, { all = true })) do out[#out + 1] = C().Encode(s) end
	return table.concat(out, "\n")
end

-- Deterministic shuffle (no dependency on math.random state).
local function shuffled(list, seed)
	local copy = {}
	for i, v in ipairs(list) do copy[i] = v end
	local x = seed
	for i = #copy, 2, -1 do
		x = (x * 1103515245 + 12345) % 2147483648
		local j = x % i + 1
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

describe("accepting listings", function()
	it("stores a valid summary and reports it", function()
		record()
		local ok, why = put({}, chan())
		eq(ok, true)
		eq(why, "added")
		local entry, status = C():Get(KEY)
		eq(status, "listed")
		eq(entry.sum.sub, "Friendly raiders")
		eq(entry.own, "a1b2c3d4")
		eq(entry.state, "listed")
		eq(entry.firstSeenAt, GetServerTime())
		eq(entry.annAt, GetServerTime())
		eq(C():Count(), 1)
		deepEq(events, { { KEY, "added" } })
	end)

	it("keeps the record under the saved variables with the documented shape", function()
		put({}, chan())
		local entry = AzerothGuildFinderDB.catalog.TestRealm.Horde[KEY]
		notNil(entry)
		deepEq(entry.sum, AzerothGuildFinder.Listing.SanitizeSummary(summary()))
		isNil(entry.det)
		isNil(entry.annBy)
	end)

	it("drops other realms and the other faction", function()
		local ok, why = put({ k = "OtherRealm|Horde|Night Watch" }, chan())
		eq(ok, false) eq(why, "foreign")
		ok, why = put({ k = "TestRealm|Alliance|Night Watch" }, chan())
		eq(ok, false) eq(why, "foreign")
		eq(C():Count(true), 0)
		isNil(AzerothGuildFinderDB.catalog.OtherRealm)
		isNil(AzerothGuildFinderDB.catalog.TestRealm and AzerothGuildFinderDB.catalog.TestRealm.Alliance)
	end)

	it("follows the player: another faction accepts the other keys", function()
		Mock.player.faction = "Alliance"
		Mock.Reload()
		eq(put({ k = "TestRealm|Alliance|Night Watch" }), true)
		eq(put({}), false)
	end)

	it("rejects invalid, incomplete and ownerless records", function()
		local ok, why = C():PutSummary({ k = "x", rev = 1 })
		eq(ok, false) eq(why, "invalid")
		ok, why = C():PutSummary("nope")
		eq(why, "invalid")
		ok, why = put({ own = "nil" })
		eq(why, "no-owner")
		ok, why = put({ tags = "nil" })
		eq(why, "incomplete")
		ok, why = put({ pace = "nil" })
		eq(why, "incomplete")
		ok, why = put({ own = "zzzz" })
		eq(why, "no-owner")
		eq(C():Count(true), 0)
	end)

	it("sanitizes what it stores (INT-06)", function()
		put({ sub = "|cffff0000red|r" })
		eq(sumOf().sub, "||cffff0000red||r")
		put({ evil = "x", rev = 2 })
		isNil(sumOf().evil)
	end)

	it("a channel announcement needs a sender; local records do not", function()
		local ok, why = C():PutSummary(summary(), { dist = "CHANNEL" })
		eq(ok, false) eq(why, "no-sender")
		eq(put({}), true)
		eq(put({ k = key("B") }, { dist = "WHISPER", sender = "Bob-TestRealm" }), true)
	end)

	it("an announcement older than 60 days is not stored", function()
		local ok, why = put({}, { dist = "WHISPER", annAt = GetServerTime() - 61 * DAY })
		eq(ok, false) eq(why, "expired")
		eq(C():Count(true), 0)
	end)
end)

describe("INT-01: order by (rev, upd), ties by the lowest content hash", function()
	it("a higher rev replaces, a lower one is older", function()
		put({ rev = 2, sub = "two" }, chan())
		local ok, why = put({ rev = 3, sub = "three" }, chan())
		eq(ok, true) eq(why, "updated")
		eq(sumOf().sub, "three")
		ok, why = put({ rev = 1, sub = "one" }, chan())
		eq(ok, false) eq(why, "older")
		eq(sumOf().sub, "three")
	end)

	it("the same rev goes by the later upd", function()
		put({ rev = 2, upd = 1767000100, sub = "late" }, chan())
		eq(put({ rev = 2, upd = 1767000050, sub = "early" }, chan()), false)
		eq(sumOf().sub, "late")
		eq(put({ rev = 2, upd = 1767000200, sub = "later" }, chan()), true)
		eq(sumOf().sub, "later")
	end)

	it("a repeated record changes nothing", function()
		record()
		put({}, chan())
		local ok, why = put({}, chan())
		eq(ok, false) eq(why, "unchanged")
		eq(#events, 1)
	end)

	it("the same rev and upd go by the lower hash, whatever the arrival order", function()
		local a, b = summary({ rev = 4, sub = "alpha" }), summary({ rev = 4, sub = "bravo" })
		local function content(s)
			local c = {}
			for f, v in pairs(AzerothGuildFinder.Listing.SanitizeSummary(s)) do c[f] = v end
			return C().Encode(c)
		end
		local N = AzerothGuildFinder.Normalize
		local winner = N.Hash32(content(a)) < N.Hash32(content(b)) and "alpha" or "bravo"
		C():PutSummary(a, chan()) C():PutSummary(b, chan())
		eq(sumOf().sub, winner)
		C():Clear()
		C():PutSummary(b, chan()) C():PutSummary(a, chan())
		eq(sumOf().sub, winner)
	end)

	it("the encoding does not depend on the order the fields were written in", function()
		local x = { a = 1, b = { 3, 2, 1 }, c = "x|y" }
		local y = { c = "x|y", b = { 3, 2, 1 }, a = 1 }
		eq(C().Encode(x), C().Encode(y))
		ne(C().Encode({ a = 1 }), C().Encode({ a = "1" }))
	end)
end)

describe("statistics: the newest srev wins on its own", function()
	local function st(m) return { m = m, a7 = m } end

	it("newer statistics replace the old ones even in an older revision", function()
		put({ rev = 5, st = st(10), srev = 1000 }, chan())
		local ok, why = put({ rev = 3, st = st(20), srev = 2000, sub = "old content" }, chan())
		eq(ok, true) eq(why, "stats")
		eq(sumOf().rev, 5)
		eq(sumOf().sub, "Friendly raiders")
		eq(sumOf().st.m, 20)
		eq(sumOf().srev, 2000)
	end)

	it("older statistics never replace newer ones, even with a newer revision", function()
		put({ rev = 1, st = st(10), srev = 2000 }, chan())
		put({ rev = 2, st = st(99), srev = 1000, sub = "new content" }, chan())
		eq(sumOf().rev, 2)
		eq(sumOf().sub, "new content")
		eq(sumOf().st.m, 10)
		eq(sumOf().srev, 2000)
	end)

	it("a record without statistics keeps the ones we have", function()
		put({ rev = 1, st = st(10), srev = 2000 }, chan())
		put({ rev = 2 }, chan())
		eq(sumOf().st.m, 10)
	end)

	it("equal srev with different numbers is decided by the lower hash", function()
		local N = AzerothGuildFinder.Normalize
		local a, b = st(11), st(12)
		local winner = N.Hash32(C().Encode(a)) < N.Hash32(C().Encode(b)) and 11 or 12
		put({ st = a, srev = 500 }, chan())
		put({ st = b, srev = 500 }, chan())
		eq(sumOf().st.m, winner)
		C():Clear()
		put({ st = b, srev = 500 }, chan())
		put({ st = a, srev = 500 }, chan())
		eq(sumOf().st.m, winner)
	end)
end)

describe("convergence: the same updates in any order give the same catalog", function()
	-- Updates for several guilds: new revisions, late old ones, ties, statistics, a withdrawal and a re-listing.
	local function updates()
		local list = {}
		local function add(name, extra, sender)
			local fields = { k = key(name) }
			for f, v in pairs(extra) do fields[f] = v end
			list[#list + 1] = { summary(fields), sender }
		end
		for _, name in ipairs({ "Alpha", "Bravo", "Charlie", "Delta" }) do
			add(name, { rev = 1, upd = 1767000000, sub = name .. " v1" }, "S1")
			add(name, { rev = 2, upd = 1767000100, sub = name .. " v2", st = { m = 10, a7 = 5 }, srev = 100 }, "S2")
			add(name, { rev = 3, upd = 1767000200, sub = name .. " v3" }, "S3")
			add(name, { rev = 3, upd = 1767000200, sub = name .. " v3 twin" }, "S4")
			add(name, { rev = 1, upd = 1767000050, sub = name .. " old", st = { m = 30, a7 = 20 }, srev = 300 }, "S1")
			add(name, { rev = 2, upd = 1767000100, sub = name .. " v2 twin", st = { m = 31, a7 = 21 }, srev = 300 }, "S5")
		end
		return list
	end

	local function run(order)
		C():Clear()
		for _, u in ipairs(order) do C():PutSummary(u[1], chan(u[2] .. u[1].k:match("[^|]*$") .. "-TestRealm")) end
		return snapshot()
	end

	it("converges for twenty arrival orders", function()
		local all = updates()
		local reference = run(all)
		contains(reference, "v3")
		eq(C():Count(), 4)
		for seed = 1, 20 do
			eq(run(shuffled(all, seed)), reference, "order " .. seed)
		end
	end)

	it("converges with withdrawals and re-listings, the DEL after its sender's ANN", function()
		local function play(order)
			C():Clear()
			for _, step in ipairs(order) do
				local sender = step.sender .. "-TestRealm"
				if step.del then C():Delist(KEY, step.del, chan(sender))
				else C():PutSummary(summary(step.s), chan(sender)) end
			end
			return snapshot(), C():Get(KEY).state
		end
		local steps = {
			{ sender = "A", s = { rev = 1 } },
			{ sender = "A", s = { rev = 2, sub = "v2" } },
			{ sender = "A", del = 2 },
			{ sender = "B", s = { rev = 3, sub = "v3" } },
		}
		local snap, state = play(steps)
		eq(state, "listed")
		contains(snap, "v3")
		-- the DEL needs A's ANN first; the other steps can come in any order
		local orders = {
			{ steps[1], steps[2], steps[3], steps[4] },
			{ steps[4], steps[1], steps[2], steps[3] },
			{ steps[1], steps[4], steps[2], steps[3] },
			{ steps[2], steps[1], steps[4], steps[3] },
		}
		for i, order in ipairs(orders) do
			local s2, st2 = play(order)
			eq(s2, snap, "order " .. i)
			eq(st2, "listed")
		end
	end)
end)

describe("INT-03: the known ownerId sticks", function()
	it("an announcement with another ownerId is ignored", function()
		put({ rev = 1 }, chan("A-TestRealm"))
		local ok, why = put({ rev = 9, own = "deadbeef", sub = "usurper" }, chan("B-TestRealm"))
		eq(ok, false) eq(why, "owner")
		eq(sumOf().sub, "Friendly raiders")
		eq(sumOf().own, "a1b2c3d4")
	end)

	it("the ownerId is compared without regard to case", function()
		put({ own = "A1B2C3D4" }, chan())
		eq(put({ own = "a1b2c3d4", rev = 2 }, chan()), true)
	end)

	it("an ignored announcement does not keep the old listing alive", function()
		put({}, chan("A-TestRealm"))
		local before = C():Get(KEY).annAt
		skip(10 * DAY)
		put({ own = "deadbeef" }, chan("B-TestRealm"))
		eq(C():Get(KEY).annAt, before)
	end)

	it("an announcement of the same owner keeps it alive, even an older revision", function()
		put({ rev = 5 }, chan("A-TestRealm"))
		skip(20 * DAY)
		local ok, why = put({ rev = 4 }, chan("A-TestRealm"))
		eq(why, "older")
		eq(C():Get(KEY).annAt, GetServerTime())
		eq(C():Status(KEY), "listed")
	end)

	it("a new owner may take over after 30 days without an announcement", function()
		put({ rev = 7, sub = "old guard" }, chan("A-TestRealm"))
		C():PutDetail(detail({ rev = 7 }))
		skip(29 * DAY)
		eq(put({ own = "deadbeef", rev = 1 }, chan("B-TestRealm")), false)
		skip(2 * DAY)
		local ok, why = put({ own = "deadbeef", rev = 1, sub = "new guard" }, chan("B-TestRealm"))
		eq(ok, true) eq(why, "takeover")
		eq(sumOf().own, "deadbeef")
		eq(sumOf().rev, 1)
		eq(sumOf().sub, "new guard")
		isNil(C():Get(KEY).det)
		eq(C():Status(KEY), "listed")
		eq(put({ own = "a1b2c3d4", rev = 50 }, chan("A-TestRealm")), false)
	end)
end)

describe("INT-04: one guild per sender in the channel", function()
	it("a sender that announces a second guild within 24 h is ignored for 24 h", function()
		eq(put({ k = key("A") }, chan("Eve-TestRealm")), true)
		local ok, why = put({ k = key("B") }, chan("Eve-TestRealm"))
		eq(ok, false) eq(why, "ignored-sender")
		eq(C():Get(key("B")), nil)
		-- even the first guild is refused while the ban lasts
		ok, why = put({ k = key("A"), rev = 2 }, chan("Eve-TestRealm"))
		eq(why, "ignored-sender")
		skip(23 * DAY / 24 + 3000)
		eq(put({ k = key("A"), rev = 2 }, chan("Eve-TestRealm")), false)
		skip(2 * 3600)
		eq(put({ k = key("B") }, chan("Eve-TestRealm")), true)
	end)

	it("repeating the same guild is fine, at any rate", function()
		for i = 1, 5 do
			eq(put({ k = key("A"), rev = i }, chan("Eve-TestRealm")), true)
			skip(3600)
		end
	end)

	it("after 24 h without announcements the sender may switch guild", function()
		eq(put({ k = key("A") }, chan("Eve-TestRealm")), true)
		skip(DAY + 1)
		eq(put({ k = key("B") }, chan("Eve-TestRealm")), true)
		local ok, why = put({ k = key("C") }, chan("Eve-TestRealm"))
		eq(why, "ignored-sender")
	end)

	it("other senders are not affected", function()
		put({ k = key("A") }, chan("Eve-TestRealm"))
		put({ k = key("B") }, chan("Eve-TestRealm"))
		eq(put({ k = key("B") }, chan("Bob-TestRealm")), true)
	end)

	it("replies by whisper do not count", function()
		local whisper = { dist = "WHISPER", sender = "Carol-TestRealm" }
		for _, name in ipairs({ "A", "B", "C", "D" }) do eq(put({ k = key(name) }, whisper), true) end
		eq(C():Count(), 4)
		-- and a whisper sender may still announce one guild in the channel afterwards
		eq(put({ k = key("A"), rev = 2 }, chan("Carol-TestRealm")), true)
	end)

	it("a whisper from a banned sender is still accepted", function()
		put({ k = key("A") }, chan("Eve-TestRealm"))
		put({ k = key("B") }, chan("Eve-TestRealm"))
		eq(put({ k = key("B") }, { dist = "WHISPER", sender = "Eve-TestRealm" }), true)
	end)

	it("a rejected announcement still counts as a claim for that guild", function()
		put({ k = key("A") }, chan("A-TestRealm"))
		eq(put({ k = key("A"), own = "deadbeef" }, chan("Mallory-TestRealm")), false)
		local ok, why = put({ k = key("B") }, chan("Mallory-TestRealm"))
		eq(why, "ignored-sender")
	end)
end)

describe("INT-05: delisting", function()
	it("a DEL from a sender that announced the guild withdraws it", function()
		record()
		put({ rev = 2 }, chan("Gm-TestRealm"))
		local ok, why = C():Delist(KEY, 2, chan("Gm-TestRealm"))
		eq(ok, true) eq(why, "delisted")
		eq(C():Status(KEY), "delisted")
		eq(C():Count(), 0)
		eq(#C():List(), 0)
		eq(C():Count(true), 1)
		eq(events[#events][2], "delisted")
	end)

	it("a DEL from a stranger is refused", function()
		put({ rev = 2 }, chan("Gm-TestRealm"))
		local ok, why = C():Delist(KEY, 2, chan("Mallory-TestRealm"))
		eq(ok, false) eq(why, "not-announcer")
		eq(C():Status(KEY), "listed")
	end)

	it("a whisper reply does not make the sender an announcer", function()
		put({ rev = 2 }, { dist = "WHISPER", sender = "Carol-TestRealm" })
		local ok, why = C():Delist(KEY, 2, chan("Carol-TestRealm"))
		eq(why, "not-announcer")
	end)

	it("a DEL needs a sender and a known guild, and is checked", function()
		eq(select(2, C():Delist(KEY, 1, chan())), "unknown")
		put({}, chan())
		eq(select(2, C():Delist(KEY, 1, {})), "no-sender")
		eq(select(2, C():Delist("bad", 1, chan())), "invalid")
		eq(select(2, C():Delist(KEY, 0, chan())), "invalid")
		eq(select(2, C():Delist(KEY, 1.5, chan())), "invalid")
		eq(select(2, C():Delist("OtherRealm|Horde|X", 1, chan())), "foreign")
	end)

	it("a DEL older than the listing is ignored", function()
		put({ rev = 5 }, chan())
		local ok, why = C():Delist(KEY, 4, chan())
		eq(ok, false) eq(why, "older")
		eq(C():Status(KEY), "listed")
	end)

	it("an ANN with a higher rev brings the listing back; an older or equal one does not", function()
		record()
		put({ rev = 2 }, chan())
		C():Delist(KEY, 2, chan())
		eq(put({ rev = 2, sub = "same rev", upd = 1767009999 }, chan("Other-TestRealm")), true)   -- content changed, still withdrawn
		eq(C():Status(KEY), "delisted")
		eq(put({ rev = 1 }, chan("Other-TestRealm")), false)
		eq(C():Status(KEY), "delisted")
		local ok, why = put({ rev = 3, sub = "back" }, chan("Other-TestRealm"))
		eq(ok, true) eq(why, "relisted")
		eq(C():Status(KEY), "listed")
		eq(sumOf().sub, "back")
		eq(C():Count(), 1)
		isNil(C():Get(KEY).delRev)
	end)

	it("a repeated DEL changes nothing; a higher one moves the tombstone", function()
		put({ rev = 2 }, chan())
		C():Delist(KEY, 2, chan())
		local ok, why = C():Delist(KEY, 2, chan())
		eq(why, "unchanged")
		eq(C():Delist(KEY, 3, chan()), true)
		eq(C():Get(KEY).delRev, 3)
		put({ rev = 3, sub = "withdrawn too" }, chan("X-TestRealm"))   -- rev 3 is withdrawn as well
		eq(C():Status(KEY), "delisted")
	end)

	it("a banned sender cannot delist (INT-04)", function()
		put({ k = key("A") }, chan("Eve-TestRealm"))
		put({ k = key("B") }, chan("Eve-TestRealm"))
		local ok, why = C():Delist(key("A"), 1, chan("Eve-TestRealm"))
		eq(why, "ignored-sender")
	end)

	it("withdrawn listings are kept as tombstones until they are 60 days old", function()
		put({ rev = 2 }, chan())
		skip(10 * DAY)
		C():Delist(KEY, 2, chan())
		skip(59 * DAY)
		C():Housekeeping()
		eq(C():Count(true), 1)   -- 59 days since the DEL, 69 since the ANN
		skip(2 * DAY)
		eq(C():Housekeeping(), 1)
		eq(C():Count(true), 0)
	end)

	it("withdrawn listings are not offered to others, but are in the digest", function()
		put({ rev = 2 }, chan())
		C():Delist(KEY, 2, chan())
		eq(#C():Newer({}), 0)
		eq(#C():Digest(), 1)
	end)
end)

describe("staleness", function()
	it("passes through listed, inactive, hidden and purged", function()
		record()
		put({}, chan())
		eq(C():Status(KEY), "listed")
		skip(14 * DAY)
		eq(C():Status(KEY), "listed")
		skip(1)
		eq(C():Status(KEY), "inactive")
		eq(C():Count(), 1)
		skip(16 * DAY - 1)
		eq(C():Status(KEY), "inactive")
		skip(1)
		eq(C():Status(KEY), "hidden")
		eq(C():Count(), 0)
		eq(#C():List(), 0)
		eq(#C():List(nil, { all = true }), 1)
		eq(C():Count(true), 1)
		skip(30 * DAY - 1)
		eq(C():Housekeeping(), 0)   -- exactly 60 days
		skip(1)
		eq(C():Housekeeping(), 1)
		eq(C():Count(true), 0)
		isNil(C():Get(KEY))
		deepEq(events[#events], { KEY, "removed" })
	end)

	it("a new announcement makes an inactive listing current again", function()
		put({}, chan())
		skip(20 * DAY)
		eq(C():Status(KEY), "inactive")
		put({}, chan())
		eq(C():Status(KEY), "listed")
	end)

	it("a hidden listing comes back with a new announcement", function()
		put({}, chan())
		skip(40 * DAY)
		eq(C():Count(), 0)
		put({ rev = 2 }, chan())
		eq(C():Count(), 1)
	end)

	it("second-hand records do not keep a listing alive, but can carry the peer's time", function()
		put({}, chan())
		skip(20 * DAY)
		put({ rev = 2 }, { dist = "WHISPER", sender = "Carol-TestRealm" })
		eq(C():Status(KEY), "inactive")
		put({ rev = 3 }, { dist = "WHISPER", sender = "Carol-TestRealm", annAt = GetServerTime() - 1 * DAY })
		eq(C():Status(KEY), "listed")
		-- a peer cannot make it newer than now, nor older than what we know
		put({ rev = 4 }, { dist = "WHISPER", annAt = GetServerTime() + 5 * DAY })
		eq(C():Get(KEY).annAt, GetServerTime())
		put({ rev = 5 }, { dist = "WHISPER", annAt = GetServerTime() - 40 * DAY })
		eq(C():Get(KEY).annAt, GetServerTime())
	end)

	it("a new second-hand listing takes the peer's time", function()
		put({}, { dist = "WHISPER", annAt = GetServerTime() - 20 * DAY })
		eq(C():Status(KEY), "inactive")
	end)

	it("purges on every realm and faction, not only the player's", function()
		AzerothGuildFinderDB.catalog.OtherRealm = { Alliance = { ["OtherRealm|Alliance|Old"] = (function()
			local s = AzerothGuildFinder.Listing.SanitizeSummary(summary({ k = "OtherRealm|Alliance|Old" }))
			return { sum = s, own = s.own, firstSeenAt = 1, annAt = GetServerTime() - 61 * DAY, state = "listed" }
		end)() } }
		eq(C():Housekeeping(), 1)
		deepEq(AzerothGuildFinderDB.catalog.OtherRealm.Alliance, {})
	end)
end)

describe("details", function()
	it("needs a known listing and is checked", function()
		local ok, why = C():PutDetail(detail())
		eq(ok, false) eq(why, "unknown")
		put({ rev = 2 }, chan())
		ok, why = C():PutDetail({ k = "bad", rev = 1 })
		eq(why, "invalid")
		ok, why = C():PutDetail(detail({ k = "OtherRealm|Horde|X", rev = 1 }))
		eq(why, "foreign")
	end)

	it("is stored beside the summary and cleaned", function()
		record()
		put({ rev = 2 }, chan())
		local ok, why = C():PutDetail(detail({ rev = 2, desc = "a|b" }))
		eq(ok, true) eq(why, "detail")
		eq(C():Get(KEY).det.desc, "a||b")
		eq(C():Get(KEY).det.disc, "abc123")
		eq(events[#events][2], "detail")
		eq(C():Get(KEY).detAt, GetServerTime())
	end)

	it("a revision ahead of the summary is refused; an older one never replaces a newer one", function()
		put({ rev = 3 }, chan())
		eq(select(2, C():PutDetail(detail({ rev = 4 }))), "ahead")
		eq(C():PutDetail(detail({ rev = 2, desc = "two" })), true)
		eq(C():PutDetail(detail({ rev = 3, desc = "three" })), true)
		local ok, why = C():PutDetail(detail({ rev = 2, desc = "two again" }))
		eq(ok, false) eq(why, "older")
		eq(C():Get(KEY).det.desc, "three")
	end)

	it("the same revision with different text goes by the lower hash, in any order", function()
		local N = AzerothGuildFinder.Normalize
		local a, b = detail({ desc = "first" }), detail({ desc = "second" })
		local function enc(d) return C().Encode(AzerothGuildFinder.Listing.SanitizeDetail(d)) end
		local winner = N.Hash32(enc(a)) < N.Hash32(enc(b)) and "first" or "second"
		put({}, chan())
		C():PutDetail(a) C():PutDetail(b)
		eq(C():Get(KEY).det.desc, winner)
		C():Clear()
		put({}, chan())
		C():PutDetail(b) C():PutDetail(a)
		eq(C():Get(KEY).det.desc, winner)
	end)

	it("is dropped after 60 days unseen while the listing stays", function()
		put({}, chan())
		C():PutDetail(detail())
		for _ = 1, 5 do   -- the guild keeps announcing every 15 days
			skip(15 * DAY)
			put({}, chan())
		end
		local purged, dropped = C():Housekeeping()
		eq(purged, 0) eq(dropped, 1)
		isNil(C():Get(KEY).det)
		isNil(C():Get(KEY).detAt)
		eq(C():Status(KEY), "listed")
	end)

	it("receiving the detail again keeps it", function()
		put({}, chan())
		C():PutDetail(detail())
		skip(40 * DAY)
		put({}, chan())
		local ok, why = C():PutDetail(detail())
		eq(why, "unchanged")
		skip(40 * DAY)
		put({}, chan())
		eq(select(2, C():Housekeeping()), 0)
		notNil(C():Get(KEY).det)
	end)
end)

describe("the limit per realm and faction", function()
	local function fill(n, age)
		for i = 1, n do
			local name = ("Guild%03d"):format(i)
			local ok = put({ k = key(name) }, { dist = "WHISPER", annAt = GetServerTime() - (age and age(i) or 0) })
			if not ok then error("could not add " .. name) end
		end
	end

	it("holds 500; one more evicts the stalest", function()
		fill(500, function(i) return i * 60 end)   -- Guild500 is the stalest
		eq(C():Count(true), 500)
		record()
		eq(put({ k = key("Newcomer") }, chan()), true)
		eq(C():Count(true), 500)
		isNil(C():Get(key("Guild500")))
		notNil(C():Get(key("Guild499")))
		notNil(C():Get(key("Newcomer")))
		eq(events[1][2], "removed")
		eq(events[1][1], key("Guild500"))
		eq(events[2][2], "added")
	end)

	it("a newcomer staler than everything is refused", function()
		fill(500, function() return DAY end)
		local ok, why = put({ k = key("Ancient") }, { dist = "WHISPER", annAt = GetServerTime() - 5 * DAY })
		eq(ok, false) eq(why, "limit")
		eq(C():Count(true), 500)
	end)

	it("updating a listing never evicts anything", function()
		fill(500)
		eq(put({ k = key("Guild001"), rev = 2 }, chan()), true)
		eq(C():Count(true), 500)
	end)

	it("the limit is per realm and faction", function()
		fill(500)
		AzerothGuildFinderDB.catalog.OtherRealm = { Horde = {} }
		eq(C():Count(true), 500)
		eq(C():Housekeeping(), 0)
		eq(C():Count(true), 500)
	end)

	it("a saved catalog above the limit is trimmed when it loads", function()
		fill(500, function(i) return i * 60 end)
		local bucket = AzerothGuildFinderDB.catalog.TestRealm.Horde
		for i = 501, 510 do
			local name = ("Extra%03d"):format(i)
			local s = AzerothGuildFinder.Listing.SanitizeSummary(summary({ k = key(name) }))
			bucket[key(name)] = { sum = s, own = s.own, firstSeenAt = 1, annAt = GetServerTime() - i * 60, state = "listed" }
		end
		Mock.Reload()
		eq(C():Count(true), 500)
		isNil(AzerothGuildFinderDB.catalog.TestRealm.Horde[key("Extra510")])
		notNil(AzerothGuildFinderDB.catalog.TestRealm.Horde[key("Guild001")])
	end)
end)

describe("queries", function()
	it("lists A to Z by the normalized name, with symbols last", function()
		for _, name in ipairs({ "zeta", "[AD] Gank", "Ördine del Drago", "Alpha", "123", "beta", "Éclair" }) do
			put({ k = key(name) }, { dist = "WHISPER" })
		end
		local names = {}
		for _, s in ipairs(C():List()) do names[#names + 1] = s.k:match("[^|]*$") end
		deepEq(names, { "[AD] Gank", "Alpha", "beta", "Éclair", "Ördine del Drago", "zeta", "123" })
	end)

	it("the order is the one of Normalize.Compare", function()
		local names = { "delta", "Alpha", "charlie", "Bravo", "Écho", "foxtrot", "golf 2", "Golf-1" }
		for _, name in ipairs(names) do put({ k = key(name) }, { dist = "WHISPER" }) end
		local expected = {}
		for _, name in ipairs(names) do expected[#expected + 1] = name end
		table.sort(expected, AzerothGuildFinder.Normalize.Compare)
		local got = {}
		for _, s in ipairs(C():List()) do got[#got + 1] = s.k:match("[^|]*$") end
		deepEq(got, expected)
	end)

	it("filters keep the order and see the status", function()
		for _, name in ipairs({ "Cc", "Aa", "Bb" }) do put({ k = key(name), rec = name == "Bb" and 0 or 1 }, { dist = "WHISPER" }) end
		skip(20 * DAY)
		put({ k = key("Aa"), rev = 2 }, chan("Anna-TestRealm"))
		local seen = {}
		local list = C():List(function(s, info)
			seen[s.k:match("[^|]*$")] = info.status
			return s.rec ~= 0
		end)
		eq(#list, 2)
		eq(list[1].k, key("Aa"))
		eq(list[2].k, key("Cc"))
		eq(seen.Aa, "listed") eq(seen.Cc, "inactive") eq(seen.Bb, "inactive")
	end)

	it("a cached order follows additions and removals", function()
		put({ k = key("B") }, chan())
		eq(#C():List(), 1)
		put({ k = key("A") }, { dist = "WHISPER" })
		eq(C():List()[1].k, key("A"))
		eq(#C():List(), 2)
		skip(61 * DAY)
		C():Housekeeping()
		eq(#C():List(nil, { all = true }), 0)
	end)

	it("Get returns nothing for an unknown guild; Count and List are empty without data", function()
		isNil(C():Get(KEY))
		isNil(C():Status(KEY))
		eq(C():Count(), 0)
		deepEq(C():List(), {})
		deepEq(C():Digest(), {})
	end)

	it("the digest lists h, rev and srev, A to Z", function()
		put({ k = key("B"), rev = 4, st = { m = 3 }, srev = 900 }, chan())
		put({ k = key("A"), rev = 2 }, { dist = "WHISPER" })
		local N = AzerothGuildFinder.Normalize
		deepEq(C():Digest(), {
			{ h = N.Hash32(key("A")), rev = 2, srev = 0 },
			{ h = N.Hash32(key("B")), rev = 4, srev = 900 },
		})
	end)

	it("Newer offers what the other side lacks or has older, never hidden ones", function()
		local N = AzerothGuildFinder.Normalize
		put({ k = key("A"), rev = 3 }, chan("A-TestRealm"))
		put({ k = key("B"), rev = 3, st = { m = 5 }, srev = 200 }, chan("B-TestRealm"))
		put({ k = key("C"), rev = 3 }, chan("C-TestRealm"))
		put({ k = key("D"), rev = 3 }, { dist = "WHISPER", annAt = GetServerTime() - 40 * DAY })
		local remote = {
			{ h = N.Hash32(key("A")), rev = 3, srev = 0 },     -- up to date
			{ h = N.Hash32(key("B")), rev = 3, srev = 100 },   -- older statistics
			-- C missing; D missing but hidden
		}
		local got = {}
		for _, s in ipairs(C():Newer(remote)) do got[#got + 1] = s.k:match("[^|]*$") end
		deepEq(got, { "B", "C" })
		remote[1].rev = 2
		eq(#C():Newer(remote), 3)
		eq(#C():Newer(nil), 3)
		eq(#C():Newer({ "junk", { h = "x" } }), 3)
	end)

	it("/gf debug shows counts and no names", function()
		put({}, chan("Anna-TestRealm"))
		put({ k = key("B") }, chan("Anna-TestRealm"))   -- bans Anna
		Mock.Slash("/gf debug")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Listings: 1 listed")
		contains(text, "senders ignored now: 1")
		falsy(text:find("Anna", 1, true))
		falsy(text:find("Night Watch", 1, true))
	end)
end)

describe("persistence and memory", function()
	it("keeps listings across a reload", function()
		put({ rev = 3, sub = "kept" }, chan())
		C():PutDetail(detail({ rev = 3 }))
		local before = snapshot()
		Mock.Reload()
		eq(snapshot(), before)
		eq(C():Get(KEY).det.desc, "We raid on weekends.")
		eq(C():Status(KEY), "listed")
	end)

	it("never saves who announced what", function()
		put({}, chan("Zelda-TestRealm"))
		put({ k = key("Two") }, chan("Zelda-TestRealm"))   -- a ban in memory
		local function dump(v, seen)
			if type(v) ~= "table" then return tostring(v) end
			local out = {}
			for k, x in pairs(v) do out[#out + 1] = tostring(k) .. "=" .. dump(x) end
			return table.concat(out, ";")
		end
		falsy(dump(AzerothGuildFinderDB):find("Zelda", 1, true))
	end)

	it("forgets announcers on reload, so an old DEL is refused until they announce again", function()
		put({ rev = 2 }, chan("Gm-TestRealm"))
		Mock.Reload()
		eq(select(2, C():Delist(KEY, 2, chan("Gm-TestRealm"))), "not-announcer")
		put({ rev = 2 }, chan("Gm-TestRealm"))
		eq(C():Delist(KEY, 2, chan("Gm-TestRealm")), true)
		Mock.Reload()
		eq(C():Status(KEY), "delisted")
		eq(C():Get(KEY).delRev, 2)
	end)

	it("forgets sender bans on reload", function()
		put({ k = key("A") }, chan("Eve-TestRealm"))
		put({ k = key("B") }, chan("Eve-TestRealm"))
		Mock.Reload()
		eq(put({ k = key("B") }, chan("Eve-TestRealm")), true)
	end)

	it("the ownerId stays known after a reload", function()
		put({}, chan())
		Mock.Reload()
		eq(select(2, put({ own = "deadbeef" }, chan("Other-TestRealm"))), "owner")
	end)

	it("Clear forgets everything", function()
		record()
		put({}, chan("Zelda-TestRealm"))
		C():Clear()
		eq(C():Count(true), 0)
		deepEq(AzerothGuildFinderDB.catalog, {})
		deepEq(events[#events], { nil, "cleared" })
	end)
end)

describe("a damaged saved catalog", function()
	before_boot(function()
		local good = AzerothGuildFinder
		local now = GetServerTime()
		local function entry(k, extra)
			local e = { sum = { k = k, rev = 2, own = "a1b2c3d4", lang = 1, lang1 = 1, tags = { 1 }, pace = 1, sub = "ok" },
				own = "a1b2c3d4", firstSeenAt = now - 100, annAt = now - 50, state = "listed" }
			for f, v in pairs(extra or {}) do if v == "nil" then e[f] = nil else e[f] = v end end
			return e
		end
		local TR = "TestRealm|Horde|"
		AzerothGuildFinderDB = { schemaVersion = 1, catalog = { TestRealm = { Horde = {
			[TR .. "Good"] = entry(TR .. "Good"),
			[TR .. "NoTags"] = entry(TR .. "NoTags", { sum = { k = TR .. "NoTags", rev = 1, own = "a1b2c3d4" } }),
			[TR .. "WrongKey"] = entry(TR .. "Other"),
			[TR .. "NoTime"] = entry(TR .. "NoTime", { annAt = "yesterday" }),
			[TR .. "NotATable"] = "junk",
			["TestRealm|Alliance|Wrong"] = entry("TestRealm|Alliance|Wrong"),
			[42] = entry(TR .. "NumberKey"),
			[TR .. "Escapes"] = entry(TR .. "Escapes", { sum = { k = TR .. "Escapes", rev = 1, own = "a1b2c3d4", lang = 1, lang1 = 1,
				tags = { 1 }, pace = 1, sub = "|cffff0000x" } }),
			[TR .. "BadDetail"] = entry(TR .. "BadDetail", { det = { k = TR .. "Elsewhere", rev = 1 }, detAt = now }),
			[TR .. "Delisted"] = entry(TR .. "Delisted", { state = "delisted" }),
			[TR .. "FutureTime"] = entry(TR .. "FutureTime", { annAt = now + 10 * 86400 }),
		} } } }
	end)

	it("drops what is unusable and cleans the rest", function()
		local TR = "TestRealm|Horde|"
		local bucket = AzerothGuildFinderDB.catalog.TestRealm.Horde
		eq(C():Count(true), 5)
		notNil(bucket[TR .. "Good"])
		isNil(bucket[TR .. "NoTags"])
		isNil(bucket[TR .. "WrongKey"])
		isNil(bucket[TR .. "NoTime"])
		isNil(bucket[TR .. "NotATable"])
		isNil(bucket[42])
		eq(bucket[TR .. "Escapes"].sum.sub, "||cffff0000x")
		isNil(bucket[TR .. "BadDetail"].det)
		eq(bucket[TR .. "Delisted"].delRev, 2)
		notNil(bucket[TR .. "FutureTime"])
		eq(bucket[TR .. "FutureTime"].annAt, GetServerTime())   -- a time in the future is clamped to now
		deepEq(AzerothGuildFinderDB.catalog.TestRealm.Alliance, nil)
	end)

	it("a withdrawn saved listing is not listed", function()
		eq(C():Status("TestRealm|Horde|Delisted"), "delisted")
		eq(C():Count(), 4)   -- Good, Escapes, BadDetail and FutureTime
	end)
end)

describe("housekeeping at login", function()
	before_boot(function()
		local now = GetServerTime()
		local function old(k, days)
			local s = { k = k, rev = 1, own = "a1b2c3d4", lang = 1, lang1 = 1, tags = { 1 }, pace = 1 }
			return { sum = s, own = "a1b2c3d4", firstSeenAt = now - days * 86400, annAt = now - days * 86400, state = "listed" }
		end
		AzerothGuildFinderDB = { schemaVersion = 1, catalog = { TestRealm = { Horde = {
			["TestRealm|Horde|Fresh"] = old("TestRealm|Horde|Fresh", 1),
			["TestRealm|Horde|Ancient"] = old("TestRealm|Horde|Ancient", 61),
		} } } }
	end)

	it("purges old listings when the world loads", function()
		eq(C():Count(true), 1)
		notNil(C():Get("TestRealm|Horde|Fresh"))
		isNil(C():Get("TestRealm|Horde|Ancient"))
	end)
end)
