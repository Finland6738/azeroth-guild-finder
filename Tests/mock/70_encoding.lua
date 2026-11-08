-- Mock client, part 8: C_EncodingUtil stand-ins.
--
-- Imitates: C_EncodingUtil.SerializeCBOR / DeserializeCBOR, CompressString / DecompressString,
-- EncodeBase64 / DecodeBase64, EncodeHex / DecodeHex. SerializeJSON / DeserializeJSON are not mocked (they raise).
-- Dump file: ../WoW-Addons/docs/api/Core-Shared-Libraries/C_EncodingUtil.md.
--
-- The dump gives signatures, not byte layouts, so these are faithful to the standards, not to the client's exact
-- output: CBOR is RFC 8949 (definite lengths, shortest integers, map keys sorted for a deterministic result, strings
-- as text when valid UTF-8 and bytes otherwise, arrays for 1..n sequences); compression is the real zlib of Python
-- (Deflate, Zlib, Gzip), so sizes are realistic but a test must never compare compressed bytes with a literal;
-- Base64 is standard (and URL-safe variant); hex is lower case. Malformed input raises a Lua error, which is what the
-- addon's Codec must catch with pcall (the real functions fail the same way; unconfirmed in the client).
local Mock, H = ...

C_EncodingUtil = {}

local floor = math.floor

-- Base64 ---------------------------------------------------------------------------------------------------------
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
	local c = ALPHABET:sub(i, i)
	ENC[i - 1], DEC[c] = c, i - 1
end

local function b64variant(variant)
	if variant == nil or variant == Enum.Base64Variant.Standard then return false end
	if variant == Enum.Base64Variant.StandardUrlSafe then return true end
	error("C_EncodingUtil: invalid Base64 variant " .. tostring(variant), 3)
end

function C_EncodingUtil.EncodeBase64(source, variant)
	local urlSafe = b64variant(variant)
	local out, n = {}, 0
	for i = 1, #source, 3 do
		local a, b, c = source:byte(i, i + 2)
		local v = a * 65536 + (b or 0) * 256 + (c or 0)
		local chunk = ENC[floor(v / 262144)] .. ENC[floor(v / 4096) % 64] ..
			(b and ENC[floor(v / 64) % 64] or "=") .. (c and ENC[v % 64] or "=")
		n = n + 1
		out[n] = chunk
	end
	local text = table.concat(out)
	if urlSafe then text = text:gsub("%+", "-"):gsub("/", "_") end
	return text
end

