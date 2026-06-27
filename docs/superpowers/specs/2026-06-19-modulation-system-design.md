# Modulation system — design

**Date:** 2026-06-19

## Goal

Replace the four disconnected mechanisms that currently move parameter values —
schema params, superparams (macros), the director, the build envelope — with
**one modulation model** the user can *reason about* like a synthesizer, instead
of fiddling blind. The disconnect today is that those mechanisms inject at
different layers, with different math, and compose in different places, so "what
is this param's value right now, and what's moving it?" has no single answer.

The fix is **one composition rule per scope, evaluated in one place**.

Proving ground: **radial_burst** (the model under active tuning). Other models
keep using the legacy `director` until migrated in follow-up passes.

## The model (synth vocabulary, used literally)

### Two scopes of parameter

- **Global params** — the simulation template/settings (the destinations the sim
  code reads: `burst_speed`, `loop_period`, `glow`, …). Two flavors:
  - **Seed globals** — copied into an item at its creation (`particle_count`,
    `burst_speed`, `streak_len`, `particle_life`). They shape *future* items.
  - **Ambient globals** — never copied; they are the render itself (`glow`,
    `trail_persist`, `mirror_mix`, `hue_drift`). They act on what's on screen
    *now*.
- **Item params** — per-instance values (a burst; a peg; a ball). **Seeded from
  globals at creation** (a snapshot, not a live link), then shaped only by that
  item's envelopes over its lifetime.

### Source types (what moves a destination)

- **Superparam** (manual, global) — a 0..1 macro knob that fans out to many
  global params via a per-param range map `lerp(lo, hi, value)`. This is today's
  macro system, kept as-is.
- **LFO** (continuous, global) — a free-running periodic source. Bipolar output
  in `[-1, 1]`. Has `rate_sec` and a `shape` (incl. the organic dual-sine the
  director uses today, so long renders never visibly loop).
- **Tween** (one-shot at scene start, global) — a single curve from `from`→`to`
  over `secs`, then holds. This is what the build *actually* is — automation, not
  an envelope. Output is the interpolated value.
- **Envelope** (event-triggered, **polyphonic**) — a one-shot attack/decay curve
  fired by a *simulation event*. Each trigger spawns an independent instance;
  instances run concurrently and **sum** onto the destination. Unipolar output in
  `[0, peak]`.

### Routing and composition (the one-way rules)

A **routing** is `source → destination, amount`. Composition is layered and each
layer is one rule in one place:

1. **Live superparam value** = `macro_base + Σ(LFO/tween/envelope offsets routed
   to this superparam)`, clamped to `[0, 1]`.
2. **Global param value** = `override` **or** `lerp(lo, hi, live_superparam)`
   **or** `schema_default`; then `+ jitter`; then `+ Σ(LFO/tween/envelope offsets
   routed to this param)`; clamped to the param's `[min, max]`.
3. **Item param value** = `seed_snapshot_of_global_at_creation + Σ(this item's own
   envelopes)`.

Contribution of a dynamic source to a destination = `normalized_output × amount`,
where `amount` is in the destination's units (superparam units 0..1, or the
param's native units). Superparams remain *range maps* (lerp); LFO/tween/envelope
are *additive offsets*. (Two maths, but each is one clearly-stated rule — a macro
remaps a range, a mod source offsets. Standard synth behavior.)

**Scope valve.** Continuous global sources (superparam/LFO/tween) drive **globals
only**. Envelopes are the **only** thing that can drive an **item**, and may also
**send to ambient globals** (summed). The only global→item path is the seed copy
at birth. Every value therefore has exactly one composition formula.

**Footgun, named:** an envelope *may* target a seed global, but that creates
**birth-time feedback** (an event makes subsequent items bigger). Default envelope
sends target **ambient** globals; seed-global sends are advanced.

## Config / preset format

The preset's `director` key is replaced by `modulators`. `macros` (superparam
base values), `overrides`, `jitter` are unchanged.

```json
{
  "model": "radial_burst", "seed": 204, "duration_sec": 300.0,
  "macros": { "energy": 0.4, "density": 0.45 },
  "overrides": { "palette": "galton" },
  "jitter": {},
  "modulators": {
    "lfo": [
      { "name": "sym_wobble", "rate_sec": 35.0, "shape": "drift",
        "targets": [ { "to": "symmetry", "amount": 0.3 } ] }
    ],
    "tween": [
      { "name": "build", "secs": 275.0, "curve": "ease_in", "from": 0.0, "to": 1.0,
        "targets": [
          { "to": "energy",  "amount": 0.5 },
          { "to": "density", "amount": 0.4 },
          { "to": "loop_period", "amount": -7.7 }
        ] }
    ],
    "envelope": [
      { "name": "flash", "event": "burst", "attack": 0.04, "decay": 0.6, "peak": 1.0,
        "targets": [ { "to": "glow", "amount": 0.5 } ] }
    ]
  }
}
```

