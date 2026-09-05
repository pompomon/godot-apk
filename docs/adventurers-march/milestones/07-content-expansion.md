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

No new public interfaces are introduced — this milestone is primarily
content authoring against the schemas already established in Milestones
2–6 (`RegionResource`, `HeroTraitResource`, `EnemyGroupResource`,
`BalancingConfig`). The one new piece of tooling:

```gdscript
# balance_simulation tool (headless-runnable)
# For each Region and a range of Party Power tiers (below/at/above
# recommended), runs N seeded combats and prints win rate.
func run_balance_report(regions: Array[RegionResource], trials_per_tier: int) -> void
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
