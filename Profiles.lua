-- Profiles.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The account-wide addon data: the Instance and World lists (#37), the protect list, and
-- (v0.4.0) import/export and suggested lists. Data only; never calls a mutating C_AddOns
-- function. Filled in by v0.2.0 (#9), v0.3.0 (#11, #16) and v0.4.0 (#19, #20, #21).
-- The file keeps its v0.1.0 name; "profiles" here means the two fixed lists.

local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

--------------------------------------------------------------------------
-- Protect list (#9)
--
-- A protected addon is skipped by every profile: no switch plan may disable it. KeyMode
-- itself is protected here in code, whatever the saved data says, because disabling it
-- would leave no way back. Everything else lives in ns.db.protected as
-- name -> true | false, where false records a default the player removed (see the
-- comment on ns.defaults.protected for why it is not nil).
--
-- Names match case-insensitively: addon folder names are case-insensitive on Windows, so
-- "bugsack" and "BugSack" are the same addon. The saved spelling is kept for display.
--------------------------------------------------------------------------

local function SavedList()
    local list = ns.db and ns.db.protected
    return type(list) == "table" and list or nil
end

local function IsSelf(name)
    return name:lower() == ns.ADDON_NAME:lower()
end

-- Every saved key that names `name`, in any case. Normally zero or one; more only if a
-- hand-edited SavedVariables file holds two spellings of the same addon.
local function SavedKeys(name)
    local keys, wanted = {}, name:lower()
    local list = SavedList()
    if list then
        for key in pairs(list) do
            if type(key) == "string" and key:lower() == wanted then keys[#keys + 1] = key end
        end
    end
    return keys
end

-- Trims surrounding whitespace; returns nil for anything that cannot be an addon name.
local function Clean(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end

function Profiles:IsProtected(name)
    name = Clean(name)
    if not name then return false end
    if IsSelf(name) then return true end
    local list = SavedList()
    for _, key in ipairs(SavedKeys(name)) do
        if list[key] == true then return true end
    end
    return false
end

-- Every protected addon, KeyMode included, sorted case-insensitively for display.
function Profiles:ProtectedList()
    local names = { ns.ADDON_NAME }
    local list = SavedList()
    if list then
        for key, value in pairs(list) do
            if value == true and type(key) == "string" and not IsSelf(key) then
                names[#names + 1] = key
            end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- Adds `name` to the protect list. Returns true, or false and a player-facing reason.
-- Protecting an addon that already is one succeeds and changes nothing.
function Profiles:Protect(name)
    name = Clean(name)
    if not name then return false, "No addon name given." end
    if IsSelf(name) then return true end
    local list = SavedList()
    if not list then return false, "Saved data is not loaded yet." end
    -- Re-protecting a removed default flips its existing entry back rather than adding a
    -- second spelling beside it.
    local keys = SavedKeys(name)
    if #keys == 0 then keys[1] = name end
    for _, key in ipairs(keys) do list[key] = true end
    return true
end

-- Removes `name` from the protect list. Returns true, or false and a player-facing
-- reason. KeyMode itself can never be removed.
function Profiles:Unprotect(name)
    name = Clean(name)
    if not name then return false, "No addon name given." end
    if IsSelf(name) then return false, ns.ADDON_NAME .. " is always protected." end
    if not self:IsProtected(name) then return false, name .. " is not protected." end
    -- false, not nil: see ns.defaults.protected.
    local list = SavedList()
    for _, key in ipairs(SavedKeys(name)) do list[key] = false end
    return true
end

--------------------------------------------------------------------------
-- Instance and World lists (#11, #37)
--
-- ns.db.lists.instance and ns.db.lists.world, each addon name -> true. Account-wide, so
-- a name may be an addon this character does not have installed; the switch plan (#13)
-- ignores those and reports them. Matching is case-insensitive like the protect list.
-- A removal deletes the key: the lists have no defaults for ApplyDefaults to refill.
--------------------------------------------------------------------------

Profiles.LISTS = { "instance", "world" }

local function List(which)
    local lists = ns.db and ns.db.lists
    local list = type(lists) == "table" and lists[which]
    return type(list) == "table" and list or nil
end

local function ListKeys(list, name)
    local keys, wanted = {}, name:lower()
    for key in pairs(list) do
        if type(key) == "string" and key:lower() == wanted then keys[#keys + 1] = key end
    end
    return keys
end

function Profiles:IsList(which)
    return which == "instance" or which == "world"
end

-- The names on one list, sorted case-insensitively for display. Empty for an unknown list.
function Profiles:ListNames(which)
    local names = {}
    local list = List(which)
    if list then
        for key, value in pairs(list) do
            if value and type(key) == "string" then names[#names + 1] = key end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function Profiles:InList(which, name)
    name = Clean(name)
    local list = List(which)
    return name and list and #ListKeys(list, name) > 0 or false
end

-- Adds `name` to a list. Returns true, or false and a player-facing reason. Adding a name
-- already on the list, in any case, succeeds and keeps the spelling already saved.
function Profiles:ListAdd(which, name)
    name = Clean(name)
    if not name then return false, "No addon name given." end
    if IsSelf(name) then return false, ns.ADDON_NAME .. " is always protected." end
    local list = List(which)
    if not list then return false, "Saved data is not loaded yet." end
    if #ListKeys(list, name) == 0 then list[name] = true end
    return true
end

-- Removes `name` from a list. Returns true, or false and a player-facing reason.
function Profiles:ListRemove(which, name)
    name = Clean(name)
    if not name then return false, "No addon name given." end
    local list = List(which)
    if not list then return false, "Saved data is not loaded yet." end
    local keys = ListKeys(list, name)
    if #keys == 0 then return false, name .. " is not on the " .. which .. " list." end
    for _, key in ipairs(keys) do list[key] = nil end
    return true
end

-- Both lists as plain sets, the shape the switch plan takes.
function Profiles:Lists()
    return { instance = List("instance") or {}, world = List("world") or {} }
end
