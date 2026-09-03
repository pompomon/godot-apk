# Milestone 2 — Hero Roster

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Introduce Heroes as real, generated data: classes, attributes, traits, and
status, plus the screens needed to view the Company's roster.

## Scope

**In scope:** `HeroClassResource`/`HeroTraitResource` content for the four
MVP classes, `HeroData` model, seeded `HeroGenerator`, derived-stat
calculation, Company Roster and Hero Detail screens, seeding a starting
roster of 4 Heroes.

**Out of scope:** Party formation, equipment, Expeditions, combat — Heroes
exist and can be inspected, but cannot yet be sent anywhere.

## Prerequisites / dependencies

- Milestone 1 (Technical foundation): autoloads, base Resource classes,
  `UIManager.show_screen`, test framework must already exist.

## Tasks

1. Fill in `HeroClassResource` fields (per
   [plan §6](../../adventurers-march-implementation-plan.md#6-heroes-classes-attributes-traits-status-generation)):
   class name, base attribute ranges (`MIG`/`FOC`/`GRT`/`GUI`/`FTH`), and
   per-level growth curve values.
2. Author four `.tres` instances under `data/classes/`: Knight, Ranger,
   Wizard, Cleric.
3. Fill in `HeroTraitResource` fields: trait name, description, stat/flag
   modifiers. Author 3–5 `.tres` instances under `data/traits/` (e.g.,
   Brave, Cautious, Quick Healer).
4. Implement `scripts/models/hero_data.gd` (`class_name HeroData`,
   `RefCounted`, not `Node`): name, class reference, level, XP, attributes,
   traits, equipment slots (empty for now), status enum.
5. Implement `scripts/systems/hero_generator.gd`
   (`class_name HeroGenerator`) with a pure `generate_hero(seed, class_pool,
   level = 1) -> HeroData` function per the plan's pseudocode.
6. Implement derived-stat calculation (`MaxHP`, `Attack`, `MagicPower`,
   `Defense`, `Evasion`, `Initiative`, `CritChance`) as a pure function
   taking a `HeroData` and returning a stats struct/dictionary, reusable by
   later combat/evaluation code.
7. Build Company Roster screen: list/grid of Heroes with class icon
   (placeholder OK), level, and status badge; tapping navigates to Hero
   Detail via `UIManager.show_screen`.
8. Build Hero Detail screen: attributes, traits, status, XP progress bar
   (equipment section can be a stub pointing to Milestone 6).
9. On new-game creation (`SaveManager.load_or_create()` when no save
   exists), generate and store 4 Heroes (one per class) into
   `GameState.roster`.

## Expected files / scenes / scripts / data

```
data/classes/knight.tres
data/classes/ranger.tres
data/classes/wizard.tres
data/classes/cleric.tres
data/traits/brave.tres
data/traits/cautious.tres
data/traits/quick_healer.tres
scripts/models/hero_data.gd
scripts/systems/hero_generator.gd
scripts/systems/hero_stats.gd            # derived-stat calculation
scenes/ui/roster/roster_screen.tscn
scenes/ui/hero_detail/hero_detail_screen.tscn
tests/test_hero_generator.gd
tests/test_hero_stats.gd
```

## Interfaces / data contracts

```gdscript
# HeroGenerator
static func generate_hero(seed: int, class_pool: Array[HeroClassResource],
        level: int = 1) -> HeroData

# HeroData (RefCounted)
var hero_name: String
var hero_class: HeroClassResource
var level: int
var xp: int
var attributes: Dictionary   # { "MIG": int, "FOC": int, "GRT": int, "GUI": int, "FTH": int }
var traits: Array[HeroTraitResource]
var status: HeroStatus       # enum: IDLE, ASSIGNED, ON_EXPEDITION, RESTING, WOUNDED, DEAD

# derived stats
static func compute_derived_stats(hero: HeroData) -> Dictionary
    # returns { "MaxHP", "Attack", "MagicPower", "Defense", "Evasion",
    #           "Initiative", "CritChance" }
```

`HeroStatus` should be declared once (e.g., in `hero_data.gd` or a shared
enums script) and reused by Party formation (Milestone 3) and Expeditions
(Milestone 4) — do not redefine status values in multiple places.

## Testing requirements

- Unit test: `generate_hero` with a fixed seed and class pool produces an
  exact, reproducible `HeroData` (same name, class, attributes, traits)
  across repeated calls and across test runs.
- Unit test: `compute_derived_stats` produces expected values for at least
  one hand-computed example Hero per class.
- Manual test: new game shows exactly 4 Heroes (one per class) in Company
  Roster; each opens a correct Hero Detail screen.

## Acceptance criteria

- [ ] Four `HeroClassResource` `.tres` files exist with distinct,
      class-appropriate attribute ranges/growth curves.
- [ ] 3–5 `HeroTraitResource` `.tres` files exist.
- [ ] `HeroGenerator.generate_hero` is deterministic for a given seed
      (covered by a passing unit test).
- [ ] Company Roster screen lists all Heroes with correct status badges.
- [ ] Hero Detail screen shows correct attributes/traits/status/XP for the
      selected Hero.
- [ ] New game seeds exactly 4 Heroes, one per class.

## Risks

- **Attribute ranges too similar across classes** would make Party
  composition feel meaningless later. Mitigation: sanity-check that each
  class's primary attribute (per plan §6 table) is clearly highest for
  that class across the generation range.
- **Trait power creep:** a trait that's strictly better than "no trait"
  with no downside undermines build diversity. Mitigation: pair
  bonuses/penalties per plan §6 guidance and review before merging new
  traits.

## Next-milestone handoff

Milestone 3 (Party formation) consumes `HeroData`/`HeroStatus` and the
Company Roster's list of `Idle` Heroes to let the player build a Party.
`compute_derived_stats` will be reused by `PartyEvaluator`.

→ Next: [03-party-formation.md](03-party-formation.md)
