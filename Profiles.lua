-- Profiles.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Named, account-wide profiles: which addons a profile turns off, the protect list, the
-- default profile, and import/export. Data only; never calls a mutating C_AddOns
-- function. Filled in by v0.3.0 (#11) and v0.4.0 (#19, #20, #21).

local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles
