-- Normalize: name keys for ordering and search (SPEC-03 §7), UTF-8 helpers and a 32-bit hash. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local N = {}
ns.Normalize, ns.modules = N, ns.modules or {}
ns.modules.Normalize = N

local byte, char, sub, lower, find, concat = string.byte, string.char, string.sub, string.lower, string.find, table.concat
N.MIN_QUERY = 3

---------------------------------------------------------------------------------------------------------------------
-- UTF-8
---------------------------------------------------------------------------------------------------------------------

-- Number of characters (every byte that is not a continuation byte starts one).
function N.Utf8Len(s)
	if type(s) ~= "string" then return 0 end
	local n = 0
	for i = 1, #s do
		local b = byte(s, i)
		if b < 0x80 or b >= 0xC0 then n = n + 1 end
	end
	return n
end

-- Byte offset where each character starts; the last entry is #s + 1.
local function starts(s)
	local list = {}
	for i = 1, #s do
		local b = byte(s, i)
		if b < 0x80 or b >= 0xC0 then list[#list + 1] = i end
	end
	list[#list + 1] = #s + 1
	return list
end

-- Characters i..j (1-based, inclusive, negative counts from the end, like string.sub).
function N.Utf8Sub(s, i, j)
	if type(s) ~= "string" then return "" end
	local list = starts(s)
	local len = #list - 1
	i, j = i or 1, j or -1
	if i < 0 then i = len + i + 1 end
	if j < 0 then j = len + j + 1 end
	if i < 1 then i = 1 end
	if j > len then j = len end
	if i > j then return "" end
	return sub(s, list[i], list[j + 1] - 1)
end

-- Decodes the code point at byte i: codepoint, next index. An invalid byte comes back as a negative number, which maps to no letter.
local function decode(s, i)
	local b = byte(s, i)
	if b < 0x80 then return b, i + 1 end
	local n = b >= 0xF0 and 3 or b >= 0xE0 and 2 or b >= 0xC0 and 1 or 0
	if n == 0 or i + n > #s then return -b, i + 1 end
	local cp = b - (n == 3 and 0xF0 or n == 2 and 0xE0 or 0xC0)
	for k = 1, n do
		local c = byte(s, i + k)
		if c < 0x80 or c >= 0xC0 then return -b, i + 1 end
		cp = cp * 64 + (c - 0x80)
	end
	return cp, i + n + 1
end

---------------------------------------------------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------------------------------------------------

-- Latin letters with marks (Latin-1, Latin Extended-A/B and common Vietnamese forms) folded to a-z.
local FOLD = {}
local function add(base, letters)
	local i = 1
	while i <= #letters do
		local cp, nextI = decode(letters, i)
		FOLD[cp] = base
		i = nextI
	end
end
add("a", "àáâãäåāăąǎǟǡǻȁȃȧạảấầẩẫậắằẳẵặÀÁÂÃÄÅĀĂĄǍǞǠǺȀȂȦẠẢẤẦẨẪẬẮẰẲẴẶ")
add("ae", "æǣǽÆǢǼ")
add("b", "ƀɓḃḅḇƁḂḄḆ")
add("c", "çćĉċčƈḉÇĆĈĊČƇḈ")
add("d", "ďđðḋḍḏḑḓĎĐÐḊḌḎḐḒ")
add("e", "èéêëēĕėęěȅȇȩẹẻẽếềểễệḕḗḙḛḝÈÉÊËĒĔĖĘĚȄȆȨẸẺẼẾỀỂỄỆḔḖḘḚḜ")
add("f", "ƒḟḞ")
add("g", "ĝğġģǥǧǵḡĜĞĠĢǤǦǴḠ")
add("h", "ĥħȟḣḥḧḩḫĤĦȞḢḤḦḨḪ")
add("i", "ìíîïĩīĭįıǐȉȋḭḯỉịÌÍÎÏĨĪĬĮİǏȈȊḬḮỈỊ")
add("j", "ĵǰĴ")
add("k", "ķƙǩḱḳḵĶƘǨḰḲḴ")
add("l", "ĺļľŀłḷḹḻḽĹĻĽĿŁḶḸḺḼ")
add("m", "ḿṁṃḾṀṂ")
add("n", "ñńņňŉǹṅṇṉṋÑŃŅŇǸṄṆṈṊ")
add("o", "òóôõöøōŏőơǒǫǭǿȍȏȫȭȯȱọỏốồổỗộớờởỡợṍṏṑṓÒÓÔÕÖØŌŎŐƠǑǪǬǾȌȎȪȬȮȰỌỎỐỒỔỖỘỚỜỞỠỢṌṎṐṒ")
add("oe", "œŒ")
add("p", "ƥṕṗṔṖ")
add("r", "ŕŗřȑȓṙṛṝṟŔŖŘȐȒṘṚṜṞ")
add("s", "śŝşšșṡṣṥṧṩŚŜŞŠȘṠṢṤṦṨ")
add("ss", "ß")
add("t", "ţťŧțṫṭṯṱŢŤŦȚṪṬṮṰ")
add("u", "ùúûüũūŭůűųưǔǖǘǚǜȕȗụủứừửữựṳṵṷṹṻÙÚÛÜŨŪŬŮŰŲƯǓǕǗǙǛȔȖỤỦỨỪỬỮỰṲṴṶṸṺ")
add("v", "ṽṿṼṾ")
add("w", "ŵẁẃẅẇẉẘŴẀẂẄẆẈ")
add("x", "ẋẍẊẌ")
add("y", "ýÿŷȳẏỳỵỷỹẙÝŶŸȲẎỲỴỶỸ")
add("z", "źżžƶẑẓẕŹŻŽƵẐẒẔ")

-- Folds the accents, lowercases and drops everything that is not a-z.
function N.SortKey(name)
	if type(name) ~= "string" or name == "" then return "" end
	local out, n, i, len = {}, 0, 1, #name
	while i <= len do
		local cp, nextI = decode(name, i)
		local piece
		if cp < 0 then
			piece = nil
		elseif cp < 0x80 then
			piece = lower(char(cp))
			if not find(piece, "^[a-z]$") then piece = nil end
		else
			piece = FOLD[cp]
		end
		if piece then n = n + 1 out[n] = piece end
		i = nextI
	end
	return concat(out)
end
N.SearchKey = N.SortKey   -- the query is normalized the same way

-- Substring search on the normalized name; the query needs at least 3 letters after normalization.
function N.Matches(name, query)
	local q = N.SearchKey(query)
	if #q < N.MIN_QUERY then return false end
	return find(N.SortKey(name), q, 1, true) ~= nil
end

-- Comparator for table.sort: true when `a` comes before `b`. Ascending sortKey, ties by the original name,
-- names whose key is empty (symbols or digits only) last (ordered by the original name).
function N.Compare(a, b)
	local ka, kb = N.SortKey(a), N.SortKey(b)
	local ea, eb = ka == "", kb == ""
	if ea ~= eb then return eb end
	if ka ~= kb then return ka < kb end
	return (a or "") < (b or "")
end

---------------------------------------------------------------------------------------------------------------------
-- FNV-1a, 32 bit
---------------------------------------------------------------------------------------------------------------------
local OFFSET, MOD = 2166136261, 4294967296

-- XOR of two bytes without bit operators.
local function xor8(a, b)
	local r, p = 0, 1
	for _ = 1, 8 do
		local x, y = a % 2, b % 2
		if x ~= y then r = r + p end
		a, b, p = (a - x) / 2, (b - y) / 2, p * 2
	end
	return r
end

-- h * 16777619 mod 2^32 with exact doubles: 16777619 = 2^24 + 403.
local function mulPrime(h)
	return (h * 403 + (h % 256) * 16777216) % MOD
end

local function hashWith(str, xorByte)
	local h = OFFSET
	for i = 1, #str do h = mulPrime(xorByte(h, byte(str, i))) end
	return h
end

local function xorArith(h, b)
	local low = h % 256
	return h - low + xor8(low, b)
end

local function xorBit(h, b)
	return bit.bxor(h, b) % MOD
end

-- Both variants exist so the tests can check that they agree.
function N.Hash32Arithmetic(str) return hashWith(tostring(str or ""), xorArith) end
function N.Hash32Bit(str) return hashWith(tostring(str or ""), xorBit) end

-- FNV-1a 32 bit of the bytes of `str`, as a number 0..2^32-1 (the bit library when the client has it).
if type(bit) == "table" and bit.bxor then N.Hash32 = N.Hash32Bit else N.Hash32 = N.Hash32Arithmetic end

function N.Hash32Hex(str) return ("%08x"):format(N.Hash32(str)) end

if ns.addon then ns.addon.Normalize = N end
