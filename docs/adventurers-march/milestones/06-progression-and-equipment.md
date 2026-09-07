# Milestone 6 — Progression and Equipment

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Give completed Expeditions lasting consequences: Hero XP/leveling, an
equipment system that meaningfully changes derived stats, and a complete
Wounded/Resting recovery flow — closing out the MVP's core Hero
progression systems.

## Scope

**In scope:** XP gain and leveling using class growth curves, item model
and starter item pool, Equipment screen, full Wounded → Resting → Idle
recovery flow, and item-loot integration.

**Out of scope:** crafting/enchanting (explicit non-goal), additional
Regions/content variety (Milestone 7).

## Prerequisites / dependencies

- Milestone 5 (Combat simulation): Combat outcomes and Hero HP/status
  results must already flow into Expedition finalization.
- Milestone 4 (First expedition) already owns and tests applying Loot gold
  at reveal time; this milestone extends that path rather than replacing it.

## Tasks

### Delivery contracts (2026-09-07)

The implementation uses the following MVP defaults. They are balance choices,
not physical-device acceptance; subsequent tuning must preserve frozen saves.

- Every participant earns the same XP on completion, including Defeat and
  terminal Retreat, using the **selected** duration, not the shortened journal.
  Freeze `xp_award` at dispatch; legacy Expeditions migrate with zero and never
  gain retroactive rewards. Cumulative XP and level are persisted independently:
  loading does not relevel Heroes against today's curve. Never lower a saved
  level. At the existing maximum level, retain cumulative XP without advancing.
  Reject XP overflow before any mutation; unreachable thresholds stop advancement.
  A zero frozen award skips progression altogether, including legacy Heroes
  whose saved XP and level do not match today's thresholds. Positive awards
  advance using the current threshold curve at first completion; already
  committed levels never change merely because content was retuned.
- Configure XP weights initially to `recommended_party_power: 0.25` and
  `duration_seconds: 1.0`, with threshold `base: 100, growth_factor: 1.25`.
  Growth remains on class Resources; generated attributes are never rewritten.
- Use one canonical Hero deadline, `recovery_ready_at`, rather than introducing
  a competing `resting_until_timestamp`. New finalization converts frozen
  Wounded results to Resting, also resting positive-HP survivors at or below
  25% of their **dispatch** MaxHP. Freeze the recovery duration and HP percentage
  in new Expeditions, initially 60 seconds and 25 percent. Deadlines start at
  the observation committing completion. Do not change CombatResult's numeric
  statuses or replay semantics.
- Version 5 preserves original-schema validation of versions 1–4. Existing
  positive Wounded deadlines become Resting with the same deadline; legacy
  Wounded/Resting Heroes without deadlines remain unchanged. Old Expeditions
  use zero XP, 60-second recovery, and zero heavy-damage percentage, retaining
  their prior finalization behavior except for the explicit Resting phase.
- All classes can use any slot-compatible item. Equipment is editable for Idle,
  Assigned, and Resting roster Heroes, never OnExpedition, Wounded, Dead, or
  recruitment offers. Drafts hold desired slots and expected original slots;
  confirmation revalidates identity, status and current inventory rather than
  replacing inventory from a stale draft.
- Inventory is an `Array[ItemResource]` of unequipped copies. Duplicate IDs
  represent distinct owned copies of the same immutable authored Resource.
  Equipping consumes one copy; swapping/unequipping returns one copy. Persist
  item IDs only through an explicit registry, never caller-provided paths.
- Loot authors an ordered weighted item pool and a drop probability. Resolve
  at most one item per Loot result using the existing Expedition RNG after
  all encounters have been selected. Event outcomes may contain `item_ids`.
  Gold-only historical payloads remain valid; new item-bearing Loot/Event
  payloads have exactly `gold` and `item_ids`, with a bounded list of known IDs.
  Travel and Combat retain their existing exact payload schemas.
  `LootResource.item_pool` maps known item IDs to finite nonnegative weights;
  `item_drop_chance` is in `[0, 1]`. An empty/zero-chance pool consumes no RNG
  draws and preserves controlled gold-only fixture behavior. Event item lists
  contain at most 16 copies. No new reward-loss penalty is introduced beyond
  omitting encounters after a terminal result.
- `ExpeditionData` adds frozen integer `xp_award`, `recovery_seconds`, and
  `rest_hp_percent`. XP awards and recovery parameters are validated before
  dispatch; presentation reads frozen rewards only after commit. Item rewards,
  gold, XP/level, statuses/deadlines, cursor and clocks share the existing save
  transaction; report acknowledgment never awards anything.
