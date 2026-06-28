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
var _drag := false

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

static func frac(v: float, lo: float, hi: float) -> float:
	return clampf((v - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)

static func angle(f: float) -> float:
	return deg_to_rad(135.0 + 270.0 * f)  # 270deg sweep, gap at bottom

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	draw_circle(c, r, Color(0.11, 0.13, 0.19))
	draw_arc(c, r, angle(0.0), angle(1.0), 48, Color(0.24, 0.29, 0.41), 2.0)
	if not is_nan(live_v):
		var lf := frac(live_v, min_v, max_v)
		draw_arc(c, r, angle(0.0), angle(lf), 48, ring_color, 3.0)
		draw_circle(c + Vector2.from_angle(angle(lf)) * r, 3.5, ring_color)
	var a := angle(frac(value, min_v, max_v))
	draw_line(c, c + Vector2.from_angle(a) * (r - 2.0), Color(0.88, 0.92, 0.97), 2.0)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and ev.double_click:
			value = default_v
			value_changed.emit(value)
			queue_redraw()
		else:
			_drag = ev.pressed
	elif ev is InputEventMouseMotion and _drag:
		var step := (max_v - min_v) / 200.0
		if ev.shift_pressed:
			step *= 0.2
		value = clampf(value - ev.relative.y * step, min_v, max_v)
		value_changed.emit(value)
		queue_redraw()
