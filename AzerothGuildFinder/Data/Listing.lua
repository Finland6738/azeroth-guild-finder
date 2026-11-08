-- Listing: the guild listing records (SPEC-03 §2-§3, §6) and the application record (§8): constructors and Sanitize.
-- Every record that is received or saved goes through here. Sanitize never raises and never trusts its input:
--   record, issues = Listing.SanitizeSummary(raw [, opts])   -- opts.maxLevel overrides the client's maximum level
--   record, issues = Listing.SanitizeDetail(raw)
--   record, issues = Listing.SanitizeFull(raw)                -- summary + detail fields in one record (GLIST)
--   record, issues = Listing.SanitizeApplication(raw [, opts])
-- `record` is a NEW table holding only the known fields that passed (unknown fields are dropped); it is nil when the
-- whole record is rejected (no valid `k`, no valid `rev`; for an application no valid `id` or `k`). `issues` is a list
-- of strings "field: reason" (empty when nothing had to be changed). A field that is invalid is left out, never
-- repaired into something else, except numbers that are clamped to their range as SPEC-03 §6 says. A summary can pass
-- Sanitize and still be incomplete (no tags, no pace): Listing.IsComplete tells; the editor and the catalog decide.
-- Sanitize is idempotent: sanitizing its own output changes nothing (pipes are escaped to an even run: `|` -> `||`,
-- `||` stays `||`). Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Listing = {}
ns.Listing, ns.modules = Listing, ns.modules or {}
ns.modules.Listing = Listing

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor, ceil, huge = math.floor, math.ceil, math.huge
local find, sub, gsub, rep, lower, format = string.find, string.sub, string.gsub, string.rep, string.lower, string.format
local sort, concat = table.sort, table.concat

local Normalize = function() return ns.Normalize end
local Enums = function() return ns.Enums end

-- Limits of SPEC-03 (characters count as UTF-8 characters, not bytes).
Listing.LIMITS = {
	KEY = 80, SUB = 60, DESC = 500, DESC_LINES = 12, NOTE = 120, CONTACTS = 3, CONTACT = 48,
	WANT = 30, TAGS = 3, MIN_ILVL = 999, DISCORD_MIN = 2, DISCORD_MAX = 32, BG = 255,
	STAT = 1000000, EPOCH = 4102444800,            -- 2100-01-01
	WHO = 64, BY = 64, FALLBACK_MAX_LEVEL = 60,
}
local LIM = Listing.LIMITS

---------------------------------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------------------------------
local function isInt(v) return type(v) == "number" and v == v and v ~= huge and v ~= -huge and v == floor(v) end
local function intIn(v, lo, hi) return isInt(v) and v >= lo and v <= hi end