- Shared interfaces: `ItemCatalog.items()`, `item_by_id(id)`,
  `validate_item(item)` and `validate_catalog()`; `Leveling` accepts an optional
  `BalancingConfig` for calculations: `validation_error(balancing)`,
  `award(recommended_power, duration_seconds, balancing)`,
  `threshold(level, balancing)`, `preview(hero, amount, balancing)` and
  `grant_xp(hero, amount, balancing)`. Invalid awards return `-1`, invalid
  previews return an `error`
  dictionary, valid previews contain `xp` and `level`; grant returns a boolean
  and mutates only XP/level after validation. Threshold `-1` means unreachable.
  Threshold/preview validation is independent of live award/recovery tuning,
  since those inputs are already frozen for pending Expeditions.
- Equipment uses a scene-local `EquipmentService` instance holding the selected
  canonical Hero and original/desired slot references. Its `preview_stats()`
  computes with detached Hero values, never temporarily mutating a roster Hero.
  `confirm()` revalidates and saves the transfer; `last_error` is instance-local
  feedback. Failed pre-commit writes preserve both ownership and the draft for
  retry; navigation occurs only after success.

### Bounded delivery and ownership

1. Validate pure leveling, item Resources/registry and shared stat effects before
   enabling rewards or changing save schemas.
2. Integrate version-5 persistence and lifecycle together, including checkpoints,
   migrations and save-fault tests. Do not ship converted Resting statuses
   without their observer.
3. Add Equipment transactions/UI and complete progression/reward presentation,
   then activate item drops and validate the integrated revision.

The pure-domain writer owns Leveling, ItemCatalog/items, HeroStats and balancing.
The integration writer owns GameState, SaveManager, ExpeditionData/Step,
generation/catalog/reward Resources and ExpeditionManager. The UI writer owns
EquipmentService and screens. Each owns corresponding focused tests; one
validation owner checks each integrated revision with both standard GUT hooks,
clean import and Android export. No new polling system or reward handler is
introduced. Confirm all writers have stopped before publication.

Map inventory and equipped IDs through ItemCatalog → GameState/HeroData →
SaveManager → EquipmentService/UI; frozen reward metadata through
ExpeditionGenerator → ExpeditionData/Step validators → SaveManager →
ExpeditionManager → Report; XP/stat changes through Leveling → HeroStats →
PartyEvaluator/snapshot capture and Hero Detail. Extend the existing isolated
test state and rollback coverage with every mutable field.

### Validation evidence

**Baseline (2026-09-07, `767759b`):** the exact Godot 4.7.2 editor and
templates were installed with the workflow's SHA512 checks. Clean import,
the full GUT suite (**267 tests / 20,238 assertions**, both hooks enabled),
and Android debug export passed. The nonempty APK was **28,448,447 bytes**.
Logs are `/tmp/m6-baseline-import.log`, `/tmp/m6-baseline-tests.log`, and
`/tmp/m6-baseline-export.log`. This is local baseline evidence, not new
milestone acceptance, remote CI, or physical-device validation.

**Pure-domain checkpoint:** six starter items, the explicit registry, cached
cumulative leveling, and shared equipment stat contributions are implemented.
Clean import and focused checks passed (**33 tests / 1,557 assertions**);
the full suite passed **282 tests / 21,237 assertions**, and Android export
produced **28,462,395 bytes**. Logs: `build/m6-domain-*.log` (ignored build
artifacts). The domain writer confirmed all messages handled and no pending
writes before publication. This checkpoint does not yet enable XP rewards,
inventory persistence, Equipment UI, or the full recovery flow.
Published as **`eb84828`**, with the working tree verified clean. Changed-file
secret scanning was clean; CodeQL reported no supported changed language, so
no CodeQL analysis was performed.

**Persistence/lifecycle and Equipment checkpoint:** version-5 original-schema
migrations, item ownership, frozen reward/recovery fields, exactly-once
finalization, Resting recovery, and Equipment draft/preview/confirmation UI are
implemented. Hero Detail refreshes XP and stat values in place, preserving its
existing container-identity regression. Controlled Loot/Event fixtures exercise
item rewards, but production drops remain disabled at this boundary.

