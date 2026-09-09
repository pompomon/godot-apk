# Player-experience review rubric

Apply only the dimensions and journeys affected by the PR. The questions below
guide investigation; they are not a checklist of mandatory new features.
Consult current code and the owning milestone before treating an omission as
a defect. Preserve the design pillars of preparation over reflexes, legible
simulation, idle-friendly sessions, and consistent terminology.

## Authoritative references

- [Product goals and design pillars](../../../../docs/adventurers-march-implementation-plan.md#1-product-definition-and-design-goals)
- [Mobile UX constraints](../../../../docs/adventurers-march-implementation-plan.md#2-target-platform-and-mobile-ux-constraints)
- [Core loop](../../../../docs/adventurers-march-implementation-plan.md#4-core-gameplay-loop)
  and [screen/navigation plan](../../../../docs/adventurers-march-implementation-plan.md#5-screen-and-navigation-plan)
- [UI/art direction](../../../../docs/adventurers-march-implementation-plan.md#14-ui-and-art-direction),
  [audio](../../../../docs/adventurers-march-implementation-plan.md#15-audio), and
  [balancing](../../../../docs/adventurers-march-implementation-plan.md#16-balancing)
- [Milestone status and linked acceptance evidence](../../../../docs/adventurers-march-milestones.md)
  and [presentation acceptance](../../../../docs/adventurers-march/milestones/08-presentation-pass.md#acceptance-criteria)
- [Architecture boundaries](../../../../README.md#architecture-boundaries)
  and [contributor gates](../../../../AGENTS.md)

Do not freeze current prices, durations, save versions, win rates, milestone
completion, or device results here. Read their current authoritative sources.

## Quality dimensions

### Gameplay decisions and pacing

- Does the change preserve preparation-based choices rather than demand precise
  timing, repeated taps, or constant attendance?
- Are class, formation, equipment, and destination trade-offs understandable
  wherever those systems are implemented? Can a player find the next useful
  action after success, defeat, or a blocked action?
- Does the affected loop still support a brief check-in as well as a longer
  management session, without needless navigation or punishing absence?
- For balance/resource changes, trace the effect through derived stats, Party
  Power, simulation, rewards/recovery, and displayed guidance. Compare with
  documented intent and applicable multi-seed simulation evidence.
- Do not call a change balanced or unbalanced from one lucky/unlucky outcome.
  Missing balance evidence is a validation gap, not an invented win-rate defect.

### Cohesive information

- Use Company, Hero, Party, Expedition, and Region consistently with the design.
  Report terminology inconsistencies when they confuse an action or concept,
  not as a repository-wide capitalization cleanup.
- Compare status, gold, costs, Party Power, durations, and outcomes across Home,
  Roster, Detail, Formation, Region Select, and Report as applicable.
- Confirm units, rounding, and percentage presentation match the domain values.
  A UI must not silently duplicate or diverge from domain calculations.
- Check unavailable states and explanations, stale selections, missing Heroes,
  empty lists, full capacity, and insufficient resources.

### Navigation and player control

- Are the primary action, disabled reason, and recovery path discoverable without
  hover? Do Back, Cancel, Confirm, Disband, and acknowledgment mean what they say?
- Preserve a scene-local Party draft until confirmation; cancellation, Android
  Back, and background saves must not commit or discard the old confirmed Party.
- Trace deferred navigation through
  [UIManager](../../../../autoload/UIManager.gd). Outgoing screens and stale
  callbacks must not redirect the player or commit repeated transactions.
- Check touch versus scrolling, repeated activation, and whether a failed
  operation leaves the intended selection available for retry.

### Legible outcomes

- Recommended Party Power is advisory, not a guaranteed outcome or an unintended
  dispatch requirement. Legal partial or back-row-only Parties must not become
  invalid without an intentional contract change.
- Check that players can understand Victory, Retreat, Defeat, damage, misses,
  critical hits, Guard, and healing. Healing power is not necessarily HP restored.
- Inspect both rendered journals and surrounding progress/countdown UI for
  disclosure of unrevealed outcomes or a future terminal step.
- Historical reports must use frozen names and values, not today's content or
  a rerun of simulation. Verify continued legibility after reload/retuning.

### Progress and player trust

- Trace mutations through the existing save boundary. `SaveManager.save()` is
  void; `last_committed` distinguishes a committed result from a pre-commit
  failure. Post-commit warnings must not reverse saved state.
- Rewards, reveal cursor, clock accounting, and Hero status must agree with
  what the UI presents. Inspect failed-save feedback and retry behavior.
- Avoid lost/duplicate rewards and misleading claim buttons when rewards were
  already credited. Leaving a report must not silently acknowledge it.
- Inspect recovery availability across Roster, Detail, and Formation on
  foreground observations, resume, restart, and failed saves. Respect the
  current milestone's recovery contract rather than invent a new timer policy.
- Check migration/backup behavior when affected: old progress must remain
  understandable and recoverable without rerolling historical results.

### Mobile usability and accessibility

- Inspect [project settings](../../../../project.godot), scene layouts, shared
  helpers, and dynamically generated controls. Preserve portrait and touch-first
  behavior; no required hover, multi-touch, or precisely timed drag gestures.
- Check long names, dense logs, narrow/tall displays, wrapping, vertical scroll,
  focus visibility, and controls obscured by screen edges or system UI.
- Audit effective touch areas on exported Android builds at target densities:
  the product requires at least **48×48 dp**. A Godot `custom_minimum_size` in
  viewport pixels does **not** establish dp compliance.
- Review readable typography, contrast in normal/disabled/selected states, and
  icon/text alternatives to color-only status information. Do not invent
  numeric contrast thresholds absent an agreed accessibility standard.
- Separate source/layout risks from observed device failures. Request the
  affected screen/state and density measurements when evidence is missing.

### Presentation cohesion

- Compare information hierarchy, spacing, typography, status language, and
  icon meanings against [HeroUI](../../../../scenes/ui/hero_ui.gd) and neighboring
  scenes, including intentional scene-specific overrides.
- Assess whether feedback acknowledges the player's action and clearly explains
  what happened and what to do next, without distracting from the primary task.
- Apply final art, consistent audio cues, and functional volume/mute expectations
  when they are in scope. Do not flag agreed placeholders or deferred Settings
  features as defects in an unrelated gameplay PR.
- A presentation-only milestone must preserve gameplay contracts. Suggest
  separate bounded work for design improvements outside the PR's intent.

### Responsiveness

- Trace changes that could stall dispatch, add heavy per-frame work, rebuild a
  long journal, reset scroll/focus, or repeatedly refresh unchanged controls.
- Report a demonstrated interaction disruption as a defect; label an unmeasured
  performance concern as a hypothesis requiring profiling.
- Source inspection and successful export do not prove frame rate, battery use,
  native lifecycle behavior, or that the experience feels rewarding.

## Player journeys and source/test map

Use these as entry points, following dependencies only as the diff requires.
Test files establish existing assertions, not proof that the reviewed revision
passed them.

| Journey | Important states | Source entry points | Existing regression coverage |
|---|---|---|---|
| Inspect and recruit | Stable Hero selection; insufficient gold; full roster; empty/stale offers; save failure and retry; successful purchase; long content; swipe versus tap. | [Roster](../../../../scenes/ui/roster/roster_screen.gd), [Hero Detail](../../../../scenes/ui/hero_detail/hero_detail_screen.gd), [recruitment service](../../../../scripts/systems/recruitment_service.gd) | [Roster UI](../../../../tests/test_roster_ui.gd), [recruitment](../../../../tests/test_recruitment.gd), [Hero stats](../../../../tests/test_hero_stats.gd) |
| Form and revise a Party | Empty/partial formations; unavailable Heroes; occupied slots; live Power; Confirm/Cancel/Disband; Android Back; backgrounding; failed saves. | [Formation UI](../../../../scenes/ui/party_formation/party_formation_screen.gd), [formation service](../../../../scripts/systems/party_formation_service.gd), [Party evaluator](../../../../scripts/systems/party_evaluator.gd) | [Party UI](../../../../tests/test_party_ui.gd), [Party evaluator](../../../../tests/test_party_evaluator.gd), [Party persistence](../../../../tests/test_party_persistence.gd) |
| Dispatch and observe | Missing/stale Party; advisory difficulty; duration; retry; repeated activation; off-Home observations; pause/resume; no future-result disclosure. | [Home](../../../../scenes/ui/home/home_screen.gd), [Region Select](../../../../scenes/ui/region_select/region_select_screen.gd), [ExpeditionManager](../../../../autoload/ExpeditionManager.gd), [generator](../../../../scripts/systems/expedition_generator.gd) | [Expedition UI](../../../../tests/test_expedition_ui.gd), [Expedition manager](../../../../tests/test_expedition_manager.gd), [combat generation](../../../../tests/test_combat_expedition_generator.gd) |
| Read results and continue | Partial journals; Victory/Retreat/Defeat; healing wording; retained report; acknowledgment; restart; recovery; return to formation. | [Report](../../../../scenes/ui/expedition_report/expedition_report_screen.gd), [Expedition model](../../../../scripts/models/expedition_data.gd), [SaveManager](../../../../autoload/SaveManager.gd), [CombatResult](../../../../scripts/models/combat_result.gd) | [Expedition UI](../../../../tests/test_expedition_ui.gd), [combat persistence](../../../../tests/test_combat_persistence.gd), [save recovery](../../../../tests/test_save_manager.gd) |

As equipment, progression, additional Regions, and Settings implementations
land, inspect their owning milestones and current tests, and include the
corresponding journeys when affected. Do not infer availability merely from a
placeholder directory or schema field. Propose updating this map when entry
points change; the review itself remains read-only.

## Calibration and rollout

This section is a **maintainer procedure**, not authorization for the reviewer
to modify fixtures, request reviews, trigger workflows, or change settings.

### Instruction-package checks

- Check `SKILL.md` naming, matching lowercase/hyphenated `name`, nonempty
  review-focused `description`, valid YAML frontmatter, and local links/anchors.
- Check that discovery includes systems and Resources, not only scene changes;
  the discovery instruction must remain explicitly review-only.
- Check consistency with AGENTS, the README, owning milestones, and current
  source/test entry points. Do not add dependencies or a validation harness.
- Review documentation whitespace and links. No gameplay tests or APK export
  are needed for an instruction-only revision.

### Calibration cases

These are hypothetical review inputs, not current bug reports or executed
tests. Use existing regression cases as expectations; do not inject defects
into production code or weaken tests just to exercise the skill.

| Review input | Expected response |
|---|---|
| A roster input change makes a swipe activate recruitment. | Defect: trace accidental gold spend and Hero purchase, cite the changed handler and `test_touch_swipes_scroll_without_activation_and_taps_still_recruit` in Roster UI tests. |
| Party cancellation saves the edited draft, or a post-commit warning rolls it back. | Defect: explain the changed Cancel/commit semantics and consequences across Home/Roster/reload; use Party UI cancellation and post-commit tests. |
| Report progress reveals a terminal outcome before its step commits. | Defect: include the countdown/progress disclosure, not just log text; use `test_terminal_combat_is_hidden_until_committed_and_saved_log_survives_retuning`. |
| A non-UI recovery change refreshes availability before saving; saving can fail. | Defect: follow status into Roster, Detail, and Formation; use `test_recovery_refreshes_roster_detail_and_party_draft_only_after_commit`. |
| Balance coefficients change with no matching simulation evidence. | Trace affected choices and guidance; request relevant multi-seed evidence. Do not invent win rates or declare the change unbalanced from one outcome. |
| Harmless formatting or equivalent presentation refactoring. | No fabricated player-impact defect and no unsolicited whole-game audit. |
| An unrelated PR retains placeholders explicitly deferred by its milestone. | No demand to implement the future feature or complete the presentation milestone. |
| A UI change has headless layout tests but no Android capture/density evidence. | Relevant native visual, touch-size, and lifecycle checks remain unverified; no claim that viewport pixels prove dp compliance. |
| An old successful CI run or screenshot accompanies a new head revision. | Identify the mismatch and request current evidence rather than report a pass. |
| A supplied screenshot cannot be accessed. | State that it was not inspected; request a supported replacement or attributed transcription, and leave visual acceptance unverified. |
| Attachment ingestion reports a content-fetch or image MIME error. | Apply AGENTS' media-failure policy; do not infer a game defect, retry through alternative models/tools, or assume a follow-up clears historical media. Hand off text to a fresh task if recovery is needed. |
| An optional simplification could shorten a journey, but existing behavior meets the contract. | A bounded, non-blocking design improvement, separate from defects and tied to the short-session design goal. |

### Live GitHub pilot

1. On a PR whose head contains this skill, manually request Copilot review.
   Reference affected journeys and relevant evidence in the PR description.
   Include representative roster, Party, Expedition, non-UI, and no-defect cases
   across pilot reviews without introducing deliberately broken gameplay.
2. Record the head SHA, review URL, covered cases, expected versus actual
   findings, false positives, and missed player consequences in the PR
   discussion. A local instruction read-through is not a hosted review.
3. Verify actual skill use through comment attributions or available review
   session evidence. A completed review request or lack of comments alone does
   not prove invocation; record invocation as unverified if evidence is absent.
4. Accept the pilot only when findings connect changes to player impact, include
   indirect cross-screen effects, avoid deferred-feature false positives, and
   accurately disclose missing device evidence. Tune instructions if needed and
   re-review before treating calibration as complete.
5. If a PR, permissions, or session evidence is unavailable, leave the live pilot
   pending with that blocker and the next action. Do not claim acceptance.
   Decide whether to enable automatic reviews separately after the pilot;
   neither this skill nor its discovery instruction creates a merge gate.

GitHub documents [review skills, MCP context, and head-branch loading](https://docs.github.com/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review?tool=webui#mcp-servers-and-agent-skills)
and [skill authoring and discovery](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills).
Discovery is relevance-based: installing the files alone is not a passed pilot.
