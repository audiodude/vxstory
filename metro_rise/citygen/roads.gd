extends RefCounted
# Seeded street network: a jittered arterial grid plus 1-2 diagonal boulevards
# walked node-to-node across it. Pure logic — no nodes, no rendering.
#
# build(rng, params) -> {
#   "segments": [{id, a: Vector2, b: Vector2, na, nb, kind: "street"|"blvd",
#                 diag: bool, ring: int, width: float}],
#   "nodes":    [{id, pos: Vector2, segs: [int], ring: int}],
#   "xs": PackedFloat32Array, "ys": PackedFloat32Array,
#   "kx": Array[String], "ky": Array[String],   # per-line kinds
#   "vseg": {"i:j": id}, "hseg": {"i:j": id} }  # grid-cell -> segment lookup

const RINGS := 6
const W_STREET := 12.0
const W_BLVD := 24.0

static func build(rng: RandomNumberGenerator, params: Dictionary) -> Dictionary:
	var r: float = params["city_radius"]
	var xs := _lines(rng, params)
	var ys := _lines(rng, params)
	var kx := _kinds(rng, xs.size())
	var ky := _kinds(rng, ys.size())

	var nodes: Array = []
	var grid := {}  # "i,j" -> node id
	for i in xs.size():
		for j in ys.size():
			grid["%d,%d" % [i, j]] = nodes.size()
			var pos := Vector2(xs[i], ys[j])
			nodes.append({"id": nodes.size(), "pos": pos, "segs": [], "ring": _ring(pos, r)})

	var segments: Array = []
	var vseg := {}
	var hseg := {}
	for i in xs.size():
		for j in ys.size() - 1:
			vseg["%d:%d" % [i, j]] = _add_seg(segments, nodes, grid["%d,%d" % [i, j]], grid["%d,%d" % [i, j + 1]], kx[i], false)
	for j in ys.size():
		for i in xs.size() - 1:
			hseg["%d:%d" % [i, j]] = _add_seg(segments, nodes, grid["%d,%d" % [i, j]], grid["%d,%d" % [i + 1, j]], ky[j], false)
	for s in segments:
		s["ring"] = _ring((s["a"] + s["b"]) * 0.5, r)

	for k in int(params.get("boulevard_count", 2)):
		_walk_diagonal(rng, segments, nodes, grid, xs, ys, r)

	return {"segments": segments, "nodes": nodes, "xs": xs, "ys": ys,
			"kx": kx, "ky": ky, "vseg": vseg, "hseg": hseg}

static func _lines(rng: RandomNumberGenerator, params: Dictionary) -> PackedFloat32Array:
	var r: float = params["city_radius"]
	var out := PackedFloat32Array()
	var pos := -r + rng.randf_range(0.0, float(params["block_max"]) * 0.5)
	while pos <= r:
		out.append(pos)
		pos += rng.randf_range(float(params["block_min"]), float(params["block_max"]))
	return out

static func _kinds(rng: RandomNumberGenerator, n: int) -> Array:
	var kinds: Array = []
	var until_blvd := 1 + (rng.randi() % 3)
	for i in n:
		until_blvd -= 1
		if until_blvd <= 0:
			kinds.append("blvd")
			until_blvd = 3 + (rng.randi() % 2)
		else:
			kinds.append("street")
	return kinds

static func _ring(p: Vector2, r: float) -> int:
	return clampi(int(maxf(absf(p.x), absf(p.y)) / r * float(RINGS)), 0, RINGS - 1)

static func _add_seg(segments: Array, nodes: Array, na: int, nb: int, kind: String, diag: bool) -> int:
	var id := segments.size()
	segments.append({
		"id": id, "a": nodes[na]["pos"], "b": nodes[nb]["pos"], "na": na, "nb": nb,
		"kind": kind, "diag": diag, "ring": 0,
		"width": W_BLVD if kind == "blvd" else W_STREET,
	})
	nodes[na]["segs"].append(id)
	nodes[nb]["segs"].append(id)
	return id

static func _walk_diagonal(rng: RandomNumberGenerator, segments: Array, nodes: Array, grid: Dictionary, xs: PackedFloat32Array, ys: PackedFloat32Array, r: float) -> void:
	# A straight target line through a near-center point; greedily hop grid nodes
	# (+1 in x, -1/0/+1 in y) toward it. (+1,0) hops upgrade the existing grid
	# segment to boulevard; (+1,±1) hops add new diagonal segments.
	var center := Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25)) * r
	var slope := rng.randf_range(0.35, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0)
	var line_dir := Vector2(1.0, slope).normalized()

	var j := _nearest_j(ys, center.y + (xs[0] - center.x) * slope)
	var i := 0
	while i < xs.size() - 1:
		var best_dj := 0
		var best_d := INF
		for dj in [-1, 0, 1]:
			var jn: int = j + dj
			if jn < 0 or jn >= ys.size():
				continue
			var p := Vector2(xs[i + 1], ys[jn])
			var d := absf((p - center).cross(line_dir))
			if d < best_d:
				best_d = d
				best_dj = dj
		var a_id: int = grid["%d,%d" % [i, j]]
		var b_id: int = grid["%d,%d" % [i + 1, j + best_dj]]
		if best_dj == 0:
			_upgrade_between(segments, a_id, b_id)
		else:
			var sid := _add_seg(segments, nodes, a_id, b_id, "blvd", true)
			segments[sid]["ring"] = _ring((segments[sid]["a"] + segments[sid]["b"]) * 0.5, r)
		j += best_dj
		i += 1

static func _nearest_j(ys: PackedFloat32Array, y: float) -> int:
	var best := 0
	var best_d := INF
	for j in ys.size():
		var d := absf(ys[j] - y)
		if d < best_d:
			best_d = d
			best = j
	return best

static func _upgrade_between(segments: Array, na: int, nb: int) -> void:
	for s in segments:
		if not s["diag"] and ((s["na"] == na and s["nb"] == nb) or (s["na"] == nb and s["nb"] == na)):
			s["kind"] = "blvd"
			s["width"] = W_BLVD
			return
