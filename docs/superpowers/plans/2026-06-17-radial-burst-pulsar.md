# radial_burst "pulsar" + long-form toolkit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `radial_burst` a 5-minute attention-holding preset (`pulsar`) built on a calm→riot→calm Director arc, multiple sympathetically-coupled burst sources, and radio-cribbed color palettes — plus two small shared helpers (`hue.gd`, `cascade.gd`) the later models will reuse.

**Architecture:** Two pure, unit-tested helpers land in `common/core/` first. Then `radial_burst/main.gd` is restructured from a single center emitter + scheduled satellites into N independent **sources** (each a colored emitter with its own satellites and fire timer). When a source ignites it re-reads drifted params, spawns a ring, and runs a probabilistic **sympathetic flood** (`cascade.gd`) so nearby sources catch in a cascade whose strength is the Director-driven `coupling` macro. Color comes from new palettes with slow `hue_drift`.

**Tech Stack:** Godot 4.6, GDScript. Framework: `common/core/` (SimModel, MacroMapper, Director, ParamSchema). Test runner: `common/core/tests/run_tests.gd` (symlinked into each model as `core/tests/`).

## Global Constraints

- **Pure data presets:** `pulsar` is JSON only — macros, a `director` key, and `overrides` for long-form knobs. Mirror how `supernova_orbit/presets/odyssey.json` is built.
- **No regressions to existing presets:** every new param/macro defaults to off/neutral (`source_count` 1, `coupling` 0.0, `sympathy` 0.0, `hue_drift` 0.0). With `source_count` 1 and `coupling` 0, the model must behave as a single center source (the `default`/`gentle`/`cataclysm` look). No back-compat constraint on the *new* preset's look.
- **Determinism:** all randomness via `s = rng.stream("sim")` (or a named stream). Same seed → same render.
- **Sim stays LDR:** `sim_vp.use_hdr_2d = false`, additive blend — unchanged.
- **Design space is 1920×1080.** Never shrink the viewport.
- **Verification model:** pure helpers are TDD'd against `run_tests.gd`. Visual model behavior is verified by a headless smoke run (no script errors) + a short proof render the user reviews — not scripted assertions.
- **Test command:** `godot --headless --path radial_burst --script res://core/tests/run_tests.gd` → `TESTS: N run, 0 failed` (exit 0).

---

### Task 1: `hue.gd` — slow hue-rotation helper

**Files:**
- Create: `common/core/hue.gd`
- Test: `common/core/tests/run_tests.gd` (add `test_hue_*` methods + `const Hue`)
- Modify: `README.md` (test-count line)

**Interfaces:**
- Produces: `Hue.rotated(c: Color, deg: float) -> Color` — returns `c` with hue rotated by `deg` degrees (absolute), saturation/value/alpha preserved.

- [ ] **Step 1: Write the failing tests**

In `common/core/tests/run_tests.gd`, add after the director section (near the end of the file):

```gdscript
# ---------------- hue ----------------

const Hue = preload("res://core/hue.gd")

func test_hue_zero_is_identity() -> void:
	var c := Color.from_hsv(0.2, 0.5, 0.8)
	var r := Hue.rotated(c, 0.0)
	check(absf(r.h - c.h) < 0.001, "0 deg keeps hue")
	check(absf(r.s - c.s) < 0.001 and absf(r.v - c.v) < 0.001, "0 deg keeps sat/val")

func test_hue_360_wraps_to_same() -> void:
	var c := Color.from_hsv(0.3, 0.7, 0.9)
	var r := Hue.rotated(c, 360.0)
	check(absf(r.h - c.h) < 0.001, "360 deg wraps to same hue")

func test_hue_180_is_opposite() -> void:
	var c := Color.from_hsv(0.0, 1.0, 1.0)  # h = 0
	var r := Hue.rotated(c, 180.0)
	check(absf(r.h - 0.5) < 0.001, "180 deg -> h = 0.5")

func test_hue_preserves_alpha() -> void:
	var r := Hue.rotated(Color(1, 1, 1, 0.4), 90.0)
	check_eq(r.a, 0.4, "alpha preserved")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: FAIL — parse/preload error on missing `res://core/hue.gd`.

