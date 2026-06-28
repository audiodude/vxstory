extends VBoxContainer
# Editor for one modulation source (tween | lfo | env). Preview-on-top, controls
# below, then source-centric routing rows. Holds an editable copy of the source;
# to_config() returns it in scene format. Emits `changed` on any edit.

const Knob = preload("res://core/designer/knob.gd")
const WavePreview = preload("res://core/designer/wave_preview.gd")
const MS = preload("res://core/mod_sources.gd")
# OSC period as a ratio of the run length; non-linear, evenly-spaced steps on the dial.
const OSC_PERIOD_RATIOS := [0.01, 0.15, 0.25, 0.4, 0.5, 0.625, 0.75, 1.0, 1.1, 1.25, 1.33, 1.5, 1.75, 2.0, 2.5, 3.0, 5.0, 10.0]

signal changed()

var kind := ""
var src := {}
var schema := {}
var _prev  # WavePreview, set in _build
var _duration := 300.0  # run length; OSC period dial is a ratio of this

func setup(p_kind: String, p_src: Dictionary, p_schema: Dictionary, p_duration := 300.0) -> void:
	kind = p_kind
	src = p_src.duplicate(true)
	schema = p_schema
	_duration = maxf(p_duration, 0.0001)
	add_theme_constant_override("separation", 6)
	_build()

func to_config() -> Dictionary:
	return src

func set_time(t: float) -> void:
	# move the preview playhead to run-time t (tween: progress over its secs; lfo: wrap the window)
	if _prev == null:
		return
	match kind:
		"tween":
			var secs: float = maxf(float(src.get("secs", 1.0)), 0.0001)
			_prev.set_playhead(clampf(t / secs, 0.0, 1.0))
		"lfo":
			var span := 0.0
			for o in _runtime_oscs(src.get("oscillators", [])):
				span = maxf(span, float(o["period"]))
			span = maxf(span * 2.0, 0.0001)
			_prev.set_playhead(fposmod(t, span) / span)
		_:
			pass

func _color() -> Color:
	match kind:
		"tween": return Color(1.0, 0.8, 0.2)
		"lfo": return Color(0.4, 1.0, 0.7)
		_: return Color(0.69, 0.49, 1.0)

func _build() -> void:
	var hdr := Label.new()
	hdr.text = "%s · %s" % [kind.to_upper(), str(src.get("name", kind))]
	hdr.add_theme_color_override("font_color", _color())
	add_child(hdr)

	var prev := WavePreview.new()
	prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(prev)
	_wire_preview(prev)
	_prev = prev

	match kind:
		"tween":
			var ctrl := HBoxContainer.new()
			ctrl.add_theme_constant_override("separation", 10)
			add_child(ctrl)
			ctrl.add_child(_knob("secs", src, "secs", 1.0, 600.0))
			ctrl.add_child(_knob("from", src, "from", 0.0, 1.0))
			ctrl.add_child(_knob("to", src, "to", 0.0, 1.0))
			var curve_box := VBoxContainer.new()
			curve_box.alignment = BoxContainer.ALIGNMENT_CENTER
			var curve_items := ["linear", "ease_in", "ease_out", "smooth"]
			var curve_opts := OptionButton.new()
			for c in curve_items:
				curve_opts.add_item(c)
			var ci := curve_items.find(str(src.get("curve", "linear")))
			curve_opts.selected = ci if ci >= 0 else 0
			curve_opts.item_selected.connect(func(idx):
				src["curve"] = curve_items[idx]
				_wire_preview(_prev)
				changed.emit())
			curve_box.add_child(curve_opts)
			var curve_lbl := Label.new()
			curve_lbl.text = "curve"
			curve_lbl.add_theme_font_size_override("font_size", 10)
			curve_box.add_child(curve_lbl)
			ctrl.add_child(curve_box)
		"lfo":
			var oscs := HBoxContainer.new()
			oscs.add_theme_constant_override("separation", 8)
			add_child(oscs)
			for i in src.get("oscillators", []).size():
				oscs.add_child(_osc_subcard(i))
		"env":
			var ctrl := HBoxContainer.new()
			ctrl.add_theme_constant_override("separation", 10)
			add_child(ctrl)
			ctrl.add_child(_knob("attack", src, "attack", 0.0, 1.0))
			ctrl.add_child(_knob("decay", src, "decay", 0.0, 2.0))
			ctrl.add_child(_knob("peak", src, "peak", 0.0, 2.0))
			var ev_lbl := Label.new()
			ev_lbl.text = "on: " + str(src.get("event", "?"))
			ev_lbl.add_theme_color_override("font_color", _color())
			ev_lbl.add_theme_font_size_override("font_size", 10)
			ctrl.add_child(ev_lbl)

	var routes := HFlowContainer.new()
	routes.add_theme_constant_override("h_separation", 10)
	routes.add_theme_constant_override("v_separation", 6)
	add_child(routes)
	for tg in src.get("targets", []):
		var chip := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.05, 0.065, 0.10)
		csb.border_color = Color(0.14, 0.18, 0.27)
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(14)
		csb.content_margin_left = 12
		csb.content_margin_right = 7
		csb.content_margin_top = 2
		csb.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", csb)
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		chip.add_child(item)
		var lab := Label.new()
		lab.text = "→ %s" % str(tg.get("to", "?"))
		item.add_child(lab)
		var k = Knob.new()
		k.setup(-10.0, 10.0, float(tg.get("amount", 0.0)), float(tg.get("amount", 0.0)), _color())
		k.set_bipolar(true)
		k.custom_minimum_size = Vector2(30, 30)
		k.value_changed.connect(func(v):
			tg["amount"] = v
			changed.emit())
		item.add_child(k)
		routes.add_child(chip)

