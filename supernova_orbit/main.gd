extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")
const FluidSim = preload("res://fluid_sim/fluid_sim.gd")
const CORE_SHADER := preload("res://core.gdshader")
const CENTER := Vector2(960, 540)

const PALETTES := {
	"solar": {"core": Color(1.0, 0.85, 0.5), "streams": [Color(1.0, 0.8, 0.4), Color(1.0, 0.53, 0.2), Color(1.0, 1.0, 0.67)], "debris": Color(0.67, 0.47, 0.33)},
	"void": {"core": Color(0.7, 0.5, 1.0), "streams": [Color(0.6, 0.4, 1.0), Color(1.0, 0.4, 0.8), Color(0.4, 0.8, 1.0)], "debris": Color(0.4, 0.33, 0.53)},
	"emerald": {"core": Color(0.5, 1.0, 0.7), "streams": [Color(0.4, 1.0, 0.67), Color(0.67, 1.0, 0.4), Color(0.2, 0.8, 0.67)], "debris": Color(0.33, 0.53, 0.4)},
}

class Debris extends RigidBody2D:
	var verts := PackedVector2Array()
	var col := Color.WHITE
	func _init(radius: float, c: Color, vrng: RandomNumberGenerator) -> void:
		col = c
		gravity_scale = 0.0
		var n := 5 + vrng.randi() % 3
		for i in n:
			verts.append(Vector2.from_angle(TAU * i / n) * radius * vrng.randf_range(0.7, 1.2))
		var shape := CollisionPolygon2D.new()
		shape.polygon = verts
		add_child(shape)
	func _draw() -> void:
		var pts := verts.duplicate()
		pts.append(verts[0])
		draw_polyline(pts, col * 1.3, 2.0, true)

var fluid: Node2D
var fluid_display: TextureRect
var sim_vp: SubViewport
var fade_rect: ColorRect
var swarm_mm: MultiMesh
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var col := PackedColorArray()
var alive := 0
var _prev_alive := 0
var debris: Array = []
var cores: Array = []  # {pos: Vector2, vel: Vector2, mass: float, rect: ColorRect, mat: ShaderMaterial, ph: Vector2}
var flash_rect: ColorRect
var flash_a := 0.0
var rings: Array = []
var rings_node: Node2D
var spawn_acc := 0.0
var sim_t := 0.0
var det_cooldown := 0.0  # seconds until next detonation is allowed
var _wipe_t := 0.0      # soft wipe countdown (replaces _trail_clear_frames)
var pal: Dictionary
var s: RandomNumberGenerator
var env: Environment

func model_name() -> String:
	return "supernova_orbit"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("accretion", 0.5), PS.macro_def("critical_mass", 0.35),
			PS.macro_def("detonation", 0.7), PS.macro_def("chaos", 0.4),
			PS.macro_def("duality", 0.4),
		],
		"params": [
			PS.i("stream_count", 3, 1, 8, {"live": false}),
			PS.f("spawn_rate", 120.0, 10.0, 400.0, {"macro": {"name": "accretion", "lo": 30.0, "hi": 300.0}}),
			PS.i("max_particles", 16000, 2000, 24000, {"live": false}),
			PS.f("g_strength", 60000000.0, 10000000.0, 250000000.0),
			PS.f("core_radius", 100.0, 20.0, 150.0),
			PS.i("critical", 1500, 100, 6000, {"macro": {"name": "critical_mass", "lo": 300, "hi": 1730}}),
			PS.f("orbit_factor", 0.6, 0.5, 1.3),
			PS.f("chaos_spread", 0.35, 0.0, 1.0, {"macro": {"name": "chaos", "lo": 0.05, "hi": 0.8}}),
			PS.f("detonation_speed", 1200.0, 200.0, 3000.0, {"macro": {"name": "detonation", "lo": 400.0, "hi": 2500.0}}),
			PS.i("debris_count", 18, 0, 60),
			PS.f("debris_radius", 16.0, 6.0, 40.0, {"jitter": {"pct": 20.0}}),
			PS.f("trail_persist", 0.025, 0.02, 0.5),
			PS.f("fluid_reactivity", 0.5, 0.0, 1.0),
			PS.f("glow", 0.3, 0.0, 3.0),
			PS.e("palette", "solar", PackedStringArray(["solar", "void", "emerald"]), {"live": false}),
			PS.f("split_chance", 0.35, 0.0, 0.85, {"macro": {"name": "duality", "lo": 0.0, "hi": 0.85}}),
			PS.f("core_drift", 120.0, 0.0, 260.0, {"macro": {"name": "duality", "lo": 40.0, "hi": 240.0}}),
			PS.f("split_kick", 260.0, 80.0, 500.0, {"macro": {"name": "duality", "lo": 150.0, "hi": 420.0}}),
			PS.f("merge_radius", 130.0, 60.0, 300.0),
			PS.f("core_gravity", 900000.0, 0.0, 3000000.0),
			PS.i("debris_cap", 80, 10, 200),
			PS.f("hue_drift", 0.0, 0.0, 90.0),
			PS.f("pulse_depth", 0.08, 0.0, 0.25),
			PS.f("pulse_rate", 1.0, 0.0, 2.0),
		],
	}

