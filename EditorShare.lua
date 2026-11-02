-- EditorShare.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The import and export dialog of the Lists page, on top of Share.lua. Loads after
-- Editor.lua.

local _, ns = ...

local Editor = ns.Editor
local Confirm = Editor.Confirm

--------------------------------------------------------------------------
-- Import and export (#20)
--
-- One dialog with a multi-line text box, used both ways. Export fills it with
-- Share.Encode and selects the text for copying. Import reads what was pasted, and
-- Merge or Replace first shows the exact changes (Share.Diff) in a confirmation, so
-- nothing is replaced unseen.
--------------------------------------------------------------------------

-- The changes as player-facing lines, one per list that changes. Pure, for the tests.
function Editor.ChangeLines(changes)
    local lines = {}
    for _, which in ipairs({ "instance", "world", "protected" }) do
        local change = changes[which]
        local label = which == "protected" and "Protect list" or (ns.Switch.MODES[which] .. " list")
        local parts = {}
        if #change.add > 0 then parts[#parts + 1] = "add " .. table.concat(change.add, ", ") end
        if #change.remove > 0 then parts[#parts + 1] = "remove " .. table.concat(change.remove, ", ") end
        if #parts > 0 then lines[#lines + 1] = label .. ": " .. table.concat(parts, "; ") end
    end
    return lines
end

local function CurrentLists()
    local lists = ns.Profiles:Lists()
    return { instance = lists.instance, world = lists.world, protected = ns.Profiles:ProtectedList() }
end

-- Reads the pasted text and, after a confirmation listing every change, applies it.
function Editor:Import(text, mode)
    local incoming, err = ns.Share.Decode(text)
    if not incoming then return false, err end
    local changes = ns.Share.Diff(CurrentLists(), incoming, mode)
    for _, warning in ipairs(incoming.warnings) do ns.Print(warning) end
    if changes.total == 0 then return true, "Nothing to change: the lists already match." end
    local verb = mode == "replace" and "Replace" or "Merge"
    Confirm(verb .. " the lists?\n\n" .. table.concat(Editor.ChangeLines(changes), "\n"), function()
        local applied = ns.Share.Apply(changes, ns.Profiles)
        ns.Print("Import: " .. applied .. " change" .. (applied == 1 and "" or "s") .. " made.")
        if self.shareDialog then self.shareDialog:Hide() end
        self:Refresh()
    end)
    return true
end

local SHARE_WIDTH, SHARE_HEIGHT = 460, 380

local function CreateShareDialog()
    local dialog, template = ns.CreateFrameWithFallback("Frame", UIParent,
        { "BasicFrameTemplateWithInset" }, "KeyModeShareDialog")
    dialog:SetSize(SHARE_WIDTH, SHARE_HEIGHT)
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
    local title = template and dialog.TitleText
    if not title then
        title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        title:SetPoint("TOP", 0, -6)
    end
    dialog.title = title

    local intro = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, -32)
    intro:SetPoint("RIGHT", dialog, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    dialog.intro = intro

    local scroll, scrollTemplate = ns.CreateFrameWithFallback("ScrollFrame", dialog,
        { "InputScrollFrameTemplate", "UIPanelScrollFrameTemplate" })
    scroll:SetPoint("TOPLEFT", 20, -62)
    scroll:SetPoint("BOTTOMRIGHT", -32, 76)
    local edit = scrollTemplate == "InputScrollFrameTemplate" and scroll.EditBox
    if not edit then
        edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject("ChatFontNormal")
        edit:SetAutoFocus(false)
        scroll:SetScrollChild(edit)
    end
    edit:SetWidth(SHARE_WIDTH - 60)
    edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
    dialog.edit = edit

    local include = ns.CreateFrameWithFallback("CheckButton", dialog, { "UICheckButtonTemplate" })
    include:SetSize(22, 22)
    include:SetPoint("BOTTOMLEFT", 16, 44)
    if include.Text then include.Text:SetText("Include the protect list") end
    include:SetScript("OnClick", function() Editor:FillExport() end)
    dialog.includeProtected = include

    local close = ns.CreateFrameWithFallback("Button", dialog, { "UIPanelButtonTemplate" })
    close:SetSize(90, 22)
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    close:SetText("Close")
    close:SetScript("OnClick", function() dialog:Hide() end)
    dialog.closeButton = close

    local function ImportButton(text, mode, anchor)
        local button = ns.CreateFrameWithFallback("Button", dialog, { "UIPanelButtonTemplate" })
        button:SetSize(100, 22)
        button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        button:SetText(text)
        button:SetScript("OnClick", function()
            local ok, message = Editor:Import(dialog.edit:GetText() or "", mode)
            if message then ns.Print((ok and "" or "Import: ") .. message) end
        end)
        return button
    end
    dialog.replaceButton = ImportButton("Replace", "replace", close)
    dialog.mergeButton = ImportButton("Merge", "merge", dialog.replaceButton)

    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "KeyModeShareDialog"
    end
    return dialog
end

local function ShareDialog(self)
    self.shareDialog = self.shareDialog or CreateShareDialog()
    return self.shareDialog
end

function Editor:FillExport()
    local dialog = self.shareDialog
    if not dialog then return end
    local protected = dialog.includeProtected:GetChecked() and ns.Profiles:ProtectedList() or nil
    dialog.edit:SetText(ns.Share.Encode(ns.Profiles:Lists(), protected))
    dialog.edit:HighlightText()
    dialog.edit:SetFocus()
end

function Editor:ShowExport()
    local dialog = ShareDialog(self)
    dialog.mode = "export"
    dialog.title:SetText("Export lists")
    dialog.intro:SetText("Press Ctrl+C to copy. The text can be kept as a backup or imported on another account.")
    dialog.includeProtected:Show()
    dialog.mergeButton:Hide()
    dialog.replaceButton:Hide()
    dialog:Show()
    self:FillExport()
end

function Editor:ShowImport()
    local dialog = ShareDialog(self)
    dialog.mode = "import"
    dialog.title:SetText("Import lists")
    dialog.intro:SetText("Paste exported lists with Ctrl+V. Merge adds to the current lists; Replace also "
        .. "removes what the text does not name. Both show the changes first.")
    dialog.includeProtected:Hide()
    dialog.mergeButton:Show()
    dialog.replaceButton:Show()
    dialog.edit:SetText("")
    dialog:Show()
    dialog.edit:SetFocus()
end
