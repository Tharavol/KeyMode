-- Core.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- KeyMode - switch to a lean addon set for Mythic+ and back again.
-- Copyright (C) 2026 Tharavol
--
-- This program is free software: you can redistribute it and/or modify it under the
-- terms of the GNU General Public License as published by the Free Software Foundation,
-- either version 3 of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
-- PARTICULAR PURPOSE. See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with this
-- program. If not, see <https://www.gnu.org/licenses/>.
--
-- Loads first. Owns the shared namespace, chat output, version reporting and the
-- SavedVariables lifecycle. Every other file repeats `local ADDON_NAME, ns = ...`;
-- WoW hands the same `ns` table to each file the TOC lists, which is how state crosses
-- files without adding globals.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

-- Every chat line goes through here (S10 of the cross-addon slash command standard),
-- so output carries one coloured, greppable prefix instead of one retyped per call site.
local PREFIX = "|cffffd200KeyMode|r: "
function ns.Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

-- Diagnostic output, shown only while debug mode is on (`/km debug`).
function ns.Debug(...)
    if ns.db and ns.db.settings.debug then
        ns.Print("|cff999999[debug]|r", ...)
    end
end

-- Returns a display-ready version string with exactly one leading "v". The packager
-- substitutes `@project-version@` with the release tag, which already carries a "v";
-- an unbuilt git clone leaves the token as-is, which is reported as "dev".
function ns.GetAddonVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMeta and getMeta(ADDON_NAME, "Version")
    if type(version) ~= "string" or version == "" or version:match("^@.*@$") then
        return "dev"
    end
    if not version:match("^[vV]") then
        version = "v" .. version
    end
    return version
end

-- Schema version for KeyModeDB. Bump it, and add a migration, whenever the shape of a
-- saved table changes; never reinterpret an old shape in place.
ns.DB_VERSION = 1

ns.defaults = {
    dbVersion = ns.DB_VERSION,
    -- Account-wide: profile name -> { disable = { [addonName] = true } }. (v0.3.0)
    profiles = {},
    -- Keyed by UnitGUID("player"): the pre-switch enable state to restore. (v0.3.0)
    snapshots = {},
    settings = {
        debug = false,
    },
}

-- Fills in any key missing from `target` with a deep copy of the default, without
-- overwriting what the player already has.
local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                ApplyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
end
ns.ApplyDefaults = ApplyDefaults

-- Restores `settings` to defaults, and nothing else (S9 of the slash command standard):
-- profiles and pending snapshots are the player's data, not settings, and a reset that
-- dropped a snapshot would strand a character in M+ mode with no way back. Shared by
-- `/km reset` and the options panel's button so the two cannot drift apart.
function ns.ResetSettings()
    ns.db.settings = {}
    ApplyDefaults(ns.db.settings, ns.defaults.settings)
end

local frame = CreateFrame("Frame")
ns.eventFrame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        KeyModeDB = KeyModeDB or {}
        ApplyDefaults(KeyModeDB, ns.defaults)
        ns.db = KeyModeDB
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
