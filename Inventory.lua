-- Inventory.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- What is installed, and what this character has enabled. Read-only over C_AddOns:
-- enumerates addons (name, title, loadable/reason, load-on-demand, enable state for the
-- current character), builds the dependency graph (required deps and reverse
-- dependents), and answers the safe-to-switch question. Pure where it can be, so the
-- offline suite covers it. Filled in by v0.2.0 (#7, #8, #10).

local _, ns = ...

local Inventory = {}
ns.Inventory = Inventory

--------------------------------------------------------------------------
-- Inventory (#7)
--
-- One read of every installed addon into plain records, the input to the dependency
-- graph and (v0.3.0) the switch plan. The enable state is read for this character by
-- GUID: the live client treats the GUID and the name as the same character, while nil
-- and "0" mean every character (#6, docs/HANDOFF.md "API facts").
--------------------------------------------------------------------------

-- Returns a list of records in the client's addon order:
--   { index, name, title, loadable, reason, loadOnDemand, loaded, enabled,
--     deps = {...}, optionalDeps = {...} }
-- `reason` is nil when the client has nothing to report (it answers "" for that).
-- `deps` and `optionalDeps` are spelled as each TOC wrote them; BuildGraph matches
-- them to folder names case-insensitively.
function Inventory:Scan()
    local guid = UnitGUID("player")
    local none = Enum.AddOnEnableState.None
    local records = {}
    for index = 1, C_AddOns.GetNumAddOns() do
        local name, title, _, loadable, reason = C_AddOns.GetAddOnInfo(index)
        if name then
            records[#records + 1] = {
                index = index,
                name = name,
                title = title or name,
                loadable = loadable and true or false,
                reason = reason ~= "" and reason or nil,
                loadOnDemand = C_AddOns.IsAddOnLoadOnDemand(index) and true or false,
                loaded = C_AddOns.IsAddOnLoaded(index) and true or false,
                enabled = C_AddOns.GetAddOnEnableState(index, guid) > none,
                deps = { C_AddOns.GetAddOnDependencies(index) },
                optionalDeps = { C_AddOns.GetAddOnOptionalDependencies(index) },
            }
        end
    end
    return records
end

-- The installed addons and their dependency graph, read now.
function Inventory:Read()
    local records = self:Scan()
    return records, Inventory.BuildGraph(records)
end

--------------------------------------------------------------------------
-- Dependency graph (#8)
--
-- Pure functions over a plain list of records, `{ name = "Altoholic", deps = {...},
-- optionalDeps = {...} }`; any other field is ignored. Nothing here touches C_AddOns:
-- the inventory (#7) builds the records, this turns them into edges, and the switch
-- plan (v0.3.0) walks the edges.
--
-- Names are matched case-insensitively, because a TOC's `## Dependencies:` line is
-- often written in a different case from the folder it names (`datastore` for
-- `DataStore`). Whether the client already normalises that is unverified (#6), so the
-- graph tolerates it either way. Outputs always use the installed folder's spelling.
--------------------------------------------------------------------------

-- Case-insensitive, with the raw string as tie-breaker, so two names differing only in
-- case still come out in the same order every run.
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

-- Returns a table of:
--   names         every installed addon, sorted
--   canonical     lower-cased name -> installed spelling
--   deps          name -> sorted list of installed required dependencies
--   optionalDeps  name -> sorted list of installed optional dependencies; recorded for
--                 display, never followed by a cascade
--   dependents    name -> sorted list of installed addons that require it
--   missing       name -> sorted list of required dependencies that are not installed,
--                 as the TOC spelled them; no entry when there are none
-- Every installed name has a list (possibly empty) in deps, optionalDeps and dependents.
-- A self-dependency is dropped rather than recorded as an edge, a repeated record (same
-- name in any case) is ignored after the first, and a missing optional dependency is
-- simply not recorded: leaving an optional addon uninstalled is normal.
function Inventory.BuildGraph(records)
    local graph = {
        names = {}, canonical = {}, deps = {}, optionalDeps = {}, dependents = {}, missing = {},
    }
    local canonical = graph.canonical
    local installed = {}

    for _, record in ipairs(records or {}) do
        local name = record.name
        if type(name) == "string" and not canonical[name:lower()] then
            canonical[name:lower()] = name
            installed[#installed + 1] = record
        end
    end

    -- Splits a dependency list into a set of installed names and a set of missing
    -- spellings, dropping the owner itself.
    local function Resolve(owner, list)
        local found, absent = {}, {}
        for _, dep in ipairs(list or {}) do
            if type(dep) == "string" then
                local name = canonical[dep:lower()]
                if not name then
                    absent[dep] = true
                elseif name ~= owner then
                    found[name] = true
                end
            end
        end
        return found, absent
    end

    local reverse = {}
    for _, record in ipairs(installed) do
        local name = record.name
        reverse[name] = reverse[name] or {}
        local required, absent = Resolve(name, record.deps)
        local optional = Resolve(name, record.optionalDeps)
        graph.deps[name] = SortedKeys(required)
        graph.optionalDeps[name] = SortedKeys(optional)
        if next(absent) then graph.missing[name] = SortedKeys(absent) end
        for dep in pairs(required) do
            reverse[dep] = reverse[dep] or {}
            reverse[dep][name] = true
        end
    end

    for name, set in pairs(reverse) do
        graph.dependents[name] = SortedKeys(set)
    end
    graph.names = SortedKeys(reverse)
    return graph
end

-- Breadth-first walk over one edge map from every start name. The start names are left
-- out of the result, so it holds only what the cascade adds: the caller already has the
-- names it asked about, and the preview marks cascade entries separately. Unknown names
-- are ignored, and the visited set is what makes a cycle terminate with each addon
-- listed once.
local function Closure(graph, edges, names)
    local start, queue = {}, {}
    for _, given in ipairs(names or {}) do
        local name = type(given) == "string" and graph.canonical[given:lower()]
        if name and not start[name] then
            start[name] = true
            queue[#queue + 1] = name
        end
    end

    local seen, result = {}, {}
    local head = 1
    while queue[head] do
        for _, nextName in ipairs(edges[queue[head]]) do
            if not start[nextName] and not seen[nextName] then
                seen[nextName] = true
                result[#result + 1] = nextName
                queue[#queue + 1] = nextName
            end
        end
        head = head + 1
    end
    table.sort(result, NameLess)
    return result
end

-- The disable cascade: every installed addon that transitively requires any of `names`
-- and so would fail to load without it. Turning off DataStore takes Altoholic and every
-- DataStore_* module with it. Optional dependencies never cascade. The input names
-- themselves are not included; the result is sorted case-insensitively.
function Inventory.Dependents(graph, names)
    return Closure(graph, graph.dependents, names)
end

-- The enable cascade for a restore: every installed addon that any of `names`
-- transitively requires. Same rules as Dependents: input names excluded, optional
-- dependencies not followed, missing ones skipped (they are in graph.missing), sorted.
function Inventory.Requirements(graph, names)
    return Closure(graph, graph.deps, names)
end

--------------------------------------------------------------------------
-- Safe-to-switch guard (#10)
--
-- The one check every switch path goes through (HANDOFF design rule "One guard"): no
-- switch, and so no reload, in combat, inside an active keystone, or during a boss
-- encounter. Each API is looked up at call time and nil-guarded. A missing API means the
-- check is unavailable on this client, not that it is unsafe: blocking on it would lock
-- the player out of switching entirely, so it is skipped rather than counted against
-- them. IsEncounterInProgress in particular is not yet confirmed to exist on 12.x.
--------------------------------------------------------------------------

-- True only when the client has `fn` and it answers yes; an unavailable check is a no.
local function Ask(fn)
    return type(fn) == "function" and fn() and true or false
end

-- Returns true when a switch may happen now, or false and a short player-facing reason.
function Inventory:CanSwitch()
    if Ask(InCombatLockdown) then return false, "in combat" end
    local challengeMode = C_ChallengeMode
    if type(challengeMode) == "table" and Ask(challengeMode.IsChallengeModeActive) then
        return false, "a keystone is active"
    end
    if Ask(IsEncounterInProgress) then return false, "a boss encounter is in progress" end
    return true
end