func _hue_rotated(c: Color) -> Color:
	var deg: float = params["hue_drift"] * sim_t / 60.0
	var shift := fposmod(deg, 360.0) / 360.0
	var h := fposmod(c.h + shift, 1.0)
	return Color.from_hsv(h, c.s, c.v, c.a)

func _spawn_core(p: Vector2, v: Vector2, m: float) -> Dictionary:
	var mat := ShaderMaterial.new()
	mat.shader = CORE_SHADER
	mat.set_shader_parameter("base_col", _hue_rotated(pal["core"]))
	var rect := ColorRect.new()
	rect.size = Vector2(700, 700)
	rect.material = mat
	add_child(rect)
	var core := {"pos": p, "vel": v, "mass": m, "rect": rect, "mat": mat,
		"ph": Vector2(s.randf_range(0.0, TAU), s.randf_range(0.0, TAU))}
	cores.append(core)
	return core

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):
			c.queue_free()
	debris.clear()
	rings.clear()
	cores.clear()
	alive = 0
	_prev_alive = 0
	spawn_acc = 0.0
	sim_t = 0.0
	flash_a = 0.0
	det_cooldown = 0.0
	_wipe_t = 0.0
	s = rng.stream("sim")
	pal = PALETTES[params["palette"]]
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = params["glow"]
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)
	# fluid haze (behind everything)
	fluid = FluidSim.new()
	add_child(fluid)
	fluid.setup(rng.stream("vortices"), 480, 270, {"dissipation": 0.97, "noise_strength": 0.5, "flow_speed": 1.0, "noise_scale": 2.0, "vortex_count": 2, "vortex_strength": 0.4})
	fluid_display = TextureRect.new()
	fluid_display.size = Vector2(1920, 1080)
	fluid_display.stretch_mode = TextureRect.STRETCH_SCALE
	fluid_display.modulate = Color(1, 1, 1, 0.55)
	add_child(fluid_display)
	# trail viewport: transparent_bg=false + additive display for robust compositing
	sim_vp = SubViewport.new()
	sim_vp.size = Vector2i(1920, 1080)
	sim_vp.disable_3d = true
	sim_vp.use_hdr_2d = true
	sim_vp.transparent_bg = false
	sim_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sim_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	add_child(sim_vp)
	sim_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	# fade rect is first child — darkens old frames for trail persistence
	fade_rect = ColorRect.new()
	fade_rect.size = Vector2(1920, 1080)
	fade_rect.color = Color(0, 0, 0, params["trail_persist"])
	sim_vp.add_child(fade_rect)
	# MultiMesh swarm — set transform_format/use_colors BEFORE instance_count
	var cap: int = params["max_particles"]
	pos.resize(cap)
	vel.resize(cap)
	col.resize(cap)
	swarm_mm = MultiMesh.new()
	swarm_mm.transform_format = MultiMesh.TRANSFORM_2D
	swarm_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 4)
	swarm_mm.mesh = quad
	swarm_mm.instance_count = cap
	for i in cap:
		swarm_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(-9999, -9999)))
	var swarm_node := MultiMeshInstance2D.new()
	swarm_node.multimesh = swarm_mm
	var cmat := CanvasItemMaterial.new()
	cmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	swarm_node.material = cmat
	sim_vp.add_child(swarm_node)
	# display the viewport additively over the fluid haze
	var vp_show := TextureRect.new()
	vp_show.texture = sim_vp.get_texture()
	vp_show.size = Vector2(1920, 1080)
	var amat := CanvasItemMaterial.new()
	amat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	vp_show.material = amat
	add_child(vp_show)
	# rings node (origin-based; rings draw at their own pos)
	rings_node = Node2D.new()
	rings_node.position = Vector2.ZERO
	rings_node.draw.connect(_draw_rings)
	add_child(rings_node)
	# flash
	flash_rect = ColorRect.new()
	flash_rect.size = Vector2(1920, 1080)
	flash_rect.color = Color(1, 1, 1, 0)
	add_child(flash_rect)
	# spawn initial lone core at CENTER
	_spawn_core(CENTER, Vector2.ZERO, 0.0)

