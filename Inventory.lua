-- Inventory.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- What is installed, and what this character has enabled. Read-only over C_AddOns:
-- enumerates addons (name, title, loadable/reason, load-on-demand, enable state for the
-- current character), builds the dependency graph (required deps and reverse
-- dependents), and answers the safe-to-switch question. Pure where it can be, so the
-- offline suite covers it. Filled in by v0.2.0 (#7, #8, #9, #10).

local _, ns = ...

local Inventory = {}
ns.Inventory = Inventory

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
