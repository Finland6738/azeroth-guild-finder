-- M3.2: the editor's shell (UI/Editor.lua) on the mock client: who sees it, the stepper, the placeholder pages and the step
-- registration API, the auto-saved draft, the live preview, the "Before publishing" checklist and its links, the main button
-- and the reasons it is off (checklist, Guild Master, the 5-minute limit), Save changes, Discard changes and Delist.
-- The mock player is "Testchar", Horde, on "Test Realm"; the guild is "Iron Wolves".

local GUILD = "Iron Wolves"
local KEY = "TestRealm|Horde|" .. GUILD

local function A() return AzerothGuildFinder end
local function main() return A().Main end
local function editor() return A().Editor end
local function OL() return A().OwnListing end
local function host() return main().hosts[main():CurrentPage()] end
local function snack() return A().Widgets.Snackbar.Current() end
local function click(f) Mock.RunScript(f, "OnClick", "LeftButton") end

local function asLeader()
	Mock.guild.Set{ name = GUILD, myRank = 0, members = { { name = "Jaina", rank = 1 }, { name = "Garrosh", rank = 3 } } }
end

-- A listing that satisfies every item of the checklist.
local function full(extra)
	local t = { sub = "Friendly raiders", desc = "We raid on weekends and we like to chat in voice.", lang1 = 1, lang = 1, tags = { 1, 2 },
		pace = 2, days = 21, t0 = 1140, t1 = 1380, rec = 1, apps = true, want = { [0] = 15 }, newb = true, minL = 30,
		emb = { t = 2, e = 0 }, disc = "wolves1", cont = { "Thrall" }, note = "Voice required" }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

-- Opens the window on the editor as the Guild Master of a guild with no listing.
local function open()
	asLeader()
	main():Show()
	return host()
end

local function stepLabels(h)
	local out = {}
	for i, b in ipairs(h.stepButtons) do out[i] = b.label:GetText() end
	return out
end

