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
var core_rect: ColorRect
var core_mat: ShaderMaterial
var flash_rect: ColorRect
var flash_a := 0.0
var rings: Array = []
var rings_node: Node2D
var mass := 0.0
var spawn_acc := 0.0
var sim_t := 0.0
var det_cooldown := 0.0  # seconds until next detonation is allowed
var _trail_clear_frames := 0  # flush trail buffer for N frames after detonation
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
		],
	}

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):
			c.queue_free()
	debris.clear()
	rings.clear()
	alive = 0
	_prev_alive = 0
	mass = 0.0
	spawn_acc = 0.0
	sim_t = 0.0
	flash_a = 0.0
	det_cooldown = 0.0
	_trail_clear_frames = 0
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
	# core glow (shader), rings, flash — crisp, on top
	core_rect = ColorRect.new()
	core_rect.size = Vector2(700, 700)
	core_rect.position = CENTER - Vector2(350, 350)
	core_mat = ShaderMaterial.new()
	core_mat.shader = CORE_SHADER
	core_mat.set_shader_parameter("base_col", pal["core"])
	core_rect.material = core_mat
	add_child(core_rect)
	rings_node = Node2D.new()
	rings_node.position = CENTER
	rings_node.draw.connect(_draw_rings)
	add_child(rings_node)
	flash_rect = ColorRect.new()
	flash_rect.size = Vector2(1920, 1080)
	flash_rect.color = Color(1, 1, 1, 0)
	add_child(flash_rect)

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
		col[alive] = cols[k % cols.size()]
		alive += 1

func _detonate() -> void:
	flash_a = 0.9
	det_cooldown = 5.0  # prevent immediate re-detonation
	for ri in 3:
		rings.append({"r": 40.0 + ri * 30.0, "speed": 900.0 + ri * 400.0, "alpha": 1.0})
	# blast all accumulated particles outward (clear the swarm)
	for i in alive:
		var d := pos[i] - CENTER
		var dist := maxf(d.length(), 30.0)
		vel[i] = d / dist * params["detonation_speed"] * (0.6 + 0.6 * _frac(i * 0.6180339887)) + vel[i] * 0.2
	# old debris get a fresh impulse, then clean up old ones
	for b in debris:
		if is_instance_valid(b):
			b.queue_free()
	debris.clear()
	for i in int(params["debris_count"]):
		var rock := Debris.new(params["debris_radius"] * s.randf_range(0.6, 1.4), pal["debris"], s)
		rock.position = CENTER + Vector2.from_angle(s.randf_range(0.0, TAU)) * s.randf_range(20.0, 80.0)
		rock.linear_velocity = (rock.position - CENTER).normalized() * params["detonation_speed"] * s.randf_range(0.5, 1.1)
		rock.angular_velocity = s.randf_range(-6.0, 6.0)
		add_child(rock)  # root scene — debris render crisp, not in trail buffer
		debris.append(rock)
	fluid.add_impulse(CENTER, 1.2 * params["fluid_reactivity"])
	fluid.inject_dye(CENTER, pal["core"], 180.0, 0.5 * params["fluid_reactivity"])
	mass = 0.0
	alive = 0  # clear all infalling particles — fresh accretion cycle
	_trail_clear_frames = 3  # flush trail buffer so gray smear doesn't persist

func _frac(x: float) -> float:
	return x - floorf(x)

func _draw_rings() -> void:
	for r in rings:
		rings_node.draw_arc(Vector2.ZERO, r["r"], 0, TAU, 128, Color(1, 1, 1, r["alpha"]) * 1.6, 5.0, true)

func _process(delta: float) -> void:
	super._process(delta)
	if s == null:
		return
	sim_t += delta
	_spawn_particles(delta)
	var g: float = params["g_strength"]
	var core_r: float = params["core_radius"]
	var absorbed := 0
	var i := 0
	while i < alive:
		var d := CENTER - pos[i]
		var r2 := maxf(d.length_squared(), 900.0)
		vel[i] += d / sqrt(r2) * (g / r2) * delta
		pos[i] += vel[i] * delta
		var r := sqrt(r2)
		if r < core_r or r > 1500.0:
			if r < core_r:
				absorbed += 1
			alive -= 1
			pos[i] = pos[alive]
			vel[i] = vel[alive]
			col[i] = col[alive]
			continue
		i += 1
	mass += absorbed
	if absorbed > 0 and s.randf() < 0.3:
		fluid.inject_dye(CENTER, pal["core"], 120.0, 0.1 * params["fluid_reactivity"])
	# debris gravity + cleanup
	debris = debris.filter(func(b): return is_instance_valid(b))
	for b in debris:
		var d: Vector2 = CENTER - b.position
		var r2 := maxf(d.length_squared(), 2500.0)
		b.apply_central_force(d.normalized() * (g * 0.6 / r2) * b.mass * 60.0)
		if b.position.distance_to(CENTER) > 1600.0:
			b.queue_free()
		elif b.position.distance_to(CENTER) < core_r:
			mass += 5.0
			b.queue_free()
	det_cooldown = maxf(det_cooldown - delta, 0.0)
	var charge := clampf(mass / float(params["critical"]), 0.0, 1.0)
	core_mat.set_shader_parameter("charge", charge)
	core_mat.set_shader_parameter("t", sim_t)
	if charge >= 1.0 and det_cooldown <= 0.0:
		_detonate()
	# flush trail buffer for a few frames after detonation to kill the gray smear
	# (must come AFTER _detonate() so the flush starts on the same frame)
	if _trail_clear_frames > 0:
		sim_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_trail_clear_frames -= 1
		if _trail_clear_frames == 0:
			sim_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	# render swarm — high-water mark optimization: only update slots that changed
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
		r["r"] += r["speed"] * delta
		r["alpha"] = maxf(r["alpha"] - delta * 1.1, 0.0)
	rings = rings.filter(func(r): return r["alpha"] > 0.0)
	rings_node.queue_redraw()
	fluid.step(delta)
	fluid_display.texture = fluid.output_texture()

func apply_live(p: Dictionary) -> void:
	if env != null:
		env.glow_intensity = p["glow"]
	if fade_rect != null:
		fade_rect.color = Color(0, 0, 0, p["trail_persist"])
