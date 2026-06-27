extends Node
# Hot-reload: polls the scene file's modification time (~4 Hz) and calls
# model.reload_from_file() when it changes. Preview mode only. mtime resolution
# is whole seconds, so two saves within one second may collapse into one reload —
# fine for human-paced editing.

var model
var path: String = ""
var _last_mtime: int = 0
var _acc := 0.0

func setup(p_model, p_path: String) -> void:
	model = p_model
	path = p_path
	if path != "" and FileAccess.file_exists(path):
		_last_mtime = FileAccess.get_modified_time(path)

func _is_newer(mtime: int) -> bool:
	return mtime > _last_mtime

func _process(delta: float) -> void:
	if path == "" or model == null:
		return
	_acc += delta
	if _acc < 0.25:
		return
	_acc = 0.0
	if not FileAccess.file_exists(path):
		return
	var m := FileAccess.get_modified_time(path)
	if _is_newer(m):
		_last_mtime = m
		model.reload_from_file()