- [ ] **Step 3: Implement `common/core/hue.gd`**

```gdscript
extends RefCounted
# Slow hue rotation for long-form palette drift. `deg` is absolute degrees;
# saturation, value and alpha are preserved. Grayscale (s == 0) is unaffected.

static func rotated(c: Color, deg: float) -> Color:
	var shift := fposmod(deg, 360.0) / 360.0
	var h := fposmod(c.h + shift, 1.0)
	return Color.from_hsv(h, c.s, c.v, c.a)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 26 run, 0 failed` (22 prior + 4 new).

- [ ] **Step 5: Update README test count**

In `README.md`, change the `## Tests` expected line from `TESTS: 22 run, 0 failed` to `TESTS: 26 run, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add common/core/hue.gd common/core/tests/run_tests.gd README.md
git commit -m "core: hue.gd — shared hue-rotation helper for long-form palette drift"
```

---

### Task 2: `cascade.gd` — probabilistic sympathetic flood

**Files:**
- Create: `common/core/cascade.gd`
- Test: `common/core/tests/run_tests.gd` (add `test_cascade_*` + `const Cascade`)
- Modify: `README.md` (test-count line)

**Interfaces:**
- Consumes: `RNGService` (already imported in the test file).
- Produces: `Cascade.flood(positions: Array, origin: int, coupling: float, radius: float, rng: RandomNumberGenerator) -> Array` — BFS over `positions` (Array of `Vector2`). Starting at `origin`, each not-yet-lit point within `radius` of a lit point catches with probability `coupling`. Returns an Array of `{idx: int, dist: float}` for caught points (excluding `origin`); `dist` is straight-line distance from `origin`.

- [ ] **Step 1: Write the failing tests**

In `common/core/tests/run_tests.gd`, add:

```gdscript
# ---------------- cascade ----------------

const Cascade = preload("res://core/cascade.gd")

func _line5() -> Array:
	# 5 points in a row, 100 px apart
	return [Vector2(0, 0), Vector2(100, 0), Vector2(200, 0), Vector2(300, 0), Vector2(400, 0)]

func test_cascade_zero_coupling_no_catch() -> void:
	var got := Cascade.flood(_line5(), 0, 0.0, 150.0, RNGService.new(1).stream("c"))
	check_eq(got.size(), 0, "coupling 0 -> nobody catches")

func test_cascade_full_coupling_chains_within_radius() -> void:
	# radius 150 links 100px neighbors -> chain reaches all 4 from idx 0
	var got := Cascade.flood(_line5(), 0, 1.0, 150.0, RNGService.new(1).stream("c"))
	check_eq(got.size(), 4, "coupling 1 chains down the line")

func test_cascade_radius_below_gap_no_catch() -> void:
	var got := Cascade.flood(_line5(), 0, 1.0, 50.0, RNGService.new(1).stream("c"))
	check_eq(got.size(), 0, "radius below neighbor gap -> no catch")

func test_cascade_deterministic() -> void:
	var a := Cascade.flood(_line5(), 0, 0.5, 150.0, RNGService.new(7).stream("c"))
	var b := Cascade.flood(_line5(), 0, 0.5, 150.0, RNGService.new(7).stream("c"))
	check_eq(a.size(), b.size(), "same seed -> same catch count")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: FAIL — missing `res://core/cascade.gd`.

- [ ] **Step 3: Implement `common/core/cascade.gd`**

```gdscript
extends RefCounted
# Probabilistic sympathetic flood. Given point positions and an ignition origin,
# each not-yet-lit point within `radius` of a lit point catches with probability
# `coupling`, cascading outward (BFS). Deterministic given `rng`. Returns an
# Array of {idx:int, dist:float} for caught points, excluding the origin;
# `dist` is straight-line distance from the origin (for ripple timing).

static func flood(positions: Array, origin: int, coupling: float, radius: float, rng: RandomNumberGenerator) -> Array:
	var lit := {origin: true}
	var frontier := [origin]
	var caught := []
	var r2 := radius * radius
	while not frontier.is_empty():
		var n: int = frontier.pop_front()
		for m in positions.size():
			if lit.has(m):
				continue
			if (positions[m] - positions[n]).length_squared() <= r2 and rng.randf() < coupling:
				lit[m] = true
				frontier.push_back(m)
				caught.append({"idx": m, "dist": (positions[m] - positions[origin]).length()})
	return caught
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 30 run, 0 failed`.

