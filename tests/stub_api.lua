-- stub_api.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Stubs the slice of the WoW API the addon touches, then loads every file KeyMode.toc
-- lists, in TOC order, into a fresh environment per call so tests cannot leak state into
-- one another. Reading the TOC rather than hard-coding a file list keeps the loader
-- correct automatically as files are added or reordered.
--
-- Usage: local stub = dofile("tests/stub_api.lua"); local env = stub.Load()

local M = {}

-- Any widget: records scripts and events, answers the handful of methods the addon calls.
local function MakeWidget(kind, name)
    local w = { kind = kind, name = name, _scripts = {}, _events = {} }
    function w:SetScript(scriptType, fn) self._scripts[scriptType] = fn end
    function w:GetScript(scriptType) return self._scripts[scriptType] end
    function w:RegisterEvent(event) self._events[event] = true end
    function w:UnregisterEvent(event) self._events[event] = nil end
    function w:Show() self._shown = true end
    function w:Hide() self._shown = false end
    function w:IsShown() return self._shown and true or false end
    return w
end

-- Fixture: the installed addon list, per-character enable state, metadata.
-- Tests mutate `env.fixtures` between calls rather than reloading.
local function MakeFixtures()
    return {
        metadata = { KeyMode = { Version = "@project-version@" } },
        chat = {},
    }
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

function M.Load(configure)
    local fixtures = MakeFixtures()
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.fixtures = fixtures
    env.frames = {}

    env.CreateFrame = function(kind, name)
        local w = MakeWidget(kind, name)
        env.frames[#env.frames + 1] = w
        if name then env[name] = w end
        return w
    end
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text) fixtures.chat[#fixtures.chat + 1] = text end,
    }
    env.C_AddOns = {
        GetAddOnMetadata = function(addon, field)
            local meta = fixtures.metadata[addon]
            return meta and meta[field]
        end,
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

return M
