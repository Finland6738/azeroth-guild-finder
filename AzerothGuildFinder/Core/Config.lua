-- Config: SavedVariables, schema versions, defaults, validation and migrations (SPEC-01 §6, ADR 0011). Lua 5.1.
--   AzerothGuildFinderDB          (account)   = { schemaVersion, accountSecret, catalog[realm][faction], syncAt, tokens,
--                                                 settings }
--   AzerothGuildFinderCharDB      (character) = { schemaVersion, application, officerInbox, ownListing, ui, minimap }
--                                                 application = { recs = { ... } } is owned by Data/Applications.lua
-- Load() runs on ADDON_LOADED (from AGF:OnInitialize): defaults are merged without overwriting anything, old data is
-- migrated step by step, bad values are reset and listed in Config.issues. Data from a NEWER schema is never rewritten:
-- the addon works on a copy and refuses writes (Config:IsReadOnly). Nothing here reads a player or guild name.
local ADDON_NAME, ns = ...
ns = ns or {}
local Config = {}
ns.Config, ns.modules = Config, ns.modules or {}
ns.modules.Config = Config

local type, pairs, ipairs, pcall, tostring, tonumber, next = type, pairs, ipairs, pcall, tostring, tonumber, next
local floor, huge = math.floor, math.huge

Config.SCHEMA_VERSION = 1

-- Development build. A checkout of the repository is one; the BigWigs packager comments out the block between the
-- debug markers below in every packaged build, so a release has DEV = false. Development builds enable
-- /gf debug announce and keep the test listings it sends; release builds ignore test listings (Net/Sync.lua).
Config.DEV = false
--@debug@
Config.DEV = true
--@end-debug@
Config.VARIABLES = { account = "AzerothGuildFinderDB", char = "AzerothGuildFinderCharDB" }

-- Limits of SPEC-01 §6, enforced by the modules that own the data (catalog, inbox).
Config.LIMITS = {
	LISTINGS_PER_REALM_FACTION = 500,
	APPLICATIONS_PER_INBOX = 200,
	DETAIL_CACHE_DAYS = 60,
	DETAIL_CACHE_SECONDS = 60 * 86400,
}

Config.defaults = {
	account = {
		schemaVersion = Config.SCHEMA_VERSION,
		accountSecret = "",            -- created once on first load, never sent anywhere
		catalog = {},                  -- [realm][faction] = { ... } (SPEC-03)
		syncAt = {},                   -- ["realm|faction"] = time of the last full catalog sync (SPEC-02 §6)
		tokens = { mine = {}, heard = {} },   -- GTOK store (Data/Stats.lua, SPEC-03 §4): tokens heard, own characters as hashes
		settings = {
			minimapButton = true,
			notifyIcon = true,
			onlyWhenPending = false,
			sound = true,
			shareAltCount = true,
			uiScale = 1.0,
			windowPos = {},            -- [windowName] = { point, relPoint, x, y }
		},
	},
	char = {
		schemaVersion = Config.SCHEMA_VERSION,
		officerInbox = {},             -- [guildKey] = { ... }
		ownListing = { draft = nil, published = nil, pubAt = nil },   -- Data/OwnListing.lua
		ui = { filters = {} },         -- notifyPos, mainPos: nil until the user moves them; appsSeenAt: when the Applications panel was last left
		minimap = { hide = false },    -- LibDBIcon format
	},
}