- [ ] **Step 5: Update README test count**

In `README.md`, change the expected line to `TESTS: 30 run, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add common/core/cascade.gd common/core/tests/run_tests.gd README.md
git commit -m "core: cascade.gd — probabilistic sympathetic flood helper"
```

---

### Task 3: radial_burst — multi-source + sympathetic firing + palettes

**Files:**
- Modify (full rewrite): `radial_burst/main.gd`

**Interfaces:**
- Consumes: `Hue.rotated()` (Task 1), `Cascade.flood()` (Task 2), `SimModel` base, `MacroMapper` (via base `resolve_*`).
- Produces: schema with new macro `coupling` and params `source_count`, `sympathy`, `sympathy_radius`, `ripple_speed`, `hue_drift`; palette enum extended with `danger`, `board`. New runtime structures `sources`, `pending`, `rings`.

**Behavior contract (what the smoke + proof must show):**
- `source_count` 1, `coupling` 0 → single center source with satellites (no cascade) — matches today.
- `source_count` ≥ 2 → sources placed on a loose ring; each fires on its own staggered timer.
- `sympathy` > 0 → an ignition can trigger nearby sources in a visible ripple.
- `hue_drift` > 0 → source/ring colors rotate over the run.
- `energy`/`density` drift reaches the particle emitters on each new burst (re-read at ignite).

- [ ] **Step 1: Replace `radial_burst/main.gd` with the restructured model**

