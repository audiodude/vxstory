# peg_cascade finishing pass — engine design

_Date: 2026-07-06. Status: approved (user), implementation via subagent-driven-development._

## Goal

Make `peg_cascade` hold attention for 300 s: replace the static random-ish peg field
with a **legible morphing playfield** (pattern eras + glide), replace the single fixed
ball emitter with **parameterized drops**, and add **hue drift**. All new behavior is
driven by live params so the Designer choreographs the whole arc.

## 1. Pattern-era playfield

### patterns.gd (new file, `peg_cascade/patterns.gd`)

Pure static functions; no scene access, no RNG. Board constants:

- Center `C = Vector2(960, 620)`.
- All patterns are elliptically scaled (x stretched 1.5×) so they fill the 16:9 frame.

`static func positions(pattern: int, n: int) -> PackedVector2Array`
— `pattern` is wrapped `posmod(pattern, 3)`; returns **exactly `n`** positions,
**sorted by polar angle about C (radius as tiebreaker)**. The sort gives peg *i* in
one pattern a coherent partner in the next, so glides read as a radial swirl.

Generators:

- **0 — hex lattice**: staggered rows filling x 240–1680, y 300–980.
  `cols = max(3, int(round(sqrt(n * 1440.0 / 680.0))))`, `rows = ceili(n / cols)`,
  spacing derived from region / (cols, rows); odd rows offset half a column; the final
  (partial) row is center-justified.
- **1 — concentric rings**: ellipses about C. Ring count
  `rings = clampi(int(round(sqrt(n / 6.0))), 2, 6)`; vertical radii `ry` evenly spaced
  from 110 to 360, `rx = ry * 1.5`. Pegs allocated per ring proportional to `ry`
  (≈ circumference), the outermost ring absorbs the rounding remainder. Even angular
  spacing per ring, ring k phase-offset by `k * 0.35` rad.
- **2 — radial spokes**: `S = clampi(int(round(n / 10.0)), 6, 20)` spokes at even
  angles; each spoke is a line of pegs from inner radius 100 to outer 360 (elliptical:
  offset = `Vector2(cos(a) * 1.5, sin(a)) * r`), evenly spaced along the spoke.
  Spoke lengths balanced so the total is exactly `n` (first `n % S` spokes get the
  extra peg).

### Driver params (schema)

- `pattern_phase` (float, 0.0–3.0, default 0.0, **live**) — integer part selects the
  era (hex → rings → spokes; 3.0 wraps to hex so an LFO can cycle), fractional part is
  morph progress through the era interval.
- `morph_dwell` (float, 0.0–0.9, default 0.7, **live**) — fraction of each unit
  interval spent AT REST in the pure pattern. Glide occupies the remainder, eased with
  `smoothstep`. `f <= dwell → t = 0`; else `t = smoothstep(0,1,(f-dwell)/(1-dwell))`.
  Peg position = `lerp(positions(era)[i], positions(era+1)[i], t)`.

Position sets are cached per era index at restart-resolution (`n` fixed between
restarts); cache cleared on `restart()`.

### Field vs spinner pegs

- **Field pegs**: count = `peg_count`, positions fully owned by the pattern system,
  re-set every frame from `pattern_phase` (StaticBody2D positions moved directly; balls
  collide with gliding pegs).
- **Spinner pegs**: unchanged overlay — `spinner_count` hubs × 12 pegs each, parented
  to rotating hubs, **in addition to** `peg_count`. They keep `parent_idx >= 0` in
  `peg_defs`; field pegs get a `pattern_i` index instead. Chain destruction and
  respawn cover both kinds; a respawning field peg appears at the *current
  interpolated* pattern position.

### Removed

- The `layout` enum param, the grid/scatter generators, and the scatter top-up/trim.
  Presets referencing `layout` are patched (no back-compat constraint).

## 2. Parameterized drops

New live params (all hot-patchable; read at fire time):

- `drop_x` (float, 0.0–1.0, default 0.5) — emitter-group center, mapped to x 160–1760, y = 60.
- `emitter_count` (int, 1–3, default 1) — emitters at `drop_x` center with fixed
  350 px spacing (1: `[0]`; 2: `[-175, +175]`; 3: `[-350, 0, +350]`), each clamped to
  x 120–1800.
- `volley_count` (int, 1–7, default 1) — balls per fire event per emitter, fanned.
- `volley_spread` (float, 0.0–0.8 rad, default 0.35) — fan half-angle (evenly spaced
  offsets in `[-spread, +spread]`; single ball fires at offset 0).
- `aim_bias` (float, 0.0–1.0, default 0.0) — launch direction blends
  `lerp_angle(sweep_angle, angle_to_C, aim_bias)` where `sweep_angle` is the existing
  `PI/2 + sin(sim_t * sweep_speed * TAU * 0.25) * sweep_range`.

Fire logic: when `fire_acc >= fire_interval`, spawn `emitter_count × volley_count`
balls (stopping at `max_balls`); emit the `spawn` event **once per fire moment** (if
at least one ball spawned), not per ball.

## 3. Hue drift

- `hue_drift` (float, 0.0–1.0, default 0.0, **live**) — palette hue rotation in full
  wheel turns.
- The working palette `pal` is a **mutable Dictionary shared by reference** with every
  Peg and Ball (they store `pal` + a role key `"peg"|"hot"|"ball"` instead of a baked
  Color). `apply_live` rotates each base-palette color's hue by `hue_drift` (via
  `Color.h = fposmod(base.h + drift, 1.0)`), mutating `pal` in place, and queues
  redraws on all pegs/balls — only when the value moved by > 0.0005.

## 4. Schema delta summary

Removed: `layout`.
Added: `pattern_phase`, `morph_dwell`, `drop_x`, `emitter_count`, `volley_count`,
`volley_spread`, `aim_bias`, `hue_drift` (ranges/defaults above; all live).
Macros unchanged (`complexity`, `ball_rate`, `bounciness`, `fx`); `complexity` still
maps `peg_count` 40–200 and `spinner_count` 0–4.
Events unchanged (`spawn`, `hit`, `chain`).

## 5. Presets, README, Designer retune

- `clockwork.json` retuned as the long-form flagship: tween `pattern_phase` 0→3 over
  the piece, LFO on `drop_x`, a volley/fx build, slow `hue_drift` ramp, `chain`
  envelope kept.
- `default.json`, `pachinko_riot.json`, `zen_garden.json`: drop `layout` overrides;
  `zen_garden` pins `pattern_phase: 1.0` (rings).
- `peg_cascade/README.md` updated (params/superparams/events/presets) per the
  standing per-model-README rule.

## 6. Testing & verification

- Unit tests in `common/core/tests/run_tests.gd` for `patterns.gd` (guarded with
  `ResourceLoader.exists("res://patterns.gd")` so they self-skip under other models):
  exact count for assorted `n`, bounds, sort order, determinism. Suite run under both
  `radial_burst` and `peg_cascade`.
- Headless smoke of preview + designer; 60 s proof render of retuned `clockwork`
  (`scripts/render.sh`) — the user reviews aesthetics (cheap checks only on our side).
