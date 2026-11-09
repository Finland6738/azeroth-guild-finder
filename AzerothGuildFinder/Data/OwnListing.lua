-- OwnListing: the listing of the player's own guild (SPEC-06 §1, §3-§5, SPEC-02 §5, §7, ADR 0021). Lua 5.1.
--
--   draft        AzerothGuildFinderCharDB.ownListing.draft: the editor's work in progress (any fields, tagged with the
--                guild key), saved without limits, never sent. Only the Guild Master saves one.
--   guild copy   ownListing.published: the full record (summary + detail, SPEC-03 §2-§3) of the guild's listing, for
--                every role: the Guild Master's own publication, or the newest GLIST a member accepted. del = true
--                marks a withdrawn listing (the content stays, so the editor can publish it again with one click).
--   publish      Guild Master only, IsGuildLeader() read again first, at most one every PUBLISH_GAP seconds (pubAt is
--                saved, so /reload does not reset it): rev = highest revision known + 1, upd = now, first and own kept
--                from the guild copy (or the public catalog, for a new Guild Master whose copy never arrived) or made
--                at the first publication. Then GLIST over GUILD, ANN on the channel (c = 1) and the detail in the
--                local catalog, so this client answers DETREQ.
--   delist       a revision of its own: rev + 1, del = true; GLIST over GUILD and DEL on the channel (Sync:Withdraw).
--   GLIST        accepted only over GUILD and only from the Guild Master of the roster (rank 0, INT-02); refused from
--                anybody else. While the roster is not loaded the newest GLIST waits ROSTER_WAIT seconds for it. The
--                newer copy (INT-01) replaces the guild copy and goes in the local catalog; then the member relays it
--                on the channel after RELAY_DELAY, unless an ANN of that revision was heard in the last RECENT_ANN
--                seconds (SPEC-02 §5). A withdrawn copy is relayed as a DEL, only by a client that announced the guild
--                itself this session (INT-05: the others would refuse its DEL).
--   GLREQ        a member asks at login, and when the public catalog shows a newer revision than its copy, after
--                REQUEST_DELAY, unless a GLIST or another member's GLREQ for the same or an older revision arrived
--                meanwhile; one per REQUEST_GAP. Only the Guild Master answers (a member's GLIST would be refused by
--                INT-02 anyway): one GLIST over GUILD serves every member, at most one answer per REPLY_GAP.
--   GM change    the roster decides: the old Guild Master's GLIST is refused as soon as the roster names another one;
--                the new one publishes from the guild copy, so the ownerId stays (SPEC-06 §5).
--
-- Bus event: OWN_LISTING_CHANGED(what, k), what = "draft", "published", "delisted", "received". Sender names stay in
-- memory for the length of one check and are never printed or saved.
local ADDON_NAME, ns = ...
ns = ns or {}
local OwnListing = {}
ns.OwnListing, ns.modules = OwnListing, ns.modules or {}
ns.modules.OwnListing = OwnListing

local type, pairs, tostring, tonumber = type, pairs, tostring, tonumber
local floor, max, random = math.floor, math.max, math.random

---------------------------------------------------------------------------------------------------------------------
-- Constants (read on use, so tests may change them)
---------------------------------------------------------------------------------------------------------------------
OwnListing.PUBLISH_GAP = 300          -- SPEC-06 §3: one published save every 5 minutes
OwnListing.REQUEST_DELAY = { 3, 10 }  -- login or a newer public revision -> GLREQ
OwnListing.REQUEST_GAP = 300          -- one GLREQ per client in this time
OwnListing.REPLY_DELAY = 2            -- Guild Master: GLREQs heard in this window share one GLIST
OwnListing.REPLY_GAP = 30             -- Guild Master: one GLIST answer in this time
OwnListing.RELAY_DELAY = { 5, 30 }    -- SPEC-02 §5: a member's ANN after a newer GLIST
OwnListing.RECENT_ANN = 60            -- an ANN of the same revision heard in this time suppresses the relay
OwnListing.ROSTER_WAIT = 30           -- a GLIST waits this long for the roster to name the Guild Master
OwnListing.AUTO = true                -- false: no GLREQ by itself (the single-client tests switch it off)

local DETAIL_FIELDS = { desc = true, disc = true, cont = true, note = true }

