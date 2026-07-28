# vxstory

Seven parameterized generative video models in Godot 4.6. No sound — pure visuals.

| Model | What it is |
|---|---|
| `radial_burst` | Monochrome streak starburst: rings, sub-bursts, mirror symmetry |
| `fluid_swirl` | Psychedelic marbled dye advection |
| `peg_cascade` | Peggle-style ball/peg kinetics with chain detonations |
| `chromatic_cascade` | Peg physics driving a reactive ink/dye field |
| `matter_cycle` | Polygons shatter to particles, swirl, re-condense — forever |
| `supernova_orbit` | Accretion → critical mass → detonation cycle |
| `metro_rise` | 3D era-city: dawn-to-night build-out, brick→concrete→glass, traffic + cranes |

## Preview / tune

    godot --path <model>                                                           # schema defaults
    godot --path <model> -- --preset presets/<name>.json                           # start from a preset
    godot --path <model> -- --designer --preset presets/<name>.json                # tune a scene visually (Designer)

Examples:

    godot --path supernova_orbit -- --preset presets/strobe_core.json
    godot --path fluid_swirl -- --preset presets/lava_lamp.json

The Designer writes `scene.json` (the preset file) on every edit, which the preview hot-reloads.
The preset path is relative to the model's project dir (absolute paths work too).
Tab toggles the tweak panel: macro dials on top, low-level params below (editing pins
a param: ✕ unpins), Save/Load JSON presets, Reroll seed, Restart. The Load button is
the in-app alternative — it opens a file dialog over the model's `presets/` dir.

## Render

    scripts/render.sh <model> <preset> [duration_sec]
    # e.g. scripts/render.sh radial_burst cataclysm 30

    scripts/render-batch.sh [duration_sec] [model:preset ...]
    # no preset args = the long-form set (one per model); e.g. render-batch.sh 60 for quick proofs

Output: `renders/<model>_<preset>.mp4` (1920×1080 @ 60fps). Uses Godot Movie Maker
mode — renders every frame at exactly 60fps, never drops. Requires a display
(X11/Wayland); `xvfb-run` can be used if headless GPU is needed.

## Presets

JSON files in `<model>/presets/`. Format:

```json
{
  "model": "radial_burst",
  "seed": 7041,
  "duration_sec": 30.0,
  "macros": {"energy": 0.72, "density": 0.6},
  "overrides": {},
  "jitter": {}
}
```

