# Handoff Notes

## Project summary

KeyMode is a World of Warcraft addon for Retail / Midnight that switches the current
character to a saved, lean set of addons before Mythic+ and restores the previous set
afterwards. A switch is: snapshot this character's enable state, disable the profile's
addons (plus anything that depends on them), save, `ReloadUI()`. Leaving restores the
snapshot.

## Current state

- Scaffolding only. `Core.lua` holds the namespace, `ns.Print`, `ns.GetAddonVersion`,
  SavedVariables defaults and the `ADDON_LOADED` handler. Everything else is planned in
  [PLAN.md](PLAN.md) and tracked as GitHub milestones v0.1.0-v1.0.0.
- Tests: `tests/stub_api.lua` loads every file `KeyMode.toc` lists, in TOC order, into
  an isolated environment per test; `tests/run_tests.lua` runs the `*_spec.lua` files.
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