---------------------------------------------------------------------------------------------------------------------
-- State (memory only)
---------------------------------------------------------------------------------------------------------------------
local function newStats()
	return {
		published = 0, delisted = 0, glistSent = 0, glistReceived = 0, accepted = 0, refused = 0, older = 0, foreign = 0,
		invalid = 0, rosterWaits = 0, requestsSent = 0, requestsHeard = 0, requestsSuppressed = 0, replies = 0,
		relays = 0, relaysSuppressed = 0, delRelays = 0,
	}
end

local state
local function resetState()
	state = {
		announced = {},        -- [k] = true: this client announced guild k on the channel this session
		pending = nil,         -- { msg, sender, at }: a GLIST waiting for the roster
		lastGlistAt = nil,     -- Now() of the last GLIST accepted or sent
		heardRequestAt = nil,  -- Now() of the last GLREQ of another member that our own would repeat
		lastRequestAt = nil, requestGen = 0, requestItem = nil,
		replyAt = nil, replyPending = false,
		relayGen = {},
		stats = newStats(),
	}
	OwnListing.state = state
end
resetState()

local function C() return ns.Compat end
local function now() return C().Now() end
local function clock() return C().ServerTime() end
local function rnd(range) return range[1] + (range[2] - range[1]) * random() end
local function after(seconds, fn) return C().After(seconds, fn) end
local function emit(...) if ns.Bus then ns.Bus:Emit(...) end end

-- "Name" or "Name-Realm" -> "name": the roster and AceComm may disagree about the realm suffix (one realm only).
local function baseName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return (name:match("^[^%-]+") or name):lower()
end
local function isSelf(sender)
	local mine = baseName(C().Player.Name())
	return mine ~= nil and baseName(sender) == mine
end

local function store()
	local db = ns.Config and ns.Config.db and ns.Config.db.char
	if type(db) ~= "table" then return nil end
	if type(db.ownListing) ~= "table" then db.ownListing = {} end
	return db.ownListing
end
local function readOnly() return ns.Config ~= nil and ns.Config.IsReadOnly ~= nil and ns.Config:IsReadOnly("char") end

-- Read from the client every time (not the cached Role): the role, the guild key.
local function current()
	if not ns.Role then return "none", nil end
	return ns.Role.Compute()
end

-- Plain data only (no functions, no cycles), at most a few levels deep: drafts come from the editor.
local function plain(v, depth)
	local t = type(v)
	if t == "string" or t == "number" or t == "boolean" then return v end
	if t ~= "table" or (depth or 0) > 4 then return nil end
	local out = {}
	for k, value in pairs(v) do
		local kt = type(k)
		if kt == "string" or kt == "number" then out[k] = plain(value, (depth or 0) + 1) end
	end
	return out
end

-- The sanitized full record plus the withdrawn flag, or nil.
local function full(rec)
	if type(rec) ~= "table" then return nil end
	local out = ns.Listing.SanitizeFull(rec)
	if not out then return nil end
	if rec.del == true then out.del = true end
	return out
end

local function summaryOf(rec)
	local s = {}
	for field, value in pairs(rec) do
		if not DETAIL_FIELDS[field] and field ~= "del" then s[field] = value end
	end
	return s
end

local function detailOf(rec)
	local d = { k = rec.k, rev = rec.rev }
	for field in pairs(DETAIL_FIELDS) do d[field] = rec[field] end
	return d
end

-- INT-01 for two guild copies: true when a beats b (rev, then upd, then the lower hash of the content).
local function beats(a, b)
	if not b then return true end
	if a.rev ~= b.rev then return a.rev > b.rev end
	local ua, ub = a.upd or 0, b.upd or 0
	if ua ~= ub then return ua > ub end
	local ea, eb = ns.Catalog.Encode(a), ns.Catalog.Encode(b)
	if ea == eb then return false end
	local ha, hb = ns.Normalize.Hash32(ea), ns.Normalize.Hash32(eb)
	if ha ~= hb then return ha < hb end
	return ea < eb
end

local function newOwner() return ("%04x%04x"):format(random(0, 65535), random(0, 65535)) end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------

-- The guild copy (a sanitized copy, del = true when withdrawn), or nil without one for the current guild.
function OwnListing:Get()
	local s = store()
	local _, key = current()
	local p = s and s.published
	if type(p) ~= "table" or not key or p.k ~= key then return nil end
	return full(p)
end

-- "none" | "listed" | "delisted": the state of the guild copy.
function OwnListing:Status()
	local copy = self:Get()
	if not copy then return "none" end
	return copy.del and "delisted" or "listed"
end

