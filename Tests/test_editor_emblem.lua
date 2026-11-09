-- M3.6: the emblem in the listing editor (UI/EditorSteps.lua, Identity) and the designer (UI/EmblemDesigner.lua) on the mock
-- client: the guild tabard is the default, a tabard the client has not sent yet is waited for (GUILDTABARD_UPDATE), a tabard
-- that changed is offered again, and the designer's sections, Random and Reset write the draft. Also the emblem on the editor's
-- preview and on the guild page. The mock player is "Testchar", Horde, on "Test Realm"; the guild is "Iron Wolves".

local GUILD = "Iron Wolves"
local KEY = "TestRealm|Horde|" .. GUILD

local function A() return AzerothGuildFinder end
local function editor() return A().Editor end
local function OL() return A().OwnListing end
local function main() return A().Main end
local function P() return A().TabardParts end
local L = setmetatable({}, { __index = function(_, key) return LibStub("AceLocale-3.0"):GetLocale("AzerothGuildFinder")[key] end })

local TABARD = { backgroundColor = { r = 74 / 255, g = 20 / 255, b = 20 / 255 }, borderColor = { r = 1, g = 1, b = 1 },
	emblemColor = { r = 227 / 255, g = 180 / 255, b = 61 / 255 }, emblemStyle = 12 }
local TABARD_EMB = { t = 1, e = 12, b = 0, gc = 0x4A1414, bc = 0xFFFFFF, ec = 0xE3B43D }

local function lcg(seed)
	local state = seed
	return function(n)
		state = (state * 1103515245 + 12345) % 2147483648
		return math.floor(state / 65536) % n + 1
	end
end

local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end

local function open(tabard)
	Mock.guild.Set{ name = GUILD, myRank = 0, members = { { name = "Jaina", rank = 1 } }, tabard = tabard }
	main():Show()
	editor():GoTo(1)
	return editor().pages.identity.frame
end

