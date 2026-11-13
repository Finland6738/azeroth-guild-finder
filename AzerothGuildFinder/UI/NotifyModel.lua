-- NotifyModel: the floating notification icon of the Guild Master and the officers (SPEC-07 §6, mockup 05), as plain Lua
-- with no frames. UI/Notify.lua copies what this module says; the tests run it without a client.
--
--   Model.Visible(ctx)             -> shown, why: should the icon be on screen? ctx = { role, key, listed (the guild has a listing),
--                                     enabled (the notifyIcon option), onlyWhenPending (option), pending (count), forced (the menu
--                                     was used to show it for now) }; why is "role" | "listing" | "off" | "idle" | nil
--   Model.Badge(count)             -> "" | "7" | "99+"
--   Model.Quick(ctx, L)            -> { rows (the last 5 pending, newest first, as ApplicationsModel rows), total, more, moreText,
--                                     title, guild, empty }  ctx = { recs, now, busy, guild }
--   Model.Alert(k, id, state, oldState, source, ownKey) -> "chat" | "silent" | nil: a record that just arrived and is open
--   Model.ChatLine(rec, L)         -> "New application from Elarin (Mage 32)" and the hyperlink "Open"
--   Model.Menu(ctx, L)             -> the entries of the right-click menu: { key, text, checked, kind }
--   Model.Pulse(prevPending, pending) -> true when the number went up (a new application)
--   Model.ToSaved / FromSaved      the position saved per character (point, relPoint, x, y in screen units)
--   Model.Clamp(pos, w, h, sw, sh) keeps a saved position on the screen
--   Model.LINK / Model.ParseLink   the chat link that opens the Applications panel
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.NotifyModel, ns.modules = Model, ns.modules or {}
ns.modules.NotifyModel = Model

local type, ipairs, tostring, tonumber = type, ipairs, tostring, tonumber
local floor, min, max = math.floor, math.min, math.max

Model.QUICK_MAX = 5
Model.SIZE = 60
Model.LINK = "addon:AzerothGuildFinder:applications"

local function AppsModel() return ns.AppsModel end

-- Only the Guild Master and the officers of a guild that has a listing; then the options.
function Model.Visible(ctx)
	ctx = ctx or {}
	if not (AppsModel() and AppsModel().CanSee(ctx.role)) or type(ctx.key) ~= "string" then return false, "role" end
	if ctx.listed ~= true then return false, "listing" end
	if ctx.forced then return true end
	if ctx.enabled ~= true then return false, "off" end
	if ctx.onlyWhenPending == true and (tonumber(ctx.pending) or 0) < 1 then return false, "idle" end
	return true
end

function Model.Badge(count)
	if type(count) ~= "number" or count ~= count or count < 1 then return "" end
	if count > 99 then return "99+" end
	return tostring(floor(count))
end

function Model.Pulse(previous, now)
	return type(previous) == "number" and type(now) == "number" and now > previous
end

function Model.Quick(ctx, L)
	local pending = AppsModel().Split(ctx.recs, ctx.now)
	local out = { rows = {}, total = #pending, title = L["NOTIFY_TITLE"], guild = ctx.guild }
	local rctx = { now = ctx.now, busy = ctx.busy, manual = ctx.manual, canAct = true }
	for i = 1, min(#pending, Model.QUICK_MAX) do
		local row = AppsModel().Row(pending[i], rctx, L)
		row.line = L["NOTIFY_QUICK_LINE"]:format(row.classLabel or "?", row.level or 0, row.ageText or "")
		if not row.classLabel or not row.level then row.line = row.ageText or "" end
		out.rows[#out.rows + 1] = row
	end
	out.more = max(0, out.total - #out.rows)
	out.moreText = out.more > 0 and L["NOTIFY_MORE"]:format(out.more) or nil
	out.empty = out.total == 0 and L["NOTIFY_EMPTY"] or nil
	out.openText = L["NOTIFY_OPEN_ALL"]
	return out
end

-- A record that arrives straight from the applicant (no `source`) says it in chat and plays the sound; one that comes
-- from another officer's sync (login catch-up) only moves the badge, so a returning officer is not flooded.
function Model.Alert(k, id, state, oldState, source, ownKey)
	if k == nil or k ~= ownKey or oldState ~= nil then return nil end
	if state ~= "received" and state ~= "sent" then return nil end
	if source == "sync" or source == "limit" or source == "sweep" then return "silent" end
	return "chat"
end

function Model.ChatLine(rec, L)
	local who = type(rec.who) == "string" and rec.who:match("^[^%-]+") or "?"
	local class = rec.cls and ns.Enums.CLASS_ROLES[rec.cls]
	local details = (class and rec.lvl) and L["NOTIFY_CHAT_DETAILS"]:format(L["CLASS_" .. class.key], rec.lvl) or nil
	local text = details and L["NOTIFY_CHAT_NEW"]:format(who, details) or L["NOTIFY_CHAT_NEW_BARE"]:format(who)
	local link = ("|H%s|h|cff3fc7eb[%s]|r|h"):format(Model.LINK, L["NOTIFY_CHAT_OPEN"])
	return text .. " " .. link, text, link
end

function Model.ParseLink(link)
	return type(link) == "string" and link == Model.LINK
end

-- The right-click menu: lock, only when pending, sound, hide.
function Model.Menu(ctx, L)
	return {
		{ key = "title", text = L["NOTIFY_MENU_TITLE"], kind = "title" },
		{ key = "lock", text = L["NOTIFY_MENU_LOCK"], checked = ctx.locked == true, kind = "check" },
		{ key = "onlyWhenPending", text = L["NOTIFY_MENU_PENDING"], checked = ctx.onlyWhenPending == true, kind = "check" },
		{ key = "sound", text = L["NOTIFY_MENU_SOUND"], checked = ctx.sound == true, kind = "check" },
		{ key = "hide", text = L["NOTIFY_MENU_HIDE"], hint = "/gf notify", kind = "action" },
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------------------------------------------------
function Model.ToSaved(point, relPoint, x, y)
	if type(point) ~= "string" then return nil end
	return { point = point, relPoint = relPoint or point, x = tonumber(x) or 0, y = tonumber(y) or 0 }
end

function Model.FromSaved(pos)
	if not (ns.Config and ns.Config.IsPos(pos)) then return nil end
	return pos.point, pos.relPoint or pos.point, pos.x, pos.y
end

Model.DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 360, y = 120 }

-- A position far off the screen (another resolution) is pulled back so that the icon cannot be lost. Only CENTER-based
-- and corner-based points matter for the limit; the check uses the offset against the half sizes.
function Model.Clamp(pos, size, screenW, screenH)
	if not (ns.Config and ns.Config.IsPos(pos)) then return Model.DEFAULT_POS end
	if type(screenW) ~= "number" or type(screenH) ~= "number" then return pos end
	local limitX, limitY = screenW, screenH
	local x = min(limitX, max(-limitX, pos.x))
	local y = min(limitY, max(-limitY, pos.y))
	if x == pos.x and y == pos.y then return pos end
	return { point = pos.point, relPoint = pos.relPoint, x = x, y = y }
end

if ns.addon then ns.addon.NotifyModel = Model end
