-- Codec (M1.6): round trip of every message type, raw and compressed paths, malformed input, versions.
local function codec() return AzerothGuildFinder.Codec end
local function b64(s) return C_EncodingUtil.EncodeBase64(s) end
local function cbor(t) return C_EncodingUtil.SerializeCBOR(t) end

local SAMPLES = {
	ANN = { k = "Firemaw|Alliance|Night Watch", rev = 3, srev = 1700000000, c = 1, tags = { 1, 2 }, pace = 2 },
	DEL = { k = "Firemaw|Alliance|Night Watch", rev = 4 },
	CATREQ = { nonce = 123456, cat = { { h = 99, rev = 1, srev = 2 }, { h = 100, rev = 5, srev = 6 } } },
	CATACK = { to = "Someone-Firemaw", nonce = 123456 },
	CAT = { nonce = 123456, items = { { k = "A", rev = 1 }, { k = "B", rev = 2 } } },
	DETREQ = { k = "Firemaw|Alliance|Night Watch", rev = 3, nonce = 7 },
	DETACK = { to = "Someone-Firemaw", nonce = 7 },
	DET = { k = "Firemaw|Alliance|Night Watch", rev = 3, desc = "We raid on Tuesday.", disc = "abc123", cont = { "Gm" } },
	GLIST = { k = "Firemaw|Alliance|Night Watch", rev = 3, desc = "Hello", sub = "Friendly" },
	GLREQ = { rev = 2 },
	GTOK = { token = "deadbeef", n = 3 },
	APPLY = { id = "a1b2c3", k = "Firemaw|Alliance|Night Watch", msg = "Hi" },
	APPACK = { id = "a1b2c3", state = "accepted" },
	APPPING = { id = "a1b2c3" },
	APPWD = { id = "a1b2c3" },
	APPSYNC = { ids = { a1b2c3 = 4 }, recs = { { id = "x", state = "sent" } } },
	PING = { nonce = 424242 },
	PONG = { nonce = 424242 },
}

local function long()
	return string.rep("The quick brown fox jumps over the lazy dog. ", 30)
end

