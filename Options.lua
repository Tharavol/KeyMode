-- Options.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The options panel under Options > AddOns > KeyMode. Filled in by #3, and later by the
-- list editor (#18) and per-trigger toggles (#25).

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

local CreateFrameWithFallback = ns.CreateFrameWithFallback

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
    -- Switch prompts (#25), stored under settings.prompts. Each only opens the preview
    -- dialog; "Not now" there snoozes one until the next reload, these turn it off.
    {
        prompt = "arrival",
        heading = "Prompts",
        label = "Offer Instance mode on entering a raid or a Mythic dungeon",
        tooltip = "In a group, on arrival at any raid (LFR included) or a Mythic dungeon. "
            .. "Same as /km prompts arrival.",
    },
    {
        prompt = "group",
        label = "Offer Instance mode on joining or listing a Mythic+ or raid group",
        tooltip = "Through the Group Finder. Same as /km prompts group.",
    },
    {
        prompt = "departure",
        label = "Offer World mode on leaving afterwards",
        tooltip = "In Instance mode: on reaching the open world after a completed key or a raid, "
            .. "or on leaving the group. Same as /km prompts departure.",
    },
}

-- A checkbox's setting, wherever it lives: settings[key], or settings.prompts[prompt].
function Options.GetSetting(definition)
    local settings = ns.db.settings
    if definition.prompt then return settings.prompts[definition.prompt] == true end
    return settings[definition.key] and true or false
end

function Options.SetSetting(definition, value)
    local settings = ns.db.settings
    if definition.prompt then
        settings.prompts[definition.prompt] = value
    else
        settings[definition.key] = value
    end
end

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
    subtitle:SetText("Switches to a lean set of addons for Mythic+ and raids, and back to "
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
        if definition.heading then
            local subheading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            subheading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
            subheading:SetText(definition.heading)
            anchor = subheading
        end
        checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        if checkbox.Text then checkbox.Text:SetText(definition.label) end
        checkbox.tooltipText = definition.tooltip
        checkbox:SetScript("OnClick", function(self)
            Options.SetSetting(definition, self:GetChecked() and true or false)
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

    -- The lists live on their own subpage (#18); this is the way there from the main page.
    local lists = CreateFrameWithFallback("Button", panel, { "UIPanelButtonTemplate" })
    lists:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    lists:SetSize(160, 22)
    lists:SetText("Edit Lists...")
    lists:SetScript("OnClick", function() ns.Editor:Open() end)
    panel.listsButton = lists

    panel:SetScript("OnShow", function() Options:Refresh() end)
    return panel
end

-- Re-reads every widget from ns.db. Called on show and after anything that changes
-- settings outside the panel (slash commands, reset), so the panel never shows stale
-- state.
function Options:Refresh()
    local panel = self.panel
    if not (panel and ns.db) then return end
    panel.statusText:SetText("Mode: " .. ns.Switch:ModeLabel())
    for _, checkbox in ipairs(panel.checkboxes) do
        checkbox:SetChecked(Options.GetSetting(checkbox.definition))
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
