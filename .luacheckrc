std = "lua51"
max_line_length = 120

-- The luarocks CI action installs into .luarocks/ inside the workspace, so
-- `luacheck .` would otherwise lint the toolchain along with the addon.
exclude_files = {".luarocks/**", ".luarocks", "lua_modules/**"}

-- WoW event handlers always receive (self, event, ...); ignore unused args
-- entirely since callbacks must match Blizzard's fixed signatures.
ignore = {
    "212", -- unused argument
}

globals = {
    -- SavedVariables declared in the .toc
    "KeyModeDB",
}

read_globals = {
    -- Namespaced API tables
    "C_AddOns",

    -- Frame / UI globals
    "CreateFrame", "DEFAULT_CHAT_FRAME",

    -- Pre-C_AddOns fallback the version helper still branches on
    "GetAddOnMetadata",
}

-- The test harness deliberately writes WoW globals into its stub environment.
files["tests/"] = { globals = { "_G" }, ignore = { "111", "112", "113", "121", "122" } }