```gdscript
extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")
const Hue = preload("res://core/hue.gd")
const Cascade = preload("res://core/cascade.gd")

var sim_vp: SubViewport
var fade_rect: ColorRect
var rings_node: Node2D
var mirror_rects: Array[TextureRect] = []
var env: Environment
var s: RandomNumberGenerator
var sim_t := 0.0

# Independent burst sources:
#   {pos: Vector2, base: Color, main: GPUParticles2D, subs: Array,
#    timer: float, period: float}
var sources: Array = []
var pending: Array = []   # sympathetic ignitions: {at: float, idx: int}
var rings: Array = []     # {center: Vector2, r, speed, alpha, color}

const PALETTES := {
	"silver": [Color(1, 1, 1), Color(0.78, 0.82, 0.88)],
	"bone": [Color(1, 0.97, 0.9), Color(0.9, 0.82, 0.7)],
	"ice": [Color(0.85, 0.95, 1), Color(0.6, 0.8, 1)],
	# cribbed from radio.dangerthirdrail.com (offline.html --red + board colors)
	"danger": [Color("#ff2a2a"), Color(1, 1, 1), Color(0.45, 0.55, 1.0)],
	"board": [
		Color(1.00, 0.20, 0.20), Color(0.15, 0.85, 1.00), Color(1.00, 0.95, 0.15),
		Color(0.55, 0.20, 1.00), Color(1.00, 0.40, 0.10), Color(0.10, 1.00, 0.45),
		Color(1.00, 0.20, 0.55), Color(0.00, 1.00, 0.85),
	],
}

func model_name() -> String:
	return "radial_burst"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("energy", 0.7), PS.macro_def("density", 0.55),
			PS.macro_def("symmetry", 0.35), PS.macro_def("grit", 0.4),
			PS.macro_def("coupling", 0.0),
		],
		"params": [
			PS.f("loop_period", 5.0, 2.0, 12.0, {"live": false, "jitter": {"pct": 10.0}}),
			PS.i("source_count", 1, 1, 6, {"live": false}),
			PS.i("particle_count", 4500, 500, 20000, {"live": false, "macro": {"name": "density", "lo": 2000, "hi": 7000}}),
			PS.f("burst_speed", 260.0, 50.0, 900.0, {"live": false, "macro": {"name": "energy", "lo": 120.0, "hi": 400.0}, "jitter": {"pct": 8.0}}),
			PS.f("speed_spread", 0.55, 0.0, 0.9, {"live": false, "macro": {"name": "grit", "lo": 0.25, "hi": 0.85}}),
			PS.f("particle_life", 3.5, 0.5, 6.0, {"live": false}),
			PS.f("damping", 60.0, 0.0, 200.0, {"live": false}),
			PS.f("streak_len", 27.5, 5.0, 80.0, {"live": false, "macro": {"name": "energy", "lo": 10.0, "hi": 45.0}}),
			PS.f("trail_persist", 0.10, 0.02, 0.5),
			PS.i("ring_count", 3, 0, 8, {"live": false, "macro": {"name": "energy", "lo": 1, "hi": 6}}),
			PS.f("ring_speed", 600.0, 100.0, 1600.0, {"live": false}),
			PS.f("ring_width", 5.0, 1.0, 18.0, {"live": false}),
			PS.i("subburst_count", 9, 0, 24, {"live": false, "macro": {"name": "density", "lo": 2, "hi": 18}}),
			PS.f("subburst_scale", 0.22, 0.05, 0.5, {"live": false}),
			PS.f("sympathy", 0.0, 0.0, 1.0, {"macro": {"name": "coupling", "lo": 0.0, "hi": 1.0}}),
			PS.f("sympathy_radius", 500.0, 50.0, 1200.0),
			PS.f("ripple_speed", 1600.0, 200.0, 4000.0),
			PS.f("hue_drift", 0.0, 0.0, 90.0),
			PS.e("mirror", "horizontal", PackedStringArray(["off", "horizontal", "quad"]), {"live": false}),
			PS.f("mirror_mix", 0.55, 0.0, 1.0, {"macro": {"name": "symmetry", "lo": 0.0, "hi": 0.9}}),
			PS.f("glow", 0.35, 0.0, 3.0),
			PS.e("palette", "silver", PackedStringArray(["silver", "bone", "ice", "danger", "board"]), {"live": false}),
		],
	}

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):  # keep the tweak panel
			c.queue_free()
	sources.clear()
	mirror_rects.clear()
	rings.clear()
	pending.clear()
	sim_t = 0.0
	s = rng.stream("sim")
	_build()

func _build() -> void:
	sim_vp = SubViewport.new()
	sim_vp.size = Vector2i(1920, 1080)
	sim_vp.disable_3d = true
	sim_vp.use_hdr_2d = false  # keep sim in LDR so additive particles clamp at 1.0
	sim_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE  # then never
	sim_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sim_vp)
	sim_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER

	fade_rect = ColorRect.new()
	fade_rect.size = Vector2(1920, 1080)
	fade_rect.color = Color(0, 0, 0, params["trail_persist"])
	var fade_mat := CanvasItemMaterial.new()
	fade_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	fade_rect.material = fade_mat
	sim_vp.add_child(fade_rect)

	rings_node = Node2D.new()
	rings_node.position = Vector2.ZERO
	rings_node.draw.connect(_draw_rings)
	sim_vp.add_child(rings_node)

	var pal: Array = PALETTES[params["palette"]]
	var positions := _place_sources()
	var n := positions.size()
	for i in n:
		var base: Color = pal[i % pal.size()]
		var main := _make_emitter(int(params["particle_count"]), 1.0, base)
		main.position = positions[i]
		sim_vp.add_child(main)
		var subs: Array = []
		for k in int(params["subburst_count"]):
			var amt := maxi(int(params["particle_count"] * params["subburst_scale"] / maxf(1.0, params["subburst_count"])), 50)
			var e := _make_emitter(amt, 0.45, base)
			sim_vp.add_child(e)
			subs.append(e)
		var period: float = params["loop_period"] * s.randf_range(0.85, 1.15)
		# phase-offset so sources fire staggered; source 0 fires almost immediately
		sources.append({"pos": positions[i], "base": base, "main": main, "subs": subs,
			"timer": period - period * float(i) / float(n), "period": period})

	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = params["glow"]
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	we.environment = env
	add_child(we)

	var flips := [[false, false]]
	match params["mirror"]:
		"horizontal":
			flips = [[false, false], [true, false]]
		"quad":
			flips = [[false, false], [true, false], [false, true], [true, true]]
	for i in flips.size():
		var tr := TextureRect.new()
		tr.texture = sim_vp.get_texture()
		tr.size = Vector2(1920, 1080)
		tr.flip_h = flips[i][0]
		tr.flip_v = flips[i][1]
		if i > 0:
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			tr.material = mat
			tr.modulate = Color(1, 1, 1, params["mirror_mix"])
			mirror_rects.append(tr)
		add_child(tr)

func _place_sources() -> Array:
	var center := Vector2(960, 540)
	var n: int = maxi(int(params["source_count"]), 1)
	var out := []
	if n == 1:
		out.append(center)
		return out
	for i in n:
		var ang := TAU * float(i) / float(n) + s.randf_range(-0.15, 0.15)
		out.append(center + Vector2.from_angle(ang) * 360.0 * s.randf_range(0.85, 1.1))
	return out

func _make_emitter(amount: int, scale_mul: float, base: Color) -> GPUParticles2D:
	var g := GPUParticles2D.new()
	g.amount = maxi(amount, 8)
	g.one_shot = true
	g.explosiveness = 1.0
	g.emitting = false
	g.lifetime = params["particle_life"]
	g.texture = _streak_texture()
	if "use_fixed_seed" in g:
		g.use_fixed_seed = true
		g.seed = s.randi()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	g.process_material = _make_process_material(scale_mul, base)
	return g

func _make_process_material(scale_mul: float, base: Color) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 4.0
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.gravity = Vector3.ZERO
	var spd: float = params["burst_speed"] * scale_mul
	pm.initial_velocity_min = spd * (1.0 - params["speed_spread"])
	pm.initial_velocity_max = spd * (1.0 + params["speed_spread"])
	pm.damping_min = params["damping"] * 0.6
	pm.damping_max = params["damping"] * 1.4
	pm.particle_flag_align_y = true
	pm.scale_min = params["streak_len"] / 128.0 * 0.5
	pm.scale_max = params["streak_len"] / 128.0 * 1.3
	pm.lifetime_randomness = 0.45
	var col := Hue.rotated(base, params["hue_drift"] * sim_t / 60.0)
	var grad := Gradient.new()
	grad.set_color(0, col.lerp(Color(1, 1, 1), 0.5))         # hot core
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))       # fade to transparent
	grad.add_point(0.35, col)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	return pm

func _streak_texture() -> ImageTexture:
	var w := 16
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var fy := sin(PI * float(y) / float(h))
		for x in w:
			var dx := (float(x) - w / 2.0 + 0.5) / 3.5
			var a := exp(-dx * dx) * pow(fy, 0.7)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _src_color(src: Dictionary) -> Color:
	return Hue.rotated(src["base"], params["hue_drift"] * sim_t / 60.0)

func _ignite(i: int, depth: int) -> void:
	var src: Dictionary = sources[i]
	# re-read drifted params so energy/density/hue take effect on each burst
	src["main"].amount = maxi(int(params["particle_count"]), 8)
	src["main"].lifetime = params["particle_life"]
	src["main"].process_material = _make_process_material(1.0, src["base"])
	src["main"].position = src["pos"]
	src["main"].restart()
	for e in src["subs"]:
		var ang := s.randf_range(0.0, TAU)
		var at := s.randf_range(0.1, 0.5)
		var dist: float = params["burst_speed"] * 0.55 * at
		e.process_material = _make_process_material(0.45, src["base"])
		e.position = src["pos"] + Vector2.from_angle(ang) * dist
		e.restart()
	for ri in int(params["ring_count"]):
		rings.append({"center": src["pos"], "r": 10.0,
			"speed": params["ring_speed"] * s.randf_range(0.7, 1.3),
			"alpha": 1.0, "color": _src_color(src)})
	src["timer"] = 0.0
	src["period"] = params["loop_period"] * s.randf_range(0.85, 1.15)
	# sympathetic cascade (only from a primary ignition)
	if sources.size() > 1 and depth == 0 and params["sympathy"] > 0.0:
		var positions := []
		for sc in sources:
			positions.append(sc["pos"])
		var caught := Cascade.flood(positions, i, params["sympathy"], params["sympathy_radius"], s)
		for c in caught:
			pending.append({"at": sim_t + c["dist"] / maxf(params["ripple_speed"], 1.0), "idx": int(c["idx"])})

func _draw_rings() -> void:
	for r in rings:
		var c: Color = r["color"]
		c.a = r["alpha"]
		rings_node.draw_arc(r["center"], r["r"], 0, TAU, 96, c, params["ring_width"], true)

func _process(delta: float) -> void:
	super._process(delta)
	if s == null:
		return
	sim_t += delta
	for i in sources.size():
		var src: Dictionary = sources[i]
		src["timer"] += delta
		if src["timer"] >= src["period"]:
			_ignite(i, 0)
	for ev in pending.duplicate():
		if sim_t >= ev["at"]:
			_ignite(int(ev["idx"]), 1)
			pending.erase(ev)
	for r in rings:
		r["r"] += r["speed"] * delta
		r["alpha"] = maxf(r["alpha"] - delta * 0.8, 0.0)
	for j in range(rings.size() - 1, -1, -1):  # cull dead rings over a long run
		if rings[j]["alpha"] <= 0.0:
			rings.remove_at(j)
	rings_node.queue_redraw()

func apply_live(p: Dictionary) -> void:
	if fade_rect != null:
		fade_rect.color = Color(0, 0, 0, p["trail_persist"])
	if env != null:
		env.glow_intensity = p["glow"]
	for tr in mirror_rects:
		tr.modulate = Color(1, 1, 1, p["mirror_mix"])
```

