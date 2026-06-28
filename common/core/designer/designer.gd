extends Control
# Root of the visual Designer. Builds a BasesPanel + a SourceCard per source from
# the model's adopted scene, and writes scene.json (debounced) on any edit so the
# Phase 1 preview hot-reloads. Reuses the model's schema (get_schema()).

const PresetIO = preload("res://core/preset_io.gd")
const BasesPanel = preload("res://core/designer/bases_panel.gd")
const SourceCard = preload("res://core/designer/source_card.gd")

var model
var _bases: BasesPanel
var _cards := []   # [{kind, idx, card}]
var _save_timer: Timer

func setup(p_model) -> void:
	model = p_model
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.15
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	_build()

func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "DESIGNER · %s · %s" % [model.model_name(), model.preset_path]
	title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	col.add_child(title)

	_bases = BasesPanel.new()
	_bases.setup(model.get_schema(), model.macros, model.overrides)
	_bases.changed.connect(_on_changed)
	col.add_child(_bases)

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
			col.add_child(card)
			_cards.append({"kind": kind, "card": card})

func _on_changed() -> void:
	_save_timer.start()

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
	PresetIO.save_preset(model.preset_path, model.model_name(), model.seed_value, model.duration_sec, s["macros"], s["overrides"], model.jitter, {}, s["modulators"])
