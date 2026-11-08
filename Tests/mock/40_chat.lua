-- Mock client, part 5: addon messages and channels.
--
-- Imitates: C_ChatInfo.RegisterAddonMessagePrefix, IsAddonMessagePrefixRegistered, SendAddonMessage,
-- InChatMessagingLockdown, AreOutgoingAddonChatMessagesRestricted, SendChatMessage, C_BattleNet.SendGameData; the legacy channel globals JoinChannelByName,
-- GetChannelName, GetChannelList, LeaveChannelByName, ChatFrame_RemoveChannel / AddMessageEventFilter, SwapChatChannelsByChannelIndex;
-- the CHAT_MSG_ADDON and CHAT_MSG_CHANNEL_NOTICE events.
-- Dump files: ../WoW-Addons/docs/api/Guild-Social-Chat/C_ChatInfo.md. The channel globals are absent from the dump
-- (spec marks them "to verify"); the result codes of SendAddonMessage are the retail values (see 00_core.lua).
--
-- What the mock does NOT do: real throttling (the limits are what milestone M0 measures; use Mock.chat.forceResult or
-- Mock.chat.QueueResults to make the next sends fail) and delivery to other clients (the network simulator of M1.8
-- sits on top of Mock.chat.sent and Mock.chat.Receive).
--
-- Controls (all in Mock.chat, kept across Mock.Reload):
--   lockdown        InChatMessagingLockdown() result; while true, sends return AddOnMessageLockdown
--   restricted      AreOutgoingAddonChatMessagesRestricted() result; while true, sends return AddOnMessageLockdown
--   forceResult     every send returns this code (and is not recorded as sent) until set back to nil
--   QueueResults(...)  the next sends return these codes, one each
--   channelsRejectAddon  sends to a CHANNEL return InvalidChannel (temporary channels, ADR/SPEC-01 §1)
--   sent            list of {prefix, message, chatType, target, time, result} of accepted sends
local Mock, H = ...
local W = Mock.world
local Result = Enum.SendAddonMessageResult

W.chat = W.chat or {
	lockdown = false, restricted = false, forceResult = nil, queued = {}, channelsRejectAddon = false,
	sent = {}, attempts = {}, channels = {}, maxPrefixes = 64,
}
local chat = W.chat
Mock.chat = chat

-- Prefixes are registered per session (a reload forgets them), so they live outside the world.
local prefixes, prefixCount = {}, 0

local CHAT_TYPES = {
	PARTY = true, RAID = true, GUILD = true, OFFICER = true, WHISPER = true, CHANNEL = true, INSTANCE_CHAT = true,
	SAY = true, YELL = true, BATTLEGROUND = true,
}

C_ChatInfo = {}

function C_ChatInfo.RegisterAddonMessagePrefix(prefix)
	if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then return Enum.RegisterAddonMessagePrefixResult.InvalidPrefix end
	if prefixes[prefix] then return Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix end
	if prefixCount >= chat.maxPrefixes then return Enum.RegisterAddonMessagePrefixResult.MaxPrefixes end
	prefixes[prefix] = true
	prefixCount = prefixCount + 1
	return Enum.RegisterAddonMessagePrefixResult.Success
end

function C_ChatInfo.IsAddonMessagePrefixRegistered(prefix) return prefixes[prefix] == true end
function C_ChatInfo.InChatMessagingLockdown() return chat.lockdown end
function C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() return chat.restricted end

