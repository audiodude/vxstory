extends "res://core/sim_model.gd"
# metro_rise: a 3D city grows from empty dawn land to a lit night metropolis.
# Everything visible is a pure function of two live dials — `development` (P)
# selects plan-at-P city structure, `day_phase` drives the single sun arc —
# plus transient layers (traffic, cranes, dust) keyed to the sim clock.

const PS = preload("res://core/param_schema.gd")
const Hue = preload("res://core/hue.gd")
const Plan = preload("res://citygen/plan.gd")
const State = preload("res://sim/state.gd")
const Sun = preload("res://sim/sun.gd")
const Cam = preload("res://sim/campath.gd")
const CityView = preload("res://view/city_view.gd")

var plan: Dictionary = {}
var tracker  # StateTracker
var city_view  # CityView
var world: Node3D
var env: Environment
var sky_mat: ShaderMaterial
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var cam: Camera3D
var sim_t := 0.0
var _ring_p := 0.22

func model_name() -> String:
	return "metro_rise"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("development", 0.5), PS.macro_def("day_phase", 0.55),
			PS.macro_def("density", 0.55), PS.macro_def("verticality", 0.5),
			PS.macro_def("sprawl", 0.5), PS.macro_def("traffic", 0.55),
			PS.macro_def("nightlife", 0.6),
		],
		"params": [
			# The two master dials (live).
			PS.f("progress", 0.5, 0.0, 1.0, {"macro": {"name": "development", "lo": 0.0, "hi": 1.0}}),
			PS.f("time_of_day", 0.55, 0.0, 1.0, {"macro": {"name": "day_phase", "lo": 0.0, "hi": 1.0}}),
			# Structural (frozen into the plan at restart).
			PS.f("city_radius", 550.0, 320.0, 780.0, {"live": false, "macro": {"name": "sprawl", "lo": 380.0, "hi": 740.0}}),
			PS.f("lot_fill", 0.78, 0.5, 0.95, {"live": false, "macro": {"name": "density", "lo": 0.55, "hi": 0.95}}),
			PS.f("height_scale", 1.0, 0.6, 1.6, {"live": false, "macro": {"name": "verticality", "lo": 0.7, "hi": 1.5}}),
			PS.f("tower_share", 0.25, 0.05, 0.5, {"live": false, "macro": {"name": "verticality", "lo": 0.08, "hi": 0.45}}),
			PS.f("block_min", 90.0, 70.0, 120.0, {"live": false}),
			PS.f("block_max", 130.0, 100.0, 170.0, {"live": false}),
			PS.i("boulevard_count", 2, 0, 3, {"live": false}),
			PS.f("park_pct", 0.07, 0.0, 0.2, {"live": false}),
			PS.f("floor_h", 3.2, 2.6, 4.0, {"live": false}),
			PS.f("era1_end", 0.34, 0.15, 0.5, {"live": false}),
			PS.f("era2_end", 0.66, 0.5, 0.85, {"live": false}),
			PS.f("era_overlap", 0.08, 0.0, 0.15, {"live": false}),
			PS.f("demolish_core", 0.85, 0.0, 1.0, {"live": false}),
			PS.f("demolish_edge", 0.25, 0.0, 1.0, {"live": false}),
			PS.f("construct_speed", 1.0, 0.4, 2.5, {"live": false}),
			PS.i("topout_floors", 18, 8, 40, {"live": false}),
			PS.f("crane_density", 0.7, 0.0, 1.0, {"live": false}),
			PS.f("tree_density", 0.6, 0.0, 1.0, {"live": false}),
			PS.f("lamp_density", 0.6, 0.0, 1.0, {"live": false}),
			PS.f("win_scale", 1.0, 0.7, 1.4, {"live": false}),
			# Live look dials.
			PS.f("lit_fraction", 0.6, 0.0, 0.95, {"macro": {"name": "nightlife", "lo": 0.25, "hi": 0.95}}),
			PS.f("neon_amount", 0.45, 0.0, 1.0, {"macro": {"name": "nightlife", "lo": 0.1, "hi": 1.0}}),
			PS.f("glow", 1.1, 0.0, 3.0),
			PS.f("fog_amount", 0.35, 0.0, 1.0),
			PS.f("star_density", 0.5, 0.0, 1.0),
			PS.f("hue_drift", 0.0, 0.0, 90.0),
			PS.e("palette", "daybreak", PackedStringArray(["daybreak", "sodium", "overcast"])),
			# Live camera dials.
			PS.f("orbit_rate", 1.3, 0.2, 4.0),
			PS.f("cam_pull", 1.0, 0.7, 1.3),
			PS.f("cam_height", 1.0, 0.7, 1.3),
			PS.f("cam_fov", 40.0, 25.0, 60.0),
			# Live traffic dials (consumed in Task 10).
			PS.f("car_density", 0.55, 0.0, 1.0, {"macro": {"name": "traffic", "lo": 0.0, "hi": 1.0}}),
			PS.f("car_speed", 1.0, 0.5, 1.5),
			PS.f("light_cycle", 14.0, 8.0, 30.0),
		],
	}

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):
			c.queue_free()
	plan = Plan.build(rng, params)
	tracker = State.new(plan, params)

	world = Node3D.new()
	add_child(world)

	env = Environment.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://view/sky.gdshader")
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.75
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_sun_scatter = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	sun_light = DirectionalLight3D.new()
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_max_distance = 1700.0
	sun_light.directional_shadow_split_1 = 0.12
	sun_light.directional_shadow_split_2 = 0.3
	sun_light.directional_shadow_split_3 = 0.6
	world.add_child(sun_light)

	moon_light = DirectionalLight3D.new()
	moon_light.light_color = Color(0.6, 0.72, 1.0)
	moon_light.rotation_degrees = Vector3(-42.0, 140.0, 0.0)
	world.add_child(moon_light)

	city_view = CityView.new()
	world.add_child(city_view)
	city_view.setup(plan, params, tracker.building_count())

	cam = Camera3D.new()
	cam.near = 2.0
	cam.far = 4000.0
	world.add_child(cam)
	cam.current = true

	_frame_update()

