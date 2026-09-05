# Milestone 4 — First Expedition

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Implement the Expedition pipeline end-to-end for a single Region using
non-combat steps only (Travel/Loot/Event), proving the "resolve fully at
start, reveal over elapsed time" architecture — the core idle mechanic of
the game — before combat is added.

## Scope

**In scope:** `RegionResource` content for "Green Hollow" (non-combat
steps only), `ExpeditionData` model, seeded step generation, `Expedition
Manager.start_expedition`/`reveal_progress`, Region Select and Expedition
Report screens, Home screen status display, offline/idle progress
verification.

**Out of scope:** Combat encounters (Milestone 5 wires them into the same
pipeline built here) — Green Hollow's encounter pool for this milestone
should contain only Loot and Event-card entries.

## Prerequisites / dependencies

- Milestone 3 (Party formation): `GameState.current_party` must be
  populated via the Party Formation screen before an Expedition can start.

## Tasks

1. Fill in `RegionResource` fields (per
   [plan §10](../../adventurers-march-implementation-plan.md#10-events-regions-equipment-progression)):
   name, recommended Party Power, available durations, travel-step count,
   weighted encounter pool (Loot/Event entries only for this milestone),
   unlock condition.
2. Author `data/regions/green_hollow.tres` and a small
   `data/encounters/green_hollow_events.tres` event table (5–10 entries).
3. Implement `scripts/models/expedition_data.gd`
   (`class_name ExpeditionData`): Region reference, Party snapshot, seed,
   `start_timestamp`, duration, immutable `step_duration_seconds`,
   `steps: Array[ExpeditionStep]`, `last_revealed_index`,
   `terminal_step_index` (default `-1`), `effective_end_timestamp`,
   `last_observed_utc`, and `credited_elapsed_seconds`.
4. Implement `scripts/systems/expedition_generator.gd`: given a Region,
   Party, seed, and duration, produce the full `steps` array with each
   step's outcome **already resolved** (Loot gold amount rolled, Event
   outcome rolled) — per
   [plan §8](../../adventurers-march-implementation-plan.md#8-expeditions-travel-encounters-outcomes-deterministic-resolution).
   After generating the full candidate step list but before resolving any
   outcome that could later truncate it, compute
   `step_duration_seconds = duration_seconds / candidate_step_count`.
   Persist this positive integer and never recompute it from `steps.size()`.
   Initialize `effective_end_timestamp` to
   `start_timestamp + duration_seconds`; Milestone 5 may shorten it using
   the stored step duration.
   Combat steps can be represented now (e.g., a `COMBAT` step kind) but
   should not appear in Green Hollow's pool yet — leave the kind defined
   so Milestone 5 doesn't need a data-model change.
5. Implement `ExpeditionManager.start_expedition(region, party, duration)
   -> void`: snapshots the Party, generates steps via
   `ExpeditionGenerator`, sets `GameState`'s active Expedition, autosaves.
6. Implement `ExpeditionManager.reveal_progress() -> void`: computes
   elapsed time, advances `last_revealed_index`, applies newly revealed
   gold rewards to `GameState`, and marks the Expedition
   finalized when fully revealed (Heroes' status returns from
   `OnExpedition`/`Assigned` appropriately — see Hero status handling
   below). Save the rewards and updated cursor together immediately, before
   presenting the newly revealed results, so restarting cannot apply a
   reward batch twice.
7. Set each Party Hero's status to `OnExpedition` when
   `start_expedition` runs, and back to `Idle` when
   `reveal_progress` finalizes the Expedition (no Wounded/Defeat handling
   needed yet since there is no combat in this milestone's content).
8. Build Region Select screen: shows Green Hollow (locked-state UI not yet
   needed since it's the only Region), duration options, and a "Start
   Expedition" action that calls `ExpeditionManager.start_expedition` and
   returns to Home.
9. Build Expedition Report screen: renders the revealed `steps` as a
   scrollable travel journal (text is sufficient for this milestone;
   icons/formatting polish is a Milestone 8 concern).
10. Update Home screen to show current Expedition progress (e.g.,
    "Step 3 of 5") and call `ExpeditionManager.reveal_progress()` on
    `_ready()` and on app focus-in.
11. Manually verify offline progress: start an Expedition with a short
    duration, force-quit the app, wait past the duration, reopen, and
    confirm the Expedition Report shows complete, correct results.
12. Extend `SaveManager`'s JSON-safe serializers/deserializers for
    `PartyData`, `ExpeditionData`, and every `ExpeditionStep.result`
    dictionary, including immutable `step_duration_seconds`, the reveal
    cursor, terminal/end fields, and clock-accounting fields. Add an
    active-Expedition round-trip test, including the maximum allowed seed
    `2^53 - 1`.

## Expected files / scenes / scripts / data

```
data/regions/green_hollow.tres
data/encounters/green_hollow_events.tres
scripts/models/expedition_data.gd
scripts/models/expedition_step.gd
scripts/systems/expedition_generator.gd
scenes/ui/region_select/region_select_screen.tscn
scenes/ui/expedition_report/expedition_report_screen.tscn
tests/test_expedition_generator.gd
tests/test_expedition_manager.gd
```

## Interfaces / data contracts

```gdscript
# ExpeditionStep (RefCounted)
enum StepKind { TRAVEL, LOOT, EVENT, COMBAT }   # COMBAT defined, unused this milestone
var kind: StepKind
var result: Dictionary   # shape depends on kind, e.g. { "gold": 12 } for LOOT

# ExpeditionData (RefCounted)
var region: RegionResource
var party_snapshot: PartyData
var seed: int
var start_timestamp: int      # unix time, UTC
var duration_seconds: int
var step_duration_seconds: int # immutable; based on pre-truncation step count
var steps: Array             # Array[ExpeditionStep]
var last_revealed_index: int
var terminal_step_index: int # -1 when no generated step is terminal
var effective_end_timestamp: int
var last_observed_utc: int
var credited_elapsed_seconds: int

# ExpeditionManager (autoload)
func start_expedition(region: RegionResource, party: PartyData,
        duration_seconds: int) -> void
func reveal_progress() -> void
func is_expedition_active() -> bool
func get_active_expedition() -> ExpeditionData
```

## Testing requirements

- Unit test: given a fixed seed/Region/Party/duration,
  `ExpeditionGenerator` produces byte-identical `steps` across two
  separate calls (determinism regression test per
  [plan §19](../../adventurers-march-implementation-plan.md#19-testing)).
- Unit test: `reveal_progress` called with a simulated elapsed time
  reveals exactly the expected number of steps (test by constructing an
  `ExpeditionData` with known `start_timestamp`/`step_duration_seconds` and
  mocking "now").
- Unit test: generation computes `step_duration_seconds` from the complete
  candidate count and rejects a zero count or a duration that does not divide
  into positive whole-second slices.
- Unit test: after a reward batch is revealed, reloading and calling
  `reveal_progress` again does not grant the batch twice.
- Unit test: an active Expedition save/load round trip preserves its Party
  snapshot, JSON-safe step results, immutable `step_duration_seconds`, reveal
  cursor, terminal/end fields, clock-accounting fields, and maximum seed
  `2^53 - 1`.
- Unit test: a negative observed UTC delta credits zero and a forward delta
  above `BalancingConfig.max_offline_delta_seconds` credits only that maximum;
  both update `last_observed_utc`, persist credited elapsed time, and never
  reveal or grant the same step twice.
- Manual test: full offline-progress check described in Task 11.

## Acceptance criteria

- [ ] Green Hollow Region data exists with Loot/Event-only encounter pool.
- [ ] Starting an Expedition snapshots the Party, sets Heroes to
      `OnExpedition`, fully resolves `steps` immediately, and persists the
      pre-truncation `step_duration_seconds`.
- [ ] `reveal_progress` correctly reveals steps based on elapsed real
      time, including across an app restart, with negative and excessive
      clock deltas handled by the §11 policy.
- [ ] Each reveal batch persists gold rewards and its cursor atomically before
      presentation and cannot be granted twice after restart.
- [ ] Active Expedition state round-trips through the versioned save.
- [ ] Expedition Report shows a correct, readable journal once the
      Expedition completes.
- [ ] Determinism unit test passes.

## Risks

- **Clock/timezone edge cases:** the device UTC clock is not trusted across
  restarts. Mitigation: persist credited elapsed time and clamp each observed
  delta as specified by
  [plan §11](../../adventurers-march-implementation-plan.md#11-idle--offline-progress)
  and this milestone's tests.
- **Forgetting to leave `COMBAT` as a defined-but-unused step kind** would
  force a data-model migration in Milestone 5. Mitigation: Task 4
  explicitly calls this out.

## Next-milestone handoff

Milestone 5 (Combat simulation) adds `CombatSimulator` and wires `COMBAT`
step kind entries into Green Hollow's (and future Regions') encounter
pools, reusing `ExpeditionGenerator`'s existing resolve-at-start pipeline
without changing its architecture.

→ Next: [05-combat-simulation.md](05-combat-simulation.md)