function chat.QueueResults(...)
	for i = 1, select("#", ...) do chat.queued[#chat.queued + 1] = (select(i, ...)) end
end

-- The client's checks, in a plausible order: argument shape, lockdown, then the destination.
local function sendResult(prefix, message, chatType, target)
	if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then return Result.InvalidPrefix end
	if type(message) ~= "string" or #prefix + #message > 255 then return Result.InvalidMessage end
	if not CHAT_TYPES[chatType] then return Result.InvalidChatType end
	if chat.lockdown or chat.restricted then return Result.AddOnMessageLockdown end
	if chatType == "CHANNEL" then
		if chat.channelsRejectAddon or not chat.channels[tonumber(target) or -1] then return Result.InvalidChannel end
	elseif chatType == "WHISPER" and (type(target) ~= "string" or target == "") then
		return Result.InvalidChatType
	elseif (chatType == "GUILD" or chatType == "OFFICER") and not IsInGuild() then
		return Result.GeneralError
	end
	return Result.Success
end

function C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)
	chatType = chatType and chatType:upper()
	local entry = { prefix = prefix, message = message, chatType = chatType, target = target, time = GetTime() }
	local result = table.remove(chat.queued, 1) or chat.forceResult or sendResult(prefix, message, chatType, target)
	entry.result = result
	chat.attempts[#chat.attempts + 1] = entry
	if result == Result.Success then
		chat.sent[#chat.sent + 1] = entry
	end
	return result
end
C_ChatInfo.SendAddonMessageLogged = C_ChatInfo.SendAddonMessage

-- Plain chat messages (ChatThrottleLib hooks this function); recorded in Mock.chat.messages, never delivered.
chat.messages = chat.messages or {}
function C_ChatInfo.SendChatMessage(message, chatType, languageID, target)
	chat.messages[#chat.messages + 1] = { message = message, chatType = chatType, languageID = languageID, target = target }
end

-- Battle.net game data (ChatThrottleLib hooks it for its traffic accounting); recorded, never delivered. Not used by the addon.
C_BattleNet = C_BattleNet or {}
chat.bnetSent = chat.bnetSent or {}
function C_BattleNet.SendGameData(gameAccountID, prefix, data)
	chat.bnetSent[#chat.bnetSent + 1] = { gameAccountID = gameAccountID, prefix = prefix, data = data }
	return Result.Success
end

-- Clears the record of sends (attempts and accepted ones).
function chat.ClearSent()
	for i = #chat.sent, 1, -1 do chat.sent[i] = nil end
	for i = #chat.attempts, 1, -1 do chat.attempts[i] = nil end
end

-- The accepted sends of one prefix, in order.
function chat.SentWithPrefix(prefix)
	local out = {}
	for _, e in ipairs(chat.sent) do if e.prefix == prefix then out[#out + 1] = e end end
	return out
end

-- Delivers an addon message from another player: fires CHAT_MSG_ADDON when the prefix is registered, as the client
-- does. `channelInfo` is {zoneChannelID, localID, name} for CHANNEL messages.
function chat.Receive(prefix, text, chatType, sender, target, channelInfo)
	if not prefixes[prefix] then return false end
	channelInfo = channelInfo or {}
	Mock.Fire("CHAT_MSG_ADDON", prefix, text, chatType, sender, target or "", channelInfo[1] or 0, channelInfo[2] or 0,
		channelInfo[3] or "", 0)
	return true
end

-- Channels, chat windows and message filters.
--
-- JoinChannelByName answers asynchronously in the client: the notice arrives on a later frame. A new channel takes
-- the lowest free number and is shown in the first chat window, as the client does. Controls (Mock.chat):
--   maxChannels        a join above this many channels does nothing (the client prints an error); default 10
--   joinIgnored        JoinChannelByName does nothing at all (no channel, no notice)
--   joinNotice         a notice code ("THROTTLED", "BANNED", "WRONG_PASSWORD", ...): the join is refused with that notice
--   AddChannel(name)   puts a channel in the list without a notice (General, Trade, ... before the addon starts)
--   windows[i]         { [lowercase channel name] = true } for the channels shown in ChatFrame<i>
--   Showing(name, i)   true while the channel is shown in window i (default: any window)
--   displayed          the channel lines that reached a window: { window =, event =, text =, channel = }
--   filters            event -> list of the functions given to ChatFrame_AddMessageEventFilter
local WINDOWS = 10
NUM_CHAT_WINDOWS = WINDOWS
for i = 2, WINDOWS do
	_G["ChatFrame" .. i] = CreateFrame("ScrollingMessageFrame", "ChatFrame" .. i, UIParent)
end
chat.windows = chat.windows or {}
chat.displayed = chat.displayed or {}
chat.maxChannels = chat.maxChannels or 10
chat.filters = {}   -- registered by addons at load time: rebuilt with the Lua state, like the client's

local function windowIndex(frame)
	for i = 1, WINDOWS do
		if _G["ChatFrame" .. i] == frame then return i end
	end
end

function chat.Showing(name, window)
	local key = tostring(name):lower()
	if window then return chat.windows[window] ~= nil and chat.windows[window][key] == true end
	for i = 1, WINDOWS do
		if chat.windows[i] and chat.windows[i][key] then return true end
	end
	return false
end

function ChatFrame_AddChannel(frame, name)
	local i = windowIndex(frame)
	if not i then return end
	chat.windows[i] = chat.windows[i] or {}
	chat.windows[i][tostring(name):lower()] = true
	return name
end

function ChatFrame_RemoveChannel(frame, name)
	local i = windowIndex(frame)
	if not i then error("ChatFrame_RemoveChannel: bad chat frame", 2) end
	if chat.windows[i] then chat.windows[i][tostring(name):lower()] = nil end
	return name
end

function ChatFrame_AddMessageEventFilter(event, fn)
	if type(event) ~= "string" or type(fn) ~= "function" then error("ChatFrame_AddMessageEventFilter: bad arguments", 2) end
	local list = chat.filters[event]
	if not list then list = {} chat.filters[event] = list end
	for _, f in ipairs(list) do if f == fn then return end end
	list[#list + 1] = fn
end

function ChatFrame_RemoveMessageEventFilter(event, fn)
	local list = chat.filters[event] or {}
	for i, f in ipairs(list) do
		if f == fn then table.remove(list, i) return end
	end
end

-- Delivers a channel chat event the way the client does: the chat windows handle it first (they registered for it before
-- any addon did): every window that has the channel runs the filters and shows the line unless one hides it. Then the
-- event fires for the addons. Arguments are those of the CHAT_MSG_CHANNEL* events: text, sender, language, channel
-- string ("1. Name"), target, flags, zone channel id, channel index, channel base name, ...
function chat.DeliverChannelEvent(event, ...)
	local args = { ... }
	local name = args[9]
	if type(name) == "string" then
		for i = 1, WINDOWS do
			if chat.Showing(name, i) then
				local hidden = false
				for _, filter in ipairs(chat.filters[event] or {}) do
					local ok, result = pcall(filter, _G["ChatFrame" .. i], event, ...)
					if not ok then Mock.safecall(error, result, 0) end
					if ok and result then hidden = true break end
				end
				if not hidden then
					chat.displayed[#chat.displayed + 1] = { window = i, event = event, text = args[1], channel = name }
				end
			end
		end
	end
	Mock.Fire(event, ...)
end

function chat.Notice(kind, id, name)
	chat.DeliverChannelEvent("CHAT_MSG_CHANNEL_NOTICE", kind, "", "", id .. ". " .. name, "", 0, 0, id, name, 0, 0)
end

function chat.ClearDisplayed()
	for i = #chat.displayed, 1, -1 do chat.displayed[i] = nil end
end

local function channelCount()
	local n = 0
	for _ in pairs(chat.channels) do n = n + 1 end
	return n
end

local function findChannel(name)
	for id, channel in pairs(chat.channels) do
		if channel.name:lower() == name:lower() then return id, channel end
	end
end

function chat.AddChannel(name)
	local id = findChannel(name)
	if id then return id end
	id = 1
	while chat.channels[id] do id = id + 1 end
	chat.channels[id] = { name = name }
	chat.windows[1] = chat.windows[1] or {}
	chat.windows[1][name:lower()] = true
	return id
end

function JoinChannelByName(name)
	if chat.joinIgnored or findChannel(name) then return end
	if chat.joinNotice then
		C_Timer.After(0, function() chat.Notice(chat.joinNotice, 0, name) end)
		return
	end
	if channelCount() >= chat.maxChannels then return end
	local id = chat.AddChannel(name)
	C_Timer.After(0, function() chat.Notice("YOU_JOINED", id, name) end)
end

function GetChannelName(nameOrId)
	for id, channel in pairs(chat.channels) do
		if id == nameOrId or (type(nameOrId) == "string" and channel.name:lower() == nameOrId:lower()) then
			return id, channel.name, 0
		end
	end
	return 0, nil, 0
end

-- id1, name1, disabled1, id2, name2, disabled2, ... in channel order.
function GetChannelList()
	local ids = {}
	for id in pairs(chat.channels) do ids[#ids + 1] = id end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		out[#out + 1], out[#out + 2], out[#out + 3] = id, chat.channels[id].name, false
	end
	return unpack(out)
end

function C_ChatInfo.SwapChatChannelsByChannelIndex(a, b)
	if type(a) ~= "number" or type(b) ~= "number" or not chat.channels[a] then error("SwapChatChannelsByChannelIndex: bad index", 2) end
	chat.channels[a], chat.channels[b] = chat.channels[b], chat.channels[a]
end

function LeaveChannelByName(name)
	local id = findChannel(name)
	if not id then return end
	chat.channels[id] = nil
	for i = 1, WINDOWS do
		if chat.windows[i] then chat.windows[i][name:lower()] = nil end
	end
	chat.Notice("YOU_LEFT", id, name)
end
