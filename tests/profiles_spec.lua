-- profiles_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The protect list (#9): KeyMode is always protected, the defaults are BugGrabber and
-- BugSack, names match in any case, and a removal survives the next login.

return function(stub, T)
    print("profiles")

    local function Joined(env)
        return table.concat(env.ns.Profiles:ProtectedList(), ",")
    end

    -- Boots a second session over the first one's SavedVariables, the way a /reload or a
    -- fresh login would: same KeyModeDB table, fresh addon code and defaults pass.
    local function Reboot(env)
        local saved = env.KeyModeDB
        return stub.Boot(function(e) e.KeyModeDB = saved end)
    end

    T.Test("defaults: KeyMode, BugGrabber and BugSack, sorted", function()
        local env = stub.Boot()
        T.AssertEqual(Joined(env), "BugGrabber,BugSack,KeyMode")
    end)

    T.Test("the list is stored at the top level, not under settings", function()
        local env = stub.Boot()
        T.AssertEqual(env.KeyModeDB.protected.BugSack, true, "top level")
        T.AssertEqual(env.KeyModeDB.settings.protected, nil, "not a setting")
    end)

    T.Test("KeyMode is protected in code, whatever the saved data says", function()
        local env = stub.Boot(function(e)
            e.KeyModeDB = { protected = { KeyMode = false } }
        end)
        local Profiles = env.ns.Profiles
        T.AssertTrue(Profiles:IsProtected("KeyMode"), "saved false ignored")
        T.AssertTrue(Profiles:IsProtected("keymode"), "any case")
        T.AssertEqual(Joined(env), "BugGrabber,BugSack,KeyMode", "listed once")
    end)

    T.Test("KeyMode cannot be removed", function()
        local env = stub.Boot()
        local ok, err = env.ns.Profiles:Unprotect("KEYMODE")
        T.AssertFalse(ok, "refused")
        T.AssertTrue(err:find("always protected", 1, true), "said why")
        T.AssertTrue(env.ns.Profiles:IsProtected("KeyMode"), "still protected")
    end)

    T.Test("names match case-insensitively", function()
        local env = stub.Boot()
        local Profiles = env.ns.Profiles
        T.AssertTrue(Profiles:IsProtected("bugsack"), "lower")
        T.AssertTrue(Profiles:IsProtected("BUGGRABBER"), "upper")
        T.AssertTrue(Profiles:IsProtected("  BugSack "), "trimmed")
        T.AssertFalse(Profiles:IsProtected("Details"), "unlisted")
        T.AssertFalse(Profiles:IsProtected(""), "empty")
        T.AssertFalse(Profiles:IsProtected(nil), "nil")
    end)

    T.Test("Protect adds a name and keeps its spelling", function()
        local env = stub.Boot()
        local Profiles = env.ns.Profiles
        T.AssertTrue(Profiles:Protect("Details"), "ok")
        T.AssertTrue(Profiles:IsProtected("details"), "protected")
        T.AssertEqual(Joined(env), "BugGrabber,BugSack,Details,KeyMode")
        T.AssertTrue(Profiles:Protect("DETAILS"), "again is ok")
        T.AssertEqual(Joined(env), "BugGrabber,BugSack,Details,KeyMode", "no second spelling")
    end)

    T.Test("Protect rejects an empty name", function()
        local env = stub.Boot()
        local ok, err = env.ns.Profiles:Protect("   ")
        T.AssertFalse(ok, "refused")
        T.AssertTrue(err ~= nil, "said why")
    end)

    T.Test("Unprotect removes a default, in any case", function()
        local env = stub.Boot()
        local Profiles = env.ns.Profiles
        T.AssertTrue(Profiles:Unprotect("bugsack"), "ok")
        T.AssertFalse(Profiles:IsProtected("BugSack"), "removed")
        T.AssertEqual(Joined(env), "BugGrabber,KeyMode")
        T.AssertEqual(env.KeyModeDB.protected.bugsack, nil, "no stray lower-case key")
    end)

    T.Test("Unprotect of an unlisted addon says so", function()
        local env = stub.Boot()
        local ok, err = env.ns.Profiles:Unprotect("Details")
        T.AssertFalse(ok, "refused")
        T.AssertTrue(err:find("not protected", 1, true), "said why")
    end)

    T.Test("a removed default stays removed after the next login", function()
        local env = stub.Boot()
        env.ns.Profiles:Unprotect("BugSack")
        local again = Reboot(env)
        T.AssertFalse(again.ns.Profiles:IsProtected("BugSack"), "defaults did not refill it")
        T.AssertEqual(Joined(again), "BugGrabber,KeyMode")
    end)

    T.Test("an added addon survives the next login", function()
        local env = stub.Boot()
        env.ns.Profiles:Protect("Details")
        T.AssertTrue(Reboot(env).ns.Profiles:IsProtected("Details"))
    end)

    T.Test("re-protecting a removed default flips it back", function()
        local env = stub.Boot()
        local Profiles = env.ns.Profiles
        Profiles:Unprotect("BugSack")
        T.AssertTrue(Profiles:Protect("bugsack"), "ok")
        T.AssertEqual(env.KeyModeDB.protected.BugSack, true, "existing entry reused")
        T.AssertEqual(Joined(env), "BugGrabber,BugSack,KeyMode", "one spelling")
    end)

    T.Test("/km reset keeps the protect list", function()
        local env = stub.Boot()
        env.ns.Profiles:Unprotect("BugSack")
        env.ns.Profiles:Protect("Details")
        stub.Slash(env, "/km reset")
        T.AssertEqual(Joined(env), "BugGrabber,Details,KeyMode")
    end)

    T.Test("before ADDON_LOADED only KeyMode is protected, and edits are refused", function()
        local env = stub.Load()
        local Profiles = env.ns.Profiles
        T.AssertTrue(Profiles:IsProtected("KeyMode"), "self")
        T.AssertFalse(Profiles:IsProtected("BugSack"), "no saved data yet")
        T.AssertFalse((Profiles:Protect("Details")), "refused")
    end)
end
