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
        T.AssertTrue(Has(lines, "guid=2 name=2 full=n/a zero=0 all="), "per-key states")
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
        T.AssertTrue(Has(stub.TakeChat(env), "guid=0 name=2"), "the change is visible in the report")
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

    T.Test("debug on/off still toggles", function()
        local env = Boot(false)
        stub.Slash(env, "/km debug on")
        T.AssertTrue(env.ns.db.settings.debug, "on")
        stub.Slash(env, "/km debug off")
        T.AssertFalse(env.ns.db.settings.debug, "off")
    end)
end
