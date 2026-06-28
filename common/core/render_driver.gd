extends RefCounted
# CLI arg parsing + movie-mode detection. User args come after `--`:
#   godot --path <proj> --write-movie out.avi -- --preset presets/x.json

static func parse_user_args(args: PackedStringArray) -> Dictionary:
	var out := {"preset": "", "duration": 0.0, "designer": false}
	var i := 0
	while i < args.size():
		if args[i] == "--preset" and i + 1 < args.size():
			out["preset"] = args[i + 1]
			i += 1
		elif args[i] == "--duration" and i + 1 < args.size():
			out["duration"] = float(args[i + 1])
			i += 1
		elif args[i] == "--designer":
			out["designer"] = true
		i += 1
	return out

static func is_movie_mode() -> bool:
	return OS.has_feature("movie")
