# Designer — Phase 2a (edit an existing scene) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A visual Designer (a `--designer` mode inside a model's Godot project) that loads an existing scene + the model schema, lets you tune the superparam bases, all basic params, and the existing sources' params/oscillators/routing-amounts via Ableton-style knobs and signal editors, and writes `scene.json` on every edit (so the Phase 1 preview hot-reloads). Final task adds a transport that animates the knobs with the live modulated value.

**Architecture:** Code-built Godot `Control` widgets under `common/core/designer/` (no `.tscn`, mirroring `tweak_panel.gd`). `SimModel._ready` sees `--designer` and attaches `designer.gd` instead of building the sim; the Designer reads the schema from `model.get_schema()` and the scene from the already-adopted `macros`/`overrides`/`modulators_cfg`, and saves via `PresetIO.save_preset`. Previews/animation reuse `mod_sources`/`modulation` (zero drift).

**Tech Stack:** Godot 4.6, GDScript. Reuses `common/core/` (`param_schema`, `mod_sources`, `modulation`, `preset_io`, `render_driver`). Test runner: `common/core/tests/run_tests.gd`.

## Global Constraints

- **Designer is a mode in the model's project:** launched `godot --path <model> -- --designer --preset presets/<name>.json`. When `--designer` is set, `SimModel._ready` attaches the Designer and does NOT build the sim (returns before `resolve_and_restart`). Schema comes from `model.get_schema()`; no export, no cross-project.
- **2a edits an existing scene only** — no add/remove of sources, routings, or oscillators (those are 2b). Editing changes values/shapes/amounts of what's already in the scene + the bases.
- **Every edit writes the scene file** (`PresetIO.save_preset` to `model.preset_path`), debounced ~150 ms, so the preview hot-reloads.
- **Knobs are fixed-size; previews flex; panel is responsive** (fills window; `Control` anchors + `VBox`/`HBox` reflow). No fixed pixel width on the panel.
- **Reuse `mod_sources`** for all previews and live values — never re-derive curve math.
- **Determinism unaffected**; the preview/movie paths are untouched (Designer only attaches under `--designer`).
- **No `.tscn`** — build Controls in code (follow `tweak_panel.gd`).
- **Test command:** `godot --headless --path radial_burst --script res://core/tests/run_tests.gd` → `TESTS: N run, 0 failed`. Baseline **51**; when you add tests set the README line to the actual printed total.
- **GUI verification:** pure logic is unit-tested; rendering is checked by an **xvfb screenshot** (the controller captures it — headless `_draw` doesn't fire) and the user's hands-on review. Per-task UI smoke: `godot --headless --path radial_burst --quit-after 90 -- --designer --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN`.

## File structure

- `common/core/render_driver.gd` — add `--designer` parse.
- `common/core/sim_model.gd` — `_attach_designer()`; `--designer` branch in `_ready`.
- `common/core/designer/designer.gd` — root: holds scene+schema, builds panels, saves on edit, transport+animation.
- `common/core/designer/knob.gd` — animated Ableton knob.
- `common/core/designer/wave_preview.gd` — draws a sampled signal.
- `common/core/designer/source_card.gd` — per-source editor (tween/lfo/env).
- `common/core/designer/bases_panel.gd` — superparam knobs + "all params A–Z" zippy.
- Each model already symlinks `core -> ../common/core`, so `res://core/designer/*` resolves.

---

### Task 1: `--designer` launch mode

**Files:**
- Modify: `common/core/render_driver.gd`
- Modify: `common/core/sim_model.gd`
- Create: `common/core/designer/designer.gd` (stub for now)
- Test: `common/core/tests/run_tests.gd`
- Modify: `README.md` (test count)

**Interfaces:**
- Produces: `RenderDriver.parse_user_args(...)["designer"]: bool`; `SimModel._attach_designer()`; `designer.gd` with `func setup(model) -> void` (stores the model; later tasks build the UI).

- [ ] **Step 1: Write the failing test**

Add to `common/core/tests/run_tests.gd` (in the render-driver section):

```gdscript
func test_parse_user_args_designer_flag() -> void:
	var out := RD.parse_user_args(PackedStringArray(["--designer", "--preset", "/tmp/s.json"]))
	check_eq(out["designer"], true, "--designer parsed as true")
	check_eq(out["preset"], "/tmp/s.json", "preset still parsed alongside --designer")
	var out2 := RD.parse_user_args(PackedStringArray([]))
	check_eq(out2["designer"], false, "no --designer -> false")
```

- [ ] **Step 2: Run it — expect FAIL** (`designer` key missing).

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`

- [ ] **Step 3: Add `--designer` to `render_driver.gd`**

In `parse_user_args`, change the initial `out` and add a branch. The function becomes:

```gdscript
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
```

- [ ] **Step 4: Create the stub `common/core/designer/designer.gd`**

```gdscript
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
```

- [ ] **Step 5: Attach the Designer in `sim_model.gd`**

In `_ready()`, replace the tail (from `resolve_and_restart()` onward) with a `--designer` branch first:

```gdscript
	if cli["designer"]:
		_attach_designer()
		return
	resolve_and_restart()
	if not movie_mode:
		_attach_panel()
		_attach_scene_tools()
```

(`adopt_preset` has already run above when `--preset` was given, so the scene data is on `self`.) Add the method:

```gdscript
func _attach_designer() -> void:
	var Designer = load("res://core/designer/designer.gd")
	if Designer == null:
		return
	var d = Designer.new()
	add_child(d)
	d.setup(self)
```

- [ ] **Step 6: Run tests + UI smoke**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd` → `TESTS: 52 run, 0 failed` (use actual total).
Run: `godot --headless --path radial_burst --quit-after 60 -- --designer --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN` → `CLEAN` (Designer attaches, sim not built).

- [ ] **Step 7: Update README count; commit**

```bash
git add common/core/render_driver.gd common/core/sim_model.gd common/core/designer/designer.gd common/core/tests/run_tests.gd README.md
git commit -m "designer: --designer launch mode attaches Designer (no sim) + reads schema"
```

---

### Task 2: `knob.gd` — animated Ableton knob

**Files:**
- Create: `common/core/designer/knob.gd`
- Test: `common/core/tests/run_tests.gd`
- Modify: `README.md`

**Interfaces:**
- Produces: a `Control` with `signal value_changed(value: float)`; `setup(min_v, max_v, value, default_v, ring_color: Color) -> void`; `set_live(v: float) -> void` (NAN hides the ring); static `frac(v, lo, hi) -> float` and `angle(frac) -> float`.

- [ ] **Step 1: Write the failing tests**

```gdscript
# ---------------- designer knob ----------------

const Knob = preload("res://core/designer/knob.gd")

func test_knob_frac() -> void:
	check_eq(Knob.frac(5.0, 0.0, 10.0), 0.5, "midpoint -> 0.5")
	check_eq(Knob.frac(-1.0, 0.0, 10.0), 0.0, "below min clamps")
	check_eq(Knob.frac(11.0, 0.0, 10.0), 1.0, "above max clamps")

func test_knob_angle_sweep() -> void:
	check_eq(Knob.angle(0.0), deg_to_rad(135.0), "frac 0 -> 135deg")
	check_eq(Knob.angle(1.0), deg_to_rad(405.0), "frac 1 -> 135+270 deg")
```

- [ ] **Step 2: Run — expect FAIL** (missing `knob.gd`).

- [ ] **Step 3: Implement `common/core/designer/knob.gd`**

```gdscript
extends Control
# Ableton-style rotary knob. Vertical-drag changes value; Shift = fine;
# double-click resets to default. Pointer shows the set value; an optional bright
# ring shows a live (modulated) value. Fixed-size; emits value_changed(v).

signal value_changed(value: float)

var min_v := 0.0
var max_v := 1.0
var value := 0.0
var default_v := 0.0
var live_v := NAN  # NAN -> no ring
var ring_color := Color(0.5, 0.8, 1.0)
var _drag := false

func setup(p_min: float, p_max: float, p_value: float, p_default: float, p_ring := Color(0.5, 0.8, 1.0)) -> void:
	min_v = p_min
	max_v = p_max
	value = p_value
	default_v = p_default
	ring_color = p_ring
	custom_minimum_size = Vector2(40, 40)
	queue_redraw()

func set_live(v: float) -> void:
	live_v = v
	queue_redraw()

static func frac(v: float, lo: float, hi: float) -> float:
	return clampf((v - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)

static func angle(f: float) -> float:
	return deg_to_rad(135.0 + 270.0 * f)  # 270deg sweep, gap at bottom

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	draw_circle(c, r, Color(0.11, 0.13, 0.19))
	draw_arc(c, r, angle(0.0), angle(1.0), 48, Color(0.24, 0.29, 0.41), 2.0)
	if not is_nan(live_v):
		var lf := frac(live_v, min_v, max_v)
		draw_arc(c, r, angle(0.0), angle(lf), 48, ring_color, 3.0)
		draw_circle(c + Vector2.from_angle(angle(lf)) * r, 3.5, ring_color)
	var a := angle(frac(value, min_v, max_v))
	draw_line(c, c + Vector2.from_angle(a) * (r - 2.0), Color(0.88, 0.92, 0.97), 2.0)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and ev.double_click:
			value = default_v
			value_changed.emit(value)
			queue_redraw()
		else:
			_drag = ev.pressed
	elif ev is InputEventMouseMotion and _drag:
		var step := (max_v - min_v) / 200.0
		if ev.shift_pressed:
			step *= 0.2
		value = clampf(value - ev.relative.y * step, min_v, max_v)
		value_changed.emit(value)
		queue_redraw()
```

- [ ] **Step 4: Run — expect PASS** (`TESTS: 54 run, 0 failed`; use actual).

- [ ] **Step 5: Update README; commit**

```bash
git add common/core/designer/knob.gd common/core/tests/run_tests.gd README.md
git commit -m "designer: knob.gd — animated Ableton rotary (drag/fine/reset, live ring)"
```

---

### Task 3: `wave_preview.gd` — signal preview

**Files:**
- Create: `common/core/designer/wave_preview.gd`
- Test: `common/core/tests/run_tests.gd`
- Modify: `README.md`

**Interfaces:**
- Produces: a `Control` with `set_sampler(cb: Callable, lo: float, hi: float) -> void` where `cb.call(x01: float) -> float` returns the signal value for x in [0,1]; draws it as a polyline scaled into [lo,hi]. Static `points(cb, lo, hi, w, h, n) -> PackedVector2Array` for testing.

- [ ] **Step 1: Write the failing test**

```gdscript
# ---------------- designer wave preview ----------------

const WavePreview = preload("res://core/designer/wave_preview.gd")

func test_wave_points_map_range() -> void:
	var flat := func(_x): return 0.0
	var pts := WavePreview.points(flat, -1.0, 1.0, 100.0, 40.0, 5)
	check_eq(pts.size(), 5, "one point per sample")
	check_eq(pts[0].x, 0.0, "first x = 0")
	check(absf(pts[0].y - 20.0) < 0.001, "value 0 in [-1,1] maps to vertical middle")
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `common/core/designer/wave_preview.gd`**

```gdscript
extends Control
# Draws a signal as a polyline. The sampler maps x in [0,1] -> a value; values are
# scaled from [lo,hi] into the control height (hi at top). Flexes to its width.

var _cb: Callable
var _lo := -1.0
var _hi := 1.0
var _color := Color(0.5, 0.8, 1.0)

func set_sampler(cb: Callable, lo: float, hi: float, color := Color(0.5, 0.8, 1.0)) -> void:
	_cb = cb
	_lo = lo
	_hi = hi
	_color = color
	custom_minimum_size = Vector2(0, 44)
	queue_redraw()

static func points(cb: Callable, lo: float, hi: float, w: float, h: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if n < 2 or not cb.is_valid():
		return out
	for i in n:
		var x01 := float(i) / float(n - 1)
		var v: float = cb.call(x01)
		var f := clampf((v - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)
		out.append(Vector2(x01 * w, lerpf(h, 0.0, f)))
	return out

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.08), true)
	if not _cb.is_valid():
		return
	var pts := points(_cb, _lo, _hi, size.x, size.y, maxi(int(size.x / 3.0), 2))
	if pts.size() >= 2:
		draw_polyline(pts, _color, 1.5)
```

- [ ] **Step 4: Run — expect PASS** (use actual total). **Step 5: README + commit**

```bash
git add common/core/designer/wave_preview.gd common/core/tests/run_tests.gd README.md
git commit -m "designer: wave_preview.gd — polyline preview of a sampled signal"
```

---

### Task 4: `source_card.gd` — per-source editor

**Files:**
- Create: `common/core/designer/source_card.gd`
- Test: `common/core/tests/run_tests.gd`
- Modify: `README.md`

**Interfaces:**
- Consumes: `Knob`, `WavePreview`, `MS = mod_sources`.
- Produces: a `VBoxContainer` with `signal changed()`; `setup(kind: String, src: Dictionary, schema: Dictionary) -> void` (kind ∈ `tween|lfo|env`); `to_config() -> Dictionary` returns the edited source dict in scene format. Mutates its own copy of `src`; emits `changed` on any knob/picker edit. Preview-on-top, controls below; routing rows show destination + amount knob (amount editable, destination read-only in 2a).

- [ ] **Step 1: Write the failing test** (logic: round-trips a source through setup → to_config, and an amount edit updates it)

```gdscript
# ---------------- designer source card ----------------

const SourceCard = preload("res://core/designer/source_card.gd")

func test_source_card_tween_roundtrip() -> void:
	var src := {"name": "build", "secs": 275.0, "curve": "linear", "from": 0.0, "to": 1.0,
		"targets": [{"to": "energy", "amount": 0.45}]}
	var card = SourceCard.new()
	get_root().add_child(card)
	card.setup("tween", src, _demo_schema())
	var cfg := card.to_config()
	check_eq(cfg["secs"], 275.0, "tween secs round-trips")
	check_eq(cfg["targets"][0]["to"], "energy", "target name preserved")
	check_eq(cfg["targets"][0]["amount"], 0.45, "target amount round-trips")
	card.free()

func test_source_card_lfo_roundtrip() -> void:
	var src := {"name": "w", "oscillators": [{"shape": "sine", "period_sec": 40.0, "phase_deg": 0.0, "amount": 0.6}],
		"targets": [{"to": "grit", "amount": 0.2}]}
	var card = SourceCard.new()
	get_root().add_child(card)
	card.setup("lfo", src, _demo_schema())
	var cfg := card.to_config()
	check_eq(cfg["oscillators"][0]["period_sec"], 40.0, "osc period round-trips")
	card.free()
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `common/core/designer/source_card.gd`**

```gdscript
extends VBoxContainer
# Editor for one modulation source (tween | lfo | env). Preview-on-top, controls
# below, then source-centric routing rows. Holds an editable copy of the source;
# to_config() returns it in scene format. Emits `changed` on any edit.

const Knob = preload("res://core/designer/knob.gd")
const WavePreview = preload("res://core/designer/wave_preview.gd")
const MS = preload("res://core/mod_sources.gd")

signal changed()

var kind := ""
var src := {}
var schema := {}
var _knobs := {}  # path -> Knob (for later animation hooks if needed)

func setup(p_kind: String, p_src: Dictionary, p_schema: Dictionary) -> void:
	kind = p_kind
	src = p_src.duplicate(true)
	schema = p_schema
	add_theme_constant_override("separation", 6)
	_build()

func to_config() -> Dictionary:
	return src

func _color() -> Color:
	match kind:
		"tween": return Color(1.0, 0.8, 0.2)
		"lfo": return Color(0.4, 1.0, 0.7)
		_: return Color(1.0, 0.4, 0.6)

func _build() -> void:
	var hdr := Label.new()
	hdr.text = "%s · %s" % [kind.to_upper(), str(src.get("name", kind))]
	hdr.add_theme_color_override("font_color", _color())
	add_child(hdr)

	var prev := WavePreview.new()
	prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(prev)
	_wire_preview(prev)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 10)
	add_child(ctrl)
	match kind:
		"tween":
			ctrl.add_child(_knob("secs", src, "secs", 1.0, 600.0))
			ctrl.add_child(_knob("from", src, "from", 0.0, 1.0))
			ctrl.add_child(_knob("to", src, "to", 0.0, 1.0))
		"lfo":
			for i in src.get("oscillators", []).size():
				var o = src["oscillators"][i]
				ctrl.add_child(_knob("osc%d.period_sec" % i, o, "period_sec", 1.0, 120.0))
				ctrl.add_child(_knob("osc%d.amount" % i, o, "amount", 0.0, 1.0))
		"env":
			ctrl.add_child(_knob("attack", src, "attack", 0.0, 1.0))
			ctrl.add_child(_knob("decay", src, "decay", 0.0, 2.0))
			ctrl.add_child(_knob("peak", src, "peak", 0.0, 2.0))

	for tg in src.get("targets", []):
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = "→ %s" % str(tg.get("to", "?"))
		lab.custom_minimum_size = Vector2(160, 0)
		row.add_child(lab)
		row.add_child(_knob_for(tg, "amount", -10.0, 10.0, prev))
		add_child(row)

func _knob(_path: String, holder: Dictionary, key: String, lo: float, hi: float) -> VBoxContainer:
	return _make_labeled_knob(holder, key, lo, hi, key, null)

func _knob_for(holder: Dictionary, key: String, lo: float, hi: float, prev) -> VBoxContainer:
	return _make_labeled_knob(holder, key, lo, hi, key, prev)

func _make_labeled_knob(holder: Dictionary, key: String, lo: float, hi: float, label: String, prev) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var k = Knob.new()
	k.setup(lo, hi, float(holder.get(key, 0.0)), float(holder.get(key, 0.0)), _color())
	k.value_changed.connect(func(v):
		holder[key] = v
		if prev != null:
			_wire_preview(prev)
		changed.emit())
	box.add_child(k)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)
	return box

func _wire_preview(prev) -> void:
	match kind:
		"tween":
			var secs: float = maxf(float(src.get("secs", 1.0)), 0.0001)
			prev.set_sampler(func(x): return MS.tween(x * secs, secs, str(src.get("curve", "linear")), float(src.get("from", 0.0)), float(src.get("to", 1.0))), 0.0, 1.0, _color())
		"lfo":
			var oscs: Array = src.get("oscillators", [])
			var span := 0.0
			for o in oscs:
				span = maxf(span, float(o.get("period_sec", 30.0)))
			span = maxf(span * 2.0, 0.0001)
			prev.set_sampler(func(x): return MS.lfo_value(x * span, oscs), -1.0, 1.0, _color())
		"env":
			var dur: float = maxf(float(src.get("attack", 0.01)) + float(src.get("decay", 0.3)), 0.0001)
			prev.set_sampler(func(x): return MS.envelope(x * dur, float(src.get("attack", 0.01)), float(src.get("decay", 0.3)), float(src.get("peak", 1.0))), 0.0, maxf(float(src.get("peak", 1.0)), 0.0001), _color())
		_:
			pass
```

- [ ] **Step 4: Run — expect PASS** (use actual total).
- [ ] **Step 5: UI smoke** — covered once wired in Task 6; for now confirm the suite passes. **README + commit**

```bash
git add common/core/designer/source_card.gd common/core/tests/run_tests.gd README.md
git commit -m "designer: source_card.gd — per-source editor (tween/lfo/env) with preview + knobs"
```

---

### Task 5: `bases_panel.gd` — superparams + all-params zippy

**Files:**
- Create: `common/core/designer/bases_panel.gd`
- Test: `common/core/tests/run_tests.gd`
- Modify: `README.md`

**Interfaces:**
- Consumes: `Knob`.
- Produces: a `VBoxContainer` with `signal changed()`; `setup(schema, macros: Dictionary, overrides: Dictionary) -> void`; `macro_values() -> Dictionary` and `override_values() -> Dictionary` (the edited values). Superparam knobs always shown; a "Show all basic params (A–Z)" button toggles a section of knobs for every numeric param (alphabetical), seeded from override-or-default. Static `numeric_param_names_sorted(schema) -> Array` for testing.

- [ ] **Step 1: Write the failing test**

```gdscript
# ---------------- designer bases panel ----------------

const BasesPanel = preload("res://core/designer/bases_panel.gd")

func test_bases_param_names_sorted() -> void:
	var names := BasesPanel.numeric_param_names_sorted(_demo_schema())
	# _demo_schema numeric params are "speed", "count", "plain" -> sorted
	check_eq(names, ["count", "plain", "speed"], "numeric params sorted A-Z")

func test_bases_edit_updates_macro() -> void:
	var bp = BasesPanel.new()
	get_root().add_child(bp)
	bp.setup(_demo_schema(), {"energy": 0.5}, {})
	bp.set_macro("energy", 0.8)
	check_eq(bp.macro_values()["energy"], 0.8, "macro edit reflected in macro_values")
	bp.free()
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `common/core/designer/bases_panel.gd`**

```gdscript
extends VBoxContainer
# Superparam (macro) knobs, always shown; plus a "Show all basic params (A-Z)"
# zippy that reveals a knob per numeric param (alphabetical), seeded from the
# scene's override (or the schema default). Emits `changed` on any edit.

const Knob = preload("res://core/designer/knob.gd")

signal changed()

var schema := {}
var macros := {}
var overrides := {}
var _all_box: VBoxContainer

func setup(p_schema: Dictionary, p_macros: Dictionary, p_overrides: Dictionary) -> void:
	schema = p_schema
	macros = p_macros.duplicate(true)
	overrides = p_overrides.duplicate(true)
	_build()

func macro_values() -> Dictionary:
	return macros

func override_values() -> Dictionary:
	return overrides

func set_macro(name: String, v: float) -> void:
	macros[name] = v

static func numeric_param_names_sorted(p_schema: Dictionary) -> Array:
	var names := []
	for p in p_schema["params"]:
		if p["type"] == "float" or p["type"] == "int":
			names.append(p["name"])
	names.sort()
	return names

func _param_def(name: String) -> Dictionary:
	for p in schema["params"]:
		if p["name"] == name:
			return p
	return {}

func _build() -> void:
	var t := Label.new()
	t.text = "BASES — superparams"
	t.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for m in schema["macros"]:
		row.add_child(_macro_knob(m))

	var toggle := Button.new()
	toggle.text = "▸ Show all basic params (A–Z)"
	toggle.flat = true
	add_child(toggle)
	_all_box = VBoxContainer.new()
	_all_box.visible = false
	add_child(_all_box)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	_all_box.add_child(grid)
	for name in numeric_param_names_sorted(schema):
		grid.add_child(_param_knob(name))
	toggle.pressed.connect(func():
		_all_box.visible = not _all_box.visible
		toggle.text = ("▾ " if _all_box.visible else "▸ ") + "Show all basic params (A–Z)")

func _macro_knob(m: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	var k = Knob.new()
	var v := float(macros.get(m["name"], m["default"]))
	k.setup(0.0, 1.0, v, float(m["default"]), Color(0.6, 0.85, 1.0))
	k.value_changed.connect(func(nv):
		macros[m["name"]] = nv
		changed.emit())
	box.add_child(k)
	var l := Label.new(); l.text = m["name"]; l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)
	return box

func _param_knob(name: String) -> VBoxContainer:
	var p := _param_def(name)
	var box := VBoxContainer.new()
	var k = Knob.new()
	var v := float(overrides.get(name, p["default"]))
	k.setup(float(p["min"]), float(p["max"]), v, float(p["default"]), Color(0.7, 0.78, 0.9))
	k.value_changed.connect(func(nv):
		overrides[name] = nv
		changed.emit())
	box.add_child(k)
	var l := Label.new(); l.text = name; l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)
	return box
