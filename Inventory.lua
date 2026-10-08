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
