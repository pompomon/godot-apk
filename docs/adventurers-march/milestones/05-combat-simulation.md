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
needed when equipment starts modifying them), XP/progression and the full
Wounded/Resting recovery system (Milestone 6), and additional Regions
(Milestone 7). Limit recovery work here to the agreed placeholder/handoff
described below; do not expand it into the next milestone.

## Prerequisites / dependencies

- Milestone 4 (First expedition): `ExpeditionData`/`ExpeditionStep`
  (including the reserved `COMBAT` kind) and `ExpeditionGenerator` must
  exist.
- Milestone 4's `ExpeditionPartySnapshot` provides detached formation members,
  stable Hero IDs, derived stats, and authored targeting rules. Consume those
  frozen values, not live roster Heroes or recomputed class statistics.

## Bounded delivery and integration gates

Follow the [shared agent guidelines](../../../AGENTS.md). Deliver the slices
below as independently validated tasks or PRs, in dependency order; the
numbered tasks later in this document describe the complete milestone, not
one mandatory all-in-one session. Each slice must preserve usable existing
gameplay. Do not activate Combat in production content before persistence,
orchestration, and presentation are ready.

On resumption, inspect the last published checkpoint and remaining diff before
choosing a slice. Do not assume an earlier session's unpushed work exists.
Record evidence in this milestone and the task/PR handoff rather than creating
another instruction file.

### Slice 1 — Contracts and decisions

**Depends on:** the existing First Expedition interfaces and baseline evidence.

Resolve and record the following decisions before dependent code or parallel
work begins. The interface and formulas below remain normative; unresolved
details are not permission to replace them with worker-specific assumptions.

- [x] **Frozen input and state:** reconcile the stale `PartyData` reference in
      the Combat autoload stub with the `ExpeditionPartySnapshot` signature.
      The existing `hero_states()` helper supplies HP only; specify where the
      complete per-Hero HP/status map is constructed and what its statuses
      mean. Define which skill values must be detached at dispatch and retained
      for historical results, without consulting live roster state on reload.
- [x] **Skill semantics:** agree Guard activation/expiry, cooldown decrement
      timing, skill availability when no valid target exists, and whether
      cooldown/effect state resets between Combats. Keep multipliers and any
      new global coefficients in the existing balancing asset.
- [x] **Result and errors:** settle compatibility between Combat's documented
      result dictionary and generic consumers currently reading `result.gold`.
      Specify required keys, numeric encodings, invalid-input signaling, and
      nonmutation guarantees. An empty dictionary is not a combat outcome;
      do not silently accept invalid data or weaken noncombat validation.
- [x] **Terminal metadata and presentation:** agree the frozen data needed to
      validate truncated runs and display progress without revealing future
      defeat/retreat. Keep step duration based on the full candidate list;
      neither loading nor UI may reconstruct historical rules from live content.
- [x] **Recovery boundary:** define the limited Wounded placeholder and
      Milestone 6 handoff. If mutable recovery fields are introduced, cover
      their persistence, initialization, migration, and rollback together.
- [x] **Compatibility and bounds:** decide whether a schema change requires a
      version bump, how valid legacy saves remain loadable, and how complete
      combat logs fit `SaveManager.MAX_SAVE_BYTES`. Cover bounded rounds,
      combatants, actions/text, finite numbers, and rejected oversized saves.
      Never silently truncate required logs or discard an existing save.

Map the contract across these existing owners before assigning file ownership:

| Boundary | Producers, validators, and consumers to account for |
|---|---|
| Content and simulation | Hero class/skill/enemy Resources, balancing, content catalogs, snapshot capture, and `CombatSimulator` |
| Saved results | `ExpeditionStep`, `ExpeditionData` construction/serialization/validation, `SaveManager` schema/migration/size checks |
| Orchestration | `ExpeditionGenerator`, `ExpeditionManager` dispatch/reveal/finalization, `GameState` checkpoints and Hero fields |
| Presentation | Home progress, Expedition Report, roster/detail status, and Party availability |
| Regression fixtures | Combat tests plus existing generator, manager, persistence, formation, and UI suites |

**Gate:** agreed decisions and affected consumers/tests are documented; each
shared integration file has one writer. Use the agreed contract for every
worker handoff. This documentation-only slice does not claim working combat.

### Slice 2 — Pure combat and authored models

**Depends on:** Slice 1.