function C_EncodingUtil.DecodeBase64(source, variant)
	local urlSafe = b64variant(variant)
	if urlSafe then source = source:gsub("%-", "+"):gsub("_", "/") end
	if #source % 4 ~= 0 then error("C_EncodingUtil.DecodeBase64: invalid length", 2) end
	local out, n = {}, 0
	for i = 1, #source, 4 do
		local c1, c2, c3, c4 = source:sub(i, i), source:sub(i + 1, i + 1), source:sub(i + 2, i + 2), source:sub(i + 3, i + 3)
		local v1, v2 = DEC[c1], DEC[c2]
		local v3, v4 = DEC[c3], DEC[c4]
		if c3 == "=" then v3 = 0 end
		if c4 == "=" then v4 = 0 end
		if not (v1 and v2 and v3 and v4) or (c3 == "=" and c4 ~= "=") or ((c3 == "=" or c4 == "=") and i + 3 < #source) then
			error("C_EncodingUtil.DecodeBase64: invalid character", 2)
		end
		local v = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
		local bytes = string.char(floor(v / 65536), floor(v / 256) % 256, v % 256)
		if c3 == "=" then bytes = bytes:sub(1, 1) elseif c4 == "=" then bytes = bytes:sub(1, 2) end
		n = n + 1
		out[n] = bytes
	end
	return table.concat(out)
end

-- Hex ------------------------------------------------------------------------------------------------------------
function C_EncodingUtil.EncodeHex(source)
	return (source:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

function C_EncodingUtil.DecodeHex(source)
	if #source % 2 ~= 0 or source:find("[^%x]") then error("C_EncodingUtil.DecodeHex: invalid hex string", 2) end
	return (source:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
end

-- Compression (real zlib through the harness) -----------------------------------------------------------------------
local WBITS = { [Enum.CompressionMethod.Deflate] = -15, [Enum.CompressionMethod.Zlib] = 15, [Enum.CompressionMethod.Gzip] = 31 }
local LEVELS = {
	[Enum.CompressionLevel.Default] = 6, [Enum.CompressionLevel.OptimizeForSpeed] = 1, [Enum.CompressionLevel.OptimizeForSize] = 9,
}

function C_EncodingUtil.CompressString(source, method, level)
	if type(source) ~= "string" then error("C_EncodingUtil.CompressString: string expected", 2) end
	local bits = WBITS[method == nil and Enum.CompressionMethod.Deflate or method]
	if not bits then error("C_EncodingUtil.CompressString: invalid method", 2) end
	return H.zcompress(source, bits, LEVELS[level == nil and Enum.CompressionLevel.Default or level] or 6)
end

function C_EncodingUtil.DecompressString(source, method)
	if type(source) ~= "string" then error("C_EncodingUtil.DecompressString: string expected", 2) end
	local bits = WBITS[method == nil and Enum.CompressionMethod.Deflate or method]
	if not bits then error("C_EncodingUtil.DecompressString: invalid method", 2) end
	local ok, result = H.zdecompress(source, bits)
	if not ok then error("C_EncodingUtil.DecompressString: " .. result, 2) end
	return result
end

-- CBOR (RFC 8949 subset: no tags, no indefinite lengths) --------------------------------------------------------------
local function head(major, n)
	local m = major * 32
	if n < 24 then return string.char(m + n)
	elseif n < 256 then return string.char(m + 24, n)
	elseif n < 65536 then return string.char(m + 25, floor(n / 256), n % 256)
	elseif n < 4294967296 then
		return string.char(m + 26, floor(n / 16777216), floor(n / 65536) % 256, floor(n / 256) % 256, n % 256)
	end
	local hi, lo = floor(n / 4294967296), n % 4294967296
	return string.char(m + 27, floor(hi / 16777216), floor(hi / 65536) % 256, floor(hi / 256) % 256, hi % 256,
		floor(lo / 16777216), floor(lo / 65536) % 256, floor(lo / 256) % 256, lo % 256)
end

local function float64(x)
	local sign = 0
	if x < 0 or (x == 0 and 1 / x < 0) then sign, x = 1, -x end
	local expf, mant
	if x ~= x then expf, mant = 2047, 2 ^ 51
	elseif x == math.huge then expf, mant = 2047, 0
	elseif x == 0 then expf, mant = 0, 0
	else
		local m, e = math.frexp(x)
		expf = e + 1022
		if expf <= 0 then
			mant, expf = x / 2 ^ -1074, 0                -- subnormal
		else
			mant = (m * 2 - 1) * 2 ^ 52
		end
	end
	local hi = sign * 2147483648 + expf * 1048576 + floor(mant / 4294967296)
	local lo = mant % 4294967296
	return "\251" .. string.char(floor(hi / 16777216), floor(hi / 65536) % 256, floor(hi / 256) % 256, hi % 256,
		floor(lo / 16777216), floor(lo / 65536) % 256, floor(lo / 256) % 256, lo % 256)
end

local function validUtf8(s)
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		local len = c < 128 and 1 or (c >= 194 and c < 224) and 2 or (c >= 224 and c < 240) and 3 or (c >= 240 and c < 245) and 4 or 0
		if len == 0 or i + len - 1 > n then return false end
		for j = i + 1, i + len - 1 do
			local cc = s:byte(j)
			if cc < 128 or cc > 191 then return false end
		end
		i = i + len
	end
	return true
end

local function isSequence(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	for i = 1, n do if t[i] == nil then return false end end
	return true, n
end

local function keyOrder(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then return ta < tb end
	if ta == "number" or ta == "string" then return a < b end
	return tostring(a) < tostring(b)
end

local function encode(v, out, ignoreErrors, depth)
	if depth > 64 then error("C_EncodingUtil.SerializeCBOR: nesting too deep", 0) end
	local t = type(v)
	if v == nil then out[#out + 1] = "\246"
	elseif t == "boolean" then out[#out + 1] = v and "\245" or "\244"
	elseif t == "number" then
		if v == floor(v) and math.abs(v) < 2 ^ 53 then
			out[#out + 1] = v >= 0 and head(0, v) or head(1, -1 - v)
		else
			out[#out + 1] = float64(v)
		end
	elseif t == "string" then
		out[#out + 1] = head(validUtf8(v) and 3 or 2, #v) .. v
	elseif t == "table" then
		local seq, n = isSequence(v)
		if seq then
			out[#out + 1] = head(4, n)
			for i = 1, n do encode(v[i], out, ignoreErrors, depth + 1) end
		else
			local keys = {}
			for k in pairs(v) do keys[#keys + 1] = k end
			table.sort(keys, keyOrder)
			out[#out + 1] = head(5, #keys)
			for _, k in ipairs(keys) do
				encode(k, out, ignoreErrors, depth + 1)
				encode(v[k], out, ignoreErrors, depth + 1)
			end
		end
	elseif ignoreErrors then
		out[#out + 1] = "\246"
	else
		error("C_EncodingUtil.SerializeCBOR: cannot serialize a " .. t, 0)
	end
end

function C_EncodingUtil.SerializeCBOR(value, options)
	local out = {}
	local ok, err = pcall(encode, value, out, options and options.ignoreSerializationErrors, 0)
	if not ok then error(err, 2) end
	return table.concat(out)
end

local function malformed(why) error("C_EncodingUtil.DeserializeCBOR: " .. why, 0) end

local function readFloat(s, pos, size)
	local b = { s:byte(pos, pos + size - 1) }
	if #b < size then malformed("truncated") end
	if size == 8 then
		local hi = ((b[1] * 256 + b[2]) * 256 + b[3]) * 256 + b[4]
		local lo = ((b[5] * 256 + b[6]) * 256 + b[7]) * 256 + b[8]
		local sign = hi >= 2147483648 and -1 or 1
		local expf = floor(hi / 1048576) % 2048
		local mant = (hi % 1048576) * 4294967296 + lo
		if expf == 2047 then return mant == 0 and sign * math.huge or 0 / 0 end
		if expf == 0 then return sign * mant * 2 ^ -1074 end
		return sign * (1 + mant / 2 ^ 52) * 2 ^ (expf - 1023)
	elseif size == 4 then
		local v = ((b[1] * 256 + b[2]) * 256 + b[3]) * 256 + b[4]
		local sign = v >= 2147483648 and -1 or 1
		local expf = floor(v / 8388608) % 256
		local mant = v % 8388608
		if expf == 255 then return mant == 0 and sign * math.huge or 0 / 0 end
		if expf == 0 then return sign * mant * 2 ^ -149 end
		return sign * (1 + mant / 8388608) * 2 ^ (expf - 127)
	end
	local v = b[1] * 256 + b[2]
	local sign = v >= 32768 and -1 or 1
	local expf, mant = floor(v / 1024) % 32, v % 1024
	if expf == 31 then return mant == 0 and sign * math.huge or 0 / 0 end
	if expf == 0 then return sign * mant * 2 ^ -24 end
	return sign * (1 + mant / 1024) * 2 ^ (expf - 15)
end

local decode
local function readArgument(s, pos, info)
	if info < 24 then return info, pos end
	local size = info == 24 and 1 or info == 25 and 2 or info == 26 and 4 or info == 27 and 8
	if not size then malformed("unsupported additional information " .. info) end
	local b = { s:byte(pos, pos + size - 1) }
	if #b < size then malformed("truncated") end
	local n = 0
	for i = 1, size do n = n * 256 + b[i] end
	return n, pos + size
end

function decode(s, pos, depth)
	if depth > 64 then malformed("nesting too deep") end
	local byte = s:byte(pos)
	if not byte then malformed("truncated") end
	pos = pos + 1
	local major, info = floor(byte / 32), byte % 32
	if major == 7 then
		if info == 20 then return false, pos elseif info == 21 then return true, pos
		elseif info == 22 or info == 23 then return nil, pos
		elseif info == 25 then return readFloat(s, pos, 2), pos + 2
		elseif info == 26 then return readFloat(s, pos, 4), pos + 4
		elseif info == 27 then return readFloat(s, pos, 8), pos + 8 end
		malformed("unsupported simple value")
	end
	local n
	n, pos = readArgument(s, pos, info)
	if major == 0 then return n, pos
	elseif major == 1 then return -1 - n, pos
	elseif major == 2 or major == 3 then
		if pos + n - 1 > #s then malformed("truncated string") end
		return s:sub(pos, pos + n - 1), pos + n
	elseif major == 4 then
		if n > #s - pos + 1 then malformed("array longer than the data") end
		local t = {}
		for i = 1, n do t[i], pos = decode(s, pos, depth + 1) end
		return t, pos
	elseif major == 5 then
		if n * 2 > #s - pos + 1 then malformed("map longer than the data") end
		local t = {}
		for _ = 1, n do
			local k, v
			k, pos = decode(s, pos, depth + 1)
			v, pos = decode(s, pos, depth + 1)
			if k == nil then malformed("nil map key") end
			t[k] = v
		end
		return t, pos
	end
	malformed("unsupported major type " .. major)
end

function C_EncodingUtil.DeserializeCBOR(source)
	if type(source) ~= "string" then error("C_EncodingUtil.DeserializeCBOR: string expected", 2) end
	local ok, value, pos = pcall(decode, source, 1, 0)
	if not ok then error(value, 2) end
	if pos <= #source then error("C_EncodingUtil.DeserializeCBOR: trailing data", 2) end
	return value
end

function C_EncodingUtil.SerializeJSON() error("C_EncodingUtil.SerializeJSON is not mocked (the addon uses CBOR)", 2) end
function C_EncodingUtil.DeserializeJSON() error("C_EncodingUtil.DeserializeJSON is not mocked (the addon uses CBOR)", 2) end
