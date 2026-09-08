# Adventurer's March — Content Expansion

A Godot 4.7.2 portrait Android game with a generated Company roster, Hero
inspection, deterministic recruitment, Party formation, timed Combat
Expeditions, Hero leveling, equipment, unlockable Regions, and local JSON saves. The
application/package name and APK artifact retain their original **Hello World**
identifiers. Green Hollow includes deterministic Combat and readable saved
logs; completed Expeditions award XP and revealed Loot/Events can award equipment.

Contributors and coding agents: start with the
[agent implementation guidelines](AGENTS.md) for bounded scope, integration
gates, validation ownership, and verified handoffs.

## Run locally

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/).
2. Open this directory in the Godot editor:

   ```sh
   godot --editor --path .
   ```

3. Press **F5** or click **Run Project**. The configured `main.tscn` scene
   binds the persistent screen root, calls `SaveManager.load_or_create()`,
   and displays Home with the Company's gold and roster count. Open
   **Company Roster** to inspect or recruit Heroes, or **Form Party** to
   assemble a formation, then choose a Region (initially **Green Hollow**).

You can also run the project directly:

```sh
godot --path .
```

## Recruitment and saves

- A new Company starts with one Knight, Ranger, Wizard, and Cleric, **100 gold**,
  and capacity for **12 Heroes**.
- Three generated recruitment offers persist across navigation and restarts.
  Recruiting costs **100 gold** by default, read from the existing balancing
  resource. Only the purchased offer is replaced; there is no timer or refresh
  button. Insufficient gold and full capacity disable recruitment.
- Heroes retain their original stable IDs when recruited and after reload.
  Each has zero or one of eight flat-stat trade-off traits. Conditional combat/recovery
  traits are deferred, not represented as working effects.
- Hero Detail shows attributes, derived stats, traits, status, cumulative XP and
  next-level progress. **Manage equipment** opens a weapon/armor draft with
  before/after stat changes. Confirm saves ownership; Cancel/Android Back
  discards the draft. All classes can use either slot's items while Idle,
  Assigned or Resting, but equipment is locked during an Expedition.
- Inventory holds unequipped item copies, including duplicates. Equipping
  consumes one copy and replacing/unequipping returns one. The starter pool
  contains Short Sword, Hunting Bow, Apprentice Staff, Leather Armor, Chainmail
  and Robes with Common/Uncommon flat-stat modifiers; no crafting or shop is added.
- Saves live in Godot's app-private user-data directory as `save.json`.
  New-game creation, recruitment, confirmed Party changes, Expedition starts,
  progress observations/rewards, equipment confirmation, and report acknowledgment
  save immediately;
  initialized state is also saved on application pause/close. Failed
  pre-commit mutations roll back and show retry feedback.
- Versioned saves validate the complete state and known content IDs. Writes
  flush, close, reopen, and validate a same-directory temporary file before
  replacing the primary. The previous valid primary is retained as `.bak`.
  A missing or invalid primary can recover from that backup, with visible
  feedback; recovery does not overwrite the valid backup. If neither copy is
  usable, a new Company is created.
- This is best-effort replacement using Godot APIs, **not** a guarantee of
  atomic replacement or durability across arbitrary power loss. Do not delete
  a player's save to troubleshoot; copy the primary and backup elsewhere first.

## Forming a Party

- Open **Form Party** from Home or Company Roster. Tap one of the four named
  front/back slots, then an available Hero to place them. Remove or move
  members explicitly; occupied slots are never silently overwritten.
- Only `Idle` roster Heroes may be newly added. Heroes already in your
  confirmed Party remain editable while `Assigned`.
- Slot edits are a local draft. Heroes disappear from the available pool when
  selected, but their statuses and saved formation do not change until
  **Confirm**. Confirming a Party returns Home and exposes **Edit Party**.
- **Cancel/Back** discards edits and preserves any previously confirmed
  Party. **Disband Party** explicitly clears that Party and returns its members
  to `Idle`. Backgrounding or closing saves committed state only.
