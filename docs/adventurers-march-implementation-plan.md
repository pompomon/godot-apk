# Adventurer's March — Implementation Plan

**Adventurer's March** is a mobile idle fantasy simulator: the player recruits
Heroes into a Company, assembles them into a Party, equips and prepares them,
and sends the Party on Expeditions across Regions of a fantasy world. Combat
and travel resolve automatically (auto-combat / idle simulation); the
player's decisions are about preparation, composition, and risk, not
moment-to-moment control.

This document is the single comprehensive design-and-implementation reference
for the project. It is meant to be actionable: a developer should be able to
open this repository, read this plan, and start building the first
milestone without needing additional context.

> Related documents:
> - [Milestones checklist](adventurers-march-milestones.md) — ordered,
>   trackable list of milestones with acceptance criteria.
> - [`adventurers-march/milestones/`](adventurers-march/milestones/) —
>   one detailed plan per milestone (01 through 09).

---

## Table of contents

1. [Product definition and design goals](#1-product-definition-and-design-goals)
2. [Target platform and mobile UX constraints](#2-target-platform-and-mobile-ux-constraints)
3. [MVP scope and non-goals](#3-mvp-scope-and-non-goals)
4. [Core gameplay loop](#4-core-gameplay-loop)
5. [Screen and navigation plan](#5-screen-and-navigation-plan)
6. [Heroes: classes, attributes, traits, status, generation](#6-heroes-classes-attributes-traits-status-generation)
7. [Party formation and evaluation](#7-party-formation-and-evaluation)
8. [Expeditions: travel, encounters, outcomes, deterministic resolution](#8-expeditions-travel-encounters-outcomes-deterministic-resolution)
9. [Auto-combat simulation design](#9-auto-combat-simulation-design)
10. [Events, regions, equipment, progression](#10-events-regions-equipment-progression)
11. [Idle / offline progress](#11-idle--offline-progress)
12. [Save system](#12-save-system)
13. [Godot project architecture](#13-godot-project-architecture)
14. [UI and art direction](#14-ui-and-art-direction)
15. [Audio](#15-audio)
16. [Balancing](#16-balancing)
17. [Monetization considerations](#17-monetization-considerations)
18. [Analytics](#18-analytics)
19. [Testing strategy](#19-testing)
20. [Risks](#20-risks)
21. [Release preparation](#21-release-preparation)
22. [First playable vertical slice and build order](#22-first-playable-vertical-slice-and-build-order)

---

## 1. Product definition and design goals

**Elevator pitch:** *Recruit a Company of Heroes, form a Party, send them on
Expeditions across a fantasy world, and watch them succeed or fail through
deterministic auto-combat — even while you're not playing.*

### Design pillars

1. **Preparation over reflexes.** The player's skill expresses itself
   through Party composition, equipment choices, and Expedition selection —
   not through taps-per-second. This keeps the game friendly to short,
   asynchronous mobile sessions.
2. **Legible simulation.** Auto-combat and travel must be deterministic and
   explainable. The player should be able to look at a Party and a
   destination and reasonably predict the outcome.
3. **Idle-friendly, not idle-only.** The game must reward players who check
   in briefly (queue an Expedition, collect rewards, re-equip) and must not
   punish players who are away, but it should also give engaged players
   meaningful decisions each session.
4. **Data-driven content.** Heroes, Regions, encounters, items, and events
   are defined as data (Godot `Resource` files), not hard-coded logic, so
   content can grow without code changes.
5. **Consistent terminology.** The game uses **Company** (the player's
   collection of all recruited Heroes), **Hero** (an individual unit),
   **Party** (the active subset of Heroes sent on an Expedition),
   **Expedition** (a timed journey into a **Region**), and **Milestone**
   (a development checkpoint for this project — see the
   [milestones checklist](adventurers-march-milestones.md)). These terms
   must be used consistently in UI text, code symbols, and documentation.

## 2. Target platform and mobile UX constraints

This repository already targets **Godot 4.7.2** with an **Android** export
preset (`export_presets.cfg`, package id `com.example.helloworld`) using the
`gl_compatibility` renderer for broad device support (see `project.godot`
and `README.md`). Adventurer's March continues on this foundation:

- **Primary platform:** Android (phones), portrait orientation. The existing
  project already configures a portrait viewport
  (`window/size/viewport_width=720`, `window/size/viewport_height=1280`)
  with `canvas_items` stretch mode — reuse this configuration.
- **Renderer:** keep `gl_compatibility` for the widest device compatibility
  and lowest battery/thermal impact, which matters for a game that may run
  simulation ticks while the app is foregrounded for long idle sessions.
- **Input:** touch-first. Every interactive control must have a touch target
  of at least 40x40 dp (roughly 72x72 px at the project's base 720p
  design resolution). No control should require multi-touch gestures,
  precise drag timing, or hover states (mobile has no hover).
- **Session shape:** support both short sessions (30–60 seconds: check
  Expedition, collect rewards, requeue) and longer sessions (several
  minutes: manage roster, equipment, Region selection). No screen should
  require more than a few taps to reach from the home/status screen.
- **Backgrounding:** the game must correctly compute progress made while the
  app was backgrounded or closed (see [§11 Idle / offline
  progress](#11-idle--offline-progress)), since players will frequently
  background or quit the app during an Expedition.
- **Performance:** target 60 FPS on UI screens on mid-range Android hardware;
  auto-combat simulation must be lightweight (no per-frame heavy
  computation — batch-resolve rounds, see [§9](#9-auto-combat-simulation-design)).
- **Accessibility:** legible font sizes (minimum ~14pt at design resolution),
  sufficient color contrast for status effects, and no gameplay information
  conveyed by color alone (pair color with icon/text).

## 3. MVP scope and non-goals

### MVP scope (must ship in the first playable + early releases)

- One Company with a roster cap (e.g., 12 Heroes).
- A fixed set of Hero classes (recommend: Knight, Ranger, Wizard, Cleric —
  four classes covering tank/physical-dps/magic-dps/support archetypes).
- Hero generation with randomized name, class, attributes within class
  ranges, and 0–1 traits.
- Deterministic recruitment offers that can be purchased with gold and are
  persisted with the Company roster.
- Party formation for up to 4 Heroes with a simple formation grid
  (front/back row) affecting who is targeted first.
- 2–3 starter Regions, each with a linear sequence of travel steps and a
  pool of encounters (combat, loot, and a couple of narrative "event card"
  encounters).
- Deterministic auto-combat simulation (turn/tick based, seeded RNG).
- Equipment: weapon and armor slots per Hero, a small starter item pool,
  and simple stat modification (no crafting yet).
- Idle/offline progress: Expeditions continue while the app is closed, with
  a results summary ("travel journal") shown on return.
- Local save system (single save slot, JSON/Resource-backed, versioned).
- Core screens: Home/Status, Company Roster, Party Formation, Region/Map
  select, Expedition Report, Hero Detail, Equipment.

### Non-goals for MVP (explicitly deferred)

- Multiple simultaneous Parties or multiple concurrent Expeditions.
- PvP, multiplayer, or any networked/server-authoritative play.
- Crafting, enchanting, or item fusion systems.
- Procedurally generated overworld maps (use a small number of
  hand-authored Regions first; procedural generation is a post-MVP
  enhancement, see [§10](#10-events-regions-equipment-progression)).
- Faction reputation/diplomacy systems (mentioned in earlier concept
  brainstorming for related idle-fantasy concepts, but out of scope here).
- Cosmetics, gacha-style recruitment, or any monetization beyond what is
  described as *considerations* in [§17](#17-monetization-considerations)
  — no store integration is required for MVP.
- Cloud save / account system (local save only for MVP; see
  [§12](#12-save-system) for the forward-compatible design).
- Localization pipeline (write MVP UI text in English; keep strings in a
  single place to make localization easy later).

## 4. Core gameplay loop

```
┌─────────────────────────────────────────────────────────────────┐
│                         SESSION LOOP                             │
│                                                                   │
│  1. Review Company roster and Hero status (idle, resting,        │
│     wounded, on Expedition).                                     │
│  2. Form or adjust a Party (choose up to 4 Heroes, assign         │
│     formation slots).                                            │
│  3. Equip the Party from available inventory.                    │
│  4. Choose a Region and an Expedition length/route.               │
│  5. Confirm — Expedition starts, consuming real time.             │
│  6. (Player leaves / app backgrounds / player waits)              │
│  7. Expedition resolves deterministically over its duration       │
│     (travel steps → encounters → outcomes).                       │
│  8. Player returns: Expedition Report screen summarizes travel     │
│     journal, loot, XP, injuries, deaths (if any).                  │
│  9. Rewards applied to Company (XP, gold, items); wounded Heroes   │
│     enter recovery; loop returns to step 1.                        │
└─────────────────────────────────────────────────────────────────┘
```

Meta-progression wraps this loop: as the Company earns gold and items, the
player unlocks new Regions, hires more Heroes (up to roster cap), and
improves equipment, which allows tackling harder Regions, which yields
better rewards.

## 5. Screen and navigation plan

Recommended screen set and navigation graph (all screens are Godot scenes
under `scenes/ui/`, see [§13](#13-godot-project-architecture)):

```
Home / Status  ──────────────┬──────────────┬───────────────┬────────────┐
(current Expedition          │              │               │            │
 status, quick actions)      ▼              ▼               ▼            ▼
                        Company Roster  Region Select  Expedition   Settings
                              │              │          Report
                              ▼              │
                        Hero Detail          │
                              │              ▼
                              ▼        (confirm →starts
                        Equipment       Expedition, returns
                        (per Hero)      to Home)
                              │
                              ▼
                        Party Formation
                        (select up to 4
                         Heroes + slots)
```

- **Home / Status** — the app's default screen. Shows: current Expedition
  progress (if any), a summary of the Company (roster count, gold), and
  primary call-to-action buttons ("Form Party" if idle, "View Report" if an
  Expedition just completed).
- **Company Roster** — scrollable list/grid of all Heroes with class icon,
  level, and status badge (idle / resting / on Expedition / wounded). Tap a
  Hero to open Hero Detail.
- **Hero Detail** — attributes, traits, status, equipped items, XP progress.
  Entry point to Equipment screen for that Hero.
- **Equipment** — assign weapon/armor from inventory to the selected Hero;
  shows stat deltas before confirming.
- **Party Formation** — pick up to 4 Heroes from the roster (only
  idle/available Heroes selectable) and place them into front/back
  formation slots; shows a computed Party Power estimate
  (see [§7](#7-party-formation-and-evaluation)).
- **Region Select** — list of unlocked Regions with recommended Party Power,
  Expedition length options, and expected reward tier; confirming starts
  the Expedition and returns to Home.
- **Expedition Report** — the "travel journal": a scrollable log of travel
  steps and encounters resolved, final outcome, loot/XP/gold gained, and
  any Hero injuries or deaths.
- **Settings** — audio toggle, save management (export/reset), credits.

Navigation should use a single persistent UI root (an autoloaded scene
manager, see [§13](#13-godot-project-architecture)) that swaps the active
screen, rather than each screen managing its own back-stack independently.

## 6. Heroes: classes, attributes, traits, status, generation

### Attributes

Each Hero has a small set of base attributes that drive combat formulas
(see [§9](#9-auto-combat-simulation-design)):

| Attribute | Abbrev. | Effect |
|---|---|---|
| Might | `MIG` | Physical damage scaling, carry capacity for heavy equipment |
| Focus | `FOC` | Magic damage scaling, resist chance vs. magic effects |
| Grit | `GRT` | Max HP, physical damage reduction |
| Guile | `GUI` | Turn order priority (initiative), evasion chance |
| Faith | `FTH` | Healing output scaling, resist chance vs. debuffs |

Derived stats (computed from attributes + class + equipment + level):
`MaxHP`, `Attack`, `MagicPower`, `Defense`, `Evasion`, `Initiative`,
`CritChance`.

### Classes (MVP set)

| Class | Role | Primary attribute | Notes |
|---|---|---|---|
| Knight | Tank / front-line melee | Might, Grit | High HP and Defense, low Evasion |
| Ranger | Physical damage, back-line | Might, Guile | High Initiative and single-target damage |
| Wizard | Magic damage, back-line | Focus | High burst magic damage, low HP |
| Cleric | Support / healer | Faith | Heals and cleanses debuffs, low damage |

Each class defines base attribute ranges and per-level growth curves in a
`HeroClassResource` (see [§13](#13-godot-project-architecture)). Post-MVP,
additional classes (Rogue, Beastmaster, etc., as brainstormed in the
project's originating design conversation) can be added as new resources
without engine code changes.

### Traits

Traits are small modifiers that add flavor and build diversity, generated
randomly (0–1 for MVP, up to 2–3 post-MVP) at Hero creation. Examples:

- **Brave** — +10% damage while this Hero is below 50% HP.
- **Cautious** — +15% Evasion, −10% Initiative.
- **Quick Healer** — recovers from "Wounded" status in half the normal time.
- **Unlucky** — −5% Crit chance, +5% chance to trigger negative encounter
  outcomes (used sparingly; must never be a pure trap trait — pair
  penalties with a compensating upside per design pillar of legibility).

Traits are defined as `HeroTraitResource` data and applied as modifiers to
derived stats or as flags checked during encounter/combat resolution.

### Status

A Hero's status is one of: `Idle`, `Assigned` (in a formed Party not yet on
Expedition), `OnExpedition`, `Resting` (recovering after "Wounded"),
`Wounded` (survived combat at low HP, unavailable until rest completes), or
`Dead` (only possible under permadeath settings — see below).

**Permadeath policy (MVP default: off).** For MVP, Heroes cannot die
permanently; a fatal outcome instead produces a long "Wounded" recovery and
a loot/reward penalty for that Expedition. This keeps the loop
idle-friendly and avoids punishing offline players harshly. Permadeath (or
an optional "Hardcore" mode) is a clearly-flagged post-MVP option.

### Generation

Hero generation (used for starting roster and for recruitable Heroes
offered over time) is a pure function of a seed:

```
generate_hero(seed, class_pool, level = 1) -> HeroData
  rng := RandomNumberGenerator seeded with `seed`
  class := pick from class_pool using rng
  name := pick from name table using rng
  attributes := class.base_attributes + rng-rolled variance within class range
  traits := roll 0..1 traits from trait_pool using rng, filtered to valid
            combinations for this class
  return HeroData(name, class, level, attributes, traits, equipment = none)
```

Using a seeded RNG (see [§8](#8-expeditions-travel-encounters-outcomes-deterministic-resolution)
for the shared determinism approach) means recruitment offers can be
regenerated/audited and, if desired, previewed deterministically.

## 7. Party formation and evaluation

- A Party consists of **1–4 Heroes** (MVP cap), each assigned to a
  **formation slot**: two front-row slots, two back-row slots.
- **Targeting rule (MVP):** melee/short-range attacks target the front row
  first (front row must be empty before back row can be targeted); ranged
  and magic attacks may target any slot. This gives front-row Knights a
  clear tanking role.
- Only Heroes with status `Idle` may be added to a Party. Adding a Hero sets
  their status to `Assigned`; forming/confirming the Party does not yet
  start an Expedition (formation and Region selection are separate steps,
  matching the [screen plan](#5-screen-and-navigation-plan)).
- **Party Power** is a single legible number shown to the player to help
  judge readiness against a Region's recommended Power. Recommended
  baseline formula:

  ```
  PartyPower = Σ over Heroes in Party of (
      HeroLevel * 10
      + MaxHP * 0.5
      + Attack * 1.0
      + MagicPower * 1.0
      + Defense * 0.5
  ) * FormationFactor
  ```

  where `FormationFactor` is 1.0 for a full 4-Hero Party with at least one
  front-row Hero, and a data-tunable penalty (e.g., 0.85) for Parties
  missing a front-row Hero (to reflect fragility), and scales down linearly
  for Parties smaller than 4. Exact coefficients live in a single
  `BalancingConfig` resource ([§16](#16-balancing)), not hard-coded.
- Party Power is an *estimate* for player decision-making, not the value
  used internally by combat resolution — actual outcomes still run the full
  deterministic simulation ([§9](#9-auto-combat-simulation-design)), so
  favorable traits/equipment synergies can outperform the raw number.

## 8. Expeditions: travel, encounters, outcomes, deterministic resolution

An **Expedition** sends a Party into a **Region** for a chosen duration.
Internally, an Expedition is modeled as an ordered list of **travel
steps**; each step takes a fixed slice of the Expedition's total duration
and has a chance to trigger an **encounter**.

### Structure

```
Expedition
 ├─ Region reference
 ├─ Party reference (snapshot of Hero stats at start)
 ├─ Seed (u64) — derived from save-level RNG state at confirm time
 ├─ StartTimestamp (unix time, UTC)
 ├─ Duration (seconds; selected by player from Region's offered options)
 └─ Steps[] (generated at start time, not at resolution time — see below)
      each Step:
        ├─ Kind (Travel | Encounter)
        ├─ EncounterPool reference (if Kind == Encounter)
        └─ ResolvedResult (computed and stored at Expedition start)
 ├─ TerminalStepIndex (-1 unless Defeat or a Region-terminal Retreat occurs)
 └─ EffectiveEndTimestamp (scheduled reveal time of the final stored step)
```

### Encounter types (MVP)

- **Combat** — resolved via the auto-combat simulator
  ([§9](#9-auto-combat-simulation-design)); outcomes: Victory, Retreat
  (Party takes damage but survives, Expedition may end early depending on
  Region rules), or Defeat (Party takes heavy damage, all surviving Heroes
  become Wounded, Expedition ends at that Combat step).
- **Loot** — a straightforward reward step (gold/items), no risk.
- **Event card** — a narrative choice or automatic flavor text with a
  small, table-driven outcome (e.g., "A merchant offers a trade" →
  gold-for-item swap), resolved by rolling against the event's outcome
  table. Event cards exist to add narrative texture without requiring new
  gameplay systems; keep MVP event tables small (5–10 events per Region)
  and expand as content post-MVP.

### Deterministic resolution

Determinism is required so that (a) offline/idle progress can be computed
by fast-forwarding without replaying real time, and (b) results are
reproducible for testing and support/debugging. The approach:

1. At Expedition **start**, generate the full sequence of steps and roll
   *which* encounter occurs at each Encounter step, using a
   `RandomNumberGenerator` seeded from a per-Expedition seed. Store the
   seed and the generated step list in the save (not just the seed) so
   that changing the encounter-pool data later does not retroactively
   change an in-flight Expedition.
2. Do **not** wait for real-time ticks to "roll" outcomes; instead, each
   step's outcome (e.g., a combat's full round-by-round log) is *also*
   computed at start time, deterministically, from the same seed stream.
   This means the entire Expedition's result is known immediately after
   confirming — what changes over real time is only how much of the
   already-computed travel journal has been "revealed" to the player.
3. Resolve steps in order. On Defeat, or on Retreat when the Region marks
   Retreat as terminal, store that step as `TerminalStepIndex`, truncate all
   later generated steps, and set `EffectiveEndTimestamp` to that step's
   scheduled reveal time. No later rewards may exist or be revealed.
4. The Home/Status screen and Expedition Report simply compute
   `elapsed = now - StartTimestamp`, map that to a step index using each
   step's fixed duration slice, and reveal the journal up to that index.
   This makes idle/offline progress trivial: **resolution never depends
   on wall-clock ticking while the app is closed** (see
   [§11](#11-idle--offline-progress)).
5. This "resolve-at-start, reveal-over-time" design is the single most
   important architectural decision in the plan — it eliminates an entire
   class of offline-catch-up bugs and background-processing/battery
   concerns, at the cost of not supporting player interrupts mid-Expedition
   for MVP (a documented non-goal).

## 9. Auto-combat simulation design

Combat is resolved as a deterministic, round-based simulation (not
real-time physics), so it can run instantly at Expedition-start time
(per [§8](#8-expeditions-travel-encounters-outcomes-deterministic-resolution)).

### Turn order

All combatants (Party Heroes + enemy group for this encounter) are sorted
once per round by `Initiative` (derived from `Guile`, with a small seeded
random tiebreaker so identical Initiative doesn't always resolve in the
same order). Ties use the seeded RNG stream, not engine iteration order,
to preserve determinism across platforms.

### Per-turn action resolution (example formulas)

For a combatant taking its turn:

1. **Choose target** using the targeting rule from
   [§7](#7-party-formation-and-evaluation) (front row first for
   melee/short-range; any valid slot for ranged/magic), breaking ties by
   lowest current HP% among valid targets (finish off weak targets — a
   simple, legible AI policy for MVP).
2. **Hit chance:**
   ```
   HitChance = clamp(0.90 + (Attacker.Guile - Defender.Guile) * 0.01, 0.50, 0.99)
   ```
3. **Crit chance:**
   ```
   CritChance = clamp(0.05 + Attacker.CritChance, 0.0, 0.50)
   ```
4. **Damage (physical example, e.g. Knight/Ranger basic attack):**
   ```
   BaseDamage = Attacker.Attack * SkillMultiplier
   Mitigated  = max(1, BaseDamage - Defender.Defense)
   FinalDamage = Mitigated * (Attacker.rolled_crit ? 1.5 : 1.0)
   ```
5. **Damage (magic example, e.g. Wizard spell):**
   ```
   BaseDamage = Attacker.MagicPower * SkillMultiplier
   Mitigated  = BaseDamage * (1.0 - Defender.MagicResist)
   FinalDamage = Mitigated * (Attacker.rolled_crit ? 1.5 : 1.0)
   ```
6. **Healing (e.g. Cleric skill):**
   ```
   HealAmount = Attacker.Faith * SkillMultiplier
   ```
7. Apply `FinalDamage`/`HealAmount`, clamp HP to `[0, MaxHP]`, apply any
   status effects the skill carries (e.g., a debuff with a `Faith`-based
   resist check on the defender).
8. A combatant at `HP == 0` is removed from turn order for the remainder of
   the encounter (marked for Wounded/Defeat resolution at encounter end,
   not deleted from the simulation state, so combat logs remain complete).

### Encounter resolution loop

```
round := 1
while round <= MaxRounds and both sides have living members:
    for combatant in turn_order(round):
        if combatant.HP == 0: continue
        resolve_action(combatant)   # steps 1–8 above
    round += 1

outcome := Victory   if enemy side has 0 living members
           Defeat    if party side has 0 living members
           Stalemate/Retreat if MaxRounds reached (data-tunable per Region;
                     MVP default: treat as Retreat)
```

`MaxRounds` (e.g., 20) guarantees the simulation always terminates in
bounded time, which matters because it must run synchronously at
Expedition-start.

### Skill/ability design (MVP)

Give each class exactly **one** simple active skill beyond a basic attack
for MVP (e.g., Knight: "Guard" — reduces damage to self next turn; Wizard:
"Firebolt" — higher multiplier, single target; Cleric: "Mend" — heal
lowest-HP ally). A simple deterministic AI policy chooses skill vs. basic
attack (e.g., "use skill if off cooldown, else basic attack"). Keep the
skill roster minimal for MVP; expand skill variety as
[content expansion](adventurers-march/milestones/07-content-expansion.md).

## 10. Events, regions, equipment, progression

### Regions

A **Region** is a data-defined destination (`RegionResource`) containing:
recommended Party Power, available Expedition durations (e.g., Short/
Medium/Long), a travel-step count, an encounter pool (weighted table of
Combat/Loot/Event entries, each referencing enemy-group or event data), and
an unlock condition (e.g., "Company gold ≥ X" or "cleared Region Y"). MVP
ships with 2–3 hand-authored Regions (e.g., *Green Hollow* — easy forest,
*Ashen Reach* — medium desert/ruins, teaching different encounter mixes).
Procedural Region generation is an explicit post-MVP enhancement noted in
[non-goals](#3-mvp-scope-and-non-goals).

### Equipment

Items are `ItemResource` data: a slot (`Weapon` or `Armor`), a rarity tier,
and a flat set of stat modifiers (e.g., `+Attack`, `+Defense`). MVP keeps
one weapon slot and one armor slot per Hero and a simple inventory list (no
stacking limits needed at MVP scale). Crafting/enchanting are post-MVP
(non-goal).

### Progression

- **Hero XP/levels:** Heroes gain XP from completed Expeditions
  (proportional to Region difficulty and Expedition duration); leveling up
  increases derived stats per the class's growth curve
  ([§6](#6-heroes-classes-attributes-traits-status-generation)).
- **Company-level unlocks:** gold and completed-Region milestones unlock
  new Regions and increase roster cap.
- **Post-MVP progression hooks** (explicitly deferred, but the data model
  should not preclude them): permanent Company-wide bonuses ("legendary
  order" reincarnation bonuses), artifact items, expedition outposts,
  faction contracts — these were raised in the originating design
  brainstorm and are good candidates for
  [content expansion](adventurers-march/milestones/07-content-expansion.md).

## 11. Idle / offline progress

Because Expedition outcomes are fully resolved at start time
([§8](#8-expeditions-travel-encounters-outcomes-deterministic-resolution)),
"offline progress" requires no simulation catch-up loop — it is a pure
function of elapsed wall-clock time:

```
on_app_resume():
    for each active Expedition:
        elapsed = now_utc() - expedition.StartTimestamp
        revealed_step_index = min(len(expedition.Steps) - 1,
                                   floor(elapsed / expedition.StepDuration))
        if revealed_step_index > expedition.LastRevealedIndex:
            # Apply rewards/status changes and advance the cursor as one
            # mutation, persist it, then present the consolidated summary.
            newly_revealed = expedition.Steps[
                expedition.LastRevealedIndex+1 .. revealed_step_index]
            apply(newly_revealed)
            expedition.LastRevealedIndex = revealed_step_index
            SaveManager.save()
            display(newly_revealed)
        if revealed_step_index == len(expedition.Steps) - 1:
            finalize_expedition(expedition)  # move to Expedition Report
```

This runs both on normal app resume (`NOTIFICATION_APPLICATION_FOCUS_IN` /
`_notification` in Godot, or simply on `_ready()` of the Home screen) and
can also be safely called from a periodic `Timer` while the app is in the
foreground, so a session left open also naturally reveals progress without
special-casing. No background threads, background services, or
platform-specific background-execution APIs are required for MVP.

## 12. Save system

- **Format:** a single versioned save resource, serialized as JSON (human
  debuggable, straightforward to diff in tests) stored via
  `user://save.json` (Godot's per-platform user data directory, which maps
  to Android app-private storage — no extra permissions required).
- **Versioning:** every save includes a `save_version` integer. A
  `SaveManager` autoload owns a migration table (`version -> migration
  function`) so future saves can upgrade old data instead of resetting
  players' progress. MVP ships with `save_version = 1` and an explicit
  (even if initially empty) migration entry point, so the pattern exists
  before it's needed.
- **Contents:** Company roster (all Heroes + stats + status), current
  recruitment offers and their refresh seed, inventory, gold, unlocked
  Regions, active Expedition (including its pre-resolved, JSON-safe
  `Steps[]` dictionaries, `LastRevealedIndex`, `TerminalStepIndex`, and
  `EffectiveEndTimestamp`), and RNG seed state for future generation calls.
- **Cadence:** autosave after any state-mutating action (Hero recruited,
  Party formed, Expedition started, each revealed reward batch and cursor
  update, Expedition Report acknowledged, item equipped) and on app pause
  (`NOTIFICATION_APPLICATION_FOCUS_OUT` / `NOTIFICATION_WM_CLOSE_REQUEST`).
  Avoid saving on a fixed timer only — mobile OSes may terminate a
  backgrounded app without further notice, so save-on-mutation is required,
  not optional.
- **Corruption handling:** keep the previous save as a `.bak` before
  overwriting; if the primary fails to parse, fall back to `.bak` and log a
  warning (surface as a small non-blocking toast, not a hard crash).
- **No cloud save for MVP** (non-goal); the JSON format and version field
  are chosen specifically so cloud sync can be layered on later without a
  redesign.

## 13. Godot project architecture

Building on the existing minimal project (`project.godot`, `main.tscn`),
restructure toward a scalable, data-driven layout:

```
res://
├── project.godot
├── main.tscn                      # boots into the game's UI root
├── autoload/                      # Godot autoload singletons ("managers")
│   ├── GameState.gd               # current Company, gold, unlocked Regions
│   ├── SaveManager.gd             # load/save/migrate (see §12)
│   ├── ExpeditionManager.gd       # start/resolve/reveal Expeditions (§8, §11)
│   ├── CombatSimulator.gd         # pure combat resolution (§9); stateless
│   │                              #   given inputs, easy to unit test
│   └── UIManager.gd               # active-screen switching (§5)
├── data/                          # Resource (.tres) content — no logic
│   ├── classes/                  # HeroClassResource per class (§6)
│   ├── traits/                   # HeroTraitResource per trait (§6)
│   ├── items/                    # ItemResource per item (§10)
│   ├── regions/                  # RegionResource per Region (§10)
│   ├── encounters/                # enemy-group and event-table resources
│   └── balancing/                 # BalancingConfig (formula coefficients, §16)
├── scripts/
│   ├── models/                    # plain data classes: HeroData, PartyData,
│   │                              #   ExpeditionData, ItemData (RefCounted,
│   │                              #   not Node — easy to serialize/test)
│   └── systems/                   # HeroGenerator, PartyEvaluator,
│                                   #   RegionUnlockRules, etc. — pure logic
│                                   #   operating on models + data resources
├── scenes/
│   └── ui/
│       ├── home/
│       ├── roster/
│       ├── hero_detail/
│       ├── equipment/
│       ├── party_formation/
│       ├── region_select/
│       ├── expedition_report/
│       └── settings/
└── tests/                         # GUT or GdUnit4 test suites (see §19)
```

### Autoload managers (runtime flow)

- **GameState** — single source of truth for the current Company, gold,
  inventory, and unlocked Regions; other systems read/mutate through it
  rather than holding duplicate state.
- **SaveManager** — serializes `GameState` (+ `ExpeditionManager`'s active
  Expedition) to `user://save.json` and back; owns versioning/migration.
- **ExpeditionManager** — starts Expeditions (generates and fully resolves
  `Steps[]` using `CombatSimulator` and seeded RNG at start time, per §8),
  and on each `UIManager`-driven "check progress" call, reveals steps
  based on elapsed time (per §11).
- **CombatSimulator** — pure/stateless functions taking a Party snapshot,
  an enemy group definition, and a seed, returning a full round-by-round
  result. No Node dependencies, so it can be exercised directly in unit
  tests without a running scene tree.
- **UIManager** — swaps the visible screen under a single UI root scene
  (instantiate/free or show/hide child scenes under `main.tscn`), keeping
  navigation logic ([§5](#5-screen-and-navigation-plan)) out of individual
  screen scripts.

### Data-driven resources

Every piece of content (Hero classes, traits, items, Regions, encounter
tables, balancing coefficients) is a custom Godot `Resource` (`.tres`)
subclass with typed exported fields, editable directly in the Godot
editor's inspector. This keeps designers/content-authors out of GDScript
logic files and keeps `CombatSimulator`/`ExpeditionManager` generic across
however much content is added later — directly supporting the
[content expansion milestone](adventurers-march/milestones/07-content-expansion.md).

### Runtime flow (summary)

```
App boot (main.tscn)
  → SaveManager.load_or_create()
  → GameState populated
  → UIManager shows Home screen
       → ExpeditionManager.reveal_progress() runs once on boot and again
         on resume/focus-in, and periodically while foregrounded
  → player navigates via UIManager between screens (§5)
  → confirming a Party + Region calls ExpeditionManager.start_expedition(...)
       → resolves fully via CombatSimulator + seeded RNG (§8, §9)
       → SaveManager.save() (autosave on mutation, §12)
  → time passes (foreground or background)
  → ExpeditionManager.reveal_progress() surfaces newly completed steps
  → Expedition Report screen shown when fully revealed
```

## 14. UI and art direction

- **Style:** stylized 2D flat/painterly fantasy portraits and icons; the
  simulation nature of the game means most "action" is read from text/
  numbers/icons rather than animated combat, so art budget should prioritize
  **Hero portraits, class icons, item icons, and Region backdrops** over
  combat animation.
- **Combat/Expedition Report presentation:** present the pre-resolved
  combat log as a readable, scrollable log with small icon/portrait
  accents (e.g., a damage/heal icon per line) rather than real-time
  animated battle scenes — consistent with the "resolve-at-start" design
  ([§8](#8-expeditions-travel-encounters-outcomes-deterministic-resolution))
  and cheaper to produce.
- **Iconography:** consistent icon language for classes, status effects,
  item slots, and Region difficulty, reused across all screens.
- **Color:** limited, high-contrast palette per class/status for quick
  scanning of the roster grid; pair every color cue with an icon/label for
  accessibility (§2).
- **Post-MVP:** lightweight portrait animation (idle blink/breathing) and a
  simplified overworld map visualization for Region select.

## 15. Audio

- MVP: a short ambient loop for Home, a distinct ambient loop per Region
  during Expedition, simple UI SFX (tap, confirm, level-up, victory/
  defeat stingers), and a mute/volume toggle in Settings.
- Keep audio triggering decoupled from `CombatSimulator` (which is
  pure/stateless) — an `AudioManager` autoload should listen for/be called
  by `UIManager`/`ExpeditionManager` when presenting results, not from
  inside the simulation itself.
- Post-MVP: per-class combat SFX stingers, dynamic music layers tied to
  Region danger level.

## 16. Balancing

- All formula coefficients (damage multipliers, XP curves, Party Power
  weights, encounter odds) live in a single `BalancingConfig` `Resource`
  under `data/balancing/`, not scattered as magic numbers in scripts. This
  is the single place designers tune numbers without touching code.
- Maintain a simple internal balancing spreadsheet/table (can start as a
  markdown table in the relevant milestone doc) mapping Region difficulty
  tiers to recommended Party Power, so new Regions can be authored
  consistently.
- Use the deterministic simulator to script **balance simulations**: run
  `CombatSimulator` headlessly (via a test/tool script) across many seeded
  Parties vs. a given encounter to sanity-check win rates before shipping
  new content — this is a natural extension of the unit-test harness in
  [§19](#19-testing).
- Target win-rate guidance for MVP: a Party at or above a Region's
  recommended Power should win the majority of Combat encounters in that
  Region (~70–85%), while a Party notably under-leveled should lose
  more often than not — tune `BalancingConfig` to hit these bands using the
  balance-simulation approach above.

## 17. Monetization considerations

No store integration is required for MVP (non-goal, §3). For future
consideration, once the core loop is validated:

- **Non-intrusive options that fit the idle genre:** an optional "speed up
  current Expedition" consumable, cosmetic Hero portrait variants, or an
  optional ad-supported "instant reveal" for an in-progress Expedition.
- **Avoid** anything that undermines the "legible simulation" pillar (§1),
  e.g., pay-to-win stat boosts that break the Party Power ↔ outcome
  relationship players learn to read.
- Any monetization work should be isolated behind a small `StoreManager`
  interface (autoload) so it can be added without touching
  `CombatSimulator`/`ExpeditionManager` internals.

## 18. Analytics

- MVP does not require a third-party analytics SDK (avoid adding new
  dependencies without cause). If/when adopted, prefer event logging
  through a single `AnalyticsManager` autoload with a small, stable event
  vocabulary: `expedition_started`, `expedition_completed`,
  `hero_recruited`, `hero_leveled_up`, `party_formed`, `region_unlocked`.
- Keep event payloads free of personally identifiable information.
- Local-only debug logging (e.g., `print`/a simple log file under
  `user://`) is sufficient for MVP development and QA.

## 19. Testing

- **Unit tests** for pure logic: `CombatSimulator` (given a fixed seed,
  Party, and enemy group, assert an exact expected outcome/log — this is
  possible precisely because combat is deterministic, §9), `HeroGenerator`
  (given a seed, assert exact generated Hero), `PartyEvaluator`
  (Party Power formula), and `SaveManager` migrations (load an old-version
  fixture, assert migrated shape).
- Use a Godot-native test framework such as **GUT (Gut Unit Test)** or
  **GdUnit4** under `tests/`, run headlessly via
  `godot --headless --path . -s addons/gut/gut_cmdln.gd` (or the
  equivalent GdUnit4 CLI invocation) so tests can run in CI alongside the
  existing Android export workflow.
- **Integration/manual test checklist** for UI flows (documented per
  milestone) since full UI automation is not required for MVP.
- **Determinism regression test:** run the same Expedition seed twice and
  assert byte-identical resolved `Steps[]`, guarding the core architectural
  guarantee in §8.
- Testing requirements are broken down per milestone in the
  [milestone plans](adventurers-march/milestones/).

## 20. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Combat feels "unwatchable"/opaque since it's pre-resolved | Player disengagement | Present a clear, well-formatted travel journal/combat log (§14); keep formulas simple and consistent so outcomes feel fair |
| Balancing drift as content grows | Regions become trivial or unfair | Centralize coefficients in `BalancingConfig`; use scripted balance simulations (§16) before adding new Regions |
| Offline-progress edge cases (clock changes, long absences) | Incorrect rewards, exploits | Clamp `elapsed` to a sane maximum when computing revealed steps; use monotonic-safe UTC timestamps; cover with tests (§19) |
| Scope creep beyond MVP (factions, crafting, procedural regions) | Delayed first playable | Explicit non-goals list (§3); milestones checklist enforces order |
| Save corruption / data loss on device | Player frustration, poor reviews | `.bak` fallback, versioned migrations (§12) |
| Godot mobile export/build regressions | Broken releases | Keep relying on the existing CI workflow (`.github/workflows/android-apk.yml`) and its debug-export smoke test; extend it to run headless unit tests before export |

## 21. Release preparation

- Extend the existing `.github/workflows/android-apk.yml` CI (which already
  builds a debug APK on push/PR) to also run the headless unit test suite
  (§19) before export, failing the build on test failure.
- Before a public/store release: switch to a signed release export preset
  (the current preset is debug-only per `export_presets.cfg`), pick a real
  package identifier (replacing the placeholder
  `com.example.helloworld`), and produce store assets (icon, feature
  graphic, screenshots of the core screens).
- Perform a full manual playtest across the entire
  [core gameplay loop](#4-core-gameplay-loop) on at least one physical
  Android device, including a real backgrounding/offline-progress check
  (start an Expedition, close the app, reopen after the Expedition's
  duration has elapsed, verify the report is correct).
- Confirm save-file resilience: manually corrupt `user://save.json` in a
  test build and verify the `.bak` fallback path (§12) works.

## 22. First playable vertical slice and build order

The **first playable vertical slice** proves the entire core loop
end-to-end with minimal content, before investing in additional Regions,
classes, or polish:

- 1 Region ("Green Hollow"), 1 Expedition duration option, ~5 travel steps.
- 4 Hero classes, a starting roster of 4 pre-generated Heroes (one per
  class), plus deterministic gold-priced recruitment offers in the Company
  Roster.
- 1 Party of up to 4 Heroes, both formation rows usable.
- Deterministic combat against 1–2 simple enemy-group definitions.
- Full save/load of roster + one active/completed Expedition.
- Screens: Home, Party Formation, Region Select (single Region), Expedition
  Report. (Company Roster/Hero Detail/Equipment/Settings can be minimal
  stubs for the slice and fleshed out in subsequent milestones.)

Recommended build order (matching the
[milestones checklist](adventurers-march-milestones.md), most-dependent
work last):

1. **Technical foundation** — project structure, autoloads, base data
   Resource classes, empty screen scenes wired through `UIManager`.
2. **Hero roster** — `HeroClassResource`/`HeroTraitResource` data, Hero
   generation/recruitment, save/load, Company Roster + Hero Detail screens.
3. **Party formation** — formation UI, Party Power evaluation.
4. **First expedition** — `RegionResource` for Green Hollow,
   `ExpeditionManager` start/resolve/reveal pipeline (non-combat steps
   only, to validate the idle/offline design first).
5. **Combat simulation** — `CombatSimulator`, enemy-group data, wiring
   Combat encounter steps into the Expedition pipeline.
6. **Progression and equipment** — XP/leveling, item resources, Equipment
   screen.
7. **Content expansion** — additional Regions, traits, events, skills.
8. **Presentation pass** — art/audio integration, UI polish, accessibility
   pass.
9. **Testing and release preparation** — full test suite, CI hardening,
   store-ready export, manual device playtest.

Each of these has a dedicated, expanded plan in
[`adventurers-march/milestones/`](adventurers-march/milestones/); start
with
[01-technical-foundation.md](adventurers-march/milestones/01-technical-foundation.md).
