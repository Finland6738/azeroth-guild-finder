-- Mock client, part 1: Lua environment of the WoW client and the plumbing shared by every other mock file.
--
-- Imitates: the Lua 5.1 environment of the game (xpcall with arguments, global helpers such as wipe, tinsert,
-- strsplit, format, the `bit` library, hooksecurefunc, the error handler), `Enum`, and `print`.
-- Dump files: ../WoW-Addons/docs/api/Core-Shared-Libraries/ (helper globals), Enum.* in types/WowForeverAPI.lua.
--
-- Every mock file is a chunk run with `(Mock, H)`: `Mock` is the table tests use (Mock.Fire, Mock.Advance, ...),
-- `H` is the harness (Tests/lib/harness.lua). Persistent "world" state (clock, player, guild, chat) lives in
-- `Mock.world` and survives Mock.Reload(); everything else is rebuilt by a reload, like the client's UI.
local Mock, H = ...
local W = Mock.world

-- The client's xpcall forwards extra arguments (plain Lua 5.1 drops them); AceAddon's safecall relies on it.
local plainXpcall = xpcall
function xpcall(f, handler, ...)
	local n = select("#", ...)
	if n == 0 then return plainXpcall(f, handler) end
	local args = { ... }
	return plainXpcall(function() return f(unpack(args, 1, n)) end, handler)
end

-- Lua errors raised inside handlers are caught like the client does (the error handler shows them, the game goes on).
-- The test library fails a test that leaves errors behind unless it called Mock.ClearErrors().
W.errors = W.errors or {}
Mock.errors = W.errors

local userHandler

