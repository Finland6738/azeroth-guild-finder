-- AzGF Probe, M0.5: texture gallery (S9): banner, parchment, class icon, role icon and emblem candidates.
-- Lua 5.1. Every game API call goes through pcall. Textures are only ever referenced by path, fileID or atlas name:
-- nothing is copied. The candidate list is built from known path patterns; the owner marks each one after looking at it.

local Probe = _G.AzGF_Probe
if not Probe then
    return
end

local call = Probe.Call
local out = Probe.Print

local HEADER_W, HEADER_H = 860, 140 -- the real banner size of the listing header (SPEC-08 section 3)
local CROP = (HEADER_H / HEADER_W) * (16 / 9) -- fraction of the image height visible, assuming a 16:9 source
local PER_TICK = 12 -- gallery cells built per timer tick
local COLS = 7

local function db()
    AzGF_ProbeDB = AzGF_ProbeDB or {}
    local d = AzGF_ProbeDB.textures
    if not d then
        d = {}
        AzGF_ProbeDB.textures = d
    end
    d.marks = d.marks or {} -- key -> "ok" | "bad"
    d.results = d.results or {} -- key -> compact API result text
    d.custom = d.custom or {} -- extra candidates added with /agfp tex: { {kind=, value=} }
    return d
end

-- Candidates ------------------------------------------------------------------------------------------------------------------------
local STATIC = {}

