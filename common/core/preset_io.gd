extends RefCounted
# JSON preset load/save + validation against a schema.

static func save_preset(path: String, model: String, seed_value: int, duration_sec: float, macros: Dictionary, overrides: Dictionary, jitter: Dictionary, director: Dictionary = {}, modulators: Dictionary = {}) -> Error:
	var ov := {}
	for k in overrides:
		ov[k] = ("#" + overrides[k].to_html(false)) if overrides[k] is Color else overrides[k]
	var doc := {
		"model": model,
		"seed": seed_value,
		"duration_sec": duration_sec,
		"macros": macros,
		"overrides": ov,
		"jitter": jitter,
	}
	if not director.is_empty():
		doc["director"] = director
	if not modulators.is_empty():
		doc["modulators"] = modulators
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_string(JSON.stringify(doc, "  "))
	fa.close()
	return OK

static func load_preset(path: String, schema: Dictionary, model: String) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg, "warnings": [], "preset": {}}
	if not FileAccess.file_exists(path):
		return fail.call("preset not found: " + path)
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		return fail.call("invalid JSON in " + path)
	if data.get("model", model) != model:
		return fail.call("preset is for model '%s', not '%s'" % [data.get("model"), model])
	var warnings: Array[String] = []
	var known_params := {}
	for p in schema["params"]:
		known_params[p["name"]] = true
	var known_macros := {}
	for m in schema["macros"]:
		known_macros[m["name"]] = true
	for k in data.get("macros", {}):
		if not known_macros.has(k):
			warnings.append("unknown macro: " + str(k))
	for section in ["overrides", "jitter"]:
		for k in data.get(section, {}):
			if not known_params.has(k):
				warnings.append("unknown param in %s: %s" % [section, str(k)])
	for kind in ["lfo", "tween", "envelope"]:
		for md in data.get("modulators", {}).get(kind, []):
			for tg in md.get("targets", []):
				var to_name := str(tg.get("to", ""))
				if not (known_params.has(to_name) or known_macros.has(to_name)):
					warnings.append("unknown modulator target: " + to_name)
	var raw_director = data.get("director", {})
	var director: Dictionary = raw_director if raw_director is Dictionary else {}
	var raw_mod = data.get("modulators", {})
	var modulators: Dictionary = raw_mod if raw_mod is Dictionary else {}
	var preset := {
		"model": model,
		"seed": int(data.get("seed", 1)),
		"duration_sec": float(data.get("duration_sec", 30.0)),
		"macros": data.get("macros", {}),
		"overrides": data.get("overrides", {}),
		"jitter": data.get("jitter", {}),
		"director": director,
		"modulators": modulators,
	}
	return {"ok": true, "error": "", "warnings": warnings, "preset": preset}