-- Rules by path (scope first). type: boolean | number | string | table | timestamp. number: min, max, integer.
-- string: enum, pattern, maxLen. optional: nil is allowed. A value that breaks a rule is reset to its default
-- (nil for optional values). timestamp: integer epoch >= 0; one in the future is clamped to now, not reset.
local function posRule() return { type = "table", optional = true, validate = function(v) return Config.IsPos(v) end } end
Config.rules = {
	["account.schemaVersion"] = { type = "number", min = 0, integer = true },
	["account.accountSecret"] = { type = "string", pattern = "^%x+$", minLen = 32, maxLen = 32 },
	["account.catalog"] = { type = "table" },
	["account.syncAt"] = { type = "table" },
	["account.tokens"] = { type = "table" },
	["account.tokens.mine"] = { type = "table" },
	["account.tokens.heard"] = { type = "table" },
	["account.settings"] = { type = "table" },
	["account.settings.minimapButton"] = { type = "boolean" },
	["account.settings.notifyIcon"] = { type = "boolean" },
	["account.settings.onlyWhenPending"] = { type = "boolean" },
	["account.settings.sound"] = { type = "boolean" },
	["account.settings.shareAltCount"] = { type = "boolean" },
	["account.settings.uiScale"] = { type = "number", min = 0.5, max = 2.0 },
	["account.settings.windowPos"] = { type = "table" },
	["char.schemaVersion"] = { type = "number", min = 0, integer = true },
	["char.application"] = { type = "table", optional = true },
	["char.officerInbox"] = { type = "table" },
	["char.ownListing"] = { type = "table" },
	["char.ownListing.draft"] = { type = "table", optional = true },
	["char.ownListing.published"] = { type = "table", optional = true },
	["char.ownListing.pubAt"] = { type = "timestamp", optional = true },
	["char.ui"] = { type = "table" },
	["char.ui.filters"] = { type = "table" },
	["char.ui.notifyPos"] = posRule(),
	["char.ui.mainPos"] = posRule(),
	["char.ui.appsSeenAt"] = { type = "timestamp", optional = true },
	["char.minimap"] = { type = "table" },
	["char.minimap.hide"] = { type = "boolean" },
}

-- Migrations: Config.migrations[scope][n] brings data from version n-1 to n. Each step must be idempotent (running it
-- on data that already has the new shape changes nothing). Version 1 is the first schema: data without a version is
-- treated as 0 and only needs the defaults and the rules, so step 1 has nothing to do.
Config.migrations = {
	account = { [1] = function(db) end },
	char = { [1] = function(db) end },
}

Config.issues = {}          -- problems found and fixed by the last Load (text only, no names)
Config.readOnly = {}        -- readOnly[scope] = true: newer schema (or failed migration), writes refused
Config.db = {}              -- Config.db.account / Config.db.char: the tables the addon works on
Config.loadedVersion = {}   -- the schema version found in the saved data (0 for none or damaged)

