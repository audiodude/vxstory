extends SceneTree
# metro_rise pure-logic tests. Run with:
#   godot --headless --path metro_rise --script res://tests/run_tests.gd
# Add new `func test_*() -> void` methods; they are discovered by name.

var _fails: int = 0
var _count: int = 0
var _skips: int = 0

func _initialize() -> void:
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_"):
			_count += 1
			call(n)
	print("TESTS: %d run, %d failed, %d skipped" % [_count, _fails, _skips])
	quit(1 if _fails > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		push_error("FAIL: " + msg)

func check_eq(a, b, msg: String) -> void:
	check(is_same_ish(a, b), msg + " (got %s, want %s)" % [str(a), str(b)])

func skip(reason: String) -> void:
	_skips += 1
	print("SKIP: " + reason)

func is_same_ish(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.0001
	return a == b

# ---------------- smoke ----------------

const RNGService = preload("res://core/rng_service.gd")

func test_smoke_rng() -> void:
	var a := RNGService.new(7).stream("plan")
	var b := RNGService.new(7).stream("plan")
	check_eq(a.randf(), b.randf(), "runner + core symlink alive")

# ---------------- citygen/roads ----------------

const Roads = preload("res://citygen/roads.gd")

func _road_params() -> Dictionary:
	return {"city_radius": 600.0, "block_min": 90.0, "block_max": 130.0,
			"boulevard_count": 2}

func test_roads_deterministic() -> void:
	var a := Roads.build(RNGService.new(11).stream("roads"), _road_params())
	var b := Roads.build(RNGService.new(11).stream("roads"), _road_params())
	check_eq(a["segments"].size(), b["segments"].size(), "same seed same segment count")
	check_eq(str(a["segments"][0]), str(b["segments"][0]), "same first segment")
	var c := Roads.build(RNGService.new(12).stream("roads"), _road_params())
	check(str(a["xs"]) != str(c["xs"]), "different seed different grid")

func test_roads_rings_and_kinds() -> void:
	var r := Roads.build(RNGService.new(3).stream("roads"), _road_params())
	var blvds := 0
	var diags := 0
	for s in r["segments"]:
		check(s["ring"] >= 0 and s["ring"] <= 5, "ring in range")
		check(s["width"] > 0.0, "width set")
		if s["kind"] == "blvd":
			blvds += 1
		if s["diag"]:
			diags += 1
	check(blvds > 0, "boulevards exist")
	check(diags > 0, "diagonal boulevard segments exist")

func test_roads_nodes_connect() -> void:
	var r := Roads.build(RNGService.new(3).stream("roads"), _road_params())
	for n in r["nodes"]:
		check(n["segs"].size() >= 2, "every node joins >=2 segments")
	for s in r["segments"]:
		var na: Dictionary = r["nodes"][s["na"]]
		var nb: Dictionary = r["nodes"][s["nb"]]
		check_eq(str(na["pos"]), str(s["a"]), "segment a matches node na")
		check_eq(str(nb["pos"]), str(s["b"]), "segment b matches node nb")
		check(s["id"] in na["segs"] and s["id"] in nb["segs"], "node backrefs segment")

# ---------------- citygen/lots ----------------

const Lots = preload("res://citygen/lots.gd")

func _city(seed_v: int) -> Dictionary:
	var svc := RNGService.new(seed_v)
	var p := {"city_radius": 600.0, "block_min": 90.0, "block_max": 130.0,
			"boulevard_count": 2, "park_pct": 0.07, "tower_share": 0.25,
			"lot_fill": 0.8}
	var roads := Roads.build(svc.stream("roads"), p)
	return {"roads": roads, "lots": Lots.build(svc.stream("lots"), roads, p), "params": p}

func test_lots_front_roads() -> void:
	var c := _city(5)
	check(c["lots"]["lots"].size() > 50, "a real city has lots")
	for l in c["lots"]["lots"]:
		check(l["front_seg"] >= 0 and l["front_seg"] < c["roads"]["segments"].size(),
				"lot fronts a real segment")

func test_lots_inside_blocks_and_districts() -> void:
	var c := _city(5)
	var blocks: Array = c["lots"]["blocks"]
	for l in c["lots"]["lots"]:
		check(blocks[l["block"]]["rect"].grow(0.5).encloses(l["rect"]), "lot within block")
		check(l["district"] in ["core", "commercial", "residential", "industrial"], "district set")
	var seen := {}
	for b in blocks:
		seen[b["district"]] = true
	check(seen.has("park"), "some parks")
	check(seen.has("core") and seen.has("residential"), "district spread")

func test_lots_avoid_diagonal_corridors() -> void:
	var c := _city(5)
	for l in c["lots"]["lots"]:
		for s in c["roads"]["segments"]:
			if s["diag"]:
				var center: Vector2 = l["rect"].get_center()
				var q := Geometry2D.get_closest_point_to_segment(center, s["a"], s["b"])
				check(q.distance_to(center) > s["width"] * 0.5,
						"lot center clear of diagonal corridor")

func test_parcels_are_grouped() -> void:
	var found_any := false
	for seed_v in [9, 5, 21, 33]:
		var c := _city(seed_v)
		for pc in c["lots"]["parcels"]:
			found_any = true
			check(pc["lots"].size() >= 2, "parcel groups >=2 lots")
			for li in pc["lots"]:
				check_eq(c["lots"]["lots"][li]["parcel"], pc["id"], "backref consistent")
				check(pc["rect"].grow(0.5).encloses(c["lots"]["lots"][li]["rect"]),
						"parcel rect covers member lots")
	check(found_any, "at least one parcel across seeds")

# ---------------- citygen/eras + plan ----------------

const Plan = preload("res://citygen/plan.gd")

func _params() -> Dictionary:
	return {"city_radius": 600.0, "block_min": 90.0, "block_max": 130.0,
			"boulevard_count": 2, "park_pct": 0.07, "tower_share": 0.25,
			"lot_fill": 0.8, "height_scale": 1.0, "era1_end": 0.34,
			"era2_end": 0.66, "era_overlap": 0.08, "demolish_core": 0.85,
			"demolish_edge": 0.25, "construct_speed": 1.0, "floor_h": 3.2,
			"tree_density": 0.6, "lamp_density": 0.6, "win_scale": 1.0,
			"topout_floors": 18}

func test_plan_deterministic() -> void:
	var a := Plan.build(RNGService.new(21), _params())
	var b := Plan.build(RNGService.new(21), _params())
	check_eq(str(a["timelines"]), str(b["timelines"]), "identical timelines for same seed")
	check_eq(a["trees"].size(), b["trees"].size(), "identical scatter")

func test_timelines_valid() -> void:
	var p := Plan.build(RNGService.new(4), _params())
	check(p["timelines"].size() > 50, "most lots get buildings")
	for lot_id in p["timelines"]:
		var prev_end := -1.0
		for e in p["timelines"][lot_id]:
			check(e["p0"] >= 0.0 and e["p1"] <= 1.0 and e["p0"] < e["p1"],
					"window in [0,1] (got %.3f..%.3f)" % [e["p0"], e["p1"]])
			check(e["p0"] >= prev_end - 0.0001, "entries non-overlapping")
			prev_end = e["p_demo"] if e["p_demo"] != INF else 2.0
			check(e["floors"] >= 1, "has floors")
			check(e["tiers"].size() >= 1 and e["tiers"].size() <= 3, "1..3 tiers")
			var tf := 0
			for t in e["tiers"]:
				tf += int(t["floors"])
				check(e["rect"].grow(0.1).encloses(t["rect"]), "tiers within footprint")
			check_eq(tf, e["floors"], "tier floors sum to entry floors")
			if e["p_demo"] != INF:
				check(e["p_demo"] >= e["p1"] - 0.0001, "no demolition before topout")

func test_era_bands_respected() -> void:
	var p := Plan.build(RNGService.new(4), _params())
	var styles := {}
	for lot_id in p["timelines"]:
		for e in p["timelines"][lot_id]:
			styles[e["style"]] = styles.get(e["style"], 0) + 1
			if e["style"] == 2:
				check(e["p0"] > 0.66 - 0.08 - 0.001, "glass not before its band")
			if e["style"] == 0:
				check(e["p0"] < 0.34 + 0.08 + 0.001, "brick not after its band")
	check(styles.get(0, 0) > 0 and styles.get(1, 0) > 0 and styles.get(2, 0) > 0,
			"all three eras appear")

func test_replacement_happens() -> void:
	var p := Plan.build(RNGService.new(4), _params())
	var demos := 0
	var chains := 0
	for lot_id in p["timelines"]:
		var entries: Array = p["timelines"][lot_id]
		for e in entries:
			if e["p_demo"] != INF:
				demos += 1
		if entries.size() >= 2:
			chains += 1
	check(demos > 20, "replacement demolitions exist (got %d)" % demos)
	check(chains > 20, "replacement chains exist (got %d)" % chains)

func test_parcels_demolish_together() -> void:
	var found := false
	for seed_v in [13, 4, 21]:
		var p := Plan.build(RNGService.new(seed_v), _params())
		for pc in p["parcels"]:
			var demo_ps := {}
			var successors := 0
			for li in pc["lots"]:
				for e in p["timelines"].get(li, []):
					if e["parcel_id"] == pc["id"]:
						successors += 1
						check_eq(e["style"], 2, "parcel successor is glass")
					elif e["p_demo"] != INF and e["p_demo"] < 1.0:
						demo_ps[snappedf(e["p_demo"], 0.0001)] = true
			if successors == 1:
				found = true
				check(demo_ps.size() <= 1, "parcel members share one demo P")
	check(found, "at least one parcel tower across seeds")
