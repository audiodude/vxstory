extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")

var sim_vp: SubViewport
var fade_rect: ColorRect
var rings_node: Node2D
var main_emitter: GPUParticles2D
var sub_emitters: Array[GPUParticles2D] = []
var mirror_rects: Array[TextureRect] = []
var env: Environment
var cycle_t := 0.0
var sub_schedule: Array = []  # {at: float, idx: int, pos: Vector2} per cycle
var rings: Array = []         # {r, speed, alpha}
var s: RandomNumberGenerator

const PALETTES := {
	"silver": [Color(1, 1, 1), Color(0.75, 0.78, 0.82), Color(0.3, 0.3, 0.33)],
	"bone": [Color(1, 0.97, 0.9), Color(0.85, 0.8, 0.7), Color(0.35, 0.3, 0.25)],
	"ice": [Color(0.85, 0.95, 1), Color(0.6, 0.8, 1), Color(0.2, 0.3, 0.5)],
}

func model_name() -> String:
	return "radial_burst"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("energy", 0.7), PS.macro_def("density", 0.55),
			PS.macro_def("symmetry", 0.35), PS.macro_def("grit", 0.4),
		],
		"params": [
			PS.f("loop_period", 5.0, 2.0, 12.0, {"live": false, "jitter": {"pct": 10.0}}),
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
			PS.e("mirror", "horizontal", PackedStringArray(["off", "horizontal", "quad"]), {"live": false}),
			PS.f("mirror_mix", 0.55, 0.0, 1.0, {"macro": {"name": "symmetry", "lo": 0.0, "hi": 0.9}}),
			PS.f("glow", 0.35, 0.0, 3.0),
			PS.e("palette", "silver", PackedStringArray(["silver", "bone", "ice"]), {"live": false}),
		],
	}

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):  # keep the tweak panel
			c.queue_free()
	sub_emitters.clear()
	mirror_rects.clear()
	rings.clear()
	sub_schedule.clear()
	cycle_t = 0.0
	s = rng.stream("sim")
	_build()

func _build() -> void:
	var center := Vector2(960, 540)
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
	rings_node.position = center
	rings_node.draw.connect(_draw_rings)
	sim_vp.add_child(rings_node)

	main_emitter = _make_emitter(params["particle_count"], 1.0)
	main_emitter.position = center
	sim_vp.add_child(main_emitter)
	for i in int(params["subburst_count"]):
		var e := _make_emitter(maxi(int(params["particle_count"] * params["subburst_scale"] / maxf(1.0, params["subburst_count"])), 50), 0.45)
		sim_vp.add_child(e)
		sub_emitters.append(e)

	# Root-level glow + mirrored display
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
		add_child(tr)
		if i > 0:
			mirror_rects.append(tr)

func _make_emitter(amount: int, scale_mul: float) -> GPUParticles2D:
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
	var grad := Gradient.new()
	var cols: Array = PALETTES[params["palette"]]
	grad.set_color(0, cols[0])
	grad.set_color(1, Color(cols[2].r, cols[2].g, cols[2].b, 0.0))
	grad.add_point(0.35, cols[1])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	g.process_material = pm
	return g

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

func _fire_cycle() -> void:
	main_emitter.restart()
	rings.clear()
	for i in int(params["ring_count"]):
		rings.append({"r": 10.0, "speed": params["ring_speed"] * s.randf_range(0.7, 1.3), "alpha": 1.0})
	sub_schedule.clear()
	for i in sub_emitters.size():
		var ang := s.randf_range(0.0, TAU)
		var at := s.randf_range(0.35, 1.4)
		var dist: float = params["burst_speed"] * at * 0.55
		sub_schedule.append({"at": at, "idx": i, "pos": Vector2(960, 540) + Vector2.from_angle(ang) * dist})

func _draw_rings() -> void:
	var cols: Array = PALETTES[params["palette"]]
	for r in rings:
		var c: Color = cols[0]
		c.a = r["alpha"]
		rings_node.draw_arc(Vector2.ZERO, r["r"], 0, TAU, 128, c, params["ring_width"], true)

func _process(delta: float) -> void:
	super._process(delta)
	if s == null:
		return
	var prev := cycle_t
	cycle_t += delta
	if prev == 0.0 or cycle_t >= params["loop_period"]:
		cycle_t = 0.001
		_fire_cycle()
	for ev in sub_schedule.duplicate():
		if cycle_t >= ev["at"]:
			var e := sub_emitters[ev["idx"]]
			e.position = ev["pos"]
			e.restart()
			sub_schedule.erase(ev)
	for r in rings:
		r["r"] += r["speed"] * delta
		r["alpha"] = maxf(r["alpha"] - delta * 0.8, 0.0)
	rings_node.queue_redraw()

func apply_live(p: Dictionary) -> void:
	if fade_rect != null:
		fade_rect.color = Color(0, 0, 0, p["trail_persist"])
	if env != null:
		env.glow_intensity = p["glow"]
	for tr in mirror_rects:
		tr.modulate = Color(1, 1, 1, p["mirror_mix"])
