-- The Lua side of the offline test harness. Tests/run_tests.py loads this chunk with a config table and calls H.run().
--
-- Two Lua "worlds" live in one Lua 5.1 state (lupa.lua51):
--   * the harness (this file, the assertion library, the test files' own helpers) runs in the real globals;
--   * the "game" (mock client, Ace3, the addon) runs in the table E, its global environment, via setfenv.
-- Booting empties E in place and fills it again, so a test that holds `_G` or `Mock` keeps a valid reference, while a
-- value copied out of the game before a reload goes stale, as it would after a real /reload.
--
-- The network simulator (Tests/sim/sim.lua) needs several clients at once: H.newWorld() builds another instance of this
-- harness (own game environment E, own Mock, own SavedVariables) in the same Lua state; the simulator registers each
-- one in H.worlds so a Lua error in any of them fails the test that was running.
--
-- Boot order, as the client does it: the mock client, the addon files in TOC order (each called with the addon name
-- and its private namespace table), the SavedVariables, ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
local cfg = ...

local H = {
	addonName = cfg.addonName,
	tocFields = cfg.tocFields,
	validEvents = cfg.events,
	zcompress = cfg.zcompress,
	zdecompress = cfg.zdecompress,
	traceback = debug.traceback,
	os = os,
}

local E, Mock = {}, {}
H.E, H.Mock = E, Mock

local T = assert(loadstring(cfg.readfile(cfg.assertPath), "@Tests/lib/assert.lua"))()

local STD_GLOBALS = {
	"assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "tonumber", "tostring", "type", "unpack",
	"rawget", "rawset", "rawequal", "setmetatable", "getmetatable", "getfenv", "setfenv", "collectgarbage", "newproxy",
}

local function copyTable(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local function loadChunk(path, display, env)
	local source = cfg.readfile(path)
	if source:sub(1, 3) == "\239\187\191" then source = source:sub(4) end   -- UTF-8 byte order mark
	local chunk, err = loadstring(source, "@" .. display)
	if not chunk then error(err, 0) end
	setfenv(chunk, env or E)
	return chunk
end

-- SavedVariables as the client writes them: a table literal per variable. Functions cannot be saved (the client drops
-- them silently; the harness fails, because it is always a bug in the addon).
local function serialize(value, path, seen)
	local t = type(value)
	if t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("SavedVariables: " .. path .. " is not a finite number", 0)
		end
		return string.format("%.17g", value)
	elseif t == "string" then
		return string.format("%q", value)
	elseif t == "boolean" then
		return tostring(value)
	elseif t == "table" then
		seen = seen or {}
		if seen[value] then error("SavedVariables: " .. path .. " is a circular table", 0) end
		seen[value] = true
		local keys = {}
		for k in pairs(value) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			if ta == "number" or ta == "string" then return a < b end
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, k in ipairs(keys) do
			local kt = type(k)
			if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then
				error("SavedVariables: " .. path .. " has a key of type " .. kt, 0)
			end
			parts[#parts + 1] = "[" .. serialize(k, path .. ".<key>", seen) .. "]=" .. serialize(value[k], path .. "." .. tostring(k), seen)
		end
		seen[value] = nil
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("SavedVariables: " .. path .. " is a " .. t .. ", which cannot be saved", 0)
end
H.serialize = serialize

local function deserialize(text)
	local chunk = assert(loadstring("return " .. text, "=SavedVariables"))
	setfenv(chunk, {})
	return chunk()
end

-- Builds a fresh client and loads the addon.
--   opts.carry     keep Mock.world (clock, player, guild, chat, errors): true on /reload
--   opts.setups    functions called with Mock after the mock client is built, before the addon loads
--   opts.saved     { VariableName = "table literal" } restored before ADDON_LOADED
--   opts.isReload  second argument of PLAYER_ENTERING_WORLD
function H.boot(opts)
	opts = opts or {}
	local world = opts.carry and Mock.world or {}

	setmetatable(E, nil)
	for k in pairs(E) do rawset(E, k, nil) end
	for k in pairs(Mock) do Mock[k] = nil end
	Mock.world = world

	E._G = E
	for _, name in ipairs(STD_GLOBALS) do E[name] = _G[name] end
	E.string, E.table, E.math, E.coroutine = copyTable(string), copyTable(table), copyTable(math), copyTable(coroutine)
	E.loadstring = function(source, name)
		local chunk, err = loadstring(source, name)
		if chunk then setfenv(chunk, E) end
		return chunk, err
	end

	for _, file in ipairs(cfg.mockFiles) do
		loadChunk(file.path, file.name)(Mock, H)
	end
	Mock.Reload = H.reload
	Mock.player.loggedIn = false

	for _, setup in ipairs(opts.setups or {}) do setup(Mock) end

	local ns = {}
	Mock.loadedFiles = {}
	for _, entry in ipairs(cfg.plan) do
		Mock.loadedFiles[#Mock.loadedFiles + 1] = entry.name
		if entry.code then
			local chunk, err = loadstring(entry.code, "@" .. entry.name)
			if not chunk then error(err, 0) end
			setfenv(chunk, E)
			chunk(cfg.addonName, ns)
		else
			loadChunk(entry.path, entry.name)(cfg.addonName, ns)
		end
	end

	-- The catalog sync starts by itself at CHANNEL_READY in the game. Single-client tests switch that off (their
	-- traffic counts stay exact); the simulator switches it on for its clients (Sim.new option `sync`).
	local addonObject = E.AzerothGuildFinder
	if addonObject and addonObject.Sync then addonObject.Sync.AUTO = H.autoSync == true end

	for name, text in pairs(opts.saved or {}) do E[name] = deserialize(text) end

	Mock.Fire("ADDON_LOADED", cfg.addonName)
	Mock.player.loggedIn = true
	Mock.Fire("PLAYER_LOGIN")
	Mock.Fire("PLAYER_ENTERING_WORLD", not opts.isReload, opts.isReload == true)
end

-- /reload: PLAYER_LOGOUT, SavedVariables written out and read back, the Lua state rebuilt, the world (time, player,
-- guild, chat) untouched. Mock.savedText keeps the text that was "written to disk".
function H.reload()
	Mock.Fire("PLAYER_LOGOUT")
	local saved = {}
	for _, name in ipairs(cfg.savedVars) do
		local value = E[name]
		if value ~= nil then saved[name] = serialize(value, name) end
	end
	H.boot({ carry = true, saved = saved, isReload = true })
	Mock.savedText = saved
end

-- Another independent client: a second copy of this harness without test files. Returns its H (H.boot, H.E, H.Mock).
H.worlds = {}
function H.newWorld()
	local chunk, err = loadstring(cfg.readfile(cfg.harnessPath), "@Tests/lib/harness.lua")
	if not chunk then error(err, 0) end
	local sub = copyTable(cfg)
	sub.testFiles, sub.simPath = {}, nil
	return chunk(sub)
end

-- Test files -------------------------------------------------------------------------------------------------------
-- Test files see: the assertion library, Mock, the game's globals, and (while the game is not built, e.g. when the
-- file is first loaded) the plain Lua library.
local plainLua = { string = true, table = true, math = true, coroutine = true }
for _, name in ipairs(STD_GLOBALS) do plainLua[name] = true end

local testEnv = setmetatable({ T = T, Mock = Mock }, {
	__index = function(_, key)
		local v = T[key]
		if v ~= nil then return v end
		v = E[key]
		if v == nil and plainLua[key] then return _G[key] end
		return v
	end,
	__newindex = function(_, key, value) E[key] = value end,
})

-- The simulator module (nil in a sub-harness): test files see it as the global `Sim`.
if cfg.simPath then
	local simEnv = setmetatable({}, { __index = _G })
	rawset(testEnv, "Sim", loadChunk(cfg.simPath, "Tests/sim/sim.lua", simEnv)(H, T))
end

local currentSetups = {}
T.log = function(...)
	local parts = { ... }
	for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
	cfg.log("    " .. table.concat(parts, " ") .. "\n")
end

-- Boots a fresh client again inside a test (new world), keeping the setups of the enclosing groups.
T.boot = function(extraSetup)
	local setups = { unpack(currentSetups) }
	if extraSetup then setups[#setups + 1] = extraSetup end
	H.boot({ setups = setups })
end

local function matchesFilter(name)
	local filter = cfg.filter
	return filter == "" or name:lower():find(filter:lower(), 1, true) ~= nil
end

local function handler(err)
	return { message = tostring(err), trace = debug.traceback("", 2) }
end

local function runTest(fullName, setups, fn, totals)
	currentSetups = setups
	local ok, failure = xpcall(function()
		H.boot({ setups = setups })
		fn()
		local errors = Mock.errors
		if #errors > 0 then
			local extra = #errors > 1 and (" (+" .. (#errors - 1) .. " more)") or ""
			error("Lua error caught by the client's error handler" .. extra .. ": " .. errors[1].message .. "\n" .. errors[1].trace, 0)
		end
	end, handler)
	if ok then
		totals.passed = totals.passed + 1
		cfg.log("  ok    " .. fullName .. "\n")
	else
		totals.failed = totals.failed + 1
		cfg.log("  FAIL  " .. fullName .. "\n")
		for line in (failure.message .. "\n"):gmatch("(.-)\n") do
			if line ~= "" then cfg.log("          " .. line .. "\n") end
		end
		if cfg.verbose then
			cfg.log("          " .. failure.trace:gsub("\n", "\n          ") .. "\n")
		end
	end
end

local function walk(node, path, setups, fileName, totals)
	local own = { unpack(setups) }
	for _, s in ipairs(node.setups) do own[#own + 1] = s end
	for _, child in ipairs(node.children) do
		local childPath = path
		if child.name ~= "" then childPath = (path ~= "" and path .. " > " or "") .. child.name end
		if child.kind == "group" then
			walk(child, childPath, own, fileName, totals)
		else
			local full = fileName .. " > " .. childPath
			if matchesFilter(full) then
				runTest(childPath, own, child.fn, totals)
			end
		end
	end
end

-- Runs every test file; returns passed, failed, files.
function H.run()
	local totals = { passed = 0, failed = 0 }
	local files = 0
	for _, file in ipairs(cfg.testFiles) do
		local root = T._reset()
		local ok, err = pcall(function() loadChunk(file.path, file.name, testEnv)() end)
		cfg.log(file.name .. "\n")
		files = files + 1
		if not ok then
			totals.failed = totals.failed + 1
			cfg.log("  FAIL  (could not load the file)\n          " .. tostring(err) .. "\n")
		else
			walk(root, "", {}, file.name, totals)
		end
	end
	if totals.passed + totals.failed == 0 then
		cfg.log(cfg.filter ~= "" and ("No test matches '" .. cfg.filter .. "'.\n") or "No tests found.\n")
	end
	return totals.passed, totals.failed, files
end

return H