func apply_live(_p: Dictionary) -> void:
	pass  # all live params are read fresh in _frame_update each frame

func _on_scrub(t: float) -> void:
	sim_t = t

func _process(delta: float) -> void:
	super._process(delta)
	sim_t += delta
	_frame_update()

func _frame_update() -> void:
	if tracker == null or params.is_empty():
		return
	var st: Dictionary = tracker.eval(params["progress"])
	_ring_p = st["ring_p"]
	city_view.apply_slots(tracker, st["changed"])
	for ev in st["events"]:
		emit_event(ev["kind"])

	var sun_out: Dictionary = Sun.eval(params["time_of_day"], params["palette"], params)
	_apply_sky(sun_out)

	var hue_shift: float = fposmod(float(params["hue_drift"]) * sim_t / 60.0, 360.0)
	city_view.set_globals(sun_out, {
		"lit_fraction": params["lit_fraction"], "neon_amount": params["neon_amount"],
		"hue_shift": hue_shift, "ring_p": _ring_p,
	}, sim_t)

	var c: Dictionary = Cam.eval(sim_t, params["progress"], params)
	cam.fov = c["fov"]
	cam.look_at_from_position(c["pos"], c["look"], Vector3.UP)

func _apply_sky(s: Dictionary) -> void:
	var dir: Vector3 = s["sun_dir"]
	if dir.length() > 0.001:
		sun_light.transform = Transform3D.IDENTITY.looking_at(dir, Vector3.UP)
	sun_light.light_energy = s["sun_energy"]
	sun_light.light_color = s["sun_color"]
	moon_light.light_energy = s["moon_energy"]
	sky_mat.set_shader_parameter("top_color", Vector3(s["sky_top"].r, s["sky_top"].g, s["sky_top"].b))
	sky_mat.set_shader_parameter("horizon_color", Vector3(s["sky_horizon"].r, s["sky_horizon"].g, s["sky_horizon"].b))
	sky_mat.set_shader_parameter("sun_color", Vector3(s["sun_color"].r, s["sun_color"].g, s["sun_color"].b))
	sky_mat.set_shader_parameter("to_sun", -dir)
	sky_mat.set_shader_parameter("sun_energy", s["sun_energy"])
	sky_mat.set_shader_parameter("star_alpha", s["star_alpha"])
	sky_mat.set_shader_parameter("star_density", params["star_density"])
	env.ambient_light_energy = s["ambient_energy"]
	env.fog_density = s["fog_density"]
	env.fog_light_color = s["sky_horizon"]
	env.glow_intensity = 0.9 * float(params["glow"])
