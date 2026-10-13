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

-- Child-region fields a template creates (`checkbox.Text`). Without the template they
-- don't exist on the live client either, so the catch-all must not invent them.
local TEMPLATE_FIELDS = { Text = true, TitleText = true, CloseButton = true, EditBox = true }

local WidgetMethods = {}
WidgetMethods.__index = function(_, key)
    local method = WidgetMethods[key]
    if method ~= nil then return method end
    if TEMPLATE_FIELDS[key] then return nil end
    -- A widget's own state (`_text`, `_shown`, ...) is unset until a method writes it; it
    -- must read as nil, not as the catch-all method, or an unshown frame reads as shown.
    if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
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
function WidgetMethods:SetSize(width, height) self._width, self._height = width, height end
function WidgetMethods:GetSize() return self._width, self._height end
function WidgetMethods:GetWidth() return self._width end
function WidgetMethods:GetHeight() return self._height end
function WidgetMethods:SetPoint(...) self._point = { ... } end
function WidgetMethods:ClearAllPoints() self._point = nil end
function WidgetMethods:GetPoint() if self._point then return unpack(self._point) end end
function WidgetMethods:HasScript() return true end
function WidgetMethods:IsProtected() return false end
function WidgetMethods:GetObjectType() return self.kind end
function WidgetMethods:SetTexture(texture) self._texture = texture end
function WidgetMethods:GetTexture() return self._texture end
function WidgetMethods:GetParent() return self.parent end
function WidgetMethods:SetDataProvider(provider) self._dataProvider = provider end
function WidgetMethods:Enable() self._disabled = false end
function WidgetMethods:Disable() self._disabled = true end
function WidgetMethods:IsEnabled() return not self._disabled end
function WidgetMethods:SetAlpha(alpha) self._alpha = alpha end
function WidgetMethods:GetAlpha() return self._alpha or 1 end
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
    if template == "InputScrollFrameTemplate" then
        w.EditBox = MakeWidget(env, "EditBox", nil, w)
    end
    if template == "BasicFrameTemplateWithInset" then
        w.TitleText = MakeWidget(env, "FontString", nil, w)
        w.CloseButton = MakeWidget(env, "Button", nil, w)
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
-- `characterKey` is a character's GUID. The `character` argument resolves the way the
-- live client was seen to resolve it (#6, docs/HANDOFF.md "API facts"):
--   UnitGUID("player") or UnitName("player")  -> this character (the two are aliases)
--   nil or "0"                                -> every known character: a query
--                                                aggregates to None/Some/All, a
--                                                mutation applies to all of them
--   anything else (e.g. "Name-Realm")         -> not a character: a query answers All,
--                                                a mutation does nothing
-- "Known" means having an entry for the addon, which is why a brand-new addon's "all"
-- query reflects only the characters that have one.
--------------------------------------------------------------------------

local ENABLE_STATE = { None = 0, Some = 1, All = 2 }

-- Adds one installed addon to fixtures. `opts.enabled` is shorthand for "enabled for
-- the default player".
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
    return seen
end

-- A character GUID, "all" for nil and "0", or nil for a key the client ignores.
local function ResolveCharacter(fixtures, character)
    if character == nil or character == "0" then return "all" end
    if character == fixtures.player.guid or character == fixtures.player.name then
        return fixtures.player.guid
    end
    if type(character) == "string" and character:match("^Player%-") then return character end
    return nil
end

local function MakeAddOnsApi(fixtures)
    local api = {}
    local calls = fixtures.calls

    function api.GetNumAddOns() return #fixtures.addons end

    function api.GetAddOnInfo(nameOrIndex)
        local entry = FindAddon(fixtures, nameOrIndex)
        if not entry then return nil end
        -- The live client answers "" (not nil) for an addon with nothing to report.
        local reason = entry.reason
        if not reason and not entry.enabledFor[fixtures.player.guid] then reason = "DISABLED" end
        if not reason and entry.loadOnDemand and not entry.loaded then reason = "DEMAND_LOADED" end
        return entry.name, entry.title, entry.notes, entry.loadable, reason or "", entry.security
    end

    function api.GetAddOnEnableState(nameOrIndex, character)
        local entry = FindAddon(fixtures, nameOrIndex)
        if not entry then return ENABLE_STATE.None end
        local who = ResolveCharacter(fixtures, character)
        if who == nil then return ENABLE_STATE.All end
        if who ~= "all" then
            return entry.enabledFor[who] and ENABLE_STATE.All or ENABLE_STATE.None
        end
        local on, total = 0, 0
        for key in pairs(entry.enabledFor) do
            total = total + 1
            if entry.enabledFor[key] then on = on + 1 end
        end
        if on == 0 then return ENABLE_STATE.None end
        return on == total and ENABLE_STATE.All or ENABLE_STATE.Some
    end

    local function SetEnabled(nameOrIndex, character, value)
        local entry = FindAddon(fixtures, nameOrIndex)
        if not entry then return end
        local who = ResolveCharacter(fixtures, character)
        if who == nil then return end
        if who ~= "all" then
            entry.enabledFor[who] = value
        else
            for key in pairs(KnownCharacters(fixtures)) do entry.enabledFor[key] = value end
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
        challengeModeActive = false, -- C_ChallengeMode.IsChallengeModeActive
        encounterInProgress = false, -- IsEncounterInProgress
        inInstance = false,          -- IsInInstance
        inGroup = false,             -- IsInGroup
        region = 1,                  -- GetCurrentRegion: 1 US, 2 KR, 3 EU, 4 TW, 5 CN
        -- GetInstanceInfo: { name, instanceType, difficultyID, instanceID }; the open world
        -- answers instanceType "none" (switch prompts, #22, #24)
        instance = { name = "Dornogal", instanceType = "none", difficultyID = 0, instanceID = 2552 },
        -- C_LFGList (#23): activities[id] = GetActivityInfoTable result,
        -- searchResults[id] = { activityIDs }, activeEntry = { activityIDs } or nil
        lfg = { activities = {}, searchResults = {}, activeEntry = nil },
        cursor = { x = 0, y = 0 },  -- GetCursorPosition, in screen pixels
        minimapShape = nil,         -- GetMinimapShape is only defined when this is set
    }
    -- KeyMode itself is always installed, enabled and loaded, with whatever metadata its
    -- real TOC declares, so the stub and the TOC cannot disagree about a field.
    M.AddAddon(fixtures, "KeyMode", { title = "KeyMode", loaded = true, metadata = M.TocMetadata() })
    return fixtures
end

-- Every `## Field: value` line of KeyMode.toc, as GetAddOnMetadata would return it.
function M.TocMetadata()
    local handle = assert(io.open("KeyMode.toc", "r"), "run from the repository root")
    local metadata = {}
    for line in handle:lines() do
        local key, value = line:gsub("\r$", ""):match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if key then metadata[key] = value end
    end
    handle:close()
    return metadata
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

-- `fixtures` is passed only by M.Reload, to carry the installed addons and their enable
-- state across a simulated reload.
function M.Load(configure, fixtures)
    fixtures = fixtures or MakeFixtures()
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
    -- A 140x140 minimap centred at (1000, 600) at scale 1, roughly the default layout.
    env.Minimap = MakeWidget(env, "Frame", "Minimap")
    env.Minimap:SetSize(140, 140)
    env.Minimap.GetCenter = function() return 1000, 600 end
    env.Minimap.GetEffectiveScale = function() return fixtures.minimapScale or 1 end
    env.GetCursorPosition = function() return fixtures.cursor.x, fixtures.cursor.y end
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
    -- The safe-to-switch guard's inputs. A test models a client that lacks one by setting
    -- it to nil, in `configure` or afterwards (`env.IsEncounterInProgress = nil`); the
    -- lookup then falls through to the host _G, which has no WoW globals.
    env.C_ChallengeMode = {
        IsChallengeModeActive = function() return fixtures.challengeModeActive end,
    }
    env.IsEncounterInProgress = function() return fixtures.encounterInProgress end
    env.ReloadUI = function() fixtures.reloads = fixtures.reloads + 1 end
    env.IsInInstance = function() return fixtures.inInstance end
    env.IsInGroup = function() return fixtures.inGroup end
    env.GetCurrentRegion = function() return fixtures.region end
    env.GetInstanceInfo = function()
        local i = fixtures.instance
        return i.name, i.instanceType, i.difficultyID, "", 5, 0, false, i.instanceID
    end
    env.C_LFGList = {
        GetActivityInfoTable = function(id) return fixtures.lfg.activities[id] end,
        GetSearchResultInfo = function(id) return fixtures.lfg.searchResults[id] end,
        GetActiveEntryInfo = function() return fixtures.lfg.activeEntry end,
    }
    env.time = os.time

    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    env.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name)
            local category = { panel = panel, name = name, id = name .. "-category" }
            function category:GetID() return self.id end
            fixtures.category = category
            return category
        end,
        RegisterAddOnCategory = function(category) fixtures.registeredCategory = category end,
        OpenToCategory = function(id) fixtures.settingsOpened[#fixtures.settingsOpened + 1] = id end,
        RegisterCanvasLayoutSubcategory = function(parent, panel, name)
            local category = { panel = panel, name = name, parent = parent, id = name .. "-subcategory" }
            function category:GetID() return self.id end
            fixtures.subcategories = fixtures.subcategories or {}
            fixtures.subcategories[name] = category
            return category
        end,
    }
    -- The scroll list API the list editor uses (#18). The view keeps its row initializer
    -- so a test can draw a row by hand; the data provider is just the row list.
    env.CreateScrollBoxListLinearView = function()
        local view = {}
        function view:SetElementExtent(extent) self.extent = extent end
        function view:SetElementInitializer(kind, init) self.kind, self.init = kind, init end
        return view
    end
    env.ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(box, bar, view) box._view, box._bar = view, bar end,
    }
    env.CreateDataProvider = function(rows) return { rows = rows } end
    env.StaticPopup_ShowGenericConfirmation = function(text, callback)
        fixtures.confirmations = fixtures.confirmations or {}
        fixtures.confirmations[#fixtures.confirmations + 1] = text
        if fixtures.autoConfirm ~= false then callback() end
    end

    if configure then configure(env, fixtures) end
    if fixtures.minimapShape then
        env.GetMinimapShape = function() return fixtures.minimapShape end
    end

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
-- A /reload or a fresh login: a new addon environment over the same installed addons,
-- enable state and SavedVariables, with ADDON_LOADED and PLAYER_LOGIN fired. Each
-- addon's `loaded` follows its enable state for the player, as the client would load it.
-- The mutation log and chat are cleared so the new session starts clean.
function M.Reload(env)
    local fixtures, db = env.fixtures, env.KeyModeDB
    for _, entry in ipairs(fixtures.addons) do
        entry.loaded = entry.name == "KeyMode"
            or (entry.enabledFor[fixtures.player.guid] and not entry.loadOnDemand) or false
    end
    fixtures.calls, fixtures.chat = {}, {}
    local new = M.Load(function(e) e.KeyModeDB = db end, fixtures)
    M.Fire(new, "ADDON_LOADED", "KeyMode")
    M.Fire(new, "PLAYER_LOGIN")
    return new
end

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
