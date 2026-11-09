-- Seed: fake listings for the development of the list (/gf debug seed). Development builds only (Config.DEV): a release
-- refuses. The listings go into the LOCAL catalog as "local only" (Catalog meta.localOnly): they are shown in the list,
-- never put in a digest and never sent in an answer to another client, and nothing here talks to the network.
-- Everything is deterministic: the same count gives the same guilds, so a screenshot or a test can be repeated.
--   Seed.Make(n [, ctx])   the list of summaries (pure; ctx = { realm, faction, now, classIds })
--   Seed:Run(n)            puts n of them into the catalog (default 60, at most the catalog limit). Returns how many.
--   Seed:Clear()           removes every local only listing
-- The names mix accents, symbols and one-word names on purpose: they exercise the ordering and the search of SPEC-03 §7.
-- Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Seed = {}
ns.Seed, ns.modules = Seed, ns.modules or {}
ns.modules.Seed = Seed

local floor = math.floor
local format = string.format

Seed.DEFAULT = 60

local FIRST = { "Order of the", "Ordine del", "Ördine", "Legion of", "Guardians of", "Les", "Die", "Los", "Pack of the",
	"Knights of", "Sons of", "[AD]", "Night", "Iron", "Silver", "Ember", "Frost", "Storm", "Old", "Free" }
local SECOND = { "Dragon", "Drago", "Wolf", "Lupi", "Phoenix", "Dawn", "Aurora", "Raven", "Ravens", "Lion", "Oak", "Anvil",
	"Tide", "Hollow", "Thorn", "Banner", "Citadel", "Vale", "Ashes", "Echo", "Café Noir", "Æther", "Crown", "Hearth" }
local SUBS = { "Raids on weekends, relaxed and friendly", "Small-scale PvP and a calm raid night", "Leveling together, no pressure",
	"Hardcore progression, voice chat required", "Dungeons, professions and good company", "A home for returning players",
	"Casual evenings, everyone welcome", "Organised world PvP and battlegrounds", "Roleplay on the roads of Azeroth", "" }

local function lcg(seed)
	local x = seed
	return function(n)
		x = (x * 1103515245 + 12345) % 2147483648
		return floor(x / 65536) % n + 1   -- 1..n
	end
end

local function clock()
	if ns.Compat and ns.Compat.ServerTime then return ns.Compat.ServerTime() end
	return time()
end

-- The summaries of `n` fake guilds of realm/faction (ctx.realm, ctx.faction), newest announcement first in the list.
-- Returns { { sum = <summary>, annAt = <server time of its last announcement> }, ... }.
function Seed.Make(n, ctx)
	ctx = ctx or {}
	local E, N = ns.Enums, ns.Normalize
	local now = ctx.now or clock()
	local classIds = ctx.classIds or E.ClassesForFaction(ctx.faction)
	local rnd = lcg(20261109)
	local out, used = {}, {}
	for i = 1, n do
		local name, tries = nil, 0
		repeat
			name = FIRST[rnd(#FIRST)] .. " " .. SECOND[rnd(#SECOND)]
			tries = tries + 1
			if tries > 8 then name = name .. " " .. i end
		until not used[name]
		used[name] = true
		local k = format("%s|%s|%s", ctx.realm, ctx.faction, name)

		local lang1 = rnd(E.LANGUAGE_COUNT)
		local lang = E.LanguageBit(lang1)
		if rnd(3) == 1 then
			local second = rnd(E.LANGUAGE_COUNT)
			if second ~= lang1 then lang = lang + E.LanguageBit(second) end
		end
		local tags, seen = {}, {}
		for _ = 1, rnd(E.MAX_TAGS) do
			local id = rnd(E.ACTIVITY_COUNT)
			if not seen[id] then seen[id] = true tags[#tags + 1] = id end
		end
		local want, wants = {}, rnd(5) - 1   -- 0..4 classes
		for _ = 1, wants do
			local id = classIds[rnd(#classIds)]
			local mask = E.FilterRoles(id, rnd(15))
			if mask > 0 then want[id] = mask end
		end
		if wants == 0 and rnd(2) == 1 then want[0] = rnd(15) end
		if next(want) == nil then want = nil end

		local days = rnd(127)
		local t0 = (rnd(24) - 1) * 60 + (rnd(2) - 1) * 30
		local t1 = (t0 + rnd(6) * 60 + 60) % 1440
		if rnd(10) == 1 then t1 = t0 end   -- all day
		local members = rnd(150) + 4
		local active = rnd(members)
		local ageDays = rnd(10) == 1 and (14 + rnd(10)) or (rnd(14) - 1)   -- one in ten may be inactive
		local sub = SUBS[rnd(#SUBS)]
		local sum = {
			k = k, rev = now - rnd(20) * 86400, upd = now - rnd(20) * 86400, first = now - 86400 * 30,
			own = N.Hash32Hex("seed:" .. k), sub = sub ~= "" and sub or nil,
			lang1 = lang1, lang = lang, tags = tags, pace = rnd(E.PACE_COUNT), days = days, t0 = t0, t1 = t1,
			rec = rnd(10) == 1 and 0 or 1, apps = rnd(4) ~= 1, want = want, newb = rnd(3) == 1,
			minL = rnd(3) == 1 and (rnd(6) * 10) or nil, minI = rnd(8) == 1 and (rnd(10) * 10) or nil,
			bg = rnd(12), st = { m = members, a7 = active, u7lo = floor(active * 0.6), u7hi = active, max = floor(active / 3) },
			srev = now - now % 3600,
		}
		out[#out + 1] = { sum = sum, annAt = now - ageDays * 86400 - rnd(80000) }
	end
	return out
end

local function say(text) if ns.addon and ns.addon.Print then ns.addon:Print(text) end end

-- Puts `n` fake guilds in the local catalog. Returns how many were added, or nil, reason ("release" | "nocatalog").
function Seed:Run(n)
	if not (ns.Config and ns.Config.DEV) then return nil, "release" end
	local P = ns.Compat and ns.Compat.Player
	local realm, faction = P and P.Realm(), P and P.Faction()
	if not realm or not faction or not ns.Catalog then return nil, "nocatalog" end
	local max = ns.Config.LIMITS.LISTINGS_PER_REALM_FACTION
	n = floor(tonumber(n) or Seed.DEFAULT)
	if n < 1 then n = 1 elseif n > max then n = max end
	local now = clock()
	local added = 0
	for _, item in ipairs(Seed.Make(n, { realm = realm, faction = faction, now = now })) do
		if ns.Catalog:PutSummary(item.sum, { annAt = item.annAt, now = now, localOnly = true }) then added = added + 1 end
	end
	return added
end

function Seed:Clear() return ns.Catalog and ns.Catalog:RemoveLocal() or 0 end

-- /gf debug seed [n | clear]
function Seed:Command(argument)
	local L = ns.L
	if not (ns.Config and ns.Config.DEV) then return say(L["SEED_DEV_ONLY"]) end
	argument = tostring(argument or ""):lower()
	if argument == "clear" then return say(L["SEED_CLEARED"]:format(Seed:Clear())) end
	local n = argument ~= "" and tonumber(argument) or nil
	if argument ~= "" and not n then return say(L["SEED_BAD"]:format(argument:sub(1, 20))) end
	local added, why = Seed:Run(n)
	if not added then return say(L["SEED_FAILED"]:format(tostring(why))) end
	say(L["SEED_DONE"]:format(added))
end

if ns.addon then ns.addon.Seed = Seed end