- Parties may contain 1–4 Heroes. Power updates live from the shared derived
  stats and balancing asset: member-count scaling applies below four Heroes,
  and an additional 0.85 factor applies without a front-row Hero. These
  formations are allowed; the UI explains the penalties. Empty drafts cannot
  be confirmed. Power is an estimate, not a combat result.
- Version-2 saves store named formation slots referencing stable roster IDs.
  Version-1 saves migrate without regenerating Heroes or losing Company
  progress; legacy `Assigned` statuses become `Idle` because that version did
  not store a Party. Other statuses are preserved.
- Dispatching consumes the confirmed Party. Its Heroes become `On expedition`
  and cannot be reassigned until the Expedition finishes; completion returns
  them to `Idle` if healthy. Frozen Wounded outcomes (zero HP or Defeat) become
  `Resting`; survivors at or below 25% of dispatch MaxHP also rest.

## First Expedition

- Confirm a Party, then choose **Green Hollow** from Home. It is always
  available and offers one **60-second** Expedition. Recommended Party Power
  is guidance, not an entry requirement; partial and back-row-only Parties
  remain valid.
- Green Hollow plans five Travel/encounter pairs: **10 steps**, one every
  **6 seconds**. The weighted pool contains five automatic narrative Events,
  Loot, Forest Wolves, and Bandit Skirmishers. Loot/Events award modest
  nonnegative gold; Combat awards no gold. Loot and selected Event outcomes can
  also grant equipment: each Wayside Cache has a 50% chance of one weighted
  starter item, and the Quiet Ruins coin outcome includes a Short Sword.
  Choices and resource costs remain deferred.
- Combat uses Guard, Aimed Shot, Firebolt, and Mend, with HP carrying between
  encounters and no automatic healing between them. Defeat ends the Expedition
  at that Combat step; Retreat continues in Green Hollow. Terminal runs retain
  their original six-second step duration and cannot award later rewards.
- At dispatch, the game freezes the Party's starting values and resolves the
  entire journal using a saved seed. Time reveals those stored results; it
  never rerolls them. Later changes to content or roster values do not alter
  an existing journal.
- Home displays progress and provides access to the Report. Only revealed
  entries and their earned gold are visible. Revealed Combat entries show the
  outcome and round-by-round actors, actions, targets, misses, critical damage,
  healing, and Guard. Planned progress hides future early endings until their
  step is committed. Progress is checked while the
  app is open and when resuming, including from screens other than Home.
- Closing the app does not require background execution. On return, the
  game credits elapsed UTC time since its previous saved observation.
  Backward clock changes credit zero; a single forward observation credits
  at most the configured **24 hours**, capped at the Expedition duration.
  This is an offline clock policy, not protection against repeated clock
  manipulation.
- Each observation persists clock accounting together with any newly
  revealed gold/items, cursor, and final Hero XP/level/status changes before
  displaying them. Failed pre-commit saves restore the previous state and can be retried;
  post-commit warnings do not undo saved rewards.
- Every participating Hero gains the same frozen XP award when completion
  commits, including after Defeat/terminal Retreat. The initial formula is
  `floor(recommended_party_power * 0.25 + selected_duration_seconds)`.
  Level costs start at 100 XP and grow by 1.25, individually rounded up;
  thresholds are cumulative and a single award can advance multiple levels.
  Growth never overwrites generated attributes. Saved levels are not recomputed
  on load; later positive awards use the current threshold curve.
- A completed report remains available across restarts until explicitly
  acknowledged. Acknowledgment does **not** award gold, items or XP again.
  Forming a new Party is allowed after completion, but the previous report must be
  acknowledged before dispatching another Expedition. Back leaves a report
  available rather than silently dismissing it.
- Newly injured Heroes enter Resting with a **60-second** UTC recovery deadline
  starting at the observation that commits completion, including after a long
  offline absence. Foreground/resume/load observations return due Heroes to
  Idle transactionally, even without an active Expedition or report. Failed
  saves preserve Resting status and expose retry feedback; Party availability
  refreshes only after commit. Legacy Wounded Heroes without a deadline remain
  unchanged. Recovery duration and the heavy-damage percentage are frozen at
  dispatch; subsequent content changes do not alter a pending run's policy.
