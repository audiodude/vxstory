extends RefCounted
# Resolution pipeline: defaults -> macro mapping -> jitter -> overrides (pin).

const PS = preload("res://core/param_schema.gd")

static func curve_apply(t: float, curve: String) -> float:
	match curve:
		"ease_in":
			return t * t
		"ease_out":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"smooth":
			return t * t * (3.0 - 2.0 * t)
		_:
			return t

static func resolve(schema: Dictionary, macros: Dictionary, overrides: Dictionary, jitter: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for p in schema["params"]:
		var p_name: String = p["name"]
		if overrides.has(p_name):
			out[p_name] = _coerce(p, overrides[p_name])
			continue
		var v = p["default"]
		var numeric: bool = p["type"] == "float" or p["type"] == "int"
		if numeric and p.has("macro"):
			var m: Dictionary = p["macro"]
			var mv := clampf(float(macros.get(m["name"], PS.macro_default(schema, m["name"]))), 0.0, 1.0)
			v = lerpf(float(m["lo"]), float(m["hi"]), curve_apply(mv, m.get("curve", "linear")))
		var j: Dictionary = jitter.get(p_name, p.get("jitter", {}))
		if numeric and not j.is_empty():
			if j.has("pct"):
				v = float(v) * (1.0 + rng.randf_range(-float(j["pct"]), float(j["pct"])) / 100.0)
			elif j.has("abs"):
				v = float(v) + rng.randf_range(-float(j["abs"]), float(j["abs"]))
		out[p_name] = _coerce(p, v)
	return out

static func _coerce(p: Dictionary, v):
	match p["type"]:
		"float":
			return clampf(float(v), float(p["min"]), float(p["max"]))
		"int":
			return clampi(roundi(float(v)), int(p["min"]), int(p["max"]))
		"bool":
			return bool(v)
		"enum":
			var opts: PackedStringArray = p["options"]
			if v is String and opts.has(v):
				return v
			return p["default"]
		"color":
			if v is String:
				return Color.html(v)
			return v
	return v
