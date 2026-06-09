extends RefCounted
# Schema builder helpers. A schema is plain Dictionaries — see plan/spec.

static func macro_def(macro_name: String, default := 0.5) -> Dictionary:
	return {"name": macro_name, "default": default}

static func _base(p_name: String, p_type: String, default, extra: Dictionary) -> Dictionary:
	var d := {"name": p_name, "type": p_type, "default": default, "live": true}
	d.merge(extra, true)
	return d

static func f(p_name: String, default: float, min_v: float, max_v: float, extra := {}) -> Dictionary:
	var d := _base(p_name, "float", default, extra)
	d["min"] = min_v
	d["max"] = max_v
	if not d.has("step"):
		d["step"] = 0.0
	return d

static func i(p_name: String, default: int, min_v: int, max_v: int, extra := {}) -> Dictionary:
	var d := _base(p_name, "int", default, extra)
	d["min"] = min_v
	d["max"] = max_v
	d["step"] = 1
	return d

static func b(p_name: String, default: bool, extra := {}) -> Dictionary:
	return _base(p_name, "bool", default, extra)

static func e(p_name: String, default: String, options: PackedStringArray, extra := {}) -> Dictionary:
	var d := _base(p_name, "enum", default, extra)
	d["options"] = options
	return d

static func c(p_name: String, default: Color, extra := {}) -> Dictionary:
	return _base(p_name, "color", default, extra)

static func macro_default(schema: Dictionary, macro_name: String) -> float:
	for m in schema["macros"]:
		if m["name"] == macro_name:
			return float(m["default"])
	return 0.5