```

- [ ] **Step 4: Run — expect PASS** (use actual). **Step 5: README + commit**

```bash
git add common/core/designer/bases_panel.gd common/core/tests/run_tests.gd README.md
git commit -m "designer: bases_panel.gd — superparam knobs + all-params (A–Z) zippy"
```

---

### Task 6: `designer.gd` assembly + scene save

**Files:**
- Modify: `common/core/designer/designer.gd` (replace the stub body)
- Test: `common/core/tests/run_tests.gd`
- Modify: `README.md`

**Interfaces:**
- Consumes: `BasesPanel`, `SourceCard`, `PresetIO`, `ModStack`. Reads `model.get_schema()`, `model.macros`, `model.overrides`, `model.modulators_cfg`, `model.seed_value`, `model.duration_sec`, `model.preset_path`.
- Produces: a scrollable Designer that builds BasesPanel + a SourceCard per source; on any `changed`, rebuilds the scene dict and writes it (debounced) via `PresetIO.save_preset`. `current_scene() -> Dictionary` (the live scene) for testing.

- [ ] **Step 1: Write the failing test** (scene assembly + save round-trips)

```gdscript
func test_designer_saves_edited_scene() -> void:
	var M = load("res://main.gd")
	var m = M.new()
	get_root().add_child(m)
	m.preset_path = "/tmp/vx_designer_scene.json"
	m.modulators_cfg = {"lfo": [{"name": "w", "oscillators": [{"shape": "sine", "period_sec": 40.0, "phase_deg": 0.0, "amount": 0.6}], "targets": [{"to": "grit", "amount": 0.2}]}]}
	var Designer = load("res://core/designer/designer.gd")
	var d = Designer.new()
	get_root().add_child(d)
	d.setup(m)
	d.save_now()  # writes preset_path
	var res := PIO.load_preset("/tmp/vx_designer_scene.json", m.get_schema(), m.model_name())
	check(res["ok"], "designer wrote a loadable scene")
	check_eq(res["preset"]["modulators"]["lfo"][0]["oscillators"][0]["period_sec"], 40.0, "modulators round-trip through the designer's save")
	m.free(); d.free()
