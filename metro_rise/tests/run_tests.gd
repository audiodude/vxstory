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
