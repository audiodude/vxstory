extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")

func model_name() -> String:
	return "text_ident"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("intensity", 0.5),
		],
		"params": [
			PS.s("text", "DANGER THIRD RAIL"),
			PS.f("flash_hz", 1.0, 0.5, 8.0, {"macro": {"name": "intensity", "lo": 0.7, "hi": 4.0}}),
			PS.f("duty", 0.5, 0.05, 1.0),
			PS.i("font_size", 88, 24, 220),
			PS.f("jitter_px", 5.0, 0.0, 40.0, {"macro": {"name": "intensity", "lo": 0.0, "hi": 24.0}}),
			PS.f("glow", 1.0, 0.0, 3.0),
			PS.c("text_color", Color.WHITE),
		],
	}

var env: Environment
var label: Label
var _label_base_pos := Vector2.ZERO
var _sim_t := 0.0
var _phase_prev := 1.0  # start at 1.0 so first frame triggers edge detection correctly
var _sim_rng: RandomNumberGenerator

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):
			c.queue_free()
	_sim_t = 0.0
	_phase_prev = 1.0
	_sim_rng = rng.stream("sim")

	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = params["glow"]
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	label = Label.new()
	label.text = params["text"]

	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DejaVu Sans"])
	f.font_weight = 700
	label.add_theme_font_override("font", f)
	label.add_theme_font_size_override("font_size", params["font_size"])

	var col: Color = params["text_color"]
	col *= 1.3
	label.add_theme_color_override("font_color", col)

	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Anchors are meaningless under a Node2D parent (no Control ancestor), so
	# size the label to the full 1920x1080 design space explicitly; the
	# center alignments then center the text within it.
	label.position = Vector2.ZERO
	label.size = Vector2(1920, 1080)

	add_child(label)
	_label_base_pos = Vector2.ZERO

func _process(delta: float) -> void:
	super._process(delta)
	if label == null:
		return
	_sim_t += delta
	var phase := fposmod(_sim_t * params["flash_hz"], 1.0)
	label.visible = phase < params["duty"]
	# rising edge: invisible -> visible
	if label.visible and _phase_prev >= params["duty"]:
		var jx := _sim_rng.randf_range(-params["jitter_px"], params["jitter_px"])
		var jy := _sim_rng.randf_range(-params["jitter_px"], params["jitter_px"])
		label.position = _label_base_pos + Vector2(jx, jy)
	_phase_prev = phase

func apply_live(p: Dictionary) -> void:
	if env != null:
		env.glow_intensity = p["glow"]
	if label != null:
		label.text = p["text"]
		label.add_theme_font_size_override("font_size", p["font_size"])
		var col: Color = p["text_color"]
		col *= 1.3
		label.add_theme_color_override("font_color", col)