func _spawn_particles(delta: float) -> void:
	spawn_acc += params["spawn_rate"] * delta
	var streams: int = params["stream_count"]
	var cols: Array = pal["streams"]
	while spawn_acc >= 1.0 and alive < int(params["max_particles"]):
		spawn_acc -= 1.0
		var k := s.randi() % streams
		var edge_ang := TAU * k / streams + sin(sim_t * 0.13 + k * 2.1) * 0.5
		var p := CENTER + Vector2.from_angle(edge_ang) * s.randf_range(640.0, 760.0)
		var to_c := (CENTER - p).normalized()
		var tang := Vector2(-to_c.y, to_c.x) * (1.0 if k % 2 == 0 else -1.0)
		var r := p.distance_to(CENTER)
		var orbit_v: float = sqrt(float(params["g_strength"]) / r) * float(params["orbit_factor"])
		var ch: float = params["chaos_spread"]
		vel[alive] = tang * orbit_v * s.randf_range(1.0 - ch, 1.0 + ch) + to_c * orbit_v * s.randf_range(0.0, 0.25)
		pos[alive] = p
		col[alive] = _hue_rotated(cols[k % cols.size()])
		alive += 1

func _fission(c: Dictionary) -> void:
	# Half-strength detonation event + split into two cores
	flash_a = 0.45
	det_cooldown = 5.0
	rings.append({"r": 40.0, "speed": 900.0, "alpha": 1.0, "origin": c["pos"]})
	var det_spd: float = params["detonation_speed"]
	var core_r: float = params["core_radius"]
	var cpos: Vector2 = c["pos"]
	# Fling nearby particles at half strength
	for i in alive:
		var d: Vector2 = pos[i] - cpos
		var dist := maxf(d.length(), 30.0)
		if dist < core_r * 4.0:
			vel[i] = d / dist * det_spd * 0.5 * (0.6 + 0.6 * _frac(i * 0.6180339887)) + vel[i] * 0.2
	# Reset this core's mass to half-charged state
	c["mass"] = 0.35 * float(params["critical"])
	# Tangent direction for kick
	var tangent := Vector2(-s.randf_range(-1.0, 1.0), s.randf_range(-1.0, 1.0)).normalized()
	var kick: float = params["split_kick"]
	var cvel: Vector2 = c["vel"]
	# Spawn second core — start outside merge_radius so they don't immediately re-merge
	var sep: float = maxf(float(params["merge_radius"]) + 40.0, 80.0)
	var new_pos: Vector2 = cpos + tangent * sep
	var new_vel: Vector2 = cvel + tangent * kick
	_spawn_core(new_pos, new_vel, 0.35 * float(params["critical"]))
	# Kick original core in opposite direction
	c["vel"] = cvel - tangent * kick * 0.6
	_wipe_t = 0.6

