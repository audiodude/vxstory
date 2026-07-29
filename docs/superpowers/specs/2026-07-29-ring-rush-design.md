# ring_rush — design spec & implementation handoff

**Date:** 2026-07-29 · **Status:** approved design, not yet implemented
**Audience:** an LLM (or human) implementing this model in the vxstory repo with no prior context. Everything needed is in this document plus the repo itself.

---

## Part 1 — Repo background: what vxstory is and how it operates

vxstory is a collection of parameterized generative video models built in **Godot 4.x** (GDScript; the binary on this machine is 4.7.1, projects declare "4.6" features). Each model is a self-contained Godot project directory at the repo root (`radial_burst/`, `supernova_orbit/`, `peg_cascade/`, `chromatic_cascade/`, `matter_cycle/`, `fluid_swirl/`, `metro_rise/`) sharing a common framework via `common/core/`, which is **symlinked into each project as `<model>/core/`**. Output is 1920×1080@60fps video rendered deterministically with Godot's Movie Maker mode. The long-form 300-second pieces feed a 24/7 generative radio/video station, so determinism, scrub-exactness, and slow legible arcs matter.

### The framework (`common/core/`)

- **`sim_model.gd`** — base class every model's `main.gd` extends (a `Node2D` root). Subclass contract:
  - `model_name() -> String`
  - `get_schema() -> Dictionary` — declares macros + params (see below)
  - `restart()` — (re)build the whole world from `rng` + `params`; called on seed change and preset load
  - `apply_live(changed: Dictionary)` — react to live param changes (may be a no-op if params are read fresh every frame)
  - `_on_scrub(t: float)` — transport jumped to time `t`; make time-dependent state consistent
  - `emit_event(kind: String)` — fire named events that preset envelope modulators can bind to
  - The base class handles the param store (`params` dict), seeding (`seed_value`, `rng`), transport, and designer/tweak-panel plumbing.
- **`param_schema.gd`** (`PS`) — schema builders: `PS.f(name, default, min, max, opts)`, `PS.i(...)`, `PS.e(name, default, PackedStringArray values)`, `PS.macro_def(name, default)`. Opts:
  - `{"live": false}` → structural param, changing it triggers `restart()`
  - `{"macro": {"name": "density", "lo": 0.55, "hi": 0.95}}` → param is driven by that macro, linearly mapped lo→hi (`macro_mapper.gd`)
- **`modulation.gd` / `mod_sources.gd`** — the ModStack. Presets attach **tweens** (one-shot ramps; negative `from` gives a delayed start), **LFOs**, and **envelopes** (triggered by `emit_event` kinds) to macros/params. Offsets **add** to the macro base value. Curves: `linear`, `ease_in`, `ease_out`, `smooth`.
- **`preset_io.gd`** — presets are JSON in `<model>/presets/*.json` with keys `model, seed, duration_sec, macros, overrides, jitter, modulators`. See `metro_rise/presets/century.json` for a canonical long-form example.
- **`rng_service.gd`** — `rng.stream("name")` gives an independent deterministically-seeded `RandomNumberGenerator` per subsystem; use one stream per generator stage so adding a stage never perturbs others.
- **`render_driver.gd` / `transport_link.gd` / `tweak_panel.gd` / `designer/`** — offline render harness, transport, and the interactive tuning UI. You don't touch these.

### Rendering & verifying

