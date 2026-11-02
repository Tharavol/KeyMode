-- Suggest.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Suggested lists (#21): a starting Instance list and World list worked out from what is
-- installed, each addon's `## Category` and its folder name. Build is pure: no ns.db
-- access, no C_AddOns calls, no chat output. Region is the one thin helper that reads
-- the client. The rules are data tables below, so a new addon or category is one line.
-- Modelled on docs/REFERENCE_PROFILE.md.
--
-- The model: Instance mode (Mythic Keystone dungeons and raids) turns off the Instance
-- list, World mode (everything else) turns off the World list. A suggestion must never
-- break play, so when in doubt an addon is left out: the player can always add more.
-- Turning an addon off also turns off everything that requires it (the disable cascade),
-- so each list is the smallest set that does the job: DataStore, not also Altoholic and
-- every DataStore_* module.

local _, ns = ...

local Suggest = {}
ns.Suggest = Suggest

-- The expansion whose raids are current. DBM names its raid modules DBM-Raids-<name>
-- (DBM-Raids-Midnight), so this is bumped with each expansion; every other DBM-Raids-*
-- module is a legacy raid and goes on the Instance list.
Suggest.CURRENT_EXPANSION = "Midnight"

-- GetCurrentRegion() -> the region tag Raider.IO uses in its database folder names.
Suggest.REGIONS = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }

--------------------------------------------------------------------------
-- Rules
--
-- Categories match the TOC's `## Category` exactly, ignoring case. Patterns are Lua
-- patterns matched against the lower-cased folder name after the pattern itself is
-- lower-cased, so they are written in any case but must not use an upper-case
-- character class (%A, %S, ...), which lower-casing would turn into its opposite.
-- Within a list the first matching rule gives the reason.
--------------------------------------------------------------------------

-- Instance list by category. Deliberately not here:
--   Quests (Preydator, RecklessAbandon): undecided on the reference install, and a quest
--     helper can matter inside a dungeon.
--   Inventory: SimpleItemLevel is useful in dungeons.
--   User Interface, Chat, Unit Frames (Titan and its plugins, BlizzMove, ...): layout the
--     player sees everywhere; turning it off moves their screen around.
--   Archon, Dungeons & Raids: built for instanced content.
--   Libraries as such: a library is turned off through what requires it, never alone.
--   Development Tools: BugSack and !BugGrabber should catch errors in every mode.
Suggest.INSTANCE_CATEGORIES = {
    "Professions", "Auctions", "Auction House", "Collections", "Pet Battles", "Housing", "Map",
}

-- Instance list by name. Also deliberately not here: Details plugins (the player picks
-- which meters they want), DBM-Party-* (a legacy dungeon can be in the current season),
-- and Titan plugins.
Suggest.INSTANCE_PATTERNS = {
    { "^Altoholic", "alt tracking" },
    -- Only the root: the DataStore_* modules require it and follow in the cascade.
    { "^DataStore$", "alt tracking data" },
    { "^TradeSkillMaster", "auction house and professions" },
    { "^Auctionator$", "auction house" },
    { "^Collectionator$", "auction house" },
    { "^HandyNotes", "open-world map notes" },
    { "^TomTom$", "open-world navigation" },
    { "^MapPinEnhanced$", "open-world navigation" },
    { "^WaypointUI$", "open-world navigation" },
    { "^WorldQuestsList$", "world quests" },
    { "^Leatrix_Maps$", "world map" },
    { "^DragonRider$", "skyriding" },
    { "^%+?Wowhead_Looter$", "data collection" },
    { "^AutoMailer$", "mail" },
    { "^BuyEmAll$", "vendor purchases" },
    { "^Currency Transfer Helper$", "currency transfers" },
    { "^AccountWideStats$", "alt tracking" },
    { "^ReputationWatcher$", "reputation tracking" },
    { "^Simulationcraft$", "sim export" },
    { "_Debug$", "debug module" },
    { "^QoLify_Decor", "housing" },
    -- DBM modules for open-world and side content.
    { "^DBM%-Delves%-", "DBM delves" },
    { "^DBM%-Lairs%-", "DBM open-world content" },
    { "^DBM%-Brawlers$", "DBM Brawler's Guild" },
    { "^DBM%-PvP$", "DBM PvP" },
    { "^DBM%-WorldEvents$", "DBM world events" },
    { "^DBM%-Scenario%-", "DBM scenarios" },
    { "^DBM%-LegionFishing$", "DBM fishing" },
    { "^DBM%-Test", "DBM test module" },
}

-- DBM's world-boss modules, one per expansion. Lua patterns have no alternation, so
-- these are exact folder names.
Suggest.DBM_WORLD_BOSSES = {
    "DBM-Azeroth", "DBM-Outlands", "DBM-Cataclysm", "DBM-Pandaria", "DBM-Draenor",
    "DBM-BrokenIsles", "DBM-BfA", "DBM-Shadowlands", "DBM-Midnight",
}

-- World list by name; nothing by category. Raid and dungeon boss modules, and the
-- Details plugins that only matter in a raid.
Suggest.WORLD_PATTERNS = {
    { "^DBM%-Raids%-", "DBM raid module" },
    { "^DBM%-Party%-", "DBM dungeon module" },
    { "^Details_RaidCheck$", "raid tool" },
    { "^Details_EncounterDetails$", "boss encounter breakdown" },
}

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

