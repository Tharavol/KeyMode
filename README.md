KeyMode
=======

World of Warcraft retail addon (12.x / Midnight) that switches a character to a lean
set of addons for Mythic+ dungeons and raids, and back again afterwards -- one command,
one `/reload`.

> **Status: pre-release.** Development is tracked in milestones v0.1.0 through v1.0.0;
> see [docs/PLAN.md](docs/PLAN.md). v0.1.0: the options panel, the commands, the
> minimap button and the Addon Compartment entry. v0.2.0: the addon inventory,
> dependency graph, protect list and safe-to-switch guard, with the enable-state API
> verified in-game. v0.3.0: Instance and World modes and the switch engine. v0.4.0: the
> preview dialog, the list editor, import/export and suggested lists. v0.5.0: the
> switch prompts and the key binding.

Why
---
A typical addon folder carries a lot of weight that does nothing in a dungeon:
profession and auction-house tools, alt trackers, map and collection addons, raid and
legacy boss modules. Most of their cost is SavedVariables parsed at login. Disabling
them by hand in the AddOns list before every key, then re-enabling exactly what was on
before, is tedious and error-prone. KeyMode does both halves.

Features (planned for 1.0)
--------------------------
- **Two modes, two lists.** The Instance list names what to turn off in Mythic
  Keystone dungeons and raids; the optional World list names what to turn off the rest
  of the time (empty by default). Both are account-wide, so they work on every
  character. Nothing to create or name.
- **Snapshot and restore.** The first switch records this character's exact enable
  state as its baseline. Each mode is worked out from that baseline, and Off restores
  precisely it -- not a fixed list. Addons turned on or off by hand in the game's AddOn
  list while in a mode are kept on Off.
- **Dependency aware.** Turning off a library-style addon also turns off everything that
  requires it (DataStore takes Altoholic with it); turning an addon back on brings its
  required dependencies with it. No "missing dependency" errors after a switch.
- **Preview before reload.** A dialog lists what will be turned off and on, and the
  reload happens only on confirmation.
- **Prompts.** Offers Instance mode on entering a raid (LFR included) or a Mythic
  dungeon in a group, or on joining or listing a Mythic+ or raid group, and World mode on
  leaving afterwards. Each prompt is the preview dialog: nothing switches without
  Confirm and Reload. Never in combat (shown when combat ends) or during an active key;
  "Not now" silences that prompt until the next reload, and each can be turned off.
- **Entry points.** `/keymode` (alias `/km`), a minimap button, an Addon Compartment
  entry, and a key binding.

Installation
------------
Copy the folder to:

- Windows: `World of Warcraft\_retail_\Interface\AddOns\KeyMode`

Commands
--------
(alias: `/km`) -- follows the cross-addon slash command standard used by the other
Tharavol addons.

- `/km` - open the options panel (also: `options`, `config`, `gui`)
- `/km instance` - preview turning off the Instance list, then confirm and reload
- `/km world` - preview turning off the World list, then confirm and reload
- `/km off` - preview restoring this character's own setup, then confirm and reload
- `/km toggle` - the same for Instance <-> World (from Off: Instance)
- `/km preview [instance|world|off]` - list what a switch would change in chat
- `/km list [instance|world] [add|remove <addon>|clear|copy <other>]` - show or edit a list
- `/km export` - copy both lists as text, for backup or another account
- `/km import` - paste exported lists; shows the changes before applying
- `/km protect [add|remove <addon>]` - show or edit the addons no switch turns off
- `/km prompts [arrival|group|departure] [on|off]` - show, toggle or set the switch prompts
- `/km status` - show the current mode, list sizes and settings
- `/km version` - show the addon version
- `/km reset` - restore settings to defaults; the lists, the protect list and the mode are kept
- `/km minimap [on|off]` - toggle or set the minimap button
- `/km debug [on|off]` - toggle or set debug messages
- `/km help` - list every command

The minimap button and the Addon Compartment entry (the addon button by the minimap)
do the same thing: left-click opens the preview dialog for a toggle, right-click opens
the options panel. The key binding (Key Bindings > AddOns > KeyMode) does the same as
the left click. The lists are edited under Options > AddOns > KeyMode > Lists, which
also has Suggest, Import and Export. Drag
the minimap button around the minimap edge to move it; minimap-button bars such as
HidingBar can collect it.

Release notes are in [CHANGELOG.md](CHANGELOG.md).

Development
-----------
- `luacheck .` lints the addon.
- `lua scripts/validate-toc.lua` runs the same TOC check CI does, from the repository root.
- `lua tests/run_tests.lua` runs the addon against a stubbed WoW API, from the repository root.
- Design notes and verified API facts: [docs/HANDOFF.md](docs/HANDOFF.md).

License
-------
Copyright (C) 2026 Tharavol. Licensed under the GNU General Public License, version 3
or (at your option) any later version (GPL-3.0-or-later). See [LICENSE](LICENSE) for the
full text.
