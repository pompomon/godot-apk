# Milestone 9 — Testing and Release Preparation

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Bring the project to release-ready quality: complete automated test
coverage of core systems, CI enforcement of that coverage, a full manual
device playtest, and a signed, store-ready Android build.

## Scope

**In scope:** unit-test coverage completion for
`CombatSimulator`/`HeroGenerator`/`PartyEvaluator`/`SaveManager`
migrations, CI workflow extension to run tests before export, full manual
playtest (including offline progress and save-corruption fallback),
release export preset and store asset preparation.

**Out of scope:** any new gameplay features or content (this milestone is
hardening and release logistics only).

## Prerequisites / dependencies

- Milestone 8 (Presentation pass): the build must be feature-complete and
  visually/audibly finished before investing in release logistics.

## Tasks

1. Audit existing unit tests from Milestones 1–7 and fill gaps so that
   `CombatSimulator`, `HeroGenerator`, `PartyEvaluator`, and
   `SaveManager` migrations each have tests covering their documented
   acceptance criteria from their respective milestone files, per
   [plan §19](../../adventurers-march-implementation-plan.md#19-testing).
2. Add a determinism regression test (if not already added in Milestone
   4) that runs a full Expedition — including Combat steps — twice from
   the same seed and asserts byte-identical resolved results end-to-end.
3. Extend `.github/workflows/android-apk.yml` (or add a sibling job/
   workflow) to run the headless test suite
   (`godot --headless --path . -s <test-runner-entrypoint>`) as a required
   step **before** the export step, failing the workflow on any test
   failure.
4. Prepare a release export preset in `export_presets.cfg`: a real package
   identifier (replacing the placeholder `com.example.helloworld`), a
   signed release configuration (keystore handling per Godot's Android
   export docs), and version code/name bump process.
5. Prepare store assets: app icon, feature graphic, and screenshots of the
   core screens (Home, Party Formation, Region Select, Expedition Report)
   for store listing purposes.
6. Perform a full manual playtest on at least one physical Android device
   covering the entire [core gameplay loop](../../adventurers-march-implementation-plan.md#4-core-gameplay-loop):
   recruit/inspect Heroes, form a Party, equip items, start an Expedition
   in each shipped Region, background/close the app mid-Expedition, and
   verify correct offline-progress results on return.
7. Perform a save-resilience check: manually corrupt `user://save.json` on
   a test build/device and verify the `.bak` fallback path from
   [plan §12](../../adventurers-march-implementation-plan.md#12-save-system)
   loads correctly instead of crashing or resetting progress silently.
8. Record playtest and save-resilience results (e.g., in the release PR
   description) as the sign-off artifact for this milestone.

## Expected files / scenes / scripts / data

```
.github/workflows/android-apk.yml (updated to run tests before export)
export_presets.cfg (release preset added/updated)
tests/... (coverage gaps filled)
tests/test_expedition_end_to_end.gd   # full-run determinism regression test
assets/store/icon.png
assets/store/feature_graphic.png
assets/store/screenshots/*.png
```

## Interfaces / data contracts

No new gameplay interfaces. This milestone consumes and validates every
interface established in Milestones 1–8
(`HeroGenerator`, `PartyEvaluator`, `CombatSimulator`, `ExpeditionManager`,
`SaveManager`) rather than introducing new ones.

## Testing requirements

- CI: headless test suite must run and pass on every push/PR before the
  Android export step proceeds (this is itself the primary testing
  requirement of this milestone).
- Full end-to-end determinism regression test covering a complete
  Expedition with Combat steps.
- Manual device playtest and save-corruption fallback check, both
  recorded as sign-off evidence (Tasks 6–8).

## Acceptance criteria

- [ ] `CombatSimulator`, `HeroGenerator`, `PartyEvaluator`, and
      `SaveManager` migrations have unit tests covering their milestone
      acceptance criteria.
- [ ] End-to-end determinism regression test passes.
- [ ] CI runs the headless test suite before export and fails the build on
      test failure.
- [ ] Release export preset exists with a real package id and signed
      release configuration.
- [ ] Store assets (icon, feature graphic, screenshots) are prepared.
- [ ] Manual device playtest of the full core loop, including offline
      progress, is completed and recorded.
- [ ] Save-corruption `.bak` fallback is verified working.

## Risks

- **CI test flakiness from timing-dependent tests:** any test that relies
  on real wall-clock delays (rather than injecting/mocking "now") will be
  flaky in CI. Mitigation: ensure all offline-progress/recovery-timer
  tests use an injectable/mockable time source rather than real `sleep`
  calls.
- **Keystore/signing secrets handling:** release signing credentials must
  never be committed to the repository. Mitigation: use CI secrets/
  environment configuration for signing, consistent with how the existing
  workflow avoids committing credentials.
- **Last-minute device-specific bugs:** mitigate by playtesting on a
  physical device (not only the editor) as required by Task 6, since
  touch input and backgrounding behavior can differ from editor testing.

## Next-milestone handoff

This is the final milestone in the initial checklist. Once complete, the
project is at a release-ready MVP state per
[plan §21](../../adventurers-march-implementation-plan.md#21-release-preparation).
Further work (post-MVP enhancements noted throughout the
[implementation plan](../../adventurers-march-implementation-plan.md) and
explicitly deferred in
[plan §3](../../adventurers-march-implementation-plan.md#3-mvp-scope-and-non-goals))
should be tracked as new milestones appended to the
[milestones checklist](../../adventurers-march-milestones.md).
