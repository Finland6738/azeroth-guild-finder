-- Compat layer (M1.3): guarded calls, missing / erroring / secret APIs, the C_Club fallback, restrictions, /gf debug.
-- The module is reachable as AzerothGuildFinder.Compat. Tests replace client globals AFTER login; the capability
-- table is rebuilt with Compat:Probe() when a test needs it.
local function compat()
	return AzerothGuildFinder.Compat
end

describe("Resolve and Call", function()
	it("resolves dotted names and returns nil for nothing", function()
		local C = compat()
		eq(C.Resolve("C_ChatInfo.InChatMessagingLockdown"), C_ChatInfo.InChatMessagingLockdown)
		eq(C.Resolve("Enum.Base64Variant.Standard"), 0)
		eq(C.Resolve("Nope.Nothing.Here"), nil)
		eq(C.Resolve(""), nil)
		eq(C.Resolve(42), nil)
	end)

	it("reports an available function with its values", function()
		local state, a, b = compat().Call("GetBuildInfo")
		eq(state, "available")
		eq(a, "1.60.1")
		eq(b, "70170")
	end)

	it("reports a missing function", function()
		local state, v = compat().Call("C_Club.DoesNotExist")
		eq(state, "missing")
		eq(v, nil)
	end)

	it("catches an erroring function", function()
		function BoomGlobal() error("kaput") end
		eq((compat().Call("BoomGlobal")), "error")
	end)

	it("classes a restriction error as restricted", function()
		function RestrictedGlobal() error("action restricted by the client") end
		eq((compat().Call("RestrictedGlobal")), "restricted")
	end)

	it("drops secret values and reports restricted", function()
		local secret = {}
		function issecretvalue(v) return v == secret end
		function SecretGlobal() return secret, 5 end
		local state, a, b = compat().Call("SecretGlobal")
		eq(state, "restricted")
		eq(a, nil)
		eq(b, 5)
		truthy(compat().IsSecret(secret))
		eq(compat().Readable(secret), nil)
		eq(compat().Readable(7), 7)
	end)

	it("honours canaccessvalue", function()
		local hidden = {}
		function canaccessvalue(v) return v ~= hidden end
		truthy(compat().IsSecret(hidden))
		falsy(compat().IsSecret({}))
	end)

	it("works when the secret functions do not exist", function()
		issecretvalue, canaccessvalue, issecrettable = nil, nil, nil
		falsy(compat().IsSecret({}))
		eq((compat().Call("GetBuildInfo")), "available")
	end)
end)

describe("guild helpers", function()
	it("reads guild, rank and roster from the classic API", function()
		local C = compat()
		Mock.guild.Set{ name = "Test Guild", myRank = 0, members = { { name = "Bob", level = 40, rank = 2, online = false, lastOnline = { 0, 1, 2, 3 } } } }
		truthy(C.Guild.InGuild())
		eq(C.Guild.GuildName(), "Test Guild")
		truthy(C.Guild.IsGuildLeader())
		truthy(C.Guild.IsOfficer())
		eq((C.Guild.RosterCount()), 2)
		local row = C.Guild.RosterRow(2)
		eq(row.name, "Bob")
		eq(row.level, 40)
		eq(row.online, false)
		eq(row.lastOnlineHours, 720 + 48 + 3)
		eq(C.Guild.LastOnline(2), 771)
		eq(C.Guild.LastOnline(1), nil)
		eq(C.Guild.RosterRow(9), nil)
	end)

	it("an officer who is not the leader is an officer", function()
		Mock.guild.Set{ name = "G", myRank = 1 }
		falsy(compat().Guild.IsGuildLeader())
		truthy(compat().Guild.IsOfficer())
		Mock.guild.SetMyRank(3)
		falsy(compat().Guild.IsOfficer())
	end)

	it("no guild", function()
		Mock.guild.Leave()
		falsy(compat().Guild.InGuild())
		eq(compat().Guild.GuildName(), nil)
		eq((compat().Guild.RosterCount()), 0)
	end)

	it("falls back to C_Club when the classic functions are missing", function()
		local members = {
			[11] = { name = "Ann", level = 30, classID = 5, guid = "Player-1-A", guildRankOrder = 2 },
			[12] = { name = "Cid", level = 50, classID = 1, guid = "Player-1-C", guildRankOrder = 4,
				lastOnlineYear = 0, lastOnlineMonth = 0, lastOnlineDay = 3, lastOnlineHour = 4 },
		}
		IsInGuild, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo, GetGuildRosterLastOnline, IsGuildLeader = nil, nil, nil, nil, nil, nil
		C_Club = {
			GetGuildClubId = function() return 7 end,
			GetClubInfo = function(id) return id == 7 and { name = "Club Guild" } or nil end,
			GetClubMembers = function() return { 11, 12 } end,
			GetMemberInfo = function(_, id) return members[id] end,
		}
		local C = compat()
		truthy(C.Guild.InGuild())
		eq(C.Guild.GuildName(), "Club Guild")
		eq((C.Guild.RosterCount()), 2)
		local a, c = C.Guild.RosterRow(1), C.Guild.RosterRow(2)
		eq(a.name, "Ann"); eq(a.rankIndex, 1); eq(a.online, true); eq(a.lastOnlineHours, nil)
		eq(c.classID, 1); eq(c.online, false); eq(c.lastOnlineHours, 76)
		eq(C.Guild.LastOnline(2), 76)
		eq(C.Guild.RosterRow(3), nil)
	end)

	it("degrades to nothing when neither API exists", function()
		IsInGuild, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo, IsGuildLeader, C_Club = nil, nil, nil, nil, nil, nil
		local C = compat()
		falsy(C.Guild.InGuild())
		eq(C.Guild.GuildName(), nil)
		eq((C.Guild.RosterCount()), 0)
		eq(C.Guild.RosterRow(1), nil)
		falsy(C.Guild.IsGuildLeader())
	end)

	it("an erroring GetGuildInfo does not raise", function()
		function GetGuildInfo() error("no") end
		eq(compat().Guild.GuildName(), nil)
	end)
end)

