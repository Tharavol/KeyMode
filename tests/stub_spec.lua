-- stub_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The C_AddOns fixture model is what the inventory, dependency and switch specs will be
-- written against, so its own behaviour is pinned here: if it drifts, every later spec
-- is testing against the wrong shape.

return function(stub, T)
    print("stub")

    local function Setup()
        return stub.Load(function(_, fixtures)
            stub.AddAddon(fixtures, "DataStore")
            stub.AddAddon(fixtures, "Altoholic", { deps = { "DataStore" }, optionalDeps = { "Auctionator" } })
            stub.AddAddon(fixtures, "DBM-GUI", { loadOnDemand = true })
            stub.AddAddon(fixtures, "Broken", { loadable = false, reason = "MISSING" })
            stub.AddAddon(fixtures, "OffHere", { enabled = false })
        end)
    end

    T.Test("addons are addressable by index and by name", function()
        local env = Setup()
        local api = env.C_AddOns
        T.AssertEqual(api.GetNumAddOns(), 6, "KeyMode plus five fixtures")
        T.AssertEqual((api.GetAddOnInfo(1)), "KeyMode", "index 1")
        T.AssertEqual(select(2, api.GetAddOnInfo("Altoholic")), "Altoholic", "title by name")
        T.AssertEqual(api.GetAddOnInfo("NotInstalled"), nil, "unknown name")
    end)

    T.Test("dependencies come back as varargs", function()
        local env = Setup()
        local deps = { env.C_AddOns.GetAddOnDependencies("Altoholic") }
        T.AssertEqual(#deps, 1, "one required dep")
        T.AssertEqual(deps[1], "DataStore")
        T.AssertEqual((env.C_AddOns.GetAddOnOptionalDependencies("Altoholic")), "Auctionator")
        T.AssertEqual(select("#", env.C_AddOns.GetAddOnDependencies("DataStore")), 0, "none")
    end)

    T.Test("load-on-demand and unloadable addons report a reason", function()
        local env = Setup()
        T.AssertEqual(select(5, env.C_AddOns.GetAddOnInfo("DBM-GUI")), "DEMAND_LOADED", "LoD")
        T.AssertTrue(env.C_AddOns.IsAddOnLoadOnDemand("DBM-GUI"), "LoD flag")
        local _, _, _, loadable, reason = env.C_AddOns.GetAddOnInfo("Broken")
        T.AssertFalse(loadable, "unloadable")
        T.AssertEqual(reason, "MISSING")
    end)

    T.Test("per-character enable state is independent per key", function()
        local env = Setup()
        local api, state = env.C_AddOns, env.Enum.AddOnEnableState
        local guid = env.UnitGUID("player")
        T.AssertEqual(api.GetAddOnEnableState("Altoholic", guid), state.All, "enabled by default")
        T.AssertEqual(api.GetAddOnEnableState("OffHere", guid), state.None, "enabled = false")
        api.DisableAddOn("Altoholic", guid)
        T.AssertEqual(api.GetAddOnEnableState("Altoholic", guid), state.None, "disabled by GUID")
        T.AssertEqual(api.GetAddOnEnableState("Altoholic", env.UnitName("player")), state.All,
            "name key untouched -- the model treats keys as distinct until #6 says otherwise")
        T.AssertEqual(api.GetAddOnEnableState("Altoholic"), state.Some, "nil = across characters")
    end)

    T.Test("nil character enables and disables for everyone", function()
        local env = Setup()
        local api, state = env.C_AddOns, env.Enum.AddOnEnableState
        api.EnableAddOn("OffHere")
        T.AssertEqual(api.GetAddOnEnableState("OffHere"), state.All, "all")
        api.DisableAddOn("OffHere")
        T.AssertEqual(api.GetAddOnEnableState("OffHere"), state.None, "none")
    end)

    T.Test("mutations and saves are recorded in order", function()
        local env = Setup()
        local guid = env.UnitGUID("player")
        env.C_AddOns.DisableAddOn("DataStore", guid)
        env.C_AddOns.EnableAddOn(3, guid)
        env.C_AddOns.SaveAddOns()
        local calls = env.fixtures.calls
        T.AssertEqual(#calls, 3, "three calls")
        T.AssertEqual(calls[1][1] .. ":" .. calls[1][2], "DisableAddOn:DataStore")
        T.AssertEqual(calls[2][1] .. ":" .. calls[2][2], "EnableAddOn:3")
        T.AssertEqual(calls[3][1], "SaveAddOns")
    end)

    T.Test("TOC load order is what the loader uses", function()
        local files = stub.TocFiles()
        T.AssertEqual(files[1], "Core.lua", "Core loads first")
    end)
end
