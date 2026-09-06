# Milestone 3 — Party Formation

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Let the player assemble up to 4 Heroes into a Party with a front/back
formation and see a legible Party Power estimate before committing to an
Expedition.

## Scope

**In scope:** `PartyData` model, draft formation editing, `PartyEvaluator`
Party Power formula, Party Formation screen, transactional confirmation and
disbanding (`Idle` ↔ `Assigned`), and version-2 persistence with version-1
migration.

**Out of scope:** actually starting an Expedition (Milestone 4), combat
resolution (Milestone 5), equipment stat contributions beyond what
Milestone 2's derived stats already provide (equipment itself lands in
Milestone 6, but `PartyEvaluator` should already read equipment-modified
stats if present so no rework is needed later).

## Prerequisites / dependencies

- Milestone 2 (Hero roster): `HeroData`, `HeroStatus`,
  `compute_derived_stats`, and the Company Roster screen must exist.

## Tasks

1. Implement `scripts/models/party_data.gd` (`class_name PartyData`):
   up to 4 `HeroData` references, each mapped to a formation slot
   (`FRONT_LEFT`, `FRONT_RIGHT`, `BACK_LEFT`, `BACK_RIGHT`).
2. Implement `scripts/systems/party_evaluator.gd`
   (`class_name PartyEvaluator`) with a pure `compute_party_power(party:
   PartyData, balancing: BalancingConfig) -> float` function implementing
   the formula from
   [plan §7](../../adventurers-march-implementation-plan.md#7-party-formation-and-evaluation).
3. Consume and, if needed, tune the existing Party Power values in
   `data/balancing/default_balancing.tres` (per-level/per-stat weights,
   no-front-row penalty, party-size scaling). Extend this single asset rather
   than recreating it; preserve recruitment, combat, and Expedition settings.
   Validate required stat keys, finite nonnegative weights, a positive divisor,
   and a formation factor in `(0, 1]` before evaluation.
4. Build Party Formation screen: tap a slot, then an available Hero to place
   them. Only `Idle` roster Heroes may be newly added; members of the current
   confirmed Party remain editable while `Assigned`. The draft owns its slot
   mapping but references the canonical roster Heroes. Draft edits do not
   mutate statuses or save; selected Heroes are excluded from the available
   pool. Support moving to an empty slot and explicit removal, without silent
   overwrites. Display live Party Power and explain partial/no-front-row
   penalties. Drag-and-drop remains deferred.
5. On confirming a Party in this screen, set each included Hero's status
   to `Assigned` (via `GameState`) and store the resulting `PartyData` as
   the Company's current/pending Party (single Party for MVP, per
   non-goals). Extend `SaveManager` to serialize each occupied formation
   slot by stable Hero ID and autosave the Party and status changes together.
6. Cancel/Back discards only draft edits and preserves any confirmed Party.
   **Disband Party** explicitly clears the confirmed Party and releases its
   members to `Idle`, saving both together. Confirmation returns Home until
   Region Select exists; Home and Company Roster provide Form/Edit Party
   entry points. Pause/close saves only committed state, never the draft.
7. Validate again on confirmation through `PartyFormationService`, including
   canonical roster identity and current Hero availability. Reject empty
   confirmed Parties, duplicates, unavailable Heroes, stale references, and
   editing/disbanding during an active Expedition. Preserve the screen and
   show retry feedback when saving fails.
8. Extend `GameState` checkpoints to capture mutable Hero statuses and a
   separate copy of the Party slot mapping while retaining Hero identity.
   Roll back only when `SaveManager.last_committed` is false, not for a
   post-commit warning.
9. Add save version 2 with `current_party` as `null` or four named slots
   containing stable roster Hero IDs/empty values. Validate membership and
   `Assigned` statuses together; reject orphan assignments, unknown IDs,
   recruitment offers, and duplicate members. Restore roster objects before
   resolving Party references. Never persist derived Power or draft state.
   Validate version-1 data before migration, initialize its Party to `null`,
   release legacy orphan `Assigned` Heroes to `Idle`, and preserve all other
   progress. Retain the validated temporary-write/backup-recovery pipeline.

