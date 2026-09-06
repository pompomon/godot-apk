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

## First-playable behavior

- Green Hollow is always available, with one 60-second duration and five
  Travel/encounter pairs: ten steps at six seconds per step.
- The pool contains five Event Resources and one Loot Resource. Events resolve
  automatically to narrative-only or nonnegative gold outcomes; items, XP,
  injuries, spending, and mid-Expedition choices remain out of scope.
- Recommended Party Power is advisory. Partial and back-row-only Parties can
  depart; there is no minimum-Power gate.
- Starting consumes the pending Party and changes its Heroes from `Assigned`
  to `OnExpedition`. Finalization returns those Heroes to `Idle`; it does not
  silently recreate a confirmed Party.
- One completed report remains saved until explicit acknowledgment.
  Acknowledgment clears the report without granting rewards. Players may form
  the next Party after completion, but cannot dispatch until the old report
  is acknowledged. Back does not acknowledge a report.
- Step content, Party starting values, and journal text are frozen at dispatch.
  A restart or later content change must not reroll or reinterpret the results.

## Prerequisites / dependencies

- Milestone 3 (Party formation): `GameState.current_party` must be
  populated via the Party Formation screen before an Expedition can start.

## Tasks

1. Reuse the existing typed `RegionResource` fields (per
   [plan §10](../../adventurers-march-implementation-plan.md#10-events-regions-equipment-progression)):
   name, recommended Party Power, available durations, travel-step count,
   weighted encounter pool (Loot/Event entries only for this milestone),
   unlock condition.
2. Author `data/regions/green_hollow.tres` and a small
   set of `EventResource` entries under `data/encounters/` (5–10 total),
   each with a weighted automatic outcome table. Also author one or more
   `LootResource` entries in the Loot registry under `data/encounters/`;
   each defines an inclusive `min_gold`/`max_gold` range keyed by `loot_id`.
3. Implement `scripts/models/expedition_data.gd`
   (`class_name ExpeditionData`): frozen Region ID/name, Party snapshot, seed,
   `start_timestamp`, duration, immutable `step_duration_seconds`,
   `steps: Array[ExpeditionStep]`, `last_revealed_index`,
   `terminal_step_index` (default `-1`), `effective_end_timestamp`,
   `last_observed_utc`, and `credited_elapsed_seconds`.
4. Implement `scripts/systems/expedition_generator.gd`: given a Region,
   Party, seed, and duration, produce the full `steps` array with each
   step's outcome **already resolved** (Loot gold amount rolled, Event
   outcome rolled). First construct exactly `travel_step_count` pairs of
   `[TRAVEL, encounter]`, with no trigger roll or extra steps; thus
   `candidate_step_count = 2 * travel_step_count`, independent of duration.
   Reject nonpositive travel counts or pools with no positive-weight entries.
   In pair order, select one encounter per pair, with replacement, by
   `EncounterEntryResource.weight *
   BalancingConfig.encounter_kind_weight_multipliers[kind]`, resolve
   `content_id` through the registry for that entry's kind, and select an
   Event outcome by its `EventOutcomeResource.weight` — per
   [plan §8](../../adventurers-march-implementation-plan.md#8-expeditions-travel-encounters-outcomes-deterministic-resolution).
   For Loot, resolve `content_id` through the Loot registry and roll
   `rng.randi_range(min_gold, max_gold)` into the stored `{ "gold": int }`
   result.
   After generating the full candidate step list but before resolving any
   outcome that could later truncate it, compute
   `step_duration_seconds = duration_seconds / candidate_step_count`.
   Persist this positive integer and never recompute it from `steps.size()`.
   Only then resolve outcomes in step order using the same seeded RNG stream.
   Initialize `effective_end_timestamp` to
   `start_timestamp + duration_seconds`; Milestone 5 may shorten it using
   the stored step duration.
   Combat steps can be represented now (e.g., a `COMBAT` step kind) but
   should not appear in Green Hollow's pool yet — leave the kind defined
   so Milestone 5 doesn't need a data-model change.
5. Implement `ExpeditionManager.start_expedition(region, party, duration)
   -> void`: snapshots the Party, generates steps via
   `ExpeditionGenerator`, stores the active Expedition on `ExpeditionManager`,
   and autosaves. `ExpeditionManager` is its sole owner; `GameState` must not
   hold a second copy. `SaveManager` serializes/restores it alongside Company
   state, and readers use `get_active_expedition()`.
   Revalidate that the input is the current confirmed Party with canonical,
   available roster members. Save its removal, Hero status changes, and
   independent Expedition seed advancement together. Reject duplicate starts
   and replacement of an unacknowledged report.
6. Implement `ExpeditionManager.reveal_progress() -> void`: computes
   elapsed time, advances `last_revealed_index`, applies newly revealed
   gold rewards to `GameState`, and marks the Expedition
   finalized when fully revealed (Heroes' status returns from
   `OnExpedition`/`Assigned` appropriately — see Hero status handling
   below). Save the rewards and updated cursor together immediately, before
   presenting the newly revealed results, so restarting cannot apply a
   reward batch twice. Save every changed clock observation, including one
   that reveals no step. Use `SaveManager.last_committed`, not a return value
   from `save()`, to distinguish pre-commit failure from post-commit warnings.
   Roll back Company and manager state together on pre-commit failure.
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
    "Step 3 of 10") and call `ExpeditionManager.reveal_progress()` on entry.
    The persistent lifecycle owner also checks progress after load, on
    focus/resume, and periodically while foregrounded, even when Home is not
    visible. Duplicate notifications must not duplicate rewards or writes.
11. Manually verify offline progress: start an Expedition with a short
    duration, force-quit the app, wait past the duration, reopen, and
    confirm the Expedition Report shows complete, correct results.
12. Extend `SaveManager`'s JSON-safe serializers/deserializers for
    `PartyData`, `ExpeditionData`, and every `ExpeditionStep.result`
    dictionary, including immutable `step_duration_seconds`, the reveal
    cursor, terminal/end fields, and clock-accounting fields. Add an
    active-Expedition round-trip test, including the maximum allowed seed
    `2^53 - 1`. Introduce version 3 with separately persisted Expedition RNG
    state. Validate original version-1/version-2 schemas before migration;
    preserve valid pending Parties and recruitment state. Normalize legacy
    orphan `OnExpedition` statuses to `Idle` because those versions could not
    store an Expedition. Reset/restore manager state alongside Company state
    on new-game creation, load, and backup recovery.
13. Consume the existing balancing asset's neutral encounter-kind multipliers
    and provisional 86400-second offline cap. Validate that every used kind has
    a finite nonnegative multiplier, the effective pool has positive total
    weight, and the offline cap is positive before starting/revealing an
    Expedition. Reject invalid configuration rather than silently freezing
    progress or substituting hard-coded values.
14. Persist completed-report acknowledgment through the same transaction
    boundary. Never grant rewards on acknowledgment or change statuses a second
    time when reopening a completed report. Preserve the report on save failure.
15. Extend test isolation to reset and restore the manager, injected clock, and
    diagnostics. Keep all autoload initialization I/O-free and use the existing
    OS-temporary save-storage hooks.

## Expected files / scenes / scripts / data

```
data/regions/green_hollow.tres
data/encounters/green_hollow_loot.tres
data/encounters/green_hollow_<event_id>.tres
scripts/models/expedition_data.gd
scripts/models/expedition_step.gd
scripts/models/expedition_party_snapshot.gd
scripts/systems/expedition_catalog.gd
scripts/systems/expedition_generator.gd
scenes/ui/region_select/region_select_screen.tscn
scenes/ui/region_select/region_select_screen.gd
scenes/ui/expedition_report/expedition_report_screen.tscn
scenes/ui/expedition_report/expedition_report_screen.gd
tests/test_expedition_generator.gd
tests/test_expedition_manager.gd
tests/test_expedition_persistence.gd
tests/test_expedition_ui.gd
```

## Interfaces / data contracts

```gdscript
# ExpeditionStep (RefCounted)
enum StepKind { TRAVEL, LOOT, EVENT, COMBAT }   # COMBAT defined, unused this milestone
var kind: StepKind
var content_id: String
var title: String
var journal_text: String
var result: Dictionary   # shape depends on kind, e.g. { "gold": 12 } for LOOT

# ExpeditionPartySnapshot (RefCounted)
# Four named slots with detached plain-data members or null.
# Members retain stable ID, name, class ID/name, level, effective attributes,
# derived stats, and the authored basic-attack targeting rule.
var slots: Dictionary

# ExpeditionData (RefCounted)
enum Status { RUNNING, COMPLETED }
var region_id: String
var region_name: String
var party_snapshot: ExpeditionPartySnapshot
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
var status: Status

# ExpeditionManager (autoload)
func start_expedition(region: RegionResource, party: PartyData,
        duration_seconds: int) -> void
func reveal_progress() -> void
func is_expedition_active() -> bool
func get_active_expedition() -> ExpeditionData
func acknowledge_report(expected: ExpeditionData) -> void
```

Resolved fields expose defensive copies; mutable clock/cursor/status fields
are updated only by the manager's saved transactions. The model deliberately
uses `ExpeditionPartySnapshot`, not `PartyData.copy()`: formation drafts must
continue sharing canonical roster Heroes, whereas in-flight snapshots must not.
The manager retains a completed record for the Report, but
`is_expedition_active()` is true only while it is running.
Start/acknowledgment callers check the manager's `last_committed` and
`last_error`; a queued navigation is not proof that a transaction succeeded.
Acknowledgment requires the current report identity, so a stale screen cannot
clear a replacement record.

The snapshot's fractional `Evasion` and `CritChance` values are encoded on disk
as validated 16-character float64 hexadecimal strings; runtime readers receive
numbers. This preserves their exact starting values through Godot's JSON decimal
parser. Other numeric fields retain bounded JSON numbers. Save validation rejects
malformed encodings, nonfinite values, and probabilities outside `[0, 1]`.

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
- Unit test: `travel_step_count = 2` and a Loot-only pool produce exactly
  `[TRAVEL, LOOT, TRAVEL, LOOT]`; a 40-second duration yields 10-second
  slices. A fixed-seed mixed pool produces the exact expected encounter
  sequence and outcomes, selecting with replacement before resolving outcomes.
  Reject negative travel counts and pools with no positive-weight entries.
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
- Unit tests: pre-commit failure at every existing save fault boundary restores
  Party/status/seed state on dispatch and gold/cursor/clock state on reveal;
  retry works, while post-commit warnings never undo saved mutations.
- Unit tests: saved Party values and journal results remain independent of
  subsequent roster/class/encounter edits. Unsupported payloads, invalid numeric
  values, stale Parties, and duplicate starts are rejected without mutation.
- Unit tests: completed-report acknowledgment is persisted, never reapplies
  rewards, and preserves a newly formed Party. Version-1/version-2 migration
  and corrupt/missing-primary recovery preserve valid progress.
- UI tests: running/completed/no-report states, no future journal disclosure,
  failed-save retry, Back without acknowledgment, and lifecycle progress while
  another screen is open. Include same-frame cancellation followed by an outgoing
  Start/Acknowledge callback and a failed dispatch retried on the same screen.
- Manual test: full offline-progress check described in Task 11.

## Acceptance criteria

- [x] Green Hollow Region data exists with Loot/Event-only encounter pool.
- [x] Starting an Expedition snapshots the Party, sets Heroes to
      `OnExpedition`, fully resolves `steps` immediately, and persists the
      pre-truncation `step_duration_seconds`.
- [x] `reveal_progress` correctly reveals steps based on elapsed real
      time, including across an app restart, with negative and excessive
      clock deltas handled by the §11 policy.
- [x] Each reveal batch persists gold rewards, its cursor, and clock accounting
      in one validated save before presentation and cannot be granted twice
      after restart. Replacement remains best-effort through Godot APIs, not
      a promise of filesystem atomicity or arbitrary-power-loss durability.
- [x] Active Expedition state round-trips through the versioned save.
- [x] Expedition Report shows a correct, readable journal once the
      Expedition completes.
- [x] Determinism unit test passes.
- [x] Completed reports survive restart until acknowledgment; acknowledgment
      cannot award gold again or discard a newly formed Party.

### Exported-device acceptance

Automated tests and debug export do not substitute for device checks. Keep the
overall milestone unchecked until the following evidence is recorded:

- [ ] Complete Party → Region → Expedition → Report → acknowledgment on Android.
- [ ] Observe foreground progress without navigation, then background/resume
  from Home and another screen.
- [ ] Force-close during partial progress and verify correct continuation after
  relaunch; repeat after waiting beyond the duration and verify single rewards.
- [ ] Restart with a completed, unacknowledged report and verify it remains
  available; acknowledge, recruit/form a Party, and start the next Expedition.
- [ ] Verify Back behavior, long-text wrapping, touch scrolling without
  accidental activation, portrait lock, and effective 48×48 dp touch targets.

## Implementation and validation evidence

- **Local suite (2026-09-06):** the existing clean import and full GUT runner
  passed with pinned Godot 4.7.2: **182 tests, 17,267 assertions**.
  Four Expedition suites cover authored content,
  exact seeded generation, frozen snapshots, timing/transactions, persistence,
  and UI/lifecycle behavior alongside the earlier milestones' regressions.
- **Persistence coverage:** all existing injected save boundaries are exercised
  for dispatch, clock-only observations, reward revelation, finalization, and
  acknowledgment. Tests cover retry/reload idempotency, maximum safe seeds,
  legacy migration, gold overflow, and corrupt/missing-primary recovery.
- **Review follow-up:** rollback preserves the confirmed Party's identity for
  same-screen retry. Backup-recovery notices remain visible through automatic
  catch-up saves. Completion routing ignores outgoing Home screens; leaving-state
  guards prevent canceled screens from dispatching or acknowledging through
  queued callbacks.
- **Security/review checks:** changed-file secret scanning found no secrets.
  The final read-only review found no significant remaining issues. CodeQL was
  invoked, but performed no analysis because the changed source languages are
  unsupported; this is not a clean CodeQL security-analysis result.
- **Android export:** the existing debug preset exported successfully.
  Expedition scripts/content are included and tests remain excluded. The
  missing-icon and unavailable-ADB diagnostics did not prevent export; no
  application/package identifiers or export presets were changed.
- **Evidence artifacts:** local import, GUT, and export logs are under
  `build/validation/`; the APK is `build/android/hello-world.apk`. These generated
  artifacts are ignored, not committed. Local results are not a claim of remote
  CI approval or physical-device acceptance.
- **Device checks:** no physical Android device checks were performed.
  The checklist above and earlier milestones' outstanding device checks remain
  open; headless lifecycle tests do not prove force-quit behavior on a device.

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

Combat must consume `ExpeditionPartySnapshot`'s frozen member statistics,
formation, stable IDs, and targeting rules rather than recomputing live
`PartyData` statistics. Extend current non-combat result/timing validation to
accept terminal combat payloads and truncated journals while preserving the
stored pre-truncation step duration. Item/XP rewards later extend the existing
reveal transaction, not a second collection path.

→ Next: [05-combat-simulation.md](05-combat-simulation.md)
