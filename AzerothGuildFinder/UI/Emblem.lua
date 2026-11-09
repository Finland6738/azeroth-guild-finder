-- Emblem: the guild emblem on screen and the guild tabard as the game gives it (SPEC-08 §2, ADR 0007, M3.6). Lua 5.1.
--
--   Emblem.Create(parent, size)      a `size` px frame (48, 64, 96 and 150 are the sizes it is drawn for; any size works)
--       e:SetEmblem(emb, name)        draws a listing's emblem (nil or invalid: the neutral shield with the guild's initial)
--       e.drawn                       what each layer shows now: { field = "media", border = "file" | "media", emblem =
--                                     "file" | "path" | "media" | "initial", ... } (tests, /gf debug)
--   Emblem.ReadTabard()              -> emb (t = 1) | nil, state: "ok" | "noguild" | "pending" (in a guild, the client has not
--                                     sent the tabard yet: wait for GUILDTABARD_UPDATE) | "none" (the guild has no tabard)
--   Emblem.GameEmblemsLoad()         whether this client can draw the game's emblem sheet (else the designer offers only the
--                                     addon's own symbols)
--   Emblem.ApplyPiece(texture, piece) draws one piece of TabardParts on a texture: true, or false when the client cannot load it
-- Bus: TABARD_UPDATED() when GUILDTABARD_UPDATE (or a change of guild) may have changed what ReadTabard answers.
--
-- The layers, their sizes and colours come from Emblems.Layers (pure, tested): the same emblem looks the same on every client.
-- A game piece the client cannot load (SetTexture answers false) is replaced by its fallback: the addon's own drawing of a
-- border style, the guild's initial instead of an emblem. Nothing here ever changes the real tabard.
local ADDON_NAME, ns = ...
ns = ns or {}
local Emblem = {}
ns.Emblem, ns.modules = Emblem, ns.modules or {}
ns.modules.Emblem = Emblem

local W, Skin = ns.Widgets, ns.Skin
local type, ipairs, pairs, pcall = type, ipairs, pairs, pcall

local function Emblems() return ns.Emblems end
local function Parts() return ns.TabardParts end

Emblem.TABARD_WAIT = 10        -- seconds after the first look before "pending" becomes "none" without a GUILDTABARD_UPDATE

---------------------------------------------------------------------------------------------------------------------
-- One piece on a texture
---------------------------------------------------------------------------------------------------------------------
local function setTexture(tex, value)
	local ok, result = pcall(tex.SetTexture, tex, value)
	return ok and result ~= false
end

-- piece = { media = name } | { file = fileID } | { path = "...", coords = { l, r, t, b } } (TabardParts.Emblem / Border, or a
-- layer of Emblems.Layers). Returns true when the texture shows it, and which kind it used.
function Emblem.ApplyPiece(tex, piece)
	if type(piece) ~= "table" then return false end
	local ok, kind
	if piece.file then ok, kind = setTexture(tex, piece.file), "file"
	elseif piece.path then ok, kind = setTexture(tex, piece.path), "path"
	elseif piece.media then ok, kind = setTexture(tex, W.Media(piece.media)), "media"
	else return false end
	local c = piece.coords
	if ok and c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) else tex:SetTexCoord(0, 1, 0, 1) end
	return ok, kind
end

-- Whether the game's emblem sheet loads in this client (asked once; a client without it gets the addon's symbols only).
function Emblem.GameEmblemsLoad()
	if Emblem.gameLoads == nil then
		local probe = Emblem.probeFrame or CreateFrame("Frame")
		Emblem.probeFrame = probe
		local tex = probe:CreateTexture(nil, "ARTWORK")
		Emblem.gameLoads = Emblem.ApplyPiece(tex, Parts().Emblem(0)) and true or false
	end
	return Emblem.gameLoads
end

-- The emblem indices the designer offers on this client.
function Emblem.Available()
	return Parts().EmblemList(Emblem.GameEmblemsLoad())
end

---------------------------------------------------------------------------------------------------------------------
-- The emblem frame
---------------------------------------------------------------------------------------------------------------------
local LAYER = {   -- draw layer and sublevel of each layer of Emblems.Layers
	field = { "ARTWORK", 0 }, border = { "ARTWORK", 1 }, emblem = { "ARTWORK", 2 },
	gloss = { "OVERLAY", 0 }, frame = { "OVERLAY", 1 },
}

local function place(region, frame, rect)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", frame, "TOPLEFT", rect[1], -rect[2])
	region:SetSize(rect[3], rect[4])
end

