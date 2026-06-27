# Modulation system (radial_burst v1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four disconnected value-movers (params, superparams, director, build) with one synth-style modulation system — sources (superparam/LFO/tween/envelope) routed to destinations (params) under one composition rule — proven on radial_burst.

**Architecture:** Two pure, unit-tested helpers (`mod_sources.gd` signal functions; `modulation.gd` ModStack that composes the live param set each frame). `SimModel` gains a ModStack + `emit_event`, composing every frame when a preset carries `modulators`; the legacy `director` path is left intact for not-yet-migrated models. radial_burst drops its bespoke build code, emits a `burst` event, and reads the composed params; `pulsar` is rebuilt as tween + LFO + envelope.

**Tech Stack:** Godot 4.6, GDScript. Framework in `common/core/` (symlinked into each model as `core/`). Test runner: `common/core/tests/run_tests.gd`.

## Global Constraints

- **One composition rule, layered, in one place** (`modulation.gd`):
  1. live superparam = `clamp(macro_base + Σ offsets→superparam, 0, 1)`
  2. param = `resolve(with live superparams)` `+ Σ offsets→param`, clamped to `[min,max]`
  3. (item params: deferred — radial_burst has no CPU-tracked items)
- **Contribution = `source_output × amount`.** LFO output ∈ [-1,1]; tween output = curve-interpolated `from→to`; envelope output ∈ [0,peak] summed over live instances.
- **Scope valve:** superparam/LFO/tween target globals; envelopes may target ambient globals (summed). radial_burst envelopes send to ambient globals only (no per-item path).
- **Legacy director preserved:** a preset uses `modulators` *or* `director`; when `modulators` is non-empty it takes precedence. Existing director-based presets (e.g. supernova `odyssey`) must behave identically. Do **not** modify `director.gd`.
- **Determinism:** every per-frame compose builds its jitter rng fresh as `RNGService.new(seed_value).stream("jitter")` (same as today's `resolve_live`); LFO phases seeded from `rng_service.stream("mod:"+name)`.
- **No new visual mechanics.** This is an architecture change; the look should reach where pulsar already is, now expressed as modulators.
- **Sim stays LDR; design space 1920×1080.** Unchanged.
- **Test command:** `godot --headless --path radial_burst --script res://core/tests/run_tests.gd` → `TESTS: N run, 0 failed`. The current baseline is **33** (the README's stated number may lag — when you add tests, set the README line to the actual printed total and assert `0 failed`).
- **Headless smoke pattern:** `godot --headless --path radial_burst --quit-after <frames> [-- --preset <p>] 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN`.

---

### Task 1: `mod_sources.gd` — pure modulation signals

**Files:**
- Create: `common/core/mod_sources.gd`
- Test: `common/core/tests/run_tests.gd` (add `test_modsrc_*` + `const MS`)
- Modify: `README.md` (test-count line)

**Interfaces:**
- Consumes: `MacroMapper.curve_apply` (already in `macro_mapper.gd`).
- Produces:
  - `MS.lfo(t: float, rate_sec: float, shape: String, phase := 0.0) -> float` ∈ [-1,1]
  - `MS.tween(t: float, secs: float, curve: String, from_v: float, to_v: float) -> float`
  - `MS.envelope(age: float, attack: float, decay: float, peak: float) -> float` ∈ [0,peak]

- [ ] **Step 1: Write the failing tests**

In `common/core/tests/run_tests.gd`, add near the end:

```gdscript
# ---------------- mod_sources ----------------

const MS = preload("res://core/mod_sources.gd")

func test_modsrc_lfo_sine_range_and_phase() -> void:
	check_eq(MS.lfo(0.0, 4.0, "sine"), 0.0, "sine at t=0 is 0")
	check_eq(MS.lfo(1.0, 4.0, "sine"), 1.0, "sine at quarter period is 1")
	check_eq(MS.lfo(0.0, 0.0, "sine"), 0.0, "rate 0 -> 0 (no div by zero)")

func test_modsrc_lfo_drift_bounded() -> void:
	for i in 50:
		var v := MS.lfo(float(i) * 0.37, 5.0, "drift")
		check(v >= -1.0001 and v <= 1.0001, "drift stays within [-1,1]")

func test_modsrc_tween_endpoints_and_curve() -> void:
	check_eq(MS.tween(0.0, 10.0, "linear", 2.0, 8.0), 2.0, "t=0 -> from")
	check_eq(MS.tween(10.0, 10.0, "linear", 2.0, 8.0), 8.0, "t=secs -> to")
	check_eq(MS.tween(99.0, 10.0, "linear", 2.0, 8.0), 8.0, "past end holds at to")
	check_eq(MS.tween(5.0, 10.0, "linear", 2.0, 8.0), 5.0, "linear midpoint")
	check_eq(MS.tween(5.0, 10.0, "ease_in", 0.0, 1.0), 0.25, "ease_in midpoint = 0.25")

func test_modsrc_envelope_attack_decay() -> void:
	check_eq(MS.envelope(-1.0, 0.1, 0.1, 1.0), 0.0, "before trigger -> 0")
	check_eq(MS.envelope(0.05, 0.1, 0.1, 1.0), 0.5, "mid-attack linear")
	check_eq(MS.envelope(0.1, 0.1, 0.1, 1.0), 1.0, "end of attack -> peak")
	check_eq(MS.envelope(0.15, 0.1, 0.1, 1.0), 0.5, "mid-decay linear")
	check_eq(MS.envelope(0.2, 0.1, 0.1, 1.0), 0.0, "end of decay -> 0")
	check_eq(MS.envelope(1.0, 0.1, 0.1, 1.0), 0.0, "after -> 0")
	check_eq(MS.envelope(0.0, 0.0, 1.0, 1.0), 1.0, "zero attack -> instant peak")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: FAIL — missing `res://core/mod_sources.gd`.

- [ ] **Step 3: Implement `common/core/mod_sources.gd`**

```gdscript
extends RefCounted
# Pure modulation source signals — deterministic functions of time.

const MM = preload("res://core/macro_mapper.gd")

# LFO: free-running periodic, bipolar output in [-1, 1].
static func lfo(t: float, rate_sec: float, shape: String, phase := 0.0) -> float:
	if rate_sec <= 0.0:
		return 0.0
	var ph := TAU * t / rate_sec + phase
	match shape:
		"triangle":
			return 2.0 / PI * asin(sin(ph))
		"drift":  # two incommensurate sines -> organic, non-repeating
			return 0.6 * sin(ph) + 0.4 * sin(TAU * t / (rate_sec * 0.391) + phase)
		_:  # "sine"
			return sin(ph)

# Tween: one-shot curve from->to over secs; holds at `to` afterward.
static func tween(t: float, secs: float, curve: String, from_v: float, to_v: float) -> float:
	if secs <= 0.0:
		return to_v
	var x := clampf(t / secs, 0.0, 1.0)
	return lerpf(from_v, to_v, MM.curve_apply(x, curve))

# Envelope (one instance): age since trigger -> [0, peak]; 0 before trigger and
# after attack+decay. Linear attack, then linear decay.
static func envelope(age: float, attack: float, decay: float, peak: float) -> float:
	if age < 0.0:
		return 0.0
	if age < attack:
		return peak * (age / maxf(attack, 0.0001))
	var d := age - attack
	if d < decay:
		return peak * (1.0 - d / maxf(decay, 0.0001))
	return 0.0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 40 run, 0 failed` (33 + 7). If the printed total differs, use the actual number in Step 5.

- [ ] **Step 5: Update README test count**

In `README.md`, set the `## Tests` expected line to the actual printed total (`TESTS: 40 run, 0 failed`).

- [ ] **Step 6: Commit**

```bash
git add common/core/mod_sources.gd common/core/tests/run_tests.gd README.md
git commit -m "core: mod_sources.gd — pure LFO/tween/envelope signal functions"
```

---

### Task 2: `modulation.gd` — the ModStack

**Files:**
- Create: `common/core/modulation.gd`
- Test: `common/core/tests/run_tests.gd` (add `test_mod_*` + `const Mod`)
- Modify: `README.md` (test-count line)

**Interfaces:**
- Consumes: `MS` (Task 1), `MacroMapper.resolve`, `RNGService`.
- Produces (instance of `modulation.gd`):
  - `Mod.from_config(cfg: Dictionary, rng_service) -> RefCounted` (sets `enabled`)
  - `.tick(delta: float) -> void` (advances time, culls dead envelope instances)
  - `.emit(event_name: String) -> void` (spawns an envelope instance per matching envelope)
  - `.offsets() -> Dictionary` (destination name → summed offset)
  - `.compose(schema, macros, overrides, jitter, rng: RandomNumberGenerator) -> Dictionary`
  - fields: `enabled: bool`, `t: float`

- [ ] **Step 1: Write the failing tests**

In `common/core/tests/run_tests.gd`, add (uses the existing `_demo_schema`: `energy`→`speed` lerp(200,800), `plain` float 0..10):

```gdscript
# ---------------- modulation ----------------

const Mod = preload("res://core/modulation.gd")

func _jit() -> RandomNumberGenerator:
	return RNGService.new(1).stream("jitter")

func test_mod_disabled_when_empty() -> void:
	var m = Mod.from_config({}, RNGService.new(1))
	check_eq(m.enabled, false, "empty config -> disabled")

func test_mod_tween_drives_superparam() -> void:
	var cfg := {"tween": [{"name": "b", "secs": 10.0, "curve": "linear", "from": 0.0, "to": 1.0,
		"targets": [{"to": "energy", "amount": 0.5}]}]}
	var m = Mod.from_config(cfg, RNGService.new(1))
	var p0 := m.compose(_demo_schema(), {"energy": 0.5}, {}, {}, _jit())
	check_eq(p0["speed"], 500.0, "t=0: energy 0.5 -> speed 500")
	m.tick(10.0)
	var p1 := m.compose(_demo_schema(), {"energy": 0.5}, {}, {}, _jit())
	check_eq(p1["speed"], 800.0, "tween raised energy to 1.0 -> speed 800")

func test_mod_envelope_polyphonic_and_decays() -> void:
	var cfg := {"envelope": [{"name": "f", "event": "hit", "attack": 0.1, "decay": 0.1, "peak": 1.0,
		"targets": [{"to": "plain", "amount": 2.0}]}]}
	var m = Mod.from_config(cfg, RNGService.new(1))
	m.emit("hit")            # instance at t=0
	m.tick(0.1)              # age 0.1 = peak
	check_eq(m.compose(_demo_schema(), {}, {}, {}, _jit())["plain"], 7.0, "peak adds amount (5+2)")
	m.tick(0.2)              # t=0.3: instance dead
	check_eq(m.compose(_demo_schema(), {}, {}, {}, _jit())["plain"], 5.0, "decayed -> base 5")

func test_mod_clamps_to_param_range() -> void:
	var cfg := {"envelope": [{"name": "f", "event": "hit", "attack": 0.0, "decay": 1.0, "peak": 1.0,
		"targets": [{"to": "plain", "amount": 100.0}]}]}
	var m = Mod.from_config(cfg, RNGService.new(1))
	m.emit("hit")
	check_eq(m.compose(_demo_schema(), {}, {}, {}, _jit())["plain"], 10.0, "offset clamped to param max 10")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: FAIL — missing `res://core/modulation.gd`.

- [ ] **Step 3: Implement `common/core/modulation.gd`**

```gdscript
extends RefCounted
# The modulation stack. Parses a preset's `modulators` and composes the live
# param set each frame under one rule (see the modulation-system design spec):
#   live superparam = clamp(macro_base + Σ offsets, 0, 1)
#   param           = resolve(live superparams) + Σ offsets, clamped to [min,max]
# Sources: LFO (continuous), tween (one-shot at t=0), envelope (event-triggered,
# polyphonic). Envelope output sums over live instances.

const MS = preload("res://core/mod_sources.gd")
const MM = preload("res://core/macro_mapper.gd")

var enabled := false
var t := 0.0
var lfos: Array = []       # {shape, rate, phase, targets:[{to, amount}]}
var tweens: Array = []     # {secs, curve, from, to, targets}
var envelopes: Array = []  # {event, attack, decay, peak, targets, instances:[float]}

static func from_config(cfg: Dictionary, rng_service) -> RefCounted:
	var m = new()
	for d in cfg.get("lfo", []):
		var nm := str(d.get("name", "lfo"))
		var r: RandomNumberGenerator = rng_service.stream("mod:" + nm)
		m.lfos.append({
			"shape": str(d.get("shape", "sine")),
			"rate": maxf(float(d.get("rate_sec", 30.0)), 0.0),
			"phase": r.randf_range(0.0, TAU),
			"targets": m._targets(d),
		})
	for d in cfg.get("tween", []):
		m.tweens.append({
			"secs": maxf(float(d.get("secs", 60.0)), 0.0),
			"curve": str(d.get("curve", "linear")),
			"from": float(d.get("from", 0.0)),
			"to": float(d.get("to", 1.0)),
			"targets": m._targets(d),
		})
	for d in cfg.get("envelope", []):
		m.envelopes.append({
			"event": str(d.get("event", "")),
			"attack": maxf(float(d.get("attack", 0.01)), 0.0),
			"decay": maxf(float(d.get("decay", 0.3)), 0.0),
			"peak": float(d.get("peak", 1.0)),
			"targets": m._targets(d),
			"instances": [],
		})
	m.enabled = not (m.lfos.is_empty() and m.tweens.is_empty() and m.envelopes.is_empty())
	return m

func _targets(d: Dictionary) -> Array:
	var out := []
	for tg in d.get("targets", []):
		out.append({"to": str(tg.get("to", "")), "amount": float(tg.get("amount", 0.0))})
	return out

func tick(delta: float) -> void:
	t += delta
	for env in envelopes:
		var dur: float = env["attack"] + env["decay"]
		var live := []
		for trig in env["instances"]:
			if t - float(trig) <= dur:
				live.append(trig)
		env["instances"] = live

func emit(event_name: String) -> void:
	for env in envelopes:
		if env["event"] == event_name:
			env["instances"].append(t)

func offsets() -> Dictionary:
	var d := {}
	for lfo in lfos:
		var o := MS.lfo(t, lfo["rate"], lfo["shape"], lfo["phase"])
		for tg in lfo["targets"]:
			d[tg["to"]] = float(d.get(tg["to"], 0.0)) + o * float(tg["amount"])
	for tw in tweens:
		var o := MS.tween(t, tw["secs"], tw["curve"], tw["from"], tw["to"])
		for tg in tw["targets"]:
			d[tg["to"]] = float(d.get(tg["to"], 0.0)) + o * float(tg["amount"])
	for env in envelopes:
		var o := 0.0
		for trig in env["instances"]:
			o += MS.envelope(t - float(trig), env["attack"], env["decay"], env["peak"])
		for tg in env["targets"]:
			d[tg["to"]] = float(d.get(tg["to"], 0.0)) + o * float(tg["amount"])
	return d

func compose(schema: Dictionary, macros: Dictionary, overrides: Dictionary, jitter: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var off := offsets()
	var live := {}
	for mm in schema["macros"]:
		var base: float = float(macros.get(mm["name"], mm["default"]))
		live[mm["name"]] = clampf(base + float(off.get(mm["name"], 0.0)), 0.0, 1.0)
	var params := MM.resolve(schema, live, overrides, jitter, rng)
	for p in schema["params"]:
		var pn: String = p["name"]
		if (p["type"] == "float" or p["type"] == "int") and off.has(pn):
			var v := float(params[pn]) + float(off[pn])
			if p["type"] == "int":
				params[pn] = clampi(roundi(v), int(p["min"]), int(p["max"]))
			else:
				params[pn] = clampf(v, float(p["min"]), float(p["max"]))
	return params
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 45 run, 0 failed` (40 + 5). Use the actual printed total in Step 5.

- [ ] **Step 5: Update README test count** to the actual printed total.

- [ ] **Step 6: Commit**

```bash
git add common/core/modulation.gd common/core/tests/run_tests.gd README.md
git commit -m "core: modulation.gd — ModStack composes live params from LFO/tween/envelope sources"
```

---

### Task 3: preset_io — load/save `modulators`

**Files:**
- Modify: `common/core/preset_io.gd`
- Test: `common/core/tests/run_tests.gd` (add `test_preset_modulators_*`)
- Modify: `README.md` (test-count line)

**Interfaces:**
- Consumes: existing `PIO.save_preset` / `PIO.load_preset`.
- Produces: `load_preset(...)["preset"]["modulators"]` (Dictionary, default `{}`); a warning per unknown modulator target; `save_preset(..., modulators := {})` writes a `modulators` key when non-empty.

- [ ] **Step 1: Write the failing tests**

In `common/core/tests/run_tests.gd`, add:

```gdscript
# ---------------- preset modulators ----------------

func test_preset_modulators_roundtrip_and_warn() -> void:
	var path := "/tmp/vx_test_mod.json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({
		"model": "demo",
		"modulators": {
			"tween": [{"name": "b", "secs": 5.0, "targets": [{"to": "energy", "amount": 0.5}]}],
			"envelope": [{"name": "f", "event": "hit", "targets": [{"to": "bogusparam", "amount": 1.0}]}],
		},
	}))
	fa.close()
	var res := PIO.load_preset(path, _demo_schema(), "demo")
	check(res["ok"], "loads with modulators")
	check_eq(res["preset"]["modulators"]["tween"][0]["secs"], 5.0, "modulators roundtrip")
	check(res["warnings"].size() >= 1, "unknown modulator target warns")

func test_preset_modulators_absent_defaults_empty() -> void:
	var path := "/tmp/vx_test_mod2.json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"model": "demo"}))
	fa.close()
	var res := PIO.load_preset(path, _demo_schema(), "demo")
	check_eq(res["preset"]["modulators"], {}, "absent modulators -> {}")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: FAIL — `modulators` key missing from the loaded preset.

- [ ] **Step 3: Edit `common/core/preset_io.gd`**

In `load_preset`, after the existing `for section in ["overrides", "jitter"]:` validation loop and before the `raw_director` line, add modulator-target validation:

```gdscript
	for kind in ["lfo", "tween", "envelope"]:
		for md in data.get("modulators", {}).get(kind, []):
			for tg in md.get("targets", []):
				var to_name := str(tg.get("to", ""))
				if not (known_params.has(to_name) or known_macros.has(to_name)):
					warnings.append("unknown modulator target: " + to_name)
	var raw_mod = data.get("modulators", {})
	var modulators: Dictionary = raw_mod if raw_mod is Dictionary else {}
```

Then add `"modulators": modulators,` to the returned `preset` dictionary (alongside `"director": director,`).

In `save_preset`, add a trailing optional parameter and write it when present. Change the signature line:

```gdscript
static func save_preset(path: String, model: String, seed_value: int, duration_sec: float, macros: Dictionary, overrides: Dictionary, jitter: Dictionary, director: Dictionary = {}, modulators: Dictionary = {}) -> Error:
```

and after the `if not director.is_empty(): doc["director"] = director` block add:

```gdscript
	if not modulators.is_empty():
		doc["modulators"] = modulators
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — `TESTS: 47 run, 0 failed` (45 + 2). Use the actual printed total in Step 5.

- [ ] **Step 5: Update README test count** to the actual printed total.

- [ ] **Step 6: Commit**

```bash
git add common/core/preset_io.gd common/core/tests/run_tests.gd README.md
git commit -m "core: preset_io — load/save modulators + warn on unknown targets"
```

---

### Task 4: SimModel — own a ModStack, compose per frame, emit events

**Files:**
- Modify: `common/core/sim_model.gd`

**Interfaces:**
- Consumes: `Mod` (Task 2), `PresetIO` (Task 3), existing `MacroMapper`/`RNGService`/`Director`.
- Produces: `SimModel.emit_event(name: String)`; per-frame `params` composition when `modulators` present. `var mod_stack`, `var modulators_cfg`.

**Behavior contract:** a preset with non-empty `modulators` composes `params` every frame via the ModStack; a preset with only `director` behaves exactly as today; a preset with neither resolves once and is static.

- [ ] **Step 1: Add the ModStack preload and fields**

At the top of `common/core/sim_model.gd`, after `const DirectorScript = preload("res://core/director.gd")`, add:

```gdscript
const ModStack = preload("res://core/modulation.gd")
```

After `var director_cfg: Dictionary = {}`, add:

```gdscript
var mod_stack  # ModStack (null until resolve_and_restart)
var modulators_cfg: Dictionary = {}
```

- [ ] **Step 2: Parse modulators in `adopt_preset`**

In `adopt_preset`, after `director_cfg = p.get("director", {})`, add:

```gdscript
	modulators_cfg = p.get("modulators", {})
```

- [ ] **Step 3: Build the ModStack and add a single compose path**

Replace `resolve_and_restart` and `resolve_live` with:

```gdscript
func resolve_and_restart() -> void:
	rng = RNGService.new(seed_value)
	mod_stack = ModStack.from_config(modulators_cfg, rng)
	director = DirectorScript.from_config(director_cfg, macros, rng)
	_compose()
	restart()

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
```

- [ ] **Step 4: Add the per-frame compose to `_process`**

Replace `_process` with (mod path first; legacy director path unchanged):

```gdscript
func _process(delta: float) -> void:
	if mod_stack != null and mod_stack.enabled:
		mod_stack.tick(delta)
		_compose()
		apply_live(params)
	elif director != null and director.enabled:
		director.tick(delta)
		_dir_acc += delta
		if _dir_acc >= 0.25:
			_dir_acc = 0.0
			if director.apply(macros):
				resolve_live()
	if movie_mode:
		_elapsed += delta
		if _elapsed >= duration_sec:
			get_tree().quit()
```

- [ ] **Step 5: Persist modulators in `save_to`**

Replace `save_to` with:

```gdscript
func save_to(path: String) -> Error:
	return PresetIO.save_preset(path, model_name(), seed_value, duration_sec, macros, overrides, jitter, director_cfg, modulators_cfg)
```

- [ ] **Step 6: Run the unit suite — confirm no regression**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — same total as Task 3, `0 failed` (framework tests, incl. all `test_director_*`, unaffected).

- [ ] **Step 7: Smoke — legacy director model still works**

Run: `godot --headless --path supernova_orbit --quit-after 240 -- --preset presets/odyssey.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN`
Expected: `CLEAN` (odyssey uses `director`; the legacy path must be intact).

- [ ] **Step 8: Commit**

```bash
git add common/core/sim_model.gd
git commit -m "core: SimModel — per-frame ModStack compose + emit_event (legacy director preserved)"
```

---

### Task 5: radial_burst — adopt modulation, drop bespoke build, emit `burst`

**Files:**
- Modify: `radial_burst/main.gd`

**Interfaces:**
- Consumes: `SimModel.emit_event` (Task 4); composed `params`.
- Produces: emits `"burst"` on each ignition; schema no longer declares `build_secs`/`build_size_start`/`build_period_start`.

- [ ] **Step 1: Remove the three build params from `get_schema()`**

Delete these three lines (the `# Build envelope:` comment block and its params):

```gdscript
			# Build envelope: when build_secs > 0, bursts ramp from small+infrequent
			# to large+frequent over build_secs (then hold). 0 disables it (constant).
			PS.f("build_secs", 0.0, 0.0, 600.0),
			PS.f("build_size_start", 0.25, 0.05, 1.0),
			PS.f("build_period_start", 9.0, 1.0, 20.0),
```

- [ ] **Step 2: Delete `_build_p()` and simplify `_ignite_period()`**

Delete the entire `_build_p()` function. Replace `_ignite_period()` with:

```gdscript
# Inter-burst period (seeded jitter); frequency is now driven by modulating loop_period.
func _ignite_period() -> float:
	return params["loop_period"] * s.randf_range(0.85, 1.15)
```

- [ ] **Step 3: Drop `size_mul` from `_make_process_material`**

Replace the signature and the two scaled lines. Change:

```gdscript
func _make_process_material(scale_mul: float, base: Color, size_mul := 1.0) -> ParticleProcessMaterial:
```
to:
```gdscript
func _make_process_material(scale_mul: float, base: Color) -> ParticleProcessMaterial:
```

Change `var spd: float = params["burst_speed"] * scale_mul * size_mul` to:
```gdscript
	var spd: float = params["burst_speed"] * scale_mul
```

Change the two scale lines:
```gdscript
	pm.scale_min = params["streak_len"] * size_mul / 128.0 * 0.5
	pm.scale_max = params["streak_len"] * size_mul / 128.0 * 1.3
```
to:
```gdscript
	pm.scale_min = params["streak_len"] / 128.0 * 0.5
	pm.scale_max = params["streak_len"] / 128.0 * 1.3
```

- [ ] **Step 4: Rewrite `_ignite()` — read composed params, emit `burst`**

Replace the whole `_ignite` function with:

```gdscript
func _ignite(i: int, depth: int) -> void:
	var src: Dictionary = sources[i]
	# params are the live composed values (modulators already applied this frame)
	src["main"].amount = maxi(int(params["particle_count"]), 8)
	src["main"].lifetime = params["particle_life"]
	src["main"].process_material = _make_process_material(1.0, src["base"])
	src["main"].position = src["pos"]
	src["main"].restart()
	for e in src["subs"]:
		var ang := s.randf_range(0.0, TAU)
		var at := s.randf_range(0.1, 0.5)
		var dist: float = params["burst_speed"] * 0.55 * at
		e.amount = maxi(int(params["particle_count"] * params["subburst_scale"] / maxf(1.0, float(src["subs"].size()))), 50)
		e.process_material = _make_process_material(0.45, src["base"])
		e.position = src["pos"] + Vector2.from_angle(ang) * dist
		e.restart()
	for ri in int(params["ring_count"]):
		rings.append({"center": src["pos"], "r": 10.0,
			"speed": params["ring_speed"] * s.randf_range(0.7, 1.3),
			"alpha": 1.0, "color": _src_color(src)})
	src["timer"] = 0.0
	src["period"] = _ignite_period()
	emit_event("burst")
	# sympathetic cascade (only from a primary ignition); strength is composed sympathy
	if sources.size() > 1 and depth == 0 and params["sympathy"] > 0.0:
		var positions := []
		for sc in sources:
			positions.append(sc["pos"])
		var caught := Cascade.flood(positions, i, params["sympathy"], params["sympathy_radius"], s)
		for c in caught:
			var cidx := int(c["idx"])
			var already := false
			for pe in pending:
				if int(pe["idx"]) == cidx:
					already = true
					break
			if not already:
				pending.append({"at": sim_t + c["dist"] / maxf(params["ripple_speed"], 1.0), "idx": cidx})
```

- [ ] **Step 5: Run the unit suite — confirm no regression**

Run: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`
Expected: PASS — same total as Task 4, `0 failed`.

- [ ] **Step 6: Smoke — default preset (no modulators) still runs**

Run: `godot --headless --path radial_burst --quit-after 240 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN`
Expected: `CLEAN`.

- [ ] **Step 7: Commit**

```bash
git add radial_burst/main.gd
git commit -m "radial_burst: read composed params, emit 'burst' event, drop bespoke build envelope"
```

---

### Task 6: `pulsar` on modulators + docs + render

**Files:**
- Modify: `radial_burst/presets/pulsar.json`
- Modify: `README.md` (pulsar description)

**Interfaces:**
- Consumes: the schema (Task 5: macros `energy`/`density`/`coupling`/`grit`/`symmetry`; params `loop_period`/`glow`/etc.) and the `modulators` format (Tasks 2–3).

- [ ] **Step 1: Rewrite `radial_burst/presets/pulsar.json`**

```json
{
  "model": "radial_burst",
  "seed": 204,
  "duration_sec": 300.0,
  "macros": {
    "energy": 0.3,
    "density": 0.35,
    "symmetry": 0.3,
    "grit": 0.4,
    "coupling": 0.0
  },
  "overrides": {
    "source_count": 4,
    "palette": "galton",
    "loop_period": 7.0,
    "sympathy_radius": 620.0,
    "ripple_speed": 1500.0,
    "hue_drift": 0.0,
    "trail_persist": 0.08,
    "glow": 0.5,
    "mirror": "off"
  },
  "jitter": {},
  "modulators": {
    "lfo": [
      { "name": "grit_wobble", "shape": "drift", "rate_sec": 40.0,
        "targets": [ { "to": "grit", "amount": 0.2 } ] }
    ],
    "tween": [
      { "name": "build", "secs": 275.0, "curve": "linear", "from": 0.0, "to": 1.0,
        "targets": [
          { "to": "energy", "amount": 0.45 },
          { "to": "density", "amount": 0.4 },
          { "to": "coupling", "amount": 0.7 },
          { "to": "loop_period", "amount": -5.7 }
        ] }
    ],
    "envelope": [
      { "name": "flash", "event": "burst", "attack": 0.04, "decay": 0.5, "peak": 1.0,
        "targets": [ { "to": "glow", "amount": 0.35 } ] }
    ]
  }
}
```

Reasoning: bases sit low/infrequent (`energy` 0.3, `loop_period` 7); the **tween** ("build", linear, 275s) raises `energy`/`density`/`coupling` and lowers `loop_period`, so bursts grow larger, more frequent, and more sympathetically chained over the run (the build is now one declared source, its shape an editable `curve`). An **LFO** drifts `grit` for textural variation; an **envelope** on the `burst` event sends a glow flash to the ambient `glow` global — sparse swells early, a stacked blaze at the peak. All three source types exercised.

- [ ] **Step 2: Smoke — the real preset (build path)**

Run: `godot --headless --path radial_burst --quit-after 600 -- --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid|nil" || echo CLEAN`
Expected: `CLEAN`.

- [ ] **Step 3: Update the pulsar description in README**

Replace the existing `- \`pulsar\`` bullet under **radial_burst** with:

```markdown
- `pulsar` — 5-minute long-form on the unified modulation model: four burst
  sources on the 12-hue `galton` palette, driven by a **tween** ("build") that
  raises energy/density/coupling and tightens `loop_period` over 275s (small +
  rare → large + frequent + sympathetically chained), an **LFO** drifting `grit`
  for texture, and a per-`burst` **envelope** flashing the ambient `glow`. Seed-
  shuffled hues, so each render differs.
```

- [ ] **Step 4: Commit**

```bash
git add radial_burst/presets/pulsar.json README.md
git commit -m "radial_burst: pulsar rebuilt on the modulation model (tween build + grit LFO + burst->glow envelope)"
```

- [ ] **Step 5: Render the 300s piece and hand off (USER REVIEW GATE)**

Run: `xvfb-run -a -s "-screen 0 1920x1080x24" scripts/render.sh radial_burst pulsar 300`
Expected: `rendered: <repo>/renders/radial_burst_pulsar.mp4`.
Then tell the user it's ready and what to verify: the build still reads as small/rare → large/frequent, the opening is no longer dead (now a function of the tween `curve`/bases — trivially adjustable), the per-burst glow flashes stack at the peak, galton colors. **Do not claim the architecture "works" beyond tests + smoke until the user reviews the render.**

---

## Self-Review

**Spec coverage** (against `2026-06-19-modulation-system-design.md`):
- Source types superparam/LFO/tween/envelope → Tasks 1–2 (`mod_sources` + `ModStack`); superparams remain the macro lerp (untouched). ✓
- One composition rule per scope (live superparam → param + offsets, clamped) → Task 2 `compose`. ✓
- Polyphonic event envelopes summing → Task 2 `emit`/`tick`/`offsets`; tests cover summing + decay. ✓
- Config/preset format (`modulators`) + unknown-target warnings → Task 3. ✓
- Per-frame pipeline in SimModel; legacy director preserved → Task 4 (+ odyssey smoke). ✓
- `emit_event`, scope valve (radial_burst envelope → ambient `glow` only) → Tasks 4–6. ✓
- radial_burst drops build_*, reads composed params, emits `burst` → Task 5. ✓
- pulsar rebuilt as tween+LFO+envelope; build is a tween whose `curve` fixes the opening → Task 6. ✓
- Determinism (fresh jitter rng per compose; seeded LFO phase) → Task 4 `_compose`, Task 2 `from_config`. ✓
- Deferred per spec, no task (intentional): item-param envelopes (no CPU-tracked bursts), multi-keyframe tweens, tweak-panel matrix UI, migrating other models off `director`. The panel keeps working unchanged; the live-value/matrix panel is a separate follow-up plan.

**Placeholder scan:** none — all code and commands are concrete. Test-count totals are computed (40/45/47) with an explicit "use the actual printed total" instruction since the README baseline may lag.

**Type consistency:** `MS.lfo/tween/envelope` signatures match between Task 1 and their callers in Task 2. `Mod.from_config/tick/emit/offsets/compose` and fields `enabled`/`t` match between Task 2, its tests, and Task 4. `save_preset(..., director, modulators)` matches between Task 3 and Task 4's `save_to`. `emit_event("burst")` (Task 4) ↔ envelope `"event": "burst"` (Task 6).
