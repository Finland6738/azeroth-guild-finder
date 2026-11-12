-- MyGuildModel: what "My Guild" shows to each role, as plain Lua with no frames (SPEC-06 §1, SPEC-00 §5, mockup 06, M3.8).
-- UI/MyGuild.lua draws what this module says; the tests run it without a client. Lua 5.1.
--
--   Model.HasListing(status)      the guild has a listing people can see (the catalog says listed or inactive)
--   Model.Kind(ctx)               "listing" | "loading" | "none": what the page holds
--   Model.View(ctx)               the kind plus every control of the page, per role (below)
--   Model.Matrix(L)               every role against every state of the listing: { role, state, tabs, view } rows (the tests)
--
-- ctx = { role = "none"|"member"|"officer"|"gm", status = Catalog:Status(guildKey) (nil without an entry),
--         waiting = OwnListing:Waiting() }
--
-- The rules of SPEC-00 §5, one line each:
--   member,  listing     My Guild, the guild's page read-only
--   member,  no listing  My Guild, "Your guild has no listing yet"        (while the copy may still come: "waiting")
--   officer, listing     My Guild, the page read-only, and Applications (a placeholder until M4)
--   officer, no listing  My Guild, "Your guild has no listing yet"
--   gm,      listing     My Guild with Edit listing and Delist, and Applications
--   gm,      no listing  no My Guild at all: only Create Listing (the editor)
--   no guild             Find a Guild and My Application
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.MyGuildModel, ns.modules = Model, ns.modules or {}
ns.modules.MyGuildModel = Model

local ipairs = ipairs

Model.ROLES = { "none", "member", "officer", "gm" }
-- The states of the listing a role can be in (Matrix): the catalog's statuses ("none" = no entry), plus "waiting" for a copy still on its way.
Model.STATES = { "none", "waiting", "listed", "inactive", "hidden", "delisted" }

-- True when the guild has a listing that others can see: it is what adds Applications and removes Create Listing.
function Model.HasListing(status)
	return status == "listed" or status == "inactive"
end

-- What the page holds: the guild's page ("listing"), the wait for its copy ("loading") or the empty state ("none").
function Model.Kind(ctx)
	if Model.HasListing(ctx.status) then return "listing" end
	if ctx.waiting == true then return "loading" end
	return "none"
end

local function inGuild(role) return role == "member" or role == "officer" or role == "gm" end

-- The page for one role in one state. Fields:
--   page       true when My Guild is a tab of this role in this state (a Guild Master without a listing has none)
--   kind       "listing" | "loading" | "none" (nil when there is no page)
--   edit, delist       the Guild Master's two buttons          readOnly   the "only the Guild Master can edit" note
--   applications       the placeholder for the Applications that arrive with M4 (officers and the Guild Master)
--   copyMessage        a message to copy for the Guild Master (a member or an officer, nothing listed yet)
--   roleLabelKey       the locale key of the role's name
function Model.View(ctx)
	local role = ctx.role
	local view = { role = role, page = false, edit = false, delist = false, readOnly = false, applications = false,
		copyMessage = false }
	if not inGuild(role) then return view end
	local kind = Model.Kind(ctx)
	if role == "gm" and kind ~= "listing" then return view end   -- the editor is this role's only panel
	view.page, view.kind = true, kind
	view.roleLabelKey = "MG_ROLE_" .. role
	if kind == "listing" then
		view.edit, view.delist = role == "gm", role == "gm"
		view.readOnly = role ~= "gm"
		view.applications = role == "officer" or role == "gm"
	elseif kind == "none" then
		view.copyMessage = true   -- only members and officers get here
	end
	return view
end

-- Every role against every state: the table the tests check against SPEC-00 §5. `Nav` gives the tabs.
function Model.Matrix()
	local rows = {}
	for _, role in ipairs(Model.ROLES) do
		for _, state in ipairs(Model.STATES) do
			local ctx = { role = role, status = (state ~= "waiting" and state ~= "none") and state or nil,
				waiting = state == "waiting" }
			local tabs = ns.Nav and ns.Nav.TabsFor(role, Model.HasListing(ctx.status)) or {}
			rows[#rows + 1] = { role = role, state = state, ctx = ctx, tabs = tabs, view = Model.View(ctx) }
		end
	end
	return rows
end

if ns.addon then ns.addon.MyGuildModel = Model end
