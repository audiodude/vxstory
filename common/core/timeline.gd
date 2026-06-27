extends CanvasLayer
# Read-only scrub timeline for preview mode. Draws each modulation source as the
# curve/motion it produces over the render duration, with a draggable playhead;
# dragging calls model.scrub_to(t) (character-at-t) and flashes a wipe overlay.
# Shown only when the scene has modulators.

const MS = preload("res://core/mod_sources.gd")
const STRIP_H := 150.0

var model
var _strip: Control
var _wipe: Control
var _wipe_alpha := 0.0

func _init(p_model) -> void:
	model = p_model
	layer = 90  # below the tweak panel (100), above the render
	_wipe = Control.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.draw.connect(_draw_wipe)
	add_child(_wipe)
	_strip = Control.new()
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_strip.offset_top = -STRIP_H
	_strip.draw.connect(_draw_strip)
	_strip.gui_input.connect(_on_strip_input)
	add_child(_strip)

static func time_to_x(t: float, dur: float, w: float) -> float:
	return clampf(t / maxf(dur, 0.0001), 0.0, 1.0) * w

static func value_to_frac(v: float, lo: float, hi: float) -> float:
	return clampf((v - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)

func _enabled() -> bool:
	return model != null and model.mod_stack != null and model.mod_stack.enabled

func _process(delta: float) -> void:
	var on := _enabled()
	_strip.visible = on
	_wipe.visible = on and _wipe_alpha > 0.0
	if not on:
		return
	if _wipe_alpha > 0.0:
		_wipe_alpha = maxf(_wipe_alpha - delta * 3.0, 0.0)
		_wipe.queue_redraw()
	_strip.queue_redraw()

func _draw_wipe() -> void:
	if _wipe_alpha <= 0.0:
		return
	_wipe.draw_rect(Rect2(Vector2.ZERO, _wipe.size), Color(1, 1, 1, 0.35 * _wipe_alpha), true)

func _draw_strip() -> void:
	var w := _strip.size.x
	var h := _strip.size.y
	var dur: float = maxf(model.duration_sec, 0.0001)
	var font := ThemeDB.fallback_font
	_strip.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.66), true)
	_strip.draw_line(Vector2(0, 0), Vector2(w, 0), Color(0.4, 0.6, 0.9, 0.8), 2.0)

	var lanes := []
	for tw in model.mod_stack.tweens:
		lanes.append({"kind": "tween", "src": tw})
	for lf in model.mod_stack.lfos:
		lanes.append({"kind": "lfo", "src": lf})
	for en in model.mod_stack.envelopes:
		lanes.append({"kind": "env", "src": en})

	var px := time_to_x(model.mod_stack.t, dur, w)  # playhead x
	var n := maxi(lanes.size(), 1)
	var lane_h := (h - 22.0) / float(n)
	for i in lanes.size():
		var top := 4.0 + i * lane_h
		var bot := top + lane_h - 4.0
		var L = lanes[i]
		var src = L["src"]
		var col := Color(0.5, 0.8, 1.0)
		var pts := PackedVector2Array()
		var cur_frac := 0.0
		match L["kind"]:
			"tween":
				col = Color(1.0, 0.8, 0.2)
				for sx in range(0, int(w), 3):
					var t := (float(sx) / w) * dur
					pts.append(Vector2(sx, lerpf(bot, top, clampf(MS.tween(t, src["secs"], src["curve"], src["from"], src["to"]), 0.0, 1.0))))
				cur_frac = clampf(MS.tween(model.mod_stack.t, src["secs"], src["curve"], src["from"], src["to"]), 0.0, 1.0)
			"lfo":
				col = Color(0.4, 1.0, 0.7)
				for sx in range(0, int(w), 3):
					var t := (float(sx) / w) * dur
					pts.append(Vector2(sx, lerpf(bot, top, (MS.lfo(t, src["rate"], src["shape"], src["phase"]) + 1.0) * 0.5)))
				cur_frac = (MS.lfo(model.mod_stack.t, src["rate"], src["shape"], src["phase"]) + 1.0) * 0.5
			"env":
				col = Color(1.0, 0.4, 0.6)
				var active: bool = src["instances"].size() > 0
				_strip.draw_rect(Rect2(0, top, w, lane_h - 4.0), Color(col.r, col.g, col.b, 0.16 if active else 0.05), true)
		if pts.size() >= 2:
			_strip.draw_polyline(pts, col, 1.5)
		if L["kind"] != "env":
			# live "what it does now" dot riding the curve at the playhead
			_strip.draw_circle(Vector2(px, lerpf(bot, top, cur_frac)), 4.0, Color.WHITE)
		_strip.draw_string(font, Vector2(6, top + 14), str(src.get("name", L["kind"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1.0, 0.7))

	# playhead + time
	_strip.draw_line(Vector2(px, 0), Vector2(px, h), Color(1, 1, 1, 0.9), 2.0)
	var tt := int(model.mod_stack.t)
	_strip.draw_string(font, Vector2(clampf(px + 5.0, 0.0, w - 56.0), 16), "%d:%02d" % [tt / 60, tt % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _on_strip_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_scrub_at(ev.position.x)
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_scrub_at(ev.position.x)

func _scrub_at(x: float) -> void:
	if not _enabled():
		return
	var dur: float = maxf(model.duration_sec, 0.0001)
	var t := clampf(x / maxf(_strip.size.x, 1.0), 0.0, 1.0) * dur
	model.scrub_to(t)
	_wipe_alpha = 1.0
	_wipe.queue_redraw()
