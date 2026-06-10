# Long-form Supernova — Milestone 1 Design

**Date:** 2026-06-09
**Status:** Approved direction (user picked options 2+3+4 of the long-form proposal)
**Goal:** Make `supernova_orbit` hold visual interest for 4–6 minutes instead of ~30s,
via three mechanisms: binary cores, persistent consequences, and a director layer.
Items 1/5/6 of the proposal are deferred to TODO.md.

## Problem

v1.0 models are statistically stationary (fixed params → same event distribution
forever) and reset state on climax (detonation wipes debris and trails). Nothing
compounds; nothing drifts; the viewer has seen the whole distribution in 30 seconds.

## 1. Binary cores (dynamics)

Core state becomes a small list (1–2 cores), each `{pos, vel, mass, node, mat}`.

- **Wander:** a lone core drifts slowly around the screen center (seeded smooth noise
  path, bounded ~±220 px); particles/debris gravitate toward the *sum* of core fields.
- **Fission:** at detonation time, with seeded probability `split_chance`, the core
  fissions instead of fully detonating: two cores at half mass, kicked apart
  tangentially (`split_kick`), plus a half-strength detonation (flash, rings, modest
  fling). The pair orbits under mutual gravity while both keep accreting — two
  interacting disks.
- **Merge:** cores within `merge_radius` merge (masses sum, bright flash, impulse to
  nearby debris); if merged charge ≥ 1 it detonates immediately — the "double event."
- **Binary detonation:** when one core of a pair detonates, the survivor receives a
  kick and keeps its disk; the system returns to lone-core mode.
- **Absorption/charge:** each core absorbs in its own radius and accumulates its own
  mass; the core shader's `charge` is per-core. Critical threshold stays global.
- New macro **`duality`** (0..1) → `split_chance` (0..0.85), `core_drift` (0..1 of max),
  `split_kick`. Existing macros unchanged.

## 2. Persistent consequences (memory)

- **Debris belt:** detonation no longer clears existing debris. New debris spawns with
  an outward+tangential velocity mix biased toward orbit-ish speeds, so survivors
  settle into an accumulating belt. Total debris capped (`debris_cap`, default ~80);
  beyond cap, oldest are culled. Debris survives across cycles indefinitely otherwise.
- **Trail ghosts:** replace the 3-frame hard viewport clear at detonation with a soft
  wipe — fade-rect alpha temporarily raised (≈0.5 for ≈0.6 s), then restored. Old
  trails dim fast but leave visible history instead of vanishing.
- Dye haze behavior unchanged (already lingers ~2 s; acceptable).

## 3. Director layer (drift) — framework feature, model-agnostic

New `common/core/director.gd`, integrated in `SimModel` so any model can use it.

- **Config lives in the preset** (new optional top-level key, backward compatible —
  absent ⇒ disabled):

  ```json
  "director": {"enabled": true, "period_sec": 90.0, "amplitude": 0.25,
               "macros": ["accretion", "chaos", "duality"]}
  ```

- **Behavior:** each listed macro follows `clamp(base + amplitude * drift(t), 0, 1)`
  where `base` is the preset's macro value and `drift(t)` is smooth seeded value-noise
  (2 octaves, period `period_sec`), stream-seeded per macro (`"director:<macro>"`) so
  runs are reproducible and macros drift independently.
- **Application:** SimModel ticks the director in `_process` and re-resolves **live**
  params at 4 Hz (`resolve_live()`); non-live params are not churned (their resolved
  values change in `params` but take effect only on restart — acceptable; the director
  is meant to drive live params).
- **Panel:** macro sliders reflect drifting values (read-only effect; user edits still
  work — an edit rebases that macro's `base`). Minimal UI: a "director" indicator
  label when active. No editor for director config (YAGNI — it's preset JSON).
- `preset_io` must round-trip the `director` key (defaults: disabled).

## 4. Hue drift (model-level polish enabled by the director's clock)

New live param `hue_drift` (deg/min, default 0) on supernova_orbit: stream/debris/core
palette colors rotate hue slowly over time (`Color.from_hsv` rotation at color-assign
time). At 10–20°/min a 5-minute render passes through the whole wheel once.

## Deliverables

- Framework: director.gd + SimModel/preset_io integration + unit tests (determinism,
  clamping, preset round-trip, disabled-by-default).
- supernova_orbit: binary cores, persistent belt, soft trail wipe, `duality` macro,
  `hue_drift` param.
- New preset `odyssey.json`: director enabled (period ~90 s, amplitude ~0.3, macros
  accretion/chaos/duality), duality ~0.6, hue_drift ~12, `duration_sec: 300`.
- Verification: unit tests green; 5-minute render of `odyssey`; frames sampled every
  ~30 s must show: at least one binary phase, debris belt growth over time, palette
  hue visibly shifted late vs early, no two sampled frames near-identical.
- VERSIONS.md entry + tag `v1.1` after verification.

## Success criteria

1. `scripts/render.sh supernova_orbit odyssey 300` completes; sampled frames at
   30-second intervals are pairwise visually distinct (regime, geometry, or palette).
2. A binary-core phase occurs and is visually evident (two disks / two glow centers).
3. Debris count visibly accumulates across ≥3 detonation cycles (belt grows).
4. Director determinism: same preset+seed twice → identical macro drift curves
   (unit-tested); old presets behave exactly as before (director off).
5. All v1.0 tests still pass; total suite grows with director tests.

## Out of scope (TODO.md)

Epochs/life-story arc, heavy-tailed rare events, camera breathing.