```

- [ ] **Step 2: Run — expect FAIL** (`save_now`/assembly missing).

- [ ] **Step 3: Replace `common/core/designer/designer.gd`**

```gdscript
extends Control
# Root of the visual Designer. Builds a BasesPanel + a SourceCard per source from
# the model's adopted scene, and writes scene.json (debounced) on any edit so the
# Phase 1 preview hot-reloads. Reuses the model's schema (get_schema()).

const PresetIO = preload("res://core/preset_io.gd")
const BasesPanel = preload("res://core/designer/bases_panel.gd")
const SourceCard = preload("res://core/designer/source_card.gd")

var model
var _bases: BasesPanel
var _cards := []   # [{kind, idx, card}]
var _save_timer: Timer

func setup(p_model) -> void:
	model = p_model
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.15
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	_build()

func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "DESIGNER · %s · %s" % [model.model_name(), model.preset_path]
	title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	col.add_child(title)

	_bases = BasesPanel.new()
	_bases.setup(model.get_schema(), model.macros, model.overrides)
	_bases.changed.connect(_on_changed)
	col.add_child(_bases)

	var slab := Label.new()
	slab.text = "SOURCES"
	slab.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	col.add_child(slab)

	var cfg: Dictionary = model.modulators_cfg
	for kind in ["tween", "lfo", "envelope"]:
		for i in cfg.get(kind, []).size():
			var card_kind := "env" if kind == "envelope" else kind
			var card = SourceCard.new()
			card.setup(card_kind, cfg[kind][i], model.get_schema())
			card.changed.connect(_on_changed)
			col.add_child(card)
			_cards.append({"kind": kind, "card": card})

