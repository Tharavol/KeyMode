-- Commands.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Slash commands /keymode and /km. Loads last, so every module above is available to
-- the handlers. Conforms to the cross-addon slash command standard (S1-S13): a table of
-- { name, help, handler } drives both dispatch and the help text, so the two cannot
-- drift apart. Parsing and dispatch follow ShoppingConverter/Commands.lua.

local ADDON_NAME, ns = ...

local Commands = {}
ns.Commands = Commands

local function Cmd(text) return "|cffffff00" .. text .. "|r" end
local function OnOff(value) return value and "|cff00ff00on|r" or "|cffff0000off|r" end

local function OpenPanel() ns.Options:Open() end

-- Mode commands are registered now so `help` shows the whole surface, but the switch
-- engine lands in v0.3.0. Saying so beats an "Unknown command" for a documented word.
local function NotYet() ns.Print("Switching is not available yet; it arrives with the switch engine (v0.3.0).") end

-- Sets a boolean setting from "on"/"off", or toggles it when bare (S8), and always reports
-- the resulting state. Anything else is rejected rather than read as "off" (S12).
local function Toggle(key, value, label)
    if value == "on" then
        ns.db.settings[key] = true
    elseif value == "off" then
        ns.db.settings[key] = false
    elseif value == "" then
        ns.db.settings[key] = not ns.db.settings[key]
    else
        ns.Print("'" .. value .. "' - expected 'on' or 'off'.")
        return
    end
    ns.Options:Refresh()
    ns.Print(label .. " is " .. OnOff(ns.db.settings[key]) .. ".")
end

local function CountKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Forward-declared so the "help" entry can close over it before COMMANDS exists.
local PrintUsage

-- "", "config" and "gui" are silent aliases of "options" (S5): each opens the panel but
-- carries no help line of its own, so the help doesn't repeat one line four times.
local COMMANDS = {
    { name = "", help = {}, handler = OpenPanel },
    {
        name = "options",
        help = { Cmd("/km") .. ", " .. Cmd("/km options") .. ", " .. Cmd("config") .. ", "
            .. Cmd("gui") .. " - open the options panel" },
        handler = OpenPanel,
    },
    { name = "config", help = {}, handler = OpenPanel },
    { name = "gui", help = {}, handler = OpenPanel },
    {
        name = "on",
        help = { Cmd("/km on [profile]") .. " - switch to M+ mode (preview first)" },
        handler = NotYet,
    },
    {
        name = "off",
        help = { Cmd("/km off") .. " - restore the addons this character had before" },
        handler = NotYet,
    },
    {
        name = "toggle",
        help = { Cmd("/km toggle") .. " - switch to whichever mode is not active" },
        handler = NotYet,
    },
    {
        name = "preview",
        help = { Cmd("/km preview [profile]") .. " - list what a switch would change, without reloading" },
        handler = NotYet,
    },
    {
        name = "status",
        help = { Cmd("/km status") .. " - show the current mode and settings" },
        handler = function()
            ns.Print(ADDON_NAME .. " " .. ns.GetAddonVersion() .. " status:")
            ns.Print("  Mode: " .. (ns.Switch:IsActive() and "Mythic+" or "Normal"))
            ns.Print("  Profiles: " .. CountKeys(ns.db.profiles))
            for _, definition in ipairs(ns.Options.CHECKBOXES) do
                ns.Print("  " .. definition.label .. ": " .. OnOff(ns.db.settings[definition.key]))
            end
        end,
    },
    {
        name = "version",
        help = { Cmd("/km version") .. " - show the addon version" },
        handler = function() ns.Print(ADDON_NAME .. " " .. ns.GetAddonVersion()) end,
    },
    {
        name = "reset",
        help = { Cmd("/km reset") .. " - restore settings to defaults (profiles are kept)" },
        handler = function()
            ns.ResetSettings()
            ns.Options:Refresh()
            ns.Print("Settings restored to defaults.")
        end,
    },
    {
        name = "debug",
        help = { Cmd("/km debug [on|off]") .. " - toggle or set debug messages" },
        handler = function(_, rest) Toggle("debug", rest, "Debug messages") end,
    },
    {
        name = "help",
        help = { Cmd("/km help") .. " - show this list" },
        handler = function() PrintUsage() end,
    },
}
Commands.COMMANDS = COMMANDS

PrintUsage = function()
    ns.Print(ADDON_NAME .. " " .. ns.GetAddonVersion() .. " commands (" .. Cmd("/keymode")
        .. " or " .. Cmd("/km") .. "):")
    for _, command in ipairs(COMMANDS) do
        for _, line in ipairs(command.help) do
            ns.Print("  " .. line)
        end
    end
end

-- `command` and `rest` are lowercased for matching; `argument` keeps the case the player
-- typed, since profile names are case sensitive (S11).
local function Parse(input)
    local command, argument = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    return command:lower(), argument, argument:lower()
end
Commands.Parse = Parse

function Commands:Dispatch(input)
    local command, argument, rest = Parse(input)
    for _, entry in ipairs(COMMANDS) do
        if entry.name == command then
            entry.handler(argument, rest)
            return
        end
    end
    -- A typo must be visibly a typo, never a silent fallback (S4).
    ns.Print("Unknown command: " .. command)
    PrintUsage()
end

SLASH_KEYMODE1 = "/keymode"
SLASH_KEYMODE2 = "/km"
SlashCmdList.KEYMODE = function(message) Commands:Dispatch(message) end
