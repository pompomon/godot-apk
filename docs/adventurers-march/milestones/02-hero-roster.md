# Milestone 2 — Hero Roster

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Introduce Heroes as real, generated data: classes, attributes, traits, and
status, deterministic recruitment, persistence, and the screens needed to
view and grow the Company's roster.

## Scope

**In scope:** `HeroClassResource`/`HeroTraitResource` content for the four
MVP classes, `HeroData` model, seeded `HeroGenerator`, derived-stat
calculation, Company Roster and Hero Detail screens, seeding a starting
roster of 4 Heroes, gold-priced recruitment offers, and versioned save/load.

**Out of scope:** Party formation, equipment, Expeditions, combat — Heroes
exist and can be inspected, but cannot yet be sent anywhere.

## Prerequisites / dependencies

- Milestone 1 (Technical foundation): autoloads, base Resource classes,
  `UIManager.show_screen`, test framework must already exist.

## Implementation decisions

- Start with three persisted offers. Replace only the purchased slot; no
  timed refresh or manual reroll is introduced.
- Use immediately functional additive-stat traits with compensating penalties.
  Brave, Cautious, and Quick Healer below are design examples, not required
  content: their conditional/percentage effects belong to later gameplay
  systems and are not silently reinterpreted as flat bonuses.
- Show cumulative XP with an inactive progress bar and explanatory text.
  XP thresholds, awards, and level-up processing remain in Milestone 6.
- Initial class ranges, growth, stat weights, trait values, and names are
  provisional authored content. Preserve explicit zero weights and distinct
  class roles; tuning does not require changes to generic generation/stat code.
- Retain the foundation's test-before-export pipeline and app/package IDs.
  Passing local tests or manifest inspection does not complete physical-device
  acceptance checks.

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
   `RefCounted`, not `Node`): immutable stable ID, name, class reference,
   level, XP, attributes, traits, equipment slots (empty for now), status
   enum.
5. Implement `scripts/systems/hero_generator.gd`
   (`class_name HeroGenerator`) with a pure `generate_hero(hero_id, seed,
   class_pool, trait_pool, level = 1) -> HeroData` function per the plan's
   pseudocode. Roll each attribute independently and uniformly with
   `rng.randi_range(min, max)` from the selected class's inclusive
   `base_attribute_ranges`; there is no separate `base_attributes` field.
6. Implement derived-stat calculation (`MaxHP`, `Attack`, `MagicPower`,
   `Defense`, `Evasion`, `Initiative`, `CritChance`) as a pure function
   taking a `HeroData` and returning a stats struct/dictionary, reusable by
   later combat/evaluation code. Implement the exact level-growth,
   class-base, attribute-weight, modifier, flooring, and clamping order from
   plan §6; author all bases and weights on each class resource.
7. Build Company Roster screen: list/grid of Heroes with class icon
   (placeholder OK), level, and status badge; tapping navigates to Hero
   Detail via `UIManager.show_screen`.
8. Build Hero Detail screen: attributes, traits, status, XP progress bar
   (equipment section can be a stub pointing to Milestone 6).
9. On new-game creation (`SaveManager.load_or_create()` when no save
   exists), initialize `GameState.gold` to **100**, then generate and store
   4 Heroes (one per class) into `GameState.roster`, and initialize
   `GameState.roster_capacity` to **12**.
10. Implement deterministic recruitment offers from the save-level RNG seed
    and caller-reserved Hero IDs.
    Read the price from `BalancingConfig.recruitment_cost` (the default
    resource sets it to **100 gold**), so a fresh save can buy one offer
    immediately. Show the current offers and cost on the Company Roster
    screen; a successful recruit deducts gold, adds the same Hero ID that
    was assigned to the offer, advances/replaces the offer, and saves
    immediately. Disable recruitment when funds are insufficient or the
    roster cap is reached.
