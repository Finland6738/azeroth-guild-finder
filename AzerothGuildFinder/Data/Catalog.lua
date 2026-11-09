-- Catalog: the local catalog of guild listings every client keeps in SavedVariables (SPEC-03 §1, SPEC-02 §8).
-- Lua 5.1. No server: every client applies the same merge rules, so clients that hear the same updates, in any
-- order, end with the same listings (INT-01). Nothing here reads a player or guild name from the client except the
-- player's own realm and faction (only those listings are accepted, D4/D5).
--
-- Storage (account-wide): AzerothGuildFinderDB.catalog[realm][faction][guildKey] =
--   { sum, det, own, firstSeenAt, annAt, state, delRev, delAt, detAt }
--   sum          the sanitized summary (Listing.SanitizeSummary), with the statistics `st`/`srev` merged in
--   det          the sanitized detail (Listing.SanitizeDetail) or nil; detAt = when it was last received
--   own          the ownerId known for the guild (INT-03)
--   firstSeenAt  when this client first heard of the listing; annAt = last time it was announced (staleness clock)
--   state        "listed" | "delisted" (a DEL tombstone: delRev = highest revision withdrawn, delAt = when)
--   localOnly    true for listings put in with meta.localOnly (the development seed, /gf debug seed): kept and shown
--                here, never offered to other clients (not in the digest, not in CAT answers)
-- Who announced what (INT-04, INT-05) lives in memory only and is NEVER saved: sender names stay out of the file.
--
-- meta (all optional) describes where a record came from:
--   meta.sender   who sent it (Name-Realm), memory only      meta.dist    "CHANNEL" | "WHISPER" | "GUILD" | ...
--   meta.now      override the clock (tests)                 meta.annAt   when a peer last heard an ANN (CAT replies)
--   meta.localOnly  the listing is never shared with other clients (new entries only)
-- INT-04 and INT-05 apply to announcements that arrive in the channel (meta.dist == "CHANNEL"): there the sender
-- is required. A record without meta (local use) or from another distribution skips those two rules.
--
-- Writes return `changed, reason`: changed is true when the stored data changed; reason is "added", "updated",
-- "stats", "takeover", "relisted", "detail", "delisted", "unchanged", "older" or a rejection ("invalid", "foreign",
-- "incomplete", "no-owner", "no-sender", "ignored-sender", "owner", "unknown", "not-announcer", "ahead", "expired", "limit").
-- The Bus event CATALOG_UPDATED(k, what) follows every change, what = "added", "updated", "stats", "detail",
-- "delisted", "removed", "cleared" (k is nil). Query results are the stored tables: read them, never change them.
local ADDON_NAME, ns = ...
ns = ns or {}
local Catalog = {}
ns.Catalog, ns.modules = Catalog, ns.modules or {}
ns.modules.Catalog = Catalog

local type, pairs, ipairs, tostring, tonumber, next, select = type, pairs, ipairs, tostring, tonumber, next, select
local floor, max, min = math.floor, math.max, math.min
local format, sub, find = string.format, string.sub, string.find
local sort, concat = table.sort, table.concat

local DAY = 86400
-- Age is measured from the last announcement (annAt) and every limit is crossed when the age is MORE than the value.
Catalog.AGE = {
	INACTIVE = 14 * DAY,   -- "May be inactive" in the list
	HIDDEN = 30 * DAY,     -- no longer listed; also: a different ownerId may take over (INT-03)
	PURGE = 60 * DAY,      -- removed from the file
}
Catalog.SENDER_WINDOW = DAY       -- INT-04: one guild per sender in this time
Catalog.SENDER_IGNORE = DAY       -- INT-04: how long a sender that announced two guilds is ignored
Catalog.MAX_ANNOUNCERS = 50       -- announcers remembered per guild (INT-05), oldest forgotten first
Catalog.MAX_SENDERS = 1000        -- senders remembered for INT-04

local function Listing() return ns.Listing end
local function Normalize() return ns.Normalize end