func _detonate(c: Dictionary) -> void:
	flash_a = 0.9
	det_cooldown = 5.0
	var cpos: Vector2 = c["pos"]
	for ri in 3:
		rings.append({"r": 40.0 + ri * 30.0, "speed": 900.0 + ri * 400.0, "alpha": 1.0, "origin": cpos})
	var det_spd: float = params["detonation_speed"]
	# Blast all accumulated particles outward from this core
	for i in alive:
		var d: Vector2 = pos[i] - cpos
		var dist := maxf(d.length(), 30.0)
		vel[i] = d / dist * det_spd * (0.6 + 0.6 * _frac(i * 0.6180339887)) + vel[i] * 0.2
	# Spawn new debris (do NOT clear existing debris)
	for i in int(params["debris_count"]):
		var ang := s.randf_range(0.0, TAU)
		var outward := Vector2.from_angle(ang)
		var tangent_dir := Vector2(-outward.y, outward.x)
		var rock := Debris.new(params["debris_radius"] * s.randf_range(0.6, 1.4), _hue_rotated(pal["debris"]), s)
		rock.position = cpos + outward * s.randf_range(20.0, 80.0)
		rock.linear_velocity = (outward * 0.55 + tangent_dir * 0.8).normalized() * det_spd * s.randf_range(0.35, 0.7)
		rock.angular_velocity = s.randf_range(-6.0, 6.0)
		add_child(rock)
		debris.append(rock)
	# Cull oldest debris beyond cap
	while debris.size() > int(params["debris_cap"]):
		var oldest = debris.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	fluid.add_impulse(cpos, 1.2 * params["fluid_reactivity"])
	fluid.inject_dye(cpos, _hue_rotated(pal["core"]), 180.0, 0.5 * params["fluid_reactivity"])
	# Soft trail wipe instead of hard clear
	_wipe_t = 0.6
	# Handle core removal vs reset
	if cores.size() > 1:
		# Binary: survivor gets kick, detonated core is removed
		for other in cores:
			var odict: Dictionary = other
			if odict == c:
				continue
			var other_vel: Vector2 = odict["vel"]
			var other_pos: Vector2 = odict["pos"]
			var dir_from_blast: Vector2 = (other_pos - cpos).normalized()
			odict["vel"] = other_vel + dir_from_blast * 300.0
		# Free the detonated core's rect before removing from array
		var crect: ColorRect = c["rect"]
		crect.queue_free()
		cores.erase(c)
	else:
		# Lone core: reset mass, keep the core
		c["mass"] = 0.0
	alive = 0  # clear infalling particles — fresh accretion cycle

func _frac(x: float) -> float:
	return x - floorf(x)

func _draw_rings() -> void:
	for r in rings:
		var rdict: Dictionary = r
		var origin: Vector2 = rdict.get("origin", CENTER)
		rings_node.draw_arc(origin, rdict["r"], 0, TAU, 128, Color(1, 1, 1, rdict["alpha"]) * 1.6, 5.0, true)

