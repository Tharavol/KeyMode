-- Triggers.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Watches for the moments a switch is worth offering -- entering a Mythic dungeon or a
-- raid, joining a keystone or raid group, leaving afterwards -- and opens the preview
-- dialog. Never switches on its own: the dialog's Confirm and Reload is the only way a
-- prompt changes anything. (#22, #23, #24, #25)
--
-- Event facts come from the live client's generated API docs (Gethe/wow-ui-source, live,
-- 12.1.0): LFG_LIST_JOINED_GROUP(searchResultID, groupName), LFG_LIST_ACTIVE_ENTRY_UPDATE
-- (created), GROUP_LEFT(category, partyGUID), CHALLENGE_MODE_COMPLETED; search results and
-- listings carry `activityIDs`, a table, and GetActivityInfoTable answers
-- isMythicPlusActivity and categoryID.

local _, ns = ...

local Triggers = {}
ns.Triggers = Triggers

Triggers.PROMPTS = { "arrival", "group", "departure" }
Triggers.LABELS = {
    arrival = "Arrival prompt",
    group = "Group prompt",
    departure = "Departure prompt",
}

-- Difficulty 23 is Mythic, which a keystone dungeon also reports until the key starts
-- (then 8, and the guard blocks switching). Normal and Heroic dungeons never prompt (#37).
local MYTHIC_DUNGEON = 23
-- The Group Finder's Raids category. Blizzard names only the Dungeons one
-- (GROUP_FINDER_CATEGORY_ID_DUNGEONS = 2, Blizzard_GroupFinder/Mainline/LFGList.lua);
-- 3 for Raids was confirmed in-game with `/km debug probe lfg` (v0.5.0 check).
local RAID_CATEGORY = 3
Triggers.MYTHIC_DUNGEON, Triggers.RAID_CATEGORY = MYTHIC_DUNGEON, RAID_CATEGORY

--------------------------------------------------------------------------
-- Decisions (pure, so the stub tests cover them without events)
--------------------------------------------------------------------------

-- Why arriving here is worth a prompt, or nil. `info` is GetInstanceInfo()'s first three
-- returns as { name, instanceType, difficultyID }. Only in a group: LFR and keys always
-- are, and soloing old raids or Mythic dungeons for transmog would otherwise prompt on
-- every visit.
function Triggers.ArrivalReason(info, inGroup)
    if not (info and inGroup) then return nil end
    if info.instanceType == "raid" then return "Entered a raid: " .. tostring(info.name) .. "." end
    if info.instanceType == "party" and info.difficultyID == MYTHIC_DUNGEON then
        return "Entered a Mythic dungeon: " .. tostring(info.name) .. "."
    end
    return nil
end

-- The first of `activities` (GetActivityInfoTable results) that is a Mythic+ or a raid
-- activity, and which kind, or nil.
function Triggers.GroupActivity(activities)
    for _, activity in ipairs(activities or {}) do
        if activity.isMythicPlusActivity then return activity, "Mythic+" end
        if activity.categoryID == RAID_CATEGORY then return activity, "raid" end
    end
    return nil
end

--------------------------------------------------------------------------
-- Prompt rules (#25)
--
-- One way in for every trigger. A prompt is dropped when it is turned off, snoozed this
-- session, already satisfied, would change nothing, or the guard (#10) says no; combat
-- defers it to the end of combat instead, keeping only the latest. "Session" is until the
-- next reload or logout: the snooze lives in Lua state only, and a switch reloads anyway.
--------------------------------------------------------------------------

local snoozed = {}
local pending -- { trigger, mode, reason, still = function -> bool }
local regenFrame

function Triggers:IsEnabled(trigger)
    local prompts = ns.db and ns.db.settings.prompts
    return prompts ~= nil and prompts[trigger] == true
end

function Triggers:Snooze(trigger)
    snoozed[trigger] = true
end

function Triggers:IsSnoozed(trigger)
    return snoozed[trigger] == true
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

-- Offers a switch to `mode` for `trigger`, saying `reason`. `still`, when given, is asked
-- again before a deferred offer opens, since the moment may have passed during combat.
-- Returns "shown", "deferred", or false and why not (for the tests and the debug path).
function Triggers:Offer(trigger, mode, reason, still)
    if not self:IsEnabled(trigger) then return false, "turned off" end
    if self:IsSnoozed(trigger) then return false, "snoozed" end
    if ns.Switch:Mode() == mode then return false, "already in that mode" end
    if InCombat() then
        pending = { trigger = trigger, mode = mode, reason = reason, still = still }
        if regenFrame then regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return "deferred"
    end
    local ok, why = ns.Switch:Check(mode)
    if not ok then return false, why end
    local plan = ns.Switch:Preview(mode)
    -- A no-op switch is applied without a dialog when asked for by hand; a prompt must
    -- not change the recorded mode unasked, so it simply does not appear.
    if #plan.disable == 0 and #plan.enable == 0 then return false, "nothing to change" end
    -- Never cover a dialog the player opened, or another prompt.
    local dialog = ns.UI.dialog
    if dialog and dialog:IsShown() then return false, "dialog already open" end
    ns.UI:Preview(mode, { trigger = trigger, reason = reason })
    return "shown"
end

function Triggers:OnCombatEnded()
    if regenFrame then regenFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    local offer = pending
    pending = nil
    if offer and (not offer.still or offer.still()) then
        self:Offer(offer.trigger, offer.mode, offer.reason, offer.still)
    end
end

--------------------------------------------------------------------------
-- Where the player is (#22, #24)
--------------------------------------------------------------------------

-- Session state: the instance last prompted for (one prompt per visit, not per zone
-- change inside), where the player was at the last zone event, whether a key was
-- completed since entering, and whether the player was in a group.
local state = { promptedFor = nil, last = nil, keyDone = false, inGroup = false }
Triggers.state = state

local function InstanceInfo()
    if type(GetInstanceInfo) ~= "function" then return nil end
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    return { name = name, instanceType = instanceType, difficultyID = difficultyID, instanceID = instanceID }
end

local function InGroup()
    return type(IsInGroup) == "function" and IsInGroup() and true or false
end

local function InInstance(info)
    return info ~= nil and info.instanceType ~= nil and info.instanceType ~= "none"
end

-- Arrival (#22): once per visit to a raid or a Mythic dungeon, outside Instance mode.
local function CheckArrival(info)
    if not InInstance(info) then
        state.promptedFor = nil
        return
    end
    if state.promptedFor == info.instanceID then return end
    local reason = Triggers.ArrivalReason(info, InGroup())
    if not reason then return end
    state.promptedFor = info.instanceID
    Triggers:Offer("arrival", "instance", reason, function()
        local now = InstanceInfo()
        return now ~= nil and now.instanceID == info.instanceID
    end)
end

-- Departure (#24), on reaching the open world: after a completed key, or out of a raid.
-- Walking out of a dungeon mid-key is not a departure, since the key has not completed.
local function CheckDeparture(info)
    local last = state.last
    if InInstance(info) or not InInstance(last) then return end
    local finished = state.keyDone or last.instanceType == "raid"
    state.keyDone = false
    if not finished or ns.Switch:Mode() ~= "instance" then return end
    Triggers:Offer("departure", "world", "Left " .. tostring(last.name) .. ".", function()
        return not InInstance(InstanceInfo())
    end)
end

function Triggers:OnZoneChanged()
    local info = InstanceInfo()
    if not info then return end
    CheckDeparture(info)
    CheckArrival(info)
    state.last = info
    state.inGroup = InGroup()
end

-- Departure (#24) on leaving the group, in Instance mode. GROUP_LEFT fires per group
-- category (home and instance), so it counts only once no group of either kind is left.
function Triggers:OnGroupLeft()
    local wasInGroup = state.inGroup
    state.inGroup = InGroup()
    if not wasInGroup or state.inGroup or ns.Switch:Mode() ~= "instance" then return end
    self:Offer("departure", "world", "Left the group.", function() return not InGroup() end)
end

function Triggers:OnGroupJoined()
    state.inGroup = InGroup()
end

--------------------------------------------------------------------------
-- Group Finder (#23)
--------------------------------------------------------------------------

-- Each of `activityIDs` looked up, skipping any the client cannot (or will not) answer.
-- The lookups take secret arguments on 12.x, so each call is guarded and a refusal reads
-- as "not a Mythic+ or raid activity" rather than an error.
local function Activities(activityIDs)
    local activities = {}
    local lfg = C_LFGList
    if type(lfg) ~= "table" or type(lfg.GetActivityInfoTable) ~= "function" then return activities end
    for _, id in ipairs(activityIDs or {}) do
        local ok, info = pcall(lfg.GetActivityInfoTable, id)
        if ok and type(info) == "table" then activities[#activities + 1] = info end
    end
    return activities
end

local function OfferGroup(activityIDs, verb)
    local activity, kind = Triggers.GroupActivity(Activities(activityIDs))
    if not activity then return end
    local name = activity.fullName or activity.shortName or kind
    Triggers:Offer("group", "instance", verb .. " a " .. kind .. " group: " .. tostring(name) .. ".")
end

-- Joined through the Group Finder, as an applicant.
function Triggers:OnJoinedGroup(searchResultID)
    state.lastJoined = searchResultID -- for `/km debug probe lfg`
    local lfg = C_LFGList
    if type(lfg) ~= "table" or type(lfg.GetSearchResultInfo) ~= "function" then return end
    local ok, info = pcall(lfg.GetSearchResultInfo, searchResultID)
    if ok and type(info) == "table" then OfferGroup(info.activityIDs, "Joined") end
end

-- Listed one's own group. Only on creation, not on every edit of the listing.
function Triggers:OnActiveEntryUpdate(created)
    if not created then return end
    local lfg = C_LFGList
    if type(lfg) ~= "table" or type(lfg.GetActiveEntryInfo) ~= "function" then return end
    local ok, info = pcall(lfg.GetActiveEntryInfo)
    if ok and type(info) == "table" then OfferGroup(info.activityIDs, "Listed") end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local HANDLERS = {
    PLAYER_ENTERING_WORLD = function() Triggers:OnZoneChanged() end,
    ZONE_CHANGED_NEW_AREA = function() Triggers:OnZoneChanged() end,
    CHALLENGE_MODE_COMPLETED = function() state.keyDone = true end,
    GROUP_JOINED = function() Triggers:OnGroupJoined() end,
    GROUP_LEFT = function() Triggers:OnGroupLeft() end,
    LFG_LIST_JOINED_GROUP = function(searchResultID) Triggers:OnJoinedGroup(searchResultID) end,
    LFG_LIST_ACTIVE_ENTRY_UPDATE = function(created) Triggers:OnActiveEntryUpdate(created) end,
    PLAYER_REGEN_ENABLED = function() Triggers:OnCombatEnded() end,
}

local frame = CreateFrame("Frame")
regenFrame = frame
for event in pairs(HANDLERS) do
    if event ~= "PLAYER_REGEN_ENABLED" then frame:RegisterEvent(event) end
end
frame:SetScript("OnEvent", function(_, event, ...)
    if ns.db then HANDLERS[event](...) end
end)

--------------------------------------------------------------------------
-- Testing aid: `/km debug trigger <arrival|group|departure>`
--
-- Runs a prompt through every rule above with a made-up reason, so the dialog, Not now
-- and the per-prompt toggles can be checked in-game without a real raid or key.
--------------------------------------------------------------------------

local SIMULATED = {
    arrival = { mode = "instance", reason = "Entered a raid (simulated)." },
    group = { mode = "instance", reason = "Joined a Mythic+ group (simulated)." },
    -- Like the real one, a departure is only offered in Instance mode.
    departure = { mode = "world", reason = "Left the instance (simulated).", from = "instance" },
}

function Triggers:Simulate(trigger)
    local simulated = SIMULATED[trigger]
    if not simulated then
        ns.Print("'" .. tostring(trigger) .. "' - expected 'arrival', 'group' or 'departure'.")
        return
    end
    if simulated.from and ns.Switch:Mode() ~= simulated.from then
        ns.Print(self.LABELS[trigger] .. " not shown: not in " .. ns.Switch.MODES[simulated.from] .. " mode.")
        return
    end
    local result, why = self:Offer(trigger, simulated.mode, simulated.reason)
    if result == "deferred" then
        ns.Print(self.LABELS[trigger] .. ": in combat, shown when combat ends.")
    elseif not result then
        ns.Print(self.LABELS[trigger] .. " not shown: " .. (tostring(why):gsub("%.$", "")) .. ".")
    end
end