local function limit() return ns.Config and ns.Config.LIMITS.LISTINGS_PER_REALM_FACTION or 500 end
local function detailSeconds() return ns.Config and ns.Config.LIMITS.DETAIL_CACHE_SECONDS or 60 * DAY end

local function clock()
	if ns.Compat and ns.Compat.ServerTime then return ns.Compat.ServerTime() end
	return time()
end

local function nowOf(meta)
	if meta and type(meta.now) == "number" then return meta.now end
	return clock()
end

---------------------------------------------------------------------------------------------------------------------
-- Memory only: who announced what
---------------------------------------------------------------------------------------------------------------------
local announcers = {}   -- [guildKey] = { [sender] = time of the last accepted ANN }
local senders = {}      -- [sender] = { k = guild, at = time, ignoreUntil = time }
local senderCount = 0
local version = 0       -- bumped by every change: the sorted list is rebuilt when it moves
local sortedCache       -- { version =, bucket =, keys = }
local checked = setmetatable({}, { __mode = "k" })   -- buckets already validated this session

local function changed() version = version + 1 end

local function emit(k, what)
	changed()
	if ns.Bus then ns.Bus:Emit("CATALOG_UPDATED", k, what) end
end

local function rememberAnnouncer(k, sender, t)
	if not sender then return end
	local list = announcers[k]
	if not list then list = {} announcers[k] = list end
	list[sender] = t
	local n, oldest, oldestAt = 0, nil, nil
	for s, at in pairs(list) do
		n = n + 1
		if not oldestAt or at < oldestAt then oldest, oldestAt = s, at end
	end
	if n > Catalog.MAX_ANNOUNCERS then list[oldest] = nil end
end

local function pruneSenders(t)
	local n = 0
	for s, info in pairs(senders) do
		if (info.ignoreUntil and t >= info.ignoreUntil) or (not info.ignoreUntil and t - info.at >= Catalog.SENDER_WINDOW) then
			senders[s] = nil
		else
			n = n + 1
		end
	end
	senderCount = n
end

-- INT-04. true when `sender` may announce `k`; false when it is ignored. A second guild within 24 h starts the ban.
local function senderMayAnnounce(sender, k, t)
	local s = senders[sender]
	if not s then
		if senderCount >= Catalog.MAX_SENDERS then pruneSenders(t) end
		if senderCount >= Catalog.MAX_SENDERS then return true end   -- table full of live entries: do not track
		senders[sender] = { k = k, at = t }
		senderCount = senderCount + 1
		return true
	end
	if s.ignoreUntil then
		if t < s.ignoreUntil then return false end
		s.k, s.at, s.ignoreUntil = k, t, nil   -- the ban is over: a fresh start
		return true
	end
	if s.k == k or t - s.at >= Catalog.SENDER_WINDOW then
		s.k, s.at = k, t
		return true
	end
	s.ignoreUntil = t + Catalog.SENDER_IGNORE
	return false
end

local function senderIgnored(sender, t)
	local s = senders[sender]
	return s ~= nil and s.ignoreUntil ~= nil and t < s.ignoreUntil
end

