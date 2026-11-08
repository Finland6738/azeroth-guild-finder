-- AzGF Probe, M0.5: tabard info and tabard pieces catalogue (S8).
-- Lua 5.1. Every game API call goes through pcall. Never record player, guild or realm names: strings returned by the game are
-- reported by length only. The catalogue only stores numbers (fileIDs, RGB). Save() of the tabard is NEVER called.

local Probe = _G.AzGF_Probe
if not Probe then
    return
end

local call = Probe.Call
local out = Probe.Print

local MAX_VARIATION = 10 -- variation indices tried: 1..MAX_VARIATION (the real count is found empirically)
local MAX_STEPS = 600 -- safety cap of CycleVariation steps per variation
local PER_TICK = 8 -- CycleVariation steps per timer tick (/agfp tabard slow: 1)
local TICK_DELAY = 0.02 -- seconds between ticks
local LOAD_WAIT = 3 -- seconds to wait for the model to report its first file

local FIELDS = { "UE", "UB", "UG", "LE", "LB", "LG" }
local GETTERS = {
    UE = "GetUpperEmblemFile", UB = "GetUpperBorderFile", UG = "GetUpperBackgroundFileName",
    LE = "GetLowerEmblemFile", LB = "GetLowerBorderFile", LG = "GetLowerBackgroundFileName",
}
local FIELD_NAMES = {
    UE = "upper emblem", UB = "upper border", UG = "upper background",
    LE = "lower emblem", LB = "lower border", LG = "lower background",
    EC = "emblem texture vertex colour",
}

local function db()
    AzGF_ProbeDB = AzGF_ProbeDB or {}
    AzGF_ProbeDB.tabard = AzGF_ProbeDB.tabard or {}
    return AzGF_ProbeDB.tabard
end

local function buildString()
    local ok, version, build = pcall(GetBuildInfo)
    return ok and (tostring(version) .. "." .. tostring(build)) or "unknown"
end

