# Long-form Supernova (Milestone 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make supernova_orbit hold interest 4–6 minutes: binary cores, persistent debris belt + trail ghosts, and a model-agnostic director layer that drifts macros over time. Spec: `docs/superpowers/specs/2026-06-09-longform-supernova-design.md`.

**Architecture:** Director is a framework feature (`common/core/director.gd` + SimModel/preset_io/tweak_panel integration, preset-driven, off by default). Binary cores generalize supernova_orbit's single core into a 1–2 element `cores` array with fission/merge/per-core detonation. Persistence removes detonation resets (debris accumulates to a cap; hard trail flush becomes a soft wipe).

**Tech Stack:** Existing vxstory framework (Godot 4.6). Conventions in force: tabs in GDScript, preload not class_name, all sim randomness via `rng.stream()`, schema-not-overrides tuning, default presets keep `overrides: {}` (variant presets may override).

**Baseline:** tag v1.0, tests `17 run, 0 failed`.

---

### Task A: Director layer (framework, TDD)

**Files:**
- Create: `common/core/director.gd`
- Modify: `common/core/preset_io.gd` (carry `director` key), `common/core/sim_model.gd` (own + tick a director), `common/core/tweak_panel.gd` (rebase hook + active indicator), `common/core/tests/run_tests.gd` (append tests)

- [ ] **Step 1: Append failing tests to run_tests.gd**

```gdscript
# ---------------- director ----------------

const Director = preload("res://core/director.gd")

func _dir_cfg() -> Dictionary:
	return {"enabled": true, "period_sec": 60.0, "amplitude": 0.3, "macros": ["energy", "bogus"]}

func test_director_disabled_by_default() -> void:
	var d = Director.from_config({}, {"energy": 0.5}, RNGService.new(3))
	check_eq(d.enabled, false, "empty config -> disabled")
	var macros := {"energy": 0.5}
	check_eq(d.apply(macros), false, "disabled apply is a no-op")
	check_eq(macros["energy"], 0.5, "macros untouched when disabled")

func test_director_deterministic_and_clamped() -> void:
	var a = Director.from_config(_dir_cfg(), {"energy": 0.9}, RNGService.new(7))
	var b = Director.from_config(_dir_cfg(), {"energy": 0.9}, RNGService.new(7))
	for i in 50:
		a.tick(0.5)
		b.tick(0.5)
		var va: float = a.current("energy")
		check_eq(va, b.current("energy"), "same seed -> same drift curve")
		check(va >= 0.0 and va <= 1.0, "drift clamped to 0..1")

func test_director_ignores_unknown_macros() -> void:
	var d = Director.from_config(_dir_cfg(), {"energy": 0.5}, RNGService.new(7))
	check_eq(d.macro_names.size(), 1, "unknown macro 'bogus' dropped")

func test_director_apply_and_rebase() -> void:
	var d = Director.from_config(_dir_cfg(), {"energy": 0.5}, RNGService.new(7))
	d.tick(13.0)
	var macros := {"energy": 0.5}
	check_eq(d.apply(macros), true, "apply reports change")
	check(absf(macros["energy"] - 0.5) > 0.0001, "macro drifted from base")
	d.rebase("energy", 0.9)
	d.apply(macros)
	var hi: float = macros["energy"]
	d.rebase("energy", 0.1)
	d.apply(macros)
	check(hi > macros["energy"], "rebase shifts the curve's center")

func test_preset_roundtrip_director() -> void:
	var path := "/tmp/vx_test_director.json"
	var err := PIO.save_preset(path, "demo", 1, 10.0, {}, {}, {}, _dir_cfg())
	check_eq(err, OK, "save with director ok")
	var res := PIO.load_preset(path, _demo_schema(), "demo")
	check(res["ok"], "load ok")
	check_eq(res["preset"]["director"]["period_sec"], 60.0, "director roundtrips")
	# absent director -> empty dict default
	PIO.save_preset(path, "demo", 1, 10.0, {}, {}, {})
	var res2 := PIO.load_preset(path, _demo_schema(), "demo")
	check_eq(res2["preset"]["director"], {}, "missing director defaults to {}")
```

