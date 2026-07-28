extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")

func model_name() -> String:
	return "metro_rise"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("development", 0.5), PS.macro_def("day_phase", 0.55),
		],
		"params": [
			PS.f("progress", 0.5, 0.0, 1.0, {"macro": {"name": "development", "lo": 0.0, "hi": 1.0}}),
			PS.f("time_of_day", 0.55, 0.0, 1.0, {"macro": {"name": "day_phase", "lo": 0.0, "hi": 1.0}}),
		],
	}

func restart() -> void:
	pass
