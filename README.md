# Adventurer's March — Combat Simulation

A Godot 4.7.2 portrait Android game with a generated Company roster, Hero
inspection, deterministic recruitment, Party formation, timed Expeditions with
deterministic auto-combat, and local JSON saves. The
application/package name and APK artifact retain their original **Hello World**
identifiers. Equipment management and XP progression remain future milestones.

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
   assemble a formation, then choose **Green Hollow** for the first Expedition.

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
  Each has zero or one flat-stat trade-off trait. Conditional combat/recovery
  traits are deferred, not represented as working effects.
- Hero Detail shows attributes, derived stats, traits, status, and cumulative
  XP. The XP bar is inactive until progression is implemented in Milestone 6;
  weapon and armor slots are empty placeholders.
- Saves live in Godot's app-private user-data directory as `save.json`.
  New-game creation, recruitment, confirmed Party changes, Expedition starts,
  progress observations/rewards, injury recovery, and report acknowledgment save immediately;
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
  and cannot be reassigned until the Expedition finishes. Surviving Heroes
  return to `Idle`; knocked-out Heroes and participants in a Defeat become
  `Wounded` until their saved recovery deadline. No Hero is permanently killed.

## First Expedition

- Confirm a Party, then choose **Green Hollow** from Home. It is always
  available and offers one **60-second** Expedition. Recommended Party Power
  is guidance, not an entry requirement; partial and back-row-only Parties
  remain valid.
- Green Hollow schedules five Travel/encounter pairs: **10 steps**, one every
  **6 seconds**. The weighted pool combines five automatic narrative Events,
  Loot, and Combat. Loot and Events award modest nonnegative gold; Combat
  itself awards no gold. Item rewards, XP awards, and interrupting choices
  remain deferred.
- At dispatch, the game freezes the Party's starting values and resolves the
  entire journal using a saved seed. Time reveals those stored results; it
  never rerolls them. Later changes to content or roster values do not alter
  an existing journal.
- Home displays progress and provides access to the Report. Only revealed
  entries and their earned gold are visible. Progress is checked while the
  app is open and when resuming, including from screens other than Home.
- Defeat or Retreat ends Green Hollow early at that Combat's original scheduled
  reveal time. Later steps and rewards are discarded, never stretched into a
  new schedule. Until the terminal entry is revealed, progress shows the
  original plan rather than exposing the precomputed outcome.
- Closing the app does not require background execution. On return, the
  game credits elapsed UTC time since its previous saved observation.
  Backward clock changes credit zero; a single forward observation credits
  at most the configured **24 hours**, capped at the Expedition's effective duration.
  This is an offline clock policy, not protection against repeated clock
  manipulation.
- Each observation persists clock accounting together with any newly
  revealed gold, cursor, and final Hero-status changes before displaying
  them. Failed pre-commit saves restore the previous state and can be retried;
  post-commit warnings do not undo saved rewards.
- A completed report remains available across restarts until explicitly
  acknowledged. Acknowledgment does **not** award gold again. Forming a new
  Party is allowed after completion, but the previous report must be
  acknowledged before dispatching another Expedition. Back leaves a report
  available rather than silently dismissing it.
- Version-4 saves preserve combat journals, frozen Party/skill values, terminal
  timing, and recovery deadlines. Versions 1–3 migrate after original-schema
  validation without regenerating Heroes, offers, or existing journals.
  Version-3 non-combat Expeditions retain their progress and original snapshots;
  migration does not retroactively add skills or Combat encounters. Only
  versions 1 and 2 normalize orphan `On expedition` statuses to `Idle`, since
  those schemas could not store an Expedition.

## Combat and recovery

- Combat runs immediately at dispatch, using frozen derived stats and seeded
  randomness. The Report reveals its saved rounds later; opening a report or
  resuming the app never reruns combat.
- Initiative determines turn order with seeded tie-breaking. Basic attacks
  are physical. Knights target living front-row enemies first; the other
  classes can target either row. Within the eligible targets, lowest HP
  percentage wins, then ascending stable combatant ID.
- Each class has one active skill: **Guard**, **Aimed Shot**, **Firebolt**, or
  **Mend**. Guard reduces incoming damage until the Knight's next turn;
  Aimed Shot deals physical damage and Firebolt deals magical damage. Mend
  heals a living injured ally, including its caster, and falls back to a basic
  attack if nobody needs healing.
- Skills start ready. Cooldowns count subsequent personal turns; cooldowns
  and temporary effects reset between encounters. HP does **not** reset:
  a Hero at zero HP cannot act or be revived later in that Expedition.
- Defender Evasion reduces hit chance. Damage and healing use derived stats,
  not raw attributes, and are floored once before being applied to HP.
  Combat ends in Victory, Defeat, or Retreat at the configured round cap.
- The combat journal distinguishes misses, critical hits, healing, and Guard,
  and shows final participant HP and injury results.
- Finalization persists Wounded Heroes and their recovery deadlines together.
  The provisional recovery period is **one hour**, frozen at dispatch from
  `BalancingConfig.base_recovery_seconds` and starting when completion is first
  saved. It does not retroactively credit recovery before that observation.
  The existing foreground/resume checks release them to Idle after their
  deadline, including after report acknowledgment or restart. This is a
  minimal timed recovery, not the full Wounded/Resting progression flow
  planned for Milestone 6. Recovery is checked against device UTC, not an
  anti-cheat clock.