- [ ] **Step 2: Run tests, confirm load failure** (director.gd missing; save_preset arity).

- [ ] **Step 3: Implement `common/core/director.gd`**

```gdscript
extends RefCounted
# Drifts macro values along smooth seeded curves over time. Preset config:
#   "director": {"enabled": true, "period_sec": 90.0, "amplitude": 0.25,
#                "macros": ["accretion", "chaos"]}
# Drift = sum of two seeded sines at incommensurate periods -> smooth, bounded,
# deterministic, non-repeating over any practical render length.

var enabled := false
var period := 90.0
var amplitude := 0.25
var macro_names: PackedStringArray = PackedStringArray()
var bases := {}    # macro -> curve center (preset value; rebased on user edit)
var _phases := {}  # macro -> [phase1, phase2]
var t := 0.0

static func from_config(cfg: Dictionary, macros: Dictionary, rng_service) -> RefCounted:
	var d = new()
	d.enabled = bool(cfg.get("enabled", false))
	d.period = maxf(float(cfg.get("period_sec", 90.0)), 1.0)
	d.amplitude = clampf(float(cfg.get("amplitude", 0.25)), 0.0, 1.0)
	for n in cfg.get("macros", []):
		if macros.has(n):
			d.macro_names.append(n)
			d.bases[n] = float(macros[n])
			var r: RandomNumberGenerator = rng_service.stream("director:" + str(n))
			d._phases[n] = [r.randf_range(0.0, TAU), r.randf_range(0.0, TAU)]
	return d

func tick(delta: float) -> void:
	t += delta

func current(macro_name: String) -> float:
	var ph: Array = _phases[macro_name]
	var drift := 0.6 * sin(TAU * t / period + ph[0]) \
		+ 0.4 * sin(TAU * t / (period * 0.391) + ph[1])
	return clampf(float(bases[macro_name]) + amplitude * drift, 0.0, 1.0)

func rebase(macro_name: String, v: float) -> void:
	if bases.has(macro_name):
		bases[macro_name] = v

func apply(macros: Dictionary) -> bool:
	if not enabled:
		return false
	var changed := false
	for n in macro_names:
		var v := current(n)
		if absf(float(macros.get(n, -1.0)) - v) > 0.0005:
			macros[n] = v
			changed = true
	return changed
```

- [ ] **Step 4: preset_io.gd** — `save_preset(..., jitter: Dictionary, director: Dictionary = {})`; include `"director": director` in the doc only when non-empty. In `load_preset`, add `"director": data.get("director", {})` to the returned preset. No validation of its contents beyond it being a Dictionary (coerce non-dict to `{}`).

- [ ] **Step 5: sim_model.gd integration**

```gdscript
# new members
var director  # Director (always constructed; may be disabled)
var director_cfg: Dictionary = {}
var _dir_acc := 0.0
const DirectorScript = preload("res://core/director.gd")
```

- `adopt_preset`: `director_cfg = p.get("director", {})`
- `resolve_and_restart`: after `rng` is created and macros exist:
  `director = DirectorScript.from_config(director_cfg, macros, rng)`
- `save_to`: pass `director_cfg` as the new arg.
- `_process` (before the movie-quit logic): 

```gdscript
	if director != null and director.enabled:
		director.tick(delta)
		_dir_acc += delta
		if _dir_acc >= 0.25:
			_dir_acc = 0.0
			if director.apply(macros):
				resolve_live()
```

- [ ] **Step 6: tweak_panel.gd** — in the macro slider `value_changed` callback, after `model.macros[...] = v`, add `if model.director != null: model.director.rebase(m["name"], v)`. In `_ready`/build, if `model.director_cfg.get("enabled", false)`, add a cyan `_title("DIRECTOR ACTIVE — macros drift")` label above the macros section.

- [ ] **Step 7: Run tests** — expect `TESTS: 22 run, 0 failed` (17 + 5). Headless smoke radial_burst + supernova_orbit (old presets must behave identically: director off).

- [ ] **Step 8: Commit** `core: director layer — preset-driven seeded macro drift`

---

### Task B: Supernova binary cores + persistence + hue drift

