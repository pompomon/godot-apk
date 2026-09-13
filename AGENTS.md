# Agent implementation guidelines

This is the shared entry point for coding agents. Keep work bounded and
recoverable; follow the requested scope rather than implementing an entire
milestone by default. The [README](README.md) owns setup, validation commands,
and architecture; the [milestone checklist](docs/adventurers-march-milestones.md)
and linked milestone details own requirements and acceptance evidence.

## Before editing: scope and baseline

- Classify the current request as investigation/planning, implementation, or
  visual/device acceptance. Planning does not authorize edits. Distinguish the
  latest requested action from historical PR comments; read the referenced
  decision and necessary evidence, not the entire discussion by default.
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
- For work requiring game validation, check the
  [toolchain preflight](README.md#cloud-agent-environment) before editing.
  Setup can fail and still leave the agent running; report missing tools rather
  than assuming a ready environment or weakening validation.
- Resolve decisions affecting persistence or public interfaces before coding.
  Split large work into independently validated tasks or PRs, keeping existing
  gameplay usable at each boundary. A split does not expand authorized scope.

**Gate:** state the bounded deliverable and its acceptance criteria before edits.

## Visual evidence and fresh tasks

Separate screenshot-heavy investigation from implementation:

1. Use a bounded, read-only visual investigation task. Inspect only the images
   needed for the current diagnostic question, without concurrent implementation.
2. Record a textual handoff in the normal discussion before implementation:
   source comment, tested commit/APK run, screen and reproduction steps, device
   and display configuration, diagnostic mode, exact observed markers,
   observations versus hypotheses, bounded fix, acceptance criteria, and missing
   evidence. Do not embed the images again in the handoff.
3. Start implementation as a fresh task using that text and the published
   revision. A follow-up comment, subagent, or restored session is not proof of
   clean history. If the platform does not expose fresh context, state that
   limitation and ask the maintainer to start a separate task; do not promise
   that a text-only follow-up removed earlier media.

For generated previews, publish the implementation and validation checkpoint
before handing off to a separate visual-review task. Keep visual and device
acceptance unverified until actually performed.

- A local download or successful image tool call does not establish that the
  model service can retrieve or ingest the image on subsequent requests.
- After an attachment-fetch or MIME failure, do not repeatedly try the same
  media through different models, browsers, URL rewrites, or network bypasses.
  If still able to respond, request a fresh supported attachment or a textual
  diagnostic transcription; after a fatal session error, use the recovery
  procedure below in a fresh task.
- Never claim inaccessible media was inspected or infer a game defect from a
  media-service failure. Attribute user-provided transcriptions as such.
- Do not commit screenshots or private diagnostic data just to make them
  accessible, and do not upload private evidence to third-party services.

**Gate:** implementation starts from a recoverable textual diagnostic contract,
not a dependency on reloading historical attachments.

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

### Android layout stability

- Company Roster and Party Formation use plain `MarginContainer` nodes with
  their authored margins. Do not attach `ScreenMargin` or mutate their theme
  margins at runtime without new matching device evidence. On 2026-09-10, the
  user reported that both Fold 4 displays hid idle Hero rows in dynamic modes
  A–C while static-margin mode D showed them consistently.
- Other screens retain `ScreenMargin`. Never connect a `Control`'s own
  `resized` signal to code that mutates its theme margins. The helper coalesces
  viewport and resume requests into one deferred update, ignores
  detached/re-entrant work, skips unchanged values, and applies all four
  constants in one bulk theme override.
- For foldable safe-area changes, device acceptance covers both displays plus
  fold/unfold, background/resume, scrolling, and Back/Cancel. Headless layout
  checks and a successful APK export remain separate evidence.

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
following in normal publication updates, not only the final assistant response:

- Published revision, completed scope, and remaining changes.
- Validation owner, tested revision (identify any uncommitted diff), actual
  command outcomes and GUT summaries, and relevant export/artifact evidence.
- Local validation, matching-revision CI, and device acceptance as separate
  statuses; include unrun checks, blockers, and the next bounded action.
- Security-check results and limitations. For example, CodeQL reporting no
  supported languages is not a successful GDScript security analysis.

Confirm the commit exists remotely before treating work as recoverable; never
rely on emergency error-time publication. A failed session does not imply its
earlier published implementation was lost.

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
   broad review, optional visual investigation, or subsystem implementation
   during closeout.

## Classify failures before recovery

For CI investigation, first list recent workflow runs, then inspect relevant
job logs and the tested revision. Select the remedy from the actual failure:

| Failure | Required response |
|---|---|
| Parser, GUT, or export failure | Inspect the failing command and earliest error; fix the relevant regression and repeat affected checks. |
| Agent content-fetch or image MIME error | Preserve/verify the published checkpoint and request fresh textual context; do not change game code or extend the Android timeout to fix a service error. |
| Runner firewall restriction | Identify the blocked destination and ask for narrowly scoped maintainer action if necessary; do not disable protections. Runner access does not prove provider-side access. |
| `action_required`, cancelled, or otherwise unexecuted CI | Report the exact status and required approval/action, not a test result; do not poll indefinitely. |
| Managed session deadline | Stop dependent work, preserve the existing closeout reserve, and publish an honest incomplete handoff before shutdown. |

After a fatal error, the next task verifies the remote commit and inspects the
remaining diff before resuming. Recover published work rather than implementing
it again; identify missing validation and missing final communication separately.
Leave device acceptance unchecked until performed.

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

On 2026-09-09, [run 34373765801](https://github.com/pompomon/godot-apk/actions/runs/34373765801/job/102541251614)
failed with `CAPIError: 400 Unable to download content from the provided URL
before the timeout`, after [commit 663a036](https://github.com/pompomon/godot-apk/commit/663a0362bcde4999caec2d0661439c9d8d916ad6)
had been published. It restored session history; the visible tools immediately
before failure were repository verification and CodeQL, not image inspection.
The failing URL was not identified, so historical media involvement remains a
hypothesis. [Run 34368747542](https://github.com/pompomon/godot-apk/actions/runs/34368747542)
separately reported `validating image item: image media type is required` and
attachment-host firewall blocks. These are distinct from the earlier deadline
failures. Fresh tasks and checkpoints reduce exposure and recovery cost; they
cannot guarantee elimination of managed-runtime failures.

For maintainer escalation, provide the run/job links, error signature, request
ID, relevant timestamps, resumed-session status, and last verified remote commit
to GitHub Support. Exclude credentials, private attachments, and unredacted
diagnostics. Do not identify a blocked runner host as the failing provider URL
without evidence or file an external report without authorization.
