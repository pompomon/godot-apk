# Adventurer's March — Party Formation

A Godot 4.7.2 portrait Android game with a generated Company roster, Hero
inspection, deterministic recruitment, Party formation, and local JSON saves. The
application/package name and APK artifact retain their original **Hello World**
identifiers. Expeditions, combat, equipment management, and
XP progression remain future milestones.

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
   assemble a formation.

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
  New-game creation, recruitment, and confirmed Party changes save immediately;
  initialized state is also saved on application pause/close. Failed
  pre-commit purchases and Party changes roll back and show retry feedback.
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
- Region selection and expedition execution remain deferred to Milestone 4.

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
Party models/evaluation/transactions, save validation/migration/recovery, and
formation/roster/detail navigation alongside the foundation autoload, Resource,
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
- `ExpeditionManager` and `CombatSimulator` remain documented stubs;
  start/resolve calls warn rather than fabricate success.
- `ExpeditionManager` is the sole future owner of the active Expedition.
  `SaveManager` serializes/restores it alongside `GameState`; no second copy
  belongs on `GameState`.
- `UIManager.bind_screen_root()` is bootstrap-only; screens navigate using
  `UIManager.show_screen()`. Navigation before binding is rejected, not queued.
  Accepted requests run after tree callbacks finish; requests belonging to a
  root that has exited are discarded. Hero Detail receives a stable Hero ID
  through request-specific navigation context, not a roster index. Await a
  process frame before inspecting the resulting screen in tests.
- Content Resource scripts, `HeroData`, and `PartyData` live under
  `scripts/models/`. `ExpeditionManager.start_expedition` accepts `PartyData`
  but remains a stub; the Expedition model and combat types remain deferred,
  and inventory remains untyped until Milestone 6.
- `data/balancing/default_balancing.tres` is the single balancing asset. It
  defines the 100-gold recruitment price, design §7 Party Power baseline
  (including divisor 4 and no-front-row factor 0.85), and §9 combat defaults
  with a 20-round cap. Encounter-kind multipliers start at a neutral 1.0; the
  offline cap is provisionally 86400 seconds (24 hours) per observation, not a
  finalized balance decision. Skills, XP, and recovery remain unconfigured:
  their owning milestones must author and validate them before use. Extend
  this asset rather than replace it, preserving unrelated values.

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

## Adventurer's March design & implementation docs

Planning documentation for the **Adventurer's March** mobile idle fantasy
simulator lives under [`docs/`](docs/):

- [Implementation plan](docs/adventurers-march-implementation-plan.md) —
  the comprehensive design and architecture reference.
- [Milestones checklist](docs/adventurers-march-milestones.md) — ordered,
  trackable milestone list.
- [`docs/adventurers-march/milestones/`](docs/adventurers-march/milestones/) —
  a detailed implementation-ready plan per milestone.