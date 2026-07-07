# peg_cascade Finishing Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace peg_cascade's static random peg field with a pattern-era morphing playfield (`pattern_phase`), parameterize ball drops (movable/multi emitters, volleys, aim), and add palette hue drift — all as live params the Designer can modulate.

**Architecture:** A new pure-static pattern library (`peg_cascade/patterns.gd`) generates exactly-N, angle-sorted peg positions for 3 patterns (hex lattice / rings / spokes); `main.gd` derives every field peg's position per-frame from `pattern_phase` + `morph_dwell` (rest-then-glide easing), so scrubbing is exact. Drops and hue drift are read-at-use live params; the palette dict is shared by reference with pegs/balls so hue rotation propagates.

**Tech Stack:** Godot 4.6 GDScript (tabs for indentation), existing vxstory core (`sim_model.gd`, `param_schema.gd`, `modulation.gd`), assert-based test runner `common/core/tests/run_tests.gd`.

**Spec:** `docs/superpowers/specs/2026-07-06-peg-cascade-finishing-pass-design.md`

## Global Constraints

- Board center is `Vector2(960, 620)`; hex region x 240–1680, y 300–980; rings `ry` 110–360 with `rx = ry * 1.5`; spokes radius 100–360 elliptical (`Vector2(cos(a) * 1.5, sin(a)) * r`).
- `positions(pattern, n)` MUST return **exactly n** positions, **sorted by polar angle about center (radius tiebreaker)**, deterministic (no RNG), pattern index wrapped `posmod(pattern, 3)`.
- New schema params (exact names/ranges/defaults): `pattern_phase` f 0.0–3.0 def 0.0; `morph_dwell` f 0.0–0.9 def 0.7; `drop_x` f 0.0–1.0 def 0.5; `emitter_count` i 1–3 def 1; `volley_count` i 1–7 def 1; `volley_spread` f 0.0–0.8 def 0.35; `aim_bias` f 0.0–1.0 def 0.0; `hue_drift` f 0.0–1.0 def 0.0 — all live (no `"live": false`).
- The `layout` param, grid/scatter generators, and scatter top-up/trim are REMOVED. No preset back-compat required, but shipped presets must load warning-free after Task 3.
- Macros unchanged: `complexity`, `ball_rate`, `bounciness`, `fx`; `complexity` still maps `peg_count` 40–200 and `spinner_count` 0–4. Events unchanged: `spawn`, `hit`, `chain` — but `spawn` fires once per fire moment, not per ball.
- Spinner pegs are an overlay IN ADDITION to `peg_count` (they no longer count against the budget).
- Test suite must pass under BOTH projects: `godot --headless --path peg_cascade --script res://core/tests/run_tests.gd` and `--path radial_burst`. Pattern tests self-skip under non-peg models via `ResourceLoader.exists("res://patterns.gd")`.
- GDScript files use TAB indentation (match existing files exactly).
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: Pattern library (`patterns.gd`) + unit tests

**Files:**
- Create: `peg_cascade/patterns.gd`
- Test: `common/core/tests/run_tests.gd` (append at end of file)

