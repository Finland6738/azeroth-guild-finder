-- AzGF Probe, M0.3: channel messaging and throttling. S2 (exchange in the channel), S3 (level limit), S6 (throttle).
-- Lua 5.1. Every game API call goes through pcall. Never record player, guild or realm names: peers are "<peer N>".
-- Uses ONLY the test channel "AzGFProbe" (never "AzGuildFinder") and the test prefix "AzGFP".

local Probe = _G.AzGF_Probe
if not Probe then
    return
end

local call = Probe.Call
local out = Probe.Print

local CHANNEL = Probe:AssertTestChannel(Probe.TEST_CHANNEL) -- "AzGFProbe"
local PREFIX = "AzGFP" -- test prefix; the real addon uses "AzGF"
local BURST_BYTES = 200 -- size of every burst message (the real traffic is up to 255 bytes)
local BURST_MAX = 100 -- safety cap for /agfp burst
local LOG_CAP = 120 -- entries kept in each saved log
local JOIN_TRIES = 3

-- Fallback names for SendAddonMessageResult; the real table is read from Enum.SendAddonMessageResult at runtime.
local FALLBACK_CODES = { [0] = "Success", [3] = "AddonMessageThrottle", [7] = "InvalidChannel", [8] = "ChannelThrottle" }

local function db()
    AzGF_ProbeDB = AzGF_ProbeDB or {}
    local d = AzGF_ProbeDB
    d.channel = d.channel or {}
    local c = d.channel
    c.rx = c.rx or {} -- received addon messages (capped log)
    c.tx = c.tx or {} -- sent addon messages (capped log)
    c.log = c.log or {} -- join / notice / error events (capped log)
    c.byLevel = c.byLevel or {} -- S3: aggregated by level and account flags
    c.bursts = c.bursts or {} -- S6: sender side, one entry per burst
    c.burstsRx = c.burstsRx or {} -- S6: receiver side, one entry per burst seen
    return c
end

local function now()
    return date("%Y-%m-%d %H:%M:%S")
end