-- Values ----------------------------------------------------------------------------------------------------------------------
-- Colours may come as 0..1 floats or 0..255 bytes: both end up as one 24-bit integer 0xRRGGBB.
local function colorInt(r, g, b)
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not (r and g and b) then
        return nil
    end
    local scale = (r > 1 or g > 1 or b > 1) and 1 or 255
    local function byte(x)
        return math.max(0, math.min(255, math.floor(x * scale + 0.5)))
    end
    return byte(r) * 65536 + byte(g) * 256 + byte(b)
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- Describes every field of a value (type and value) into lines; colours as RGB; strings by length only (never stored).
local function dump(value, path, lines, depth)
    local t = type(value)
    if t == "table" then
        local r, g, b = rawget(value, "r"), rawget(value, "g"), rawget(value, "b")
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            local a = rawget(value, "a")
            lines[#lines + 1] = string.format("%s = colour RGB(%s, %s, %s)%s = 0x%06X", path, tostring(r), tostring(g), tostring(b),
                type(a) == "number" and (" alpha " .. tostring(a)) or "", colorInt(r, g, b))
            return
        end
        if depth >= 3 then
            lines[#lines + 1] = path .. " = table (depth limit)"
            return
        end
        local keys = sortedKeys(value)
        if #keys == 0 then
            lines[#lines + 1] = path .. " = empty table"
        end
        for _, k in ipairs(keys) do
            dump(value[k], path .. "." .. tostring(k), lines, depth + 1)
        end
    elseif t == "string" then
        lines[#lines + 1] = string.format("%s = string (length %d, value not stored)", path, #value)
    elseif t == "number" or t == "boolean" then
        lines[#lines + 1] = string.format("%s = %s %s", path, t, tostring(value))
    else
        lines[#lines + 1] = string.format("%s = %s", path, t)
    end
end

-- Numbers, booleans and colours of the top level of the tabard info, for the exported catalogue.
local function flatInfo(info)
    local flat = {}
    if type(info) ~= "table" then
        return flat
    end
    for _, k in ipairs(sortedKeys(info)) do
        local v = info[k]
        if type(v) == "number" or type(v) == "boolean" then
            flat[tostring(k)] = v
        elseif type(v) == "table" then
            local c = colorInt(rawget(v, "r"), rawget(v, "g"), rawget(v, "b"))
            if c then
                flat[tostring(k)] = c
            end
        end
    end
    return flat
end

-- S8 part 1: C_GuildInfo.GetGuildTabardInfo("player") ------------------------------------------------------------------------------
local function readInfo()
    local fn = C_GuildInfo and C_GuildInfo.GetGuildTabardInfo
    local result = { lines = {}, apiOk = false, hasTabard = false, summary = "" }
    if type(fn) ~= "function" then
        result.summary = "C_GuildInfo.GetGuildTabardInfo missing"
        result.lines[1] = result.summary
        return result
    end
    local ok, info = pcall(fn, "player")
    if not ok then
        result.summary = "GetGuildTabardInfo(\"player\") raised an error: " .. tostring(info)
        result.lines[1] = result.summary
        return result
    end
    result.apiOk = true
    local inGuild = select(2, pcall(IsInGuild))
    result.lines[#result.lines + 1] = "IsInGuild = " .. tostring(inGuild)
    if type(info) ~= "table" then
        result.lines[#result.lines + 1] = "GetGuildTabardInfo(\"player\") = " .. type(info) .. " (no tabard)"
        result.summary = "no tabard (returned " .. type(info) .. ", inGuild=" .. tostring(inGuild) .. ")"
    else
        result.hasTabard = true
        local fields = {}
        dump(info, "tabardInfo", fields, 0)
        for _, l in ipairs(fields) do
            result.lines[#result.lines + 1] = l
        end
        result.flat = flatInfo(info)
        result.summary = string.format("tabard info: %d fields (see export)", #fields)
    end
    -- the call without an argument is documented too (unit is optional): same table or not?
    local ok2, info2 = pcall(fn)
    result.lines[#result.lines + 1] = "GetGuildTabardInfo() without unit = " .. (ok2 and type(info2) or ("error " .. tostring(info2)))
    db().info = result.lines
    db().infoFlat = result.flat
    db().infoTime = date("%Y-%m-%d %H:%M:%S")
    return result
end

-- S8 part 2: the TabardModel catalogue --------------------------------------------------------------------------------------------
local modelFrame, scratchTexture -- created once: frames cannot be destroyed

local function createModel()
    if modelFrame then
        return modelFrame
    end
    local ok, model = pcall(CreateFrame, "TabardModel", nil, UIParent)
    if not ok or not model then
        return nil, tostring(model)
    end
    -- "hidden": tiny, fully transparent and parked off-screen, but Shown so that the client loads it
    pcall(model.SetSize, model, 32, 32)
    pcall(model.SetPoint, model, "TOPLEFT", UIParent, "TOPLEFT", -400, 400)
    pcall(model.SetAlpha, model, 0)
    if model.EnableMouse then
        pcall(model.EnableMouse, model, false)
    end
    pcall(model.Show, model)
    local okT, tex = pcall(model.CreateTexture, model, nil, "ARTWORK")
    if okT then
        scratchTexture = tex
    end
    modelFrame = model
    return model
end

--- Reads the six file getters plus the colour/coords of the emblem texture. Strings are kept as they are (file names are paths).
local function readRow(model)
    local row = {}
    for _, f in ipairs(FIELDS) do
        local fn = model[GETTERS[f]]
        local ok, v = call(fn, model)
        if ok and v ~= nil then
            row[f] = v
        end
    end
    local tex = scratchTexture
    if tex and type(model.GetUpperEmblemTexture) == "function" then
        pcall(tex.SetTexture, tex, nil)
        pcall(tex.SetVertexColor, tex, 1, 1, 1, 1)
        pcall(tex.ResetTexCoord, tex)
        pcall(model.GetUpperEmblemTexture, model, tex)
        local ok, r, g, b = pcall(tex.GetVertexColor, tex)
        if ok then
            row.EC = colorInt(r, g, b)
        end
        local okC, ulx, uly, _, _, _, _, lrx, lry = pcall(tex.GetTexCoord, tex)
        if okC and ulx then
            row.XY = string.format("%.4f,%.4f,%.4f,%.4f", ulx or 0, uly or 0, lrx or 0, lry or 0)
        end
    end
    return row
end

local function signature(row)
    local parts = {}
    for _, f in ipairs(FIELDS) do
        parts[#parts + 1] = tostring(row[f])
    end
    parts[#parts + 1] = tostring(row.EC)
    parts[#parts + 1] = tostring(row.XY)
    return table.concat(parts, "|")
end

local run -- the running catalogue job, nil when idle

local function finishRun(status, message)
    local job = run
    run = nil
    if not job then
        return
    end
    local cat = job.cat
    cat.done = status == "done"
    cat.status = status
    cat.message = message
    cat.endTime = date("%Y-%m-%d %H:%M:%S")
    db().catalog = cat
    out("tabard catalogue " .. status .. (message and (": " .. message) or "") .. ". /agfp export tabard for the Lua table.")
    if Probe.checks.S8 then
        Probe:Run("S8")
    end
end

-- Turns the full rows of one variation into compact per-field sequences (only the fields that change).
local function compactVariation(job)
    local rows = job.rows
    local v = { index = job.v, steps = #rows, wrapped = job.wrapped, clamped = job.clamped, capped = job.capped, seq = {}, distinct = {} }
    local changed = {}
    for _, f in ipairs({ "UE", "UB", "UG", "LE", "LB", "LG", "EC", "XY" }) do
        local first, differs = rows[1][f], false
        for i = 2, #rows do
            if rows[i][f] ~= first then
                differs = true
                break
            end
        end
        if differs then
            local seq, seen, count = {}, {}, 0
            for i = 1, #rows do
                local value = rows[i][f]
                seq[i] = value == nil and 0 or value
                if not seen[tostring(value)] then
                    seen[tostring(value)] = true
                    count = count + 1
                end
            end
            v.seq[f] = seq
            v.distinct[f] = count
            if f ~= "XY" then
                changed[#changed + 1] = f
            end
        end
    end
    v.changes = table.concat(changed, ",")
    return v
end

local function describeVariation(v)
    if v.error then
        return string.format("variation %d: error %s", v.index, tostring(v.error))
    end
    if v.noChange then
        return string.format("variation %d: no visible change (index unused?)", v.index)
    end
    local parts = {}
    for _, f in ipairs({ "UE", "UB", "UG", "LE", "LB", "LG", "EC", "XY" }) do
        if v.distinct[f] then
            parts[#parts + 1] = string.format("%s(%s)=%d distinct", f, FIELD_NAMES[f] or "texture coords", v.distinct[f])
        end
    end
    return string.format("variation %d: %d steps%s%s%s, changes %s", v.index, v.steps,
        v.wrapped and ", wraps" or "", v.clamped and ", clamps at the end (does not wrap)" or "", v.capped and ", CAPPED" or "",
        #parts > 0 and table.concat(parts, "; ") or "nothing")
end

local function nextVariation(job)
    job.v = job.v + 1
    if job.v > MAX_VARIATION then
        return false
    end
    job.rows, job.phase, job.wrapped, job.clamped, job.capped = nil, "start", false, false, false
    return true
end

-- Restores the model after a variation so the next one starts from the same baseline.
local function restoreBaseline(job)
    local model = job.model
    if job.rows and #job.rows > 1 and not job.wrapped then
        -- the variation clamped or was capped: walk back
        for _ = 1, #job.rows - 1 do
            pcall(model.CycleVariation, model, job.v, -1)
        end
    end
    local row = readRow(model)
    if signature(row) ~= job.baseSig then
        -- could not walk back exactly: reinitialise from the guild colours and take the new state as the baseline
        if type(model.InitializeTabardColors) == "function" then
            pcall(model.InitializeTabardColors, model)
        end
        row = readRow(model)
        job.cat.notes[#job.cat.notes + 1] = string.format("baseline changed after variation %d (model reinitialised)", job.v)
        job.baseSig = signature(row)
        job.baseRow = row
    end
end

local function storeVariation(job, entry)
    job.cat.variations[entry.index] = entry
    out(describeVariation(entry))
end

-- One CycleVariation step (or the bookkeeping of one phase). Returns true when the tick should yield.
local function advance(job)
    local model = job.model
    if job.phase == "start" then
        local row = readRow(model)
        job.rows = { row }
        job.initSig = signature(row)
        job.phase = "cycle"
        return false
    end
    if job.phase == "cycle" or job.phase == "recheck" then
        if job.phase == "cycle" then
            local ok, err = pcall(model.CycleVariation, model, job.v, 1)
            if not ok then
                storeVariation(job, { index = job.v, error = tostring(err) })
                restoreBaseline(job)
                if not nextVariation(job) then
                    finishRun("done")
                end
                return false
            end
        end
        local row = readRow(model)
        local sig = signature(row)
        local steps = #job.rows
        if steps == 1 and sig == job.initSig then
            if job.phase == "cycle" then
                job.phase = "recheck" -- the model may need one more frame to apply the change
                return true
            end
            storeVariation(job, { index = job.v, noChange = true })
            restoreBaseline(job)
            if not nextVariation(job) then
                finishRun("done")
            end
            return false
        end
        job.phase = "cycle"
        if steps > 1 and sig == job.initSig then
            job.wrapped = true
            storeVariation(job, compactVariation(job))
        elseif steps > 1 and sig == signature(job.rows[steps]) then
            job.clamped = true
            storeVariation(job, compactVariation(job))
        else
            job.rows[#job.rows + 1] = row
            if #job.rows - 1 >= MAX_STEPS then
                job.capped = true
                storeVariation(job, compactVariation(job))
            else
                return false
            end
        end
        restoreBaseline(job)
        if not nextVariation(job) then
            finishRun("done")
        end
        return false
    end
    return false
end

local function tick()
    local job = run
    if not job then
        return
    end
    if job.stop then
        finishRun("stopped")
        return
    end
    local budget = job.perTick
    while budget > 0 and run == job do
        budget = budget - 1
        local ok, yield = pcall(advance, job)
        if not ok then
            finishRun("error", tostring(yield))
            return
        end
        if yield then
            break
        end
    end
    if run == job then
        C_Timer.After(TICK_DELAY, tick)
    end
end

local function begin(job)
    local model = job.model
    local row = readRow(model)
    local any = false
    for _, f in ipairs(FIELDS) do
        if row[f] ~= nil then
            any = true
        end
    end
    local cat = job.cat
    if not any then
        cat.notes[#cat.notes + 1] = "the model never returned a file: GetUpper*/GetLower* all nil"
        finishRun("failed", "the TabardModel returned no file (not loaded?)")
        return
    end
    job.baseRow, job.baseSig = row, signature(row)
    cat.start = row
    out(string.format("tabard model ready after %.1f s, baseline UE=%s UB=%s UG=%s; cycling variations 1..%d",
        job.waited, tostring(row.UE), tostring(row.UB), tostring(row.UG), MAX_VARIATION))
    job.v = 0
    nextVariation(job)
    C_Timer.After(TICK_DELAY, tick)
end

local function waitForModel(job)
    if run ~= job then
        return
    end
    local row = readRow(job.model)
    local any = false
    for _, f in ipairs(FIELDS) do
        if row[f] ~= nil then
            any = true
        end
    end
    job.waited = job.waited + 0.1
    if any or job.waited >= LOAD_WAIT then
        begin(job)
    else
        C_Timer.After(0.1, function()
            waitForModel(job)
        end)
    end
end

local function startCatalogue(slow)
    if run then
        out("tabard catalogue already running (/agfp tabard stop to abort)")
        return
    end
    local model, err = createModel()
    if not model then
        local cat = { done = false, status = "failed", message = "CreateFrame(\"TabardModel\") failed: " .. tostring(err), notes = {},
            variations = {}, build = buildString(), time = date("%Y-%m-%d %H:%M:%S") }
        db().catalog = cat
        out(cat.message)
        Probe:Run("S8")
        return
    end
    local cat = { build = buildString(), time = date("%Y-%m-%d %H:%M:%S"), notes = {}, variations = {} }
    -- load the player's own look into the model, as the tabard window does (a local model: nothing is saved)
    if type(model.SetUnit) == "function" then
        pcall(model.SetUnit, model, "player")
    end
    if type(model.InitializeTabardColors) == "function" then
        local ok, e = pcall(model.InitializeTabardColors, model)
        if not ok then
            cat.notes[#cat.notes + 1] = "InitializeTabardColors error: " .. tostring(e)
        end
    else
        cat.notes[#cat.notes + 1] = "InitializeTabardColors missing"
    end
    local okG, isGuild = call(model.IsGuildTabard, model)
    cat.isGuildTabard = okG and isGuild or nil
    cat.hasCycle = type(model.CycleVariation) == "function"
    if not cat.hasCycle then
        cat.status, cat.message = "failed", "CycleVariation missing on the TabardModel"
        db().catalog = cat
        out(cat.message)
        Probe:Run("S8")
        return
    end
    -- never Save(): this probe does not even reference it
    local info = readInfo()
    cat.info = db().infoFlat
    out("tabard catalogue started (slow=" .. tostring(slow and true or false) .. "); IsGuildTabard=" .. tostring(cat.isGuildTabard) ..
        ", guild tabard info: " .. (info.hasTabard and "yes" or "no"))
    run = { model = model, cat = cat, perTick = slow and 1 or PER_TICK, waited = 0, v = 0 }
    waitForModel(run)
end

-- Export: a Lua table the owner can paste back (seeds Data/TabardParts.lua in M3) ------------------------------------------------------
local function lit(v)
    if type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

local function listLines(seq, indent, hexColours)
    local lines, chunk = {}, {}
    for i, v in ipairs(seq) do
        chunk[#chunk + 1] = (hexColours and type(v) == "number") and string.format("0x%06X", v) or lit(v)
        if #chunk == 12 or i == #seq then
            lines[#lines + 1] = indent .. table.concat(chunk, ", ") .. ","
            chunk = {}
        end
    end
    return lines
end

local function catalogueText()
    local cat = db().catalog
    if not cat then
        return "-- no tabard catalogue yet: run /agfp tabard and wait for it to finish"
    end
    local lines = {
        string.format("-- AzGF Probe tabard catalogue (build %s, %s, status %s). Numbers only: fileIDs and RGB (0xRRGGBB).", tostring(cat.build),
            tostring(cat.time), tostring(cat.status)),
        "-- Seeds Data/TabardParts.lua in M3. Each variation lists the value of every changed field after each CycleVariation step.",
        "-- Index 1 of every list is the starting state; steps = list length; wrapped = the cycle returned to the start.",
        "AzGF_TabardCatalog = {",
        string.format("  build = %s, isGuildTabard = %s,", lit(cat.build), tostring(cat.isGuildTabard)),
    }
    if cat.info then
        local keys = sortedKeys(cat.info)
        local parts = {}
        for _, k in ipairs(keys) do
            local v = cat.info[k]
            parts[#parts + 1] = string.format("%s = %s", k, type(v) == "number" and (k:lower():find("color") and string.format("0x%06X", v) or tostring(v)) or tostring(v))
        end
        lines[#lines + 1] = "  guildTabardInfo = { " .. table.concat(parts, ", ") .. " },"
    end
    if cat.start then
        local parts = {}
        for _, f in ipairs({ "UE", "UB", "UG", "LE", "LB", "LG", "EC" }) do
            if cat.start[f] ~= nil then
                parts[#parts + 1] = string.format("%s = %s", f, f == "EC" and string.format("0x%06X", cat.start[f]) or lit(cat.start[f]))
            end
        end
        lines[#lines + 1] = "  start = { " .. table.concat(parts, ", ") .. " },"
    end
    if cat.notes and #cat.notes > 0 then
        for _, n in ipairs(cat.notes) do
            lines[#lines + 1] = "  -- note: " .. n
        end
    end
    lines[#lines + 1] = "  variations = {"
    for i = 1, MAX_VARIATION do
        local v = cat.variations[i]
        if v then
            lines[#lines + 1] = "    -- " .. describeVariation(v)
            if v.error or v.noChange then
                lines[#lines + 1] = string.format("    [%d] = { %s },", i, v.error and ("error = " .. lit(v.error)) or "noChange = true")
            else
                lines[#lines + 1] = string.format("    [%d] = {", i)
                lines[#lines + 1] = string.format("      steps = %d, wrapped = %s, clamped = %s, capped = %s, changes = %s,", v.steps, tostring(v.wrapped and true or false),
                    tostring(v.clamped and true or false), tostring(v.capped and true or false), lit(v.changes))
                for _, f in ipairs({ "UE", "UB", "UG", "LE", "LB", "LG", "EC", "XY" }) do
                    if v.seq[f] then
                        lines[#lines + 1] = string.format("      %s = {", f)
                        for _, l in ipairs(listLines(v.seq[f], "        ", f == "EC")) do
                            lines[#lines + 1] = l
                        end
                        lines[#lines + 1] = "      },"
                    end
                end
                lines[#lines + 1] = "    },"
            end
        end
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end
Probe.exportTexts.tabard = catalogueText

local function catalogueSummary(cat)
    local parts = {}
    for i = 1, MAX_VARIATION do
        local v = cat.variations[i]
        if v and not v.error and not v.noChange then
            parts[#parts + 1] = string.format("v%d:%s x%d", i, v.changes ~= "" and v.changes or "-", v.steps)
        end
    end
    return string.format("catalogue %s (%d changing variations: %s)", tostring(cat.status), #parts, table.concat(parts, " "))
end

-- Check S8 and commands -----------------------------------------------------------------------------------------------------------------
Probe:Register("S8", "Tabard info and TabardModel CycleVariation catalogue (/agfp tabard)", function()
    local info = readInfo()
    for _, l in ipairs(info.lines) do
        out("  " .. l)
    end
    local cat = db().catalog
    local summary = info.summary
    if not cat then
        return "todo", summary .. "; catalogue not run yet (/agfp tabard)"
    end
    summary = summary .. "; " .. (cat.done and catalogueSummary(cat) or ("catalogue " .. tostring(cat.status) .. ": " .. tostring(cat.message)))
    if cat.done then
        local changing = 0
        for _, v in pairs(cat.variations) do
            if v.changes and v.changes ~= "" then
                changing = changing + 1
            end
        end
        return (info.apiOk and changing > 0) and "pass" or "fail", summary
    end
    return cat.status == "failed" and "fail" or "info", summary
end)

Probe.commands.tabard = function(arg)
    arg = (arg or ""):lower()
    if arg == "stop" then
        if run then
            run.stop = true
        else
            out("no tabard catalogue running")
        end
    elseif arg == "info" then
        Probe:Run("S8")
    elseif arg == "status" then
        local cat = db().catalog
        out(run and ("catalogue running: variation " .. tostring(run.v) .. " of " .. MAX_VARIATION) or
            (cat and catalogueSummary(cat) or "no catalogue yet"))
    else
        startCatalogue(arg == "slow")
    end
end

-- /agfp export adds S8 lines: tabard info fields and the catalogue summary
Probe.exportHooks[#Probe.exportHooks + 1] = function()
    local lines = {}
    local d = db()
    if d.info then
        for _, l in ipairs(d.info) do
            lines[#lines + 1] = "S8 tabard info | " .. l
        end
    end
    local cat = d.catalog
    if cat then
        lines[#lines + 1] = string.format("S8 catalogue | status %s | IsGuildTabard %s | %s", tostring(cat.status), tostring(cat.isGuildTabard), cat.message or "")
        for i = 1, MAX_VARIATION do
            if cat.variations and cat.variations[i] then
                lines[#lines + 1] = "S8 catalogue | " .. describeVariation(cat.variations[i])
            end
        end
        for _, n in ipairs(cat.notes or {}) do
            lines[#lines + 1] = "S8 catalogue | note: " .. n
        end
        lines[#lines + 1] = "S8 catalogue | the full lists: /agfp export tabard"
    end
    return lines
end