**Interfaces:**
- Produces: `static func positions(pattern: int, n: int) -> PackedVector2Array` on `res://patterns.gd` (preloadable from peg_cascade's `main.gd`). Also `const CENTER := Vector2(960, 620)`.
- Consumes: nothing (pure math).

- [ ] **Step 1: Create a failing stub**

Write `peg_cascade/patterns.gd` (NOTE: `peg_cascade/core` is a symlink to `common/core`; this new file lives at the model root, NOT in core):

```gdscript
extends RefCounted
# Pure pattern-position generators for peg_cascade's morphing playfield.
# positions(pattern, n) returns EXACTLY n positions for pattern 0 (hex
# lattice), 1 (concentric rings) or 2 (radial spokes), sorted by polar angle
# about the board center (radius tiebreak) so index i in one pattern glides
# to a coherent partner in the next. Deterministic: no RNG, no scene access.

const CENTER := Vector2(960, 620)

static func positions(pattern: int, n: int) -> PackedVector2Array:
	return PackedVector2Array()
```

- [ ] **Step 2: Append the tests to `common/core/tests/run_tests.gd`**

Append at the very end of the file:

```gdscript
# ---------------- peg_cascade patterns ----------------
# These load the model-local patterns.gd; they self-skip when the suite runs
# under a model that doesn't have it (only peg_cascade does).

func test_peg_patterns_exact_counts() -> void:
	if not ResourceLoader.exists("res://patterns.gd"):
		return
	var P = load("res://patterns.gd")
	for n in [20, 47, 110, 200, 240]:
		for pat in 3:
			check_eq(P.positions(pat, n).size(), n, "pattern %d must return exactly %d positions" % [pat, n])

func test_peg_patterns_bounds() -> void:
	if not ResourceLoader.exists("res://patterns.gd"):
		return
	var P = load("res://patterns.gd")
	for pat in 3:
		for p in P.positions(pat, 150):
			check(p.x >= 140.0 and p.x <= 1780.0 and p.y >= 180.0 and p.y <= 1050.0,
				"pattern %d peg %s out of bounds" % [pat, str(p)])

func test_peg_patterns_sorted_by_angle() -> void:
	if not ResourceLoader.exists("res://patterns.gd"):
		return
	var P = load("res://patterns.gd")
	var c := Vector2(960, 620)
	for pat in 3:
		var pts: PackedVector2Array = P.positions(pat, 120)
		for i in pts.size() - 1:
			check((pts[i] - c).angle() <= (pts[i + 1] - c).angle() + 0.0001,
				"pattern %d must be angle-sorted at index %d" % [pat, i])

func test_peg_patterns_deterministic_and_wrapping() -> void:
	if not ResourceLoader.exists("res://patterns.gd"):
		return
	var P = load("res://patterns.gd")
	check(P.positions(0, 90) == P.positions(3, 90), "pattern index must wrap mod 3")
	check(P.positions(1, 90) == P.positions(1, 90), "generators must be deterministic")
```

- [ ] **Step 3: Run the suite under peg_cascade — verify the new tests FAIL**

Run: `cd /home/tmoney/code/vibes/vxstory && godot --headless --path peg_cascade --script res://core/tests/run_tests.gd 2>&1 | tail -3`
Expected: `TESTS: 67 run, 15 failed` — the 15 exact-count checks (5 n values × 3 patterns) fail against the empty stub; bounds/sorted/deterministic pass trivially on empty arrays. That's the red state.

- [ ] **Step 4: Implement the generators**

Replace the body of `peg_cascade/patterns.gd` below the header comment with:

```gdscript
const CENTER := Vector2(960, 620)

static func positions(pattern: int, n: int) -> PackedVector2Array:
	var pts: Array
	match posmod(pattern, 3):
		0: pts = _hex(n)
		1: pts = _rings(n)
		_: pts = _spokes(n)
	pts.sort_custom(_angle_sort)
	return PackedVector2Array(pts)

static func _angle_sort(a: Vector2, b: Vector2) -> bool:
	var oa := a - CENTER
	var ob := b - CENTER
	var aa := oa.angle()
	var ab := ob.angle()
	if absf(aa - ab) > 0.0001:
		return aa < ab
	return oa.length_squared() < ob.length_squared()

static func _hex(n: int) -> Array:
	# Staggered rows filling x 240-1680, y 300-980. Every row is centered on
	# x=960; full odd rows shift half a column (the stagger). The final
	# partial row is centered too, so the lattice never looks ragged.
	var cols := maxi(3, int(round(sqrt(n * 1440.0 / 680.0))))
	var rows := ceili(float(n) / float(cols))
	var dx := 1440.0 / float(cols)
	var dy := 680.0 / float(maxi(rows - 1, 1))
	var out := []
	var left := n
	for r in rows:
		var count := mini(cols, left)
		var stagger := dx * 0.5 if (r % 2 == 1 and count == cols) else 0.0
		var x0 := 960.0 - dx * float(count - 1) * 0.5 + stagger
		var y := (300.0 + dy * float(r)) if rows > 1 else 640.0
		for j in count:
			out.append(Vector2(x0 + dx * float(j), y))
		left -= count
	return out

static func _rings(n: int) -> Array:
	# Concentric ellipses about CENTER; pegs allocated per ring proportional
	# to its vertical radius (~circumference); outermost ring absorbs the
	# rounding remainder. Ring k is phase-offset so seams don't align.
	var rings := clampi(int(round(sqrt(float(n) / 6.0))), 2, 6)
	var rys: Array = []
	var total := 0.0
	for k in rings:
		var ry := 110.0 + 250.0 * (float(k) / float(maxi(rings - 1, 1)))
		rys.append(ry)
		total += ry
	var out := []
	var left := n
	for k in rings:
		var count := left
		if k < rings - 1:
			count = mini(int(round(float(n) * float(rys[k]) / total)), left)
		for j in count:
			var a := TAU * float(j) / float(maxi(count, 1)) + 0.35 * float(k)
			out.append(CENTER + Vector2(cos(a) * float(rys[k]) * 1.5, sin(a) * float(rys[k])))
		left -= count
	return out

static func _spokes(n: int) -> Array:
	# S evenly-angled spokes; each a line of pegs from inner radius 100 to
	# outer 360, elliptically stretched. First n % S spokes get one extra peg.
	var spokes := clampi(int(round(float(n) / 10.0)), 6, 20)
	var base := floori(float(n) / float(spokes))
	var extra := n % spokes
	var out := []
	for si in spokes:
		var count := base + (1 if si < extra else 0)
		if count == 0:
			continue
		var a := TAU * float(si) / float(spokes)
		var dir := Vector2(cos(a) * 1.5, sin(a))
		for j in count:
			var r := 100.0 + 260.0 * (float(j) / float(maxi(count - 1, 1)))
			out.append(CENTER + dir * r)
	return out
```

(Keep the file's `extends RefCounted` + header comment from Step 1; the file ends up with ONE `const CENTER` — replace the stub's `positions` rather than duplicating.)

- [ ] **Step 5: Run the suite under peg_cascade — verify green**

Run: `cd /home/tmoney/code/vibes/vxstory && godot --headless --path peg_cascade --script res://core/tests/run_tests.gd 2>&1 | tail -3`
Expected: `TESTS: 67 run, 0 failed`

- [ ] **Step 6: Run the suite under radial_burst — verify the new tests self-skip (still green)**

Run: `cd /home/tmoney/code/vibes/vxstory && godot --headless --path radial_burst --script res://core/tests/run_tests.gd 2>&1 | tail -3`
Expected: `TESTS: 67 run, 0 failed`

- [ ] **Step 7: Commit**

```bash
git add peg_cascade/patterns.gd common/core/tests/run_tests.gd
git commit -m "peg_cascade: pattern library (hex/rings/spokes, exact-N, angle-sorted)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: main.gd rework — morphing playfield, parameterized drops, hue drift

**Files:**
- Modify: `peg_cascade/main.gd` (full-file replacement below)

**Interfaces:**
- Consumes: `preload("res://patterns.gd")` → `positions(pattern: int, n: int) -> PackedVector2Array` (Task 1).
- Produces: the new schema params listed in Global Constraints (Task 3's presets/README depend on those exact names).

- [ ] **Step 1: Replace `peg_cascade/main.gd` with the following complete file**

```gdscript
extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")
const Patterns = preload("res://patterns.gd")

const PALETTES := {
	"classic": {"peg": Color("#2266ff"), "hot": Color("#ff7711"), "ball": Color("#ffffff")},
	"neon": {"peg": Color("#ff2299"), "hot": Color("#00ffcc"), "ball": Color("#ccff00")},
	"mono": {"peg": Color("#999999"), "hot": Color("#ffffff"), "ball": Color("#dddddd")},
}

class Peg extends StaticBody2D:
	var radius := 14.0
	var pal: Dictionary   # shared working palette (hue-rotated in place by the model)
	var role := "peg"     # "peg" | "hot"
	var lit := 0.0
	func _init(r: float, p_pal: Dictionary, p_role: String, mat: PhysicsMaterial) -> void:
		radius = r
		pal = p_pal
		role = p_role
		physics_material_override = mat
		var shape := CollisionShape2D.new()
		var circ := CircleShape2D.new()
		circ.radius = r
		shape.shape = circ
		add_child(shape)
	func _draw() -> void:
		var base: Color = pal[role]
		var c := base.lerp(Color.WHITE, lit * 0.8)
		c *= (1.0 + lit * 2.0)  # overbright when lit -> glows
		draw_circle(Vector2.ZERO, radius, c)
		draw_arc(Vector2.ZERO, radius + 2.0, 0, TAU, 32, Color(base, 0.5 + lit * 0.5), 2.0, true)
	func _process(delta: float) -> void:
		if lit > 0.0:
			lit = maxf(lit - delta * 2.0, 0.0)
			queue_redraw()

class Ball extends RigidBody2D:
	var radius := 11.0
	var pal: Dictionary
	func _init(r: float, p_pal: Dictionary, mat: PhysicsMaterial) -> void:
		radius = r
		pal = p_pal
		physics_material_override = mat
		contact_monitor = true
		max_contacts_reported = 4
		var shape := CollisionShape2D.new()
		var circ := CircleShape2D.new()
		circ.radius = r
		shape.shape = circ
		add_child(shape)
	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, (pal["ball"] as Color) * 1.6)
		draw_circle(Vector2.ZERO, radius * 0.55, Color.WHITE * 2.0)

