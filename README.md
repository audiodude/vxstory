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

    godot --path <model>            # Tab toggles the tweak panel

Panel: macro dials on top, low-level params below (editing pins a param: ✕ unpins),
Save/Load JSON presets, Reroll seed, Restart.

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

Each model ships two named variants. Descriptions below are from their actual renders.

**radial_burst**
- `gentle` — a soft sea-urchin of fine ice-blue streaks breathing out of the dark every
  8 seconds, no mirror, low density. Delicate, almost botanical.
- `cataclysm` — relentless full-screen quad-mirrored detonations every 3 seconds; dense
  white streak fields with heavy spread chaos and fast-fading trails. Pure violence.

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

## Tests

    godot --headless --path radial_burst --script res://core/tests/run_tests.gd

Expected: `TESTS: 17 run, 0 failed`

## Layout

```
vxstory/
  common/
    core/          # framework: RNGService, ParamSchema, MacroMapper, PresetIO,
    │              #            RenderDriver, SimModel, TweakPanel
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
