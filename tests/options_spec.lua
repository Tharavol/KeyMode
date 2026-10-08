-- options_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Options panel wiring: registration, opening, checkbox <-> DB round trip, and the reset
-- button sharing ns.ResetSettings with /km reset. Layout is not checked here -- the stub
-- has no geometry -- and needs an in-game look (#3).

return function(stub, T)
    print("options")

    T.Test("panel registers one AddOns category named KeyMode", function()
        local env = stub.Boot()
        T.AssertTrue(env.fixtures.registeredCategory ~= nil, "registered")
        T.AssertEqual(env.fixtures.registeredCategory.name, "KeyMode")
    end)

    T.Test("Open goes to this panel's category", function()
        local env = stub.Boot()
        env.ns.Options:Open()
        T.AssertEqual(env.fixtures.settingsOpened[1], env.fixtures.category:GetID())
    end)

    T.Test("showing the panel reflects saved settings", function()
        local env = stub.Load(function(e) e.KeyModeDB = { settings = { debug = true } } end)
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        local panel = env.ns.Options.panel
        panel:GetScript("OnShow")(panel)
        T.AssertTrue(panel.checkboxes[1]:GetChecked(), "debug checkbox checked")
        T.AssertTrue(panel.statusText:GetText():find("Normal", 1, true), "mode line")
    end)

    T.Test("clicking a checkbox writes the setting", function()
        local env = stub.Boot()
        local checkbox = env.ns.Options.panel.checkboxes[1]
        checkbox:SetChecked(true)
        checkbox:Click()
        T.AssertEqual(env.KeyModeDB.settings.debug, true)
    end)

    T.Test("reset restores settings but keeps profiles and snapshots", function()
        local env = stub.Boot()
        env.KeyModeDB.settings.debug = true
        env.KeyModeDB.profiles.Keys = { disable = { TomTom = true } }
        env.KeyModeDB.snapshots["Player-1"] = { state = {} }
        env.ns.Options.panel.resetButton:Click()
        T.AssertEqual(env.KeyModeDB.settings.debug, false, "debug reset")
        T.AssertTrue(env.KeyModeDB.profiles.Keys ~= nil, "profile kept")
        T.AssertTrue(env.KeyModeDB.snapshots["Player-1"] ~= nil, "snapshot kept")
        T.AssertFalse(env.ns.Options.panel.checkboxes[1]:GetChecked(), "panel refreshed")
    end)

    T.Test("a missing checkbox template falls back instead of erroring", function()
        local env = stub.Load(function(e)
            local real = e.CreateFrame
            e.CreateFrame = function(kind, name, parent, template)
                if template == "UICheckButtonTemplate" then error("unknown template") end
                return real(kind, name, parent, template)
            end
        end)
        T.AssertEqual(#env.ns.Options.panel.checkboxes, 1, "checkbox still created")
        T.AssertTrue(env.ns.Options.panel.resetButton ~= nil, "rest of the panel built")
    end)
end