var peg_defs: Array = []      # field: {pattern_i, parent_idx:-1, hot, node, dead_at}
                              # spinner: {pos, pattern_i:-1, parent_idx, hot, node, dead_at}
var spinners: Array = []      # {node, speed}
var balls: Array = []
var fx_pool: Array[GPUParticles2D] = []
var fx_i := 0
var boom_pool: Array[GPUParticles2D] = []
var boom_i := 0
var recent_hits: Array = []   # {pos, time}
var phys_mat: PhysicsMaterial
var base_pal: Dictionary      # untouched palette source colors
var pal: Dictionary           # working palette, hue-rotated in place (shared by ref)
var pattern_cache := {}       # era int (0..2) -> PackedVector2Array of size peg_count
var last_hue := 0.0
var sim_t := 0.0
var fire_acc := 0.0
var respawn_acc := 0.0
var s: RandomNumberGenerator
var env: Environment

func model_name() -> String:
	return "peg_cascade"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("complexity", 0.5), PS.macro_def("ball_rate", 0.5),
			PS.macro_def("bounciness", 0.6), PS.macro_def("fx", 0.7),
		],
		"params": [
			PS.i("peg_count", 110, 20, 240, {"live": false, "macro": {"name": "complexity", "lo": 40, "hi": 200}}),
			PS.f("peg_radius", 14.0, 8.0, 26.0, {"live": false}),
			PS.f("pattern_phase", 0.0, 0.0, 3.0),
			PS.f("morph_dwell", 0.7, 0.0, 0.9),
			PS.i("spinner_count", 2, 0, 4, {"live": false, "macro": {"name": "complexity", "lo": 0, "hi": 4}}),
			PS.f("spinner_speed", 1.0, 0.2, 3.0, {"live": false, "jitter": {"pct": 25.0}}),
			PS.f("fire_interval", 0.45, 0.1, 2.0, {"macro": {"name": "ball_rate", "lo": 1.2, "hi": 0.12}}),
			PS.f("ball_speed", 900.0, 400.0, 1600.0),
			PS.f("ball_radius", 11.0, 6.0, 18.0, {"live": false}),
			PS.f("bounce", 0.8, 0.3, 1.0, {"live": false, "macro": {"name": "bounciness", "lo": 0.45, "hi": 0.98}}),
			PS.f("drop_x", 0.5, 0.0, 1.0),
			PS.i("emitter_count", 1, 1, 3),
			PS.i("volley_count", 1, 1, 7),
			PS.f("volley_spread", 0.35, 0.0, 0.8),
			PS.f("aim_bias", 0.0, 0.0, 1.0),
			PS.f("sweep_range", 0.7, 0.0, 1.2),
			PS.f("sweep_speed", 0.8, 0.1, 3.0),
			PS.i("chain_trigger", 4, 2, 8),
			PS.f("chain_radius", 180.0, 60.0, 400.0, {"macro": {"name": "fx", "lo": 100.0, "hi": 320.0}}),
			PS.f("blast_impulse", 600.0, 0.0, 1500.0, {"macro": {"name": "fx", "lo": 100.0, "hi": 1200.0}}),
			PS.f("respawn_period", 8.0, 2.0, 20.0),
			PS.i("max_balls", 28, 4, 80),
			PS.f("hot_fraction", 0.25, 0.0, 1.0, {"live": false}),
			PS.f("hue_drift", 0.0, 0.0, 1.0),
			PS.f("glow", 1.3, 0.0, 3.0),
			PS.e("palette", "classic", PackedStringArray(["classic", "neon", "mono"]), {"live": false}),
		],
	}

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):
			c.queue_free()
	peg_defs.clear()
	spinners.clear()
	balls.clear()
	fx_pool.clear()
	boom_pool.clear()
	recent_hits.clear()
	pattern_cache.clear()
	sim_t = 0.0
	fire_acc = 0.0
	respawn_acc = 0.0
	fx_i = 0
	boom_i = 0
	s = rng.stream("sim")
	base_pal = PALETTES[params["palette"]]
	pal = base_pal.duplicate()
	last_hue = 0.0
	_apply_hue(params["hue_drift"])
	phys_mat = PhysicsMaterial.new()
	phys_mat.bounce = params["bounce"]
	phys_mat.friction = 0.15
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = params["glow"]
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)
	_gen_layout()
	for d in peg_defs:
		_spawn_peg(d)
	for i in 16:
		fx_pool.append(_make_pop(140, 12))
	for i in 6:
		boom_pool.append(_make_pop(420, 60))