describe("player helpers", function()
	it("reads the player", function()
		local C = compat()
		eq(C.Player.Faction(), "Horde")
		eq(C.Player.Realm(), "TestRealm")
		eq(C.Player.Level(), 60)
		eq(C.Player.ClassID(), 1)
		eq(C.Player.RaceID(), 2)
		eq(C.Player.MaxLevel(), 60)
		eq(C.Player.AverageItemLevel(), 0)
	end)

	it("missing player APIs return nil", function()
		UnitFactionGroup, UnitLevel, UnitClass, UnitRace, GetNormalizedRealmName, GetRealmName = nil, nil, nil, nil, nil, nil
		GetAverageItemLevel, GetMaxPlayerLevel = nil, nil
		local C = compat()
		eq(C.Player.Faction(), nil); eq(C.Player.Level(), nil); eq(C.Player.ClassID(), nil); eq(C.Player.RaceID(), nil)
		eq(C.Player.Realm(), nil); eq(C.Player.AverageItemLevel(), nil); eq(C.Player.MaxLevel(), nil)
	end)

	it("realm falls back to GetRealmName and max level to the expansion", function()
		GetNormalizedRealmName, GetMaxPlayerLevel = nil, nil
		GetMaxLevelForPlayerExpansion = function() return 70 end
		eq(compat().Player.Realm(), "TestRealm")
		eq(compat().Player.MaxLevel(), 70)
	end)
end)

describe("restrictions", function()
	local function install(states)
		Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 }
		C_RestrictedActions = { GetAddOnRestrictionState = function(kind) return states[kind] or 0 end }
	end

	it("chat lockdown and outgoing restriction follow the client", function()
		local C = compat()
		falsy(C.Chat.InChatLockdown())
		falsy(C.Chat.OutgoingAddonRestricted())
		Mock.chat.lockdown, Mock.chat.restricted = true, true
		truthy(C.Chat.InChatLockdown())
		truthy(C.Chat.OutgoingAddonRestricted())
	end)

	it("a missing lockdown API is not a lockdown, an erroring one is", function()
		C_ChatInfo.InChatMessagingLockdown = nil
		falsy(compat().Chat.InChatLockdown())
		C_ChatInfo.InChatMessagingLockdown = function() error("x") end
		truthy(compat().Chat.InChatLockdown())
	end)

	it("a secret lockdown result counts as locked", function()
		local secret = {}
		function issecretvalue(v) return v == secret end
		C_ChatInfo.InChatMessagingLockdown = function() return secret end
		truthy(compat().Chat.InChatLockdown())
	end)

	it("reads the restriction states", function()
		install({ [1] = 2 })
		local C = compat()
		local active, state = C.Chat.RestrictionActive("Encounter")
		truthy(active); eq(state, 2)
		falsy((C.Chat.RestrictionActive("Combat")))
		eq(C.Chat.RestrictionAny(), "Encounter")
		falsy(C.Chat.CanSend())
	end)

	it("no enum or no function means no restriction", function()
		Enum.AddOnRestrictionType = nil
		falsy((compat().Chat.RestrictionActive("Combat")))
		eq(compat().Chat.RestrictionAny(), nil)
		truthy(compat().Chat.CanSend())
	end)

	it("an erroring state function counts as restricted; IsAddOnRestrictionActive is the fallback", function()
		install({})
		C_RestrictedActions.GetAddOnRestrictionState = function() error("boom") end
		truthy((compat().Chat.RestrictionActive("Combat")))
		C_RestrictedActions.GetAddOnRestrictionState = nil
		C_RestrictedActions.IsAddOnRestrictionActive = function(kind) return kind == 3 end
		truthy((compat().Chat.RestrictionActive("PvPMatch")))
		falsy((compat().Chat.RestrictionActive("Combat")))
	end)