Implement detached simulation, enemy/skill models and authored assets, and
required balancing validation. Add exact-output determinism, input
nonmutation, targeting, formula/rounding, skill-policy, and round-bound tests
from the testing requirements below. Wire complete input maps at the agreed
boundary; do not depend on scene-tree or live singleton state.

**Gate:** focused combat tests and the existing regression suite pass under
the documented validation sequence. Keep the live Green Hollow encounter
pool noncombat; authoring an enemy asset does not activate it.

### Implementation decisions (2026-09-06)

These decisions refine the normative interface below. Implementation proceeds
through the numbered slices, not by enabling encounters before their consumers
are ready.

- **Inputs:** the autoload delegates to a pure `CombatEngine`. It accepts an
  `ExpeditionPartySnapshot`, complete current Hero states, an
  `EnemyGroupResource`, a seed, and `BalancingConfig`. No inputs are mutated.
  `hero_states()` supplies `{hp, status}` for every stable Hero ID: positive HP
  starts `IDLE` (0), zero HP is `WOUNDED` (4). These are simulation/finalization
  statuses, not changes to the live roster's `ON_EXPEDITION` status.
- **Skills:** each class references one `SkillResource` with `skill_id`,
  `display_name`, `effect` (`Physical`, `Magic`, `Heal`, `Guard`), `target_rule`
  (`FrontRowFirst`, `AnySlot`, `LowestHPAlly`, `Self`), and `cooldown_turns`.
  Combat snapshots detach this definition into `active_skill`; legacy
  noncombat snapshots need no skill. Multipliers come from the supplied
  balancing asset during dispatch; saved logs never consult that asset again.
- **Skill timing:** skills start ready and reset between encounters. A skill
  sets its cooldown to the authored number of intervening actor turns; each
  subsequent turn with positive cooldown decrements it and uses a basic
  attack. Mend selects living injured allies only, including self; if none
  exists, use a basic attack without consuming the skill cooldown. Guard
  affects incoming damage immediately until the beginning of the guarding
  actor's next turn. Its multiplier is applied after mitigation/crit and before
  the single final floor. Guard cannot reduce successful damage below one.
  Basic attacks are physical; Firebolt uses MagicPower.
- **Ordering:** canonical stable-ID order precedes RNG tiebreak assignment
  each round; descending Initiative, seeded tiebreak, then stable ID determine
  action order. Target ties use HP percentage then stable ID. Enemies have
  unique authored IDs, explicit rows/rules, and no active skills in this slice.
- **Results:** success has exactly `gold` (zero for Combat), `outcome`, `rounds`,
  `final_hero_states`, and `enemy_states`. Final Hero states cover every input
  Hero, with zero-HP Heroes Wounded, all Heroes Wounded on Defeat, and other
  survivors Idle. Frozen `enemy_states` maps each enemy ID to
  `{name, max_hp, hp, row}` for validation and historical presentation.
  Each action retains the documented name/amount/crit fields and adds
  `actor_id`, `target_id`, `effect`, and `hit`. Misses log zero; Heal/Guard
  always hit and never crit. Amounts are the calculated integers before HP
  clamping, not the clamped difference. Invalid inputs return only an `error`
  string; callers abort dispatch, never treat that dictionary as an outcome.
- **Numbers and bounds:** HP, statuses, rounds, cooldowns, and logged amounts
  are bounded JSON-safe integers; finite probabilities/multipliers are
  validated before use. Keep the existing eight-byte hexadecimal encoding of
  snapshot Evasion/CritChance. Limit enemies to four, rounds to at most 100
  (authored default 20), and actions to at most eight per round. Bound strings
  and nested collections; check complete serialized saves against the existing
  1 MiB limit. Stress the authored five-encounter/20-round case before activation.
  Reject oversized dispatch without altering the previous save; never remove
  log entries to make a save fit.
- **Persistence:** new saves use version 4. Validate supported original schemas
  before migration; preserve historical noncombat results and exact snapshot
  doubles. Freeze `planned_step_count` and `retreat_ends_expedition` in new
  Expedition records; legacy noncombat runs migrate with their full saved step
  count and nonterminal Retreat. Do not consult today's Region rules on load.
- **Terminal behavior:** selection still completes before any resolution.
  A Combat seed is drawn from that same Expedition RNG during ordered
  resolution. Defeat always terminates; Retreat terminates only under the
  frozen Region rule. Retain the original slice duration and calculate the
  effective end from the terminal index. Running UI uses the planned count
  and duration, concealing early termination until it is revealed.
