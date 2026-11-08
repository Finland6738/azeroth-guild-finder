-- AzGF Probe, M0.4: addon whisper (S4) and guild distributions OFFICER / GUILD (S5).
-- Lua 5.1. Every game API call goes through pcall. Never record player, guild or realm names: peers are "<peer N>" and the
-- whisper target is only ever stored as "<target>". Uses the test prefix "AzGFP" of Checks_Channel.lua; never the real channel.

local Probe = _G.AzGF_Probe
if not Probe or not Probe.Channel then
    return
end

local C = Probe.Channel
local call = Probe.Call
local out = Probe.Print
local PREFIX = C.PREFIX

-- message kinds of this file (the channel handler ignores them):
--   W|<sid>|<seq>|<serverTime>|<getTime>                         whisper ping
--   WO|<sid>|<origSid>|<seq>|<origGetTime>|<serverTime>|<lvl>|<trial>   whisper reply (receiver level and trial status)
--   D|<sid>|<seq>|<distribution>|<serverTime>|<role>|<rank>      OFFICER / GUILD test message
Probe.foreignKinds.W = true
Probe.foreignKinds.WO = true
Probe.foreignKinds.D = true

local function db()
    AzGF_ProbeDB = AzGF_ProbeDB or {}
    local d = AzGF_ProbeDB.whisper
    if not d then
        d = {}
        AzGF_ProbeDB.whisper = d
    end
    d.tx = d.tx or {} -- sent whispers (capped)
    d.rx = d.rx or {} -- received whispers and replies (capped)
    d.guildTx = d.guildTx or {} -- sent OFFICER / GUILD messages (capped)
    d.guildRx = d.guildRx or {} -- received OFFICER / GUILD messages (capped)
    return d
end

local S = { seq = 0, dseq = 0, pending = {} } -- pending: seq -> GetTime of the whisper

