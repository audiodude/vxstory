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

# ---------------- sim/state ----------------

const State = preload("res://sim/state.gd")

func test_state_scrub_exact() -> void:
	var plan := Plan.build(RNGService.new(8), _params())
	var a := State.new(plan, _params())
	a.eval(0.7)
	var b := State.new(plan, _params())
	for P in [0.1, 0.9, 0.3, 0.7]:
		b.eval(P)
	check_eq(a.building_count(), b.building_count(), "same slot count")
	var diffs := 0
	for i in a.building_count():
		if str(a.slot(i)) != str(b.slot(i)):
			diffs += 1
	check_eq(diffs, 0, "slots identical after scrub walk")

func test_state_first_eval_silent_then_events() -> void:
	var plan := Plan.build(RNGService.new(8), _params())
	var t := State.new(plan, _params())
	check_eq(t.eval(0.5)["events"].size(), 0, "first eval fires nothing")
	var evs := []
	var P := 0.5
	while P < 0.72:
		P += 0.002
		evs.append_array(t.eval(P)["events"])
	var kinds := {}
	for e in evs:
		kinds[e["kind"]] = true
	check(kinds.has("era"), "era edge crossed fires era")
	check(kinds.has("topout") or kinds.has("demolish"), "life happens between 0.5 and 0.72")

func test_state_monotone_and_demo() -> void:
	var plan := Plan.build(RNGService.new(8), _params())
	var t := State.new(plan, _params())
	t.eval(0.4)
	var grown := 0
	var p_before := {}
	for i in t.building_count():
		p_before[i] = t.slot(i)["progress"]
	t.eval(0.45)
	for i in t.building_count():
		var s := t.slot(i)
		if s["demo"] == 0.0:
			check(s["progress"] >= float(p_before[i]) - 0.0001, "progress monotone without demo")
		if s["progress"] > float(p_before[i]) + 0.0001:
			grown += 1
	check(grown > 0, "something under construction between 0.40 and 0.45")

func test_state_changed_is_sparse() -> void:
	var plan := Plan.build(RNGService.new(8), _params())
	var t := State.new(plan, _params())
	var first: Dictionary = t.eval(0.5)
	check(first["changed"].size() > 0, "first eval reports active slots as changed")
	var second: Dictionary = t.eval(0.5)
	check_eq(second["changed"].size(), 0, "no change when P static")
	var third: Dictionary = t.eval(0.503)
	check(third["changed"].size() < t.building_count() / 4,
			"small P step touches a small slot subset (got %d of %d)" % [third["changed"].size(), t.building_count()])

func test_state_cranes_only_during_construction() -> void:
	var plan := Plan.build(RNGService.new(8), _params())
	var t := State.new(plan, _params())
	t.eval(0.5)
	var cranes := 0
	for i in t.building_count():
		var s := t.slot(i)
		if s["crane"]:
			cranes += 1
			check(s["progress"] < 0.999 or s["demo"] == 0.0, "crane only while rising")
			check(s["floors"] >= 8, "crane only on tall builds")
	check(cranes > 0, "mid-run has active cranes")

# ---------------- sim/sun + campath ----------------

const Sun = preload("res://sim/sun.gd")
const Cam = preload("res://sim/campath.gd")

func _sun_p() -> Dictionary:
	return {"fog_amount": 0.35, "star_density": 0.5}

func test_sun_day_night() -> void:
	var noon := Sun.eval(0.45, "daybreak", _sun_p())
	var mid := Sun.eval(0.97, "daybreak", _sun_p())
	check(noon["night"] < 0.05, "noon is day")
	check(mid["night"] > 0.95, "late is night")
	check(mid["moon_energy"] > 0.0 and noon["moon_energy"] == 0.0, "moon only at night")
	check(noon["sun_dir"].y < -0.5, "noon sun shines downward")
	check(noon["sun_energy"] > 1.0 and mid["sun_energy"] < 0.05, "sun energy follows arc")
	check(mid["star_alpha"] > 0.9 and noon["star_alpha"] == 0.0, "stars only at night")

func test_sun_continuous_at_dusk() -> void:
	for day in [0.859, 0.861, 0.039, 0.041]:
		var a := Sun.eval(day, "sodium", _sun_p())
		var b := Sun.eval(day + 0.002, "sodium", _sun_p())
		check(absf(a["night"] - b["night"]) < 0.08, "no night discontinuity at %f" % day)
		check(abs(a["sun_energy"] - b["sun_energy"]) < 0.2, "no energy pop at %f" % day)

func test_sun_palettes_differ() -> void:
	var a := Sun.eval(0.8, "daybreak", _sun_p())
	var b := Sun.eval(0.8, "sodium", _sun_p())
	check(str(a["sun_color"]) != str(b["sun_color"]), "palettes grade the sun")

func test_campath_smooth_and_orbiting() -> void:
	var p := {"cam_pull": 1.0, "cam_height": 1.0, "orbit_rate": 1.3,
			"orbit_deg0": 20.0, "cam_fov": 40.0}
	var a: Vector3 = Cam.eval(10.0, 0.3, p)["pos"]
	var b: Vector3 = Cam.eval(10.1, 0.3005, p)["pos"]
	check(a.distance_to(b) < 1.5, "sub-1.5m step per 0.1s")
	var near: Vector3 = Cam.eval(0.0, 0.1, p)["pos"]
	var far: Vector3 = Cam.eval(100.0, 0.9, p)["pos"]
	check(far.length() > near.length() + 200.0, "pulls back as city grows")
	check(far.y > near.y + 100.0, "rises as city grows")
	var look: Vector3 = Cam.eval(50.0, 0.5, p)["look"]
	check(look.length() < 120.0, "look target stays near center")
