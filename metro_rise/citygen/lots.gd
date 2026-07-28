extends RefCounted
# Blocks between grid lines -> districts -> seeded lot subdivision. Core blocks
# may pre-designate a merged multi-lot tower parcel (used only by era-3 entries).
# Pure logic — no nodes, no rendering.
#
# build(rng, roads, params) -> {
#   "blocks":  [{id, rect: Rect2, district, ring: int, gi: int, gj: int}],
#   "lots":    [{id, block, rect: Rect2, district, ring: int, front_seg, parcel}],
#   "parcels": [{id, lots: [int], rect: Rect2}] }

const SIDEWALK := 3.0
const RINGS := 6

static func build(rng: RandomNumberGenerator, roads: Dictionary, params: Dictionary) -> Dictionary:
	var r: float = params["city_radius"]
	var xs: PackedFloat32Array = roads["xs"]
	var ys: PackedFloat32Array = roads["ys"]
	var diags: Array = []
	for s in roads["segments"]:
		if s["diag"]:
			diags.append(s)

	var blocks: Array = []
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var inset_l := _half(roads["kx"][i]) + SIDEWALK
			var inset_r := _half(roads["kx"][i + 1]) + SIDEWALK
			var inset_b := _half(roads["ky"][j]) + SIDEWALK
			var inset_t := _half(roads["ky"][j + 1]) + SIDEWALK
			var rect := Rect2(xs[i] + inset_l, ys[j] + inset_b,
					xs[i + 1] - xs[i] - inset_l - inset_r, ys[j + 1] - ys[j] - inset_b - inset_t)
			if rect.size.x < 20.0 or rect.size.y < 20.0:
				continue
			var center := rect.get_center()
			if maxf(absf(center.x), absf(center.y)) > r:
				continue
			var d := center.length() / r
			var district := "core"
			if d >= 0.75:
				district = "industrial"
			elif d >= 0.45:
				district = "residential"
			elif d >= 0.22:
				district = "commercial"
			if district != "core" and rng.randf() < float(params["park_pct"]):
				district = "park"
			blocks.append({"id": blocks.size(), "rect": rect, "district": district,
					"ring": _ring(center, r), "gi": i, "gj": j})

	var lots: Array = []
	var parcels: Array = []
	for b in blocks:
		if b["district"] == "park":
			continue
		var rect: Rect2 = b["rect"]
		var target := rng.randf_range(30.0, 46.0)
		var nx := clampi(roundi(rect.size.x / target), 1, 6)
		var ny := clampi(roundi(rect.size.y / target), 1, 6)
		var cell := Vector2(rect.size.x / nx, rect.size.y / ny)
		var block_lots := {}  # "u,v" -> lot id
		for u in nx:
			for v in ny:
				if rng.randf() > float(params["lot_fill"]):
					continue
				var lrect := Rect2(rect.position + Vector2(u * cell.x, v * cell.y), cell)
				if _hits_diag(lrect, diags):
					continue
				var lid := lots.size()
				block_lots["%d,%d" % [u, v]] = lid
				lots.append({"id": lid, "block": b["id"], "rect": lrect,
						"district": b["district"], "ring": b["ring"],
						"front_seg": _front_seg(roads, b, lrect), "parcel": -1})
		if b["district"] == "core" and rng.randf() < float(params["tower_share"]) and block_lots.size() >= 2:
			_mark_parcel(rng, lots, parcels, block_lots, nx, ny)

	return {"blocks": blocks, "lots": lots, "parcels": parcels}

static func _half(kind: String) -> float:
	return 12.0 if kind == "blvd" else 6.0

static func _ring(p: Vector2, r: float) -> int:
	return clampi(int(maxf(absf(p.x), absf(p.y)) / r * float(RINGS)), 0, RINGS - 1)

static func _hits_diag(rect: Rect2, diags: Array) -> bool:
	for s in diags:
		var grown := rect.grow(s["width"] * 0.5 + SIDEWALK)
		if _seg_hits_rect(s["a"], s["b"], grown):
			return true
	return false

static func _seg_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var tl := rect.position
	var tr := rect.position + Vector2(rect.size.x, 0)
	var bl := rect.position + Vector2(0, rect.size.y)
	var br := rect.end
	for edge in [[tl, tr], [tr, br], [br, bl], [bl, tl]]:
		if Geometry2D.segment_intersects_segment(a, b, edge[0], edge[1]) != null:
			return true
	return false

static func _front_seg(roads: Dictionary, b: Dictionary, lrect: Rect2) -> int:
	# Nearest of the block's four bounding grid segments.
	var i: int = b["gi"]
	var j: int = b["gj"]
	var candidates := []
	for key in ["%d:%d" % [i, j], "%d:%d" % [i + 1, j]]:
		if roads["vseg"].has(key):
			candidates.append(roads["vseg"][key])
	for key in ["%d:%d" % [i, j], "%d:%d" % [i, j + 1]]:
		if roads["hseg"].has(key):
			candidates.append(roads["hseg"][key])
	var center := lrect.get_center()
	var best := -1
	var best_d := INF
	for sid in candidates:
		var s: Dictionary = roads["segments"][sid]
		var d := Geometry2D.get_closest_point_to_segment(center, s["a"], s["b"]).distance_to(center)
		if d < best_d:
			best_d = d
			best = sid
	return best

static func _mark_parcel(rng: RandomNumberGenerator, lots: Array, parcels: Array, block_lots: Dictionary, nx: int, ny: int) -> void:
	# Try a seeded 2x2 or 1x2 group of adjacent occupied cells.
	var shapes := [[2, 2], [2, 1], [1, 2]] if nx >= 2 and ny >= 2 else [[2, 1], [1, 2]]
	var u0 := rng.randi() % maxi(nx - 1, 1)
	var v0 := rng.randi() % maxi(ny - 1, 1)
	for shape in shapes:
		var members: Array = []
		var ok := true
		for du in shape[0]:
			for dv in shape[1]:
				var key := "%d,%d" % [u0 + du, v0 + dv]
				if not block_lots.has(key):
					ok = false
				else:
					members.append(block_lots[key])
		if ok and members.size() >= 2:
			var pid := parcels.size()
			var rect: Rect2 = lots[members[0]]["rect"]
			for li in members:
				rect = rect.merge(lots[li]["rect"])
				lots[li]["parcel"] = pid
			parcels.append({"id": pid, "lots": members, "rect": rect})
			return
