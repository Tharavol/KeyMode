-- suggest_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Suggested lists (#21): the Instance and World lists worked out from category and folder
-- name, the smallest-set rule, protection, Raider.IO by region, DBM legacy raids, and
-- Suggest.Region over GetCurrentRegion.
--
-- The fixture mirrors a real 191-addon install: folder names and `## Category` as that
-- install reported them (the DataStore_* and Altoholic_* suffixes are stand-ins). The
-- dependencies are the well-known ones (DBM modules need DBM-Core, plugins need their host,
-- DataStore needs AddonFactory), written by hand.

return function(stub, T)
    print("suggest")

    local ns = stub.Boot().ns
    local Suggest = ns.Suggest

    local function Join(list) return table.concat(list or {}, ",") end

    local function Has(list, name)
        for _, value in ipairs(list) do
            if value == name then return true end
        end
        return false
    end

    local function Expand(prefix, suffixes)
        local list = {}
        for _, suffix in ipairs(suffixes) do list[#list + 1] = prefix .. suffix end
        return list
    end

    local DATASTORE = Expand("DataStore_", {
        "Achievements", "Agenda", "Auctions", "Characters", "Containers", "Crafts", "Currencies",
        "Garrisons", "Inventory", "Mails", "Pets", "Quests", "Reputations", "Spells", "Stats",
        "Talents", "Professions",
    })
    local ALTOHOLIC = Expand("Altoholic_", {
        "Achievements", "Agenda", "Characters", "Grids", "Guild", "Search", "Summary", "Options",
    })
    local RAIDERIO_DB = {}
    for _, region in ipairs({ "US", "CN", "EU", "KR", "TW" }) do
        for _, kind in ipairs({ "M", "R", "F" }) do
            RAIDERIO_DB[#RAIDERIO_DB + 1] = "RaiderIO_DB_" .. region .. "_" .. kind
        end
    end

    local function Concat(...)
        local all = {}
        for _, list in ipairs({ ... }) do
            for _, value in ipairs(list) do all[#all + 1] = value end
        end
        return all
    end

    -- Category -> folder names; false = no `## Category`.
    local REAL = {
        { "DBM", Concat({ "DBM-Core", "DBM-GUI", "DBM-StatusBarTimers", "DBM-LegionFishing",
            "DBM-SoundEventsPack", "DBM-VPVEM", "DBM-Brawlers", "DBM-Challenges", "DBM-Delves-Midnight",
            "DBM-Delves-WarWithin", "DBM-Lairs-Midnight", "DBM-PvP", "DBM-Scenario-MoP", "DBM-Outlands",
            "DBM-BfA", "DBM-Cataclysm", "DBM-BrokenIsles", "DBM-Midnight", "DBM-Pandaria",
            "DBM-Shadowlands", "DBM-Draenor", "DBM-WorldEvents" },
            Expand("DBM-Party-", { "BC", "BfA", "Cataclysm", "Dragonflight", "Legion", "Midnight", "MoP",
                "Shadowlands", "Vanilla", "WoD", "WotLK", "WarWithin" }),
            Expand("DBM-Raids-", { "BC", "BfA", "Cata", "Legion", "Midnight", "MoP", "Shadowlands",
                "Vanilla", "WoD", "WoTLK" })) },
        { "Libraries", Concat({ "AddonFactory", "DataStore" }, DATASTORE) },
        { "Auctions", { "Auctionator", "Collectionator", "TradeSkillMaster", "TradeSkillMaster_AppHelper" } },
        { "Auction House", { "ShoppingConverter" } },
        { "Professions", { "BetterFishing", "CraftSim", "MoxieTracker", "PublicOrdersReagentsColumn",
            "ProfessionShoppingList", "TradeSkillFluxCapacitor", "WeeklyKnowledge" } },
        { "Collections", { "CanIMogIt", "ManuscriptsJournal", "MountJournalEnhanced", "PepeCollection" } },
        { "Pet Battles", { "BattlePetBattleUITweaks", "tdBattlePetScript", "Rematch" } },
        { "Housing", { "DecorSpendwatch" } },
        { "Map", { "CoyFlightline", "HandyNotes" } },
        { "Quests", { "Preydator", "RecklessAbandon" } },
        { "Inventory", { "LarlenCacheOpener", "SimpleItemLevel", "WarbandMiser" } },
        { "Archon", { "ArchonTooltip", "ArchonTooltipDB_US" } },
        { "Dungeons & Raids", { "KeystoneLoot", "SmartLFG" } },
        { "Development Tools", { "!BugGrabber", "BugSack" } },
        { "User Interface", { "BlizzMove", "DragonRider", "HidingBar", "HidingBar_Options", "NoAutoClose",
            "PasteNG", "SlackersTweakSuite", "Titan" } },
        { "Chat", { "Chattynator", "ChatUtils" } },
        { "Unit Frames", { "Platynator" } },
        { "Other", { "Simulationcraft" } },
        { false, Concat({ "AccountWideStats", "AchievementsBackButton", "AdvancedInterfaceOptions",
            "Altoholic" }, ALTOHOLIC, { "AutoLooter", "AutoMailer", "BestCraft", "BlizzMove_Debug",
            "BonusRollConfirm", "BuyEmAll", "ClassCodex", "Crosshairs", "Currency Transfer Helper",
            "DejaCharacterStats", "DeModal", "Details" },
            Expand("Details_", { "Compare2", "EncounterDetails", "RaidCheck", "DataStorage", "Streamer",
                "TinyThreat", "Vanguard" }),
            { "GearFlyout", "GearSweep", "HandyNotes_MapNotes", "idTip", "Leatrix_Maps", "Leatrix_Plus",
            "Leatrix_Sounds", "LiteMount", "LoggerHead", "MapPinEnhanced", "Plumber", "Porter", "QoLify" },
            Expand("QoLify_", { "CompassBar", "Decor", "DecorSpendwatch", "SoundScaper" }),
            { "RaiderIO" }, RAIDERIO_DB,
            { "ReputationWatcher" },
            Expand("Titan", { "Alts", "Bag", "Clock", "CurrenciesMulti", "Gold", "Location", "LootType",
                "Performance", "Post", "Repair", "UI", "Volume", "XP" }),
            { "TomTom", "TooltipID", "WaypointUI", "WorldQuestsList", "+Wowhead_Looter" }) },
    }

    -- Required dependencies by name prefix, the well-known ones for these addons.
    local function DepsFor(name)
        if name == "DBM-Core" then return {} end
        if name:match("^DBM%-") then return { "DBM-Core" } end
        if name == "DataStore" then return { "AddonFactory" } end
        if name:match("^DataStore_") then return { "DataStore" } end
        if name == "Altoholic" then return { "DataStore", "DataStore_Characters", "DataStore_Containers" } end
        if name:match("^Altoholic_") then return { "Altoholic" } end
        if name == "BugSack" then return { "!BugGrabber" } end
        if name == "Collectionator" then return { "Auctionator" } end
        if name == "TradeSkillMaster_AppHelper" then return { "TradeSkillMaster" } end
        if name == "HandyNotes_MapNotes" then return { "HandyNotes" } end
        if name == "HidingBar_Options" then return { "HidingBar" } end
        if name == "ArchonTooltipDB_US" then return { "ArchonTooltip" } end
        if name:match("^Details_") then return { "Details" } end
        if name:match("^QoLify_") then return { "QoLify" } end
        if name:match("^RaiderIO_DB_") then return { "RaiderIO" } end
        if name:match("^Titan.") then return { "Titan" } end
        return {}
    end

    local function RealRecords()
        local records = { { name = "KeyMode" } }
        for _, group in ipairs(REAL) do
            for _, name in ipairs(group[2]) do
                records[#records + 1] = { name = name, category = group[1] or nil, deps = DepsFor(name) }
            end
        end
        return records
    end

    local function Run(opts)
        opts = opts or {}
        local records = opts.records or RealRecords()
        local protected = {}
        for _, name in ipairs(opts.protected or {}) do protected[name:lower()] = true end
        return Suggest.Build({
            records = records,
            graph = ns.Inventory.BuildGraph(records),
            region = opts.region,
            expansion = opts.expansion,
            isProtected = function(name) return protected[name:lower()] or false end,
        })
    end

    T.Test("fixture mirrors the real install: 191 addons plus KeyMode", function()
        T.AssertEqual(#RealRecords(), 192)
    end)

    --------------------------------------------------------------------------
    -- Instance list
    --------------------------------------------------------------------------

    T.Test("instance: the listed categories are suggested, with the category as reason", function()
        local s = Run({ region = "US" })
        for _, name in ipairs({ "CraftSim", "ShoppingConverter", "CanIMogIt", "Rematch", "DecorSpendwatch",
            "CoyFlightline", "Auctionator", "TradeSkillMaster" }) do
            T.AssertTrue(Has(s.instance, name), name)
        end
        T.AssertEqual(s.reasons.instance.CraftSim, "Professions category")
        T.AssertEqual(s.reasons.instance.ShoppingConverter, "Auction House category")
    end)

    T.Test("instance: category matches ignore case", function()
        local s = Run({ records = { { name = "A", category = "PROFESSIONS" }, { name = "B", category = "map" } } })
        T.AssertEqual(Join(s.instance), "A,B")
    end)

    T.Test("instance: name patterns pick up uncategorised open-world addons", function()
        local s = Run({ region = "US" })
        for _, name in ipairs({ "TomTom", "MapPinEnhanced", "WaypointUI", "WorldQuestsList", "Leatrix_Maps",
            "DragonRider", "+Wowhead_Looter", "AutoMailer", "BuyEmAll", "Currency Transfer Helper",
            "AccountWideStats", "ReputationWatcher", "Simulationcraft", "BlizzMove_Debug", "QoLify_Decor",
            "QoLify_DecorSpendwatch" }) do
            T.AssertTrue(Has(s.instance, name), name)
        end
        T.AssertEqual(s.reasons.instance.DragonRider, "skyriding", "pattern beats an unlisted category")
    end)

    T.Test("instance: DataStore is suggested, not its modules, Altoholic or AddonFactory", function()
        local s = Run({ region = "US" })
        T.AssertTrue(Has(s.instance, "DataStore"), "root")
        T.AssertFalse(Has(s.instance, "AddonFactory"), "required by DataStore, not by itself")
        T.AssertFalse(Has(s.instance, "Altoholic"), "requires DataStore")
        T.AssertFalse(Has(s.instance, "Altoholic_Grids"), "requires Altoholic")
        T.AssertFalse(Has(s.instance, "DataStore_Containers"), "module")
        local off = ns.Inventory.Dependents(ns.Inventory.BuildGraph(RealRecords()), { "DataStore" })
        T.AssertTrue(Has(off, "Altoholic") and Has(off, "Altoholic_Grids") and Has(off, "DataStore_Pets"),
            "the cascade still takes them")
    end)

    T.Test("instance: a plugin of a suggested host is left to the cascade", function()
        local s = Run({ region = "US" })
        T.AssertTrue(Has(s.instance, "HandyNotes"), "host")
        T.AssertFalse(Has(s.instance, "HandyNotes_MapNotes"), "plugin")
        T.AssertFalse(Has(s.instance, "Collectionator"), "requires Auctionator")
        T.AssertFalse(Has(s.instance, "TradeSkillMaster_AppHelper"), "requires TradeSkillMaster")
    end)

    T.Test("instance: Altoholic alone is suggested when DataStore is not installed", function()
        local s = Run({ records = { { name = "Altoholic" }, { name = "Altoholic_Grids", deps = { "Altoholic" } } } })
        T.AssertEqual(Join(s.instance), "Altoholic")
    end)

    T.Test("instance: DBM open-world, side-content and world-boss modules", function()
        local s = Run({ region = "US" })
        for _, name in ipairs({ "DBM-Delves-Midnight", "DBM-Delves-WarWithin", "DBM-Lairs-Midnight",
            "DBM-Brawlers", "DBM-PvP", "DBM-WorldEvents", "DBM-Scenario-MoP", "DBM-LegionFishing",
            "DBM-Outlands", "DBM-BfA", "DBM-Cataclysm", "DBM-BrokenIsles", "DBM-Midnight", "DBM-Pandaria",
            "DBM-Shadowlands", "DBM-Draenor" }) do
            T.AssertTrue(Has(s.instance, name), name)
        end
        T.AssertEqual(s.reasons.instance["DBM-Pandaria"], "DBM world bosses")
        local t = Run({ records = { { name = "DBM-Test" }, { name = "DBM-Test-Dungeons" }, { name = "DBM-Azeroth" } } })
        T.AssertEqual(Join(t.instance), "DBM-Azeroth,DBM-Test,DBM-Test-Dungeons")
    end)

    T.Test("instance: legacy raid modules on, the current expansion's raid module off", function()
        local s = Run({ region = "US" })
        T.AssertTrue(Has(s.instance, "DBM-Raids-Legion"), "legacy")
        T.AssertTrue(Has(s.instance, "DBM-Raids-WoTLK"), "legacy")
        T.AssertFalse(Has(s.instance, "DBM-Raids-Midnight"), "current raids are Instance mode")
        T.AssertEqual(s.reasons.instance["DBM-Raids-Legion"], "matches DBM-Raids-* (legacy raid)")
        local later = Run({ region = "US", expansion = "legion" })
        T.AssertFalse(Has(later.instance, "DBM-Raids-Legion"), "expansion input, any case")
        T.AssertTrue(Has(later.instance, "DBM-Raids-Midnight"), "now legacy")
    end)

    T.Test("instance: DBM core, dungeon and challenge modules stay on", function()
        local s = Run({ region = "US" })
        for _, name in ipairs({ "DBM-Core", "DBM-GUI", "DBM-StatusBarTimers", "DBM-Challenges",
            "DBM-Party-Legion", "DBM-Party-Midnight", "DBM-SoundEventsPack", "DBM-VPVEM" }) do
            T.AssertFalse(Has(s.instance, name), name)
        end
    end)

    T.Test("instance: Raider.IO keeps only the player's own Mythic+ database", function()
        local s = Run({ region = "US" })
        T.AssertFalse(Has(s.instance, "RaiderIO_DB_US_M"), "own region M")
        T.AssertFalse(Has(s.instance, "RaiderIO"), "the addon itself")
        for _, name in ipairs(RAIDERIO_DB) do
            if name ~= "RaiderIO_DB_US_M" then T.AssertTrue(Has(s.instance, name), name) end
        end
        T.AssertEqual(s.reasons.instance.RaiderIO_DB_EU_M, "Raider.IO data for another region")
        local eu = Run({ region = "eu" })
        T.AssertFalse(Has(eu.instance, "RaiderIO_DB_EU_M"), "region compared ignoring case")
        T.AssertTrue(Has(eu.instance, "RaiderIO_DB_US_M"), "other region")
    end)

    T.Test("instance: without a region no Mythic+ database is suggested", function()
        local s = Run()
        for _, name in ipairs(RAIDERIO_DB) do
            T.AssertEqual(Has(s.instance, name), not name:match("_M$"), name)
        end
    end)

    T.Test("instance: deliberately excluded addons stay off the list", function()
        local s = Run({ region = "US" })
        for _, name in ipairs({ "Preydator", "RecklessAbandon", "SimpleItemLevel", "LarlenCacheOpener",
            "WarbandMiser", "Titan", "TitanBag", "TitanXP", "Details", "Details_Streamer", "Details_Compare2",
            "ArchonTooltip", "ArchonTooltipDB_US", "KeystoneLoot", "SmartLFG", "AddonFactory", "BlizzMove",
            "Chattynator", "Platynator", "GearSweep", "Plumber", "SlackersTweakSuite", "QoLify",
            "QoLify_CompassBar", "Leatrix_Plus", "BestCraft" }) do
            T.AssertFalse(Has(s.instance, name), name)
        end
    end)

    --------------------------------------------------------------------------
    -- World list
    --------------------------------------------------------------------------

    T.Test("world: every DBM raid and dungeon module, and two Details raid plugins", function()
        local s = Run({ region = "US" })
        T.AssertTrue(Has(s.world, "DBM-Raids-Midnight"), "current raid")
        T.AssertTrue(Has(s.world, "DBM-Raids-Legion"), "legacy raid")
        T.AssertTrue(Has(s.world, "DBM-Party-Midnight"), "dungeon")
        T.AssertTrue(Has(s.world, "Details_RaidCheck"), "RaidCheck")
        T.AssertTrue(Has(s.world, "Details_EncounterDetails"), "EncounterDetails")
        T.AssertEqual(#s.world, 10 + 12 + 2, "nothing else")
        T.AssertEqual(s.reasons.world["DBM-Party-MoP"], "DBM dungeon module")
    end)

    T.Test("world: nothing by category", function()
        local s = Run({ records = { { name = "CraftSim", category = "Professions" } } })
        T.AssertEqual(Join(s.world), "")
        T.AssertEqual(Join(s.instance), "CraftSim")
    end)

    T.Test("both lists: DBM-Party only on World, a legacy raid on both", function()
        local s = Run({ region = "US" })
        T.AssertFalse(Has(s.instance, "DBM-Party-BC"), "not Instance")
        T.AssertTrue(Has(s.world, "DBM-Party-BC"), "World")
        T.AssertTrue(Has(s.instance, "DBM-Raids-BC") and Has(s.world, "DBM-Raids-BC"), "both")
        T.AssertEqual(s.reasons.world["DBM-Raids-BC"], "DBM raid module", "reason per list")
    end)

    --------------------------------------------------------------------------
    -- Protection
    --------------------------------------------------------------------------

    T.Test("never KeyMode, a protected addon, or what a protected addon requires", function()
        local records = RealRecords()
        records[#records + 1] = { name = "!BugGrabber_Debug" }
        local s = Run({ records = records, region = "US", protected = { "BugSack", "!BugGrabber_Debug" } })
        T.AssertFalse(Has(s.instance, "!BugGrabber_Debug"), "protected, though it matches _Debug$")
        T.AssertFalse(Has(s.instance, "KeyMode"), "self")
        local t = Run({ region = "US", protected = { "Altoholic" } })
        T.AssertFalse(Has(t.instance, "Altoholic"), "protected")
        T.AssertFalse(Has(t.instance, "DataStore"), "required by a protected addon")
        -- A module of a protected addon is its own addon: nothing protected requires it.
        T.AssertTrue(Has(t.instance, "Altoholic_Grids"), "module of a protected addon")
        local u = Run({ records = { { name = "KeyMode", category = "Map" },
            { name = "BugSack", deps = { "!BugGrabber" } }, { name = "!BugGrabber", category = "Professions" } },
            protected = { "bugsack" } })
        T.AssertEqual(Join(u.instance), "", "!BugGrabber needed by protected BugSack; KeyMode never")
    end)

    --------------------------------------------------------------------------
    -- Shape
    --------------------------------------------------------------------------

    T.Test("lists are sorted case-insensitively and every name has a reason", function()
        local s = Run({ region = "US" })
        for _, which in ipairs({ "instance", "world" }) do
            for i, name in ipairs(s[which]) do
                T.AssertEqual(type(s.reasons[which][name]), "string", which .. " " .. name)
                if i > 1 then T.AssertTrue(s[which][i - 1]:lower() < name:lower(), "sorted at " .. name) end
            end
        end
    end)

    T.Test("an empty input gives empty lists; the graph is built when not passed", function()
        local s = Suggest.Build({})
        T.AssertEqual(#s.instance + #s.world, 0)
        local t = Suggest.Build({ records = { { name = "TomTom" } } })
        T.AssertEqual(Join(t.instance), "TomTom")
    end)

    T.Test("CURRENT_EXPANSION is the default expansion", function()
        T.AssertEqual(Suggest.CURRENT_EXPANSION, "Midnight")
        local s = Run({ region = "US" })
        T.AssertFalse(Has(s.instance, "DBM-Raids-Midnight"))
    end)

    T.Test("Build touches no state", function()
        local env = stub.Boot()
        env.ns.Suggest.Build({ records = env.ns.Inventory:Scan(), region = "US" })
        T.AssertEqual(#env.fixtures.calls, 0, "no C_AddOns mutation")
        T.AssertEqual(#env.fixtures.chat, 0, "no chat")
    end)

    --------------------------------------------------------------------------
    -- Region
    --------------------------------------------------------------------------

    T.Test("Region maps GetCurrentRegion and nil-guards the API", function()
        local expected = { "US", "KR", "EU", "TW", "CN" }
        for id, tag in ipairs(expected) do
            local env = stub.Boot(function(_, fixtures) fixtures.region = id end)
            T.AssertEqual(env.ns.Suggest.Region(), tag, "region " .. id)
        end
        local env = stub.Boot(function(_, fixtures) fixtures.region = 72 end)
        T.AssertEqual(env.ns.Suggest.Region(), nil, "unknown id")
        env = stub.Boot()
        T.AssertEqual(env.ns.Suggest.Region(), "US", "default fixture")
        env.GetCurrentRegion = nil
        T.AssertEqual(env.ns.Suggest.Region(), nil, "API missing")
    end)
end
