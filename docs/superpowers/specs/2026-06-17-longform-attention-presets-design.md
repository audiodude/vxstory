# Long-form attention-holding presets — design

**Date:** 2026-06-17

## Goal

Create presets that hold a viewer's attention for ~3–5 minutes across the
vxstory piece-models that lack a long-form treatment. `supernova_orbit` already
has this in `odyssey`; `text_ident` is an ident (out of scope). That leaves five
models: **radial_burst, peg_cascade, fluid_swirl, matter_cycle,
chromatic_cascade**.

Approach is **code-forward** — like `odyssey`, we add whatever per-model
mechanics are needed, not just data tuning.

## Thesis: three simultaneous timescales

Repetition is the enemy. Attention is held by layering three incommensurate
rates of change at once:

- **Fast** — the model's native action (bursts, ball hits, detonations).
- **Medium** — the **Director** drifting macros on ~90–150s seeded curves, so
  "no two minutes look alike" (existing framework feature, `common/core/director.gd`).
- **Slow** — a guaranteed full-run gradient (hue/color drift) plus occasional
  large structural events.

Each long-form preset gets all three, plus one **signature slow mechanic**
unique to its medium.

## Shared toolkit

1. **`common/core/hue.gd`** — `static func rotated(c: Color, deg: float) -> Color`,
   lifting the pattern from `supernova_orbit._hue_rotated()`. Convention: each
   model that adopts it gets a `hue_drift` param in **deg/min, default 0**, so
   every existing preset is unaffected. (Leave supernova's inline copy as-is;
   optional later refactor.)
2. **Director config** in each long-form preset (`period_sec`, `amplitude`,
   `macros`). Existing feature, no new code.
3. **Per-model signature mechanic** (the creative core, below).
4. `duration_sec: 300` in each long-form preset; **~60s 720p proof renders**
   during iteration before committing to full renders (~30+ min each).

## Build order

Two trickiest models first — they have baked structure the Director can't reach
live, and they're the two absent from the radio catalog. Each gets an
**individual, detailed pass**: implement → proof render → review, then the next.

1. **radial_burst** ("pulsar")
2. **peg_cascade** ("clockwork")

Then the three live-friendly models follow the playbook, each its own focused
pass (sketched at the end of this doc, designed in detail when reached):
fluid_swirl ("aurora"), matter_cycle ("tides"), chromatic_cascade ("fresco").

---

## radial_burst — "pulsar"

Identity: monochrome streak starburst — center burst, rings, scheduled
sub-bursts, mirror symmetry. Bursts every `loop_period` (~5s). Today only
`symmetry` drifts live; `energy`/`density`/`grit` are baked into the GPUParticles
emitters at build time, and `_fire_cycle()` re-reads only ring/sub-burst params.

### Character

`calm → riot → calm`. Director drives `energy` + `density` as one slow swell
across the run (riot in the middle), with `symmetry` + `grit` drifting on shorter
cycles for texture.

### Color (NEW — cribbed from the radio repo)

Add palettes alongside the existing `silver`/`bone`/`ice`, sourced from
`../radio.dangerthirdrail.com`:

- **`danger`** — `#ff2a2a` red (from `assets/radio-offline.html` `--red`) / white /
  deep navy `(0.05, 0.05, 0.12)` (the station background). The signature look.
- **`board`** — vibrant multi-hue drawn from the 12-color board set in
  `scripts/main.gd` (red, cyan, yellow, purple, orange, green, hot-pink, teal,
  …). Different sources carry different colors.

Each radial_burst palette is a `[bright, mid, dark]` gradient ramp; `board` is
a wider set so the multiple sources can each take a distinct hue.

A `hue_drift` param (deg/min, default 0) rotates the active palette slowly over
the run via `hue.gd`.

### Multiple interacting sources (NEW signature mechanic)

Replace the single center emitter + randomly-scattered sub-bursts with **N
independent burst sources** (`source_count`, ~2–5), positioned in the field, each
assigned a distinct hue from the palette.

Interaction is **sympathetic triggering**: when one source fires, it can set off
**nearby** sources in a cascade. The coupling strength is a new macro
**`coupling` (0..1)** that the **Director drives**:

- High `coupling` → a single ignition ripples outward as a chain reaction of
  blooms across the field; colors overlap where cascades meet.
- Low `coupling` → sources fire independently on their own staggered timers.