- `to` names a superparam or a global param. Unknown names warn (like unknown
  macros/overrides today).
- `shape` ∈ `sine | triangle | drift` (`drift` = the director's two-incommensurate-
  sines, for organic non-repeating motion).
- `curve` ∈ `linear | ease_in | ease_out | smooth` (reuses MacroMapper curves) —
  this is the knob that fixes "the opening is too dark": you pick the build's
  shape explicitly.

## Events

The framework owns a tiny event bus; each model declares its **event vocabulary**
(its inherent triggers) and emits events. `SimModel` gains `emit_event(name:
String)`. On emit, every envelope subscribed to `name` spawns an instance.

- **radial_burst** emits `burst` on each ignition (both primary and sympathetic).

(Other models, when migrated, declare their own: e.g. supernova `detonation`,
peg_cascade `chain` / `ball_fired`, matter_cycle `shatter` / `condense`.)

## Per-frame pipeline (SimModel)

Each frame (replacing the director tick + the build's `_build_p` scaling):

1. Tick the modulation stack (`t += delta`); advance/cull envelope instances.
2. Compose `params` per the layered rule above (live superparams → globals →
   param-targeted offsets).
3. `apply_live(params)` pushes ambient globals to their live nodes (as today).

Items still read `params[...]` at creation — now those are the *composed* values,
so seeding is automatic. Model code mostly reads `params` exactly as before.

## File structure

- `common/core/mod_sources.gd` — pure, unit-tested source functions:
  `lfo(t, rate, shape) -> float` (∈[-1,1]), `tween(t, secs, curve, from, to) ->
  float`, `envelope(age, attack, decay, peak) -> float` (∈[0,peak]).
- `common/core/modulation.gd` — the `ModStack`: parses `modulators`, holds
  envelope instances + event subscriptions, composes `params` each frame using
  `mod_sources` + `MacroMapper`.
- `common/core/sim_model.gd` — own a `ModStack`; add `emit_event`; tick + compose
  in `_process`.
- `common/core/preset_io.gd` — load/save `modulators` (replacing `director`).
- `radial_burst/main.gd` — emit `burst`; drop `build_*` params and `_build_p`
  scaling; its params become the modulation destinations.

## v1 scope (radial_burst proving ground)

**In:** the source types (superparam/LFO/tween/envelope), the layered composition,
the event bus, the `modulators` preset format, radial_burst emitting `burst` and a
`pulsar` preset rebuilt on the new model (build → tween on `energy`/`density`/
`loop_period`; an LFO for texture; a `burst`→`glow` envelope as the event-path
proof).

**Deferred (not built until a consumer needs them):**
- **Item-param envelopes** (the `seed + own envelope` per-frame item update) —
  radial_burst has no CPU-tracked items (bursts are fire-and-forget GPU; per the
  decision, we do **not** track bursts as CPU nodes). This path is designed for
  but unbuilt until we convert a CPU-item model (peg_cascade / matter_cycle /
  supernova).
- **Multi-keyframe tweens** (v1 tween is 2-point from→to + curve).
- **Full tweak-panel matrix UI.** v1 panel: each param row shows its **live
  composed value** next to the base control, and a read-only list of active
  modulators. Editing the matrix lives in the preset JSON for v1.
- **Migrating other models off `director`.** `director.gd` stays for
  supernova/odyssey until their own passes; it is deleted once all models migrate.

## Verification

- `mod_sources.gd` is pure → TDD unit tests (LFO bipolar range + periodicity;
  tween endpoints + curve; envelope attack/decay shape + zero-after; determinism).
- `ModStack` composition → unit tests (superparam offset clamps 0..1; param
  additive offset clamps to min/max; polyphonic envelope summing; unknown-target
  warnings).
- radial_burst: existing suite stays green; headless smokes (default + pulsar)
  clean; a 300s `pulsar` render the user reviews.
- Determinism preserved (all randomness via seeded streams; per-frame recompose
  uses a fresh seeded rng for jitter, as `resolve_live` does today).

## Out of scope

No new visual mechanics for radial_burst beyond what's needed to exercise the
system. This is an architecture change; the *look* should be reachable to where
pulsar already is, now expressed as modulators you can reason about.
