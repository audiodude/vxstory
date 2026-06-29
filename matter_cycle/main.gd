extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")

# Use direct linear color constants (not sRGB hex) — Godot renders in linear space
const PALETTES := {
	"spectrum": null,  # hue wheel per poly
	"ember": [Color(1.0, 0.4, 0.13), Color(1.0, 0.67, 0.2), Color(1.0, 0.2, 0.0)],
	"mono": [Color(0.8, 0.8, 0.8), Color(0.53, 0.53, 0.53), Color(1.0, 1.0, 1.0)],
}

class Poly extends RigidBody2D:
	var verts := PackedVector2Array()
	var hue := 0.0
	var col := Color.WHITE
	var age := 0.0
	func _init(p_verts: PackedVector2Array, p_col: Color, bounce: float) -> void:
		verts = p_verts
		col = p_col
		contact_monitor = true
		max_contacts_reported = 4
		var pm := PhysicsMaterial.new()
		pm.bounce = bounce
		pm.friction = 0.6
		physics_material_override = pm
		var shape := CollisionPolygon2D.new()
		shape.polygon = verts
		add_child(shape)
	func _draw() -> void:
		var pts := verts.duplicate()
		pts.append(verts[0])
		draw_polyline(pts, col * 1.4, 2.0, true)
	func _process(delta: float) -> void:
		age += delta

var bodies: Array = []
var swarm_mm: MultiMesh
var swarm_node: MultiMeshInstance2D
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var col := PackedColorArray()
var age := PackedFloat32Array()
var alive := 0
var _prev_alive := 0
var flow := PackedVector2Array()  # (FLOW_W+1)x(FLOW_H+1) grid
var rings: Array = []
var rings_node: Node2D
var burst_pool: Array[GPUParticles2D] = []
var burst_i := 0
var spawn_acc := 0.0
var condense_cd := 0.0
var sim_t := 0.0
var s: RandomNumberGenerator
var env: Environment

const FLOW_W := 48
const FLOW_H := 27
const CELL := 40.0  # 1920/48

func model_name() -> String:
	return "matter_cycle"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("matter", 0.5), PS.macro_def("fragility", 0.5),
			PS.macro_def("turbulence", 0.5), PS.macro_def("cycle_speed", 0.5),
		],
		"params": [
			PS.f("spawn_interval", 1.0, 0.3, 3.0, {"macro": {"name": "matter", "lo": 2.2, "hi": 0.45}}),
			PS.i("max_bodies", 22, 4, 60, {"macro": {"name": "matter", "lo": 8, "hi": 44}}),
			PS.f("poly_size", 80.0, 30.0, 160.0, {"jitter": {"pct": 10.0}}),
			PS.f("bounce", 0.3, 0.0, 0.9, {"live": false}),
			PS.f("shatter_speed", 520.0, 150.0, 1200.0, {"macro": {"name": "fragility", "lo": 950.0, "hi": 260.0}}),
			PS.f("min_poly_age", 0.5, 0.0, 2.0),
			PS.f("frag_per_100px2", 2.5, 0.5, 8.0),
			PS.i("swarm_cap", 6000, 1000, 12000, {"live": false}),
			PS.f("flow_strength", 220.0, 0.0, 600.0, {"macro": {"name": "turbulence", "lo": 40.0, "hi": 480.0}}),
			PS.f("flow_scale", 1.6, 0.5, 4.0),
			PS.f("updraft", -120.0, -300.0, 300.0),
			PS.f("particle_drag", 0.6, 0.0, 3.0),
			PS.i("condense_count", 150, 40, 400, {"macro": {"name": "cycle_speed", "lo": 280, "hi": 70}}),
			PS.f("condense_radius", 140.0, 60.0, 300.0),
			PS.f("condense_cooldown", 1.0, 0.2, 4.0),
			PS.f("particle_max_age", 14.0, 3.0, 30.0),
			PS.f("glow", 1.1, 0.0, 3.0),
			PS.e("palette", "spectrum", PackedStringArray(["spectrum", "ember", "mono"]), {"live": false}),
		],
	}

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):
			c.queue_free()
	bodies.clear()
	rings.clear()
	burst_pool.clear()
	alive = 0
	_prev_alive = 0
	burst_i = 0
	spawn_acc = 0.0
	condense_cd = 0.0
	sim_t = 0.0
	s = rng.stream("sim")
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = params["glow"]
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)
	# floor + walls
	var floor_body := StaticBody2D.new()
	var fshape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2400, 60)
	fshape.shape = rect
	fshape.position = Vector2(960, 1110)
	floor_body.add_child(fshape)
	for wx in [-30.0, 1950.0]:
		var wshape := CollisionShape2D.new()
		var wrect := RectangleShape2D.new()
		wrect.size = Vector2(60, 2400)
		wshape.shape = wrect
		wshape.position = Vector2(wx, 540)
		floor_body.add_child(wshape)
	add_child(floor_body)
	# swarm — set format/colors BEFORE instance_count (Godot requirement)
	var cap: int = params["swarm_cap"]
	pos.resize(cap)
	vel.resize(cap)
	col.resize(cap)
	age.resize(cap)
	swarm_mm = MultiMesh.new()
	swarm_mm.transform_format = MultiMesh.TRANSFORM_2D
	swarm_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(5, 5)
	swarm_mm.mesh = quad
	swarm_mm.instance_count = cap
	for i in cap:
		swarm_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(-9999, -9999)))
	swarm_node = MultiMeshInstance2D.new()
	swarm_node.multimesh = swarm_mm
	var cmat := CanvasItemMaterial.new()
	cmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	swarm_node.material = cmat
	add_child(swarm_node)
	flow.resize((FLOW_W + 1) * (FLOW_H + 1))
	rings_node = Node2D.new()
	rings_node.draw.connect(_draw_rings)
	add_child(rings_node)
	for i in 8:
		burst_pool.append(_make_burst())

