# Adventurer's March — Milestones Checklist

This is the ordered, trackable checklist for implementing **Adventurer's
March**. Work through milestones **in order** — each milestone lists its
dependencies, and later milestones assume earlier ones are complete. Update
this file (check boxes, add notes/links to PRs) as work progresses; it is
the single place to see overall status at a glance.

> See also:
> - [Full implementation plan](adventurers-march-implementation-plan.md) —
>   the comprehensive design/architecture reference.
> - [`adventurers-march/milestones/`](adventurers-march/milestones/) —
>   one detailed plan per milestone below.

## How to use this file

- Pick the **first milestone with an unchecked box**, in order — that is
  the next task.
- Open the linked milestone file for full task breakdown, acceptance
  criteria, interfaces, and testing requirements before starting.
- Check a milestone's box only when its **Definition of Done** (below) is
  fully met, not just when code is written.
- If a milestone must be split across multiple PRs, check off individual
  tasks within its own file rather than the top-level box, and only check
  the top-level box here once the whole milestone is done.

## Recommended execution order

| # | Milestone | Depends on | Status | Detail |
|---|---|---|---|---|
| 1 | Technical foundation | — | [ ] | [01-technical-foundation.md](adventurers-march/milestones/01-technical-foundation.md) |
| 2 | Hero roster | 1 | [ ] | [02-hero-roster.md](adventurers-march/milestones/02-hero-roster.md) |
| 3 | Party formation | 2 | [ ] | [03-party-formation.md](adventurers-march/milestones/03-party-formation.md) |
| 4 | First expedition | 3 | [ ] | [04-first-expedition.md](adventurers-march/milestones/04-first-expedition.md) |
| 5 | Combat simulation | 4 | [ ] | [05-combat-simulation.md](adventurers-march/milestones/05-combat-simulation.md) |
| 6 | Progression and equipment | 5 | [ ] | [06-progression-and-equipment.md](adventurers-march/milestones/06-progression-and-equipment.md) |
| 7 | Content expansion | 6 | [ ] | [07-content-expansion.md](adventurers-march/milestones/07-content-expansion.md) |
| 8 | Presentation pass | 7 | [ ] | [08-presentation-pass.md](adventurers-march/milestones/08-presentation-pass.md) |
| 9 | Testing and release preparation | 8 | [ ] | [09-testing-and-release.md](adventurers-march/milestones/09-testing-and-release.md) |

