std = "lua51"
max_line_length = 120

-- The luarocks CI action installs into .luarocks/ inside the workspace, so
-- `luacheck .` would otherwise lint the toolchain along with the addon.
exclude_files = {".luarocks/**", ".luarocks", "lua_modules/**", ".claude/**"}

-- Methods take an implicit `self` whether they use it or not. Every other unused
-- argument is flagged: callbacks with a fixed signature name the ones they skip `_`.
ignore = {
    "212/self", -- unused implicit self
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

    -- Key binding (#26): Bindings.xml calls KeyMode_Toggle by name; the Key Bindings page
    -- reads the header and binding names from these globals
    "KeyMode_Toggle", "BINDING_HEADER_KEYMODE", "BINDING_NAME_KEYMODE_TOGGLE",
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
    -- Suggested lists (#21): the player's region picks the Raider.IO database to keep; nil-checked
    "GetCurrentRegion",
    -- Switch prompts (#22, #23, #24); nil-checked, and the C_LFGList calls are pcall'd
    "GetInstanceInfo", "C_LFGList",

    -- Safe-to-switch guard inputs (#10), also probed by `/km debug probe scan` (#6);
    -- each is nil-checked, IsEncounterInProgress unverified on 12.x
    "C_ChallengeMode", "IsEncounterInProgress",

    -- Pre-C_AddOns fallback the version helper still branches on
    "GetAddOnMetadata",
}

-- The test harness deliberately writes WoW globals into its stub environment.
files["tests/"] = { globals = { "_G" }, ignore = { "111", "112", "113", "121", "122" } }
