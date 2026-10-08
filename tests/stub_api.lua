-- stub_api.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Stubs the slice of the WoW API the addon touches, then loads every file KeyMode.toc
-- lists, in TOC order, into a fresh environment per call so tests cannot leak state into
-- one another. Reading the TOC rather than hard-coding a file list keeps the loader
-- correct automatically as files are added or reordered.
--
-- Usage:
--   local stub = dofile("tests/stub_api.lua")
--   local env = stub.Load(function(env, fixtures) ... end)  -- configure before load
--   stub.Fire(env, "ADDON_LOADED", "KeyMode")

local M = {}

--------------------------------------------------------------------------
-- Widgets
--
-- One table type stands in for every frame, texture, font string and button. Methods
-- the tests inspect record their arguments; anything else answers with a no-op through
-- the metatable, so UI construction code at file scope runs without a method list that
-- has to grow every time a layout call is added.
--------------------------------------------------------------------------

local function NoOp() end

local WidgetMethods = {}
WidgetMethods.__index = function(_, key)
    local method = WidgetMethods[key]
    if method ~= nil then return method end
    return NoOp
end

function WidgetMethods:SetScript(scriptType, fn) self._scripts[scriptType] = fn end
function WidgetMethods:GetScript(scriptType) return self._scripts[scriptType] end
function WidgetMethods:HookScript(scriptType, fn)
    local previous = self._scripts[scriptType]
    self._scripts[scriptType] = function(...)
        if previous then previous(...) end
        fn(...)
    end
end
function WidgetMethods:RegisterEvent(event) self._events[event] = true end
function WidgetMethods:UnregisterEvent(event) self._events[event] = nil end
function WidgetMethods:IsEventRegistered(event) return self._events[event] or false end
function WidgetMethods:Show() self._shown = true end
function WidgetMethods:Hide() self._shown = false end
function WidgetMethods:IsShown() return self._shown and true or false end
function WidgetMethods:SetText(text) self._text = text end
function WidgetMethods:GetText() return self._text end
function WidgetMethods:SetChecked(checked) self._checked = checked and true or false end
function WidgetMethods:GetChecked() return self._checked or false end
function WidgetMethods:GetName() return self.name end
function WidgetMethods:GetParent() return self.parent end
function WidgetMethods:Click(button)
    local onClick = self._scripts.OnClick
    if onClick then onClick(self, button or "LeftButton") end
end

