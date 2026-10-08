# KeyMode development plan

Six milestones, each a GitHub milestone of the same name with one issue per bullet.
Each milestone ends with a tagged release of that version. Every v0.x tag is published
as a GitHub pre-release (`release.yml` flags it); v1.0.0 is the first stable release. Work is merged in milestone order -- later milestones
build on the switch engine, so it lands and is verified before any UI goes on top of it.

| Milestone | Theme | Exit criteria |
| --- | --- | --- |
| v0.1.0 | Scaffolding and command surface | Addon loads clean, `/km help` works, CI green |
| v0.2.0 | Addon inventory and live API verification | Every C_AddOns assumption confirmed in-game and written down |
| v0.3.0 | Profiles and the switch engine | Enter/exit M+ mode from the command line, restore is exact |
| v0.4.0 | Preview dialog and profile editor | No profile editing or switching needs a slash command |
| v0.5.0 | Triggers and entry points | Arrival and departure prompts, key binding |
| v1.0.0 | Polish pass and stable release | QA matrix passed, docs final, v1.0.0 tagged and released |

## v0.1.0 -- Scaffolding and command surface

- **Addon skeleton.** File-per-concern layout matching the other Tharavol addons, in TOC
  load order: `Core.lua` (exists), `Inventory.lua`, `Profiles.lua`, `Switch.lua`,
  `Triggers.lua`, `UI.lua`, `Options.lua`, `Commands.lua`. Each file starts as a
  documented stub so later issues only fill in bodies.
- **Slash command dispatch: `/keymode`, `/km`.** Table-driven, conforming to the
  cross-addon slash command standard (S1-S13): bare opens options, `help`, `version`,
  `status`, `reset`, `debug [on|off]`, unknown input named. Mode commands are registered
  but report "not yet available" until v0.3.0.
- **Options panel skeleton.** Settings API canvas category with the version label,
  a General page, and a "Reset to Defaults" button sharing code with `/km reset`.
- **Addon Compartment entry and icon.** `## AddonCompartmentFunc` opening the options
  panel. Verify in-game that `INV_Relics_Hourglass` renders as the keystone icon;
  pick another if not.
- **Test harness: C_AddOns fixture model.** Extend `tests/stub_api.lua` with an
  installed-addon table (name, title, deps, LoD, per-character enable state) so the
  engine issues in v0.2.0-v0.3.0 can be test-first.

## v0.2.0 -- Addon inventory and live API verification

- **Live-verify the enable-state API.** Blizzard's own AddOn list (Gethe/wow-ui-source,
  `Blizzard_AddOnList/AddonList.lua`, `live` branch) passes `UnitGUID("player")` as the
  `character` argument in-game and `nil` for "all characters"; the generated docs list
  the parameter as non-nilable with default `"0"`. Confirm with a `/km debug probe` on a
  throwaway addon: which character argument changes only this character, whether
  `C_AddOns.SaveAddOns()` is needed before `ReloadUI()`, and what `AddOns.txt` looks
  like afterwards. Record the results in docs/HANDOFF.md before building on them.
- **Inventory.** Enumerate installed addons: folder name, title, loadable/reason,
  load-on-demand, enable state for this character, required and optional dependencies.
- **Dependency graph.** Forward dependencies and reverse dependents, tolerant of missing
  dependencies and cycles. Pure functions, fully covered by tests.
- **Protected addons.** KeyMode itself can never be disabled. A user-editable protect
  list (default: BugGrabber, BugSack) is skipped by every profile.
- **Minimap button.** Hand-made, no library, shown by default, draggable, with the same
  click actions as the compartment entry and a `/km minimap` toggle. Collectable by
  HidingBar. (Moved here from v0.5.0 after the v0.1.0 check, #34.)
- **Safe-to-switch guard.** One function answering "may a switch happen now, and if not
  why": combat lockdown, an active keystone (`C_ChallengeMode.IsChallengeModeActive`),
  an encounter in progress. Every entry point goes through it.

## v0.3.0 -- Profiles and the switch engine

- **SavedVariables schema v1.** `KeyModeDB.profiles[name] = { disable = {...} }`,
  `activeProfile`, `snapshots[guid] = { taken, profile, state = {...} }`, a migration
  hook keyed on `dbVersion`.
- **Snapshot.** Before any switch, record every installed addon's enable state for this
  character. A snapshot is never overwritten while one is pending restore.
- **Switch plan.** Pure function: (inventory, profile, protect list) -> list of addons
  to disable, including dependents that would otherwise fail to load. Tested against
  real-world shapes (DataStore/Altoholic, Details plugins, DBM modules).
- **Enter and exit.** Apply the plan, save, reload. Exit restores the snapshot exactly,
  enabling required dependencies first; addons installed since the snapshot are left as
  they are, addons removed since are skipped and reported.
- **Recovery.** The mode flag and snapshot survive logout and crashes. Logging in while
  still in M+ mode and not in a group prints a one-line reminder with the exit command.
- **Commands.** `on [profile]`, `off`, `toggle`, `preview [profile]` (text diff in chat),
  `status`, `profile list|create|delete|add|remove`.

## v0.4.0 -- Preview dialog and profile editor

- **Preview dialog.** "Will turn off" / "Will turn on" lists with counts and
  dependency-cascade entries marked; Confirm and Reload / Cancel. Every switch path uses it.
- **Profile editor.** In options: searchable addon list with checkboxes, dependents
  nested under their parent, check/uncheck a whole group, protected addons shown locked.
- **Profile management.** Create, rename, copy, delete, choose the default profile.
- **Import and export.** A profile as a copyable string, for backup and for moving
  between accounts.
- **Suggested profile.** A one-time "suggest a starting profile" action grouping addons
  by heuristics (TOC `## Category` metadata if present -- verify the field on 12.x --
  plus known patterns: `DBM-Raids-*`, non-local `RaiderIO_DB_*`, profession and AH
  tools). Shows the suggestion in the editor; never applies it on its own.

## v0.5.0 -- Triggers and entry points

- **Arrival prompt.** On entering a Mythic or Mythic Keystone dungeon (instance
  difficulty 23 / 8) outside M+ mode, offer the switch through the preview dialog.
- **Group prompt.** On joining a premade group whose listing is a Mythic+ activity, or
  listing one's own key, offer the switch.
- **Departure prompt.** In M+ mode, after `CHALLENGE_MODE_COMPLETED` and leaving the
  instance, or on leaving the group, offer to restore.
- **Prompt rules.** Never in combat or during an active key; "not now" snoozes for the
  session; each trigger has its own toggle in options.
- **Key binding.** `Bindings.xml` toggle binding. (The minimap button moved to v0.2.0.)

## v1.0.0 -- Polish pass and stable release

- **Test coverage.** Every pure function in Inventory/Profiles/Switch covered, including
  the dependency edge cases found during v0.2.0-v0.5.0.
- **In-game QA matrix.** Several characters on different realms; addons added and
  removed between switches; load-on-demand addons; an addon with a load error; deep
  dependency trees (DBM, Details, DataStore); reload during a prompt; logout in M+ mode.
- **Rough-edge sweep.** No new scope: wording, layout at different UI scales, chat
  noise, options panel clipping, error handling in every C_AddOns call.
- **Docs and metadata.** README final, `## X-ReleaseNotes`, CHANGELOG versioned,
  HANDOFF current.
- **Release.** Tag v1.0.0, verify the release workflow and archive layout, close the
  issues and the milestone.
