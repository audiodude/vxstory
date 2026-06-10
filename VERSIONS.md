# Versions

Git tags marking known-good states of the simulations, so experiments can be ruthless.
Every entry here corresponds to an annotated tag of the same name.

## Workflow

- Before (or after) a burst of experimentation, tag a state worth keeping:
  `git tag -a v0.X -m "short description"` — then add an entry here and commit.
- Look around at an old state: `git checkout v1.0` (detached HEAD; `git checkout main`
  to come back).
- Compare: `git diff v1.0 -- radial_burst/`
- Resurrect one model from a tag without touching the rest:
  `git checkout v1.0 -- radial_burst/ common/`
- Hard reset everything to a tag (destroys later work on main — be sure):
  `git reset --hard v1.0`

Renders are gitignored, so jumping tags never touches `renders/`. Re-render after a
jump if you want videos that match the code.

## Tags

### v1.1 — long-form milestone 1 (2026-06-09)

Long-form supernova: director layer, binary cores, persistent consequences, hue drift.

- **Director layer** (`common/core/director.gd` + SimModel/preset_io/tweak_panel
  integration): model-agnostic framework feature. Preset key `"director"` drives
  smooth seeded macro drift over time (2-octave sine noise, configurable period and
  amplitude). Deterministic (stream-seeded per macro), clamped 0..1, rebased on user
  edits. Off by default — all v1.0 presets are unaffected. 5 new unit tests; total
  suite: 22 run, 0 failed.
- **supernova_orbit — binary cores:** core state is now a 1–2 element array. Lone
  core wanders with seeded smooth noise; at critical mass, `split_chance` (macro
  `duality`) triggers fission into two half-charged cores that orbit under mutual
  gravity, both accreting. Cores within `merge_radius` merge (momentum-averaged); if
  merged charge ≥ 1, immediate detonation. Binary detonation: detonated core removed,
  survivor gets kick, system returns to lone-core.
- **Persistent debris belt:** detonation no longer clears existing debris. New ejecta
  launches with an orbit-biased velocity (outward + tangential mix) so survivors
  settle into an accumulating belt. Total capped at `debris_cap` (default 80); oldest
  culled beyond cap.
- **Soft trail wipe:** hard 3-frame viewport clear replaced with a 0.6 s fade-rect
  alpha ramp — old trails dim fast but leave visible history on detonation.
- **Hue drift** (`hue_drift`, deg/min, default 0): particle, debris, and core colors
  rotate hue slowly over time — 14°/min gives a 70° palette shift across a 5-minute
  render, cycling warm→cool→warm.
- **`odyssey` preset** (`supernova_orbit/presets/odyssey.json`): 300 s director-driven
  long-form. Director period 90 s, amplitude 0.3, drifting accretion/chaos/duality.
  Macro `duality` 0.6 (fission-biased), `hue_drift` override 14°/min. Seed 31416.

### v1.0 — complete baseline (2026-06-09)

The full spec implementation, all verified against rendered frames:

- **Framework** (`common/core/`): schema-driven params, 4 macro dials per model,
  seeded jitter, JSON presets (overrides pin params), auto-generated tweak panel,
  Movie Maker render driver. 17 unit tests passing.
- **Shared fluid module** (`common/fluid_sim/`): ping-pong curl-noise dye advection
  with splat/impulse API, dye clamped at 1.0.
- **Six models**, each with `default` + 2 variant presets:
  - `radial_burst` — LDR persistence-trail starburst; rings, sub-bursts, mirror.
    Variants: gentle, cataclysm.
  - `fluid_swirl` — full-screen dye marbling. Variants: lava_lamp, maelstrom.
  - `peg_cascade` — peg/ball physics, chain detonations, respawn waves.
    Variants: zen_garden, pachinko_riot.
  - `chromatic_cascade` — peg cascade + reactive ink field (linear-space palette,
    wakes off by default). Variants: watercolor, paintstorm.
  - `matter_cycle` — polygon→particle→condensation loop, CPU swarm with flow grid.
    Variants: slow_genesis, grinder.
  - `supernova_orbit` — accretion disk → detonation cycle, trail viewport flushed on
    detonation. Variants: slow_burn, strobe_core.
- Conventions in force: default presets keep `overrides: {}` (tuning lives in
  schemas); all sim randomness via seeded `rng.stream()`; models extend
  `res://core/sim_model.gd` via symlinked `common/`.
