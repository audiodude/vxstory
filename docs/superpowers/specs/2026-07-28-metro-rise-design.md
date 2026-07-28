# metro_rise — 3D era-city model (design spec)

_Approved 2026-07-28. Seventh vxstory model: a 3D city grows from empty land at dawn
to a lit metropolis at nightfall over one long-form render._

## Concept

One 300 s piece reading as a single continuous shot: the sun's lone arc across the sky
is metaphorical time. Brick low-rises at dawn, concrete mid-rises by midday, glass
towers through the afternoon — old stock demolished and replaced as eras advance — and
nightfall pays off with thousands of lit windows, streetlights, and headlight streams.
A slow orbiting camera rises and pulls back so the skyline always just-fills the frame.
Traffic appears from the concrete era on; tower cranes work the skyline throughout.
No pedestrians, no sky extras (v1).

Decisions locked with the user:
- **Style**: procedural shader facades on low-poly massing (no image assets).
- **Arc**: single-day timelapse × era progression (options "2 + 3").
- **Camera**: slow orbit + pull-back, no cuts.
- **Life**: traffic + construction cranes; pedestrians and sky extras cut.
- **Architecture**: direct 3D under the existing 2D framework (approach 1), zero
  framework changes.

## The core mechanic — two master dials

The whole model hangs on one architectural rule: **visible state is a pure function of
two live 0..1 params**, each an ordinary macro animated by the existing modulation
system.

