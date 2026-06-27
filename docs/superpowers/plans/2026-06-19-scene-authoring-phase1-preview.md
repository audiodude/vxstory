# Scene authoring — Phase 1 (preview upgrade) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the Godot preview into a read-only scene viewer — it hot-reloads the scene file on change and shows a scrubbable timeline of the modulation program (curves, playhead, wipe-on-scrub) — so a designer process can drive it.

**Architecture:** Two small framework additions plus SimModel hooks. `scene_watcher.gd` polls the scene file's mtime and calls `model.reload_from_file()` on change. `timeline.gd` is a read-only `CanvasLayer` that draws each modulation source as the curve/motion it produces over the duration (via `mod_sources.gd`), with a draggable playhead that calls `model.scrub_to(t)`. `SimModel` gains `preset_path`, `reload_from_file()`, `scrub_to(t)`, and an `_on_scrub(t)` hook; both tools attach only in preview (non-movie) mode.

**Tech Stack:** Godot 4.6, GDScript. Framework in `common/core/` (symlinked into each model as `core/`). Test runner: `common/core/tests/run_tests.gd`.

## Global Constraints

- **Preview-only.** The watcher and timeline attach only when `not movie_mode`. Movie renders are unchanged (no panel, no timeline, no watcher).
- **Timeline shows only when the scene has modulators** (`model.mod_stack != null and model.mod_stack.enabled`); otherwise it's hidden and inert.
- **Read-only** except the playhead drag. No editing of values in the preview.
- **Scrub = character-at-`t`, not frame-exact:** `scrub_to(t)` sets the modulation clock to `t`, recomposes, restarts (clears the canvas), and calls the `_on_scrub(t)` hook (model sets its own sim clock). Then play proceeds forward from `t`.
- **Wipe indicator:** each scrub-clear shows a brief full-screen white flash that fades within ~0.3 s, so the reset reads as intentional.
- **Hot-reload mtime resolution is whole seconds** (`FileAccess.get_modified_time`): two saves within one second may collapse into one reload — acceptable for human-paced edits; note it, don't engineer around it.
- **Do not break:** the existing tweak panel and its test (`test_tweak_panel_builds_rows`), movie renders, or legacy/non-modulator presets.
- **Determinism unaffected** — scrub only changes which `t` you view from.
- **Test command:** `godot --headless --path radial_burst --script res://core/tests/run_tests.gd` → `TESTS: N run, 0 failed`. Baseline is **43**; when you add tests, set the README `## Tests` line to the actual printed total and assert `0 failed` (the README number may lag).
- **Headless smoke pattern (preview mode):** `godot --headless --path radial_burst --quit-after <frames> -- --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN`. (Headless uses a dummy renderer, so `Control._draw` may not fire — smoke covers `_process`/scrub/watcher logic; the visual look is verified by the user + a controller-run xvfb screenshot.)

## File structure

- `common/core/scene_watcher.gd` (new) — `Node`; polls scene-file mtime, triggers reload. Pure helper `_is_newer(mtime)` for testing.
- `common/core/timeline.gd` (new) — `CanvasLayer`; the read-only timeline + playhead + wipe. Pure static helpers `time_to_x`, `value_to_frac` for testing.
- `common/core/sim_model.gd` — `preset_path`, `reload_from_file()`, `scrub_to(t)`, `_on_scrub(t)`; attach watcher + timeline in preview mode.
- `radial_burst/main.gd` — override `_on_scrub(t)` to set its `sim_t`.

---

### Task 1: SimModel hooks — `reload_from_file`, `scrub_to`, `_on_scrub`

**Files:**
- Modify: `common/core/sim_model.gd`
- Modify: `radial_burst/main.gd`
- Test: `common/core/tests/run_tests.gd` (add `test_reload_*`, `test_scrub_*`)
- Modify: `README.md` (test count)

**Interfaces:**
- Consumes: existing `PresetIO.load_preset`, `adopt_preset`, `resolve_and_restart`, `_compose`, `restart`, `mod_stack`.
- Produces: `SimModel.preset_path: String`; `SimModel.reload_from_file() -> void`; `SimModel.scrub_to(t: float) -> void`; `SimModel._on_scrub(t: float) -> void` (no-op default; radial_burst overrides to set `sim_t`).

