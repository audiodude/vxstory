extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")
const FluidSim = preload("res://fluid_sim/fluid_sim.gd")
const GRADE := preload("res://fluid_sim/grade.gdshader")

const PALETTES := {
	"psychedelic": [Color("#2222dd"), Color("#dd2211"), Color("#22aa33"), Color("#ddaa11"), Color("#aa22cc")],
	"magma": [Color("#ff4400"), Color("#ffaa00"), Color("#881100"), Color("#ffe080"), Color("#330000")],
	"ocean": [Color("#0044ff"), Color("#00ccff"), Color("#003377"), Color("#88ffee"), Color("#001133")],
	"neon": [Color("#ff00aa"), Color("#00ffcc"), Color("#aaff00"), Color("#7700ff"), Color("#ff5500")],
}

var fluid: Node2D
var display: TextureRect
var grade_mat: ShaderMaterial
var injectors: Array = []  # {ph: Vector2, fr: Vector2, color: Color}
var sim_t := 0.0

func model_name() -> String:
	return "fluid_swirl"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("turbulence", 0.55), PS.macro_def("viscosity", 0.5),
			PS.macro_def("flow", 0.5), PS.macro_def("vibrance", 0.6),
		],
		"params": [
			PS.i("sim_height", 540, 270, 1080, {"live": false}),
			PS.f("noise_strength", 1.2, 0.0, 3.0, {"macro": {"name": "turbulence", "lo": 0.2, "hi": 2.5}}),
			PS.f("noise_scale", 3.0, 1.0, 8.0),
			PS.f("dissipation", 0.985, 0.9, 1.0, {"macro": {"name": "viscosity", "lo": 0.95, "hi": 0.999}}),
			PS.f("flow_speed", 1.5, 0.2, 4.0, {"macro": {"name": "flow", "lo": 0.4, "hi": 3.5}}),
			PS.i("vortex_count", 5, 0, 8, {"live": false}),
			PS.f("vortex_strength", 0.8, 0.0, 2.0, {"macro": {"name": "turbulence", "lo": 0.1, "hi": 1.6}}),
			PS.i("injector_count", 4, 1, 8, {"live": false}),
			PS.f("inject_radius", 80.0, 20.0, 200.0),
			PS.f("inject_strength", 0.35, 0.05, 1.0),
			PS.f("injector_speed", 0.3, 0.05, 1.0),
			PS.e("palette", "psychedelic", PackedStringArray(["psychedelic", "magma", "ocean", "neon"]), {"live": false}),
			PS.f("saturation", 1.25, 0.5, 2.0, {"macro": {"name": "vibrance", "lo": 0.8, "hi": 1.8}}),
			PS.f("contrast", 1.1, 0.8, 1.6),
		],
	}

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):
			c.queue_free()
	injectors.clear()
	sim_t = 0.0
	var srng: RandomNumberGenerator = rng.stream("sim")
	fluid = FluidSim.new()
	add_child(fluid)
	var h: int = params["sim_height"]
	fluid.setup(rng.stream("vortices"), int(h * 16.0 / 9.0), h, _fluid_opts())
	var cols: Array = PALETTES[params["palette"]]
	for i in int(params["injector_count"]):
		injectors.append({
			"ph": Vector2(srng.randf_range(0.0, TAU), srng.randf_range(0.0, TAU)),
			"fr": Vector2(srng.randf_range(0.5, 1.5), srng.randf_range(0.5, 1.5)),
			"color": cols[i % cols.size()],
		})
	display = TextureRect.new()
	display.size = Vector2(1920, 1080)
	display.stretch_mode = TextureRect.STRETCH_SCALE
	grade_mat = ShaderMaterial.new()
	grade_mat.shader = GRADE
	display.material = grade_mat
	add_child(display)
	apply_live(params)

func _fluid_opts() -> Dictionary:
	return {
		"noise_strength": params["noise_strength"], "noise_scale": params["noise_scale"],
		"dissipation": params["dissipation"], "flow_speed": params["flow_speed"],
		"vortex_count": params["vortex_count"], "vortex_strength": params["vortex_strength"],
	}

func _process(delta: float) -> void:
	super._process(delta)
	if fluid == null:
		return
	sim_t += delta
	var spd: float = params["injector_speed"]
	for inj in injectors:
		var uv := Vector2(
			0.5 + 0.38 * sin(sim_t * spd * inj["fr"].x + inj["ph"].x),
			0.5 + 0.38 * sin(sim_t * spd * inj["fr"].y + inj["ph"].y))
		fluid.inject_dye(uv * Vector2(1920, 1080), inj["color"], params["inject_radius"], params["inject_strength"])
	fluid.step(delta)
	display.texture = fluid.output_texture()

func apply_live(p: Dictionary) -> void:
	if fluid != null:
		fluid.set_opts(_fluid_opts())
	if grade_mat != null:
		grade_mat.set_shader_parameter("saturation", p["saturation"])
		grade_mat.set_shader_parameter("contrast", p["contrast"])