-- The draft of the current guild (a copy), or nil.
function OwnListing:Draft()
	local s = store()
	local _, key = current()
	local d = s and s.draft
	if type(d) ~= "table" or not key or d.k ~= key then return nil end
	return plain(d)
end

-- May this character change the listing now? Returns the guild key, or nil plus "nodb", "readonly", "no-guild" or
-- "not-leader" (SPEC-06 §1: IsGuildLeader() is asked again before every save).
function OwnListing:CanEdit()
	if not store() then return nil, "nodb" end
	if readOnly() then return nil, "readonly" end
	local _, key = current()
	if not key then return nil, "no-guild" end
	if not C().Guild.IsGuildLeader() then return nil, "not-leader" end
	return key
end

-- Seconds before the next publication is allowed (0 = now).
function OwnListing:PublishWait()
	local s = store()
	local at = s and s.pubAt
	if type(at) ~= "number" then return 0 end
	local wait = at + OwnListing.PUBLISH_GAP - clock()
	return wait > 0 and wait or 0
end

---------------------------------------------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------------------------------------------
local function sendGlist(rec)
	local msg = plain(rec)
	msg.t = "GLIST"
	state.lastGlistAt = now()
	state.stats.glistSent = state.stats.glistSent + 1
	return ns.Transport:Send("GUILD", msg, { key = "GLIST" })
end

-- The summary on the channel (Sync:Announce also puts it in the local catalog) and the detail in the local catalog.
local function announce(rec, contact)
	ns.Sync:Announce(summaryOf(rec), { contact = contact })
	ns.Catalog:PutDetail(detailOf(rec))
	state.announced[rec.k] = true
end

---------------------------------------------------------------------------------------------------------------------
-- The Guild Master's side
---------------------------------------------------------------------------------------------------------------------

-- Saves the editor's fields as the draft (no limits, nothing is sent). Returns true, or false plus a reason.
function OwnListing:SaveDraft(fields)
	local key, why = self:CanEdit()
	if not key then return false, why end
	if type(fields) ~= "table" then return false, "shape" end
	local d = plain(fields)
	d.k, d.rev, d.upd, d.first, d.own, d.del, d.test, d.t = key, nil, nil, nil, nil, nil, nil, nil
	store().draft = d
	emit("OWN_LISTING_CHANGED", "draft", key)
	return true
end

-- Forgets the draft ("Discard changes": back to the published version).
function OwnListing:DiscardDraft()
	local s = store()
	if not s or readOnly() then return false, s and "readonly" or "nodb" end
	local _, key = current()
	s.draft = nil
	emit("OWN_LISTING_CHANGED", "draft", key)
	return true
end

-- The highest revision this client knows for guild k: guild copy, public summary, public withdrawal.
local function highestRev(k, copy)
	local entry = ns.Catalog:Get(k)
	return max(copy and copy.rev or 0, entry and entry.sum.rev or 0, entry and entry.delRev or 0), entry
end

-- Publishes `fields` (default: the draft, else the guild copy). Returns true, "published", or false plus "nodb",
-- "readonly", "no-guild", "not-leader", "rate" (and the seconds to wait) or "incomplete".
function OwnListing:Publish(fields)
	local key, why = self:CanEdit()
	if not key then return false, why end
	local wait = self:PublishWait()
	if wait > 0 then return false, "rate", wait end
	local source = fields or self:Draft() or self:Get()
	if type(source) ~= "table" then return false, "incomplete" end
	local copy = self:Get()
	local rev, entry = highestRev(key, copy)
	local t = clock()
	local raw = plain(source)
	raw.k, raw.rev, raw.upd = key, rev + 1, t
	raw.first = copy and copy.first or (entry and entry.sum.first) or t
	raw.own = copy and copy.own or (entry and entry.own) or newOwner()
	raw.del, raw.test, raw.st, raw.srev, raw.t = nil, nil, nil, nil, nil   -- statistics arrive with M3.7
	local rec = ns.Listing.SanitizeFull(raw)
	if not rec or not rec.own or not ns.Listing.IsComplete(rec) then return false, "incomplete" end
	local s = store()
	s.published, s.pubAt, s.draft = rec, t, nil
	state.stats.published = state.stats.published + 1
	sendGlist(rec)
	announce(rec, true)
	emit("OWN_LISTING_CHANGED", "published", key)
	return true, "published"
end