- [ ] **Step 1: Write the failing tests**

In `common/core/tests/run_tests.gd`, add near the end (these instantiate the real model like `test_tweak_panel_builds_rows` does — `res://main.gd` is the model under `--path radial_burst`):

```gdscript
# ---------------- preview hooks (reload + scrub) ----------------

func test_reload_from_file_adopts_new_scene() -> void:
	var M = load("res://main.gd")
	var m = M.new()
	get_root().add_child(m)
	var path := "/tmp/vx_reload.json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"model": "radial_burst", "seed": 777, "duration_sec": 42.0}))
	fa.close()
	m.preset_path = path
	m.reload_from_file()
	check_eq(m.seed_value, 777, "reload adopts new seed")
	check_eq(m.duration_sec, 42.0, "reload adopts new duration")
	m.free()

func test_reload_bad_file_keeps_state() -> void:
	var M = load("res://main.gd")
	var m = M.new()
	get_root().add_child(m)
	m.seed_value = 5
	m.preset_path = "/tmp/vx_does_not_exist_reload.json"
	m.reload_from_file()  # missing file -> no-op, no crash
	check_eq(m.seed_value, 5, "missing file leaves state untouched")
	m.free()

func test_scrub_sets_clocks() -> void:
	var M = load("res://main.gd")
	var m = M.new()
	get_root().add_child(m)
	m.modulators_cfg = {"tween": [{"name": "b", "secs": 10.0, "targets": [{"to": "energy", "amount": 0.5}]}]}
	m.resolve_and_restart()
	m.scrub_to(5.0)
	check_eq(m.mod_stack.t, 5.0, "scrub sets the modulation clock")
	check_eq(m.sim_t, 5.0, "scrub sets sim_t via _on_scrub override")
	m.free()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: FAIL — `preset_path`/`reload_from_file`/`scrub_to` not defined.

- [ ] **Step 3: Add the hooks to `common/core/sim_model.gd`**

Add the field (after `var _elapsed: float = 0.0`):

```gdscript
var preset_path: String = ""
```

In `_ready()`, store the path — change the `if cli["preset"] != "":` block's start so the path is saved. Right after `var cli := RenderDriver.parse_user_args(OS.get_cmdline_user_args())`, add:

```gdscript
	preset_path = cli["preset"]
```

Add these methods (after `resolve_and_restart`):

```gdscript
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

func _on_scrub(_t: float) -> void:
	# Models with their own sim clock override this to set it to t.
	pass
```

- [ ] **Step 4: Override `_on_scrub` in `radial_burst/main.gd`**

Add this method (anywhere at top-level, e.g. right after `func restart() -> void: ... ` block — placement is free):

```gdscript
func _on_scrub(t: float) -> void:
	sim_t = t
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 46 run, 0 failed` (43 + 3). Use the actual printed total in Step 6.

- [ ] **Step 6: Update README test count** to the actual printed total.

- [ ] **Step 7: Commit**

```bash
git add common/core/sim_model.gd radial_burst/main.gd common/core/tests/run_tests.gd README.md
git commit -m "core: SimModel reload_from_file + scrub_to (+ radial_burst _on_scrub)"
```

---

### Task 2: `scene_watcher.gd` — hot-reload on file change

**Files:**
- Create: `common/core/scene_watcher.gd`
- Modify: `common/core/sim_model.gd` (attach in preview mode)
- Test: `common/core/tests/run_tests.gd` (add `test_scene_watcher_*`)
- Modify: `README.md` (test count)

**Interfaces:**
- Consumes: `SimModel.reload_from_file()` (Task 1), `SimModel.preset_path`.
- Produces: `scene_watcher.gd` `Node` with `setup(p_model, p_path: String) -> void`, `_is_newer(mtime: int) -> bool`, and a `_process` poll.

- [ ] **Step 1: Write the failing test**

In `common/core/tests/run_tests.gd`, add:

```gdscript
# ---------------- scene watcher ----------------

