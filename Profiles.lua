-- Profiles.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Named, account-wide profiles: which addons a profile turns off, the protect list, the
-- default profile, and import/export. Data only; never calls a mutating C_AddOns
-- function. Filled in by v0.2.0 (#9), v0.3.0 (#11) and v0.4.0 (#19, #20, #21).

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
