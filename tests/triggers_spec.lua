-- triggers_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The switch prompts (#22, #23, #24, #25) and the key binding (#26): the pure decisions,
-- then each prompt end to end through the events the client fires, the rules every
-- prompt goes through, and the dialog's Not now.

return function(stub, T)
    print("triggers")

    local RAID = { name = "Liberation of Undermine", instanceType = "raid", difficultyID = 14, instanceID = 2769 }
    local OTHER_RAID = { name = "Nerub-ar Palace", instanceType = "raid", difficultyID = 17, instanceID = 2657 }
    local MYTHIC = { name = "Ara-Kara", instanceType = "party", difficultyID = 23, instanceID = 2660 }
    local KEY = { name = "Ara-Kara", instanceType = "party", difficultyID = 8, instanceID = 2660 }
    local HEROIC = { name = "Ara-Kara", instanceType = "party", difficultyID = 2, instanceID = 2660 }
    local WORLD = { name = "Dornogal", instanceType = "none", difficultyID = 0, instanceID = 2552 }

    -- TomTom is on the Instance list, so Instance mode always has something to change.
    local function Boot(configure)
        local env = stub.Boot(function(e, fixtures)
            stub.AddAddon(fixtures, "TomTom")
            stub.AddAddon(fixtures, "Details")
            if configure then configure(e, fixtures) end
        end)
        stub.Slash(env, "/km list instance add TomTom")
        stub.TakeChat(env)
        return env
    end

    local function Dialog(env) return env.ns.UI.dialog end

    local function Shown(env)
        local dialog = Dialog(env)
        return dialog ~= nil and dialog:IsShown()
    end

    local function Close(env)
        local dialog = Dialog(env)
        if dialog then dialog:Hide() end
    end

    -- Moves the player to `where`, in or out of a group, and fires the zone event.
    local function Enter(env, where, inGroup, event)
        env.fixtures.instance = where
        if inGroup ~= nil then env.fixtures.inGroup = inGroup end
        stub.Fire(env, event or "PLAYER_ENTERING_WORLD")
    end

    local function Has(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return true end
        end
        return false
    end

    -- Into Instance mode through the dialog, then the reload that follows.
    local function InInstanceMode(env)
        stub.Slash(env, "/km instance")
        Dialog(env).confirmButton:Click()
        return stub.Reload(env)
    end

    --------------------------------------------------------------------------
    -- Decisions
    --------------------------------------------------------------------------

    T.Test("arrival: any raid or a Mythic dungeon, in a group; not Heroic, not solo, not the world", function()
        local env = Boot()
        local Reason = env.ns.Triggers.ArrivalReason
        T.AssertEqual(Reason(RAID, true), "Entered a raid: Liberation of Undermine.", "raid")
        T.AssertEqual(Reason(OTHER_RAID, true), "Entered a raid: Nerub-ar Palace.", "LFR")
        T.AssertEqual(Reason(MYTHIC, true), "Entered a Mythic dungeon: Ara-Kara.", "Mythic")
        T.AssertEqual(Reason(HEROIC, true), nil, "Heroic")
        T.AssertEqual(Reason(KEY, true), nil, "a started key reports 8")
        T.AssertEqual(Reason(RAID, false), nil, "solo raid")
        T.AssertEqual(Reason(MYTHIC, false), nil, "solo Mythic")
        T.AssertEqual(Reason(WORLD, true), nil, "open world")
    end)

    T.Test("group activity: Mythic+ or the Raids category; the first match wins", function()
        local env = Boot()
        local Activity = env.ns.Triggers.GroupActivity
        local heroic = { fullName = "Ara-Kara (Heroic)", categoryID = 2 }
        local key = { fullName = "Ara-Kara (Mythic Keystone)", categoryID = 2, isMythicPlusActivity = true }
        local raid = { fullName = "Liberation of Undermine (Heroic)", categoryID = 3 }
        local found, kind = Activity({ heroic, key })
        T.AssertTrue(found == key, "key found")
        T.AssertEqual(kind, "Mythic+", "kind")
        found, kind = Activity({ raid })
        T.AssertTrue(found == raid, "raid found")
        T.AssertEqual(kind, "raid", "raid kind")
        T.AssertEqual(Activity({ heroic }), nil, "Heroic dungeon")
        T.AssertEqual(Activity(nil), nil, "nothing")
    end)

    --------------------------------------------------------------------------
    -- Arrival (#22)
    --------------------------------------------------------------------------

    T.Test("arrival: entering a raid in a group opens the dialog with the reason and Not now", function()
        local env = Boot()
        Enter(env, RAID, true)
        T.AssertTrue(Shown(env), "dialog shown")
        local dialog = Dialog(env)
        T.AssertEqual(dialog.title:GetText(), "Switch to Instance mode", "title")
        T.AssertTrue(dialog.intro:GetText():find("^Entered a raid: Liberation of Undermine%. "), "reason leads")
        T.AssertEqual(dialog.cancelButton:GetText(), "Not now", "Not now")
        T.AssertEqual(env.fixtures.reloads, 0, "nothing switched")
    end)

    T.Test("arrival: once per visit, again after leaving and coming back", function()
        local env = Boot()
        Enter(env, RAID, true)
        Close(env)
        Enter(env, RAID, true, "ZONE_CHANGED_NEW_AREA")
        T.AssertFalse(Shown(env), "no second prompt inside")
        Enter(env, WORLD, true)
        Enter(env, RAID, true)
        T.AssertTrue(Shown(env), "prompted on the next visit")
    end)

    T.Test("arrival: Mythic dungeon yes; Heroic, solo and a started key no", function()
        local env = Boot()
        Enter(env, HEROIC, true)
        T.AssertFalse(Shown(env), "Heroic")
        Enter(env, WORLD, true)
        Enter(env, MYTHIC, false)
        T.AssertFalse(Shown(env), "solo")
        Enter(env, WORLD, true)
        env.fixtures.challengeModeActive = true
        Enter(env, KEY, true)
        T.AssertFalse(Shown(env), "started key")
        env.fixtures.challengeModeActive = false
        Enter(env, WORLD, true)
        Enter(env, MYTHIC, true)
        T.AssertTrue(Shown(env), "Mythic in a group")
    end)

    T.Test("arrival: nothing in Instance mode already, nothing with an empty Instance list", function()
        local env = InInstanceMode(Boot())
        Enter(env, RAID, true)
        T.AssertFalse(Shown(env), "already in Instance mode")

        local empty = Boot()
        stub.Slash(empty, "/km list instance clear")
        Enter(empty, RAID, true)
        T.AssertFalse(Shown(empty), "nothing to change")
        T.AssertEqual(empty.ns.Switch:Mode(), "off", "the mode is not changed unasked")
    end)

    T.Test("a prompt's Confirm and Reload switches like any other", function()
        local env = Boot()
        Enter(env, RAID, true)
        Dialog(env).confirmButton:Click()
        T.AssertEqual(env.fixtures.reloads, 1, "reloaded")
        T.AssertEqual(env.ns.Switch:Mode(), "instance", "Instance mode")
    end)

    --------------------------------------------------------------------------
    -- Rules (#25)
    --------------------------------------------------------------------------

    T.Test("Not now snoozes that prompt until the next reload, and only that one", function()
        local env = Boot()
        Enter(env, RAID, true)
        Dialog(env).cancelButton:Click()
        T.AssertFalse(Shown(env), "closed")
        T.AssertEqual(env.fixtures.reloads, 0, "nothing switched")
        Enter(env, WORLD, true)
        Enter(env, OTHER_RAID, true)
        T.AssertFalse(Shown(env), "arrival snoozed")

        env.fixtures.lfg.activities[1] = { fullName = "Ara-Kara (Mythic Keystone)", isMythicPlusActivity = true }
        env.fixtures.lfg.searchResults[7] = { activityIDs = { 1 } }
        stub.Fire(env, "LFG_LIST_JOINED_GROUP", 7, "Pug")
        T.AssertTrue(Shown(env), "the group prompt is not snoozed")
        Close(env)

        local reloaded = stub.Reload(env)
        Enter(reloaded, WORLD, true)
        Enter(reloaded, RAID, true)
        T.AssertTrue(Shown(reloaded), "a reload ends the snooze")
    end)

    T.Test("Cancel on a dialog opened by hand snoozes nothing, and says Cancel", function()
        local env = Boot()
        Enter(env, RAID, true)
        Close(env)
        stub.Slash(env, "/km instance")
        T.AssertEqual(Dialog(env).cancelButton:GetText(), "Cancel", "Cancel again")
        T.AssertTrue(Dialog(env).intro:GetText():find("^Turns off"), "no reason")
        Dialog(env).cancelButton:Click()
        T.AssertFalse(env.ns.Triggers:IsSnoozed("arrival"), "not snoozed")
    end)

    T.Test("a prompt never covers an open dialog", function()
        local env = Boot()
        stub.Slash(env, "/km instance")
        Enter(env, RAID, true)
        T.AssertEqual(Dialog(env).cancelButton:GetText(), "Cancel", "the player's dialog stays")
    end)

    T.Test("a prompt turned off does not appear; /km prompts reports and sets", function()
        local env = Boot()
        stub.Slash(env, "/km prompts arrival off")
        T.AssertTrue(Has(stub.TakeChat(env), "Arrival prompt is off."), "reported")
        T.AssertEqual(env.KeyModeDB.settings.prompts.arrival, false, "saved")
        Enter(env, RAID, true)
        T.AssertFalse(Shown(env), "not shown")
        stub.Slash(env, "/km prompts")
        T.AssertTrue(Has(stub.TakeChat(env), "Prompts: arrival off, group on, departure on"), "listed")
        stub.Slash(env, "/km prompts arrival")
        T.AssertEqual(env.KeyModeDB.settings.prompts.arrival, true, "bare toggles")
        stub.Slash(env, "/km prompts lobby on")
        T.AssertTrue(Has(stub.TakeChat(env), "'lobby' - expected 'arrival', 'group' or 'departure'."), "unknown")
        stub.Slash(env, "/km prompts group maybe")
        T.AssertTrue(Has(stub.TakeChat(env), "'maybe' - expected 'on' or 'off'."), "bad value")
    end)

    T.Test("combat defers a prompt to its end, and drops it if the moment passed", function()
        local env = Boot()
        env.fixtures.inCombat = true
        Enter(env, RAID, true)
        T.AssertFalse(Shown(env), "not in combat")
        env.fixtures.inCombat = false
        stub.Fire(env, "PLAYER_REGEN_ENABLED")
        T.AssertTrue(Shown(env), "shown after combat")
        Close(env)

        local left = Boot()
        left.fixtures.inCombat = true
        Enter(left, RAID, true)
        left.fixtures.inCombat = false
        Enter(left, WORLD, true)
        stub.Fire(left, "PLAYER_REGEN_ENABLED")
        T.AssertFalse(Shown(left), "left the raid during combat")
    end)

    T.Test("old saved settings get every prompt turned on", function()
        local env = stub.Load(function(e) e.KeyModeDB = { dbVersion = 3, settings = { debug = true } } end)
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        local prompts = env.KeyModeDB.settings.prompts
        T.AssertTrue(prompts.arrival and prompts.group and prompts.departure, "all on")
    end)

    T.Test("the options panel has a checkbox per prompt, under Prompts", function()
        local env = Boot()
        local byPrompt = {}
        for _, checkbox in ipairs(env.ns.Options.panel.checkboxes) do
            if checkbox.definition.prompt then byPrompt[checkbox.definition.prompt] = checkbox end
        end
        for _, name in ipairs(env.ns.Triggers.PROMPTS) do
            T.AssertTrue(byPrompt[name] ~= nil, name .. " checkbox")
        end
        env.ns.Options:Refresh()
        T.AssertTrue(byPrompt.group:GetChecked(), "reflects on")
        byPrompt.group:SetChecked(false)
        byPrompt.group:Click()
        T.AssertEqual(env.KeyModeDB.settings.prompts.group, false, "click saves")
        T.AssertEqual(env.KeyModeDB.settings.debug, false, "other settings untouched")
    end)

    T.Test("/km debug trigger shows a simulated prompt, through the same rules", function()
        local env = Boot()
        stub.Slash(env, "/km debug trigger arrival")
        T.AssertTrue(Shown(env), "shown")
        T.AssertTrue(Dialog(env).intro:GetText():find("(simulated)", 1, true), "says simulated")
        Dialog(env).cancelButton:Click()
        stub.TakeChat(env)
        stub.Slash(env, "/km debug trigger arrival")
        T.AssertTrue(Has(stub.TakeChat(env), "Arrival prompt not shown: snoozed."), "snoozed")
        stub.Slash(env, "/km debug trigger departure")
        T.AssertTrue(Has(stub.TakeChat(env), "Departure prompt not shown: not in Instance mode."), "needs Instance")
        stub.Slash(env, "/km debug trigger lobby")
        T.AssertTrue(Has(stub.TakeChat(env), "'lobby' - expected"), "unknown")
    end)

    --------------------------------------------------------------------------
    -- Departure (#24)
    --------------------------------------------------------------------------

    T.Test("departure: out of a completed key offers World mode", function()
        local env = InInstanceMode(Boot())
        Enter(env, KEY, true)
        stub.Fire(env, "CHALLENGE_MODE_COMPLETED")
        Enter(env, WORLD, true)
        T.AssertTrue(Shown(env), "shown")
        T.AssertEqual(Dialog(env).title:GetText(), "Switch to World mode", "title")
        T.AssertTrue(Dialog(env).intro:GetText():find("^Left Ara%-Kara%. "), "reason")
    end)

    T.Test("departure: walking out mid-key is not a departure", function()
        local env = InInstanceMode(Boot())
        Enter(env, KEY, true)
        Enter(env, WORLD, true)
        T.AssertFalse(Shown(env), "no prompt")
        Enter(env, KEY, true)
        stub.Fire(env, "CHALLENGE_MODE_COMPLETED")
        Enter(env, WORLD, true)
        T.AssertTrue(Shown(env), "after completing it")
    end)

    T.Test("departure: out of a raid offers World mode; nothing outside Instance mode", function()
        local env = InInstanceMode(Boot())
        Enter(env, RAID, true)
        Enter(env, WORLD, true)
        T.AssertTrue(Shown(env), "out of a raid")

        local off = Boot()
        stub.Slash(off, "/km prompts arrival off")
        Enter(off, RAID, true)
        Enter(off, WORLD, true)
        T.AssertFalse(Shown(off), "Off: no departure")
    end)

    T.Test("departure: leaving the group in Instance mode offers World mode, once no group is left", function()
        local env = InInstanceMode(Boot())
        Enter(env, WORLD, true)
        env.fixtures.inGroup = true
        stub.Fire(env, "GROUP_JOINED", 1, "Party-1")
        stub.Fire(env, "GROUP_LEFT", 2, "Party-2") -- still in the home group
        T.AssertFalse(Shown(env), "still grouped")
        env.fixtures.inGroup = false
        stub.Fire(env, "GROUP_LEFT", 1, "Party-1")
        T.AssertTrue(Shown(env), "shown")
        T.AssertTrue(Dialog(env).intro:GetText():find("^Left the group%. "), "reason")
    end)

    --------------------------------------------------------------------------
    -- Group Finder (#23)
    --------------------------------------------------------------------------

    T.Test("group: joining a Mythic+ group offers Instance mode, naming the activity", function()
        local env = Boot()
        env.fixtures.lfg.activities[1] = { fullName = "Ara-Kara (Mythic Keystone)", categoryID = 2,
            isMythicPlusActivity = true }
        env.fixtures.lfg.searchResults[7] = { activityIDs = { 1 } }
        stub.Fire(env, "LFG_LIST_JOINED_GROUP", 7, "Pug")
        T.AssertTrue(Shown(env), "shown")
        T.AssertTrue(Dialog(env).intro:GetText():find("^Joined a Mythic%+ group: Ara%-Kara %(Mythic Keystone%)%. "),
            "reason")
    end)

    T.Test("group: listing a raid offers it on creation only; a Heroic dungeon never", function()
        local env = Boot()
        env.fixtures.lfg.activities[2] = { fullName = "Liberation of Undermine (Heroic)", categoryID = 3 }
        env.fixtures.lfg.activities[3] = { fullName = "Ara-Kara (Heroic)", categoryID = 2 }
        env.fixtures.lfg.activeEntry = { activityIDs = { 2 } }
        stub.Fire(env, "LFG_LIST_ACTIVE_ENTRY_UPDATE", nil)
        T.AssertFalse(Shown(env), "an edit is not a new listing")
        stub.Fire(env, "LFG_LIST_ACTIVE_ENTRY_UPDATE", true)
        T.AssertTrue(Shown(env), "shown")
        T.AssertTrue(Dialog(env).intro:GetText():find("^Listed a raid group: "), "reason")
        Close(env)

        local heroic = Boot()
        heroic.fixtures.lfg.activities[3] = { fullName = "Ara-Kara (Heroic)", categoryID = 2 }
        heroic.fixtures.lfg.searchResults[8] = { activityIDs = { 3 } }
        stub.Fire(heroic, "LFG_LIST_JOINED_GROUP", 8, "Pug")
        T.AssertFalse(Shown(heroic), "Heroic dungeon")
    end)

    T.Test("group: a lookup that errors or answers nothing is not a prompt and not an error", function()
        local env = Boot()
        env.C_LFGList.GetActivityInfoTable = function() error("secret value") end
        env.fixtures.lfg.searchResults[7] = { activityIDs = { 1 } }
        stub.Fire(env, "LFG_LIST_JOINED_GROUP", 7, "Pug")
        stub.Fire(env, "LFG_LIST_JOINED_GROUP", 99, "Gone")
        env.C_LFGList = nil
        stub.Fire(env, "LFG_LIST_JOINED_GROUP", 7, "Pug")
        stub.Fire(env, "LFG_LIST_ACTIVE_ENTRY_UPDATE", true)
        T.AssertFalse(Shown(env), "nothing shown")
    end)

    T.Test("/km debug probe lfg reports the instance, the group and the last group joined", function()
        local env = Boot()
        env.fixtures.lfg.activities[1] = { fullName = "Ara-Kara (Mythic Keystone)", categoryID = 2,
            difficultyID = 8, isMythicPlusActivity = true }
        env.fixtures.lfg.searchResults[7] = { activityIDs = { 1 } }
        stub.Fire(env, "LFG_LIST_JOINED_GROUP", 7, "Pug")
        Close(env)
        env.fixtures.instance = MYTHIC
        stub.TakeChat(env)
        stub.Slash(env, "/km debug probe lfg")
        local lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "Instance: Ara-Kara, type party, difficultyID 23"), "instance")
        T.AssertTrue(Has(lines, "Own listing: none"), "no listing")
        T.AssertTrue(Has(lines, "activity 1: Ara-Kara (Mythic Keystone), categoryID 2, difficultyID 8, "
            .. "isMythicPlusActivity true"), "joined activity")
    end)

    --------------------------------------------------------------------------
    -- Key binding (#26)
    --------------------------------------------------------------------------

    T.Test("key binding: Bindings.xml calls KeyMode_Toggle, which opens the toggle's dialog", function()
        local handle = assert(io.open("Bindings.xml", "r"))
        local xml = handle:read("*a")
        handle:close()
        T.AssertTrue(xml:find('name="KEYMODE_TOGGLE"', 1, true), "binding name")
        T.AssertTrue(xml:find('category="ADDONS"', 1, true), "AddOns category")
        T.AssertTrue(xml:find("KeyMode_Toggle()", 1, true), "calls the global")
        local env = Boot()
        T.AssertEqual(env.BINDING_HEADER_KEYMODE, "KeyMode", "header name")
        T.AssertEqual(type(env.BINDING_NAME_KEYMODE_TOGGLE), "string", "binding label")
        env.KeyMode_Toggle()
        T.AssertTrue(Shown(env), "dialog shown")
        T.AssertEqual(Dialog(env).title:GetText(), "Switch to Instance mode", "toggle target")
    end)
end
