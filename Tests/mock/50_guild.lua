-- Mock client, part 6: the guild and its roster.
--
-- Imitates: IsInGuild, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo, GetGuildRosterLastOnline, IsGuildLeader,
-- CanGuildInvite, C_GuildInfo.{IsGuildOfficer, GuildRoster, Invite, GuildControlGetRankFlags, GetGuildTabardInfo,
-- GetMOTD, GetInfoText, MemberExistsByName, CanSpeakInGuildChat}.
-- Dump files: ../WoW-Addons/docs/api/Guild-Social-Chat/C_GuildInfo.md; GetGuildInfo, GetNumGuildMembers,
-- GetGuildRosterInfo, IsGuildLeader and IsInGuild are in api.json "globals"; GetGuildRosterLastOnline is not
-- (spec: "to verify"). GuildTabardInfo is not in the dump: the fields are what the M0.5 probe will confirm.
--
-- Configure with Mock.guild (kept across Mock.Reload):
--   Mock.guild.Set{ name=, realm=, ranks={"Guild Master","Officer",...}, myRank=<index, 0 = Guild Master>,
--                   officerRanks=<highest rank index that counts as officer, default 1>, motd=, info=, tabard=,
--                   members={ {name=, level=, class=, rank=<index>, online=, zone=, note=, lastOnline={y,m,d,h}} } }
--   Mock.guild.Leave()          the character has no guild
--   Mock.guild.SetMyRank(i)     changes the rank and fires PLAYER_GUILD_UPDATE and GUILD_ROSTER_UPDATE
--   Mock.guild.invites          names of the invites that went out (C_GuildInfo.Invite)
--   Mock.guild.inviteReply      what the game answers to an invite: "ok" | "silent" | "offline" | "denied" | "inguild" | "blocked"
-- The roster arrives asynchronously after C_GuildInfo.GuildRoster(), as in the client (GUILD_ROSTER_UPDATE on a later frame).
local Mock, H = ...
local W = Mock.world

local DEFAULT_RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Member", "Initiate" }

W.guild = W.guild or { invites = {}, members = {}, ranks = DEFAULT_RANKS, officerRanks = 1 }
local guild = W.guild
Mock.guild = guild

local CLASS_NAMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest", DEATHKNIGHT = "Death Knight",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", MONK = "Monk", DRUID = "Druid", DEMONHUNTER = "Demon Hunter",
	EVOKER = "Evoker",
}

local function me()
	local p = W.player
	return {
		name = p.name, level = p.level, class = p.classFile, rank = guild.myRank, online = true, zone = "Orgrimmar",
		note = "", officerNote = "", me = true,
	}
end