- Guard currently reduces incoming damage by 50%; the Aimed Shot, Firebolt, and
  Mend multipliers are 1.6, 1.8, and 1.5. Cooldowns are two subsequent personal
  turns except Firebolt's one. These are provisional values in authored data,
  not finalized balance targets.

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
Party models/evaluation/transactions, exact combat results, skills, targeting,
Expedition content/generation/timing/rewards, injury recovery,
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
`user://gut_temp_directory/`, outside the checkout. Tests and the GUT addon are
excluded from the Android APK.

## Architecture boundaries

- `GameState` owns the typed Hero roster and offers, nullable confirmed
  `current_party`, gold, roster capacity, ID/seed state, inventory, and unlocked
  Region IDs. Inventory and unlocked
  Regions remain empty until their owning milestones.
- `HeroData` is a `RefCounted` runtime model. Generation and derived-stat
  calculation are pure; generated attributes are not overwritten by growth.
  Class-specific stat bases and weights live on authored class Resources.
- `SaveManager` owns validation, migration dispatch, serialization, and backup
  recovery. Recruitment saves its gold, Hero, offer, ID, and seed changes
  together and rolls back a failed pre-commit purchase.
- `PartyData` is a `RefCounted` four-slot model referencing canonical roster
  Heroes. Drafts copy only its mapping; deterministic slot order is front-left,
  front-right, back-left, back-right. `PartyEvaluator` is pure and consumes
  `HeroStats`, so future equipment effects need no duplicate Power formula.
- `PartyFormationService` validates and commits Party/status changes together.
  `GameState` checkpoints retain Hero identity while restoring mutable
  statuses and the previous formation on pre-commit failure. A post-commit
  warning never undoes saved changes. Version-2 validation rejects orphan
  `Assigned` statuses and Party members not belonging to the roster.
- `CombatSimulator` is a stateless runtime facade for pure combat resolution.
  It consumes frozen Party values, a complete Hero-ID HP/status map, enemy
  content, a seed, and balancing. It never reads live roster values, clocks,
  scene-tree state, or global randomness and never mutates its inputs.
- `ExpeditionManager` is the sole owner of the active or completed Expedition.
  `SaveManager` serializes/restores it alongside `GameState`; no second copy
  belongs on `GameState`. Expedition seed advancement is independent of
  recruitment and is committed with dispatch.
- `ExpeditionGenerator` is pure: it selects all encounters with replacement
  before resolving their outcomes using the same seeded RNG stream.
  Step duration is computed from the complete candidate count and persisted,
  never recalculated from a potentially truncated journal. Combat seeds come
  from that outcome stream, and complete final Hero-state maps carry HP into
  subsequent Combats. Terminal policy is frozen with the Expedition.
- Frozen Party and journal snapshots contain plain, JSON-safe values. They
  do not share mutable roster Heroes or depend on recomputing current content
  when a save is loaded. Pending Party mappings still reference canonical
  roster Heroes.
- Expedition start, reveal/finalization, and acknowledgment use the existing
  save commit boundary. Gold, cursor, clock state, and Hero statuses are one
  saved snapshot; only committed state is presented. Recovery deadlines share
  the same rollback/commit boundary. Completed-report reads and acknowledgment
  never apply injuries or rewards a second time.
- `UIManager.bind_screen_root()` is bootstrap-only; screens navigate using
  `UIManager.show_screen()`. Navigation before binding is rejected, not queued.
  Accepted requests run after tree callbacks finish; requests belonging to a
  root that has exited are discarded. Hero Detail receives a stable Hero ID
  through request-specific navigation context, not a roster index. Await a
  process frame before inspecting the resulting screen in tests.
- Content Resource scripts and runtime Hero, Party, and Expedition models
  live under `scripts/models/`. `ExpeditionManager.start_expedition` accepts
  the confirmed `PartyData`; it must not use the draft-oriented
  `PartyData.copy()` as a frozen Expedition snapshot. Enemy groups and skills
  are authored Resources; inventory remains untyped until Milestone 6.
- `data/balancing/default_balancing.tres` is the single balancing asset. It
  defines the 100-gold recruitment price, design §7 Party Power baseline
  (including divisor 4 and no-front-row factor 0.85), and §9 combat defaults
  with a 20-round cap. Encounter-kind multipliers start at a neutral 1.0; the
  offline cap is provisionally 86400 seconds (24 hours) per observation, not a
  finalized balance decision. Skill strengths and recovery duration are
  provisional authored values; XP remains unconfigured until Milestone 6.
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

Hero Roster's implementation is complete, but final OS-temp-isolated CI
verification requires workflow approval and exported-device acceptance remains
pending. See the [milestone evidence](docs/adventurers-march/milestones/02-hero-roster.md#implementation-and-validation-evidence)
for the tested revision, local results, and remaining checks.
Party Formation's validation evidence and separate exported-device checklist
are tracked in its [milestone detail](docs/adventurers-march/milestones/03-party-formation.md).
First Expedition's automated/export evidence and outstanding physical-device
offline/lifecycle checks are tracked in its
[milestone detail](docs/adventurers-march/milestones/04-first-expedition.md).

## Adventurer's March design & implementation docs

Planning documentation for the **Adventurer's March** mobile idle fantasy
simulator lives under [`docs/`](docs/):

- [Implementation plan](docs/adventurers-march-implementation-plan.md) —
  the comprehensive design and architecture reference.
- [Milestones checklist](docs/adventurers-march-milestones.md) — ordered,
  trackable milestone list.
- [`docs/adventurers-march/milestones/`](docs/adventurers-march/milestones/) —
  a detailed implementation-ready plan per milestone.