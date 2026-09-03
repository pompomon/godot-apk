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
recovery flow, loot/gold reward wiring.

**Out of scope:** crafting/enchanting (explicit non-goal), additional
Regions/content variety (Milestone 7).

## Prerequisites / dependencies

- Milestone 5 (Combat simulation): Combat outcomes and Hero HP/status
  results must already flow into Expedition finalization.

## Tasks

1. Implement XP gain: each completed Expedition step (or the Expedition as
   a whole — pick whichever the Milestone 4 `ExpeditionGenerator` already
   computes per-step rewards for, and keep it consistent) grants XP to
   each participating Hero, proportional to Region difficulty and
   Expedition duration per
   [plan §10](../../adventurers-march-implementation-plan.md#10-events-regions-equipment-progression).
2. Implement leveling: when a Hero's XP crosses their level's threshold,
   increment level and reapply the class's growth curve to recompute
   derived stats (via the `compute_derived_stats` function from
   Milestone 2).
3. Fill in `ItemResource` fields (slot: `Weapon`/`Armor`, rarity tier, flat
   stat modifiers) and author a small starter item pool under
   `data/items/` (e.g., 2–3 weapons, 2–3 armor pieces, spanning Common/
   Uncommon rarity).
4. Implement inventory storage on `GameState` (`Array[ItemData]` — actual
   item instances, referencing an `ItemResource` template plus any
   per-instance state if needed, though MVP items can be stateless
   references to their resource).
5. Extend `HeroData`/`compute_derived_stats` to apply equipped item stat
   modifiers on top of base/leveled stats.
6. Build Equipment screen: per-Hero weapon/armor slot assignment from
   available inventory, showing before/after stat deltas prior to
   confirming.
7. Implement the full Wounded/Resting recovery flow: a `Wounded` Hero
   enters `Resting` with a recovery-duration timer (data-tunable, e.g., via
   `BalancingConfig`), and `ExpeditionManager.reveal_progress` (or a
   similarly-invoked periodic check) transitions `Resting` Heroes back to
   `Idle` once their timer elapses — reusing the same elapsed-time-based
   pattern as Expedition reveal (no new polling architecture needed).
8. Wire Loot-step gold/item rewards (already rolled by
   `ExpeditionGenerator` since Milestone 4) into `GameState.gold` and
   `GameState.inventory` at reveal time.

## Expected files / scenes / scripts / data

```
data/items/short_sword.tres
data/items/hunting_bow.tres
data/items/apprentice_staff.tres
data/items/leather_armor.tres
data/items/chainmail.tres
data/items/robes.tres
scripts/models/item_data.gd
scripts/systems/leveling.gd
scenes/ui/equipment/equipment_screen.tscn
tests/test_leveling.gd
tests/test_equipment_stats.gd
tests/test_recovery_flow.gd
```

## Interfaces / data contracts

```gdscript
# ItemResource (Resource)
enum ItemSlot { WEAPON, ARMOR }
var item_name: String
var slot: ItemSlot
var rarity: StringName
var stat_modifiers: Dictionary   # e.g. { "Attack": 5, "Defense": 2 }

# HeroData additions
var equipped_weapon: ItemResource   # or null
var equipped_armor: ItemResource    # or null
var resting_until_timestamp: int    # unix time, UTC; valid only while status == RESTING

# Leveling
static func grant_xp(hero: HeroData, amount: int) -> void
    # mutates hero.xp/level in place, recomputing derived stats on level-up
```

## Testing requirements

- Unit test: `grant_xp` crossing a level threshold increments level and
  changes derived stats per the class's growth curve.
- Unit test: equipping/unequipping an item changes
  `compute_derived_stats` output by exactly the item's `stat_modifiers`.
- Unit test: a `Wounded`→`Resting` Hero transitions back to `Idle` only
  after `resting_until_timestamp` has elapsed (test with a simulated
  "now" before and after the timestamp).
- Manual test: complete an Expedition, verify XP/level/gold/items are
  applied correctly and are visible in Hero Detail/Equipment/Roster
  screens.

## Acceptance criteria

- [ ] Heroes gain XP and level up from completed Expeditions with
      correctly recomputed stats.
- [ ] Starter item pool exists and can be equipped/unequipped via the
      Equipment screen with correct stat-delta preview.
- [ ] Equipped items correctly modify combat-relevant derived stats (
      verifiable via `CombatSimulator` picking up the change).
- [ ] Wounded Heroes automatically recover to `Idle` after their rest
      duration elapses, including across app restarts.
- [ ] Expedition loot correctly updates `GameState.gold`/`inventory`.

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
