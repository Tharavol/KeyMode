-- share_spec.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Import and export (#20): the "KeyMode lists 1" text format, decoding with its errors
-- and warnings, the replace/merge diff, and applying a diff through the real Profiles.

return function(stub, T)
    print("share")

    local ns = stub.Boot().ns
    local Share = ns.Share

    local function Join(list) return table.concat(list or {}, ",") end

    local function Set(...)
        local set = {}
        for _, name in ipairs({ ... }) do set[name] = true end
        return set
    end

    local function Decoded(text)
        local result, err = Share.Decode(text)
        T.AssertTrue(result, "decode failed: " .. tostring(err))
        return result
    end

    local function DecodeError(text)
        local result, err = Share.Decode(text)
        T.AssertEqual(result, nil, "expected an error")
        return err
    end

    --------------------------------------------------------------------------
    -- Encode
    --------------------------------------------------------------------------

    T.Test("encode: exact format, names sorted case-insensitively", function()
        local text = Share.Encode({
            instance = { DataStore = true, altoholic = true, Off = false },
            world = Set("DBM-Core"),
        }, { "BugSack" })
        T.AssertEqual(text, "KeyMode lists 1\n[instance]\naltoholic\nDataStore\n[world]\nDBM-Core\n"
            .. "[protected]\nBugSack\n")
    end)

    T.Test("encode: empty sections are written, nil protected omits the section", function()
        T.AssertEqual(Share.Encode({ instance = {}, world = {} }), "KeyMode lists 1\n[instance]\n[world]\n")
        T.AssertEqual(Share.Encode({}, {}), "KeyMode lists 1\n[instance]\n[world]\n[protected]\n")
    end)

    T.Test("encode then decode round-trips", function()
        local lists = { instance = Set("DataStore", "Altoholic"), world = Set("DBM-Core", "WeakAuras") }
        local r = Decoded(Share.Encode(lists, { "!BugGrabber", "BugSack", "KeyMode" }))
        T.AssertEqual(Join(r.instance), "Altoholic,DataStore")
        T.AssertEqual(Join(r.world), "DBM-Core,WeakAuras")
        T.AssertEqual(Join(r.protected), "!BugGrabber,BugSack", "KeyMode dropped silently")
        T.AssertEqual(#r.warnings, 0, "no warnings")
    end)

    --------------------------------------------------------------------------
    -- Decode
    --------------------------------------------------------------------------

    T.Test("decode: CRLF, CR and a UTF-8 BOM", function()
        local r = Decoded("\239\187\191KeyMode lists 1\r\n[instance]\r\nA\r\nB\r\n")
        T.AssertEqual(Join(r.instance), "A,B", "BOM + CRLF")
        r = Decoded("KeyMode lists 1\r[world]\rC\r")
        T.AssertEqual(Join(r.world), "C", "CR")
    end)

    T.Test("decode: comments, blank lines, whitespace and a case-insensitive header", function()
        local r = Decoded("\n  keymode LISTS 1  \n# a comment\n\n[ Instance ]\n  DataStore  \n\n# Altoholic\n")
        T.AssertEqual(Join(r.instance), "DataStore")
        T.AssertEqual(Join(r.world), "", "absent world is empty")
        T.AssertEqual(r.protected, nil, "absent protected is nil")
    end)

    T.Test("decode: duplicates collapse to the first spelling; a repeated section merges", function()
        local r = Decoded("KeyMode lists 1\n[instance]\nDataStore\ndatastore\n[world]\nX\n[INSTANCE]\nDATASTORE\nZed\n")
        T.AssertEqual(Join(r.instance), "DataStore,Zed")
        T.AssertEqual(Join(r.world), "X")
    end)

    T.Test("decode: an empty [protected] section is present, not nil", function()
        local r = Decoded("KeyMode lists 1\n[protected]\n")
        T.AssertEqual(type(r.protected), "table")
        T.AssertEqual(#r.protected, 0)
    end)

    T.Test("decode errors: empty text, missing header, newer version", function()
        T.AssertEqual(DecodeError(""), "Nothing to import.")
        T.AssertEqual(DecodeError("  \r\n\t\n"), "Nothing to import.")
        T.AssertEqual(DecodeError(nil), "Nothing to import.")
        T.AssertTrue(DecodeError("[instance]\nA\n"):find("KeyMode lists 1", 1, true), "missing header")
        T.AssertTrue(DecodeError("KeyMode lists\n"):find("first line", 1, true), "no version")
        T.AssertTrue(DecodeError("KeyMode lists 2\n[instance]\n"):find("newer KeyMode", 1, true), "newer")
        T.AssertEqual(DecodeError("KeyMode lists 0\n[instance]\n"), "Unsupported list format 0.", "zero")
    end)

    T.Test("decode errors: a name before a section and an unknown section name the line", function()
        local err = DecodeError("KeyMode lists 1\n\nDataStore\n")
        T.AssertTrue(err:find("Line 3", 1, true), err)
        err = DecodeError("KeyMode lists 1\n[instance]\nA\n[raid]\nB\n")
        T.AssertTrue(err:find("Line 4", 1, true), err)
        T.AssertTrue(err:find("[raid]", 1, true), err)
    end)

    T.Test("decode: KeyMode is dropped from lists with a warning, silently from protected", function()
        local r = Decoded("KeyMode lists 1\n[instance]\nkeymode\nA\n[world]\nKeyMode\n[protected]\nKEYMODE\nB\n")
        T.AssertEqual(Join(r.instance), "A")
        T.AssertEqual(Join(r.world), "")
        T.AssertEqual(Join(r.protected), "B")
        T.AssertEqual(#r.warnings, 2, "one warning per list")
        T.AssertTrue(r.warnings[1]:find("instance", 1, true), r.warnings[1])
        T.AssertTrue(r.warnings[2]:find("world", 1, true), r.warnings[2])
    end)

    --------------------------------------------------------------------------
    -- Diff
    --------------------------------------------------------------------------

    local function Current()
        return {
            instance = Set("DataStore", "Altoholic"),
            world = Set("DBM-Core"),
            protected = { "!BugGrabber", "BugSack", "KeyMode" },
        }
    end

    T.Test("diff replace: adds and removes, with incoming and current spellings", function()
        local incoming = Decoded("KeyMode lists 1\n[instance]\ndatastore\nTSM\n[world]\n[protected]\nbugsack\nWA\n")
        local c = Share.Diff(Current(), incoming, "replace")
        T.AssertEqual(Join(c.instance.add), "TSM")
        T.AssertEqual(Join(c.instance.remove), "Altoholic")
        T.AssertEqual(Join(c.world.add), "")
        T.AssertEqual(Join(c.world.remove), "DBM-Core")
        T.AssertEqual(Join(c.protected.add), "WA")
        T.AssertEqual(Join(c.protected.remove), "!BugGrabber", "KeyMode never removed")
        T.AssertEqual(c.total, 5)
    end)

    T.Test("diff replace: no [protected] section leaves the protect list alone", function()
        local incoming = Decoded("KeyMode lists 1\n[instance]\n[world]\n")
        local c = Share.Diff(Current(), incoming, "replace")
        T.AssertEqual(Join(c.protected.add) .. "|" .. Join(c.protected.remove), "|")
        T.AssertEqual(Join(c.instance.remove), "Altoholic,DataStore")
        T.AssertEqual(c.total, 3)
    end)

    T.Test("diff replace: an empty [protected] section removes all but KeyMode", function()
        local c = Share.Diff(Current(), Decoded("KeyMode lists 1\n[protected]\n"), "replace")
        T.AssertEqual(Join(c.protected.remove), "!BugGrabber,BugSack")
    end)

    T.Test("diff merge: adds only, never removes", function()
        local incoming = Decoded("KeyMode lists 1\n[instance]\nTSM\nALTOHOLIC\n[world]\n[protected]\nWA\n")
        local c = Share.Diff(Current(), incoming, "merge")
        T.AssertEqual(Join(c.instance.add), "TSM", "case-insensitive match is not an add")
        T.AssertEqual(Join(c.instance.remove), "")
        T.AssertEqual(Join(c.world.remove), "")
        T.AssertEqual(Join(c.protected.add), "WA")
        T.AssertEqual(Join(c.protected.remove), "")
        T.AssertEqual(c.total, 2)
    end)

    T.Test("diff: identical lists produce no changes", function()
        local cur = Current()
        local incoming = Decoded(Share.Encode(cur, cur.protected))
        T.AssertEqual(Share.Diff(cur, incoming, "replace").total, 0)
    end)

    --------------------------------------------------------------------------
    -- Apply
    --------------------------------------------------------------------------

    T.Test("apply replace through the real Profiles", function()
        local env = stub.Boot()
        local P = env.ns.Profiles
        P:ListAdd("instance", "DataStore")
        P:ListAdd("instance", "Altoholic")
        P:ListAdd("world", "DBM-Core")
        local current = { instance = P:Lists().instance, world = P:Lists().world, protected = P:ProtectedList() }
        local incoming = Decoded("KeyMode lists 1\n[instance]\nDataStore\nTSM\n[world]\n[protected]\nBugSack\nWA\n")
        local changes = Share.Diff(current, incoming, "replace")
        T.AssertEqual(env.ns.Share.Apply(changes, P), changes.total, "every change applied")
        T.AssertEqual(Join(P:ListNames("instance")), "DataStore,TSM")
        T.AssertEqual(Join(P:ListNames("world")), "")
        T.AssertEqual(Join(P:ProtectedList()), "BugSack,KeyMode,WA")
        T.AssertEqual(env.ns.db.protected["!BugGrabber"], false, "removed default stored as false")
        T.AssertEqual(env.ns.db.lists.instance.Altoholic, nil, "list removal deletes the key")
        T.AssertEqual(env.ns.db.lists.instance.TSM, true)
    end)

    T.Test("apply merge through the real Profiles keeps existing entries", function()
        local env = stub.Boot()
        local P = env.ns.Profiles
        P:ListAdd("world", "DBM-Core")
        local current = { instance = P:Lists().instance, world = P:Lists().world, protected = P:ProtectedList() }
        local incoming = Decoded("KeyMode lists 1\n[world]\nWeakAuras\n")
        local changes = Share.Diff(current, incoming, "merge")
        T.AssertEqual(env.ns.Share.Apply(changes, P), 1)
        T.AssertEqual(Join(P:ListNames("world")), "DBM-Core,WeakAuras")
        T.AssertEqual(Join(P:ProtectedList()), "!BugGrabber,BugSack,KeyMode", "protect list untouched")
    end)
end
