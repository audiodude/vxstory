extends CanvasLayer
# Root of the visual Designer. Builds a BasesPanel + a SourceCard per source from
# the model's adopted scene, and writes scene.json (debounced) on any edit so the
# Phase 1 preview hot-reloads. Reuses the model's schema (get_schema()).
# Transport (▶ toggle + HSlider scrub) drives a per-frame ModStack clock and
# animates the bases macro knobs via Knob.set_live (Ableton-style).

const PresetIO = preload("res://core/preset_io.gd")
const BasesPanel = preload("res://core/designer/bases_panel.gd")
const SourceCard = preload("res://core/designer/source_card.gd")

var model
var _bases: BasesPanel
var _cards := []   # [{kind, idx, card}]
var _save_timer: Timer
var _mod
var _t := 0.0
var _playing := false
var _scrub: HSlider
var _macro_knobs := {}  # name -> Knob   (populated from BasesPanel)

func setup(p_model) -> void:
	model = p_model
	var win := get_window()
	if win != null:
		# Designer reflows on resize; the models' project keeps fixed-aspect
		# letterbox for renders, so override it here (this process only).
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.15
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	_build()

func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := Label.new()
	title.text = "DESIGNER · %s · %s" % [model.model_name(), model.preset_path]
	title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	col.add_child(title)

	_bases = BasesPanel.new()
	_bases.setup(model.get_schema(), model.macros, model.overrides)
	_bases.changed.connect(_on_changed)
	col.add_child(_framed(_bases))

	_macro_knobs = _bases.macro_knobs()
	var tr := HBoxContainer.new()
	var play := Button.new()
	play.text = "▶"
	play.toggle_mode = true
	play.toggled.connect(func(on): _playing = on)
	tr.add_child(play)
	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.001
	_scrub.custom_minimum_size = Vector2(240, 0)
	_scrub.value_changed.connect(func(f): _t = f * maxf(model.duration_sec, 0.0001))
	tr.add_child(_scrub)
	col.add_child(tr)
	_mod = load("res://core/modulation.gd").from_config(model.modulators_cfg)

	var slab := Label.new()
	slab.text = "SOURCES"
	slab.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	col.add_child(slab)

	var cfg: Dictionary = model.modulators_cfg
	for kind in ["tween", "lfo", "envelope"]:
		for i in cfg.get(kind, []).size():
			var card_kind: String = "env" if kind == "envelope" else kind
			var card = SourceCard.new()
			card.setup(card_kind, cfg[kind][i], model.get_schema())
			card.changed.connect(_on_changed)
			col.add_child(_framed(card))
			_cards.append({"kind": kind, "card": card})

func _on_changed() -> void:
	_save_timer.start()
	_mod = load("res://core/modulation.gd").from_config(current_scene()["modulators"])

func _process(delta: float) -> void:
	if _mod == null or not _mod.enabled:
		return
	if _playing:
		_t = fmod(_t + delta, maxf(model.duration_sec, 0.0001))
		_scrub.set_value_no_signal(_t / maxf(model.duration_sec, 0.0001))
	_mod.t = _t
	var off: Dictionary = _mod.offsets()
	var live: Dictionary = live_macro_values(model.get_schema(), _bases.macro_values(), off)
	for name in _macro_knobs:
		_macro_knobs[name].set_live(float(live.get(name, 0.0)))

func current_scene() -> Dictionary:
	var mods := {}
	for c in _cards:
		mods.get_or_add(c["kind"], [])
		mods[c["kind"]].append(c["card"].to_config())
	return {
		"macros": _bases.macro_values(),
		"overrides": _bases.override_values(),
		"modulators": mods,
	}

func save_now() -> void:
	if model.preset_path == "":
		return
	var s := current_scene()
	PresetIO.save_preset(model.preset_path, model.model_name(), model.seed_value, model.duration_sec, s["macros"], s["overrides"], model.jitter, model.director_cfg, s["modulators"])

static func live_macro_values(schema: Dictionary, macros: Dictionary, offsets: Dictionary) -> Dictionary:
	var out := {}
	for m in schema["macros"]:
		out[m["name"]] = clampf(float(macros.get(m["name"], m["default"])) + float(offsets.get(m["name"], 0.0)), 0.0, 1.0)
	return out

func _framed(node: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.065, 0.10)
	sb.border_color = Color(0.16, 0.19, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(node)
	return panel