Triggering is evaluated in `_process` against the live `params` dict (refreshed
by `resolve_live()` on each director tick), so `coupling` drift takes effect
without a restart. `source_count` is structural (baked at build).

### Supporting code

- **Per-burst emitter re-config** so `energy`/`density` drift actually reaches
  particle count / speed / streak length on each burst (today they're frozen at
  build). Update the process material (or rebuild the emitter) when a source
  fires.
- **Optional rare mega-burst** at the riot peak — a single amplified, full-field
  ignition.

### Schema additions

- macros: `+ coupling`
- params: `+ source_count` (int), `+ sympathy_radius` (float, trigger reach),
  `+ hue_drift` (float deg/min, default 0); `palette` enum extended with
  `danger`, `board`.

---

## peg_cascade — "clockwork"

Identity: Peggle-style ball/peg kinetics, chain detonations, respawn waves. The
peg field is generated once at restart. The current `mixed` layout stacks rings +
half a grid + randomly-placed spinners + a **random scatter top-up** to hit the
peg budget — that scatter is what makes it illegible.

### Character

`calm → riot → calm`. Director drives `ball_rate` + `fx` (chain radius / blast
impulse), both live. Sparse and gentle at the ends, pachinko chaos in the middle.

### Predictable, legible playfield (FIX)

Remove the `mixed` layout's **random scatter top-up** entirely. Use only **clean,
regular geometries**: true concentric rings, an even grid, symmetric spinner
hubs. The peg budget **completes a regular pattern** rather than being padded
with random pegs — so ball paths are readable and the drops are fun to watch.

### Architecture shifts (NEW signature mechanic)

Every `morph_period` seconds the field **metamorphoses** from one clean layout to
the next (rings → grid → spinners → rings). Implemented as a mid-run rebuild
(`_morph_layout()`) that clears the current pegs and regenerates the next clean
layout **without a full restart**. Re-reads `params` on each morph, so
`complexity` drift applies to the next field. Legible within each state; never
static across the run.

### Parameterized drops (NEW)

- **Drop rate** — first-class interval between balls; the `ball_rate` macro
  drives it and the Director drifts it.
- **Ball size as a range** — `ball_size_min` / `ball_size_max` (default to a
  modest spread) so big and small balls mix in the stream. Size is sampled per
  ball at spawn.

### Schema additions

- params: `+ morph_period` (float), `+ ball_size_min`, `+ ball_size_max`
  (replacing / extending the single `ball_radius`); ensure drop rate is cleanly
  exposed; `+ hue_drift` (deg/min, default 0) for slow palette rotation on pegs.

---

## Verification (per model)

- Keep the existing unit suite green (`godot --headless --path <model>
  --script res://core/tests/run_tests.gd`); add a `hue.gd` unit test.
- Cheap headless sanity run: launches, params resolve, director enabled, no
  errors over a few seconds.
- **~60s 720p proof render** → user reviews the look.
- Iterate on feedback; **full 300s render** once the look is approved.

## Conventions

- New **named presets** (`pulsar`, `clockwork`) — pure data: macro values, a
  `director` key, and `overrides` only for long-form-specific knobs (`hue_drift`,
  etc.), mirroring how `odyssey` is built.
- All new params/macros default to **off / neutral** (`hue_drift` 0, single-color
  fallback, no morph unless set), so every existing preset and render is
  unaffected. No preset back-compat constraint on the *new* presets' looks.
- Tuning lives in schema defaults where it generalizes; per-preset overrides only
  for the long-form-specific knobs.

## Out of scope (this pass)

- fluid_swirl / matter_cycle / chromatic_cascade get only the playbook sketch
  here; each receives its own detailed design pass after the first two land.
- No refactor of `supernova_orbit`'s inline hue code.

### Playbook sketch for the deferred three

- **fluid_swirl ("aurora")** — fully live macros; Director drifts
  turbulence/flow/vibrance + slow hue voyage via a `hue_shift` uniform added to
  `grade.gdshader`. Smallest code.
- **matter_cycle ("tides")** — Director oscillates matter/cycle_speed/turbulence
  (genesis ↔ grinder) + hue drift on draw colors.
- **chromatic_cascade ("fresco")** — ink field builds and washes in slow waves
  (drift ink/dissipation) + hue drift on the ink palette; Director on
  ink/shockwave/ball_rate.
