# vxstory — Parameterized Physics Video Models in Godot

**Date:** 2026-06-09
**Status:** Approved design, pending implementation plan

## Overview

Six visually striking, physics/particle-driven "video models" — generative
simulations intended to be watched, tuned, and rendered to video. Each model is
its own Godot 4.6 project; all six live in one repo and share a common framework. Each model is fully parameterized; settings are tuned live in a tweak UI,
baked to JSON preset files, and reloaded for deterministic-ish batch rendering.
Graphics only — no audio anywhere in the project.

## Goals & Success Criteria

1. Six base models, each its own Godot project sharing one framework, each
   runnable directly (open project → sim starts).
2. Every model runs in *Preview* mode at interactive framerates at 1920×1080.
3. Tweak UI: every schema parameter is live-editable; edits apply immediately or on
   sim restart (per-parameter flag).
4. Presets: Save → Load round-trips exactly. Preset files are hand-editable JSON.
5. Render mode: `godot --preset <file.json> --write-movie out.avi --fixed-fps 60`
   produces a complete 1080p60 video with zero dropped frames regardless of sim cost.
   A wrapper script converts to .mp4 via ffmpeg.
6. Hyperparameters: each model exposes 3–5 macro dials driving many low-level params;
   per-parameter jitter ranges + a master seed produce related-but-unique variations
   of the same preset.
7. Same preset + same seed reproduces the same run (modulo GPU-particle
   nondeterminism — see Tradeoffs); same preset + different seeds produce visibly
   related variants.

## Architecture

One Godot 4.6 project **per model** (six projects), living in one repo, sharing a
single framework via symlink. All six models are 2D (one rendering pipeline; the
framework does not preclude adding 3D models later).

```
vxstory/
  common/
    core/
      sim_model.gd         # base class: schema declaration, param storage, seed mgmt
      param_schema.gd      # param definitions: type, range, default, macro maps, jitter
      preset_io.gd         # JSON load/save, validation
      macro_mapper.gd      # macro dial -> low-level param curves
      rng_service.gd       # single seeded RandomNumberGenerator handed to models
      tweak_panel.tscn/.gd # auto-generated UI from schema
      render_driver.gd     # CLI args, Movie Maker setup, duration cutoff
    fluid_sim/             # reusable viewport dye-advection sim (used by 3 models)
  radial_burst/
    project.godot
    core -> ../common/core          # symlink, appears as res://core
    fluid_sim -> ../common/fluid_sim  # only in projects that need it
    main.tscn / main.gd / shaders/
    presets/               # baked .json presets for this model
  fluid_swirl/             # same shape
  peg_cascade/
  chromatic_cascade/
  matter_cycle/
  supernova_orbit/
  scripts/
    render.sh              # render.sh <model> <preset> — godot --write-movie + ffmpeg
```

Each project opens directly into its model scene with the tweak panel (no global
launcher needed). Shared code lives once in `common/` and is symlinked into each
project as `res://core` — Godot's importer follows symlinks on Linux, and a
change to the framework is immediately live in all six projects. The reusable
fluid sim is its own shared sub-scene with an injection API, symlinked only into
the three models that composite it (Fluid Swirl, Chromatic Cascade, Supernova
Orbit).

### SimModel contract

Each model extends `SimModel` and implements:

- `get_schema() -> ParamSchema` — declares all parameters (name, type, range,
  default, ui hints, `live` flag, macro mappings, jitter range).
- `apply_params(params: Dictionary)` — (re)configure the sim from resolved values.
- `tick(...)` — normal `_process`/`_physics_process` simulation.
- Models receive all randomness from the injected seeded RNG; no `randi()`/
  `randf()` global calls, so a seed fully determines CPU-side behavior.

### Parameter resolution pipeline

```
preset JSON
  → macros resolved through MacroMapper curves → base param values
  → jitter applied (seeded)                    → varied param values
  → explicit overrides win                     → final params → apply_params()
```

A parameter listed in `overrides` is pinned: macros and jitter do not touch it.

### Hyperparameters

Two kinds, both supported:

1. **Macro dials** — 3–5 per model (e.g. Energy, Chaos, Density, Palette). Each
   macro maps to many low-level params via per-param curves (linear, eased, or
   custom Curve resources) defined in the schema.
