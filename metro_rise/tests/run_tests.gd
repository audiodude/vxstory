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