- [ ] **Step 2: Run the unit suite — confirm no regression**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 30 run, 0 failed`. (Schema change doesn't touch framework tests.)

- [ ] **Step 3: Headless smoke — default preset (single-source path)**

Run: `godot --headless --path radial_burst --quit-after 240 2>&1 | grep -iE "SCRIPT ERROR|ERROR|Parse" || echo "CLEAN"`
Expected: `CLEAN` — runs ~4s (240 frames), no script errors. Exercises build, ignite, rings, hue (drift 0), single source.

- [ ] **Step 4: Headless smoke — multi-source + sympathy**

Create a throwaway preset to exercise the new paths:

```bash
cat > /tmp/rb_smoke.json <<'JSON'
{"model":"radial_burst","seed":7,"duration_sec":5.0,
 "macros":{"coupling":0.6},
 "overrides":{"source_count":5,"palette":"board","hue_drift":30.0,"loop_period":2.0,"mirror":"off"},
 "jitter":{},"director":{}}
JSON
godot --headless --path radial_burst --quit-after 300 -- --preset /tmp/rb_smoke.json 2>&1 | grep -iE "SCRIPT ERROR|ERROR|Parse" || echo "CLEAN"
```

Expected: `CLEAN` — exercises 5 sources, cascade flood, ripple scheduling, board palette, hue drift.

- [ ] **Step 5: Commit**

```bash
git add radial_burst/main.gd
git commit -m "radial_burst: multi-source sympathetic bursts + radio-cribbed palettes + hue drift