-- Withdraws the listing (SPEC-06 §4). Returns true, "delisted", or false plus a CanEdit reason or "not-listed".
-- Withdrawing is never rate limited; publishing again still waits for PUBLISH_GAP after the last publication.
function OwnListing:Delist()
	local key, why = self:CanEdit()
	if not key then return false, why end
	local copy = self:Get()
	local rev, entry = highestRev(key, copy)
	local base = copy
	if not base or base.del then
		-- no guild copy here: a new Guild Master whose GLIST never arrived may still withdraw the public listing
		base = nil
		if entry and entry.state ~= "delisted" then
			local merged = plain(entry.sum)
			for field, value in pairs(entry.det or {}) do if DETAIL_FIELDS[field] then merged[field] = value end end
			base = full(merged)
		end
		if not base then return false, "not-listed" end
	end
	local rec = plain(base)
	rec.rev, rec.upd, rec.del, rec.st, rec.srev = rev + 1, clock(), true, nil, nil
	rec = full(rec)
	store().published = rec
	state.stats.delisted = state.stats.delisted + 1
	sendGlist(rec)
	ns.Sync:Withdraw(key, rec.rev)
	emit("OWN_LISTING_CHANGED", "delisted", key)
	return true, "delisted"
end

---------------------------------------------------------------------------------------------------------------------
-- The members' side
---------------------------------------------------------------------------------------------------------------------
local function scheduleRelay(rec)
	local k = rec.k
	state.relayGen[k] = (state.relayGen[k] or 0) + 1
	local gen = state.relayGen[k]
	if rec.del and not state.announced[k] then return end
	after(rnd(OwnListing.RELAY_DELAY), function()
		if state.relayGen[k] ~= gen then return end
		local copy = OwnListing:Get()
		if not copy or copy.rev ~= rec.rev or (copy.del and true or false) ~= (rec.del and true or false) then return end
		if copy.del then
			state.stats.delRelays = state.stats.delRelays + 1
			ns.Sync:Withdraw(k, copy.rev)
			return
		end
		if ns.Sync:Suppressed(k, copy.rev, 0, now() - OwnListing.RECENT_ANN) then
			state.stats.relaysSuppressed = state.stats.relaysSuppressed + 1
			return
		end
		state.stats.relays = state.stats.relays + 1
		local role = current()
		announce(copy, role == "officer" or role == "gm")
	end)
end

local dropOwnRequest   -- forward (GLREQ section)

-- A GLIST whose sender the roster confirmed as the Guild Master.
local function accept(msg, sender)
	local _, key = current()
	if not key or msg.k ~= key then
		state.stats.foreign = state.stats.foreign + 1
		return false, "foreign"
	end
	local rec = full(msg)
	if not rec or not rec.own or not ns.Listing.IsComplete(rec) then
		state.stats.invalid = state.stats.invalid + 1
		return false, "invalid"
	end
	local s = store()
	if not s or readOnly() then return false, "readonly" end
	local copy = OwnListing:Get()
	if copy and not beats(rec, copy) then
		state.stats.older = state.stats.older + 1
		return false, rec.rev < copy.rev and "older" or "unchanged"
	end
	s.published = rec
	state.lastGlistAt = now()
	state.stats.accepted = state.stats.accepted + 1
	dropOwnRequest()
	-- the public catalog follows the guild copy (summary first: a withdrawn listing needs an entry for its tombstone)
	ns.Catalog:PutSummary(summaryOf(rec), { dist = "GUILD", sender = sender })
	if rec.del then
		ns.Catalog:Delist(rec.k, rec.rev, { trusted = true })
	else
		ns.Catalog:PutDetail(detailOf(rec), { dist = "GUILD" })
	end
	scheduleRelay(rec)
	emit("OWN_LISTING_CHANGED", "received", key)
	return true, rec.del and "delisted" or "accepted"
end

-- INT-02: the roster names the Guild Master; nothing else does. Returns accepted, reason.
local function verify(msg, sender)
	local leader = C().Guild.LeaderName()
	if not leader then
		local p = state.pending
		if not p or (tonumber(msg.rev) or 0) >= (tonumber(p.msg.rev) or 0) then
			state.pending = { msg = msg, sender = sender, at = now() }
		end
		state.stats.rosterWaits = state.stats.rosterWaits + 1
		C().Guild.RequestRoster()
		return false, "roster"
	end
	if baseName(leader) ~= baseName(sender) then
		state.stats.refused = state.stats.refused + 1
		return false, "not-leader"
	end
	return accept(msg, sender)
end

local function onGlist(msg, sender)
	if isSelf(sender) then return false, "self" end   -- the server sends our own GUILD messages back
	state.stats.glistReceived = state.stats.glistReceived + 1
	return verify(msg, sender)
