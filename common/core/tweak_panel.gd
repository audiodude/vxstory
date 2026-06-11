extends CanvasLayer
# Auto-generated parameter UI. Constructed with the SimModel it controls:
#   add_child(TweakPanel.new(model))

const MacroMapper = preload("res://core/macro_mapper.gd")
const PresetIO = preload("res://core/preset_io.gd")

var model  # SimModel
var _root: PanelContainer
var _hint: Label
var _param_rows: Dictionary = {}  # name -> {control, clear_btn, set_value(v)}
var _macro_sliders: Dictionary = {}
var _seed_edit: LineEdit
var _drift_acc := 0.0

func _init(p_model) -> void:
	model = p_model
	layer = 100
	# Build all UI immediately so _param_rows and _macro_sliders are populated
	# even before _ready() fires (important for headless test context).
	_build_ui()

func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_root.custom_minimum_size = Vector2(380, 0)
	_root.anchor_bottom = 1.0
	_root.offset_left = -380
	add_child(_root)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	vbox.add_child(_title("vxstory · " + model.model_name() + "   [Tab] hide"))
	_build_seed_row(vbox)
	_hint = Label.new()
	_hint.text = "changed params need Restart"
	_hint.modulate = Color(1.0, 0.7, 0.2)
	_hint.visible = false
	vbox.add_child(_hint)

	if model.director_cfg.get("enabled", false):
		var dir_label := _title("DIRECTOR ACTIVE — macros drift")
		dir_label.add_theme_color_override("font_color", Color.CYAN)
		vbox.add_child(dir_label)
	vbox.add_child(_title("MACROS"))
	for m in model.get_schema()["macros"]:
		_build_macro_row(vbox, m)
	vbox.add_child(_title("PARAMS  (editing pins ✕ unpins)"))
	for p in model.get_schema()["params"]:
		_build_param_row(vbox, p)
	_build_buttons(vbox)

func _ready() -> void:
	_refresh_all()

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	return l

func _build_seed_row(vbox: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label_min("seed", 110))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(model.seed_value)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_submitted.connect(func(t):
		model.seed_value = int(t)
		model.resolve_and_restart()
		_refresh_all())
	row.add_child(_seed_edit)
	var reroll := Button.new()
	reroll.text = "Reroll"
	reroll.pressed.connect(func():
		model.seed_value = randi() % 1000000000
		_seed_edit.text = str(model.seed_value)
		model.resolve_and_restart()
		_refresh_all())
	row.add_child(reroll)
	vbox.add_child(row)

