-- Switch.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The only file that changes enable state. Snapshots this character's state, computes
-- the switch plan (profile + dependency cascade - protected addons), applies it, saves
-- and reloads; on exit, restores the snapshot exactly. Every entry point goes through
-- Inventory's safe-to-switch guard first. Filled in by v0.3.0 (#12, #13, #14, #15).

local _, ns = ...

local Switch = {}
ns.Switch = Switch

-- Whether this character is currently in M+ mode, i.e. has a snapshot pending restore.
-- Until v0.3.0 there is no way to enter it, so this is always false.
function Switch:IsActive()
    return false
end