func _on_changed() -> void:
	_save_timer.start()

func current_scene() -> Dictionary:
	var mods := {}
	for c in _cards:
		mods.get_or_add(c["kind"], [])
		mods[c["kind"]].append(c["card"].to_config())
	return {
		"macros": _bases.macro_values(),
		"overrides": _bases.override_values(),
		"modulators": mods,
	}

func save_now() -> void:
	if model.preset_path == "":
		return
	var s := current_scene()
	PresetIO.save_preset(model.preset_path, model.model_name(), model.seed_value, model.duration_sec, s["macros"], s["overrides"], model.jitter, {}, s["modulators"])
```

- [ ] **Step 4: Run — expect PASS** (use actual). 
- [ ] **Step 5: UI smoke + screenshot prep**

Run: `godot --headless --path radial_burst --quit-after 90 -- --designer --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN` → `CLEAN`.
(The controller will run an xvfb screenshot at the end to confirm it renders.)

- [ ] **Step 6: README + commit**

```bash
git add common/core/designer/designer.gd common/core/tests/run_tests.gd README.md
git commit -m "designer: assemble bases + source cards, write scene.json on edit (debounced)"
```

---

### Task 7: transport + animated knobs

**Files:**
- Modify: `common/core/designer/designer.gd` (add transport + clock + animation)
- Modify: `common/core/designer/source_card.gd` (expose its routed/param knobs for animation) — only if needed; bases knobs are the primary animation target
- Test: `common/core/tests/run_tests.gd`
- Modify: `README.md`

**Interfaces:**
- Consumes: `ModStack` (`from_config`, `tick`, `offsets`), `Knob.set_live`.
- Produces: a play/scrub transport in the Designer; a per-frame clock that ticks a `ModStack` built from the live scene and pushes live values to the bases knobs via `set_live`. Static `Designer` has `live_macro_values(schema, macros, offsets) -> Dictionary` for testing (clamped base+offset).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_designer_live_macro_values() -> void:
	var Designer = load("res://core/designer/designer.gd")
	var live := Designer.live_macro_values(_demo_schema(), {"energy": 0.4}, {"energy": 0.3})
	check_eq(live["energy"], 0.7, "live macro = clamp(base + offset)")
	var live2 := Designer.live_macro_values(_demo_schema(), {"energy": 0.9}, {"energy": 0.5})
	check_eq(live2["energy"], 1.0, "live macro clamps to 1")
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Add transport + animation to `designer.gd`**

Add the static helper and the runtime. Add this static func:

```gdscript
static func live_macro_values(schema: Dictionary, macros: Dictionary, offsets: Dictionary) -> Dictionary:
	var out := {}
	for m in schema["macros"]:
		out[m["name"]] = clampf(float(macros.get(m["name"], m["default"])) + float(offsets.get(m["name"], 0.0)), 0.0, 1.0)
	return out