func _label_min(text: String, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.clip_text = true
	return l

func _build_macro_row(vbox: VBoxContainer, m: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label_min(m["name"], 110))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := _label_min("", 44)
	slider.value_changed.connect(func(v):
		model.macros[m["name"]] = v
		val.text = "%.2f" % v
		if model.director != null:
			model.director.rebase(m["name"], v)
		_on_macro_changed())
	var entry := {"slider": slider, "val": val, "dragging": false}
	slider.drag_started.connect(func(): entry["dragging"] = true)
	slider.drag_ended.connect(func(_changed): entry["dragging"] = false)
	row.add_child(slider)
	row.add_child(val)
	vbox.add_child(row)
	_macro_sliders[m["name"]] = entry

func _on_macro_changed() -> void:
	# If every macro-affected, non-overridden param is live, apply now; else hint.
	var any_structural := false
	for p in model.get_schema()["params"]:
		if p.has("macro") and not model.overrides.has(p["name"]) and not p.get("live", true):
			any_structural = true
	model.resolve_live()
	_refresh_param_values()
	_hint.visible = any_structural

func _build_param_row(vbox: VBoxContainer, p: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label_min(p["name"], 150))
	var entry := {"control": null, "clear_btn": null, "set_value": null}
	match p["type"]:
		"float", "int":
			var slider := HSlider.new()
			slider.min_value = float(p["min"])
			slider.max_value = float(p["max"])
			slider.step = 1.0 if p["type"] == "int" else (float(p["step"]) if float(p.get("step", 0.0)) > 0.0 else (float(p["max"]) - float(p["min"])) / 200.0)
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var val := _label_min("", 56)
			slider.value_changed.connect(func(v):
				_set_override(p, int(v) if p["type"] == "int" else v)
				val.text = _fmt(p, v))
			row.add_child(slider)
			row.add_child(val)
			entry["control"] = slider
			entry["set_value"] = func(v):
				slider.set_value_no_signal(float(v))
				val.text = _fmt(p, float(v))
		"bool":
			var cb := CheckBox.new()
			cb.toggled.connect(func(v): _set_override(p, v))
			row.add_child(cb)
			entry["control"] = cb
			entry["set_value"] = func(v): cb.set_pressed_no_signal(bool(v))
		"enum":
			var ob := OptionButton.new()
			for o in p["options"]:
				ob.add_item(o)
			ob.item_selected.connect(func(idx): _set_override(p, p["options"][idx]))
			row.add_child(ob)
			entry["control"] = ob
			entry["set_value"] = func(v):
				var idx: int = (p["options"] as PackedStringArray).find(str(v))
				ob.select(maxi(idx, 0))
		"color":
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(60, 0)
			cp.color_changed.connect(func(v): _set_override(p, v))
			row.add_child(cp)
			entry["control"] = cp
			entry["set_value"] = func(v): cp.color = v
		"string":
			var le := LineEdit.new()
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_submitted.connect(func(t): _set_override(p, t))
			row.add_child(le)
			entry["control"] = le
			entry["set_value"] = func(v): le.text = str(v)
	var clear := Button.new()
	clear.text = "✕"
	clear.tooltip_text = "unpin (remove override)"
	clear.visible = false
	clear.pressed.connect(func():
		model.overrides.erase(p["name"])
		_after_edit(p))
	row.add_child(clear)
	entry["clear_btn"] = clear
	vbox.add_child(row)
	_param_rows[p["name"]] = entry

func _fmt(p: Dictionary, v: float) -> String:
	return str(int(v)) if p["type"] == "int" else "%.2f" % v

func _set_override(p: Dictionary, v) -> void:
	model.overrides[p["name"]] = v
	_after_edit(p)

func _after_edit(p: Dictionary) -> void:
	# Always re-resolve so model.params stays current; non-live params won't
	# take visual effect until Restart, hence the hint.
	model.resolve_live()
	if not p.get("live", true):
		_hint.visible = true
	_param_rows[p["name"]]["clear_btn"].visible = model.overrides.has(p["name"])

func _build_buttons(vbox: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	var presets_dir := ProjectSettings.globalize_path("res://presets")
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(func(): _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, presets_dir, func(path):
		var err: Error = model.save_to(path)
		if err != OK:
			push_error("save failed: " + str(err))))
	var load_b := Button.new()
	load_b.text = "Load"
	load_b.pressed.connect(func(): _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, presets_dir, func(path):
		var res: Dictionary = PresetIO.load_preset(path, model.get_schema(), model.model_name())
		if res["ok"]:
			model.adopt_preset(res["preset"])
			model.resolve_and_restart()
			_refresh_all()
		else:
			push_error(res["error"])))
	var restart := Button.new()
	restart.text = "Restart"
	restart.pressed.connect(func():
		model.resolve_and_restart()
		_hint.visible = false)
	for b in [save, load_b, restart]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	vbox.add_child(row)

func _file_dialog(mode: FileDialog.FileMode, dir: String, cb: Callable) -> void:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.current_dir = dir
	fd.filters = PackedStringArray(["*.json"])
	fd.file_selected.connect(func(p):
		cb.call(p)
		fd.queue_free())
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(800, 600))

func _refresh_param_values() -> void:
	for p in model.get_schema()["params"]:
		var entry: Dictionary = _param_rows[p["name"]]
		(entry["set_value"] as Callable).call(model.params[p["name"]])
		entry["clear_btn"].visible = model.overrides.has(p["name"])

func _refresh_all() -> void:
	for m_name in _macro_sliders:
		_macro_sliders[m_name]["slider"].set_value_no_signal(model.macros[m_name])
		_macro_sliders[m_name]["val"].text = "%.2f" % float(model.macros[m_name])
	_seed_edit.text = str(model.seed_value)
	_refresh_param_values()
	_hint.visible = false

func _process(delta: float) -> void:
	# Mirror director-driven macro drift into the UI (4 Hz, matching SimModel's
	# apply cadence). set_value_no_signal avoids re-triggering rebase; sliders
	# mid-drag and overridden params are left alone so user edits aren't yanked.
	if model == null or model.director == null or not model.director.enabled:
		return
	_drift_acc += delta
	if _drift_acc < 0.25:
		return
	_drift_acc = 0.0
	for m_name in _macro_sliders:
		var entry: Dictionary = _macro_sliders[m_name]
		if entry["dragging"]:
			continue
		var v := float(model.macros[m_name])
		entry["slider"].set_value_no_signal(v)
		entry["val"].text = "%.2f" % v
	for p in model.get_schema()["params"]:
		var p_name: String = p["name"]
		if not model.overrides.has(p_name) and model.params.has(p_name):
			(_param_rows[p_name]["set_value"] as Callable).call(model.params[p_name])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_root.visible = not _root.visible
