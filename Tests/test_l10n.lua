-- Localization readiness (M5.3, ADR 0016): every visible string goes through L[...]; this audit fails on hard-coded
-- user-visible strings in UI/, on L keys that are used but missing from enUS, and on enUS keys nothing uses.
-- Exceptions: a "-- l10n-ok: reason" comment on the line of the string (or the line above) marks it as not visible
-- (event name, template, texture path, debug output). See docs/l10n.md.

local function sources()
	local out = {}
	for _, name in ipairs(Mock.loadedFiles) do
		if name:match("^AzerothGuildFinder/") and not name:match("/Libs/") and not name:match("/Locale/") and name:match("%.lua$") then
			out[#out + 1] = name
		end
	end
	return out
end

-- Splits Lua 5.1 source into tokens: { t = "str"|"name"|"op"|"num", v = value, line = n }, plus the comments per line.
local function tokenize(src)
	local toks, comments, i, line, n = {}, {}, 1, 1, #src
	while i <= n do
		local c = src:sub(i, i)
		if c == "\n" then line = line + 1; i = i + 1
		elseif c:match("%s") then i = i + 1
		elseif src:sub(i, i + 1) == "--" then
			local eqs = src:match("^%-%-%[(=*)%[", i)
			local e
			if eqs then
				local _, ce = src:find("]" .. eqs .. "]", i, true)
				e = ce or n
				comments[line] = (comments[line] or "") .. src:sub(i, e)
				for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
			else
				e = (src:find("\n", i, true) or n + 1) - 1
				comments[line] = (comments[line] or "") .. src:sub(i, e)
			end
			i = e + 1
		elseif c == '"' or c == "'" then
			local j, buf = i + 1, {}
			while j <= n do
				local d = src:sub(j, j)
				if d == "\\" then buf[#buf + 1] = src:sub(j, j + 1); j = j + 2
				elseif d == c then break
				else buf[#buf + 1] = d; j = j + 1 end
			end
			toks[#toks + 1] = { t = "str", v = table.concat(buf), line = line }
			i = j + 1
		elseif src:match("^%[=*%[", i) then
			local eqs = src:match("^%[(=*)%[", i)
			local _, ce = src:find("]" .. eqs .. "]", i, true)
			ce = ce or n
			toks[#toks + 1] = { t = "str", v = src:sub(i + #eqs + 2, ce - #eqs - 2), line = line }
			for _ in src:sub(i, ce):gmatch("\n") do line = line + 1 end
			i = ce + 1
		elseif c:match("[%a_]") then
			local w = src:match("^[%w_]+", i)
			toks[#toks + 1] = { t = "name", v = w, line = line }
			i = i + #w
		elseif c:match("%d") then
			local w = src:match("^[%w%.]+", i)
			toks[#toks + 1] = { t = "num", v = w, line = line }
			i = i + #w
		else
			toks[#toks + 1] = { t = "op", v = c, line = line }
			i = i + 1
		end
	end
	return toks, comments
end

local cache = {}
local function parsed(name)
	if not cache[name] then
		local toks, comments = tokenize(Mock.ReadSource(name))
		cache[name] = { toks = toks, comments = comments, src = Mock.ReadSource(name) }
	end
	return cache[name]
end

---------------------------------------------------------------------------------------------------------------------
-- Keys
local LOCALE_FILE = "AzerothGuildFinder/Locale/enUS.lua"

local function keysOfLocale()
	local keys, list = {}, {}
	for k in ("\n" .. Mock.ReadSource(LOCALE_FILE)):gmatch('\nL%["([^"]+)"%] = ') do
		keys[k] = true
		list[#list + 1] = k
	end
	return keys, list
end

local function isKeyLike(s) return s:match("^[A-Z][A-Z0-9]*_[A-Za-z0-9_]*$") ~= nil or s:match("^[A-Z][A-Z0-9]+$") ~= nil end

-- Static keys: L["KEY"] and L("KEY"). Prefixes / suffixes: "PREFIX_" .. x and x .. "_SUFFIX" built keys. Literals: every
-- key-shaped string literal in the code (keys kept in data tables, for example option.label = "APPS_OPT_X").
local function usage()
	local static, prefixes, suffixes, literals = {}, {}, {}, {}
	for _, name in ipairs(sources()) do
		local toks = parsed(name).toks
		for i, t in ipairs(toks) do
			if t.t == "str" then
				local p, pp, nx = toks[i - 1], toks[i - 2], toks[i + 1]
				if isKeyLike(t.v) then
					literals[t.v] = literals[t.v] or (name .. ":" .. t.line)
					if p and nx and pp and pp.v == "L" and ((p.v == "[" and nx.v == "]") or (p.v == "(" and nx.v == ")")) then
						static[#static + 1] = { key = t.v, where = name .. ":" .. t.line }
					end
				end
				if nx and nx.v == "." and toks[i + 2] and toks[i + 2].v == "." and t.v:match("^[A-Z][A-Z0-9_]*_$") then prefixes[t.v] = true end
				if p and p.v == "." and pp and pp.v == "." and t.v:match("^_[A-Z0-9_]+$") then suffixes[t.v] = true end
			end
		end
	end
	return static, prefixes, suffixes, literals
end

describe("L keys", function()
	it("enUS defines every key once, with a non-empty string and an upper-case name", function()
		local _, list = keysOfLocale()
		local seen = {}
		for _, k in ipairs(list) do
			falsy(seen[k], "duplicate key " .. k)
			seen[k] = true
			truthy(k:match("^[A-Z][A-Za-z0-9_]*$"), "bad key name " .. k)
		end
		truthy(#list > 100, "keys found: " .. #list)
		for k, v in ("\n" .. Mock.ReadSource(LOCALE_FILE)):gmatch('\nL%["([^"]+)"%] = "(.-)"\r?\n') do truthy(v ~= "", "empty value for " .. k) end
	end)

	it("every key used in code exists in enUS", function()
		local locale = keysOfLocale()
		local static, prefixes, suffixes = usage()
		truthy(#static > 100, "static uses: " .. #static)
		for _, u in ipairs(static) do truthy(locale[u.key], u.where .. ": L key " .. u.key .. " is not in enUS") end
		prefixes.AGF_ = nil -- frame names, not keys
		for prefix in pairs(prefixes) do
			local found = false
			for k in pairs(locale) do if k:sub(1, #prefix) == prefix then found = true break end end
			truthy(found, 'no key starts with the prefix "' .. prefix .. '" built in code')
		end
		for suffix in pairs(suffixes) do
			local found = false
			for k in pairs(locale) do if k:sub(-#suffix) == suffix then found = true break end end
			truthy(found, 'no key ends with the suffix "' .. suffix .. '" built in code')
		end
	end)

	it("no key of enUS is unused (used = L[...] / L(...), a key-shaped literal in code, or a built prefix / suffix)", function()
		local _, list = keysOfLocale()
		local _, prefixes, suffixes, literals = usage()
		local unused = {}
		for _, k in ipairs(list) do
			local used = literals[k] ~= nil
			for p in pairs(prefixes) do if k:sub(1, #p) == p then used = true end end
			for s in pairs(suffixes) do if k:sub(-#s) == s then used = true end end
			if not used then unused[#unused + 1] = k end
		end
		eq(#unused, 0, "unused enUS keys: " .. table.concat(unused, ", "))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Hard-coded visible strings in UI/
local VISIBLE_SLOTS = {
	SetText = true, SetFormattedText = true, text = true, label = true, title = true, placeholder = true, hint = true,
	help = true, tip = true, tooltip = true, header = true, body = true, desc = true, description = true, subtitle = true,
	AddLine = true, AddDoubleLine = true, SetTooltip = true, SetTitle = true, SetLabel = true, Print = true, say = true,
	print = true,
}

-- A literal with no word of two letters (spacing, separators, numbers, format only) is never visible text of its own.
local function hasWords(s)
	local t = s:gsub("%%[%d%.%-]*[a-zA-Z%%]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return t:match("%a%a") ~= nil
end

-- Debug output is English only (it goes into bug reports): the body of a DebugLines function (up to the "end" in column 0)
-- and the AddDebugSection call lines are exempt without a comment, and so is a region between "-- l10n-off: reason" and
-- "-- l10n-on".
local function debugLines(src)
	local exempt, inside, off, n = {}, false, false, 0
	for line in (src .. "\n"):gmatch("(.-)\n") do
		n = n + 1
		if line:match("^function [%w_.:]*DebugLines%(") then inside = true end
		if line:find("l10n-off:", 1, true) then off = true end
		if inside or off or line:find("AddDebugSection", 1, true) then exempt[n] = true end
		if line:find("l10n-on", 1, true) then off = false end
		if inside and line:match("^end") then inside = false end
	end
	return exempt
end

local function audit(name)
	local data, findings = parsed(name), {}
	local toks = data.toks
	local exempt = debugLines(data.src)
	for i, t in ipairs(toks) do
		if t.t == "str" and hasWords(t.v) and not exempt[t.line] and not isKeyLike(t.v) and not t.v:match("^#%x+$") then
			local p, pp = toks[i - 1], toks[i - 2]
			local inL = p and (p.v == "[" or p.v == "(") and pp and pp.v == "L"
			local slot = false
			if p and p.v == "(" and pp and VISIBLE_SLOTS[pp.v] then slot = true end
			if p and p.v == "=" and pp and VISIBLE_SLOTS[pp.v] then slot = true end
			local multiword = t.v:match("%a%a+%s+%a%a") ~= nil
			if not inL and (slot or multiword) then
				local c = (data.comments[t.line] or "") .. (data.comments[t.line - 1] or "")
				if not c:find("l10n-ok:", 1, true) then findings[#findings + 1] = name .. ":" .. t.line .. ': "' .. t.v .. '"' end
			end
		end
	end
	return findings
end

describe("hard-coded visible strings", function()
	it("the tokenizer reads strings, comments and long strings", function()
		local toks, comments = tokenize('local a = "x\\"y" -- c "no"\nlocal b = [[long\nstring]] --[[ block\n]] local c = \'s\'')
		local strs = {}
		for _, t in ipairs(toks) do if t.t == "str" then strs[#strs + 1] = t.v end end
		eq(#strs, 4 - 1)
		eq(strs[1], 'x\\"y')
		eq(strs[2], "long\nstring")
		eq(strs[3], "s")
		truthy(comments[1]:find("no", 1, true))
	end)

	it("the audit detects a hard-coded string and honors the exception comment", function()
		local function run(src)
			local toks, comments = tokenize(src)
			cache.x = { toks = toks, comments = comments, src = src }
			local f = audit("x")
			cache.x = nil
			return #f
		end
		eq(run('frame.title:SetText("Hello")'), 1)
		eq(run('local t = { label = "Close" }'), 1)
		eq(run('local s = "two words"'), 1)
		eq(run('frame.title:SetText(L["HELLO"])'), 0)
		eq(run('local t = { label = "Close" } -- l10n-ok: test'), 0)
		eq(run('-- l10n-ok: test\nlocal t = { label = "Close" }'), 0)
		eq(run('f:SetPoint("TOPLEFT", 0, 0)'), 0)
		eq(run('local s = "%d / %d"'), 0)
		eq(run('-- "two words" in a comment'), 0)
		eq(run('local k = { title = "SETTINGS_WINDOW", c = "#ffdc7a" }'), 0)
		eq(run('-- l10n-off: x\nlocal a = "two words"\n-- l10n-on\nlocal b = "two words"'), 1)
		eq(run('function Foo:DebugLines()\n\treturn { "two words" }\nend\nlocal s = "two words"'), 1)
	end)

	it("no file of UI/ has a hard-coded visible string (mark a non-visible one with '-- l10n-ok: reason')", function()
		local all = {}
		for _, name in ipairs(sources()) do
			if name:match("^AzerothGuildFinder/UI/") then
				for _, f in ipairs(audit(name)) do all[#all + 1] = f end
			end
		end
		eq(#all, 0, "hard-coded strings:\n" .. table.concat(all, "\n"))
	end)
end)
