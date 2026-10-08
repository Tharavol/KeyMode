-- minimap_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The minimap button (#34). Two external contracts are pinned here, because breaking
-- either fails silently in-game:
--   * HidingBar v12.1.5 only collects buttons meeting its grabMinimapAddonsButtons /
--     addMButton criteria -- miss one and the button just never appears in its bar.
--   * Minimap-shape addons publish GetMinimapShape names whose per-quadrant meaning
--     comes from LibDBIcon-1.0's minimapShapes table (MINOR 56); the table below is that
--     data, used only to check KeyMode's own rule against it.

return function(stub, T)
    print("minimap")

    local function Near(actual, expected, msg)
        if math.abs(actual - expected) > 0.01 then
            error(string.format("%s: expected %.2f, got %.2f", msg, expected, actual), 2)
        end
    end

    local function Button(env) return env.ns.UI.minimapButton end

    T.Test("button meets every HidingBar collection criterion at ADDON_LOADED", function()
        local env = stub.Boot()
        local button = Button(env)
        T.AssertTrue(button ~= nil, "created by the end of ADDON_LOADED")
        T.AssertEqual(button:GetName(), "KeyModeMinimapButton", "named")
        T.AssertTrue(button:GetParent() == env.Minimap, "direct child of Minimap")
        local width, height = button:GetSize()
        local mapWidth, mapHeight = env.Minimap:GetSize()
        T.AssertTrue(math.abs(width - height) < 5, "square")
        T.AssertTrue(math.max(width, height) > 16, "larger than 16px")
        T.AssertTrue(width < mapWidth / 2 and height < mapHeight / 2, "under half the minimap")
        T.AssertFalse(button:IsProtected(), "unprotected")
        T.AssertEqual(type(button:GetScript("OnClick")), "function", "has OnClick")
    end)

    T.Test("button uses the border and background textures bars recognise", function()
        local env = stub.Boot()
        local textures = {}
        for _, child in ipairs(Button(env)._children) do
            if child:GetTexture() then textures[child:GetTexture()] = true end
        end
        T.AssertTrue(textures[136430], "MiniMap-TrackingBorder")
        T.AssertTrue(textures[136467], "UI-Minimap-Background")
        T.AssertTrue(textures["Interface\\Icons\\INV_Relics_Hourglass"], "icon from the TOC")
    end)

    T.Test("clicks do what the compartment entry does", function()
        local env = stub.Boot()
        Button(env):Click("LeftButton")
        T.AssertEqual(#env.fixtures.settingsOpened, 1, "left opens options")
        Button(env):Click("RightButton")
        T.AssertTrue(stub.TakeChat(env)[2]:find("Mode: Normal", 1, true), "right prints status")
    end)

    T.Test("shown by default; /km minimap toggles and the checkbox follows", function()
        local env = stub.Boot()
        local panel = env.ns.Options.panel
        T.AssertTrue(Button(env):IsShown(), "shown by default")
        stub.Slash(env, "/km minimap")
        T.AssertFalse(Button(env):IsShown(), "hidden")
        T.AssertEqual(env.KeyModeDB.settings.minimapButton, false, "saved")
        T.AssertFalse(panel.checkboxes[2]:GetChecked(), "checkbox refreshed")
        stub.Slash(env, "/km minimap on")
        T.AssertTrue(Button(env):IsShown(), "shown again")
        stub.Slash(env, "/km minimap sideways")
        T.AssertTrue(Button(env):IsShown(), "bad value rejected, state unchanged")
    end)

    T.Test("options checkbox hides and shows the button", function()
        local env = stub.Boot()
        local checkbox = env.ns.Options.panel.checkboxes[2]
        T.AssertEqual(checkbox.definition.key, "minimapButton")
        checkbox:SetChecked(false)
        checkbox:Click()
        T.AssertFalse(Button(env):IsShown(), "hidden by checkbox")
    end)

    T.Test("saved setting off: created hidden", function()
        local env = stub.Load(function(e) e.KeyModeDB = { settings = { minimapButton = false } } end)
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        T.AssertTrue(Button(env) ~= nil, "still created, so it can be shown later")
        T.AssertFalse(Button(env):IsShown(), "hidden")
    end)

    T.Test("round edge: the button follows the circle 5px outside the minimap", function()
        local env = stub.Boot()
        local offset = env.ns.UI.MinimapOffset
        local x, y = offset(0, 140, 140)
        Near(x, 75, "0 deg x"); Near(y, 0, "0 deg y")
        x, y = offset(90, 140, 140)
        Near(x, 0, "90 deg x"); Near(y, 75, "90 deg y")
        x, y = offset(225, 140, 140)
        Near(x, -75 * math.sqrt(0.5), "225 deg x"); Near(y, -75 * math.sqrt(0.5), "225 deg y")
    end)

    T.Test("square edge: pushed along the diagonal and clamped to the side", function()
        local env = stub.Boot()
        -- The diagonal stops 10px short of the corner, so 45 deg sits just inside it.
        local inset = (math.sqrt(2) * 75 - 10) * math.sqrt(0.5)
        local x, y = env.ns.UI.MinimapOffset(45, 140, 140, "SQUARE")
        Near(x, inset, "corner x"); Near(y, inset, "corner y")
        x, y = env.ns.UI.MinimapOffset(0, 140, 140, "SQUARE")
        Near(x, 75, "side x clamped to the edge"); Near(y, 0, "side y")
        x, y = env.ns.UI.MinimapOffset(20, 140, 140, "SQUARE")
        Near(x, 75, "near-side x clamped"); T.AssertTrue(y > 0 and y < 75, "near-side y on the edge")
    end)

    T.Test("every GetMinimapShape name rounds the same quadrants LibDBIcon does", function()
        -- Quadrant order as LibDBIcon numbers them: 1 bottom-right, 2 bottom-left,
        -- 3 top-right, 4 top-left.
        local shapes = {
            ["ROUND"] = { true, true, true, true },
            ["SQUARE"] = { false, false, false, false },
            ["CORNER-TOPLEFT"] = { false, false, false, true },
            ["CORNER-TOPRIGHT"] = { false, false, true, false },
            ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
            ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
            ["SIDE-LEFT"] = { false, true, false, true },
            ["SIDE-RIGHT"] = { true, false, true, false },
            ["SIDE-TOP"] = { false, false, true, true },
            ["SIDE-BOTTOM"] = { true, true, false, false },
            ["TRICORNER-TOPLEFT"] = { false, true, true, true },
            ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
            ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
            ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
        }
        local quadrants = { { false, false }, { false, true }, { true, false }, { true, true } }
        local env = stub.Boot()
        for shape, expected in pairs(shapes) do
            for q, topLeft in ipairs(quadrants) do
                T.AssertEqual(env.ns.UI.IsRoundQuadrant(shape, topLeft[1], topLeft[2]), expected[q],
                    shape .. " quadrant " .. q)
            end
        end
    end)

    T.Test("a reshaped minimap is honoured when the button is placed", function()
        local env = stub.Load(function(_, fixtures) fixtures.minimapShape = "SQUARE" end)
        stub.Fire(env, "ADDON_LOADED", "KeyMode")
        env.KeyModeDB.settings.minimapAngle = 0
        env.ns.UI:PositionMinimapButton()
        local point = Button(env)._point
        Near(point[4], 75, "x on the square edge")
        Near(point[5], 0, "y")
        env.KeyModeDB.settings.minimapAngle = 45
        env.ns.UI:PositionMinimapButton()
        local inset = (math.sqrt(2) * 75 - 10) * math.sqrt(0.5)
        Near(Button(env)._point[4], inset, "square diagonal, not the 53px round-edge x")
    end)

    T.Test("dragging saves the cursor's angle and moves the button", function()
        local env = stub.Boot()
        local button = Button(env)
        env.fixtures.cursor = { x = 1000, y = 700 } -- straight above the minimap centre
        button:GetScript("OnDragStart")(button)
        button:GetScript("OnUpdate")(button)
        Near(env.KeyModeDB.settings.minimapAngle, 90, "angle")
        Near(button._point[4], 0, "x"); Near(button._point[5], 75, "y")
        button:GetScript("OnDragStop")(button)
        T.AssertEqual(button:GetScript("OnUpdate"), nil, "stops following the cursor")
    end)

    T.Test("cursor angle accounts for the minimap's scale", function()
        local env = stub.Boot()
        env.fixtures.minimapScale = 2
        env.fixtures.cursor = { x = 2000, y = 1000 } -- (1000, 500) in minimap space: straight below
        Near(env.ns.UI.CursorAngle(), 270, "angle at scale 2")
    end)

    T.Test("reset restores the default angle and visibility", function()
        local env = stub.Boot()
        env.KeyModeDB.settings.minimapAngle = 10
        env.KeyModeDB.settings.minimapButton = false
        stub.Slash(env, "/km reset")
        T.AssertEqual(env.KeyModeDB.settings.minimapAngle, 225, "angle")
        T.AssertTrue(Button(env):IsShown(), "shown")
        local x = env.ns.UI.MinimapOffset(225, 140, 140)
        Near(Button(env)._point[4], x, "repositioned")
    end)
end
