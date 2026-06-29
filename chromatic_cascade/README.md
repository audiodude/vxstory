# chromatic_cascade

Balls drop through a field of pegs, each collision injecting a splash of dye into an
underlying fluid simulation. The fluid advects, diffuses, and persists — building up a
painting that evolves with every bounce. When enough nearby hits cluster in a short
window, a chain-blast detonates: pegs shatter, balls scatter, and a shockwave churns the
ink field. Destroyed pegs respawn on a timer so the field regenerates. Three color palettes
(classic blue/orange/white, neon pink/teal/green, grayscale mono) shape everything from
pegs to particle fx.

## Superparameters

The 0..1 macro dials — each shifts many low-level params at once.

- **complexity** — at 0: ~40 pegs, no spinning hubs; at 1: ~200 pegs with up to 4
  rotating spinner arms. Controls overall structural density of the peg field.
- **ball_rate** — at 0: one ball every ~1.2 s; at 1: one ball every ~0.12 s. Scales
  the spawn tempo from a slow trickle to a rapid stream.
- **ink** — at 0: small (r≈25), faint dye injections per hit; at 1: wide (r≈100),
  vivid splashes. Controls how aggressively each ball-peg contact paints the fluid.
- **shockwave** — at 0: chain blasts are modest (radius≈100, impulse≈100, low fluid
  churn); at 1: enormous detonations (radius≈320, impulse≈1200) that scatter every
  nearby ball and violently smear the dye field.

## Parameters

Low-level knobs (pin exact values via a preset's `overrides`).

- **layout** (`enum`, default `"mixed"`) — peg field arrangement.
  Options: `"rings"` (concentric arc rows around a central point), `"grid"` (offset
  brick-pattern rows), `"spinners"` (only rotating hub-and-arm clusters), `"mixed"`
  (ring core + grid border + spinners). Not live — requires restart.
- **peg_count** (`int`, 20–240, default `110`) — total number of pegs placed (scatter-
  filled or trimmed to this budget after the layout is generated). Not live.
  Driven by the `complexity` macro (range 40–200).
- **peg_radius** (`float`, 8.0–26.0, default `14.0`) — collision and draw radius of
  each peg in pixels. Not live.
- **spinner_count** (`int`, 0–4, default `2`) — number of rotating hub nodes, each
  carrying 12 pegs on two-length arms. Not live. Driven by `complexity` (range 0–4).
- **spinner_speed** (`float`, 0.2–3.0, default `1.0`) — rotation rate of spinner hubs
  in rad/s (alternates sign per hub). Not live. Seeded per-run jitter ±25%.
- **fire_interval** (`float`, 0.1–2.0, default `0.45`) — seconds between ball spawns.
  Driven by `ball_rate` (range 1.2→0.12, inverted: higher macro = shorter interval).
- **ball_speed** (`float`, 400.0–1600.0, default `900.0`) — initial launch speed of
  each ball in px/s.
- **ball_radius** (`float`, 6.0–18.0, default `11.0`) — collision and draw radius of
  balls. Not live.
- **bounce** (`float`, 0.3–1.0, default `0.8`) — physics material restitution; 1.0 is
  perfectly elastic. Applies to both pegs and balls.
- **sweep_range** (`float`, 0.0–1.2, default `0.7`) — half-angle (in radians) of the
  sinusoidal left-right sweep applied to each ball's launch direction. 0 fires straight
  down; 1.2 sweeps nearly horizontal.
- **sweep_speed** (`float`, 0.1–3.0, default `0.8`) — oscillation frequency of the
  launch sweep in cycles/s (before the ×0.25 TAU factor in the code).
- **chain_trigger** (`int`, 2–8, default `4`) — minimum number of recent hits (within
  the last second, within `chain_radius`) required to detonate a chain-blast.
- **chain_radius** (`float`, 60.0–400.0, default `180.0`) — radius in pixels used for
  both clustering chain-trigger hits and for the blast's peg-kill and ball-impulse zone.
  Driven by `shockwave` (range 100–320).
- **blast_impulse** (`float`, 0.0–1500.0, default `600.0`) — outward impulse (px/s)
  applied to balls inside the chain-blast radius. Driven by `shockwave` (range 100–1200).
- **respawn_period** (`float`, 2.0–20.0, default `8.0`) — seconds between respawn
  passes that revive any dead pegs.
- **max_balls** (`int`, 4–80, default `28`) — cap on simultaneous live balls;
  new spawns are suppressed while at or above this limit.
- **hot_fraction** (`float`, 0.0–1.0, default `0.2`) — fraction of pegs randomly
  designated "hot" (drawn in the palette's accent color and injecting accent-colored dye
  on contact). Not live.
- **glow** (`float`, 0.0–3.0, default `0.8`) — Godot `Environment` glow intensity
  (additive blend mode). Controls bloom brightness over the whole scene.
- **palette** (`enum`, default `"classic"`) — color scheme applied to pegs, hot-pegs,
  and balls. Options: `"classic"` (blue pegs, orange hot, white balls), `"neon"` (pink
  pegs, cyan-green hot, lime balls), `"mono"` (mid-gray pegs, near-white hot and balls).
  Not live.
- **ink_radius** (`float`, 20.0–200.0, default `70.0`) — radius of dye injected into
  the fluid on each peg hit. Driven by `ink` (range 25–100).
- **ink_strength** (`float`, 0.1–2.0, default `0.8`) — intensity of dye injected on
  each hit. Driven by `ink` (range 0.5–1.5).
- **wake_strength** (`float`, 0.0–0.4, default `0.0`) — dye injected continuously
  along each ball's path (up to 10 balls per frame). 0 disables ball wakes entirely.
- **fluid_dissipation** (`float`, 0.9–0.999, default `0.992`) — per-step decay
  multiplier on the dye field. Values near 1.0 make ink near-permanent; lower values
  cause it to fade quickly.
- **fluid_noise** (`float`, 0.0–2.5, default `0.8`) — strength of Perlin-style noise
  stirred into the fluid velocity field each step.
- **fluid_flow** (`float`, 0.2–3.0, default `1.2`) — base advection speed of the fluid
  simulation's background vortex flow.
- **shock_power** (`float`, 0.0–2.0, default `0.6`) — magnitude of the fluid impulse
  injected at the chain-blast epicenter (via `fluid.add_impulse`). Driven by `shockwave`
  (range 0.15–1.5).

## Events

Discrete moments emitted for envelope modulation:

- `hit` — fires on every ball-peg contact (once per peg, debounced while the peg is
  still lit from a recent hit).
- `chain` — fires when a chain-blast detonates (enough clustered hits in a short window).

## Presets

- `default` — mid-range everything: balanced peg density, steady ball stream, visible
  dye splashes, moderate chain blasts. The schema baseline.
- `watercolor` — high `ink` (0.9), low `shockwave` (0.3), near-permanent dissipation
  (0.995) and a faint ball wake: ink pools build slowly into a luminous pastel wash with
  no violent disruptions.
- `paintstorm` — neon palette, rapid balls (`ball_rate` 0.9), maximum ink and shockwave
  (both 0.95): neon pegs disappear in clouds of magenta and white dye, chains explode
  constantly and smear the whole field.
- `fresco` — 5-minute long-form modulation starting sparse and quiet: a tween builds
  `ball_rate` and `ink` over 275 s; a 60 s LFO breathes `complexity`; each `chain`
  event triggers a short ink-surge envelope.
