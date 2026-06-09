extends SceneTree
# Minimal assert-based test runner. Run with:
#   godot --headless --path radial_burst --script res://core/tests/run_tests.gd
# Add new `func test_*() -> void` methods; they are discovered by name.

var _fails: int = 0
var _count: int = 0

func _initialize() -> void:
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_"):
			_count += 1
			call(n)
	print("TESTS: %d run, %d failed" % [_count, _fails])
	quit(1 if _fails > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		push_error("FAIL: " + msg)

func check_eq(a, b, msg: String) -> void:
	check(is_same_ish(a, b), msg + " (got %s, want %s)" % [str(a), str(b)])

func is_same_ish(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.0001
	return a == b

# ---------------- rng_service ----------------

const RNGService = preload("res://core/rng_service.gd")

func test_rng_same_seed_same_stream() -> void:
	var a := RNGService.new(42).stream("sim")
	var b := RNGService.new(42).stream("sim")
	for i in 5:
		check_eq(a.randf(), b.randf(), "same seed+stream must repeat")

func test_rng_streams_independent() -> void:
	var svc := RNGService.new(42)
	var a := svc.stream("sim")
	var b := svc.stream("jitter")
	var same := true
	for i in 5:
		if a.randf() != b.randf():
			same = false
	check(not same, "different stream names must differ")

func test_rng_different_seeds_differ() -> void:
	var a := RNGService.new(1).stream("sim")
	var b := RNGService.new(2).stream("sim")
	var same := true
	for i in 5:
		if a.randf() != b.randf():
			same = false
	check(not same, "different seeds must differ")
