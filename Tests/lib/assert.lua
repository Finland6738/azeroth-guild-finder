-- A tiny assertion and test-registration library (describe / it style). No dependencies.
--
-- Loaded by Tests/lib/harness.lua; test files see everything below as globals:
--   describe(name, fn)        groups tests; may nest
--   it(name, fn)              one test; the harness boots a fresh client and the addon before it runs
--   before_boot(fn)           inside a describe: fn(Mock) runs after the mock client is built and before the addon's
--                             files load, for every test of that group (set up the fake guild, player, ... here)
--   eq(actual, expected)      ==            ne(a, b)            ~=
--   truthy(v) / falsy(v)      truthiness    isNil(v) / notNil(v)
--   deepEq(actual, expected)  tables compared by content (keys and values, recursively)
--   near(a, b, epsilon)       numbers within epsilon (default 1e-9)
--   contains(whole, part)     plain substring of a string, or an element of a list
--   matches(text, pattern)    Lua pattern found in text
--   raises(fn, pattern)       fn() must raise; with `pattern` the message must match it; returns the message
--   fail(message)             fails the test
-- Every failure message carries the file and line of the assertion.
local T = {}

-- Readable one-line rendering of a value for failure messages (tables sorted by key, depth limited).
local function show(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "string" then return string.format("%q", v) end
	if t ~= "table" then return tostring(v) end
	if depth >= 3 then return "{...}" end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then return ta < tb end
		if ta == "number" or ta == "string" then return a < b end
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for i, k in ipairs(keys) do
		if i > 12 then parts[#parts + 1] = "..."; break end
		local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or "[" .. show(k, depth + 1) .. "]"
		parts[#parts + 1] = key .. "=" .. show(v[k], depth + 1)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end
T.show = show

local function fail(message)
	error(message, 3)   -- 1 = fail, 2 = the assertion, 3 = the test that called it
end

local function withNote(message, note)
	return note and (note .. ": " .. message) or message
end

function T.fail(message) error(message or "failed", 2) end

function T.eq(actual, expected, note)
	if actual ~= expected then
		fail(withNote("expected " .. show(expected) .. ", got " .. show(actual), note))
	end
end

function T.ne(actual, other, note)
	if actual == other then fail(withNote("expected a value different from " .. show(other), note)) end
end

function T.truthy(v, note)
	if not v then fail(withNote("expected a true value, got " .. show(v), note)) end
end

function T.falsy(v, note)
	if v then fail(withNote("expected a false value, got " .. show(v), note)) end
end

function T.isNil(v, note)
	if v ~= nil then fail(withNote("expected nil, got " .. show(v), note)) end
end

function T.notNil(v, note)
	if v == nil then fail(withNote("expected a value, got nil", note)) end
end

local function sameContent(a, b, seen)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	seen = seen or {}
	if seen[a] == b then return true end
	seen[a] = b
	for k, v in pairs(a) do
		if not sameContent(v, b[k], seen) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

function T.deepEq(actual, expected, note)
	if not sameContent(actual, expected) then
		fail(withNote("expected " .. show(expected) .. ", got " .. show(actual), note))
	end
end

function T.near(actual, expected, epsilon, note)
	epsilon = epsilon or 1e-9
	if type(actual) ~= "number" or math.abs(actual - expected) > epsilon then
		fail(withNote("expected " .. show(expected) .. " (+/- " .. epsilon .. "), got " .. show(actual), note))
	end
end

function T.contains(whole, part, note)
	if type(whole) == "string" then
		if not whole:find(part, 1, true) then
			fail(withNote("expected " .. show(whole) .. " to contain " .. show(part), note))
		end
		return
	end
	for _, v in ipairs(whole) do
		if v == part then return end
	end
	fail(withNote("expected " .. show(whole) .. " to contain " .. show(part), note))
end

function T.matches(text, pattern, note)
	if type(text) ~= "string" or not text:find(pattern) then
		fail(withNote("expected " .. show(text) .. " to match " .. show(pattern), note))
	end
end

function T.raises(fn, pattern, note)
	local ok, err = pcall(fn)
	if ok then fail(withNote("expected an error, but the call returned", note)) end
	err = tostring(err)
	if pattern and not err:find(pattern) then
		fail(withNote("expected an error matching " .. show(pattern) .. ", got " .. show(err), note))
	end
	return err
end

-- Registration ---------------------------------------------------------------------------------------------------
local root, stack

function T._reset()
	root = { kind = "group", name = "", children = {}, setups = {} }
	stack = { root }
	return root
end
T._reset()

function T.describe(name, fn)
	local node = { kind = "group", name = name, children = {}, setups = {} }
	local parent = stack[#stack]
	parent.children[#parent.children + 1] = node
	stack[#stack + 1] = node
	local ok, err = pcall(fn)
	stack[#stack] = nil
	if not ok then error(err, 0) end
end

function T.it(name, fn)
	if type(fn) ~= "function" then error("it(" .. tostring(name) .. "): a function is required", 2) end
	local parent = stack[#stack]
	parent.children[#parent.children + 1] = { kind = "test", name = name, fn = fn }
end

function T.before_boot(fn)
	local node = stack[#stack]
	node.setups[#node.setups + 1] = fn
end

function T._root() return root end

return T
