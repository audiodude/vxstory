# metro_rise Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A seventh vxstory model: a 3D city that grows from empty dawn land to a lit
night metropolis across architectural eras, as a pure function of two live dials
(`development`, `day_phase`), inside the existing SimModel framework.

**Architecture:** Root stays `Node2D` (framework untouched); the model parents a 3D
subtree (WorldEnvironment, sun/moon DirectionalLight3D, Camera3D, MultiMesh city).
`restart()` generates a seeded **CityPlan** with per-lot timelines in P-space; each
frame a **StateTracker** diffs plan-at-P and the view writes only dirty instances.
Traffic/cranes/dust are transient character-at-t layers. Spec:
`docs/superpowers/specs/2026-07-28-metro-rise-design.md`.

**Tech Stack:** Godot 4.6 (Forward+), GDScript, spatial shaders, MultiMesh,
shared `common/core` framework (SimModel, ParamSchema, ModStack, PresetIO, tests).

## Global Constraints

- 1 unit = 1 m. 1920×1080 @ 60 fps movie mode. Filmic tonemap + glow.
- Determinism: all randomness through `rng.stream(name)`; no physics engine; no
  `Time.*`/wall-clock in sim paths. Structural state exact under scrub; transient
  layers re-seed from t.
- Pure-logic modules (`citygen/`, `sim/`) are `RefCounted`, scene-free,
  headless-testable; they never touch nodes.
- Naming/conventions per repo: `PS.f/i/e/macro_def` schema helpers, `live:false`
  for structural params, `hue_drift` in deg/min via `core/hue.gd`, presets in
  `metro_rise/presets/`, tests via `tests/run_tests.gd` (SceneTree runner pattern).
- Commit after every green test cycle. Godot-generated `.uid` files get committed.
- Performance: per-frame instance writes only for dirty subsets; preview target
  ≥30 fps at default density (movie mode is offline and exempt).

---

### Task 1: Project scaffold + test runner

**Files:**
- Create: `metro_rise/project.godot`, `metro_rise/main.tscn`, `metro_rise/main.gd`,
  `metro_rise/tests/run_tests.gd`, symlink `metro_rise/core -> ../common/core`
- Reference: `supernova_orbit/project.godot`, `common/core/tests/run_tests.gd`,
  `scripts/render.sh`

**Interfaces:**
- Produces: bootable Godot project; `main.gd` extends `res://core/sim_model.gd` with
  `model_name() -> "metro_rise"` and a stub `get_schema()` containing macros
  `development` (0.5) + `day_phase` (0.55) and live params `progress`, `time_of_day`
  mapped from them (`PS.f("progress", 0.5, 0.0, 1.0, {"macro": {"name": "development", "lo": 0.0, "hi": 1.0}})`,
  same shape for `time_of_day`←`day_phase`).
- Produces: `tests/run_tests.gd` — copy of the shared runner's harness (extends
  SceneTree, `test_*` discovery, `check/check_eq/skip`) but preloading metro modules;
  shared framework tests stay where they are.

- [ ] **Step 1:** Read `scripts/render.sh`; confirm it takes any `<model>` dir (no
  hardcoded model list). Note `godot --version` (expect 4.6.x).
- [ ] **Step 2:** Create `project.godot` cloned from supernova's but: name
  `vxstory_metro_rise`, drop `viewport/hdr_2d`, keep movie fps 60 + mjpeg 0.9, size
  1920×1080, clear color black. No `[rendering]` renderer override (Forward+ default).
