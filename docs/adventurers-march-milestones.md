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
- If a milestone must be split across multiple PRs, record completion notes
  and PR links alongside the numbered tasks in its own file, and only check
  the top-level box here once the whole milestone is done.

## Recommended execution order

| # | Milestone | Depends on | Status | Detail |
|---|---|---|---|---|
| 1 | Technical foundation | — | [x] | [01-technical-foundation.md](adventurers-march/milestones/01-technical-foundation.md) |
| 2 | Hero roster | 1 | [x] | [02-hero-roster.md](adventurers-march/milestones/02-hero-roster.md) |
| 3 | Party formation | 2 | [x] | [03-party-formation.md](adventurers-march/milestones/03-party-formation.md) |
| 4 | First expedition | 3 | [x] | [04-first-expedition.md](adventurers-march/milestones/04-first-expedition.md) |
| 5 | Combat simulation | 4 | [x] | [05-combat-simulation.md](adventurers-march/milestones/05-combat-simulation.md) |
| 6 | Progression and equipment | 5 | [ ] | [06-progression-and-equipment.md](adventurers-march/milestones/06-progression-and-equipment.md) |
| 7 | Content expansion | 6 | [ ] | [07-content-expansion.md](adventurers-march/milestones/07-content-expansion.md) |
| 8 | Presentation pass | 7 | [ ] | [08-presentation-pass.md](adventurers-march/milestones/08-presentation-pass.md) |
| 9 | Testing and release preparation | 8 | [ ] | [09-testing-and-release.md](adventurers-march/milestones/09-testing-and-release.md) |

