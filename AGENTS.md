# Agent implementation guidelines

This is the shared entry point for coding agents. Keep work bounded and
recoverable; follow the requested scope rather than implementing an entire
milestone by default. The [README](README.md) owns setup, validation commands,
and architecture; the [milestone checklist](docs/adventurers-march-milestones.md)
and linked milestone details own requirements and acceptance evidence.

## Before editing: scope and baseline

- Identify the deliverable, exclusions, acceptance criteria, and relevant
  interfaces and regression tests. Read milestone evidence: an unchecked box
  may mean device acceptance is pending, not that implementation is missing.
- Inspect the current revision, working-tree changes, and last successfully
  published checkpoint. On resumption, inspect the remaining diff first;
  do not assume the previous session's final edits reached GitHub or restart
  the whole milestone.
- Establish applicable baseline validation and record existing failures
  separately from new ones. For documentation-only changes, review links,
  consistency, and whitespace; gameplay tests/export are unnecessary unless
  documentation-specific checks require them.
- Resolve decisions affecting persistence or public interfaces before coding.
  Split large work into independently validated tasks or PRs, keeping existing
  gameplay usable at each boundary. A split does not expand authorized scope.

**Gate:** state the bounded deliverable and its acceptance criteria before edits.

## Agree contracts before parallel work

Identify input/output types, required dictionary keys and numeric encodings,
ownership, mutation permissions, error signaling, and save-version/migration
implications. Map every producer, validator, serializer, and consumer, including
UI and tests. Resolve disagreements in the owning milestone specification;
do not let workers invent competing interfaces.

