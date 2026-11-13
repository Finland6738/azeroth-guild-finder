-- ApplyModel: what the applicant's screens show (SPEC-05 §4, SPEC-07 §7), as plain Lua, no frames. Lua 5.1.
-- UI/Apply.lua (the Apply button and its confirmation) and UI/MyApplication.lua (the tab) copy what this module says.
--
--   Model.Button(reason, info, ctx, L)  -> the Apply button for an answer of Applications:Check (Applications.Decide):
--        { state, shown, enabled, kind ("primary" | "tonal"), label, tooltip = { title, lines }, note, link }
--        ctx = { name (the guild's), place ("card" | "page"), sum, player }
--   Model.Confirm(ctx, L)               -> the confirmation: { title, question, roles = { { bit, key, label } }, rolesHint,
--        privacy, apply, cancel }   ctx = { name, player = { name, classID, level } }
--   Model.MyApplication(rec, ctx, L)    -> the My Application tab: the empty state, or the guild, the state and its
--        explanation, the steps, Withdraw and View guild     ctx = { now, listed (the guild still has a listing),
--        cannotSend (Delivery:CannotSend(): why nothing can go out now, nil when it can) }
--   Model.ShortDate(stamp, L)           -> "15 Nov"
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.ApplyModel, ns.modules = Model, ns.modules or {}
ns.modules.ApplyModel = Model

local type, ipairs, pcall, floor, max, ceil = type, ipairs, pcall, math.floor, math.max, math.ceil

local ROLE_KEYS = { [1] = "tank", [2] = "healer", [4] = "melee", [8] = "ranged" }
Model.ROLE_KEYS = ROLE_KEYS

-- "15 Nov" in this computer's zone; nil for something that is not a time.
function Model.ShortDate(stamp, L)
	if type(stamp) ~= "number" or stamp <= 0 or type(date) ~= "function" then return nil end
	local ok, t = pcall(date, "*t", stamp)
	if not ok or type(t) ~= "table" or not t.month then return nil end
	return L["DATE_SHORT"]:format(t.day, L["MONTH_" .. t.month])
end

-- The requirement that fails, in words: "level 40", "item level 120", or both.
local function failedRequirements(info, ctx, L)
	local sum, parts = ctx.sum or {}, {}
	if info and info.levelOk == false and sum.minL then parts[#parts + 1] = L["APPLY_REQ_LEVEL"]:format(sum.minL) end
	if info and info.ilvlOk == false and sum.minI then parts[#parts + 1] = L["APPLY_REQ_ILVL"]:format(sum.minI) end
	return table.concat(parts, ", ")
end

local function guildOf(rec)
	local _, _, name = ns.Listing.ParseKey(rec and rec.k)
	return name or (rec and rec.k) or ""
end

-- The Apply button for each answer of Applications.Decide (SPEC-05 §4). The guild page writes the label of "ok" in full
-- ("Apply to Aurora") and adds a line under the button (`note`); a card has no room for the line, so the reason is on the
-- button and in its tooltip.
function Model.Button(reason, info, ctx, L)
	local page = ctx.place == "page"
	local b = { state = reason, shown = true, enabled = false, kind = "tonal" }
	if reason == "ok" then
		b.enabled, b.kind = true, "primary"
		b.label = page and L["APPLY_TO"]:format(ctx.name or "") or L["APPLY"]
		b.tooltip = { title = L["APPLY_TO"]:format(ctx.name or ""), lines = { L["APPLY_TIP"] } }
		b.note = L["APPLY_NOTE"]
	elseif reason == "nolisting" or reason == "closed" then
		b.shown = false
		b.note = reason == "closed" and L["GP_APPS_CLOSED"] or nil
	elseif reason == "applied" then
		-- the button leads to the My Application tab (SPEC-05 §4: "link to My Application")
		b.enabled, b.link = true, "MyApplication"
		b.label = L[info and info.state == "received" and "APPLY_STATE_RECEIVED" or "APPLY_STATE_SENT"]
		b.tooltip = { title = b.label, lines = { L["APPLY_OPEN_TAB"] } }
		b.note = L["APPLY_APPLIED_NOTE"]
	elseif reason == "elsewhere" then
		b.label = L["APPLY_ELSEWHERE"]:format(guildOf(info))
		b.tooltip = { title = b.label, lines = { L["APPLY_WITHDRAW_FIRST"] } }
		b.note = L["APPLY_WITHDRAW_FIRST"]
	elseif reason == "cooldown" then
		local when = Model.ShortDate(info and info.untilAt, L) or "?"
		b.label = L["APPLY_AGAIN_ON"]:format(when)
		b.tooltip = { title = b.label, lines = { L["APPLY_COOLDOWN_TIP"] } }
		b.note = L["APPLY_COOLDOWN_TIP"]
	elseif reason == "requirements" then
		b.label = L["TAG_REQ_FAIL"]
		local what = failedRequirements(info, ctx, L)
		local line = what ~= "" and L["APPLY_REQ_FAIL"]:format(what) or L["TAG_REQ_FAIL"]
		b.tooltip = { title = b.label, lines = { line } }
		b.note = line
	elseif reason == "listenonly" then
		b.label = L["APPLY_LISTEN_ONLY"]
		b.tooltip = { title = b.label, lines = { L["APPLY_LISTEN_ONLY_TIP"] } }
		b.note = L["APPLY_LISTEN_ONLY_TIP"]
	elseif reason == "inguild" then
		b.label = L["APPLY_IN_GUILD"]
		b.tooltip = { title = b.label, lines = { L["APPLY_IN_GUILD_TIP"] } }
		b.note = L["APPLY_IN_GUILD_TIP"]
	else   -- "readonly", or an answer this file does not know
		b.label = L["APPLY_READ_ONLY"]
		b.tooltip = { title = b.label, lines = { L["APPLY_READ_ONLY_TIP"] } }
		b.note = L["APPLY_READ_ONLY_TIP"]
	end
	return b
end

---------------------------------------------------------------------------------------------------------------------
-- The confirmation
---------------------------------------------------------------------------------------------------------------------
local function classLabel(classID, L)
	local E = ns.Enums
	local c = E.CLASS_ROLES[classID]
	return c and L["CLASS_" .. c.key] or (E.ClassLabel(classID) or "?")
end

-- "Apply to Aurora with Elarin (Mage 32)?" and the roles the class can play, to tick if the player wants.
function Model.Confirm(ctx, L)
	local p = ctx.player or {}
	local out = {
		title = L["APPLY_TO"]:format(ctx.name or ""),
		question = L["APPLY_CONFIRM"]:format(ctx.name or "", p.name or "?", classLabel(p.classID, L), p.level or 0),
		rolesHint = L["APPLY_ROLES_HINT"], privacy = L["APPLY_PRIVACY"],
		apply = L["APPLY"], cancel = L["ED_CANCEL"], roles = {},
	}
	for _, bit in ipairs(ns.Applications.RolesFor(p.classID)) do
		out.roles[#out.roles + 1] = { bit = bit, key = ROLE_KEYS[bit], label = L["ROLE_" .. ROLE_KEYS[bit]] }
	end
	return out
end

-- The roles ticked (a list of bits) as a mask, nil when none.
function Model.RolesMask(bits)
	local mask = 0
	for _, bit in ipairs(bits or {}) do
		if ROLE_KEYS[bit] and not ns.Enums.HasRole(mask, bit) then mask = mask + bit end
	end
	return mask > 0 and mask or nil
end

---------------------------------------------------------------------------------------------------------------------
-- My Application
---------------------------------------------------------------------------------------------------------------------
-- state -> { title key, body key, kind of the status card }
local STATUS = {
	sent = { "MA_SENT", "MA_SENT_BODY", "gold" },
	received = { "MA_RECEIVED", "MA_RECEIVED_BODY", "ok" },
	accepted = { "MA_ACCEPTED", "MA_ACCEPTED_BODY", "ok" },
	declined = { "MA_DECLINED", "MA_DECLINED_BODY", "bad" },
	withdrawn = { "MA_WITHDRAWN", "MA_WITHDRAWN_BODY", "default" },
	withdrawing = { "MA_WITHDRAWING", "MA_WITHDRAWING_BODY", "default" },
	joined = { "MA_JOINED", "MA_JOINED_BODY", "ok" },           -- accepted because the player joined (M4.6)
	delisted = { "MA_DELISTED", "MA_DELISTED_BODY", "default" },   -- declined because the guild's listing was withdrawn
	expired = { "MA_EXPIRED", "MA_EXPIRED_BODY", "default" },
}

-- The empty state, or the application: { empty } | { k, name, emb?, state, kind, title, body, appliedText, expiresText,
-- roles = { { bit, key, label } }, steps = { { text, on } }, withdraw, viewGuild, again (the date of a cooldown) }.
function Model.MyApplication(rec, ctx, L)
	if type(rec) ~= "table" then
		return { empty = true, title = L["MA_EMPTY_TITLE"], body = L["MA_EMPTY_BODY"], find = L["MA_FIND"] }
	end
	local A = ns.Applications
	local now = ctx.now or 0
	local view = { k = rec.k, name = guildOf(rec), state = rec.state, open = A.IsOpen(rec) }
	local key = (rec.state == "withdrawn" and rec.wd) and "withdrawing" or rec.why or rec.state
	local s = STATUS[key] or STATUS.expired
	view.statusKey, view.title, view.kind = key, L[s[1]], s[3]
	view.body = L[s[2]]:format(view.name)
	-- something still has to go out (the application, or the withdrawal) and the game does not let it (SPEC-01 §8)
	if ctx.cannotSend and (key == "sent" or key == "withdrawing") then
		view.cannotSend = ctx.cannotSend
		view.body = view.body .. " " .. L["MA_CANT_SEND"]
	end
	view.appliedText = L["MA_APPLIED"]:format(ns.BrowseModel.AgeText(max(0, now - (rec.at or now)), L))
	if view.open then
		local days = max(0, ceil((A.ExpiresAt(rec) - now) / 86400))
		view.expiresText = days <= 1 and L["MA_EXPIRES_1"] or L["MA_EXPIRES"]:format(days)
	end
	if rec.state == "declined" and rec.why ~= "delisted" then
		local untilAt = (rec.upd or rec.at or 0) + A.COOLDOWN
		if untilAt > now then view.again = L["APPLY_AGAIN_ON"]:format(Model.ShortDate(untilAt, L) or "?") end
	end
	view.roles = {}
	for _, bit in ipairs(ns.Enums.RoleList(rec.roles or 0)) do
		view.roles[#view.roles + 1] = { bit = bit, key = ROLE_KEYS[bit], label = L["ROLE_" .. ROLE_KEYS[bit]] }
	end
	-- the road: SENT > RECEIVED > ACCEPTED / DECLINED (the reached steps are "on")
	local rank = ({ sent = 1, received = 2, accepted = 3, declined = 3 })[rec.state] or 0
	view.steps = {
		{ text = L["MA_STEP_SENT"], on = rank >= 1 },
		{ text = L["MA_STEP_RECEIVED"], on = rank >= 2 },
		{ text = rec.state == "accepted" and L["MA_STEP_ACCEPTED"] or (rec.state == "declined" and L["MA_STEP_DECLINED"]
			or L["MA_STEP_DECISION"]), on = rank >= 3, bad = rec.state == "declined" },
	}
	view.withdraw = view.open
	view.viewGuild = ctx.listed == true
	view.hint = view.open and L["MA_HINT_OPEN"] or L["MA_HINT_CLOSED"]
	return view
end

if ns.addon then ns.addon.ApplyModel = Model end
