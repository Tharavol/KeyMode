-- inventory_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Inventory:Scan() (#7): one read of every installed addon into the records the
-- dependency graph and the switch plan work from.

return function(stub, T)
    print("inventory")

    local OTHER = "Player-5678-0FEDCBA9"

    local function Boot()
        return stub.Boot(function(_, fixtures)
            stub.AddAddon(fixtures, "DataStore", { title = "|cff00ff00DataStore|r",
                metadata = { Category = "Libraries" } })
            stub.AddAddon(fixtures, "DataStore_Containers", { deps = { "datastore" } })
            stub.AddAddon(fixtures, "Altoholic", { deps = { "DataStore", "DataStore_Containers" },
                optionalDeps = { "Auctionator" } })
            stub.AddAddon(fixtures, "DBM-GUI", { loadOnDemand = true })
            stub.AddAddon(fixtures, "OffHere", { enabled = false })
            stub.AddAddon(fixtures, "AltOnly", { enabledFor = { [OTHER] = true } })
            stub.AddAddon(fixtures, "Broken", { loadable = false, reason = "MISSING", deps = { "Gone" },
                metadata = { Category = "" } })
        end)
    end

    local function ByName(records)
        local map = {}
        for _, record in ipairs(records) do map[record.name] = record end
        return map
    end

    T.Test("every installed addon comes back once, in client order", function()
        local env = Boot()
        local records = env.ns.Inventory:Scan()
        T.AssertEqual(#records, 8, "KeyMode plus seven fixtures")
        T.AssertEqual(records[1].name, "KeyMode", "client order")
        T.AssertEqual(records[3].index, 3, "index kept")
    end)

    T.Test("records carry title, flags and dependencies as the TOC spells them", function()
        local env = Boot()
        local r = ByName(env.ns.Inventory:Scan())
        T.AssertEqual(r.DataStore.title, "|cff00ff00DataStore|r", "title as given")
        T.AssertEqual(r.DataStore_Containers.deps[1], "datastore", "TOC case kept")
        T.AssertEqual(r.Altoholic.optionalDeps[1], "Auctionator", "optional deps")
        T.AssertTrue(r["DBM-GUI"].loadOnDemand, "LoD")
        T.AssertEqual(r["DBM-GUI"].reason, "DEMAND_LOADED", "LoD reason")
        T.AssertTrue(r.KeyMode.loaded, "loaded")
        T.AssertFalse(r.Broken.loadable, "unloadable")
        T.AssertEqual(r.Broken.reason, "MISSING", "reason")
    end)

    T.Test("category is the TOC's ## Category, nil when absent or empty", function()
        local env = Boot()
        local r = ByName(env.ns.Inventory:Scan())
        T.AssertEqual(r.DataStore.category, "Libraries", "set")
        T.AssertEqual(r.Altoholic.category, nil, "absent")
        T.AssertEqual(r.Broken.category, nil, "empty string")
    end)

    T.Test("the client's empty reason becomes nil", function()
        local env = Boot()
        T.AssertEqual(ByName(env.ns.Inventory:Scan()).DataStore.reason, nil, "nil, not \"\"")
    end)

    T.Test("enabled is this character's state, read by GUID", function()
        local env = Boot()
        local r = ByName(env.ns.Inventory:Scan())
        T.AssertTrue(r.DataStore.enabled, "on here")
        T.AssertFalse(r.OffHere.enabled, "off here")
        T.AssertFalse(r.AltOnly.enabled, "on for another character only")
        local reads = 0
        local original = env.C_AddOns.GetAddOnEnableState
        env.C_AddOns.GetAddOnEnableState = function(index, character)
            T.AssertEqual(character, env.fixtures.player.guid, "always the GUID, never nil or \"0\"")
            reads = reads + 1
            return original(index, character)
        end
        env.ns.Inventory:Scan()
        T.AssertEqual(reads, 8, "one read per addon")
    end)

    T.Test("a scan changes nothing", function()
        local env = Boot()
        env.ns.Inventory:Read()
        T.AssertEqual(#env.fixtures.calls, 0, "no C_AddOns mutation")
    end)

    T.Test("Read builds the graph over the scan", function()
        local env = Boot()
        local _, graph = env.ns.Inventory:Read()
        local off = env.ns.Inventory.Dependents(graph, { "DataStore" })
        T.AssertEqual(table.concat(off, ","), "Altoholic,DataStore_Containers", "cascade across TOC case")
        T.AssertEqual(graph.missing.Broken[1], "Gone", "missing reported")
    end)

    T.Test("/km debug probe inventory summarises and shows one addon's cascades", function()
        local env = Boot()
        stub.Slash(env, "/km debug probe inventory datastore")
        local text = table.concat(stub.TakeChat(env), "\n")
        T.AssertTrue(text:find("8 installed, 6 enabled for this character", 1, true), "summary")
        T.AssertTrue(text:find("also turns off: Altoholic, DataStore_Containers", 1, true), "dependents")
        stub.Slash(env, "/km debug probe inventory Altoholic")
        text = table.concat(stub.TakeChat(env), "\n")
        T.AssertTrue(text:find("also needs: DataStore, DataStore_Containers", 1, true), "requirements")
        T.AssertEqual(#env.fixtures.calls, 0, "read only")
    end)
end
