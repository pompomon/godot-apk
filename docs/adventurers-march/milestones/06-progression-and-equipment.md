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
  results must already flow into Expedition finalization. Its minimal
  persisted Wounded → Idle timer prevents roster exhaustion before this
  milestone; extend that existing recovery path rather than add a second one.
- Milestone 4 (First expedition) already owns and tests applying Loot gold
  at reveal time; this milestone extends that path rather than replacing it.

## Tasks

Before enabling progression, configure `xp_award_coefficients` and
`xp_threshold_curve` in the existing `data/balancing/default_balancing.tres`.
These are intentionally unconfigured foundation fields; retain or tune
the `base_recovery_seconds` already used by Milestone 5's minimal recovery.
Validate required keys, finite nonnegative XP coefficients,
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
7. Extend Milestone 5's persisted timer into the full Wounded/Resting recovery
   flow, migrating existing Wounded deadlines without resetting them: when Expedition
   finalization applies a `Wounded` result to the roster, immediately
   transition that Hero to `Resting`, assign
   `resting_until_timestamp = now_utc + recovery_duration` (data-tunable,
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
var resting_until_timestamp: int    # unix time, UTC; valid only while status == RESTING

# Leveling
static func grant_xp(hero: HeroData, amount: int) -> void
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
  and persists `resting_until_timestamp` in the same mutation, and the Hero
  transitions back to `Idle` only after that timestamp has elapsed (test with
  a simulated "now" before and after the timestamp).
- Unit test: Loot and Event `item_ids` both use the same reveal handler; each
  item reward and the reveal cursor persist in one save mutation, and
  reloading cannot grant an item or its accompanying gold twice.
- Manual test: complete an Expedition, verify XP/level/gold/items are
  applied correctly and are visible in Hero Detail/Equipment/Roster
  screens, including regression-checking Milestone 4's gold path.

## Acceptance criteria

- [ ] Heroes gain XP and level up from completed Expeditions with
      correctly recomputed stats.
- [ ] Starter item pool exists and can be equipped/unequipped via the
      Equipment screen with correct stat-delta preview.
- [ ] Equipped items correctly modify combat-relevant derived stats (
      verifiable via `CombatSimulator` picking up the change).
- [ ] Wounded Heroes automatically recover to `Idle` after their rest
      duration elapses, including across app restarts.
- [ ] Loot and Event item rewards extend the existing reveal path and
      correctly update `GameState.inventory` without duplicating gold or
      item grants.

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