Milestones 1–5 constitute the
[first playable vertical slice](adventurers-march-implementation-plan.md#22-first-playable-vertical-slice-and-build-order).
Milestones 6–9 build out full MVP scope and release readiness.

**Acceptance update (2026-09-07):** the user accepted Milestones 1–4 and
directed that device acceptance be considered complete externally for now.
Their checked device criteria record that external acceptance, not device tests
performed by this agent. Milestone 5 slices 4–5 were subsequently implemented
and validated as recorded below; Milestone 6 is the next unfinished work.

---

## 1. Technical foundation

**Depends on:** none (starting point).

- [x] Restructure the project into the recommended folder layout
      (`autoload/`, `data/`, `scripts/models/`, `scripts/systems/`,
      `scenes/ui/`, `tests/`).
- [x] Add `GameState`, `SaveManager`, `ExpeditionManager`,
      `CombatSimulator`, `UIManager` autoloads (can be near-empty stubs
      with correct responsibilities/interfaces defined).
- [x] Define base `Resource` script classes for content
      (`HeroClassResource`, `HeroTraitResource`, `ItemResource`,
      `RegionResource`, `BalancingConfig`) with typed exported fields.
- [x] Wire an empty Home screen through `UIManager` so the app boots to it.
- [x] Set up a headless test framework (GUT or GdUnit4) under `tests/`
      with one passing smoke test.

**Status:** accepted. Implementation and local test/export validation are
complete, the Android workflow passed, and device acceptance was confirmed
externally by the user on 2026-09-07.

**Definition of done:** the project builds/exports via the existing
Android workflow, boots to an empty Home screen through `UIManager`, all
autoloads exist with documented responsibilities, base data Resource
classes exist (even if unused by content yet), and the test framework runs
headlessly with at least one passing test.

Detail: [01-technical-foundation.md](adventurers-march/milestones/01-technical-foundation.md)

## 2. Hero roster

**Depends on:** 1 (Technical foundation).

- [x] Author `HeroClassResource` data for Knight, Ranger, Wizard, Cleric.
- [x] Author 3–5 `HeroTraitResource` entries.
- [x] Implement `HeroGenerator` (seeded, pure function per
      [plan §6](adventurers-march-implementation-plan.md#6-heroes-classes-attributes-traits-status-generation)).
- [x] Implement `HeroData` with immutable, persisted stable IDs and
      derived-stat calculation.
- [x] Build Company Roster screen (list/grid + status badges).
- [x] Build Hero Detail screen (attributes, traits, status, XP).
- [x] Seed a starting roster of 4 Heroes (one per class) and 100 starting
      gold on new-game creation.
- [x] Add deterministic 100-gold recruitment offers to the Company Roster,
      including roster-cap checks and immediate persistence.
- [x] Implement versioned JSON save/load with validated same-directory
      temporary writes, best-effort replacement through Godot APIs, and
      recovery from a missing or invalid primary via `.bak`.

**Status:** implemented with automated generation, statistics, persistence,
recruitment, and UI coverage. Three offers use functional flat-stat traits;
XP progression remains deferred. Accepted by the user on 2026-09-07 with
external device acceptance; see the detail file for validation evidence.

**Definition of done:** a new game starts with 4 generated Heroes visible
in the Company Roster screen; tapping a Hero opens Hero Detail showing
correct attributes/traits/status; the player can recruit an offered Hero and
reload without losing it; `HeroGenerator` and `SaveManager` have deterministic
generation, stable-ID, round-trip, interrupted-write, and recovery tests.

Detail: [02-hero-roster.md](adventurers-march/milestones/02-hero-roster.md)

## 3. Party formation

**Depends on:** 2 (Hero roster).

- [x] Implement `PartyData` model (up to 4 Heroes + formation slots).
- [x] Implement `PartyEvaluator` (Party Power formula per
      [plan §7](adventurers-march-implementation-plan.md#7-party-formation-and-evaluation)).
- [x] Build Party Formation screen: select idle Heroes, assign front/back
      slots, display computed Party Power.
- [x] Enforce Hero status transitions (`Idle` → `Assigned`) on confirmation;
      persist Party edits/disbanding together with their statuses.
- [x] Migrate version-1 saves and validate version-2 Party references.

**Status:** implemented with draft-only editing, explicit disbanding,
transactional Party/status persistence, migration, and automated coverage.
Accepted by the user on 2026-09-07 with external device acceptance; see the
detail file for validation evidence.

**Definition of done:** the player can select up to 4 idle Heroes, place
them in front/back slots, see a live-updating Party Power value, and only
idle Heroes may be newly added (existing Party members remain editable);
canceling preserves the confirmed Party, explicit disbanding releases its
Heroes, and committed state survives reload. `PartyEvaluator` has unit tests
covering full, partial, and no-front-row Parties.

Detail: [03-party-formation.md](adventurers-march/milestones/03-party-formation.md)

## 4. First expedition

**Depends on:** 3 (Party formation).

- [x] Author `RegionResource` data for "Green Hollow" with non-combat
      travel/loot/event steps only (combat wired in Milestone 5).
- [x] Implement `ExpeditionData` model and step-generation logic
      (seeded, resolved-at-start per
      [plan §8](adventurers-march-implementation-plan.md#8-expeditions-travel-encounters-outcomes-deterministic-resolution)),
      including persisted immutable step duration computed before any
      terminal truncation.
- [x] Implement `ExpeditionManager.start_expedition(...)` and
      `reveal_progress(...)`.
- [x] Build Region Select screen (single Region for now) and Expedition
      Report screen (travel journal).
- [x] Wire Home screen to show in-progress Expedition status and route to
      the Report screen when complete.
- [x] Verify offline/idle progress: closing and reopening the app reveals
      the correct amount of progress based on elapsed time.

**Status:** implemented with five non-combat Travel/encounter pairs over
60 seconds, frozen Party/journal snapshots, version-3 saves, transactional
gold/status updates, and retained reports requiring acknowledgment.
Clean import, all 182 tests, and the Android debug export passed locally.
Accepted by the user on 2026-09-07, including external device offline/lifecycle
acceptance recorded in its detail file.

**Definition of done:** the player can select the Party, start an
Expedition to Green Hollow, see it progress on Home, and view a correct
Expedition Report after the duration elapses — including after fully
closing and reopening the app; a determinism test confirms the same seed
produces byte-identical resolved steps across two runs.

Detail: [04-first-expedition.md](adventurers-march/milestones/04-first-expedition.md)

## 5. Combat simulation

**Depends on:** 4 (First expedition).

- [x] Implement `CombatSimulator` per
      [plan §9](adventurers-march-implementation-plan.md#9-auto-combat-simulation-design)
      (derived-stat hit/crit/damage/heal formulas including Evasion, round
      loop, outcome).
- [x] Author 1–2 enemy-group data definitions for Green Hollow.
- [x] Wire Combat encounter steps into `ExpeditionManager`'s step
      generation/resolution.
- [x] Truncate generated steps at Defeat or a Region-terminal Retreat and
      persist the terminal step/end timestamp without changing the stored
      pre-truncation step duration.
- [x] Carry HP through sequential Combats and merge `final_hero_states` by
      stable Hero ID before Expedition finalization.
- [x] Extend Expedition Report to render a readable combat log.
- [x] Add one active skill per class (Guard / Firebolt / Mend / basic
      Ranger attack variant).

**Status:** all five delivery slices are implemented. Green Hollow includes
Forest Wolves and Bandit Skirmishers; reports render revealed-only combat logs,
and recovery refreshes Hero/Party availability after commit. Version-4 saves
preserve frozen logs and migrate versions 1–3. All **267 tests / 20,238 assertions**
pass locally, with a successful Android debug export. Device acceptance is
treated as external per the user's direction, not as a device test run by this
agent. See the detail file for separate local, publication and CI evidence.

**Definition of done:** Combat steps in Green Hollow resolve
deterministically via `CombatSimulator`, produce a correct
Victory/Retreat/Defeat outcome, and display a readable round-by-round log
in the Expedition Report; unit tests assert an exact expected outcome/log
for a fixed seed, Party/current-Hero-state map, and enemy group.

Detail: [05-combat-simulation.md](adventurers-march/milestones/05-combat-simulation.md)

## 6. Progression and equipment

**Depends on:** 5 (Combat simulation).

- [x] Implement Hero XP gain and leveling using class growth curves.
- [x] Implement `ItemResource`/inventory model and starter item pool.
- [x] Build Equipment screen (assign weapon/armor, show stat deltas).
- [x] Apply Wounded/Resting recovery flow after Defeat/heavy-damage
      outcomes.
- [x] Extend Milestone 4's existing gold-reward reveal path with item loot
      updates to inventory, without a second reward handler.

**Status:** implementation and local automated validation are complete:
**314 tests / 21,874 assertions**, clean import, and a successful Android debug
export. Version-5 saves preserve equipment copies and frozen rewards while
migrating versions 1–4. The top-level milestone remains unchecked pending
physical Android acceptance; see the detail file for contracts, checkpoint
evidence, and the remaining manual check.

**Definition of done:** Heroes gain XP and level up from completed
Expeditions with visibly updated stats, items can be equipped/unequipped
with correct stat deltas shown before confirming, and a Hero that survives
a Defeat becomes Wounded and later becomes Idle again after a recovery
period.

Detail: [06-progression-and-equipment.md](adventurers-march/milestones/06-progression-and-equipment.md)

## 7. Content expansion

**Depends on:** 6 (Progression and equipment).

- [ ] Author 2 additional Regions (different encounter mixes/difficulty
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
- [ ] Audit the foundation's existing test-before-export CI gate against the
      complete gameplay suite, including failure/discovery rejection.
- [ ] Perform full manual device playtest of the core loop, including a
      real offline/backgrounding check and a save-corruption/`.bak`
      fallback check for both invalid and missing primary saves.
- [ ] Prepare release export preset (real package id, signed release
      build) and store assets (icon, screenshots).

**Definition of done:** CI runs and passes the full test suite before
every export, a full manual playtest (including offline progress and save
fallback) has been completed and recorded, and a signed release build with
store assets is ready to publish.

Detail: [09-testing-and-release.md](adventurers-march/milestones/09-testing-and-release.md)
