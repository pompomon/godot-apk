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
