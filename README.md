KeyMode
=======

World of Warcraft retail addon (12.x / Midnight) that switches a character to a lean,
saved set of addons before Mythic+ and restores the full setup afterwards -- one click,
one `/reload`.

> **Status: pre-release.** Development is tracked in milestones v0.1.0 through v1.0.0;
> see [docs/PLAN.md](docs/PLAN.md). The options panel, the commands and the Addon
> Compartment entry work; switching itself arrives with v0.3.0.

Why
---
A typical addon folder carries a lot of weight that does nothing in a dungeon:
profession and auction-house tools, alt trackers, map and collection addons, raid and
legacy boss modules. Most of their cost is SavedVariables parsed at login. Disabling
them by hand in the AddOns list before every key, then re-enabling exactly what was on
before, is tedious and error-prone. KeyMode does both halves.

Features (planned for 1.0)
--------------------------
- **Snapshot and restore.** Entering M+ mode records this character's exact enable
  state first, so leaving it restores precisely that -- not a fixed list.
- **Profiles.** Account-wide named profiles listing which addons to turn off. The same
  profile works on every character.
- **Dependency aware.** Turning off a library-style addon also turns off everything that
  requires it (DataStore takes Altoholic with it); turning an addon back on brings its
  required dependencies with it. No "missing dependency" errors after a switch.
- **Preview before reload.** A dialog lists what will be turned off and on, and the
  reload happens only on confirmation.
- **Prompt on arrival.** Optionally offers to switch on entering a Mythic+ dungeon or
  joining a keystone group, and to switch back on leaving. Never prompts in combat or
  during an active keystone, and never switches without a click.
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
- `/km on [profile]` - switch to M+ mode, showing the preview first *(v0.3.0)*
- `/km off` - restore the addons this character had before *(v0.3.0)*
- `/km toggle` - switch to whichever mode is not active *(v0.3.0)*
- `/km preview [profile]` - list what a switch would change, without reloading *(v0.3.0)*
- `/km status` - show the current mode and settings
- `/km version` - show the addon version
- `/km reset` - restore settings to defaults; profiles and pending restores are kept
- `/km minimap [on|off]` - toggle or set the minimap button
- `/km debug [on|off]` - toggle or set debug messages
- `/km help` - list every command

The minimap button and the Addon Compartment entry (the addon button by the minimap)
do the same thing: left-click opens the options panel, right-click prints status. Drag
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
