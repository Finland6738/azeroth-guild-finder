-- Decisions: what an officer or the Guild Master does with an application (Invite, Decline; SPEC-07 §5). Lua 5.1.
--
-- The panel (UI/Applications.lua) only asks; this module decides whether it may, talks to the game and changes the record
-- through Data/Inbox.lua (`Inbox:Decide`), which announces INBOX_CHANGED: Net/InboxSync.lua then tells the other officers
-- and Net/Delivery.lua answers the applicant's next APPPING with the new state, so nothing here sends a message.
--
--   Decisions:Decline(k, id)        received -> declined. true, or false and why ("role", "unknown", "state", "busy").
--   Decisions:Invite(k, id)         the game's guild invite (C_GuildInfo.Invite through Compat). The call returns nothing and
--                                   a refusal comes as a message, so the application becomes accepted only when the invite
--                                   went out without an error (SPEC-07 §5): the game's "invited" message accepts it at once,
--                                   an error message refuses it (offline, already in a guild, no permission, anything else
--                                   the game says in the next WATCH seconds), and a quiet WATCH seconds count as sent.
--                                   Returns true, "pending" | "manual", or false and why.
--   Decisions:MarkInvited(k, id)    the manual fallback: the officer says the invite was sent -> accepted.
--   Decisions.Classify(text, name, source)   pure: what a message of the game says about the invite of `name`.
--
-- Fallback (spike S10, M0.6, not yet run in the game): when C_GuildInfo.Invite is missing, restricted, or the client fires
-- ADDON_ACTION_FORBIDDEN / ADDON_ACTION_BLOCKED for this addon (a protected call), the Invite button opens the chat box with
-- "/ginvite Name " typed in (Compat.Chat.OpenGuildInvite) and the row offers "Mark as invited"; the game's "invited"
-- message in the next MANUAL_WATCH seconds marks it by itself. From then on the session goes straight to the fallback.
-- If even the chat box cannot be opened the panel says to invite the player by hand and to whisper.
--
-- Closing cases without a button (M4.6, SPEC-07 §2 and §5):
--   Decisions:OnListing(what, key)  the Guild Master withdrew the listing, or the verified guild copy this officer received
--                                   says so (OWN_LISTING_CHANGED "delisted" / "received" with the own copy delisted): every
--                                   open application of the guild becomes declined, by this character. A record that
--                                   still arrives open afterwards (from an officer who had not heard yet) is declined too.
--                                   Only the verified guild copy counts, never a DEL heard on the channel (INT-05 is
--                                   about hiding a listing, not about closing other people's applications).
--   Decisions:CheckJoined()         the roster says an applicant with an open record is a member of the guild now (he was
--                                   invited by other means): the record becomes accepted, `by` nil. Read at
--                                   GUILD_ROSTER_UPDATE at most every ROSTER_GAP seconds, with one more look after the gap
--                                   when events came meanwhile; nothing is requested from the server [verify in game: the
--                                   roster events the client gives without the guild window].
-- Bus: APPLICATIONS_CLOSED(k, state, count, why), why "delisted" or "joined".
--
-- Every change needs the role: the Guild Master or an officer of the guild of the key (SPEC-00 §5, APP-07).
-- Bus: DECISION_STARTED(k, id) when an invite is being watched; DECISION_RESULT(k, id, result, detail) with result
-- "accepted" | "declined" | "offline" | "refused" | "manual" | "changed" (another officer decided first, or it expired).
local ADDON_NAME, ns = ...
ns = ns or {}
local Decisions = {}
ns.Decisions, ns.modules = Decisions, ns.modules or {}
ns.modules.Decisions = Decisions

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

Decisions.WATCH = 3            -- seconds an invite is watched for an error before it counts as sent
Decisions.ROSTER_GAP = 60      -- seconds between two looks at the roster for applicants who joined
Decisions.MANUAL_WATCH = 90    -- seconds the game's "invited" message still marks a "/ginvite" typed by the officer

-- The game's messages about an invite: client global string, and the English text used when the client has none
-- [verify in game: the dump has no strings]. kind: "ok" the invite went out, "offline" the player is not online,
-- "refused" the game said no.
Decisions.MESSAGES = {
	{ kind = "ok", global = "ERR_GUILD_INVITE_S", fallback = "You have invited %s to join your guild." },
	{ kind = "offline", global = "ERR_CHAT_PLAYER_NOT_FOUND_S", fallback = "No player named '%s' is currently playing." },
	{ kind = "offline", global = "ERR_GUILD_PLAYER_NOT_FOUND_S", fallback = "\"%s\" not found." },
	{ kind = "refused", global = "ERR_ALREADY_IN_GUILD_S", fallback = "%s is already in a guild." },
	{ kind = "refused", global = "ERR_ALREADY_INVITED_TO_GUILD_S", fallback = "%s has already been invited to a guild." },
	{ kind = "refused", global = "ERR_GUILD_PERMISSIONS", fallback = "You don't have permission to do that." },
	{ kind = "refused", global = "ERR_GUILD_INTERNAL", fallback = "Internal guild error." },
}

local state
local function resetState()
	state = {
		pending = {},    -- [id] = { k, id, who, base, gen }: an invite the game is being watched for
		manual = {},     -- [id] = { k, who, base, until }: the fallback was offered for this application
		apiBlocked = false,
		gen = 0,
		stats = { invites = 0, accepted = 0, offline = 0, refused = 0, manual = 0, declined = 0, blocked = 0,
			delisted = 0, joined = 0 },
		rosterAt = nil, rosterArmed = false,
	}
	Decisions.state = state
end
resetState()

local function C() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function now() return C().Now() end

-- "Name" or "Name-Realm" -> "name".
local function baseName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return (name:match("^[^%-]+") or name):lower()
end

---------------------------------------------------------------------------------------------------------------------
-- The game's messages (pure)
---------------------------------------------------------------------------------------------------------------------
-- A client format string ("No player named '%s' is currently playing.") as a Lua pattern with one capture.
local function patternOf(fmt)
	local escaped = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	return "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
end

-- What `text` says about the invite of `name`: "ok", "offline", "refused" and the text, or nil when it is about
-- somebody else or about something else. source "error" (UI_ERROR_MESSAGE): a message that no pattern knows is
-- "refused" (the invite is accepted only if it started without an error); source "system" (CHAT_MSG_SYSTEM): unknown
-- messages are ignored (the chat is full of them).
function Decisions.Classify(text, name, source)
	if type(text) ~= "string" or text == "" then return nil end
	local base = baseName(name)
	for _, m in ipairs(Decisions.MESSAGES) do
		local fmt = C().GlobalString(m.global) or m.fallback
		local named = fmt:find("%s", 1, true) ~= nil
		local captured = text:match(patternOf(fmt))
		if captured ~= nil then
			if not named or baseName(captured:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")) == base then
				return m.kind, text
			end
		end
	end
	if source == "error" then return "refused", text end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------------------------------------------------
-- true when this character is the Guild Master or an officer of the guild `k` (APP-07).
local function contactOf(k)
	local Role = ns.Role
	if not Role or type(k) ~= "string" then return false end
	local role = Role:Get()
	return (role == "gm" or role == "officer") and Role:GuildKey() == k
end
function Decisions:Can(k) return contactOf(k) end

-- The open record id of guild k, or nil and why.
local function check(k, id)
	if not contactOf(k) then return nil, "role" end
	ns.Inbox:Sweep()   -- an application past its 14 days is expired even before the next sweep
	local rec = ns.Inbox:Get(k, id)
	if not rec then return nil, "unknown" end
	if not ns.Applications.IsOpen(rec) then return nil, "state" end
	return rec
end

local function byName() return C().Player.Name() end

-- "api": the game's own invite is tried first; "manual": the fallback of the header (missing, restricted or blocked).
function Decisions:Mode()
	if state.apiBlocked or C().Resolve("C_GuildInfo.Invite") == nil then return "manual" end
	return "api"
end

function Decisions:IsBusy(id) return state.pending[id] ~= nil end
function Decisions:IsManual(id) return state.manual[id] ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- Decline
---------------------------------------------------------------------------------------------------------------------
function Decisions:Decline(k, id)
	local rec, why = check(k, id)
	if not rec then return false, why end
	if state.pending[id] then return false, "busy" end
	local ok, reason = ns.Inbox:Decide(k, id, "declined", byName())
	if not ok then return false, reason end
	state.manual[id] = nil
	state.stats.declined = state.stats.declined + 1
	emit("DECISION_RESULT", k, id, "declined")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Invite
---------------------------------------------------------------------------------------------------------------------
-- The invite watched for `job` is over: `result` "accepted" changes the record (another officer may have decided first).
local function settle(job, result, detail)
	if state.pending[job.id] ~= job then return end
	state.pending[job.id] = nil
	job.settled = true
	if result == "accepted" then
		local ok, why = ns.Inbox:Decide(job.k, job.id, "accepted", byName())
		if not ok then result, detail = "changed", why end
	end
	if state.stats[result] then state.stats[result] = state.stats[result] + 1 end
	state.manual[job.id] = nil
	job.outcome = result
	emit("DECISION_RESULT", job.k, job.id, result, detail)
end

-- The fallback: the chat box with "/ginvite Name " and, on the row, "Mark as invited".
local function startManual(k, id, who, why)
	local opened = C().Chat.OpenGuildInvite(who)
	local m = state.manual[id] or { k = k, who = who, base = baseName(who) }
	m.watchUntil = now() + Decisions.MANUAL_WATCH
	state.manual[id] = m
	state.stats.manual = state.stats.manual + 1
	emit("DECISION_RESULT", k, id, "manual", opened and "chat" or "hand", why)
	return true, "manual"
end

function Decisions:Invite(k, id)
	local rec, why = check(k, id)
	if not rec then return false, why end
	if state.pending[id] then return false, "busy" end
	local who = rec.who
	if type(who) ~= "string" or who == "" then return false, "state" end
	if self:Mode() == "manual" then return startManual(k, id, who, state.apiBlocked and "blocked" or "missing") end

	local job = { k = k, id = id, who = who, base = baseName(who) }
	state.pending[id] = job
	state.gen = state.gen + 1
	job.gen = state.gen
	state.stats.invites = state.stats.invites + 1
	local sent, reason = C().Guild.Invite(who)
	if job.settled then return true, job.outcome end   -- the game answered inside the call
	if not sent then
		state.pending[id] = nil
		if reason == "name" then return false, "name" end
		state.apiBlocked = true
		state.stats.blocked = state.stats.blocked + 1
		return startManual(k, id, who, reason)
	end
	emit("DECISION_STARTED", k, id)
	local gen = job.gen
	local timer = C().After(Decisions.WATCH, function()
		if state.pending[id] == job and job.gen == gen then settle(job, "accepted") end
	end)
	if not timer then settle(job, "accepted") end   -- no timer to watch with: the call ran, that is all that can be known
	return true, job.settled and job.outcome or "pending"
end

-- The officer says the invite was sent (the fallback's "Mark as invited").
function Decisions:MarkInvited(k, id)
	local rec, why = check(k, id)
	if not rec then return false, why end
	if state.pending[id] then return false, "busy" end
	local ok, reason = ns.Inbox:Decide(k, id, "accepted", byName())
	if not ok then return false, reason end
	state.manual[id] = nil
	state.stats.accepted = state.stats.accepted + 1
	emit("DECISION_RESULT", k, id, "accepted")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- What the game says
---------------------------------------------------------------------------------------------------------------------
local function onText(text, source)
	for _, job in pairs(state.pending) do
		local kind, detail = Decisions.Classify(text, job.who, source)
		if kind == "ok" then settle(job, "accepted")
		elseif kind then settle(job, kind, detail) end
	end
	if source == "system" then
		local t = now()
		for id, m in pairs(state.manual) do
			if m.watchUntil and t <= m.watchUntil and Decisions.Classify(text, m.who, "system") == "ok" then
				m.watchUntil = nil
				Decisions:MarkInvited(m.k, id)
			end
		end
	end
end

-- A protected call from an addon does not raise: the client fires ADDON_ACTION_FORBIDDEN (or ..._BLOCKED) and drops it.
local function onBlocked(addon)
	if addon ~= ADDON_NAME then return end
	for id, job in pairs(state.pending) do
		state.pending[id] = nil
		job.settled = true
		job.outcome = "manual"
		state.apiBlocked = true
		state.stats.blocked = state.stats.blocked + 1
		startManual(job.k, id, job.who, "blocked")
	end
end

-- true when the guild copy of this character is withdrawn (the verified one: the Guild Master's own, or a GLIST that the
-- roster's Guild Master sent, Data/OwnListing.lua).
local function listingWithdrawn()
	local OL = ns.OwnListing
	return OL ~= nil and OL:Status() == "delisted"
end

local function closed(k, st, n, why)
	state.stats[why] = state.stats[why] + n
	emit("APPLICATIONS_CLOSED", k, st, n, why)
end

-- The listing of guild k was withdrawn: its open applications are declined (SPEC-07 §2).
function Decisions:OnListing(what, k)
	if what ~= "delisted" and what ~= "received" then return 0 end
	if not contactOf(k) or not listingWithdrawn() then return 0 end
	local n = ns.Inbox:CloseOpen(k, "declined", byName())
	if n > 0 then closed(k, "declined", n, "delisted") end
	return n
end

-- A closed application needs no fallback any more.
-- An invite being watched when the record closes (another officer decided first, the player withdrew) ends there.
local function onInboxChanged(k, id, st, old, source)
	if st ~= "received" and st ~= "sent" then
		state.manual[id] = nil
		local job = state.pending[id]
		if job then settle(job, "changed", "state") end
	elseif source == "sync" and contactOf(k) and listingWithdrawn() then
		-- a copy that is still open reached us after the guild withdrew its listing: it closes like the others
		if ns.Inbox:Decide(k, id, "declined", byName()) then closed(k, "declined", 1, "delisted") end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Applicants who joined
---------------------------------------------------------------------------------------------------------------------
-- The names (lower case, without the realm) of the guild's roster, as a set; nil while the roster is empty.
local function rosterNames()
	local G = C().Guild
	local total = (G.RosterCount())   -- (two results: tonumber would read the second as a base)
	total = math.min(type(total) == "number" and total or 0, G.MAX_ROSTER)
	if total <= 0 then return nil end
	local set = {}
	for i = 1, total do
		local row = G.RosterRow(i)
		local base = row and baseName(row.name)
		if base then set[base] = true end
	end
	return set
end

-- Closes as accepted the open records of the guild whose applicant is in the roster. `force`: ignore the gap.
function Decisions:CheckJoined(force)
	local Role = ns.Role
	local k = Role and Role:GuildKey()
	if not k or not contactOf(k) or ns.Inbox:Count(k, true) == 0 then return 0 end
	local t = now()
	if not force and state.rosterAt and t - state.rosterAt < Decisions.ROSTER_GAP then
		if not state.rosterArmed then
			state.rosterArmed = true
			C().After(Decisions.ROSTER_GAP - (t - state.rosterAt) + 0.5, function()
				state.rosterArmed = false
				Decisions:CheckJoined()
			end)
		end
		return 0
	end
	state.rosterAt = t
	local names = rosterNames()
	if not names then return 0 end
	local n = ns.Inbox:CloseOpen(k, "accepted", nil, function(rec) return names[baseName(rec.who)] == true end)
	if n > 0 then closed(k, "accepted", n, "joined") end
	return n
end

function Decisions:Reset() resetState() end

function Decisions:DebugLines()
	local s, n = state.stats, 0
	for _ in pairs(state.pending) do n = n + 1 end
	return { ("Decisions: invite by %s%s, tried %d (accepted %d, offline %d, refused %d, blocked %d), manual %d, declined %d, watching %d, closed by delisting %d, by joining %d"):format(
		self:Mode() == "api" and "the game's call" or "/ginvite", state.apiBlocked and " (blocked)" or "", s.invites, s.accepted,
		s.offline, s.refused, s.blocked, s.manual, s.declined, n, s.delisted, s.joined) }
end

if ns.Bus then
	ns.Bus:On("INBOX_CHANGED", onInboxChanged)
	ns.Bus:On("OWN_LISTING_CHANGED", function(what, k) Decisions:OnListing(what, k) end)
end
if ns.addon then
	ns.addon.Decisions = Decisions
	-- Own AceEvent object: the addon object keeps one handler per event.
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if AceEvent then
		AceEvent:Embed(Decisions)
		Decisions:RegisterEvent("UI_ERROR_MESSAGE", function(_, _, message) onText(message, "error") end)
		Decisions:RegisterEvent("CHAT_MSG_SYSTEM", function(_, text) onText(text, "system") end)
		Decisions:RegisterEvent("GUILD_ROSTER_UPDATE", function() Decisions:CheckJoined() end)
		Decisions:RegisterEvent("ADDON_ACTION_FORBIDDEN", function(_, addon) onBlocked(addon) end)
		Decisions:RegisterEvent("ADDON_ACTION_BLOCKED", function(_, addon) onBlocked(addon) end)
	end
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Decisions", function() return Decisions:DebugLines() end) end
end
