-- init_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Load-time behaviour: version reporting and SavedVariables initialisation.

return function(stub, T)
    print("init")

    T.Test("unbuilt clone reports version as dev", function()
        local env = stub.Load()
        T.AssertEqual(env.ns.GetAddonVersion(), "dev")
    end)

    T.Test("packaged tag gets exactly one leading v", function()
        local env = stub.Load(function(_, fixtures)
            fixtures.metadata.KeyMode.Version = "v1.0.0"
        end)
        T.AssertEqual(env.ns.GetAddonVersion(), "v1.0.0")
    end)

    T.Test("ADDON_LOADED fills defaults into an empty DB", function()
        local env = stub.Load()
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        T.AssertEqual(env.KeyModeDB.dbVersion, env.ns.DB_VERSION, "dbVersion")
        T.AssertEqual(type(env.KeyModeDB.profiles), "table", "profiles")
        T.AssertEqual(env.KeyModeDB.settings.debug, false, "settings.debug")
        T.AssertTrue(env.ns.db == env.KeyModeDB, "ns.db aliases the saved table")
    end)

    T.Test("ADDON_LOADED keeps existing settings", function()
        local env = stub.Load(function(e)
            e.KeyModeDB = { settings = { debug = true } }
        end)
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        T.AssertEqual(env.KeyModeDB.settings.debug, true)
    end)

    T.Test("another addon's ADDON_LOADED is ignored", function()
        local env = stub.Load()
        stub.Fire(env, "ADDON_LOADED", "SomeOtherAddon")
        T.AssertEqual(env.KeyModeDB, nil)
    end)

    T.Test("Print applies the prefix", function()
        local env = stub.Load()
        env.ns.Print("hello", 42)
        T.AssertTrue(env.fixtures.chat[1]:find("KeyMode", 1, true), "prefix")
        T.AssertTrue(env.fixtures.chat[1]:find("hello 42", 1, true), "joined args")
    end)
end
