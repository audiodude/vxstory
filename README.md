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

### Variation presets

Each model ships two named variants:

| Model | Preset | Character |
|---|---|---|
| radial_burst | `gentle` | Sparse ice-toned bursts, slow 8s period, no mirror |
| radial_burst | `cataclysm` | Max-energy quad-mirror blast, high density, spread chaos |
| fluid_swirl | `lava_lamp` | Slow magma blobs, high viscosity, deep reds/oranges |
| fluid_swirl | `maelstrom` | Violent neon turbulence, 8 vortices, fast decay |
| peg_cascade | `zen_garden` | Sparse mono rings, slow ball rate, calm rebounds |
| peg_cascade | `pachinko_riot` | Dense neon chaos, max balls, spinning hubs, chain explosions |
| chromatic_cascade | `watercolor` | Soft lingering ink pools, slow play, subtle ball wakes |
| chromatic_cascade | `paintstorm` | Saturated neon ink chaos, max shockwaves |
| matter_cycle | `slow_genesis` | Sparse mono polygons, gentle turbulence, slow cycle |
| matter_cycle | `grinder` | Fast dense spectrum churn, rapid condensation |
| supernova_orbit | `slow_burn` | Long purple-void buildup to single massive detonation |
| supernova_orbit | `strobe_core` | Rapid emerald detonation cycles every few seconds |

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