local function roster()
	local list = { me() }
	for _, m in ipairs(guild.members) do list[#list + 1] = m end
	return list
end

-- Empties the data fields; the functions (Set, Leave, ...) stay because they live in the same table.
local function resetData()
	for k, v in pairs(guild) do
		if type(v) ~= "function" then guild[k] = nil end
	end
	guild.invites, guild.members, guild.ranks, guild.officerRanks = {}, {}, DEFAULT_RANKS, 1
end

function Mock.guild.Set(config)
	resetData()
	guild.name = config.name or "Test Guild"
	guild.realm = config.realm
	guild.ranks = config.ranks or DEFAULT_RANKS
	guild.myRank = config.myRank or 0
	guild.officerRanks = config.officerRanks or 1
	guild.motd, guild.info, guild.tabard = config.motd or "", config.info or "", config.tabard
	for _, m in ipairs(config.members or {}) do
		guild.members[#guild.members + 1] = {
			name = m.name, level = m.level or 60, class = m.class or "WARRIOR", rank = m.rank or #guild.ranks,
			online = m.online ~= false, zone = m.zone or "Orgrimmar", note = m.note or "", officerNote = m.officerNote or "",
			lastOnline = m.lastOnline,
		}
	end
	Mock.Fire("PLAYER_GUILD_UPDATE", "player")
	Mock.Fire("GUILD_ROSTER_UPDATE")
end

function Mock.guild.Leave()
	local had = guild.name ~= nil
	resetData()
	if had then Mock.Fire("PLAYER_GUILD_UPDATE", "player") end
end

function Mock.guild.SetMyRank(index)
	guild.myRank = index
	Mock.Fire("PLAYER_GUILD_UPDATE", "player")
	Mock.Fire("GUILD_ROSTER_UPDATE")
end

function IsInGuild() return guild.name ~= nil end

function GetGuildInfo(unit)
	if unit ~= "player" or not guild.name then return nil end
	return guild.name, guild.ranks[guild.myRank], guild.myRank, guild.realm
end

function IsGuildLeader() return guild.name ~= nil and guild.myRank == 0 end
function CanGuildInvite() return guild.name ~= nil and guild.myRank <= guild.officerRanks end

function GetNumGuildMembers()
	if not guild.name then return 0, 0, 0 end
	local list, online = roster(), 0
	for _, m in ipairs(list) do if m.online then online = online + 1 end end
	return #list, online, online
end

-- name, rankName, rankIndex, level, classDisplayName, zone, note, officerNote, isOnline, status, classFileName,
-- achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid
function GetGuildRosterInfo(index)
	local m = guild.name and roster()[index]
	if not m then return nil end
	return m.name, guild.ranks[m.rank], m.rank, m.level, CLASS_NAMES[m.class] or m.class, m.zone, m.note, m.officerNote,
		m.online, 0, m.class, 0, 0, false, false, 4, "Player-1-" .. string.format("%08X", index)
end

-- years, months, days, hours since the member was last online; nothing while online.
function GetGuildRosterLastOnline(index)
	local m = guild.name and roster()[index]
	if not m or m.online then return nil end
	local t = m.lastOnline or { 0, 0, 1, 0 }
	return t[1], t[2], t[3], t[4]
end

C_GuildInfo = {}
function C_GuildInfo.IsGuildOfficer() return guild.name ~= nil and guild.myRank <= guild.officerRanks end
function C_GuildInfo.CanSpeakInGuildChat() return guild.name ~= nil end
function C_GuildInfo.GetMOTD() return guild.motd or "" end
function C_GuildInfo.GetInfoText() return guild.info or "" end

function C_GuildInfo.MemberExistsByName(name)
	for _, m in ipairs(roster()) do
		if m.name == name then return true end
	end
	return false
end

function C_GuildInfo.GuildRoster()
	C_Timer.After(0, function() Mock.Fire("GUILD_ROSTER_UPDATE") end)
end

-- What the game answers is Mock.guild.inviteReply: "ok" (default: the invite goes out and the game says so), "silent" (it
-- goes out and the game says nothing), "offline" (UI_ERROR_MESSAGE: no player named ...), "denied" (no permission),
-- "inguild" (already in a guild) or "blocked" (a protected call: ADDON_ACTION_FORBIDDEN, nothing happens).
function C_GuildInfo.Invite(name)
	local reply = guild.inviteReply or "ok"
	local base = tostring(name):match("^[^%-]+") or tostring(name)
	if reply == "blocked" then
		Mock.Fire("ADDON_ACTION_FORBIDDEN", "AzerothGuildFinder", "C_GuildInfo.Invite()")
	elseif reply == "offline" then
		Mock.Fire("UI_ERROR_MESSAGE", 50, ("No player named '%s' is currently playing."):format(base))
	elseif reply == "denied" then
		Mock.Fire("UI_ERROR_MESSAGE", 51, "You don't have permission to do that.")
	elseif reply == "inguild" then
		Mock.Fire("UI_ERROR_MESSAGE", 52, ("%s is already in a guild."):format(base))
	else
		guild.invites[#guild.invites + 1] = name
		if reply == "ok" then Mock.Fire("CHAT_MSG_SYSTEM", ("You have invited %s to join your guild."):format(base)) end
	end
end

-- rankOrder is 1-based (luaIndex). Flags follow the order of the retail UI: 1 guild chat listen, 2 guild chat speak,
-- 3 officer chat listen, 4 officer chat speak, 5 promote, 6 demote, 7 invite, 8 remove, 9 set MOTD, ...
function C_GuildInfo.GuildControlGetRankFlags(rankOrder)
	local rank = rankOrder - 1
	local officer = rank <= guild.officerRanks
	local flags = {}
	for i = 1, 20 do flags[i] = officer end
	flags[1], flags[2] = true, true
	return flags
end

-- Returns a copy of the table given to Mock.guild.Set; nil when the guild has no tabard configured.
function C_GuildInfo.GetGuildTabardInfo(unit)
	if not guild.name or unit ~= "player" or not guild.tabard then return nil end
	return CopyTable(guild.tabard)
end
