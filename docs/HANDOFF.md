# Handoff Notes

## Project summary

KeyMode is a World of Warcraft addon for Retail / Midnight that switches the current
character to a saved, lean set of addons before Mythic+ and restores the previous set
afterwards. A switch is: snapshot this character's enable state, disable the profile's
addons (plus anything that depends on them), save, `ReloadUI()`. Leaving restores the
snapshot.

## Current state

- v0.1.0 released as a pre-release. Next: v0.2.0 (inventory and live API
  verification, starting with #6). Files, in TOC load order:
  - `Core.lua` -- namespace, `ns.Print`, `ns.Debug`, `ns.GetAddonVersion`, SavedVariables
    defaults, `ns.ResetSettings`, the `ADDON_LOADED` handler.
  - `Inventory.lua`, `Profiles.lua`, `Triggers.lua` -- module tables only (v0.2.0-v0.5.0).
  - `Switch.lua` -- `Switch:IsActive()`, always false until v0.3.0.
  - `UI.lua` -- Addon Compartment handlers (globals named in the TOC) and the minimap
    button (#34); both route through `UI:OnEntryClick` / `UI:ShowEntryTooltip`.
  - `Options.lua` -- Settings canvas panel; `Options.CHECKBOXES` drives the General
    section; `Options:Refresh()` re-reads every widget from `ns.db`.
  - `Probe.lua` -- `/km debug probe`, the in-game enable-state checks for #6 (see
    "Enable-state probe procedure").
  - `Commands.lua` -- loads last; `/keymode`, `/km`; `Commands.COMMANDS` drives both
    dispatch and help.
- Tests: `tests/stub_api.lua` loads every file `KeyMode.toc` lists, in TOC order, into
  an isolated environment per test; `tests/run_tests.lua` runs the `*_spec.lua` files.
  The stub models installed addons (`stub.AddAddon`), dependencies and per-character
  enable state; `stub_spec.lua` pins that model. Character keys resolve the way the live
  client was seen to resolve them (#6, "API facts").
- Settings plumbing: writers call `ns.SettingsChanged()`; views register with
  `ns.OnSettingsChanged(fn)`. Startup work needing `ns.db` registers with
  `ns.OnLoaded(fn)`, run at KeyMode's `ADDON_LOADED` in TOC order.
- Checked in-game (PR #35 checklist): the minimap button's look, clicks, tooltip,
  dragging and persistence over `/reload`, `/km minimap` and checkbox sync, collection
  by HidingBar, and HidingBar keeping it when it is hidden and shown again (#34).
  Reshaped (non-round) minimaps have not been tried in-game.
- Checked in-game (PR #32 checklist): panel layout and debug checkbox/`/km debug` sync
  (#3), the compartment entry, its click/hover behaviour and the `INV_Relics_Hourglass`
  keystone icon (#4), and `help`/`status`/unknown-command output (#2). KeyMode does not
  appear in HidingBar: HidingBar collects LibDataBroker launchers and minimap buttons,
  not individual compartment entries. Decided: a hand-made minimap button instead of a
  broker launcher (#34).
- `## Version` in the TOC is the literal `@project-version@`, substituted by the
  packager from the release tag. Do not edit it.
- License: GPL-3.0-or-later. `LICENSE` is the full GPLv3 text; `Core.lua` (the first
  file the TOC loads) carries the "or any later version" notice header. Other files
  carry only the SPDX line.
- Credits: created by Tharavol, built with Claude via Claude Code.

## API facts

Verified against source, then checked in-game with `/km debug probe` on 2026-10-12
(#6): Interface 120100, 192 addons, three characters -- A and B on one
realm, C on another. "yes (#6)" means the live client did exactly this.

| Fact | Source | Live |
| --- | --- | --- |
| `C_AddOns.EnableAddOn(name, character)`, `DisableAddOn`, `GetAddOnEnableState` take a `character` cstring, documented non-nilable with default `"0"` | `Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua` | nil is accepted without error by all three (#6) |
| Blizzard's in-game AddOn list passes `UnitGUID("player")` as `character`, and `nil` for "All characters" | `Blizzard_AddOnList/AddonList.lua` (`addonCharacter = UnitGUID("player")`, `GetAddonCharacter`) | yes (#6) |
| `UnitGUID("player")` and `UnitName("player")` address the same character: a change through either reads back identically through both | probe | yes (#6) |
| A change by GUID, saved, reaches only this character: B (same realm) and C (other realm) still loaded the fixture | probe, steps 7-8 | yes (#6) |
| A change by nil, saved, reaches every character, across realms | probe, steps 10-11 | yes (#6) |
| As a query, `"0"` answers the same as nil (the across-characters aggregate). Its reach as a mutation was not tested across characters, so KeyMode never passes it | probe | partly (#6) |
| `"Name-Realm"` is not a character key: queries answer All whatever the state, mutations do nothing | probe, step 3e | yes (#6) |
| The nil aggregate counts only characters that have an entry for the addon. A brand-new addon has one only for characters it was set on, so `nil` read None after disabling it for one character; after an "all characters" change it read Some (others still on). Explanation inferred from the data | probe | inferred (#6) |
| A change shows in `GetAddOnEnableState` at once, and takes effect at the next `/reload` even **without** `SaveAddOns()` | probe, step 3 | yes (#6) |
| `ResetAddOns()` undoes every unsaved change at once, so anything that calls it between KeyMode's changes and the reload (Blizzard's AddOn list "Cancel") would discard a switch. KeyMode calls `SaveAddOns()` and then `ReloadUI()` in the same click | probe, step 6 | yes (#6) |
| Enabled means `GetAddOnEnableState(i, character) > Enum.AddOnEnableState.None` | `AddonList.lua` | yes (#6) |
| Blizzard calls `C_AddOns.SaveAddOns()` on "Okay" and `C_AddOns.ResetAddOns()` on "Cancel" | same | -- |
| `GetAddOnInfo` reason is `""` (not nil) when there is nothing to report; also seen: `DEMAND_LOADED`, `DISABLED` | probe scan | yes (#6) |
| `GetAddOnDependencies` returns names exactly as the TOC spells them (`keymode`, not `KeyMode`), so dependency matching must be case-insensitive (#8 does this). Dependencies on Blizzard addons (`Blizzard_Professions`) are not in the addon list and show up as missing | probe scan | yes (#6) |
| `## Category` metadata is readable through `GetAddOnMetadata(i, "Category")`; 107 of 192 installed addons set it (#21) | probe scan | yes (#6) |
| `IsEncounterInProgress`, `C_ChallengeMode.IsChallengeModeActive` and `UnitFullName` exist on 12.x (#10) | probe scan | yes (#6) |
| The Addon Compartment passes `UnitName("player")` (not the GUID) and counts an addon only when `GetAddOnEnableState(i, name) == Enum.AddOnEnableState.All`; `Enum.AddOnEnableState` is None = 0, Some = 1, All = 2 | `Blizzard_Minimap/Mainline/AddonCompartment.lua`, `AddOnsDocumentation.lua` | values yes (#6) |
| Compartment TOC fields are `AddonCompartmentFunc`, `AddonCompartmentFuncOnEnter`, `AddonCompartmentFuncOnLeave`, called as globals with `(addonName, buttonName)` and `(addonName, menuButton)`; icon from `IconTexture` or `IconAtlas` | `AddonCompartment.lua` | yes (PR #32) |
| Enable state is stored per character in `WTF\Account\<ACCOUNT>\<Realm>\<Character>\AddOns.txt` as `Name: enabled|disabled`. At exit the client rewrote that file for every character with an entry for a changed addon (30 of 49), not only those logged in. Not every installed addon appears (KeyMode itself does not), so the file is no substitute for the API and KeyMode never reads it | observed on disk | yes (#6) |

Decision for v0.3.0: the switch engine passes `UnitGUID("player")` to every enable-state
call, calls `SaveAddOns()` then `ReloadUI()`, and never passes nil or `"0"`.

Source: `Gethe/wow-ui-source`, `live` branch, fetched 2026-10-08.

### Enable-state probe procedure (#6)

`/km debug probe` (`Probe.lua`) prints what the client reports; its mutations touch only
the `KeyModeProbe` fixture. Setup: copy `tests/fixtures/KeyModeProbe` into
`Interface\AddOns`, log in on character A, and keep character B (same realm) and C
(another realm) for the cross-character checks. `<key>` is one of `guid`, `name`,
`full` (Name-Realm), `zero` (`"0"`), `all` (nil).

1. `/km debug probe scan` -- reason strings, dependency-name case, missing deps,
   `## Category` count, and whether `IsEncounterInProgress` /
   `C_ChallengeMode.IsChallengeModeActive` exist. Record the output.
2. `/km debug probe` -- baseline states for every key; `deps (as returned)` shows
   whether `keymode` comes back lowercased or as the folder name.
3. For each of `guid`, `name`, `zero`, `all`: `/km debug probe disable <key>` (does the
   report change at once, and under which keys?), then `/reload` without saving -- did
   `KeyModeProbe: loaded` print? Re-enable with the same key before the next one.
4. `/km debug probe disable guid`, `/km debug probe save`, `/reload` -- the fixture must
   not load. Repeat without `save` to learn whether `SaveAddOns()` is required.
5. `/km debug probe disable guid`, `/km debug probe reset` -- does `ResetAddOns()` undo
   an unsaved change?
6. With the fixture disabled by `guid` and saved: log out, read
   `WTF\Account\<ACCOUNT>\<Realm>\<A>\AddOns.txt`, then log in on B and C -- the fixture
   must still load there.
7. Disable by `all` and save; check B and C again, then restore.

Every probe line, plus an automatic report at each login or reload while the log is
non-empty, is kept in `KeyModeDB.probeLog` (`WTF\Account\<ACCOUNT>\SavedVariables\KeyMode.lua`,
written at logout or reload). `/km debug probe clear` empties it.

Results go in the "API facts" table above (and the stub's character-key model is
corrected to match) before #7 builds on them.

### Minimap button (#34)

| Fact | Source | Live |
| --- | --- | --- |
| HidingBar collects a child of `Minimap` or `MinimapBackdrop` that is named, unprotected, square (sides within 5px), larger than 16px and under half the minimap's size, with an `OnClick`/`OnMouseUp`/`OnMouseDown` script | HidingBar v12.1.5 `HidingBar.lua`, `grabMinimapAddonsButtons`, `addMButton` | yes (PR #35) |
| HidingBar scans in `C_Timer.After(0)` after its own `ADDON_LOADED` (optionally again after a delay), so a button made at KeyMode's `ADDON_LOADED` exists by then | same, `ADDON_LOADED` -> `setProfile` -> `init` | yes (PR #35) |
| Mainline minimap button layout: 31px button, `MEDIUM` strata level 8; border 136430 at 50x50 `TOPLEFT`; background 136467 at 24x24 `CENTER`; icon 18x18 `CENTER`; highlight 136477; 5px beyond the edge; default angle 225 | LibDBIcon-1.0 MINOR 56 (bundled with HidingBar) | yes (PR #35) |
| `GetMinimapShape` shape names and which quadrants each rounds | same, `minimapShapes` | -- |

LibDBIcon's bundled copy carries no license header or file, so KeyMode reuses only
these facts; `UI.lua`'s code is its own, and `minimap_spec.lua` checks the shape rule
against LibDBIcon's table as data.

## Design rules

- **Never switch without a click.** Triggers only ever open the preview dialog.
- **Restore is exact.** Exit restores the snapshot, not "everything the profile turned
  off". Anything the player changed by hand while in M+ mode is overwritten on restore;
  the preview dialog says so.
- **One guard.** Every switch path calls the same safe-to-switch check (combat, active
  keystone, encounter).
- **Pure planning, thin applying.** Inventory, dependency graph and switch plan are pure
  functions over plain tables so they can be tested offline; only `Switch.lua` calls the
  mutating C_AddOns functions. The one exception is `Probe.lua` (#6), which only ever
  changes the `KeyModeProbe` fixture addon.
- **KeyMode is always protected.** It can never appear in a disable plan.