- Version-6 saves preserve inventory copies, equipped item IDs, pending Parties
  and active/completed Expeditions,
  including frozen combat payloads, planned step counts, terminal rules, and
  Hero recovery deadlines and frozen progression rewards. Versions 1–5 migrate
  without regenerating Heroes,
  recruitment offers, or historical journals. Combat dispatch, finalization,
  recovery observation, equipment and presentation share the existing transaction
  boundary.
  Old Expeditions gain no retroactive XP or items. Existing positive Wounded
  deadlines migrate to Resting without restarting their timer; legacy
  Wounded/Resting states with no deadline remain unchanged.
  Legacy `On expedition` statuses become `Idle`: those schemas could not
  store an Expedition to which those Heroes belonged.

## Region and Company progression

- Green Hollow is always available. Holding **200 gold** permanently unlocks
  **Ashen Reach**, and holding **400 gold** permanently unlocks **Frostbound Pass**.
  These are current-balance thresholds, not prices or lifetime-gold counters.
  Spending gold after a committed unlock never relocks a Region.
- The Regions offer **60 / 120 / 180 seconds** respectively. Each has five
  authored automatic Event cards, its own Combat mix, and item-bearing Loot.
  Recommended Power is guidance, never an additional dispatch restriction.
- Unlocking the Regions raises roster capacity to **12 / 16 / 20** respectively.
  Region Select displays requirements; Company Roster displays capacity and
  progression guidance. Capacity and unlocks are committed with earned gold,
  not granted again when a report is acknowledged.
- Existing Companies are evaluated on load and foreground observations even
  without an Expedition. Unlocks appear only after saving succeeds. Save
  version 6 validates known Region IDs and supports expanded capacities;
  legacy unused, unknown unlock strings are removed during migration, without
  rerolling journals, changing equipment, or awarding historical rewards.
- This milestone does not add skills, event choices, crafting, a shop, or
  conditional trait effects.