- **`development` (P)** — at `restart()` a full **city plan** is generated from
  seed+params: roads, lots, and per-lot *timelines in P-space* (e.g. construct at
  P=0.12, demolish at P=0.55, replaced by 24-floor glass at P=0.58). Each frame
  evaluates the plan at the current P; buildings rise floor-by-floor inside their
  construction windows. Scrubbing is therefore structurally **exact** at any t
  (stronger than the repo's character-at-t bar), and dragging `development` in the
  Designer grows/ungrows the city live.
- **`day_phase`** — sun azimuth/elevation, sky gradient + stars, ambient, fog tint,
  window-lit fraction, streetlamps/headlights. Fully decoupled from P: "half-built
  city at 3pm" is one dial-drag.

The long-form preset is then just two tweens (P 0→1, day 0→1) plus garnish LFOs and
envelopes — pure schema-and-preset, per repo convention (no per-preset code paths).

Transient layers (traffic positions, crane angles, dust) follow the existing
"character-at-t" scrub convention: re-seeded/re-phased from t, not replayed.

## 3D integration (framework untouched)

- Root scene stays `Node2D` extending `res://core/sim_model.gd`. The model parents a
  3D subtree under itself: `WorldEnvironment`, `DirectionalLight3D` sun (+ dim cool
  moon light for night legibility), `Camera3D`, and city geometry. Godot renders the
  3D world behind the 2D canvas natively, so TweakPanel / Designer / Timeline /
  transport-link overlays work unchanged.
- `metro_rise/project.godot`: Forward+, 1920×1080, movie fps 60, filmic tonemap, glow,
  subtle distance fog, shadows on the sun light (long dawn/dusk shadows are half the
  payoff). All quality settings are per-project; other models unaffected.
- `restart()` frees non-CanvasLayer children per repo convention, then rebuilds.
- No physics engine anywhere: all motion is custom kinematics off the modulation
  clock / sim clock.

## City generation (seeded pure logic, `citygen/`)

- **Units**: 1 unit = 1 m. Ground plane ~2400×2400. Max city radius ~700 (scaled by
  `sprawl`).
- **Roads**: jittered arterial grid (spacing ~90–140 m) + 1–2 diagonal boulevards.
  Hierarchy: boulevard (~24 m, 2×2 lanes, median) and street (~12 m, 1×1). Roads carry
  ring indices; the footprint grows outward with P (outer roads pave in — dirt→asphalt
  fade — as their ring activates).
- **Blocks → lots**: seeded subdivision, 2–6 street-fronting lots per block side.
  Districts by distance-from-core: downtown → commercial → residential → industrial
  edge. Seeded park blocks (~7%) never build; they get scatter trees and paths.
  Downtown blocks may pre-designate one **merged tower parcel** (2×2 or 1×2 lots) at
  subdivision time, used only by an era-3 entry: when it fires, the member lots'
  buildings demolish together and one big-footprint tower constructs. (Fallback if
  hairy in implementation: single-lot towers with fatter footprints.)
- **Massing**: 1–3 stacked shrinking box tiers + parapet + roof clutter (water towers
  early eras, AC boxes/antennas late). Heights sample district×era distributions
  (floors, floor_h 3.2): era1 brick 2–6 (downtown 4–8), era2 concrete 6–18 (downtown
  10–24), era3 glass 12–40 (downtown 24–60, rare supertalls). Industrial: low, wide,
  sparse windows.

## Era timelines (`citygen/eras.gd`)

- Era of a new construction is chosen by its start-P against bands
  `era1_end≈0.34`, `era2_end≈0.66` with an overlap width (~0.08) blending
  probabilities, so the transition is a mix, not a hard cut.
- Construction duration in P units grows with floors (taller = longer on screen).
- **Replacement**: per lot, seeded demolition events with probability by district
  (core ≈0.85 per era step, edge ≈0.25). Chains like brick→concrete→glass downtown;
  brick→glass for late-activating lots; single-era at the fringe. A gap separates
  demolition and the successor's groundbreaking.
- Plan invariants (tested): per-lot entries non-overlapping in P, construction windows
  within [0,1], every lot fronts a road, era bands honored within tolerance.

## Look (view layer, `view/`)

- **Facades**: one flexible `ShaderMaterial` on MultiMesh unit-box instances
  (per-era-styled via instance CUSTOM data + COLOR tint). Face-space UVs derived from
  local position+normal; window cells at world scale (cell ~1.4–2.2 m by era,
  floor rows 3.2 m). Styles: brick = small punched windows + banding; concrete =
  ribbon windows with piers; glass = curtain wall, low roughness, sky reflections,
  ~0.85 glass fraction. Per-window hash → lit/unlit, ramping with darkness ×
  `nightlife`, mixed warm/cool interior temperatures.
- **Construction**: fragments above `progress × height` discarded; emissive scaffold
  band at the build line. Ground gets a dirt patch quad under active constructions.
- **Demolition**: quick sink + small dust puff (seeded GPUParticles one-shot;
  transient garnish, exempt from scrub-exactness like traffic).
- **Roads/ground**: ground = one plane with world-noise shader; roads/sidewalks =
  flat MultiMesh boxes with lane markings in-shader by road-type flag.
- **Trees**: low-poly cone+cylinder MultiMesh in parks, boulevard medians, residential
  sidewalks; slight vertex-shader sway.
- **Streetlamps**: pole+head MultiMesh, emissive after dusk (no real lights).
- **Cars**: one MultiMesh; two-tone body, emissive head/tail quads after dusk.
- **Cranes**: mast+jib+counterweight assemblies on constructions ≥ ~8 floors, slow
  seeded jib rotation, mast tracking the build line.
- **Palette**: enum `daybreak` / `sodium` / `overcast` (sun+sky+interior-light
  grading), plus standard `hue_drift` (deg/min via `core/hue.gd`) on accent/neon hues.
- **Sky**: custom sky shader — gradient keyed to `day_phase`, sun disc, horizon haze,
  hash-star field fading in past dusk. Moon = second dim cool DirectionalLight3D at
  night.

## Traffic (`sim/traffic.gd`)

- Directed lane polylines from road segments; cars hold (route, segment index, offset).
- Routes = seeded random walks at spawn (straight-bias ~0.7 at intersections) until
  the map edge. Target speeds ~12 m/s street / 16 m/s boulevard; min spacing ~7 m;
  accordion queue at reds (fixed-cycle lights, period ~14 s, NS/EW split, per-node
  seeded phase offset). Car budget = `traffic` macro × active road capacity, capped
  (~2000). Cars appear from the concrete era on (gated by P).
- Deterministic per-frame advance off the sim clock; on scrub, positions re-hashed
  from t then evolve (character-at-t).

## Camera (`sim/campath.gd`)

Closed-form from (t, P, params): azimuth = az0 + orbit_rate·t (~1.2–1.4°/s default);
radius ~250→900 and height ~120→450 as smooth functions of P (scaled by cam dials);
look-at drifts from ground center up to skyline mid-height; fov ~40°. Optional
miniature-DOF param, default off. LFO-able via live cam params (e.g. slow radius
breathing).

## Events

- `topout` — a building of ≥ `topout_floors` (~18) completes.
- `demolish` — each demolition starts.
- `era` — P crosses an era band edge (~2×/run).
- After restart/scrub, prev-state initializes to current so a P jump never fires an
  event storm into envelopes.

## Schema sketch

Macros (0..1): `development`, `day_phase`, `density`, `verticality`, `sprawl`,
`traffic`, `nightlife`.

Params (~30, PS conventions with `live` flags and macro lo/hi mappings):
- Live: `progress` (←development), `time_of_day` (←day_phase), `car_density`
  (←traffic), `lit_fraction` + `neon_amount` (←nightlife), `orbit_rate`, `cam_pull`,
  `cam_height`, `cam_fov`, `dof`, `glow`, `fog_amount`, `hue_drift`, `car_speed`,
  `star_density`.
- Structural (`live: false`, frozen into the plan at restart): `city_radius`
  (←sprawl), `lot_fill` (←density), `height_scale` + `tower_share` (←verticality),
  `block_min/max`, `boulevard_count`, `park_pct`, `floor_h`, `era1_end`, `era2_end`,
  `era_overlap`, `demolish_core`, `demolish_edge`, `construct_speed`,
  `topout_floors`, `crane_density`, `tree_density`, `lamp_density`, `light_cycle`,
  `win_scale`, `palette` (enum).
- Modulating structural macros mid-run is a documented no-op (plan is frozen between
  restarts); long-form presets modulate the live dials.

## Performance

- Everything instanced: ~10–15 MultiMeshes total (buildings ×3 era pools, roofs,
  roads, sidewalks, lamps, trees, cars, crane parts, dirt patches). Per-frame writes
  via packed buffer API only for cars, cranes, and *active* constructions.
- Target ≥30 fps preview at default density on this machine; Movie Maker renders
  offline so the final render never depends on FPS. Density caps degrade gracefully.

## Testing (`tests/run_tests.gd`, model-local, same runner pattern)

Pure-logic modules (`citygen/*`, `sim/*`) take explicit RNG streams + params and run
headless. Tests: plan determinism (same seed+params → identical plan); lot-timeline
validity; every-lot-fronts-a-road; era bands honored; merged-parcel consistency
(members demolish together, one successor); traffic stays on lanes with spacing ≥ 0;
scrub equivalence (evaluate(P) identical after up/down scrub); camera path continuity;
sun curve sanity (dawn/noon/dusk elevations, night factor monotone around dusk).
Run: `godot --headless --path metro_rise --script res://tests/run_tests.gd`.

## File layout

```
metro_rise/
  project.godot  main.tscn  main.gd        # thin orchestrator over the modules
  core -> ../common/core                    # symlink
  citygen/  plan.gd roads.gd lots.gd eras.gd
  sim/      state.gd traffic.gd sun.gd campath.gd
  view/     city_view.gd crane_view.gd
            facade.gdshader road.gdshader ground.gdshader car.gdshader
            tree.gdshader sky.gdshader
  tests/    run_tests.gd
  presets/  default.json boomtown.json garden_city.json century.json
  README.md
```

## Ships with

- `default.json` — mid-build afternoon (dev 0.55, day 0.55), alive via traffic,
  cranes, window shimmer; no modulators.
- `boomtown.json` — dense/tall/hazy sodium dusk, heavy traffic.
- `garden_city.json` — low-rise morning, parks-heavy, sparse traffic, daybreak
  palette.
- `century.json` — the 300 s long-form: tween development 0.02→1.0 (~290 s) +
  day_phase 0.03→0.98 (300 s); traffic and nightlife tweens mid/late; small camera
  LFO; envelopes on `topout` (glow pip) and `era` (fog/glow swell). Proof first via a
  ÷5 timescale clone (60 s), per the compressed-arc convention.

## Verification / done criteria

1. Model-local headless tests pass (plus existing shared suite still passes).
2. Preview launches and holds ≥30 fps at default density; Designer + transport link
   spot-checked.
3. 60 s century-proof renders via `scripts/render.sh`; stills at ~{2,15,30,45,58} s
   show: growth arc legible, era shift visible, night payoff, no z-fighting/holes/
   black frames. Aesthetic judgment then hands off to the user (their render review).
4. Docs: `metro_rise/README.md` (superparams/params/events in natural language), root
   README table + variants section, STATUS.md row (local working doc; not committed).
   VERSIONS.md is tag-driven and stays untouched unless the user tags.

## Risks

- **Preview perf on this GPU** — density caps + instancing; worst case the render is
  still fine (offline).
- **Facade shader face-UV math on scaled boxes** — spike it first; it gates the look.
- **"Programmer-city" blandness** — boulevards, parks, roof clutter, fog, long
  shadows; user reviews early renders.
- **Scrub event storms** — prev-state init on restart/scrub (specified above).
- **GDScript per-frame cost** — buffer writes, touch only active subsets.
