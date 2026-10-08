-- UI.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Player-facing entry points and dialogs: the Addon Compartment entry (#4), and later
-- the preview dialog (#17), key binding and minimap button (#26).

local ADDON_NAME, ns = ...

local UI = {}
ns.UI = UI

--------------------------------------------------------------------------
-- Addon Compartment
--
-- The client reads `## AddonCompartmentFunc` / `FuncOnEnter` / `FuncOnLeave` from the
-- TOC and calls those globals by name: the click handler as (addonName, buttonName),
-- enter and leave as (addonName, menuButton). Source: Blizzard_Minimap/Mainline/
-- AddonCompartment.lua, AddonCompartmentMixin:RegisterAddons (Gethe/wow-ui-source, live).
--------------------------------------------------------------------------

-- Shared by the compartment entry and the minimap button so the two always do the same
-- thing. Left click opens the options panel; right click prints status. Once switching
-- exists (v0.3.0), left click becomes "toggle via the preview dialog".
function UI:OnEntryClick(buttonName)
    if buttonName == "RightButton" then
        ns.Commands:Dispatch("status")
    else
        ns.Options:Open()
    end
end

function UI:ShowEntryTooltip(owner, extraHint)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(ADDON_NAME)
    GameTooltip:AddLine("Mode: " .. (ns.Switch:IsActive() and "|cff00ff00Mythic+|r" or "Normal"), 1, 1, 1)
    GameTooltip:AddLine("Left-click: options", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: status", 0.6, 0.6, 0.6)
    if extraHint then GameTooltip:AddLine(extraHint, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

function KeyMode_OnAddonCompartmentClick(_, buttonName)
    UI:OnEntryClick(buttonName)
end

function KeyMode_OnAddonCompartmentEnter(_, menuButton)
    UI:ShowEntryTooltip(menuButton)
end

function KeyMode_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

--------------------------------------------------------------------------
-- Minimap button (#34)
--
-- Hand-made, no library. Layout values (31px button, 50px tracking border anchored
-- TOPLEFT, 24px background and 18px icon centred, highlight texture, 5px radius beyond
-- the minimap edge, MEDIUM strata at level 8) match LibDBIcon-1.0 MINOR 56's mainline
-- branch, so the button looks like every other minimap button and bars that reskin
-- them recognise its regions. The code is not taken from LibDBIcon.
--
-- HidingBar (v12.1.5, grabMinimapAddonsButtons) only collects a child of Minimap or
-- MinimapBackdrop that is named, unprotected, square, larger than 16px and under half
-- the minimap's size, with an OnClick script, and it scans one frame after its own
-- ADDON_LOADED. The button is therefore created at KeyMode's ADDON_LOADED, before the
-- first frame, and every one of those properties is pinned by ui_spec.lua.
--------------------------------------------------------------------------

local BUTTON_SIZE = 31
local EDGE_OFFSET = 5

local TEXTURE_BORDER = 136430     -- Interface\Minimap\MiniMap-TrackingBorder
local TEXTURE_BACKGROUND = 136467 -- Interface\Minimap\UI-Minimap-Background
local TEXTURE_HIGHLIGHT = 136477  -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

-- Whether the minimap is rounded in the quadrant the button sits in. GetMinimapShape is
-- defined by minimap-reshaping addons, not by the base client; absent means ROUND.
-- Shape names describe which quadrants are round: CORNER-<corner> rounds that one,
-- SIDE-<side> the two on that side, TRICORNER-<corner> every one except the opposite.
local function IsRoundQuadrant(shape, top, left)
    if shape == "ROUND" then return true end
    if shape == "SQUARE" then return false end
    local kind, where = shape:match("^(%u+)%-(%u+)$")
    if not kind then return true end
    local vertical = where:match("^TOP") and "top" or where:match("^BOTTOM") and "bottom"
    local horizontal = where:match("LEFT$") and "left" or where:match("RIGHT$") and "right"
    local isTop, isLeft = top, left
    if kind == "SIDE" then
        if where == "TOP" then return isTop end
        if where == "BOTTOM" then return not isTop end
        if where == "LEFT" then return isLeft end
        if where == "RIGHT" then return not isLeft end
        return true
    end
    local matchesCorner = ((vertical == "top") == isTop) and ((horizontal == "left") == isLeft)
    if kind == "CORNER" then return matchesCorner end
    if kind == "TRICORNER" then
        local opposite = ((vertical == "top") ~= isTop) and ((horizontal == "left") ~= isLeft)
        return not opposite
    end
    return true
end
UI.IsRoundQuadrant = IsRoundQuadrant

-- Offset from the minimap's centre for a button at `angle` degrees. On a round edge the
-- button follows the circle; on a square edge it is pushed out along a diagonal 10px
-- short of the corner and clamped to the side, so it runs along the edge and rounds the
-- corner slightly inside it rather than overhanging.
function UI.MinimapOffset(angle, width, height, shape)
    local radians = math.rad(angle)
    local x, y = math.cos(radians), math.sin(radians)
    local w, h = width / 2 + EDGE_OFFSET, height / 2 + EDGE_OFFSET
    if IsRoundQuadrant(shape or "ROUND", y > 0, x < 0) then
        return x * w, y * h
    end
    local diagonalW = math.sqrt(2 * w * w) - 10
    local diagonalH = math.sqrt(2 * h * h) - 10
    return math.max(-w, math.min(x * diagonalW, w)), math.max(-h, math.min(y * diagonalH, h))
end

function UI:PositionMinimapButton()
    local button = self.minimapButton
    if not button then return end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local x, y = UI.MinimapOffset(ns.db.settings.minimapAngle, Minimap:GetWidth(), Minimap:GetHeight(), shape)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Angle of the cursor around the minimap's centre, 0-360, counter-clockwise from the
-- right edge. Cursor coordinates are in screen pixels, the minimap's in its own scale.
local function CursorAngle()
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    return math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)) % 360
end
UI.CursorAngle = CursorAngle

local function OnDragUpdate()
    ns.db.settings.minimapAngle = CursorAngle()
    UI:PositionMinimapButton()
end

function UI:CreateMinimapButton()
    if self.minimapButton or not Minimap then return end
    local button = CreateFrame("Button", "KeyModeMinimapButton", Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(TEXTURE_HIGHLIGHT)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetTexture(TEXTURE_BORDER)
    border:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetTexture(TEXTURE_BACKGROUND)
    background:SetPoint("CENTER")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(C_AddOns.GetAddOnMetadata(ADDON_NAME, "IconTexture"))
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) -- trim the icon's own frame
    icon:SetPoint("CENTER")
    button.icon = icon

    button:SetScript("OnClick", function(_, mouseButton) UI:OnEntryClick(mouseButton) end)
    button:SetScript("OnEnter", function(btn) UI:ShowEntryTooltip(btn, "Drag: move") end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(btn)
        btn:LockHighlight()
        GameTooltip:Hide()
        btn:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(btn)
        btn:SetScript("OnUpdate", nil)
        btn:UnlockHighlight()
    end)

    self.minimapButton = button
    self:UpdateMinimapButton()
end

function UI:UpdateMinimapButton()
    local button = self.minimapButton
    if not button then return end
    self:PositionMinimapButton()
    if ns.db.settings.minimapButton then button:Show() else button:Hide() end
end

ns.OnLoaded(function() UI:CreateMinimapButton() end)
ns.OnSettingsChanged(function() UI:UpdateMinimapButton() end)

-- Minimap-reshaping addons may define GetMinimapShape after KeyMode loads; position
-- again once everything has, so a square minimap doesn't keep a round-edge placement.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    UI:UpdateMinimapButton()
end)
