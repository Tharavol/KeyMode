-- probe_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- `/km debug probe` (#6). What the live client answers is checked in-game; this pins
-- that the probe asks the right questions, and that its mutations never reach anything
-- but the KeyModeProbe fixture addon.

return function(stub, T)
    print("probe")

    local function Has(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return true end
        end
        return false
    end

    local function Boot(withTarget)
        return stub.Boot(function(_, fixtures)
            stub.AddAddon(fixtures, "DataStore")
            stub.AddAddon(fixtures, "Altoholic", { deps = { "datastore", "NotHere" } })
            if withTarget then
                stub.AddAddon(fixtures, "KeyModeProbe", { deps = { "keymode" } })
            end
        end)
    end

    T.Test("bare probe reports the fixture addon under every character key", function()
        local env = Boot(true)
        stub.Slash(env, "/km debug probe")
        local lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "Probe: KeyModeProbe"), "header")
        T.AssertTrue(Has(lines, "guid=2 name=2 full=n/a zero=2 all=2"), "per-key states")
        T.AssertTrue(Has(lines, "deps (as returned): keymode"), "raw dependency case")
        T.AssertEqual(#env.fixtures.calls, 0, "a report changes nothing")
        T.AssertFalse(env.ns.db.settings.debug, "and does not toggle debug")
    end)

    T.Test("a missing fixture is named, not an error", function()
        local env = Boot(false)
        stub.Slash(env, "/km debug probe")
        T.AssertTrue(Has(stub.TakeChat(env), "'KeyModeProbe' is not installed"), "named")
    end)

    T.Test("any installed addon can be reported on, case-insensitively", function()
        local env = Boot(false)
        stub.Slash(env, "/km debug probe altoholic")
        local lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "Probe: Altoholic"), "canonical folder name")
        T.AssertEqual(#env.fixtures.calls, 0, "read only")
    end)

    T.Test("disable acts on the fixture alone, with the chosen key, then re-reports", function()
        local env = Boot(true)
        stub.Slash(env, "/km debug probe disable guid")
        local calls = env.fixtures.calls
        T.AssertEqual(#calls, 1, "one call")
        T.AssertEqual(calls[1][1], "DisableAddOn")
        T.AssertEqual(calls[1][2], "KeyModeProbe")
        T.AssertEqual(calls[1][3], env.fixtures.player.guid)
        T.AssertTrue(Has(stub.TakeChat(env), "guid=0 name=0 full=n/a zero=0 all=0"), "visible at once")
    end)

    T.Test("'all' passes nil and 'zero' passes \"0\"", function()
        local env = Boot(true)
        stub.Slash(env, "/km debug probe enable all")
        stub.Slash(env, "/km debug probe disable zero")
        T.AssertEqual(env.fixtures.calls[1][3], nil, "all")
        T.AssertEqual(env.fixtures.calls[2][3], "0", "zero")
    end)

    T.Test("an unknown key or a missing fixture makes no call", function()
        local env = Boot(true)
        stub.Slash(env, "/km debug probe disable everyone")
        T.AssertTrue(Has(stub.TakeChat(env), "expected a character key"), "key rejected")
        local bare = Boot(false)
        stub.Slash(bare, "/km debug probe disable guid")
        T.AssertTrue(Has(stub.TakeChat(bare), "install tests/fixtures/KeyModeProbe"), "fixture asked for")
        T.AssertEqual(#env.fixtures.calls + #bare.fixtures.calls, 0, "no calls")
    end)

    T.Test("save and reset call through", function()
        local env = Boot(true)
        stub.Slash(env, "/km debug probe save")
        stub.Slash(env, "/km debug probe reset")
        T.AssertEqual(env.fixtures.calls[1][1], "SaveAddOns")
        T.AssertEqual(env.fixtures.calls[2][1], "ResetAddOns")
        T.AssertEqual(env.fixtures.reloads, 0, "never reloads on its own")
    end)

    T.Test("scan tallies reasons, case mismatches and missing dependencies", function()
        local env = Boot(true)
        stub.Slash(env, "/km debug probe scan")
        local lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "4 addons installed"), "count")
        T.AssertTrue(Has(lines, "differing in case from the folder: 2"), "datastore and keymode")
        T.AssertTrue(Has(lines, "Altoholic -> datastore (folder DataStore)"), "mismatch listed")
        T.AssertTrue(Has(lines, "dependencies not installed: 1"), "NotHere")
        T.AssertTrue(Has(lines, "IsEncounterInProgress true"), "API presence reported")
    end)

    T.Test("probe output is kept in KeyModeDB.probeLog until cleared", function()
        local env = Boot(true)
        stub.Slash(env, "/km debug probe")
        local log = env.ns.db.probeLog
        T.AssertTrue(log and log[1]:find("Testchar", 1, true), "header names the character")
        T.AssertTrue(log[1]:find("/km debug probe", 1, true), "and the command")
        T.AssertTrue(#log > 3, "report lines logged")
        stub.Slash(env, "/km debug probe clear")
        T.AssertEqual(env.ns.db.probeLog, nil, "cleared")
    end)

    T.Test("a login during a probe session logs whether the fixture loaded", function()
        local env = Boot(true)
        stub.Fire(env, "PLAYER_LOGIN")
        T.AssertEqual(env.ns.db.probeLog, nil, "no session, nothing logged")
        stub.Slash(env, "/km debug probe")
        local before = #env.ns.db.probeLog
        stub.Fire(env, "PLAYER_LOGIN")
        local log = env.ns.db.probeLog
        T.AssertTrue(#log > before, "logged")
        T.AssertTrue(log[before + 1]:find("KeyModeProbe loaded = false", 1, true), "load result")
    end)

    T.Test("categories tallies ## Category in chat and logs the full map", function()
        local env = stub.Boot(function(_, fixtures)
            stub.AddAddon(fixtures, "Auctionator", { metadata = { Category = "Auction House" } })
            stub.AddAddon(fixtures, "TSM", { metadata = { Category = "Auction House" } })
            stub.AddAddon(fixtures, "TomTom", { metadata = { Category = "Map" } })
            stub.AddAddon(fixtures, "Plain")
        end)
        stub.Slash(env, "/km debug probe categories")
        local text = table.concat(stub.TakeChat(env), "\n")
        T.AssertTrue(text:find("Categories: 2 values over 3 addons; 2 have none.", 1, true), "summary")
        T.AssertTrue(text:find("2  Auction House\n", 1, true), "most used first")
        T.AssertFalse(text:find("category: TomTom", 1, true), "map not in chat")
        local log = table.concat(env.ns.db.probeLog, "\n")
        T.AssertTrue(log:find("category: TomTom = Map", 1, true), "map in the log")
        T.AssertTrue(log:find("category: Plain = (none)", 1, true), "none logged")
        T.AssertEqual(#env.fixtures.calls, 0, "read only")
    end)

    T.Test("a login after the fixture is uninstalled stays silent", function()
        local env = Boot(false)
        env.ns.db.probeLog = { "an old session" }
        stub.Fire(env, "PLAYER_LOGIN")
        T.AssertEqual(#env.ns.db.probeLog, 1, "nothing logged")
        T.AssertEqual(#stub.TakeChat(env), 0, "nothing printed")
    end)

    T.Test("packaged: the fixture probes are gone, the read-only ones remain", function()
        local env = stub.Boot(function(_, fixtures)
            fixtures.packaged = true
            stub.AddAddon(fixtures, "KeyModeProbe", { deps = { "keymode" } })
        end)
        T.AssertEqual(env.ns.Probe.Set, nil, "no Set")
        stub.Slash(env, "/km debug probe")
        T.AssertTrue(Has(stub.TakeChat(env), "Probe: expected scan, inventory [addon], categories, lfg, clear"),
            "bare lists the probes")
        for _, word in ipairs({ "enable guid", "disable guid", "save", "reset" }) do
            stub.Slash(env, "/km debug probe " .. word)
        end
        T.AssertEqual(#env.fixtures.calls, 0, "no mutation reaches the client")
        stub.Slash(env, "/km debug probe keymodeprobe")
        T.AssertTrue(Has(stub.TakeChat(env), "Probe: KeyModeProbe"), "an addon report still works")
        local before = #env.ns.db.probeLog
        stub.Fire(env, "PLAYER_LOGIN")
        T.AssertEqual(#env.ns.db.probeLog, before, "no login logging")
        stub.Slash(env, "/km help")
        local help = table.concat(stub.TakeChat(env), "\n")
        T.AssertTrue(help:find("/km debug probe <scan", 1, true), "read-only probes in help")
        T.AssertFalse(help:find("KeyModeProbe", 1, true), "fixture probes not in help")
    end)

    T.Test("every addon file still compiles with its do-not-package blocks removed", function()
        for _, path in ipairs(stub.TocFiles()) do
            local handle = assert(io.open(path, "r"))
            local source = handle:read("*a")
            handle:close()
            local chunk, err = loadstring(stub.Packaged(source), "@" .. path)
            T.AssertTrue(chunk, tostring(err))
        end
    end)

    T.Test("debug on/off still toggles", function()
        local env = Boot(false)
        stub.Slash(env, "/km debug on")
        T.AssertTrue(env.ns.db.settings.debug, "on")
        stub.Slash(env, "/km debug off")
        T.AssertFalse(env.ns.db.settings.debug, "off")
    end)
end
