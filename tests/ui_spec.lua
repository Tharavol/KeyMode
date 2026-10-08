-- ui_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Addon Compartment wiring. The TOC names three globals that the client calls by name,
-- so the test reads those names from the TOC itself: a renamed function with a stale
-- TOC line fails silently in-game (the entry just never appears), so it must fail here.

return function(stub, T)
    print("ui")

    local function TocField(field)
        local handle = assert(io.open("KeyMode.toc", "r"))
        local contents = handle:read("*a")
        handle:close()
        return contents:match("##%s*" .. field .. "%s*:%s*([%w_]+)")
    end

    T.Test("every compartment function the TOC names exists as a global", function()
        local env = stub.Boot()
        for _, field in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter",
                "AddonCompartmentFuncOnLeave" }) do
            local name = TocField(field)
            T.AssertTrue(name ~= nil, field .. " present in TOC")
            T.AssertEqual(type(env[name]), "function", field .. " -> " .. tostring(name))
        end
    end)

    T.Test("left click opens options, right click prints status", function()
        local env = stub.Boot()
        local click = env[TocField("AddonCompartmentFunc")]
        click("KeyMode", "LeftButton")
        T.AssertEqual(#env.fixtures.settingsOpened, 1, "left opened panel")
        click("KeyMode", "RightButton")
        T.AssertEqual(#env.fixtures.settingsOpened, 1, "right did not")
        T.AssertTrue(stub.TakeChat(env)[2]:find("Mode: Normal", 1, true), "status printed")
    end)

    T.Test("hover shows the mode in the tooltip", function()
        local env = stub.Boot()
        env[TocField("AddonCompartmentFuncOnEnter")]("KeyMode", {})
        local found = false
        for _, line in ipairs(env.GameTooltip._lines) do
            if line:find("Mode: Normal", 1, true) then found = true end
        end
        T.AssertTrue(found, "mode line")
        env[TocField("AddonCompartmentFuncOnLeave")]("KeyMode", {})
        T.AssertFalse(env.GameTooltip:IsShown(), "hidden on leave")
    end)
end