func _process(delta: float) -> void:
	super._process(delta)
	if s == null:
		return
	sim_t += delta
	_spawn_particles(delta)
	var g: float = params["g_strength"]
	var core_r: float = params["core_radius"]
	var critical: float = float(params["critical"])
	# --- Core motion ---
	if cores.size() == 1:
		var c: Dictionary = cores[0]
		var cpos: Vector2 = c["pos"]
		var cvel: Vector2 = c["vel"]
		var ph: Vector2 = c["ph"]
		var drift: float = params["core_drift"]
		var target := CENTER + Vector2(sin(sim_t * 0.11 + ph.x), cos(sim_t * 0.13 + ph.y)) * drift
		cvel += (target - cpos) * 0.8 * delta
		cvel *= 0.995
		cpos += cvel * delta
		c["pos"] = cpos
		c["vel"] = cvel
		var crect: ColorRect = c["rect"]
		crect.position = cpos - Vector2(350, 350)
	elif cores.size() == 2:
		# Compute new velocities first (using current positions), then update positions
		var c0: Dictionary = cores[0]
		var c1: Dictionary = cores[1]
		var pos0: Vector2 = c0["pos"]
		var pos1: Vector2 = c1["pos"]
		var vel0: Vector2 = c0["vel"]
		var vel1: Vector2 = c1["vel"]
		var diff: Vector2 = pos1 - pos0
		var d: float = maxf(diff.length(), 100.0)
		var dir01: Vector2 = diff / d
		var dir10: Vector2 = -dir01
		var grav_f: float = float(params["core_gravity"]) / maxf(d * d, 10000.0)
		vel0 += dir01 * grav_f * delta + (CENTER - pos0) * 0.05 * delta
		vel1 += dir10 * grav_f * delta + (CENTER - pos1) * 0.05 * delta
		vel0 *= 0.995
		vel1 *= 0.995
		pos0 += vel0 * delta
		pos1 += vel1 * delta
		c0["vel"] = vel0
		c0["pos"] = pos0
		c1["vel"] = vel1
		c1["pos"] = pos1
		var rect0: ColorRect = c0["rect"]
		var rect1: ColorRect = c1["rect"]
		rect0.position = pos0 - Vector2(350, 350)
		rect1.position = pos1 - Vector2(350, 350)
	# --- Refresh core hue and shader charge ---
	for ci in cores.size():
		var c: Dictionary = cores[ci]
		var cmass: float = c["mass"]
		var charge := clampf(cmass / critical, 0.0, 1.0)
		var cmat: ShaderMaterial = c["mat"]
		cmat.set_shader_parameter("charge", charge)
		cmat.set_shader_parameter("t", sim_t)
		cmat.set_shader_parameter("base_col", _hue_rotated(pal["core"]))
		cmat.set_shader_parameter("pulse_depth", params["pulse_depth"])
		cmat.set_shader_parameter("pulse_rate", params["pulse_rate"])
	# --- Swarm: gravity sums over all cores; absorption goes to nearest core ---
	var absorbed_by: Array = []
	for _c in cores:
		absorbed_by.append(0)
	var i := 0
	while i < alive:
		# Sum gravitational pull from all cores
		var total_accel := Vector2.ZERO
		for ci in cores.size():
			var c: Dictionary = cores[ci]
			var cpos: Vector2 = c["pos"]
			var dv: Vector2 = cpos - pos[i]
			var r2 := maxf(dv.length_squared(), 900.0)
			total_accel += dv / sqrt(r2) * (g / r2)
		vel[i] += total_accel * delta
		pos[i] += vel[i] * delta
		# Check absorption / out-of-bounds
		var removed := false
		for ci in cores.size():
			var c: Dictionary = cores[ci]
			var cpos: Vector2 = c["pos"]
			var dist := pos[i].distance_to(cpos)
			if dist < core_r:
				absorbed_by[ci] += 1
				alive -= 1
				pos[i] = pos[alive]
				vel[i] = vel[alive]
				col[i] = col[alive]
				removed = true
				break
		if not removed:
			# Check if particle is too far away
			if pos[i].distance_to(CENTER) > 1500.0:
				alive -= 1
				pos[i] = pos[alive]
				vel[i] = vel[alive]
				col[i] = col[alive]
			else:
				i += 1
		# if removed, don't increment i (swap-remove)
	# Apply absorption to each core
	for ci in cores.size():
		var c: Dictionary = cores[ci]
		c["mass"] = float(c["mass"]) + absorbed_by[ci]
		if absorbed_by[ci] > 0 and s.randf() < 0.3:
			var cpos: Vector2 = c["pos"]
			fluid.inject_dye(cpos, _hue_rotated(pal["core"]), 120.0, 0.1 * params["fluid_reactivity"])
	# --- Debris gravity + cleanup (sums over all cores) ---
	debris = debris.filter(func(b): return is_instance_valid(b))
	var to_remove_debris: Array = []
	for b in debris:
		var body: RigidBody2D = b
		var total_force := Vector2.ZERO
		for c in cores:
			var cdict: Dictionary = c
			var cpos: Vector2 = cdict["pos"]
			var dv: Vector2 = cpos - body.position
			var r2 := maxf(dv.length_squared(), 2500.0)
			total_force += dv.normalized() * (g * 0.6 / r2) * body.mass * 60.0
		body.apply_central_force(total_force)
		# Check if absorbed by any core
		var absorbed_debris := false
		for c in cores:
			var cdict: Dictionary = c
			var cpos: Vector2 = cdict["pos"]
			if body.position.distance_to(cpos) < core_r:
				cdict["mass"] = float(cdict["mass"]) + 5.0
				to_remove_debris.append(b)
				absorbed_debris = true
				break
		if not absorbed_debris and body.position.distance_to(CENTER) > 1600.0:
			to_remove_debris.append(b)
	for b in to_remove_debris:
		if is_instance_valid(b):
			var body: RigidBody2D = b
			body.queue_free()
		debris.erase(b)
	# --- Merge check (binary only) ---
	if cores.size() == 2:
		var c0: Dictionary = cores[0]
		var c1: Dictionary = cores[1]
		var p0: Vector2 = c0["pos"]
		var p1: Vector2 = c1["pos"]
		var diff: Vector2 = p0 - p1
		if diff.length() < float(params["merge_radius"]):
			# Merge: survivor = cores[0], loser = cores[1]
			var m0: float = float(c0["mass"])
			var m1: float = float(c1["mass"])
			var total_mass := m0 + m1
			var v0: Vector2 = c0["vel"]
			var v1: Vector2 = c1["vel"]
			# Momentum-average velocity
			if total_mass > 0.0:
				c0["vel"] = (v0 * m0 + v1 * m1) / total_mass
			c0["mass"] = total_mass
			flash_a = 0.5
			# Free the loser's rect before removing
			var loser_rect: ColorRect = c1["rect"]
			loser_rect.queue_free()
			cores.erase(c1)
			# If merged charge >= 1, allow fast detonation (short cooldown)
			if total_mass / critical >= 1.0 and det_cooldown > 0.5:
				det_cooldown = 0.0
	# --- Detonation / fission per core ---
	det_cooldown = maxf(det_cooldown - delta, 0.0)
	# Iterate over copy since _detonate/_fission may mutate cores.
	# cores.has(c) compares dicts by VALUE, but each dict holds a unique
	# rect Object (compared by reference), so no two cores can be equal.
	var cores_snapshot: Array = cores.duplicate()
	for ci in cores_snapshot.size():
		var c: Dictionary = cores_snapshot[ci]
		if not cores.has(c):
			continue  # already removed (e.g. merged)
		var cmass: float = float(c["mass"])
		var charge := clampf(cmass / critical, 0.0, 1.0)
		if charge >= 1.0 and det_cooldown <= 0.0:
			if cores.size() == 1 and s.randf() < float(params["split_chance"]):
				_fission(c)
			else:
				_detonate(c)
			break  # only one event per frame
	# --- Soft trail wipe ---
	if _wipe_t > 0.0:
		fade_rect.color.a = lerpf(params["trail_persist"], 0.5, clampf(_wipe_t / 0.6, 0.0, 1.0))
		_wipe_t = maxf(_wipe_t - delta, 0.0)
		if _wipe_t <= 0.0:
			fade_rect.color.a = params["trail_persist"]
	# --- Render swarm ---
	for k in maxi(alive, _prev_alive):
		if k < alive:
			swarm_mm.set_instance_transform_2d(k, Transform2D(0.0, pos[k]))
			swarm_mm.set_instance_color(k, col[k] * 0.35)
		else:
			swarm_mm.set_instance_transform_2d(k, Transform2D(0.0, Vector2(-9999, -9999)))
	_prev_alive = alive
	flash_a = maxf(flash_a - delta * 3.5, 0.0)
	flash_rect.color = Color(1, 1, 1, flash_a)
	for r in rings:
		var rdict: Dictionary = r
		rdict["r"] = float(rdict["r"]) + float(rdict["speed"]) * delta
		rdict["alpha"] = maxf(float(rdict["alpha"]) - delta * 1.1, 0.0)
	rings = rings.filter(func(r): return float(r["alpha"]) > 0.0)
	rings_node.queue_redraw()
	fluid.step(delta)
	fluid_display.texture = fluid.output_texture()

func apply_live(p: Dictionary) -> void:
	if env != null:
		env.glow_intensity = p["glow"]
	if fade_rect != null and _wipe_t <= 0.0:
		fade_rect.color = Color(0, 0, 0, p["trail_persist"])