local function MakeWidget(env, kind, name, parent, template)
    local w = setmetatable({
        kind = kind, name = name, parent = parent, template = template,
        _scripts = {}, _events = {}, _children = {},
    }, WidgetMethods)
    w.CreateFontString = function(self, fsName)
        local fs = MakeWidget(env, "FontString", fsName, self)
        self._children[#self._children + 1] = fs
        return fs
    end
    w.CreateTexture = function(self, texName)
        local tex = MakeWidget(env, "Texture", texName, self)
        self._children[#self._children + 1] = tex
        return tex
    end
    -- Templates that carry a label expose it as `.Text` on the live client.
    if template == "UICheckButtonTemplate" then
        w.Text = MakeWidget(env, "FontString", nil, w)
    end
    if name then env[name] = w end
    return w
end

--------------------------------------------------------------------------
-- Installed-addon model
--
-- fixtures.addons is an ordered list, because the client addresses addons by index as
-- well as by name. Each entry:
--   { name, title, notes, deps = {...}, optionalDeps = {...}, loadOnDemand = bool,
--     loadable = bool, reason = string|nil, security = "INSECURE"|"SECURE",
--     enabledFor = { [characterKey] = bool }, loaded = bool }
--
-- `characterKey` is whatever string the caller passes as the `character` argument.
-- Blizzard's own UI passes UnitGUID("player") in AddonList.lua and UnitName("player")
-- in AddonCompartment.lua, and nil means "all characters". Which of those the live
-- client treats as equivalent is exactly what issue #6 verifies in-game; this model
-- treats every key as distinct and is to be corrected once that is known.
--------------------------------------------------------------------------

local ENABLE_STATE = { None = 0, Some = 1, All = 2 }

-- Adds one installed addon to fixtures. `opts.enabled` is shorthand for "enabled for
-- the default player" (both the GUID and the name, since the client uses both).
function M.AddAddon(fixtures, name, opts)
    opts = opts or {}
    local entry = {
        name = name,
        title = opts.title or name,
        notes = opts.notes,
        deps = opts.deps or {},
        optionalDeps = opts.optionalDeps or {},
        loadOnDemand = opts.loadOnDemand or false,
        loadable = opts.loadable ~= false,
        reason = opts.reason,
        security = opts.security or "INSECURE",
        enabledFor = opts.enabledFor or {},
        loaded = opts.loaded or false,
        metadata = opts.metadata or {},
    }
    if opts.enabled ~= false and opts.enabledFor == nil then
        entry.enabledFor[fixtures.player.guid] = true
        entry.enabledFor[fixtures.player.name] = true
    end
    fixtures.addons[#fixtures.addons + 1] = entry
    return entry
end

local function FindAddon(fixtures, nameOrIndex)
    if type(nameOrIndex) == "number" then
        return fixtures.addons[nameOrIndex], nameOrIndex
    end
    for index, entry in ipairs(fixtures.addons) do
        if entry.name == nameOrIndex then return entry, index end
    end
    return nil
end

local function KnownCharacters(fixtures)
    local seen = {}
    for _, entry in ipairs(fixtures.addons) do
        for key in pairs(entry.enabledFor) do seen[key] = true end
    end
    seen[fixtures.player.guid] = true
    seen[fixtures.player.name] = true
    return seen
end

local function MakeAddOnsApi(fixtures)
    local api = {}
    local calls = fixtures.calls

    function api.GetNumAddOns() return #fixtures.addons end

    function api.GetAddOnInfo(nameOrIndex)
        local entry = FindAddon(fixtures, nameOrIndex)
        if not entry then return nil end
        local reason = entry.reason
        if not reason and entry.loadOnDemand and not entry.loaded then reason = "DEMAND_LOADED" end
        return entry.name, entry.title, entry.notes, entry.loadable, reason, entry.security
    end

    function api.GetAddOnEnableState(nameOrIndex, character)
        local entry = FindAddon(fixtures, nameOrIndex)
        if not entry then return ENABLE_STATE.None end
        if character ~= nil then
            return entry.enabledFor[character] and ENABLE_STATE.All or ENABLE_STATE.None
        end
        local on, total = 0, 0
        for key in pairs(KnownCharacters(fixtures)) do
            total = total + 1
            if entry.enabledFor[key] then on = on + 1 end
        end
        if on == 0 then return ENABLE_STATE.None end
        return on == total and ENABLE_STATE.All or ENABLE_STATE.Some
    end

    local function SetEnabled(nameOrIndex, character, value)
        local entry = FindAddon(fixtures, nameOrIndex)
        if not entry then return end
        if character ~= nil then
            entry.enabledFor[character] = value or nil
        else
            for key in pairs(KnownCharacters(fixtures)) do entry.enabledFor[key] = value or nil end
        end
    end

    function api.EnableAddOn(nameOrIndex, character)
        calls[#calls + 1] = { "EnableAddOn", nameOrIndex, character }
        SetEnabled(nameOrIndex, character, true)
    end

    function api.DisableAddOn(nameOrIndex, character)
        calls[#calls + 1] = { "DisableAddOn", nameOrIndex, character }
        SetEnabled(nameOrIndex, character, false)
    end

    function api.GetAddOnDependencies(nameOrIndex)
        local entry = FindAddon(fixtures, nameOrIndex)
        if not entry then return end
        return unpack(entry.deps)
    end

    function api.GetAddOnOptionalDependencies(nameOrIndex)
        local entry = FindAddon(fixtures, nameOrIndex)
        if not entry then return end
        return unpack(entry.optionalDeps)
    end

    function api.IsAddOnLoadOnDemand(nameOrIndex)
        local entry = FindAddon(fixtures, nameOrIndex)
        return entry and entry.loadOnDemand or false
    end

    function api.IsAddOnLoaded(nameOrIndex)
        local entry = FindAddon(fixtures, nameOrIndex)
        return entry and entry.loaded or false
    end

    function api.GetAddOnMetadata(nameOrIndex, field)
        local entry = FindAddon(fixtures, nameOrIndex)
        return entry and entry.metadata[field]
    end

    function api.SaveAddOns() calls[#calls + 1] = { "SaveAddOns" } end
    function api.ResetAddOns() calls[#calls + 1] = { "ResetAddOns" } end

    return api
end

--------------------------------------------------------------------------
-- Fixtures and loader
--------------------------------------------------------------------------

local function MakeFixtures()
    local fixtures = {
        player = { guid = "Player-1234-0ABCDEF0", name = "Testchar" },
        addons = {},
        calls = {},          -- C_AddOns mutations, in order
        chat = {},           -- every line sent to DEFAULT_CHAT_FRAME
        settingsOpened = {}, -- category IDs passed to Settings.OpenToCategory
        reloads = 0,
        inCombat = false,
    }
    -- KeyMode itself is always installed, enabled and loaded.
    M.AddAddon(fixtures, "KeyMode", {
        title = "KeyMode", loaded = true,
        metadata = { Version = "@project-version@", Title = "KeyMode" },
    })
    return fixtures
end

local function TocFiles()
    local handle = assert(io.open("KeyMode.toc", "r"), "run from the repository root")
    local files = {}
    for line in handle:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    handle:close()
    return files
end
M.TocFiles = TocFiles

function M.Load(configure)
    local fixtures = MakeFixtures()
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.fixtures = fixtures
    env.frames = {}

    env.CreateFrame = function(kind, name, parent, template)
        local w = MakeWidget(env, kind, name, parent, template)
        env.frames[#env.frames + 1] = w
        return w
    end
    env.UIParent = MakeWidget(env, "Frame", "UIParent")
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text) fixtures.chat[#fixtures.chat + 1] = text end,
    }
    env.GameTooltip = MakeWidget(env, "GameTooltip", "GameTooltip")
    env.GameTooltip.AddLine = function(self, text)
        self._lines = self._lines or {}
        self._lines[#self._lines + 1] = text
    end
    env.GameTooltip.SetOwner = function(self) self._lines = {} end

    env.Enum = { AddOnEnableState = ENABLE_STATE }
    env.C_AddOns = MakeAddOnsApi(fixtures)
    env.UnitGUID = function(unit) return unit == "player" and fixtures.player.guid or nil end
    env.UnitName = function(unit) return unit == "player" and fixtures.player.name or nil end
    env.InCombatLockdown = function() return fixtures.inCombat end
    env.ReloadUI = function() fixtures.reloads = fixtures.reloads + 1 end

    env.SlashCmdList = {}
    env.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name)
            local category = { panel = panel, name = name, id = name .. "-category" }
            function category:GetID() return self.id end
            fixtures.category = category
            return category
        end,
        RegisterAddOnCategory = function(category) fixtures.registeredCategory = category end,
        OpenToCategory = function(id) fixtures.settingsOpened[#fixtures.settingsOpened + 1] = id end,
    }

    if configure then configure(env, fixtures) end

    local ns = {}
    for _, path in ipairs(TocFiles()) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        chunk("KeyMode", ns)
    end
    env.ns = ns
    return env
end

-- Delivers an event to every frame that registered for it, the way the client would.
function M.Fire(env, event, ...)
    for _, w in ipairs(env.frames) do
        if w._events[event] and w._scripts.OnEvent then
            w._scripts.OnEvent(w, event, ...)
        end
    end
end

-- Runs a slash command the way the chat box would: finds the SLASH_<KEY>n global that
-- matches `command`, then calls SlashCmdList[KEY] with the rest of the line.
function M.Slash(env, line)
    local command, rest = line:match("^(%S+)%s*(.-)$")
    for key, handler in pairs(env.SlashCmdList) do
        for i = 1, 9 do
            local alias = env["SLASH_" .. key .. i]
            if alias == nil then break end
            if alias:lower() == command:lower() then
                handler(rest)
                return true
            end
        end
    end
    return false
end

-- Loads the addon and fires ADDON_LOADED, the state every non-init spec starts from.
function M.Boot(configure)
    local env = M.Load(configure)
    M.Fire(env, "ADDON_LOADED", "KeyMode")
    return env
end

-- Chat output since the last call, with colour codes stripped, then cleared.
function M.TakeChat(env)
    local lines = {}
    for i, text in ipairs(env.fixtures.chat) do
        lines[i] = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    env.fixtures.chat = {}
    return lines
end

return M
