-- plan_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The switch plan (#13, model in #37): baseline minus the mode's list and its cascade,
-- protected addons and their requirements kept, off restoring the baseline exactly.
-- Records are plain tables and the protect check is passed in, so these specs need no
-- C_AddOns fixtures or saved data.

return function(stub, T)
    print("plan")

    local ns = stub.Load().ns
    local Inventory, Plan = ns.Inventory, ns.Plan

    -- Records from a compact { name, enabled, deps, optionalDeps } shorthand.
    local function Records(list)
        local records = {}
        for i, entry in ipairs(list) do
            records[i] = { name = entry[1], enabled = entry[2], deps = entry[3], optionalDeps = entry[4] }
        end
        return records
    end

    local function NoneProtected() return false end

    local function Run(records, mode, opts)
        opts = opts or {}
        return Plan.Build({
            records = records,
            graph = Inventory.BuildGraph(records),
            baseline = opts.baseline,
            mode = mode,
            lists = opts.lists or {},
            isProtected = opts.isProtected or NoneProtected,
        })
    end

    local function Join(list) return table.concat(list, ",") end

    -- "name:reason" entries, in plan order.
    local function Entries(list)
        local out = {}
        for i, entry in ipairs(list) do out[i] = entry.name .. ":" .. entry.reason end
        return table.concat(out, ",")
    end

    local function Names(list)
        local out = {}
        for i, entry in ipairs(list) do out[i] = entry.name end
        return table.concat(out, ",")
    end

    -- The installed names whose target is on, sorted.
    local function On(plan)
        local out = {}
        for name, on in pairs(plan.target) do
            if on then out[#out + 1] = name end
        end
        table.sort(out, function(a, b) return a:lower() < b:lower() end)
        return table.concat(out, ",")
    end

    T.Test("off restores the baseline exactly, both directions", function()
        local records = Records({ { "A", true }, { "B", false }, { "C", true }, { "D", false } })
        local plan = Run(records, "off", { baseline = { A = false, B = true, C = true, D = false } })
        T.AssertEqual(Entries(plan.disable), "A:baseline", "A was off in the baseline")
        T.AssertEqual(Entries(plan.enable), "B:baseline", "B was on in the baseline")
        T.AssertEqual(On(plan), "B,C", "target is the baseline")
        T.AssertEqual(plan.target.D, false, "D stays off")
        T.AssertEqual(#plan.kept + #plan.removed + #plan.unknown, 0, "nothing else to report")
    end)

    T.Test("instance mode: listed and cascade, with reasons", function()
        local records = Records({ { "Core", true }, { "Mod", true, { "Core" } }, { "Other", true } })
        local plan = Run(records, "instance", {
            baseline = { Core = true, Mod = true, Other = true },
            lists = { instance = { Core = true }, world = { Other = true } },
        })
        T.AssertEqual(Entries(plan.disable), "Core:listed,Mod:cascade", "Core and what needs it")
        T.AssertEqual(#plan.enable, 0, "nothing to enable")
        T.AssertEqual(On(plan), "Other", "the world list does not apply in instance mode")
    end)

    T.Test("listing DataStore takes Altoholic, DataStore_* and AddonFactory", function()
        local records = Records({
            { "DataStore", true },
            { "DataStore_Characters", true, { "DataStore" } },
            { "DataStore_Containers", true, { "DataStore" } },
            { "DataStore_Talents", false, { "DataStore" } },
            { "Altoholic", true, { "DataStore", "DataStore_Characters", "DataStore_Containers" } },
            { "Altoholic_Grids", true, { "Altoholic" } },
            { "AddonFactory", true, { "DataStore" } },
            { "Details", true },
        })
        local plan = Run(records, "instance", { lists = { instance = { DataStore = true } } })
        T.AssertEqual(Entries(plan.disable),
            "AddonFactory:cascade,Altoholic:cascade,Altoholic_Grids:cascade,DataStore:listed,"
                .. "DataStore_Characters:cascade,DataStore_Containers:cascade", "the whole family")
        T.AssertEqual(plan.target.DataStore_Talents, false, "already off, stays off")
        T.AssertEqual(On(plan), "Details", "only the unrelated addon is left")
    end)

    T.Test("listing Details takes its plugins", function()
        local records = Records({
            { "Details", true },
            { "Details_Streamer", true, { "Details" } },
            { "Details_Vanguard", true, { "Details" } },
            { "BugSack", true },
        })
        local plan = Run(records, "world", { lists = { world = { Details = true } } })
        T.AssertEqual(Entries(plan.disable),
            "Details:listed,Details_Streamer:cascade,Details_Vanguard:cascade", "core and plugins")
        local leaf = Run(records, "world", { lists = { world = { Details_Streamer = true } } })
        T.AssertEqual(Entries(leaf.disable), "Details_Streamer:listed", "a plugin takes nothing")
    end)

    T.Test("DBM: modules hang off DBM-Core; DBM-StatusBarTimers takes it all", function()
        local records = Records({
            { "DBM-StatusBarTimers", true },
            { "DBM-Core", true, { "DBM-StatusBarTimers" } },
            { "DBM-GUI", true, { "DBM-Core" } },
            { "DBM-Raids-Midnight", true, { "DBM-Core" } },
            { "DBM-Party-Midnight", true, { "DBM-Core" } },
        })
        local core = Run(records, "instance", { lists = { instance = { ["DBM-Core"] = true } } })
        T.AssertEqual(Entries(core.disable),
            "DBM-Core:listed,DBM-GUI:cascade,DBM-Party-Midnight:cascade,DBM-Raids-Midnight:cascade",
            "modules go with the core")
        T.AssertEqual(core.target["DBM-StatusBarTimers"], true, "a requirement is not cascaded")
        local timers = Run(records, "instance", { lists = { instance = { ["DBM-StatusBarTimers"] = true } } })
        T.AssertEqual(Entries(timers.disable),
            "DBM-Core:cascade,DBM-GUI:cascade,DBM-Party-Midnight:cascade,DBM-Raids-Midnight:cascade,"
                .. "DBM-StatusBarTimers:listed", "the core requires the timers")
    end)

    T.Test("World -> Instance turns world-listed addons back on unless instance-listed", function()
        -- Current state is World mode: A and B (world-listed) are off.
        local records = Records({ { "A", false }, { "B", false }, { "C", true }, { "D", true } })
        local plan = Run(records, "instance", {
            baseline = { A = true, B = true, C = true, D = true },
            lists = { world = { A = true, B = true }, instance = { B = true, D = true } },
        })
        T.AssertEqual(Entries(plan.enable), "A:baseline", "A comes back")
        T.AssertEqual(Entries(plan.disable), "D:listed", "D goes")
        T.AssertEqual(plan.target.B, false, "B is on both lists, stays off")
        T.AssertEqual(On(plan), "A,C", "target")
    end)

    T.Test("an empty world list makes world mode the baseline", function()
        local records = Records({ { "A", true }, { "B", false }, { "C", false } })
        local baseline = { A = true, B = true, C = false }
        local plan = Run(records, "world", { baseline = baseline, lists = { instance = { A = true } } })
        T.AssertEqual(On(plan), "A,B", "target == baseline")
        T.AssertEqual(Entries(plan.enable), "B:baseline", "B comes back")
        T.AssertEqual(#plan.disable, 0, "nothing off")
        local missing = Run(records, "world", { baseline = baseline, lists = { world = {} } })
        T.AssertEqual(On(missing), "A,B", "an explicit empty list is the same")
    end)

    T.Test("protected addons are never disabled; their requirements are kept", function()
        local records = Records({
            { "KeyMode", true },
            { "Lib", true },
            { "BugSack", true, { "Lib" } },
            { "Other", true, { "Lib" } },
            { "Solo", true },
        })
        local protected = { keymode = true, bugsack = true }
        local plan = Run(records, "instance", {
            lists = { instance = { KeyMode = true, Lib = true, Solo = true } },
            isProtected = function(name) return protected[name:lower()] or false end,
        })
        T.AssertEqual(Entries(plan.disable), "Solo:listed", "only unprotected addons")
        T.AssertEqual(Join(plan.kept), "BugSack,KeyMode,Lib", "kept because of protection")
        T.AssertEqual(plan.target.Lib, true, "BugSack still loads")
        T.AssertEqual(plan.target.Other, true, "a kept Lib takes no cascade with it")
        T.AssertEqual(plan.target.KeyMode, true, "KeyMode stays on")
    end)

    T.Test("list and baseline names match case-insensitively; unknown and removed", function()
        local records = Records({ { "DataStore", true }, { "BugSack", false } })
        local plan = Run(records, "instance", {
            baseline = { datastore = true, BUGSACK = true, OldAddon = true },
            lists = { instance = { DATASTORE = true, NotInstalled = true, gone = true } },
        })
        T.AssertEqual(Entries(plan.disable), "DataStore:listed", "installed spelling")
        T.AssertEqual(Entries(plan.enable), "BugSack:baseline", "baseline in any case")
        T.AssertEqual(Join(plan.unknown), "gone,NotInstalled", "as the list spelled them")
        T.AssertEqual(Join(plan.removed), "OldAddon", "baseline names no longer installed")
        local off = Run(records, "off", { baseline = { datastore = false } })
        T.AssertEqual(Names(off.disable), "DataStore", "off matches in any case too")
        T.AssertEqual(#off.unknown, 0, "off mode has no list")
    end)

    T.Test("an addon installed after the baseline", function()
        local records = Records({ { "A", true }, { "New", true }, { "NewOff", false } })
        local baseline = { A = true }
        local off = Run(records, "off", { baseline = baseline })
        T.AssertEqual(#off.disable + #off.enable, 0, "off leaves it as it is")
        T.AssertEqual(On(off), "A,New", "current state stands in for the baseline")
        local mode = Run(records, "world", { baseline = baseline, lists = { world = { New = true } } })
        T.AssertEqual(Entries(mode.disable), "New:listed", "a mode still applies the list")
    end)

    T.Test("a nil baseline uses the current state", function()
        local records = Records({ { "A", true }, { "B", false }, { "C", true } })
        local off = Run(records, "off")
        T.AssertEqual(#off.disable + #off.enable, 0, "off is a no-op")
        T.AssertEqual(#off.removed, 0, "nothing removed")
        local plan = Run(records, "instance", { lists = { instance = { C = true } } })
        T.AssertEqual(Entries(plan.disable), "C:listed", "C off")
        T.AssertEqual(On(plan), "A", "B stays off")
    end)

    T.Test("a dependency cycle does not hang", function()
        local records = Records({
            { "A", true, { "B" } }, { "B", true, { "C" } }, { "C", true, { "A" } }, { "D", true },
        })
        local plan = Run(records, "instance", { lists = { instance = { A = true } } })
        T.AssertEqual(Entries(plan.disable), "A:listed,B:cascade,C:cascade", "each once")
        T.AssertEqual(On(plan), "D", "target")
        local guarded = Run(records, "instance", {
            lists = { instance = { A = true } },
            isProtected = function(name) return name == "B" end,
        })
        T.AssertEqual(Join(guarded.kept), "A,B,C", "B requires the whole cycle")
        T.AssertEqual(#guarded.disable, 0, "nothing off")
    end)

    T.Test("input tables are not mutated", function()
        local records = Records({ { "Core", true }, { "Mod", false, { "Core" } }, { "X", true } })
        local graph = Inventory.BuildGraph(records)
        local baseline = { Core = true, Mod = true, Gone = true }
        local lists = { instance = { core = true, Missing = true }, world = { X = true } }
        local function Dump(value, seen)
            seen = seen or {}
            if type(value) ~= "table" then return tostring(value) end
            if seen[value] then return "<cycle>" end
            seen[value] = true
            local keys = {}
            for k in pairs(value) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            local parts = {}
            for _, k in ipairs(keys) do
                local v = value[k]
                if v == nil then v = value[tonumber(k)] end
                parts[#parts + 1] = k .. "=" .. Dump(v, seen)
            end
            return "{" .. table.concat(parts, ";") .. "}"
        end
        local before = Dump({ records, graph, baseline, lists })
        for _, mode in ipairs({ "instance", "world", "off" }) do
            Plan.Build({
                records = records, graph = graph, baseline = baseline, mode = mode, lists = lists,
                isProtected = function(name) return name == "X" end,
            })
        end
        T.AssertEqual(Dump({ records, graph, baseline, lists }), before, "unchanged")
    end)
end
