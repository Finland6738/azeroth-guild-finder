-- M3.6: emblems. First the rules without frames (Data/Emblems.lua, Data/TabardParts.lua): validation of what arrives from the
-- network, the round trip through the real codec, the rendering parameters every client computes the same way, the fallbacks,
-- the guild tabard, Random and Reset. Then the renderer (UI/Emblem.lua) on the mock client, including pieces the client cannot
-- load (Mock.missingTextures).

local function A() return AzerothGuildFinder end
local function E() return A().Emblems end
local function P() return A().TabardParts end

local FULL = { t = 2, e = 1006, b = 2, gc = 0x4A1414, bc = 0xE3B43D, ec = 0xE3B43D }

-- A seeded generator in the shape Emblems.Random wants (n -> 1..n): the same seed gives the same draws on every platform.
local function lcg(seed)
	local state = seed
	return function(n)
		state = (state * 1103515245 + 12345) % 2147483648
		return math.floor(state / 65536) % n + 1
	end
end

local function layer(spec, id)
	for _, l in ipairs(spec.layers) do if l.id == id then return l end end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------------------------------------------------
describe("emblem validation", function()
	it("keeps a valid emblem as it is, and only the known fields", function()
		deepEq(E().Sanitize(FULL), FULL)
		local extra = { t = 1, e = 5, b = 0, gc = 1, bc = 2, ec = 3, x = "evil", f = { 1, 2 }, [1] = 9 }
		deepEq(E().Sanitize(extra), { t = 1, e = 5, b = 0, gc = 1, bc = 2, ec = 3 })
	end)

	it("refuses anything that is not an emblem", function()
		for _, bad in ipairs({ "string", 42, true, function() end, {}, { t = 3, e = 1 }, { t = "2", e = 1 }, { t = 2 },
			{ t = 2, ec = 5 }, { e = 1 } }) do
			isNil(E().Sanitize(bad), tostring(bad))
		end
	end)

	it("drops pieces and colours out of range, wrong types, fractions, NaN and infinities", function()
		local huge = math.huge
		local raw = { t = 2, e = 5, b = P().MAX_INDEX + 1, g = -1, gc = 0x1000000, bc = 1.5, ec = 0 / 0 }
		local issues = {}
		deepEq(E().Sanitize(raw, issues), { t = 2, e = 5 })
		eq(#issues, 5)
		for _, v in ipairs({ huge, -huge, 2 ^ 53, -0.5, "7", { 7 } }) do
			isNil(E().Sanitize({ t = 2, e = v }), "e = " .. tostring(v))
			deepEq(E().Sanitize({ t = 2, e = 1, ec = v }), { t = 2, e = 1 }, "ec = " .. tostring(v))
		end
		eq(E().Sanitize({ t = 2, e = P().MAX_INDEX }).e, P().MAX_INDEX, "the largest index passes")
		eq(E().Sanitize({ t = 2, e = 0, gc = 0xFFFFFF }).gc, 0xFFFFFF, "white passes")
	end)

	it("never runs code hidden in a table and never raises", function()
		local trap = setmetatable({}, { __index = function() error("trap") end })
		isNil(E().Sanitize(trap))
		local proxy = setmetatable({ t = 2 }, { __index = function() error("trap") end })
		isNil(E().Sanitize(proxy), "no piece: the missing fields are not looked up through the metatable")
		local issues = {}
		local ok = pcall(function() E().Sanitize(setmetatable({ t = 1, e = 1 }, { __index = error }), issues) end)
		truthy(ok)
	end)

	it("an oversized emblem costs nothing more and comes out small", function()
		local big = { t = 2, e = 1, gc = 1 }
		for i = 1, 5000 do big["junk" .. i] = string.rep("x", 50) end
		for i = 1, 5000 do big[i] = i end
		deepEq(E().Sanitize(big), { t = 2, e = 1, gc = 1 })
	end)

	it("is what Listing keeps from a summary, and sanitizing twice changes nothing", function()
		local sum = A().Listing.SanitizeSummary({ k = "TestRealm|Horde|Iron Wolves", rev = 1, emb = FULL })
		deepEq(sum.emb, FULL)
		local again = A().Listing.SanitizeSummary(sum)
		deepEq(again.emb, FULL)
		isNil(A().Listing.SanitizeSummary({ k = "TestRealm|Horde|Iron Wolves", rev = 1, emb = { t = 2, e = 99999 } }).emb)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Encode, decode, size
---------------------------------------------------------------------------------------------------------------------
describe("emblem encode and decode", function()
	it("a round trip through the codec of the network gives back the same emblem, for a tabard and for a design", function()
		for _, emb in ipairs({ FULL, { t = 1, e = 0, b = 0, gc = 0, bc = 0xFFFFFF, ec = 0x123456 }, { t = 2, e = 1000 } }) do
			local wire = E().Encode(emb)
			local payload = assert(A().Codec:Encode("ANN", { k = "TestRealm|Horde|Iron Wolves", rev = 2, emb = wire }))
			local msg = assert(A().Codec:Decode(payload))
			local sum = A().Listing.SanitizeSummary(msg)
			deepEq(E().Decode(sum.emb), emb)
			truthy(E().Equal(E().Decode(sum.emb), emb))
		end
	end)

	it("Encode publishes only a valid emblem", function()
		isNil(E().Encode({ t = 2 }))
		isNil(E().Encode(nil))
		deepEq(E().Encode({ t = 2, e = 3, junk = 1 }), { t = 2, e = 3 })
	end)

	it("the largest emblem stays a few dozen bytes in CBOR (the summary budget of SPEC-03 is about 160)", function()
		local max = { t = 2, e = P().MAX_INDEX, b = P().MAX_INDEX, g = P().MAX_INDEX, gc = 0xFFFFFF, bc = 0xFFFFFF, ec = 0xFFFFFF }
		local bytes = C_EncodingUtil.SerializeCBOR(E().Encode(max))
		truthy(#bytes <= 48, "CBOR bytes: " .. #bytes)
	end)

	it("Equal compares every field", function()
		truthy(E().Equal(FULL, E().Copy(FULL)))
		local other = E().Copy(FULL)
		other.ec = 1
		falsy(E().Equal(FULL, other))
		falsy(E().Equal(FULL, nil))
		truthy(E().Equal(nil, nil))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Rendering parameters
---------------------------------------------------------------------------------------------------------------------
describe("rendering parameters", function()
	it("are the same for the same emblem, every time", function()
		for _, size in ipairs({ 48, 58, 64, 84, 96, 150 }) do
			deepEq(E().Layers(FULL, size, "Iron Wolves"), E().Layers(E().Copy(FULL), size, "Iron Wolves"), "size " .. size)
		end
	end)

	it("have exact pixels and colours (what every client draws)", function()
		local spec = E().Layers(FULL, 150, "Iron Wolves")
		eq(spec.tier, 150)
		local ids = {}
		for _, l in ipairs(spec.layers) do ids[#ids + 1] = l.id end
		deepEq(ids, { "field", "border", "emblem", "gloss", "frame" })
		local field = layer(spec, "field")
		eq(field.media, "emblem_field")
		deepEq(field.rect, { 0, 0, 150, 150 })
		deepEq(field.color, { 74 / 255, 20 / 255, 20 / 255 })
		local border = layer(spec, "border")
		eq(border.media, "emblem_border_2")
		deepEq(border.color, { 227 / 255, 180 / 255, 61 / 255 })
		local emblem = layer(spec, "emblem")
		eq(emblem.media, "emblem_sym_crown")
		deepEq(emblem.rect, { 41, 38, 69, 69 })
		eq(emblem.fallback.id, "initial")
		eq(emblem.fallback.text, "I")
		eq(emblem.fallback.fontPx, 54)
		eq(layer(spec, "frame").media, "emblem_frame")
	end)

	it("draw the four sizes inside their frame, with the thick frame at 48 and 64", function()
		for _, size in ipairs(E().SIZES) do
			local spec = E().Layers(FULL, size, "X")
			eq(spec.tier, size)
			for _, l in ipairs(spec.layers) do
				local r = l.rect
				truthy(r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= size and r[2] + r[4] <= size, l.id .. " at " .. size)
			end
			eq(layer(spec, "frame").media, size <= 64 and "emblem_frame_small" or "emblem_frame")
		end
		eq(E().Tier(30), 48); eq(E().Tier(58), 48); eq(E().Tier(84), 64); eq(E().Tier(400), 150)
	end)

	it("do not depend on the palettes: the colour travels as RGB", function()
		local before = E().Layers(FULL, 96, "X")
		local saved = P().COLORS.background
		P().COLORS.background = { 0x000000 }
		deepEq(E().Layers(FULL, 96, "X"), before)
		P().COLORS.background = saved
	end)

	it("a game emblem is drawn from its cell of the emblem sheet, or from its fileID once M0.7 knows it", function()
		local spec = E().Layers({ t = 1, e = 17, gc = 0 }, 96, "X")
		local emblem = layer(spec, "emblem")
		eq(emblem.path, P().EMBLEM_SHEET.path)
		deepEq(emblem.coords, { 1 / 16, 2 / 16, 1 / 16, 2 / 16 })
		P().EMBLEM_FILES[17] = 4242
		emblem = layer(E().Layers({ t = 1, e = 17, gc = 0 }, 96, "X"), "emblem")
		eq(emblem.file, 4242)
		isNil(emblem.path)
		P().EMBLEM_FILES[17] = nil
	end)

	it("fall back cleanly: an unknown emblem is the initial, an unknown border is no border, nothing valid is the neutral shield", function()
		local spec = E().Layers({ t = 2, e = 999, b = 77, gc = 0x123456, ec = 0xFFFFFF }, 64, "Iron Wolves")
		isNil(layer(spec, "emblem"))
		isNil(layer(spec, "border"))
		local initial = layer(spec, "initial")
		eq(initial.text, "I")
		deepEq(initial.color, { 1, 1, 1 })
		local neutral = E().Layers({ t = 9, e = 1 }, 64, "élite")
		falsy(neutral.valid)
		deepEq(layer(neutral, "field").color, { 0x2B / 255, 0x35 / 255, 0x47 / 255 })
		eq(layer(neutral, "initial").text, "é")
		deepEq(layer(neutral, "initial").color, { 0xE3 / 255, 0xB4 / 255, 0x3D / 255 })
		truthy(layer(E().Layers(nil, 0, nil), "initial"), "no size, no name: still a shield")
		eq(layer(E().Layers(nil, 64, nil), "initial").text, "?")
	end)

	it("the initial is one whole character", function()
		eq(E().Initial("iron Wolves"), "I")
		eq(E().Initial("  ombra"), "O")
		eq(E().Initial("Ötzi"), "Ö")
		eq(E().Initial("\200abc"), "?")
		eq(E().Initial(""), "?")
		eq(E().Initial(42), "?")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The catalogue
---------------------------------------------------------------------------------------------------------------------
describe("the catalogue of pieces (provisional until M0.7)", function()
	it("is marked provisional and lists the game's emblems first, then the addon's symbols", function()
		truthy(P().PROVISIONAL)
		local list = P().EmblemList()
		eq(#list, P().EMBLEM_COUNT + P().OWN_COUNT)
		eq(list[1], 0)
		eq(list[#list], P().OWN_BASE + P().OWN_COUNT - 1)
		local own = P().EmblemList(false)
		eq(#own, P().OWN_COUNT)
		eq(own[1], P().OWN_BASE)
	end)

	it("knows a game fileID only after M0.7 fills it in", function()
		isNil(P().EmblemIndexOfFile(123))
		P().EMBLEM_FILES[4] = 123
		eq(P().EmblemIndexOfFile(123), 4)
		P().EMBLEM_FILES[4] = nil
		isNil(P().Emblem(P().EMBLEM_COUNT), "past the game's count, below the own symbols")
		isNil(P().Emblem(-1))
		isNil(P().Border(P().BORDER_COUNT))
	end)

	it("pages of 16 emblems", function()
		local list = {}
		for i = 1, 40 do list[i] = i end
		local items, page, pages = E().Page(list, 3)
		eq(#items, 8); eq(page, 3); eq(pages, 3); eq(items[1], 33)
		local _, clamped = E().Page(list, 99)
		eq(clamped, 3)
		eq(E().PageOf(list, 17), 2)
		eq(E().PageOf(list, 500), 1)
		local _, p, n = E().Page({}, 1)
		eq(p, 1); eq(n, 1)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The guild tabard
---------------------------------------------------------------------------------------------------------------------
describe("the guild tabard", function()
	local INFO = { backgroundColor = { r = 74 / 255, g = 20 / 255, b = 20 / 255 }, borderColor = { r = 1, g = 1, b = 1 },
		emblemColor = { r = 0.890, g = 0.706, b = 0.239 }, emblemStyle = 12, emblemFileID = 99999 }

	it("is copied as it is: colours, the emblem by its style, the default border style until the probe says more", function()
		local emb, why = E().FromTabardInfo(INFO)
		isNil(why)
		deepEq(emb, { t = 1, e = 12, b = P().TABARD_BORDER, gc = 0x4A1414, bc = 0xFFFFFF, ec = 0xE3B43D })
	end)

	it("takes colours as 0..255 bytes too, a border style when the client gives one, the emblem by fileID when only that is known", function()
		P().EMBLEM_FILES[30] = 99999
		local emb = E().FromTabardInfo({ backgroundColor = { r = 10, g = 20, b = 30 }, borderStyle = 3, emblemFileID = 99999 })
		eq(emb.gc, 10 * 65536 + 20 * 256 + 30)
		eq(emb.b, 3)
		eq(emb.e, 30)
		P().EMBLEM_FILES[30] = nil
	end)

	it("says why there is nothing", function()
		local emb, why = E().FromTabardInfo(nil)
		isNil(emb); eq(why, "none")
		emb, why = E().FromTabardInfo({})
		isNil(emb); eq(why, "empty")
	end)

	it("ignores nonsense from the client", function()
		local emb = E().FromTabardInfo({ emblemStyle = 1e12, borderStyle = -4, backgroundColor = { r = "x" }, emblemColor = { r = 0, g = 0, b = 0 } })
		deepEq(emb, { t = 1, b = P().TABARD_BORDER, ec = 0 })
		isNil(E().FromTabardInfo({ emblemStyle = 1003 }), "the addon's own symbols are never a tabard emblem")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Random and Reset
---------------------------------------------------------------------------------------------------------------------
describe("Random", function()
	it("gives a valid design from the catalogue, the same for the same seed", function()
		local a, b = E().Random(lcg(7)), E().Random(lcg(7))
		deepEq(a, b)
		deepEq(E().Sanitize(a), a)
		eq(a.t, 2)
	end)

	it("keeps the emblem and the border readable on the background, and uses every border style", function()
		local seen, rng = {}, lcg(2026)
		local list = P().EmblemList()
		local inList = {}
		for _, i in ipairs(list) do inList[i] = true end
		local palette = {}
		for _, c in ipairs(P().COLORS.background) do palette[c] = true end
		for _ = 1, 300 do
			local d = E().Random(rng)
			truthy(inList[d.e], "emblem " .. tostring(d.e))
			truthy(palette[d.gc])
			truthy(d.b >= 0 and d.b < P().BORDER_COUNT)
			truthy(math.abs(E().Luma(d.ec) - E().Luma(d.gc)) >= E().MIN_CONTRAST, "emblem on background")
			truthy(math.abs(E().Luma(d.bc) - E().Luma(d.gc)) >= E().MIN_CONTRAST, "border on background")
			seen[d.b] = true
		end
		for i = 0, P().BORDER_COUNT - 1 do truthy(seen[i], "border style " .. i) end
	end)

	it("picks only from the emblems it is given (the client cannot load the game's)", function()
		local own = P().EmblemList(false)
		local rng = lcg(3)
		for _ = 1, 50 do truthy(E().Random(rng, own).e >= P().OWN_BASE) end
	end)
end)

describe("Reset", function()
	local TABARD = { t = 1, e = 12, b = 0, gc = 1, bc = 2, ec = 3 }

	it("goes back to the published design", function()
		deepEq(E().Reset(FULL, TABARD), FULL)
	end)

	it("else to the guild tabard's pieces, as a design", function()
		deepEq(E().Reset({ t = 1, e = 4 }, TABARD), { t = 2, e = 12, b = 0, gc = 1, bc = 2, ec = 3 })
		deepEq(E().Reset(nil, TABARD), { t = 2, e = 12, b = 0, gc = 1, bc = 2, ec = 3 })
	end)

	it("else to the starting design; a broken published emblem does not count", function()
		deepEq(E().Reset(nil, nil), P().DEFAULT)
		deepEq(E().Reset({ t = 2 }, { t = 7 }), P().DEFAULT)
		local d = E().Reset(nil, nil)
		d.e = 1
		eq(P().DEFAULT.e, 1006, "Reset hands out a copy")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The renderer on the mock client
---------------------------------------------------------------------------------------------------------------------
describe("the emblem frame", function()
	local function make(size) return A().Emblem.Create(UIParent, size or 96) end

	it("draws the layers of Emblems.Layers, sized and tinted", function()
		local f = make(150)
		f:SetEmblem(FULL, "Iron Wolves")
		deepEq(f.drawn, { field = "media", border = "media", emblem = "media", gloss = "media", frame = "media" })
		local tex = f.tex.emblem
		truthy(tex:IsShown())
		matches(tex:GetTexture(), "emblem_sym_crown")
		local r, g, b = tex:GetVertexColor()
		near(r, 227 / 255, 1e-9); near(g, 180 / 255, 1e-9); near(b, 61 / 255, 1e-9)
		eq(tex:GetWidth(), 69)
		falsy(f.initial:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("without an emblem it is the neutral shield with the initial", function()
		local f = make(64)
		f:SetEmblem(nil, "Iron Wolves")
		eq(f.drawn.emblem, "initial")
		truthy(f.initial:IsShown())
		eq(f.initial:GetText(), "I")
		falsy(f.tex.border:IsShown())
		matches(f.tex.frame:GetTexture(), "emblem_frame_small")
	end)

	it("a game emblem the client cannot load becomes the initial; a border file that does not load becomes our own style", function()
		P().EMBLEM_FILES[3] = 555001
		P().BORDERS[1].file = 555002
		Mock.missingTextures[555001] = true
		Mock.missingTextures[555002] = true
		local f = make(96)
		f:SetEmblem({ t = 1, e = 3, b = 1, gc = 0, bc = 0xFFFFFF, ec = 0xFF0000 }, "Iron Wolves")
		eq(f.drawn.emblem, "initial")
		eq(f.drawn.border, "media")
		matches(f.tex.border:GetTexture(), "emblem_border_1")
		local r, g, b = f.initial:GetTextColor()
		eq(r, 1); eq(g, 0); eq(b, 0)
		Mock.missingTextures[555001] = nil
		f:SetEmblem({ t = 1, e = 3, b = 1, gc = 0, bc = 0xFFFFFF, ec = 0xFF0000 }, "Iron Wolves")
		eq(f.drawn.emblem, "file")
		eq(f.tex.emblem:GetTexture(), 555001)
		falsy(f.initial:IsShown())
		P().EMBLEM_FILES[3] = nil
		P().BORDERS[1].file = nil
	end)

	it("a missing emblem sheet makes every game emblem the initial, and the designer offers only our symbols", function()
		Mock.missingTextures[P().EMBLEM_SHEET.path] = true
		local f = make(96)
		f:SetEmblem({ t = 1, e = 5, gc = 0 }, "Iron Wolves")
		eq(f.drawn.emblem, "initial")
		falsy(A().Emblem.GameEmblemsLoad())
		eq(#A().Emblem.Available(), P().OWN_COUNT)
	end)

	it("with the sheet, the game emblem is the right cell", function()
		local f = make(96)
		f:SetEmblem({ t = 1, e = 17, gc = 0 }, "Iron Wolves")
		eq(f.drawn.emblem, "path")
		eq(f.tex.emblem:GetTexture(), P().EMBLEM_SHEET.path)
		truthy(A().Emblem.GameEmblemsLoad())
	end)

	it("redrawing with another emblem creates no texture (cards are rebound while scrolling)", function()
		local f = make(84)
		f:SetEmblem(FULL, "A")
		local before = f:GetNumRegions()
		f:SetEmblem(nil, "B")
		f:SetEmblem({ t = 1, e = 17, b = 4, gc = 5 }, "C")
		eq(f:GetNumRegions(), before)
	end)
end)
