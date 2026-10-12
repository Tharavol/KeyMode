-- switch_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The switch engine end to end (#11, #12, #14, #15, #16): schema migration, the baseline
-- snapshot, Instance/World/Off through the real commands, a simulated reload after each
-- switch, the login check and the recovery reminder.

return function(stub, T)
    print("switch")

    local OTHER = "Player-5678-0FEDCBA9"

    local function Boot(configure)
        return stub.Boot(function(env, fixtures)
            local add = stub.AddAddon
            add(fixtures, "DataStore")
            add(fixtures, "DataStore_Containers", { deps = { "DataStore" } })
            add(fixtures, "AddonFactory", { deps = { "DataStore" } })
            add(fixtures, "DBM-StatusBarTimers")
            add(fixtures, "DBM-Core", { deps = { "DBM-StatusBarTimers" } })
            add(fixtures, "DBM-Raids-Midnight", { deps = { "DBM-Core" }, loadOnDemand = true })
            add(fixtures, "Details")
            add(fixtures, "TomTom")
            add(fixtures, "!BugGrabber")
            add(fixtures, "BugSack", { deps = { "!BugGrabber" } })
            add(fixtures, "OffHere", { enabled = false })
            add(fixtures, "AltOnly", { enabledFor = { [OTHER] = true } })
            if configure then configure(env, fixtures) end
        end)
    end

    -- Every installed addon's state for `guid` (default: the player), "name=0|1" joined.
    local function State(env, guid)
        guid = guid or env.fixtures.player.guid
        local parts = {}
        for _, entry in ipairs(env.fixtures.addons) do
            parts[#parts + 1] = entry.name .. "=" .. (entry.enabledFor[guid] and 1 or 0)
        end
        return table.concat(parts, " ")
    end

    local function On(env, name)
        for _, entry in ipairs(env.fixtures.addons) do
            if entry.name == name then return entry.enabledFor[env.fixtures.player.guid] and true or false end
        end
    end

    local function SetOn(env, name, value)
        for _, entry in ipairs(env.fixtures.addons) do
            if entry.name == name then entry.enabledFor[env.fixtures.player.guid] = value end
        end
    end

    local function Has(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return true end
        end
        return false
    end

    -- A mode command as the player gives it: the command opens the preview dialog (#17),
    -- then Confirm and Reload. A refusal or a no-op switch opens no dialog.
    local function Go(env, line)
        local dialog = env.ns.UI.dialog
        if dialog then dialog:Hide() end
        stub.Slash(env, line)
        dialog = env.ns.UI.dialog
        if dialog and dialog:IsShown() then dialog.confirmButton:Click() end
    end

    local function Instance(env)
        stub.Slash(env, "/km list instance add DataStore")
        stub.Slash(env, "/km list instance add DBM-StatusBarTimers")
        stub.Slash(env, "/km list instance add TomTom")
        stub.TakeChat(env)
    end

    --------------------------------------------------------------------------
    -- Schema (#11)
    --------------------------------------------------------------------------

    T.Test("a v0.2.0 DB migrates to the current version: profiles dropped, lists added, rest kept", function()
        local env = stub.Load(function(e)
            e.KeyModeDB = { dbVersion = 1, profiles = {}, protected = { BugSack = false },
                settings = { debug = true } }
        end)
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        T.AssertEqual(env.KeyModeDB.dbVersion, 3, "version")
        T.AssertEqual(env.KeyModeDB.profiles, nil, "profiles dropped")
        T.AssertEqual(type(env.KeyModeDB.lists.instance), "table", "lists")
        T.AssertEqual(env.KeyModeDB.protected.BugSack, false, "protect list kept")
        T.AssertEqual(env.KeyModeDB.settings.debug, true, "settings kept")
    end)

    T.Test("the v0.3.0 BugGrabber protect entry moves to the real folder name, !BugGrabber", function()
        local env = stub.Load(function(e)
            e.KeyModeDB = { dbVersion = 2, protected = { BugGrabber = true, BugSack = true } }
        end)
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        T.AssertEqual(env.KeyModeDB.protected.BugGrabber, nil, "old name gone")
        T.AssertEqual(env.KeyModeDB.protected["!BugGrabber"], true, "new name protected")
        local removed = stub.Load(function(e)
            e.KeyModeDB = { dbVersion = 2, protected = { BugGrabber = false, BugSack = true } }
        end)
        stub.Fire(removed, "ADDON_LOADED", "KeyMode")
        T.AssertEqual(removed.KeyModeDB.protected["!BugGrabber"], false, "a removed default stays removed")
    end)

    T.Test("a DB from a newer version is not downgraded", function()
        local env = stub.Load(function(e) e.KeyModeDB = { dbVersion = 99 } end)
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        T.AssertEqual(env.KeyModeDB.dbVersion, 99)
    end)

    --------------------------------------------------------------------------
    -- Enter and exit (#12, #14)
    --------------------------------------------------------------------------

    T.Test("instance: baseline taken, plan applied by GUID, saved, then reloaded", function()
        local env = Boot()
        local before = State(env)
        Instance(env)
        Go(env, "/km instance")
        local snapshot = env.KeyModeDB.snapshots[env.fixtures.player.guid]
        T.AssertEqual(snapshot.mode, "instance", "mode")
        T.AssertEqual(snapshot.state.TomTom, true, "baseline is the state before the switch")
        T.AssertEqual(snapshot.state.OffHere, false, "including what was off")
        local calls = env.fixtures.calls
        for i = 1, #calls - 1 do
            T.AssertEqual(calls[i][1], "DisableAddOn", "only disables")
            T.AssertEqual(calls[i][3], env.fixtures.player.guid, "by GUID")
        end
        T.AssertEqual(calls[#calls][1], "SaveAddOns", "saved last")
        T.AssertEqual(env.fixtures.reloads, 1, "reloaded")
        T.AssertFalse(On(env, "AddonFactory"), "DataStore takes AddonFactory")
        T.AssertFalse(On(env, "DBM-Raids-Midnight"), "DBM-StatusBarTimers takes DBM-Core and modules")
        T.AssertTrue(On(env, "BugSack") and On(env, "Details"), "the rest stays on")
        T.AssertTrue(before ~= State(env), "state changed")

        env = stub.Reload(env)
        local lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "Now in Instance mode."), "confirmed after the reload")
        T.AssertFalse(Has(lines, "by hand"), "nothing folded")
        T.AssertFalse(Has(lines, "but they are on"), "nothing stray")
    end)

    T.Test("instance -> world -> off restores the baseline exactly", function()
        local env = Boot()
        local before = State(env)
        Instance(env)
        stub.Slash(env, "/km list world add Details")
        stub.Slash(env, "/km list world add DBM-Raids-Midnight")
        Go(env, "/km instance")
        env = stub.Reload(env)
        Go(env, "/km world")
        env = stub.Reload(env)
        T.AssertTrue(On(env, "TomTom") and On(env, "DataStore") and On(env, "DBM-Core"), "instance list back on")
        T.AssertFalse(On(env, "Details"), "world list off")
        T.AssertFalse(On(env, "DBM-Raids-Midnight"), "world list off")
        Go(env, "/km off")
        env = stub.Reload(env)
        T.AssertEqual(State(env), before, "exact restore")
        T.AssertEqual(env.KeyModeDB.snapshots[env.fixtures.player.guid], nil, "snapshot deleted")
        T.AssertEqual(env.KeyModeDB.switched, nil, "no pending notice left")
        T.AssertTrue(Has(stub.TakeChat(env), "Now in Off mode."), "confirmed")
    end)

    T.Test("world -> instance turns world-listed addons back on unless instance-listed", function()
        local env = Boot()
        stub.Slash(env, "/km list world add Details")
        stub.Slash(env, "/km list world add TomTom")
        stub.Slash(env, "/km list instance add TomTom")
        Go(env, "/km world")
        env = stub.Reload(env)
        Go(env, "/km instance")
        T.AssertTrue(On(env, "Details"), "back on in an instance")
        T.AssertFalse(On(env, "TomTom"), "on both lists, stays off")
    end)

    T.Test("another character's enable state is never touched", function()
        local env = Boot()
        local other = State(env, OTHER)
        Instance(env)
        Go(env, "/km instance")
        env = stub.Reload(env)
        Go(env, "/km off")
        T.AssertEqual(State(env, OTHER), other, "unchanged")
    end)

    T.Test("the guard blocks a switch and says why", function()
        local env = Boot()
        Instance(env)
        env.fixtures.inCombat = true
        Go(env, "/km instance")
        T.AssertTrue(stub.TakeChat(env)[1]:find("Cannot switch now: in combat.", 1, true), "reason")
        T.AssertEqual(#env.fixtures.calls, 0, "nothing changed")
        T.AssertEqual(env.KeyModeDB.snapshots[env.fixtures.player.guid], nil, "no baseline taken")
    end)

    T.Test("same mode and off while unmanaged are refused", function()
        local env = Boot()
        Go(env, "/km off")
        T.AssertTrue(stub.TakeChat(env)[1]:find("not managing", 1, true), "off unmanaged")
        Instance(env)
        Go(env, "/km instance")
        env = stub.Reload(env)
        stub.TakeChat(env)
        Go(env, "/km instance")
        T.AssertTrue(stub.TakeChat(env)[1]:find("Already in Instance mode.", 1, true), "same mode")
        T.AssertEqual(env.fixtures.reloads, 1, "no second reload")
    end)

    T.Test("a switch with nothing to change records the mode without a reload", function()
        local env = Boot()
        Go(env, "/km world")
        T.AssertTrue(stub.TakeChat(env)[1]:find("nothing to change", 1, true), "said so")
        T.AssertEqual(env.fixtures.reloads, 0, "no reload")
        T.AssertEqual(env.ns.Switch:Mode(), "world", "now managed")
    end)

    T.Test("toggle goes off -> instance -> world -> instance", function()
        local env = Boot()
        Instance(env)
        Go(env, "/km toggle")
        T.AssertEqual(env.ns.Switch:Mode(), "instance", "from off")
        env = stub.Reload(env)
        Go(env, "/km toggle")
        T.AssertEqual(env.ns.Switch:Mode(), "world", "from instance")
        env = stub.Reload(env)
        Go(env, "/km toggle")
        T.AssertEqual(env.ns.Switch:Mode(), "instance", "from world")
    end)

    T.Test("an addon removed since the baseline is skipped and reported on off", function()
        local env = Boot()
        Instance(env)
        Go(env, "/km instance")
        env = stub.Reload(env)
        table.remove(env.fixtures.addons) -- AltOnly
        env.KeyModeDB.snapshots[env.fixtures.player.guid].state.AltOnly = true
        stub.TakeChat(env)
        Go(env, "/km off")
        T.AssertTrue(Has(stub.TakeChat(env), "AltOnly was part of this character's setup but is no longer installed"),
            "reported")
    end)

    --------------------------------------------------------------------------
    -- Login check (#14) and recovery (#15)
    --------------------------------------------------------------------------

    T.Test("a hand change to an unlisted addon is folded into the baseline", function()
        local env = Boot()
        Instance(env)
        Go(env, "/km instance")
        env = stub.Reload(env)
        SetOn(env, "Details", false) -- turned off in the game's AddOn list
        SetOn(env, "OffHere", true)  -- turned on there
        env = stub.Reload(env)
        local lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "Changed by hand since the last switch, kept on Off: Details, OffHere."), "said so")
        local state = env.KeyModeDB.snapshots[env.fixtures.player.guid].state
        T.AssertEqual(state.Details, false, "folded off")
        T.AssertEqual(state.OffHere, true, "folded on")
        Go(env, "/km off")
        T.AssertFalse(On(env, "Details"), "off does not undo it")
        T.AssertTrue(On(env, "OffHere"), "off does not undo it")
    end)

    T.Test("a listed addon turned back on is reported, not folded", function()
        local env = Boot()
        Instance(env)
        Go(env, "/km instance")
        env = stub.Reload(env)
        SetOn(env, "TomTom", true)
        env = stub.Reload(env)
        T.AssertTrue(Has(stub.TakeChat(env), "Instance mode turns these off, but they are on: TomTom. /km instance"),
            "reported")
        T.AssertEqual(env.KeyModeDB.snapshots[env.fixtures.player.guid].state.TomTom, true, "baseline unchanged")
    end)

    T.Test("Instance mode outside an instance and a group prints the way back", function()
        local env = Boot()
        Instance(env)
        Go(env, "/km instance")
        env = stub.Reload(env)
        T.AssertTrue(Has(stub.TakeChat(env), "Still in Instance mode. /km world or /km off"), "reminder")
        env.fixtures.inInstance = true
        env = stub.Reload(env)
        T.AssertFalse(Has(stub.TakeChat(env), "Still in Instance mode"), "not inside an instance")
        env.fixtures.inInstance, env.fixtures.inGroup = false, true
        env = stub.Reload(env)
        T.AssertFalse(Has(stub.TakeChat(env), "Still in Instance mode"), "not in a group")
    end)

    T.Test("an unmanaged character's login prints nothing", function()
        local env = Boot()
        env = stub.Reload(env)
        T.AssertEqual(#stub.TakeChat(env), 0, "silent")
    end)

    --------------------------------------------------------------------------
    -- Commands (#16)
    --------------------------------------------------------------------------

    T.Test("list add, show and remove, case-insensitive, with a not-installed warning", function()
        local env = Boot()
        stub.Slash(env, "/km list instance add Details")
        stub.Slash(env, "/km list instance add DETAILS")
        stub.Slash(env, "/km list instance add NotHere")
        local lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "Details added to the Instance list."), "added")
        T.AssertTrue(Has(lines, "(NotHere is not installed on this character.)"), "warned")
        stub.Slash(env, "/km list instance")
        T.AssertTrue(stub.TakeChat(env)[1]:find("Instance list (2): Details, NotHere", 1, true), "one spelling")
        stub.Slash(env, "/km list instance remove details")
        stub.Slash(env, "/km list instance remove details")
        lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "details removed from the Instance list."), "removed")
        T.AssertTrue(Has(lines, "details is not on the instance list."), "second remove refused")
        stub.Slash(env, "/km list")
        lines = stub.TakeChat(env)
        T.AssertTrue(Has(lines, "Instance list (1): NotHere") and Has(lines, "World list (0): empty"), "both")
        stub.Slash(env, "/km list instance add KeyMode")
        T.AssertTrue(Has(stub.TakeChat(env), "KeyMode is always protected."), "KeyMode refused")
    end)

    T.Test("protect add and remove", function()
        local env = Boot()
        stub.Slash(env, "/km protect add Details")
        stub.Slash(env, "/km protect remove BugSack")
        stub.Slash(env, "/km protect")
        T.AssertTrue(Has(stub.TakeChat(env), "Protected: !BugGrabber, Details, KeyMode"), "listed")
    end)

    T.Test("the preview dialog: title, sections, Cancel changes nothing, Escape closes it", function()
        local env = Boot()
        Instance(env)
        stub.Slash(env, "/km protect add DBM-Core")
        stub.Slash(env, "/km instance")
        local dialog = env.ns.UI.dialog
        T.AssertTrue(dialog:IsShown(), "opened")
        T.AssertEqual(dialog.title:GetText(), "Switch to Instance mode", "title")
        local text = dialog.body:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        T.AssertTrue(text:find("Will turn off (4)\nDataStore, TomTom\n"
            .. "Because they require one of those: AddonFactory, DataStore_Containers", 1, true), "turn off")
        T.AssertTrue(text:find("Kept on (protected, or needed by a protected addon)\n"
            .. "DBM-Core, DBM-StatusBarTimers", 1, true), "kept")
        T.AssertEqual(#env.fixtures.calls, 0, "nothing changed while open")
        dialog.cancelButton:Click()
        T.AssertFalse(dialog:IsShown(), "cancel closes")
        T.AssertEqual(#env.fixtures.calls, 0, "cancel changes nothing")
        T.AssertEqual(env.ns.Switch:Mode(), "off", "still off")
        local escapable = false
        for _, name in ipairs(env.UISpecialFrames) do
            if name == "KeyModePreviewDialog" then escapable = true end
        end
        T.AssertTrue(escapable, "Escape closes it")
    end)

    T.Test("Confirm re-runs the guard: combat after opening blocks the switch", function()
        local env = Boot()
        Instance(env)
        stub.Slash(env, "/km instance")
        env.fixtures.inCombat = true
        env.ns.UI.dialog.confirmButton:Click()
        T.AssertTrue(Has(stub.TakeChat(env), "Cannot switch now: in combat."), "said why")
        T.AssertEqual(env.fixtures.reloads, 0, "no reload")
        T.AssertEqual(#env.fixtures.calls, 0, "nothing changed")
    end)

    T.Test("preview prints the plan and changes nothing", function()
        local env = Boot()
        Instance(env)
        stub.Slash(env, "/km protect add DBM-Core")
        stub.Slash(env, "/km list instance add Gone")
        stub.TakeChat(env)
        stub.Slash(env, "/km preview instance")
        local lines = stub.TakeChat(env)
        T.AssertTrue(lines[1]:find("Preview of Instance mode (now Off):", 1, true), "heading")
        T.AssertTrue(Has(lines, "Turns off (4): DataStore, TomTom; because they require one of those: "
            .. "AddonFactory, DataStore_Containers"), "listed then cascade")
        T.AssertTrue(Has(lines, "Kept on, protected or needed by a protected addon: "
            .. "DBM-Core, DBM-StatusBarTimers"), "kept")
        T.AssertTrue(Has(lines, "On the list but not installed here: Gone"), "unknown")
        T.AssertEqual(#env.fixtures.calls, 0, "no change")
        T.AssertEqual(env.KeyModeDB.snapshots[env.fixtures.player.guid], nil, "no baseline")
        stub.Slash(env, "/km preview world")
        T.AssertTrue(Has(stub.TakeChat(env), "Nothing to change."), "empty world list")
        stub.Slash(env, "/km preview raid")
        T.AssertTrue(stub.TakeChat(env)[1]:find("expected 'instance', 'world' or 'off'", 1, true), "rejected")
    end)
end
