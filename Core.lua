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

-- CreateFrame raises immediately if a template doesn't resolve on the running client,
-- which would abort the rest of the calling file. Blizzard periodically retires UI
-- templates (Crosshairs #53), so every candidate is tried in order and an untemplated
-- frame is the last resort rather than an error. Returns the frame and the template
-- that resolved, or nil when none did. `name` is optional (a global frame name).
function ns.CreateFrameWithFallback(frameType, parent, templates, name)
    for _, template in ipairs(templates) do
        local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
        if ok and frame then return frame, template end
    end
    return CreateFrame(frameType, name, parent), nil
end

-- Schema version for KeyModeDB. Bump it, and add a migration, whenever the shape of a
-- saved table changes; never reinterpret an old shape in place.
ns.DB_VERSION = 3

ns.defaults = {
    dbVersion = ns.DB_VERSION,
    -- Account-wide: the two fixed addon sets (#37), each addon name -> true. Instance is
    -- what to turn off in Mythic Keystone dungeons and raids, World what to turn off the
    -- rest of the time (empty by default, so World mode is the baseline as it was).
    lists = {
        instance = {},
        world = {},
    },
    -- Keyed by UnitGUID("player"): { taken, mode, state = { [addonName] = enabled } }.
    -- `state` is the character's baseline, its own setup before KeyMode first switched
    -- it; `mode` is "instance" or "world". No entry means KeyMode is not managing that
    -- character. (#11, #12)
    snapshots = {},
    -- Account-wide: addon name -> true (protected) or false (a default the player
    -- removed). A removal is stored as false, never nil, because ApplyDefaults refills
    -- every nil key at login and would quietly put a removed default back. KeyMode itself
    -- is protected in code (Profiles.lua) and needs no entry here. (#9)
    protected = {
        ["!BugGrabber"] = true, -- the folder name has the "!"; "BugGrabber" never matched (#9)
        BugSack = true,
    },
    settings = {
        debug = false,
        minimapButton = true,  -- shown by default (#34)
        minimapAngle = 225,    -- degrees counter-clockwise from the minimap's right edge
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
-- the lists, the protect list and pending snapshots are the player's data, not settings,
-- and a reset that dropped a snapshot would strand a character in a mode with no way
-- back. Shared by `/km reset` and the options panel's button so the two cannot drift
-- apart.
function ns.ResetSettings()
    ns.db.settings = {}
    ApplyDefaults(ns.db.settings, ns.defaults.settings)
    ns.SettingsChanged()
end

-- Settings can change from the options panel, a slash command, a reset or a drag. Every
-- view that reflects a setting registers here once, and every writer calls
-- SettingsChanged afterwards, so no writer needs to know which views exist.
local settingsListeners = {}
function ns.OnSettingsChanged(fn)
    settingsListeners[#settingsListeners + 1] = fn
end
function ns.SettingsChanged()
    for _, fn in ipairs(settingsListeners) do fn() end
end

-- One function per schema version, each upgrading a DB from the version before it.
-- They run before ApplyDefaults, so a key a migration drops is not refilled first and a
-- key it reshapes is not shadowed by a fresh default.
local MIGRATIONS = {
    -- v0.1.0 and v0.2.0 shipped an always-empty `profiles` table, replaced by `lists`
    -- (#37). Nothing could fill it, so there is nothing to carry over.
    [2] = function(db) db.profiles = nil end,
    -- The default protect entry was "BugGrabber", but the addon's folder is "!BugGrabber",
    -- so it never matched (found in the v0.4.0 in-game check). The saved entry moves to
    -- the real name, keeping its value: a removed default stays removed (false).
    [3] = function(db)
        local protected = db.protected
        if type(protected) ~= "table" or protected.BugGrabber == nil then return end
        if protected["!BugGrabber"] == nil then protected["!BugGrabber"] = protected.BugGrabber end
        protected.BugGrabber = nil
    end,
}

-- Brings a saved DB up to DB_VERSION. An empty table is a first login with nothing to
-- upgrade. A populated one without dbVersion is treated as version 1, the oldest shape.
-- A DB from a newer KeyMode keeps its version: it is never downgraded.
local function Migrate(db)
    if next(db) == nil then return end
    local version = tonumber(db.dbVersion) or 1
    for target = version + 1, ns.DB_VERSION do
        if MIGRATIONS[target] then MIGRATIONS[target](db) end
    end
    db.dbVersion = math.max(version, ns.DB_VERSION)
end
ns.Migrate = Migrate

-- Work that needs ns.db (anything reading a saved setting at startup) registers here and
-- runs once, at this addon's ADDON_LOADED, in registration (= TOC) order.
local loadedListeners = {}
function ns.OnLoaded(fn)
    loadedListeners[#loadedListeners + 1] = fn
end

local frame = CreateFrame("Frame")
ns.eventFrame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        KeyModeDB = KeyModeDB or {}
        Migrate(KeyModeDB)
        ApplyDefaults(KeyModeDB, ns.defaults)
        ns.db = KeyModeDB
        self:UnregisterEvent("ADDON_LOADED")
        for _, fn in ipairs(loadedListeners) do fn() end
    end
end)
