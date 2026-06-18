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

# ---------------- preset io ----------------

const PIO = preload("res://core/preset_io.gd")

func test_preset_roundtrip() -> void:
	var path := "/tmp/vx_test_preset.json"
	var err := PIO.save_preset(path, "demo", 99, 12.5,
		{"energy": 0.8}, {"speed": 440.0, "tint": Color(0, 1, 0)}, {"count": {"pct": 10.0}})
	check_eq(err, OK, "save ok")
	var res := PIO.load_preset(path, _demo_schema(), "demo")
	check(res["ok"], "load ok")
	check_eq(res["preset"]["seed"], 99, "seed roundtrips")
	check_eq(res["preset"]["duration_sec"], 12.5, "duration roundtrips")
	check_eq(res["preset"]["macros"]["energy"], 0.8, "macros roundtrip")
	check_eq(res["preset"]["overrides"]["speed"], 440.0, "overrides roundtrip")
	check_eq(res["preset"]["overrides"]["tint"], "#00ff00", "color saved as html string")
	check_eq(res["preset"]["jitter"]["count"]["pct"], 10.0, "jitter roundtrips")
	check_eq(res["warnings"].size(), 0, "no warnings on clean preset")

func test_preset_defaults_and_warnings() -> void:
	var path := "/tmp/vx_test_preset2.json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"model": "demo", "macros": {"bogus": 1.0}, "overrides": {"nope": 5}}))
	fa.close()
	var res := PIO.load_preset(path, _demo_schema(), "demo")
	check(res["ok"], "loads despite unknowns")
	check_eq(res["preset"]["seed"], 1, "seed defaults to 1")
	check_eq(res["preset"]["duration_sec"], 30.0, "duration defaults to 30")
	check_eq(res["warnings"].size(), 2, "unknown macro + unknown override warned")

func test_preset_model_mismatch_fails() -> void:
	var path := "/tmp/vx_test_preset3.json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"model": "other"}))
	fa.close()
	var res := PIO.load_preset(path, _demo_schema(), "demo")
	check(not res["ok"], "model mismatch is an error")

func test_preset_missing_file_fails() -> void:
	var res := PIO.load_preset("/tmp/vx_does_not_exist.json", _demo_schema(), "demo")
	check(not res["ok"], "missing file is an error")

# ---------------- string param type ----------------

func _string_schema() -> Dictionary:
	return {
		"macros": [],
		"params": [
			PS.s("label", "HELLO"),
		],
	}

func test_string_default_passthrough() -> void:
	var rng := RNGService.new(1).stream("jitter")
	var out := MM.resolve(_string_schema(), {}, {}, {}, rng)
	check_eq(out["label"], "HELLO", "string default passes through resolve")

func test_string_override_coerces_to_str() -> void:
	var rng := RNGService.new(1).stream("jitter")
	var out := MM.resolve(_string_schema(), {}, {"label": 42}, {}, rng)
	check_eq(out["label"], "42", "non-string override coerced to str")

func test_string_preset_roundtrip() -> void:
	var path := "/tmp/vx_test_string_preset.json"
	var schema := _string_schema()
	var err := PIO.save_preset(path, "demo_str", 1, 5.0, {}, {"label": "TEST TEXT"}, {})
	check_eq(err, OK, "save with string override ok")
	var res := PIO.load_preset(path, schema, "demo_str")
	check(res["ok"], "load ok")
	var rng := RNGService.new(1).stream("jitter")
	var out := MM.resolve(schema, {}, res["preset"]["overrides"], {}, rng)
	check_eq(out["label"], "TEST TEXT", "string override roundtrips through preset")

# ---------------- render driver ----------------

const RD = preload("res://core/render_driver.gd")

func test_parse_user_args() -> void:
	var out := RD.parse_user_args(PackedStringArray(["--preset", "/tmp/p.json", "--duration", "12.5"]))
	check_eq(out["preset"], "/tmp/p.json", "preset parsed")
	check_eq(out["duration"], 12.5, "duration parsed")

func test_parse_user_args_empty_and_partial() -> void:
	var out := RD.parse_user_args(PackedStringArray([]))
	check_eq(out["preset"], "", "no preset -> empty")
	check_eq(out["duration"], 0.0, "no duration -> 0")
	var out2 := RD.parse_user_args(PackedStringArray(["--preset"]))
	check_eq(out2["preset"], "", "dangling flag ignored")

# ---------------- tweak panel (instancing smoke) ----------------