func test_scene_watcher_is_newer() -> void:
	var W = load("res://core/scene_watcher.gd")
	var w = W.new()
	w._last_mtime = 100
	check_eq(w._is_newer(200), true, "newer mtime -> changed")
	check_eq(w._is_newer(100), false, "equal mtime -> unchanged")
	check_eq(w._is_newer(50), false, "older mtime -> unchanged")
	w.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: FAIL — missing `res://core/scene_watcher.gd`.

- [ ] **Step 3: Implement `common/core/scene_watcher.gd`**

```gdscript
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
```

- [ ] **Step 4: Attach the watcher in preview mode**

In `common/core/sim_model.gd`, change the preview block in `_ready()`:

```gdscript
	if not movie_mode:
		_attach_panel()
```

to:

```gdscript
	if not movie_mode:
		_attach_panel()
		_attach_scene_tools()
```

and add the method:

```gdscript
func _attach_scene_tools() -> void:
	var Watcher = load("res://core/scene_watcher.gd")
	var w = Watcher.new()
	add_child(w)
	w.setup(self, preset_path)
```

- [ ] **Step 5: Run test + smoke**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 47 run, 0 failed` (use actual total).
Run: `godot --headless --path radial_burst --quit-after 90 -- --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN`
Expected: `CLEAN` (preview attaches the watcher without error).

- [ ] **Step 6: Update README test count** to the actual printed total.

- [ ] **Step 7: Commit**

```bash
git add common/core/scene_watcher.gd common/core/sim_model.gd common/core/tests/run_tests.gd README.md
git commit -m "core: scene_watcher.gd — hot-reload the scene file in preview mode"
```

---

### Task 3: `timeline.gd` — read-only scrub timeline + wipe

**Files:**
- Create: `common/core/timeline.gd`
- Modify: `common/core/sim_model.gd` (attach in preview mode)
- Test: `common/core/tests/run_tests.gd` (add `test_timeline_*`)
- Modify: `README.md` (test count)

**Interfaces:**
- Consumes: `mod_sources.gd` (`MS.tween`, `MS.lfo`), `SimModel.scrub_to()` (Task 1), `model.mod_stack` (`.t`, `.tweens`, `.lfos`, `.envelopes`, `.enabled`), `model.duration_sec`.
- Produces: `timeline.gd` `CanvasLayer` with static `time_to_x(t, dur, w) -> float` and `value_to_frac(v, lo, hi) -> float`.

- [ ] **Step 1: Write the failing tests**

In `common/core/tests/run_tests.gd`, add:

```gdscript
# ---------------- timeline ----------------

func test_timeline_time_to_x() -> void:
	var T = load("res://core/timeline.gd")
	check_eq(T.time_to_x(0.0, 10.0, 100.0), 0.0, "t=0 -> x=0")
	check_eq(T.time_to_x(10.0, 10.0, 100.0), 100.0, "t=dur -> x=w")
	check_eq(T.time_to_x(5.0, 10.0, 100.0), 50.0, "midpoint")
	check_eq(T.time_to_x(20.0, 10.0, 100.0), 100.0, "past end clamps to w")

func test_timeline_value_to_frac() -> void:
	var T = load("res://core/timeline.gd")
	check_eq(T.value_to_frac(5.0, 0.0, 10.0), 0.5, "midpoint -> 0.5")
	check_eq(T.value_to_frac(-5.0, 0.0, 10.0), 0.0, "below min clamps to 0")
	check_eq(T.value_to_frac(15.0, 0.0, 10.0), 1.0, "above max clamps to 1")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: FAIL — missing `res://core/timeline.gd`.

- [ ] **Step 3: Implement `common/core/timeline.gd`**