end

-- GUILD_ROSTER_UPDATE: a GLIST that waited for the roster is checked now (or dropped after ROSTER_WAIT).
function OwnListing:OnRoster()
	local p = state.pending
	if not p then return end
	if now() - p.at > OwnListing.ROSTER_WAIT then state.pending = nil return end
	if not C().Guild.LeaderName() then return end
	state.pending = nil
	return verify(p.msg, p.sender)
end

-- Sends a GLREQ now (members and officers; the Guild Master has nobody to ask). Returns true, or false plus
-- "no-guild", "leader" or "rate".
function OwnListing:Request()
	local _, key = current()
	if not key then return false, "no-guild" end
	if C().Guild.IsGuildLeader() then return false, "leader" end
	local t = now()
	if state.lastRequestAt and t - state.lastRequestAt < OwnListing.REQUEST_GAP then return false, "rate" end
	state.lastRequestAt = t
	local copy = self:Get()
	state.stats.requestsSent = state.stats.requestsSent + 1
	state.requestItem = ns.Transport:Send("GUILD", { t = "GLREQ", rev = copy and copy.rev or 0 }, { key = "GLREQ" })
	return true
end

-- A GLREQ after REQUEST_DELAY, skipped when a GLIST or another member's GLREQ that serves us too arrives first.
function OwnListing:ScheduleRequest()
	if not OwnListing.AUTO then return false end
	state.requestGen = state.requestGen + 1
	local gen, since = state.requestGen, now()
	after(rnd(OwnListing.REQUEST_DELAY), function()
		if gen ~= state.requestGen then return end
		if (state.lastGlistAt and state.lastGlistAt >= since) or (state.heardRequestAt and state.heardRequestAt >= since) then
			state.stats.requestsSuppressed = state.stats.requestsSuppressed + 1
			return
		end
		OwnListing:Request()
	end)
	return true
end

-- Guild Master: one GLIST answers every GLREQ heard in REPLY_DELAY, at most one answer per REPLY_GAP.
local function scheduleReply()
	if state.replyPending then return end
	state.replyPending = true
	local wait = OwnListing.REPLY_DELAY
	if state.replyAt then wait = max(wait, state.replyAt + OwnListing.REPLY_GAP - now()) end
	after(wait, function()
		state.replyPending = false
		local copy = OwnListing:Get()
		if not copy or not C().Guild.IsGuildLeader() then return end
		state.replyAt = now()
		state.stats.replies = state.stats.replies + 1
		sendGlist(copy)
	end)
end

-- Our GLREQ still waiting in the queue is not needed any more (a GLIST arrived, or another member asked the same).
dropOwnRequest = function()
	local item = state.requestItem
	state.requestItem = nil
	if item and ns.Transport:Cancel(item) then
		state.stats.requestsSent = state.stats.requestsSent - 1
		state.stats.requestsSuppressed = state.stats.requestsSuppressed + 1
	end
end

local function onGlreq(msg, sender)
	if isSelf(sender) then return end
	state.stats.requestsHeard = state.stats.requestsHeard + 1
	local copy = OwnListing:Get()
	local theirs = tonumber(msg.rev) or 0
	if theirs <= (copy and copy.rev or 0) then   -- the answer will reach us too
		state.heardRequestAt = now()
		dropOwnRequest()
	end
	if not copy or theirs >= copy.rev or not C().Guild.IsGuildLeader() then return end
	scheduleReply()
end

function OwnListing:OnMessage(msg, sender, dist)
	if dist ~= "GUILD" then return end   -- INT-02: the server delivers GUILD messages to members only
	if msg.t == "GLIST" then return onGlist(msg, sender) end
	if msg.t == "GLREQ" then return onGlreq(msg, sender) end
end

-- CATALOG_UPDATED: the public catalog shows a newer revision of our guild than the guild copy -> ask for it.
function OwnListing:OnCatalog(k)
	if not ns.Role or k ~= ns.Role:GuildKey() then return end   -- cheap filter: a full sync updates hundreds of keys
	local role, key = current()
	if not key or k ~= key or role == "gm" then return end
	local entry = ns.Catalog:Get(k)
	if not entry then return end
	local copy = self:Get()
	if max(entry.sum.rev, entry.delRev or 0) > (copy and copy.rev or 0) then self:ScheduleRequest() end
end

