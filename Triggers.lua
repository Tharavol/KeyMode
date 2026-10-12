-- Triggers.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Watches for the moments a switch is worth offering -- entering a Mythic dungeon or a
-- raid, joining a keystone or raid group, leaving afterwards -- and opens the preview dialog. Never
-- switches on its own. Filled in by v0.5.0 (#22, #23, #24, #25).

local _, ns = ...

local Triggers = {}
ns.Triggers = Triggers
