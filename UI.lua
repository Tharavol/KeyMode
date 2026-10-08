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

-- Left click opens the options panel; right click prints status. Once switching exists
-- (v0.3.0), left click becomes "toggle via the preview dialog".
function UI:OnCompartmentClick(buttonName)
    if buttonName == "RightButton" then
        ns.Commands:Dispatch("status")
    else
        ns.Options:Open()
    end
end

function UI:ShowCompartmentTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(ADDON_NAME)
    GameTooltip:AddLine("Mode: " .. (ns.Switch:IsActive() and "|cff00ff00Mythic+|r" or "Normal"), 1, 1, 1)
    GameTooltip:AddLine("Left-click: options", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: status", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function KeyMode_OnAddonCompartmentClick(_, buttonName)
    UI:OnCompartmentClick(buttonName)
end

function KeyMode_OnAddonCompartmentEnter(_, menuButton)
    UI:ShowCompartmentTooltip(menuButton)
end

function KeyMode_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