---------------------------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------------------------
local function copy(value, seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
	return out
end
Config.Copy = copy

local function issue(text)
	Config.issues[#Config.issues + 1] = text
end

local function isFiniteNumber(v)
	return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function now()
	if ns.Compat and ns.Compat.ServerTime then return ns.Compat.ServerTime() end
	return time()
end

-- A saved window position: { point, relPoint, x, y } (relPoint optional).
function Config.IsPos(v)
	return type(v) == "table" and type(v.point) == "string" and isFiniteNumber(v.x) and isFiniteNumber(v.y)
		and (v.relPoint == nil or type(v.relPoint) == "string")
end

local function split(path)
	local parts = {}
	for part in tostring(path):gmatch("[^.]+") do parts[#parts + 1] = part end
	return parts
end

-- The table that holds `path` (below the scope root) and the key: nil when a parent is missing or not a table.
local function locate(root, parts, from)
	local node = root
	for i = from, #parts - 1 do
		node = node[parts[i]]
		if type(node) ~= "table" then return nil end
	end
	return node, parts[#parts]
end

-- nil when `value` satisfies `rule`, else the reason. Timestamps are checked for shape only (clamping is separate).
local function violation(rule, value)
	if value == nil then return (not rule.optional) and "missing" or nil end
	local t = rule.type
	if t == "timestamp" then
		if not isFiniteNumber(value) or value < 0 or value ~= floor(value) then return "not an epoch" end
		return nil
	end
	if type(value) ~= t then return "expected " .. t .. ", got " .. type(value) end
	if t == "number" then
		if not isFiniteNumber(value) then return "not a finite number" end
		if rule.integer and value ~= floor(value) then return "not an integer" end
		if rule.min and value < rule.min then return "below " .. rule.min end
		if rule.max and value > rule.max then return "above " .. rule.max end
	elseif t == "string" then
		if rule.enum then
			local found = false
			for _, option in ipairs(rule.enum) do if option == value then found = true end end
			if not found then return "not an allowed value" end
		end
		if rule.minLen and #value < rule.minLen then return "too short" end
		if rule.maxLen and #value > rule.maxLen then return "too long" end
		if rule.pattern and not value:find(rule.pattern) then return "bad format" end
	elseif t == "table" and rule.validate and not rule.validate(value) then
		return "bad shape"
	end
	return nil
end

local function defaultAt(scope, path)
	local node = Config.defaults[scope]
	for _, part in ipairs(split(path)) do
		if type(node) ~= "table" then return nil end
		node = node[part]
	end
	return copy(node)
end

local function randomSecret()
	local seed = (ns.Compat and ns.Compat.ServerTime and ns.Compat.ServerTime() or time()) + floor((GetTime and GetTime() or 0) * 1000)
	math.randomseed(seed)
	local hex = {}
	for i = 1, 32 do hex[i] = ("%x"):format(math.random(0, 15)) end
	return table.concat(hex)
end

-- Fills what is missing from `defaults`, recursively; an existing value is never overwritten.
local function mergeDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = copy(v)
		elseif type(v) == "table" and type(db[k]) == "table" then
			mergeDefaults(db[k], v)
		end
	end
end
Config.MergeDefaults = mergeDefaults

---------------------------------------------------------------------------------------------------------------------
-- Sanitize: rules, extra checks, clamping
---------------------------------------------------------------------------------------------------------------------
-- The catalog is { [realm] = { [faction] = { ... } } }: anything else in the first two levels is dropped.
local function sanitizeCatalog(db)
	local catalog = db.catalog
	if type(catalog) ~= "table" then return end
	for realm, factions in pairs(catalog) do
		if type(realm) ~= "string" or type(factions) ~= "table" then
			catalog[realm] = nil
			issue("account.catalog: dropped a malformed realm entry")
		else
			for faction, entries in pairs(factions) do
				if type(faction) ~= "string" or type(entries) ~= "table" then
					factions[faction] = nil
					issue("account.catalog: dropped a malformed faction entry")
				end
			end
		end
	end
end

local function sortedRulePaths(scope)
	local paths, prefix = {}, scope .. "."
	for path in pairs(Config.rules) do
		if path:sub(1, #prefix) == prefix then paths[#paths + 1] = path end
	end
	table.sort(paths, function(a, b)   -- parents first, so a reset parent is validated again below
		local da, db = select(2, a:gsub("%.", "")), select(2, b:gsub("%.", ""))
		if da ~= db then return da < db end
		return a < b
	end)
	return paths
end

-- Brings `db` (the working table of `scope`) within the rules. Returns the number of fixes.
function Config.Sanitize(scope, db)
	local before = #Config.issues
	local nowValue = now()
	for _, path in ipairs(sortedRulePaths(scope)) do
		local rule = Config.rules[path]
		local parts = split(path)
		local parent, key = locate(db, parts, 2)
		if parent then
			local value = parent[key]
			local why = violation(rule, value)
			if why then
				if path == "account.accountSecret" then
					parent[key] = randomSecret()
					if value ~= nil and value ~= "" then issue(path .. ": replaced (" .. why .. ")") end
				else
					parent[key] = defaultAt(scope, table.concat(parts, ".", 2))
					issue(path .. ": reset (" .. why .. ")")
				end
			elseif rule.type == "timestamp" and value and value > nowValue then
				parent[key] = nowValue
				issue(path .. ": future time clamped")
			end
		end
	end
	if scope == "account" then sanitizeCatalog(db) end
	return #Config.issues - before
end

---------------------------------------------------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------------------------------------------------
local function schemaOf(raw)
	local v = raw.schemaVersion
	if v == nil then return 0 end
	if isFiniteNumber(v) and v >= 0 and v == floor(v) then return v end
	return nil   -- damaged
end

local function isEmpty(t) return next(t) == nil end

-- Runs the steps from..target on `db`. Returns true, or false and the reason (db may be half changed: use a copy).
local function migrate(scope, db, from, target)
	local steps = Config.migrations[scope] or {}
	for n = from + 1, target do
		local step = steps[n]
		if step then
			local ok, err = pcall(step, db)
			if not ok then return false, "step " .. n .. " failed: " .. tostring(err):sub(1, 100) end
		end
		db.schemaVersion = n
	end
	return true
end

local function loadScope(scope)
	local var = Config.VARIABLES[scope]
	local raw = _G[var]
	local target = Config.SCHEMA_VERSION
	Config.readOnly[scope] = nil
	local work

	if type(raw) ~= "table" then
		if raw ~= nil then issue(var .. ": not a table, replaced by defaults") end
		raw = {}
		_G[var] = raw
		Config.loadedVersion[scope] = target
		work = raw
		raw.schemaVersion = target
	else
		local version = schemaOf(raw)
		if version == nil then
			issue(var .. ": damaged schemaVersion, treated as 0")
			version = 0
		elseif version == 0 and raw.schemaVersion == nil and not isEmpty(raw) then
			issue(var .. ": schemaVersion lost, treated as 0")
		end
		Config.loadedVersion[scope] = version

		if version > target then
			-- Newer addon wrote this: read it, never rewrite it. All work happens on a copy.
			Config.readOnly[scope] = true
			issue(("%s: schema %d is newer than %d, read-only"):format(var, version, target))
			work = copy(raw)
			work.schemaVersion = target
		elseif version < target and not (version == 0 and isEmpty(raw)) then
			local trial = copy(raw)
			local ok, why = migrate(scope, trial, version, target)
			if ok then
				-- success: apply in place so the saved table keeps its identity
				for k in pairs(raw) do raw[k] = nil end
				for k, v in pairs(trial) do raw[k] = v end
				work = raw
			else
				Config.readOnly[scope] = true
				issue(var .. ": migration " .. why .. ", read-only")
				work = copy(raw)
				work.schemaVersion = target
			end
		else
			work = raw
		end
		work.schemaVersion = target
	end

	mergeDefaults(work, Config.defaults[scope])
	Config.Sanitize(scope, work)
	Config.db[scope] = work
end

-- Loads both variables. Safe to call again (tests, /reload): the second run changes nothing.
function Config:Load()
	Config.issues = {}
	for _, scope in ipairs({ "account", "char" }) do loadScope(scope) end
	self.loaded = true
	return #Config.issues == 0
end

function Config:IsReadOnly(scope)
	if scope then return Config.readOnly[scope] == true end
	return Config.readOnly.account == true or Config.readOnly.char == true
end

---------------------------------------------------------------------------------------------------------------------
-- Get / Set by path: "account.settings.uiScale", "char.minimap.hide"
---------------------------------------------------------------------------------------------------------------------
function Config:Get(path)
	local parts = split(path)
	local node = Config.db[parts[1]]
	for i = 2, #parts do
		if type(node) ~= "table" then return nil end
		node = node[parts[i]]
	end
	return node
end

-- Validated write. Returns true, or false and a reason ("unknown path", "read-only", or the rule violation).
function Config:Set(path, value)
	local parts = split(path)
	local scope = parts[1]
	local rule = Config.rules[table.concat(parts, ".")]
	if not rule or not Config.db[scope] then return false, "unknown path" end
	if Config.readOnly[scope] then return false, "read-only" end
	if #parts < 2 or table.concat(parts, ".") == scope .. ".schemaVersion" then return false, "protected" end
	local why = violation(rule, value)
	if why then return false, why end
	local parent, key = locate(Config.db[scope], parts, 2)
	if not parent then return false, "parent missing" end
	if rule.type == "timestamp" and value > now() then value = now() end
	parent[key] = value
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- /gf debug
---------------------------------------------------------------------------------------------------------------------
function Config:DebugLines()
	local lines = {}
	for _, scope in ipairs({ "account", "char" }) do
		lines[#lines + 1] = ("%s: schema found %s, current %d%s"):format(Config.VARIABLES[scope],
			tostring(Config.loadedVersion[scope]), Config.SCHEMA_VERSION,
			Config.readOnly[scope] and " - READ-ONLY (never rewritten)" or "")
	end
	local realms, listings = 0, 0
	for _, factions in pairs((Config.db.account or {}).catalog or {}) do
		realms = realms + 1
		for _, entries in pairs(factions) do for _ in pairs(entries) do listings = listings + 1 end end
	end
	lines[#lines + 1] = ("Catalog: %d realm(s), %d entries (limit %d per realm and faction)"):format(
		realms, listings, Config.LIMITS.LISTINGS_PER_REALM_FACTION)
	lines[#lines + 1] = #Config.issues == 0 and "Saved data: no problems" or
		("Saved data: %d problem(s) fixed or noted:"):format(#Config.issues)
	for i, text in ipairs(Config.issues) do
		if i > 15 then lines[#lines + 1] = "  ..." break end
		lines[#lines + 1] = "  " .. text
	end
	return lines
end

if ns.addon then
	ns.addon.Config = Config
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Saved data", function() return Config:DebugLines() end)
	end
end