describe("Codec round trips", function()
	for t, fields in pairs(SAMPLES) do
		it("round trips " .. t, function()
			local payload, err = codec():Encode(t, fields)
			truthy(payload, err)
			local msg, reason = codec():Decode(payload)
			truthy(msg, reason)
			eq(msg.v, 1)
			eq(msg.t, t)
			for k, v in pairs(fields) do deepEq(msg[k], v, k) end
		end)
	end

	it("covers every type of the schema", function()
		for t in pairs(codec().SCHEMA) do truthy(SAMPLES[t], t) end
		for t in pairs(SAMPLES) do truthy(codec().SCHEMA[t], t) end
	end)

	it("sends short messages raw and long ones compressed", function()
		local short = codec():Encode("GLREQ", { rev = 1 })
		eq(C_EncodingUtil.DecodeBase64(short):sub(1, 1), "\0")
		local big = codec():Encode("DET", { k = "K", rev = 1, desc = long() })
		eq(C_EncodingUtil.DecodeBase64(big):sub(1, 1), "\1")
		truthy(#big < #long())
		eq(codec():Decode(big).desc, long())
	end)

	it("keeps incompressible long content raw", function()
		local noise = {}
		local seed = 7
		for i = 1, 200 do seed = (seed * 1103515245 + 12345) % 2147483648; noise[i] = string.char(seed % 256) end
		local payload = codec():Encode("DET", { k = "K", rev = 1, desc = table.concat(noise) })
		local flag = C_EncodingUtil.DecodeBase64(payload):sub(1, 1)
		truthy(flag == "\0" or flag == "\1")
		eq(#codec():Decode(payload).desc, 200)
	end)

	it("is deterministic and ASCII-safe", function()
		local a = codec():Encode("ANN", SAMPLES.ANN)
		eq(codec():Encode("ANN", SAMPLES.ANN), a)
		falsy(a:find("[^A-Za-z0-9+/=]"))
		falsy(a:find("%z"))
	end)

	it("does not modify the fields it is given", function()
		local fields = { rev = 5 }
		codec():Encode("GLREQ", fields)
		deepEq(fields, { rev = 5 })
	end)

	it("keeps unknown fields and nested data untouched", function()
		local payload = codec():Encode("GLREQ", { rev = 1, future = { 1, 2, 3 }, name = "x" })
		local msg = codec():Decode(payload)
		deepEq(msg.future, { 1, 2, 3 })
		eq(msg.name, "x")
	end)
end)

describe("Codec encode errors", function()
	it("refuses unknown types and missing required fields", function()
		eq(select(2, codec():Encode("NOPE", {})), "type")
		eq(select(2, codec():Encode("ANN", { k = "x" })), "invalid")
		eq(select(2, codec():Encode("GLREQ", { rev = "1" })), "invalid")
		eq(select(2, codec():Encode("GLREQ", "text")), "shape")
	end)

	it("refuses a message a receiver would reject for its size, even when it compresses well", function()
		local payload, why = codec():Encode("DET", { k = "K", rev = 1, desc = string.rep("a", codec().MAX_DECODED + 1) })
		eq(payload, nil); eq(why, "size")
		truthy(codec():Encode("DET", { k = "K", rev = 1, desc = string.rep("a", codec().MAX_DECODED - 100) }))
	end)
end)

describe("Codec malformed input", function()
	local function rejected(payload, reason)
		local ok, msg, why = pcall(codec().Decode, codec(), payload)
		truthy(ok, "Decode raised")
		eq(msg, nil)
		eq(why, reason)
	end

	it("rejects non-strings, empty and oversized payloads", function()
		rejected(nil, "size")
		rejected(42, "size")
		rejected({}, "size")
		rejected("", "size")
		rejected(string.rep("A", codec().MAX_PAYLOAD + 1), "size")
	end)

	it("rejects bad Base64", function()
		rejected("not base64 at all!", "base64")
		rejected("AAA", "base64")
		rejected("====", "base64")
	end)

	it("rejects a bad flag", function()
		rejected(b64("\2" .. cbor({ v = 1, t = "GLREQ", rev = 1 })), "flag")
		rejected(b64("\0"), "size")
	end)

	it("rejects broken compression", function()
		rejected(b64("\1garbage garbage garbage"), "inflate")
	end)

	it("rejects a decompressed size over the limit", function()
		local big = cbor({ v = 1, t = "DET", k = "K", rev = 1, pad = string.rep("a", codec().MAX_DECODED + 100) })
		rejected(b64("\0" .. big), "size")
		rejected(b64("\1" .. C_EncodingUtil.CompressString(big)), "size")
	end)

	it("rejects broken or non-table CBOR", function()
		rejected(b64("\0\255\255"), "cbor")
		rejected(b64("\0" .. cbor(12)), "shape")
		rejected(b64("\0" .. cbor("text")), "shape")
		rejected(b64("\0" .. cbor(true)), "shape")
		rejected(b64("\0" .. cbor({ 1, 2, 3 })), "version")
	end)

	it("rejects a missing or invalid version", function()
		rejected(b64("\0" .. cbor({ t = "GLREQ", rev = 1 })), "version")
		rejected(b64("\0" .. cbor({ v = "1", t = "GLREQ", rev = 1 })), "version")
		rejected(b64("\0" .. cbor({ v = 0, t = "GLREQ", rev = 1 })), "version")
		rejected(b64("\0" .. cbor({ v = 1.5, t = "GLREQ", rev = 1 })), "version")
	end)

	it("rejects a missing, non-string or unknown type", function()
		rejected(b64("\0" .. cbor({ v = 1, rev = 1 })), "type")
		rejected(b64("\0" .. cbor({ v = 1, t = 5 })), "type")
		rejected(b64("\0" .. cbor({ v = 1, t = "ZZZ" })), "type")
	end)

	it("rejects a message missing required fields", function()
		rejected(b64("\0" .. cbor({ v = 1, t = "ANN", k = "x" })), "invalid")
	end)

	it("survives random garbage", function()
		local seed = 11
		for n = 1, 60 do
			local bytes = {}
			for i = 1, n do seed = (seed * 1103515245 + 12345) % 2147483648; bytes[i] = string.char(seed % 256) end
			local raw = table.concat(bytes)
			local ok = pcall(codec().Decode, codec(), raw)
			truthy(ok)
			ok = pcall(codec().Decode, codec(), b64(raw))
			truthy(ok)
		end
	end)

	it("counts rejections for /gf debug", function()
		local before = codec().stats.rejected
		codec():Decode("!!")
		eq(codec().stats.rejected, before + 1)
		eq(codec().lastReject, "base64")
		truthy(#codec():DebugLines() == 1)
	end)
end)

describe("Codec versions", function()
	it("treats a newer version as unreadable and flags it once", function()
		local payload = b64("\0" .. cbor({ v = 2, t = "UNKNOWN_FUTURE", x = 1 }))
		local msg, why = codec():Decode(payload)
		eq(msg, nil)
		eq(why, "newer")
		truthy(codec().newerSeen)
		truthy(codec():ConsumeNewer())
		falsy(codec():ConsumeNewer())
		falsy(codec().newerSeen)
	end)

	it("does not flag a current message", function()
		codec():Decode(codec():Encode("GLREQ", { rev = 1 }))
		falsy(codec().newerSeen)
	end)

	it("exposes the protocol constants", function()
		eq(codec().PROTO, 1)
		eq(codec().PREFIX, "AzGF")
		eq(codec().COMPRESS_OVER, 120)
		eq(codec().MAX_DECODED, 8192)
	end)
end)