```

Add fields and a transport built in `_build()` (append after the title):

```gdscript
var _mod
var _t := 0.0
var _playing := false
var _scrub: HSlider
var _macro_knobs := {}  # name -> Knob   (populated from BasesPanel)
```

After creating `_bases`, capture its macro knobs and build the transport. Append in `_build()` (after `col.add_child(_bases)`):

```gdscript
	_macro_knobs = _bases.macro_knobs()
	var tr := HBoxContainer.new()
	var play := Button.new()
	play.text = "▶"
	play.toggle_mode = true
	play.toggled.connect(func(on): _playing = on)
	tr.add_child(play)
	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.001
	_scrub.custom_minimum_size = Vector2(240, 0)
	_scrub.value_changed.connect(func(f): _t = f * maxf(model.duration_sec, 0.0001))
	tr.add_child(_scrub)
	col.add_child(tr)
	_mod = load("res://core/modulation.gd").from_config(model.modulators_cfg)
```

Add `_process` to advance the clock and animate the macro knobs:

```gdscript
func _process(delta: float) -> void:
	if _mod == null or not _mod.enabled:
		return
	if _playing:
		_t = fmod(_t + delta, maxf(model.duration_sec, 0.0001))
		_scrub.set_value_no_signal(_t / maxf(model.duration_sec, 0.0001))
	_mod.t = _t
	var off := _mod.offsets()
	var live := live_macro_values(model.get_schema(), _bases.macro_values(), off)
	for name in _macro_knobs:
		_macro_knobs[name].set_live(float(live.get(name, 0.0)))