local function initialFont()
	local font = Skin.Font("display")
	local file = font and font.GetFont and font:GetFont()
	if type(file) ~= "string" then file = (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF" end
	return file
end

local function showInitial(frame, layer)
	local fs = frame.initial
	place(fs, frame, layer.rect)
	fs:SetFont(initialFont(), layer.fontPx, "OUTLINE")
	local c = layer.color
	fs:SetTextColor(c[1], c[2], c[3], 1)
	fs:SetText(layer.text)
	fs:Show()
	frame.drawn.emblem = "initial"
end

local function texFor(frame, id)
	local tex = frame.tex[id]
	if not tex then
		local spec = LAYER[id] or { "ARTWORK", 0 }
		tex = frame:CreateTexture(nil, spec[1], nil, spec[2])
		frame.tex[id] = tex
	end
	return tex
end

local Methods = {}

-- Draws `emb` (a listing's emblem) for the guild `name`. Safe with any input: an invalid emblem is the neutral shield.
function Methods:SetEmblem(emb, name)
	local size = self.emblemSize
	local spec = Emblems().Layers(emb, size, name)
	self.spec, self.drawn = spec, {}
	for _, tex in pairs(self.tex) do tex:Hide() end
	self.initial:Hide()
	for _, layer in ipairs(spec.layers) do
		if layer.id == "initial" then
			showInitial(self, layer)
		else
			local tex = texFor(self, layer.id)
			local ok, kind = Emblem.ApplyPiece(tex, layer)
			if not ok and layer.fallback then
				if layer.fallback.id == "initial" then
					showInitial(self, layer.fallback)
				else
					ok, kind = Emblem.ApplyPiece(tex, layer.fallback)
				end
			end
			if ok then
				place(tex, self, layer.rect)
				local c = layer.color
				if c then tex:SetVertexColor(c[1], c[2], c[3], 1) else tex:SetVertexColor(1, 1, 1, 1) end
				tex:Show()
				self.drawn[layer.id] = kind
			end
		end
	end
	self.shadow:SetShown(true)
	return self.drawn
end

function Emblem.Create(parent, size)
	size = size or 64
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.emblemSize = size
	f.tex, f.drawn = {}, {}
	f.shadow = f:CreateTexture(nil, "BACKGROUND")
	f.shadow:SetTexture(W.Media("emblem_field"))
	f.shadow:SetVertexColor(0.1, 0.05, 0, 0.35)
	f.shadow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -math.floor(size * 0.04 + 0.5))
	f.shadow:SetSize(size, size)
	f.initial = f:CreateFontString(nil, "ARTWORK")
	f.initial:SetJustifyH("CENTER")
	f.initial:Hide()
	for id in pairs(LAYER) do texFor(f, id) end   -- every texture now: binding a card while scrolling creates nothing
	for k, fn in pairs(Methods) do f[k] = fn end
	f:SetEmblem(nil, nil)
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- The guild tabard
---------------------------------------------------------------------------------------------------------------------
-- Reads the guild tabard now (see the header for the states). A first "pending" starts the wait: after TABARD_WAIT
-- seconds without a GUILDTABARD_UPDATE the answer becomes "none" (the guild has no tabard). `noWait`: only look.
function Emblem.ReadTabard(noWait)
	local G = ns.Compat.Guild
	if not G.InGuild() then return nil, "noguild" end
	local emb = Emblems().FromTabardInfo((G.TabardInfo()))
	if emb then return emb, "ok" end
	if Emblem.tabardHeard or Emblem.tabardWaited then return nil, "none" end
	if not Emblem.tabardTimer and not noWait then
		local gen = (Emblem.tabardGen or 0) + 1
		Emblem.tabardGen, Emblem.tabardTimer = gen, true
		ns.Compat.After(Emblem.TABARD_WAIT, function()
			if Emblem.tabardGen ~= gen then return end
			Emblem.tabardWaited, Emblem.tabardTimer = true, nil
			if ns.Bus then ns.Bus:Emit("TABARD_UPDATED") end
		end)
	end
	return nil, "pending"
end

function Emblem.OnTabardEvent(event)
	if event == "PLAYER_GUILD_UPDATE" then
		-- another guild (or none): what was heard about the old tabard does not count any more
		Emblem.tabardHeard, Emblem.tabardWaited, Emblem.tabardTimer = nil, nil, nil
		Emblem.tabardGen = (Emblem.tabardGen or 0) + 1
	else
		Emblem.tabardHeard = true
	end
	if ns.Bus then ns.Bus:Emit("TABARD_UPDATED") end
end

if CreateFrame then
	local events = CreateFrame("Frame")
	events:RegisterEvent("GUILDTABARD_UPDATE")
	events:RegisterEvent("PLAYER_GUILD_UPDATE")
	events:SetScript("OnEvent", function(_, event) Emblem.OnTabardEvent(event) end)
	Emblem.events = events
end

function Emblem.DebugLines()
	local P = Parts()
	local _, state = Emblem.ReadTabard(true)
	Emblem.GameEmblemsLoad()
	return { ("Emblems: catalogue %s, %d game emblems (sheet %s), %d own symbols, %d border styles; tabard %s"):format(
		P.PROVISIONAL and "provisional (M0.7)" or ("verified " .. tostring(P.VERIFIED)), P.EMBLEM_COUNT,
		Emblem.gameLoads and "loads" or "missing", P.OWN_COUNT, P.BORDER_COUNT, state) }
end

if ns.addon then
	ns.addon.Emblem = Emblem
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Emblems", function() return Emblem.DebugLines() end) end
end
