# Models on the modulation paradigm — Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Make the 5 non-`radial_burst` models modulation-native — add `emit_event()` hooks, migrate `supernova_orbit` off the legacy Director, retire the Director, and seed one long-form starter preset per model.

**Architecture:** `SimModel` already composes + applies params live every frame for all models; this adds events (so envelopes fire), migrates one preset family, removes a subsystem, and adds data presets. Spec: `docs/superpowers/specs/2026-06-28-models-modulation-native-design.md`.

**Tech stack:** Godot 4.6 / GDScript. Test runner: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd` (the suite lives in `common/core/tests/`, run via any model). Baseline **65**.

## Global Constraints
- Modulation-native only: **no** new macros, params, or signature mechanics; existing mechanics only.
- Events fire on real discrete moments (no throttling); never emit every frame (esp. fluid).
- Suite stays green; use the live printed total (baseline 65), set the README `## Tests` line to it.
- Per-model headless smoke must be clean (no `SCRIPT ERROR`/`Parse Error`).
- Determinism + non-modulated presets unaffected (removing the Director just means non-modulated presets don't drift, as before it existed).
- `emit_event(name)` is an existing `SimModel` method that routes to `mod_stack.emit(name)`.

---

### Task 1 — supernova_orbit: migrate odyssey off the Director + add events

**Files:** `supernova_orbit/main.gd`, `supernova_orbit/presets/odyssey.json`, `supernova_orbit/presets/odyssey_slow_pulse.json`, `common/core/tests/run_tests.gd`.

- [ ] **Read `common/core/director.gd`** to see its two-sine drift (periods/ratio, output range) so the LFO migration matches its character. Read `supernova_orbit/main.gd` to find the detonation/fission/merge moments and `get_schema()` macro names.

- [ ] **Add events to `supernova_orbit/main.gd`:** `emit_event("detonation")` where the core detonates (survey ~491), `emit_event("fission")` where a core fissions (~489), `emit_event("merge")` where two cores merge (~467). Place at the correct semantic spots (read the code; the hints are approximate).

- [ ] **Migrate `odyssey.json`:** remove the `director` block; add `modulators` — one LFO per old director macro (`accretion`, `chaos`, `duality`), each two incommensurate sine oscillators, plus a detonation envelope:

```json
"modulators": {
  "lfo": [
    {"name": "accretion_drift", "oscillators": [
      {"shape": "sine", "period_sec": 60.0, "phase_deg": 0.0, "amount": 0.6},
      {"shape": "sine", "period_sec": 83.0, "phase_deg": 40.0, "amount": 0.4}],
     "targets": [{"to": "accretion", "amount": 0.45}]},
    {"name": "chaos_drift", "oscillators": [
      {"shape": "sine", "period_sec": 60.0, "phase_deg": 120.0, "amount": 0.6},
      {"shape": "sine", "period_sec": 83.0, "phase_deg": 200.0, "amount": 0.4}],
     "targets": [{"to": "chaos", "amount": 0.45}]},
    {"name": "duality_drift", "oscillators": [
      {"shape": "sine", "period_sec": 60.0, "phase_deg": 240.0, "amount": 0.6},
      {"shape": "sine", "period_sec": 83.0, "phase_deg": 300.0, "amount": 0.4}],
     "targets": [{"to": "duality", "amount": 0.45}]}
  ],
  "envelope": [
    {"name": "flash", "event": "detonation", "attack": 0.05, "decay": 0.6, "peak": 1.0,
     "targets": [{"to": "chaos", "amount": 0.2}]}
  ]
}
```
  (Keep the preset's existing `seed`/`duration_sec`/`macros`/`overrides`. If old director `amplitude`/`period_sec` differ from 0.45/60, use the preset's actual values.)

- [ ] **Migrate `odyssey_slow_pulse.json`** the same way, using ITS director params (read them) for the oscillator periods + target amounts.

- [ ] **Test** in `run_tests.gd`:
```gdscript
func test_supernova_odyssey_is_modulation_native() -> void:
	var txt := FileAccess.get_file_as_string("res://../supernova_orbit/presets/odyssey.json")
	var d = JSON.parse_string(txt)
	check(d != null, "odyssey.json parses")
	check(not d.has("director"), "odyssey has no director block")
	check(d.has("modulators"), "odyssey has modulators")
	check_eq(d["modulators"]["lfo"].size(), 3, "odyssey has 3 macro-drift LFOs")
```
  (If `res://../supernova_orbit/...` doesn't resolve from the radial_burst project, use an absolute path read or `FileAccess.open` on the repo path; confirm the path works headlessly.)

- [ ] Run suite (live total, expect 66) + smoke: `godot --headless --path supernova_orbit --quit-after 90 -- --preset presets/odyssey.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo CLEAN`. Commit `supernova_orbit: migrate odyssey to modulation + detonation/fission/merge events`.

---

### Task 2 — Retire the Director

**Files:** `common/core/sim_model.gd`, `common/core/director.gd` (delete), `common/core/preset_io.gd`, `common/core/designer/designer.gd`, `common/core/tweak_panel.gd`, `common/core/tests/run_tests.gd`, `README.md`.

- [ ] **Read** `sim_model.gd` (the `_process` director branch + `director`/`director_cfg` members + instantiation), `preset_io.gd` (`load_preset` director handling + `save_preset` signature), and grep `grep -rn "save_preset(\|director_cfg\|director" common/ supernova_orbit radial_burst` to find every reference.

- [ ] **`sim_model.gd`:** remove the Director branch from `_process` (the modulation-disabled path that ticks the director) and the `director`/`director_cfg` members + instantiation. `_process` should compose+apply only when `mod_stack.enabled`, else do nothing.

- [ ] **`preset_io.gd`:** in `load_preset`, if the JSON has a `director` key, push a warning into `warnings` and do NOT include it in the returned preset (ignore it). Remove the `director` parameter from `save_preset` (new tail: `…, jitter: Dictionary, modulators := {}`); stop writing `doc["director"]`.

- [ ] **Update callers:** `designer.gd` `save_now` — drop `model.director_cfg` from the `PresetIO.save_preset(...)` call. `tweak_panel.gd` Save path — same if it passes director. Any test calling `save_preset` with a director arg — fix to the new signature.

- [ ] **Delete** `common/core/director.gd`.

- [ ] **README:** replace the `### Director` section with a `### Modulation` section: scenes carry a `modulators` block (tween / LFO-of-oscillators / event envelope) composed live each frame; author it visually with `--designer`. Keep it proportionate to the old section.

- [ ] **Tests** in `run_tests.gd`:
```gdscript
func test_preset_ignores_legacy_director() -> void:
	var path := "/tmp/vx_legacy_director.json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"model": "demo", "director": {"enabled": true, "macros": ["energy"]}}))
	fa.close()
	var res := PIO.load_preset(path, _demo_schema(), "demo")
	check(res["ok"], "loads despite legacy director key")
	check(not res["preset"].has("director"), "director key is dropped, not carried")
	check(res["warnings"].size() >= 1, "warns about the ignored director key")
```
  Update the existing `test_preset_roundtrip` if it passed a director arg to `save_preset` (it should now omit it).

- [ ] Run suite (expect ~67) + a quick smoke on two models (`supernova_orbit` with odyssey, `radial_burst` with pulsar) → CLEAN. Commit `core: retire the Director (superseded by the modulation system)`.

---

### Tasks 3–6 — Events for the remaining models

Each task: **read the model's `main.gd`**, add the listed `emit_event()` calls at the correct semantic moments (survey hints are approximate), run suite (stays green) + headless smoke, commit. No preset changes here.

- [ ] **Task 3 — peg_cascade** (`peg_cascade/main.gd`): `emit_event("hit")` when a peg is lit (~252), `emit_event("chain")` when a chain blast triggers (~277), `emit_event("spawn")` when a ball is fired (~294). Smoke: `godot --headless --path peg_cascade --quit-after 60 -- --preset presets/default.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo CLEAN`. Commit `peg_cascade: emit hit/chain/spawn events`.

- [ ] **Task 4 — chromatic_cascade** (`chromatic_cascade/main.gd`): `emit_event("hit")` on ball↔peg contact (~280), `emit_event("shockwave")` on chain blast (~309). Smoke (path chromatic_cascade). Commit `chromatic_cascade: emit hit/shockwave events`.

- [ ] **Task 5 — matter_cycle** (`matter_cycle/main.gd`): `emit_event("shatter")` on polygon break (~215/237), `emit_event("condense")` on swarm condense (~328), `emit_event("spawn")` on body spawn (~293). Smoke (path matter_cycle). Commit `matter_cycle: emit shatter/condense/spawn events`.

- [ ] **Task 6 — fluid_swirl** (`fluid_swirl/main.gd`): `emit_event("inject")` once per injector **cycle** (~91) — NOT every frame. If injection has no clear cycle boundary, omit the event and note it in the report (fluid's starter will use LFO/tween only). Smoke (path fluid_swirl). Commit `fluid_swirl: emit inject event (per cycle)`.

---

### Task 7 — Seed starter long-form presets

**Files:** create `peg_cascade/presets/clockwork.json`, `chromatic_cascade/presets/fresco.json`, `matter_cycle/presets/tides.json`, `fluid_swirl/presets/aurora.json`.

- [ ] **Read each model's `get_schema()`** to confirm macro names + sensible mid-range macro values, then create each preset. Shape: `{model, seed, duration_sec: 300, macros, overrides: {}, jitter: {}, modulators}`. Use the spec's per-model table. Template (peg_cascade `clockwork`):

```json
{
  "model": "peg_cascade",
  "seed": 1337,
  "duration_sec": 300.0,
  "macros": {"complexity": 0.4, "ball_rate": 0.3, "bounciness": 0.5, "fx": 0.3},
  "overrides": {},
  "jitter": {},
  "modulators": {
    "tween": [
      {"name": "build", "secs": 275.0, "curve": "ease_in", "from": 0.0, "to": 1.0,
       "targets": [{"to": "ball_rate", "amount": 0.5}, {"to": "fx", "amount": 0.5}]}
    ],
    "lfo": [
      {"name": "texture", "oscillators": [
        {"shape": "sine", "period_sec": 45.0, "phase_deg": 0.0, "amount": 1.0}],
       "targets": [{"to": "complexity", "amount": 0.2}]}
    ],
    "envelope": [
      {"name": "burst_fx", "event": "chain", "attack": 0.03, "decay": 0.5, "peak": 1.0,
       "targets": [{"to": "fx", "amount": 0.3}]}
    ]
  }
}
```
  Build the other three analogously from the spec table:
  - `fresco` (chromatic_cascade): macros `{complexity:0.4, ball_rate:0.3, ink:0.4, shockwave:0.4}`; build → `ball_rate`+`ink`; LFO → `complexity`; envelope `shockwave` → `ink`.
  - `tides` (matter_cycle): macros `{matter:0.4, fragility:0.4, turbulence:0.4, cycle_speed:0.4}`; build → `matter`+`cycle_speed`; LFO → `turbulence`; envelope `shatter` → `fragility`.
  - `aurora` (fluid_swirl): macros `{turbulence:0.4, viscosity:0.5, flow:0.4, vibrance:0.5}`; build → `turbulence`+`flow`; LFO → `vibrance`; envelope `inject` → `flow` **only if Task 6 emits `inject`** (else omit the envelope).

- [ ] **Smoke each** new preset: `godot --headless --path <model> --quit-after 90 -- --preset presets/<starter>.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|warning" || echo CLEAN` (no unknown-macro/param warnings → macro names correct).

- [ ] **README:** add the four new starters to the variation-presets list (one line each, brief). Commit `presets: seed long-form modulation starters (clockwork/fresco/tides/aurora)`.

---

## Self-review
- Spec coverage: events (Tasks 1,3–6) ✓; supernova migration (Task 1) ✓; Director retirement (Task 2) ✓; starter presets (Task 7) ✓; verification (per-task suite + smoke) ✓.
- Order: supernova migrated (1) before Director retired (2) so no preset uses the Director when it's removed; events (3–6) before starters (7) so envelopes have events to bind.
- Placeholder scan: event placements are "read + place at semantic spot" (inherent — adding a call at a described moment), with survey line hints; no TODO/TBD.
- Types: `emit_event(String)` (existing); `PIO.load_preset(path, schema, model)` / `save_preset(path, model, seed, dur, macros, overrides, jitter, modulators)` (director param removed in Task 2); preset JSON shape matches `pulsar.json`.
