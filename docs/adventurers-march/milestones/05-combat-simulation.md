# Milestone 5 — Combat Simulation

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Implement the deterministic auto-combat simulator and wire Combat
encounters into the Expedition pipeline built in Milestone 4, completing
the [first playable vertical slice](../../adventurers-march-implementation-plan.md#22-first-playable-vertical-slice-and-build-order).

## Scope

**In scope:** `CombatSimulator` (turn order, hit/crit/damage/heal
formulas, round loop, outcome determination), enemy-group data, one active
skill per class, Combat step integration into `ExpeditionGenerator`,
combat log rendering in Expedition Report.

**Out of scope:** equipment stat contributions (Milestone 6 — the
simulator should read whatever derived stats it's given, so no rework is
needed when equipment starts modifying them), additional Regions
(Milestone 7).

## Prerequisites / dependencies

- Milestone 4 (First expedition): `ExpeditionData`/`ExpeditionStep`
  (including the reserved `COMBAT` kind) and `ExpeditionGenerator` must
  exist.

## Tasks

1. Implement `scripts/models/enemy_group_resource.gd`
   (`class_name EnemyGroupResource`): list of enemy stat blocks
   using the same combat-relevant derived-stat keys as Heroes. Enemy authoring
   may use a simplified "class"-like definition, but it must produce derived
   stats before simulation; enemies do not need the full Hero trait/generation
   system.
2. Author 1–2 `.tres` enemy groups under `data/encounters/` for Green
   Hollow (e.g., "Bandit Skirmishers", "Forest Wolves").
3. Implement one active skill per MVP class as simple data + resolution
   logic (Knight: Guard, Ranger: Aimed Shot or similar, Wizard: Firebolt,
   Cleric: Mend), per
   [plan §9](../../adventurers-march-implementation-plan.md#9-auto-combat-simulation-design).
   A simple `SkillResource` (name, target rule, multiplier ID, cooldown) is
   sufficient; resolve the multiplier ID through
   `BalancingConfig.skill_damage_multipliers`. AI policy: use skill if off
   cooldown, else basic attack.
4. Implement `CombatSimulator` (fill in the `autoload/CombatSimulator.gd`
   stub from Milestone 1) as **pure/stateless**: given a Party snapshot, the
   current per-Hero HP/status map, an `EnemyGroupResource`, and a seed, return
   a JSON-safe result dictionary: outcome
   (`VICTORY`/`DEFEAT`/`RETREAT`), round-by-round log, and final HP/status for
   every Party Hero keyed by the stable ID introduced in Milestone 2.
   - Turn order: sort by Initiative each round, seeded RNG tiebreak.
   - Targeting: front-row-first for melee/short-range; any slot for
     ranged/magic; lowest-HP%-among-valid-targets tiebreak.
   - Hit/crit/damage/heal formulas use only derived stats and are exactly as
     specified in plan §9; in particular, defender `Evasion` reduces hit
     chance.
   - Bounded by `MaxRounds` (data-tunable via `BalancingConfig`).
5. Update `ExpeditionGenerator` to include `COMBAT` steps in Green
   Hollow's encounter pool, calling `CombatSimulator` at step-generation
   time (still resolve-at-start, per Milestone 4's architecture) and
   storing the full result in the step's `result` dictionary.
   Resolve steps in order; on `DEFEAT`, or on `RETREAT` when Green Hollow's
   rules mark it terminal, set `terminal_step_index`, truncate later steps,
   and set `effective_end_timestamp` to
   `start_timestamp + (terminal_step_index + 1) *
   step_duration_seconds`. The persisted `step_duration_seconds` was computed
   from the full candidate list in Milestone 4 and must not change when
   `steps` is truncated. Reveal/finalization must never process later steps.
6. During generation, initialize one current-Hero-state map from the Party
   snapshot at `MaxHP`. Pass it to each Combat in step order, then overlay
   that Combat's complete `final_hero_states` by stable Hero ID before
   resolving the next step. There is no automatic heal between Combats; a
   Hero at 0 HP remains at 0 and cannot participate later. At Expedition
   finalization, fold the saved `final_hero_states` maps in step order with
   later entries replacing earlier entries for the same ID, then apply the
   merged map to the roster once. Any Hero at 0 HP becomes `Wounded`
   regardless of Party outcome. On `DEFEAT`, surviving Heroes also become
   `Wounded`; otherwise surviving Heroes return to `Idle` (the recovery timer
   can be a fixed placeholder duration for now; full Wounded/Resting recovery
   flow is fleshed out in Milestone 6).
7. Extend Expedition Report to render the combat log readably (round
   number, actor, action, target, result) — plain text/labels are
   sufficient for this milestone.

## Expected files / scenes / scripts / data

```
scripts/models/enemy_group_resource.gd
scripts/models/skill_resource.gd
data/encounters/bandit_skirmishers.tres
data/encounters/forest_wolves.tres
data/skills/guard.tres
data/skills/aimed_shot.tres
data/skills/firebolt.tres
data/skills/mend.tres
autoload/CombatSimulator.gd (filled in)
tests/test_combat_simulator.gd
```

## Interfaces / data contracts

```gdscript
# CombatSimulator (autoload, stateless functions)
func resolve_combat(party: PartyData, current_hero_states: Dictionary,
        enemy_group: EnemyGroupResource, seed: int,
        balancing: BalancingConfig) -> Dictionary
# {
#   "outcome": "victory" | "defeat" | "retreat",
#   "rounds": [{ "round_number": int, "actions": [{
#       "actor_name": String, "action_name": String, "target_name": String,
#       "damage_or_heal": int, "was_crit": bool
#   }]}],
#   "final_hero_states": { hero_id: { "hp": int, "status": int } }
# }
```

`ExpeditionStep.result` remains a `Dictionary` for every kind. A `COMBAT`
result uses the nested plain-data shape above, with no `RefCounted` objects
or object keys, so the active Expedition can be written directly to JSON.
Both `current_hero_states` and `final_hero_states` use Hero ID strings as
keys and contain every Party Hero; `resolve_combat` must not mutate its input
map.

## Testing requirements

- Unit test: `resolve_combat` with a fixed seed, Party/current-Hero-state map,
  and enemy group produces an **exact** expected result dictionary (outcome,
  full log, and `final_hero_states`), asserting the determinism guarantee from
  [plan §9](../../adventurers-march-implementation-plan.md#9-auto-combat-simulation-design).
- Unit test: turn order respects Initiative with seeded tiebreaks
  (same inputs → same order across runs).
- Unit test: hand-computed hit/crit/physical-damage/magic-damage/heal cases
  use the §9 derived stats; increasing defender `Evasion` lowers hit chance
  without changing raw attributes. Include fractional multiplier cases and
  assert damage/healing is floored once to the logged integer before HP is
  changed.
- Unit test: front-row targeting rule is enforced (melee/short-range
  attacks never target back row while front row has a living member).
- Unit test: `MaxRounds` bound is respected (simulation always
  terminates).
- Unit test: Defeat and Region-terminal Retreat truncate later steps without
  changing `step_duration_seconds`, set the exact terminal index/end
  timestamp from that stored slice, and reveal no later rewards.
- Unit test: in an Expedition with two Combats, the second starts from the
  first Combat's final HP; folding the two `final_hero_states` maps by ID
  produces the roster state applied at finalization.
- Unit test: a Hero at 0 final HP becomes `Wounded` after a Victory or Retreat,
  while surviving Heroes return to `Idle`.
- Manual test: complete an Expedition in Green Hollow that includes a
  Combat step and verify the Expedition Report shows a correct, readable
  log matching the actual resolved outcome.

## Acceptance criteria

- [ ] `CombatSimulator.resolve_combat` is deterministic and covered by a
      passing exact-output unit test.
- [ ] Front-row-first targeting and Initiative-based turn order are
      correctly implemented and tested.
- [ ] Combat formulas consume the documented derived stats, including an
      effective defender `Evasion`, and are covered by hand-computed tests.
- [ ] Green Hollow includes at least one Combat encounter using at least
      one enemy group.
- [ ] HP carries across multiple Combats, and ordered
      `final_hero_states` merging correctly affects Hero status
      (Idle vs. Wounded) at Expedition finalization.
- [ ] Terminal combat outcomes end reveal/finalization at the Combat step
      using the unchanged pre-truncation step duration and cannot grant
      rewards from later generated steps.
- [ ] Expedition Report renders a readable combat log.

## Risks

- **Formula tuning producing degenerate outcomes** (always-win or
  always-lose) at this stage is acceptable — full balancing happens in
  Milestone 7 — but a sanity check (a starting-roster Party should not
  always lose to the easiest enemy group) should be done manually before
  moving on.
- **`CombatSimulator` accidentally depending on Node/scene-tree state**
  would break the "pure/stateless, unit-testable without a running scene"
  guarantee from plan §13. Mitigation: keep it operating only on plain
  data models (`PartyData`, `EnemyGroupResource`, primitives).

## Next-milestone handoff

Milestone 6 (Progression and equipment) will make equipment modify the
derived stats `CombatSimulator` already reads, and will implement the full
Wounded/Resting recovery flow this milestone only stubs.

→ Next: [06-progression-and-equipment.md](06-progression-and-equipment.md)
