extends Node2D
# Base for all vxstory models. Lifecycle:
#   _ready -> load preset (if --preset) -> resolve params -> restart()
#   movie mode: quits after duration_sec; no UI.
#   preview mode: TweakPanel attached (Task 6).

const RNGService = preload("res://core/rng_service.gd")
const MacroMapper = preload("res://core/macro_mapper.gd")
const PresetIO = preload("res://core/preset_io.gd")
const RenderDriver = preload("res://core/render_driver.gd")
const ModStack = preload("res://core/modulation.gd")

var seed_value: int = 1
var duration_sec: float = 30.0
var macros: Dictionary = {}
var overrides: Dictionary = {}
var jitter: Dictionary = {}
var params: Dictionary = {}
var rng  # RNGService
var mod_stack  # ModStack (null until resolve_and_restart)
var modulators_cfg: Dictionary = {}
var movie_mode: bool = false
var _elapsed: float = 0.0
var preset_path: String = ""
var _link  # TransportLink (preview-only, null in movie/designer mode)
var _tl  # Timeline CanvasLayer; shelters restart-surviving helpers (watcher, link)
var _paused := false
var _applying_remote := false

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
	preset_path = cli["preset"]
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
	if cli["designer"]:
		_attach_designer()
		return
	resolve_and_restart()
	if not movie_mode:
		_attach_panel()
		_attach_scene_tools()
		_attach_link()

func _attach_designer() -> void:
	var Designer = load("res://core/designer/designer.gd")
	if Designer == null:
		return
	var d = Designer.new()
	add_child(d)
	d.setup(self)

func _attach_panel() -> void:
	var TweakPanel = load("res://core/tweak_panel.gd")
	if TweakPanel != null:
		add_child(TweakPanel.new(self))

func _attach_link() -> void:
	_link = load("res://core/transport_link.gd").new()
	# Parent under the Timeline CanvasLayer (like the scene watcher): models'
	# restart() sweeps queue_free every non-CanvasLayer child of the model, and
	# a direct-child link dies silently on the first scrub/hot-reload.
	if _tl != null:
		_tl.add_child(_link)
	else:
		add_child(_link)
	_link.setup("preview")
	_link.remote.connect(_on_remote_transport)
	# ask the peer (if already open) for its transport, so this window snaps to it on open
	_link.send(mod_stack.t if mod_stack != null else 0.0, not _paused, "hello")

func _set_paused(p: bool) -> void:
	_paused = p
	Engine.time_scale = 0.0 if p else 1.0

func _unhandled_key_input(ev: InputEvent) -> void:
	if movie_mode:
		return
	if ev is InputEventKey and ev.keycode == KEY_SPACE and ev.pressed and not ev.echo:
		_set_paused(not _paused)
		if _link != null and not _applying_remote:
			_link.send(mod_stack.t if mod_stack != null else 0.0, not _paused, "toggle")

func _on_remote_transport(t: float, playing: bool, kind: String) -> void:
	if kind == "hello":
		# a newly-opened peer wants state; reply with ours so it snaps to us
		if _link != null:
			_link.send(mod_stack.t if mod_stack != null else 0.0, not _paused, "toggle")
		return
	if kind == "tick":
		return  # preview is the clock master; it doesn't follow ticks
	_applying_remote = true
	if mod_stack != null and absf(mod_stack.t - t) > 0.01:
		scrub_to(t)
	if kind == "toggle":
		_set_paused(not playing)  # scrubs (kind "seek") never change play/pause
	_applying_remote = false

func _attach_scene_tools() -> void:
	# Timeline is a CanvasLayer, so it survives restart()'s "free non-CanvasLayer
	# children" sweep. Parent the watcher (a plain Node) UNDER it so the sweep
	# can't free the watcher and silently kill hot-reload on the first restart/scrub.
	var Timeline = load("res://core/timeline.gd")
	_tl = Timeline.new(self)
	add_child(_tl)
	var Watcher = load("res://core/scene_watcher.gd")
	var w = Watcher.new()
	_tl.add_child(w)
	w.setup(self, preset_path)

func adopt_preset(p: Dictionary) -> void:
	seed_value = int(p["seed"])
	duration_sec = float(p["duration_sec"])
	for k in p["macros"]:
		macros[k] = float(p["macros"][k])
	overrides = p["overrides"].duplicate()
	jitter = p["jitter"].duplicate()
	modulators_cfg = p.get("modulators", {})

func resolve_and_restart() -> void:
	rng = RNGService.new(seed_value)
	mod_stack = ModStack.from_config(modulators_cfg, rng)
	_compose()
	restart()

func reload_from_file() -> void:
	# Hot-reload the scene file (preview mode). Bad file -> keep current state.
	if preset_path == "":
		return
	var res := PresetIO.load_preset(preset_path, get_schema(), model_name())
	if not res["ok"]:
		push_warning("hot-reload skipped: " + res["error"])
		return
	for w in res["warnings"]:
		push_warning(w)
	adopt_preset(res["preset"])
	resolve_and_restart()

func scrub_to(t: float) -> void:
	# Jump the modulation clock to t, recompose, clear+rebuild, set the model
	# clock via _on_scrub, then play forward (character-at-t, not frame-exact).
	if mod_stack != null and mod_stack.enabled:
		mod_stack.t = t
	_compose()
	restart()
	_on_scrub(t)
	if _link != null and not _applying_remote:
		_link.send(mod_stack.t if mod_stack != null else t, not _paused, "seek")

func _on_scrub(_t: float) -> void:
	# Models with their own sim clock override this to set it to t.
	pass

func _compose() -> void:
	var jrng := RNGService.new(seed_value).stream("jitter")
	if mod_stack != null and mod_stack.enabled:
		params = mod_stack.compose(get_schema(), macros, overrides, jitter, jrng)
	else:
		params = MacroMapper.resolve(get_schema(), macros, overrides, jitter, jrng)

func resolve_live() -> void:
	# Re-resolve without restarting; used by the tweak panel for live params.
	rng = RNGService.new(seed_value)
	_compose()
	apply_live(params)

func emit_event(event_name: String) -> void:
	if mod_stack != null and mod_stack.enabled:
		mod_stack.emit(event_name)

func save_to(path: String) -> Error:
	return PresetIO.save_preset(path, model_name(), seed_value, duration_sec, macros, overrides, jitter, modulators_cfg)

func _process(delta: float) -> void:
	if mod_stack != null and mod_stack.enabled:
		mod_stack.tick(delta)
		_compose()
		apply_live(params)
		if _link != null and not _paused:
			_link.send(mod_stack.t, true, "tick")  # broadcast the live clock so the Designer stays locked
	if movie_mode:
		_elapsed += delta
		if _elapsed >= duration_sec:
			get_tree().quit()
