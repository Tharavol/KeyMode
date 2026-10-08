# Changelog

All notable changes to the KeyMode addon are documented in this file.

## [Unreleased]

- Minimap button, shown by default: left-click opens options, right-click prints
  status, drag to move it around the minimap edge (round and reshaped minimaps).
  `/km minimap [on|off]` and a "Show minimap button" checkbox toggle it. Built to be
  collectable by minimap-button bars such as HidingBar; no library dependency (#34).

## [0.1.0]

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
