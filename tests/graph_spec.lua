-- graph_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The dependency graph (#8) against the shapes the reference profile actually has to
-- cut through: DataStore/Altoholic, Details plugins, DBM modules. Records are plain
-- tables, so these specs need no C_AddOns fixtures, only the loaded Inventory module.

return function(stub, T)
    print("graph")

    local Inventory = stub.Load().ns.Inventory

    -- Builds records from a compact { name, deps, optionalDeps } shorthand.
    local function Build(list)
        local records = {}
        for i, entry in ipairs(list) do
            records[i] = { name = entry[1], deps = entry[2], optionalDeps = entry[3] }
        end
        return Inventory.BuildGraph(records)
    end

    local function Join(list) return table.concat(list, ",") end

    T.Test("a simple chain: requirements forward, dependents back", function()
        local g = Build({ { "A", { "B" } }, { "B", { "C" } }, { "C" } })
        T.AssertEqual(Join(g.deps.A), "B", "A requires B")
        T.AssertEqual(Join(g.deps.C), "", "C requires nothing")
        T.AssertEqual(Join(Inventory.Requirements(g, { "A" })), "B,C", "A needs B and C")
        T.AssertEqual(Join(Inventory.Dependents(g, { "C" })), "A,B", "C takes B and A")
        T.AssertEqual(Join(Inventory.Dependents(g, { "A" })), "", "nothing needs A")
    end)

    T.Test("reverse dependents are direct and required-only", function()
        local g = Build({ { "Core" }, { "One", { "Core" } }, { "Two", { "Core" } }, { "Opt", {}, { "Core" } } })
        T.AssertEqual(Join(g.dependents.Core), "One,Two", "Opt is optional, so not a dependent")
        T.AssertEqual(Join(g.dependents.One), "", "leaf has none")
        T.AssertEqual(Join(g.names), "Core,One,Opt,Two", "every installed name")
    end)

    T.Test("DataStore off takes Altoholic and every DataStore_* module", function()
        local g = Build({
            { "DataStore" },
            { "DataStore_Characters", { "DataStore" } },
            { "DataStore_Containers", { "DataStore" } },
            { "DataStore_Talents", { "DataStore" } },
            { "Altoholic", { "DataStore", "DataStore_Characters", "DataStore_Containers" } },
            { "Altoholic_Summary", { "Altoholic" } },
            { "Altoholic_Grids", { "Altoholic" } },
            { "AddonFactory" },
        })
        T.AssertEqual(Join(Inventory.Dependents(g, { "DataStore" })),
            "Altoholic,Altoholic_Grids,Altoholic_Summary,DataStore_Characters,DataStore_Containers,"
                .. "DataStore_Talents", "the whole family")
        T.AssertEqual(Join(Inventory.Dependents(g, { "DataStore_Talents" })), "", "unused module")
        T.AssertEqual(Join(Inventory.Dependents(g, { "DataStore_Containers" })),
            "Altoholic,Altoholic_Grids,Altoholic_Summary", "a module Altoholic requires")
        T.AssertEqual(Join(Inventory.Requirements(g, { "Altoholic_Grids" })),
            "Altoholic,DataStore,DataStore_Characters,DataStore_Containers", "restore order input")
    end)

    T.Test("Details off takes its plugins; a plugin off takes nothing", function()
        local g = Build({
            { "Details" },
            { "Details_Streamer", { "Details" } },
            { "Details_Compare2", { "Details" } },
            { "Details_Vanguard", { "Details" } },
            { "Details_RaidCheck", { "Details" } },
        })
        T.AssertEqual(Join(Inventory.Dependents(g, { "Details" })),
            "Details_Compare2,Details_RaidCheck,Details_Streamer,Details_Vanguard", "all plugins")
        T.AssertEqual(Join(Inventory.Dependents(g, { "Details_Streamer" })), "", "leaf")
        T.AssertEqual(Join(Inventory.Requirements(g, { "Details_Vanguard" })), "Details", "core")
    end)

    T.Test("DBM: raid modules and the GUI hang off DBM-Core", function()
        local g = Build({
            { "DBM-Core" },
            { "DBM-GUI", { "DBM-Core" } },
            { "DBM-Raids-Midnight", { "DBM-Core" } },
            { "DBM-Raids-WarWithin", { "DBM-Core" } },
            { "DBM-Raids-Dragonflight", { "DBM-Core" }, { "DBM-GUI" } },
        })
        T.AssertEqual(Join(Inventory.Dependents(g, { "DBM-Raids-Midnight", "DBM-Raids-WarWithin" })), "",
            "turning raid modules off cascades nowhere")
        T.AssertEqual(Join(Inventory.Dependents(g, { "DBM-GUI" })), "", "optional dep on the GUI")
        T.AssertEqual(Join(Inventory.Dependents(g, { "DBM-Core" })),
            "DBM-GUI,DBM-Raids-Dragonflight,DBM-Raids-Midnight,DBM-Raids-WarWithin", "core takes all")
    end)

    T.Test("optional dependencies are recorded but never cascade", function()
        local g = Build({ { "Altoholic", {}, { "Auctionator", "NotInstalled" } }, { "Auctionator" } })
        T.AssertEqual(Join(g.optionalDeps.Altoholic), "Auctionator", "installed optional kept")
        T.AssertEqual(Join(g.dependents.Auctionator), "", "not a dependent")
        T.AssertEqual(Join(Inventory.Dependents(g, { "Auctionator" })), "", "disable does not cascade")
        T.AssertEqual(Join(Inventory.Requirements(g, { "Altoholic" })), "", "enable does not cascade")
        T.AssertEqual(g.missing.Altoholic, nil, "a missing optional dep is not reported")
    end)

    T.Test("a missing required dependency is reported, not fatal", function()
        local g = Build({ { "Altoholic", { "DataStore", "Ghost", "DataStore_Gone" } }, { "DataStore" } })
        T.AssertEqual(Join(g.missing.Altoholic), "DataStore_Gone,Ghost", "missing, sorted")
        T.AssertEqual(g.missing.DataStore, nil, "no entry when nothing is missing")
        T.AssertEqual(Join(g.deps.Altoholic), "DataStore", "installed deps still resolve")
        T.AssertEqual(Join(Inventory.Requirements(g, { "Altoholic" })), "DataStore", "missing skipped")
        T.AssertEqual(Join(Inventory.Dependents(g, { "Ghost" })), "", "unknown input ignored")
    end)

    T.Test("a two-node cycle terminates and lists each addon once", function()
        local g = Build({ { "A", { "B" } }, { "B", { "A" } }, { "C", { "A" } } })
        T.AssertEqual(Join(Inventory.Dependents(g, { "A" })), "B,C", "A excluded as the input")
        T.AssertEqual(Join(Inventory.Requirements(g, { "C" })), "A,B", "each once")
    end)

    T.Test("a three-node cycle terminates and lists each addon once", function()
        local g = Build({ { "A", { "B" } }, { "B", { "C" } }, { "C", { "A" } } })
        T.AssertEqual(Join(Inventory.Dependents(g, { "A" })), "B,C", "dependents")
        T.AssertEqual(Join(Inventory.Requirements(g, { "B" })), "A,C", "requirements")
        T.AssertEqual(Join(Inventory.Dependents(g, { "A", "B", "C" })), "", "all inputs, nothing added")
    end)

    T.Test("a self-dependency is dropped", function()
        local g = Build({ { "Narcissus", { "Narcissus", "narcissus" } }, { "Other", { "Narcissus" } } })
        T.AssertEqual(Join(g.deps.Narcissus), "", "no self edge")
        T.AssertEqual(g.missing.Narcissus, nil, "and not reported missing")
        T.AssertEqual(Join(Inventory.Dependents(g, { "Narcissus" })), "Other", "terminates")
    end)

    T.Test("names match case-insensitively and keep the installed spelling", function()
        local g = Build({
            { "DataStore" },
            { "DataStore_Characters", { "datastore" } },
            { "Altoholic", { "DATASTORE", "datastore_characters" } },
        })
        T.AssertEqual(Join(g.deps.Altoholic), "DataStore,DataStore_Characters", "canonical spelling")
        T.AssertEqual(Join(g.dependents.DataStore), "Altoholic,DataStore_Characters", "reverse too")
        T.AssertEqual(Join(Inventory.Dependents(g, { "dAtAsToRe" })),
            "Altoholic,DataStore_Characters", "query in any case")
        T.AssertEqual(g.canonical.datastore, "DataStore", "lookup table")
        T.AssertEqual(Join(Inventory.Dependents(g, { "DataStore", "DATASTORE" })),
            "Altoholic,DataStore_Characters", "duplicate input in another case")
    end)

    T.Test("extra record fields are ignored; repeated names keep the first", function()
        local g = Inventory.BuildGraph({
            { name = "A", title = "Alpha", loadable = false, enabled = true, deps = { "B" } },
            { name = "B", reason = "MISSING" },
            { name = "a", deps = { "C" } },
        })
        T.AssertEqual(Join(g.names), "A,B", "the second A is ignored")
        T.AssertEqual(Join(g.deps.A), "B", "first record wins")
    end)

    T.Test("empty input gives an empty graph and empty closures", function()
        local g = Inventory.BuildGraph({})
        T.AssertEqual(#g.names, 0, "no names")
        T.AssertEqual(#Inventory.Dependents(g, { "Anything" }), 0, "no dependents")
        T.AssertEqual(#Inventory.Requirements(g, {}), 0, "no requirements")
        T.AssertEqual(#Inventory.BuildGraph(nil).names, 0, "nil tolerated")
    end)

    T.Test("output order is case-insensitive and stable across input order", function()
        local forward = { { "zeta", { "Core" } }, { "Alpha", { "Core" } }, { "beta", { "Core" } }, { "Core" } }
        local backward = {}
        for i = #forward, 1, -1 do backward[#backward + 1] = forward[i] end
        local a = Join(Inventory.Dependents(Build(forward), { "Core" }))
        local b = Join(Inventory.Dependents(Build(backward), { "Core" }))
        T.AssertEqual(a, "Alpha,beta,zeta", "case-insensitive sort")
        T.AssertEqual(b, a, "same result either way")
        T.AssertEqual(Join(Build(backward).names), "Alpha,beta,Core,zeta", "names sorted too")
    end)
end
