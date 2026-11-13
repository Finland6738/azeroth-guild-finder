-- Config (M1.4): defaults, validation, migrations, newer schema read-only, idempotent reload, damaged data.
-- Saved data is set up in before_boot: the harness restores it before ADDON_LOADED, like the client.
local function config() return AzerothGuildFinder.Config end
local function issuesText() return table.concat(config().issues, "\n") end

describe("defaults", function()
	it("creates both variables with schema 1 and every default", function()
		local C = config()
		eq(AzerothGuildFinderDB.schemaVersion, 1)
		eq(AzerothGuildFinderCharDB.schemaVersion, 1)
		eq(#C.issues, 0)
		eq(C:Get("account.settings.shareAltCount"), true)
		eq(C:Get("account.settings.uiScale"), 1.0)
		eq(C:Get("account.settings.sound"), true)
		eq(C:Get("char.minimap.hide"), false)
		deepEq(AzerothGuildFinderDB.catalog, {})
		deepEq(AzerothGuildFinderCharDB.officerInbox, {})
		deepEq(AzerothGuildFinderCharDB.ui.filters, {})
		isNil(AzerothGuildFinderCharDB.application)
		falsy(C:IsReadOnly())
	end)

	it("creates a 32-hex account secret once and keeps it", function()
		local secret = AzerothGuildFinderDB.accountSecret
		matches(secret, "^%x+$")
		eq(#secret, 32)
		Mock.Reload()
		eq(AzerothGuildFinderDB.accountSecret, secret)
	end)

	it("never prints the secret in /gf debug", function()
		Mock.Slash("/gf debug")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Saved data")
		falsy(text:find(AzerothGuildFinderDB.accountSecret, 1, true))
	end)

	it("exposes the limits for later modules", function()
		local L = config().LIMITS
		eq(L.LISTINGS_PER_REALM_FACTION, 500)
		eq(L.APPLICATIONS_PER_INBOX, 200)
		eq(L.DETAIL_CACHE_DAYS, 60)
	end)
end)

describe("merge", function()
	before_boot(function()
		AzerothGuildFinderDB = { schemaVersion = 1, settings = { sound = false, uiScale = 1.5 },
			catalog = { Realm = { Alliance = { a = 1 } } } }
	end)

	it("fills what is missing and never overwrites existing values", function()
		local C = config()
		eq(C:Get("account.settings.sound"), false)
		eq(C:Get("account.settings.uiScale"), 1.5)
		eq(C:Get("account.settings.shareAltCount"), true)
		eq(AzerothGuildFinderDB.catalog.Realm.Alliance.a, 1)
		eq(#C.issues, 0)
	end)
end)

describe("validation", function()
	before_boot(function()
		AzerothGuildFinderDB = { schemaVersion = 1, accountSecret = "nothex",
			settings = { sound = "yes", uiScale = 9, shareAltCount = false, windowPos = 5 },
			catalog = { Good = { Horde = {} }, Bad = 3, [4] = {}, Half = { Horde = "x" } } }
		AzerothGuildFinderCharDB = { schemaVersion = 1, minimap = { hide = "no" },
			ui = { notifyPos = { point = "TOP", x = 1, y = 2 }, mainPos = { point = 7 } } }
	end)

	it("resets bad values to their defaults and lists them", function()
		local C = config()
		eq(C:Get("account.settings.sound"), true)
		eq(C:Get("account.settings.uiScale"), 1.0)
		eq(C:Get("account.settings.shareAltCount"), false, "a valid value is kept")
		deepEq(C:Get("account.settings.windowPos"), {})
		eq(C:Get("char.minimap.hide"), false)
		isNil(C:Get("char.ui.mainPos"))
		eq(C:Get("char.ui.notifyPos").point, "TOP")
		eq(#AzerothGuildFinderDB.accountSecret, 32)
		contains(issuesText(), "account.settings.uiScale")
		contains(issuesText(), "char.ui.mainPos")
		eq(#Mock.errors, 0)
	end)

	it("drops malformed catalog entries", function()
		local catalog = AzerothGuildFinderDB.catalog
		truthy(catalog.Good)
		isNil(catalog.Bad)
		isNil(catalog[4])
		isNil(catalog.Half.Horde)
	end)

	it("shows the issues in /gf debug", function()
		Mock.Slash("/gf debug")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "problem(s)")
		contains(text, "account.settings.uiScale")
	end)

	it("Set validates, Get reads, unknown paths are refused", function()
		local C = config()
		truthy(C:Set("account.settings.uiScale", 1.25))
		eq(AzerothGuildFinderDB.settings.uiScale, 1.25)
		local ok, why = C:Set("account.settings.uiScale", 5)
		falsy(ok)
		contains(why, "above")
		falsy((C:Set("account.settings.sound", "x")))
		falsy((C:Set("account.nothing", 1)))
		falsy((C:Set("account.schemaVersion", 9)))
		falsy((C:Set("char.ui.mainPos", { point = 1 })))
		truthy(C:Set("char.ui.mainPos", nil), "optional values accept nil")
		eq(AzerothGuildFinderDB.settings.uiScale, 1.25)
	end)

	it("rejects NaN and infinity", function()
		falsy((config():Set("account.settings.uiScale", 0 / 0)))
		falsy((config():Set("account.settings.uiScale", math.huge)))
	end)
end)

describe("damaged data", function()
	it("replaces a variable that is not a table", function()
		T.boot(function() AzerothGuildFinderDB = "garbage"; AzerothGuildFinderCharDB = 12 end)
		eq(type(AzerothGuildFinderDB), "table")
		eq(AzerothGuildFinderCharDB.schemaVersion, 1)
		contains(issuesText(), "not a table")
		eq(#Mock.errors, 0)
	end)

	it("treats a lost or damaged schemaVersion as 0 and migrates", function()
		T.boot(function()
			AzerothGuildFinderDB = { settings = { sound = false } }
			AzerothGuildFinderCharDB = { schemaVersion = "two" }
		end)
		eq(config().loadedVersion.account, 0)
		eq(config().loadedVersion.char, 0)
		eq(AzerothGuildFinderDB.schemaVersion, 1)
		eq(AzerothGuildFinderCharDB.schemaVersion, 1)
		eq(AzerothGuildFinderDB.settings.sound, false, "user data is kept")
		falsy(config():IsReadOnly())
	end)

	it("a negative or fractional version is damaged", function()
		T.boot(function() AzerothGuildFinderDB = { schemaVersion = -3 }; AzerothGuildFinderCharDB = { schemaVersion = 1.5 } end)
		eq(config().loadedVersion.account, 0)
		eq(config().loadedVersion.char, 0)
	end)

	it("clamps a future timestamp to now and resets a malformed one", function()
		T.boot(function() end)
		local C = config()
		C.rules["account.settings.seenAt"] = { type = "timestamp", optional = true }
		C.rules["account.settings.lastAt"] = { type = "timestamp", optional = true }
		AzerothGuildFinderDB.settings.seenAt = GetServerTime() + 99999
		AzerothGuildFinderDB.settings.lastAt = -5
		C:Load()
		eq(AzerothGuildFinderDB.settings.seenAt, GetServerTime())
		isNil(AzerothGuildFinderDB.settings.lastAt)
		contains(issuesText(), "future time clamped")
	end)
end)

describe("migrations", function()
	it("runs the steps in order from the stored version", function()
		T.boot(function()
			AzerothGuildFinderDB = { schemaVersion = 1, settings = { oldName = 7 } }
		end)
		local C = config()
		local calls = {}
		C.SCHEMA_VERSION = 3
		C.migrations.account[2] = function(db) calls[#calls + 1] = 2; db.settings.newName = db.settings.newName or db.settings.oldName; db.settings.oldName = nil end
		C.migrations.account[3] = function(db) calls[#calls + 1] = 3 end
		C:Load()
		deepEq(calls, { 2, 3 })
		eq(AzerothGuildFinderDB.schemaVersion, 3)
		eq(AzerothGuildFinderDB.settings.newName, 7)
		isNil(AzerothGuildFinderDB.settings.oldName)
		falsy(C:IsReadOnly("account"))
		-- a second load changes nothing and runs no step
		C:Load()
		deepEq(calls, { 2, 3 })
		eq(AzerothGuildFinderDB.settings.newName, 7)
	end)

	it("a migration step is idempotent when applied twice", function()
		T.boot(function() end)
		local C = config()
		local step = function(db) db.settings.n = (db.settings.n or 0) + 0; db.settings.moved = db.settings.moved or "x" end
		local db = { settings = {} }
		step(db)
		local snapshot = C.Copy(db)
		step(db)
		deepEq(db, snapshot)
	end)

	it("a failing step leaves the saved data untouched and goes read-only", function()
		T.boot(function() AzerothGuildFinderDB = { schemaVersion = 1, settings = { sound = false } } end)
		local C = config()
		C.SCHEMA_VERSION = 2
		C.migrations.account[2] = function(db) db.settings.sound = true; error("boom") end
		C:Load()
		eq(AzerothGuildFinderDB.schemaVersion, 1)
		eq(AzerothGuildFinderDB.settings.sound, false)
		truthy(C:IsReadOnly("account"))
		contains(issuesText(), "migration")
		falsy((C:Set("account.settings.sound", true)))
		eq(#Mock.errors, 0)
	end)
end)

describe("newer schema", function()
	before_boot(function()
		AzerothGuildFinderDB = { schemaVersion = 9, futureField = { keep = true }, settings = { sound = "weird", uiScale = 1.5 } }
	end)

	it("is loaded read-only: the saved table is never rewritten", function()
		local C = config()
		truthy(C:IsReadOnly("account"))
		falsy(C:IsReadOnly("char"))
		eq(AzerothGuildFinderDB.schemaVersion, 9)
		eq(AzerothGuildFinderDB.settings.sound, "weird", "not sanitized in place")
		isNil(AzerothGuildFinderDB.settings.shareAltCount, "defaults not merged in place")
		isNil(AzerothGuildFinderDB.accountSecret)
		contains(issuesText(), "newer")
	end)

	it("the addon works on a sanitized copy", function()
		local C = config()
		eq(C:Get("account.settings.sound"), true)
		eq(C:Get("account.settings.uiScale"), 1.5)
		eq(C:Get("account.settings.shareAltCount"), true)
		truthy(C.db.account.futureField.keep)
		ne(C.db.account, AzerothGuildFinderDB)
		local ok, why = C:Set("account.settings.uiScale", 1.2)
		falsy(ok)
		eq(why, "read-only")
		eq(AzerothGuildFinderDB.settings.uiScale, 1.5)
	end)

	it("survives a reload unchanged and is reported in /gf debug", function()
		Mock.Reload()
		eq(AzerothGuildFinderDB.schemaVersion, 9)
		eq(AzerothGuildFinderDB.futureField.keep, true)
		Mock.Slash("/gf debug")
		contains(table.concat(Mock.PlainOutput(), "\n"), "READ-ONLY")
	end)
end)

describe("reload", function()
	it("is idempotent: a second round trip changes nothing", function()
		Mock.Reload()
		local first = Mock.savedText.AzerothGuildFinderDB
		local firstChar = Mock.savedText.AzerothGuildFinderCharDB
		Mock.Reload()
		eq(Mock.savedText.AzerothGuildFinderDB, first)
		eq(Mock.savedText.AzerothGuildFinderCharDB, firstChar)
		eq(#config().issues, 0)
	end)

	it("keeps values changed through Set", function()
		truthy(config():Set("account.settings.uiScale", 0.8))
		truthy(config():Set("char.ui.notifyLocked", true))
		Mock.Reload()
		eq(config():Get("account.settings.uiScale"), 0.8)
		eq(config():Get("char.ui.notifyLocked"), true)
	end)
end)
