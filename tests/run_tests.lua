-- run_tests.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Loads the addon into a stubbed WoW API (stub_api.lua) and runs the regression suite in
-- the sibling *_spec.lua files. Catches runtime shape errors luacheck cannot.
--
-- Usage: lua tests/run_tests.lua   (run from the repository root)

local T = dofile("tests/test_helpers.lua")
local stub = dofile("tests/stub_api.lua")

dofile("tests/stub_spec.lua")(stub, T)
dofile("tests/init_spec.lua")(stub, T)
dofile("tests/profiles_spec.lua")(stub, T)
dofile("tests/guard_spec.lua")(stub, T)
dofile("tests/options_spec.lua")(stub, T)
dofile("tests/commands_spec.lua")(stub, T)
dofile("tests/ui_spec.lua")(stub, T)
dofile("tests/minimap_spec.lua")(stub, T)
dofile("tests/probe_spec.lua")(stub, T)
dofile("tests/graph_spec.lua")(stub, T)
dofile("tests/plan_spec.lua")(stub, T)
dofile("tests/share_spec.lua")(stub, T)
dofile("tests/suggest_spec.lua")(stub, T)
dofile("tests/inventory_spec.lua")(stub, T)
dofile("tests/switch_spec.lua")(stub, T)
dofile("tests/editor_spec.lua")(stub, T)

os.exit(T.Summary() and 0 or 1)
