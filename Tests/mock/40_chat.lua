-- Mock client, part 5: addon messages and channels.
--
-- Imitates: C_ChatInfo.RegisterAddonMessagePrefix, IsAddonMessagePrefixRegistered, SendAddonMessage,
-- InChatMessagingLockdown, AreOutgoingAddonChatMessagesRestricted, SendChatMessage, C_BattleNet.SendGameData; the legacy channel globals JoinChannelByName,
-- GetChannelName, LeaveChannelByName; the CHAT_MSG_ADDON event.
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

-- Channels. JoinChannelByName answers asynchronously in the client: the notice arrives on a later frame.
function JoinChannelByName(name)
	for id, channel in pairs(chat.channels) do
		if channel.name:lower() == name:lower() then return end
	end
	local id = 1
	while chat.channels[id] do id = id + 1 end
	chat.channels[id] = { name = name }
	C_Timer.After(0, function()
		Mock.Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", id .. ". " .. name, "", 0, 0, id, name, 0, 0)
	end)
end

function GetChannelName(nameOrId)
	for id, channel in pairs(chat.channels) do
		if id == nameOrId or (type(nameOrId) == "string" and channel.name:lower() == nameOrId:lower()) then
			return id, channel.name, 0
		end
	end
	return 0, nil, 0
end

function LeaveChannelByName(name)
	local id = GetChannelName(name)
	if id ~= 0 then chat.channels[id] = nil end
end
