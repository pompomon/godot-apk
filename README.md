# Adventurer's March — Technical Foundation

A Godot 4.7.2 foundation that boots to an empty Home screen through `UIManager`
and exports a portrait-only debug Android APK. Gameplay and persistence remain
unimplemented; the application/package name and APK artifact retain their
original **Hello World** identifiers.

## Run locally

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/).
2. Open this directory in the Godot editor:

   ```sh
   godot --editor --path .
   ```

3. Press **F5** or click **Run Project**. The configured `main.tscn` scene
   binds the persistent screen root, calls the placeholder
   `SaveManager.load_or_create()`, and displays the empty Home screen.

You can also run the project directly:

```sh
godot --path .
```

## Run the foundation tests

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
Navigation rejection tests deliberately emit Godot warnings; normal app startup
does not.

The suite covers autoloads, Resource schemas/Inspector hints, the default
balancing asset, real main-scene bootstrap, screen replacement and invalid
navigation, and mobile settings. No test reads or writes a player save.
Persistence must derive primary, backup, and temporary paths from
`SaveManager.get_save_path()`, never hard-code `user://save.json`. Autoload
initialization must remain I/O-free. Milestone 2 replaces the explicitly named
foundation-empty-state test with isolated new-game/round-trip tests, resetting
in-memory state and using fresh storage per persistence case.

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

## Foundation boundaries

- `GameState` owns empty roster/inventory arrays, zero gold, and unlocked Region
  IDs. Milestone 2 introduces starting Heroes/gold and persistence.
- `SaveManager`, `ExpeditionManager`, and `CombatSimulator` expose documented
  stubs; save/start/resolve calls warn rather than fabricate success.
- `ExpeditionManager` is the sole future owner of the active Expedition.
  `SaveManager` serializes/restores it alongside `GameState`; no second copy
  belongs on `GameState`.
- `UIManager.bind_screen_root()` is bootstrap-only; screens navigate using
  `UIManager.show_screen()`. Navigation before binding is rejected, not queued.
  Accepted requests run after tree callbacks finish; requests belonging to a
  root that has exited are discarded. Await a process frame before inspecting
  the resulting screen in tests.
- Nine content Resource scripts live under `scripts/models/`. Runtime Hero,
  Party, and Expedition models do not exist yet, so their stub parameters use
  `Variant` and the roster/inventory model arrays remain untyped.
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

## Adventurer's March design & implementation docs

Planning documentation for the **Adventurer's March** mobile idle fantasy
simulator lives under [`docs/`](docs/):

- [Implementation plan](docs/adventurers-march-implementation-plan.md) —
  the comprehensive design and architecture reference.
- [Milestones checklist](docs/adventurers-march-milestones.md) — ordered,
  trackable milestone list.
- [`docs/adventurers-march/milestones/`](docs/adventurers-march/milestones/) —
  a detailed implementation-ready plan per milestone.