func test_tweak_panel_builds_rows() -> void:
	var SimModelScript = load("res://main.gd")  # demo model from Task 5
	var model = SimModelScript.new()
	get_root().add_child(model)
	var TweakPanel = load("res://core/tweak_panel.gd")
	var panel = TweakPanel.new(model)
	get_root().add_child(panel)
	# panel _ready ran synchronously on add_child
	check(panel._param_rows.size() == model.get_schema()["params"].size(), "one row per param")
	check(panel._macro_sliders.size() == model.get_schema()["macros"].size(), "one slider per macro")
	panel.free()
	model.free()

# ---------------- director ----------------

const Director = preload("res://core/director.gd")

func _dir_cfg() -> Dictionary:
	return {"enabled": true, "period_sec": 60.0, "amplitude": 0.3, "macros": ["energy", "bogus"]}

func test_director_disabled_by_default() -> void:
	var d = Director.from_config({}, {"energy": 0.5}, RNGService.new(3))
	check_eq(d.enabled, false, "empty config -> disabled")
	var macros := {"energy": 0.5}
	check_eq(d.apply(macros), false, "disabled apply is a no-op")
	check_eq(macros["energy"], 0.5, "macros untouched when disabled")

func test_director_deterministic_and_clamped() -> void:
	var a = Director.from_config(_dir_cfg(), {"energy": 0.9}, RNGService.new(7))
	var b = Director.from_config(_dir_cfg(), {"energy": 0.9}, RNGService.new(7))
	for i in 50:
		a.tick(0.5)
		b.tick(0.5)
		var va: float = a.current("energy")
		check_eq(va, b.current("energy"), "same seed -> same drift curve")
		check(va >= 0.0 and va <= 1.0, "drift clamped to 0..1")

func test_director_ignores_unknown_macros() -> void:
	var d = Director.from_config(_dir_cfg(), {"energy": 0.5}, RNGService.new(7))
	check_eq(d.macro_names.size(), 1, "unknown macro 'bogus' dropped")

func test_director_apply_and_rebase() -> void:
	var d = Director.from_config(_dir_cfg(), {"energy": 0.5}, RNGService.new(7))
	d.tick(13.0)
	var macros := {"energy": 0.5}
	check_eq(d.apply(macros), true, "apply reports change")
	check(absf(macros["energy"] - 0.5) > 0.0001, "macro drifted from base")
	d.rebase("energy", 0.9)
	d.apply(macros)
	var hi: float = macros["energy"]
	d.rebase("energy", 0.1)
	d.apply(macros)
	check(hi > macros["energy"], "rebase shifts the curve's center")

func test_preset_roundtrip_director() -> void:
	var path := "/tmp/vx_test_director.json"
	var err := PIO.save_preset(path, "demo", 1, 10.0, {}, {}, {}, _dir_cfg())
	check_eq(err, OK, "save with director ok")
	var res := PIO.load_preset(path, _demo_schema(), "demo")
	check(res["ok"], "load ok")
	check_eq(res["preset"]["director"]["period_sec"], 60.0, "director roundtrips")
	# absent director -> empty dict default
	PIO.save_preset(path, "demo", 1, 10.0, {}, {}, {})
	var res2 := PIO.load_preset(path, _demo_schema(), "demo")
	check_eq(res2["preset"]["director"], {}, "missing director defaults to {}")

# ---------------- hue ----------------

const Hue = preload("res://core/hue.gd")

func test_hue_zero_is_identity() -> void:
	var c := Color.from_hsv(0.2, 0.5, 0.8)
	var r := Hue.rotated(c, 0.0)
	check(absf(r.h - c.h) < 0.001, "0 deg keeps hue")
	check(absf(r.s - c.s) < 0.001 and absf(r.v - c.v) < 0.001, "0 deg keeps sat/val")

func test_hue_360_wraps_to_same() -> void:
	var c := Color.from_hsv(0.3, 0.7, 0.9)
	var r := Hue.rotated(c, 360.0)
	check(absf(r.h - c.h) < 0.001, "360 deg wraps to same hue")

func test_hue_180_is_opposite() -> void:
	var c := Color.from_hsv(0.0, 1.0, 1.0)  # h = 0
	var r := Hue.rotated(c, 180.0)
	check(absf(r.h - 0.5) < 0.001, "180 deg -> h = 0.5")

func test_hue_preserves_alpha() -> void:
	var r := Hue.rotated(Color(1, 1, 1, 0.4), 90.0)
	check_eq(r.a, 0.4, "alpha preserved")