N independent burst sources (source_count) on a loose ring, each a colored
emitter with satellites and its own fire timer. Ignition runs a probabilistic
sympathetic flood (cascade.gd) so nearby sources catch in a ripple whose
strength is the director-driven coupling macro -> sympathy param. New danger/
board palettes cribbed from radio.dangerthirdrail.com; hue_drift rotates colors
over the run. source_count 1 + coupling 0 reproduces the single-center look."
```

---

### Task 4: `pulsar` preset + proof render + docs

**Files:**
- Create: `radial_burst/presets/pulsar.json`
- Modify: `README.md` (radial_burst variant descriptions)

**Interfaces:**
- Consumes: the schema from Task 3 (macros `energy`/`density`/`coupling`; params `source_count`/`palette`/`hue_drift`/`sympathy_radius`/`ripple_speed`).

- [ ] **Step 1: Write `radial_burst/presets/pulsar.json`**

```json
{
  "model": "radial_burst",
  "seed": 204,
  "duration_sec": 300.0,
  "macros": {
    "energy": 0.35,
    "density": 0.4,
    "symmetry": 0.3,
    "grit": 0.45,
    "coupling": 0.2
  },
  "overrides": {
    "source_count": 4,
    "palette": "danger",
    "hue_drift": 10.0,
    "loop_period": 4.0,
    "sympathy_radius": 560.0,
    "ripple_speed": 1500.0,
    "trail_persist": 0.08,
    "glow": 0.6,
    "mirror": "off"
  },
  "jitter": {},
  "director": {
    "enabled": true,
    "period_sec": 150.0,
    "amplitude": 0.4,
    "macros": ["energy", "density", "coupling"]
  }
}
```

Rationale: base macros sit low (calm); the Director swells `energy`/`density`/`coupling` together on a 150s curve so the run rises into a coupled riot mid-cycle and settles back (calm→riot→calm). 4 sources, `danger` palette, `hue_drift` 10°/min (≈50° over 5 min).

- [ ] **Step 2: Headless smoke — the real preset**

Run: `godot --headless --path radial_burst --quit-after 600 -- --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|ERROR|Parse" || echo "CLEAN"`
Expected: `CLEAN` — ~10s, exercises director ticking + sympathy + hue together.

