-- guard_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The safe-to-switch guard (#10): combat, an active keystone and a boss encounter each
-- block a switch with a reason, and a client missing one of those APIs neither errors
-- nor blocks.

return function(stub, T)
    print("guard")

    local function Status(env)
        stub.TakeChat(env)
        stub.Slash(env, "/km status")
        for _, line in ipairs(stub.TakeChat(env)) do
            local value = line:match("Switch allowed: (.*)$")
            if value then return value end
        end
    end

    T.Test("a quiet moment allows a switch", function()
        local env = stub.Boot()
        local ok, reason = env.ns.Inventory:CanSwitch()
        T.AssertTrue(ok, "allowed")
        T.AssertEqual(reason, nil, "no reason")
    end)

    T.Test("combat blocks a switch", function()
        local env = stub.Boot(function(_, fixtures) fixtures.inCombat = true end)
        local ok, reason = env.ns.Inventory:CanSwitch()
        T.AssertFalse(ok, "blocked")
        T.AssertEqual(reason, "in combat")
    end)

    T.Test("an active keystone blocks a switch", function()
        local env = stub.Boot(function(_, fixtures) fixtures.challengeModeActive = true end)
        local ok, reason = env.ns.Inventory:CanSwitch()
        T.AssertFalse(ok, "blocked")
        T.AssertEqual(reason, "a keystone is active")
    end)

    T.Test("a boss encounter blocks a switch", function()
        local env = stub.Boot(function(_, fixtures) fixtures.encounterInProgress = true end)
        local ok, reason = env.ns.Inventory:CanSwitch()
        T.AssertFalse(ok, "blocked")
        T.AssertEqual(reason, "a boss encounter is in progress")
    end)

    T.Test("combat is reported first when several apply", function()
        local env = stub.Boot(function(_, fixtures)
            fixtures.inCombat = true
            fixtures.challengeModeActive = true
            fixtures.encounterInProgress = true
        end)
        T.AssertEqual(select(2, env.ns.Inventory:CanSwitch()), "in combat")
    end)

    T.Test("the guard reads live state on every call", function()
        local env = stub.Boot()
        T.AssertTrue((env.ns.Inventory:CanSwitch()), "allowed")
        env.fixtures.inCombat = true
        T.AssertFalse((env.ns.Inventory:CanSwitch()), "now blocked")
        env.fixtures.inCombat = false
        T.AssertTrue((env.ns.Inventory:CanSwitch()), "allowed again")
    end)

    T.Test("missing APIs are skipped, neither erroring nor blocking", function()
        local env = stub.Boot(function(e)
            e.InCombatLockdown = nil
            e.C_ChallengeMode = nil
            e.IsEncounterInProgress = nil
        end)
        local ok, reason = env.ns.Inventory:CanSwitch()
        T.AssertTrue(ok, "allowed")
        T.AssertEqual(reason, nil, "no reason")
    end)

    T.Test("C_ChallengeMode without IsChallengeModeActive is skipped", function()
        local env = stub.Boot(function(e) e.C_ChallengeMode = {} end)
        T.AssertTrue((env.ns.Inventory:CanSwitch()))
    end)

    T.Test("a missing API does not hide the checks that remain", function()
        local env = stub.Boot(function(e, fixtures)
            e.IsEncounterInProgress = nil
            fixtures.challengeModeActive = true
        end)
        T.AssertEqual(select(2, env.ns.Inventory:CanSwitch()), "a keystone is active")
    end)

    T.Test("/km status shows the answer and the reason", function()
        local env = stub.Boot()
        T.AssertEqual(Status(env), "yes", "allowed")
        env.fixtures.inCombat = true
        T.AssertEqual(Status(env), "no (in combat)", "blocked")
    end)
end
