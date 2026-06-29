# Models on the modulation paradigm — design

**Date:** 2026-06-28

## Goal

Make all six models authorable in the visual Designer on the unified modulation
system. The base `SimModel` already re-composes and re-applies params every frame
(`_process` → `_compose` → `apply_live`), so **every model is already
live-reactive** — modulation reaches the running sim today. The remaining gaps are
small and surgical:

1. **Events** — only `radial_burst` emits any (`burst`). The other five emit none,
   so envelopes can't fire on them. Add `emit_event()` at each model's natural
   moments.
2. **`supernova_orbit` is on the legacy Director** — migrate its `odyssey` presets
   to modulation, then **retire the Director** entirely.
3. **Starter presets** — only `pulsar` has a `modulators` config. Seed one
   long-form starter per model to then tune in the Designer (seed-then-tune, since
   Designer 2b "add sources" is deferred).

**Scope decisions (locked):** modulation-native only — **no** new signature
mechanics (no morphing playfields, `hue_drift`, `source_count`, etc.) and **no**
new macros this pass; use each model's existing mechanics and macros. Code all in
one pass, then author/tune presets.

## Component 1 — Event contract

Add `emit_event(<name>)` at the discrete moment named. Events fire on real
occurrences (no throttling in code); the user controls response via envelope
`attack`/`decay`/`amount` in the Designer. Survey line hints are approximate —
the implementer reads each `main.gd` and places at the correct semantic spot.

| Model | Event | When (semantic) | survey hint |
|---|---|---|---|
| peg_cascade | `hit` | a peg is lit by a ball | ~252 |
| peg_cascade | `chain` | a chain blast triggers | ~277 |
| peg_cascade | `spawn` | a ball is fired | ~294 |
| chromatic_cascade | `hit` | ball contacts a peg | ~280 |
| chromatic_cascade | `shockwave` | chain blast triggers | ~309 |
| matter_cycle | `shatter` | a polygon breaks/collides | ~215/237 |
| matter_cycle | `condense` | a swarm condenses into a ring | ~328 |
| matter_cycle | `spawn` | a body spawns | ~293 |
| fluid_swirl | `inject` | once per injector **cycle** (not per frame) | ~91 |
| supernova_orbit | `detonation` | core detonates | ~491 |
| supernova_orbit | `fission` | a core fissions | ~489 |
| supernova_orbit | `merge` | two cores merge | ~467 |

Notes:
- High-frequency events (`hit`, `shatter`) suit accumulating envelopes (busy →
  sustained); rare ones (`chain`, `detonation`, `condense`, `merge`) suit
  punctuated flashes.
- **fluid_swirl** has no per-collision moment; emit `inject` once per injector
  path cycle. If there is no clean cycle boundary, drop the event and let
  fluid's starter use LFO/tween only (note it in the report) — do not emit every
  frame.

## Component 2 — supernova_orbit: Director → modulation

The Director drifts macros via two incommensurate sines and applies
`clamp(base + amplitude × drift(t), 0, 1)` — which an **LFO of two oscillators**
reproduces. Migrate `supernova_orbit/presets/odyssey.json` and
`odyssey_slow_pulse.json`:

- Read `common/core/director.gd` to match its two-sine drift (periods/ratio).
- For each macro in the old `director.macros` (odyssey: `accretion`, `chaos`,
  `duality`), add a `modulators.lfo` entry `"<macro>_drift"` with **two
  incommensurate sine oscillators** (e.g. `period_sec` ≈ the old `period_sec` and
  ~1.4× it; oscillator `amount`s summing to ~1.0) and a single target
  `{to: <macro>, amount: <old amplitude>}`.
- Remove the `director` block from these presets.
- Add the supernova events (`detonation`/`fission`/`merge`) and an envelope on
  `detonation` in the migrated `odyssey` (a brief flash — target a sensible
  param/macro; user tunes).

Migration is behavior-approximate (the user tunes); the goal is that odyssey
drifts the same macros, now on the unified system and Designer-authorable.

## Component 3 — Retire the Director

Once odyssey is migrated (the only Director user):

- **`sim_model.gd`** — remove the Director branch in `_process` (the
  modulation-disabled path that ticks the director), the `director`/`director_cfg`
  members, and any director instantiation. Non-modulated presets simply don't
  drift (as before the Director existed).
- **`common/core/director.gd`** — delete.
- **`preset_io.gd`** — `load_preset` **ignores** a legacy `director` key (emit a
  warning, do not crash, do not carry it into the returned preset). `save_preset`
  **drops** its `director` parameter (new signature ends `…, jitter, modulators`).
- **Callers of `save_preset`** — update all (`designer.gd` `save_now` stops
  passing `model.director_cfg`; the tweak panel's Save path; tests). The
  implementer greps for `save_preset(` and `director_cfg`.
- **README** — replace the `### Director` section with a `### Modulation` section
  describing `modulators` (tween / LFO / envelope) and the Designer.

## Component 4 — Starter long-form presets (seed-then-tune)

Seed one starter `modulators` preset per model, shaped like `pulsar` (a `build`
tween, a texture LFO, and an event envelope), using **existing macros only**.
`duration_sec: 300`. Names follow the `2026-06-17` umbrella:

| Model | Preset | build tween → | texture LFO → | envelope (event → target) |
|---|---|---|---|---|
| peg_cascade | `clockwork` | `ball_rate`, `fx` | `complexity` | `chain` → `fx` |
| chromatic_cascade | `fresco` | `ball_rate`, `ink` | `complexity` | `shockwave` → `ink` |
| matter_cycle | `tides` | `matter`, `cycle_speed` | `turbulence` | `shatter` → `fragility` |
| fluid_swirl | `aurora` | `turbulence`, `flow` | `vibrance` | `inject` → `flow` (omit if no event) |
| supernova_orbit | `odyssey` | (migrated; the macro-drift LFOs) | — | `detonation` → a flash param |

Starters are deliberately simple and valid; the user tunes them in the Designer.
Envelope/tween targets are macros (0..1) unless a param flash is clearly better;
keep amounts modest. No back-compat constraint on these new presets' looks.

## Verification

- Suite stays green (`godot --headless --path <model> --script
  res://core/tests/run_tests.gd`) plus new tests:
  - `preset_io` ignores a legacy `director` key (warns, loads) and `save_preset`'s
    new signature round-trips.
  - `supernova_orbit/presets/odyssey.json` loads with `modulators` (3 macro-drift
    LFOs) and **no** `director` key; `director.gd` is gone.
- Per-model headless smoke: `godot --headless --path <model> --quit-after 120 --
  --preset presets/<starter>.json` runs clean (params resolve, modulation enabled,
  no errors).
- The user reviews the seeded starters in the Designer / via renders (look/feel is
  the user's review, per project convention).

## Out of scope

- Signature mechanics, `hue.gd`/`hue_drift`, new params/macros (a later pass).
- Designer 2b/2c/2d.
- Deep per-preset tuning (the user does this in the Designer after seeding).