func _knob(_path: String, holder: Dictionary, key: String, lo: float, hi: float) -> VBoxContainer:
	return _make_labeled_knob(holder, key, lo, hi, key, false)

func _make_labeled_knob(holder: Dictionary, key: String, lo: float, hi: float, label: String, bipolar: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var k = Knob.new()
	k.setup(lo, hi, float(holder.get(key, 0.0)), float(holder.get(key, 0.0)), _color())
	if bipolar:
		k.set_bipolar(true)
	k.value_changed.connect(func(v):
		holder[key] = v
		if _prev != null:
			_wire_preview(_prev)
		changed.emit())
	box.add_child(k)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)
	return box

func _osc_subcard(i: int) -> PanelContainer:
	var o = src["oscillators"][i]
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09)
	sb.border_color = Color(0.16, 0.19, 0.29)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var hl := Label.new()
	hl.text = "OSC %d" % (i + 1)
	hl.add_theme_font_size_override("font_size", 10)
	hl.add_theme_color_override("font_color", Color(0.74, 0.82, 0.95))
	box.add_child(hl)
	var mini := WavePreview.new()
	mini.custom_minimum_size = Vector2(130, 22)
	box.add_child(mini)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	box.add_child(row)
	var shape_items := ["sine", "triangle", "saw", "square"]
	var shape_opts := OptionButton.new()
	for s_item in shape_items:
		shape_opts.add_item(s_item)
	var si := shape_items.find(str(o.get("shape", "sine")))
	shape_opts.selected = si if si >= 0 else 0
	shape_opts.item_selected.connect(func(idx):
		o["shape"] = shape_items[idx]
		_wire_osc_mini(mini, o)
		_wire_preview(_prev)
		changed.emit())
	row.add_child(shape_opts)
	row.add_child(_osc_period_knob(o, mini))
	row.add_child(_osc_knob(o, "amount", 0.0, 1.0, mini))
	_wire_osc_mini(mini, o)
	return panel

func _osc_knob(o: Dictionary, key: String, lo: float, hi: float, mini) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var k = Knob.new()
	k.setup(lo, hi, float(o.get(key, 0.0)), float(o.get(key, 0.0)), _color())
	k.value_changed.connect(func(v):
		o[key] = v
		_wire_osc_mini(mini, o)
		if _prev != null:
			_wire_preview(_prev)
		changed.emit())
	box.add_child(k)
	var l := Label.new()
	l.text = key
	l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)
	return box

func _osc_period_knob(o: Dictionary, mini) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var ratio := float(o.get("period_sec", 30.0)) / _duration
	var k = Knob.new()
	k.setup(float(OSC_PERIOD_RATIOS[0]), float(OSC_PERIOD_RATIOS[-1]), ratio, ratio, _color())
	k.set_steps(OSC_PERIOD_RATIOS, ratio)
	var lbl := Label.new()
	lbl.text = _fmt_ratio(k.value)
	lbl.add_theme_font_size_override("font_size", 10)
	k.value_changed.connect(func(r):
		o["period_sec"] = r * _duration
		lbl.text = _fmt_ratio(r)
		_wire_osc_mini(mini, o)
		if _prev != null:
			_wire_preview(_prev)
		changed.emit())
	box.add_child(k)
	box.add_child(lbl)
	return box

static func _fmt_ratio(r: float) -> String:
	var s := "%.3f" % r
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	return s

func _wire_osc_mini(mini, o: Dictionary) -> void:
	var period: float = maxf(float(o.get("period_sec", 30.0)), 0.0001)
	var shape := str(o.get("shape", "sine"))
	var phase := float(o.get("phase_deg", 0.0))
	mini.set_sampler(func(x): return MS.osc(x * period * 2.0, period, shape, phase), -1.0, 1.0, _color())

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
