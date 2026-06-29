# radial_burst

Periodic starburst explosions: one to six independent sources each fire a radial spray of
streak particles, a ring of expanding arcs, and a cluster of satellite sub-bursts. The
frame accumulates additively between ignitions, producing trail glow that the next burst
cuts through. An optional mirror pass folds the sim symmetrically before output.

## Superparameters

The 0..1 macro dials — each shifts many low-level params at once.

- **energy** — raising it makes bursts faster, longer-streaked, and spawns more expanding
  rings per ignition (drives `burst_speed` 120→400, `streak_len` 10→45, `ring_count` 1→6).
- **density** — more particles per burst and more satellite sub-bursts; the canvas fills
  faster and stays busier between ignitions (drives `particle_count` 2000→7000,
  `subburst_count` 2→18).
- **symmetry** — increases the opacity of the mirrored copy blended over the output,
  strengthening the bilateral or quad-fold reflection (drives `mirror_mix` 0→0.9).
- **grit** — widens the velocity spread so streaks fan out chaotically instead of
  radiating in a clean shell (drives `speed_spread` 0.25→0.85).
- **coupling** — enables sympathetic ignition: nearby sources catch fire after a primary
  burst, with a propagation delay based on distance and `ripple_speed`
  (drives `sympathy` 0→1).

## Parameters

Low-level knobs (pin exact values via a preset's `overrides`).

- **loop_period** (`float`, 2.0–12.0, default `5.0`) — seconds between ignitions for each
  source (±15% seeded jitter applied per source).
- **source_count** (`int`, 1–6, default `1`) — number of independent burst origins placed
  around the canvas centre.
- **particle_count** (`int`, 500–20000, default `4500`) — particle budget for each main
  burst emitter.
- **burst_speed** (`float`, 50.0–900.0, default `260.0`) — nominal initial velocity of
  emitted particles (pixels/second).
- **speed_spread** (`float`, 0.0–0.9, default `0.55`) — fractional velocity variance;
  0 = tight shell, 0.9 = wide fan with fast and slow streaks mixed.
- **particle_life** (`float`, 0.5–6.0, default `3.5`) — particle lifetime in seconds
  before each streak fades out.
- **damping** (`float`, 0.0–200.0, default `60.0`) — velocity decay rate; higher values
  slow streaks to a stop more quickly.
- **streak_len** (`float`, 5.0–80.0, default `27.5`) — visual length of each streak
  particle (controls the emitter's scale range).
- **trail_persist** (`float`, 0.02–0.5, default `0.10`) — alpha of the black fade rect
  drawn each frame; lower = longer-lived trails, higher = fast erasure between bursts.
- **ring_count** (`int`, 0–8, default `3`) — number of expanding arc rings launched per
  ignition; 0 disables rings entirely.
- **ring_speed** (`float`, 100.0–1600.0, default `600.0`) — expansion speed of each ring
  in pixels/second (±30% per-ring jitter applied).
- **ring_width** (`float`, 1.0–18.0, default `5.0`) — stroke thickness of each ring arc
  in pixels.
- **subburst_count** (`int`, 0–24, default `9`) — satellite sub-emitters launched at
  random angles around the main burst centre; 0 disables sub-bursts.
- **subburst_scale** (`float`, 0.05–0.5, default `0.22`) — sub-burst particle count and
  speed relative to the main emitter.
- **sympathy** (`float`, 0.0–1.0, default `0.0`) — probability/strength of sympathetic
  cascades: after a primary ignition, nearby sources may catch and fire with a travel-time
  delay. Has no effect with a single source.
- **sympathy_radius** (`float`, 50.0–1200.0, default `500.0`) — maximum distance in pixels
  within which a source can be caught by a sympathetic cascade.
- **ripple_speed** (`float`, 200.0–4000.0, default `1600.0`) — speed of the sympathetic
  ignition wavefront (pixels/second); sets the delay between the primary and caught
  sources.
- **hue_drift** (`float`, 0.0–90.0, default `0.0`) — hue rotation in degrees per minute
  of simulation time; slowly shifts the burst colour over a long render.
- **mirror** (`enum`, default `horizontal`) — symmetry mode applied to the output:
  - `off` — no mirroring; raw sim output.
  - `horizontal` — left half additively blended with a flipped right copy.
  - `quad` — all four quadrants folded and blended, producing full bilateral symmetry.
- **mirror_mix** (`float`, 0.0–1.0, default `0.55`) — opacity of the mirrored copies;
  0 = only the unflipped frame, 1 = fully symmetric blend.
- **glow** (`float`, 0.0–3.0, default `0.35`) — Godot environment glow intensity (softlight
  blend mode); amplifies bright particle cores.
- **palette** (`enum`, default `silver`) — colour set assigned to burst sources:
  - `silver` — white and cool grey.
  - `bone` — warm white and tan.
  - `ice` — pale blue and sky blue.
  - `danger` — station red, white, and periwinkle (Danger Third Rail signature palette).
  - `galton` — 12 vibrant hues from the galton-board palette.

## Events

Discrete moments emitted for envelope modulation:

- `burst` — fires each time any source ignites (primary or sympathetic).

## Presets

- `gentle` — a soft sea-urchin of fine ice-blue streaks breathing out of the dark every
  8 seconds, no mirror, low density. Delicate, almost botanical.
- `cataclysm` — relentless full-screen quad-mirrored detonations every 3 seconds; dense
  white streak fields with heavy spread chaos and fast-fading trails. Pure violence.
- `pulsar` — 5-minute long-form on the unified modulation model: four burst sources on the
  12-hue `galton` palette, driven by a tween ("build") that raises energy/density/coupling
  and tightens `loop_period` over 275s (small + rare → large + frequent + sympathetically
  chained), an LFO drifting `grit` for texture, and a per-`burst` envelope flashing the
  ambient `glow`. Seed-shuffled hues, so each render differs.
