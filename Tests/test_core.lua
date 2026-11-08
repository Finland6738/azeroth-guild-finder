-- Bus, Role and Normalize (M1.5): listener isolation, every role transition and the panel matrix, the name keys of
-- SPEC-03 §7, FNV-1a known vectors, UTF-8 helpers.
local function bus() return AzerothGuildFinder.Bus end
local function role() return AzerothGuildFinder.Role end
local function norm() return AzerothGuildFinder.Normalize end

describe("Bus", function()
	it("delivers arguments in subscription order", function()
		local seen = {}
		bus():On("T_A", function(a, b) seen[#seen + 1] = "1:" .. a .. b end)
		bus():On("T_A", function(a, b) seen[#seen + 1] = "2:" .. a .. b end)
		eq(bus():Emit("T_A", "x", "y"), 2)
		deepEq(seen, { "1:xy", "2:xy" })
	end)

	it("registers a function once and removes it with Off", function()
		local n = 0
		local f = function() n = n + 1 end
		truthy(bus():On("T_B", f))
		falsy(bus():On("T_B", f))
		bus():Emit("T_B")
		eq(n, 1)
		truthy(bus():Off("T_B", f))
		falsy(bus():Off("T_B", f))
		bus():Emit("T_B")
		eq(n, 1)
		eq(bus():ListenerCount("T_B"), 0)
	end)

	it("Off without a function removes every listener of the event", function()
		bus():On("T_C", function() end)
		bus():On("T_C", function() end)
		truthy(bus():Off("T_C"))
		eq(bus():ListenerCount("T_C"), 0)
	end)

	it("isolates a failing listener and records the error for /gf debug", function()
		local after = false
		bus():On("T_D", function() error("boom") end)
		bus():On("T_D", function() after = true end)
		eq(bus():Emit("T_D"), 1)
		truthy(after)
		eq(bus().errorCount, 1)
		contains(bus().errors[1].message, "boom")
		Mock.ClearOutput()
		Mock.Slash("/gf debug")
		contains(table.concat(Mock.PlainOutput(), "\n"), "error in T_D")
	end)

	it("allows a listener to unsubscribe itself while delivering", function()
		local n = 0
		local f
		f = function() n = n + 1 bus():Off("T_E", f) end
		bus():On("T_E", f)
		bus():On("T_E", function() n = n + 10 end)
		bus():Emit("T_E")
		bus():Emit("T_E")
		eq(n, 21)
	end)

	it("ignores bad arguments and unknown events", function()
		falsy(bus():On(nil, function() end))
		falsy(bus():On("T_F", "no"))
		eq(bus():Emit("T_NOBODY"), 0)
	end)
end)

describe("Role", function()
	local changes
	local function track()
		changes = {}
		bus():On("ROLE_CHANGED", function(r, key, oldR, oldKey) changes[#changes + 1] = { r, key, oldR, oldKey } end)
	end

	it("is none without a guild, with no guild key", function()
		Mock.guild.Leave()
		eq(role():Get(), "none")
		isNil(role():GuildKey())
	end)

	it("computes member, officer and gm from the rank", function()
		Mock.guild.Set{ name = "Test Guild", myRank = 3 }
		eq(role():Get(), "member")
		Mock.guild.SetMyRank(1)
		eq(role():Get(), "officer")
		Mock.guild.SetMyRank(0)
		eq(role():Get(), "gm")
	end)

	it("builds the guild key from realm, faction and guild name", function()
		Mock.player.realm, Mock.player.faction = "Fire Maw", "Alliance"
		Mock.guild.Set{ name = "Ördine del Drago", myRank = 2 }
		eq(role():GuildKey(), "FireMaw|Alliance|Ördine del Drago")
	end)

	it("has no guild key when the faction is unknown, but keeps the role", function()
		Mock.guild.Set{ name = "G", myRank = 2 }
		Mock.player.faction = "Neutral"
		role():Refresh()
		eq(role():Get(), "member")
		isNil(role():GuildKey())
	end)

	it("emits ROLE_CHANGED for every transition", function()
		Mock.guild.Leave()
		role():Refresh()
		track()
		Mock.guild.Set{ name = "Test Guild", myRank = 3 }   -- none -> member
		Mock.guild.SetMyRank(1)                             -- member -> officer
		Mock.guild.SetMyRank(0)                             -- officer -> gm
		Mock.guild.SetMyRank(3)                             -- gm -> member
		Mock.guild.Leave()                                  -- member -> none
		local path = {}
		for _, c in ipairs(changes) do path[#path + 1] = c[3] .. ">" .. c[1] end
		deepEq(path, { "none>member", "member>officer", "officer>gm", "gm>member", "member>none" })
		isNil(changes[5][2])
		eq(changes[1][2], "TestRealm|Horde|Test Guild")
	end)

	it("emits when only the guild changes (same role, other guild)", function()
		Mock.guild.Set{ name = "One", myRank = 3 }
		track()
		Mock.guild.Set{ name = "Two", myRank = 3 }
		eq(#changes, 1)
		eq(changes[1][4], "TestRealm|Horde|One")
		eq(changes[1][2], "TestRealm|Horde|Two")
	end)

	it("does not emit when nothing changed", function()
		Mock.guild.Set{ name = "One", myRank = 3 }
		track()
		Mock.Fire("GUILD_ROSTER_UPDATE")
		Mock.Fire("GUILD_RANKS_UPDATE")
		Mock.Fire("PLAYER_GUILD_UPDATE", "player")
		Mock.Fire("PLAYER_ENTERING_WORLD", false, false)
		eq(#changes, 0)
	end)

	it("recomputes on each of the four events", function()
		for _, event in ipairs{ "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILD_RANKS_UPDATE", "PLAYER_ENTERING_WORLD" } do
			Mock.guild.Leave()
			role():Refresh()
			Mock.guild.myRank, Mock.guild.name = 0, "G"   -- changes the client state without any event
			Mock.Fire(event, "player")
			eq(role():Get(), "gm", event)
			Mock.guild.Leave()
			role():Refresh()
		end
	end)

	it("survives a missing guild API (none, no error)", function()
		local saved = IsInGuild
		IsInGuild = nil
		if C_Club then C_Club.GetGuildClubId = nil end
		eq((role().Compute()), "none")
		IsInGuild = saved
	end)

	it("shows the panels of the SPEC-00 §5 matrix", function()
		local R = role()
		deepEq(R.PanelsFor("none", false), { "FindGuild", "MyApplication" })
		deepEq(R.PanelsFor("none", true), { "FindGuild", "MyApplication" })
		deepEq(R.PanelsFor("member", true), { "MyGuild" })
		deepEq(R.PanelsFor("member", false), { "MyGuild" })
		deepEq(R.PanelsFor("gm", false), { "CreateListing" })
		deepEq(R.PanelsFor("gm", true), { "MyGuild", "Applications" })
		deepEq(R.PanelsFor("officer", true), { "MyGuild", "Applications" })
		deepEq(R.PanelsFor("officer", false), { "MyGuild" })
	end)

	it("gives the panels of the current role", function()
		Mock.guild.Set{ name = "G", myRank = 0 }
		deepEq(role():Panels(false), { "CreateListing" })
		deepEq(role():Panels(true), { "MyGuild", "Applications" })
		Mock.guild.Leave()
		deepEq(role():Panels(), { "FindGuild", "MyApplication" })
	end)
end)

describe("Normalize keys", function()
	it("matches the examples of SPEC-03 §7", function()
		eq(norm().SortKey("Ördine del Drago"), "ordinedeldrago")
		eq(norm().SortKey("[AD] GankEmAll"), "adgankemall")
		eq(norm().SortKey("wjwkskjs i"), "wjwkskjsi")
	end)

	it("folds accents, ß, æ and œ", function()
		eq(norm().SortKey("àéöñç"), "aeonc")
		eq(norm().SortKey("ÀÉÖÑÇ"), "aeonc")
		eq(norm().SortKey("Straße"), "strasse")
		eq(norm().SortKey("Ælfred Œuvre"), "aelfredoeuvre")
		eq(norm().SortKey("Łódź Ørsted"), "lodzorsted")
	end)

	it("drops digits, symbols, spaces and other scripts", function()
		eq(norm().SortKey("a-b_c 1d2"), "abcd")
		eq(norm().SortKey("Guild 4 Life!"), "guildlife")
		eq(norm().SortKey("日本Guild"), "guild")
		eq(norm().SortKey("Гильдия"), "")
	end)

	it("returns an empty key for empty, digit-only and non-string input", function()
		eq(norm().SortKey(""), "")
		eq(norm().SortKey("12345"), "")
		eq(norm().SortKey("[]-_"), "")
		eq(norm().SortKey(nil), "")
		eq(norm().SortKey(42), "")
	end)

	it("survives invalid UTF-8", function()
		eq(norm().SortKey("ab\255\128c"), "abc")
		eq(norm().SortKey("ab\195"), "ab")
	end)

	it("SearchKey normalizes like SortKey", function()
		eq(norm().SearchKey("  Ördine-Del "), "ordinedel")
	end)

	it("Matches needs 3 letters and looks for a substring of the key", function()
		truthy(norm().Matches("Ördine del Drago", "ordine"))
		truthy(norm().Matches("Ördine del Drago", "DEL dra"))
		truthy(norm().Matches("[AD] GankEmAll", "gank em"))
		truthy(norm().Matches("Straße", "asse"))
		falsy(norm().Matches("Ördine del Drago", "or"))
		falsy(norm().Matches("Ördine del Drago", "o r"))
		falsy(norm().Matches("Ördine del Drago", "12-3"))
		falsy(norm().Matches("Ördine del Drago", ""))
		falsy(norm().Matches("Ördine del Drago", "xyz"))
		falsy(norm().Matches("", "abc"))
	end)

	it("Compare sorts by key, then by name, with empty keys last", function()
		local list = { "Zeta", "[1]", "Ördine", "alpha", "ordine", "99", "Alpha", "beta" }
		table.sort(list, norm().Compare)
		deepEq(list, { "Alpha", "alpha", "beta", "ordine", "Ördine", "Zeta", "99", "[1]" })
		truthy(norm().Compare("a", "b"))
		falsy(norm().Compare("a", "a"))
		falsy(norm().Compare("[", "a"))
		truthy(norm().Compare("a", "["))
	end)
end)

describe("Hash32 (FNV-1a)", function()
	local vectors = {
		{ "", 0x811c9dc5 }, { "a", 0xe40c292c }, { "b", 0xe70c2de5 }, { "foobar", 0xbf9cf968 }, { "foo", 0xa9f37ed7 },
	}

	it("matches the known vectors", function()
		for _, v in ipairs(vectors) do eq(norm().Hash32(v[1]), v[2], v[1]) end
	end)

	it("gives identical results with and without the bit library", function()
		local samples = { "", "a", "foobar", "Test Guild", "Ördine del Drago", string.rep("x", 300), "\0\255\128" }
		for _, s in ipairs(samples) do
			eq(norm().Hash32Arithmetic(s), norm().Hash32Bit(s), s)
		end
		for _, v in ipairs(vectors) do eq(norm().Hash32Arithmetic(v[1]), v[2], v[1]) end
	end)

	it("falls back to arithmetic when there is no bit library", function()
		local saved = bit
		bit = nil
		Mock.Reload()
		eq(norm().Hash32("foobar"), 0xbf9cf968)
		bit = saved
	end)

	it("formats as 8 hex digits", function()
		eq(norm().Hash32Hex(""), "811c9dc5")
		eq(norm().Hash32Hex("a"), "e40c292c")
	end)
end)

describe("UTF-8 helpers", function()
	it("counts characters", function()
		eq(norm().Utf8Len(""), 0)
		eq(norm().Utf8Len("abc"), 3)
		eq(norm().Utf8Len("Ördine"), 6)
		eq(norm().Utf8Len("日本語"), 3)
		eq(norm().Utf8Len(nil), 0)
	end)

	it("cuts by character", function()
		eq(norm().Utf8Sub("Ördine", 1, 1), "Ö")
		eq(norm().Utf8Sub("Ördine", 2, 4), "rdi")
		eq(norm().Utf8Sub("日本語", 2), "本語")
		eq(norm().Utf8Sub("日本語", -1), "語")
		eq(norm().Utf8Sub("日本語", 1, -2), "日本")
		eq(norm().Utf8Sub("abc", 0, 99), "abc")
		eq(norm().Utf8Sub("abc", 3, 2), "")
		eq(norm().Utf8Sub("", 1, 5), "")
		eq(norm().Utf8Sub(nil, 1, 5), "")
	end)
end)