end)

describe("time, encoding, channels", function()
	it("server time falls back to os time", function()
		eq(type(compat().ServerTime()), "number")
		GetServerTime = nil
		eq(type(compat().ServerTime()), "number")
	end)

	it("encoding round trip through the wrappers", function()
		local C = compat()
		local cbor = C.CBOR.Encode({ a = 1, b = "x" })
		deepEq(C.CBOR.Decode(cbor), { a = 1, b = "x" })
		local packed = C.Compress.Deflate(("abc"):rep(100))
		eq(C.Compress.Inflate(packed), ("abc"):rep(100))
		eq(C.Base64.Decode(C.Base64.Encode("hello")), "hello")
	end)

	it("encoding wrappers return nil and a text, never raise", function()
		local C = compat()
		local v, err = C.Base64.Decode("###")
		eq(v, nil)
		contains(err, "error")
		C_EncodingUtil = nil
		v, err = C.CBOR.Encode({})
		eq(v, nil)
		contains(err, "missing")
	end)

	it("channels", function()
		local C = compat()
		eq(C.JoinChannelByName("AzGuildFinder"), "available")
		local id, name = C.GetChannelName("AzGuildFinder")
		truthy(id > 0); eq(name, "AzGuildFinder")
		C.LeaveChannelByName("AzGuildFinder")
		eq((C.GetChannelName("AzGuildFinder")), 0)
	end)

	it("missing channel functions", function()
		JoinChannelByName, GetChannelName, LeaveChannelByName = nil, nil, nil
		local C = compat()
		eq(C.JoinChannelByName("x"), "missing")
		eq(C.GetChannelName("x"), nil)
		eq(C.LeaveChannelByName("x"), "missing")
	end)
end)

describe("capability probe and /gf debug", function()
	it("probes at login", function()
		local C = compat()
		truthy(C.probed)
		eq(C:State("guild.IsInGuild"), "available")
		eq(C:State("club.GetGuildClubId"), "missing")
		truthy(C:IsAvailable("encoding.roundTrip"))
	end)

	it("marks missing, restricted and erroring APIs", function()
		T.boot(function()
			GetGuildRosterLastOnline = nil
			C_ChatInfo.InChatMessagingLockdown = function() return true end
			C_GuildInfo.IsGuildOfficer = function() error("bad") end
			Enum.AddOnRestrictionType = { Combat = 0 }
			C_RestrictedActions = { GetAddOnRestrictionState = function() return 1 end }
		end)
		local C = compat()
		eq(C:State("guild.GetGuildRosterLastOnline"), "missing")
		eq(C:State("chat.InChatMessagingLockdown"), "restricted")
		eq(C:State("guild.IsGuildOfficer"), "error")
		eq(C:State("restriction.Combat"), "restricted")
		eq(C:State("restriction.Encounter"), "missing")
	end)

	it("/gf debug prints build, project id and every capability, without names", function()
		Mock.guild.Set{ name = "Secret Guild Name" }
		Mock.ClearOutput()
		truthy(Mock.Slash("/gf debug"))
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "1.60.1 (build 70170), interface 16001, project id 99 (Forever)")
		contains(text, "[available] guild.IsInGuild")
		contains(text, "[missing] club.GetGuildClubId")
		contains(text, "Capabilities:")
		for _, id in ipairs(compat().capOrder) do contains(text, id) end
		falsy(text:find("Testchar", 1, true), "no player name")
		falsy(text:find("Secret Guild Name", 1, true), "no guild name")
	end)

	it("/gf debug probes when the login probe did not run", function()
		compat().probed = false
		Mock.ClearOutput()
		Mock.Slash("/gf debug")
		contains(table.concat(Mock.PlainOutput(), "\n"), "[available] guild.IsInGuild")
	end)
end)