Clean import passed. Backend focused checks passed **113 tests / 3,309
assertions**; Equipment/UI focused checks passed **38 / 794**. The full suite
passed **312 tests / 21,815 assertions**, with both GUT hooks, and Android
debug export produced **28,479,394 bytes**. Logs:
`build/m6-integration-{import,backend,ui,full,export}.log`. Initial iteration
failures exposed fixture Resource aliasing, a test-local inferred type, and
the intentional inventory/Loot schema changes; these were fixed without
removing regression coverage. Read-only review found no significant issues.
All source writers confirmed they had stopped with no queued work before
publication as **`8214d5e`**, with a clean working tree verified. Changed-file
secret scanning was clean; CodeQL again reported no supported changed language.
Production activation and mobile acceptance remain separate gates.

**Activated milestone validation (2026-09-07):** Green Hollow's Wayside Cache
now has a 50% chance of one weighted starter item; Quiet Ruins' coin outcome
also grants a Short Sword. The live-loop tests demonstrate both authored reward
paths, fixed-seed repeatability, hidden future rewards, failed-save retry,
leveling, equipping earned items, and reload/acknowledgment without duplication.
The historical gold-only persistence fixture temporarily strips/restores Event
item rewards instead of relaxing original-schema migration validation.

Clean import passed. Live/backend focused tests passed **72 / 2,487 assertions**;
fixture/live-loop focus passed **14 / 435**. The full GUT suite passed
**314 tests / 21,874 assertions**, both standard hooks enabled, with no skipped
scripts or GUT warnings/errors. Android debug export exited successfully and
produced a nonempty **28,479,394-byte APK**. Logs:
`build/m6-final-{import,focused,fixtures,full,export}.log`. The existing missing
project-icon/ADB diagnostics are not new gameplay failures. All source writers
confirmed they had stopped with no pending edits or queued work before closeout.
These are local results; physical-device acceptance is still pending below.

Progression/recovery uses `xp_award_coefficients`, `xp_threshold_curve`,
`base_recovery_seconds`, and `recovery_hp_percent` in the existing
`data/balancing/default_balancing.tres`. The XP fields were unconfigured
foundation fields; recovery already had the Milestone 5 default. Validate
required keys, finite nonnegative XP coefficients,
a positive threshold base/growth factor, and a positive recovery duration;
do not consume placeholder zeros or replace unrelated balancing settings.