```gdscript
extends CanvasLayer
# Read-only scrub timeline for preview mode. Draws each modulation source as the
# curve/motion it produces over the render duration, with a draggable playhead;
# dragging calls model.scrub_to(t) (character-at-t) and flashes a wipe overlay.
# Shown only when the scene has modulators.

const MS = preload("res://core/mod_sources.gd")
const STRIP_H := 150.0

var model
var _strip: Control
var _wipe: Control
var _wipe_alpha := 0.0

func _init(p_model) -> void:
	model = p_model
	layer = 90  # below the tweak panel (100), above the render
	_wipe = Control.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.draw.connect(_draw_wipe)
	add_child(_wipe)
	_strip = Control.new()
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_strip.offset_top = -STRIP_H
	_strip.draw.connect(_draw_strip)
	_strip.gui_input.connect(_on_strip_input)
	add_child(_strip)

static func time_to_x(t: float, dur: float, w: float) -> float:
	return clampf(t / maxf(dur, 0.0001), 0.0, 1.0) * w

static func value_to_frac(v: float, lo: float, hi: float) -> float:
	return clampf((v - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)

func _enabled() -> bool:
	return model != null and model.mod_stack != null and model.mod_stack.enabled

func _process(delta: float) -> void:
	var on := _enabled()
	_strip.visible = on
	_wipe.visible = on and _wipe_alpha > 0.0
	if not on:
		return
	if _wipe_alpha > 0.0:
		_wipe_alpha = maxf(_wipe_alpha - delta * 3.0, 0.0)
		_wipe.queue_redraw()
	_strip.queue_redraw()

func _draw_wipe() -> void:
	if _wipe_alpha <= 0.0:
		return
	_wipe.draw_rect(Rect2(Vector2.ZERO, _wipe.size), Color(1, 1, 1, 0.35 * _wipe_alpha), true)

func _draw_strip() -> void:
	var w := _strip.size.x
	var h := _strip.size.y
	var dur: float = maxf(model.duration_sec, 0.0001)
	var font := ThemeDB.fallback_font
	_strip.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.66), true)
	_strip.draw_line(Vector2(0, 0), Vector2(w, 0), Color(0.4, 0.6, 0.9, 0.8), 2.0)

	var lanes := []
	for tw in model.mod_stack.tweens:
		lanes.append({"kind": "tween", "src": tw})
	for lf in model.mod_stack.lfos:
		lanes.append({"kind": "lfo", "src": lf})
	for en in model.mod_stack.envelopes:
		lanes.append({"kind": "env", "src": en})

	var px := time_to_x(model.mod_stack.t, dur, w)  # playhead x
	var n := maxi(lanes.size(), 1)
	var lane_h := (h - 22.0) / float(n)
	for i in lanes.size():
		var top := 4.0 + i * lane_h
		var bot := top + lane_h - 4.0
		var L = lanes[i]
		var src = L["src"]
		var col := Color(0.5, 0.8, 1.0)
		var pts := PackedVector2Array()
		var cur_frac := 0.0
		match L["kind"]:
			"tween":
				col = Color(1.0, 0.8, 0.2)
				for sx in range(0, int(w), 3):
					var t := (float(sx) / w) * dur
					pts.append(Vector2(sx, lerpf(bot, top, clampf(MS.tween(t, src["secs"], src["curve"], src["from"], src["to"]), 0.0, 1.0))))
				cur_frac = clampf(MS.tween(model.mod_stack.t, src["secs"], src["curve"], src["from"], src["to"]), 0.0, 1.0)
			"lfo":
				col = Color(0.4, 1.0, 0.7)
				for sx in range(0, int(w), 3):
					var t := (float(sx) / w) * dur
					pts.append(Vector2(sx, lerpf(bot, top, (MS.lfo(t, src["rate"], src["shape"], src["phase"]) + 1.0) * 0.5)))
				cur_frac = (MS.lfo(model.mod_stack.t, src["rate"], src["shape"], src["phase"]) + 1.0) * 0.5
			"env":
				col = Color(1.0, 0.4, 0.6)
				var active: bool = src["instances"].size() > 0
				_strip.draw_rect(Rect2(0, top, w, lane_h - 4.0), Color(col.r, col.g, col.b, 0.16 if active else 0.05), true)
		if pts.size() >= 2:
			_strip.draw_polyline(pts, col, 1.5)
		if L["kind"] != "env":
			# live "what it does now" dot riding the curve at the playhead
			_strip.draw_circle(Vector2(px, lerpf(bot, top, cur_frac)), 4.0, Color.WHITE)
		_strip.draw_string(font, Vector2(6, top + 14), str(src.get("name", L["kind"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1.0, 0.7))

	# playhead + time
	_strip.draw_line(Vector2(px, 0), Vector2(px, h), Color(1, 1, 1, 0.9), 2.0)
	var tt := int(model.mod_stack.t)
	_strip.draw_string(font, Vector2(clampf(px + 5.0, 0.0, w - 56.0), 16), "%d:%02d" % [tt / 60, tt % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _on_strip_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_scrub_at(ev.position.x)
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_scrub_at(ev.position.x)

func _scrub_at(x: float) -> void:
	if not _enabled():
		return
	var dur: float = maxf(model.duration_sec, 0.0001)
	var t := clampf(x / maxf(_strip.size.x, 1.0), 0.0, 1.0) * dur
	model.scrub_to(t)
	_wipe_alpha = 1.0
	_wipe.queue_redraw()
```