func _make_burst() -> GPUParticles2D:
	var g := GPUParticles2D.new()
	g.amount = 40
	g.one_shot = true
	g.explosiveness = 1.0
	g.emitting = false
	g.lifetime = 0.6
	if "use_fixed_seed" in g:
		g.use_fixed_seed = true
		g.seed = s.randi()
	var cmat := CanvasItemMaterial.new()
	cmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = cmat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 200.0
	pm.initial_velocity_max = 600.0
	pm.scale_min = 2.0
	pm.scale_max = 4.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1) * 2.0)
	grad.set_color(1, Color(0.6, 0.8, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	g.process_material = pm
	add_child(g)
	return g

func _poly_color() -> Color:
	if params["palette"] == "spectrum":
		return Color.from_hsv(s.randf(), 0.8, 1.0)
	var cols: Array = PALETTES[params["palette"]]
	return cols[s.randi() % cols.size()]

func _spawn_poly(at: Vector2, radius: float, kick: Vector2) -> void:
	var n := 5 + s.randi() % 5
	var verts := PackedVector2Array()
	for i in n:
		var ang := TAU * i / n + s.randf_range(-0.25, 0.25)
		verts.append(Vector2.from_angle(ang) * radius * s.randf_range(0.7, 1.15))
	var poly := Poly.new(verts, _poly_color(), params["bounce"])
	poly.position = at
	poly.linear_velocity = kick
	poly.angular_velocity = s.randf_range(-2.0, 2.0)
	poly.body_entered.connect(_on_poly_contact.bind(poly))
	add_child(poly)
	bodies.append(poly)
	emit_event("spawn")

func _on_poly_contact(other: Node, poly: Poly) -> void:
	if not is_instance_valid(poly) or poly.age < params["min_poly_age"]:
		return
	var ov := Vector2.ZERO
	if other is RigidBody2D:
		ov = other.linear_velocity
	if (poly.linear_velocity - ov).length() > params["shatter_speed"]:
		call_deferred("_shatter", poly)

func _shatter(poly: Poly) -> void:
	if not is_instance_valid(poly):
		return
	var radius := 0.0
	for v in poly.verts:
		radius = maxf(radius, v.length())
	var area := PI * radius * radius * 0.7
	var n := clampi(int(area / 100.0 * params["frag_per_100px2"]), 30, 600)
	var origin: Vector2 = poly.position
	var pvel: Vector2 = poly.linear_velocity
	for i in n:
		if alive >= int(params["swarm_cap"]):
			break
		var dir := Vector2.from_angle(s.randf_range(0.0, TAU))
		pos[alive] = origin + dir * s.randf_range(0.0, radius * 0.8)
		vel[alive] = pvel * 0.4 + dir * s.randf_range(60.0, 420.0)
		col[alive] = poly.col
		age[alive] = 0.0
		alive += 1
	_fire_burst(origin)
	emit_event("shatter")
	bodies.erase(poly)
	poly.queue_free()

func _fire_burst(at: Vector2) -> void:
	var g := burst_pool[burst_i % burst_pool.size()]
	g.position = at
	g.restart()
	burst_i += 1

func _hash01(xi: int, yi: int) -> float:
	var h: int = (xi * 374761393 + yi * 668265263 + rng.master_seed * 974711) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float(h ^ (h >> 16)) / 2147483647.0

func _vnoise(p: Vector2) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var fx := p.x - ix
	var fy := p.y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	return lerpf(
		lerpf(_hash01(ix, iy), _hash01(ix + 1, iy), ux),
		lerpf(_hash01(ix, iy + 1), _hash01(ix + 1, iy + 1), ux), uy)

func _rebuild_flow() -> void:
	var sc: float = params["flow_scale"] * 0.005
	var drift := sim_t * 0.07
	for gy in FLOW_H + 1:
		for gx in FLOW_W + 1:
			var p := Vector2(gx * CELL, gy * CELL) * sc + Vector2(drift, -drift * 0.6)
			var e := 0.35
			var dy := _vnoise(p + Vector2(0, e)) - _vnoise(p - Vector2(0, e))
			var dx := _vnoise(p + Vector2(e, 0)) - _vnoise(p - Vector2(e, 0))
			flow[gy * (FLOW_W + 1) + gx] = Vector2(dy, -dx) / (2.0 * e)

func _flow_at(p: Vector2) -> Vector2:
	var gx := clampi(int(p.x / CELL), 0, FLOW_W - 1)
	var gy := clampi(int(p.y / CELL), 0, FLOW_H - 1)
	return flow[gy * (FLOW_W + 1) + gx]

func _draw_rings() -> void:
	for r in rings:
		rings_node.draw_arc(r["pos"], r["r"], 0, TAU, 96, Color(1, 1, 1, r["alpha"]) * 1.5, 4.0, true)

func _process(delta: float) -> void:
	super._process(delta)
	if s == null:
		return
	sim_t += delta
	condense_cd = maxf(condense_cd - delta, 0.0)
	# rain polygons
	spawn_acc += delta
	bodies = bodies.filter(func(b): return is_instance_valid(b))
	if spawn_acc >= params["spawn_interval"] and bodies.size() < int(params["max_bodies"]):
		spawn_acc = 0.0
		_spawn_poly(Vector2(s.randf_range(200, 1720), -100), params["poly_size"] * s.randf_range(0.6, 1.4), Vector2(s.randf_range(-80, 80), s.randf_range(0, 120)))
	# swarm physics
	_rebuild_flow()
	var drag: float = params["particle_drag"]
	var density := {}
	var i := 0
	while i < alive:
		vel[i] += (_flow_at(pos[i]) * params["flow_strength"] + Vector2(0, params["updraft"])) * delta
		vel[i] *= maxf(1.0 - drag * delta, 0.0)
		pos[i] += vel[i] * delta
		age[i] += delta
		var dead: bool = age[i] > params["particle_max_age"] or pos[i].y < -200 or pos[i].x < -200 or pos[i].x > 2120 or pos[i].y > 1300
		if dead:
			alive -= 1
			pos[i] = pos[alive]
			vel[i] = vel[alive]
			col[i] = col[alive]
			age[i] = age[alive]
			continue
		var key := Vector2i(int(pos[i].x / 120.0), int(pos[i].y / 120.0))
		density[key] = density.get(key, 0) + 1
		i += 1
	# render swarm — slots above the high-water mark are already parked offscreen
	for k in maxi(alive, _prev_alive):
		if k < alive:
			swarm_mm.set_instance_transform_2d(k, Transform2D(0.0, pos[k]))
			swarm_mm.set_instance_color(k, col[k] * 1.5)
		else:
			swarm_mm.set_instance_transform_2d(k, Transform2D(0.0, Vector2(-9999, -9999)))
	_prev_alive = alive
	# condensation
	if condense_cd <= 0.0:
		for key in density:
			if density[key] >= int(params["condense_count"]):
				var center := Vector2(key.x * 120.0 + 60.0, key.y * 120.0 + 60.0)
				_condense(center)
				condense_cd = params["condense_cooldown"]
				break
	# rings decay
	for r in rings:
		r["r"] += 500.0 * delta
		r["alpha"] = maxf(r["alpha"] - delta * 1.5, 0.0)
	rings = rings.filter(func(r): return r["alpha"] > 0.0)
	rings_node.queue_redraw()

func _condense(center: Vector2) -> void:
	var avg_col := Color(0, 0, 0)
	var taken := 0
	var i := 0
	while i < alive:
		if pos[i].distance_to(center) < params["condense_radius"]:
			avg_col += col[i]
			taken += 1
			alive -= 1
			pos[i] = pos[alive]
			vel[i] = vel[alive]
			col[i] = col[alive]
			age[i] = age[alive]
			continue
		i += 1
	if taken == 0:
		return
	avg_col = (avg_col / taken).clamp(Color(0.2, 0.2, 0.2), Color(1, 1, 1))
	rings.append({"pos": center, "r": 20.0, "alpha": 1.0})
	_fire_burst(center)
	emit_event("condense")
	var radius := clampf(sqrt(float(taken)) * 8.0, 30.0, 160.0)
	_spawn_poly(center, radius, Vector2(s.randf_range(-60, 60), -220))

func apply_live(p: Dictionary) -> void:
	if env != null:
		env.glow_intensity = p["glow"]
