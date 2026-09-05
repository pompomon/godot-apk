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
3. Define base `Resource` subclasses (empty/minimal exported fields for
   now, to be filled out starting Milestone 2):
   - `scripts/models/hero_class_resource.gd` (`class_name HeroClassResource`)
   - `scripts/models/hero_trait_resource.gd` (`class_name HeroTraitResource`)
   - `scripts/models/item_resource.gd` (`class_name ItemResource`)
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
7. Confirm the existing Android debug export
   (`.github/workflows/android-apk.yml`) still succeeds with the
   restructured project (no gameplay change expected, but autoload
   registration and folder moves can break exports if misconfigured).

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
scripts/models/region_resource.gd
scripts/models/balancing_config.gd
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
  this milestone so the autoload parses before `HeroData` and `ItemData`
  exist; change them to `Array[HeroData]` in Milestone 2 and
  `Array[ItemData]` in Milestone 6 when those classes are defined.
- Each base `Resource` subclass declares its exported fields exactly as
  named in [plan §6](../../adventurers-march-implementation-plan.md#6-heroes-classes-attributes-traits-status-generation)
  and [plan §10](../../adventurers-march-implementation-plan.md#10-events-regions-equipment-progression)
  so Milestone 2+ can author `.tres` data against a stable schema.

## Testing requirements

- One passing smoke test proving the headless test runner works in this
  project (`godot --headless --path . -s <test-runner-entrypoint>`
  exits 0).
- Manual check: app boots to the empty Home screen with no errors in the
  Godot output panel.
- CI check: existing Android debug export workflow still succeeds after
  the restructuring.

## Acceptance criteria

- [ ] Folder structure matches [plan §13](../../adventurers-march-implementation-plan.md#13-godot-project-architecture).
- [ ] All five autoloads are registered and load without errors.
- [ ] Base Resource classes exist with documented, stable field names.
- [ ] App boots to an empty Home screen via `UIManager`.
- [ ] Headless test framework runs with ≥1 passing test.
- [ ] Android debug export CI workflow still passes.

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

→ Next: [02-hero-roster.md](02-hero-roster.md)
