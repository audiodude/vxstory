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
	# the station's signature red, cribbed from radio.dangerthirdrail.com offline.html
	"danger": [Color("#ff2a2a"), Color(1, 1, 1), Color(0.45, 0.55, 1.0)],
	# the full galton-board palette, verbatim from
	# radio.dangerthirdrail.com/scripts/main.gd ALL_COLORS (12 vibrant hues)
	"galton": [
		Color(1.00, 0.20, 0.20), Color(0.15, 0.85, 1.00), Color(1.00, 0.95, 0.15),
		Color(0.55, 0.20, 1.00), Color(1.00, 0.40, 0.10), Color(0.10, 1.00, 0.45),
		Color(1.00, 0.20, 0.55), Color(0.20, 0.40, 1.00), Color(1.00, 0.65, 0.80),
		Color(0.00, 1.00, 0.85), Color(0.90, 0.70, 0.10), Color(0.75, 0.55, 1.00),
	],
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
			PS.f("sympathy", 0.0, 0.0, 1.0),  # direct param (was the `coupling` n=1 passthrough macro)
			PS.f("sympathy_radius", 500.0, 50.0, 1200.0),
			PS.f("ripple_speed", 1600.0, 200.0, 4000.0),
			PS.f("hue_drift", 0.0, 0.0, 90.0),
			PS.e("mirror", "horizontal", PackedStringArray(["off", "horizontal", "quad"]), {"live": false}),
			PS.f("mirror_mix", 0.55, 0.0, 1.0, {"macro": {"name": "symmetry", "lo": 0.0, "hi": 0.9}}),
			PS.f("glow", 0.35, 0.0, 3.0),
			PS.e("palette", "silver", PackedStringArray(["silver", "bone", "ice", "danger", "galton"]), {"live": false}),
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

func _on_scrub(t: float) -> void:
	sim_t = t

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
	var order := _shuffled_indices(pal.size())  # vary source hues per seed
	var positions := _place_sources()
	var n := positions.size()
	for i in n:
		var base: Color = pal[order[i % pal.size()]]
		var main := _make_emitter(int(params["particle_count"]), 1.0, base)
		main.position = positions[i]
		sim_vp.add_child(main)
		var subs: Array = []
		for k in int(params["subburst_count"]):
			var amt := maxi(int(params["particle_count"] * params["subburst_scale"] / maxf(1.0, params["subburst_count"])), 50)
			var e := _make_emitter(amt, 0.45, base)
			sim_vp.add_child(e)
			subs.append(e)
		var period: float = _ignite_period()
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

func _shuffled_indices(count: int) -> Array:
	var order := []
	for i in count:
		order.append(i)
	for k in range(count - 1, 0, -1):  # seeded Fisher-Yates
		var j := s.randi() % (k + 1)
		var tmp = order[k]
		order[k] = order[j]
		order[j] = tmp
	return order

# Inter-burst period (seeded jitter); frequency is now driven by modulating loop_period.
func _ignite_period() -> float:
	return params["loop_period"] * s.randf_range(0.85, 1.15)

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
	# params are the live composed values (modulators already applied this frame)
	src["main"].amount = maxi(int(params["particle_count"]), 8)
	src["main"].lifetime = params["particle_life"]
	src["main"].process_material = _make_process_material(1.0, src["base"])
	src["main"].position = src["pos"]
	src["main"].restart()
	for e in src["subs"]:
		var ang := s.randf_range(0.0, TAU)
		var at := s.randf_range(0.1, 0.5)
		var dist: float = params["burst_speed"] * 0.55 * at
		e.amount = maxi(int(params["particle_count"] * params["subburst_scale"] / maxf(1.0, float(src["subs"].size()))), 50)
		e.process_material = _make_process_material(0.45, src["base"])
		e.position = src["pos"] + Vector2.from_angle(ang) * dist
		e.restart()
	for ri in int(params["ring_count"]):
		rings.append({"center": src["pos"], "r": 10.0,
			"speed": params["ring_speed"] * s.randf_range(0.7, 1.3),
			"alpha": 1.0, "color": _src_color(src)})
	src["timer"] = 0.0
	src["period"] = _ignite_period()
	emit_event("burst")
	# sympathetic cascade (only from a primary ignition); strength is composed sympathy
	if sources.size() > 1 and depth == 0 and params["sympathy"] > 0.0:
		var positions := []
		for sc in sources:
			positions.append(sc["pos"])
		var caught := Cascade.flood(positions, i, params["sympathy"], params["sympathy_radius"], s)
		for c in caught:
			var cidx := int(c["idx"])
			var already := false
			for pe in pending:
				if int(pe["idx"]) == cidx:
					already = true
					break
			if not already:
				pending.append({"at": sim_t + c["dist"] / maxf(params["ripple_speed"], 1.0), "idx": cidx})

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
