extends Control
# Root of the visual Designer (attached by SimModel under --designer). Reads the
# model schema via model.get_schema() and the scene from the model's adopted
# macros/overrides/modulators_cfg; writes the scene file on edits. (UI built up in
# later tasks; this stub proves the launch path + schema access.)

const PresetIO = preload("res://core/preset_io.gd")

var model  # SimModel

func setup(p_model) -> void:
	model = p_model
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var schema: Dictionary = model.get_schema()
	var lbl := Label.new()
	lbl.position = Vector2(20, 20)
	lbl.text = "DESIGNER · %s · %s\n%d macros, %d params" % [
		model.model_name(), model.preset_path,
		schema["macros"].size(), schema["params"].size()]
	add_child(lbl)