describe("the emblem of the Identity step", function()
	it("a guild with a tabard gets it as the emblem by default, and the checklist item turns green", function()
		local page = open(TABARD)
		A().Emblems.Equal(editor():Get("emb"), TABARD_EMB)
		deepEq(editor():Get("emb"), TABARD_EMB)
		deepEq(OL():Draft().emb, TABARD_EMB)
		eq(page.embMode:GetSelected(), 1)
		eq(page.embStatus:GetText(), L["ED_EMB_TABARD_OK"])
		falsy(page.embAction:IsShown())
		eq(page.emblem.drawn.emblem, "path", "the game's emblem 12, from the sheet")
		local chk
		for _, it in ipairs(editor():View().items) do if it.id == "emblem" then chk = it end end
		eq(chk.state, "ok")
		eq(#Mock.errors, 0)
	end)

	it("while the client has not sent the tabard it says so, and GUILDTABARD_UPDATE fills it in", function()
		local page = open(nil)
		isNil(editor():Get("emb"))
		eq(page.embStatus:GetText(), L["ED_EMB_TABARD_PENDING"])
		eq(page.embMode.segments[1]:GetAlpha(), 0.5)
		Mock.guild.tabard = TABARD
		Mock.Fire("GUILDTABARD_UPDATE")
		deepEq(editor():Get("emb"), TABARD_EMB)
		eq(page.embStatus:GetText(), L["ED_EMB_TABARD_OK"])
		eq(page.embMode.segments[1]:GetAlpha(), 1)
	end)

	it("a guild without a tabard is told so after the wait and is offered the designer; Guild tabard does nothing", function()
		local page = open(nil)
		Mock.Advance(A().Emblem.TABARD_WAIT + 1)
		eq(page.embStatus:GetText(), L["ED_EMB_NO_TABARD"])
		eq(page.embMode:GetSelected(), 2)
		truthy(page.embAction:IsShown())
		eq(page.embAction:GetLabel(), L["ED_EMB_DESIGN"])
		click(page.embMode.segments[1])
		isNil(editor():Get("emb"))
		eq(page.embMode:GetSelected(), 2)
		eq(page.emblem.drawn.emblem, "initial")
		eq(page.emblem.initial:GetText(), "I")
	end)

	it("a tabard that changed since it was copied is offered again with Update emblem", function()
		local page = open(TABARD)
		local changed = {}
		for k, v in pairs(TABARD) do changed[k] = v end
		changed.emblemStyle = 40
		Mock.guild.tabard = changed
		Mock.Fire("GUILDTABARD_UPDATE")
		eq(editor():Get("emb").e, 12, "nothing changes by itself")
		eq(page.embStatus:GetText(), L["ED_EMB_TABARD_CHANGED"])
		eq(page.embAction:GetLabel(), L["ED_EMB_UPDATE"])
		click(page.embAction)
		eq(editor():Get("emb").e, 40)
		eq(page.embStatus:GetText(), L["ED_EMB_TABARD_OK"])
	end)

	it("the editor's preview card and the publish page draw the emblem", function()
		open(TABARD)
		local host = main().hosts[main():CurrentPage()]
		eq(host.mini.emblem.drawn.emblem, "path")
		eq(host.mini.emblem.drawn.field, "media")
	end)
end)

describe("the emblem designer", function()
	local function design(tabard)
		local page = open(tabard)
		click(page.embMode.segments[2])
		return page, page.designer
	end

	it("Custom emblem opens the designer on a design of the tabard's pieces, and the draft follows", function()
		local page, d = design(TABARD)
		truthy(d:IsShown())
		deepEq(editor():Get("emb"), { t = 2, e = 12, b = 0, gc = 0x4A1414, bc = 0xFFFFFF, ec = 0xE3B43D })
		eq(page.embMode:GetSelected(), 2)
		eq(page.embStatus:GetText(), L["ED_EMB_CUSTOM_NOTE"])
		eq(d.emblemStep.text:GetText(), L["EMB_PAGE"]:format(1, 11))
		eq(#Mock.errors, 0)
	end)

	it("without a tabard the design starts from the default", function()
		local _, d = design(nil)
		deepEq(editor():Get("emb"), P().DEFAULT)
		eq(d.preview.drawn.emblem, "media")
	end)

	it("the background, border and emblem swatches set the colours", function()
		local _, d = design(nil)
		click(d.bgRow.swatches[3])
		eq(editor():Get("emb").gc, P().COLORS.background[3])
		truthy(d.bgRow.swatches[3].selected)
		click(d.borderRow.swatches[2])
		eq(editor():Get("emb").bc, P().COLORS.border[2])
		click(d.emblemRow.swatches[4])
		eq(editor():Get("emb").ec, P().COLORS.emblem[4])
		eq(OL():Draft().emb.ec, P().COLORS.emblem[4], "saved as the draft at once")
	end)

	it("the border style arrows go round the styles", function()
		local _, d = design(nil)
		eq(editor():Get("emb").b, 0)
		click(d.borderStep.back)
		eq(editor():Get("emb").b, P().BORDER_COUNT - 1)
		eq(d.borderStep.text:GetText(), L["EMB_BORDER_STYLE"]:format(P().BORDER_COUNT, P().BORDER_COUNT, L["EMB_BORDER_notched"]))
		click(d.borderStep.next)
		click(d.borderStep.next)
		eq(editor():Get("emb").b, 1)
	end)

	it("the emblem grid pages through the game's emblems and then our symbols; a tile picks the emblem", function()
		local _, d = design(nil)
		eq(d.page, 11, "the default (our crown) is on the last page")
		eq(d.tiles[7].index, 1006)
		truthy(d.tiles[7].selected)
		falsy(d.tiles[9]:IsShown(), "8 symbols on the last page")
		click(d.emblemStep.next)
		eq(d.page, 11, "the last page stays")
		for _ = 1, 10 do click(d.emblemStep.back) end
		eq(d.page, 1)
		eq(d.tiles[1].index, 0)
		click(d.tiles[5])
		eq(editor():Get("emb").e, 4)
		truthy(d.tiles[5].selected)
		eq(d.page, 1, "picking does not move the page")
		click(d.bgRow.swatches[2])
		eq(d.page, 1, "nor does a colour")
	end)

	it("Random draws a valid design; Reset goes back to the tabard, then to the published design", function()
		local _, d = design(TABARD)
		d:Random(lcg(11))
		local drawn = editor():Get("emb")
		deepEq(A().Emblems.Sanitize(drawn), drawn)
		eq(drawn.t, 2)
		click(d.reset)
		deepEq(editor():Get("emb"), { t = 2, e = 12, b = 0, gc = 0x4A1414, bc = 0xFFFFFF, ec = 0xE3B43D })
		-- once a design is published, Reset returns to it
		click(d.bgRow.swatches[1])
		local published = editor():Get("emb")
		local fields = editor():Fields()
		fields.sub, fields.desc, fields.lang1, fields.lang, fields.tags, fields.pace = "Friendly", string.rep("a", 40), 1, 1, { 1 }, 2
		fields.rec, fields.want = 1, { [0] = 15 }
		editor():Patch(fields)
		truthy(editor():Publish())
		click(d.emblemRow.swatches[2])
		click(d.reset)
		deepEq(editor():Get("emb"), published)
	end)

	it("the Random button works with the client's own generator", function()
		local _, d = design(nil)
		click(d.random)
		deepEq(A().Emblems.Sanitize(editor():Get("emb")), editor():Get("emb"))
		eq(#Mock.errors, 0)
	end)

	it("Done closes the designer and the card shows the design", function()
		local page, d = design(nil)
		click(d.emblemRow.swatches[2])
		click(d.done)
		falsy(d:IsShown())
		eq(page.embMode:GetSelected(), 2)
		local r, g, b = page.emblem.tex.emblem:GetVertexColor()
		eq(r, 1); eq(g, 1); eq(b, 1)
		click(page.embAction)
		truthy(d:IsShown(), "Design emblem opens it again on the same design")
		eq(editor():Get("emb").ec, 0xFFFFFF)
	end)

	it("Guild tabard after a design takes the tabard back and closes the designer", function()
		local page, d = design(TABARD)
		click(d.bgRow.swatches[1])
		click(page.embMode.segments[1])
		deepEq(editor():Get("emb"), TABARD_EMB)
		falsy(d:IsShown())
		click(page.embMode.segments[2])
		eq(editor():Get("emb").gc, P().COLORS.background[1], "the last design comes back")
	end)

	it("when the client cannot load the game's emblem sheet, only our symbols are offered and shown", function()
		Mock.missingTextures[P().EMBLEM_SHEET.path] = true
		local _, d = design(nil)
		eq(d.emblemStep.text:GetText(), L["EMB_PAGE"]:format(1, 1))
		eq(d.tiles[1].index, P().OWN_BASE)
		falsy(d.tiles[9]:IsShown())
		for _ = 1, 20 do d:Random() end
		truthy(editor():Get("emb").e >= P().OWN_BASE)
	end)

	it("Discard changes empties the draft: the tabard is the emblem again, and the open designer shows it", function()
		local _, d = design(TABARD)
		click(d.bgRow.swatches[5])
		editor():Discard()
		deepEq(editor():Get("emb"), TABARD_EMB)
		deepEq(d:Get(), { t = 2, e = 12, b = 0, gc = 0x4A1414, bc = 0xFFFFFF, ec = 0xE3B43D })
		eq(#Mock.errors, 0)
	end)
end)

describe("the emblem on the guild page and in the list", function()
	it("the guild page draws the listing's emblem at 150 px", function()
		A().Catalog:PutSummary({ k = "TestRealm|Horde|Aurora", rev = 1, upd = GetServerTime() - 60, first = 1760000000, own = "a1b2c3d4",
			sub = "Hi", lang = 1, lang1 = 1, tags = { 1 }, pace = 2, rec = 1, want = { [0] = 15 }, minL = 1,
			emb = { t = 2, e = 1001, b = 3, gc = 0x1D3A22, bc = 0xE3B43D, ec = 0xF1ECE0 } })
		main():Show()
		A().Browse:OpenGuild("TestRealm|Horde|Aurora")
		local h = main().hosts.GuildPage
		eq(h.emblem.emblemSize, 150)
		eq(h.emblem.drawn.emblem, "media")
		matches(h.emblem.tex.emblem:GetTexture(), "emblem_sym_star8")
		matches(h.emblem.tex.border:GetTexture(), "emblem_border_3")
		eq(#Mock.errors, 0)
	end)
end)
