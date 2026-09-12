# Milestone 8 — Presentation Pass

[← Back to milestones checklist](../../adventurers-march-milestones.md) ·
[Full implementation plan](../../adventurers-march-implementation-plan.md)

## Objective

Replace placeholder art/audio/UI across every screen with final assets and
perform a UX/accessibility polish pass, bringing the game to a
presentable, store-quality visual and audio state.

## Scope

**In scope:** final art integration (portraits, class/status icons, Region
backdrops), audio integration (ambient loops, UI SFX, volume controls),
UI polish (spacing/typography consistency, touch-target sizing,
color-contrast/accessibility), removing all placeholder assets/text.

**Out of scope:** any new gameplay systems or content — this milestone
must not change game logic, only presentation (a useful constraint for
scoping PRs and code review).

## Prerequisites / dependencies

- Milestone 7 (Content expansion): all MVP screens and content must exist
  so there is a complete surface area to polish.

## Tasks

### Initial procedural-art slice

The initial implementation uses offline-generated pixel art, replacing the
earlier painterly direction without changing gameplay-facing contracts. Its
bounded inventory is 32 class portraits, 29 icons, three Region banners and
two additional portrait/banner fallbacks (66 PNGs total; the unknown icon is
included in the 29). The seven existing screens receive presentation-only
integration; Settings and audio are not part of this slice.