-- ROLE_CHANGED: a GLIST waiting for another guild's roster is dropped; a member of a guild asks for the copy.
function OwnListing:OnRoleChanged(role, key, oldRole, oldKey)
	if key ~= oldKey then state.pending = nil end
	if key and role ~= "gm" and role ~= "none" then self:ScheduleRequest() end
end

function OwnListing:Reset() resetState() end

---------------------------------------------------------------------------------------------------------------------
-- Texts for the editor and /gf debug (no names)
---------------------------------------------------------------------------------------------------------------------
local REASON_KEYS = {
	published = "OWN_PUBLISHED", delisted = "OWN_DELISTED", ["not-leader"] = "OWN_NOT_LEADER", rate = "OWN_RATE",
	incomplete = "OWN_INCOMPLETE", ["no-guild"] = "OWN_NO_GUILD", readonly = "OWN_READ_ONLY", nodb = "OWN_READ_ONLY",
	["not-listed"] = "OWN_NOT_LISTED",
}

-- The sentence for a result of Publish, Delist or SaveDraft (wait: the seconds of a "rate" result).
function OwnListing:Explain(reason, wait)
	local L = ns.L
	local key = REASON_KEYS[reason]
	if not L or not key then return tostring(reason) end
	if reason == "rate" then
		local seconds = floor((tonumber(wait) or 0) + 0.5)
		return L[key]:format(("%d:%02d"):format(floor(seconds / 60), seconds % 60))
	end
	return L[key]
end

-- /gf debug publish | delist (development builds): the Guild Master's listing before the editor exists (M3.2). Publish
-- takes the draft, else the guild copy, else SAMPLE, through the normal rules (Guild Master only, 5-minute limit).
OwnListing.SAMPLE = {
	sub = "Listing published with /gf debug publish", lang = 1, lang1 = 1, tags = { 11 }, pace = 1, days = 127, t0 = 0,
	t1 = 0, rec = 1, apps = false, newb = true, minL = 1,
	desc = "A listing published by a development build to check the guild sync. The editor arrives with M3.2.",
}

function OwnListing:DebugCommand(sub)
	local say = function(text) if ns.addon and ns.addon.Print then ns.addon:Print(text) end end
	if not (ns.Config and ns.Config.DEV) then return say(ns.L["OWN_DEBUG_DEV_ONLY"]) end
	local ok, why, wait
	if sub == "delist" then
		ok, why = self:Delist()
	else
		ok, why, wait = self:Publish(self:Draft() or self:Get() or OwnListing.SAMPLE)
	end
	say(self:Explain(why, wait))
	return ok, why
end

function OwnListing:DebugLines()
	local s = state.stats
	local copy = self:Get()
	return {
		("Own listing: guild copy %s, draft %s, next publication %s"):format(
			copy and (("rev %d (%s)"):format(copy.rev, copy.del and "withdrawn" or "listed")) or "none",
			self:Draft() and "yes" or "no",
			self:PublishWait() > 0 and (("in %d s"):format(floor(self:PublishWait()))) or "allowed"),
		("  published %d, delisted %d, GLIST sent %d, received %d (accepted %d, refused %d, older %d, other guild %d, invalid %d, waited for roster %d)"):format(
			s.published, s.delisted, s.glistSent, s.glistReceived, s.accepted, s.refused, s.older, s.foreign, s.invalid,
			s.rosterWaits),
		("  GLREQ sent %d (skipped %d), heard %d, answered %d; relayed ANN %d (suppressed %d), DEL %d"):format(
			s.requestsSent, s.requestsSuppressed, s.requestsHeard, s.replies, s.relays, s.relaysSuppressed, s.delRelays),
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------------------------------------
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(msg, sender, dist) OwnListing:OnMessage(msg, sender, dist) end)
	ns.Bus:On("ROLE_CHANGED", function(...) OwnListing:OnRoleChanged(...) end)
	ns.Bus:On("CATALOG_UPDATED", function(k, what) if k then OwnListing:OnCatalog(k) end end)
end
if ns.addon then
	ns.addon.OwnListing = OwnListing
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Own listing", function() return OwnListing:DebugLines() end) end
	-- Own AceEvent object: the addon object keeps one handler per event, and Role already uses these two.
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if AceEvent then
		AceEvent:Embed(OwnListing)
		OwnListing:RegisterEvent("GUILD_ROSTER_UPDATE", function() OwnListing:OnRoster() end)
		OwnListing:RegisterEvent("PLAYER_ENTERING_WORLD", function()
			local role, key = current()
			if key and role ~= "gm" and role ~= "none" then OwnListing:ScheduleRequest() end
		end)
	end
end