- [ ] **Step 3: Render a 60s proof clip**

Run: `scripts/render.sh radial_burst pulsar 60`
Expected: `rendered: <repo>/renders/radial_burst_pulsar.mp4` (1920×1080).

- [ ] **Step 4: USER REVIEW GATE — hand off the proof**

Tell the user the proof is at `renders/radial_burst_pulsar.mp4` and what to look for: calm→riot→calm swell, multiple sources, sympathetic ripples when coupling is high, danger palette + slow hue drift, legibility. **Do not proceed until the user approves the look.** Iterate on preset values (and, if needed, mechanics) per feedback; re-render the 60s proof each round.

- [ ] **Step 5: Document the variant in README**

In `README.md` under **radial_burst**, add:

```markdown
- `pulsar` — 5-minute long-form: four sympathetically-coupled burst sources on
  the station's `danger` palette (red/white/blue), drifting calm → riot → calm
  over 150s director cycles while a high-coupling ignition ripples a chain of
  blooms across the field; hue drifts ~50° across the run.
```

- [ ] **Step 6: Commit**

```bash
git add radial_burst/presets/pulsar.json README.md
git commit -m "radial_burst: pulsar — 5-min calm->riot->calm long-form preset (danger palette, coupled sources)"
```

- [ ] **Step 7: Full 300s render (after approval)**

Run: `scripts/render.sh radial_burst pulsar 300`
Expected: `rendered: <repo>/renders/radial_burst_pulsar.mp4` (~5 min, 1080p). Hand off for final confirmation.

---

## Self-Review

**Spec coverage** (against `2026-06-17-longform-attention-presets-design.md`, radial_burst section):
- calm→riot→calm Director arc → Task 4 preset `director` on energy/density/coupling. ✓
- `danger` + `board` palettes cribbed from radio → Task 3 `PALETTES`. ✓
- Multiple sources + sympathetic chain-triggering, `coupling` Director-driven → Task 3 sources + `Cascade.flood`, `coupling` macro → `sympathy` param. ✓
- Per-burst emitter re-config so energy/density drift reaches emitters → Task 3 `_ignite` rebuilds `process_material` + `amount`. ✓
- `hue.gd` helper + unit test → Tasks 1. ✓
- `hue_drift` default 0; new params neutral → Task 3 schema defaults, Global Constraints. ✓
- Verification: suite green + headless smoke + 60s proof + user review + full render → Tasks 1–4 steps. ✓
- Optional mega-burst at riot peak → **intentionally deferred** (not in pulsar v1); revisit after user reviews the proof. Noted here so it isn't silently dropped.

**Placeholder scan:** No TBD/TODO; all code and commands are concrete.

**Type consistency:** `Hue.rotated(Color, float) -> Color`, `Cascade.flood(Array, int, float, float, RNG) -> Array of {idx,dist}` used consistently in Task 3. Macro `coupling` → param `sympathy` (mapped) used consistently. `sources` dict keys (`pos/base/main/subs/timer/period`) consistent across `_build`/`_ignite`/`_process`.
