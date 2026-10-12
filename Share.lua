-- Share.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Import and export of the Instance, World and protect lists as plain text, so a setup
-- can be copied between accounts or shared with another player. Encode, Decode and Diff
-- are pure: no ns.db access, no C_AddOns calls, no chat output. Apply is thin and makes
-- every change through the Profiles methods it is handed. Filled in by v0.4.0 (#20).
--
-- The text format, version 1:
--
--   KeyMode lists 1
--   [instance]
--   DataStore
--   [world]
--   DBM-Core
--   [protected]
--   BugSack
--
-- Sections are optional and case-insensitive; names are one per line; blank lines and
-- lines starting with "#" are ignored. KeyMode itself is always protected, so it never
-- needs to be (and never may be) on a list.

local _, ns = ...

local Share = {}
ns.Share = Share

Share.VERSION = 1
Share.SECTIONS = { "instance", "world", "protected" }

local LISTS = { "instance", "world" }

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

-- Same order as Plan and Inventory: case-insensitive, raw string as tie-breaker.
local function NameLess(a, b)
    local la, lb = a:lower(), b:lower()
    if la ~= lb then return la < lb end
    return a < b
end

local function SelfName()
    return ns.ADDON_NAME or "KeyMode"
end

local function IsSelf(name)
    return name:lower() == SelfName():lower()
end

local function Trim(text)
    return text:match("^%s*(.-)%s*$")
end

-- The truthy string keys of a set, sorted.
local function SortedKeys(set)
    local list = {}
    if type(set) == "table" then
        for name, value in pairs(set) do
            if value and type(name) == "string" then list[#list + 1] = name end
        end
    end
    table.sort(list, NameLess)
    return list
end

-- A sorted array from a set or an array, whichever `names` is.
local function Names(names)
    if type(names) ~= "table" then return {} end
    if #names > 0 then
        local list = {}
        for _, name in ipairs(names) do
            if type(name) == "string" then list[#list + 1] = name end
        end
        table.sort(list, NameLess)
        return list
    end
    return SortedKeys(names)
end

-- lower-cased name -> spelling, first spelling in sorted order wins.
local function Index(list)
    local index = {}
    for _, name in ipairs(list) do
        local lower = name:lower()
        if index[lower] == nil then index[lower] = name end
    end
    return index
end

--------------------------------------------------------------------------
-- Encode
--------------------------------------------------------------------------

-- `lists` = { instance = { [name] = true }, world = { ... } }; `protected` = an optional
-- array of names (nil omits the [protected] section). Returns the text, ending in "\n".
function Share.Encode(lists, protected)
    lists = type(lists) == "table" and lists or {}
    local lines = { "KeyMode lists " .. Share.VERSION }
    for _, which in ipairs(LISTS) do
        lines[#lines + 1] = "[" .. which .. "]"
        for _, name in ipairs(SortedKeys(lists[which])) do lines[#lines + 1] = name end
    end
    if protected then
        lines[#lines + 1] = "[protected]"
        for _, name in ipairs(Names(protected)) do lines[#lines + 1] = name end
    end
    return table.concat(lines, "\n") .. "\n"
end

--------------------------------------------------------------------------
-- Decode
--------------------------------------------------------------------------

local function SplitLines(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end

-- Returns { instance = {...}, world = {...}, protected = {...} or nil, warnings = {...} },
-- name lists sorted, or nil and a player-facing error message.
function Share.Decode(text)
    if type(text) ~= "string" then return nil, "Nothing to import." end
    text = text:gsub("^\239\187\191", "")
    if not text:find("%S") then return nil, "Nothing to import." end

    local sections = {}   -- section -> { list = {...}, seen = { lower = true } }
    local warnings = {}
    local current
    local header = false

    -- Blank lines and comments dropped; each kept line remembers its number for errors.
    local content = {}
    for number, raw in ipairs(SplitLines(text)) do
        local line = Trim(raw)
        if line ~= "" and line:sub(1, 1) ~= "#" then content[#content + 1] = { number, line } end
    end

    for _, entry in ipairs(content) do
        local number, line = entry[1], entry[2]
        if not header then
            local version = line:lower():match("^keymode%s+lists%s+(%d+)$")
            if not version then
                return nil, "Not a KeyMode list: the first line should be \"KeyMode lists "
                    .. Share.VERSION .. "\"."
            end
            version = tonumber(version)
            if version > Share.VERSION then
                return nil, "These lists were made by a newer KeyMode (format " .. version
                    .. "). Update KeyMode to import them."
            elseif version < 1 then
                return nil, "Unsupported list format " .. version .. "."
            end
            header = true
        else
            local section = line:match("^%[%s*(.-)%s*%]$")
            if section then
                section = section:lower()
                if section ~= "instance" and section ~= "world" and section ~= "protected" then
                    return nil, "Line " .. number .. ": unknown section \"" .. line .. "\"."
                end
                sections[section] = sections[section] or { list = {}, seen = {} }
                current = section
            elseif not current then
                return nil, "Line " .. number .. ": \"" .. line .. "\" is not under a section."
            elseif IsSelf(line) then
                if current ~= "protected" then
                    warnings[#warnings + 1] = SelfName() .. " was dropped from the " .. current
                        .. " list: it is always protected."
                end
            else
                local into, lower = sections[current], line:lower()
                if not into.seen[lower] then
                    into.seen[lower] = true
                    into.list[#into.list + 1] = line
                end
            end
        end
    end

    local result = { warnings = warnings }
    for _, section in ipairs(Share.SECTIONS) do
        local entry = sections[section]
        if entry then
            table.sort(entry.list, NameLess)
            result[section] = entry.list
        elseif section ~= "protected" then
            result[section] = {}
        end
    end
    return result
end

--------------------------------------------------------------------------
-- Diff
--------------------------------------------------------------------------

local function DiffOne(currentList, incomingList, removes)
    local add, remove = {}, {}
    local have, want = Index(currentList), Index(incomingList)
    for lower, name in pairs(want) do
        if not have[lower] and not IsSelf(name) then add[#add + 1] = name end
    end
    if removes then
        for lower, name in pairs(have) do
            if not want[lower] and not IsSelf(name) then remove[#remove + 1] = name end
        end
    end
    table.sort(add, NameLess)
    table.sort(remove, NameLess)
    return { add = add, remove = remove }
end

-- `current` = { instance = { [name] = true }, world = {...}, protected = { names } };
-- `incoming` = a Decode result; `mode` = "replace" or "merge". Returns
-- { instance = { add, remove }, world = {...}, protected = {...}, total = n }.
function Share.Diff(current, incoming, mode)
    current = type(current) == "table" and current or {}
    incoming = type(incoming) == "table" and incoming or {}
    local replace = mode == "replace"
    local changes = { total = 0 }
    for _, which in ipairs(LISTS) do
        changes[which] = DiffOne(Names(current[which]), Names(incoming[which]), replace)
    end
    if incoming.protected then
        changes.protected = DiffOne(Names(current.protected), Names(incoming.protected), replace)
    else
        changes.protected = { add = {}, remove = {} }
    end
    for _, section in ipairs(Share.SECTIONS) do
        changes.total = changes.total + #changes[section].add + #changes[section].remove
    end
    return changes
end

--------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------

-- Makes the changes from Diff through `profiles` (ns.Profiles in the addon). Removals go
-- first. Returns the number of changes the Profiles methods accepted.
function Share.Apply(changes, profiles)
    local applied = 0
    local function Count(ok) if ok then applied = applied + 1 end end
    for _, which in ipairs(LISTS) do
        local change = changes[which] or {}
        for _, name in ipairs(change.remove or {}) do Count(profiles:ListRemove(which, name)) end
        for _, name in ipairs(change.add or {}) do Count(profiles:ListAdd(which, name)) end
    end
    local change = changes.protected or {}
    for _, name in ipairs(change.remove or {}) do Count(profiles:Unprotect(name)) end
    for _, name in ipairs(change.add or {}) do Count(profiles:Protect(name)) end
    return applied
end