local function issue(issues, field, why) issues[#issues + 1] = field .. ": " .. why end

local function utf8Len(s) return Normalize().Utf8Len(s) end
local function utf8Sub(s, i, j) return Normalize().Utf8Sub(s, i, j) end

-- Text of SPEC-03 §6: control characters removed (except "\n" when `multiline`), `|` escaped as `||` (so no colour
-- code, link or texture can be built), trimmed, cut to `max` characters (and to `maxLines` lines).
local function trim(s) return (gsub(gsub(s, "^%s+", ""), "%s+$", "")) end

local function stripControls(s, keepNewline)
	if keepNewline then
		s = gsub(s, "\r\n", "\n")
		s = gsub(s, "[%z\1-\9\11-\31\127]", "")
	else
		s = gsub(s, "[%z\1-\31\127]", "")
	end
	return (gsub(s, "\194[\128-\159]", ""))   -- C1 controls (U+0080-U+009F)
end

local function escapePipes(s)
	return (gsub(s, "|+", function(run) return rep("|", ceil(#run / 2) * 2) end))
end

-- An odd run of pipes at the end (a cut escape) loses its last pipe.
local function fixTail(s)
	local run = s:match("(|+)$")
	if run and #run % 2 == 1 then return sub(s, 1, #s - 1) end
	return s
end

function Listing.CleanText(s, max, multiline, maxLines)
	if type(s) ~= "string" then return nil end
	s = stripControls(s, multiline)
	if multiline then
		local lines, n = {}, 0
		for line in (s .. "\n"):gmatch("(.-)\n") do
			n = n + 1
			if n > (maxLines or LIM.DESC_LINES) then break end
			lines[n] = line
		end
		s = concat(lines, "\n")
	end
	s = escapePipes(trim(s))
	if utf8Len(s) > max then s = trim(fixTail(utf8Sub(s, 1, max))) end
	return s
end

-- Text field: the cleaned text, or nothing when empty. Reports a change.
local function textField(out, raw, field, max, issues, multiline)
	local v = raw[field]
	if v == nil then return end
	if type(v) ~= "string" then issue(issues, field, "not a string") return end
	local clean = Listing.CleanText(v, max, multiline)
	if clean ~= v then issue(issues, field, "text cleaned") end
	if clean ~= "" then out[field] = clean end
end

local function intField(out, raw, field, lo, hi, issues)
	local v = raw[field]
	if v == nil then return end
	if intIn(v, lo, hi) then out[field] = v else issue(issues, field, "out of range or not an integer") end
end

-- A number clamped to lo..hi (floored); non-numbers are invalid.
local function clampField(out, raw, field, lo, hi, issues)
	local v = raw[field]
	if v == nil then return end
	if type(v) ~= "number" or v ~= v then issue(issues, field, "not a number") return end
	local c = floor(v)
	if c < lo then c = lo elseif c > hi then c = hi end
	if c ~= v then issue(issues, field, "clamped") end
	out[field] = c
end

local function boolField(out, raw, field, issues)
	local v = raw[field]
	if v == nil then return end
	if type(v) == "boolean" then out[field] = v else issue(issues, field, "not a boolean") end
end

local function epochField(out, raw, field, issues) intField(out, raw, field, 0, LIM.EPOCH, issues) end

local function maxLevel(opts)
	if opts and isInt(opts.maxLevel) and opts.maxLevel >= 1 then return opts.maxLevel end
	local compat = ns.Compat
	local v = compat and compat.Player and compat.Player.MaxLevel and compat.Player.MaxLevel()
	if isInt(v) and v >= 1 then return v end
	return LIM.FALLBACK_MAX_LEVEL
end

---------------------------------------------------------------------------------------------------------------------
-- Guild key and id helpers
---------------------------------------------------------------------------------------------------------------------

-- "Realm|Faction|Guild name" -> realm, faction, name; nil when it is not a valid key (SPEC-03 §1).
function Listing.ParseKey(k)
	if type(k) ~= "string" or k == "" then return nil end
	if utf8Len(k) > LIM.KEY then return nil end
	if k:find("[%z\1-\31\127]") then return nil end
	local p1 = find(k, "|", 1, true)
	local p2 = p1 and find(k, "|", p1 + 1, true)
	if not p1 or not p2 or p1 == 1 or p2 == p1 + 1 or p2 == #k then return nil end
	local realm, faction, name = sub(k, 1, p1 - 1), sub(k, p1 + 1, p2 - 1), sub(k, p2 + 1)
	if not Enums().FACTIONS[faction] or find(name, "|", 1, true) then return nil end
	return realm, faction, name
end

function Listing.IsValidKey(k) return Listing.ParseKey(k) ~= nil end

-- The `ownerId` of INT-03 and the application id: 8 hexadecimal characters (stored lower case).
local function hex8(v)
	if type(v) ~= "string" or not v:match("^%x%x%x%x%x%x%x%x$") then return nil end
	return lower(v)
end

-- The gate of every record: a valid `k` and a `rev` >= 1, else nil plus a reason.
local function gate(raw, issues)
	if type(raw) ~= "table" then issue(issues, "record", "not a table") return nil end
	if not Listing.IsValidKey(raw.k) then issue(issues, "k", "missing or invalid, record rejected") return nil end
	if not intIn(raw.rev, 1, huge) then issue(issues, "rev", "missing or invalid, record rejected") return nil end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Discord
---------------------------------------------------------------------------------------------------------------------

-- true when `code` is a valid invite code: ^[A-Za-z0-9-]{2,32}$
function Listing.IsValidDiscordCode(code)
	return type(code) == "string" and #code >= LIM.DISCORD_MIN and #code <= LIM.DISCORD_MAX and code:match("^[A-Za-z0-9%-]+$") ~= nil
end

-- The invite code from what the GM typed: the code itself, `discord.gg/x`, `discord.com/invite/x`,
-- `discordapp.com/invite/x`, with or without `https://` and `www.`, and with a trailing `/`, `?query` or `#hash`.
-- Returns the code, or nil plus a reason ("empty", "invalid").
function Listing.ExtractDiscordCode(text)
	if type(text) ~= "string" then return nil, "invalid" end
	local s = trim(stripControls(text, false))
	if s == "" then return nil, "empty" end
	local rest = s:gsub("^[Hh][Tt][Tt][Pp][Ss]?://", ""):gsub("^[Ww][Ww][Ww]%.", "")
	local low = lower(rest)
	local code
	for _, prefix in ipairs({ "discord.gg/", "discord.com/invite/", "discordapp.com/invite/" }) do
		if sub(low, 1, #prefix) == prefix then
			code = sub(rest, #prefix + 1):match("^([^/?#%s]*)")
			break
		end
	end
	if not code then
		if find(rest, "[/.:%s]") then return nil, "invalid" end   -- some other link or text
		code = rest
	end
	if Listing.IsValidDiscordCode(code) then return code end
	return nil, "invalid"
end

---------------------------------------------------------------------------------------------------------------------
-- Summary sub-records
---------------------------------------------------------------------------------------------------------------------

-- `want`: { [classID] = rolesMask }, at most 30 entries, class 0 = any class, masks filtered by role validity.
local function sanitizeWant(v, issues)
	if type(v) ~= "table" then issue(issues, "want", "not a table") return nil end
	local ids = {}
	for id in pairs(v) do
		if intIn(id, 0, 1000) then ids[#ids + 1] = id else issue(issues, "want", "invalid class id dropped") end
	end
	sort(ids)
	local out, n = {}, 0
	for _, id in ipairs(ids) do
		local mask = v[id]
		if not isInt(mask) then
			issue(issues, "want", "invalid role mask dropped")
		else
			local clean = Enums().FilterRoles(id, mask)
			if clean ~= mask then issue(issues, "want", "roles filtered for class " .. id) end
			if clean > 0 then
				if n >= LIM.WANT then issue(issues, "want", "more than 30 entries, rest dropped") break end
				out[id] = clean
				n = n + 1
			end
		end
	end
	if n == 0 then return nil end
	return out
end

-- `tags`: 1 to 3 activity ids, unique, in order. Invalid or repeated ones are dropped, the rest cut to three.
local function sanitizeTags(v, issues)
	if type(v) ~= "table" then issue(issues, "tags", "not a table") return nil end
	local out, seen = {}, {}
	local count = 0
	for i = 1, #v do
		local id = v[i]
		count = count + 1
		if not Enums().IsActivity(id) then
			issue(issues, "tags", "invalid activity dropped")
		elseif seen[id] then
			issue(issues, "tags", "repeated activity dropped")
		elseif #out >= Enums().MAX_TAGS then
			issue(issues, "tags", "more than 3 activities, rest dropped")
			break
		else
			out[#out + 1] = id
			seen[id] = true
		end
	end
	if #out == 0 then issue(issues, "tags", "no valid activity") return nil end
	return out
end

-- Languages: `lang1` is the main one (index), `lang` the mask of all (always includes the main one).
local function sanitizeLanguages(out, raw, issues)
	local E = Enums()
	local main, mask = raw.lang1, raw.lang
	if main ~= nil and not E.LanguageBit(main) then issue(issues, "lang1", "invalid language") main = nil end
	if mask ~= nil then
		if not isInt(mask) or mask < 0 then
			issue(issues, "lang", "invalid mask")
			mask = nil
		elseif mask > E.LANGUAGE_MASK then
			issue(issues, "lang", "unknown languages removed")
			mask = mask % (E.LANGUAGE_MASK + 1)
		end
	end
	if not main and mask and mask > 0 then   -- the main language defaults to the lowest bit of the mask
		for i = 1, E.LANGUAGE_COUNT do
			if floor(mask / E.LanguageBit(i)) % 2 == 1 then main = i break end
		end
	end
	if main then
		local bit = E.LanguageBit(main)
		out.lang1 = main
		mask = mask or 0
		if floor(mask / bit) % 2 ~= 1 then mask = mask + bit end
		out.lang = mask
	elseif raw.lang1 ~= nil or raw.lang ~= nil then
		issue(issues, "lang", "no valid language")
	end
end

local function sanitizeEmblem(v, issues)
	if type(v) ~= "table" then issue(issues, "emb", "not a table") return nil end
	if v.t ~= 1 and v.t ~= 2 then issue(issues, "emb", "invalid type") return nil end
	local out = { t = v.t }
	local pieces = 0
	for _, f in ipairs({ "e", "b", "g" }) do   -- texture file ids of emblem, border, background
		if v[f] ~= nil then
			if intIn(v[f], 0, 4294967295) then out[f] = v[f] pieces = pieces + 1 else issue(issues, "emb", f .. " invalid") end
		end
	end
	for _, f in ipairs({ "ec", "bc", "gc" }) do   -- 24-bit RGB colours
		if v[f] ~= nil then
			if intIn(v[f], 0, 16777215) then out[f] = v[f] else issue(issues, "emb", f .. " invalid") end
		end
	end
	if pieces == 0 then issue(issues, "emb", "no texture piece") return nil end
	return out
end

local function sanitizeStats(v, issues)
	if type(v) ~= "table" then issue(issues, "st", "not a table") return nil end
	local out, any = {}, false
	for _, f in ipairs({ "m", "a7", "u7lo", "u7hi", "max" }) do
		if v[f] ~= nil then
			if intIn(v[f], 0, LIM.STAT) then out[f] = v[f] any = true else issue(issues, "st", f .. " invalid") end
		end
	end
	if out.a7 and out.m and out.a7 > out.m then out.a7 = out.m issue(issues, "st", "a7 above m, clamped") end
	if out.max and out.a7 and out.max > out.a7 then out.max = out.a7 issue(issues, "st", "max above a7, clamped") end
	if out.u7lo and out.u7hi and out.u7lo > out.u7hi then out.u7lo = out.u7hi issue(issues, "st", "u7lo above u7hi, clamped") end
	if type(v.cls) == "table" then
		local ids = {}
		for id in pairs(v.cls) do
			if intIn(id, 1, 1000) then ids[#ids + 1] = id else issue(issues, "st", "invalid class id dropped") end
		end
		sort(ids)
		local cls, n = {}, 0
		for _, id in ipairs(ids) do
			local c = v.cls[id]
			if intIn(c, 1, LIM.STAT) then
				if n >= LIM.WANT then issue(issues, "st", "more than 30 classes, rest dropped") break end
				cls[id] = c
				n = n + 1
			else
				issue(issues, "st", "invalid class count dropped")
			end
		end
		if n > 0 then out.cls = cls any = true end
	elseif v.cls ~= nil then
		issue(issues, "st", "cls not a table")
	end
	return any and out or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Summary (SPEC-03 §2)
---------------------------------------------------------------------------------------------------------------------
function Listing.SanitizeSummary(raw, opts)
	local issues = {}
	if not gate(raw, issues) then return nil, issues end
	local out = { k = raw.k, rev = raw.rev }
	epochField(out, raw, "upd", issues)
	epochField(out, raw, "first", issues)
	if raw.own ~= nil then
		out.own = hex8(raw.own)
		if not out.own then issue(issues, "own", "not 8 hexadecimal characters") end
	end
	textField(out, raw, "sub", LIM.SUB, issues)
	sanitizeLanguages(out, raw, issues)
	if raw.tags ~= nil then out.tags = sanitizeTags(raw.tags, issues) end
	intField(out, raw, "pace", 1, Enums().PACE_COUNT, issues)
	intField(out, raw, "days", 0, 127, issues)
	if raw.t0 ~= nil or raw.t1 ~= nil then
		if intIn(raw.t0, 0, 1439) and intIn(raw.t1, 0, 1439) then
			out.t0, out.t1 = raw.t0, raw.t1
		else
			issue(issues, "t0/t1", "both must be minutes 0-1439")
		end
	end
	intField(out, raw, "rec", 0, 2, issues)
	boolField(out, raw, "apps", issues)
	if raw.want ~= nil then out.want = sanitizeWant(raw.want, issues) end
	boolField(out, raw, "newb", issues)
	intField(out, raw, "minL", 1, maxLevel(opts), issues)
	intField(out, raw, "minI", 0, LIM.MIN_ILVL, issues)
	if raw.emb ~= nil then out.emb = sanitizeEmblem(raw.emb, issues) end
	intField(out, raw, "bg", 1, LIM.BG, issues)
	if raw.st ~= nil then out.st = sanitizeStats(raw.st, issues) end
	epochField(out, raw, "srev", issues)
	return out, issues
end

-- true when a summary has what a listing needs to be shown and filtered: a main language, 1-3 activities and a
-- commitment (SPEC-03 §2: `pace` is required).
function Listing.IsComplete(record)
	return type(record) == "table" and record.lang1 ~= nil and type(record.tags) == "table" and #record.tags >= 1
		and record.pace ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- Detail (SPEC-03 §3)
---------------------------------------------------------------------------------------------------------------------
local function sanitizeContacts(v, issues)
	if type(v) ~= "table" then issue(issues, "cont", "not a table") return nil end
	local out, seen = {}, {}
	for i = 1, #v do
		local name = v[i]
		local clean = type(name) == "string" and trim(stripControls(name, false)) or nil
		if not clean or clean == "" or find(clean, "|", 1, true) or utf8Len(clean) > LIM.CONTACT then
			issue(issues, "cont", "invalid name dropped")
		elseif seen[lower(clean)] then
			issue(issues, "cont", "repeated name dropped")
		elseif #out >= LIM.CONTACTS then
			issue(issues, "cont", "more than 3 names, rest dropped")
			break
		else
			out[#out + 1] = clean
			seen[lower(clean)] = true
		end
	end
	if #out == 0 then return nil end
	return out
end

local function detailFields(out, raw, issues)
	textField(out, raw, "desc", LIM.DESC, issues, true)
	if raw.disc ~= nil then
		if type(raw.disc) == "string" and Listing.IsValidDiscordCode(raw.disc) then
			out.disc = raw.disc
		else
			local code = Listing.ExtractDiscordCode(raw.disc)
			if code then out.disc = code else issue(issues, "disc", "not a valid Discord invite code") end
		end
	end
	if raw.cont ~= nil then out.cont = sanitizeContacts(raw.cont, issues) end
	textField(out, raw, "note", LIM.NOTE, issues)
end

function Listing.SanitizeDetail(raw)
	local issues = {}
	if not gate(raw, issues) then return nil, issues end
	local out = { k = raw.k, rev = raw.rev }
	detailFields(out, raw, issues)
	return out, issues
end

-- Summary and detail fields in one record (the GLIST message).
function Listing.SanitizeFull(raw, opts)
	local out, issues = Listing.SanitizeSummary(raw, opts)
	if not out then return nil, issues end
	detailFields(out, raw, issues)
	return out, issues
end

-- Constructors: the sanitized record for the fields given (the editor builds records this way).
function Listing.NewSummary(fields, opts) return Listing.SanitizeSummary(fields, opts) end
function Listing.NewDetail(fields) return Listing.SanitizeDetail(fields) end

---------------------------------------------------------------------------------------------------------------------
-- Application (SPEC-03 §8)
---------------------------------------------------------------------------------------------------------------------
Listing.APPLICATION_STATES = { sent = true, received = true, accepted = true, declined = true, withdrawn = true, expired = true }

-- "Name-Realm": both parts present, no pipe or control character.
local function validWho(v)
	if type(v) ~= "string" or utf8Len(v) > LIM.WHO then return false end
	if find(v, "[%z\1-\31\127|]") then return false end
	local name, realm = v:match("^([^%-]+)%-(.+)$")
	return name ~= nil and realm ~= nil
end

function Listing.SanitizeApplication(raw, opts)
	local issues = {}
	if type(raw) ~= "table" then issue(issues, "record", "not a table") return nil, issues end
	local id = hex8(raw.id)
	if not id then issue(issues, "id", "missing or invalid, record rejected") return nil, issues end
	if not Listing.IsValidKey(raw.k) then issue(issues, "k", "missing or invalid, record rejected") return nil, issues end
	local out = { id = id, k = raw.k }
	if raw.who ~= nil then
		if validWho(raw.who) then out.who = raw.who else issue(issues, "who", "not Name-Realm") end
	end
	intField(out, raw, "cls", 1, 1000, issues)
	intField(out, raw, "race", 1, 1000, issues)
	intField(out, raw, "lvl", 1, maxLevel(opts), issues)
	intField(out, raw, "ilvl", 0, LIM.MIN_ILVL, issues)
	if raw.roles ~= nil then
		if not isInt(raw.roles) then
			issue(issues, "roles", "not an integer")
		else
			local class = out.cls
			local clean = class and Enums().FilterRoles(class, raw.roles) or Enums().FilterRoles(0, raw.roles)
			if clean ~= raw.roles then issue(issues, "roles", "filtered to the roles the class can play") end
			if clean > 0 then out.roles = clean end
		end
	end
	epochField(out, raw, "at", issues)
	if raw.state ~= nil then
		if type(raw.state) == "string" and Listing.APPLICATION_STATES[raw.state] then out.state = raw.state
		else issue(issues, "state", "unknown state") end
	end
	intField(out, raw, "stateRev", 0, huge, issues)
	if raw.by ~= nil then
		if type(raw.by) == "string" and validWho(raw.by) then out.by = raw.by else issue(issues, "by", "not Name-Realm") end
	end
	return out, issues
end

if ns.addon then ns.addon.Listing = Listing end