2. **Variation controls** — per-param jitter ranges (± absolute or %) and a master
   seed. Rerolling the seed re-jitters everything not overridden, yielding endless
   siblings of one preset.

### Preset JSON format

```json
{
  "model": "chromatic_cascade",
  "seed": 1234567,
  "duration_sec": 30.0,
  "macros": { "energy": 0.8, "chaos": 0.4 },
  "overrides": { "ball_radius": 14.0 },
  "jitter": { "peg_count": { "pct": 15 } }
}
```

Unknown keys are warnings, not errors. Missing keys fall back to schema defaults.

### Run modes

- **Preview** — open a model's project (or `godot --path <model>`) → model scene
  with tweak panel (collapsible side panel: sliders/dropdowns per param, macro
  section on top, Save Preset / Load Preset / Reroll Seed / Restart buttons;
  panel toggles with Tab for clean viewing).
- **Render** — `--preset <path>` CLI arg loads settings, combined with Godot
  Movie Maker mode (`--write-movie`). `render_driver` enforces `duration_sec`
  then quits. `scripts/render.sh <model> <preset>` wraps `godot --path` and runs
  ffmpeg to produce mp4. Physics uses fixed timestep; Movie Maker guarantees no
  frame drops.

### Tweak UI

Auto-generated from the schema — adding a parameter to a model's schema is the
only step needed to get UI, preset IO, macro mapping, and jitter support for it.
Float → slider; int → slider (stepped); bool → checkbox; enum → dropdown;
color/gradient → color picker / gradient editor.

## The Six Models

All 1920×1080, 2D. "Macros" listed are the model's hyperparameter dials.

### 1. Radial Burst (pure — ref image #1)

Monochrome explosive starburst: tens of thousands of streaking particles with long
motion-blur trails erupting from center; expanding shockwave rings; recursive
sub-bursts that re-detonate at the tips of spent streaks. Mirrored symmetry option
for the bilateral look of the reference.

- **Macros:** Energy, Density, Symmetry, Grit (noise/raggedness).
- **Key params:** particle count, burst impulse ± spread, trail length, drag,
  ring count/speed/width, sub-burst depth & probability, grayscale ramp,
  mirror axes (0/1/2), bloom intensity.
- **Tech:** GPUParticles2D (multiple emitters), additive blending, trail
  rendering, screen-space bloom via WorldEnvironment glow.

### 2. Fluid Swirl (pure — ref image #2)

Psychedelic marbled fluid: vivid color fields advected by curl-noise / vortex
forces, folding and smearing into each other like wet paint. Runs as a
shader-based advection sim on ping-pong viewport textures (not a particle system).

- **Macros:** Turbulence, Viscosity, Flow Speed, Palette.
- **Key params:** noise scale/octaves, vortex count/strength/drift, dissipation,
  dye injection sites (count, radius, color), palette gradient, saturation/contrast
  post grade.
- **Tech:** two SubViewports ping-ponging a dye texture through an advection
  shader; curl-noise velocity field computed in-shader; final pass applies palette
  grading.

### 3. Peg Cascade (pure — ref image #4)

Peggle-style kinetics: balls fired from a top oscillating launcher into procedural
peg arrangements (rings, grids, spinners, orbiting clusters) that light up on hit,
pop with score-burst FX, and chain-explode when streaks connect. Pegs respawn in
waves so the show never ends.

- **Macros:** Layout Complexity, Ball Rate, Bounciness, FX Intensity.
- **Key params:** layout type/seeded generator params, peg count/size, spinner
  speed, ball radius/density/restitution/fire rate/aim sweep, gravity, hit-glow
  duration, chain radius & trigger count, particle burst size, palette.
- **Tech:** RigidBody2D balls, StaticBody2D/AnimatableBody2D pegs, GPUParticles2D
  hit FX, emissive materials + glow.

### 4. Chromatic Cascade (hybrid: Peggle × fluid × ink × burst)

Peg physics inside a living fluid. The playfield background *is* a Fluid Swirl-style
dye sim. Balls tear through it leaving wakes; every peg hit injects a splash of
that peg's ink color into the fluid, which swirls and marbles it; chained hits
detonate radial shockwaves that displace the fluid velocity field and shove
the balls.

