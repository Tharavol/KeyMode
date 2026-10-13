# KeyMode development plan

Six milestones, each a GitHub milestone of the same name with one issue per bullet.
Each milestone ends with a tagged release of that version. Every v0.x tag is published
as a GitHub pre-release (`release.yml` flags it); v1.0.0 is the first stable release.
Work is merged in milestone order -- later milestones build on the switch engine, so it
lands and is verified before any UI goes on top of it.

| Milestone | Theme | Exit criteria | Status |
| --- | --- | --- | --- |
| v0.1.0 | Scaffolding and command surface | Addon loads clean, `/km help` works, CI green | Released 2026-10-08 |
| v0.2.0 | Addon inventory and live API verification | Every C_AddOns assumption confirmed in-game and written down | Released 2026-10-12 |
| v0.3.0 | Instance and World lists, switch engine | Instance, World and Off from the command line, restore is exact | Released 2026-10-12 |
| v0.4.0 | Preview dialog and list editor | No list editing or switching needs a slash command | Released 2026-10-12 |
| v0.5.0 | Triggers and entry points | Arrival and departure prompts, key binding | Released 2026-10-12 |
| v1.0.0 | Polish pass and stable release | QA matrix passed, docs final, v1.0.0 tagged and released | In progress |

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
- **Minimap button.** Hand-made, no library, shown by default, draggable, with the same
  click actions as the compartment entry and a `/km minimap` toggle. Collectable by
  HidingBar. (Added after the in-game check, moved from v0.5.0, #34.)
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
- **Safe-to-switch guard.** One function answering "may a switch happen now, and if not
  why": combat lockdown, an active keystone (`C_ChallengeMode.IsChallengeModeActive`),
  an encounter in progress. Every entry point goes through it.

## v0.3.0 -- Instance and World lists, and the switch engine

Named profiles were replaced by two fixed lists before this milestone started (#37).
The milestone and issue titles keep their original names.

- **Two fixed addon sets: Instance and World (#37).** Instance mode (Mythic Keystone
  dungeons and raids) = baseline - Instance list - cascade, with World-list addons back
  on; World mode = baseline - World list - cascade (empty World list: the baseline);
  Off = baseline restored exactly.
- **SavedVariables schema v2 (#11).** `lists = { instance, world }`, `snapshots[guid] =
  { taken, mode, state }`; migrations keyed on `dbVersion` run before defaults, and
  1 -> 2 drops the always-empty `profiles`.
- **Snapshot (#12).** The first switch records every installed addon's enable state for
  this character as its baseline. It is never overwritten while pending restore.
- **Switch plan (#13).** Pure function: (inventory, baseline, mode, lists, protect list)
  -> addons to turn off (listed or cascade) and on. Protected addons and everything they
  require stay on. Tested against DataStore/Altoholic, Details plugins, DBM modules and
  the cascades found in-game in v0.2.0.
- **Enter and exit (#14).** Apply by GUID, save, reload. Off restores the baseline and
  deletes the snapshot; addons installed since are left as they are, addons removed
  since are reported. A login check folds hand changes into the baseline and reports
  listed addons that are on anyway.
- **Recovery (#15).** Mode and baseline live in SavedVariables. Logging in in Instance
  mode outside an instance and a group prints the way back.
- **Commands (#16).** `instance`, `world`, `off`, `toggle`, `preview [instance|world|off]`,
  `list [instance|world] [add|remove <addon>]`, `protect [add|remove <addon>]`, `status`.

## v0.4.0 -- Preview dialog and list editor

- **Preview dialog (#17).** "Will turn off" / "Will turn on" lists with counts and
  cascade entries marked; the title names the target mode. Confirm and Reload / Cancel.
  Every switch path uses it.
- **List editor (#18).** In options: Instance and World side by side, a searchable addon
  list with a checkbox per list, dependents nested under their parent, check/uncheck a
  whole group, protected addons shown locked.
- **List management (#19).** Clear a list; copy one list into the other.
- **Import and export (#20).** Both lists (optionally the protect list) as one copyable
  string; import shows what would change first.
- **Suggested lists (#21).** A one-time action filling both lists by heuristics (TOC
  `## Category` metadata, verified on 12.x, plus known patterns such as `DBM-Raids-*`,
  non-local `RaiderIO_DB_*`, profession and AH tools). Shown in the editor; never
  applied on its own.

## v0.5.0 -- Triggers and entry points

- **Arrival prompt (#22).** On entering a raid (any difficulty) or a Mythic dungeon
  (difficulty 23) in a group, outside Instance mode, offer the switch through the
  preview dialog. Normal and Heroic dungeons, and solo visits, do not trigger it.
- **Group prompt (#23).** On joining a premade group listed as a Mythic+ or raid
  activity, or listing one's own key or raid, offer Instance mode.
- **Departure prompt (#24).** In Instance mode, after `CHALLENGE_MODE_COMPLETED` and
  leaving the instance, after leaving a raid, or on leaving the group, offer World mode.
- **Prompt rules (#25).** Never in combat (deferred to its end) or during an active key;
  "not now" snoozes until the next reload; each trigger has its own toggle in options and
  `/km prompts`. `/km debug trigger` shows a simulated prompt.
- **Key binding (#26).** `Bindings.xml` toggle binding. (The minimap button moved to v0.1.0.)

## v1.0.0 -- Polish pass and stable release

- **Test coverage (#27).** Every pure function in Inventory/Profiles/Switch covered,
  including the dependency edge cases found during v0.2.0-v0.5.0. A line-coverage run
  over the suite drove the additions.
- **In-game QA matrix (#28).** Several characters on different realms; addons added and
  removed between switches; load-on-demand addons; an addon with a load error; deep
  dependency trees (DBM, Details, DataStore); reload during a prompt; logout in M+ mode.
  Plus the v0.5.0 cases so far covered only offline: arrival in a Mythic dungeon,
  departure after a completed key, the group prompt as an applicant, and a prompt
  deferred by combat.
- **Code polish pass (#42).** Developer probes kept out of the packaged zip, guarded
  C_AddOns calls in Switch and Inventory, dead code and stale comments removed, stricter
  luacheck.
- **Rough-edge sweep (#29).** No new scope: wording, layout at different UI scales, chat
  noise, options panel clipping, error handling in every C_AddOns call.
- **Docs and metadata (#30).** README final, `## X-ReleaseNotes`, CHANGELOG versioned,
  HANDOFF current.
- **Release (#31).** Tag v1.0.0, verify the release workflow and archive layout, close
  the issues and the milestone.

## After 1.0

Unscheduled; each is a backlog issue with no milestone.

- **Publish to CurseForge and Wago (#43).** The packager can upload there too; it needs
  a project on each site, the project IDs in the TOC and the API tokens as secrets.
