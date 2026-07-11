extends VBoxContainer
# Superparam (macro) knobs, always shown; plus a "Show all basic params (A-Z)"
# zippy that reveals a knob per numeric param (alphabetical), seeded from the
# scene's override (or the schema default). Emits `changed` on any edit.

const Knob = preload("res://core/designer/knob.gd")
const CELL_W := 96.0  # uniform knob-cell width -> flow rows align as columns

signal changed()

var schema := {}
var macros := {}
var overrides := {}
var _all_box: VBoxContainer
var _macro_knobs := {}

func setup(p_schema: Dictionary, p_macros: Dictionary, p_overrides: Dictionary) -> void:
	schema = p_schema
	macros = p_macros.duplicate(true)
	overrides = p_overrides.duplicate(true)
	_build()

func macro_values() -> Dictionary:
	return macros

func override_values() -> Dictionary:
	return overrides

func set_macro(name: String, v: float) -> void:
	macros[name] = v

static func numeric_param_names_sorted(p_schema: Dictionary) -> Array:
	var names := []
	for p in p_schema["params"]:
		if p["type"] == "float" or p["type"] == "int":
			names.append(p["name"])
	names.sort()
	return names

func _param_def(name: String) -> Dictionary:
	for p in schema["params"]:
		if p["name"] == name:
			return p
	return {}

func _build() -> void:
	var t := Label.new()
	t.text = "BASES — superparams"
	t.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	add_child(t)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	add_child(row)
	for m in schema["macros"]:
		row.add_child(_macro_knob(m))

	var toggle := Button.new()
	toggle.text = "▸ Show all basic params (A–Z)"
	toggle.flat = true
	add_child(toggle)
	_all_box = VBoxContainer.new()
	_all_box.visible = false
	add_child(_all_box)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	_all_box.add_child(grid)
	for name in numeric_param_names_sorted(schema):
		grid.add_child(_param_knob(name))
	toggle.pressed.connect(func():
		_all_box.visible = not _all_box.visible
		toggle.text = ("▾ " if _all_box.visible else "▸ ") + "Show all basic params (A–Z)")

func macro_knobs() -> Dictionary:
	return _macro_knobs

func _macro_knob(m: Dictionary) -> VBoxContainer:
	var k = Knob.new()
	var v := float(macros.get(m["name"], m["default"]))
	k.setup(0.0, 1.0, v, float(m["default"]), Color(0.6, 0.85, 1.0))
	k.value_changed.connect(func(nv):
		macros[m["name"]] = nv
		changed.emit())
	_macro_knobs[m["name"]] = k
	return _labeled_cell(k, m["name"])

func _param_knob(name: String) -> VBoxContainer:
	var p := _param_def(name)
	var k = Knob.new()
	var v := float(overrides.get(name, p["default"]))
	k.setup(float(p["min"]), float(p["max"]), v, float(p["default"]), Color(0.7, 0.78, 0.9))
	k.value_changed.connect(func(nv):
		overrides[name] = nv
		changed.emit())
	return _labeled_cell(k, name)

# Uniform-width cell (knob over centered label) so flow rows align as a grid.
func _labeled_cell(k: Control, name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(CELL_W, 0)
	box.add_child(k)
	var l := Label.new()
	l.text = name
	l.add_theme_font_size_override("font_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(l)
	return box
