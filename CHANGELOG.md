# Changelog

All notable changes to the KeyMode addon are documented in this file.

## [0.4.0]

Switching and list editing without slash commands.

- Preview dialog: every switch, from a command, the minimap button or the Addon
  Compartment entry, first lists what will be turned off and on (cascade entries
  marked, protected and not-installed entries shown) and switches only on Confirm and
  Reload. Left-click on the minimap button now opens it; right-click opens the options
  (#17).
- List editor: Options > AddOns > KeyMode > Lists, with an Instance and a World
  checkbox per addon, search, a "show only listed" filter, dependents nested under
  their parent and shown with a dimmed tick when their parent is listed, and protected
  addons locked (#18).
- Clear a list or copy one into the other, from the Lists page or with `/km list
  instance clear` and `/km list world copy instance` (#19).
- Import and export: both lists, and optionally the protect list, as plain text.
  `/km export`, `/km import`, or the buttons on the Lists page. Import shows every
  change before Merge or Replace (#20).
- Suggested lists: the Suggest button fills both lists with pending ticks from each
  addon's TOC category and known name patterns (profession and auction tools,
  collections, maps, legacy and open-world DBM modules, other regions' Raider.IO
  databases for Instance; DBM raid and dungeon modules for World). Nothing is saved
  until Accept (#21).
- `/km debug probe categories` lists the `## Category` values in use.

## [0.3.0]

Switching, from the command line. Named profiles are replaced by two fixed lists (#37):
**Instance** for Mythic Keystone dungeons and raids, and **World** for the rest of the
time (empty by default).

- Saved data moves to schema version 2: the Instance and World lists replace the empty
  `profiles` table, which an upgrade removes. The protect list and settings are kept
  (#11).
- The first switch records this character's own setup as its baseline (#12).
- The switch plan works out what each mode turns off: the mode's list plus every addon
  that requires something on it. Protected addons, and everything they need, stay on
  (#13).
- `/km instance`, `/km world` and `/km off` apply the plan for this character only,
  save and reload. Off restores the baseline exactly. After each login, addons changed
  by hand in the AddOn list while in a mode are kept on Off, and a listed addon that is
  on anyway is reported (#14).
- The mode survives logout and crashes. Logging in to Instance mode outside an
  instance and a group prints the way back (#15).
- New commands: `toggle`, `preview [instance|world|off]`, `list [instance|world]
  [add|remove <addon>]` and `protect [add|remove <addon>]`. `status`, the tooltip and
  the options panel show the mode (Instance, World or Off). `on` is gone (#16).

## [0.2.0]

Addon inventory and live API verification. Still no switching; that is v0.3.0.

- The enable-state API was verified in-game across characters and realms; the results
  are in docs/HANDOFF.md. `/km debug probe` is the diagnostic used, with a throwaway
  `KeyModeProbe` test addon (not shipped) (#6).
- Inventory of installed addons: title, loadable/reason, load-on-demand, loaded, this
  character's enable state, and dependencies (#7).
- Dependency graph: what turning an addon off also turns off, and what turning it on
  needs. Dependency names match regardless of case; missing dependencies and cycles are
  handled (#8).
- Protect list: KeyMode can never be turned off, and BugGrabber and BugSack are
  protected by default. The list is kept by `/km reset` (#9).
- Safe-to-switch check: not in combat, not in an active keystone, not during a boss
  encounter. `/km status` shows the protect list and whether a switch is allowed now
  (#10).

## [0.1.0]

First pre-release: scaffolding, the command surface and the entry points. Switching
itself arrives in v0.3.0.

- Repository scaffolding: TOC, `Core.lua` (namespace, `ns.Print`, version helper,
  SavedVariables defaults), CI (luacheck, TOC validation, stub-API tests, packager dry
  run), release and pre-release workflows, daily TOC Interface check, and docs.
- File layout in TOC load order: Inventory, Profiles, Switch, Triggers, UI, Options,
  Commands (#1).
- `/keymode` and `/km`, conforming to the cross-addon slash command standard: options,
  status, version, reset, debug and help. `on`, `off`, `toggle` and `preview` are listed
  and report that switching is not available yet (#2).
- Options panel under Options > AddOns > KeyMode with the mode, a debug checkbox and
  Reset to Defaults. Reset restores settings only; profiles and pending restores are
  kept (#3).
- Addon Compartment entry: left-click opens options, right-click prints status, and
  the tooltip shows the mode (#4).
- Test stub models installed addons, dependencies and per-character enable state (#5).
- Minimap button, shown by default: left-click opens options, right-click prints
  status, drag to move it around the minimap edge (round and reshaped minimaps).
  `/km minimap [on|off]` and a "Show minimap button" checkbox toggle it. Built to be
  collectable by minimap-button bars such as HidingBar; no library dependency (#34).
