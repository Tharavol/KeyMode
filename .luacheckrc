std = "lua51"
max_line_length = 120

-- The luarocks CI action installs into .luarocks/ inside the workspace, so
-- `luacheck .` would otherwise lint the toolchain along with the addon.
exclude_files = {".luarocks/**", ".luarocks", "lua_modules/**", ".claude/**"}

-- WoW event handlers always receive (self, event, ...); ignore unused args
-- entirely since callbacks must match Blizzard's fixed signatures.
ignore = {
    "212", -- unused argument
}

globals = {
    -- SavedVariables declared in the .toc
    "KeyModeDB",

    -- Slash command registration
    "SLASH_KEYMODE1", "SLASH_KEYMODE2", "SlashCmdList",

    -- Addon Compartment callbacks named in the .toc; the client looks them up in _G
    "KeyMode_OnAddonCompartmentClick",
    "KeyMode_OnAddonCompartmentEnter",
    "KeyMode_OnAddonCompartmentLeave",

    -- Blizzard's list of frames Escape closes; the preview dialog adds itself (#17)
    "UISpecialFrames",
}

read_globals = {
    -- Namespaced API tables
    "C_AddOns", "Enum",

    -- Frame / UI globals
    "CreateFrame", "DEFAULT_CHAT_FRAME", "GameTooltip", "Settings", "UIParent",
    "Minimap", "GetCursorPosition",
    -- List editor (#18): scroll list API and the generic confirmation popup
    "CreateScrollBoxListLinearView", "ScrollUtil", "CreateDataProvider",
    "StaticPopup_ShowGenericConfirmation",
    -- Defined by minimap-reshaping addons, not the base client; always nil-checked
    "GetMinimapShape",

    -- Player and session state
    "InCombatLockdown", "ReloadUI", "UnitGUID", "UnitName", "UnitFullName", "time",
    -- Recovery reminder (#15); nil-checked
    "IsInInstance", "IsInGroup",

    -- Safe-to-switch guard inputs (#10), also probed by `/km debug probe scan` (#6);
    -- each is nil-checked, IsEncounterInProgress unverified on 12.x
    "C_ChallengeMode", "IsEncounterInProgress",

    -- Pre-C_AddOns fallback the version helper still branches on
    "GetAddOnMetadata",
}

-- The test harness deliberately writes WoW globals into its stub environment.
files["tests/"] = { globals = { "_G" }, ignore = { "111", "112", "113", "121", "122" } }