func _gen_layout() -> void:
	# Field pegs: peg_count of them, positions owned by the pattern system.
	for i in int(params["peg_count"]):
		peg_defs.append({"pattern_i": i, "parent_idx": -1,
			"hot": s.randf() < params["hot_fraction"], "node": null, "dead_at": -1.0})
	# Spinner pegs: rotating-hub overlay, IN ADDITION to peg_count.
	for si in int(params["spinner_count"]):
		var hub := Vector2(s.randf_range(360, 1560), s.randf_range(380, 880))
		var node := Node2D.new()
		node.position = hub
		add_child(node)
		spinners.append({"node": node, "speed": params["spinner_speed"] * (1.0 if si % 2 == 0 else -1.0)})
		for arm in 6:
			for k in 2:
				var local := Vector2.from_angle(TAU * arm / 6.0) * (70.0 + 70.0 * k)
				peg_defs.append({"pos": local, "pattern_i": -1, "parent_idx": spinners.size() - 1,
					"hot": s.randf() < params["hot_fraction"], "node": null, "dead_at": -1.0})

func _era_positions(era: int) -> PackedVector2Array:
	var key := posmod(era, 3)
	if not pattern_cache.has(key):
		pattern_cache[key] = Patterns.positions(key, int(params["peg_count"]))
	return pattern_cache[key]

func _field_pos(i: int) -> Vector2:
	# Pure function of pattern_phase: rest at the era's pattern for the first
	# morph_dwell of each unit interval, then smoothstep-glide to the next.
	var phase: float = params["pattern_phase"]
	var era := int(floor(phase))
	var f := phase - float(era)
	var dwell: float = params["morph_dwell"]
	var a := _era_positions(era)
	if f <= dwell:
		return a[i]
	var t := smoothstep(0.0, 1.0, (f - dwell) / (1.0 - dwell))
	return a[i].lerp(_era_positions(era + 1)[i], t)