Recipes and the pixel-checksum manifest remain under `tools/art/`, separate
from exported textures. The [README workflow](../../../README.md#procedural-pixel-art)
owns regeneration and validation instructions. Hero appearance is selected
from existing stable identities without new save fields; reports use frozen
identities and never disclose unrevealed results through art.

This slice does not close Milestone 7's pending gates or any full-Milestone-8
acceptance checkbox. Physical-device artwork, touch-target, contrast and
scrolling acceptance must be recorded separately from local test/export checks.

#### Interrupted-run recovery (2026-09-08)

The [initial implementation run](https://github.com/pompomon/godot-apk/actions/runs/34275098135/job/102226054385)
failed with `CAPIError: 400 Error while downloading file. Upstream status code:
404` immediately after reading the two generated contact sheets. The managed
agent stopped after about 15 minutes, not at its 59-minute timeout. The logs
identify a file-download service error; they do not establish a broken PNG or
an Android build failure.

Its recovery commit `5a99d19` preserved recipes, UI integration and partial tests,
but omitted all 66 runtime PNGs and the manifest. A local read-only bank check
reproduced `Missing PNG: assets/art/portraits/knight_00.png`. The corresponding
[Android run](https://github.com/pompomon/godot-apk/actions/runs/34276591792)
was `action_required`, not a passing or failing test run.

The continuation generates the missing bank, adds generator regressions, and
fixes two unfinished art tests: the frozen slot key must use `PartyData.SLOT_NAMES`,
and artwork traversal must exclude Godot's internal overscroll textures without
excluding authored images. Raw PNG verification decodes file bytes rather than
using runtime resource loading, avoiding misleading export warnings.

The repository workflow now checks committed artwork without rewriting it,
publishes contact sheets as a downloadable artifact, and retains validation
logs. This changes the review/validation path; it does **not** fix the upstream
managed-agent service or bypass GitHub workflow approval.

The generated bank was published in `d67327f`; its
[Android run](https://github.com/pompomon/godot-apk/actions/runs/34278631878)
also requires approval. A subsequent source review found that the new gold-icon
wrapper lost the Roster label's horizontal expansion. A regression test
reproduced a one-pixel-wide gold label and a 375–543-pixel-tall fixed header.
The wrapper now preserves the original sizing flags and stretch ratio.

Local validation of `d67327f` plus that header fix: clean import, **18 focused
art tests**, full GUT **382 tests / 34,365 assertions**, and Android debug export
with a nonempty **28,762,614-byte APK** passed. The existing art UI tests also
passed **7/7** under a desktop Compatibility renderer and generated seven
720×1280 screen captures. All 66 texture remaps were verified in the APK; tools
and tests are excluded. Captures were not inspected through the failed image
transport. Visual quality, Android-device acceptance and current-checkpoint
CI remain separate, unverified gates; these results do not complete Milestone 8.

### Responsive layout and newest-first report slice (2026-09-09)

This bounded presentation update keeps status badges on one line, enables
portrait `canvas_items`/`expand` scaling, and shares safe-area-aware, centered
content bounds across the seven existing screens. Expedition entries are
prepended in reverse step order without changing stored results, rewards or
combat action order. Older reading positions are retained; visible updates
wait for held swipes and inertia to finish while saved progress continues.

Validation of code revision **`59cf4c5`**, against baseline **`566f6bd`**:

- Baseline clean import and **383 tests / 34,431 assertions** passed.
- Updated clean import and full GUT **393 tests / 39,244 assertions** passed.
- Focused desktop Compatibility runs passed **9 art/UI tests**, **11 smoke
  tests**, and **21 Expedition UI tests**. Coverage includes live resizing at
  720×1280, 720×1600 and 960×1280, actual root-window scaling, embedded-window
  safe-area conversion, and reveals during held touch gestures and inertia.
- Android debug export passed and produced a nonempty **28,766,875-byte APK**.
  This is local export evidence, not an installed-device playtest.
- Seven baseline and 31 updated layout/root-window captures were generated
  under `/tmp/visual-before` and `/tmp/visual-after`. The updated images could
  not be visually inspected because the session's image-viewing limit was
  reached; automated bounds checks are not a substitute for that inspection.
- Read-only review identified and then verified fixes for embedded-window
  safe-area scaling and native swipe cancellation. Secret scans passed.
  CodeQL was requested but performed no analysis because the changes contain
  no supported language; this is not a CodeQL security clearance.
- The [code-revision Android workflow](https://github.com/pompomon/godot-apk/actions/runs/34331233091)
  is **`action_required`**, with no jobs executed, not a passing or failing CI run.

Physical Android checks for cutouts/system bars, effective ≥48×48dp targets,
typography, scrolling and compatibility-mode bars remain unverified. No
Milestone 7 or full-Milestone-8 acceptance boxes are closed by this slice.

### Foldable static-margin stabilization (2026-09-10)

The user subsequently tested Company Roster and Party Formation on both Fold 4
displays in diagnostic modes A–D. All Heroes were Idle; smaller layouts exposed
their rows through scrolling, larger layouts omitted them in dynamic modes, and
only static-margin mode D showed them consistently. This is attributed device
evidence, not testing performed by the implementation agent.

The bounded follow-up retires the temporary debug panel, trace, export feature
and comparison modes. Company Roster and Party Formation now permanently keep
their authored margins, while the other five screens retain the shared dynamic
margin helper. Automated coverage includes the reported 1065×1280 viewport and
asserts that all four starting Heroes have visible, nonzero Party Formation
rows. Matching-revision checks and renewed physical-device acceptance are
recorded separately; the historical diagnostic APK is no longer shipped.

### Graphics-only expansion slice (2026-09-12)

This bounded slice retains the existing 66 procedural images pixel-for-pixel and
extends the bank to **91 PNGs**. It adds one 64×64 vignette for each of the six
enemy groups and 15 narrative events, a neutral encounter fallback, a Home
crest, a section divider, and a formation emblem. A third generated contact
sheet covers the complete addition. Runtime lookup remains an explicit preload
allowlist; frozen encounter IDs never become resource paths.

The seven existing screens share expanded button, option, panel, progress, focus,
and scrollbar styling. Status badges use distinct high-contrast colors while
retaining both text and icons. Decorative assets are passive, nearest-filtered
controls. Region choices are grouped as visual cards, and Expedition Report adds
enemy/event artwork only after the matching journal step is revealed. Journal
ordering, scroll-anchor ownership, Party drafts, gameplay results, persistence,
and the established static-margin behavior of Company Roster and Party Formation
are unchanged. The stale Party Formation statement that Expeditions were
unavailable has been replaced.

Local validation of code revision **`b47bc26`**:

- Clean Godot 4.7.2 import and the read-only 91-asset pixel/manifest check passed.
  Decoded hashes confirm that all 66 pre-existing images are unchanged.
- Focused generator, catalog, presentation, Roster, Party Formation, Region,
  Equipment, and Expedition UI suites passed during implementation.
- Full GUT passed **439 tests / 46,707 assertions** across 41 scripts with no
  test failures. Expected negative save-recovery and navigation cases emitted
  their documented warnings.
- Android debug export passed and produced a valid, nonempty
  **28,838,773-byte APK**.
- Three contact sheets were generated under `/tmp` but were not visually
  inspected in this implementation task. Current-revision CI and physical-device
  artwork, density, touch-target, contrast, scrolling, fold/unfold, and
  background/resume acceptance remain unverified.

Audio, `AudioManager`, Settings, and new gameplay/content remain explicitly
deferred. Milestone 7 is still incomplete, so this graphics slice does not close
any full-Milestone-8 acceptance checkbox below.

### Full presentation milestone

1. Produce/source final Hero class icons, status-effect icons, item-slot
   icons, and Region backdrop art (or a clearly documented placeholder-art
   licensing plan if final art is sourced from an asset pack — note
   licensing in `docs/` only if this repository's existing licensing docs
   require it; do not introduce new legal documentation beyond what's
   already needed).
2. Integrate portraits/icons into Company Roster, Hero Detail, Party
   Formation, Equipment, and Expedition Report screens.
3. Integrate Region backdrop art into Region Select and Expedition Report.
4. Add an `AudioManager` autoload (decoupled from `CombatSimulator`
   per [plan §15](../../adventurers-march-implementation-plan.md#15-audio))
   with: a Home ambient loop, a per-Region ambient loop during active
   Expeditions, UI SFX (tap/confirm/level-up/victory/defeat), and a
   Settings volume/mute toggle wired to it.
5. Perform a UI consistency pass: consistent spacing/margins/typography
   scale across all screens (Home, Roster, Hero Detail, Equipment, Party
   Formation, Region Select, Expedition Report, Settings).
6. Perform a touch-target audit: verify every interactive control meets
   the ≥48x48dp guidance from
   [plan §2](../../adventurers-march-implementation-plan.md#2-target-platform-and-mobile-ux-constraints)
   by measuring effective touch areas on exported Android builds at target
   device densities, not by converting project viewport pixels.
7. Perform a color-contrast/accessibility audit: verify status
   effects/class colors are paired with icon or text (not color alone),
   per plan §2 and
   [plan §14](../../adventurers-march-implementation-plan.md#14-ui-and-art-direction).
8. Sweep all screens for placeholder text/art (e.g., default Godot
   icons, "Lorem ipsum"/`TODO` labels) and replace/remove.

## Expected files / scenes / scripts / data

```
autoload/AudioManager.gd
assets/art/portraits/...
assets/art/icons/...
assets/art/backdrops/...
assets/audio/ambient/...
assets/audio/sfx/...
scenes/ui/settings/settings_screen.tscn (volume/mute controls wired)
```

(Exact asset folder layout can follow Godot import conventions; keep art/
audio under a top-level `assets/` directory separate from `data/` content
resources to keep binary assets and data-only resources easy to
distinguish.)

## Interfaces / data contracts

```gdscript
# AudioManager (autoload)
func play_ambient(track: AudioStream) -> void
func play_sfx(sfx: AudioStream) -> void
func set_master_volume(linear: float) -> void
func set_muted(muted: bool) -> void
```

No gameplay-facing data contracts change in this milestone — existing
`HeroData`, `PartyData`, `ExpeditionData`, combat-result dictionary, etc.
interfaces from prior milestones remain stable.

## Testing requirements

- Manual test: walk every screen and confirm no placeholder art/text
  remains.
- Manual test: touch-target and color-contrast audits completed against
  the plan's criteria (record findings/fixes in the PR description).
- Manual test: mute/volume controls in Settings correctly affect ambient
  and SFX playback.
- Regression: re-run the full unit test suite from Milestones 1–7 to
  confirm no gameplay logic regressed (this milestone should not need to
  touch `scripts/systems/` or autoload gameplay logic files).

## Acceptance criteria

- [ ] All MVP screens use final art (no default/placeholder icons or
      images remain).
- [ ] `AudioManager` is integrated with ambient loops, UI SFX, and a
      working Settings volume/mute control.
- [ ] Touch-target sizing audit completed with no failing controls.
- [ ] Color-contrast/accessibility audit completed; all status/class color
      cues are paired with icon or text.
- [ ] Full existing unit test suite still passes unmodified.

## Risks

- **Scope creep into new gameplay features** during a "polish" pass.
  Mitigation: explicit out-of-scope note in this file; code review should
  reject gameplay-logic changes in this milestone's PRs.
- **Asset licensing:** if using third-party art/audio packs, verify
  license terms allow the intended use (including any commercial release
  plans from [plan §17](../../adventurers-march-implementation-plan.md#17-monetization-considerations)).

## Next-milestone handoff

Milestone 9 (Testing and release preparation) takes the fully polished
build and hardens it for release: full test coverage, CI integration, and
store-ready export.

→ Next: [09-testing-and-release.md](09-testing-and-release.md)
