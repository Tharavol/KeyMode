-- editor_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The list editor (#18) and list management (#19): the pure row model, the Lists page
-- drawn through the stubbed scroll list, and the clear/copy actions.

return function(stub, T)
    print("editor")

    local function Boot()
        return stub.Boot(function(_, fixtures)
            local add = stub.AddAddon
            add(fixtures, "AddonFactory", { title = "|cff00ff00Addon|r Factory" })
            add(fixtures, "DataStore", { deps = { "AddonFactory" } })
            add(fixtures, "DataStore_Containers", { deps = { "DataStore" } })
            add(fixtures, "Altoholic", { deps = { "DataStore", "DataStore_Containers" } })
            add(fixtures, "BugGrabber")
            add(fixtures, "BugSack", { deps = { "BugGrabber" } })
            add(fixtures, "TomTom")
        end)
    end

    local function Rows(env, opts)
        opts = opts or {}
        local records, graph = env.ns.Inventory:Read()
        return env.ns.Editor.Rows({
            records = records,
            graph = graph,
            lists = env.ns.Profiles:Lists(),
            isProtected = function(name) return env.ns.Profiles:IsProtected(name) end,
            search = opts.search,
            onlyListed = opts.onlyListed,
        })
    end

    local function Find(rows, name)
        for _, row in ipairs(rows) do
            if row.name == name then return row end
        end
    end

    local function Has(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return true end
        end
        return false
    end

    local function Outline(rows)
        local parts = {}
        for _, row in ipairs(rows) do parts[#parts + 1] = string.rep(">", row.depth) .. row.name end
        return table.concat(parts, " ")
    end

    T.Test("rows nest a dependent under its only requirement", function()
        local env = Boot()
        T.AssertEqual(Outline(Rows(env)),
            "AddonFactory >DataStore >>DataStore_Containers Altoholic BugGrabber >BugSack KeyMode TomTom",
            "tree; Altoholic has two requirements, so it stays at the top")
        T.AssertEqual(Find(Rows(env), "AddonFactory").title, "Addon Factory", "colour codes stripped")
    end)

    T.Test("a listed addon's dependents are implied, with the addon that implies them", function()
        local env = Boot()
        env.ns.Profiles:ListAdd("instance", "datastore")
        env.ns.Profiles:ListAdd("world", "TomTom")
        local rows = Rows(env)
        T.AssertEqual(Find(rows, "DataStore").instance, "listed", "listed, any case")
        T.AssertEqual(Find(rows, "Altoholic").instance, "implied", "implied")
        T.AssertEqual(Find(rows, "Altoholic").impliedBy.instance, "DataStore", "by DataStore")
        T.AssertEqual(Find(rows, "AddonFactory").instance, nil, "a requirement is not implied")
        T.AssertEqual(Find(rows, "TomTom").world, "listed", "world list")
        T.AssertEqual(Find(rows, "TomTom").instance, nil, "lists are independent")
        T.AssertEqual(#env.ns.Profiles:ListNames("instance"), 1, "only DataStore saved")
    end)

    T.Test("protected addons are locked and never show a tick", function()
        local env = Boot()
        env.ns.Profiles:Unprotect("BugGrabber")
        env.ns.Profiles:ListAdd("instance", "BugGrabber")
        local rows = Rows(env)
        T.AssertTrue(Find(rows, "BugSack").protected, "BugSack protected")
        T.AssertEqual(Find(rows, "BugGrabber").instance, "listed", "BugGrabber listed, not protected itself")
        T.AssertEqual(Find(rows, "BugSack").instance, nil, "protected shows no implied tick")
        T.AssertTrue(Find(rows, "KeyMode").protected, "KeyMode protected")
    end)

    T.Test("search comes back flat; only-listed keeps listed and implied rows", function()
        local env = Boot()
        env.ns.Profiles:ListAdd("instance", "DataStore")
        T.AssertEqual(Outline(Rows(env, { search = "  STORE " })), "DataStore DataStore_Containers", "flat, any case")
        T.AssertEqual(Outline(Rows(env, { search = "addon factory" })), "AddonFactory", "matches the title")
        T.AssertEqual(Outline(Rows(env, { onlyListed = true })), ">DataStore >>DataStore_Containers Altoholic",
            "listed and implied")
    end)

    T.Test("list entries not installed here come last, marked", function()
        local env = Boot()
        env.ns.Profiles:ListAdd("world", "Zygor")
        env.ns.Profiles:ListAdd("instance", "Zygor")
        local rows = Rows(env)
        local last = rows[#rows]
        T.AssertEqual(last.name, "Zygor", "last")
        T.AssertTrue(last.notInstalled, "marked")
        T.AssertEqual(last.instance, "listed", "instance")
        T.AssertEqual(last.world, "listed", "world")
    end)

    T.Test("the Lists page is a subpage of KeyMode's options, reached from the main page", function()
        local env = Boot()
        local sub = env.fixtures.subcategories.Lists
        T.AssertTrue(sub ~= nil, "registered")
        T.AssertTrue(sub.parent == env.fixtures.category, "under KeyMode")
        env.ns.Options.panel.listsButton:Click()
        T.AssertEqual(env.fixtures.settingsOpened[1], "Lists-subcategory", "opened")
    end)

    T.Test("showing the page draws the rows; ticking boxes edits the list", function()
        local env = Boot()
        local page = env.ns.Editor.page
        page._scripts.OnShow(page)
        local rows = page.scrollBox._dataProvider.rows
        T.AssertEqual(#rows, 8, "every addon")
        local init = page.scrollBox._view.init
        local frame = env.CreateFrame("Frame")
        init(frame, Find(rows, "DataStore"))
        T.AssertFalse(frame.instanceBox:GetChecked(), "unticked")
        frame.instanceBox:SetChecked(true)
        frame.instanceBox:Click()
        T.AssertTrue(env.ns.Profiles:InList("instance", "DataStore"), "ticking lists it")

        rows = page.scrollBox._dataProvider.rows
        init(frame, Find(rows, "Altoholic"))
        T.AssertTrue(frame.instanceBox:GetChecked(), "implied reads as ticked")
        T.AssertEqual(frame.instanceBox:GetAlpha(), 0.45, "dimmed")
        T.AssertTrue(frame.instanceBox.tooltip:find("requires DataStore", 1, true), "says why")
        frame.instanceBox:SetChecked(false) -- the click unticks it first
        frame.instanceBox:Click()
        T.AssertTrue(env.ns.Profiles:InList("instance", "Altoholic"), "clicking an implied box lists it")

        rows = page.scrollBox._dataProvider.rows
        init(frame, Find(rows, "DataStore"))
        frame.instanceBox:SetChecked(false)
        frame.instanceBox:Click()
        T.AssertFalse(env.ns.Profiles:InList("instance", "DataStore"), "unticking removes it")

        init(frame, Find(page.scrollBox._dataProvider.rows, "BugSack"))
        T.AssertFalse(frame.instanceBox:IsEnabled(), "protected is locked")
    end)

    T.Test("clear asks first; copy adds what the other list lacks", function()
        local env = Boot()
        env.ns.Profiles:ListAdd("instance", "TomTom")
        env.ns.Profiles:ListAdd("instance", "DataStore")
        env.ns.Profiles:ListAdd("world", "tomtom")
        local buttons = env.ns.Editor.page.buttons
        buttons.copyToWorld:Click()
        T.AssertTrue(stub.TakeChat(env)[1]:find("1 added to the World list.", 1, true), "only the new one")
        T.AssertEqual(table.concat(env.ns.Profiles:ListNames("world"), ","), "DataStore,tomtom", "copied")
        env.fixtures.autoConfirm = false
        buttons.clearInstance:Click()
        T.AssertEqual(#env.ns.Profiles:ListNames("instance"), 2, "not cleared without confirming")
        T.AssertTrue(env.fixtures.confirmations[1]:find("Instance list", 1, true), "asked")
        env.fixtures.autoConfirm = true
        buttons.clearInstance:Click()
        T.AssertEqual(#env.ns.Profiles:ListNames("instance"), 0, "cleared")
    end)

    T.Test("export fills the text box; the protect list only when ticked", function()
        local env = Boot()
        env.ns.Profiles:ListAdd("instance", "TomTom")
        stub.Slash(env, "/km export")
        local dialog = env.ns.Editor.shareDialog
        T.AssertTrue(dialog:IsShown(), "shown")
        T.AssertEqual(dialog.title:GetText(), "Export lists", "title")
        T.AssertEqual(dialog.edit:GetText(), "KeyMode lists 1\n[instance]\nTomTom\n[world]\n", "text")
        T.AssertFalse(dialog.mergeButton:IsShown(), "no import buttons")
        dialog.includeProtected:SetChecked(true)
        dialog.includeProtected:Click()
        T.AssertTrue(dialog.edit:GetText():find("[protected]\nBugGrabber\nBugSack\nKeyMode\n", 1, true), "protect list")
    end)

    T.Test("import shows the changes, then merges or replaces on confirmation", function()
        local env = Boot()
        env.ns.Profiles:ListAdd("instance", "TomTom")
        env.ns.Editor:ShowImport()
        local dialog = env.ns.Editor.shareDialog
        T.AssertEqual(dialog.title:GetText(), "Import lists", "title")
        T.AssertEqual(dialog.edit:GetText(), "", "empty")
        dialog.edit:SetText("KeyMode lists 1\n[instance]\nDataStore\n[world]\nZygor\n")
        env.fixtures.autoConfirm = false
        dialog.replaceButton:Click()
        T.AssertTrue(env.ns.Profiles:InList("instance", "TomTom"), "nothing until confirmed")
        T.AssertEqual(env.fixtures.confirmations[1], "Replace the lists?\n\n"
            .. "Instance list: add DataStore; remove TomTom\nWorld list: add Zygor", "changes listed")
        env.fixtures.autoConfirm = true
        dialog.mergeButton:Click()
        T.AssertTrue(env.ns.Profiles:InList("instance", "TomTom"), "merge keeps")
        T.AssertTrue(env.ns.Profiles:InList("instance", "DataStore"), "merge adds")
        T.AssertTrue(stub.TakeChat(env)[1]:find("Import: 2 changes made.", 1, true), "reported")
        T.AssertFalse(dialog:IsShown(), "closed after importing")
        dialog.edit:SetText("not a list")
        dialog.mergeButton:Click()
        T.AssertTrue(stub.TakeChat(env)[1]:find("Import: Not a KeyMode list", 1, true), "error shown")
    end)

    T.Test("suggest shows pending ticks; untick leaves one out; accept saves, discard drops", function()
        local env = stub.Boot(function(_, fixtures)
            stub.AddAddon(fixtures, "TomTom")
            stub.AddAddon(fixtures, "CraftSim", { metadata = { Category = "Professions" } })
            stub.AddAddon(fixtures, "DBM-Core")
            stub.AddAddon(fixtures, "DBM-Raids-Midnight", { deps = { "DBM-Core" } })
            stub.AddAddon(fixtures, "Details")
        end)
        local page = env.ns.Editor.page
        page._scripts.OnShow(page)
        page.suggestButton:Click()
        T.AssertTrue(page.pendingBar.accept:IsShown(), "accept shown")
        T.AssertEqual(page.pendingBar.summary:GetText(), "Suggested: 2 Instance, 1 World", "summary")
        local rows = page.scrollBox._dataProvider.rows
        T.AssertEqual(Find(rows, "CraftSim").instance, "suggested", "pending tick")
        T.AssertEqual(Find(rows, "CraftSim").reason.instance, "Professions category", "reason")
        T.AssertEqual(Find(rows, "Details").instance, nil, "not suggested")
        T.AssertEqual(#env.ns.Profiles:ListNames("instance"), 0, "nothing saved yet")

        local frame = env.CreateFrame("Frame")
        page.scrollBox._view.init(frame, Find(rows, "TomTom"))
        frame.instanceBox:SetChecked(false)
        frame.instanceBox:Click()
        T.AssertEqual(page.pendingBar.summary:GetText(), "Suggested: 1 Instance, 1 World", "left out")

        page.pendingBar.accept:Click()
        T.AssertEqual(table.concat(env.ns.Profiles:ListNames("instance"), ","), "CraftSim", "accepted")
        T.AssertEqual(table.concat(env.ns.Profiles:ListNames("world"), ","), "DBM-Raids-Midnight", "accepted")
        T.AssertFalse(page.pendingBar.accept:IsShown(), "bar hidden")

        env.ns.Profiles:ListRemove("instance", "CraftSim")
        page.suggestButton:Click()
        page.pendingBar.discard:Click()
        T.AssertEqual(#env.ns.Profiles:ListNames("instance"), 0, "discard saves nothing")
        page.suggestButton:Click()
        page.pendingBar.accept:Click()
        page.suggestButton:Click()
        T.AssertTrue(Has(stub.TakeChat(env), "Nothing to suggest"), "nothing left to suggest")
    end)

    T.Test("/km list clear and copy", function()
        local env = Boot()
        stub.Slash(env, "/km list instance add TomTom")
        stub.Slash(env, "/km list world copy instance")
        stub.Slash(env, "/km list world copy world")
        stub.Slash(env, "/km list instance clear")
        local lines = stub.TakeChat(env)
        T.AssertTrue(lines[2]:find("1 added to the World list from the Instance list.", 1, true), "copy")
        T.AssertTrue(lines[3]:find("expected the other list's name", 1, true), "copy onto itself refused")
        T.AssertTrue(lines[4]:find("1 removed from the Instance list.", 1, true), "clear")
        T.AssertTrue(env.ns.Profiles:InList("world", "TomTom"), "world kept")
    end)
end