func _spawn_peg(d: Dictionary) -> void:
	var peg := Peg.new(params["peg_radius"], pal, "hot" if d["hot"] else "peg", phys_mat)
	peg.position = _field_pos(d["pattern_i"]) if d["parent_idx"] < 0 else d["pos"]
	peg.add_to_group("pegs")
	peg.lit = 1.0  # spawn flash
	if d["parent_idx"] >= 0:
		spinners[d["parent_idx"]]["node"].add_child(peg)
	else:
		add_child(peg)
	d["node"] = peg
	d["dead_at"] = -1.0

func _make_pop(speed: float, amount: int) -> GPUParticles2D:
	var g := GPUParticles2D.new()
	g.amount = amount
	g.one_shot = true
	g.explosiveness = 1.0
	g.emitting = false
	g.lifetime = 0.7
	if "use_fixed_seed" in g:
		g.use_fixed_seed = true
		g.seed = s.randi()
	var cmat := CanvasItemMaterial.new()
	cmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = cmat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, 600, 0)
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.scale_min = 2.0
	pm.scale_max = 5.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 0.8) * 2.0)
	grad.set_color(1, Color(1, 0.4, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	g.process_material = pm
	add_child(g)
	return g

func _fire_fx(pool: Array[GPUParticles2D], idx_ref: String, pos: Vector2) -> void:
	var i: int = fx_i if idx_ref == "fx" else boom_i
	var g := pool[i % pool.size()]
	g.position = pos
	g.restart()
	if idx_ref == "fx":
		fx_i += 1
	else:
		boom_i += 1

func _fire_volley() -> void:
	# One fire moment: every emitter launches a fan of volley_count balls.
	var cx: float = lerpf(160.0, 1760.0, params["drop_x"])
	var offsets: Array = [0.0]
	if int(params["emitter_count"]) == 2:
		offsets = [-175.0, 175.0]
	elif int(params["emitter_count"]) >= 3:
		offsets = [-350.0, 0.0, 350.0]
	var vol := int(params["volley_count"])
	var spread: float = params["volley_spread"]
	var spawned := false
	for off in offsets:
		var pos := Vector2(clampf(cx + float(off), 120.0, 1800.0), 60.0)
		var sweep: float = PI / 2.0 + sin(sim_t * params["sweep_speed"] * TAU * 0.25) * params["sweep_range"]
		var aim := (Vector2(960, 620) - pos).angle()
		var base := lerp_angle(sweep, aim, params["aim_bias"])
		for v in vol:
			if balls.size() >= int(params["max_balls"]):
				break
			var frac := 0.0 if vol == 1 else (float(v) / float(vol - 1)) * 2.0 - 1.0
			var ball := Ball.new(params["ball_radius"], pal, phys_mat)
			ball.position = pos
			ball.linear_velocity = Vector2.from_angle(base + frac * spread) * params["ball_speed"]
			ball.body_entered.connect(_on_ball_contact.bind(ball))
			add_child(ball)
			balls.append(ball)
			spawned = true
	if spawned:
		emit_event("spawn")

func _on_ball_contact(other: Node, ball: Ball) -> void:
	if not is_instance_valid(ball) or not other.is_in_group("pegs"):
		return
	var peg := other as Peg
	if peg.lit > 0.6:
		return  # debounce rapid re-hits
	peg.lit = 1.0
	var gpos := peg.global_position
	_fire_fx(fx_pool, "fx", gpos)
	emit_event("hit")
	recent_hits.append({"pos": gpos, "time": sim_t})
	_check_chain(gpos)

func _check_chain(at: Vector2) -> void:
	var cluster: Array = []
	for h in recent_hits:
		if sim_t - h["time"] < 1.0 and h["pos"].distance_to(at) < params["chain_radius"]:
			cluster.append(h)
	if cluster.size() < int(params["chain_trigger"]):
		return
	recent_hits.clear()
	_fire_fx(boom_pool, "boom", at)
	emit_event("chain")
	for d in peg_defs:
		if d["node"] != null and is_instance_valid(d["node"]):
			if (d["node"].global_position as Vector2).distance_to(at) < params["chain_radius"]:
				_fire_fx(fx_pool, "fx", d["node"].global_position)
				d["node"].queue_free()
				d["node"] = null
				d["dead_at"] = sim_t
	for b in balls:
		if is_instance_valid(b):
			var dvec: Vector2 = b.global_position - at
			var dist := maxf(dvec.length(), 40.0)
			if dist < params["chain_radius"] * 2.0:
				b.apply_central_impulse(dvec / dist * params["blast_impulse"])
	on_chain_blast(at)

func on_chain_blast(_at: Vector2) -> void:
	pass  # hook for hybrids

func _apply_hue(drift: float) -> void:
	# Rotate the working palette's hues in place (turns of the wheel); pegs
	# and balls hold `pal` by reference so they just need a redraw.
	if absf(drift - last_hue) <= 0.0005:
		return
	last_hue = drift
	for key in base_pal:
		var c: Color = base_pal[key]
		pal[key] = Color.from_hsv(fposmod(c.h + drift, 1.0), c.s, c.v, c.a)
	for d in peg_defs:
		if d["node"] != null and is_instance_valid(d["node"]):
			d["node"].queue_redraw()
	for b in balls:
		if is_instance_valid(b):
			b.queue_redraw()

func _process(delta: float) -> void:
	super._process(delta)
	if s == null:
		return
	sim_t += delta
	for sp in spinners:
		sp["node"].rotation += sp["speed"] * delta
	for d in peg_defs:
		if d["parent_idx"] < 0 and d["node"] != null and is_instance_valid(d["node"]):
			d["node"].position = _field_pos(d["pattern_i"])
	fire_acc += delta
	balls = balls.filter(func(b): return is_instance_valid(b))
	if fire_acc >= params["fire_interval"]:
		fire_acc = 0.0
		_fire_volley()
	for b in balls:
		if b.position.y > 1240 or b.position.x < -120 or b.position.x > 2040:
			b.queue_free()
	respawn_acc += delta
	if respawn_acc >= params["respawn_period"]:
		respawn_acc = 0.0
		for d in peg_defs:
			if d["node"] == null:
				_spawn_peg(d)
	recent_hits = recent_hits.filter(func(h): return sim_t - h["time"] < 1.5)

func apply_live(p: Dictionary) -> void:
	if env != null:
		env.glow_intensity = p["glow"]
	if phys_mat != null:
		phys_mat.bounce = p["bounce"]
	if not base_pal.is_empty():
		_apply_hue(p["hue_drift"])
```

- [ ] **Step 2: Run the test suite under peg_cascade — still green**

Run: `cd /home/tmoney/code/vibes/vxstory && godot --headless --path peg_cascade --script res://core/tests/run_tests.gd 2>&1 | tail -3`
Expected: `TESTS: 67 run, 0 failed`

- [ ] **Step 3: Headless smoke — default preset (no modulators)**

Run: `cd /home/tmoney/code/vibes/vxstory && timeout 15 godot --headless --path peg_cascade -- --preset presets/default.json 2>&1 | grep -iE "error|script|warn" | head -20; true`
Expected: NO `SCRIPT ERROR` lines and no peg_cascade-related errors (timeout killing the process after 15 s is the normal exit; benign Vulkan/audio driver warnings from headless mode are acceptable).

- [ ] **Step 4: Headless smoke — clockwork preset (modulators active; still the OLD clockwork.json — it has no `layout` override, so it must load and run)**

Run: `cd /home/tmoney/code/vibes/vxstory && timeout 15 godot --headless --path peg_cascade -- --preset presets/clockwork.json 2>&1 | grep -iE "error|script|warn" | head -20; true`
Expected: NO `SCRIPT ERROR` lines. (`pachinko_riot`/`zen_garden` still carry a `layout` override and would warn until Task 3 — do not smoke those here.)

- [ ] **Step 5: Commit**

```bash
git add peg_cascade/main.gd
git commit -m "peg_cascade: morphing pattern playfield, parameterized drops, hue drift

pattern_phase/morph_dwell drive per-frame peg positions from patterns.gd
(rest-then-glide, scrub-exact); drops get drop_x/emitter_count/volley_count/
volley_spread/aim_bias; hue_drift rotates the shared palette. layout enum,
grid/scatter generators and scatter top-up removed; spinner pegs are now an
overlay on top of peg_count.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Presets + README

**Files:**
- Modify: `peg_cascade/presets/clockwork.json` (full replacement)
- Modify: `peg_cascade/presets/pachinko_riot.json` (drop `layout` override)
- Modify: `peg_cascade/presets/zen_garden.json` (swap `layout` for `pattern_phase`)
- Modify: `peg_cascade/README.md` (full replacement)
- (`peg_cascade/presets/default.json` has no `layout` override — leave it untouched.)

**Interfaces:**
- Consumes: the Task 2 schema param names exactly: `pattern_phase`, `morph_dwell`, `drop_x`, `emitter_count`, `volley_count`, `volley_spread`, `aim_bias`, `hue_drift`.

- [ ] **Step 1: Replace `peg_cascade/presets/clockwork.json`**

```json
{
  "model": "peg_cascade",
  "seed": 1337,
  "duration_sec": 300.0,
  "macros": {"complexity": 0.45, "ball_rate": 0.3, "bounciness": 0.5, "fx": 0.3},
  "overrides": {"aim_bias": 0.35, "volley_spread": 0.5},
  "jitter": {},
  "modulators": {
    "tween": [
      {"name": "era_walk", "secs": 290.0, "curve": "linear", "from": 0.0, "to": 1.0,
       "targets": [{"to": "pattern_phase", "amount": 3.0}]},
      {"name": "build", "secs": 275.0, "curve": "ease_in", "from": 0.0, "to": 1.0,
       "targets": [{"to": "ball_rate", "amount": 0.45}, {"to": "fx", "amount": 0.5}, {"to": "volley_count", "amount": 3.0}]},
      {"name": "color_voyage", "secs": 300.0, "curve": "linear", "from": 0.0, "to": 1.0,
       "targets": [{"to": "hue_drift", "amount": 0.35}]}
    ],
    "lfo": [
      {"name": "drop_drift", "oscillators": [
        {"shape": "sine", "period_sec": 37.5, "phase_deg": 0.0, "amount": 1.0}],
       "targets": [{"to": "drop_x", "amount": 0.45}]}
    ],
    "envelope": [
      {"name": "burst_fx", "event": "chain", "attack": 0.03, "decay": 0.5, "peak": 1.0,
       "targets": [{"to": "fx", "amount": 0.3}]}
    ]
  }
}
```

(Arc: `pattern_phase` 0→3 over 290 s walks hex → rings → spokes → hex with ~67 s rests and ~29 s glides at the default `morph_dwell` 0.7; drops slowly sweep the top via the `drop_x` LFO while `aim_bias` keeps them purposeful; volleys and fx build ease-in across the piece; hue drifts a third of the wheel.)

- [ ] **Step 2: Patch `peg_cascade/presets/pachinko_riot.json`**

Replace the whole file with (only the `overrides` line changes — `layout` dropped):

```json
{
  "model": "peg_cascade",
  "seed": 32,
  "duration_sec": 30.0,
  "macros": {"complexity": 0.9, "ball_rate": 0.95, "bounciness": 0.9, "fx": 0.95},
  "overrides": {"palette": "neon"},
  "jitter": {"spinner_speed": {"pct": 30.0}}
}
```

- [ ] **Step 3: Patch `peg_cascade/presets/zen_garden.json`**

Replace the whole file with (`layout: rings` becomes `pattern_phase: 1.0` — the rings era):

```json
{
  "model": "peg_cascade",
  "seed": 31,
  "duration_sec": 30.0,
  "macros": {"complexity": 0.3, "ball_rate": 0.25, "bounciness": 0.5, "fx": 0.4},
  "overrides": {"palette": "mono", "pattern_phase": 1.0},
  "jitter": {}
}
```

- [ ] **Step 4: Smoke every preset loads warning-free**

Run:
```bash
cd /home/tmoney/code/vibes/vxstory
for p in default clockwork pachinko_riot zen_garden; do
  echo "== $p =="
  timeout 12 godot --headless --path peg_cascade -- --preset "presets/$p.json" 2>&1 | grep -iE "error|warn|unknown" | head -5
done; true
```
Expected: no `SCRIPT ERROR`, no `unknown param` / preset warnings for any of the four (headless driver noise acceptable).

- [ ] **Step 5: Replace `peg_cascade/README.md`**

```markdown
# peg_cascade

A Peggle-style physics piece on a living board: balls rain from parameterized emitters at the top, carom off a field of glowing pegs, and trigger chain detonations that blast pegs off the board and kick every ball in range. The peg field itself is choreography — it morphs between legible patterns (hex lattice → concentric rings → radial spokes), resting in each era then gliding every peg to its partner position in the next. Destroyed pegs respawn on a slow cycle, spinner hubs rotate through every era, and the whole palette can drift around the hue wheel across a piece.

## Superparameters

The 0..1 macro dials — each shifts many low-level params at once.

- **complexity** — 0 gives a sparse field (40 pegs, no spinners); 1 packs the board (200 pegs, 4 rotating arm clusters). Drives visual density and collision frequency.
- **ball_rate** — 0 fires roughly every 1.2 seconds; 1 fires at near-continuous pace (~0.12 s interval). Controls how busy the sim feels.
- **bounciness** — 0 gives deadened, low-restitution collisions (bounce ≈ 0.45); 1 makes the physics elastic and ricochety (bounce ≈ 0.98).
- **fx** — scales the chain-blast radius (100 → 320 px) and the impulse kick applied to nearby balls (100 → 1200). Low = small local pops; high = screen-wide demolitions.

## Parameters

Low-level knobs (pin exact values via a preset's `overrides`). Parameters marked *(restart)* take effect only on scene restart — they cannot be hot-patched mid-run.

### Playfield

- **peg_count** (`int`, 20–240, default `110`) *(restart)* — number of FIELD pegs (pattern-owned). Spinner pegs are extra, on top of this.
- **peg_radius** (`float`, 8.0–26.0, default `14.0`) *(restart)* — collision + draw radius of each peg.
- **pattern_phase** (`float`, 0.0–3.0, default `0.0`) — the morph driver. Integer part picks the era (0 hex lattice, 1 concentric rings, 2 radial spokes; 3 wraps to hex), fractional part is progress through that era's interval. Tween it 0→3 to walk the whole sequence; LFO it to rock between patterns.
- **morph_dwell** (`float`, 0.0–0.9, default `0.7`) — fraction of each era interval spent AT REST in the pure pattern; the remainder is the smoothstepped glide to the next pattern. 0 = perpetual slow drift, 0.9 = long rests with quick snaps.
- **spinner_count** (`int`, 0–4, default `2`) *(restart)* — rotating peg-arm hubs (12 pegs each, alternating CW/CCW), overlaid on the pattern field.
- **spinner_speed** (`float`, 0.2–3.0, default `1.0`) *(restart)* — hub angular speed in rad/s; 25% seeded jitter per hub.
- **hot_fraction** (`float`, 0.0–1.0, default `0.25`) *(restart)* — proportion of pegs using the palette's accent colour.

### Drops

- **fire_interval** (`float`, 0.1–2.0, default `0.45`) — seconds between fire moments.
- **drop_x** (`float`, 0.0–1.0, default `0.5`) — emitter-group center across the top edge (maps to x 160–1760). LFO it to sweep the rain across the board.
- **emitter_count** (`int`, 1–3, default `1`) — simultaneous emitters, spaced 350 px around `drop_x`.
- **volley_count** (`int`, 1–7, default `1`) — balls per fire moment per emitter, fanned evenly.
- **volley_spread** (`float`, 0.0–0.8, default `0.35`) — fan half-angle in radians (matters when volley_count > 1).
- **aim_bias** (`float`, 0.0–1.0, default `0.0`) — blends launch direction from "down + sweep oscillation" (0) toward "aimed at board center" (1).
- **sweep_range** (`float`, 0.0–1.2, default `0.7`) — half-width of the launch-angle oscillation in radians.
- **sweep_speed** (`float`, 0.1–3.0, default `0.8`) — oscillation rate of the launch angle.
- **ball_speed** (`float`, 400.0–1600.0, default `900.0`) — launch speed in px/s.
- **ball_radius** (`float`, 6.0–18.0, default `11.0`) *(restart)* — ball radius.
- **max_balls** (`int`, 4–80, default `28`) — cap on simultaneously active balls; fire moments stop spawning at the cap.

### Physics & chains

- **bounce** (`float`, 0.3–1.0, default `0.8`) — restitution on every peg/ball collision.
- **chain_trigger** (`int`, 2–8, default `4`) — recent hits (last second, within `chain_radius`) required to detonate.
- **chain_radius** (`float`, 60.0–400.0, default `180.0`) — chain detection + blast radius.
- **blast_impulse** (`float`, 0.0–1500.0, default `600.0`) — radial kick applied to balls caught in a blast.
- **respawn_period** (`float`, 2.0–20.0, default `8.0`) — seconds between respawn sweeps for destroyed pegs (they reappear at their CURRENT pattern position).

### Look

- **hue_drift** (`float`, 0.0–1.0, default `0.0`) — rotates the whole palette around the hue wheel (in turns). Tween it slowly for a colour arc across the piece.
- **glow** (`float`, 0.0–3.0, default `1.3`) — additive glow intensity.
- **palette** (`enum`, default `"classic"`) *(restart)* — base colour scheme: `classic` (blue/orange/white), `neon` (pink/cyan/chartreuse), `mono` (greys — note hue_drift has no visible effect on pure greys).

## Events

Discrete moments emitted for envelope modulation:

- `spawn` — fires once per fire moment (a volley of several balls emits ONE spawn event).
- `hit` — fires each time a ball contacts a peg (debounced: suppressed if the peg was struck within the last ~0.5 s).
- `chain` — fires when a cluster of recent hits crosses the `chain_trigger` threshold, triggering a chain detonation.

## Presets

- `default` — balanced mid-range settings; static hex-era board, classic palette.
- `clockwork` — the 300 s long-form flagship: pattern_phase walks hex → rings → spokes → hex with resting eras and glide transitions, drops sweep the top on a slow LFO with center-aim bias, volleys and fx build across the piece, and the palette drifts a third of the hue wheel.
- `pachinko_riot` — high ball rate, low chain threshold, big blasts — near-continuous demolition, neon.
- `zen_garden` — pinned to the rings era, sparse pegs, mono palette; hypnotic and low-chaos.
```

- [ ] **Step 6: Re-run the preset smoke from Step 4**

Same command as Step 4.
Expected: all four presets still load warning-free.

- [ ] **Step 7: Commit**

```bash
git add peg_cascade/presets/clockwork.json peg_cascade/presets/pachinko_riot.json peg_cascade/presets/zen_garden.json peg_cascade/README.md
git commit -m "peg_cascade: retune clockwork for the pattern-era engine; patch presets + README

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Post-plan verification (controller, not a task)

Designer + preview smoke on a display, then `scripts/render.sh peg_cascade clockwork 60` for the 60 s proof; user reviews the render.
