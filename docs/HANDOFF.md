# Handoff Notes

## Project summary

KeyMode is a World of Warcraft addon for Retail / Midnight that switches the current
character to a saved, lean set of addons before Mythic+ and restores the previous set
afterwards. A switch is: snapshot this character's enable state, disable the profile's
addons (plus anything that depends on them), save, `ReloadUI()`. Leaving restores the
snapshot.

## Current state

- v0.1.0 in progress. Files, in TOC load order:
  - `Core.lua` -- namespace, `ns.Print`, `ns.Debug`, `ns.GetAddonVersion`, SavedVariables
    defaults, `ns.ResetSettings`, the `ADDON_LOADED` handler.
  - `Inventory.lua`, `Profiles.lua`, `Triggers.lua` -- module tables only (v0.2.0-v0.5.0).
  - `Switch.lua` -- `Switch:IsActive()`, always false until v0.3.0.
  - `UI.lua` -- Addon Compartment handlers (globals named in the TOC).
  - `Options.lua` -- Settings canvas panel; `Options.CHECKBOXES` drives the General
    section; `Options:Refresh()` re-reads every widget from `ns.db`.
  - `Commands.lua` -- loads last; `/keymode`, `/km`; `Commands.COMMANDS` drives both
    dispatch and help.
- Tests: `tests/stub_api.lua` loads every file `KeyMode.toc` lists, in TOC order, into
  an isolated environment per test; `tests/run_tests.lua` runs the `*_spec.lua` files.
  The stub models installed addons (`stub.AddAddon`), dependencies and per-character
  enable state; `stub_spec.lua` pins that model. Character keys (GUID, name, nil) are
  treated as distinct until #6 says how the client resolves them.
- Not yet checked in-game: panel layout (#3), the compartment entry and the
  `INV_Relics_Hourglass` icon (#4).
- `## Version` in the TOC is the literal `@project-version@`, substituted by the
  packager from the release tag. Do not edit it.
- License: GPL-3.0-or-later. `LICENSE` is the full GPLv3 text; `Core.lua` (the first
  file the TOC loads) carries the "or any later version" notice header. Other files
  carry only the SPDX line.
- Credits: created by Tharavol, built with Claude via Claude Code.

## API facts

Verified against source; live in-game confirmation is a v0.2.0 issue. Until then treat
the "live" column as unconfirmed.

| Fact | Source | Live |
| --- | --- | --- |
| `C_AddOns.EnableAddOn(name, character)`, `DisableAddOn`, `GetAddOnEnableState` take a `character` cstring, documented non-nilable with default `"0"` | `Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua` | -- |
| Blizzard's in-game AddOn list passes `UnitGUID("player")` as `character`, and `nil` for "All characters" | `Blizzard_AddOnList/AddonList.lua` (`addonCharacter = UnitGUID("player")`, `GetAddonCharacter`) | -- |
| Enabled means `GetAddOnEnableState(i, character) > Enum.AddOnEnableState.None` | same | -- |
| Blizzard calls `C_AddOns.SaveAddOns()` on "Okay" and `C_AddOns.ResetAddOns()` on "Cancel" | same | -- |
| The Addon Compartment passes `UnitName("player")` (not the GUID) and counts an addon only when `GetAddOnEnableState(i, name) == Enum.AddOnEnableState.All`; `Enum.AddOnEnableState` is None = 0, Some = 1, All = 2 | `Blizzard_Minimap/Mainline/AddonCompartment.lua`, `AddOnsDocumentation.lua` | -- |
| Compartment TOC fields are `AddonCompartmentFunc`, `AddonCompartmentFuncOnEnter`, `AddonCompartmentFuncOnLeave`, called as globals with `(addonName, buttonName)` and `(addonName, menuButton)`; icon from `IconTexture` or `IconAtlas` | `AddonCompartment.lua` | -- |
| Enable state is stored per character in `WTF\Account\<ACCOUNT>\<Realm>\<Character>\AddOns.txt` as `Name: enabled|disabled` and rewritten by the client on logout | observed on disk | -- |

Source: `Gethe/wow-ui-source`, `live` branch, fetched 2026-10-08.

## Design rules

- **Never switch without a click.** Triggers only ever open the preview dialog.
- **Restore is exact.** Exit restores the snapshot, not "everything the profile turned
  off". Anything the player changed by hand while in M+ mode is overwritten on restore;
  the preview dialog says so.
- **One guard.** Every switch path calls the same safe-to-switch check (combat, active
  keystone, encounter).
- **Pure planning, thin applying.** Inventory, dependency graph and switch plan are pure
  functions over plain tables so they can be tested offline; only `Switch.lua` calls the
  mutating C_AddOns functions.
- **KeyMode is always protected.** It can never appear in a disable plan.
