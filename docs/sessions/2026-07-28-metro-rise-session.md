# Session summary — metro_rise: new 3D era-city model

_2026-07-28. Covers commits `1a9a9ce..9d90120` on `main` (spec → plan → 12
implementation commits)._

## What happened

Built the seventh vxstory model from scratch: **metro_rise**, the repo's first
3D model. A city grows from empty dawn land to a lit night metropolis over one
300 s render; the sun's single arc is metaphorical time (brick low-rises →
concrete mid-rises → glass towers, with demolition/replacement), traffic and
tower cranes animate the middle game, and nightfall pays off with lit windows,
neon storefronts, streetlamps, and headlight streams. Slow orbit + pull-back
camera, no cuts.

Design decisions (user-approved during brainstorming):

- **Style**: procedural shader facades on low-poly massing — zero image assets.
- **Arc**: "single-day timelapse × era progression" (user picked both options).
- **Two-dial pure-function core**: `development` (P) evaluates a seeded
  CityPlan whose per-lot timelines live in **P-space** (construct/demolish
  windows as P values); `day_phase` drives the sun/sky/night entirely
  separately. Structural scrubbing is therefore **exact** — the Designer drags
  the whole city up and down. Traffic/cranes/dust are the only character-at-t
  transients.
- **3D under the 2D framework, zero framework changes**: the model root stays
  `Node2D` (SimModel untouched); a 3D subtree (WorldEnvironment, sun/moon
  lights, Camera3D, MultiMesh city) hangs beneath it. TweakPanel / Designer /
  transport link / Movie Maker all work unchanged.
- **Cut from v1**: pedestrians, sky extras, miniature-DOF param (spec'd
  optional, dropped as YAGNI).

Artifacts:

- Spec: `docs/superpowers/specs/2026-07-28-metro-rise-design.md`
- Plan: `docs/superpowers/plans/2026-07-28-metro-rise.md`
- `metro_rise/citygen/` — roads (jittered grid + node-walked diagonal
  boulevards), lots (blocks/districts/parks + merged core tower parcels), eras
  (P-space chains with era-band overlap blending, ring-gated outward growth).
- `metro_rise/sim/` — StateTracker (slot diffs, `topout`/`demolish`/`era`
  events, silent first-eval to kill scrub event storms), deterministic lane
  traffic (routes, fixed-cycle lights, accordion queues, era gate), sun curves
  + palettes, orbit/pull-back camera. All pure RefCounted, headless-tested.
- `metro_rise/view/` — facade shader (face-space window grids styled per era,
  storefronts + neon, work-light band; construction = view scales instance Y so
  tops self-cap as slabs — no discard, correct shadows), road/ground/tree/lamp/
  car/sky shaders, CityView (sparse dirty-slot MultiMesh writes), CraneView
  (closed-form jib rotation), GPU dust puffs on demolition.
- Presets: `default`, `boomtown` (sodium dusk), `garden_city`, `century`
  (the 300 s flagship: development+sunarc tweens, delayed traffic ramp via
  negative tween `from`, nightlife ease-in, topout→glow pips, era→fog swells).
- Tests: 25 model-local (plan determinism, timeline validity, era bands,
  parcel co-demolition, scrub exactness, traffic invariants, sun/camera
  continuity) + shared suite still green (67).
- Docs: `metro_rise/README.md`, root README (table, variants, layout).

## Hard-won lessons (recorded in project memory too)

- **Grazing-angle specular washed the whole frame pastel**: Godot's default
  `SPECULAR 0.5` sky-mirrors every horizontal surface at shallow view angles.
  Diagnosed by painting road albedo pure red (rendered salmon → additive white
  light, not albedo). Fix: `SPECULAR ≈ 0.02` on matte shaders; keep specular
  only on glass. This, plus ACES + `tonemap_exposure 0.75`, is the model's
  grading foundation.
- `MultiMesh.set_instance_color` expects **linear** colors —
  `Color.from_hsv(...).srgb_to_linear()` or tints render pale.
- Under-construction cutoff via **Y-scaling beats `discard`**: face-space
  window grids measure real meters, so rows stay floor-aligned while the
  building rises, the top face reads as a slab, and shadows stay correct.

## State / next steps

- Preview holds 58–61 fps on default and boomtown (target was ≥30).
- 60 s ÷5 proofs rendered and reviewed frame-by-frame through three grading
  iterations; final proof at `renders/metro_rise_century_proof60.mp4`.
  **Awaiting user review** (their call per workflow), then:
  `scripts/render.sh metro_rise century 300` for the real piece.
- Tuning knobs if the look needs pushing: `nightlife` mapping (lit fraction),
  `fog_amount`, palette grades in `sim/sun.gd`, per-era tints in
  `view/city_view.gd::_tint`.