For Combat, use the [contract decisions and delivery slices](docs/adventurers-march/milestones/05-combat-simulation.md#bounded-delivery-and-integration-gates).
Account for serialized log size against `SaveManager.MAX_SAVE_BYTES` before
integration, not only after a generated Expedition fails to save.

**Gate:** integrate a contract change only when all affected consumers and tests
are accounted for.

## Delegate with explicit ownership

- Give each worker a concrete deliverable, allowed files, exclusions, agreed
  contracts, and acceptance checks. Assign one writer to each shared integration
  file, especially persistence, orchestration, models, and balancing assets.
- Parallelize independent work only. Do not edit a worker's files concurrently.
  Use bounded searches and scoped reviews rather than repeated whole-repository
  investigations.
- Assign one validation owner for the integrated revision. Require worker
  handoffs to identify changed files, actual validation results, assumptions,
  and blockers; accept completed delegated validation rather than duplicating
  identical runs. If the integrated revision changes, assign validation of
  that new revision explicitly.
- Obtain confirmation that every delegated writer has stopped before final
  publication. A summary alone is not confirmation; outstanding workers or
  messages can reopen work.

**Gate:** no final checkpoint while delegated writers can still change it.

## Preserve repository invariants

The [architecture boundaries](README.md#architecture-boundaries) are authoritative:

- Simulation consumes detached inputs, without live scene state, clocks, or
  global RNG. [Expedition generation](scripts/systems/expedition_generator.gd)
  selects all encounters before resolving outcomes with the same seeded stream.
  Terminal truncation never changes the original persisted step duration.
- Frozen saves contain JSON-safe values; never reroll results or recompute
  historical values from current content. Preserve the eight-byte hex encoding
  of `Evasion` and `CritChance` in
  [ExpeditionPartySnapshot](scripts/models/expedition_party_snapshot.gd).
- [ExpeditionManager](autoload/ExpeditionManager.gd) solely owns Expeditions.
  Persist rewards, cursor, clock accounting, and Hero statuses together before
  presenting success.
- [SaveManager](autoload/SaveManager.gd)'s `save()` is void. Roll back only before
  `last_committed`; post-commit warnings must not undo saved changes. Extend
  [GameState checkpoints](autoload/GameState.gd) when adding mutable
  transactional fields, retaining canonical Hero identity.
- Extend the [existing balancing asset](data/balancing/default_balancing.tres)
  rather than replacing unrelated values. Keep global gameplay coefficients
  there and class-specific bases, weights, and growth on Hero class Resources.
- Navigate through [UIManager](autoload/UIManager.gd); root binding is
  bootstrap-only. Respect deferred navigation and stale-root rejection; UI
  tests await a process frame before inspecting the destination.

## Validate incrementally; preserve regression coverage

Use the existing [test instructions](README.md#run-the-tests) and
[Android export instructions](README.md#build-the-android-apk), with their
documented toolchain. For gameplay changes, the validation owner performs:

1. Clean Godot import to discover Resource and GUT classes.
2. Focused tests for the changed behavior.
3. The full GUT suite on the integrated revision.
4. Android debug export and verification of a nonempty APK.

Do not add alternative test runners or weaken existing gates.

- Keep both [.gutconfig.json](.gutconfig.json) hooks enabled. Test storage must
  remain isolated; derive save paths from `SaveManager.get_save_path()` and keep
  autoload initialization I/O-free. Restore touched singleton state, clocks,
  and shared Resources between cases.
- Inspect process exit status and GUT summaries, not merely tool-call success.
  Empty discovery and skipped/unparseable scripts are failures. Distinguish
  intentional Godot warnings in negative tests from GUT warnings/errors.
- Fix the earliest parser or contract error before chasing cascading failures.
  Preserve noncombat regression coverage with controlled fixtures when authored
  content changes. Change assertions only for intentional contract changes;
  do not delete unrelated tests or broadly relax expectations.
- Use existing tests for diagnostics. Keep temporary logs outside the checkout,
  and do not leave disposable probe scripts in test discovery.
- Record the tested revision, checks, results, and unrun checks. Keep local
  validation, CI, and physical-device acceptance distinct.

**Gate:** each slice carries evidence before the next dependent slice starts.

## Checkpoint and close out deliberately

Publish at coherent, validated boundaries using the session's approved
commit/publish tools. Label incomplete checkpoints honestly. Include the
published revision, completed scope, validation evidence, blockers, and next
bounded action in the handoff. Confirm publication succeeded before treating
work as recoverable; never rely on emergency timeout-saving.

At task start, account for the session's runtime limit and reserve capacity for
closeout. Reassess at each checkpoint. If the next slice would consume that
reserve, stop and publish an incomplete handoff rather than starting it.

1. Freeze scope and stop or await delegated writers, obtaining acknowledgment.
2. Resolve localized blocking findings or explicitly report them as incomplete.
3. Complete applicable validation and required security checks; scan all changed
   files for secrets before any commit.
4. Publish and verify the checkpoint, completing any required post-commit checks.
   If a blocking fix is needed, repeat the affected checks and publication.
5. Report completion or an honest incomplete handoff. Do not launch another
   broad review or subsystem implementation during closeout.

For CI investigation, inspect recent workflow runs and the relevant job logs.
Distinguish `failure`, `cancelled`, and `action_required`; report approval/action
blockers instead of repeatedly waiting or claiming CI passed. Leave device
acceptance unchecked until it is actually performed.

### Why these gates exist

On 2026-09-06, [the initial Combat session](https://github.com/pompomon/godot-apk/actions/runs/34044906767/job/101518126054)
and [its continuation](https://github.com/pompomon/godot-apk/actions/runs/34056127393/job/101548248189)
both logged `Timeout after 3540000ms waiting for session.idle` at the 59-minute
limit, followed by emergency-push failures. Earlier checkpoints existed, but
work continued afterward. The Git proxy stopped before those push failures;
a shutdown-order issue is plausible, not a proven Git root cause.
The associated [Android run](https://github.com/pompomon/godot-apk/actions/runs/34058801445)
was `action_required`, not proof of test success or failure. Tool-call success
also does not establish assertion results. Bounded scope, stopped writers,
verified checkpoints, and evidence-based handoffs address these risks;
increasing the Android workflow timeout would not fix the managed session's
shutdown behavior.
