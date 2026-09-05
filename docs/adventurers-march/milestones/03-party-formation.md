# Milestone 3 — Party Formation

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Let the player assemble up to 4 Heroes into a Party with a front/back
formation and see a legible Party Power estimate before committing to an
Expedition.

## Scope

**In scope:** `PartyData` model, formation slot assignment, `PartyEvaluator`
Party Power formula, Party Formation screen, Hero status transitions
(`Idle` → `Assigned`).

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
3. Fill in `BalancingConfig` fields needed for this formula (per-level
   weight, per-stat weights, no-front-row penalty, party-size scaling) and
   author `data/balancing/default_balancing.tres`.
4. Build Party Formation screen: shows only `Idle` Heroes as selectable,
   lets the player assign selected Heroes to the 4 formation slots
   (drag-and-drop or tap-to-place, whichever is simpler to implement
   correctly first — drag-and-drop is a nice-to-have, not required for
   MVP), and displays a live-updating Party Power value as slots change.
5. On confirming a Party in this screen, set each included Hero's status
   to `Assigned` (via `GameState`) and store the resulting `PartyData` as
   the Company's current/pending Party (single Party for MVP, per
   non-goals). Extend `SaveManager` to serialize each occupied formation
   slot by stable Hero ID and autosave the Party and status changes together.
6. Allow returning to the roster/undoing formation before an Expedition is
   actually started (Region Select, Milestone 4, is a separate
   confirmation step) — releasing Heroes back to `Idle` status if the
   player backs out.

## Expected files / scenes / scripts / data

```
scripts/models/party_data.gd
scripts/systems/party_evaluator.gd
data/balancing/default_balancing.tres
scenes/ui/party_formation/party_formation_screen.tscn
tests/test_party_evaluator.gd
```

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

`GameState` gains (or fills in, if declared as a stub in Milestone 1) a
`current_party: PartyData` property — this is read by Region Select
(Milestone 4) to start an Expedition.

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
- Manual test: only `Idle` Heroes are selectable in the Party Formation
  screen; assigning a Hero updates its status and removes it from the
  selectable pool; Party Power updates live as slots change.

## Acceptance criteria

- [ ] `PartyData` supports up to 4 Heroes across 4 named formation slots.
- [ ] `PartyEvaluator.compute_party_power` matches the plan's formula and
      is covered by passing unit tests for full/partial/no-front-row
      cases.
- [ ] Party Formation screen only allows selecting `Idle` Heroes.
- [ ] Confirming a Party sets included Heroes' status to `Assigned` and
      backing out returns them to `Idle`; both mutations persist atomically
      with the current Party.

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

→ Next: [04-first-expedition.md](04-first-expedition.md)
