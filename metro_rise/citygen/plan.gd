extends RefCounted
# CityPlan: the full seeded build-out, computed once per restart. Roads, lots,
# per-lot P-space timelines, plus static scatter (trees, lamps). Pure data —
# StateTracker evaluates it at any P; the view renders it.

const Roads = preload("res://citygen/roads.gd")
const Lots = preload("res://citygen/lots.gd")
const Eras = preload("res://citygen/eras.gd")

const TREE_CAP := 3200
const LAMP_CAP := 1400

static func build(rng_service, params: Dictionary) -> Dictionary:
	var roads: Dictionary = Roads.build(rng_service.stream("plan:roads"), params)
	var lots: Dictionary = Lots.build(rng_service.stream("plan:lots"), roads, params)
	var timelines: Dictionary = Eras.timelines(rng_service.stream("plan:eras"), lots, params)
	var srng: RandomNumberGenerator = rng_service.stream("plan:scatter")
	return {
		"roads": roads,
		"blocks": lots["blocks"], "lots": lots["lots"], "parcels": lots["parcels"],
		"timelines": timelines,
		"trees": _trees(srng, roads, lots["blocks"], params),
		"lamps": _lamps(srng, roads, params),
		"city_radius": float(params["city_radius"]),
	}

static func _trees(rng: RandomNumberGenerator, roads: Dictionary, blocks: Array, params: Dictionary) -> Array:
	var density: float = params["tree_density"]
	var r: float = params["city_radius"]
	var out: Array = []
	for b in blocks:
		if b["district"] != "park":
			continue
		var rect: Rect2 = b["rect"]
		var n := int(rect.get_area() / 90.0 * density)
		for i in n:
			var pos := rect.position + Vector2(rng.randf_range(2.0, rect.size.x - 2.0), rng.randf_range(2.0, rect.size.y - 2.0))
			out.append({"pos": pos, "ring": b["ring"], "scale": rng.randf_range(0.8, 1.3)})
	for s in roads["segments"]:
		var is_median: bool = s["kind"] == "blvd" and not s["diag"]
		var is_sidewalk_row: bool = s["kind"] == "street" and s["ring"] >= 3
		if not (is_median or is_sidewalk_row):
			continue
		var spacing := 14.0 if is_median else 20.0
		var dir: Vector2 = (s["b"] - s["a"])
		var len := dir.length()
		dir /= maxf(len, 0.001)
		var side := Vector2(-dir.y, dir.x)
		var steps := int(len / spacing * density)
		for k in steps:
			var t := (float(k) + 0.5) / float(steps)
			var pos: Vector2 = s["a"] + dir * len * t
			if is_median:
				out.append({"pos": pos, "ring": s["ring"], "scale": rng.randf_range(0.7, 1.0)})
			else:
				var off: float = s["width"] * 0.5 + 1.6
				var flip := 1.0 if (k % 2 == 0) else -1.0
				out.append({"pos": pos + side * off * flip, "ring": s["ring"], "scale": rng.randf_range(0.8, 1.2)})
	return _capped(rng, out, TREE_CAP)

static func _lamps(rng: RandomNumberGenerator, roads: Dictionary, params: Dictionary) -> Array:
	var density: float = params["lamp_density"]
	var out: Array = []
	for s in roads["segments"]:
		if not (s["kind"] == "blvd" or s["ring"] <= 1):
			continue
		var dir: Vector2 = (s["b"] - s["a"])
		var len := dir.length()
		dir /= maxf(len, 0.001)
		var side := Vector2(-dir.y, dir.x)
		var steps := int(len / 28.0 * density)
		for k in steps:
			var t := (float(k) + 0.5) / float(steps)
			var flip := 1.0 if (k % 2 == 0) else -1.0
			out.append({"pos": s["a"] + dir * len * t + side * (s["width"] * 0.5 - 0.8) * flip,
					"ring": s["ring"]})
	return _capped(rng, out, LAMP_CAP)

static func _capped(rng: RandomNumberGenerator, arr: Array, cap: int) -> Array:
	if arr.size() <= cap:
		return arr
	# Deterministic thinning: keep a seeded-stride subset.
	var out: Array = []
	var stride := float(arr.size()) / float(cap)
	var t := rng.randf() * stride
	while int(t) < arr.size():
		out.append(arr[int(t)])
		t += stride
	return out