## Expected files / scenes / scripts / data

```
scripts/models/party_data.gd
scripts/systems/party_evaluator.gd
scripts/systems/party_formation_service.gd
autoload/GameState.gd
autoload/SaveManager.gd
scenes/ui/party_formation/party_formation_screen.tscn
scenes/ui/party_formation/party_formation_screen.gd
tests/test_party_data.gd
tests/test_party_evaluator.gd
tests/test_party_formation.gd
tests/test_party_persistence.gd
tests/test_party_ui.gd
```

The existing balancing asset supplies all required coefficients unchanged.
Extend Home/Roster integration, test isolation, and the existing persistence
suite alongside focused service and UI tests.

## Interfaces / data contracts

```gdscript
# PartyData (RefCounted)
enum FormationSlot { FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT }
var slots: Dictionary   # { FormationSlot: HeroData (or null) }

func heroes() -> Array[HeroData]        # non-null slot values
func has_front_row_hero() -> bool

# PartyEvaluator
static func compute_party_power(party: PartyData,
        balancing: BalancingConfig) -> float
```

`GameState.current_party: PartyData` owns the nullable, confirmed pending
Party, read by Region Select (Milestone 4). The formation draft is a separate
mapping, not a second committed Party. `heroes()` enumerates occupied slots
in front-left, front-right, back-left, back-right order. Empty drafts are
valid; confirmed Parties contain 1–4 Heroes.

Party Power is the weighted sum of `HeroStats` output and Hero levels,
multiplied by member count / `party_size_divisor`, then by
`missing_front_row_factor` only if the front row is empty. An empty draft
scores zero. Invalid inputs must expose validation feedback instead of a
normal-looking fallback value. Equipment remains deferred in `HeroStats`;
its future effects will flow through that shared calculator.

## Testing requirements

- Unit test: `compute_party_power` for a full 4-Hero Party with a front
  row present matches a hand-computed expected value for a known
  `BalancingConfig` and known Heroes.
- Unit test: `compute_party_power` applies the no-front-row penalty
  correctly (Party of only back-row Heroes scores lower than an otherwise
  identical Party with a front-row Hero).
- Unit test: `compute_party_power` scales down for Parties smaller than 4.
- Unit test: a save/load round trip preserves the current Party's slot-to-Hero
  mapping and its Heroes' `Assigned` statuses.
- Unit tests: model slot ordering, uniqueness, invalid slots, movement/removal,
  and draft mapping independence; invalid/nonfinite Power inputs and custom
  weights; evaluator input immutability.
- Unit tests: confirmation, replacement, disbanding, stale/unavailable Heroes,
  canonical identity, repeated confirmation, and active-Expedition guards.
- Persistence tests: version-1 migration, malformed legacy/current saves,
  null/full/partial Parties, orphan assignments, roster-object identity,
  pre-commit rollback, post-commit warnings, and missing/corrupt primary
  recovery without replacing the valid backup.
- UI tests: Home/Roster entry, placement/removal/movement, live Power,
  confirm/cancel/disband, failed-save retry feedback, lifecycle saves excluding
  draft edits, and reload of committed state.
- Manual test: only available Heroes can be newly selected; selection removes
  them from the pool without changing their status until confirmation.
  Cancel preserves the old Party, while Disband releases it. Verify long text,
  touch scrolling without accidental activation, and Android Back behavior.

## Acceptance criteria

- [x] `PartyData` supports up to 4 Heroes across 4 named formation slots.
- [x] `PartyEvaluator.compute_party_power` matches the plan's formula and
      is covered by passing unit tests for full/partial/no-front-row
      cases.
- [x] Party Formation screen only newly adds `Idle` roster Heroes and allows
      editing retained members of the confirmed Party.