local function add(group, kind, value, label)
    STATIC[#STATIC + 1] = { group = group, kind = kind, value = value, label = label or tostring(value) }
end

-- Banners: loading-screen art under two naming patterns (the owner marks the ones that exist and look good).
local ZONES = {
    "Elwynn", "DunMorogh", "Durotar", "Mulgore", "Teldrassil", "Tirisfal", "Westfall", "Barrens", "Stranglethorn", "Duskwood",
    "Redridge", "Ashenvale", "Stormwind", "Orgrimmar", "Ironforge", "Undercity", "Darnassus", "ThunderBluff", "Winterspring", "Tanaris",
}
for _, zone in ipairs(ZONES) do
    add("banner", "tex", "Interface\\Glues\\LoadingScreens\\LoadScreen" .. zone, "loading " .. zone)
end
for _, zone in ipairs(ZONES) do
    add("banner", "tex", "Interface\\Glues\\LoadingScreens\\LoadingScreen_" .. zone .. "_wide", "loading wide " .. zone)
end
add("banner", "tex", "Interface\\AchievementFrame\\UI-Achievement-Header", "achievement header")
add("banner", "tex", "Interface\\AchievementFrame\\UI-Achievement-Guild-Header", "guild achievement header")
add("banner", "tex", "Interface\\GuildFrame\\GuildFrame-TopBanner", "guild frame banner")

-- Parchment backgrounds for the main window and the text area.
add("parchment", "tex", "Interface\\AchievementFrame\\UI-Achievement-Parchment", "achievement parchment")
add("parchment", "tex", "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal", "achievement parchment horizontal")
add("parchment", "tex", "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal-Desaturated", "achievement parchment desaturated")
add("parchment", "tex", "Interface\\QuestFrame\\QuestBookBG", "quest book")
add("parchment", "tex", "Interface\\ItemTextFrame\\ItemText-Parchment-Light", "item text parchment")
add("parchment", "tex", "Interface\\Stationery\\StationeryTest1", "stationery")
add("parchment", "tex", "Interface\\Spellbook\\Spellbook-Page-1", "spellbook page")
add("parchment", "tex", "Interface\\FrameGeneral\\UI-Background-Marble", "marble")
add("parchment", "atlas", "QuestBG-Parchment", "atlas QuestBG-Parchment")
add("parchment", "atlas", "UI-Achievement-Parchment-Horizontal", "atlas achievement parchment")

-- Class icons: the texture file and the atlas, both tried for every class.
local CLASSES = {
    { "Warrior", "warrior" }, { "Paladin", "paladin" }, { "Hunter", "hunter" }, { "Rogue", "rogue" }, { "Priest", "priest" },
    { "DeathKnight", "deathknight" }, { "Shaman", "shaman" }, { "Mage", "mage" }, { "Warlock", "warlock" }, { "Monk", "monk" },
    { "Druid", "druid" }, { "DemonHunter", "demonhunter" }, { "Evoker", "evoker" },
}
for _, c in ipairs(CLASSES) do
    add("class", "tex", "Interface\\Icons\\ClassIcon_" .. c[1], "ClassIcon_" .. c[1])
end
for _, c in ipairs(CLASSES) do
    add("class", "atlas", "classicon-" .. c[2], "atlas classicon-" .. c[2])
end
add("class", "tex", "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES", "class sheet (whole)")

-- Role icons: the sheets and the atlases.
add("role", "tex", "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", "LFG roles sheet")
add("role", "tex", "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", "LFG portrait roles sheet")
for _, role in ipairs({ "tank", "healer", "dps" }) do
    add("role", "atlas", "roleicon-" .. role, "atlas roleicon-" .. role)
end
for _, role in ipairs({ "tank", "healer", "dps" }) do
    add("role", "atlas", "roleicon-tiny-" .. role, "atlas roleicon-tiny-" .. role)
end
for _, role in ipairs({ "Tank", "Healer", "DPS" }) do
    add("role", "atlas", "UI-LFG-RoleIcon-" .. role, "atlas UI-LFG-RoleIcon-" .. role)
end
for _, role in ipairs({ "tank", "healer", "dps" }) do
    add("role", "atlas", "groupfinder-icon-role-large-" .. role, "atlas groupfinder-icon-role-large-" .. role)
end

-- Guild emblem textures.
add("emblem", "tex", "Interface\\GuildFrame\\GuildEmblemsLG_01", "emblems sheet large")
add("emblem", "tex", "Interface\\GuildFrame\\GuildEmblems_01", "emblems sheet")
add("emblem", "tex", "Interface\\GuildFrame\\GuildLogo-NoLogo", "no logo")
add("emblem", "atlas", "communities-guildbanner-background", "atlas guild banner background")
add("emblem", "atlas", "communities-guildbanner-border", "atlas guild banner border")
add("emblem", "atlas", "communities-guildbanner-emblem", "atlas guild banner emblem")

local GROUP_ORDER = { "banner", "parchment", "class", "role", "emblem", "tabard", "custom" }

local function keyOf(kind, value)
    return kind .. ":" .. tostring(value)
end

local list, listKeys -- the full candidate list (static, tabard samples from S8, custom), rebuilt by candidates()

--- Static candidates, then up to 3 distinct fileIDs of every tabard piece found by the S8 catalogue, then the custom ones.
local function candidates()
    list, listKeys = {}, {}
    local function push(c)
        c.key = keyOf(c.kind, c.value)
        if not listKeys[c.key] then
            list[#list + 1] = c
            listKeys[c.key] = #list
        end
    end
    for _, c in ipairs(STATIC) do
        push({ group = c.group, kind = c.kind, value = c.value, label = c.label })
    end
    local cat = AzGF_ProbeDB and AzGF_ProbeDB.tabard and AzGF_ProbeDB.tabard.catalog
    if cat and cat.variations then
        local names = { UE = "emblem", UB = "border", UG = "background" }
        for _, f in ipairs({ "UE", "UB", "UG" }) do
            local seen, n = {}, 0
            for i = 1, 10 do
                local v = cat.variations[i]
                local seq = v and v.seq and v.seq[f]
                for _, id in ipairs(seq or {}) do
                    if n < 3 and type(id) == "number" and id > 0 and not seen[id] then
                        seen[id], n = true, n + 1
                        push({ group = "tabard", kind = "tex", value = id, label = "tabard " .. names[f] .. " " .. id })
                    end
                end
            end
        end
    end
    for _, c in ipairs(db().custom) do
        push({ group = "custom", kind = c.kind, value = c.value, label = "custom " .. tostring(c.value) })
    end
    return list
end

-- API test of one candidate --------------------------------------------------------------------------------------------------------------
local scratchFrame, scratchTex

local function scratch()
    if not scratchTex then
        scratchFrame = CreateFrame("Frame", nil, UIParent)
        scratchFrame:SetSize(16, 16)
        -- shown but invisible and off-screen, so that the client really loads the texture
        scratchFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -300, 300)
        scratchFrame:SetAlpha(0)
        scratchFrame:Show()
        scratchTex = scratchFrame:CreateTexture(nil, "ARTWORK")
    end
    return scratchTex
end

local function brief(v)
    if v == nil then
        return "nil"
    elseif type(v) == "string" then
        return v
    end
    return tostring(v)
end

--- Applies the candidate to the scratch texture and returns { pass, text, fileID }.
local function apiTest(c)
    local t = scratch()
    pcall(t.SetTexture, t, nil)
    pcall(t.ResetTexCoord, t)
    local parts, pass, fileID = {}, false, nil
    if c.kind == "atlas" then
        local okE, exists = call(C_Texture and C_Texture.GetAtlasExists, c.value)
        parts[#parts + 1] = "exists=" .. (okE and tostring(exists) or "n/a")
        local okS, err = pcall(t.SetAtlas, t, c.value)
        parts[#parts + 1] = "SetAtlas=" .. (okS and "ok" or ("error " .. tostring(err)))
        local okG, got = pcall(t.GetAtlas, t)
        parts[#parts + 1] = "GetAtlas=" .. (okG and brief(got) or "error")
        pass = okS and okG and got ~= nil and not (okE and exists == false)
        local okI, info = call(C_Texture and C_Texture.GetAtlasInfo, c.value)
        if okI and type(info) == "table" then
            parts[#parts + 1] = string.format("size=%sx%s file=%s", tostring(info.width), tostring(info.height), brief(info.file or info.filename))
            fileID = type(info.file) == "number" and info.file or nil
        end
    else
        local okS, err = pcall(t.SetTexture, t, c.value)
        parts[#parts + 1] = "SetTexture=" .. (okS and "ok" or ("error " .. tostring(err)))
        local okG, got = pcall(t.GetTexture, t)
        parts[#parts + 1] = "GetTexture=" .. (okG and brief(got) or "error")
        pass = okS and okG and got ~= nil
        local okF, id = call(t.GetTextureFileID, t)
        if okF and id ~= nil then
            parts[#parts + 1] = "fileID=" .. brief(id)
            fileID = type(id) == "number" and id or nil
        end
        local okP, path = call(t.GetTextureFilePath, t)
        if okP and path ~= nil then
            parts[#parts + 1] = "path=" .. brief(path)
        end
        if type(c.value) == "number" then
            fileID = c.value
            local okN, name = call(C_Texture and C_Texture.GetFilenameFromFileDataID, c.value)
            parts[#parts + 1] = "known=" .. (okN and (name ~= nil and "yes" or "no") or "n/a")
        end
    end
    local okL, loaded = call(t.IsObjectLoaded, t)
    if okL then
        parts[#parts + 1] = "loaded=" .. tostring(loaded)
    end
    pcall(t.SetTexture, t, nil)
    return { pass = pass, text = table.concat(parts, " "), fileID = fileID }
end

local function markOf(c)
    return db().marks[c.key]
end

-- Gallery frame -----------------------------------------------------------------------------------------------------------------------------
local G = { cells = {}, selected = nil, parchment = true, center = 0.5 }

local function applyHeader(c)
    local tex = G.headerTex
    if not tex then
        return
    end
    pcall(tex.SetTexture, tex, nil)
    pcall(tex.ResetTexCoord, tex)
    if not c then
        return
    end
    if c.kind == "atlas" then
        pcall(tex.SetAtlas, tex, c.value)
    else
        pcall(tex.SetTexture, tex, c.value)
        if c.group == "banner" or c.group == "parchment" or c.group == "custom" then
            local top = math.max(0, math.min(1 - CROP, G.center - CROP / 2))
            pcall(tex.SetTexCoord, tex, 0, 1, top, top + CROP)
        end
    end
end

local function refreshCell(i)
    local cell, c = G.cells[i], list and list[i]
    if not cell or not c then
        return
    end
    local mark = markOf(c)
    local r, g, b = 0.25, 0.25, 0.25
    if mark == "ok" then
        r, g, b = 0.1, 0.75, 0.2
    elseif mark == "bad" then
        r, g, b = 0.85, 0.15, 0.15
    end
    cell.bg:SetColorTexture(r, g, b, 1)
    if i == G.selected then
        cell.label:SetTextColor(1, 0.9, 0.2)
    else
        cell.label:SetTextColor(1, 1, 1)
    end
end

local function selectCandidate(i)
    local c = list and list[i]
    if not c then
        return
    end
    local previous = G.selected
    G.selected = i
    applyHeader(c)
    local r = db().results[c.key]
    local mark = markOf(c) or "not marked"
    if G.info then
        G.info:SetText(string.format("#%d of %d  [%s]  %s  %s\n%s\nmark: %s", i, #list, c.group, c.kind, tostring(c.value),
            r or "(not tested)", mark))
    end
    if previous then
        refreshCell(previous)
    end
    refreshCell(i)
end

local function setMark(i, mark)
    local c = list and list[i]
    if not c then
        out("no candidate #" .. tostring(i) .. " (open /agfp gallery to see the numbers)")
        return
    end
    db().marks[c.key] = (mark ~= "clear") and mark or nil
    if not db().results[c.key] then
        db().results[c.key] = apiTest(c).text
    end
    out(string.format("#%d [%s] %s -> %s", i, c.group, tostring(c.value), mark == "clear" and "mark cleared" or mark))
    refreshCell(i)
    if G.selected == i then
        selectCandidate(i)
    end
end

local function setupParchment()
    local tex = G.parchment_tex
    if not tex then
        return
    end
    if not G.parchment then
        tex:Hide()
        return
    end
    tex:Show()
    tex:SetColorTexture(0.93, 0.87, 0.72, 1)
    -- parchment fade from 40 % downwards: transparent at the top, nearly opaque at the bottom (API differs between builds)
    local okColor, top = pcall(CreateColor, 0.93, 0.87, 0.72, 0)
    local _, bottom = pcall(CreateColor, 0.93, 0.87, 0.72, 0.92)
    local done = false
    if okColor and tex.SetGradient then
        done = pcall(tex.SetGradient, tex, "VERTICAL", bottom, top)
    end
    if not done and tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, "VERTICAL", 0.93, 0.87, 0.72, 0.92, 0.93, 0.87, 0.72, 0)
    end
end

local function buildCell(i)
    local c = list[i]
    local content = G.content
    local cell = CreateFrame("Button", nil, content)
    cell:SetSize(112, 74)
    local row, col = math.floor((i - 1) / COLS), (i - 1) % COLS
    cell:SetPoint("TOPLEFT", content, "TOPLEFT", col * 116, -row * 78)
    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints()
    local wide = c.group == "banner" or c.group == "parchment" or c.group == "custom"
    cell.thumb = cell:CreateTexture(nil, "ARTWORK")
    cell.thumb:SetPoint("TOP", cell, "TOP", 0, -2)
    cell.thumb:SetSize(wide and 108 or 52, wide and 56 or 52)
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cell.label:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 3, 2)
    cell.label:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 2)
    cell.label:SetJustifyH("LEFT")
    cell.label:SetText(i .. " " .. c.group)
    if c.kind == "atlas" then
        pcall(cell.thumb.SetAtlas, cell.thumb, c.value)
    else
        pcall(cell.thumb.SetTexture, cell.thumb, c.value)
    end
    cell:SetScript("OnClick", function()
        selectCandidate(i)
    end)
    cell:SetScript("OnEnter", function(self)
        if GameTooltip then
            pcall(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetText, GameTooltip, "#" .. i .. " " .. tostring(c.label))
            pcall(GameTooltip.AddLine, GameTooltip, c.kind .. ": " .. tostring(c.value), 1, 1, 1, true)
            pcall(GameTooltip.Show, GameTooltip)
        end
    end)
    cell:SetScript("OnLeave", function()
        if GameTooltip then
            pcall(GameTooltip.Hide, GameTooltip)
        end
    end)
    cell.key = c.key
    G.cells[i] = cell
    if not db().results[c.key] then
        db().results[c.key] = apiTest(c).text
    end
    refreshCell(i)
end

-- Builds the missing cells a few per tick, so opening the gallery never freezes the client.
local function ensureCells()
    candidates()
    -- the list changes when the S8 catalogue is run again: drop the cells from the first one that no longer matches
    for i = 1, #G.cells do
        local cell = G.cells[i]
        if cell and (not list[i] or cell.key ~= list[i].key) then
            for j = i, #G.cells do
                if G.cells[j] then
                    G.cells[j]:Hide()
                end
                G.cells[j] = nil
            end
            break
        end
    end
    local rows = math.ceil(#list / COLS)
    G.content:SetSize(COLS * 116, math.max(10, rows * 78))
    local function step()
        local built = 0
        while #G.cells < #list and built < PER_TICK do
            built = built + 1
            local ok, err = pcall(buildCell, #G.cells + 1)
            if not ok then
                out("gallery cell error: " .. tostring(err))
                G.cells[#G.cells + 1] = false
            end
        end
        if #G.cells < #list then
            C_Timer.After(0.02, step)
        elseif G.info and not G.selected then
            selectCandidate(1)
        end
    end
    step()
end

local function buildGallery()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "AzGF_ProbeGallery", UIParent, template)
    f:SetSize(HEADER_W + 40, 640)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("AzGF Probe texture gallery (drag to move; click a thumbnail; /agfp mark <n> ok|bad)")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- header preview: the exact banner size, parchment fade from 40 % down, dark sample text on top
    local header = CreateFrame("Frame", nil, f)
    header:SetSize(HEADER_W, HEADER_H)
    header:SetPoint("TOPLEFT", 20, -38)
    header:EnableMouseWheel(true)
    local back = header:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 1)
    G.headerTex = header:CreateTexture(nil, "BACKGROUND", nil, 1)
    G.headerTex:SetAllPoints()
    G.parchment_tex = header:CreateTexture(nil, "ARTWORK")
    G.parchment_tex:SetPoint("BOTTOMLEFT")
    G.parchment_tex:SetPoint("BOTTOMRIGHT")
    G.parchment_tex:SetHeight(HEADER_H * 0.6)
    local sample = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sample:SetPoint("BOTTOMLEFT", 16, 40)
    sample:SetTextColor(0.15, 0.08, 0.02)
    sample:SetText("Sample Guild  -  Recruiting Mythic raiders")
    local sample2 = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sample2:SetPoint("BOTTOMLEFT", 16, 14)
    sample2:SetTextColor(0.15, 0.08, 0.02)
    sample2:SetText("Dark text on the lower 60 %: still readable? Small text, subtitle, 20:00 Tue/Thu, 25 members")
    header:SetScript("OnMouseWheel", function(_, delta)
        G.center = math.max(CROP / 2, math.min(1 - CROP / 2, G.center - delta * 0.04))
        applyHeader(list and list[G.selected])
    end)
    setupParchment()

    G.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    G.info:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    G.info:SetWidth(HEADER_W - 250)
    G.info:SetJustifyH("LEFT")
    G.info:SetJustifyV("TOP")
    G.info:SetHeight(48)

    local function button(text, x, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(76, 22)
        b:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", x, -6)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    button("Bad", 0, function()
        setMark(G.selected or 0, "bad")
    end)
    button("OK", -80, function()
        setMark(G.selected or 0, "ok")
    end)
    button("Parchment", -160, function()
        G.parchment = not G.parchment
        setupParchment()
    end)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -32)
    hint:SetText("mouse wheel on the banner moves the crop")

    local scroll = CreateFrame("ScrollFrame", "AzGF_ProbeGalleryScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -62)
    scroll:SetPoint("BOTTOMRIGHT", -36, 16)
    G.content = CreateFrame("Frame", nil, scroll)
    G.content:SetSize(COLS * 116, 10)
    scroll:SetScrollChild(G.content)
    G.frame = f
end

local function openGallery(index)
    if not G.frame then
        local ok, err = pcall(buildGallery)
        if not ok then
            out("gallery error: " .. tostring(err))
            G.frame = nil
            return
        end
    end
    G.frame:Show()
    ensureCells()
    if index then
        selectCandidate(index)
    end
end

-- Export -------------------------------------------------------------------------------------------------------------------------------------
local function galleryText()
    candidates()
    local d = db()
    local lines = { "-- AzGF Probe texture gallery (S9). n | group | kind | value | API result | mark" }
    for i, c in ipairs(list) do
        local r = d.results[c.key] or (apiTest(c).text)
        lines[#lines + 1] = string.format("%d | %s | %s | %s | %s | %s", i, c.group, c.kind, tostring(c.value), r, d.marks[c.key] or "-")
    end
    lines[#lines + 1] = "-- Marked OK (fileID from the API where the client reports one):"
    for i, c in ipairs(list) do
        if d.marks[c.key] == "ok" then
            local t = apiTest(c)
            lines[#lines + 1] = string.format("ok | %s | %s | %s | fileID %s", c.group, c.kind, tostring(c.value), tostring(t.fileID))
        end
    end
    return table.concat(lines, "\n")
end
Probe.exportTexts.gallery = galleryText

local function summaryLines()
    candidates()
    local d, total, tested, okMarks, badMarks = db(), {}, {}, {}, {}
    for _, g in ipairs(GROUP_ORDER) do
        total[g], tested[g], okMarks[g], badMarks[g] = 0, 0, 0, 0
    end
    for _, c in ipairs(list) do
        total[c.group] = total[c.group] + 1
        local r = d.results[c.key]
        if r then
            tested[c.group] = tested[c.group] + 1
        end
        local m = d.marks[c.key]
        if m == "ok" then
            okMarks[c.group] = okMarks[c.group] + 1
        elseif m == "bad" then
            badMarks[c.group] = badMarks[c.group] + 1
        end
    end
    return total, tested, okMarks, badMarks
end

-- Check S9 and commands ---------------------------------------------------------------------------------------------------------------------
Probe:Register("S9", "Texture gallery: banners, parchment, class and role icons (/agfp gallery)", function()
    candidates()
    local d, apiOk, byGroup = db(), 0, {}
    for _, c in ipairs(list) do
        local t = apiTest(c)
        d.results[c.key] = t.text
        if t.pass then
            apiOk = apiOk + 1
            byGroup[c.group] = (byGroup[c.group] or 0) + 1
        end
    end
    local total, _, okMarks, badMarks = summaryLines()
    local parts = {}
    for _, g in ipairs(GROUP_ORDER) do
        if total[g] > 0 then
            parts[#parts + 1] = string.format("%s api %d/%d, marked ok %d bad %d", g, byGroup[g] or 0, total[g], okMarks[g], badMarks[g])
        end
    end
    local summary = string.format("%d candidates, %d accepted by the API; %s", #list, apiOk, table.concat(parts, "; "))
    if okMarks.banner + okMarks.parchment + okMarks.class + okMarks.role + okMarks.custom == 0 then
        return "todo", summary .. "; nothing marked yet (/agfp gallery, /agfp mark <n> ok|bad)"
    end
    local enough = okMarks.banner + okMarks.custom >= 12 and okMarks.parchment >= 1
    return enough and "pass" or "info", summary
end)

Probe.commands.gallery = function()
    openGallery()
end

Probe.commands.mark = function(arg, rest)
    local n = tonumber(arg)
    local word = (rest or ""):lower()
    if not n or (word ~= "ok" and word ~= "bad" and word ~= "clear") then
        out("usage: /agfp mark <n> ok|bad|clear (n is the number shown in the gallery)")
        return
    end
    candidates()
    setMark(n, word)
end

Probe.commands.tex = function(arg, rest)
    local text = ((arg or "") .. " " .. (rest or "")):gsub("^%s+", ""):gsub("%s+$", ""):gsub('^"(.*)"$', "%1")
    if text == "" then
        out("usage: /agfp tex <path|fileID|atlas:name>  (tests one extra candidate and adds it to the gallery)")
        return
    end
    local kind, value = "tex", text
    if text:lower():sub(1, 6) == "atlas:" then
        kind, value = "atlas", text:sub(7)
    elseif tonumber(text) then
        value = tonumber(text)
    end
    local custom = db().custom
    local known = false
    for _, c in ipairs(custom) do
        if c.kind == kind and c.value == value then
            known = true
        end
    end
    if not known then
        custom[#custom + 1] = { kind = kind, value = value }
    end
    candidates()
    local index = listKeys[keyOf(kind, value)]
    local c = list[index]
    local t = apiTest(c)
    db().results[c.key] = t.text
    out(string.format("#%d %s %s: %s%s", index, kind, tostring(value), t.pass and "API accepts it. " or "API refuses it. ", t.text))
    openGallery(index)
end

Probe.exportHooks[#Probe.exportHooks + 1] = function()
    local d = AzGF_ProbeDB and AzGF_ProbeDB.textures
    if not d then
        return {}
    end
    candidates()
    local total, tested, okMarks, badMarks = summaryLines()
    local lines = {}
    for _, g in ipairs(GROUP_ORDER) do
        if total[g] > 0 then
            lines[#lines + 1] = string.format("S9 gallery | %s | %d candidates, %d tested, marked ok %d, bad %d", g, total[g], tested[g], okMarks[g], badMarks[g])
        end
    end
    lines[#lines + 1] = "S9 gallery | the full list with marks: /agfp export gallery"
    return lines
end