- `scripts/render.sh <model> <preset> [duration_sec]` → `renders/<model>_<preset>.mp4` (Movie Maker, `--fixed-fps 60`). Needs a display; wrap in `xvfb-run -a` when headless.
- `scripts/render-batch.sh [dur] [model:preset ...]` renders the long-form set (one preset per model — add the new model's long-form preset to `SET` when done).
- **Ground truth is looking at frames**: render, then `ffmpeg -i out.mp4 -vf fps=... frames/f%03d.png` and inspect the PNGs. Headless smoke runs do not execute shaders.
- **Compressed-arc proof ritual:** to proof a 300 s preset's full arc cheaply, make a temp clone of the preset with every modulator duration ÷5 and render 60 s. Structure/timing bugs show up; final grading uses the real 300 s render.
- Tests: each model has `<model>/tests/run_tests.gd`; shared core tests live in `common/core/tests/`. Run hosted in any one project, e.g. `godot --headless --path ring_rush --script res://tests/run_tests.gd` and `godot --headless --path radial_burst --script res://core/tests/run_tests.gd`.

### House conventions (hard-won; follow them)

1. **Tuning lives in schemas, not presets.** `default.json` must keep `"overrides": {}`. To retune the default look, change schema defaults or macro lo/hi ranges. Variation presets may use overrides — that's their purpose. Do not preserve old preset looks when retuning schemas (no preset back-compat; git tags are the safety net).
2. **3D-under-2D pattern** (proven by `metro_rise`): a `Node3D` world (WorldEnvironment, lights, `Camera3D` with `cam.current = true`) added as a child of the 2D `SimModel` root renders full 3D beneath any `CanvasLayer` 2D overlay. Zero framework changes needed.
3. **3D pitfalls:** default dielectric `SPECULAR 0.5` sky-mirrors horizontal surfaces at grazing angles and washes the frame pastel — set `SPECULAR ~0.02` on matte materials (or use `render_mode unshaded`, which sidesteps lighting entirely). `MultiMesh.set_instance_color` expects **linear** colors — convert with `.srgb_to_linear()` or tints render pale. Sonic-style flat colors: `render_mode unshaded` fragment shaders are the right tool and avoid all of this.
4. **Z-fighting:** any two co-planar surfaces will shimmer; don't overlap flat geometry — butt pieces into dedicated junction geometry instead. Sub-pixel patterns (thin stripes, small checkers at distance) shimmer under motion — anti-alias procedural patterns with `fwidth()` and fade them out below coverage thresholds.
5. **2D feedback viewports** (not relevant here, but for context): must be LDR or additive content compounds to white; `Color("#hex")` constructors decode dark in linear rendering — use `Color(r,g,b)` floats.
6. **Per-model README:** every `<model>/README.md` documents its macros, params, events, and presets. Keep it in sync. Also add a row/section for the model in the repo root `README.md`.
7. The human reviews renders for aesthetics; the implementer does cheap structural checks (tests, frame extraction sanity) and hands off — no long self-directed aesthetic iteration loops.

---

## Part 2 — The `ring_rush` design (approved)

### Concept

An homage to the Sonic 2 special stage: a chunky pixel-art **robot** (billboarded sprite) races down a real **3D twisting halfpipe/tube** rendered in bold flat checkered colors, sweeping up **rings**, dodging **spiky bombs**, with a **retro HUD** ring counter — one continuous 300-second escalation from lazy cruise to corkscrew frenzy, then a cooldown outro. No Sega IP: original character, original palettes; the *feel* of the reference screenshots (pseudo-3D tube, checkers, starfield sky, chunky HUD), not the artifact.

Decisions locked with the user:

| Question | Decision |
|---|---|
| Rendering | **True 3D tube** — Camera3D flying through real geometry, unshaded flat-color shaders for the retro look (not a Genesis-style scanline fake) |
| Character | **Little robot**, rendered as a **billboarded pixel-art sprite** (frames generated in the local ComfyUI; this is the repo's first image asset, by explicit user approval) |
| Arc | **One endless escalation** — no discrete stages; gradual speed-up, palette drift, twist ramp to frenzy, cooldown outro |
| Extras | **Bombs to dodge** + **retro HUD overlay**. Cut: buddy bot, quota/fail states, stage-gated palettes, sound |
| Character ref | User picks the robot design from 2–3 generated refs (the one mid-implementation gate) |

### Architecture

Directory: `ring_rush/` (Godot project mirroring `metro_rise/`'s layout: `main.gd`, `main.tscn`, `core` symlink, `sim/`, `view/`, `presets/`, `tests/`, `assets/`, `README.md`, `project.godot`).

Everything visible derives from **one master coordinate `s`** (distance along the tube) plus live dials — the same pure-function philosophy as metro_rise's `city(P)`:

- **`sim/path.gd`** — `path(s) -> {pos, tangent, normal, binormal}`: a pure function built from seeded layered sines (per-axis amplitude/frequency/phase from `rng.stream("path")`), with a **parallel-transport frame** to avoid roll flips. Curvature, climb, and bank amplitudes scale with a twist parameter. Pure-function-of-s ⇒ structure is exact under scrubbing.
- **`sim/patterns.gd`** — pure seeded placement functions of s: ring formations (rows across the tube, arcs, spirals — classic special-stage shapes) chosen per ~40 m "phrase" from `rng.stream("rings")`; sparse bomb placements from `rng.stream("bombs")` with a guaranteed clear lane. Density inputs are live params.
- **`sim/runner.gd`** — deterministic steering: the robot's angular lane position on the tube cross-section as a function of s — attracted to the next ring cluster's lane, repelled by bombs (swerve), plus a gentle sway LFO. Also picks the sprite animation state (run / roll at high speed / swerve-left / swerve-right / near-miss wobble).
- **`sim/clock`** (inside `main.gd`) — `s` advances by `speed * delta`; speed = f(pace param). `_on_scrub(t)` recomputes `s` deterministically (speed is integrated from the transport time using current params, so scrubbing lands where a straight play would).
- **`view/tube_view.gd`** — procedural tube chunks: `ArrayMesh` segments (~40 m each, ~24 radial × ~16 longitudinal quads) generated ahead of the camera, recycled behind it (ring buffer of ~12 chunks). Cross-section = arc from `-aperture` to `+aperture` where aperture morphs **halfpipe (~200°) → full tube (360°)** via a live morph param; UVs are (path-length, angle) so the checker shader is stable across chunk seams.
- **`view/tube.gdshader`** — `render_mode unshaded`; procedural checkers + lane stripes + rail/edge banding in bold flat colors from a palette function (base palette enum + continuous hue drift over the run); `fwidth()` anti-aliasing on all pattern edges; darkening by tube depth for fake occlusion; subtle emissive scanline shimmer optional.
- **`view/sky.gdshader`** — background sky: starfield + horizontal cloud-band gradient (per the reference screenshots), visible through the open half of the pipe; star density and palette follow the tube palette.
- **`view/ring_view.gd`** — MultiMesh of flat gold rings (torus or unshaded billboard quads with a ring shader), spinning; pickup = despawn + sparkle burst (GPUParticles or a short-lived quad flipbook) + HUD increment + `emit_event("ring")`.
- **`view/bomb_view.gd`** — MultiMesh spiky spheres (icosphere + spike cones, unshaded dark + red glints). Near-miss (runner passes within threshold) fires `emit_event("near_miss")` + wobble animation state.
- **`view/robot_view.gd`** — a `QuadMesh` billboard textured from `assets/robot_sheet.png`, frame-indexed by animation state + phase; positioned on the tube surface at the runner's lane angle, leaning into swerves; drop shadow blob beneath.
- **`view/hud.gd`** — `CanvasLayer` overlay drawing with a **code-drawn 5×7 bitmap pixel font** (no font asset): `RINGS <n>` counter top-left with the chunky bordered-panel look, occasional flashing center banner (`SPEED UP!`) at escalation milestones (`emit_event("milestone")`).
- **`main.gd`** — orchestrator: builds world + camera (chase cam behind/above the runner, look-ahead along the path, FOV widening with speed), evaluates path/patterns/runner per frame, feeds views, emits events.

### Schema sketch

Macros: `escalation` (master dial: speed + twist + density + morph all key off it via macro mappings), `pace`, `twist`, `ring_density`, `hazard`, `tube_morph`, `drift` (palette drift rate).
Live params (indicative): `speed`, `twist_amount`, `bank_amount`, `rings_per_phrase`, `bomb_rate`, `aperture`, `checker_scale`, `palette` (enum: e.g. `arcade`, `midnight`, `bubblegum`), `hue_drift`, `glow`, `star_density`, `cam_dist`, `cam_fov`, `sway`.
Structural (`live: false`): `seed`-derived path personality (amplitude ranges, phrase length), sprite scale, tube radius.
Events: `ring`, `near_miss`, `milestone`.

### Character pipeline (the one user gate)

1. Generate 2–3 original little-robot pixel-art reference designs with the local ComfyUI (MCP server `comfy-mcp`; `run_workflow`/`image_download`). Style target: 90s 16-bit mascot, ~48–64 px tall, bold 3–4 color palette, big readable silhouette.
2. **Pause and ask the user to pick one** (this is the only mid-implementation gate).
3. Generate/derive the frame set from the chosen ref: run cycle (4–6), ball-roll (2–4), swerve L/R (2 each), wobble (2). Consistency matters more than frame count — if ComfyUI consistency across frames is poor, generate the key poses and produce tweens by pixel-editing programmatically (palette-locked transforms), or reduce to fewer, punchier frames (Genesis games used very few).
4. Pack into `ring_rush/assets/robot_sheet.png` (+ a small JSON/GDScript frame map). Import with filtering **off** (nearest-neighbor) for crisp pixels.

### Presets

- `default.json` — mid-escalation, mid-density, `overrides: {}` (convention #1).
- Variants: `midnight.json` (dark palette, high stars, high glow), `bubblegum.json` (candy palette, low hazard, dense rings) — variants may use overrides.
- **`velocity.json`** — the 300 s long-form piece: tween `escalation` 0.05→1.0 over ~280 s (`smooth`), ease-out cooldown at the end (a second late tween pulling pace back down), tween `tube_morph` halfpipe→tube across the middle, slow LFO on camera sway, envelopes: `ring` → small glow pip, `near_miss` → brief shake/FOV kick, `milestone` → banner + glow surge. Add `ring_rush:velocity` to `scripts/render-batch.sh` SET when it grades well.

### Tests (`ring_rush/tests/run_tests.gd`)

- `path(s)` determinism (same seed ⇒ identical frames at sampled s) and frame orthonormality/continuity (no roll flips).
- Pattern placement determinism; rings and bombs never coincide; a clear lane always exists.
- Runner steering stays on the tube surface (angle within aperture) for the full run at max hazard.
- Scrub consistency: `s(t)` after `_on_scrub(t)` matches continuous playback within epsilon.
- HUD count equals emitted `ring` events.
- Schema sanity (all macro targets exist; default preset has empty overrides).
- Plus the shared core suite stays green.

### Definition of done

1. All model tests + shared core tests pass.
2. `scripts/render.sh ring_rush default 10` produces frames that look right (checkers crisp, no shimmer, robot readable, HUD correct).
3. Compressed ÷5 proof of `velocity` reviewed frame-by-frame for arc structure; then the full 300 s render.
4. `ring_rush/README.md` + root `README.md` updated; `render-batch.sh` SET updated.
5. Human reviews the render (aesthetics are their call — see convention #7).
