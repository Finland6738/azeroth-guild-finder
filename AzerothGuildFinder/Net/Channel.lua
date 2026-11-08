-- Channel: the hidden permanent channel AzGuildFinder (SPEC-02 §1, ADR 0003). Lua 5.1.
--
--   * joins with JoinChannelByName (a temporary channel would refuse addon messages), waits for the answer and tries
--     again every RETRY seconds while it fails;
--   * takes the channel out of every chat window, moves it after the other channels (so /1 stays General, not in
--     combat lockdown) and hides its join/leave/notice lines with chat message filters;
--   * knows the channel limit: a join that cannot happen because the character is in MAX_CHANNELS channels is not
--     attempted, it is reported once and tried again every RETRY seconds;
--   * gives the channel number to the Transport (Transport.channelId) and tells the rest of the addon on the Bus.
-- Every client call goes through Compat; with an API missing the module degrades (no hiding, no moving) and never raises.
--
-- Bus events:
--   CHANNEL_READY(id)       the channel is joined (also after it was lost and joined again).
--   CHANNEL_FAILED(reason)  a join did not work: "limit" (too many channels), "throttled", "banned", "refused" (the
--                           client refused it), "timeout" (no answer), "unavailable" (no join function), "left" (the
--                           player left the channel). Emitted when the reason changes, not on every retry.
local ADDON_NAME, ns = ...
ns = ns or {}
local Channel = {}
ns.Channel, ns.modules = Channel, ns.modules or {}
ns.modules.Channel = Channel

local type, ipairs = type, ipairs
local lower, find = string.lower, string.find

Channel.NAME = "AzGuildFinder"
Channel.RETRY = 60            -- seconds between two join attempts while it fails (OneForAll, totalRP3)
Channel.START_DELAY = 5       -- after entering the world: the client joins General and the zone channels first
Channel.JOIN_WAIT = 5         -- seconds to wait for the client's answer to a join
Channel.HIDE_AGAIN = { 1, 5 } -- the client may add the channel to a chat window after the notice: hide it again
Channel.MAX_CHANNELS = 10     -- the client's limit of joined channels (to confirm on Forever, SPEC-10)

-- Notices of the channel system that mean "not joined": code -> reason. Other notices are ignored.
Channel.FAILING_NOTICES = {
	THROTTLED = "throttled", BANNED = "banned", WRONG_PASSWORD = "refused", INVALID_NAME = "refused",
	NOT_IN_AREA = "refused", NOT_IN_LFG = "refused", NOT_ON_TAXI = "refused", NOT_IN_CITY = "refused",
}
-- Chat events whose lines about this channel are hidden.
Channel.FILTERED_EVENTS = {
	"CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE",
	"CHAT_MSG_CHANNEL",
}

local state
local function resetState(keepFilters)
	state = {
		ready = false, started = false, attempts = 0, failures = 0, lastReason = nil, reported = nil,
		attempt = 0, waiting = nil, noticeReason = nil,   -- the attempt being waited for, the failing notice seen during it
		joinGen = 0, pendingMove = false, limitWarned = false, filtered = 0, hid = 0, moved = 0,
		filtersInstalled = keepFilters or false,
	}
	Channel.state = state
end
resetState()

local function compat() return ns.Compat end
local function emit(event, ...)
	if ns.Bus then ns.Bus:Emit(event, ...) end
end

-- The number of the channel right now (it changes when channels are moved), nil when not joined.
function Channel:Id()
	local C = compat()
	local id = C and C.GetChannelName(Channel.NAME)
	if type(id) == "number" and id > 0 then return id end
	return nil
end

function Channel:IsReady() return state.ready and Channel:Id() ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- Hiding, moving, filtering
---------------------------------------------------------------------------------------------------------------------

-- Takes the channel out of every chat window. Returns the number of windows it was applied to.
function Channel:Hide()
	local n = compat().RemoveChannelFromChatFrames(Channel.NAME)
	state.hid = state.hid + 1
	return n
end

-- Moves the channel behind every other one. Waits for the end of combat lockdown. Returns true when it is at the end.
function Channel:MoveToEnd()
	local C = compat()
	local id = Channel:Id()
	if not id then return false end
	if C.InCombat() then
		state.pendingMove = true
		return false
	end
	state.pendingMove = false
	local list = C.GetChannelList()
	if not list then return false end
	local last = id
	for _, entry in ipairs(list) do
		if entry.id > last then last = entry.id end
	end
	for i = id, last - 1 do
		if C.SwapChatChannels(i, i + 1) ~= C.AVAILABLE then return false end
		state.moved = state.moved + 1
	end
	return true
end

local function ours(text)
	return type(text) == "string" and find(lower(text), lower(Channel.NAME), 1, true) ~= nil
end

-- Chat message filter: hides the lines of this channel (arguments of the CHAT_MSG_CHANNEL* events: text, sender,
-- language, "N. Channel name", target, flags, zone channel id, channel index, channel base name).
local function filter(_, _, _, _, _, channelString, _, _, _, _, channelName)
	if ours(channelName) or ours(channelString) then
		state.filtered = state.filtered + 1
		return true
	end
	return false
end
Channel.Filter = filter

function Channel:InstallFilters()
	if state.filtersInstalled then return end
	state.filtersInstalled = true
	for _, event in ipairs(Channel.FILTERED_EVENTS) do compat().AddChatFilter(event, filter) end
end

---------------------------------------------------------------------------------------------------------------------
-- Joining
---------------------------------------------------------------------------------------------------------------------
local join   -- forward

local function scheduleJoin(delay)
	state.joinGen = state.joinGen + 1
	local gen = state.joinGen
	compat().After(delay, function() if gen == state.joinGen then join() end end)
end

