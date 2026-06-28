extends VBoxContainer
# Editor for one modulation source (tween | lfo | env). Preview-on-top, controls
# below, then source-centric routing rows. Holds an editable copy of the source;
# to_config() returns it in scene format. Emits `changed` on any edit.

const Knob = preload("res://core/designer/knob.gd")
const WavePreview = preload("res://core/designer/wave_preview.gd")
const MS = preload("res://core/mod_sources.gd")

signal changed()

var kind := ""
var src := {}
var schema := {}
var _knobs := {}  # path -> Knob (for later animation hooks if needed)

func setup(p_kind: String, p_src: Dictionary, p_schema: Dictionary) -> void:
	kind = p_kind
	src = p_src.duplicate(true)
	schema = p_schema
	add_theme_constant_override("separation", 6)
	_build()

func to_config() -> Dictionary:
	return src

func _color() -> Color:
	match kind:
		"tween": return Color(1.0, 0.8, 0.2)
		"lfo": return Color(0.4, 1.0, 0.7)
		_: return Color(1.0, 0.4, 0.6)

func _build() -> void:
	var hdr := Label.new()
	hdr.text = "%s · %s" % [kind.to_upper(), str(src.get("name", kind))]
	hdr.add_theme_color_override("font_color", _color())
	add_child(hdr)

	var prev := WavePreview.new()
	prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(prev)
	_wire_preview(prev)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 10)
	add_child(ctrl)
	match kind:
		"tween":
			ctrl.add_child(_knob("secs", src, "secs", 1.0, 600.0))
			ctrl.add_child(_knob("from", src, "from", 0.0, 1.0))
			ctrl.add_child(_knob("to", src, "to", 0.0, 1.0))
		"lfo":
			for i in src.get("oscillators", []).size():
				var o = src["oscillators"][i]
				ctrl.add_child(_knob("osc%d.period_sec" % i, o, "period_sec", 1.0, 120.0))
				ctrl.add_child(_knob("osc%d.amount" % i, o, "amount", 0.0, 1.0))
		"env":
			ctrl.add_child(_knob("attack", src, "attack", 0.0, 1.0))
			ctrl.add_child(_knob("decay", src, "decay", 0.0, 2.0))
			ctrl.add_child(_knob("peak", src, "peak", 0.0, 2.0))

	for tg in src.get("targets", []):
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = "→ %s" % str(tg.get("to", "?"))
		lab.custom_minimum_size = Vector2(160, 0)
		row.add_child(lab)
		row.add_child(_knob_for(tg, "amount", -10.0, 10.0, prev))
		add_child(row)

func _knob(_path: String, holder: Dictionary, key: String, lo: float, hi: float) -> VBoxContainer:
	return _make_labeled_knob(holder, key, lo, hi, key, null)

func _knob_for(holder: Dictionary, key: String, lo: float, hi: float, prev) -> VBoxContainer:
	return _make_labeled_knob(holder, key, lo, hi, key, prev)

func _make_labeled_knob(holder: Dictionary, key: String, lo: float, hi: float, label: String, prev) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var k = Knob.new()
	k.setup(lo, hi, float(holder.get(key, 0.0)), float(holder.get(key, 0.0)), _color())
	k.value_changed.connect(func(v):
		holder[key] = v
		if prev != null:
			_wire_preview(prev)
		changed.emit())
	box.add_child(k)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)
	return box

static func _runtime_oscs(scene_oscs: Array) -> Array:
	# scene format {period_sec, phase_deg} -> mod_sources runtime keys {period, phase}
	var rt := []
	for o in scene_oscs:
		rt.append({
			"period": float(o.get("period_sec", 30.0)),
			"shape": str(o.get("shape", "sine")),
			"phase": float(o.get("phase_deg", 0.0)),
			"amount": float(o.get("amount", 1.0)),
		})
	return rt

func _wire_preview(prev) -> void:
	match kind:
		"tween":
			var secs: float = maxf(float(src.get("secs", 1.0)), 0.0001)
			prev.set_sampler(func(x): return MS.tween(x * secs, secs, str(src.get("curve", "linear")), float(src.get("from", 0.0)), float(src.get("to", 1.0))), 0.0, 1.0, _color())
		"lfo":
			var oscs: Array = src.get("oscillators", [])
			var rt := _runtime_oscs(oscs)
			var span := 0.0
			for o in rt:
				span = maxf(span, float(o["period"]))
			span = maxf(span * 2.0, 0.0001)
			prev.set_sampler(func(x): return MS.lfo_value(x * span, rt), -1.0, 1.0, _color())
		"env":
			var dur: float = maxf(float(src.get("attack", 0.01)) + float(src.get("decay", 0.3)), 0.0001)
			prev.set_sampler(func(x): return MS.envelope(x * dur, float(src.get("attack", 0.01)), float(src.get("decay", 0.3)), float(src.get("peak", 1.0))), 0.0, maxf(float(src.get("peak", 1.0)), 0.0001), _color())
		_:
			pass
