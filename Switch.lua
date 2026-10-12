-- Switch.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The only file that changes enable state. Takes this character's baseline snapshot,
-- asks the switch plan (Plan.lua) what Instance mode, World mode or Off means against
-- it, applies that by GUID, saves and reloads. Off restores the baseline exactly and
-- ends management. Every entry point goes through Inventory's safe-to-switch guard
-- first. Filled in by v0.3.0 (#12, #14, #15).

local _, ns = ...

local Switch = {}
ns.Switch = Switch

Switch.MODES = { instance = "Instance", world = "World", off = "Off" }

--------------------------------------------------------------------------
-- Snapshot (#12)
--
-- ns.db.snapshots[guid] = { taken, mode, state }. `state` is the baseline: every
-- installed addon's enable state for this character, read by GUID the moment before
-- KeyMode first switched it. It is taken once and kept across Instance <-> World
-- switches; only Off, or a hand change folded in by the login check, touches it again.
--------------------------------------------------------------------------

local function Guid() return UnitGUID("player") end

function Switch:Snapshot()
    local snapshots = ns.db and ns.db.snapshots
    return snapshots and snapshots[Guid()] or nil
end

-- Whether KeyMode is managing this character, i.e. has a baseline pending restore.
function Switch:IsActive()
    return self:Snapshot() ~= nil
end

-- "instance", "world", or "off" when KeyMode is not managing this character.
function Switch:Mode()
    local snapshot = self:Snapshot()
    return snapshot and snapshot.mode or "off"
end

-- What a toggle switches to: Instance <-> World, and Instance from Off, the mode KeyMode
-- exists for.
function Switch:ToggleTarget()
    return self:Mode() == "instance" and "world" or "instance"
end

-- The mode for display: green while KeyMode is managing the character.
function Switch:ModeLabel()
    local mode = self:Mode()
    return mode == "off" and Switch.MODES.off or ("|cff00ff00" .. Switch.MODES[mode] .. "|r")
end

-- Records the baseline from `records` (Inventory:Scan()). Never overwrites one that is
-- pending restore: that would make the current, switched state the "original" and lose
-- the real one. Returns the snapshot, and false when one already existed.
function Switch:TakeBaseline(records)
    local existing = self:Snapshot()
    if existing then return existing, false end
    local state = {}
    for _, record in ipairs(records) do state[record.name] = record.enabled end
    local snapshot = { taken = time(), mode = "off", state = state }
    ns.db.snapshots[Guid()] = snapshot
    return snapshot, true
end

--------------------------------------------------------------------------
-- Enter and exit (#14)
--------------------------------------------------------------------------

-- The plan for `mode` against the current inventory, without changing anything. Also
-- returns the records it read, so a caller that goes on to apply it reads once.
function Switch:Preview(mode)
    local records, graph = ns.Inventory:Read()
    local snapshot = self:Snapshot()
    local plan = ns.Plan.Build({
        records = records,
        graph = graph,
        baseline = snapshot and snapshot.state or nil,
        mode = mode,
        lists = ns.Profiles:Lists(),
        isProtected = function(name) return ns.Profiles:IsProtected(name) end,
    })
    return plan, records
end

-- Switches to `mode` ("instance", "world" or "off"). On success with changes to make it
-- reloads the UI and does not return in practice; otherwise returns true and a message
-- (nothing to change) or false and a player-facing reason.
-- Whether a switch to `mode` may start now: a known mode, the guard (#10), and not the
-- mode already active. Returns true, or false and a player-facing reason. The preview
-- dialog asks before it opens, and Apply asks again on Confirm, since combat or a key
-- can start while the dialog is up.
function Switch:Check(mode)
    if not Switch.MODES[mode] then return false, "Unknown mode '" .. tostring(mode) .. "'." end
    local canSwitch, reason = ns.Inventory:CanSwitch()
    if not canSwitch then return false, "Cannot switch now: " .. reason .. "." end
    if mode == self:Mode() then
        return false, (mode == "off" and "KeyMode is not managing this character."
            or ("Already in " .. Switch.MODES[mode] .. " mode."))
    end
    return true
end

function Switch:Apply(mode)
    local ok, reason = self:Check(mode)
    if not ok then return false, reason end

    local plan, records = self:Preview(mode)
    local guid = Guid()
    if mode == "off" then
        ns.db.snapshots[guid] = nil
    else
        self:TakeBaseline(records).mode = mode
    end
    for _, entry in ipairs(plan.disable) do C_AddOns.DisableAddOn(entry.name, guid) end
    for _, entry in ipairs(plan.enable) do C_AddOns.EnableAddOn(entry.name, guid) end
    for _, name in ipairs(plan.removed) do
        ns.Print(name .. " was part of this character's setup but is no longer installed; skipped.")
    end

    if #plan.disable == 0 and #plan.enable == 0 then
        return true, Switch.MODES[mode] .. " mode: nothing to change, no reload needed."
    end
    -- Saved before the reload so the login check can confirm the switch took (#6:
    -- changes apply at the reload either way, but only a save survives ResetAddOns).
    ns.db.switched = ns.db.switched or {}
    ns.db.switched[guid] = mode
    C_AddOns.SaveAddOns()
    ReloadUI()
    return true
end

--------------------------------------------------------------------------
-- Login check (#14) and recovery (#15)
--
-- At every login and reload while managed, the actual enable state is compared with what
-- the current mode should produce. An addon that differs where the mode would have left
-- its baseline alone was changed by hand, in the game's AddOn list: the change is folded
-- into the baseline so Off does not undo it. An addon that differs where the mode turns
-- it off means the switch did not take, or the player turned a listed addon back on;
-- that is reported, not folded, and `/km <mode>` reapplies.
--------------------------------------------------------------------------

-- Returns two sorted lists: names folded into the baseline, and names the mode turns off
-- that are on anyway. Changes nothing when the character is not managed.
function Switch:Reconcile()
    local snapshot = self:Snapshot()
    if not snapshot then return {}, {} end
    local records = ns.Inventory:Scan()
    local plan = self:Preview(snapshot.mode)
    local folded, stray = {}, {}
    local lower = {}
    for name in pairs(snapshot.state) do lower[name:lower()] = name end
    for _, record in ipairs(records) do
        local key = lower[record.name:lower()]
        local target = plan.target[record.name]
        if key ~= nil and target ~= nil and record.enabled ~= target then
            if target == snapshot.state[key] then
                snapshot.state[key] = record.enabled
                folded[#folded + 1] = record.name
            else
                stray[#stray + 1] = record.name
            end
        end
    end
    table.sort(folded, function(a, b) return a:lower() < b:lower() end)
    table.sort(stray, function(a, b) return a:lower() < b:lower() end)
    return folded, stray
end

local function OnLogin()
    local guid = Guid()
    local switched = ns.db.switched and ns.db.switched[guid]
    if switched then
        ns.db.switched[guid] = nil
        if not next(ns.db.switched) then ns.db.switched = nil end
    end

    local mode = Switch:Mode()
    local folded, stray = Switch:Reconcile()
    if switched then ns.Print("Now in " .. Switch.MODES[switched] .. " mode.") end
    if #folded > 0 then
        ns.Print("Changed by hand since the last switch, kept on Off: " .. table.concat(folded, ", ") .. ".")
    end
    if #stray > 0 then
        ns.Print(Switch.MODES[mode] .. " mode turns these off, but they are on: " .. table.concat(stray, ", ")
            .. ". /km " .. mode .. " reapplies.")
    end

    -- Recovery (#15): Instance mode outside an instance and outside a group is usually a
    -- run that ended with a logout, crash or disconnect instead of the way back.
    if mode == "instance" then
        local inInstance = type(IsInInstance) == "function" and IsInInstance()
        local inGroup = type(IsInGroup) == "function" and IsInGroup()
        if not inInstance and not inGroup then
            ns.Print("Still in Instance mode. /km world or /km off switches back.")
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if ns.db then OnLogin() end
end)