- **Recovery boundary:** add only a fixed UTC recovery deadline
  `recovery_ready_at` to Hero persistence/checkpoints, zero when inactive.
  Newly Wounded Heroes recover after `base_recovery_seconds` (60 initially)
  from the observation that commits finalization. Recovery is observed and
  saved transactionally through ExpeditionManager's existing lifecycle path,
  including when no Expedition is running. Legacy Heroes migrate with zero;
  pre-existing reserved Wounded states with no deadline are not reinterpreted.
  No Resting phase, XP, equipment, injuries, or recovery modifiers are added.
  Milestone 6 replaces this deliberately limited placeholder.

**Ownership:** one combat writer owns simulation, enemy/skill Resources and
assets, class skill references, snapshot capture, balancing, and focused combat
tests. The integration owner owns saved Expedition validation, SaveManager,
Hero recovery/checkpoints, generation, orchestration, UI, and their regression
tests. One validation owner runs each integrated revision's existing gates.

### Slice 3 — Persistence compatibility

**Depends on:** Slices 1–2.

Support the agreed frozen combat payload in constructors, serializers, and
strict validators; adapt all generic result readers consistently. Implement
applicable migrations and checkpoint coverage for new mutable fields.
Test exact round trips, malformed data, save-size boundaries, old noncombat
saves, and pre-commit rollback versus post-commit warnings. Loading a saved
Expedition must not rerun combat or recompute it from retuned content.

**Gate:** valid supported legacy saves and new combat snapshots survive
save/load, and failed writes preserve prior state. Keep live Combat disabled
until the remaining integration slices are complete.

### Slice 4 — Expedition integration

**Depends on:** Slices 2–3.

Connect combat resolution to two-pass generation using controlled encounter
fixtures. Carry complete Hero state between Combats, apply terminal truncation
with the original step duration, merge final states in order, and commit final
statuses with rewards/cursor/clock state. Cover Defeat, terminal and nonterminal
Retreat, zero-HP Heroes, multiple Combats, reload, and save retries.

**Gate:** integration tests prove no later rewards after termination, no
implicit healing, and exactly-once finalization/rewards, including offline
observations. Existing noncombat behavior still passes; production activation
remains deferred.

### Slice 5 — Presentation and activation

**Depends on:** Slices 2–4.

Render only revealed combat logs and committed statuses. Keep future terminal
outcomes hidden in progress displays. Activate authored Combat encounters in
Green Hollow only with the completed presentation and persistence pipeline.
Use controlled noncombat fixtures to retain earlier tests' intended coverage
instead of weakening exact selection, ten-step, or normal-completion assertions
indiscriminately. Add separate combat-aware UI and content expectations.

**Gate:** clean import, focused checks, full integrated GUT suite, and Android
debug export with a nonempty artifact are evidenced by the validation owner.
Record the manual readable-report and device/lifecycle checks separately;
unperformed or approval-blocked checks remain pending.

### Delivery evidence and guideline pilot

Baseline at `3ad8613` (2026-09-06): clean Godot 4.7.2 import exited 0;
the existing GUT suite passed **182 tests / 17,267 assertions** with both hooks
enabled; Android debug export exited 0 and produced a nonempty **28,409,368-byte**
APK. These are local checks, not CI or device acceptance. Contract decisions
were published separately at `8c7b823`; the gameplay pilot remains pending until
the pure-combat slice has its own validated, published checkpoint.

**Slice 2 validation (2026-09-06, changes based on `8c7b823`):** the combat
writer explicitly stopped before validation/publication. Clean import exited 0;
focused Combat tests passed **36 tests / 1,395 assertions**, Resource tests
passed **5 tests / 107 assertions**, and the full suite passed **219 tests /
18,718 assertions**, all exiting 0 with both GUT hooks enabled. Android debug
export exited 0 and produced a **28,435,984-byte** APK with build-tools 36.1.0
available. Commands are the README sequence, with
`-gselect=test_combat_simulator.gd` and `-gselect=test_resources.gd` for focused
runs. An earlier iteration exposed strict JSON float/integer comparison
assumptions and an externally shared skill Resource in test fixtures; both were
fixed without relaxing the exact expected combat result or production behavior.
Read-only review reported no significant issues. This is the bounded gameplay
pilot checkpoint; it does not claim complete combat integration or device
acceptance. Next bounded action: Slice 3 persistence compatibility.

