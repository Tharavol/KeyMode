-- Probe.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- `/km debug probe`: the in-game half of #6. The enable-state API is documented one way
-- (a non-nilable `character`, default "0") and used another by Blizzard's own AddOn list
-- (the player's GUID, or nil for all characters), so the switch engine is not built
-- until the live client has answered which is right. The probe prints what the client
-- reports for every candidate character key and lets each mutation and save step be run
-- by hand, one at a time, with a reload or logout in between.
--
-- The one exception to "only Switch.lua mutates": enable/disable/save/reset here act on
-- the KeyModeProbe fixture addon (tests/fixtures/KeyModeProbe) and nothing else. Reads
-- work on any installed addon.

local _, ns = ...

local Probe = {}
ns.Probe = Probe

Probe.TARGET = "KeyModeProbe"

-- Every probe line also goes to KeyModeDB.probeLog, account-wide, so a session spanning
-- several characters, reloads and logouts can be read back from
-- WTF\Account\<ACCOUNT>\SavedVariables\KeyMode.lua instead of retyped from chat.
-- Capped so a forgotten log cannot grow without bound; `/km debug probe clear` empties it.
local LOG_LIMIT = 2000
local function Out(text)
    ns.Print(text)
    if not ns.db then return end
    local log = ns.db.probeLog or {}
    ns.db.probeLog = log
    log[#log + 1] = text
    while #log > LOG_LIMIT do table.remove(log, 1) end
end

-- Every value worth trying as the `character` argument, in a fixed order so successive
-- reports line up. nil is "all characters" in Blizzard's AddOn list.
local function CharacterKeys()
    local name, realm = UnitName("player"), nil
    if UnitFullName then
        local fullName, fullRealm = UnitFullName("player")
        name, realm = fullName or name, fullRealm
    end
    return {
        { label = "guid", value = UnitGUID("player") },
        { label = "name", value = name },
        { label = "full", value = realm and realm ~= "" and (name .. "-" .. realm) or nil, needsRealm = true },
        { label = "zero", value = "0" },
        { label = "all", value = nil },
    }
end

local function FindKey(label)
    for _, key in ipairs(CharacterKeys()) do
        if key.label == label then return key end
    end
end

local function KeyLabels()
    local labels = {}
    for i, key in ipairs(CharacterKeys()) do labels[i] = key.label end
    return table.concat(labels, "|")
end

local function Installed(name)
    for index = 1, C_AddOns.GetNumAddOns() do
        local folder = C_AddOns.GetAddOnInfo(index)
        if folder and folder:lower() == name:lower() then return index, folder end
    end
end

-- pcall, because an argument the client rejects (a nil it documents as non-nilable)
-- raises, and that rejection is itself one of the answers being looked for.
local function Try(fn, ...)
    local results = { pcall(fn, ...) }
    if not results[1] then return "error: " .. tostring(results[2]) end
    return unpack(results, 2)
end

local function Joined(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

function Probe:Report(name)
    local index, folder = Installed(name)
    if not index then
        Out("Probe: '" .. name .. "' is not installed.")
        return
    end
    local _, title, _, loadable, reason, security = C_AddOns.GetAddOnInfo(index)
    Out("Probe: " .. folder .. " (#" .. index .. ", title '" .. tostring(title) .. "')")
    Out("  loadable " .. tostring(loadable) .. ", reason " .. tostring(reason)
        .. ", security " .. tostring(security) .. ", loaded " .. tostring(C_AddOns.IsAddOnLoaded(index))
        .. ", LoD " .. tostring(C_AddOns.IsAddOnLoadOnDemand(index)))
    local states = {}
    for _, key in ipairs(CharacterKeys()) do
        if key.needsRealm and key.value == nil then
            states[#states + 1] = key.label .. "=n/a"
        else
            states[#states + 1] = key.label .. "=" .. tostring(Try(C_AddOns.GetAddOnEnableState, folder, key.value))
        end
    end
    Out("  enable state (0 None, 1 Some, 2 All): " .. table.concat(states, " "))
    Out("  by index, guid: " .. tostring(Try(C_AddOns.GetAddOnEnableState, index, UnitGUID("player"))))
    Out("  deps (as returned): " .. Joined(C_AddOns.GetAddOnDependencies(index)))
    Out("  optional deps: " .. Joined(C_AddOns.GetAddOnOptionalDependencies(index)))
    Out("  guid " .. tostring(UnitGUID("player")) .. ", full name "
        .. tostring((FindKey("full") or {}).value))
end

-- Changes the fixture addon only. Prints the report straight after, which answers
-- "does GetAddOnEnableState see the change before SaveAddOns and a reload".
function Probe:Set(enable, label)
    local key = FindKey(label or "")
    if not key then
        Out("Probe: expected a character key: " .. KeyLabels() .. ".")
        return
    end
    if key.needsRealm and key.value == nil then
        Out("Probe: no realm name available for 'full'.")
        return
    end
    if not Installed(Probe.TARGET) then
        Out("Probe: install tests/fixtures/" .. Probe.TARGET .. " first.")
        return
    end
    local fn = enable and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn
    local ok, err = pcall(fn, Probe.TARGET, key.value)
    Out("Probe: " .. (enable and "EnableAddOn" or "DisableAddOn") .. "(" .. Probe.TARGET .. ", "
        .. label .. ") " .. (ok and "returned" or ("raised: " .. tostring(err))))
    self:Report(Probe.TARGET)
end

-- One pass over every installed addon for the facts the inventory and dependency graph
-- (#7, #8) and the suggested profile (#21) build on, plus whether each API the guard
-- (#10) needs exists on this client.
function Probe:Scan()
    local folders = {}
    local count = C_AddOns.GetNumAddOns()
    for index = 1, count do
        local folder = C_AddOns.GetAddOnInfo(index)
        folders[folder:lower()] = folder
    end

    local reasons, caseMismatches, missing, categories = {}, {}, {}, 0
    for index = 1, count do
        local folder, _, _, _, reason = C_AddOns.GetAddOnInfo(index)
        local tally = tostring(reason)
        reasons[tally] = (reasons[tally] or 0) + 1
        for _, dep in ipairs({ C_AddOns.GetAddOnDependencies(index) }) do
            local installed = folders[dep:lower()]
            if not installed then
                missing[#missing + 1] = folder .. " -> " .. dep
            elseif installed ~= dep then
                caseMismatches[#caseMismatches + 1] = folder .. " -> " .. dep .. " (folder " .. installed .. ")"
            end
        end
        local category = C_AddOns.GetAddOnMetadata(index, "Category")
        if category and category ~= "" then categories = categories + 1 end
    end

    Out("Probe scan: " .. count .. " addons installed.")
    local tallies = {}
    for reason, n in pairs(reasons) do tallies[#tallies + 1] = reason .. "=" .. n end
    table.sort(tallies)
    Out("  reasons: " .. table.concat(tallies, ", "))
    Out("  dependency names differing in case from the folder: " .. #caseMismatches)
    for i = 1, math.min(#caseMismatches, 10) do Out("    " .. caseMismatches[i]) end
    Out("  dependencies not installed: " .. #missing)
    for i = 1, math.min(#missing, 10) do Out("    " .. missing[i]) end
    Out("  addons with ## Category metadata: " .. categories)
    Out("  APIs: IsEncounterInProgress " .. tostring(IsEncounterInProgress ~= nil)
        .. ", C_ChallengeMode.IsChallengeModeActive "
        .. tostring(C_ChallengeMode ~= nil and C_ChallengeMode.IsChallengeModeActive ~= nil)
        .. ", UnitFullName " .. tostring(UnitFullName ~= nil))
end

-- `argument` keeps the player's case, since an addon name to report on can be typed.
function Probe:Run(argument)
    local sub, rest = (argument or ""):match("^(%S*)%s*(.-)$")
    local lower = sub:lower()
    local name, realm = UnitName("player"), UnitFullName and select(2, UnitFullName("player"))
    if lower == "clear" then
        if ns.db then ns.db.probeLog = nil end
        ns.Print("Probe: log cleared.")
        return
    end
    Out("---- " .. tostring(name) .. "-" .. tostring(realm) .. ": /km debug probe " .. (argument or ""))
    if lower == "" then
        self:Report(Probe.TARGET)
    elseif lower == "enable" or lower == "disable" then
        self:Set(lower == "enable", rest:lower())
    elseif lower == "save" then
        C_AddOns.SaveAddOns()
        Out("Probe: SaveAddOns() called. /reload, then /km debug probe.")
    elseif lower == "reset" then
        C_AddOns.ResetAddOns()
        Out("Probe: ResetAddOns() called.")
        self:Report(Probe.TARGET)
    elseif lower == "scan" then
        self:Scan()
    else
        self:Report(sub)
    end
end

-- While a probe session is open (the log is non-empty), every login and reload records
-- whether the fixture actually loaded and its state under every key, so "did the change
-- take effect" is answered on the next character or after the next /reload without
-- typing anything. PLAYER_LOGIN fires after every addon has loaded, the fixture included.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    if not (ns.db and ns.db.probeLog and #ns.db.probeLog > 0) then return end
    local name, realm = UnitName("player"), UnitFullName and select(2, UnitFullName("player"))
    Out("---- " .. tostring(name) .. "-" .. tostring(realm) .. ": login or reload; "
        .. Probe.TARGET .. " loaded = " .. tostring(C_AddOns.IsAddOnLoaded(Probe.TARGET)))
    Probe:Report(Probe.TARGET)
end)
