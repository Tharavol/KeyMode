-- UI.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Player-facing entry points and dialogs: the Addon Compartment entry (#4), the minimap
-- button (#34) and the preview dialog (#17); later the key binding.

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
-- thing. Left click opens the preview dialog for a toggle (#17); right click opens the
-- options panel. The tooltip shows the mode, so status needs no click of its own.
function UI:OnEntryClick(buttonName)
    if buttonName == "RightButton" then
        ns.Options:Open()
    else
        self:Preview(ns.Switch:ToggleTarget())
    end
end

function UI:ShowEntryTooltip(owner, extraHint)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(ADDON_NAME)
    GameTooltip:AddLine("Mode: " .. ns.Switch:ModeLabel(), 1, 1, 1)
    GameTooltip:AddLine("Left-click: switch to " .. ns.Switch.MODES[ns.Switch:ToggleTarget()] .. " mode",
        0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: options", 0.6, 0.6, 0.6)
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

--------------------------------------------------------------------------
-- Preview dialog (#17)
--
-- Every switch path opens this before anything changes: the mode commands, the minimap
-- button and the compartment entry. It shows the plan for the target mode and switches
-- only on Confirm and Reload, which re-runs the guard (Switch:Apply), since combat or a
-- key can start while the dialog is open. Templates were checked against the live
-- client source (docs/HANDOFF.md "UI templates for v0.4.0").
--------------------------------------------------------------------------

local GOLD, GREY, CLOSE = "|cffffd200", "|cff999999", "|r"

local function Joined(names) return table.concat(names, ", ") end

-- The dialog's body as sections, from a plan (Plan.Build). Pure, so the wording is
-- tested offline: { { title, lines = {...} }, ... }, empty sections left out.
function UI.PreviewSections(plan)
    local sections = {}
    local direct, cascade = {}, {}
    for _, entry in ipairs(plan.disable) do
        local bucket = entry.reason == "cascade" and cascade or direct
        bucket[#bucket + 1] = entry.name
    end
    if #plan.disable > 0 then
        local lines = {}
        if #direct > 0 then lines[#lines + 1] = Joined(direct) end
        if #cascade > 0 then
            lines[#lines + 1] = GREY .. "Because they require one of those: " .. Joined(cascade) .. CLOSE
        end
        sections[#sections + 1] = { title = "Will turn off (" .. #plan.disable .. ")", lines = lines }
    end
    if #plan.enable > 0 then
        local names = {}
        for _, entry in ipairs(plan.enable) do names[#names + 1] = entry.name end
        sections[#sections + 1] = { title = "Will turn on (" .. #plan.enable .. ")", lines = { Joined(names) } }
    end
    if #plan.kept > 0 then
        sections[#sections + 1] = { title = "Kept on (protected, or needed by a protected addon)",
            lines = { Joined(plan.kept) } }
    end
    if #plan.unknown > 0 then
        sections[#sections + 1] = { title = "On the list but not installed here", lines = { Joined(plan.unknown) } }
    end
    if #plan.removed > 0 then
        sections[#sections + 1] = { title = "No longer installed, skipped", lines = { Joined(plan.removed) } }
    end
    return sections
end

function UI.PreviewText(plan)
    local parts = {}
    for _, section in ipairs(UI.PreviewSections(plan)) do
        parts[#parts + 1] = GOLD .. section.title .. CLOSE .. "\n" .. table.concat(section.lines, "\n")
    end
    return table.concat(parts, "\n\n")
end

local DIALOG_WIDTH, DIALOG_HEIGHT = 480, 400

local function CreateDialog()
    local dialog, template = ns.CreateFrameWithFallback("Frame", UIParent,
        { "BasicFrameTemplateWithInset" }, "KeyModePreviewDialog")
    dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:Hide()

    -- The template supplies TitleText and a close button; without it, a plain title.
    local title = template and dialog.TitleText
    if not title then
        title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        title:SetPoint("TOP", 0, -6)
    end
    dialog.title = title

    local intro = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", 16, -34)
    intro:SetPoint("RIGHT", dialog, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    dialog.intro = intro

    local scroll = ns.CreateFrameWithFallback("ScrollFrame", dialog, { "UIPanelScrollFrameTemplate" })
    scroll:SetPoint("TOPLEFT", 16, -60)
    scroll:SetPoint("BOTTOMRIGHT", -34, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(DIALOG_WIDTH - 56, 1)
    scroll:SetScrollChild(content)
    local body = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT")
    body:SetWidth(DIALOG_WIDTH - 56)
    body:SetJustifyH("LEFT")
    body:SetSpacing(2)
    dialog.scroll, dialog.content, dialog.body = scroll, content, body

    local confirm = ns.CreateFrameWithFallback("Button", dialog, { "UIPanelButtonTemplate" })
    confirm:SetSize(160, 24)
    confirm:SetPoint("BOTTOMRIGHT", -16, 14)
    confirm:SetText("Confirm and Reload")
    confirm:SetScript("OnClick", function() UI:ConfirmPreview() end)
    dialog.confirmButton = confirm

    local cancel = ns.CreateFrameWithFallback("Button", dialog, { "UIPanelButtonTemplate" })
    cancel:SetSize(100, 24)
    cancel:SetPoint("RIGHT", confirm, "LEFT", -8, 0)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() dialog:Hide() end)
    dialog.cancelButton = cancel

    -- Escape closes it, like every other Blizzard dialog.
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "KeyModePreviewDialog"
    end
    return dialog
end

local INTRO = {
    instance = "Turns off the Instance list for this character, then reloads.",
    world = "Turns off the World list for this character, then reloads.",
    off = "Restores this character's own setup and stops managing it, then reloads.",
}

-- Opens the dialog for a switch to `mode`, or says why not. A switch with nothing to
-- change is applied straight away (it records the mode and needs no reload), since a
-- dialog listing nothing would only ask the player to confirm a no-op.
function UI:Preview(mode)
    local ok, reason = ns.Switch:Check(mode)
    if not ok then
        ns.Print(reason)
        return
    end
    local plan = ns.Switch:Preview(mode)
    if #plan.disable == 0 and #plan.enable == 0 then
        local _, message = ns.Switch:Apply(mode)
        if message then ns.Print(message) end
        return
    end
    local dialog = self.dialog or CreateDialog()
    self.dialog = dialog
    dialog.mode = mode
    dialog.title:SetText("Switch to " .. ns.Switch.MODES[mode] .. " mode")
    dialog.intro:SetText(INTRO[mode])
    dialog.body:SetText(UI.PreviewText(plan))
    dialog.content:SetHeight((dialog.body:GetStringHeight() or 0) + 8)
    dialog:Show()
end

-- Confirm and Reload. Apply plans again from the current state, so anything changed
-- since the dialog opened is accounted for; it reloads on success, or explains.
function UI:ConfirmPreview()
    local dialog = self.dialog
    if not dialog then return end
    dialog:Hide()
    local _, message = ns.Switch:Apply(dialog.mode)
    if message then ns.Print(message) end
end