- [ ] **Step 4: Attach the timeline in preview mode**

In `common/core/sim_model.gd`, extend `_attach_scene_tools()` (from Task 2) to also add the timeline:

```gdscript
func _attach_scene_tools() -> void:
	var Watcher = load("res://core/scene_watcher.gd")
	var w = Watcher.new()
	add_child(w)
	w.setup(self, preset_path)
	var Timeline = load("res://core/timeline.gd")
	add_child(Timeline.new(self))
```

- [ ] **Step 5: Run tests + smoke**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 49 run, 0 failed` (use actual total).
Run: `godot --headless --path radial_burst --quit-after 120 -- --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN`
Expected: `CLEAN` (timeline `_process`/attach run without error; `_draw` is exercised under the controller's xvfb screenshot, not headless).

- [ ] **Step 6: Update README test count** to the actual printed total.

- [ ] **Step 7: Commit**

```bash
git add common/core/timeline.gd common/core/sim_model.gd common/core/tests/run_tests.gd README.md
git commit -m "core: timeline.gd — read-only scrub timeline (curves + playhead + wipe)"
```

- [ ] **Step 8: USER REVIEW HANDOFF (controller)**

The controller runs a short xvfb-backed preview and captures a frame to confirm the timeline draws (catches `_draw` errors headless can't), then hands the screenshot + "open the preview to scrub" instructions to the user for visual review. (`_draw` correctness and the look/feel are the user's gate; the screenshot is only a smoke that it renders.)

---

## Self-Review

**Spec coverage** (against `2026-06-19-scene-authoring-design.md`, Phase 1):
- Hot-reload (watch file, reload on save, bad save ignored) → Task 1 `reload_from_file` + Task 2 `scene_watcher`. ✓
- Scrub timeline drawn as source curves/motion + playhead → Task 3 `_draw_strip` (tween/lfo curves, envelope lane, playhead). ✓
- Live composed values as visual indicators → Task 3 the white "current value" dot riding each curve at the playhead. ✓
- Scrub = character-at-`t` (set clocks, recompose, restart, `_on_scrub`) → Task 1 `scrub_to` + radial_burst `_on_scrub`. ✓
- Wipe indicator on scrub-clear → Task 3 `_wipe`/`_wipe_alpha`/`_scrub_at`. ✓
- Shown only with modulators; preview-only; tweak panel untouched → Task 3 `_enabled()`, Tasks 2–3 attach under `not movie_mode`, panel code unchanged. ✓
- mtime-seconds limitation noted → Task 2 file header + Global Constraints. ✓
- Verification: pure helpers unit-tested (time_to_x, value_to_frac, _is_newer), reload/scrub integration-tested, headless smokes, controller xvfb screenshot, user visual review. ✓
- Deferred (no task, per spec): designer app (Phase 2), playback transport, MIDI, grab-reshape, frame-exact scrub.

**Placeholder scan:** none — all code/commands concrete. Test totals (46/47/49) are computed from baseline 43 with an explicit "use the actual printed total" instruction.

**Type consistency:** `scrub_to(float)`/`reload_from_file()`/`preset_path`/`_on_scrub(float)` consistent across Task 1 (def), its tests, Task 2/3 (callers). `mod_stack` fields `.t/.tweens/.lfos/.envelopes/.enabled` match `modulation.gd`. `MS.tween(t,secs,curve,from,to)` / `MS.lfo(t,rate,shape,phase)` match `mod_sources.gd`. `_attach_scene_tools` defined in Task 2, extended in Task 3. `time_to_x`/`value_to_frac` static signatures match their tests.