local function sendFn()
    return (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
end

local function parse(text)
    local fields = {}
    for part in (text .. "|"):gmatch("([^|]*)|") do
        fields[#fields + 1] = part
    end
    return fields
end

-- Guild role of this character: no names, only flags and the rank index (0 = guild master).
local function guildRole()
    local inGuild = call(IsInGuild) and select(2, call(IsInGuild)) or false
    local ok, leader = call(IsGuildLeader)
    local isLeader = ok and leader == true
    local officerFn = C_GuildInfo and C_GuildInfo.IsGuildOfficer
    local ok2, officer = call(officerFn)
    local isOfficer = ok2 and officer == true
    local rank = "?"
    if type(GetGuildInfo) == "function" then
        local ok3, _, _, idx = pcall(function()
            return GetGuildInfo("player")
        end)
        if ok3 and type(idx) == "number" then
            rank = tostring(idx)
        end
    end
    local code = "M"
    if not inGuild then
        code = "-"
    elseif isLeader then
        code = "L"
    elseif isOfficer then
        code = "O"
    end
    return { inGuild = inGuild and true or false, leader = isLeader, officer = isOfficer, rank = rank, code = code,
        text = string.format("inGuild=%s IsGuildLeader=%s IsGuildOfficer=%s rankIndex=%s role=%s", tostring(inGuild and true or false),
            ok and tostring(leader) or "n/a", ok2 and tostring(officer) or "n/a", rank,
            code == "L" and "leader" or code == "O" and "officer" or code == "M" and "plain member" or "no guild") }
end

local function roleName(code)
    return code == "L" and "leader" or code == "O" and "officer" or code == "M" and "member" or code == "-" and "no guild" or "?"
end

local function levelText()
    local info = C.charInfo()
    return string.format("L%s trial=%s vetTrial=%s restricted=%s", tostring(info.level), info.trial, info.veteranTrial,
        info.restricted), info
end

local function pongOn()
    local c = AzGF_ProbeDB and AzGF_ProbeDB.channel
    return c and c.pong and true or false
end

-- S4: whisper -----------------------------------------------------------------------------------------------------------------
local function whisper(target)
    if not target or target == "" then
        out("usage: /agfp whisper <character name> (the name is never stored: it is logged as <target>)")
        return
    end
    S.seq = S.seq + 1
    local seq = S.seq
    local text = string.format("W|%s|%d|%d|%.3f", C.sid(), seq, C.serverTime(), C.getTime())
    local ok, result = call(sendFn(), PREFIX, text, "WHISPER", target)
    local code = ok and C.codeText(result) or ("error:" .. tostring(result))
    local lv = levelText()
    S.pending[seq] = C.getTime()
    C.push(db().tx, { time = C.now(), kind = "WHISPER", target = "<target>", seq = seq, result = code, level = lv,
        lockdown = C.lockdownText() })
    out(string.format("whisper #%d to <target> sent, result %s. %s", seq, code,
        pongOn() and "" or "(the receiver needs /agfp pong on to answer)"))
end

local function onWhisper(fields, sender, text)
    local peer = C.peerLabel(sender)
    local lv, info = levelText()
    local entry = { time = C.now(), kind = fields[1], dist = "WHISPER", peer = peer, len = #text, level = info.level, receiver = lv }
    if fields[1] == "W" then
        -- whisper ping: auto-reply when /agfp pong is ON
        entry.sid, entry.seq = fields[2], tonumber(fields[3])
        local sentAt = tonumber(fields[4])
        entry.oneWaySeconds = sentAt and (C.serverTime() - sentAt) or nil
        if pongOn() and peer ~= "<self>" then
            local reply = string.format("WO|%s|%s|%s|%s|%d|%s|%s", C.sid(), fields[2] or "?", fields[3] or "?",
                fields[5] or "0", C.serverTime(), tostring(info.level), info.trial)
            local ok, result = call(sendFn(), PREFIX, reply, "WHISPER", sender)
            entry.replyResult = ok and C.codeText(result) or ("error:" .. tostring(result))
        else
            entry.replyResult = "not sent (pong off)"
        end
    elseif fields[1] == "WO" then
        -- reply: WO|<sid>|<origSid>|<seq>|<origGetTime>|<serverTime>|<lvl>|<trial>
        entry.sid, entry.origSid, entry.seq = fields[2], fields[3], tonumber(fields[4])
        entry.peerLevel, entry.peerTrial = fields[7], fields[8]
        if fields[3] == C.sid() then
            local origT = tonumber(fields[5])
            if origT then
                entry.rttMs = math.floor((C.getTime() - origT) * 1000 + 0.5)
                out(string.format("whisper reply #%s from %s: round trip %d ms (receiver level %s, trial %s)", tostring(entry.seq), peer,
                    entry.rttMs, tostring(fields[7]), tostring(fields[8])))
            end
            if entry.seq then
                S.pending[entry.seq] = nil
            end
        end
    end
    C.push(db().rx, entry)
end

-- S5: OFFICER / GUILD -----------------------------------------------------------------------------------------------------------------
local function guildSend(dist)
    S.dseq = S.dseq + 1
    local role = guildRole()
    -- D|<sid>|<seq>|<distribution>|<serverTime>|<sender role L/O/M/->|<sender rank index>
    local text = string.format("D|%s|%d|%s|%d|%s|%s", C.sid(), S.dseq, dist, C.serverTime(), role.code, role.rank)
    local ok, result = call(sendFn(), PREFIX, text, dist)
    local code = ok and C.codeText(result) or ("error:" .. tostring(result))
    local lv = levelText()
    C.push(db().guildTx, { time = C.now(), dist = dist, seq = S.dseq, result = code, role = role.text, level = lv })
    out(string.format("%s message #%d sent, result %s. You are: %s", dist, S.dseq, code, role.text))
    if not role.inGuild then
        out("this character is not in a guild: the send is expected to fail, and the result is still recorded")
    end
end

local function onGuildMessage(fields, distribution, sender, text)
    local peer = C.peerLabel(sender)
    local role = guildRole()
    local entry = { time = C.now(), dist = tostring(distribution), requested = fields[4], peer = peer, seq = tonumber(fields[3]),
        senderRole = roleName(fields[6]), senderRank = fields[7], receiverRole = roleName(role.code), receiverRank = role.rank,
        receiverText = role.text, len = #text }
    local sentAt = tonumber(fields[5])
    entry.oneWaySeconds = sentAt and (C.serverTime() - sentAt) or nil
    C.push(db().guildRx, entry)
    if peer ~= "<self>" then
        out(string.format("%s message #%s from %s (%s) arrived on %s; you are %s", tostring(fields[4]), tostring(fields[3]), peer,
            roleName(fields[6]), tostring(distribution), roleName(role.code)))
    end
end

-- Receive handler ---------------------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, prefix, text, distribution, sender)
    if event ~= "CHAT_MSG_ADDON" or prefix ~= PREFIX or type(text) ~= "string" then
        return
    end
    local fields = parse(text)
    local kind = fields[1]
    local ok, err = pcall(function()
        if kind == "W" or kind == "WO" then
            onWhisper(fields, sender, text)
        elseif kind == "D" then
            onGuildMessage(fields, distribution, sender, text)
        end
    end)
    if not ok then
        out("whisper/guild handler error: " .. tostring(err))
    end
end)
call(frame.RegisterEvent, frame, "CHAT_MSG_ADDON")

-- Export ------------------------------------------------------------------------------------------------------------------------------
function Probe:WhisperLines()
    local d = db()
    local lines = {}
    local function add(s)
        lines[#lines + 1] = s
    end
    local lv = levelText()
    add(string.format("S4/S5 prefix %s | this character: %s | %s | pong auto-reply %s", PREFIX, lv, guildRole().text,
        tostring(pongOn())))
    for i, e in ipairs(d.tx) do
        add(string.format("S4 tx %d | %s | whisper #%s to %s | result %s | sender %s | %s", i, e.time, tostring(e.seq), e.target, e.result,
            tostring(e.level), tostring(e.lockdown)))
    end
    for i, e in ipairs(d.rx) do
        add(string.format("S4 rx %d | %s | %s from %s via %s | len %d | one-way ~%s s | rtt %s ms | peer level %s trial %s | this client %s%s",
            i, e.time, e.kind, e.peer, e.dist, e.len, tostring(e.oneWaySeconds), tostring(e.rttMs), tostring(e.peerLevel),
            tostring(e.peerTrial), tostring(e.receiver), e.replyResult and (" | reply: " .. e.replyResult) or ""))
    end
    for i, e in ipairs(d.guildTx) do
        add(string.format("S5 tx %d | %s | %s #%s | result %s | sender %s | %s", i, e.time, e.dist, tostring(e.seq), e.result, e.role,
            tostring(e.level)))
    end
    for i, e in ipairs(d.guildRx) do
        add(string.format("S5 rx %d | %s | asked %s, arrived on %s | #%s from %s (%s, rank %s) | received by %s (rank %s) | one-way ~%s s | len %d",
            i, e.time, tostring(e.requested), e.dist, tostring(e.seq), e.peer, e.senderRole, tostring(e.senderRank), e.receiverRole,
            tostring(e.receiverRank), tostring(e.oneWaySeconds), e.len))
    end
    return lines
end
table.insert(Probe.exportHooks, function(self)
    return self:WhisperLines()
end)

-- Checks ------------------------------------------------------------------------------------------------------------------------------
local function count(list, pred)
    local n = 0
    for _, e in ipairs(list) do
        if pred(e) then
            n = n + 1
        end
    end
    return n
end

local function startsWith(s, p)
    return type(s) == "string" and s:sub(1, #p) == p
end

Probe:Register("S4", "Addon WHISPER to a non-friend, also from a low-level character (/agfp whisper <name>, receiver /agfp pong on)",
    function()
        local d = db()
        local sentOk = count(d.tx, function(e) return startsWith(e.result, "0:") end)
        local replies = count(d.rx, function(e) return e.kind == "WO" and e.rttMs ~= nil end)
        local received = count(d.rx, function(e) return e.kind == "W" and e.peer ~= "<self>" end)
        local levels = {}
        for _, e in ipairs(d.tx) do
            levels[#levels + 1] = (e.level or "?"):match("^(%S+)") .. ":" .. e.result
        end
        local text = string.format("whispers sent=%d (result 0: %d), replies received=%d, whispers received from others=%d; %s; %s",
            #d.tx, sentOk, replies, received, levelText(), table.concat(levels, " "))
        if replies > 0 then
            return "pass", text
        elseif #d.tx > 0 and sentOk == 0 then
            return "fail", text .. "; every send was refused"
        elseif #d.tx > 0 then
            return "info", text .. "; sent but no reply (receiver offline, pong off, or the whisper was dropped)"
        end
        return "info", text .. "; no whisper sent yet"
    end)

Probe:Register("S5", "OFFICER as an addon channel (/agfp officer and /agfp guild from an officer; plain members listen)", function()
    local d = db()
    local officerTx = count(d.guildTx, function(e) return e.dist == "OFFICER" end)
    local officerTxOk = count(d.guildTx, function(e) return e.dist == "OFFICER" and startsWith(e.result, "0:") end)
    local guildTxOk = count(d.guildTx, function(e) return e.dist == "GUILD" and startsWith(e.result, "0:") end)
    local function rx(dist, role)
        return count(d.guildRx, function(e)
            return e.peer ~= "<self>" and e.dist == dist and (role == nil or e.receiverRole == role)
        end)
    end
    local text = string.format("%s; OFFICER sent=%d (ok %d), GUILD sent ok=%d; received from others: OFFICER by officer/leader=%d, OFFICER by plain member=%d, GUILD=%d",
        guildRole().text, officerTx, officerTxOk, guildTxOk, rx("OFFICER", "officer") + rx("OFFICER", "leader"), rx("OFFICER", "member"),
        rx("GUILD"))
    local memberGotOfficer = rx("OFFICER", "member") > 0
    if rx("OFFICER") > 0 then
        return "pass", text .. (memberGotOfficer and "; NOTE: a plain member received OFFICER (not private)" or "")
    elseif officerTx > 0 and officerTxOk == 0 then
        return "fail", text .. "; every OFFICER send was refused: use the GUILD fallback of SPEC-02 section 7"
    elseif officerTxOk > 0 and rx("GUILD") > 0 then
        return "fail", text .. "; OFFICER sends were accepted but nothing arrived while GUILD did: use the GUILD fallback"
    end
    return "info", text .. "; not enough data yet (an officer sends /agfp officer and /agfp guild while another guild member listens)"
end)

-- Slash commands -----------------------------------------------------------------------------------------------------------------------
Probe.commands.whisper = function(arg)
    whisper(arg)
end
Probe.commands.officer = function()
    guildSend("OFFICER")
end
Probe.commands.guild = function()
    guildSend("GUILD")
end