local function record(msg)
	W.errors[#W.errors + 1] = { message = tostring(msg), trace = H.traceback(tostring(msg), 3) }
	if userHandler then
		pcall(userHandler, msg)
	end
	return msg
end

function seterrorhandler(fn) userHandler = fn end
function geterrorhandler() return userHandler or record end
function CallErrorHandler(msg) return record(msg) end

-- Runs fn(...) the way the client runs a script handler: an error is recorded, not propagated. Returns ok, results.
function Mock.safecall(fn, ...)
	local args, n = { ... }, select("#", ...)
	return xpcall(function() return fn(unpack(args, 1, n)) end, record)
end
Mock.pcall = Mock.safecall

function Mock.ClearErrors()
	for i = #W.errors, 1, -1 do W.errors[i] = nil end
end

function securecall(fn, ...)
	if type(fn) == "string" then fn = _G[fn] end
	return fn(...)
end
-- securecallfunction(fn, ...): CallbackHandler (AceEvent) calls handlers through it; the mock has no taint to protect.
function securecallfunction(fn, ...) return fn(...) end
function issecure() return true end
function issecurevariable() return true end
function issecretvalue() return false end        -- secret values are modelled by the Compat step (M1.3)
function InCombatLockdown() return W.inCombat == true end

-- String helpers (wowpedia: API strsplit etc.). format is the plain Lua one.
format, gsub, strfind, strlower, strupper, strsub, strlen, strmatch, strrep, strbyte, strchar, strrev =
	string.format, string.gsub, string.find, string.lower, string.upper, string.sub, string.len, string.match,
	string.rep, string.byte, string.char, string.reverse
gmatch = string.gmatch

function strtrim(s, chars)
	chars = chars or " \t\r\n"
	local class = "[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]"
	return (s:gsub("^" .. class .. "+", ""):gsub(class .. "+$", ""))
end

function strsplit(delim, str, pieces)
	local out, pos, n = {}, 1, 0
	local class = "[" .. delim:gsub("[%]%^%-%%]", "%%%0") .. "]"
	while true do
		if pieces and n >= pieces - 1 then break end
		local s = str:find(class, pos)
		if not s then break end
		n = n + 1
		out[n] = str:sub(pos, s - 1)
		pos = s + 1
	end
	out[n + 1] = str:sub(pos)
	return unpack(out, 1, n + 1)
end

function strjoin(delim, ...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	return table.concat(t, delim)
end

function strlenutf8(s)
	local _, count = s:gsub("[^\128-\191]", "")
	return count
end

-- Table helpers.
tinsert, tremove = table.insert, table.remove
function wipe(t)
	for k in pairs(t) do t[k] = nil end
	return t
end
table.wipe = wipe
function tContains(t, value)
	for _, v in ipairs(t) do if v == value then return true end end
	return false
end
function tCount(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end
function CopyTable(src, seen)
	local out = {}
	seen = seen or {}
	seen[src] = out
	for k, v in pairs(src) do
		out[k] = type(v) == "table" and (seen[v] or CopyTable(v, seen)) or v
	end
	return setmetatable(out, getmetatable(src))
end
function Mixin(object, ...)
	for i = 1, select("#", ...) do
		for k, v in pairs((select(i, ...))) do object[k] = v end
	end
	return object
end
function CreateFromMixins(...) return Mixin({}, ...) end

-- hooksecurefunc(table|name, name|hook, hook): runs `hook` after the original with the same arguments.
function hooksecurefunc(a, b, c)
	local tbl, name, hook = _G, a, b
	if type(a) == "table" then tbl, name, hook = a, b, c end
	local original = tbl[name]
	assert(type(original) == "function", "hooksecurefunc: " .. tostring(name) .. " is not a function")
	tbl[name] = function(...)
		local results = { original(...) }
		hook(...)
		return unpack(results)
	end
end

function debugstack() return H.traceback("", 2) end
function GetFramerate() return 60 end

-- The LuaBitOp library of the client (signed 32-bit results), written with arithmetic because Lua 5.1 has no operators.
do
	local MOD = 4294967296
	local function norm(x)
		x = math.floor(x) % MOD
		if x >= 2147483648 then x = x - MOD end
		return x
	end
	local function u(x) return math.floor(x) % MOD end
	local function bitwise(a, b, op)
		a, b = u(a), u(b)
		local result, p = 0, 1
		for _ = 1, 32 do
			local x, y = a % 2, b % 2
			if op(x, y) then result = result + p end
			a, b, p = (a - x) / 2, (b - y) / 2, p * 2
		end
		return result
	end
	local function band(x, y) return x == 1 and y == 1 end
	local function bor(x, y) return x == 1 or y == 1 end
	local function bxor(x, y) return x ~= y end
	local function fold(op)
		return function(first, ...)
			local acc = u(first)
			for i = 1, select("#", ...) do acc = bitwise(acc, (select(i, ...)), op) end
			return norm(acc)
		end
	end
	bit = {
		tobit = norm,
		band = fold(band), bor = fold(bor), bxor = fold(bxor),
		bnot = function(x) return norm(-u(x) - 1) end,
		lshift = function(x, n) return norm(u(x) * 2 ^ (n % 32)) end,
		rshift = function(x, n) return norm(math.floor(u(x) / 2 ^ (n % 32))) end,
		arshift = function(x, n)
			n = n % 32
			return norm(math.floor(norm(x) / 2 ^ n))
		end,
		rol = function(x, n) n = n % 32; x = u(x); return norm(x * 2 ^ n % MOD + math.floor(x / 2 ^ (32 - n))) end,
		ror = function(x, n) n = n % 32; x = u(x); return norm(math.floor(x / 2 ^ n) + x * 2 ^ (32 - n) % MOD) end,
		bswap = function(x)
			x = u(x)
			local b0, b1, b2, b3 = x % 256, math.floor(x / 256) % 256, math.floor(x / 65536) % 256, math.floor(x / 16777216)
			return norm(b0 * 16777216 + b1 * 65536 + b2 * 256 + b3)
		end,
	}
end

-- Enumerations used by the addon. Names and values of Enum.CompressionMethod, CompressionLevel and Base64Variant are
-- in the dump. Enum.SendAddonMessageResult and RegisterAddonMessagePrefixResult are NOT in the dump: the values are
-- the retail ones (the spec records 3, 7 and 8 as observed on Forever); the M0.3 probe reads the real table.
Enum = {
	CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 },
	CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 },
	Base64Variant = { Standard = 0, StandardUrlSafe = 1 },
	SendAddonMessageResult = {
		Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4,
		NotInGroup = 5, TargetRequiresGuild = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9,
		AddOnMessageLockdown = 11, TargetOffline = 12,
	},
	RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1, InvalidPrefix = 2, MaxPrefixes = 3 },
}

-- Chat output: print() and chat frames write to Mock.output (raw lines, colour codes kept), never to the console.
W.output = W.output or {}
Mock.output = W.output

function Mock.ClearOutput()
	for i = #W.output, 1, -1 do W.output[i] = nil end
end

function Mock.Strip(text)
	return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("||", "|"))
end

-- The lines printed so far without colour codes.
function Mock.PlainOutput()
	local lines = {}
	for i, line in ipairs(W.output) do lines[i] = Mock.Strip(line) end
	return lines
end

function print(...)
	local parts = { ... }
	for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
	W.output[#W.output + 1] = table.concat(parts, " ")
end
