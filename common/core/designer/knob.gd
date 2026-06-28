extends Control
# Ableton-style rotary knob. Vertical-drag changes value; Shift = fine;
# double-click resets to default. Pointer shows the set value; an optional bright
# ring shows a live (modulated) value. Fixed-size; emits value_changed(v).

signal value_changed(value: float)

var min_v := 0.0
var max_v := 1.0
var value := 0.0
var default_v := 0.0
var live_v := NAN  # NAN -> no ring
var ring_color := Color(0.5, 0.8, 1.0)
var bipolar := false  # amount knobs: unity 0 at 12 o'clock, fill from center
var steps: Array = []  # when non-empty: snap to these discrete values (even angular spacing)
var _step_idx := 0
var _drag := false
var _drag_accum := 0.0

func setup(p_min: float, p_max: float, p_value: float, p_default: float, p_ring := Color(0.5, 0.8, 1.0)) -> void:
	min_v = p_min
	max_v = p_max
	value = clampf(p_value, p_min, p_max)
	default_v = p_default
	ring_color = p_ring
	custom_minimum_size = Vector2(40, 40)
	queue_redraw()

func set_live(v: float) -> void:
	live_v = v
	queue_redraw()

func set_bipolar(b: bool) -> void:
	bipolar = b
	queue_redraw()

func set_steps(values: Array, current: float) -> void:
	steps = values
	if not steps.is_empty():
		_step_idx = _nearest_step(current)
		value = float(steps[_step_idx])
	queue_redraw()

func _nearest_step(v: float) -> int:
	var best := 0
	var bestd := INF
	for i in steps.size():
		var d: float = absf(float(steps[i]) - v)
		if d < bestd:
			bestd = d
			best = i
	return best

func _step_frac() -> float:
	if steps.size() < 2:
		return 0.0
	return float(_step_idx) / float(steps.size() - 1)

static func frac(v: float, lo: float, hi: float) -> float:
	return clampf((v - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)

static func angle(f: float) -> float:
	return deg_to_rad(135.0 + 270.0 * f)  # 270deg sweep, gap at bottom

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	draw_circle(c, r, Color(0.11, 0.13, 0.19), true, -1.0, true)
	draw_arc(c, r, angle(0.0), angle(1.0), 64, Color(0.24, 0.29, 0.41), 2.0, true)
	var vf := _step_frac() if not steps.is_empty() else frac(value, min_v, max_v)
	var origin := 0.5 if bipolar else 0.0
	if bipolar:
		var ta := angle(0.5)  # unity tick at 12 o'clock
		draw_line(c + Vector2.from_angle(ta) * (r - 4.0), c + Vector2.from_angle(ta) * (r + 2.0), Color(0.55, 0.6, 0.72), 1.5, true)
	draw_arc(c, r, angle(origin), angle(vf), 64, ring_color.darkened(0.15), 2.5, true)
	if not is_nan(live_v):
		var lf := frac(live_v, min_v, max_v)
		draw_arc(c, r, angle(origin), angle(lf), 64, ring_color, 3.0, true)
		draw_circle(c + Vector2.from_angle(angle(lf)) * r, 3.5, ring_color, true, -1.0, true)
	var a := angle(vf)
	draw_line(c, c + Vector2.from_angle(a) * (r - 2.0), Color(0.88, 0.92, 0.97), 2.0, true)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and ev.double_click:
			if not steps.is_empty():
				_step_idx = _nearest_step(default_v)
				value = float(steps[_step_idx])
			else:
				value = default_v
			value_changed.emit(value)
			queue_redraw()
		else:
			_drag = ev.pressed
			_drag_accum = 0.0
	elif ev is InputEventMouseMotion and _drag:
		if not steps.is_empty():
			_drag_accum += -ev.relative.y
			var per := 14.0  # pixels per discrete step
			var moved := false
			while _drag_accum >= per and _step_idx < steps.size() - 1:
				_step_idx += 1
				_drag_accum -= per
				moved = true
			while _drag_accum <= -per and _step_idx > 0:
				_step_idx -= 1
				_drag_accum += per
				moved = true
			if moved:
				value = float(steps[_step_idx])
				value_changed.emit(value)
				queue_redraw()
		else:
			var step := (max_v - min_v) / 200.0
			if ev.shift_pressed:
				step *= 0.2
			value = clampf(value - ev.relative.y * step, min_v, max_v)
			value_changed.emit(value)
			queue_redraw()