- Current recommended Power is **330 / 820 / 1000**. Balance remains
  **provisional**: not all measured win-rate bands meet their targets.
  See [Milestone 7's recorded results](docs/adventurers-march/milestones/07-content-expansion.md#recorded-balance-results)
  for the outstanding tuning and device-acceptance gates.

### Reproduce the balance report

After the clean import below, run from the repository root:

```sh
godot --headless --path . -s res://tools/balance_simulation.gd -- --trials=256 --seed=7001
```

Optionally restrict the report with `--region=green_hollow`, `--region=ashen_reach`,
or `--region=frostbound_pass`. The tool prints JSON to stdout and never loads
or saves a Company. It samples generated 1–4-Hero Parties at levels 1–12, with
distinct classes and optional starter equipment. Party selection uses only
Power, not eventual combat outcomes. The report identifies actual Power ranges,
member counts, distinct sampled Parties, Victory/Retreat/Defeat counts, and
per-enemy results. Every independent Combat starts at full HP; separate complete
Expedition trials retain HP carryover and report completion rate and journal size.

Below/at/above samples use 60–80%, 95–105%, and 105–115% of recommended Power.
The target is fewer than 50% Victories below, and 70–85% at/modestly above.
`target_met` reports these bands without making statistical tuning a flaky unit
test. A valid report can contain unmet targets; malformed inputs or insufficient
samples return a nonzero exit code. The tools are excluded from the APK.

## Run the tests

Run these commands from the repository root with Godot 4.7.2:

```sh
godot --headless --path . --editor --import
godot --headless --path . -s addons/gut/gut_cmdln.gd
```

The import step is required on a clean checkout to discover global Resource and
GUT classes. There is no separate test wrapper. `.gutconfig.json` discovers
`test_*.gd` recursively under `tests/` and exits automatically. GUT reports
assertion failures with a nonzero exit code; the standard post-run hook also
fails empty discovery and GUT warnings/errors (including skipped test scripts).
The pre-run hook binds `SaveManager.storage_directory` to a fresh OS temporary
directory before tests run, aborting if isolation cannot be created. Godot removes
that directory when the hook is released. Keep both hooks enabled in the CLI
and any optional GUT editor configuration.
Negative navigation and save-recovery tests deliberately emit Godot warnings;
normal startup with healthy storage does not.

The suite covers content, deterministic generation, derived stats, recruitment,
Party models/evaluation/transactions, Expedition content/generation/timing/rewards,
save validation/migration/recovery, and Expedition/formation/roster/detail
navigation alongside the foundation autoload, Resource,
bootstrap, and mobile-setting regressions. No test reads or writes a player save.
Persistence must derive primary, backup, and temporary paths from
`SaveManager.get_save_path()`, never hard-code `user://save.json`. Autoload
initialization must remain I/O-free. Persistence and bootstrap cases use fresh
temporary storage and reset/restore singleton state between cases.

**Pinned dependency:** [GUT 9.7.1](https://github.com/bitwes/Gut/tree/v9.7.1),
the upstream Godot 4.7.x release, vendored unchanged from commit
`aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605` under `addons/gut/`.
Its [MIT license](addons/gut/LICENSE.md) and upstream notices are preserved.
To update it, replace only the addon directory from a reviewed upstream release,
update this pin, and repeat clean-import, test, and export checks.

The CLI does not require enabling the optional GUT editor plugin. Godot's import
cache is already ignored under `.godot/`; GUT's editor scratch files live under
`user://gut_temp_directory/`, outside the checkout. Tests, balance tools and the
GUT addon are excluded from the Android APK.

## Architecture boundaries

- `GameState` owns the typed Hero roster and offers, nullable confirmed
  `current_party`, gold, roster capacity, ID/seed state, inventory, and unlocked
  Region IDs. Inventory contains typed, immutable `ItemResource` references.
  `CompanyProgression` previews permanent gold-threshold unlocks and capacity
  rewards without mutating Company state; the existing observation transaction
  commits them before UI refresh.
- `HeroData` is a `RefCounted` runtime model. Generation and derived-stat
  calculation are pure; generated attributes are not overwritten by growth.
  Class-specific stat bases and weights live on authored class Resources.
- `SaveManager` owns validation, migration dispatch, serialization, and backup
  recovery. Recruitment saves its gold, Hero, offer, ID, and seed changes
  together and rolls back a failed pre-commit purchase.
- `PartyData` is a `RefCounted` four-slot model referencing canonical roster
  Heroes. Drafts copy only its mapping; deterministic slot order is front-left,
  front-right, back-left, back-right. `PartyEvaluator` is pure and consumes
  `HeroStats`, so equipment effects need no duplicate Power formula.
- `PartyFormationService` validates and commits Party/status changes together.
  `GameState` checkpoints retain Hero identity while restoring mutable
  XP, level, equipment, recovery, statuses and the previous formation on pre-commit
  failure. A post-commit warning never undoes saved changes. Version-2 validation rejects orphan
  `Assigned` statuses and Party members not belonging to the roster.
- `CombatSimulator` delegates to pure `CombatEngine` functions consuming
  detached Party/skill snapshots, current Hero HP/status, enemy data, a seed,
  and balancing. Guard, Aimed Shot, Firebolt, and Mend are authored and tested;
  Green Hollow resolves authored encounters at dispatch. `CombatResult` validates
  saved logs by applying recorded HP changes, without rerunning simulation or
  reading current combat tuning.
- `ExpeditionManager` is the sole owner of the active or completed Expedition.
  `SaveManager` serializes/restores it alongside `GameState`; no second copy
  belongs on `GameState`. Expedition seed advancement is independent of
  recruitment and is committed with dispatch.
- `ExpeditionGenerator` is pure: it selects all encounters with replacement
  before resolving their outcomes using the same seeded RNG stream.
  Step duration is computed from the complete candidate count and persisted,
  never recalculated from a potentially truncated journal. Saved `COMBAT`
  payloads are generated by live content and carried through sequential Combats.
- Frozen Party and journal snapshots contain plain, JSON-safe values. They
  do not share mutable roster Heroes or depend on recomputing current content
  when a save is loaded. Pending Party mappings still reference canonical
  roster Heroes.
- Expedition start, reveal/finalization, and acknowledgment use the existing
  save commit boundary. Gold/items, XP/level, cursor, clock state and Hero
  recovery/statuses are one saved snapshot; only committed state is presented.
- `UIManager.bind_screen_root()` is bootstrap-only; screens navigate using
  `UIManager.show_screen()`. Navigation before binding is rejected, not queued.
  Accepted requests run after tree callbacks finish; requests belonging to a
  root that has exited are discarded. Hero Detail receives a stable Hero ID
  through request-specific navigation context, not a roster index. Await a
  process frame before inspecting the resulting screen in tests.
- Content Resource scripts and runtime Hero, Party, and Expedition models
  live under `scripts/models/`. `ExpeditionManager.start_expedition` accepts
  the confirmed `PartyData`; it must not use the draft-oriented
  `PartyData.copy()` as a frozen Expedition snapshot. Combat enemy and skill
  Resources are detached before simulation. `ItemCatalog` resolves saved IDs
  through an explicit allowlist. Equipment drafts use detached stat previews
  and revalidate canonical Hero identity and current item quantities on confirm.
- `data/balancing/default_balancing.tres` is the single balancing asset. It
  defines the 100-gold recruitment price, design §7 Party Power formula
  (level weight 30, Defense weight 3, divisor 4 and no-front-row factor 0.85),
  and §9 combat defaults
  with a 20-round cap. Encounter-kind multipliers start at a neutral 1.0; the
  offline cap is provisionally 86400 seconds (24 hours) per observation, not a
  finalized balance decision. Skill multipliers are configured for Combat,
  with XP weights/thresholds and 60-second/25%-HP recovery defaults for progression.
  `Leveling` caches numeric threshold runs, handles cumulative ceiling-rounded
  costs and bounded XP without introducing a second derived-stat calculator.
  Extend this asset rather than replace it, preserving unrelated values.

## Build the Android APK

Install the matching Godot 4.7.2 export templates, OpenJDK 17, and the Android
SDK components described in the
[Godot Android export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html).
In Godot's editor settings, configure the Java SDK and Android SDK paths.

Then export the `Android` debug preset from the repository root:

```sh
mkdir -p build/android
godot --headless --path . --export-debug "Android" build/android/hello-world.apk
```

The preset uses the package identifier `com.example.helloworld` and writes the
APK to `build/android/hello-world.apk`.

## Continuous integration

`.github/workflows/android-apk.yml` runs on pushes, pull requests, and manual
dispatches. It installs Java and the required Android SDK components, downloads
Godot and its matching export templates, imports the project, runs the headless
tests, performs the debug export, and uploads
the APK as the `hello-world-android-apk` workflow artifact.

The workflow intentionally does not use GitHub Actions cache or dependency
caching; every job performs a clean build. A failing test or rejected test
discovery stops the job before export/upload. Milestone 9 audits this existing
gate with the full gameplay suite; it does not introduce a second test pipeline.

Milestones 1–4 were accepted by the user on 2026-09-07, with device acceptance
considered complete externally for now. This records external acceptance,
not physical-device testing performed by the coding agent. The
[merged Android workflow on `bbe88d5`](https://github.com/pompomon/godot-apk/actions/runs/34135467082)
passed the integrated test/export gate. Historical local results and external
acceptance are tracked in the
[Hero Roster](docs/adventurers-march/milestones/02-hero-roster.md#implementation-and-validation-evidence),
[Party Formation](docs/adventurers-march/milestones/03-party-formation.md), and
[First Expedition](docs/adventurers-march/milestones/04-first-expedition.md)
milestone details.

Milestone 6 was manually verified externally by the user on 2026-09-08.
Milestone 7's separate implementation, balance and physical-device evidence is
tracked in [Content Expansion](docs/adventurers-march/milestones/07-content-expansion.md).

## Adventurer's March design & implementation docs

Planning documentation for the **Adventurer's March** mobile idle fantasy
simulator lives under [`docs/`](docs/):

- [Implementation plan](docs/adventurers-march-implementation-plan.md) —
  the comprehensive design and architecture reference.
- [Milestones checklist](docs/adventurers-march-milestones.md) — ordered,
  trackable milestone list.
- [`docs/adventurers-march/milestones/`](docs/adventurers-march/milestones/) —
  a detailed implementation-ready plan per milestone.