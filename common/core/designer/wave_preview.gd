extends Control
# Draws a signal as a polyline. The sampler maps x in [0,1] -> a value; values are
# scaled from [lo,hi] into the control height (hi at top). Flexes to its width.

var _cb: Callable
var _lo := -1.0
var _hi := 1.0
var _color := Color(0.5, 0.8, 1.0)

func set_sampler(cb: Callable, lo: float, hi: float, color := Color(0.5, 0.8, 1.0)) -> void:
	_cb = cb
	_lo = lo
	_hi = hi
	_color = color
	custom_minimum_size = Vector2(0, 44)
	queue_redraw()

static func points(cb: Callable, lo: float, hi: float, w: float, h: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if n < 2 or not cb.is_valid():
		return out
	for i in n:
		var x01 := float(i) / float(n - 1)
		var v: float = cb.call(x01)
		var f := clampf((v - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)
		out.append(Vector2(x01 * w, lerpf(h, 0.0, f)))
	return out

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.08), true)
	if not _cb.is_valid():
		return
	var pts := points(_cb, _lo, _hi, size.x, size.y, maxi(int(size.x / 2.0), 2))
	if pts.size() >= 2:
		draw_polyline(pts, _color, 2.0, true)
