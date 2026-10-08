KeyMode
=======

World of Warcraft retail addon (12.x / Midnight) that switches a character to a lean,
saved set of addons before Mythic+ and restores the full setup afterwards -- one click,
one `/reload`.

> **Status: pre-release.** Development is tracked in milestones v0.1.0 through v1.0.0;
> see [docs/PLAN.md](docs/PLAN.md). Nothing below is functional until v0.3.0.

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
- **Entry points.** `/keymode` (alias `/km`), an Addon Compartment entry, an optional
  minimap button, and a key binding.

Installation
------------
Copy the folder to:

- Windows: `World of Warcraft\_retail_\Interface\AddOns\KeyMode`

Commands
--------
(alias: `/km`) -- follows the cross-addon slash command standard used by the other
Tharavol addons. The full list arrives with v0.1.0; planned:

- `/keymode` - open the options panel (also: `options`, `config`, `gui`)
- `/keymode on [profile]` / `off` / `toggle` - switch modes (shows the preview first)
- `/keymode preview [profile]` - show what a switch would change, without reloading
- `/keymode status` - current mode, active profile, snapshot age
- `/keymode version`, `/keymode reset`, `/keymode help`, `/keymode debug [on|off]`

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
