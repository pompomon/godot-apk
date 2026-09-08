# Milestone 7 — Content Expansion

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Grow the game beyond the single-Region vertical slice into a minimally
complete MVP content set: multiple Regions with distinct identities,
a larger trait/event pool, Region-unlock progression, and validated
balancing.

## Scope

**In scope:** 2 additional Regions with distinct encounter mixes,
expanded trait pool, expanded event-card tables, Region-unlock conditions
tied to progression, roster-cap increases, scripted balance simulations
and `BalancingConfig` tuning.

**Out of scope:** procedural Region generation, faction reputation/
diplomacy, crafting/enchanting (all explicit non-goals per
[plan §3](../../adventurers-march-implementation-plan.md#3-mvp-scope-and-non-goals)).

## Prerequisites / dependencies

- Milestone 6 (Progression and equipment): full Hero progression and
  equipment must be functional, since Party Power and combat outcomes
  depend on both when validating balance.

## Tasks

### Delivery contracts (2026-09-08)

- Add Ashen Reach and Frostbound Pass, with five distinct authored events
  each, their own Loot and enemy groups, and different encounter mixes.
  Green Hollow retains five events. Expand the four-trait pool to eight
  functional flat-stat trade-offs; conditional traits and new skills stay deferred.
- Unlock Ashen Reach at 200 **currently held** gold and Frostbound Pass at
  400. These are permanent achievements once a qualifying observation commits:
  spending gold never relocks a Region. Green Hollow is always available.
  Region clears/counters and purchases are not needed for this delivery.
- Unlock conditions use exact dictionaries: `kind: always`, or `kind: gold`
  with a positive integer `value`. No arbitrary expressions or resource paths.
  `BalancingConfig.region_roster_capacities` maps the three Region IDs to
  initial capacities 12, 16 and 20. Capacity never decreases on spending or tuning.
- `CompanyProgression.preview(gold, unlocked, capacity, balancing)` is pure and
  returns `unlocked_regions` and `roster_capacity`, or an `error` dictionary.
  `is_unlocked(region, unlocked)` and `requirement_text(region)` serve both
  dispatch and UI. Simulation remains independent of Company eligibility.
- The existing reveal/load/foreground observation path commits newly earned
  gold, unlocks and capacity together, including when no Expedition is active.
  Failed pre-commit writes roll everything back; post-commit warnings do not.
  UI only displays committed unlocks and dispatch rechecks eligibility.
- Version 6 retains the existing save fields and preserves original version
  1–5 validation before migration. Legacy reserved unlock strings that do not
  identify shipped Regions are discarded explicitly; no historical rewards
  are rerolled or awarded. Valid inventory, equipment, Hero identity, frozen
  combat logs and rewards, clocks and reports remain unchanged.
- Balance reporting uses reproducible generated Parties and seeds, actual
  Party Power, detached snapshots, and full-HP resets for each independent
  Combat trial. Record below/at/above bands and sample sizes for every Region,
  plus full-Expedition survival/serialized-size checks. Target 70–85% Victory
  near recommendation and modestly above it; below recommendation should
  lose a majority. Stronger Parties beyond the tested band may exceed 85%.
  Recommendations and authored enemy stats may be tuned; do not weaken
  established combat formulas or exact-log regression fixtures.

### Bounded delivery

1. Record Milestone 6 external acceptance; validate the unchanged baseline.
2. Author and validate content and pure progression contracts.
3. Integrate persistence/observation and Region/Roster UI with migration,
   save-fault, locked-dispatch and normal-play unlock tests.
4. Run deterministic balance reports, tune content, then validate the integrated
   revision with clean import, full GUT and Android export.
5. Publish revision-linked evidence; leave Milestone 7 physical-device
   acceptance pending until actually performed.

Content, backend integration and UI have separate writers. One validation owner
checks the integrated revision. Shared registries belong to the content writer;
SaveManager/ExpeditionManager and progression balancing fields belong to the
backend writer. Balance tuning begins only after ownership is handed back.

1. Author 2 new `RegionResource` instances (e.g., "Ashen Reach" — a
   medium desert/ruins Region) with their own encounter pools (Combat +
   Loot + Event mixes distinct from Green Hollow) and enemy groups, per
   [plan §10](../../adventurers-march-implementation-plan.md#10-events-regions-equipment-progression).
2. Define and implement Region-unlock conditions (e.g., gold threshold or
   "cleared Green Hollow N times") and surface locked/unlocked state in
   the Region Select screen.
3. Expand the trait pool (aim for the post-MVP target of richer variety
   mentioned in [plan §6](../../adventurers-march-implementation-plan.md#6-heroes-classes-attributes-traits-status-generation),
   while keeping each trait paired bonus/penalty per the legibility
   pillar).
4. Expand event-card tables (new Region-specific events, 5–10 per Region
   at minimum, per plan §8).
5. Implement roster-cap increases tied to Company progression (e.g., gold
   milestones or Region clears), surfaced in the Company Roster screen
   when the player is at cap.
6. Write a small headless "balance simulation" tool/script (can live under
   `tests/` or a `tools/` script invoked via `godot --headless`) that runs
   `CombatSimulator.resolve_combat` across many seeded Parties at, above,
   and below each Region's recommended Party Power, initializing each
   trial's Hero-state map at `MaxHP`, and reports win rates.
7. Tune `BalancingConfig` coefficients (damage multipliers, Party Power
   weights, encounter odds) until win-rate bands match the guidance in
   [plan §16](../../adventurers-march-implementation-plan.md#16-balancing)
   (~70–85% win rate at/above recommended Power, majority losses below
   it) for every Region.

## Expected files / scenes / scripts / data

```
data/regions/ashen_reach.tres
data/encounters/ashen_reach_events.tres
data/encounters/<new enemy groups>.tres
data/traits/<additional trait .tres files>
data/balancing/default_balancing.tres (updated coefficients)
tools/balance_simulation.gd            # or tests/test_balance_simulation.gd
```

## Interfaces / data contracts

Content uses the established `RegionResource`, `HeroTraitResource` and
`EnemyGroupResource` schemas. Company progression adds the pure interfaces,
capacity mapping and version-6 validation described in the delivery contracts
above; these are integrated with the existing observer, not a second manager.
The headless tooling delegates to the existing CombatSimulator facade:

```gdscript
# balance_simulation tool (headless-runnable)
# For each Region and a range of Party Power tiers (below/at/above
# recommended), runs N seeded combats and prints win rate.
static func run(regions: Array[RegionResource], trials: int, seed_value: int,
    balancing: BalancingConfig) -> Dictionary
```

## Testing requirements

- Unit test: Region-unlock condition evaluation (locked Region stays
  locked below threshold, unlocks at/above it).
- Balance-simulation run (not necessarily a pass/fail unit test, but a
  recorded report) showing win rates within target bands for every
  shipped Region; attach or summarize results in the PR description for
  this milestone.
- Manual test: play through unlocking the new Region(s) via normal
  progression (not by manually editing save data) to confirm the unlock
  condition and Region Select UI work together correctly.

## Acceptance criteria

- [ ] At least 3 total Regions are unlockable through normal play
      progression (Green Hollow + 2 new).
- [ ] Each Region has a distinct encounter/event mix and at least one
      unique enemy group.
- [ ] Region-unlock conditions are implemented and correctly reflected in
      Region Select's locked/unlocked UI state.
- [ ] Roster cap increases are tied to progression and surfaced to the
      player when reached.
- [ ] Balance-simulation results show win rates within the target bands
      from plan §16 for every Region.
- [ ] Physical Android acceptance: unlock both Regions through normal play,
      inspect their requirements and roster-cap changes, dispatch to each,
      and confirm permanent unlocks after spending, backgrounding and restart.

## Implementation and validation evidence

**Baseline (2026-09-08, `a3f8419`):** the validation owner tested an isolated
`git archive` of the unchanged revision with SHA512-verified Godot 4.7.2
editor/templates. Clean import, the full **319 tests / 21,914 assertions**
(both GUT hooks), and Android debug export exited successfully. The nonempty
APK was **28,479,394 bytes**. The missing-project-icon and unavailable-ADB
diagnostics were pre-existing. This is local baseline evidence, not integrated
Milestone 7 or device acceptance.

**Content/integration checkpoint:** all three Regions, fifteen Events, three
Loot pools, six enemy groups, eight trade-off traits, permanent unlocks/capacity,
version-6 migration, Region Select and Roster feedback are implemented.
Clean import and focused checks passed (**204 tests / 18,911 assertions**);
the integrated full suite passed **356 tests / 23,335 assertions**, both hooks
enabled. Android export/nonempty verification passed with a **28,521,467-byte
APK**. Initial parser/type errors and intentional schema/count fixture changes
were corrected without dropping regression coverage. The original four-trait
golden-generation fixture remains exact. A scoped read-only review reported
no significant defects; device behavior remains unverified.

The initial 128-trial balance report found unmet targets in all nine bands:
Green Hollow 84.4/86.7/87.5%, Ashen Reach 98.4/100/100%, Frostbound Pass
96.1/100/100% (below/at/above). This checkpoint is intentionally **not balanced
or milestone-complete**. Maximum sampled journal size was 129,063 bytes;
full-save tests also cover twenty roster Heroes and 1,024 inventory entries.
Next bounded action: tune authored encounter difficulty/recommendations and
repeat reports plus integrated regression/export validation.

## Risks

- **Content authoring taking longer than expected:** this milestone has
  the least fixed scope (how many traits/events is "enough" is
  judgment-based). Mitigation: treat the numeric minimums in the tasks
  above (2 Regions, 5–10 events per Region) as the acceptance bar, not
  a ceiling — additional content can continue post-MVP.
- **Balance tuning oscillation:** changing one coefficient can shift win
  rates across all Regions simultaneously. Mitigation: re-run the full
  balance-simulation report after every coefficient change, not just for
  the Region being tuned.

## Next-milestone handoff

Milestone 8 (Presentation pass) applies final art/audio/UI polish across
all screens and all content now authored in Milestones 2–7.

→ Next: [08-presentation-pass.md](08-presentation-pass.md)
