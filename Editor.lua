-- Editor.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The list editor (#18) and list management (#19): a "Lists" subpage under Options >
-- AddOns > KeyMode with an Instance and a World checkbox per installed addon. The rows
-- come from a pure function (Editor.Rows) the offline suite covers; the page only draws
-- them. Templates were checked against the live client source (docs/HANDOFF.md "UI
-- templates for v0.4.0"). Filled in by v0.4.0 (#18, #19).

local _, ns = ...

local Editor = {}
ns.Editor = Editor

--------------------------------------------------------------------------
-- Rows (pure)
--
-- Dependents are shown as implied, never saved: ticking DataStore shows Altoholic and
-- every DataStore_* module with a dimmed tick, and only DataStore goes on the list. The
-- switch plan turns them off anyway (the cascade), so writing them to the list would
-- only make it longer and leave stale entries behind when the parent is unticked.
--
-- A dependent is indented under its parent when it requires exactly one installed
-- addon: then "turning this off also turns off those" is a plain tree. Anything with
-- two or more requirements stays at the top level.
--------------------------------------------------------------------------

local function NameLess(a, b)
    local la, lb = a:lower(), b:lower()
    if la ~= lb then return la < lb end
    return a < b
end

-- Folder titles often carry colour codes and texture escapes; the editor shows plain text.
local function Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
Editor.Plain = Plain

-- `input`: { records, graph, lists = { instance = set, world = set }, isProtected,
-- search = string, onlyListed = bool }. Returns an ordered list of rows:
--   { name, title, depth, protected,
--     instance = "listed" | "implied" | nil, world = ..., impliedBy = { instance, world },
--     notInstalled = true for a list entry this character does not have }
-- With a search, matching rows come back flat (depth 0), since a match deep in a tree
-- means little without its parents. Not-installed list entries always come last.
function Editor.Rows(input)
    local graph = input.graph
    local canonical = graph.canonical
    local isProtected = input.isProtected or function() return false end
    local Inventory = ns.Inventory

    local titles = {}
    for _, record in ipairs(input.records or {}) do titles[record.name] = Plain(record.title) end

    -- Per list: installed names listed, the cascade, and which listed addon implies each.
    local state, impliedBy, unknown = { instance = {}, world = {} }, { instance = {}, world = {} }, {}
    for _, which in ipairs({ "instance", "world" }) do
        local listed = {}
        for key, value in pairs((input.lists or {})[which] or {}) do
            if value and type(key) == "string" then
                local name = canonical[key:lower()]
                if name then
                    listed[#listed + 1] = name
                    state[which][name] = "listed"
                else
                    unknown[key] = unknown[key] or {}
                    unknown[key][which] = true
                end
            end
        end
        table.sort(listed, NameLess)
        for _, name in ipairs(Inventory.Dependents(graph, listed)) do
            if not state[which][name] then
                state[which][name] = "implied"
                for _, required in ipairs(Inventory.Requirements(graph, { name })) do
                    if state[which][required] == "listed" then
                        impliedBy[which][name] = required
                        break
                    end
                end
            end
        end
    end

    local function MakeRow(name, depth)
        local protected = isProtected(name)
        return {
            name = name,
            title = titles[name] or name,
            depth = depth,
            protected = protected,
            instance = not protected and state.instance[name] or nil,
            world = not protected and state.world[name] or nil,
            impliedBy = { instance = impliedBy.instance[name], world = impliedBy.world[name] },
        }
    end

    local search = (input.search or ""):lower():match("^%s*(.-)%s*$")
    local function Keep(row)
        if input.onlyListed and not (row.instance or row.world) then return false end
        if search ~= "" and not (row.name:lower():find(search, 1, true)
                or row.title:lower():find(search, 1, true)) then
            return false
        end
        return true
    end

    local rows = {}
    if search ~= "" then
        for _, name in ipairs(graph.names) do
            local row = MakeRow(name, 0)
            if Keep(row) then rows[#rows + 1] = row end
        end
    else
        -- Children: addons whose only installed requirement is the parent.
        local children, isChild = {}, {}
        for _, name in ipairs(graph.names) do
            local deps = graph.deps[name]
            if #deps == 1 then
                children[deps[1]] = children[deps[1]] or {}
                table.insert(children[deps[1]], name)
                isChild[name] = true
            end
        end
        local visited = {}
        local function Walk(name, depth)
            if visited[name] then return end -- a one-requirement cycle
            visited[name] = true
            local row = MakeRow(name, depth)
            if Keep(row) then rows[#rows + 1] = row end
            for _, child in ipairs(children[name] or {}) do Walk(child, depth + 1) end
        end
        for _, name in ipairs(graph.names) do
            if not isChild[name] then Walk(name, 0) end
        end
        for _, name in ipairs(graph.names) do Walk(name, 0) end -- anything only reachable through a cycle
    end

    local missing = {}
    for key in pairs(unknown) do missing[#missing + 1] = key end
    table.sort(missing, NameLess)
    for _, key in ipairs(missing) do
        local row = {
            name = key, title = key, depth = 0, protected = false, notInstalled = true,
            instance = unknown[key].instance and "listed" or nil,
            world = unknown[key].world and "listed" or nil,
            impliedBy = {},
        }
        if search == "" or key:lower():find(search, 1, true) then rows[#rows + 1] = row end
    end
    return rows
end

--------------------------------------------------------------------------
-- List management (#19)
--------------------------------------------------------------------------

-- Empties one list. Returns how many names it removed.
function Editor:Clear(which)
    local names = ns.Profiles:ListNames(which)
    for _, name in ipairs(names) do ns.Profiles:ListRemove(which, name) end
    return #names
end

-- Adds every name on `from` to `to`. Returns how many were new.
function Editor:Copy(from, to)
    local added = 0
    for _, name in ipairs(ns.Profiles:ListNames(from)) do
        if not ns.Profiles:InList(to, name) then
            ns.Profiles:ListAdd(to, name)
            added = added + 1
        end
    end
    return added
end

--------------------------------------------------------------------------
-- The Lists page (#18)
--------------------------------------------------------------------------

local ROW_HEIGHT = 22
local COLUMN_INSTANCE, COLUMN_WORLD, COLUMN_NAME = 14, 84, 150
local INDENT = 16
local GREY, CLOSE = "|cff999999", "|r"

local function SetBox(box, state, protected, impliedBy, label)
    box:SetChecked(state ~= nil)
    box:SetAlpha(state == "implied" and 0.45 or 1)
    if protected then box:Disable() else box:Enable() end
    if state == "implied" and impliedBy then
        box.tooltip = "Off in " .. label .. " mode because it requires " .. impliedBy
            .. ". Tick it to list it on its own."
    elseif protected then
        box.tooltip = "Protected: no switch turns it off. /km protect remove changes that."
    else
        box.tooltip = nil
    end
end

local function ShowBoxTooltip(box)
    if not box.tooltip then return end
    GameTooltip:SetOwner(box, "ANCHOR_RIGHT")
    GameTooltip:AddLine(box.tooltip, 1, 1, 1, true)
    GameTooltip:Show()
end

local function MakeBox(row, which)
    local box = ns.CreateFrameWithFallback("CheckButton", row, { "UICheckButtonTemplate" })
    box:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    box:SetScript("OnClick", function(self)
        local data = row.data
        if not data then return end
        -- An implied box reads as ticked; clicking it lists the addon on its own.
        if data[which] == "implied" or self:GetChecked() then
            ns.Profiles:ListAdd(which, data.name)
        else
            ns.Profiles:ListRemove(which, data.name)
        end
        Editor:Refresh()
    end)
    box:SetScript("OnEnter", ShowBoxTooltip)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return box
end

-- Called by the scroll view for every row frame it shows; frames are recycled, so the
-- widgets are made once per frame and every field is reset from `data` each time.
function Editor.InitRow(row, data)
    if not rawget(row, "built") then
        row:SetHeight(ROW_HEIGHT)
        row.instanceBox = MakeBox(row, "instance")
        row.instanceBox:SetPoint("LEFT", COLUMN_INSTANCE, 0)
        row.worldBox = MakeBox(row, "world")
        row.worldBox:SetPoint("LEFT", COLUMN_WORLD, 0)
        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.built = true
    end
    row.data = data
    SetBox(row.instanceBox, data.instance, data.protected, data.impliedBy.instance, "Instance")
    SetBox(row.worldBox, data.world, data.protected, data.impliedBy.world, "World")
    local text = data.title
    if data.title ~= data.name then text = text .. "  " .. GREY .. data.name .. CLOSE end
    if data.protected then text = text .. "  " .. GREY .. "(protected)" .. CLOSE end
    if data.notInstalled then text = text .. "  " .. GREY .. "(not installed on this character)" .. CLOSE end
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", COLUMN_NAME + data.depth * INDENT, 0)
    row.label:SetPoint("RIGHT", -8, 0)
    row.label:SetText(text)
end

local function Button(parent, text, width, onClick)
    local button = ns.CreateFrameWithFallback("Button", parent, { "UIPanelButtonTemplate" })
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Confirm(text, action)
    if type(StaticPopup_ShowGenericConfirmation) == "function" then
        StaticPopup_ShowGenericConfirmation(text, action)
    else
        action()
    end
end

local function CreatePage()
    local page = CreateFrame("Frame")
    page.name = "Lists"

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Lists")

    local help = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    help:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    help:SetJustifyH("LEFT")
    help:SetText("Ticked addons are turned off in that mode: Instance in Mythic+ dungeons and raids, "
        .. "World the rest of the time. A dimmed tick means the addon requires a ticked one and goes "
        .. "off with it. The lists are shared by every character.")

    local search = ns.CreateFrameWithFallback("EditBox", page, { "SearchBoxTemplate", "InputBoxTemplate" })
    search:SetSize(220, 20)
    search:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 6, -12)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() Editor:Refresh() end)
    page.search = search

    local only = ns.CreateFrameWithFallback("CheckButton", page, { "UICheckButtonTemplate" })
    only:SetSize(22, 22)
    only:SetPoint("LEFT", search, "RIGHT", 16, 0)
    if only.Text then only.Text:SetText("Show only listed") end
    only:SetScript("OnClick", function() Editor:Refresh() end)
    page.onlyListed = only

    local header = CreateFrame("Frame", nil, page)
    header:SetHeight(16)
    header:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -10)
    header:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    for _, column in ipairs({ { COLUMN_INSTANCE - 6, "Instance" }, { COLUMN_WORLD - 2, "World" },
            { COLUMN_NAME, "Addon" } }) do
        local label = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", column[1], 0)
        label:SetText(column[2])
    end

    -- Bottom bar: list management (#19).
    local clearInstance = Button(page, "Clear Instance", 120, function()
        Confirm("Remove every addon from the Instance list?", function()
            ns.Print(Editor:Clear("instance") .. " removed from the Instance list.")
            Editor:Refresh()
        end)
    end)
    clearInstance:SetPoint("BOTTOMLEFT", 16, 16)
    local clearWorld = Button(page, "Clear World", 120, function()
        Confirm("Remove every addon from the World list?", function()
            ns.Print(Editor:Clear("world") .. " removed from the World list.")
            Editor:Refresh()
        end)
    end)
    clearWorld:SetPoint("LEFT", clearInstance, "RIGHT", 8, 0)
    local copyToWorld = Button(page, "Copy Instance to World", 170, function()
        ns.Print(Editor:Copy("instance", "world") .. " added to the World list.")
        Editor:Refresh()
    end)
    copyToWorld:SetPoint("LEFT", clearWorld, "RIGHT", 8, 0)
    local copyToInstance = Button(page, "Copy World to Instance", 170, function()
        ns.Print(Editor:Copy("world", "instance") .. " added to the Instance list.")
        Editor:Refresh()
    end)
    copyToInstance:SetPoint("LEFT", copyToWorld, "RIGHT", 8, 0)
    page.buttons = { clearInstance = clearInstance, clearWorld = clearWorld,
        copyToWorld = copyToWorld, copyToInstance = copyToInstance }

    -- The list itself. Without the scroll templates (retired on a future client) the page
    -- still loads and points at the commands instead of erroring.
    local okBox, scrollBox = pcall(CreateFrame, "Frame", nil, page, "WowScrollBoxList")
    local okBar, scrollBar = pcall(CreateFrame, "EventFrame", nil, page, "MinimalScrollBar")
    if okBox and okBar and type(CreateScrollBoxListLinearView) == "function"
            and type(ScrollUtil) == "table" and type(CreateDataProvider) == "function" then
        scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        scrollBox:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -30, 48)
        scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
        scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
        local view = CreateScrollBoxListLinearView()
        view:SetElementExtent(ROW_HEIGHT)
        view:SetElementInitializer("Frame", Editor.InitRow)
        ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
        page.scrollBox, page.view = scrollBox, view
    else
        local fallback = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fallback:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
        fallback:SetText("The list view is not available on this client. Use /km list instead.")
    end

    page:SetScript("OnShow", function() Editor:Refresh() end)
    return page
end

-- Rebuilds the rows from the current inventory, lists and filters, keeping the scroll
-- position so ticking a box does not jump the list back to the top.
function Editor:Refresh()
    local page = self.page
    if not (page and page.scrollBox and ns.db) then return end
    local records, graph = ns.Inventory:Read()
    local rows = Editor.Rows({
        records = records,
        graph = graph,
        lists = ns.Profiles:Lists(),
        isProtected = function(name) return ns.Profiles:IsProtected(name) end,
        search = page.search:GetText() or "",
        onlyListed = page.onlyListed:GetChecked(),
    })
    self.rows = rows
    local box = page.scrollBox
    local position = box.GetScrollPercentage and box:GetScrollPercentage()
    box:SetDataProvider(CreateDataProvider(rows))
    if position and box.SetScrollPercentage then box:SetScrollPercentage(position) end
end

function Editor:Register()
    local parent = ns.Options.category
    if not (parent and Settings.RegisterCanvasLayoutSubcategory) then return end
    self.page = CreatePage()
    self.category = Settings.RegisterCanvasLayoutSubcategory(parent, self.page, "Lists")
end

function Editor:Open()
    if self.category and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    end
end

Editor:Register()
