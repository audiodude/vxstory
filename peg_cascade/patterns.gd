extends RefCounted
# Pure pattern-position generators for peg_cascade's morphing playfield.
# positions(pattern, n) returns EXACTLY n positions for pattern 0 (hex
# lattice), 1 (concentric rings) or 2 (radial spokes), sorted by polar angle
# about the board center (radius tiebreak) so index i in one pattern glides
# to a coherent partner in the next. Deterministic: no RNG, no scene access.

const CENTER := Vector2(960, 620)

static func positions(pattern: int, n: int) -> PackedVector2Array:
	var pts: Array
	match posmod(pattern, 3):
		0: pts = _hex(n)
		1: pts = _rings(n)
		_: pts = _spokes(n)
	pts.sort_custom(_angle_sort)
	return PackedVector2Array(pts)

static func _angle_sort(a: Vector2, b: Vector2) -> bool:
	var oa := a - CENTER
	var ob := b - CENTER
	var aa := oa.angle()
	var ab := ob.angle()
	if absf(aa - ab) > 0.0001:
		return aa < ab
	return oa.length_squared() < ob.length_squared()

static func _hex(n: int) -> Array:
	# Staggered rows filling x 240-1680, y 300-980. Every row is centered on
	# x=960; full odd rows shift half a column (the stagger). The final
	# partial row is centered too, so the lattice never looks ragged.
	var cols := maxi(3, int(round(sqrt(n * 1440.0 / 680.0))))
	var rows := ceili(float(n) / float(cols))
	var dx := 1440.0 / float(cols)
	var dy := 680.0 / float(maxi(rows - 1, 1))
	var out := []
	var left := n
	for r in rows:
		var count := mini(cols, left)
		var stagger := dx * 0.5 if (r % 2 == 1 and count == cols) else 0.0
		var x0 := 960.0 - dx * float(count - 1) * 0.5 + stagger
		var y := (300.0 + dy * float(r)) if rows > 1 else 640.0
		for j in count:
			out.append(Vector2(x0 + dx * float(j), y))
		left -= count
	return out

static func _rings(n: int) -> Array:
	# Concentric ellipses about CENTER; pegs allocated per ring proportional
	# to its vertical radius (~circumference); outermost ring absorbs the
	# rounding remainder. Ring k is phase-offset so seams don't align.
	var rings := clampi(int(round(sqrt(float(n) / 6.0))), 2, 6)
	var rys: Array = []
	var total := 0.0
	for k in rings:
		var ry := 110.0 + 250.0 * (float(k) / float(maxi(rings - 1, 1)))
		rys.append(ry)
		total += ry
	var out := []
	var left := n
	for k in rings:
		var count := left
		if k < rings - 1:
			count = mini(int(round(float(n) * float(rys[k]) / total)), left)
		for j in count:
			var a := TAU * float(j) / float(maxi(count, 1)) + 0.35 * float(k)
			out.append(CENTER + Vector2(cos(a) * float(rys[k]) * 1.5, sin(a) * float(rys[k])))
		left -= count
	return out

static func _spokes(n: int) -> Array:
	# S evenly-angled spokes; each a line of pegs from inner radius 100 to
	# outer 360, elliptically stretched. First n % S spokes get one extra peg.
	var spokes := clampi(int(round(float(n) / 10.0)), 6, 20)
	var base := floori(float(n) / float(spokes))
	var extra := n % spokes
	var out := []
	for si in spokes:
		var count := base + (1 if si < extra else 0)
		if count == 0:
			continue
		var a := TAU * float(si) / float(spokes)
		var dir := Vector2(cos(a) * 1.5, sin(a))
		for j in count:
			var r := 100.0 + 260.0 * (float(j) / float(maxi(count - 1, 1)))
			out.append(CENTER + dir * r)
	return out
