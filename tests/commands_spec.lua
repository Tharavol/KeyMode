-- commands_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Slash commands against the cross-addon standard (S1-S13). Each test names the rule
-- it pins, so a failure says which part of the standard regressed.

return function(stub, T)
    print("commands")

    local function Has(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return true end
        end
        return false
    end

    T.Test("S1: /keymode and /km are both registered", function()
        local env = stub.Boot()
        T.AssertTrue(stub.Slash(env, "/keymode version"), "/keymode")
        T.AssertTrue(stub.Slash(env, "/KM version"), "/km, any case")
    end)

    T.Test("S2/S5: bare, options, config and gui all open the panel", function()
        local env = stub.Boot()
        for _, line in ipairs({ "/km", "/km options", "/km config", "/km GUI" }) do
            stub.Slash(env, line)
        end
        T.AssertEqual(#env.fixtures.settingsOpened, 4, "four opens")
        T.AssertEqual(#stub.TakeChat(env), 0, "and no usage dump alongside")
    end)

    T.Test("S3/S13: help lists every command that has help text", function()
        local env = stub.Boot()
        stub.Slash(env, "/km help")
        local lines = stub.TakeChat(env)
        for _, entry in ipairs(env.ns.Commands.COMMANDS) do
            for _, help in ipairs(entry.help) do
                T.AssertTrue(Has(lines, (help:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))),
                    "help line for '" .. entry.name .. "'")
            end
        end
    end)

    T.Test("S4: unknown input is named, then help follows", function()
        local env = stub.Boot()
        stub.Slash(env, "/km frobnicate")
        local lines = stub.TakeChat(env)
        T.AssertTrue(lines[1]:find("Unknown command: frobnicate", 1, true), "named")
        T.AssertTrue(Has(lines, "/km help"), "usage printed")
        T.AssertEqual(#env.fixtures.settingsOpened, 0, "panel not opened as a fallback")
    end)

    T.Test("S6: status reports mode and settings", function()
        local env = stub.Boot()
        stub.Slash(env, "/km status")
        local lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "Mode: Normal"), "mode")
        T.AssertTrue(Has(lines, "Debug messages: off"), "setting")
    end)

    T.Test("S7: version prints name and version", function()
        local env = stub.Boot()
        stub.Slash(env, "/km version")
        T.AssertTrue(stub.TakeChat(env)[1]:find("KeyMode dev", 1, true))
    end)

    T.Test("S8: bare debug toggles and reports; on/off set explicitly", function()
        local env = stub.Boot()
        stub.Slash(env, "/km debug")
        T.AssertEqual(env.KeyModeDB.settings.debug, true, "bare toggled on")
        T.AssertTrue(stub.TakeChat(env)[1]:find("Debug messages is on", 1, true), "reported")
        stub.Slash(env, "/km debug")
        T.AssertEqual(env.KeyModeDB.settings.debug, false, "bare toggled off")
        stub.Slash(env, "/km debug ON")
        stub.Slash(env, "/km debug on")
        T.AssertEqual(env.KeyModeDB.settings.debug, true, "explicit on is idempotent")
    end)

    T.Test("S9: reset restores settings and keeps profiles", function()
        local env = stub.Boot()
        env.KeyModeDB.settings.debug = true
        env.KeyModeDB.profiles.Keys = { disable = {} }
        stub.Slash(env, "/km reset")
        T.AssertEqual(env.KeyModeDB.settings.debug, false, "reset")
        T.AssertTrue(env.KeyModeDB.profiles.Keys ~= nil, "profile kept")
    end)

    T.Test("S10: every line carries the KeyMode prefix", function()
        local env = stub.Boot()
        stub.Slash(env, "/km help")
        for _, line in ipairs(stub.TakeChat(env)) do
            T.AssertTrue(line:find("^KeyMode: "), "prefixed: " .. line)
        end
    end)

    T.Test("S11: only the command word is lowercased", function()
        local env = stub.Boot()
        local command, argument, rest = env.ns.Commands.Parse("  ON  Tyrannical Keys  ")
        T.AssertEqual(command, "on", "command")
        T.AssertEqual(argument, "Tyrannical Keys", "argument keeps case, trimmed")
        T.AssertEqual(rest, "tyrannical keys", "rest lowercased")
    end)

    T.Test("S12: an invalid debug value is rejected, not read as off", function()
        local env = stub.Boot()
        env.KeyModeDB.settings.debug = true
        stub.Slash(env, "/km debug onn")
        T.AssertEqual(env.KeyModeDB.settings.debug, true, "unchanged")
        T.AssertTrue(stub.TakeChat(env)[1]:find("expected 'on' or 'off'", 1, true), "said why")
    end)

    T.Test("mode commands are documented but say they are not available yet", function()
        local env = stub.Boot()
        for _, word in ipairs({ "on", "off", "toggle", "preview" }) do
            stub.Slash(env, "/km " .. word)
            local lines = stub.TakeChat(env)
            T.AssertEqual(#lines, 1, word .. ": one line")
            T.AssertTrue(lines[1]:find("not available yet", 1, true), word)
        end
        T.AssertEqual(env.fixtures.reloads, 0, "nothing reloaded")
        T.AssertEqual(#env.fixtures.calls, 0, "no enable state touched")
    end)
end