-- Same order as Plan and Inventory: case-insensitive, raw string as tie-breaker.
local function NameLess(a, b)
    local la, lb = a:lower(), b:lower()
    if la ~= lb then return la < lb end
    return a < b
end

local function SortedKeys(set)
    local list = {}
    for name in pairs(set) do list[#list + 1] = name end
    table.sort(list, NameLess)
    return list
end

local function LowerSet(list)
    local set = {}
    for _, value in ipairs(list) do set[value:lower()] = true end
    return set
end

local function MatchPatterns(patterns, lower)
    for _, rule in ipairs(patterns) do
        if lower:find(rule[1]:lower()) then return rule[2] end
    end
end

-- Raider.IO keeps one database per region and kind: M (Mythic+), R (raid), F (recent
-- runs). Only the player's own region's Mythic+ database is worth loading in a key; in
-- the open world none is needed for the player's own profile. Without a known region no
-- _M database is suggested, since the player's own might be among them.
local function RaiderIOReason(lower, region)
    local dbRegion, kind = lower:match("^raiderio_db_(%a+)_(%a+)$")
    if not dbRegion then return nil end
    if region then
        if dbRegion == region:lower() and kind == "m" then return nil end
        if dbRegion ~= region:lower() then return "Raider.IO data for another region" end
        return "Raider.IO raid and recent-runs data"
    end
    if kind == "r" or kind == "f" then return "Raider.IO raid and recent-runs data" end
    return nil
end

--------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------

-- `input` is a table of:
--   records      list from Inventory:Scan(); uses `name` and `category`
--   graph        Inventory.BuildGraph(records); built from records when nil
--   region       the player's region tag ("US", "EU", ...), or nil when unknown
--   expansion    the current expansion as DBM names it; Suggest.CURRENT_EXPANSION if nil
--   isProtected  function(name) -> bool
-- Returns a table of:
--   instance  sorted names suggested for the Instance list
--   world     sorted names suggested for the World list
--   reasons   { instance = { [name] = text }, world = { [name] = text } }, a short
--             player-facing reason for each suggested name
-- KeyMode, every protected addon and everything a protected addon requires are never
-- suggested. An addon that requires another suggestion on the same list is dropped,
-- because the cascade turns it off anyway. An addon may be on both lists.
function Suggest.Build(input)
    input = input or {}
    local Inventory = ns.Inventory
    local records = input.records or {}
    local graph = input.graph or Inventory.BuildGraph(records)
    local canonical = graph.canonical
    local isProtected = input.isProtected or function() return false end
    local region = input.region
    local legacyRaidKeep = (input.expansion or Suggest.CURRENT_EXPANSION):lower()

    local instanceCategories = LowerSet(Suggest.INSTANCE_CATEGORIES)
    local worldBosses = LowerSet(Suggest.DBM_WORLD_BOSSES)

    -- Never suggested: KeyMode, protected addons and what they require.
    local selfName = ns.ADDON_NAME or "KeyMode"
    local excluded, protected = {}, {}
    for _, name in ipairs(graph.names) do
        if name:lower() == selfName:lower() or isProtected(name) then
            excluded[name] = true
            protected[#protected + 1] = name
        end
    end
    for _, name in ipairs(Inventory.Requirements(graph, protected)) do excluded[name] = true end

    local function InstanceReason(lower, category)
        if category and instanceCategories[category:lower()] then return category .. " category" end
        local reason = MatchPatterns(Suggest.INSTANCE_PATTERNS, lower)
        if reason then return reason end
        if worldBosses[lower] then return "DBM world bosses" end
        local raid = lower:match("^dbm%-raids%-(.+)$")
        if raid and raid ~= legacyRaidKeep then return "matches DBM-Raids-* (legacy raid)" end
        return RaiderIOReason(lower, region)
    end

    local candidates = { instance = {}, world = {} }
    local seen = {}
    for _, record in ipairs(records) do
        local name = type(record.name) == "string" and canonical[record.name:lower()]
        if name and not seen[name] then
            seen[name] = true
            if not excluded[name] then
                local lower = name:lower()
                local category = type(record.category) == "string" and record.category or nil
                candidates.instance[name] = InstanceReason(lower, category)
                candidates.world[name] = MatchPatterns(Suggest.WORLD_PATTERNS, lower)
            end
        end
    end

    -- The smallest set: drop an addon that transitively requires another candidate on the
    -- same list. A dependency cycle (each requires the other) keeps both rather than
    -- dropping both.
    local result = { reasons = {} }
    for _, which in ipairs({ "instance", "world" }) do
        local set, kept, reasons = candidates[which], {}, {}
        for name, reason in pairs(set) do
            local covered = false
            for _, need in ipairs(Inventory.Requirements(graph, { name })) do
                if set[need] then
                    local back = false
                    for _, other in ipairs(Inventory.Requirements(graph, { need })) do
                        if other == name then back = true break end
                    end
                    if not back then covered = true break end
                end
            end
            if not covered then
                kept[name] = true
                reasons[name] = reason
            end
        end
        result[which] = SortedKeys(kept)
        result.reasons[which] = reasons
    end
    return result
end

--------------------------------------------------------------------------
-- Region
--------------------------------------------------------------------------

-- The player's region tag ("US", "KR", "EU", "TW", "CN"), or nil when the client does
-- not say or answers something unknown.
function Suggest.Region()
    if type(GetCurrentRegion) ~= "function" then return nil end
    return Suggest.REGIONS[GetCurrentRegion()]
end
