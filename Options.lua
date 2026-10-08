-- Options.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The options panel under Options > AddOns > KeyMode. Filled in by #3, and later by the
-- profile editor (#18) and per-trigger toggles (#25).

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

-- CreateFrame raises immediately if a template doesn't resolve on the running client,
-- which would abort the rest of this file. Blizzard periodically retires UI templates
-- (Crosshairs #53), so every candidate is tried in order and an untemplated frame is the
-- last resort rather than an error.
local function CreateFrameWithFallback(frameType, parent, templates)
    for _, template in ipairs(templates) do
        local ok, frame = pcall(CreateFrame, frameType, nil, parent, template)
        if ok and frame then return frame, template end
    end
    return CreateFrame(frameType, nil, parent), nil
end

-- Checkbox definitions: one table drives both the widgets and their refresh, so adding
-- a setting is one entry rather than three edits.
Options.CHECKBOXES = {
    {
        key = "debug",
        label = "Debug messages",
        tooltip = "Print diagnostic messages to chat. Same as /km debug.",
    },
    {
        key = "minimapButton",
        label = "Show minimap button",
        tooltip = "Show KeyMode's button on the minimap edge. Drag it to move it. Same as /km minimap.",
    },
}

local function CreatePanel()
    local panel = CreateFrame("Frame")
    panel.name = ADDON_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ADDON_NAME)

    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -16)
    version:SetText(ns.GetAddonVersion())

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Switches to a lean, saved set of addons before Mythic+ and restores "
        .. "the full setup afterwards.")

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    status:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    panel.statusText = status

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -20)
    heading:SetText("General")

    local anchor = heading
    panel.checkboxes = {}
    for _, definition in ipairs(Options.CHECKBOXES) do
        local checkbox, template = CreateFrameWithFallback("CheckButton", panel,
            { "UICheckButtonTemplate", "InterfaceOptionsCheckButtonTemplate" })
        if not template then
            -- No template resolved: draw the box and label by hand rather than leave an
            -- invisible, unlabelled click target.
            checkbox:SetSize(24, 24)
            checkbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
            checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
            checkbox.Text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        end
        checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        if checkbox.Text then checkbox.Text:SetText(definition.label) end
        checkbox.tooltipText = definition.tooltip
        checkbox:SetScript("OnClick", function(self)
            ns.db.settings[definition.key] = self:GetChecked() and true or false
            ns.SettingsChanged()
        end)
        checkbox.definition = definition
        panel.checkboxes[#panel.checkboxes + 1] = checkbox
        anchor = checkbox
    end

    local reset = CreateFrameWithFallback("Button", panel, { "UIPanelButtonTemplate" })
    reset:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    reset:SetSize(160, 22)
    reset:SetText("Reset to Defaults")
    reset:SetScript("OnClick", function()
        ns.ResetSettings()
        ns.Print("Settings restored to defaults.")
    end)
    panel.resetButton = reset

    panel:SetScript("OnShow", function() Options:Refresh() end)
    return panel
end

-- Re-reads every widget from ns.db. Called on show and after anything that changes
-- settings outside the panel (slash commands, reset), so the panel never shows stale
-- state.
function Options:Refresh()
    local panel = self.panel
    if not (panel and ns.db) then return end
    panel.statusText:SetText("Mode: " .. (ns.Switch:IsActive() and "|cff00ff00Mythic+|r" or "Normal"))
    for _, checkbox in ipairs(panel.checkboxes) do
        checkbox:SetChecked(ns.db.settings[checkbox.definition.key] and true or false)
    end
end

-- Registered once at load: the category has to exist for the Settings window to list it.
function Options:Register()
ns.OnSettingsChanged(function() Options:Refresh() end)
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    self.panel = CreatePanel()
    local category = Settings.RegisterCanvasLayoutCategory(self.panel, ADDON_NAME)
    Settings.RegisterAddOnCategory(category)
    self.category = category
end

-- Opens the Settings window straight to this panel.
function Options:Open()
    if self.category and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    end
end

Options:Register()
ns.OnSettingsChanged(function() Options:Refresh() end)
