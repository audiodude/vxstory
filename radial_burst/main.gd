extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")

func model_name() -> String:
	return "demo"

func get_schema() -> Dictionary:
	return {
		"macros": [PS.macro_def("energy", 0.5)],
		"params": [PS.f("speed", 100.0, 0.0, 1000.0, {"macro": {"name": "energy", "lo": 200.0, "hi": 800.0}})],
	}

func restart() -> void:
	print("RESTART speed=", params["speed"])