- **Macros:** Layout Complexity, Ball Rate, Ink Saturation, Shockwave Power.
- **Key params:** all Peg Cascade physics params; dye injection radius/intensity
  per hit, wake strength, fluid turbulence/dissipation, shockwave impulse radius/
  falloff, per-peg-class palette.
- **Tech:** composition of the Fluid Swirl viewport sim (background + receiving
  splat injections) with Peg Cascade physics; shockwaves write radial impulses
  into the fluid velocity texture and apply forces to bodies.

### 5. Matter Cycle (hybrid: polygon rain × ink × fluid × burst)

A perpetual state-of-matter loop. Wireframe convex polygons rain into a grinding
pile; collisions above an energy threshold shatter polygons into thousands of ink
particles; a curl-noise flow field sweeps the particles upward into nebular
swirls; when a swirl region gets dense enough it collapses inward and
re-condenses into fresh polygons via a radial flash-burst, which then fall again.
Solid → particle → fluid → solid, forever.

- **Macros:** Matter Density, Shatter Threshold, Flow Turbulence, Cycle Speed.
- **Key params:** spawn rate, polygon size/vertex-count distributions, gravity,
  shatter energy threshold, fragment particle count per area, flow field
  scale/strength/updraft, condensation density threshold & radius, burst
  strength, wireframe/particle palettes.
- **Tech:** RigidBody2D polygons (seeded convex hull generator, wireframe drawn
  via Line2D/canvas draw), CPU-tracked particle swarm (or GPUParticles2D with
  attractors) for ink phase, density grid on CPU for condensation detection.

### 6. Supernova Orbit (hybrid: burst × n-body × fluid × debris)

A central gravity well pulls in orbiting streams of particles and small rigid
bodies that spiral inward and accrete into a brightening, swelling core; at
critical mass the core detonates a full-screen radial burst that flings rigid
debris outward through a reactive fluid-dye background; the survivors and new
infalling streams begin the next cycle. Endless build-up → catastrophe → rebirth.

- **Macros:** Accretion Rate, Critical Mass, Detonation Power, Orbital Chaos.
- **Key params:** stream count/spawn rate/orbital velocity spread, gravity
  strength & falloff, core growth per absorbed unit, criticality threshold,
  detonation impulse & flash, debris count/size distribution, fluid background
  reactivity, palette (core vs streams vs debris).
- **Tech:** custom gravity (point attractor) applied to particles + RigidBody2D
  debris, core rendered as layered shader sprite (pulse/swell), reduced-res
  Fluid Swirl background receiving detonation impulses.

## Tradeoffs & Notes

- **GPU particle nondeterminism:** GPUParticles2D does not guarantee bit-identical
  runs for a given seed. Re-rendering the same preset+seed gives a
  same-character but not identical video. Accepted: forcing CPUParticles2D would
  gut particle counts. Rigid-body simulation with fixed timestep and seeded
  spawning *is* reproducible.
- **Fluid sim cost:** the advection sim runs at reduced internal resolution
  (e.g. 960×540, parameterized) and upscales; Movie Maker mode means render
  quality is never compromised by cost, only preview framerate is.
- **No sound** anywhere — models must read as exciting purely visually
  (flash, glow, screen shake are in scope as parameters).
- **Out of scope:** 3D models, audio, in-app mp4 encoding (ffmpeg handles it),
  network/web export, interactivity beyond the tweak UI.

## Risks

- Fluid + physics composition models (Chromatic Cascade, Supernova Orbit) depend
  on the shared `common/fluid_sim` being built first and being composable
  (instanceable as a sub-scene with an injection API). Build order: framework →
  pure models → hybrids.
- Symlinked shared code: Godot's importer follows symlinks on Linux, but each
  project keeps its own `.godot/` import cache, and `class_name` registration
  happens per-project (this is fine — it's the same source file). Editor "open
  containing folder" type actions resolve to `common/`, which is the desired
  single source of truth. If a Godot update ever breaks symlink imports, the
  fallback is a `scripts/sync-common.sh` copy step.
- Movie Maker mode + SubViewport ping-pong sims need a fixed-FPS-safe update
  path (tie sim steps to rendered frames, not wall time).
