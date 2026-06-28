# vxstory

Six parameterized physics/particle video models in Godot 4.6. No sound — pure visuals.

| Model | What it is |
|---|---|
| `radial_burst` | Monochrome streak starburst: rings, sub-bursts, mirror symmetry |
| `fluid_swirl` | Psychedelic marbled dye advection |
| `peg_cascade` | Peggle-style ball/peg kinetics with chain detonations |
| `chromatic_cascade` | Peg physics driving a reactive ink/dye field |
| `matter_cycle` | Polygons shatter to particles, swirl, re-condense — forever |
| `supernova_orbit` | Accretion → critical mass → detonation cycle |

## Preview / tune

    godot --path <model>                                  # schema defaults
    godot --path <model> -- --preset presets/<name>.json  # start from a preset

Examples:

    godot --path supernova_orbit -- --preset presets/strobe_core.json
    godot --path fluid_swirl -- --preset presets/lava_lamp.json

The preset path is relative to the model's project dir (absolute paths work too).
Tab toggles the tweak panel: macro dials on top, low-level params below (editing pins
a param: ✕ unpins), Save/Load JSON presets, Reroll seed, Restart. The Load button is
the in-app alternative — it opens a file dialog over the model's `presets/` dir.

## Render

    scripts/render.sh <model> <preset> [duration_sec]
    # e.g. scripts/render.sh radial_burst cataclysm 30

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

### Director

An optional preset key that drifts selected macros over time via smooth seeded curves,
keeping long-form renders visually varied without manual keyframing:

```json
"director": {"enabled": true, "period_sec": 90.0, "amplitude": 0.3,
             "macros": ["accretion", "chaos", "duality"]}
```

Each listed macro follows `clamp(base + amplitude × drift(t), 0, 1)` where `base` is
the preset's macro value and `drift(t)` is two incommensurate seeded sines — smooth,
bounded, reproducible. The director ticks in `SimModel._process` and re-resolves live
params at 4 Hz. When the director is active, the tweak panel shows a cyan indicator;
user edits to a macro slider **rebase** that macro's center, so manual adjustments
still take effect and accumulate correctly.

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
  raises energy/density/coupling and tightens `loop_period` over 275s (small +
  rare → large + frequent + sympathetically chained), an **LFO** drifting `grit`
  for texture, and a per-`burst` **envelope** flashing the ambient `glow`. Seed-
  shuffled hues, so each render differs.

**fluid_swirl**
- `lava_lamp` — thick, slow magma: deep reds and incandescent yellows rising and folding
  like flame in oil, high viscosity so shapes linger and ooze.
- `maelstrom` — saturated cyan/magenta/yellow turbulence at 8 vortices; the whole canvas
  shreds and recombines continuously, edge-to-edge color with no rest.

**peg_cascade**
- `zen_garden` — grayscale meditation: dim mono pegs in loose rings, occasional white
  balls drifting through with soft glows, sparse pops. The calm one.
- `pachinko_riot` — hot-pink and cyan pegs, fast ball stream, spinning hubs, constant
  chain explosions carving holes that respawn and refill.

**chromatic_cascade**
- `watercolor` — luminous pastel pools (teal/pink/white) spreading slowly beneath the
  pegs; subtle ball wakes tint the wash; near-permanent dye so the painting accumulates.
- `paintstorm` — neon pegs over storm-front clouds of magenta and white ink; yellow-green
  balls; big shockwaves smear the whole field every chain.

**matter_cycle**
- `slow_genesis` — long stretches of near-empty black; lone white wireframe polygons
  drift down, quietly pile, and only rarely shatter. Minimalist and patient — it earns
  its moments.
- `grinder` — multicolor wireframes shattering on contact into white-hot particle spray;
  condensation rings fire constantly; matter churns through the full cycle in seconds.

**supernova_orbit**
- `slow_burn` — three violet-and-teal spiral arms feed a purple core through one long,
  ominous 30-second charge toward a single massive detonation (void palette).
- `strobe_core` — emerald accretion at maximum inflow with a hair-trigger core:
  detonation rings every few seconds, each clearing the disk to start again.
- `odyssey` — 5-minute director-driven journey: two gravitationally interacting cores
  fission, orbit, and merge while an accumulating wireframe debris belt rings the
  blast sites; solar palette hue drifts 70° across the run so early amber warmth
  cools through teal by the end. The director continuously modulates accretion, chaos,
  and duality over 90-second cycles — no two minutes look the same.

## Tests

    godot --headless --path radial_burst --script res://core/tests/run_tests.gd

Expected: `TESTS: 54 run, 0 failed`

## Layout

```
vxstory/
  common/
    core/          # framework: RNGService, ParamSchema, MacroMapper, PresetIO,
    │              #            RenderDriver, SimModel, TweakPanel, Director
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
  scripts/
    render.sh      # render.sh <model> <preset> [duration] -> renders/<model>_<preset>.mp4
  renders/         # output mp4s (gitignored)
```
