# Milestone 1 — Technical Foundation

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Establish the Godot project structure, autoload managers, and base
data-resource classes that every later milestone builds on, without
implementing any gameplay content yet.

## Scope

**In scope:** folder restructuring, autoload singleton stubs with defined
responsibilities/interfaces, base `Resource` subclasses for content types,
an empty Home screen wired through a screen manager, and a headless test
framework smoke test.

**Out of scope (later milestones):** any actual Hero/Party/Expedition/
Combat logic or content data — this milestone defines the *shape* of the
system, not its behavior.

## Prerequisites / dependencies

None. This is the starting milestone. Builds on the existing repository
state (`project.godot`, `main.tscn`, Android export preset, CI workflow).

## Tasks

1. Create the folder layout described in
   [plan §13](../../adventurers-march-implementation-plan.md#13-godot-project-architecture):
   `autoload/`, `data/{classes,traits,items,regions,encounters,balancing}/`,
   `scripts/{models,systems}/`, `scenes/ui/{home,roster,hero_detail,
   equipment,party_formation,region_select,expedition_report,settings}/`,
   `tests/`.
2. Add five autoload singletons in `autoload/` and register them in
   `project.godot`'s `[autoload]` section:
   - `GameState.gd`
   - `SaveManager.gd`
   - `ExpeditionManager.gd`
   - `CombatSimulator.gd`
   - `UIManager.gd`
   Each should exist as a real script with class-level doc comments
   describing its responsibility (per plan §13) even if method bodies are
   placeholders (e.g., `push_warning("not yet implemented")`).
3. Define base `Resource` subclasses with the typed exported fields in the
   contracts below:
   - `scripts/models/hero_class_resource.gd` (`class_name HeroClassResource`)
   - `scripts/models/hero_trait_resource.gd` (`class_name HeroTraitResource`)
   - `scripts/models/item_resource.gd` (`class_name ItemResource`)
   - `scripts/models/encounter_entry_resource.gd`
     (`class_name EncounterEntryResource`)
   - `scripts/models/loot_resource.gd` (`class_name LootResource`)
   - `scripts/models/event_resource.gd` (`class_name EventResource`)
   - `scripts/models/event_outcome_resource.gd`
     (`class_name EventOutcomeResource`)
   - `scripts/models/region_resource.gd` (`class_name RegionResource`)
   - `scripts/models/balancing_config.gd` (`class_name BalancingConfig`)
4. Create an empty Home screen scene (`scenes/ui/home/home_screen.tscn`)
   and have `UIManager` show it on boot via `main.tscn`.
5. Add a headless test framework (GUT or GdUnit4) as an addon under
   `addons/`, configure it to discover tests under `tests/`, and add one
   trivial smoke test (e.g., asserting `GameState` autoload is not null)
   under `tests/test_smoke.gd`.
6. Update `.gitignore` if the chosen test addon generates local-only
   artifacts.
7. Set `display/window/handheld/orientation=1` (`Portrait`) in
   `project.godot`, then confirm the existing Android debug export
   (`.github/workflows/android-apk.yml`) still succeeds with the
   restructured project (no gameplay change expected, but autoload
   registration and folder moves can break exports if misconfigured). Install
   that exported APK on a device/emulator with auto-rotate enabled and verify
   rotating the device does not rotate the game into landscape.

## Expected files / scenes / scripts / data

```
autoload/GameState.gd
autoload/SaveManager.gd
autoload/ExpeditionManager.gd
autoload/CombatSimulator.gd
autoload/UIManager.gd
scripts/models/hero_class_resource.gd
scripts/models/hero_trait_resource.gd
scripts/models/item_resource.gd
scripts/models/encounter_entry_resource.gd
scripts/models/loot_resource.gd
scripts/models/event_resource.gd
scripts/models/event_outcome_resource.gd
scripts/models/region_resource.gd
scripts/models/balancing_config.gd
data/balancing/default_balancing.tres
scenes/ui/home/home_screen.tscn
addons/<gut-or-gdunit4>/...
tests/test_smoke.gd
project.godot (updated [autoload] section)
main.tscn (updated to boot through UIManager)
```

## Interfaces / data contracts

- `UIManager.show_screen(scene_path: String) -> void` — the only public
  entry point later milestones should use to switch screens; screens must
  not instance each other directly.
- `SaveManager.load_or_create() -> void` and `SaveManager.save() -> void`
  — signatures fixed now, bodies filled in starting Milestone 2 (roster)
  and Milestone 4 (Expedition state).
- `GameState` exposes `roster: Array`, `gold: int`, `inventory: Array`, and
  `unlocked_regions: Array[StringName]`. Keep the model arrays untyped in
  this milestone so the autoload parses before `HeroData` exists; change
  `roster` to `Array[HeroData]` in Milestone 2 and `inventory` to
  `Array[ItemResource]` in Milestone 6.
- Base resources use these exact exported property identifiers and types;
  nested dictionaries have the stated shapes:

```gdscript
# HeroClassResource
@export var class_id: StringName
@export var display_name: String
@export_enum("FrontRowFirst", "AnySlot") var basic_attack_target_rule: String
@export var base_attribute_ranges: Dictionary
# { "MIG": Vector2i(min, max), "FOC": Vector2i(...), "GRT": Vector2i(...),
#   "GUI": Vector2i(...), "FTH": Vector2i(...) }
@export var per_level_growth: Dictionary
# { "MIG": float, "FOC": float, "GRT": float, "GUI": float, "FTH": float }
@export var derived_stat_bases: Dictionary
# { "MaxHP": float, "Attack": float, "MagicPower": float, "Defense": float,
#   "Evasion": float, "Initiative": float, "CritChance": float }
@export var derived_stat_attribute_weights: Dictionary
# { derived_stat_name: { "MIG": float, "FOC": float, "GRT": float,
#                        "GUI": float, "FTH": float } }

# HeroTraitResource
@export var trait_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var stat_modifiers: Dictionary       # { derived_stat_name: float }
@export var flags: Array[StringName]

# ItemResource
@export var item_id: StringName
@export var display_name: String
@export_enum("Weapon", "Armor") var slot: String
@export var rarity: StringName
@export var stat_modifiers: Dictionary       # { derived_stat_name: float }

# EncounterEntryResource
@export_enum("Loot", "Event", "Combat") var kind: String
@export var content_id: StringName
# Resolves through the kind-specific loot/event/enemy-group registry.
@export_range(0.001, 1000000.0) var weight: float

# LootResource; EncounterEntryResource.content_id resolves through the Loot registry
@export var loot_id: StringName
@export var min_gold: int
@export var max_gold: int

# EventOutcomeResource
@export var outcome_id: StringName
@export_multiline var journal_text: String
@export_range(0.001, 1000000.0) var weight: float
@export var result: Dictionary
# JSON-safe reward payload: { "gold": int, "item_ids": Array[StringName] }

# EventResource
@export var event_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var outcomes: Array[EventOutcomeResource]

# RegionResource
@export var region_id: StringName
@export var display_name: String
@export var recommended_party_power: int
@export var duration_options_seconds: Array[int]
@export var travel_step_count: int
# Positive; each Travel step is followed by exactly one encounter step.
@export var encounter_pool: Array[EncounterEntryResource]
@export var unlock_condition: Dictionary
# { "kind": "always" | "gold" | "region_cleared",
#   "value": int, "region_id": StringName }
@export var retreat_ends_expedition: bool

# BalancingConfig
@export var party_power_level_weight: float
@export var party_power_stat_weights: Dictionary # { derived_stat_name: float }
@export var missing_front_row_factor: float
@export var party_size_divisor: float
@export var base_hit_chance: float
@export var min_hit_chance: float
@export var max_hit_chance: float
@export var max_crit_chance: float
@export var basic_attack_damage_multiplier: float
@export var skill_damage_multipliers: Dictionary # { skill_id: float }
@export var critical_damage_multiplier: float
@export var max_combat_rounds: int
@export var xp_award_coefficients: Dictionary
# { "recommended_party_power": float, "duration_seconds": float }
@export var xp_threshold_curve: Dictionary
# { "base": int, "growth_factor": float }
@export var encounter_kind_weight_multipliers: Dictionary
# { "Loot": float, "Event": float, "Combat": float }
@export var base_recovery_seconds: int
@export var max_offline_delta_seconds: int
@export var recruitment_cost: int
```

Create `data/balancing/default_balancing.tres` with
`recruitment_cost = 100`; gameplay reads this resource rather than defining a
second recruitment-price constant.

## Testing requirements

- One passing smoke test proving the headless test runner works in this
  project (`godot --headless --path . -s <test-runner-entrypoint>`
  exits 0).
- Manual check: app boots to the empty Home screen with no errors in the
  Godot output panel.
- CI check: existing Android debug export workflow still succeeds after
  the restructuring.
- Manual exported-device check: with auto-rotate enabled, rotating the device
  leaves the game locked in portrait.

## Acceptance criteria

- [x] Folder structure matches [plan §13](../../adventurers-march-implementation-plan.md#13-godot-project-architecture).
- [x] All five autoloads are registered and load without errors.
- [x] Base Resource classes exist with documented, stable field names.
- [x] App boots to an empty Home screen via `UIManager`.
- [x] Headless test framework runs with ≥1 passing test.
- [x] Android debug export CI workflow still passes.
- [x] Exported Android app remains portrait while the device rotates.

## Implementation and validation evidence

Implemented and accepted. On 2026-09-07 the user accepted Milestones 1–4 and
directed that device acceptance be considered complete externally for now.
The checked rotation criterion records that external acceptance; this agent
did not perform a device test. CI has passed.

- **Resources and structure:** all nine Resource contracts are implemented,
  including typed nested arrays and Inspector hints. Empty future-content/screen
  directories are tracked without dummy gameplay content.
- **Balancing:** the one default resource sets recruitment cost to 100 and
  includes the §7 Party Power baseline, published §9 combat defaults and a
  20-round cap. Encounter multipliers are neutral (1.0); the provisional offline
  cap is 86400 seconds per observation, subject to gameplay tuning. Only skills,
  XP, and recovery remain unconfigured. Their owning milestones must author and
  validate them before use; extend, never recreate, the resource.
- **Autoloads:** initialization order is GameState, SaveManager,
  CombatSimulator, ExpeditionManager, UIManager. Startup performs no save I/O
  or content seeding. Stub operations warn and never fabricate gameplay results.
- **Navigation:** main binds its ready, empty screen container through
  `UIManager.bind_screen_root()` before loading/showing Home. This is
  bootstrap-only; `show_screen()` remains the public navigation entry point.
  Pre-binding calls are rejected rather than queued; invalid resources preserve
  the current screen. Screen replacement releases the previous instance.
  Accepted navigation is deferred until tree callbacks finish; pending requests
  are bound to a root generation and discarded when that root exits, including
  redirects from outgoing callbacks during root teardown.
- **Tests:** GUT 9.7.1 is vendored unchanged at upstream commit
  `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605`, with its MIT license. The standard
  CLI and `.gutconfig.json` discover the foundation suite. A pre-run hook injects
  an automatically cleaned OS temporary directory into `SaveManager`, aborting
  if isolation fails. All persistence paths must derive from `get_save_path()`.
  The post-run hook rejects empty discovery and GUT errors/warnings, including
  skipped scripts. CI now runs clean import and this suite before export/upload.
  Milestone 9 audits the gate with the full gameplay suite.
- **Initial local evidence (2026-09-06, before review fixes):** Godot 4.7.2 clean-cache import and headless
  Home launch succeeded. All 17 foundation tests passed (140 assertions).
  Negative controls for empty discovery, a failed assertion, and an unparseable
  test each exited 1. Desktop launch under Xvfb also succeeded with the
  compatibility renderer and dummy audio (the software driver warns that V-Sync
  cannot be configured). Local Android debug export succeeded and produced a
  signed, nonempty ARM64 APK. APK inspection confirms package
  `com.example.helloworld` and portrait orientation (`screenOrientation=1`);
  neither test nor GUT assets are packaged. Export still emits the baseline
  missing-project-icon diagnostic (also reproduced on the original Hello World
  project); it exits 0 and signs/verifies the APK. Icon artwork remains deferred.
- **Review follow-up (2026-09-06):** the updated suite passes 19 tests
  (153 assertions), including save-directory isolation/path injection and the
  additional balancing defaults. Empty discovery, an intentional failed assertion,
  and a skipped parse failure each exit 1 with both hooks enabled; temporary save
  directories are removed on process exit. Normal headless startup is error-free.
  The updated ARM64 APK exports and passes signature verification, preserves
  `com.example.helloworld` and portrait orientation, and excludes tests/GUT.
  The baseline missing-icon diagnostic is unchanged. CodeQL reports zero Actions
  alerts (GDScript is not analyzed). CI approval and the exported-device rotation
  check remain required.
- **CI verified (2026-09-06):** the earlier approval requirement is resolved.
  The [merged foundation workflow run](https://github.com/pompomon/godot-apk/actions/runs/34013018850)
  passed on `8923be4`, including clean import, headless tests, signed Android
  export, and APK upload. Its build job/logs were verified during Milestone 2.
  This evidence closes the foundation CI check, not the device check.
- **Device acceptance (2026-09-07):** accepted externally per the user's
  direction above. Earlier sessions had no connected Android device or
  compatible emulator; manifest inspection was not treated as a device test.

## Risks

- **Autoload load-order issues:** Godot autoloads initialize in the order
  listed in `project.godot`; if `SaveManager` depends on `GameState`
  existing, list `GameState` first. Mitigation: keep dependencies one-way
  and document the required order in `project.godot`'s comments.
- **Restructuring breaking the export preset paths:** `export_presets.cfg`
  may reference specific scene paths. Mitigation: re-run the debug export
  locally/CI immediately after restructuring, not at the end of the
  milestone.

## Next-milestone handoff

Milestone 2 (Hero roster) will fill in `HeroClassResource`/
`HeroTraitResource` field data, implement `HeroData` and `HeroGenerator`
against the stable schema defined here, and build the first real screens
(Company Roster, Hero Detail) using `UIManager.show_screen`.

`SaveManager.load_or_create()` is a no-op until then; `save()` only warns.
Keep autoload initialization I/O-free. Replace the foundation-empty-state test
with isolated new-game tests for 4 Heroes/100 gold, resetting in-memory state and
using fresh storage per persistence case as specified in Milestone 2. Preserve
the real-main bootstrap test and both GUT hooks.
`GameState.roster` becomes `Array[HeroData]` in Milestone 2 and inventory becomes
`Array[ItemResource]` in Milestone 6. Expedition/combat parameters and return
values that need not-yet-existing runtime types currently use `Variant`, with
their intended types documented in the stubs. Do not introduce duplicate state,
recruitment constants, or another balancing resource when filling them in.
`ExpeditionManager` is the sole owner of the future active Expedition;
`SaveManager` restores it alongside `GameState` without duplicating it there.

→ Next: [02-hero-roster.md](02-hero-roster.md)
