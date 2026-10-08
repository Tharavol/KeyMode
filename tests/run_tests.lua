-- run_tests.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Loads the addon into a stubbed WoW API (stub_api.lua) and runs the regression suite in
-- the sibling *_spec.lua files. Catches runtime shape errors luacheck cannot.
--
-- Usage: lua tests/run_tests.lua   (run from the repository root)

local T = dofile("tests/test_helpers.lua")
local stub = dofile("tests/stub_api.lua")

dofile("tests/init_spec.lua")(stub, T)

os.exit(T.Summary() and 0 or 1)