local function push(list, entry)
    list[#list + 1] = entry
    if #list > LOG_CAP then
        table.remove(list, 1)
    end
end

local function logEvent(text)
    push(db().log, { time = now(), text = tostring(text) })
end

-- Session-only state (never saved) ---------------------------------------------------------------------------------
local S = {
    sid = tostring(math.random(1000, 9999)), -- anonymous id of this client session, sent in the payload
    seq = 0,
    burstSeq = 0,
    peers = {}, -- sender name -> "<peer N>" (the names are NEVER saved or printed)
    peerCount = 0,
    selfNames = {},
    burstsRxSet = {}, -- burstId -> { [index] = true }
    lastPong = {}, -- peer label -> GetTime of the last auto-reply
    playedTotal = nil,
    joinTries = 0,
}
local frame = CreateFrame("Frame")

local function getTime()
    local ok, t = call(GetTime)
    return ok and t or 0
end

local function serverTime()
    local ok, t = call(GetServerTime)
    return ok and t or 0
end

-- SendAddonMessageResult names ---------------------------------------------------------------------------------------
local codeNames
local function resolveCodes()
    if codeNames then
        return codeNames
    end
    codeNames = {}
    local enum = Enum and Enum.SendAddonMessageResult
    if type(enum) == "table" then
        for name, value in pairs(enum) do
            if type(value) == "number" then
                codeNames[value] = name
            end
        end
    end
    for value, name in pairs(FALLBACK_CODES) do
        codeNames[value] = codeNames[value] or (name .. "(assumed)")
    end
    return codeNames
end

local function codeText(result)
    if result == nil then
        return "nil"
    end
    if type(result) == "boolean" then
        return tostring(result)
    end
    return tostring(result) .. ":" .. (resolveCodes()[result] or "unknown")
end

local function isThrottle(result)
    local name = type(result) == "number" and resolveCodes()[result] or ""
    return name:find("Throttle", 1, true) ~= nil
end

local function isSuccess(result)
    return result == 0 or result == true or result == "Success"
end

local function enumText()
    local enum = Enum and Enum.SendAddonMessageResult
    if type(enum) ~= "table" then
        return "Enum.SendAddonMessageResult=missing"
    end
    local parts = {}
    for name, value in pairs(enum) do
        parts[#parts + 1] = tostring(value) .. "=" .. tostring(name)
    end
    table.sort(parts)
    return "Enum.SendAddonMessageResult{" .. table.concat(parts, ",") .. "}"
end

-- Character and account info (S3) ------------------------------------------------------------------------------------
local function boolOf(fn)
    if type(fn) ~= "function" then
        return "missing"
    end
    local ok, v = call(fn)
    if not ok then
        return "error"
    end
    return tostring(v)
end

local function charInfo()
    local ok, level = call(UnitLevel, "player")
    return {
        level = ok and level or 0,
        trial = boolOf(IsTrialAccount),
        veteranTrial = boolOf(IsVeteranTrialAccount),
        restricted = boolOf(IsRestrictedAccount),
        played = S.playedTotal,
    }
end

local function levelKey(info)
    return string.format("L%s trial=%s vetTrial=%s restricted=%s", tostring(info.level), info.trial, info.veteranTrial,
        info.restricted)
end

local function levelBucket(info)
    local b = db().byLevel
    local key = levelKey(info)
    b[key] = b[key] or { level = info.level, trial = info.trial, veteranTrial = info.veteranTrial,
        restricted = info.restricted, sent = 0, ok = 0, codes = {}, joinOk = 0, joinFail = 0, rx = 0, firstTime = now() }
    local e = b[key]
    e.played = info.played or e.played -- total seconds played, when known
    e.lastTime = now()
    return e
end

-- Channel: join, hide, filter -------------------------------------------------------------------------------------------
local function channelId()
    if type(GetChannelName) ~= "function" then
        return nil
    end
    local ok, id = call(GetChannelName, CHANNEL)
    if ok and type(id) == "number" and id > 0 then
        return id
    end
    return nil
end

local function isOurs(s)
    return type(s) == "string" and s:lower():find(CHANNEL:lower(), 1, true) ~= nil
end

local function hideFromChat()
    if type(ChatFrame_RemoveChannel) ~= "function" then
        return "ChatFrame_RemoveChannel missing"
    end
    local removed = 0
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and call(ChatFrame_RemoveChannel, cf, CHANNEL) then
            removed = removed + 1
        end
    end
    return "removed from " .. removed .. " chat frames"
end

local function moveToEnd()
    local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    local id = channelId()
    if not (id and swap and type(GetChannelList) == "function") then
        return "move to end not possible (" .. (swap and "no id/GetChannelList" or "SwapChatChannelsByChannelIndex missing") .. ")"
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return "move to end skipped (combat)"
    end
    local last = 0
    for _, v in ipairs({ GetChannelList() }) do
        if type(v) == "number" and v > last then
            last = v
        end
    end
    for i = id, last - 1 do
        if not call(swap, i, i + 1) then
            break
        end
    end
    return "moved from index " .. id .. " (last=" .. last .. ")"
end

-- Hide the join/leave notices (and the channel's own chat lines) of the test channel.
local filterInstalled = false
local function installFilters()
    if filterInstalled or type(ChatFrame_AddMessageEventFilter) ~= "function" then
        return
    end
    local function filter(_, _, _, _, _, chanString, _, _, _, _, chanName)
        return isOurs(chanName) or isOurs(chanString)
    end
    for _, ev in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL" }) do
        call(ChatFrame_AddMessageEventFilter, ev, filter)
    end
    filterInstalled = true
end

local function afterJoin()
    local id = channelId()
    local info = charInfo()
    local bucket = levelBucket(info)
    if id then
        bucket.joinOk = bucket.joinOk + 1
        local hidden = hideFromChat()
        local moved = moveToEnd()
        logEvent(string.format("joined %s as channel index %d; %s; %s; %s", CHANNEL, id, hidden, moved, levelKey(info)))
        out(string.format("joined the test channel (index %d). %s. Now /agfp ping", id, hidden))
        return true
    end
    return false
end

local function tryJoin()
    if type(JoinChannelByName) ~= "function" then
        logEvent("JoinChannelByName missing")
        out("JoinChannelByName is missing in this client")
        return
    end
    installFilters()
    Probe:AssertTestChannel(CHANNEL)
    if channelId() then
        afterJoin()
        return
    end
    S.joinTries = S.joinTries + 1
    local ok, err = call(JoinChannelByName, CHANNEL)
    logEvent(string.format("JoinChannelByName attempt %d: %s", S.joinTries, ok and "called" or ("error " .. tostring(err))))
    if not (C_Timer and C_Timer.After) then
        return
    end
    -- the join takes a moment: look again, retry a few times
    C_Timer.After(3, function()
        if afterJoin() then
            S.joinTries = 0
        elseif S.joinTries < JOIN_TRIES then
            out("join not confirmed yet, retrying (" .. S.joinTries .. "/" .. JOIN_TRIES .. ")")
            tryJoin()
        else
            local info = charInfo()
            levelBucket(info).joinFail = levelBucket(info).joinFail + 1
            logEvent("join FAILED after " .. S.joinTries .. " attempts; " .. levelKey(info))
            out("could not join the test channel after " .. S.joinTries .. " attempts (see /agfp channel and the notice log)")
            S.joinTries = 0
        end
    end)
end

local function leave()
    db().autojoin = false
    local id = channelId()
    if id and type(LeaveChannelByName) == "function" then
        call(LeaveChannelByName, CHANNEL)
        logEvent("LeaveChannelByName called")
        out("left the test channel (it may stay in the game's channel list: that is itself a result, note it)")
    else
        out("not in the test channel")
    end
end

-- Peers and payloads -------------------------------------------------------------------------------------------------------
local function refreshSelfNames()
    S.selfNames = {}
    if type(UnitName) == "function" then
        local ok, name = call(UnitName, "player")
        if ok and name then
            S.selfNames[name] = true
        end
    end
    if type(GetUnitName) == "function" then
        local ok, name = call(GetUnitName, "player", true)
        if ok and name then
            S.selfNames[name] = true
        end
    end
end

--- Sender name -> "<self>" or "<peer N>" (stable during the session, never saved).
local function peerLabel(sender)
    if type(sender) ~= "string" then
        return "<unknown>"
    end
    if S.selfNames[sender] then
        return "<self>"
    end
    if not S.peers[sender] then
        S.peerCount = S.peerCount + 1
        S.peers[sender] = "<peer " .. S.peerCount .. ">"
    end
    return S.peers[sender]
end

local function pad(text, bytes)
    if #text >= bytes then
        return text:sub(1, bytes)
    end
    return text .. string.rep("x", bytes - #text)
end

-- Sending ------------------------------------------------------------------------------------------------------------------
local function lockdownText()
    local parts = {}
    for _, pair in ipairs({ { "lockdown", "InChatMessagingLockdown" }, { "outgoingRestricted", "AreOutgoingAddonChatMessagesRestricted" } }) do
        local fn = C_ChatInfo and C_ChatInfo[pair[2]]
        if type(fn) == "function" then
            local ok, v = call(fn)
            parts[#parts + 1] = pair[1] .. "=" .. (ok and tostring(v) or "error")
        end
    end
    return table.concat(parts, ",")
end

--- Sends one test message to the test channel and records the SendAddonMessageResult.
-- Returns ok (API call did not raise), result code, id (nil when not in the channel).
local function sendToChannel(kind, text)
    local id = channelId()
    if not id then
        return false, nil, nil
    end
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    local info = charInfo()
    local bucket = levelBucket(info)
    local ok, result = call(send, PREFIX, text, "CHANNEL", id)
    local code = ok and codeText(result) or ("error:" .. tostring(result))
    bucket.sent = bucket.sent + 1
    if ok and isSuccess(result) then
        bucket.ok = bucket.ok + 1
    end
    bucket.codes[code] = (bucket.codes[code] or 0) + 1
    push(db().tx, { time = now(), kind = kind, len = #text, result = code, level = info.level, id = id,
        lockdown = lockdownText() })
    return ok, result, id, code
end

local function registerPrefix()
    local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
    if type(reg) ~= "function" then
        return "RegisterAddonMessagePrefix missing"
    end
    local ok, r = call(reg, PREFIX)
    return ok and ("RegisterAddonMessagePrefix(" .. PREFIX .. ")=" .. tostring(r)) or ("error " .. tostring(r))
end

local function ping()
    S.seq = S.seq + 1
    -- P|<sid>|<seq>|<serverTime>|<getTime>
    local text = string.format("P|%s|%d|%d|%.3f", S.sid, S.seq, serverTime(), getTime())
    local ok, result, id, code = sendToChannel("PING", text)
    if not id then
        out("not in the test channel: run /agfp join first")
        return
    end
    out(string.format("ping #%d sent, result %s", S.seq, code or "?"))
    if ok and isSuccess(result) then
        return
    end
    if result == 7 then
        out("result 7 (InvalidChannel): the server refused the message. Note your level; see S3 in the README")
    end
end

-- Receiving ---------------------------------------------------------------------------------------------------------------
local function missingList(set, upto)
    local missing, n = {}, 0
    for i = 1, upto do
        if not set[i] then
            n = n + 1
            if n <= 30 then
                missing[#missing + 1] = i
            end
        end
    end
    local text = table.concat(missing, ",")
    if n > 30 then
        text = text .. ",...(" .. n .. " total)"
    end
    return text
end

local function onBurstMessage(peer, fields, len)
    -- B|<sid>|<burstId>|<i>|<n>|<gap>|<serverTime>|<pad>
    local sid, burstId, i, n, gap, sentAt = fields[2], fields[3], tonumber(fields[4]), tonumber(fields[5]),
        fields[6], tonumber(fields[7])
    if not (burstId and i and n) then
        return
    end
    local key = (sid or "?") .. ":" .. burstId
    local set = S.burstsRxSet[key]
    local entry
    if not set then
        set = {}
        S.burstsRxSet[key] = set
        entry = { key = key, peer = peer, n = n, gap = gap, first = getTime(), firstTime = now(), got = 0, byMe = (sid == S.sid) }
        db().burstsRx[key] = entry
    else
        entry = db().burstsRx[key]
        if not entry then -- the saved entry was cleared while the burst was running
            entry = { key = key, peer = peer, n = n, gap = gap, first = getTime(), firstTime = now(), got = 0 }
            db().burstsRx[key] = entry
        end
    end
    if not set[i] then
        set[i] = true
        entry.got = entry.got + 1
    end
    entry.last = i
    entry.lastTime = now()
    entry.spanSeconds = math.floor((getTime() - (entry.first or getTime())) * 100) / 100
    entry.len = len
    entry.ageSeconds = sentAt and (serverTime() - sentAt) or nil
    entry.missing = missingList(set, math.min(n, math.max(entry.last or 0, i)))
    entry.complete = entry.got >= n
end

local function onAddonMessage(prefix, text, distribution, sender, _, _, localId, channelName)
    if prefix ~= PREFIX or type(text) ~= "string" then
        return
    end
    local peer = peerLabel(sender)
    local info = charInfo()
    local bucket = levelBucket(info)
    local mine = channelId()
    local inChannel = isOurs(channelName) or (mine ~= nil and localId == mine)
    local fields = {}
    for part in (text .. "|"):gmatch("([^|]*)|") do
        fields[#fields + 1] = part
    end
    local kind = fields[1]
    local entry = { time = now(), kind = kind or "?", peer = peer, dist = tostring(distribution), len = #text,
        channel = inChannel and "AzGFProbe" or "other", level = info.level }
    if peer ~= "<self>" then
        bucket.rx = bucket.rx + 1
    end

    if kind == "P" then
        -- P|<sid>|<seq>|<serverTime>|<getTime>
        entry.sid, entry.seq = fields[2], tonumber(fields[3])
        local sentAt = tonumber(fields[4])
        entry.oneWaySeconds = sentAt and (serverTime() - sentAt) or nil -- 1 s resolution, server clock
        if db().pong and peer ~= "<self>" and inChannel then
            local t = getTime()
            if not S.lastPong[peer] or t - S.lastPong[peer] >= 1 then
                S.lastPong[peer] = t
                -- O|<sid>|<origSid>|<seq>|<origGetTime>|<serverTime>
                local reply = string.format("O|%s|%s|%s|%s|%d", S.sid, fields[2] or "?", fields[3] or "?",
                    fields[5] or "0", serverTime())
                local ok, result, id, code = sendToChannel("PONG", reply)
                entry.pongResult = id and code or "not in channel"
            end
        end
    elseif kind == "O" then
        -- O|<sid>|<origSid>|<seq>|<origGetTime>|<serverTime>
        entry.sid, entry.origSid, entry.seq = fields[2], fields[3], tonumber(fields[4])
        if fields[3] == S.sid then
            local origT = tonumber(fields[5])
            if origT then
                local rtt = (getTime() - origT) * 1000
                entry.rttMs = math.floor(rtt + 0.5)
                out(string.format("pong for ping #%s from %s: round trip %d ms", tostring(entry.seq), peer, entry.rttMs))
            end
        end
    elseif kind == "B" then
        entry.sid = fields[2]
        onBurstMessage(peer, fields, #text)
        -- bursts are summarised in burstsRx, not logged one by one
        return
    end
    push(db().rx, entry)
end

-- Burst (S6) --------------------------------------------------------------------------------------------------------------
local burst -- the running burst, if any

local function finishBurst(reason)
    if not burst then
        return
    end
    local b = burst
    burst = nil
    local gaps = b.gaps
    local sum, minG, maxG = 0, nil, nil
    for _, g in ipairs(gaps) do
        sum = sum + g
        minG = (not minG or g < minG) and g or minG
        maxG = (not maxG or g > maxG) and g or maxG
    end
    local entry = {
        id = b.id, time = b.startTime, n = b.n, gap = b.gap, sent = b.sent, ok = b.ok, bytes = BURST_BYTES,
        throttled = b.throttled, codes = b.codes, firstFailIndex = b.firstFail, firstFailCode = b.firstFailCode,
        actualGapAvg = (#gaps > 0) and (math.floor(sum / #gaps * 1000) / 1000) or nil, actualGapMin = minG,
        actualGapMax = maxG, level = b.level, ended = reason,
    }
    entry.actualGapMin = minG and (math.floor(minG * 1000) / 1000)
    entry.actualGapMax = maxG and (math.floor(maxG * 1000) / 1000)
    push(db().bursts, entry)
    out(string.format("burst %s %s: %d/%d sent OK, throttled %d, first failure at %s. Tell the receiver to run /agfp channel",
        b.id, reason, b.ok, b.sent, b.throttled, b.firstFail and (tostring(b.firstFail) .. " (" .. tostring(b.firstFailCode) .. ")") or "none"))
end

local function burstStep()
    if not burst then
        return
    end
    local b = burst
    local t = getTime()
    if b.lastT then
        b.gaps[#b.gaps + 1] = t - b.lastT
    end
    b.lastT = t
    b.index = b.index + 1
    -- B|<sid>|<burstId>|<i>|<n>|<gap>|<serverTime>|<pad>
    local head = string.format("B|%s|%s|%d|%d|%s|%d|", S.sid, b.id, b.index, b.n, tostring(b.gap), serverTime())
    local ok, result, id, code = sendToChannel("BURST", pad(head, BURST_BYTES))
    b.sent = b.sent + 1
    b.codes[code or "not in channel"] = (b.codes[code or "not in channel"] or 0) + 1
    if ok and isSuccess(result) then
        b.ok = b.ok + 1
    else
        if not b.firstFail then
            b.firstFail, b.firstFailCode = b.index, code or "not in channel"
        end
        if ok and isThrottle(result) then
            b.throttled = b.throttled + 1
        end
    end
    if not id then
        finishBurst("aborted (left the channel)")
    elseif b.index >= b.n then
        finishBurst("finished")
    elseif C_Timer and C_Timer.After then
        C_Timer.After(b.gap, burstStep)
    else
        finishBurst("aborted (no C_Timer)")
    end
end

local function startBurst(n, gap)
    if burst then
        out("a burst is already running (/agfp burst stop)")
        return
    end
    if not channelId() then
        out("not in the test channel: run /agfp join first")
        return
    end
    n = math.floor(tonumber(n) or 0)
    gap = tonumber(gap) or 0
    if n < 1 or gap <= 0 then
        out("usage: /agfp burst <n> <gapSeconds>, for example /agfp burst 20 1.2")
        return
    end
    if n > BURST_MAX then
        n = BURST_MAX
        out("n capped at " .. BURST_MAX)
    end
    S.burstSeq = S.burstSeq + 1
    burst = { id = tostring(S.burstSeq), n = n, gap = gap, index = 0, sent = 0, ok = 0, throttled = 0, codes = {},
        gaps = {}, startTime = now(), level = charInfo().level }
    out(string.format("burst %s: %d messages of %d bytes, gap %s s (about %.0f s). The other client should be in the channel",
        burst.id, n, BURST_BYTES, tostring(gap), n * gap))
    burstStep()
end

-- Reports ------------------------------------------------------------------------------------------------------------------
local function summaryLines()
    local c = db()
    local lines = {}
    local function add(s)
        lines[#lines + 1] = s
    end
    add(string.format("channel %s | prefix %s | session %s | joined index %s | pong auto-reply %s | autojoin %s", CHANNEL, PREFIX, S.sid,
        tostring(channelId()), tostring(c.pong and true or false), tostring(c.autojoin and true or false)))
    add("prefix: " .. registerPrefix())
    add(enumText())
    local info = charInfo()
    add(string.format("this character: level %s, IsTrialAccount=%s, IsVeteranTrialAccount=%s, IsRestrictedAccount=%s, played=%s s",
        tostring(info.level), info.trial, info.veteranTrial, info.restricted, tostring(info.played)))
    return lines
end

function Probe:ChannelLines()
    local c = db()
    local lines = {}
    local function add(s)
        lines[#lines + 1] = s
    end
    for _, l in ipairs(summaryLines()) do
        add("S2 " .. l)
    end
    local keys = {}
    for k in pairs(c.byLevel) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local e = c.byLevel[k]
        local codes = {}
        for code, count in pairs(e.codes) do
            codes[#codes + 1] = code .. "x" .. count
        end
        table.sort(codes)
        add(string.format("S3 %s | join ok=%d fail=%d | sent=%d ok=%d codes[%s] | received from others=%d | played=%s s | %s .. %s",
            k, e.joinOk, e.joinFail, e.sent, e.ok, table.concat(codes, " "), e.rx, tostring(e.played), tostring(e.firstTime),
            tostring(e.lastTime)))
    end
    for i, b in ipairs(c.bursts) do
        local codes = {}
        for code, count in pairs(b.codes) do
            codes[#codes + 1] = code .. "x" .. count
        end
        table.sort(codes)
        add(string.format("S6 tx %d | burst %s level %s | n=%d gap=%s bytes=%d | sent=%d ok=%d throttled=%d | firstFail=%s(%s) | actual gap min/avg/max %s/%s/%s | codes[%s] | %s | %s",
            i, tostring(b.id), tostring(b.level), b.n, tostring(b.gap), b.bytes, b.sent, b.ok, b.throttled, tostring(b.firstFailIndex),
            tostring(b.firstFailCode), tostring(b.actualGapMin), tostring(b.actualGapAvg), tostring(b.actualGapMax),
            table.concat(codes, " "), tostring(b.ended), tostring(b.time)))
    end
    local rxKeys = {}
    for k in pairs(c.burstsRx) do
        rxKeys[#rxKeys + 1] = k
    end
    table.sort(rxKeys)
    for _, k in ipairs(rxKeys) do
        local e = c.burstsRx[k]
        add(string.format("S6 rx | burst %s from %s%s | got %d/%d (complete=%s) | missing[%s] | span %s s | gap announced %s | last age %s s | %s",
            k, tostring(e.peer), e.byMe and " (own echo)" or "", e.got, e.n, tostring(e.complete), tostring(e.missing or ""),
            tostring(e.spanSeconds), tostring(e.gap), tostring(e.ageSeconds), tostring(e.firstTime)))
    end
    for i, e in ipairs(c.tx) do
        add(string.format("S2 tx %d | %s | %s | len %d | result %s | level %s | channel index %s | %s", i, e.time, e.kind, e.len,
            e.result, tostring(e.level), tostring(e.id), tostring(e.lockdown)))
    end
    for i, e in ipairs(c.rx) do
        add(string.format("S2 rx %d | %s | %s | from %s sid=%s | via %s in %s | len %d | one-way ~%s s (server clocks) | rtt %s ms | level %s%s",
            i, e.time, e.kind, e.peer, tostring(e.sid), tostring(e.dist), tostring(e.channel), e.len, tostring(e.oneWaySeconds),
            tostring(e.rttMs), tostring(e.level), e.pongResult and (" | pong sent: " .. e.pongResult) or ""))
    end
    for i, e in ipairs(c.log) do
        add(string.format("S2 log %d | %s | %s", i, e.time, e.text))
    end
    return lines
end
table.insert(Probe.exportHooks, function(self)
    return self:ChannelLines()
end)

-- Checks ------------------------------------------------------------------------------------------------------------------
local function count(list, pred)
    local n = 0
    for _, e in ipairs(list) do
        if pred(e) then
            n = n + 1
        end
    end
    return n
end

Probe:Register("S2", "Join the test channel and exchange addon messages between two clients (/agfp join, ping, pong)",
    function()
        local c = db()
        local peersSeen = {}
        for _, e in ipairs(c.rx) do
            if e.peer ~= "<self>" then
                peersSeen[e.peer] = true
            end
        end
        local nPeers = 0
        for _ in pairs(peersSeen) do
            nPeers = nPeers + 1
        end
        local sentOk = count(c.tx, function(e) return e.result == "0:Success" or e.result:find("^0:") ~= nil end)
        local fromPeers = count(c.rx, function(e) return e.peer ~= "<self>" end)
        local echoes = count(c.rx, function(e) return e.peer == "<self>" end)
        local text = string.format("joined=%s; sends logged=%d (result 0: %d); received from other peers=%d (%d distinct this session), own echoes=%d; %s; %s",
            tostring(channelId()), #c.tx, sentOk, fromPeers, nPeers, echoes, enumText(), registerPrefix())
        if fromPeers > 0 and sentOk > 0 then
            return "pass", text
        elseif not channelId() then
            return "info", text .. "; not in the channel (run /agfp join)"
        end
        return "info", text .. "; no message from another client yet"
    end)

Probe:Register("S3", "Lowest level (or play time) that can send in the channel (repeat /agfp ping at levels 1, 5, 10, 20)",
    function()
        local c = db()
        local parts = {}
        local keys = {}
        for k in pairs(c.byLevel) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local e = c.byLevel[k]
            local codes = {}
            for code, n in pairs(e.codes) do
                codes[#codes + 1] = code .. "x" .. n
            end
            table.sort(codes)
            parts[#parts + 1] = string.format("%s: join %d/%d ok, sent %d ok %d [%s], rx %d", k, e.joinOk, e.joinOk + e.joinFail,
                e.sent, e.ok, table.concat(codes, " "), e.rx)
        end
        if #parts == 0 then
            return "info", "no data yet: /agfp join then /agfp ping on characters of level 1, 5, 10, 20"
        end
        return "info", table.concat(parts, " || ")
    end)

Probe:Register("S6", "Real channel throttle: /agfp burst <n> <gapSeconds> (try gaps 2.0, 1.2, 0.8, 0.5, 0.25)", function()
    local c = db()
    local parts = {}
    for _, b in ipairs(c.bursts) do
        parts[#parts + 1] = string.format("tx gap %s: %d/%d ok, throttled %d, firstFail %s", tostring(b.gap), b.ok, b.n, b.throttled,
            tostring(b.firstFailIndex))
    end
    for k, e in pairs(c.burstsRx) do
        if not e.byMe then
            parts[#parts + 1] = string.format("rx %s gap %s: got %d/%d", k, tostring(e.gap), e.got, e.n)
        end
    end
    if #parts == 0 then
        return "info", "no burst yet: /agfp join, then /agfp burst 20 1.2 (sender) and /agfp channel (receiver)"
    end
    return "info", table.concat(parts, " || ")
end)

-- Slash commands -----------------------------------------------------------------------------------------------------------
Probe.commands.join = function()
    db().autojoin = true -- rejoin after the next login, so repeating the test on other characters is quicker
    S.joinTries = 0
    tryJoin()
end
Probe.commands.leave = leave
Probe.commands.ping = ping
Probe.commands.pong = function(arg)
    local c = db()
    arg = (arg or ""):lower()
    if arg == "on" then
        c.pong = true
    elseif arg == "off" then
        c.pong = false
    else
        c.pong = not c.pong
    end
    out("pong auto-reply " .. (c.pong and "ON: this client answers every ping from another client" or "OFF"))
end
Probe.commands.burst = function(arg, rest)
    if arg:lower() == "stop" then
        if burst then
            finishBurst("stopped by the user")
        else
            out("no burst running")
        end
        return
    end
    startBurst(arg, rest)
end
Probe.commands.channel = function()
    for _, l in ipairs(summaryLines()) do
        out(l)
    end
    local c = db()
    out(string.format("logged: %d sent, %d received, %d bursts sent, %d bursts seen", #c.tx, #c.rx, #c.bursts,
        (function() local n = 0 for _ in pairs(c.burstsRx) do n = n + 1 end return n end)()))
    for _, e in pairs(c.burstsRx) do
        out(string.format("burst %s from %s: got %d/%d, missing [%s]", e.key, e.peer, e.got, e.n, tostring(e.missing or "")))
    end
end

-- Events -------------------------------------------------------------------------------------------------------------------
local function register(ev)
    call(frame.RegisterEvent, frame, ev)
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
        -- text (YOU_JOINED, YOU_LEFT, ...), name, language, channel string, name2, flags, zoneChannelID, index, base name
        local text, _, _, chanString, _, _, _, index, baseName = ...
        if isOurs(chanString) or isOurs(baseName) then
            logEvent(string.format("notice %s (index %s)", tostring(text), tostring(index)))
        end
    elseif event == "TIME_PLAYED_MSG" then
        S.playedTotal = ...
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not S.entered then
            S.entered = true
            refreshSelfNames()
            registerPrefix()
            installFilters() -- hide the notices of the test channel from now on
            if db().autojoin and C_Timer and C_Timer.After then
                C_Timer.After(5, tryJoin)
            end
            -- total play time (S3: "level or play time"): the answer arrives in TIME_PLAYED_MSG and is also printed in chat
            if type(RequestTimePlayed) == "function" then
                call(RequestTimePlayed)
            end
        end
    end
end)
register("CHAT_MSG_ADDON")
register("CHAT_MSG_CHANNEL_NOTICE")
register("TIME_PLAYED_MSG")
register("PLAYER_ENTERING_WORLD")
refreshSelfNames()
registerPrefix()
