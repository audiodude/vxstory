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

# ---------------- param schema + resolution ----------------

const PS = preload("res://core/param_schema.gd")
const MM = preload("res://core/macro_mapper.gd")

func _demo_schema() -> Dictionary:
	return {
		"macros": [PS.macro_def("energy", 0.5)],
		"params": [
			PS.f("speed", 100.0, 0.0, 1000.0, {"macro": {"name": "energy", "lo": 200.0, "hi": 800.0, "curve": "linear"}}),
			PS.i("count", 50, 1, 100, {"jitter": {"pct": 20.0}}),
			PS.f("plain", 5.0, 0.0, 10.0),
			PS.b("mirror", true),
			PS.e("palette", "fire", PackedStringArray(["fire", "ice", "acid"])),
			PS.c("tint", Color(1, 0, 0)),
		],
	}

func test_schema_helpers_fill_defaults() -> void:
	var p := PS.f("x", 1.0, 0.0, 2.0)
	check_eq(p["type"], "float", "f() sets type")
	check_eq(p["live"], true, "live defaults true")
	var e := PS.e("pal", "fire", PackedStringArray(["fire", "ice"]))
	check_eq(e["default"], "fire", "enum default is option string")

func test_resolve_defaults_when_no_macros_given() -> void:
	var rng := RNGService.new(7).stream("jitter")
	var out := MM.resolve(_demo_schema(), {}, {}, {}, rng)
	# energy macro defaults to 0.5 -> speed = lerp(200, 800, 0.5) = 500
	check_eq(out["speed"], 500.0, "macro default drives mapped param")
	check_eq(out["plain"], 5.0, "unmapped param keeps default")
	check_eq(out["mirror"], true, "bool passes through")
	check_eq(out["palette"], "fire", "enum resolves to option string")
	check(out["tint"] is Color, "color resolves to Color")

func test_resolve_macro_curves() -> void:
	var rng := RNGService.new(7).stream("jitter")
	var s := _demo_schema()
	s["params"][0]["macro"]["curve"] = "ease_in"
	var out := MM.resolve(s, {"energy": 0.5}, {}, {}, rng)
	# ease_in: t*t = 0.25 -> lerp(200, 800, .25) = 350
	check_eq(out["speed"], 350.0, "ease_in curve applied")

func test_resolve_override_pins_param() -> void:
	var rng := RNGService.new(7).stream("jitter")
	var out := MM.resolve(_demo_schema(), {"energy": 1.0}, {"speed": 123.0}, {"speed": {"pct": 50.0}}, rng)
	check_eq(out["speed"], 123.0, "override beats macro and jitter")

func test_resolve_jitter_deterministic_and_bounded() -> void:
	var a := MM.resolve(_demo_schema(), {}, {}, {}, RNGService.new(9).stream("jitter"))
	var b := MM.resolve(_demo_schema(), {}, {}, {}, RNGService.new(9).stream("jitter"))
	var c := MM.resolve(_demo_schema(), {}, {}, {}, RNGService.new(10).stream("jitter"))
	check_eq(a["count"], b["count"], "same seed -> same jitter")
	check(int(a["count"]) >= 40 and int(a["count"]) <= 60, "pct jitter within +/-20%")
	check(a["count"] != c["count"] or a != c, "different seed -> different variation")

func test_resolve_clamps_and_coerces() -> void:
	var rng := RNGService.new(7).stream("jitter")
	var out := MM.resolve(_demo_schema(), {}, {"speed": 99999.0, "count": 3.7, "palette": "ice", "tint": "#00ff00"}, {}, rng)
	check_eq(out["speed"], 1000.0, "float clamped to max")
	check_eq(out["count"], 4, "int rounded")
	check_eq(out["palette"], "ice", "enum override by string")
	check_eq(out["tint"], Color("#00ff00"), "color coerced from html string")

func test_resolve_unknown_enum_falls_back() -> void:
	var rng := RNGService.new(7).stream("jitter")
	var out := MM.resolve(_demo_schema(), {}, {"palette": "nope"}, {}, rng)
	check_eq(out["palette"], "fire", "unknown enum option falls back to default")