- [x] Confirming a Party sets included Heroes' status to `Assigned` and
      disbanding returns them to `Idle`; Party/status changes persist in one
      validated snapshot with pre-commit rollback.
- [x] Cancel/Back and lifecycle saves never commit unfinished draft edits.
- [x] Version-1 saves migrate without losing Company progress; version-2
      Party references and statuses validate and round-trip together.

### Exported-device acceptance

Automated tests do not substitute for device checks. Keep the overall
milestone unchecked until these checks and final validation evidence are recorded:

- [ ] Form a partial and full Party, move/remove members, and verify displayed
  Power and status badges on a target Android device.
- [ ] Confirm, force-close, and relaunch: identical Heroes occupy the saved
  slots. Cancel an edit and relaunch: the previously confirmed Party remains.
- [ ] Disband and relaunch: no Party remains and its members are `Idle`.
- [ ] Verify Android Back cancels edits without disbanding or unexpectedly
  quitting; backgrounding never commits a draft.
- [ ] Verify long-text wrapping, scrolling without accidental activation,
  portrait lock, and effective 48×48 dp touch targets at target density.

## Implementation and validation evidence

Implemented `PartyData`, pure `PartyEvaluator`, `PartyFormationService`,
draft-based formation UI, Home/Roster entry points, explicit cancellation and
disbanding, and version-2 saves with validated version-1 migration.

- **Local suite (2026-09-06):** clean import with the pinned Godot 4.7.2
  succeeded; **145 tests passed with 15,897 assertions** using the existing
  GUT runner and unchanged OS-temporary-storage hooks. Five focused Party
  suites cover model/evaluation, transactions, persistence, and UI, alongside
  the existing regression suite.
- **Review follow-up:** integer-authored stat weights are converted to float
  before multiplication to prevent int64 overflow from becoming a plausible
  Power estimate. The added regression failed before the fix and passed
  afterward; nonfinite floating-point results remain rejected.
- **Security/review checks:** changed-file secret scanning found no secrets,
  and the final UI/integration review found no significant issues. CodeQL
  was invoked, but performed no analysis because the changed source languages
  are unsupported; this is not a clean CodeQL security-analysis result.
- **Android export:** the existing debug preset exported successfully and
  APK signature verification passed. The pre-existing missing-icon diagnostic
  remains; no application/package identifiers or export presets were changed.
- **Device checks:** no physical Android device checks were performed.
  The exported-device checklist above and earlier milestones' outstanding
  acceptance evidence remain open; headless UI/touch tests do not prove
  target-density sizing or device lifecycle behavior.
- **Save compatibility:** a valid version-1 primary migrates in memory and is
  written as version 2 on the next save; version-1 backup recovery writes a
  version-2 primary without modifying the valid legacy backup.

## Risks

- **Formation UI complexity:** drag-and-drop slot assignment can eat
  significant UI implementation time. Mitigation: ship a simpler
  tap-to-select-slot-then-tap-hero interaction first; drag-and-drop is a
  post-MVP polish item (candidate for
  [Presentation pass](08-presentation-pass.md)).
- **Party Power formula miscommunicating risk:** if the number doesn't
  correlate with actual encounter outcomes once Combat (Milestone 5)
  exists, players will learn to distrust it. Mitigation: revisit
  coefficients during Milestone 7's balance-simulation pass once combat
  exists end-to-end.

## Next-milestone handoff

Milestone 4 (First expedition) reads `GameState.current_party` to start
an Expedition and will need `PartyData.heroes()` to snapshot Party state
at Expedition start (per the "resolve at start" design).
`ExpeditionManager.start_expedition` accepts `PartyData` but remains a stub
until then; active Expedition ownership stays exclusively on that manager.
Milestone 4 must extend save/status invariants for the start/finalize transition,
not leave `OnExpedition` Heroes in an `Assigned`-only pending Party.

→ Next: [04-first-expedition.md](04-first-expedition.md)
