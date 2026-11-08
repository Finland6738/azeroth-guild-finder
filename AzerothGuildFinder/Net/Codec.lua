-- Codec: message <-> addon-message payload (SPEC-02 §2). Lua 5.1.
--   payload = Base64( flag .. (flag == "\1" and Deflate(CBOR(msg)) or CBOR(msg)) )
--   msg     = { v = PROTO, t = "<TYPE>", ... }
-- Decode never raises: it returns msg, or nil plus a reason ("size", "base64", "flag", "inflate", "cbor", "shape",
-- "version", "type", "invalid", "newer"). Unknown fields are kept untouched. Deep validation of records belongs to the
-- Data modules (M2/M3); here only the required fields of each type are checked.
local ADDON_NAME, ns = ...
ns = ns or {}
local Codec = {}
ns.Codec, ns.modules = Codec, ns.modules or {}
ns.modules.Codec = Codec

local type, pairs, ipairs, pcall, tostring, floor = type, pairs, ipairs, pcall, tostring, math.floor
local sub, find = string.sub, string.find

Codec.PROTO = 1
Codec.PREFIX = "AzGF"
Codec.COMPRESS_OVER = 120   -- CBOR longer than this is deflated (when that makes it shorter)
Codec.MAX_DECODED = 8192    -- largest accepted CBOR after decompression
Codec.FLAG_RAW, Codec.FLAG_DEFLATE = "\0", "\1"
-- A Base64 payload cannot be longer than the compressed form of the largest message plus the flag byte.
Codec.MAX_PAYLOAD = floor((Codec.MAX_DECODED + 1) / 3 + 1) * 4

Codec.newerSeen = false     -- a message with a newer protocol version was received (shown once by the UI)
Codec.stats = { encoded = 0, decoded = 0, rejected = 0 }
Codec.lastReject = nil      -- last rejection reason, for /gf debug

-- Required fields per message type: name -> Lua type. Unlisted fields are optional and never rejected.
Codec.SCHEMA = {
	ANN     = { k = "string", rev = "number" },                       -- summary + stats; c = 1 for a contact, test
	DEL     = { k = "string", rev = "number" },
	CATREQ  = { nonce = "number", cat = "table" },                    -- cat = { h1, rev1, srev1, h2, ... }; p, n (part)
	CATACK  = { to = "string", nonce = "number" },                    -- n = summaries to send, w = seconds before
	CAT     = { nonce = "number", items = "table" },                  -- items = summaries; age = { s, ... }; i, of, n
	DETREQ  = { k = "string", rev = "number", nonce = "number" },     -- d = detail rev the requester has (0: none)
	DETACK  = { to = "string", nonce = "number" },                    -- r = detail rev to send
	DET     = { k = "string", rev = "number" },                       -- detail fields (SPEC-03 §3) + nonce
	GLIST   = { k = "string", rev = "number" },                       -- summary + detail
	GLREQ   = { rev = "number" },
	GTOK    = { token = "string", n = "number" },
	APPLY   = { id = "string", k = "string" },
	APPACK  = { id = "string", state = "string" },
	APPPING = { id = "string" },
	APPWD   = { id = "string" },
	APPSYNC = {},                                                     -- ids = { [id] = stateRev }, recs = { ... }
	PING    = { nonce = "number" },                                   -- debug: /gf debug ping, channel (SPEC-02 §3)
	PONG    = { nonce = "number" },                                   -- debug: the answer to a PING, whisper
}

local function compat() return ns.Compat end

local function reject(reason)
	Codec.stats.rejected = Codec.stats.rejected + 1
	Codec.lastReject = reason
	return nil, reason
end

-- true, or false plus a reason. msg must be a table with a known `t` and the required fields of that type.
function Codec:Validate(msg)
	if type(msg) ~= "table" then return false, "shape" end
	local schema = type(msg.t) == "string" and Codec.SCHEMA[msg.t]
	if not schema then return false, "type" end
	for field, kind in pairs(schema) do
		if type(msg[field]) ~= kind then return false, "invalid" end
	end
	return true
end

-- Builds the payload for message type `t` with `fields`. Returns the string, or nil plus a reason.
function Codec:Encode(t, fields)
	local C = compat()
	if not C then return nil, "nocompat" end
	if fields ~= nil and type(fields) ~= "table" then return nil, "shape" end
	local msg = {}
	for k, v in pairs(fields or {}) do msg[k] = v end
	msg.v, msg.t = Codec.PROTO, t
	local ok, reason = Codec:Validate(msg)
	if not ok then return nil, reason end
	local cbor, err = C.CBOR.Encode(msg)
	if not cbor then return nil, "cbor: " .. tostring(err) end
	if #cbor > Codec.MAX_DECODED then return nil, "size" end   -- a receiver would reject it
	local flag, body = Codec.FLAG_RAW, cbor
	if #cbor > Codec.COMPRESS_OVER then
		local packed = C.Compress.Deflate(cbor)
		if packed and #packed < #cbor then flag, body = Codec.FLAG_DEFLATE, packed end
	end
	local text, err2 = C.Base64.Encode(flag .. body)
	if not text then return nil, "base64: " .. tostring(err2) end
	Codec.stats.encoded = Codec.stats.encoded + 1
	return text
end

-- Returns the message table, or nil plus a reason. Never raises.
function Codec:Decode(payload)
	local C = compat()
	if not C then return nil, "nocompat" end
	if type(payload) ~= "string" or payload == "" or #payload > Codec.MAX_PAYLOAD then return reject("size") end
	if find(payload, "[^A-Za-z0-9+/=]") then return reject("base64") end
	local raw = C.Base64.Decode(payload)
	if not raw or raw == "" then return reject("base64") end
	local flag, body = sub(raw, 1, 1), sub(raw, 2)
	if flag == Codec.FLAG_DEFLATE then
		body = C.Compress.Inflate(body)
		if not body then return reject("inflate") end
	elseif flag ~= Codec.FLAG_RAW then
		return reject("flag")
	end
	if #body == 0 or #body > Codec.MAX_DECODED then return reject("size") end
	local msg = C.CBOR.Decode(body)
	if type(msg) ~= "table" then return reject(msg == nil and "cbor" or "shape") end
	local v = msg.v
	if type(v) ~= "number" or v ~= floor(v) or v < 1 then return reject("version") end
	if v > Codec.PROTO then
		Codec.newerSeen = true
		return reject("newer")
	end
	local ok, reason = Codec:Validate(msg)
	if not ok then return reject(reason) end
	Codec.stats.decoded = Codec.stats.decoded + 1
	return msg
end

-- One-shot: true the first time after a newer version was seen, then false until another one arrives.
function Codec:ConsumeNewer()
	local seen = Codec.newerSeen
	Codec.newerSeen = false
	return seen
end

function Codec:DebugLines()
	local s = Codec.stats
	return { ("Codec: proto %d, encoded %d, decoded %d, rejected %d (last: %s), newer seen: %s"):format(
		Codec.PROTO, s.encoded, s.decoded, s.rejected, Codec.lastReject or "-", Codec.newerSeen and "yes" or "no") }
end

if ns.addon then
	ns.addon.Codec = Codec
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Codec", function() return Codec:DebugLines() end) end
end