---------------------------------------------------------------------------------------------------------------------
-- Canonical encoding and the deterministic tie-break (INT-01)
---------------------------------------------------------------------------------------------------------------------
local function keyLess(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then return ta < tb end
	return a < b
end

local function encodeInto(v, out)
	local t = type(v)
	if t == "table" then
		local keys = {}
		for key in pairs(v) do keys[#keys + 1] = key end
		sort(keys, keyLess)
		out[#out + 1] = "{"
		for _, key in ipairs(keys) do
			encodeInto(key, out)
			out[#out + 1] = "="
			encodeInto(v[key], out)
			out[#out + 1] = ";"
		end
		out[#out + 1] = "}"
	elseif t == "string" then
		out[#out + 1] = #v .. ":" .. v
	elseif t == "number" then
		out[#out + 1] = format("%.17g", v)
	else
		out[#out + 1] = tostring(v)
	end
end

-- The same text for the same content on every client, whatever the order the fields were inserted in.
function Catalog.Encode(v)
	local out = {}
	encodeInto(v, out)
	return concat(out)
end

-- true when the encoded text `a` is preferred to `b`: the lower 32-bit hash, then the lower text.
local function lowerFirst(a, b)
	local ha, hb = Normalize().Hash32(a), Normalize().Hash32(b)
	if ha ~= hb then return ha < hb end
	return a < b
end

-- A summary has two independent parts: the content (ordered by rev, upd) and the statistics (newest srev wins).
local function split(sum)
	local content, stats = {}, {}
	for field, value in pairs(sum) do
		if field == "st" or field == "srev" then stats[field] = value else content[field] = value end
	end
	return content, stats
end

local function contentBeats(a, b)
	if a.rev ~= b.rev then return a.rev > b.rev end
	local ua, ub = a.upd or 0, b.upd or 0
	if ua ~= ub then return ua > ub end
	local ea, eb = Catalog.Encode(a), Catalog.Encode(b)
	if ea == eb then return false end
	return lowerFirst(ea, eb)
end

local function statsBeat(inc, cur)
	if not inc.st then return false end
	if not cur.st then return true end
	local si, sc = inc.srev or 0, cur.srev or 0
	if si ~= sc then return si > sc end
	local ei, ec = Catalog.Encode(inc.st), Catalog.Encode(cur.st)
	if ei == ec then return false end
	return lowerFirst(ei, ec)
end

local function compose(content, stats)
	local out = {}
	for field, value in pairs(content) do out[field] = value end
	out.st, out.srev = stats.st, stats.srev
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Buckets, validation and status
---------------------------------------------------------------------------------------------------------------------
local function playerRealmFaction()
	local compat = ns.Compat
	if not compat then return nil end
	return compat.Player.Realm(), compat.Player.Faction()
end

local function root()
	local db = ns.Config and ns.Config.db and ns.Config.db.account
	if db and type(db.catalog) == "table" then return db.catalog end
end

local function bucketOf(realm, faction, create)
	local cat = root()
	if not cat or not realm or not faction then return nil end
	local r = cat[realm]
	if type(r) ~= "table" then
		if not create then return nil end
		r = {}
		cat[realm] = r
	end
	local b = r[faction]
	if type(b) ~= "table" then
		if not create then return nil end
		b = {}
		r[faction] = b
	end
	return b
end

local function last(entry)
	return max(entry.annAt or 0, entry.delAt or 0)
end

-- "listed" | "inactive" (14 days without ANN) | "hidden" (30) | "delisted" (DEL not answered by a higher rev).
local function statusOf(entry, t)
	if entry.state == "delisted" then return "delisted" end
	local age = t - entry.annAt
	if age > Catalog.AGE.HIDDEN then return "hidden" end
	if age > Catalog.AGE.INACTIVE then return "inactive" end
	return "listed"
end

local function isNumber(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= 0 end

-- Brings one saved entry into shape (the file may be damaged or edited). Returns false when it must be dropped.
local function validateEntry(k, entry, realm, faction)
	if type(k) ~= "string" or type(entry) ~= "table" then return false end
	local r, f = Listing().ParseKey(k)
	if r ~= realm or f ~= faction then return false end
	local sum = Listing().SanitizeSummary(entry.sum)
	if not sum or sum.k ~= k or not sum.own or not Listing().IsComplete(sum) then return false end
	if not isNumber(entry.annAt) then return false end
	local t = clock()
	local function time_(v, default) return isNumber(v) and min(floor(v), t) or default end   -- never in the future
	entry.sum, entry.own = sum, sum.own
	entry.annAt = time_(entry.annAt)
	entry.firstSeenAt = time_(entry.firstSeenAt, entry.annAt)
	if entry.state == "delisted" then
		if not isNumber(entry.delRev) or entry.delRev < 1 then entry.delRev = sum.rev end
		entry.delAt = time_(entry.delAt, entry.annAt)
	else
		entry.state, entry.delRev, entry.delAt = "listed", nil, nil
	end
	if entry.localOnly ~= true then entry.localOnly = nil end
	if entry.det ~= nil then
		local det = Listing().SanitizeDetail(entry.det)
		if det and det.k == k then
			entry.det = det
			entry.detAt = time_(entry.detAt, entry.annAt)
		else
			entry.det, entry.detAt = nil, nil
		end
	else
		entry.detAt = nil
	end
	return true
end

local function count(bucket)
	local n = 0
	for _ in pairs(bucket) do n = n + 1 end
	return n
end

-- The stalest entry (oldest last announcement, ties by key) of a bucket.
local function stalest(bucket)
	local bestK, bestLast
	for k, entry in pairs(bucket) do
		local l = last(entry)
		if not bestLast or l < bestLast or (l == bestLast and k < bestK) then bestK, bestLast = k, l end
	end
	return bestK, bestLast
end

-- Removes the entry and returns the event to emit (callers emit after their loops).
local function drop(bucket, k)
	bucket[k] = nil
	announcers[k] = nil
end

local function validateBucket(bucket, realm, faction)
	local events = {}
	for k, entry in pairs(bucket) do
		if not validateEntry(k, entry, realm, faction) then
			drop(bucket, k)
			events[#events + 1] = k
		end
	end
	local limitN = limit()
	while count(bucket) > limitN do
		local k = stalest(bucket)
		drop(bucket, k)
		events[#events + 1] = k
	end
	checked[bucket] = true
	for _, k in ipairs(events) do emit(k, "removed") end
end

-- The player's own realm and faction bucket, validated once per session.
local function playerBucket(create)
	local realm, faction = playerRealmFaction()
	local bucket = bucketOf(realm, faction, create)
	if bucket and not checked[bucket] then validateBucket(bucket, realm, faction) end
	return bucket, realm, faction
end

---------------------------------------------------------------------------------------------------------------------
-- Putting records in
---------------------------------------------------------------------------------------------------------------------
-- Makes room for one more entry whose last announcement is `newLast`. false when it is staler than everything.
local function makeRoom(bucket, newLast)
	if count(bucket) < limit() then return true end
	local k, l = stalest(bucket)
	if l > newLast then return false end
	drop(bucket, k)
	emit(k, "removed")
	return true
end

-- The ANN time recorded for a record: a channel announcement is "now"; a second-hand record keeps what the peer said.
local function announcedAt(meta, t, isNew)
	if meta and meta.dist == "CHANNEL" then return t end
	if meta and isNumber(meta.annAt) then return min(t, floor(meta.annAt)) end
	return isNew and t or nil
end

-- INT-04 and INT-05 need a sender for what arrives in the channel.
local function channelOnly(meta) return meta and meta.dist == "CHANNEL" end

-- The record's guild must be on the player's realm and faction. Returns bucket, key or nil, reason.
local function targetBucket(k)
	local realm, faction = playerRealmFaction()
	if not realm or not faction then return nil, "foreign" end
	local r, f = Listing().ParseKey(k)
	if r ~= realm or f ~= faction then return nil, "foreign" end
	local bucket = bucketOf(realm, faction, true)
	if bucket and not checked[bucket] then validateBucket(bucket, realm, faction) end
	return bucket
end

-- Applies a summary (ANN, CAT, GLIST): INT-01, INT-03, INT-04. Returns changed, reason.
function Catalog:PutSummary(rec, meta)
	meta = meta or {}
	local sum = Listing().SanitizeSummary(rec)
	if not sum then return false, "invalid" end
	local bucket, why = targetBucket(sum.k)
	if not bucket then return false, why end
	if not sum.own then return false, "no-owner" end
	if not Listing().IsComplete(sum) then return false, "incomplete" end
	local t = nowOf(meta)
	local channel = channelOnly(meta)
	local at = announcedAt(meta, t, true)
	if t - at > Catalog.AGE.PURGE then return false, "expired" end

	if channel then   -- INT-04
		if not meta.sender then return false, "no-sender" end
		if senderIgnored(meta.sender, t) or not senderMayAnnounce(meta.sender, sum.k, t) then
			return false, "ignored-sender"
		end
	end

	local entry = bucket[sum.k]
	local takeover = false
	if entry and entry.own ~= sum.own then   -- INT-03: the known owner sticks unless it has been silent for 30 days
		if t - entry.annAt <= Catalog.AGE.HIDDEN then return false, "owner" end
		takeover = true
	end

	if not entry or takeover then
		if takeover then
			drop(bucket, sum.k)
		elseif not makeRoom(bucket, at) then
			return false, "limit"
		end
		bucket[sum.k] = { sum = sum, own = sum.own, firstSeenAt = t, annAt = at, state = "listed",
			localOnly = meta.localOnly and true or nil }
		if channel then rememberAnnouncer(sum.k, meta.sender, t) end
		emit(sum.k, takeover and "updated" or "added")
		return true, takeover and "takeover" or "added"
	end

	-- The same listing again: refresh the clock, then merge content and statistics independently.
	if channel or isNumber(meta.annAt) then entry.annAt = max(entry.annAt, at) end
	if channel then rememberAnnouncer(sum.k, meta.sender, t) end

	local curContent, curStats = split(entry.sum)
	local incContent, incStats = split(sum)
	local contentWins = contentBeats(incContent, curContent)
	local statsWin = statsBeat(incStats, curStats)
	if not contentWins and not statsWin then
		return false, incContent.rev < curContent.rev and "older" or "unchanged"
	end
	entry.sum = compose(contentWins and incContent or curContent, statsWin and incStats or curStats)
	if entry.state == "delisted" and entry.sum.rev > (entry.delRev or 0) then   -- INT-05: a higher rev re-lists it
		entry.state, entry.delRev, entry.delAt = "listed", nil, nil
		emit(sum.k, "updated")
		return true, "relisted"
	end
	if entry.state ~= "delisted" then emit(sum.k, contentWins and "updated" or "stats") end
	return true, contentWins and "updated" or "stats"
end

-- Applies a detail (DET, GLIST). The listing must be known and the detail not newer than its summary
-- (a forged revision cannot lock out the real detail). Returns changed, reason.
function Catalog:PutDetail(rec, meta)
	meta = meta or {}
	local det = Listing().SanitizeDetail(rec)
	if not det then return false, "invalid" end
	local bucket, why = targetBucket(det.k)
	if not bucket then return false, why end
	local entry = bucket[det.k]
	if not entry then return false, "unknown" end
	local t = nowOf(meta)
	if det.rev > entry.sum.rev then return false, "ahead" end
	local cur = entry.det
	if cur then
		if det.rev < cur.rev then return false, "older" end
		if det.rev == cur.rev then
			local ec, ed = Catalog.Encode(cur), Catalog.Encode(det)
			if ec == ed then entry.detAt = max(entry.detAt or 0, t) return false, "unchanged" end
			if not lowerFirst(ed, ec) then return false, "older" end
		end
	end
	entry.det, entry.detAt = det, t
	emit(det.k, "detail")
	return true, "detail"
end

-- DEL (INT-05): k, rev. Only a sender that announced this guild in the channel may withdraw it. The tombstone keeps
-- the withdrawn revision, so a late ANN of that revision or older cannot bring the listing back. Returns changed, reason.
function Catalog:Delist(k, rev, meta)
	meta = meta or {}
	if not Listing().IsValidKey(k) or type(rev) ~= "number" or rev ~= rev or rev < 1 or rev ~= floor(rev) then
		return false, "invalid"
	end
	local bucket, why = targetBucket(k)
	if not bucket then return false, why end
	local t = nowOf(meta)
	if channelOnly(meta) and meta.sender and senderIgnored(meta.sender, t) then return false, "ignored-sender" end
	local entry = bucket[k]
	if not entry then return false, "unknown" end
	if not meta.sender then return false, "no-sender" end
	local list = announcers[k]
	if not list or not list[meta.sender] then return false, "not-announcer" end
	if rev < entry.sum.rev then return false, "older" end
	if entry.state == "delisted" and rev <= (entry.delRev or 0) then return false, "unchanged" end
	entry.state, entry.delRev, entry.delAt = "delisted", rev, t
	emit(k, "delisted")
	return true, "delisted"
end

---------------------------------------------------------------------------------------------------------------------
-- Staleness
---------------------------------------------------------------------------------------------------------------------
-- Purges what is 60 days old, drops details unseen for 60 days, forgets old sender bans. Returns purged, detailsDropped.
function Catalog:Housekeeping(t)
	t = t or clock()
	local cat = root()
	local purged, details, events = 0, 0, {}
	if cat then
		-- The player's bucket is validated; the other realms and factions of the account are only purged by age
		-- (damaged entries there wait until that realm is played, when they are checked).
		local own = playerBucket(false)
		for realm, factions in pairs(cat) do
			for faction, bucket in pairs(factions) do
				if bucket == own and not checked[bucket] then validateBucket(bucket, realm, faction) end
				for k, entry in pairs(bucket) do
					if type(entry) ~= "table" or not isNumber(entry.annAt) then
						-- left alone
					elseif t - last(entry) > Catalog.AGE.PURGE then
						drop(bucket, k)
						purged = purged + 1
						events[#events + 1] = { k, "removed" }
					elseif entry.det and t - (isNumber(entry.detAt) and entry.detAt or entry.annAt) > detailSeconds() then
						entry.det, entry.detAt = nil, nil
						details = details + 1
						events[#events + 1] = { k, "detail" }
					end
				end
			end
		end
	end
	pruneSenders(t)
	for _, e in ipairs(events) do emit(e[1], e[2]) end
	return purged, details
end

-- Removes the listings that were put in as local only (the development seed). Returns how many.
function Catalog:RemoveLocal()
	local bucket = playerBucket(false)
	local n = 0
	if bucket then
		for k, entry in pairs(bucket) do
			if entry.localOnly then drop(bucket, k) n = n + 1 end
		end
	end
	if n > 0 then emit(nil, "cleared") end
	return n
end

-- Forgets everything: all saved listings (every realm) and what was learned about senders (for `/gf reset` and tests).
function Catalog:Clear()
	local cat = root()
	if cat then for realm in pairs(cat) do cat[realm] = nil end end
	announcers, senders, senderCount, sortedCache = {}, {}, 0, nil
	emit(nil, "cleared")
end

---------------------------------------------------------------------------------------------------------------------
-- Queries (the player's realm and faction)
---------------------------------------------------------------------------------------------------------------------
local function guildName(k) return select(3, Listing().ParseKey(k)) or k end

local function sortedKeys(bucket)
	if sortedCache and sortedCache.version == version and sortedCache.bucket == bucket then return sortedCache.keys end
	local keys, names = {}, {}
	for k in pairs(bucket) do
		keys[#keys + 1] = k
		names[k] = guildName(k)
	end
	local compare = Normalize().Compare
	sort(keys, function(a, b) return compare(names[a], names[b]) end)
	sortedCache = { version = version, bucket = bucket, keys = keys }
	return keys
end

-- The listings the user may see, always A -> Z (Normalize.Compare, ADR 0009): listed ones and those that "may be
-- inactive", not the hidden or withdrawn. filterFn(summary, info) -> true keeps one; info = { status, annAt,
-- firstSeenAt, hasDetail }. opts.all lists hidden and withdrawn ones too.
function Catalog:List(filterFn, opts)
	local bucket = playerBucket(false)
	local out = {}
	if not bucket then return out end
	local t = clock()
	local all = opts and opts.all
	for _, k in ipairs(sortedKeys(bucket)) do
		local entry = bucket[k]
		local status = statusOf(entry, t)
		if all or status == "listed" or status == "inactive" then
			local keep = true
			if filterFn then
				keep = filterFn(entry.sum, { status = status, annAt = entry.annAt, firstSeenAt = entry.firstSeenAt,
					hasDetail = entry.det ~= nil })
			end
			if keep then out[#out + 1] = entry.sum end
		end
	end
	return out
end

-- The stored entry of a guild (any status) and its status, or nil.
function Catalog:Get(k)
	local bucket = playerBucket(false)
	local entry = bucket and bucket[k]
	if not entry then return nil end
	return entry, statusOf(entry, clock())
end

function Catalog:Status(k)
	local entry, status = self:Get(k)
	return status
end

-- The number of listings the user may see; Count(true) counts everything stored.
function Catalog:Count(all)
	local bucket = playerBucket(false)
	if not bucket then return 0 end
	if all then return count(bucket) end
	local t, n = clock(), 0
	for _, entry in pairs(bucket) do
		local status = statusOf(entry, t)
		if status == "listed" or status == "inactive" then n = n + 1 end
	end
	return n
end

-- For CATREQ: one { h, rev, srev } per stored listing (withdrawn ones too, so nobody sends them back), A -> Z. Local
-- only listings are left out: they are not ours to share.
function Catalog:Digest()
	local bucket = playerBucket(false)
	local out = {}
	if not bucket then return out end
	for _, k in ipairs(sortedKeys(bucket)) do
		local sum = bucket[k].sum
		if not bucket[k].localOnly then out[#out + 1] = { h = Normalize().Hash32(k), rev = sum.rev, srev = sum.srev or 0 } end
	end
	return out
end

-- For answering a CATREQ: the summaries the requester lacks or has an older revision (or statistics) of, A -> Z.
-- Hidden, withdrawn and local only listings are never offered.
function Catalog:Newer(remote)
	local bucket = playerBucket(false)
	local out = {}
	if not bucket then return out end
	local have = {}
	for _, d in ipairs(type(remote) == "table" and remote or {}) do
		if type(d) == "table" and type(d.h) == "number" then have[d.h] = d end
	end
	local t = clock()
	for _, k in ipairs(sortedKeys(bucket)) do
		local entry = bucket[k]
		local status = statusOf(entry, t)
		if (status == "listed" or status == "inactive") and not entry.localOnly then
			local r = have[Normalize().Hash32(k)]
			local sum = entry.sum
			if not r or (tonumber(r.rev) or 0) < sum.rev
				or ((tonumber(r.rev) or 0) == sum.rev and (tonumber(r.srev) or 0) < (sum.srev or 0)) then
				out[#out + 1] = sum
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- /gf debug
---------------------------------------------------------------------------------------------------------------------
function Catalog:DebugLines()
	local bucket = playerBucket(false)
	if not bucket then return { "Catalog: no data for this realm and faction" } end
	local t = clock()
	local n = { listed = 0, inactive = 0, hidden = 0, delisted = 0 }
	local details = 0
	for _, entry in pairs(bucket) do
		local s = statusOf(entry, t)
		n[s] = n[s] + 1
		if entry.det then details = details + 1 end
	end
	local banned = 0
	for s in pairs(senders) do if senderIgnored(s, t) then banned = banned + 1 end end
	return {
		("Listings: %d listed, %d may be inactive, %d hidden, %d withdrawn (limit %d)"):format(
			n.listed, n.inactive, n.hidden, n.delisted, limit()),
		("Details cached: %d; senders ignored now: %d"):format(details, banned),
	}
end

if ns.addon then
	local addon = ns.addon
	addon.Catalog = Catalog
	if addon.AddDebugSection then addon:AddDebugSection("Catalog", function() return Catalog:DebugLines() end) end
	-- Housekeeping every time the world loads. Own AceEvent object: the addon object keeps one handler per event
	-- and Role already uses PLAYER_ENTERING_WORLD. (No timer: staleness is computed from the clock on every query.)
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if AceEvent then
		AceEvent:Embed(Catalog)
		Catalog:RegisterEvent("PLAYER_ENTERING_WORLD", function() Catalog:Housekeeping() end)
	end
end