- [ ] **Step 3:** `main.tscn` = single `Node2D` "Main" with `main.gd` (same shape as
  supernova's). `main.gd`: stub schema above, empty `restart()`.
- [ ] **Step 4:** `tests/run_tests.gd` with one seed-determinism smoke test using
  `res://core/rng_service.gd` (proves the symlink + runner work):

```gdscript
func test_smoke_rng() -> void:
    var a := RNGService.new(7).stream("plan")
    var b := RNGService.new(7).stream("plan")
    check_eq(a.randf(), b.randf(), "runner + core symlink alive")
```

- [ ] **Step 5:** Run `godot --headless --path metro_rise --script res://tests/run_tests.gd`
  → expect `TESTS: 1 run, 0 failed`. Also boot
  `timeout 10 godot --headless --path metro_rise --quit-after 3` → no script errors.
- [ ] **Step 6:** `git add -A metro_rise && git commit -m "metro_rise: scaffold (project, stub model, test runner)"`

---

### Task 2: Facade shader spike (risk gate)

**Files:**
- Create: `metro_rise/view/facade.gdshader`
- Scratch harness (not committed): scratchpad scene/script that boots a few scaled
  boxes + camera + light and writes PNG frames.

**Interfaces:**
- Produces: `facade.gdshader` — spatial shader for MultiMesh unit-box instances.
  Consumes per-instance: `INSTANCE_CUSTOM = (style_id, win_cell_w_m, lit_seed, progress)`
  packed as vec4; `COLOR` = albedo tint. Global uniforms:
  `night: float`, `lit_fraction: float`, `neon: float`, `floor_h: float`,
  `interior_warm/cool: vec3`, `hue_shift: float`.
- Core math (vertex passes varyings; MODEL_MATRIX is per-instance for MultiMesh):

```glsl
// vertex: v_local = VERTEX (unit box, [-0.5,0.5]); v_nrm = NORMAL;
// v_dims = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz),
//               length(MODEL_MATRIX[2].xyz));
// v_custom = INSTANCE_CUSTOM; v_tint = COLOR.rgb;
// fragment: face-space meters from dominant local-normal axis:
vec3 an = abs(v_nrm);
vec2 f_uv; float f_w;
if (an.y > 0.9) { f_uv = vec2(0.0); }               // roof: no windows
else if (an.x > an.z) { f_uv = vec2(v_local.z * v_dims.z, v_local.y * v_dims.y); f_w = v_dims.z; }
else               { f_uv = vec2(v_local.x * v_dims.x, v_local.y * v_dims.y); f_w = v_dims.x; }
float y_m = (v_local.y + 0.5) * v_dims.y;            // height above base
// construction cutoff:
if (y_m > v_custom.w * v_dims.y) discard;
// window grid: cell = vec2(v_custom.y, floor_h); style branches on v_custom.x
```

- Styles in-fragment: 0 brick (window ratio ~0.45, mortar band every 4th row,
  ROUGHNESS 0.9), 1 concrete (ribbon: window band 0.55 of floor height full-width,
  vertical piers every 3 cells, ROUGHNESS 0.7), 2 glass (ratio 0.85, mullion lines,
  ROUGHNESS 0.15, METALLIC 0.25). Lit windows: `hash(cell, lit_seed) < lit_fraction * night`
  → EMISSION = mix(interior_warm, interior_cool, hash2) * (1.5 + neon). Scaffold band:
  if `v_custom.w < 1.0 && y_m > (v_custom.w * v_dims.y - floor_h)` → faint emissive
  work-light color.

- [ ] **Step 1:** Write the shader + a scratchpad harness scene (SceneTree script:
  MultiMesh with 6 instances at varied scales/styles/progress, camera, sun light),
  run `godot --path metro_rise --write-movie <scratch>/spike.png --quit-after 8`
  (movie mode writes numbered PNGs; requires display per README — run non-headless).
- [ ] **Step 2:** View frames with Read. Verify: windows stay square-ish across
  different box scales, rows align to 3.2 m floors, styles distinct, cutoff+scaffold
  band works, no seams at box edges. Iterate until true.
- [ ] **Step 3:** Commit shader only:
  `git add metro_rise/view && git commit -m "metro_rise: facade shader (face-space window grids, 3 era styles, build cutoff)"`

---

### Task 3: citygen/roads.gd (TDD)

**Files:**
- Create: `metro_rise/citygen/roads.gd`
- Test: extend `metro_rise/tests/run_tests.gd`

**Interfaces:**
- Produces: `static func build(rng: RandomNumberGenerator, params: Dictionary) -> Dictionary`:

```gdscript
{ "segments": [ {"id": int, "a": Vector2, "b": Vector2, "kind": "street"|"blvd",
                 "ring": int, "width": float} ],
  "nodes":    [ {"id": int, "pos": Vector2, "segs": Array[int], "ring": int} ],
  "xs": PackedFloat32Array, "ys": PackedFloat32Array }   # grid line coords
```

- Grid: vertical/horizontal lines at seeded spacings in
  [`block_min`=90, `block_max`=130] covering ±`city_radius`; every 3rd–4th line
  (seeded) is a boulevard (width 24) else street (width 12). `boulevard_count`
  extra diagonal boulevards through near-center at seeded angles, snapped to run
  node-to-node across the grid. `ring` = floor(max(|x|,|y|) at segment midpoint /
  `city_radius` × `RINGS`=6), clamped 0..5. Segments split at every grid
  intersection; nodes dedup by position.

- [ ] **Step 1:** Write failing tests:

```gdscript
const Roads = preload("res://citygen/roads.gd")
func _road_params() -> Dictionary:
    return {"city_radius": 600.0, "block_min": 90.0, "block_max": 130.0,
            "boulevard_count": 2}
func test_roads_deterministic() -> void:
    var a := Roads.build(RNGService.new(11).stream("roads"), _road_params())
    var b := Roads.build(RNGService.new(11).stream("roads"), _road_params())
    check_eq(a["segments"].size(), b["segments"].size(), "same seed same segment count")
    check_eq(str(a["segments"][0]), str(b["segments"][0]), "same first segment")
func test_roads_rings_and_kinds() -> void:
    var r := Roads.build(RNGService.new(3).stream("roads"), _road_params())
    var blvds := 0
    for s in r["segments"]:
        check(s["ring"] >= 0 and s["ring"] <= 5, "ring in range")
        check(s["width"] > 0.0, "width set")
        if s["kind"] == "blvd": blvds += 1
    check(blvds > 0, "boulevards exist")
func test_roads_nodes_connect() -> void:
    var r := Roads.build(RNGService.new(3).stream("roads"), _road_params())
    for n in r["nodes"]:
        check(n["segs"].size() >= 2, "every node joins >=2 segments")
```

- [ ] **Step 2:** Run → FAIL (module missing). **Step 3:** Implement. **Step 4:** Run
  → all pass. **Step 5:** `git commit -m "metro_rise: seeded road grid + boulevards (rings, nodes)"`

---

### Task 4: citygen/lots.gd (TDD)

**Files:**
- Create: `metro_rise/citygen/lots.gd`
- Test: extend runner

**Interfaces:**
- Consumes: roads dict from Task 3.
- Produces: `static func build(rng, roads: Dictionary, params: Dictionary) -> Dictionary`:

```gdscript
{ "blocks":  [ {"id": int, "rect": Rect2, "district": String, "ring": int} ],
  "lots":    [ {"id": int, "block": int, "rect": Rect2, "district": String,
                "ring": int, "front_seg": int, "parcel": int} ],   # parcel -1 = none
  "parcels": [ {"id": int, "lots": Array[int], "rect": Rect2} ] }
```

- Blocks = cells between adjacent grid lines (inset by half road widths + sidewalk 3).
  District by block-center distance d / `city_radius`: <0.22 core, <0.45 commercial,
  <0.75 residential, else industrial; seeded `park_pct` of non-core blocks become
  "park" (no lots). Lots: split each block into a seeded 2×2..3×4-ish grid of rects,
  each assigned `front_seg` = nearest bounding segment. Core blocks: with prob
  `tower_share`, mark a seeded 1×2 or 2×2 group of adjacent lots as one parcel.

- [ ] **Step 1:** Failing tests:

```gdscript
const Lots = preload("res://citygen/lots.gd")
func _city(seed: int) -> Dictionary:
    var svc := RNGService.new(seed)
    var p := {"city_radius": 600.0, "block_min": 90.0, "block_max": 130.0,
              "boulevard_count": 2, "park_pct": 0.07, "tower_share": 0.25,
              "lot_fill": 0.8}
    var roads := Roads.build(svc.stream("roads"), p)
    return {"roads": roads, "lots": Lots.build(svc.stream("lots"), roads, p), "params": p}
func test_lots_front_roads() -> void:
    var c := _city(5)
    for l in c["lots"]["lots"]:
        check(l["front_seg"] >= 0 and l["front_seg"] < c["roads"]["segments"].size(),
              "lot fronts a real segment")
func test_lots_inside_blocks_and_districts() -> void:
    var c := _city(5)
    var blocks: Array = c["lots"]["blocks"]
    for l in c["lots"]["lots"]:
        check(blocks[l["block"]]["rect"].grow(0.5).encloses(l["rect"]), "lot within block")
        check(l["district"] in ["core","commercial","residential","industrial"], "district set")
    var parks := 0
    for b in blocks:
        if b["district"] == "park": parks += 1
    check(parks > 0, "some parks")
func test_parcels_are_core_and_grouped() -> void:
    var c := _city(9)
    for pc in c["lots"]["parcels"]:
        check(pc["lots"].size() >= 2, "parcel groups >=2 lots")
        for li in pc["lots"]:
            check_eq(c["lots"]["lots"][li]["parcel"], pc["id"], "backref consistent")
```

- [ ] **Steps 2–4:** red → implement → green. **Step 5:**
  `git commit -m "metro_rise: blocks/lots/districts/parks + core tower parcels"`

---

### Task 5: citygen/eras.gd + citygen/plan.gd (TDD)

**Files:**
- Create: `metro_rise/citygen/eras.gd`, `metro_rise/citygen/plan.gd`
- Test: extend runner

**Interfaces:**
- `eras.gd`: `static func timelines(rng, lots: Dictionary, params: Dictionary) -> Dictionary`
  mapping `lot_id -> Array[entry]`:

```gdscript
{ "p0": float, "p1": float,        # construction window (p1 = topout)
  "p_demo": float,                 # INF if never demolished
  "style": int,                    # 0 brick 1 concrete 2 glass
  "floors": int, "industrial": bool, "parcel_id": int,  # -1 normal
  "rect": Rect2,                   # footprint (setback inside lot / parcel rect)
  "tiers": [ {"rect": Rect2, "floors": int} ],  # 1..3 stacked, shrinking
  "win_w": float, "accent": float, "lit_seed": float }
```

- Rules (constants are params where named):
  - Ring gate: `p_open(ring_r) = clamp(((ring_r / city_radius) - 0.22) / 0.78, 0.0, 1.0)`;
    a lot's first `p0` ≥ its ring's p_open (+ seeded stagger 0..0.08).
  - Era of an entry from its p0 vs bands `era1_end`=0.34, `era2_end`=0.66 with
    `era_overlap`=0.08: inside an overlap window the style is a seeded coin-flip
    biased by position through the window.
  - Floors: district×era ranges (from spec: brick 2–6 core 4–8; concrete 6–18 core
    10–24; glass 12–40 core 24–60) × `height_scale`; parcels only build era-3 towers
    at the top of the core range; industrial district: floors 1–3, wide rect,
    `industrial: true`, never glass.
  - Construction duration: `p1 - p0 = (0.010 + 0.0016 * floors) / construct_speed`.
  - Replacement: seeded chain per lot — core/commercial demolish with prob
    `demolish_core`=0.85 per era step, residential 0.5, industrial/edge
    `demolish_edge`=0.25; `p_demo` early in the next era band + jitter; successor
    `p0 = p_demo + 0.015` (dust gap). Parcel entries: all member lots get `p_demo`
    at the same P; exactly one successor entry (on the parcel, carried by the lowest
    member lot id) with `rect` = parcel rect.
  - Entries per lot sorted, non-overlapping: `entry[i].p_demo <= entry[i+1].p0`,
    all windows within [0,1] (clamp final constructions to finish ≤ 0.995).
- `plan.gd`: `static func build(rng_service, params) -> Dictionary` — orchestrates
  roads→lots→timelines and precomputes scatter:

```gdscript
{ "roads": ..., "blocks": ..., "lots": ..., "parcels": ..., "timelines": ...,
  "trees": [ {"pos": Vector2, "ring": int, "scale": float} ],   # parks + medians + residential fronts, density × tree_density
  "lamps": [ {"pos": Vector2, "ring": int} ],                   # along arterials, spacing ~30m × lamp_density
  "city_radius": float }
```

  Streams: `plan:roads`, `plan:lots`, `plan:eras`, `plan:scatter` via
  `rng_service.stream(name)`.

- [ ] **Step 1:** Failing tests:

```gdscript
const Plan = preload("res://citygen/plan.gd")
func _params() -> Dictionary:   # full structural param set with spec defaults
    return {"city_radius": 600.0, "block_min": 90.0, "block_max": 130.0,
            "boulevard_count": 2, "park_pct": 0.07, "tower_share": 0.25,
            "lot_fill": 0.8, "height_scale": 1.0, "era1_end": 0.34,
            "era2_end": 0.66, "era_overlap": 0.08, "demolish_core": 0.85,
            "demolish_edge": 0.25, "construct_speed": 1.0, "floor_h": 3.2,
            "tree_density": 0.6, "lamp_density": 0.6, "win_scale": 1.0}
func test_plan_deterministic() -> void:
    var a := Plan.build(RNGService.new(21), _params())
    var b := Plan.build(RNGService.new(21), _params())
    check_eq(str(a["timelines"]).length(), str(b["timelines"]).length(), "identical plans")
func test_timelines_valid() -> void:
    var p := Plan.build(RNGService.new(4), _params())
    for lot_id in p["timelines"]:
        var prev_end := -1.0
        for e in p["timelines"][lot_id]:
            check(e["p0"] >= 0.0 and e["p1"] <= 1.0 and e["p0"] < e["p1"], "window in [0,1]")
            check(e["p0"] >= prev_end, "entries non-overlapping")
            prev_end = e["p_demo"] if e["p_demo"] != INF else 2.0
            check(e["floors"] >= 1, "has floors")
            check(e["tiers"].size() >= 1, "has tiers")
func test_era_bands_respected() -> void:
    var p := Plan.build(RNGService.new(4), _params())
    for lot_id in p["timelines"]:
        for e in p["timelines"][lot_id]:
            if e["style"] == 2: check(e["p0"] > 0.66 - 0.08 - 0.001, "glass not before band")
            if e["style"] == 0: check(e["p0"] < 0.34 + 0.08 + 0.001, "brick not after band")
func test_parcels_demolish_together() -> void:
    var p := Plan.build(RNGService.new(13), _params())
    for pc in p["parcels"]:
        var demo_ps := {}
        var successors := 0
        for li in pc["lots"]:
            for e in p["timelines"].get(li, []):
                if e["parcel_id"] == pc["id"]:
                    if e["style"] == 2 and e["rect"].size.x > 0.0: successors += 1
                else:
                    if e["p_demo"] != INF: demo_ps[snappedf(e["p_demo"], 0.0001)] = true
        check(successors <= 1, "at most one parcel tower")
        if successors == 1: check(demo_ps.size() <= 1, "members share demo P")
```

- [ ] **Steps 2–4:** red → implement (`eras.gd` first, then `plan.gd`) → green.
- [ ] **Step 5:** `git commit -m "metro_rise: era timelines in P-space + CityPlan assembly"`

---

### Task 6: sim/state.gd — StateTracker (TDD)

**Files:**
- Create: `metro_rise/sim/state.gd`
- Test: extend runner

**Interfaces:**
- Consumes: plan dict (Task 5).
- Produces: class `StateTracker` (`RefCounted`):

```gdscript
func _init(plan: Dictionary, params: Dictionary) -> void
func eval(P: float) -> Dictionary
# { "changed": Array[int],          # building slot indices whose state changed
#   "events": Array[Dictionary],    # [{"kind":"topout"|"demolish"|"era", ...}]; [] on first eval
#   "ring_p": float }               # r_act(P)/city_radius for pave-in shading
func building_count() -> int        # total slots (all entries × tiers, fixed at init)
func slot(i: int) -> Dictionary
# { "active": bool, "progress": float,  # 0..1 build progress (1 = complete)
#   "demo": float,                      # 0 none, (0..1] sinking
#   "rect": Rect2, "y0": float, "h": float,   # tier base height & height (m)
#   "style": int, "floors": int, "win_w": float, "accent": float,
#   "lit_seed": float, "lot": int, "crane": bool }
```

- Slots are flattened (entry × tier) at init, index-stable for the model run — the
  view maps slot i ↔ MultiMesh instance i. `progress` =
  `clamp((P - p0)/(p1 - p0), 0, 1)` shaped so lower tiers finish first (tier k of n
  occupies the [k/n, (k+1)/n] slice of the window). `demo` ramps over 0.02 P after
  `p_demo`. `crane` true while `floors >= 8 && progress in (0.05, 1.0)`.
  Events: `topout` when a slot's top tier crosses progress 1 with entry floors ≥
  `topout_floors`; `demolish` when demo leaves 0; `era` when P crosses era band
  edges. First `eval()` after init returns `events: []` and `changed` = every active
  slot (scrub-storm suppression by construction).

- [ ] **Step 1:** Failing tests:

```gdscript
const State = preload("res://sim/state.gd")
func test_state_scrub_exact() -> void:
    var plan := Plan.build(RNGService.new(8), _params())
    var a := State.new(plan, _params()); a.eval(0.7)
    var b := State.new(plan, _params())
    for P in [0.1, 0.9, 0.3, 0.7]: b.eval(P)     # wander then land on 0.7
    for i in a.building_count():
        check_eq(str(a.slot(i)), str(b.slot(i)), "slot %d identical after scrub walk" % i)
func test_state_first_eval_silent_then_events() -> void:
    var plan := Plan.build(RNGService.new(8), _params())
    var t := State.new(plan, _params())
    check_eq(t.eval(0.5)["events"].size(), 0, "first eval fires nothing")
    var evs := []
    var P := 0.5
    while P < 0.72:
        P += 0.002
        evs.append_array(t.eval(P)["events"])
    var kinds := {}
    for e in evs: kinds[e["kind"]] = true
    check(kinds.has("era"), "era edge crossed fires era")
    check(kinds.has("topout") or kinds.has("demolish"), "life happens")
func test_state_monotone_build() -> void:
    var plan := Plan.build(RNGService.new(8), _params())
    var t := State.new(plan, _params())
    t.eval(0.4)
    var p1 := t.slot(0)["progress"]
    t.eval(0.45)
    check(t.slot(0)["progress"] >= p1 - 0.0001, "progress monotone in P (no demo)")
```

- [ ] **Steps 2–4:** red → implement → green. **Step 5:**
  `git commit -m "metro_rise: StateTracker — plan-at-P slots, diffs, events"`

---

### Task 7: sim/sun.gd + sim/campath.gd (TDD)

**Files:**
- Create: `metro_rise/sim/sun.gd`, `metro_rise/sim/campath.gd`
- Test: extend runner

**Interfaces:**
- `sun.gd`: `static func eval(day: float, palette: String, params: Dictionary) -> Dictionary`:

```gdscript
{ "sun_dir": Vector3,        # normalized, pointing FROM sun (light -Z convention applied by caller)
  "sun_energy": float, "sun_color": Color,
  "moon_energy": float,      # >0 only at night
  "night": float,            # 0 day .. 1 full night
  "ambient_energy": float, "fog_density": float, "star_alpha": float,
  "sky_top": Color, "sky_horizon": Color }
```

  Curves: dawn φ0=0.04, dusk φ1=0.86; `elev_deg = sin(PI * (day - φ0)/(φ1 - φ0)) * 62`
  inside [φ0, φ1], else a dip to −14 across the night wrap. `azim_deg = lerp(60, 285, day)`.
  `night = smoothstep(6.0, -8.0, elev_deg)`. `sun_energy` peaks ~1.6 midday, warm
  color ramps 2200K→5800K→1900K (precompute 3-stop gradients per palette:
  `daybreak` warm/blue, `sodium` amber-heavy dusk + orange interior, `overcast`
  desaturated cool). `star_alpha = clamp((night - 0.6)/0.4, 0, 1)`.
- `campath.gd`: `static func eval(t: float, P: float, params: Dictionary) -> Dictionary`
  → `{"pos": Vector3, "look": Vector3, "fov": float}`; `s = smoothstep(0,1,P)`;
  `radius = cam_pull * lerp(250, 900, s)`; `height = cam_height * lerp(120, 450, s)`;
  `az = deg_to_rad(orbit_deg0 + orbit_rate * t)`; `look = (0, lerp(6, 90, s), 0)`.

- [ ] **Step 1:** Failing tests:

```gdscript
const Sun = preload("res://sim/sun.gd")
const Cam = preload("res://sim/campath.gd")
func _sun_p() -> Dictionary: return {"fog_amount": 0.35, "star_density": 0.5}
func test_sun_day_night() -> void:
    var noon := Sun.eval(0.45, "daybreak", _sun_p())
    var mid := Sun.eval(0.97, "daybreak", _sun_p())
    check(noon["night"] < 0.05, "noon is day")
    check(mid["night"] > 0.95, "late is night")
    check(mid["moon_energy"] > 0.0 and noon["moon_energy"] == 0.0, "moon only at night")
    check(noon["sun_dir"].y < -0.5, "noon sun shines downward")
func test_sun_continuous_at_dusk() -> void:
    var a := Sun.eval(0.859, "sodium", _sun_p())
    var b := Sun.eval(0.861, "sodium", _sun_p())
    check(absf(a["night"] - b["night"]) < 0.05, "no discontinuity at dusk")
func test_campath_smooth_and_orbiting() -> void:
    var p := {"cam_pull": 1.0, "cam_height": 1.0, "orbit_rate": 1.3,
              "orbit_deg0": 20.0, "cam_fov": 40.0}
    var a: Vector3 = Cam.eval(10.0, 0.3, p)["pos"]
    var b: Vector3 = Cam.eval(10.1, 0.3005, p)["pos"]
    check(a.distance_to(b) < 1.0, "sub-meter step per 0.1s")
    check(Cam.eval(100.0, 0.9, p)["pos"].length() > Cam.eval(0.0, 0.1, p)["pos"].length(),
          "pulls back as city grows")
```

- [ ] **Steps 2–4:** red → implement → green. **Step 5:**
  `git commit -m "metro_rise: sun/sky curves + orbit-pullback camera path (pure)"`

---

### Task 8: view/city_view.gd — static city + buildings render

**Files:**
- Create: `metro_rise/view/city_view.gd`, `metro_rise/view/road.gdshader`,
  `metro_rise/view/ground.gdshader`, `metro_rise/view/tree.gdshader`
- Modify: `metro_rise/main.gd` (real restart/apply_live begins here)

**Interfaces:**
- Consumes: plan (Task 5), StateTracker (Task 6), facade.gdshader (Task 2).
- Produces: class `CityView` (`extends Node3D`):

```gdscript
func setup(plan: Dictionary, params: Dictionary) -> void   # builds all pools
func apply_slots(tracker, changed: Array[int]) -> void     # writes dirty instances
func set_globals(sun_out: Dictionary, live: Dictionary) -> void
    # pushes night/lit_fraction/neon/hue_shift/palette colors into materials
func on_event(e: Dictionary) -> void                       # demolish → dust puff
```

- Pools (all MultiMesh, USE_COLORS+USE_CUSTOM_DATA where noted, allocated once in
  `setup`): buildings (unit BoxMesh, facade shader, colors+custom; count =
  `tracker.building_count()`; inactive slots zero-scale), roofs (parapet + clutter
  boxes, plain flat material, seeded per completed slot — simplest v1: clutter baked
  as extra slots-driven instances updated in `apply_slots` when progress hits 1),
  roads (one box per segment, road.gdshader: asphalt + lane dashes by `kind` flag in
  CUSTOM, pave-in mix by ring vs `ring_p` global), sidewalks (lighter flat boxes),
  ground (single 2400×2400 plane, ground.gdshader world-noise + subtle district
  tint), trees (cone+cyl, tree.gdshader sway; fade in by ring like roads), lamps
  (thin pole + emissive head after dusk via global `night`), dirt patches (quad per
  actively-constructing lot, driven from `apply_slots`).
- Slot write = `multimesh.set_instance_transform(i, ...)` +
  `set_instance_custom_data` + `set_instance_color`; transform from slot rect/y0/h
  (demo sink = y offset −demo×h; scale.y stays full — facade shader handles the
  build cutoff via progress in CUSTOM).
- Dust: one shared `GPUParticles3D` (one-shot, `use_fixed_seed=true`, seed from
  event lot id) re-emitted at demolish events.

- [ ] **Step 1:** Implement `CityView` + shaders; wire `main.gd`:
  `restart()` = free non-CanvasLayer children → `Plan.build(rng, params)` →
  `StateTracker.new` → build 3D rig (temporary flat lighting: one DirectionalLight3D
  + WorldEnvironment gray sky) → `CityView.setup` → first `eval(progress)` +
  `apply_slots`. `_process` additions: `eval(params["progress"])` each frame →
  `apply_slots(changed)` + events → `emit_event`.
- [ ] **Step 2:** Scratch presets in scratchpad: `p015.json` (macros development
  0.15, day_phase 0.5), `p05.json`, `p09.json`. For each:
  `godot --path metro_rise --write-movie <scratch>/pXX.png --quit-after 10 -- --preset <abs path>`
  → view last frame with Read.
- [ ] **Step 3:** Verify by eye: growth legible across the three, districts read
  (heights cluster downtown), parks/trees present, roads pave in with rings, no
  z-fighting (roads y=0.05, sidewalks 0.03, dirt 0.02), construction cutoffs
  visible at 0.15. Iterate.
- [ ] **Step 4:** Headless suite still green. **Step 5:**
  `git commit -m "metro_rise: CityView — instanced city render off StateTracker diffs"`

---

### Task 9: Lighting rig + sky + full live wiring in main.gd

**Files:**
- Create: `metro_rise/view/sky.gdshader`
- Modify: `metro_rise/main.gd`

**Interfaces:**
- Consumes: `Sun.eval`, `Cam.eval` (Task 7), `CityView.set_globals` (Task 8).
- Produces: full schema (all macros/params from the spec's Schema sketch, with
  mappings: `density→lot_fill 0.5..0.95`, `verticality→height_scale 0.6..1.6` +
  `tower_share 0.05..0.5`, `sprawl→city_radius 320..780`, `traffic→car_density
  0..1`, `nightlife→lit_fraction 0.25..0.95` + `neon_amount 0..1`; live camera
  dials `orbit_rate 0.2..4 (default 1.3)`, `cam_pull/cam_height 0.7..1.3`,
  `cam_fov 25..60 (40)`, `dof 0..1 (0)`; `glow 0..3 (1.1)`, `fog_amount 0..1
  (0.35)`, `hue_drift 0..90 (0)`, `star_density`, `car_speed 0.5..1.5`,
  `light_cycle 8..30 (14)`, `crane_density`, `topout_floors i 8..40 (18)`,
  structural listed in spec all `live:false`). `_on_scrub(t)` sets `sim_t = t`.
- Sky shader: gradient from `sky_top/sky_horizon` uniforms + sun disc at `sun_dir`
  + hash stars × `star_alpha × star_density`.
- Per-frame (`_process` after mod tick): read live params → `Sun.eval` → set sun/moon
  light rotation/energy/color, Environment ambient/fog/glow, sky uniforms →
  `Cam.eval(sim_t, progress)` → camera transform/fov → `city_view.set_globals` (incl.
  `hue_shift = Hue.shift(hue_drift, sim_t)` — check `core/hue.gd` actual API and use
  it verbatim) → tracker eval/apply as in Task 8. `apply_live(p)` stores the params
  dict (everything live is read fresh each frame anyway).

- [ ] **Step 1:** Implement. **Step 2:** Scratch presets: dawn empty
  (dev 0.05/day 0.08), noon half (0.5/0.5), dusk dense (0.85/0.82), night full
  (1.0/0.97). PNG-frame each; view. Verify: sun elevation/color arc, long shadows at
  dawn/dusk, lit windows + lamps + stars at night, sky gradient + disc, glow not
  blowing out (LDR/sRGB pitfall memory — check mid-grays aren't crushed).
- [ ] **Step 3:** Boot preview (no preset) 5 s with panel visible over 3D — confirm
  TweakPanel renders and edits `development` live-grow the city.
  **Step 4:** suite green.
- [ ] **Step 5:** `git commit -m "metro_rise: sun/moon/sky rig, full schema, live wiring + scrub"`

---

### Task 10: sim/traffic.gd + car rendering (TDD logic, visual check)

**Files:**
- Create: `metro_rise/sim/traffic.gd`, `metro_rise/view/car.gdshader`
- Modify: `metro_rise/view/city_view.gd` (car pool + buffer write),
  `metro_rise/main.gd` (tick + reseed on scrub)
- Test: extend runner

**Interfaces:**
- Produces: class `Traffic` (`RefCounted`):

```gdscript
func _init(plan: Dictionary, seed_value: int) -> void   # builds lane graph
func reseed(t: float) -> void                           # scrub: hash cars along lanes
func tick(dt: float, t: float, P: float, live: Dictionary) -> void
    # live: {"car_density": float, "car_speed": float, "light_cycle": float}
func cars() -> Array[Dictionary]   # [{"pos": Vector2, "ang": float, "stopped": bool, "hue": float}]
func car_count() -> int
```

- Lane graph: 2 directed lanes per street segment, 4 per boulevard, offset from
  centerline by ±(width/4). Cars hold (route: Array[int] of node ids as a seeded
  random walk with straight-bias 0.7, seg progress in m). Budget:
  `target = car_density * era_gate(P) * active_lane_len / 55`, cap 2000;
  `era_gate = clamp((P - 0.30)/0.10, 0, 1)`. Spawn/despawn at outermost active
  nodes. Speeds 12/16 m/s × `car_speed`; min gap 7 m to the car ahead on the same
  lane (accordion); red = `fmod(t / light_cycle + node_phase, 1.0)` selecting NS or
  EW half-cycle, stop line 8 m before node, decel to 0 over last 12 m.
- View: cars pool MultiMesh (box 4.4×1.5×1.9 scaled, car.gdshader: COLOR body
  two-tone by hue, emissive white head / red tail quads gated by global `night`);
  written each frame via `multimesh.buffer` PackedFloat32Array rebuild (cars move
  every frame — full rebuild of just this pool is the fast path).

- [ ] **Step 1:** Failing tests:

```gdscript
const Traffic = preload("res://sim/traffic.gd")
func test_traffic_on_lanes_and_spaced() -> void:
    var plan := Plan.build(RNGService.new(8), _params())
    var tr := Traffic.new(plan, 8)
    var live := {"car_density": 0.7, "car_speed": 1.0, "light_cycle": 14.0}
    for i in 600: tr.tick(1.0/60.0, i/60.0, 0.8, live)
    check(tr.car_count() > 50, "traffic exists at P=0.8")
    for c in tr.cars():
        check(_near_any_segment(plan, c["pos"], 14.0), "car within a road corridor")
func _near_any_segment(plan: Dictionary, p: Vector2, tol: float) -> bool:
    for s in plan["roads"]["segments"]:
        if Geometry2D.get_closest_point_to_segment(p, s["a"], s["b"]).distance_to(p) <= tol:
            return true
    return false
func test_traffic_deterministic_and_reseed() -> void:
    var plan := Plan.build(RNGService.new(8), _params())
    var a := Traffic.new(plan, 8); var b := Traffic.new(plan, 8)
    var live := {"car_density": 0.5, "car_speed": 1.0, "light_cycle": 14.0}
    for i in 120:
        a.tick(1.0/60.0, i/60.0, 0.7, live); b.tick(1.0/60.0, i/60.0, 0.7, live)
    check_eq(str(a.cars().slice(0, 5)), str(b.cars().slice(0, 5)), "same seed same flow")
    a.reseed(90.0); b.reseed(90.0)
    check_eq(a.car_count(), b.car_count(), "reseed deterministic")
func test_traffic_gated_by_P() -> void:
    var plan := Plan.build(RNGService.new(8), _params())
    var tr := Traffic.new(plan, 8)
    var live := {"car_density": 0.9, "car_speed": 1.0, "light_cycle": 14.0}
    for i in 120: tr.tick(1.0/60.0, i/60.0, 0.1, live)
    check_eq(tr.car_count(), 0, "no cars in the brick dawn")
```

- [ ] **Steps 2–4:** red → implement → green. **Step 5:** visual: dusk-dense scratch
  preset PNG frames — cars on lanes, queues at reds, headlights at night. Fix.
- [ ] **Step 6:** `git commit -m "metro_rise: deterministic lane traffic + car pool (headlights, queues)"`

---

### Task 11: Cranes + demolition dressing

**Files:**
- Create: `metro_rise/view/crane_view.gd`
- Modify: `metro_rise/view/city_view.gd` (dirt patches already; add dust hook if not
  done), `metro_rise/main.gd` (crane update)

**Interfaces:**
- Consumes: slots with `crane: true` (Task 6).
- Produces: class `CraneView` (`extends Node3D`): `func sync(tracker, changed) -> void`
  + `func tick(sim_t: float) -> void`. Pools: masts (thin box 1.6×h×1.6), jibs
  (14×0.8×0.8 at mast top, rotated), counterjibs (5 m opposite). Mast height =
  building `y0 + progress×h + 8`. Jib yaw = `hash(slot) × TAU + sim_t × 0.12 ×
  (0.5 + hash2)`, i.e. closed-form from sim_t (scrub-exact for free). Crane set
  gated by `crane_density` (seeded skip). Update transforms only for slots in
  `changed` + all active cranes each frame (they rotate; count is small, ~dozens).

- [ ] **Step 1:** Implement; wire into main after `apply_slots`.
- [ ] **Step 2:** Scratch PNG check at dev 0.4 (era-2 boom: many constructions):
  cranes sit on tall builds, rotate across frames, vanish at topout; demolition dust
  puffs + sink visible when scrubbing past a `p_demo` (render 10 s with a tween
  preset from Task 12 draft if simpler). **Step 3:** suite green.
- [ ] **Step 4:** `git commit -m "metro_rise: tower cranes + demolition dressing"`

---

### Task 12: Presets + README + root docs

**Files:**
- Create: `metro_rise/presets/default.json`, `boomtown.json`, `garden_city.json`,
  `century.json`, `metro_rise/README.md`
- Modify: `README.md` (root: model table row, variants section, layout note),
  STATUS.md (local row, not committed)

**Interfaces:**
- Consumes: full schema names from Task 9 (presets reference macros exactly:
  `development, day_phase, density, verticality, sprawl, traffic, nightlife`).
- Preset contents (tune values after visual checks, structure fixed):
  - `default.json`: seed 4207, duration 30, macros {development 0.55, day_phase
    0.55, density 0.55, verticality 0.5, sprawl 0.5, traffic 0.55, nightlife 0.6}.
  - `boomtown.json`: dev 0.85, density 0.9, verticality 0.85, traffic 0.85,
    day_phase 0.8, nightlife 0.9, overrides {"palette": "sodium"}.
  - `garden_city.json`: dev 0.45, density 0.35, verticality 0.25, sprawl 0.7,
    day_phase 0.25, traffic 0.3, nightlife 0.4, overrides {"palette": "daybreak",
    "park_pct": 0.16}.
  - `century.json`: duration 300, macros start {development 0.02, day_phase 0.03,
    traffic 0.15, nightlife 0.4, others mid}; modulators:
    tween "build" 290 s ease_in_out development→1.0 (amount 1.0);
    tween "sunarc" 300 s linear day_phase→0.98;
    tween "rush" from 40 s… (framework tweens run from t=0 — check `mod_sources.gd`
    for delay support; if none, shape with curve + from/to) traffic→0.75;
    tween "lights_on" nightlife→0.85 late via ease_in;
    lfo "breath" 45 s sine amount 0.05 → cam_pull;
    envelope "pip" on `topout` attack 0.05 decay 0.8 → glow +0.25;
    envelope "epoch" on `era` attack 0.3 decay 3.0 → fog_amount +0.3.
- `metro_rise/README.md` per per-model-README convention: natural-language
  superparams (macros), params, events (`topout`, `demolish`, `era`), preset
  descriptions, the two-dial design note (structural macros need Restart).
- Root README: add table row "`metro_rise` | 3D era-city: dawn-to-night build-out,
  brick→concrete→glass, traffic + cranes"; variants section entries for the three
  + `century`; layout tree gains `metro_rise/` with its extra dirs.

- [ ] **Step 1:** Write presets; sanity-boot each
  (`--preset presets/<name>.json`, 5 s, PNG check first+last frame).
- [ ] **Step 2:** Compressed-arc proof per repo memory: scratchpad
  `century_proof.json` = century with duration 60 and all modulator time constants
  ÷5 (58 s build, 60 s sunarc, 9 s LFO…). Render via
  `scripts/render.sh` equivalent (`--write-movie` mp4 60 s) and skim stills at
  ~{2, 15, 30, 45, 58} s.
- [ ] **Step 3:** Verify arc: empty dawn → brick morning → concrete midday w/ cranes
  + first traffic → glass dusk → lit night skyline; era demolitions visible;
  camera pull-back frames the whole run; no black frames / z-fights / popping.
  Tune preset values (schema-not-overrides rule: fix schema mappings if a dial
  can't reach the look) and re-proof once.
- [ ] **Step 4:** Write both READMEs + STATUS row. **Step 5:** suite green.
- [ ] **Step 6:** `git add metro_rise README.md && git commit -m "metro_rise: presets (default/boomtown/garden_city/century) + docs"`

---

### Task 13: Performance + polish pass

**Files:**
- Modify: whatever the measurements indict (likely `city_view.gd`, densities in
  schema defaults)

- [ ] **Step 1:** Preview FPS: run windowed preview 20 s with a temporary
  `print(Engine.get_frames_per_second())` each 2 s (remove after) at `default` and
  `boomtown`. Target ≥30. If below: verify dirty-set sizes (should be ~0 when P
  static), car buffer rebuild cost, shadow map size; degrade via default densities.
- [ ] **Step 2:** Movie-mode spot render 10 s at boomtown; confirm frame pacing is
  fine (movie mode always is) and visual quality at 60 fps output.
- [ ] **Step 3:** Suite green; commit if changes:
  `git commit -m "metro_rise: perf pass (dirty-set + density tuning)"`

---

### Task 14: Final verification + handoff

- [ ] **Step 1:** Full: `godot --headless --path metro_rise --script res://tests/run_tests.gd`
  AND the shared suite `godot --headless --path peg_cascade --script res://core/tests/run_tests.gd`
  (must both be 0 failed — proves no framework breakage).
- [ ] **Step 2:** Fresh-eyes skim of spec vs implementation; note any consciously
  dropped items in the session summary.
- [ ] **Step 3:** Render the real `century.json` proof at 60 s (÷5 clone) if Task 12
  tuning changed anything; extract 5 stills; view.
- [ ] **Step 4:** Hand off to user: what shipped, the render/stills paths, the
  invitation to render the full 300 s (`scripts/render.sh metro_rise century 300`)
  and review aesthetics (their call per their workflow memory).
- [ ] **Step 5:** Final commit of any stragglers; update STATUS.md locally.