- `macros` — 0..1 dials that map onto many params simultaneously (see each model's `get_schema()`)
- `overrides` — pin exact param values (bypass macro mapping)
- `jitter` — seeded per-param noise: `{"pct": 15}` (±15%) or `{"abs": 2}` (±2 units)
- Same preset + different `seed` = visually related but uniquely different variant

### Modulation

An optional preset key that animates macros and params over time via composable sources
authored in the Designer (`--designer`):

```json
"modulators": {
  "tween": [{"name": "build", "secs": 275.0, "curve": "ease_in", "from": 0.0, "to": 1.0,
             "targets": [{"to": "energy", "amount": 0.5}]}],
  "lfo":   [{"name": "drift", "oscillators": [{"shape": "sine", "period_sec": 40.0,
             "phase_deg": 0.0, "amount": 0.6}], "targets": [{"to": "grit", "amount": 0.2}]}],
  "envelope": [{"name": "flash", "event": "burst", "attack": 0.05, "decay": 0.4, "peak": 1.0,
               "targets": [{"to": "glow", "amount": 1.0}]}]
}
```

Each source type composes additively each frame. Tweens sweep a macro from a start value
to an end value over a fixed duration. LFOs sum one or more oscillators (sine/triangle/saw/square)
to drift a target continuously. Envelopes fire on named model events (attack + decay) and
stack polyphonically. All modulation is deterministic and clock-driven — the same preset
plays back identically every render.

### Models vs presets vs seeds

Presets are pure data — every preset of a model runs the exact same code through the
same resolution pipeline. The taxonomy:

- **Models** differ in code.
- **Presets** differ in parameters. Most of a variant's character comes from its macro
  values (e.g. `strobe_core` vs `slow_burn` is mostly the `critical_mass` dial: ~440 vs
  ~1440 absorbed mass per detonation). Where a variant feels like a different *mode*,
  it's an enum override selecting a code path that exists in every run — `zen_garden`
  pins `layout: "rings"`, `cataclysm` pins `mirror: "quad"`.
- **Seeds** differ in dice rolls: jitter, layouts, spawn timing, injector paths. Same
  preset + new seed = a structural sibling, different in detail.

Parameter changes can still flip emergent behavior — peg cascade with a low
`chain_trigger` and big `chain_radius` goes from "pinball" to "constant demolition" —
but that's all initialization, never per-preset branching. Tweak dials in the panel and
hit Save: your preset has equal standing with the shipped twelve.

### Variation presets

Each model ships two named variants. Load one in preview
(`godot --path <model> -- --preset presets/<variant>.json`), render it
(`scripts/render.sh <model> <variant> [secs]`), or open it with the panel's Load
button. Descriptions below are from their actual renders.

**radial_burst**
- `gentle` — a soft sea-urchin of fine ice-blue streaks breathing out of the dark every
  8 seconds, no mirror, low density. Delicate, almost botanical.
- `cataclysm` — relentless full-screen quad-mirrored detonations every 3 seconds; dense
  white streak fields with heavy spread chaos and fast-fading trails. Pure violence.
- `pulsar` — 5-minute long-form on the unified modulation model: four burst
  sources on the 12-hue `galton` palette, driven by a **tween** ("build") that
  raises energy/density/sympathy and tightens `loop_period` over 275s (small +
  rare → large + frequent + sympathetically chained), an **LFO** drifting `grit`
  for texture, and a per-`burst` **envelope** flashing the ambient `glow`. Seed-
  shuffled hues, so each render differs.

**fluid_swirl**
- `lava_lamp` — thick, slow magma: deep reds and incandescent yellows rising and folding
  like flame in oil, high viscosity so shapes linger and ooze.
- `maelstrom` — saturated cyan/magenta/yellow turbulence at 8 vortices; the whole canvas
  shreds and recombines continuously, edge-to-edge color with no rest.
- `aurora` — 5-minute long-form modulation: a tween builds turbulence and flow from
  calm to active over 275s; a slow 75s LFO drifts vibrance for colour breathing. No
  envelope (fluid emits no discrete events).

**peg_cascade**
- `zen_garden` — grayscale meditation: dim mono pegs in loose rings, occasional white
  balls drifting through with soft glows, sparse pops. The calm one.
- `pachinko_riot` — hot-pink and cyan pegs, fast ball stream, spinning hubs, constant
  chain explosions carving holes that respawn and refill.
- `clockwork` — 5-minute long-form modulation: a tween builds ball rate and fx from
  sparse to dense over 275s; a 45s LFO oscillates complexity; each `chain` event
  triggers an fx envelope pop.

**chromatic_cascade**
- `watercolor` — luminous pastel pools (teal/pink/white) spreading slowly beneath the
  pegs; subtle ball wakes tint the wash; near-permanent dye so the painting accumulates.
- `paintstorm` — neon pegs over storm-front clouds of magenta and white ink; yellow-green
  balls; big shockwaves smear the whole field every chain.
- `fresco` — 5-minute long-form modulation: a tween builds ball rate and ink spread over
  275s; a 60s LFO breathes complexity; each `shockwave` event flashes an ink envelope.

**matter_cycle**
- `slow_genesis` — long stretches of near-empty black; lone white wireframe polygons
  drift down, quietly pile, and only rarely shatter. Minimalist and patient — it earns
  its moments.
- `grinder` — multicolor wireframes shattering on contact into white-hot particle spray;
  condensation rings fire constantly; matter churns through the full cycle in seconds.
- `tides` — 5-minute long-form modulation: a tween builds matter density and cycle speed
  over 275s; a 90s LFO undulates turbulence; each `shatter` event spikes a fragility
  envelope.

**supernova_orbit**
- `slow_burn` — three violet-and-teal spiral arms feed a purple core through one long,
  ominous 30-second charge toward a single massive detonation (void palette).
- `strobe_core` — emerald accretion at maximum inflow with a hair-trigger core:
  detonation rings every few seconds, each clearing the disk to start again.
- `odyssey` — 5-minute modulation-driven journey: two gravitationally interacting cores
  fission, orbit, and merge while an accumulating wireframe debris belt rings the
  blast sites; solar palette hue drifts 70° across the run so early amber warmth
  cools through teal by the end. Three LFOs continuously drift accretion, chaos, and
  duality over incommensurate periods — no two minutes look the same.

**metro_rise** (3D)
- `default` — mid-build afternoon: cranes over rising mid-rises, traffic, district
  contrast from downtown out to industrial fringe.
- `boomtown` — dense vertical sodium dusk: era-3 glass skyline, heavy traffic,
  neon-soaked storefronts.
- `garden_city` — low-rise parks-heavy morning: loose grid, sparse traffic, long
  soft shadows.
- `century` — 5-minute long-form: the whole city rises from empty dawn land to a lit
  night metropolis across one sun arc — brick → concrete → glass with demolition and
  replacement, traffic ramping in mid-era, envelopes pipping glow on tower topouts.
  The structural state is a pure function of the `development` dial, so the Designer
  scrubs the entire build-out exactly.

## Tests

    godot --headless --path peg_cascade --script res://core/tests/run_tests.gd

Expected: `TESTS: 67 run, 0 failed, 0 skipped`

## Layout

```
vxstory/
  common/
    core/          # framework: RNGService, ParamSchema, MacroMapper, PresetIO,
    │              #            RenderDriver, SimModel, TweakPanel, ModStack
    fluid_sim/     # shared ping-pong dye advection sim + shaders
  <model>/
    core -> ../common/core          # symlink
    fluid_sim -> ../common/fluid_sim  # symlink (models that use it)
    main.gd        # extends SimModel; implements model_name/get_schema/restart
    main.tscn      # minimal root Node2D with script
    project.godot
    presets/
      default.json
      <variant>.json
  metro_rise/      # additionally: citygen/ + sim/ (pure logic, headless-tested
                   # via tests/run_tests.gd), view/ (MultiMesh pools + shaders);
                   # the 3D world hangs under the Node2D root
  scripts/
    render.sh      # render.sh <model> <preset> [duration] -> renders/<model>_<preset>.mp4
  renders/         # output mp4s (gitignored)
```
