# peg_cascade

A Peggle-style physics piece on a living board: balls rain from parameterized emitters at the top, carom off a field of glowing pegs, and trigger chain detonations that blast pegs off the board and kick every ball in range. The peg field itself is choreography — it morphs between legible patterns (hex lattice → concentric rings → radial spokes), resting in each era then gliding every peg to its partner position in the next. Destroyed pegs respawn on a slow cycle, spinner hubs rotate through every era, and the whole palette can drift around the hue wheel across a piece.

## Superparameters

The 0..1 macro dials — each shifts many low-level params at once.

- **complexity** — 0 gives a sparse field (40 pegs, no spinners); 1 packs the board (200 pegs, 4 rotating arm clusters). Drives visual density and collision frequency.
- **ball_rate** — 0 fires roughly every 1.2 seconds; 1 fires at near-continuous pace (~0.12 s interval). Controls how busy the sim feels.
- **bounciness** — 0 gives deadened, low-restitution collisions (bounce ≈ 0.45); 1 makes the physics elastic and ricochety (bounce ≈ 0.98).
- **fx** — scales the chain-blast radius (100 → 320 px) and the impulse kick applied to nearby balls (100 → 1200). Low = small local pops; high = screen-wide demolitions.

## Parameters

Low-level knobs (pin exact values via a preset's `overrides`). Parameters marked *(restart)* take effect only on scene restart — they cannot be hot-patched mid-run.

### Playfield

- **peg_count** (`int`, 20–240, default `110`) *(restart)* — number of FIELD pegs (pattern-owned). Spinner pegs are extra, on top of this.
- **peg_radius** (`float`, 8.0–26.0, default `14.0`) *(restart)* — collision + draw radius of each peg.
- **pattern_phase** (`float`, 0.0–3.0, default `0.0`) — the morph driver. Integer part picks the era (0 hex lattice, 1 concentric rings, 2 radial spokes; 3 wraps to hex), fractional part is progress through that era's interval. Tween it 0→3 to walk the whole sequence; LFO it to rock between patterns.
- **morph_dwell** (`float`, 0.0–0.9, default `0.7`) — fraction of each era interval spent AT REST in the pure pattern; the remainder is the smoothstepped glide to the next pattern. 0 = perpetual slow drift, 0.9 = long rests with quick snaps.
- **spinner_count** (`int`, 0–4, default `2`) *(restart)* — rotating peg-arm hubs (12 pegs each, alternating CW/CCW), overlaid on the pattern field.
- **spinner_speed** (`float`, 0.2–3.0, default `1.0`) *(restart)* — hub angular speed in rad/s; 25% seeded jitter per hub.
- **hot_fraction** (`float`, 0.0–1.0, default `0.25`) *(restart)* — proportion of pegs using the palette's accent colour.

### Drops

- **fire_interval** (`float`, 0.1–2.0, default `0.45`) — seconds between fire moments.
- **drop_x** (`float`, 0.0–1.0, default `0.5`) — emitter-group center across the top edge (maps to x 160–1760). LFO it to sweep the rain across the board.
- **emitter_count** (`int`, 1–3, default `1`) — simultaneous emitters, spaced 350 px around `drop_x`.
- **volley_count** (`int`, 1–7, default `1`) — balls per fire moment per emitter, fanned evenly.
- **volley_spread** (`float`, 0.0–0.8, default `0.35`) — fan half-angle in radians (matters when volley_count > 1).
- **aim_bias** (`float`, 0.0–1.0, default `0.0`) — blends launch direction from "down + sweep oscillation" (0) toward "aimed at board center" (1).
- **sweep_range** (`float`, 0.0–1.2, default `0.7`) — half-width of the launch-angle oscillation in radians.
- **sweep_speed** (`float`, 0.1–3.0, default `0.8`) — oscillation rate of the launch angle.
- **ball_speed** (`float`, 400.0–1600.0, default `900.0`) — launch speed in px/s.
- **ball_radius** (`float`, 6.0–18.0, default `11.0`) *(restart)* — ball radius.
- **max_balls** (`int`, 4–80, default `28`) — cap on simultaneously active balls; fire moments stop spawning at the cap.

### Physics & chains

- **bounce** (`float`, 0.3–1.0, default `0.8`) — restitution on every peg/ball collision.
- **chain_trigger** (`int`, 2–8, default `4`) — recent hits (last second, within `chain_radius`) required to detonate.
- **chain_radius** (`float`, 60.0–400.0, default `180.0`) — chain detection + blast radius.
- **blast_impulse** (`float`, 0.0–1500.0, default `600.0`) — radial kick applied to balls caught in a blast.
- **respawn_period** (`float`, 2.0–20.0, default `8.0`) — seconds between respawn sweeps for destroyed pegs (they reappear at their CURRENT pattern position).

### Look

- **hue_drift** (`float`, 0.0–90.0, default `0.0`) — palette hue rotation in degrees per minute, integrated over the run (same convention as `radial_burst` / `supernova_orbit`). ~25°/min drifts the palette a third of the wheel across a 5-minute piece.
- **glow** (`float`, 0.0–3.0, default `1.3`) — additive glow intensity.
- **palette** (`enum`, default `"classic"`) *(restart)* — base colour scheme: `classic` (blue/orange/white), `neon` (pink/cyan/chartreuse), `mono` (greys — note hue_drift has no visible effect on pure greys).

## Events

Discrete moments emitted for envelope modulation:

- `spawn` — fires once per fire moment (a volley of several balls emits ONE spawn event).
- `hit` — fires each time a ball contacts a peg (debounced: suppressed if the peg was struck within the last ~0.5 s).
- `chain` — fires when a cluster of recent hits crosses the `chain_trigger` threshold, triggering a chain detonation.

## Presets

- `default` — balanced mid-range settings; static hex-era board, classic palette.
- `clockwork` — the 300 s long-form flagship: pattern_phase walks hex → rings → spokes → hex with resting eras and glide transitions, drops sweep the top on a slow LFO with center-aim bias, volleys and fx build across the piece, and the palette drifts a third of the hue wheel.
- `pachinko_riot` — high ball rate, low chain threshold, big blasts — near-continuous demolition, neon.
- `zen_garden` — pinned to the rings era, sparse pegs, mono palette; hypnotic and low-chaos.