1. Implement XP gain at Expedition finalization: compute one award
   from the existing `RegionResource.recommended_party_power` and Expedition
   duration: `floor(recommended_party_power *
   xp_award_coefficients["recommended_party_power"] + duration_seconds *
   xp_award_coefficients["duration_seconds"])`, clamped to a minimum of 0.
   Grant it exactly once to each participating Hero, per
   [plan §10](../../adventurers-march-implementation-plan.md#10-events-regions-equipment-progression).
2. Implement leveling with cumulative lifetime XP. For level `L >= 1`, the
   XP cost to advance to `L + 1` is
   `ceil(xp_threshold_curve["base"] *
   pow(xp_threshold_curve["growth_factor"], L - 1))`; therefore the cumulative
   threshold for reaching level `L` is the sum of those costs for levels
   `1` through `L - 1` (and the level-1 threshold is `0`). After adding an
   award, repeatedly increment the Hero's level while their XP meets the next
   cumulative threshold, then reapply the class's growth curve once to
   recompute derived stats (via `compute_derived_stats` from Milestone 2).
3. Fill in `ItemResource` fields (slot: `Weapon`/`Armor`, rarity tier, flat
   stat modifiers) and author a small starter item pool under
   `data/items/` (e.g., 2–3 weapons, 2–3 armor pieces, spanning Common/
   Uncommon rarity).
4. Implement inventory storage on `GameState` as `Array[ItemResource]`.
   MVP items are stateless resource references; moving one between inventory
   and equipment preserves that same resource reference.
5. Extend `HeroData`/`compute_derived_stats` to apply equipped item stat
   modifiers on top of base/leveled stats.
   Extend `SaveManager` to encode inventory entries and both equipped slots
   as `ItemResource.item_id` values and resolve those IDs through the item
   registry on load.
6. Build Equipment screen: per-Hero weapon/armor slot assignment from
   available inventory, showing before/after stat deltas prior to
   confirming.
7. Implement the full Wounded/Resting recovery flow: when Expedition
   finalization applies a `Wounded` result to the roster, immediately
   transition that Hero to `Resting`, assign
   `recovery_ready_at = now_utc + recovery_duration` (data-tunable,
   e.g., via `BalancingConfig`), and persist the status and timestamp in that
   same finalization mutation. `ExpeditionManager.reveal_progress` (or a
   similarly-invoked periodic check) transitions `Resting` Heroes back to
   `Idle` once their timer elapses and saves that transition — reusing the
   same elapsed-time-based pattern as Expedition reveal (no new polling
   architecture needed).
8. Extend Milestone 4's reveal pipeline to handle item IDs from both Loot
   results and `EventOutcomeResource.result`. Roll/store Loot item resource IDs
   from the new item pool; for every newly revealed Loot or Event result,
   resolve its `item_ids` through the item registry and add those
   `ItemResource` references to `GameState.inventory`. Keep the existing,
   tested gold application in the same handler; Milestone 6 does not introduce
   a second reward handler.

## Expected files / scenes / scripts / data

```
data/items/short_sword.tres
data/items/hunting_bow.tres
data/items/apprentice_staff.tres
data/items/leather_armor.tres
data/items/chainmail.tres
data/items/robes.tres
scripts/systems/leveling.gd
scenes/ui/equipment/equipment_screen.tscn
tests/test_leveling.gd
tests/test_equipment_stats.gd
tests/test_recovery_flow.gd
```

## Interfaces / data contracts

```gdscript
# ItemResource (Resource; extends the exact Milestone 1 schema)
@export var item_id: StringName
@export var display_name: String
@export_enum("Weapon", "Armor") var slot: String
@export var rarity: StringName
@export var stat_modifiers: Dictionary   # e.g. { "Attack": 5, "Defense": 2 }

# HeroData additions
var equipped_weapon: ItemResource   # or null
var equipped_armor: ItemResource    # or null
var recovery_ready_at: int    # unix time, UTC; active while status == RESTING

# Leveling
static func grant_xp(hero: HeroData, amount: int, balancing: BalancingConfig = null) -> bool
    # Adds to cumulative lifetime XP, processes every crossed threshold,
    # and recomputes derived stats after all resulting level-ups.
```

## Testing requirements

- Unit test: `grant_xp` uses ceiling-rounded cumulative thresholds, processes
  every threshold crossed by one award, and changes derived stats per the
  class's growth curve.
- Unit test: equipping/unequipping an item changes
  `compute_derived_stats` output by exactly the item's `stat_modifiers`.
- Unit test: a save/load round trip preserves every inventory item and each
  Hero's equipped weapon and armor by resource ID.
- Unit test: finalization converts a `Wounded` result to `Resting`, assigns
  and persists `recovery_ready_at` in the same mutation, and the Hero
  transitions back to `Idle` only after that timestamp has elapsed (test with
  a simulated "now" before and after the timestamp).
- Unit test: Loot and Event `item_ids` both use the same reveal handler; each
  item reward and the reveal cursor persist in one save mutation, and
  reloading cannot grant an item or its accompanying gold twice.
- Manual test: complete an Expedition, verify XP/level/gold/items are
  applied correctly and are visible in Hero Detail/Equipment/Roster
  screens, including regression-checking Milestone 4's gold path.

## Acceptance criteria

- [x] Heroes gain XP and level up from completed Expeditions with
      correctly recomputed stats.
- [x] Starter item pool exists and can be equipped/unequipped via the
      Equipment screen with correct stat-delta preview.
- [x] Equipped items correctly modify combat-relevant derived stats (
      verifiable via `CombatSimulator` picking up the change).
- [x] Wounded Heroes automatically recover to `Idle` after their rest
      duration elapses, including across app restarts.
- [x] Loot and Event item rewards extend the existing reveal path and
      correctly update `GameState.inventory` without duplicating gold or
      item grants.
- [ ] Physical Android acceptance: complete an Expedition, inspect XP/gold/items,
      preview/confirm/cancel equipment using touch and Android Back, and verify
      Resting recovery after backgrounding and a full restart. Automated UI and
      clock tests do not substitute for this check.

## Risks

- **Equipment stat inflation outpacing enemy scaling:** since this
  milestone doesn't yet add new Regions, defer full tuning to Milestone 7,
  but sanity-check that equipped Heroes visibly out-perform unequipped
  ones in a manual Combat test.
- **Recovery timer interacting badly with Expedition timers** if both use
  ad-hoc polling. Mitigation: Task 7 explicitly reuses the existing
  elapsed-time-based reveal pattern rather than inventing a second timer
  mechanism.

## Next-milestone handoff

Milestone 7 (Content expansion) adds more Regions/traits/events and runs
balance simulations that depend on equipment and leveling being fully
functional, since Party Power and combat outcomes are affected by both.

→ Next: [07-content-expansion.md](07-content-expansion.md)
