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
  Power's existing level/Defense coefficients may also be calibrated to avoid
  underrating high-level partial Parties. Preserve the hand-computed evaluator
  regression as an explicit original-coefficient fixture; the Resource tests
  separately assert the shipped tuning.

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

- [x] At least 3 total Regions are unlockable through normal play
      progression (Green Hollow + 2 new).
- [x] Each Region has a distinct encounter/event mix and at least one
      unique enemy group.
- [x] Region-unlock conditions are implemented and correctly reflected in
      Region Select's locked/unlocked UI state.
- [x] Roster cap increases are tied to progression and surfaced to the
      player when reached.
- [ ] Balance-simulation results show win rates within the target bands
      from plan §16 for every Region.
- [ ] Physical Android acceptance: unlock both Regions through normal play,
      inspect their requirements and roster-cap changes, dispatch to each,
      and confirm permanent unlocks after spending, backgrounding and restart.

## Implementation and validation evidence

### Balance-only follow-up protocol (2026-09-08)

- Calibration: seeds **7001, 7002 and 9001**, **256 distinct Parties per
  Region/tier/seed** (768 trials per aggregate row). Seed 9001 is now known
  and is no longer held out.
- Fresh held-out evaluation: seeds **91001, 91002 and 91003**, with the same
  sample size, declared before numerical tuning. Evaluate these only after
  freezing the calibration candidate. Do not retune against their results;
  a miss remains an explicitly reported acceptance blocker.
- Both aggregates must meet all nine existing point-estimate bands: below
  recommendation <50% Victory, at and modestly above 70–85%. Individual seeds
  need not all pass. Show Wilson 95% intervals as uncertainty, not as a way to
  relax the targets. Combat samples remain full-HP, Power-selected, and
  outcome-independent; sample shortages fail instead of recycling Parties.
- Report per-enemy Victory/Retreat/Defeat counts, separate full-Expedition
  completion and resting-Hero counts, and serialized sizes. Keep the candidate
  population, tier boundaries, Combat formulas, skills and round limits fixed.
- No new content, save schema, progression system or presentation work.
  Physical Android acceptance remains pending an actual external playthrough.

