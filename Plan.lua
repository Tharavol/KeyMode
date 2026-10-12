-- Plan.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The switch plan: which addons a switch turns off and which it turns back on, worked
-- out from the baseline, the Instance and World lists and the dependency graph. Pure: no
-- C_AddOns calls, no ns.db access, no chat output. Switch.lua applies what this returns.
-- Filled in by v0.3.0 (#13, model in #37).
--
-- The plan needs no separate requirements pass. The target is the baseline minus a
-- dependents-closed set (listed addons plus everything that transitively requires them),
-- so every addon left on still has its required dependencies whenever the baseline did.
-- An inconsistent baseline, one with an addon on and a requirement off, is restored as
-- it was: exact restore beats repair (HANDOFF design rule "Restore is exact").

local _, ns = ...

local Plan = {}
ns.Plan = Plan

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

-- Same order as Inventory's NameLess: case-insensitive, raw string as tie-breaker.
local function NameLess(a, b)
    local la, lb = a:lower(), b:lower()
    if la ~= lb then return la < lb end
    return a < b
end

local function SortedKeys(set)
    local list = {}
    for name in pairs(set) do list[#list + 1] = name end
    table.sort(list, NameLess)
    return list
end

-- A name -> value map keyed by lower-cased name. When a hand-edited table holds two
-- spellings of one addon, the first in sorted order wins, so the answer is stable.
local function Lowered(map)
    local lowered = {}
    if type(map) ~= "table" then return lowered end
    local keys = {}
    for key in pairs(map) do
        if type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys, NameLess)
    for _, key in ipairs(keys) do
        local lower = key:lower()
        if lowered[lower] == nil then lowered[lower] = map[key] end
    end
    return lowered
end

--------------------------------------------------------------------------
-- Build (#13)
--
-- Instance mode is the baseline minus the Instance list and its disable cascade; World
-- mode is the baseline minus the World list and its cascade; off is the baseline
-- exactly. Each mode is computed from the baseline, never from the current state, so
-- going World -> Instance turns World-listed addons back on unless the Instance list
-- names them too. A protected addon is never turned off, and neither is anything it
-- requires, because a protected addon must still load.
--------------------------------------------------------------------------

-- `input` is a table of:
--   records      list from Inventory:Scan(); uses `name` and `enabled` (current state)
--   graph        Inventory.BuildGraph(records)
--   baseline     { [name] = bool } taken before the first switch, or nil to use the
--                current state; names match case-insensitively
--   mode         "instance" | "world" | "off"
--   lists        { instance = { [name] = true }, world = { [name] = true } }; either may
--                be missing, names may be any case and may name addons not installed
--   isProtected  function(name) -> bool
-- Returns a table of:
--   target   installed name -> bool, the state after the switch
--   disable  sorted { name, reason } for addons the switch turns off; reason is
--            "listed" or "cascade", or "baseline" in off mode
--   enable   sorted { name, reason = "baseline" } for addons the switch turns on
--   kept     sorted names that were listed or cascade but stay as the baseline had them
--            because of protection
--   removed  sorted baseline names that are no longer installed
--   unknown  sorted names in the mode's list that are not installed, as the list
--            spelled them
-- Every list is present, possibly empty. The input tables are not modified.
function Plan.Build(input)
    local graph = input.graph
    local canonical = graph.canonical
    local Inventory = ns.Inventory
    local isProtected = input.isProtected or function() return false end
    local mode = input.mode

    -- Current state per installed name, from the first record of each name (BuildGraph
    -- ignores repeats the same way).
    local current = {}
    for _, record in ipairs(input.records or {}) do
        local name = type(record.name) == "string" and canonical[record.name:lower()]
        if name and current[name] == nil then current[name] = record.enabled and true or false end
    end

    local baseline = input.baseline
    local lowBaseline = Lowered(baseline)
    local base = {}
    for _, name in ipairs(graph.names) do
        local saved = lowBaseline[name:lower()]
        if saved == nil then
            base[name] = current[name] or false
        else
            base[name] = saved and true or false
        end
    end

    local removed = {}
    if type(baseline) == "table" then
        for key in pairs(baseline) do
            if type(key) == "string" and not canonical[key:lower()] then removed[key] = true end
        end
    end

    local listed, cascade, keptSet, unknown = {}, {}, {}, {}
    if mode == "instance" or mode == "world" then
        local list = type(input.lists) == "table" and input.lists[mode] or nil
        if type(list) == "table" then
            for key, value in pairs(list) do
                if type(key) == "string" and value then
                    local name = canonical[key:lower()]
                    if name then listed[name] = true else unknown[key] = true end
                end
            end
        end

        local protected, keep = {}, {}
        for _, name in ipairs(graph.names) do
            if isProtected(name) then
                protected[#protected + 1] = name
                keep[name] = true
            end
        end
        for _, name in ipairs(Inventory.Requirements(graph, protected)) do keep[name] = true end

        -- Kept: what the full list and its cascade would have turned off but protection
        -- holds on. The cascade is then taken from the listed addons that actually go
        -- off, so a listed DataStore kept for a protected Altoholic does not still take
        -- its other modules with it.
        for _, name in ipairs(Inventory.Dependents(graph, SortedKeys(listed))) do
            if keep[name] and not listed[name] then keptSet[name] = true end
        end
        for name in pairs(keep) do
            if listed[name] then
                keptSet[name] = true
                listed[name] = nil
            end
        end
        for _, name in ipairs(Inventory.Dependents(graph, SortedKeys(listed))) do
            if not listed[name] and not keep[name] then cascade[name] = true end
        end
    end

    local target, disable, enable = {}, {}, {}
    for _, name in ipairs(graph.names) do
        local on = base[name] and not (listed[name] or cascade[name])
        target[name] = on and true or false
        if current[name] and not on then
            local reason = "baseline"
            if listed[name] then reason = "listed" elseif cascade[name] then reason = "cascade" end
            disable[#disable + 1] = { name = name, reason = reason }
        elseif on and not current[name] then
            enable[#enable + 1] = { name = name, reason = "baseline" }
        end
    end

    return {
        target = target,
        disable = disable,
        enable = enable,
        kept = SortedKeys(keptSet),
        removed = SortedKeys(removed),
        unknown = SortedKeys(unknown),
    }
end
