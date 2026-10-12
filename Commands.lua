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

local function Joined(names) return table.concat(names, ", ") end

-- Every switch goes through the preview dialog (#17), which switches only on Confirm.
local function SwitchTo(mode) ns.UI:Preview(mode) end

-- `/km preview [instance|world|off]`: the plan as text, changing nothing. Bare previews
-- what `/km toggle` would do.
local function Preview(rest)
    local mode = rest ~= "" and rest or ns.Switch:ToggleTarget()
    if not ns.Switch.MODES[mode] then
        ns.Print("'" .. rest .. "' - expected 'instance', 'world' or 'off'.")
        return
    end
    local plan = ns.Switch:Preview(mode)
    ns.Print("Preview of " .. ns.Switch.MODES[mode] .. " mode (now " .. ns.Switch.MODES[ns.Switch:Mode()] .. "):")
    if #plan.disable == 0 and #plan.enable == 0 then ns.Print("  Nothing to change.") end
    -- Cascade entries are marked apart: they are off only because something they
    -- require is, which is the line a player reading the preview most needs explained.
    local direct, cascade = {}, {}
    for _, entry in ipairs(plan.disable) do
        local bucket = entry.reason == "cascade" and cascade or direct
        bucket[#bucket + 1] = entry.name
    end
    if #plan.disable > 0 then
        local parts = {}
        if #direct > 0 then parts[#parts + 1] = Joined(direct) end
        if #cascade > 0 then parts[#parts + 1] = "because they require one of those: " .. Joined(cascade) end
        ns.Print("  Turns off (" .. #plan.disable .. "): " .. table.concat(parts, "; "))
    end
    if #plan.enable > 0 then
        local names = {}
        for _, entry in ipairs(plan.enable) do names[#names + 1] = entry.name end
        ns.Print("  Turns on (" .. #plan.enable .. "): " .. Joined(names))
    end
    if #plan.kept > 0 then ns.Print("  Kept on, protected or needed by a protected addon: " .. Joined(plan.kept)) end
    if #plan.unknown > 0 then ns.Print("  On the list but not installed here: " .. Joined(plan.unknown)) end
    if #plan.removed > 0 then ns.Print("  No longer installed, skipped: " .. Joined(plan.removed)) end
end

-- Splits "add Some Addon" into ("add", "Some Addon"), keeping the name's case.
local function Verb(argument)
    local verb, name = argument:match("^(%S*)%s*(.-)$")
    return verb:lower(), name
end

local function Installed(name)
    for index = 1, C_AddOns.GetNumAddOns() do
        local folder = C_AddOns.GetAddOnInfo(index)
        if folder and folder:lower() == name:lower() then return true end
    end
    return false
end

-- Prints the outcome of an add or remove, warning (not refusing) about a name that is
-- not installed: the lists are account-wide, so it may be installed on another character.
local function Report(ok, err, done, name)
    if not ok then
        ns.Print(err)
        return
    end
    ns.Print(done)
    if not Installed(name) then ns.Print("  (" .. name .. " is not installed on this character.)") end
end

-- `/km list instance|world [add|remove <addon>]`.
local function ListCommand(argument)
    local which, rest = argument:match("^(%S*)%s*(.-)$")
    which = which:lower()
    if not ns.Profiles:IsList(which) then
        for _, name in ipairs(ns.Profiles.LISTS) do
            local names = ns.Profiles:ListNames(name)
            ns.Print(ns.Switch.MODES[name] .. " list (" .. #names .. "): " .. (#names > 0 and Joined(names) or "empty"))
        end
        if which ~= "" then ns.Print("'" .. which .. "' - expected 'instance' or 'world'.") end
        return
    end
    local label = ns.Switch.MODES[which] .. " list"
    local verb, name = Verb(rest)
    if verb == "" then
        local names = ns.Profiles:ListNames(which)
        ns.Print(label .. " (" .. #names .. "): " .. (#names > 0 and Joined(names) or "empty"))
    elseif verb == "add" then
        local ok, err = ns.Profiles:ListAdd(which, name)
        Report(ok, err, name .. " added to the " .. label .. ".", name)
    elseif verb == "remove" then
        local ok, err = ns.Profiles:ListRemove(which, name)
        Report(ok, err, name .. " removed from the " .. label .. ".", name)
    elseif verb == "clear" then
        ns.Print(ns.Editor:Clear(which) .. " removed from the " .. label .. ".")
    elseif verb == "copy" then
        local from = name:lower()
        if not ns.Profiles:IsList(from) or from == which then
            ns.Print("'" .. name .. "' - expected the other list's name.")
            return
        end
        ns.Print(ns.Editor:Copy(from, which) .. " added to the " .. label .. " from the "
            .. ns.Switch.MODES[from] .. " list.")
    else
        ns.Print("'" .. verb .. "' - expected 'add', 'remove', 'clear' or 'copy'.")
    end
    if ns.Editor.page and ns.Editor.page:IsShown() then ns.Editor:Refresh() end
end

-- `/km protect [add|remove <addon>]`.
local function ProtectCommand(argument)
    local verb, name = Verb(argument)
    if verb == "" then
        ns.Print("Protected: " .. Joined(ns.Profiles:ProtectedList()))
    elseif verb == "add" then
        local ok, err = ns.Profiles:Protect(name)
        Report(ok, err, name .. " is protected.", name)
    elseif verb == "remove" then
        local ok, err = ns.Profiles:Unprotect(name)
        Report(ok, err, name .. " is no longer protected.", name)
    else
        ns.Print("'" .. verb .. "' - expected 'add' or 'remove'.")
    end
end

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
    ns.SettingsChanged()
    ns.Print(label .. " is " .. OnOff(ns.db.settings[key]) .. ".")
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
        name = "instance",
        help = { Cmd("/km instance") .. " - preview turning off the Instance list, then confirm" },
        handler = function() SwitchTo("instance") end,
    },
    {
        name = "world",
        help = { Cmd("/km world") .. " - preview turning off the World list, then confirm" },
        handler = function() SwitchTo("world") end,
    },
    {
        name = "off",
        help = { Cmd("/km off") .. " - restore this character's own setup and stop managing it" },
        handler = function() SwitchTo("off") end,
    },
    {
        name = "toggle",
        help = { Cmd("/km toggle") .. " - switch between Instance and World mode" },
        handler = function() SwitchTo(ns.Switch:ToggleTarget()) end,
    },
    {
        name = "preview",
        help = { Cmd("/km preview [instance|world|off]") .. " - list what a switch would change, without reloading" },
        handler = function(_, rest) Preview(rest) end,
    },
    {
        name = "list",
        help = { Cmd("/km list [instance|world] [add|remove <addon>|clear|copy <other>]") .. " - show or edit a list" },
        handler = function(argument) ListCommand(argument) end,
    },
    {
        name = "protect",
        help = { Cmd("/km protect [add|remove <addon>]") .. " - show or edit the addons no switch turns off" },
        handler = function(argument) ProtectCommand(argument) end,
    },
    {
        name = "status",
        help = { Cmd("/km status") .. " - show the current mode and settings" },
        handler = function()
            ns.Print(ADDON_NAME .. " " .. ns.GetAddonVersion() .. " status:")
            ns.Print("  Mode: " .. ns.Switch.MODES[ns.Switch:Mode()])
            ns.Print("  Lists: Instance " .. #ns.Profiles:ListNames("instance") .. ", World "
                .. #ns.Profiles:ListNames("world"))
            ns.Print("  Protected: " .. Joined(ns.Profiles:ProtectedList()))
            local canSwitch, reason = ns.Inventory:CanSwitch()
            ns.Print("  Switch allowed: " .. (canSwitch and "yes" or ("no (" .. reason .. ")")))
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
        help = { Cmd("/km reset") .. " - restore settings to defaults (lists, protect list and mode are kept)" },
        handler = function()
            ns.ResetSettings()
            ns.Print("Settings restored to defaults.")
        end,
    },
    {
        name = "minimap",
        help = { Cmd("/km minimap [on|off]") .. " - toggle or set the minimap button" },
        handler = function(_, rest) Toggle("minimapButton", rest, "Minimap button") end,
    },
    {
        name = "debug",
        help = {
            Cmd("/km debug [on|off]") .. " - toggle or set debug messages",
            Cmd("/km debug probe [scan|inventory|categories|enable|disable|save|reset|clear]")
                .. " - addon API diagnostics (see docs/HANDOFF.md)",
        },
        handler = function(argument, rest)
            local word, probeArgs = argument:match("^(%S+)%s*(.-)$")
            if word and word:lower() == "probe" then
                ns.Probe:Run(probeArgs)
                return
            end
            Toggle("debug", rest, "Debug messages")
        end,
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
-- typed, so an addon name is saved and shown the way it was written (S11).
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