The follow-up starts from **`7a43848`**, with no pre-existing working-tree
changes. The [Android workflow on that merged baseline](https://github.com/pompomon/godot-apk/actions/runs/34218321959)
completed successfully, including tests, export and artifact upload. This is
baseline CI evidence, not validation of the follow-up changes.

Fresh local validation of an unchanged archive of `7a43848` passed clean import,
**358 tests / 23,643 assertions**, all three 256-trial baseline reports, and
Android debug export/signature/exclusion checks. The APK was **28,521,467 bytes**
(SHA256 `0b53ad5eb00877785e154da5f55d290223f12a9e2e166a7a8972341472877239`).
The extra test relative to the preceding checkpoint is already present in the
published baseline. SDK refresh failed DNS, but the installed Android platform
and build tools exported successfully. Existing missing-icon and absent-ADB
diagnostics are unchanged; no device was tested.

The distinct-sample/uncertainty reporting checkpoint passed clean import and the
full **360 tests / 23,684 assertions**. Its untuned reports reproduce the baseline
outcome counts exactly, including per-enemy counts, and add recovery diagnostics
without changing the sampled encounters or seeds.

#### Frozen calibration candidate

All nine calibration aggregate bands pass with **768 trials per row**. This
candidate is frozen before running the three predeclared held-out seeds; these
calibration results alone do not complete balance acceptance.

| Region | Below | At | Above |
|---|---:|---:|---:|
| Green Hollow | 39.97% | 71.35% | 82.68% |
| Ashen Reach | 49.48% | 70.31% | 82.94% |
| Frostbound Pass | 43.62% | 71.74% | 84.38% |

Ashen's original at-band misses included **157 Retreats / 768 trials**.
Replacing its high Defense with HP-based durability and retuning Attack reduces
that to **16 / 768** without changing the round cap or Combat formulas. Several
calibration candidates were rejected for making the below band too easy or the
above band too successful; only the declared calibration seeds informed tuning.
The final Ashen recommendation is **850** (previously 820), changing newly
dispatched 120-second runs from **325 to 332 XP** per Hero. Green Hollow and
Frostbound remain **330 / 1000**, with unchanged **142 / 430 XP**.

Frostbound Sentinels have slightly higher HP/Attack while Prowlers have lower
Attack; their existing targeting, Evasion, Initiative and encounter weights
remain unchanged. Green Hollow, global balancing coefficients, skills, classes,
durations, unlock thresholds, capacities and save version 6 are unchanged.
The candidate's content/frozen-XP/size regression slice passes **7 tests / 581
assertions**; full integrated validation and held-out acceptance follow.

#### Follow-up verdict (633d1de)

**Balance acceptance remains blocked.** The published and tested gameplay
revision is [`633d1de`](https://github.com/pompomon/godot-apk/commit/633d1de55ac9ebfaf61a801a175dddf5ca0a82be).
Calibration passes **9/9**, but the first evaluation of the predeclared held-out
seeds passes **7/9**. Ashen Reach-above and Frostbound Pass-above exceed the
unchanged 85% upper bound. No numerical changes were made after seeing held-out
results; confidence intervals do not waive point-estimate failures. Both
balance and physical-device acceptance checkboxes remain open.

Each aggregate row below sums **768 independent full-HP Combat trials**:
256 distinct Party snapshots per Region/tier/seed, from each fixed 16,000-Party
population. Distinctness is checked within each seed/row, not asserted across
seeds. Counts are **Victory / Retreat / Defeat**; brackets are Wilson 95%
Victory-rate intervals. Aggregate rates use summed counts, not rounded averages.

| Region / tier | Calibration V/R/D | Victory % [95% interval] | Held-out V/R/D | Victory % [95% interval] |
|---|---:|---:|---:|---:|
| Green Hollow / below | 307/24/437 | 39.97 [36.57, 43.48] | 331/32/405 | 43.10 [39.64, 46.63] |
| Green Hollow / at | 548/31/189 | 71.35 [68.06, 74.44] | 579/28/161 | 75.39 [72.22, 78.31] |
| Green Hollow / above | 635/32/101 | 82.68 [79.85, 85.19] | 627/34/107 | 81.64 [78.75, 84.22] |
| Ashen Reach / below | 380/22/366 | 49.48 [45.95, 53.01] | 381/33/354 | 49.61 [46.08, 53.14] |
| Ashen Reach / at | 540/16/212 | 70.31 [66.99, 73.44] | 540/11/217 | 70.31 [66.99, 73.44] |
| Ashen Reach / above | 637/26/105 | 82.94 [80.12, 85.44] | 660/25/83 | **85.94 [83.30, 88.22] — fails** |
| Frostbound Pass / below | 335/24/409 | 43.62 [40.15, 47.15] | 317/35/416 | 41.28 [37.85, 44.79] |
| Frostbound Pass / at | 551/23/194 | 71.74 [68.46, 74.81] | 578/25/165 | 75.26 [72.09, 78.18] |
| Frostbound Pass / above | 648/38/82 | 84.38 [81.64, 86.77] | 668/25/75 | **86.98 [84.41, 89.18] — fails** |

Per-enemy diagnostics retain the actual authored Combat-weight sampling. Each
cell below lists **below; at; above**, with V/R/D counts in each tier.

| Enemy group | Trials per tier, calibration / held-out | Calibration V/R/D | Held-out V/R/D |
|---|---:|---|---|
| Forest Wolves | 533 / 483 | 234/11/288; 392/20/121; 465/24/44 | 230/14/239; 373/18/92; 414/24/45 |
| Bandit Skirmishers | 235 / 285 | 73/13/149; 156/11/68; 170/8/57 | 101/18/166; 206/10/69; 213/10/62 |
| Ash-road Raiders | 467 / 441 | 223/11/233; 332/8/127; 379/16/72 | 217/15/209; 315/8/118; 382/9/50 |
| Cinder Jackals | 301 / 327 | 157/11/133; 208/8/85; 258/10/33 | 164/18/145; 225/3/99; 278/16/33 |
| Icebound Sentinels | 492 / 460 | 169/18/305; 295/14/183; 387/29/76 | 125/28/307; 302/20/138; 372/19/69 |
| Snowcrest Prowlers | 276 / 308 | 166/6/104; 256/9/11; 261/9/6 | 192/7/109; 276/5/27; 296/6/6 |

**Complete-Expedition trade-offs:** these separate trials retain HP carryover;
their completion rates are not Combat Victory rates. At recommendation:

| Region | Untuned calibration completion / resting Heroes | Final calibration completion / resting Heroes | Held-out completion / resting Heroes |
|---|---|---|---|
| Green Hollow | 61.20%; 940/1810 | 61.20%; 940/1810 | 64.97%; 874/1800 |
| Ashen Reach | 63.80%; 1238/2423 | 47.40%; 1742/2676 | 45.70%; 1791/2690 |
| Frostbound Pass | 33.46%; 1957/2596 | 35.68%; 1952/2596 | 36.72%; 1890/2588 |

Each completion percentage has 768 Expedition trials; resting counts divide
injured Heroes by participating Heroes. Ashen's reduced armor stalls come with
**worse Expedition attrition**, despite improved independent Combat Victory
rates. Its recommendation change also changes sampled Party composition, so
these comparisons are not matched-Party causal estimates. The normal-reward
progression regression still reaches and dispatches to all three Regions without
editing gold, XP or saves. No new Expedition-completion target is inferred.

**Integrated validation:** clean import, focused **98 tests / 3,083 assertions**,
full **361 tests / 23,678 assertions**, and Android debug export all exit 0.
Both GUT hooks remain enabled, with no empty discovery, skipped scripts, pending
tests or GUT errors. The actual assertion total differs from the untuned
checkpoint because authored outcomes affect existing fixture assertion counts;
no unrelated tests or assertions were removed. All six report processes exit 0
(valid reports), while checking the combined balance acceptance returns failure.
The scoped read-only gameplay/correctness review found no blocking regressions.

The largest sampled Expedition is **146,023 bytes**. The existing full-save
fixture measures **43,155–96,927 bytes** across all six enemy groups at levels
1/3/6, each with twenty Heroes, three offers and 1,024 inventory entries; every
fixture validates below the unchanged **1,048,576-byte** save limit. These are
sampled cases, not exhaustive maxima. The diagnostic only printed existing
serialized sizes in an isolated archive, without changing assertions or
production code; that instrumentation was removed afterward.

The APK is **28,521,467 bytes**, SHA256
`0e2976b969d6171b19ee6daebcf1cb6c105b1ce194a0670b737010ba647e226f`.
Nonempty, v2/v3 signature and archive-exclusion checks pass; tests, GUT and
balance tools are absent. Existing missing-icon/ADB diagnostics remain, and no
physical Android behavior was certified. Raw local evidence is retained under
the ignored `build/m7-validation/evidence/integrated-633d1de/` directory; the
revision, commands, counts and intervals here are the published evidence.

To reproduce, use the README's clean import, full GUT and Android export
commands with Godot 4.7.2. Run the existing balance command with `--trials=256`
once for each seed **7001, 7002, 9001, 91001, 91002, 91003**, and sum the
first three and last three reports separately. These last three seeds are now
known evaluation data and must not be presented as fresh holdouts for later work.

Changed-file secret scans were clean. Post-commit CodeQL was requested but
could not analyze the changed GDScript/Resource languages; this is not a clean
CodeQL analysis result. The [Android run on this candidate](https://github.com/pompomon/godot-apk/actions/runs/34233441103)
is **`action_required`**, with zero jobs/logs executed: maintainer approval is
needed, not a CI test fix. Baseline CI success does not establish candidate CI.

All validation processes and writes stopped before this evidence-only update;
the parent was the sole source/data writer and the gameplay revision stayed
frozen. **Next bounded action:** agree a subsequent calibration/holdout protocol
before any further numerical edits, address the two above-band misses without
losing the narrow Ashen below/at margins, and evaluate Ashen attrition alongside
isolated Combat rates. Then obtain physical Android normal-play acceptance.
Do not start Milestone 8 or mark this milestone complete.

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

Published as **`65d788a`**, with a clean working tree verified after push.
Changed-file secret scanning was clean. CodeQL was requested after commit,
but reported no supported changed language, so no analysis was performed.
The [Android run for this checkpoint](https://github.com/pompomon/godot-apk/actions/runs/34194489621)
is `action_required`, with zero jobs returned by the logs endpoint: a maintainer
approval blocker, not a passing or failing integrated CI result.

### Final bounded checkpoint — balance acceptance incomplete

The final tested gameplay revision calibrates the existing Power level/Defense
weights to **30 / 3**, without changing the evaluator or Combat formulas.
Recommendations are **330 / 820 / 1000** for Green Hollow, Ashen Reach and
Frostbound Pass. Authored enemy HP, Attack and Defense were tuned; historical
saved encounters are not recomputed. The original Power and Hero-generation
golden fixtures retain explicit historical inputs rather than relaxed assertions.

Clean import, focused checks (**22 tests / 1,333 assertions**), the full GUT
suite (**357 tests / 23,635 assertions**, both standard hooks), Android export
and nonempty verification all exited successfully. No skipped scripts or GUT
warnings/errors remained. The authored-reward progression test starts with the
ordinary 100-gold Company and reaches/dispatches to all three Regions without
editing gold, XP or save data. Reload and acknowledgment preserve earned rewards.
Full-save fixtures cover twenty Heroes, three offers, 1,024 inventory copies
and five-combat candidate runs; the largest measured fixture was **116,899
bytes**, below `SaveManager.MAX_SAVE_BYTES` (1,048,576). These are sampled
fixtures, not a proof about every possible journal.

The APK is **28,521,467 bytes**, SHA256
`24c4de6f165458f45e6f176301a962a6ddfce3fcc99d7f9d1b9da16ead141407`.
Archive inspection confirmed tests, GUT and balance tools are excluded.
The missing-icon/ADB diagnostics remain pre-existing and non-blocking for
export; neither export nor headless UI tests certify physical-device behavior.

#### Recorded balance results

Each seed generates a fixed 16,000-Party candidate population, independent of
combat outcomes. Trials sample actual Power at 60–80%, 95–105% and 105–115%
of recommendation. Every row/seed below has **256 distinct Parties / 256
independent full-HP Combat trials**, with enemy groups sampled according to
their authored Combat weights. Full-Expedition trials separately exercise
HP carryover; they are not used as interchangeable Combat win rates.

Seeds **7001 and 7002** were used for calibration; **9001** was evaluated only
after the final tuning and was not used for further changes. Calibration
aggregates contain 512 trials per Region/tier. A successful tool exit means a
valid report, not target acceptance.

| Region | Calibration below | At | Above | Independent 9001 below | At | Above |
|---|---:|---:|---:|---:|---:|---:|
| Green Hollow | 37.30% | 72.46% | 84.18% | 45.31% | 69.14% | 79.69% |
| Ashen Reach | 49.80% | 64.65% | 67.77% | 48.44% | 64.06% | 70.31% |
| Frostbound Pass | 42.77% | 71.88% | 88.09% | 44.53% | 71.48% | 81.25% |

**Unmet acceptance:** calibration misses Ashen Reach's at/above bands and
Frostbound Pass's above band (**6/9 pass**). The independent population misses
Green Hollow-at and Ashen Reach-at (**7/9 pass**). Targets and sample bands
were not changed to conceal these misses; the balance checkbox remains open.
The largest journal across these runs was **154,051 bytes**. Expedition
completion rates at recommendation were roughly 58–66% for Green Hollow,
59–69% for Ashen Reach and 31–35% for Frostbound Pass; attrition makes them
lower than independent Combat Victory rates.

Reproduce each report after the README's clean import:

```sh
godot --headless --path . -s res://tools/balance_simulation.gd -- --trials=256 --seed=7001
godot --headless --path . -s res://tools/balance_simulation.gd -- --trials=256 --seed=7002
godot --headless --path . -s res://tools/balance_simulation.gd -- --trials=256 --seed=9001
```

All source writers confirmed stopped with no queued edits; the validation
owner stopped all processes before publication. Scope was frozen to preserve
closeout capacity instead of beginning another tuning cycle. **Next bounded
action:** a balance-only follow-up addressing the named misses, retaining
unchanged simulation semantics and regression gates, followed by Android
physical acceptance. No Region-clear subsystem, new skills, art pass or
additional milestone implementation is needed for this handoff.

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