**Files:**
- Modify: `supernova_orbit/main.gd`

This is a refactor of the single-core model into a 1–2 core system per the spec. Read the spec section 1–2 and the existing main.gd first. Key changes, function by function:

- [ ] **Step 1: Core state** — replace `core_rect/core_mat/mass` with:

```gdscript
var cores: Array = []  # {pos, vel, mass, rect: ColorRect, mat: ShaderMaterial, ph: Vector2}

func _spawn_core(p: Vector2, v: Vector2, m: float) -> Dictionary:
	var mat := ShaderMaterial.new()
	mat.shader = CORE_SHADER
	mat.set_shader_parameter("base_col", _hue_rotated(pal["core"]))
	var rect := ColorRect.new()
	rect.size = Vector2(700, 700)
	rect.material = mat
	add_child(rect)
	var core := {"pos": p, "vel": v, "mass": m, "rect": rect, "mat": mat,
		"ph": Vector2(s.randf_range(0.0, TAU), s.randf_range(0.0, TAU))}
	cores.append(core)
	return core
```

`restart()` spawns one core at CENTER. Rings become positioned: `rings` entries gain `"pos"`; `rings_node` sits at origin and draws each ring at its own pos (matter_cycle pattern).

- [ ] **Step 2: Schema additions** — new macro `PS.macro_def("duality", 0.4)`; new params (all live unless noted):
  - `split_chance` f 0..0.85 d 0.35 macro duality lo 0.0 hi 0.85
  - `core_drift` f 0..260 d 120 macro duality lo 40 hi 240 (px wander radius)
  - `split_kick` f 80..500 d 260 macro duality lo 150 hi 420
  - `merge_radius` f 60..300 d 130
  - `core_gravity` f 0..3e6 d 9e5 (mutual core attraction)
  - `debris_cap` i 10..200 d 80
  - `hue_drift` f 0..90 d 0.0 (degrees per minute)

- [ ] **Step 3: Core motion (in `_process`)** — lone core wanders toward
  `CENTER + Vector2(sin(sim_t*0.11+ph.x), cos(sim_t*0.13+ph.y)) * core_drift` via
  `core.vel += (target - core.pos) * 0.8 * delta`; binary adds mutual gravity
  `core.vel += dir_to_other * core_gravity / max(d*d, 10000.0) * delta` plus a weak
  centering spring `(CENTER - core.pos) * 0.05 * delta`; damping `core.vel *= 0.995`;
  `core.pos += core.vel * delta`; `core.rect.position = core.pos - Vector2(350, 350)`.

- [ ] **Step 4: Fields and absorption** — particle gravity sums over cores; absorption tests each core's `core_radius` and increments that core's mass; debris force sums over cores; debris absorbed by a core adds 5 to it. Per-core charge `core.mass / critical` drives that core's `mat` uniforms (`charge`, `t`).

- [ ] **Step 5: Fission / merge / detonation**
  - Charge ≥ 1 on a core: if `cores.size() == 1` and `s.randf() < split_chance` → `_fission(core)`, else `_detonate(core)`. Keep the existing `det_cooldown` guard for both.
  - `_fission(c)`: half-strength visuals (flash 0.45, one ring at c.pos, fling particles from c.pos at 0.5× detonation_speed); set `c.mass = 0.35 * critical`; spawn second core at `c.pos + tangent * 80` with `vel = c.vel + tangent * split_kick`, mass `0.35 * critical`; give `c` the opposite kick (`c.vel -= tangent * split_kick * 0.6`).
  - Merge check (binary only): distance < `merge_radius` → survivor takes summed mass and momentum-averaged velocity, flash 0.5, free the other core's rect, remove from `cores`; if survivor charge ≥ 1 it detonates next frame (cooldown permitting — use a short 0.5 s cooldown after merge, not the full 5 s).
  - `_detonate(c)`: as v1.0 but centered on `c.pos` (flash, 3 rings at c.pos, particles flung from c.pos, fluid impulse + dye at c.pos), and:
    - **do NOT clear existing debris**; spawn new debris with `vel = (outward * 0.55 + tangent * 0.8).normalized() * detonation_speed * s.randf_range(0.35, 0.7)` (orbit-biased);
    - after spawning, `while debris.size() > debris_cap: oldest = debris.pop_front(); oldest.queue_free()` (validity-guarded);
    - if binary: survivor gets `vel += dir_from_blast * 300`; the detonated core is removed (free rect, erase from cores) so the system returns to lone-core; if lone: `c.mass = 0`.
  - **Soft trail wipe** replacing the 3-frame hard clear: `_wipe_t = 0.6` at detonation; in `_process`, `fade_rect.color.a = lerpf(params["trail_persist"], 0.5, clampf(_wipe_t / 0.6, 0.0, 1.0))` and `_wipe_t = maxf(_wipe_t - delta, 0.0)`. Remove the `_trail_clear_frames` machinery.

