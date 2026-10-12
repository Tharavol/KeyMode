# Changelog

All notable changes to the KeyMode addon are documented in this file.

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