local function onJoined()
	state.joinGen = state.joinGen + 1   -- cancels a pending retry
	state.waiting = nil
	Channel:Hide()
	Channel:MoveToEnd()
	for _, delay in ipairs(Channel.HIDE_AGAIN) do
		compat().After(delay, function() if Channel:Id() then Channel:Hide() end end)
	end
	if state.ready then return end
	state.ready, state.failures, state.lastReason, state.reported = true, 0, nil, nil
	if ns.Transport then ns.Transport:ClearListenOnly() end   -- a refusal of the old channel says nothing about this one
	emit("CHANNEL_READY", Channel:Id())
end

local function fail(reason)
	state.waiting, state.noticeReason = nil, nil
	state.ready = false
	state.failures, state.lastReason = state.failures + 1, reason
	if reason == "limit" and not state.limitWarned and ns.addon and ns.addon.Print then
		state.limitWarned = true
		ns.addon:Print(ns.L["CHANNEL_LIMIT"]:format(Channel.MAX_CHANNELS))
	end
	if reason ~= state.reported then
		state.reported = reason
		emit("CHANNEL_FAILED", reason)
	end
	if reason == "unavailable" then return end   -- the client has no join function: trying again changes nothing
	scheduleJoin(math.max(Channel.RETRY - Channel.JOIN_WAIT, 0))
end

-- The answer to attempt `attempt` (the timer ran out, or the notice came): joined, or why not.
local function check(attempt)
	if state.waiting ~= attempt then return end
	if Channel:Id() then return onJoined() end
	if state.noticeReason then return fail(state.noticeReason) end
	local list = compat().GetChannelList()
	if list and #list >= Channel.MAX_CHANNELS then return fail("limit") end
	return fail("timeout")
end

-- One attempt: already joined, too many channels, or ask the client and wait for its answer.
join = function()
	state.attempts = state.attempts + 1
	if Channel:Id() then return onJoined() end
	local C = compat()
	local list = C.GetChannelList()
	if list and #list >= Channel.MAX_CHANNELS then
		return fail("limit")   -- joining would only print an error in the chat: do not ask
	end
	state.attempt = state.attempt + 1
	local attempt = state.attempt
	state.waiting, state.noticeReason = attempt, nil
	local joinState = C.JoinChannelByName(Channel.NAME)
	if joinState == C.MISSING then return fail("unavailable") end
	if joinState ~= C.AVAILABLE then return fail("refused") end
	C.After(Channel.JOIN_WAIT, function() check(attempt) end)
end
Channel.Join = function() join() end

-- Starts joining after the start delay (once per session). Returns false when it was already started.
function Channel:Start()
	if state.started then return false end
	state.started = true
	scheduleJoin(Channel.START_DELAY)
	return true
end

-- Forgets everything (tests); the chat filters stay installed because the client cannot remove them anyway.
function Channel:Reset()
	resetState(state.filtersInstalled)
end

---------------------------------------------------------------------------------------------------------------------
-- Client events
---------------------------------------------------------------------------------------------------------------------

-- CHAT_MSG_CHANNEL_NOTICE(text, sender, language, channelString, target, flags, zoneChannelID, channelIndex, channelName)
function Channel:OnNotice(kind, _, _, channelString, _, _, _, _, channelName)
	if not (ours(channelName) or ours(channelString)) then return end
	if kind == "YOU_JOINED" then
		if state.waiting then check(state.waiting) end
		-- a join nobody asked for (the player typed /join AzGuildFinder): the channel is ours from now on
		if not state.ready and Channel:Id() then onJoined() end
	elseif kind == "YOU_LEFT" then
		if state.ready then
			state.ready, state.lastReason, state.reported = false, "left", "left"
			emit("CHANNEL_FAILED", "left")
		end
		if state.started then scheduleJoin(Channel.RETRY) end
	elseif Channel.FAILING_NOTICES[kind] and state.waiting then
		state.noticeReason = Channel.FAILING_NOTICES[kind]
		check(state.waiting)
	end
end

-- Loading screens and reloads: the chat windows may show the channel again.
function Channel:OnEnteringWorld()
	if state.ready and Channel:Id() then
		Channel:Hide()
		Channel:MoveToEnd()
	end
	Channel:Start()
end

function Channel:OnCombatEnded()
	if state.pendingMove then Channel:MoveToEnd() end
end

---------------------------------------------------------------------------------------------------------------------
-- /gf debug
---------------------------------------------------------------------------------------------------------------------
function Channel:DebugLines()
	local id = Channel:Id()
	local mode = state.ready and "ready" or (state.started and "not joined" or "not started")
	return {
		("Channel: %s (%s), %s, attempts %d, failures %d%s"):format(Channel.NAME, id and ("number " .. id) or "no number", mode,
			state.attempts, state.failures, state.lastReason and (", last problem: " .. state.lastReason) or ""),
		("  hidden from the chat windows %d time(s), moved %d step(s), lines filtered %d%s"):format(state.hid, state.moved,
			state.filtered, state.pendingMove and ", move waits for the end of combat" or ""),
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------------------------------------
if ns.Transport then
	ns.Transport.channelId = function() return Channel:Id() end
end
Channel:InstallFilters()

if ns.addon then
	ns.addon.Channel = Channel
	-- Own AceEvent object: the addon object keeps one handler per event, and Role already uses PLAYER_ENTERING_WORLD.
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if AceEvent then
		AceEvent:Embed(Channel)
		Channel:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", function(_, ...) Channel:OnNotice(...) end)
		Channel:RegisterEvent("PLAYER_ENTERING_WORLD", function() Channel:OnEnteringWorld() end)
		Channel:RegisterEvent("PLAYER_REGEN_ENABLED", function() Channel:OnCombatEnded() end)
	end
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Channel", function() return Channel:DebugLines() end) end
end