Milestones 1–5 constitute the
[first playable vertical slice](adventurers-march-implementation-plan.md#22-first-playable-vertical-slice-and-build-order).
Milestones 6–9 build out full MVP scope and release readiness.

---

## 1. Technical foundation

**Depends on:** none (starting point).

- [ ] Restructure the project into the recommended folder layout
      (`autoload/`, `data/`, `scripts/models/`, `scripts/systems/`,
      `scenes/ui/`, `tests/`).
- [ ] Add `GameState`, `SaveManager`, `ExpeditionManager`,
      `CombatSimulator`, `UIManager` autoloads (can be near-empty stubs
      with correct responsibilities/interfaces defined).
- [ ] Define base `Resource` script classes for content
      (`HeroClassResource`, `HeroTraitResource`, `ItemResource`,
      `RegionResource`, `BalancingConfig`) with typed exported fields.
- [ ] Wire an empty Home screen through `UIManager` so the app boots to it.
- [ ] Set up a headless test framework (GUT or GdUnit4) under `tests/`
      with one passing smoke test.

**Definition of done:** the project builds/exports via the existing
Android workflow, boots to an empty Home screen through `UIManager`, all
autoloads exist with documented responsibilities, base data Resource
classes exist (even if unused by content yet), and the test framework runs
headlessly with at least one passing test.

Detail: [01-technical-foundation.md](adventurers-march/milestones/01-technical-foundation.md)

## 2. Hero roster

**Depends on:** 1 (Technical foundation).

- [ ] Author `HeroClassResource` data for Knight, Ranger, Wizard, Cleric.
- [ ] Author 3–5 `HeroTraitResource` entries.
- [ ] Implement `HeroGenerator` (seeded, pure function per
      [plan §6](adventurers-march-implementation-plan.md#6-heroes-classes-attributes-traits-status-generation)).
- [ ] Implement `HeroData` model and derived-stat calculation.
- [ ] Build Company Roster screen (list/grid + status badges).
- [ ] Build Hero Detail screen (attributes, traits, status, XP).
- [ ] Seed a starting roster of 4 Heroes (one per class) on new-game
      creation.
- [ ] Add deterministic gold-priced recruitment offers to the Company
      Roster, including roster-cap checks and immediate persistence.
- [ ] Implement versioned JSON save/load, atomic `.bak` rotation, and
      round-trip/corruption-recovery tests for Milestone 2 state.

**Definition of done:** a new game starts with 4 generated Heroes visible
in the Company Roster screen; tapping a Hero opens Hero Detail showing
correct attributes/traits/status; the player can recruit an offered Hero and
reload without losing it; `HeroGenerator` and `SaveManager` have deterministic
generation and round-trip/recovery tests.

Detail: [02-hero-roster.md](adventurers-march/milestones/02-hero-roster.md)

## 3. Party formation

**Depends on:** 2 (Hero roster).

- [ ] Implement `PartyData` model (up to 4 Heroes + formation slots).
- [ ] Implement `PartyEvaluator` (Party Power formula per
      [plan §7](adventurers-march-implementation-plan.md#7-party-formation-and-evaluation)).
- [ ] Build Party Formation screen: select idle Heroes, assign front/back
      slots, display computed Party Power.
- [ ] Enforce Hero status transitions (`Idle` → `Assigned`) when added to
      a Party.

**Definition of done:** the player can select up to 4 idle Heroes, place
them in front/back slots, see a live-updating Party Power value, and only
idle Heroes are selectable; `PartyEvaluator` has unit tests covering full,
partial, and no-front-row Parties.

Detail: [03-party-formation.md](adventurers-march/milestones/03-party-formation.md)

## 4. First expedition

**Depends on:** 3 (Party formation).

- [ ] Author `RegionResource` data for "Green Hollow" with non-combat
      travel/loot/event steps only (combat wired in Milestone 5).
- [ ] Implement `ExpeditionData` model and step-generation logic
      (seeded, resolved-at-start per
      [plan §8](adventurers-march-implementation-plan.md#8-expeditions-travel-encounters-outcomes-deterministic-resolution)).
- [ ] Implement `ExpeditionManager.start_expedition(...)` and
      `reveal_progress(...)`.
- [ ] Build Region Select screen (single Region for now) and Expedition
      Report screen (travel journal).
- [ ] Wire Home screen to show in-progress Expedition status and route to
      the Report screen when complete.
- [ ] Verify offline/idle progress: closing and reopening the app reveals
      the correct amount of progress based on elapsed time.

**Definition of done:** the player can select the Party, start an
Expedition to Green Hollow, see it progress on Home, and view a correct
Expedition Report after the duration elapses — including after fully
closing and reopening the app; a determinism test confirms the same seed
produces byte-identical resolved steps across two runs.

Detail: [04-first-expedition.md](adventurers-march/milestones/04-first-expedition.md)

## 5. Combat simulation

**Depends on:** 4 (First expedition).

- [ ] Implement `CombatSimulator` per
      [plan §9](adventurers-march-implementation-plan.md#9-auto-combat-simulation-design)
      (turn order, hit/crit/damage/heal formulas, round loop, outcome).
- [ ] Author 1–2 enemy-group data definitions for Green Hollow.
- [ ] Wire Combat encounter steps into `ExpeditionManager`'s step
      generation/resolution.
- [ ] Truncate generated steps at Defeat or a Region-terminal Retreat and
      persist the terminal step/end timestamp.
- [ ] Extend Expedition Report to render a readable combat log.
- [ ] Add one active skill per class (Guard / Firebolt / Mend / basic
      Ranger attack variant).

**Definition of done:** Combat steps in Green Hollow resolve
deterministically via `CombatSimulator`, produce a correct
Victory/Retreat/Defeat outcome, and display a readable round-by-round log
in the Expedition Report; unit tests assert an exact expected outcome/log
for a fixed seed, Party, and enemy group.

Detail: [05-combat-simulation.md](adventurers-march/milestones/05-combat-simulation.md)

## 6. Progression and equipment

**Depends on:** 5 (Combat simulation).

- [ ] Implement Hero XP gain and leveling using class growth curves.
- [ ] Implement `ItemResource`/inventory model and starter item pool.
- [ ] Build Equipment screen (assign weapon/armor, show stat deltas).
- [ ] Apply Wounded/Resting recovery flow after Defeat/heavy-damage
      outcomes.
- [ ] Wire loot/gold rewards from Expeditions into inventory/Company gold.

**Definition of done:** Heroes gain XP and level up from completed
Expeditions with visibly updated stats, items can be equipped/unequipped
with correct stat deltas shown before confirming, and a Hero that survives
a Defeat becomes Wounded and later becomes Idle again after a recovery
period.

Detail: [06-progression-and-equipment.md](adventurers-march/milestones/06-progression-and-equipment.md)

## 7. Content expansion

**Depends on:** 6 (Progression and equipment).

- [ ] Author 1–2 additional Regions (different encounter mixes/difficulty
      tiers).
- [ ] Expand trait pool and event-card tables.
- [ ] Add Region-unlock conditions and roster-cap increases tied to
      progression.
- [ ] Run scripted balance simulations (per
      [plan §16](adventurers-march-implementation-plan.md#16-balancing))
      against new Regions and tune `BalancingConfig`.

**Definition of done:** at least 3 total Regions are unlockable through
normal play progression, each with a distinct encounter/event mix, and
balance-simulation results show win rates within the target bands from the
plan for Parties at/above/below recommended Party Power.

Detail: [07-content-expansion.md](adventurers-march/milestones/07-content-expansion.md)

## 8. Presentation pass

**Depends on:** 7 (Content expansion).

- [ ] Integrate final art (portraits, class/status icons, Region
      backdrops) across all screens.
- [ ] Integrate audio (ambient loops, UI SFX, volume/mute settings).
- [ ] UI polish pass: consistent spacing/typography, touch-target sizing
      audit, color-contrast/accessibility audit.
- [ ] Replace any placeholder text/art from earlier milestones.

**Definition of done:** every MVP screen uses final art/audio (no
placeholder assets remain), a touch-target and color-contrast pass has
been completed against the criteria in
[plan §2](adventurers-march-implementation-plan.md#2-target-platform-and-mobile-ux-constraints),
and Settings correctly controls audio.

Detail: [08-presentation-pass.md](adventurers-march/milestones/08-presentation-pass.md)

## 9. Testing and release preparation

**Depends on:** 8 (Presentation pass).

- [ ] Reach full unit-test coverage of `CombatSimulator`, `HeroGenerator`,
      `PartyEvaluator`, and `SaveManager` migrations.
- [ ] Extend CI to run the headless test suite before export, failing on
      test failure.
- [ ] Perform full manual device playtest of the core loop, including a
      real offline/backgrounding check and a save-corruption/`.bak`
      fallback check.
- [ ] Prepare release export preset (real package id, signed release
      build) and store assets (icon, screenshots).

**Definition of done:** CI runs and passes the full test suite before
every export, a full manual playtest (including offline progress and save
fallback) has been completed and recorded, and a signed release build with
store assets is ready to publish.

Detail: [09-testing-and-release.md](adventurers-march/milestones/09-testing-and-release.md)