- [ ] **Step 6: Hue drift** — `func _hue_rotated(c: Color) -> Color:` rotates hue by `params["hue_drift"] * sim_t / 60.0 / 360.0` (wrap with `fposmod`); apply at swarm-particle spawn, debris spawn, core color (refresh each frame on the core mat — cheap), and detonation dye color.

- [ ] **Step 7: Verify** — tests still green (22/0); headless smoke clean; render a forced-binary check: copy default.json to `/tmp` is NOT possible for render.sh, so temporarily render with a high-duality preset: create `supernova_orbit/presets/binary_test.json` (duality 0.9 via macros, hue_drift override 40, duration 40) → `scripts/render.sh supernova_orbit binary_test 40`; extract frames every 5 s; VIEW: must catch a two-core phase (two glow centers / twin disks), debris belt persisting after a detonation, and late-frame hue clearly shifted vs early. Iterate. Delete `binary_test.json` after verification passes.

- [ ] **Step 8: Commit** `supernova orbit: binary cores, persistent debris belt, soft trail wipe, hue drift`

---

### Task C: odyssey preset + 5-minute verification + release

- [ ] **Step 1: `supernova_orbit/presets/odyssey.json`**

```json
{
  "model": "supernova_orbit",
  "seed": 31416,
  "duration_sec": 300.0,
  "macros": {"accretion": 0.7, "critical_mass": 0.45, "detonation": 0.7, "chaos": 0.5, "duality": 0.6},
  "overrides": {"hue_drift": 14.0},
  "jitter": {},
  "director": {"enabled": true, "period_sec": 90.0, "amplitude": 0.3,
               "macros": ["accretion", "chaos", "duality"]}
}
```

- [ ] **Step 2: Render the full piece** — `scripts/render.sh supernova_orbit odyssey` (300 s ≈ 10–15 min wall; be patient, do not kill it).
- [ ] **Step 3: Timeline verification** — extract frames at 15, 45, 75, ..., 285 s (every 30 s, 10 frames); VIEW all; success criteria from the spec: pairwise visually distinct; ≥1 frame showing a binary phase; debris belt growth across the timeline; late hue clearly differs from early. If a criterion fails, adjust the odyssey preset (macros/director/hue_drift — overrides allowed, it's a variant) and re-render. Re-render at 120 s for iteration speed if needed, full 300 s for the final pass.
- [ ] **Step 4: Docs** — README: add `odyssey` to the supernova variant list (one description line) + a short "Director" subsection under Presets documenting the preset key. VERSIONS.md: add `v1.1` entry (director layer, binary cores, persistence, odyssey).
- [ ] **Step 5: Final checks + commit + tag** — full test suite, headless smokes of radial_burst + supernova_orbit, `git add -A && git commit`, `git tag -a v1.1 -m "Long-form milestone 1: director, binary cores, persistence"`.

---

## Plan notes

- Backward compatibility is a hard requirement: all v1.0 presets must render identically (director absent ⇒ disabled; supernova default.json gets the new schema defaults — `duality` default 0.4 means the plain default preset may now occasionally fission; that is intended and acceptable, but `hue_drift` defaults to 0 so colors stay stable in old presets).
- Sequencing: A → B → C strictly (B uses nothing from A, but C needs both; doing A first keeps the test suite green throughout B).
- The detonated-core-removal path must free the core's `rect` before erasing the dict (no orphan ColorRects).