**Publication confirmed:** Slice 2 was committed and pushed as `b13600d`, with
the writer stopped and validation complete before publication. This completes
the bounded gameplay guideline pilot without timeout recovery.
The [Android workflow for that checkpoint](https://github.com/pompomon/godot-apk/actions/runs/34063450150)
is `action_required`, with zero jobs reported by the logs endpoint; CI approval
is pending, not a test failure or a passed CI run. No physical-device checks
were performed.

**Slice 3 validation (2026-09-06, changes based on `b13600d`):** both writers
explicitly stopped before the integrated checks. Godot 4.7.2 clean import
exited 0. Focused tests passed: Combat **37 / 1,412 assertions**, Combat
persistence **12 / 390**, Expedition persistence **11 / 343**, and SaveManager
**22 / 330**. The full GUT suite passed **236 tests / 19,226 assertions** across
20 scripts, exit 0, with both standard hooks enabled. Android debug export
exited 0 and produced a nonempty **28,444,351-byte** APK. The existing README
commands were used, with `-gselect=<test filename>` for focused runs.

Coverage includes exact combat round trips; v1/v2/v3 original-schema validation
and migration; frozen terminal clocks; ordered HP-log validation; malformed
payloads; five complete 20-round/eight-combatant encounters below 1 MiB; exact
save-size boundary acceptance and oversized-write preservation; and recovery
deadline checkpoint rollback across every save fault boundary. New tests exposed
an integral-JSON-float enum-membership bug; both result validation and the pure
engine now validate integrality before converting statuses to integers. Parser
issues in new test fixtures were also resolved. No existing baseline failure
was hidden or unrelated assertion relaxed. Read-only review found no significant
issues; these results are local validation, not CI or device acceptance.

### Remaining implementation handoff

This session deliberately stops after Slice 3 to preserve a verified checkpoint.
**Milestone 5 is not complete, and production Green Hollow remains noncombat.**
No Slice 4/5 production or UI files were edited.

1. **Next bounded action — Slice 4:** extend `ExpeditionCatalog` to validate
   Combat entries and terminal Retreat; call `CombatEngine.resolve_combat`
   from the generator's second pass using a seed drawn from the same RNG.
   Capture optional skills only for Combat runs, carry HP/status maps between
   encounters, and freeze the planned count and Region terminal rule explicitly.
2. Wire terminal truncation and effective-duration clock caps through
   `ExpeditionManager`. Its current finalization still returns everyone Idle;
   replace that with the ordered `ExpeditionData.final_hero_states()` result.
   Commit Wounded statuses and `recovery_ready_at` with rewards/cursor/clock,
   and observe the limited recovery deadline even without a running Expedition.
   `GameState` already checkpoints these deadlines while preserving Hero identity.
3. Validate that slice with controlled encounters, offline/retry/fault cases,
   the full existing GUT suite, and Android export **before** enabling Combat.
4. **Then Slice 5:** Home/Report should use `display_step_count()` and
   `seconds_remaining()` to hide future terminal outcomes. Render only revealed
   logs, refresh committed recovery/Party availability, and add combat-aware UI
   tests. Preserve old noncombat regression coverage with isolated fixtures.
   Only then activate the authored enemy groups in Green Hollow.
5. Keep exported-device readability/lifecycle acceptance and workflow approval
   separate and pending until actually performed.

For each delivered slice, record its published revision/task or PR, scope,
agreed decisions, validation commands and actual results, blockers, and next
bounded action. Verify publication and obtain stopped-writer acknowledgments
before declaring a handoff complete. Reuse that evidence on resumption instead
of repeating an identical review/validation cycle.

The first bounded gameplay implementation slice using these guidelines is the
pilot: record its actual validation and whether it finished with a verified
checkpoint or an explicit incomplete handoff without relying on timeout recovery.
Keep the pilot pending through documentation-only deliveries, including Slice 1.
This remains a follow-up validation of the workflow, not evidence supplied by
adding these guidelines. Keep the milestone's overall acceptance pending until
all required behavior and checks are complete; slice completion alone does not
close the milestone.

## Tasks

1. Implement `scripts/models/enemy_group_resource.gd`
   (`class_name EnemyGroupResource`): list of enemy stat blocks
   using the same combat-relevant derived-stat keys as Heroes and a unique,
   stable authored combatant ID for each enemy, an authored formation row
   (`Front`/`Back`), and `basic_attack_target_rule` (`FrontRowFirst`/`AnySlot`,
   matching `HeroClassResource`). Enemy authoring may use a
   simplified "class"-like definition, but it must produce derived stats
   before simulation; enemies do not need the full Hero trait/generation
   system. Author the same target-rule field on all four Hero class resources:
   Knight uses `FrontRowFirst`; Ranger, Wizard, and Cleric use `AnySlot`.
   Use the class field already frozen in each Hero's Expedition snapshot; enemy
   snapshots copy their stat block's field. Never infer it from combatant IDs.
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
   - Targeting: basic attacks read `basic_attack_target_rule` from the acting
     combatant's snapshot. `FrontRowFirst` (melee/short-range) restricts targets
     to living front-row opponents, falling back to living back-row opponents
     only if none remain in front; `AnySlot` (ranged/magic) allows living
     opponents in either row. Skills use their own authored target rule.
     Choose lowest HP percentage among valid targets, then ascending stable
     combatant ID (Hero ID or authored enemy ID) when percentages tie.
   - Hit/crit/damage/heal formulas use only derived stats and are exactly as
     specified in plan §9; in particular, defender `Evasion` reduces hit
     chance.
   - Bounded by `MaxRounds` (data-tunable via `BalancingConfig`).
   - Extend the existing balancing asset with authored skill multipliers;
     retain its 20-round default and published hit/crit/damage defaults.
     Validate positive round bounds, ordered probability limits, and finite
     nonnegative multipliers for every used skill before simulation. Missing
     skill configuration is an error, not an implicit zero-damage skill.
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
func resolve_combat(party: ExpeditionPartySnapshot, current_hero_states: Dictionary,
        enemy_group: EnemyGroupResource, seed: int,
        balancing: BalancingConfig) -> Dictionary
# {
#   "gold": 0,
#   "outcome": "VICTORY" | "DEFEAT" | "RETREAT",
#   "rounds": [{ "round_number": int, "actions": [{
#       "actor_name": String, "action_name": String, "target_name": String,
#       "actor_id": String, "target_id": String,
#       "effect": "Physical" | "Magic" | "Heal" | "Guard",
#       "damage_or_heal": int, "was_crit": bool, "hit": bool
#   }]}],
#   "final_hero_states": { hero_id: { "hp": int, "status": int } },
#   "enemy_states": { enemy_id: {
#       "name": String, "max_hp": int, "hp": int, "row": "Front" | "Back"
#   } }
# }
# Invalid input returns only { "error": String }; this is not an outcome.
```

`ExpeditionStep.result` remains a `Dictionary` for every kind. A `COMBAT`
result uses the nested plain-data shape above, with no `RefCounted` objects
or object keys, so the active Expedition can be written directly to JSON.
Both `current_hero_states` and `final_hero_states` use Hero ID strings as
keys and contain every Party Hero; `resolve_combat` must not mutate its input
map. A Combat step's `outcome_id` equals its saved `result.outcome`.
`CombatResult.valid(result, snapshot, current_hero_states)` validates complete
rounds and chronological HP provenance without rerolling outcomes or reading
current enemy statistics, skill assets, or balancing. JSON integer-valued floats
are validated before normalization; Boolean, string, fractional, and unsafe
integer encodings are rejected.

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
  attacks never target back row while front row has a living member), and
  equal-HP-percentage candidates select the ascending stable combatant ID.
- Unit test: for both Hero and enemy basic attacks, changing only the authored
  rule from `FrontRowFirst` to `AnySlot` allows a lower-HP-percentage back-row
  opponent to be selected despite a living front row. `FrontRowFirst` falls
  back to the back row once all front-row opponents are at 0 HP. Snapshot
  creation preserves the authored rule regardless of class/enemy ID.
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

- [x] `CombatSimulator.resolve_combat` is deterministic and covered by a
      passing exact-output unit test.
- [x] Front-row-first targeting and Initiative-based turn order are
      correctly implemented and tested.
- [x] Combat formulas consume the documented derived stats, including an
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
  detached inputs (`ExpeditionPartySnapshot`, current-Hero-state map,
  `EnemyGroupResource`, balancing, and primitives).

## Next-milestone handoff

Milestone 6 (Progression and equipment) will make equipment modify the
derived stats `CombatSimulator` already reads, and will implement the full
Wounded/Resting recovery flow this milestone only stubs.

→ Next: [06-progression-and-equipment.md](06-progression-and-equipment.md)