```

Note: `_mod` is rebuilt on edits so animation reflects changes — in `_on_changed()`, append: `_mod = load("res://core/modulation.gd").from_config(current_scene()["modulators"])`.

- [ ] **Step 4: Add `macro_knobs()` to `bases_panel.gd`**

Track macro knobs in a dict and expose them. In `bases_panel.gd`, add `var _macro_knobs := {}`; in `_macro_knob`, before returning, add `_macro_knobs[m["name"]] = k`; and add:

```gdscript
func macro_knobs() -> Dictionary:
	return _macro_knobs
```

- [ ] **Step 5: Run tests + UI smoke**

Run the suite (use actual total) and the `--designer` smoke (expect `CLEAN`).

- [ ] **Step 6: README + commit**

```bash
git add common/core/designer/designer.gd common/core/designer/bases_panel.gd common/core/tests/run_tests.gd README.md
git commit -m "designer: transport (play/scrub) animates the bases knobs with live modulation"
```

- [ ] **Step 7: USER REVIEW HANDOFF (controller)**

Controller runs an xvfb screenshot of the Designer (`--designer --preset presets/pulsar.json`), confirms it renders, then hands off: open the Designer beside the preview, drag a knob → `scene.json` is written → the preview hot-reloads. Interaction/feel is the user's review.

---

## Self-Review

**Spec coverage** (`2026-06-19-designer-phase2-design.md`, 2a):
- `--designer` mode in the model's project, schema via `get_schema()`, no sim built → Task 1. ✓
- Animated Ableton knob (drag/fine/reset, base pointer + live ring) → Task 2 + Task 7 (animation). ✓
- Signal previews from `mod_sources` → Task 3 + source_card `_wire_preview`. ✓
- Per-source editors (tween/lfo/env incl. oscillator stack), preview-on-top, source-centric routing with amount knobs → Task 4. ✓
- Bases = superparams + "Show all basic params (A–Z)" zippy (alphabetical) → Task 5. ✓
- Edit existing scene, write scene.json debounced → Task 6. ✓
- Transport (play/scrub) driving knob animation via its own ModStack clock → Task 7. ✓
- Responsive (fixed knobs, flexible previews, reflow), no `.tscn` → widgets use containers + `SIZE_EXPAND_FILL`; knobs fixed `custom_minimum_size`. ✓
- 2a excludes add/remove (sources/routings/oscillators) and drag-handles → no task adds them; routing destinations read-only. ✓

**Placeholder scan:** none — complete code per file; test totals are "use actual printed total" from baseline 51.

**Type consistency:** `Knob.setup(min,max,value,default,ring)`, `set_live`, `frac/angle` consistent (Tasks 2,4,5,7). `WavePreview.set_sampler(cb,lo,hi,color)`/`points` consistent (Tasks 3,4). `SourceCard.setup(kind,src,schema)`/`to_config` (Tasks 4,6). `BasesPanel.setup(schema,macros,overrides)`/`macro_values`/`override_values`/`macro_knobs`/`numeric_param_names_sorted`/`set_macro` (Tasks 5,6,7). `designer.setup(model)`/`save_now`/`current_scene`/`live_macro_values` (Tasks 1,6,7). `RenderDriver...["designer"]` (Task 1). `PresetIO.save_preset(path, model, seed, dur, macros, overrides, jitter, director, modulators)` matches the existing signature (director `{}`).
