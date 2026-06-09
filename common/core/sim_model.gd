extends Node2D
# Base for all vxstory models. Lifecycle:
#   _ready -> load preset (if --preset) -> resolve params -> restart()
#   movie mode: quits after duration_sec; no UI.
#   preview mode: TweakPanel attached (Task 6).

const RNGService = preload("res://core/rng_service.gd")
const MacroMapper = preload("res://core/macro_mapper.gd")
const PresetIO = preload("res://core/preset_io.gd")
const RenderDriver = preload("res://core/render_driver.gd")

var seed_value: int = 1
var duration_sec: float = 30.0
var macros: Dictionary = {}
var overrides: Dictionary = {}
var jitter: Dictionary = {}
var params: Dictionary = {}
var rng  # RNGService
var movie_mode: bool = false
var _elapsed: float = 0.0

func model_name() -> String:
	return "base"

func get_schema() -> Dictionary:
	return {"macros": [], "params": []}

func restart() -> void:
	pass

func apply_live(_p: Dictionary) -> void:
	pass

func _ready() -> void:
	movie_mode = RenderDriver.is_movie_mode()
	var schema := get_schema()
	for m in schema["macros"]:
		macros[m["name"]] = float(m["default"])
	var cli := RenderDriver.parse_user_args(OS.get_cmdline_user_args())
	if cli["preset"] != "":
		var res := PresetIO.load_preset(cli["preset"], schema, model_name())
		if not res["ok"]:
			push_error(res["error"])
			get_tree().quit(1)
			return
		for w in res["warnings"]:
			push_warning(w)
		adopt_preset(res["preset"])
	if cli["duration"] > 0.0:
		duration_sec = cli["duration"]
	resolve_and_restart()
	if not movie_mode:
		_attach_panel()

func _attach_panel() -> void:
	var TweakPanel = load("res://core/tweak_panel.gd")
	if TweakPanel != null:
		add_child(TweakPanel.new(self))

func adopt_preset(p: Dictionary) -> void:
	seed_value = int(p["seed"])
	duration_sec = float(p["duration_sec"])
	for k in p["macros"]:
		macros[k] = float(p["macros"][k])
	overrides = p["overrides"].duplicate()
	jitter = p["jitter"].duplicate()

func resolve_and_restart() -> void:
	rng = RNGService.new(seed_value)
	params = MacroMapper.resolve(get_schema(), macros, overrides, jitter, rng.stream("jitter"))
	restart()

func resolve_live() -> void:
	# Re-resolve without restarting; used by the tweak panel for live params.
	rng = RNGService.new(seed_value)
	params = MacroMapper.resolve(get_schema(), macros, overrides, jitter, rng.stream("jitter"))
	apply_live(params)

func save_to(path: String) -> Error:
	return PresetIO.save_preset(path, model_name(), seed_value, duration_sec, macros, overrides, jitter)

func _process(delta: float) -> void:
	if movie_mode:
		_elapsed += delta
		if _elapsed >= duration_sec:
			get_tree().quit()