11. Implement `SaveManager.load_or_create()` and `save()` for the state
    available in this milestone: save version, roster, roster capacity, gold,
    unlocked Regions, recruitment offers, the save-scoped `next_hero_id`
    counter, and RNG seed state. Serialize each immutable `hero_id`,
    `HeroData`, and Resource reference to plain JSON-safe values and restore
    them on load.
    Constrain every seed/RNG-state value to `[0, 2^53 - 1]` so JSON number
    serialization preserves it exactly.
12. Add the version-to-migration dispatch entry point for version 1 and
    implement the best-effort replacement sequence from
    [plan §12](../../adventurers-march-implementation-plan.md#12-save-system):
    write, flush/close, reopen, and validate same-directory temporary files;
    copy a valid primary to the backup without first removing it; then replace
    the backup and primary through `DirAccess`. Do not claim OS-level
    durability or cross-platform atomic replacement: GDScript exposes no
    `fsync` or parent-directory sync. If the primary is missing or invalid,
    load the valid backup with a warning and restore the primary without
    overwriting that backup.
13. Preserve the foundation's injectable `SaveManager.storage_directory`.
     Derive the primary path from `get_save_path()` and sibling `.tmp`, `.bak`,
     and `.bak.tmp` paths from that primary; never bypass it with a hard-coded
     `user://` save path. Keep autoload initialization I/O-free so GUT's pre-run
     isolation hook binds storage before `load_or_create()` is called.
     Replace the foundation-empty-state smoke test with new-game assertions
     (4 Heroes, 100 gold, typed roster). Give each persistence case a fresh
     temporary directory and reset/restore in-memory singleton state between
     cases; retain the real-main-scene bootstrap test using isolated storage.

## Expected files / scenes / scripts / data

```
data/classes/knight.tres
data/classes/ranger.tres
data/classes/wizard.tres
data/classes/cleric.tres
data/traits/hearty.tres
data/traits/keen_eyed.tres
data/traits/lightfooted.tres
data/traits/studious.tres
scripts/models/hero_data.gd
scripts/systems/hero_catalog.gd          # ordered, project-owned content lookup
scripts/systems/hero_generator.gd
scripts/systems/recruitment_service.gd
scripts/systems/hero_stats.gd            # derived-stat calculation
scenes/ui/roster/roster_screen.tscn
scenes/ui/hero_detail/hero_detail_screen.tscn
tests/test_hero_generator.gd
tests/test_hero_content.gd
tests/test_hero_stats.gd
tests/test_save_manager.gd
tests/test_recruitment.gd
tests/test_roster_ui.gd
```

## Interfaces / data contracts

```gdscript
# HeroGenerator
static func generate_hero(hero_id: String, seed: int,
        class_pool: Array[HeroClassResource],
        trait_pool: Array[HeroTraitResource], level: int = 1) -> HeroData

# HeroData (RefCounted)
var hero_id: String            # immutable and unique within this save
var hero_name: String
var hero_class: HeroClassResource
var level: int
var xp: int
var attributes: Dictionary   # { "MIG": int, "FOC": int, "GRT": int, "GUI": int, "FTH": int }
var traits: Array[HeroTraitResource]
var status: HeroStatus       # enum: IDLE, ASSIGNED, ON_EXPEDITION, RESTING, WOUNDED, DEAD

# GameState addition; increment whenever an ID is reserved
var next_hero_id: int = 1
var roster_capacity: int = 12

# derived stats
static func compute_derived_stats(hero: HeroData) -> Dictionary
    # returns { "MaxHP", "Attack", "MagicPower", "Defense", "Evasion",
    #           "Initiative", "CritChance" }
```

```gdscript
# RecruitmentService
static func generate_offers(seed: int, hero_ids: Array[String],
        class_pool: Array[HeroClassResource],
        trait_pool: Array[HeroTraitResource]) -> Array[HeroData]
static func recruit(hero: HeroData, balancing: BalancingConfig) -> bool
# affordability and deduction both use balancing.recruitment_cost
```

`HeroStatus` should be declared once (e.g., in `hero_data.gd` or a shared
enums script) and reused by Party formation (Milestone 3) and Expeditions
(Milestone 4) — do not redefine status values in multiple places.

`hero_id` is allocated once from the persisted, monotonically increasing
`GameState.next_hero_id` counter when a starting Hero or offer is created.
It is never regenerated from the Hero's name/class or roster index, and an
offer keeps that ID when recruited. Callers reserve the `hero_ids` passed to
`generate_offers` and advance the counter in the same saved mutation.
`Evasion` and `CritChance` are returned as total probabilities in
`[0.0, 1.0]`, matching the Milestone 5 combat contract.

### Persistence and generation handoff

- `SaveManager.load_or_create()` and `save()` retain their `void` contracts.
  `last_success`, `last_committed`, `last_error`, and `last_warning` expose the
  result. **Primary replacement is the commit point:** recruitment checks
  `last_committed`, rolls back all pre-commit state on failure, and never undoes
  a purchase merely because a post-commit diagnostic occurred.
- Version 1 snapshots include roster and offer Hero records, gold, capacity,
  `next_hero_id`, `recruitment_seed`, `recruitment_sequence`, per-slot
  `offer_seeds`, empty inventory, and unlocked Region IDs. Hero records use
  class/trait content IDs, original attributes, cumulative XP, named statuses,
  and empty equipment slots. Derived stats and UI selection are not saved.
- `HeroCatalog` supplies explicit ordered pools and known-ID resolution.
  Generation consumes the class pool, name table, attributes in
  `MIG/FOC/GRT/GUI/FTH` order, then an equal-probability zero-or-one trait roll.
  All authored roster traits are eligible for all four classes.
- Recruitment derives each local generator seed from the saved base seed and
  sequence using bounded integer arithmetic:
  `(seed % 2147483647 + (sequence % 2147483647) * 48271) % 2147483647`.
  The sequence advances whenever a Hero is generated; IDs are reserved before
  generation. The three offers keep their own generation seeds. This is
  deterministic gameplay sampling, not a cryptographic RNG or serialized native
  RNG state. Saved seeds/counters must remain exactly representable JSON integers.
- Pool/name order and authored content are part of deterministic generation.
  Intentional changes require reviewing golden tests and existing-save
  compatibility. Future milestones must extend the versioned validation and
  migration boundary when adding equipment, Party state, or new status behavior;
  they must not bypass validation or duplicate Expedition ownership.

## Testing requirements

- Unit test: `generate_hero` with a fixed seed, class pool, and trait pool
  produces an exact, reproducible `HeroData` (same supplied ID, name, class,
  attributes, traits) across repeated calls and across test runs.
- Unit test: starting-roster and offer IDs are unique, remain unchanged when
  an offer is recruited, and survive save/load.
- Unit test: `compute_derived_stats` produces expected values for at least
  one hand-computed example Hero per class, including fractional intermediate
  values and the specified modifier/flooring order, with total `Evasion` and
  `CritChance` values in `[0.0, 1.0]`.
- Manual test: new game shows exactly 4 Heroes (one per class) in Company
  Roster; each opens a correct Hero Detail screen.
- Unit test: a save/load round trip preserves the roster (including Hero
  IDs), roster capacity, gold, unlocked Regions, recruitment offers,
  `next_hero_id`, and RNG seed state exactly, including the maximum seed
  `2^53 - 1`.
- Unit test: a missing or invalid primary save falls back to the last valid
  `.bak` and restores the primary without changing that backup; an injected
  interruption immediately before primary replacement leaves the old primary
  loadable.
- Unit test: a fresh save has 100 gold and can recruit one 100-gold offer;
  recruitment checks gold/cap, persists the mutation, and produces
  deterministic replacement offers from the stored seed/ID counter.

## Acceptance criteria

- [x] Four `HeroClassResource` `.tres` files exist with distinct,
      class-appropriate attribute ranges/growth curves.
- [x] 3–5 `HeroTraitResource` `.tres` files exist.
- [x] `HeroGenerator.generate_hero` is deterministic for a given ID and seed
      (covered by a passing unit test).
- [x] Company Roster screen lists all Heroes with correct status badges.
- [x] Hero Detail screen shows correct attributes/traits/status/XP for the
      selected Hero.
- [x] New game seeds exactly 4 Heroes, one per class, with unique immutable
      IDs.
- [x] A new game starts with 100 gold; the player can immediately recruit one
      deterministic 100-gold offer, and the purchase survives reload.
- [x] Versioned save/load round-trips all Milestone 2 state, validates
      flushed temporary files before best-effort replacement, and recovers
      from a missing or invalid primary via `.bak` before restoring the
      primary.

### Exported-device acceptance still required

The implementation and automated checks do not substitute for these manual
checks. Keep the overall milestone unchecked until they are recorded:

- [ ] Install the exported ARM64 APK and cold-launch a new Company; inspect
  each class and confirm name, attributes, traits, status, and inactive XP UI.
- [ ] Verify scrolling, long-text wrapping, readability, and effective
  48×48 dp touch targets on a target-density Android device.
- [ ] Recruit an offer, force-close and relaunch the app, and confirm the same
  Hero ID, five-Hero roster, zero gold, and unchanged replacement offers.
- [ ] Verify recovery with a missing and a corrupt primary while retaining a
  valid backup; confirm feedback and that the backup is not overwritten.
- [ ] Enable auto-rotate and rotate the device; the game remains portrait.
  This also closes the foundation's outstanding device check.

## Implementation and validation evidence

Implemented the four classes, four flat trade-off traits, immutable Hero IDs,
pure generation/stat calculations, transactional recruitment, version-1 saves,
backup recovery, and Home/Roster/Detail navigation.

- **Local gameplay suite (2026-09-06):** 93 tests passed with 14,942
  assertions using the existing Godot 4.7.2/GUT runner. Coverage includes exact
  seeded Heroes, per-class arithmetic, complete save round trips, invalid
  inputs, interrupted writes, unchanged recovery backups, save-failure purchase
  rollback, and touch-emulated scrolling/taps.
- **Test isolation follow-up:** the original OS-temporary-directory pre-run
  hook is retained unchanged, and each persistence/bootstrap/UI case now owns
  a separate `DirAccess.create_temp` directory and restores singleton state.
  This final restoration occurred after the 93-test run above; the complete
  suite with the committed OS-temp setup still requires CI verification.
  No player save is used. Verification logs and temporary tooling remain
  outside the tracked project.
- **Export:** import, Android debug export, and APK signature verification
  passed after the final isolation restoration. The ARM64 APK includes the
  four classes, four traits, and three screens, and excludes tests/GUT.
  The pre-existing missing-project-icon export diagnostic remains; final icon
  artwork is outside this milestone.
- **Review:** fixed touch scrolling over Hero buttons/offer panels and added
  input-routing regressions. Saved original attributes are validated
  independently of today's generation ranges, so balance tuning does not
  invalidate older rolls. A follow-up code review found no significant issues.
- **Security:** changed-file secret scanning found no secrets. CodeQL was
  invoked for these non-trivial changes, but no changed language is supported
  by its available analyzers; **GDScript was not analyzed**.
- **CI pending:** the [implementation workflow](https://github.com/pompomon/godot-apk/actions/runs/34018091613)
  for `578c1e5` requires approval (`action_required`); its jobs/logs endpoint
  reports zero jobs. Approve the existing Android workflow to verify the final
  isolated suite and CI export. Local export is not a substitute for that run.
- **Device pending:** no Android device or compatible emulator was connected.
  Complete the manual checklist above before checking the overall milestone.

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