local function rowTexts(card)
	local out = {}
	for _, row in ipairs(card.rows) do if row:IsShown() then out[#out + 1] = row.text:GetText() end end
	return out
end

local function rowFor(card, id)
	for _, row in ipairs(card.rows) do if row:IsShown() and row.item.id == id then return row end end
end

local function publishedStatus() return OL():Status() end

describe("who sees the editor", function()
	it("a Guild Master without a listing gets it as the Create Listing tab, on its first step", function()
		local h = open()
		eq(main():CurrentTab(), "CreateListing")
		eq(main():CurrentPage(), "CreateListing")
		eq(main().title:GetText(), "Identity")
		eq(h.stepText:GetText(), "STEP 1 OF 7")
		deepEq(stepLabels(h), { "Identity", "About", "Activity", "Recruitment", "Requirements", "Contact", "Preview & publish" })
		falsy(h.blocked:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("a member, an officer and a player without a guild have no Create Listing tab", function()
		for _, rank in ipairs({ 3, 1 }) do
			Mock.guild.Set{ name = GUILD, myRank = rank }
			main():Show()
			for _, tab in ipairs(main().book:Tabs()) do ne(tab, "CreateListing") end
		end
		Mock.guild.Leave()
		for _, tab in ipairs(main().book:Tabs()) do ne(tab, "CreateListing") end
	end)

	it("an officer who somehow reaches the page sees a note over it and cannot save, publish or delist", function()
		Mock.guild.Set{ name = GUILD, myRank = 1 }
		main():Show()
		main():Select("MyGuild")
		main():Push("ListingEditor")
		local h = host()
		eq(main():CurrentPage(), "ListingEditor")
		truthy(h.blocked:IsShown())
		eq(h.blocked.text:GetText(), "Only the Guild Master can create or edit the listing.")
		eq(editor():Set("sub", "Mine now"), true)
		isNil(OL():Draft(), "nothing is saved")
		eq(editor().failed, "not-leader")
		eq(snack(), "You are no longer the Guild Master: the change was not saved.")
		eq(h.draft:GetText(), "The draft could not be saved")
		editor():Patch(full())
		falsy(h.publish.enabledState)
		eq(h.reason:GetText(), "You are no longer the Guild Master: the change was not saved.")
		eq(editor():Publish(), false)
		eq(publishedStatus(), "none")
		eq(#Mock.errors, 0)
	end)

	it("the Guild Master losing the guild master rank while the editor is open covers the page and turns Publish off", function()
		local h = open()
		editor():Patch(full())
		truthy(h.publish.enabledState)
		Mock.guild.SetMyRank(1)
		-- the tab goes away with the role; the shell's own check also stands on its own
		editor():Evaluate()
		eq(editor().action.kind, "role")
		eq(editor():Publish(), false)
		eq(publishedStatus(), "none")
		eq(#Mock.errors, 0)
	end)
end)

describe("the stepper", function()
	it("Next and Back move one step, the title bar and the step text follow", function()
		local h = open()
		falsy(h.back.enabledState, "no Back on the first step")
		click(h.next)
		eq(editor():Step(), 2)
		eq(main().title:GetText(), "About")
		eq(h.stepText:GetText(), "STEP 2 OF 7")
		truthy(h.back.enabledState)
		click(h.back)
		eq(editor():Step(), 1)
		eq(main().title:GetText(), "Identity")
	end)

	it("a click on a step goes there, the active one is marked", function()
		local h = open()
		click(h.stepButtons[4])
		eq(editor():Step(), 4)
		eq(main().title:GetText(), "Recruitment")
		truthy(h.stepButtons[4].active)
		falsy(h.stepButtons[1].active)
		click(h.stepButtons[1])
		truthy(h.stepButtons[1].active)
		falsy(h.stepButtons[4].active)
	end)

	it("stops at the ends: no Next on the last step, GoTo ignores steps that do not exist", function()
		local h = open()
		for _ = 1, 10 do click(h.next) end
		eq(editor():Step(), 7)
		falsy(h.next.enabledState)
		eq(main().title:GetText(), "Preview & publish")
		eq(editor():GoTo(8), false)
		eq(editor():GoTo(0), false)
		eq(editor():GoTo("2"), false)
		eq(editor():Step(), 7)
		eq(editor():Next(), false)
		eq(editor():Back(), true)
		eq(editor():Step(), 6)
	end)

	it("the first six steps show their page and the right column, the last one the publish page across", function()
		local h = open()
		truthy(h.stepArea:IsShown()) truthy(h.column:IsShown()) falsy(h.publishArea:IsShown())
		editor():GoTo(7)
		falsy(h.stepArea:IsShown()) falsy(h.column:IsShown()) truthy(h.publishArea:IsShown())
		editor():GoTo(3)
		truthy(h.stepArea:IsShown()) truthy(h.column:IsShown()) falsy(h.publishArea:IsShown())
	end)

	it("only the page of the current step is shown", function()
		open()
		editor():GoTo(1)
		local first = editor().pages.identity.frame
		truthy(first:IsShown())
		editor():GoTo(2)
		falsy(first:IsShown())
		truthy(editor().pages.about.frame:IsShown())
	end)

	it("the step you were on is still there after the window is closed and opened", function()
		open()
		editor():GoTo(5)
		main():Hide()
		main():Show()
		eq(editor():Step(), 5)
		eq(main().title:GetText(), "Requirements")
	end)
end)

describe("pluggable steps", function()
	it("a step that nobody registered says that it arrives in a later version (every step has its page since M3.5: the registration is taken away here)", function()
		open()
		for i = 4, 6 do
			editor().defs[A().EditorModel.StepId(i)] = nil
			editor():GoTo(i)
			local page = editor().pages[A().EditorModel.StepId(i)]
			truthy(page.placeholder)
			matches(page.frame.soon:GetText(), "arrives in a later version")
		end
	end)

	it("a registered step is built once, shown every time, and told when the fields change from outside", function()
		local built, shown, hidden, refreshed = 0, 0, 0, 0
		local seen
		truthy(editor().RegisterStep("about", {
			Build = function(page, ed) built = built + 1; seen = ed; page.mark = true end,
			OnShow = function(page, ed) shown = shown + 1 end,
			OnHide = function(page, ed) hidden = hidden + 1 end,
			Refresh = function(page, ed) refreshed = refreshed + 1 end,
		}))
		open()
		eq(built, 0, "not built until shown")
		editor():GoTo(2)
		eq(built, 1) eq(shown, 1)
		truthy(editor().pages.about.frame.mark)
		eq(seen, editor(), "the page gets the editor to read and write fields with")
		falsy(editor().pages.about.placeholder)
		editor():GoTo(3)
		eq(hidden, 1)
		editor():GoTo(2)
		eq(built, 1) eq(shown, 2)
		editor():Patch({ sub = "x" })
		editor():Discard()
		eq(refreshed, 1)
		eq(#Mock.errors, 0)
	end)

	it("registering after the placeholder was shown replaces it", function()
		open()
		editor().defs.recruitment = nil
		editor():GoTo(4)
		truthy(editor().pages.recruitment.placeholder)
		local built = 0
		editor().RegisterStep("recruitment", { Build = function() built = built + 1 end })
		eq(built, 1, "the step on screen is rebuilt at once")
		falsy(editor().pages.recruitment.placeholder)
	end)

	it("only the six steps can be registered, with a table", function()
		falsy(editor().RegisterStep("publish", {}))
		falsy(editor().RegisterStep("nothing", {}))
		falsy(editor().RegisterStep("about", "text"))
		falsy(editor().RegisterStep(nil, {}))
		for _, id in ipairs({ "identity", "about", "activity", "recruitment", "requirements", "contact" }) do
			truthy(editor().RegisterStep(id, {}))
		end
	end)

	it("an error in a step page does not break the shell", function()
		editor().RegisterStep("about", { Build = function() error("boom") end })
		open()
		editor():GoTo(2)
		editor():GoTo(3)
		eq(editor():Step(), 3)
		eq(#Mock.errors, 1, "the error was reported to the client's handler")
		Mock.ClearErrors()
	end)

	it("a step page can read and write fields", function()
		editor().RegisterStep("identity", { OnShow = function(page, ed) ed:Set("sub", "From the page") end })
		open()
		eq(editor():Get("sub"), "From the page")
		eq(OL():Draft().sub, "From the page")
	end)
end)

describe("the draft", function()
	it("every change is saved at once as the draft, nothing is sent", function()
		local h = open()
		local sent = 0
		local send = A().Transport.Send
		A().Transport.Send = function(...) sent = sent + 1; return send(...) end
		eq(h.draft:GetText(), "Draft saved automatically")
		editor():Set("sub", "Friendly raiders")
		eq(OL():Draft().sub, "Friendly raiders")
		eq(OL():Draft().k, KEY)
		eq(h.draft:GetText(), "Draft saved automatically · just now")
		editor():Set("pace", 2)
		eq(OL():Draft().pace, 2)
		eq(OL():Draft().sub, "Friendly raiders", "the draft holds everything so far")
		eq(sent, 0)
		eq(publishedStatus(), "none")
	end)

	it("the age of the draft moves on while the page is open", function()
		local h = open()
		editor():Set("sub", "x")
		Mock.Advance(130)
		eq(h.draft:GetText(), "Draft saved automatically · 2 min ago")
	end)

	it("closing the window loses nothing: the draft comes back, with its step", function()
		open()
		editor():Patch({ sub = "Friendly raiders", tags = { 3, 1 }, disc = "https://discord.gg/wolves1" })
		main():Hide()
		editor().fields = {}   -- what the next opening reads comes from the saved draft only
		main():Show()
		eq(editor():Get("sub"), "Friendly raiders")
		deepEq(editor():Get("tags"), { 3, 1 })
		eq(editor():Get("disc"), "https://discord.gg/wolves1", "what was typed is kept as typed")
	end)

	it("the draft survives /reload", function()
		open()
		editor():Patch({ sub = "Friendly raiders", pace = 3 })
		Mock.Reload()
		asLeader()
		main():Show()
		eq(editor():Get("sub"), "Friendly raiders")
		eq(editor():Get("pace"), 3)
	end)

	it("a change that changes nothing is not saved again", function()
		open()
		local n = 0
		A().Bus:On("OWN_LISTING_CHANGED", function(what) if what == "draft" then n = n + 1 end end)
		editor():Set("sub", "x")
		eq(n, 1)
		editor():Set("sub", "x")
		editor():Patch({ sub = "x" })
		eq(n, 1)
	end)

	it("a patch of several fields is one save", function()
		open()
		local n = 0
		A().Bus:On("OWN_LISTING_CHANGED", function(what) if what == "draft" then n = n + 1 end end)
		editor():Patch({ sub = "a", pace = 1, tags = { 1 } })
		eq(n, 1)
		eq(OL():Draft().pace, 1)
	end)

	it("false clears a field", function()
		open()
		editor():Patch({ sub = "a", pace = 1 })
		editor():Patch({ pace = false })
		isNil(editor():Get("pace"))
		isNil(OL():Draft().pace)
		editor():Set("sub", nil)
		isNil(editor():Get("sub"))
	end)

	it("only the fields of a listing can be set: never rev, own, upd or the key", function()
		open()
		falsy(editor():Set("rev", 99))
		falsy(editor():Set("own", "ffffffff"))
		falsy(editor():Patch({ sub = "x", k = "Other|Horde|Guild" }))
		isNil(OL():Draft(), "a refused patch changes nothing")
		falsy(editor():Patch("text"))
	end)

	it("what comes back from Get is a copy", function()
		open()
		editor():Set("tags", { 1, 2 })
		local tags = editor():Get("tags")
		tags[1] = 9
		deepEq(editor():Get("tags"), { 1, 2 })
	end)

	it("the draft is the Guild Master's: after a change of guild it is not shown", function()
		open()
		editor():Set("sub", "Iron Wolves only")
		Mock.guild.Set{ name = "Other Guild", myRank = 0 }
		main():Hide()
		main():Show()
		isNil(editor():Get("sub"))
	end)
end)

describe("the live preview", function()
	it("follows the fields: name from the game, subtitle, commitment, activities", function()
		local h = open()
		eq(h.mini.name:GetText(), "Iron Wolves")
		eq(h.mini.sub:GetText(), "")
		editor():Patch({ sub = "Friendly raiders", pace = 3, lang1 = 5, lang = 16, tags = { 6, 1 } })
		eq(h.mini.sub:GetText(), "Friendly raiders")
		local tags = {}
		for _, t in ipairs(h.mini.tags) do if t:IsShown() then tags[#tags + 1] = t:GetText() end end
		deepEq(tags, { "IT", "HARDCORE" })
		eq(h.mini.acts:GetText(), "World PvP · Raids")
		editor():Set("tags", { 1 })
		eq(h.mini.acts:GetText(), "Raids")
	end)

	it("the guild name is read from the game and shown with its explanation", function()
		local h = open()
		eq(h.nameLabel:GetText(), "Guild name: Iron Wolves")
		matches(h.nameNote:GetText(), "Rename the guild in game")
	end)

	it("the last step shows the full card of the list, built by the list's own renderer", function()
		local h = open()
		editor():Patch({ sub = "Friendly raiders", pace = 2, tags = { 1, 2 }, minL = 20 })
		editor():GoTo(7)
		eq(h.card.name:GetText(), "Iron Wolves")
		eq(h.card.sub:GetText(), "Friendly raiders")
		eq(h.card.activities:GetText(), "Raids · Dungeons")
		eq(h.card.req:GetText(), "Level 20+")
		local rows = A().Browse.rowsCreated
		editor():Set("sub", "Changed")
		eq(h.card.sub:GetText(), "Changed")
		eq(A().Browse.rowsCreated, rows)
	end)

	it("the card is not clickable: it must not open a guild page", function()
		local h = open()
		editor():GoTo(7)
		Mock.RunScript(h.card, "OnMouseUp", "LeftButton")
		eq(main():CurrentPage(), "CreateListing")
	end)
end)

describe("the checklist", function()
	it("lists the nine items of SPEC-06 in the right column", function()
		local h = open()
		deepEq(rowTexts(h.checklist), { "You are the Guild Master", "Subtitle", "Description: at least 30 characters", "Main language",
			"Commitment (Casual, Softcore or Hardcore)", "1 to 3 activities", "Emblem (tabard or designed)",
			"\"Looking for\" set, or recruitment closed", "Discord code valid (only if filled in)" })
	end)

	it("shows each item as done, waiting or wrong, live", function()
		local h = open()
		local function icon(id) return rowFor(h.checklist, id).icon:GetTexture():match("glyph_%a+") or rowFor(h.checklist, id).icon:GetTexture():match("disc_ring") end
		eq(icon("leader"), "glyph_check")
		eq(icon("sub"), "disc_ring")
		editor():Set("sub", "Friendly raiders")
		eq(icon("sub"), "glyph_check")
		editor():Set("disc", "no way!")
		eq(icon("discord"), "glyph_close")
		matches(rowFor(h.checklist, "discord").hint:GetText(), "Paste the invite link")
		truthy(rowFor(h.checklist, "discord").hint:IsShown())
		falsy(rowFor(h.checklist, "sub").hint:IsShown())
		editor():Set("disc", "wolves1")
		eq(icon("discord"), "glyph_check")
	end)

	it("a short description says how short", function()
		local h = open()
		editor():Set("desc", "Too short")
		eq(rowFor(h.checklist, "desc").hint:GetText(), "9 of 30 characters")
	end)

	it("every item links to its step", function()
		local h = open()
		local expect = { sub = 1, desc = 2, lang = 2, pace = 3, tags = 3, emblem = 1, looking = 4, discord = 6 }
		for id, step in pairs(expect) do
			editor():GoTo(7)
			editor():GoTo(5)
			click(rowFor(h.checklist, id))
			eq(editor():Step(), step, id)
		end
		editor():GoTo(3)
		click(rowFor(h.checklist, "leader"))
		eq(editor():Step(), 3, "the Guild Master item has no step to go to")
	end)

	it("the last step shows the same list across the page, with a sentence about what is missing", function()
		local h = open()
		editor():GoTo(7)
		eq(#rowTexts(h.checklist2), 9)
		matches(h.publishNote:GetText(), "must be green")
		click(rowFor(h.checklist2, "pace"))
		eq(editor():Step(), 3)
		editor():Patch(full())
		editor():GoTo(7)
		matches(h.publishNote:GetText(), "Everything is ready")
	end)

	it("the steps on the left show their status and how many are ready", function()
		local h = open()
		eq(h.ready:GetText(), "2 / 7 ready")
		eq(h.stepButtons[6].note:GetText(), "optional")
		falsy(h.stepButtons[1].mark:IsShown())
		editor():Patch(full())
		eq(h.ready:GetText(), "7 / 7 ready")
		truthy(h.stepButtons[1].mark:IsShown())
		eq(h.stepButtons[1].mark:GetTexture():match("glyph_%a+"), "glyph_check")
		eq(h.stepButtons[6].note:GetText(), "")
		editor():Set("disc", "no way!")
		eq(h.stepButtons[6].mark:GetTexture():match("glyph_%a+"), "glyph_close")
		eq(h.ready:GetText(), "5 / 7 ready")
	end)
end)

describe("the main button", function()
	it("is off at first, with the step to fix as the reason", function()
		local h = open()
		eq(h.publish:GetLabel(), "Publish listing")
		falsy(h.publish.enabledState)
		eq(h.reason:GetText(), "Fix \"Identity\" to publish")
	end)

	it("the reason follows the first problem and goes when everything is green", function()
		local h = open()
		editor():Patch(full({ pace = false }))
		eq(h.reason:GetText(), "Fix \"Activity\" to publish")
		editor():Set("pace", 2)
		truthy(h.publish.enabledState)
		eq(h.reason:GetText(), "")
	end)

	it("pressing it while off says why, and takes you to the step", function()
		local h = open()
		editor():Patch(full({ desc = "short" }))
		editor():GoTo(5)
		eq(editor():Publish(), false)
		eq(editor():Step(), 2)
		eq(snack(), "Fix \"About\" to publish")
		eq(publishedStatus(), "none")
	end)

	it("publishes a complete listing: it is out, the confirmation shows, the draft is gone", function()
		local h = open()
		editor():Patch(full())
		click(h.publish)
		eq(snack(), "Listing published. It will reach other players over the next minutes.")
		eq(publishedStatus(), "listed")
		local copy = OL():Get()
		eq(copy.rev, 1)
		eq(copy.sub, "Friendly raiders")
		eq(copy.disc, "wolves1")
		isNil(OL():Draft())
		eq(#Mock.errors, 0)
	end)

	it("publishes what was typed as a link as its code", function()
		open()
		editor():Patch(full({ disc = "https://discord.gg/Wolves-1" }))
		click(host().publish)
		eq(OL():Get().disc, "Wolves-1")
	end)

	it("after publishing, the Guild Master has My Guild and Applications instead of the editor", function()
		open()
		editor():Patch(full())
		click(host().publish)
		deepEq(main().book:Tabs(), { "Settings", "MyGuild", "Applications" })
		eq(main():CurrentTab(), "MyGuild")
	end)

	it("is off for five minutes after a publication, with the time left, and on again after", function()
		local h = open()
		editor():Patch(full())
		click(h.publish)
		-- withdraw (never limited): the editor is back, filled with the last version
		eq(OL():Delist(), true)
		main():Show()
		h = host()
		eq(main():CurrentPage(), "CreateListing")
		falsy(h.publish.enabledState)
		matches(h.reason:GetText(), "^You can publish again in 5:0%d")
		Mock.Advance(100)
		matches(h.reason:GetText(), "^You can publish again in 3:[12]%d", "the count goes down while the page is open")
		Mock.Advance(201)
		truthy(h.publish.enabledState)
		eq(h.reason:GetText(), "")
		click(h.publish)
		eq(OL():Get().rev, 3)
		eq(publishedStatus(), "listed")
	end)

	it("is off for anybody but the Guild Master, whatever the checklist says", function()
		local h = open()
		editor():Patch(full())
		truthy(h.publish.enabledState)
		Mock.guild.SetMyRank(1)
		editor():Evaluate()
		eq(editor():Publish(), false)
		eq(publishedStatus(), "none")
		eq(snack(), "You are no longer the Guild Master: the change was not saved.")
	end)

	it("never lets an incomplete listing out, even by a direct call", function()
		open()
		editor():Patch(full({ emb = false }))
		eq(editor():Publish(), false)
		eq(publishedStatus(), "none")
	end)
end)

describe("editing a listing that is out", function()
	-- publishes `fields` and returns the editor opened on a listed listing
	local function listed(fields)
		open()
		editor():Patch(fields or full())
		click(host().publish)
		editor():Open()
		return host()
	end

	it("opens as the editor pushed on My Guild, filled with the published listing", function()
		local h = listed()
		eq(main():CurrentTab(), "MyGuild")
		eq(main():CurrentPage(), "ListingEditor")
		eq(editor():Get("sub"), "Friendly raiders")
		eq(h.ready:GetText(), "7 / 7 ready")
	end)

	it("says Save changes, and is off until something changed", function()
		local h = listed()
		eq(h.publish:GetLabel(), "Save changes")
		falsy(h.publish.enabledState)
		eq(h.reason:GetText(), "Nothing has changed since the last published version.")
		editor():Set("sub", "Now recruiting healers")
		Mock.Advance(301)
		truthy(h.publish.enabledState)
		eq(h.reason:GetText(), "")
	end)

	it("undoing the change turns it off again", function()
		local h = listed()
		Mock.Advance(301)
		editor():Set("sub", "Something else")
		truthy(h.publish.enabledState)
		editor():Set("sub", "Friendly raiders")
		falsy(h.publish.enabledState)
		editor():Set("disc", "https://discord.gg/wolves1")
		falsy(h.publish.enabledState, "the same code typed as a link is no change")
	end)

	it("a change within five minutes waits, then Save changes publishes the next revision", function()
		local h = listed()
		editor():Set("sub", "Now recruiting healers")
		falsy(h.publish.enabledState)
		matches(h.reason:GetText(), "^You can publish again in")
		Mock.Advance(301)
		truthy(h.publish.enabledState)
		click(h.publish)
		eq(OL():Get().rev, 2)
		eq(OL():Get().sub, "Now recruiting healers")
		eq(snack(), "Listing published. It will reach other players over the next minutes.")
	end)

	it("Delist asks first; cancelling does nothing", function()
		local h = listed()
		truthy(h.delist:IsShown())
		click(h.delist)
		truthy(h.confirm:IsShown())
		eq(h.confirm.text:GetText(), "Remove your guild from Guild Finder? Pending applications will be closed.")
		eq(h.confirm.yes:GetLabel(), "Delist")
		click(h.confirm.no)
		falsy(h.confirm:IsShown())
		eq(publishedStatus(), "listed")
	end)

	it("Delist, confirmed, withdraws the listing and brings the editor back, filled with it", function()
		local h = listed()
		click(h.delist)
		click(h.confirm.yes)
		eq(publishedStatus(), "delisted")
		eq(snack(), "Your guild was removed from Guild Finder.")
		deepEq(main().book:Tabs(), { "Settings", "CreateListing" })
		main():Show()
		h = host()
		eq(main():CurrentPage(), "CreateListing")
		eq(editor():Get("sub"), "Friendly raiders")
		falsy(h.delist:IsShown(), "nothing to delist")
		eq(#Mock.errors, 0)
	end)

	it("a first listing has no Delist button", function()
		local h = open()
		falsy(h.delist:IsShown())
	end)
end)

describe("discarding", function()
	it("is off while there is no draft", function()
		local h = open()
		falsy(h.discard.enabledState)
		editor():Set("sub", "x")
		truthy(h.discard.enabledState)
	end)

	it("asks first; cancelling keeps the draft", function()
		local h = open()
		editor():Set("sub", "x")
		click(h.discard)
		truthy(h.confirm:IsShown())
		eq(h.confirm.text:GetText(), "Discard the draft? Everything you entered is erased.")
		eq(h.confirm.yes:GetLabel(), "Discard changes")
		click(h.confirm.no)
		falsy(h.confirm:IsShown())
		eq(OL():Draft().sub, "x")
		eq(editor():Get("sub"), "x")
	end)

	it("confirmed, a first listing starts again from nothing", function()
		local h = open()
		editor():Patch(full())
		click(h.discard)
		click(h.confirm.yes)
		isNil(OL():Draft())
		isNil(editor():Get("sub"))
		eq(h.ready:GetText(), "2 / 7 ready")
		eq(snack(), "Changes discarded.")
		falsy(h.discard.enabledState)
	end)

	it("confirmed, a listing that is out goes back to its last published version", function()
		open()
		editor():Patch(full())
		click(host().publish)
		editor():Open()
		local h = host()
		editor():Patch({ sub = "Draft title", pace = 3 })
		eq(OL():Draft().pace, 3)
		click(h.discard)
		eq(h.confirm.text:GetText(), "Discard your changes and go back to the last published version?")
		click(h.confirm.yes)
		isNil(OL():Draft())
		eq(editor():Get("sub"), "Friendly raiders")
		eq(editor():Get("pace"), 2)
		eq(OL():Get().sub, "Friendly raiders", "the published version is untouched")
		eq(h.mini.sub:GetText(), "Friendly raiders")
	end)
end)

describe("development samples", function()
	it("the last step has a button that fills every step so the checklist can be tried", function()
		local h = open()
		editor():GoTo(7)
		truthy(h.sample, "development build")
		falsy(h.publish.enabledState)
		click(h.sample)
		truthy(h.publish.enabledState)
		eq(h.ready:GetText(), "7 / 7 ready")
		eq(snack(), "Sample values filled in.")
		click(h.publish)
		eq(publishedStatus(), "listed")
	end)
end)

describe("/gf debug editor", function()
	it("opens the editor on a listing that is out (development builds)", function()
		open()
		editor():Patch(full())
		click(host().publish)
		eq(main():CurrentTab(), "MyGuild")
		Mock.Slash("/gf debug editor")
		eq(main():CurrentPage(), "ListingEditor")
		truthy(host().delist:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("a release build refuses", function()
		A().Config.DEV = false
		Mock.ClearOutput()
		asLeader()
		Mock.Slash("/gf debug editor")
		matches(table.concat(Mock.PlainOutput(), " "), "only works in development builds")
		falsy(main():IsShown())
	end)
end)

describe("the window around the editor", function()
	it("no Lua error while stepping through everything, with and without data", function()
		local h = open()
		for i = 1, 7 do editor():GoTo(i) end
		editor():Patch(full())
		for i = 7, 1, -1 do editor():GoTo(i) end
		main():Hide()
		main():Show()
		eq(#Mock.errors, 0)
	end)

	it("the debug page names the editor and never a guild", function()
		open()
		local lines = editor():DebugLines()
		matches(lines[1], "^Editor: open, step 1 of 7")
		falsy(lines[1]:find("Iron"))
	end)

	it("the poll stops when the page is left", function()
		open()
		main():Select("Settings")
		Mock.Advance(3)
		falsy(editor():IsShown())
		eq(#Mock.errors, 0)
	end)
end)
