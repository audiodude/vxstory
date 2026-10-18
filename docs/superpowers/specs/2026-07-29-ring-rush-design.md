# ring_rush — design spec & implementation handoff

**Date:** 2026-07-29 · **Status:** approved design (amended after grilling round same day), not yet implemented
**Audience:** an LLM (or human) implementing this model in the vxstory repo with no prior context. Everything needed is in this document plus the repo itself.

**Amendment log (2026-07-29, grilling round):** the original draft made geometry-affecting params live and called for a parallel-transport frame; both were found to conflict with scrub-exactness and chunk coherence. Eight decisions were locked with the user and are integrated below: (1) event-aware replay integration for `_on_scrub`, (2) authored-roll frame (parallel transport dropped), (3) two-layer split — geometry is structural, escalation is expressed through live speed/density/palette, (4) normalized-`u` arc landmarks with calibrated `s_arc`, (5) camera rolls fully with the tube frame, (6) macro surface rationalized to 5 (`pace` deleted), (7) no loop constraint, plain cooldown ending, (8) rings as billboard quads, sparkles as GPUParticles.

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
- **`modulation.gd` / `mod_sources.gd`** — the ModStack. Presets attach **tweens** (one-shot ramps; negative `from` gives a delayed start), **LFOs**, and **envelopes** (triggered by `emit_event` kinds) to macros/params. Offsets **add** to the macro base value. Curves: `linear`, `ease_in`, `ease_out`, `smooth`. Tweens and LFOs are pure functions of the mod clock `t`; envelopes are stateful (event-triggered, instances lost on scrub — the framework's "character-at-t" contract).
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

## Part 2 — The `ring_rush` design (approved, amended)

### Concept

An homage to the Sonic 2 special stage: a chunky pixel-art **robot** (billboarded sprite) races down a real **3D twisting halfpipe/tube** rendered in bold flat checkered colors, sweeping up **rings**, dodging **spiky bombs**, with a **retro HUD** ring counter — one continuous 300-second escalation from lazy cruise to corkscrew frenzy, then a cooldown outro. No Sega IP: original character, original palettes; the *feel* of the reference screenshots (pseudo-3D tube, checkers, starfield sky, chunky HUD), not the artifact.

Decisions locked with the user:

| Question | Decision |
|---|---|
| Rendering | **True 3D tube** — Camera3D flying through real geometry, unshaded flat-color shaders for the retro look (not a Genesis-style scanline fake) |
| Character | **Little robot**, rendered as a **billboarded pixel-art sprite** (frames generated in the local ComfyUI; this is the repo's first image asset, by explicit user approval) |
| Arc | **One endless escalation** — no discrete stages; geometry arc lives in `s`-space (see below), speed/density/palette escalate live, cooldown outro at the end |
| Extras | **Bombs to dodge** + **retro HUD overlay**. Cut: buddy bot, quota/fail states, stage-gated palettes, sound |
| Character ref | User picks the robot design from 2–3 generated refs (the one mid-implementation gate) |
| Looping | **None** — the station hard-cuts between 300 s pieces like the other models; no closing banner, plain cooldown ending |

### The two-layer split (the core architectural decision)

Every existing vxstory model keeps geometry **structural** (built at `restart()`, frozen) and only forces/uniforms/camera live; metro_rise's one "live structure" dial works because it's a pure function of the dial recomputed each frame. ring_rush follows the same convention — this is what keeps chunks coherent and scrubbing cheap:

- **Structural layer — pure seeded functions of `s`, frozen at restart.** The path shape, twist/bank amplitude ramps, aperture morph, and ring/bomb placements are all profiles of the normalized arc coordinate `u = s / s_arc` with seeded texture, built once from `rng` + structural params. Tube chunks are generated once when they enter the visible window and **never rebuilt** — no stale-chunk problem, no seams.
- **Live layer:** `speed`, ring/bomb density thresholds, palette + hue drift, glow, star density, checker scale, camera dials. Read fresh each frame; zero structural consequence.
- **Transient layer — stateful, character-at-t on scrub** (metro_rise's traffic pattern): particles, sparkle bursts, banner flashes, camera shake/FOV kicks, sprite animation phase. Envelope instances are not replayed into the live ModStack after a scrub (framework-wide accepted behavior).

Key insight: since `s(t)` is monotonic, "twist ramps over the run" and "twist ramps over `s`" produce identical video — but the s-profile version is scrub-exact for free. Live geometry was costing us seam-management machinery for zero visual benefit.

### Architecture

Directory: `ring_rush/` (Godot project mirroring `metro_rise/`'s layout: `main.gd`, `main.tscn`, `core` symlink, `sim/`, `view/`, `presets/`, `tests/`, `assets/`, `README.md`, `project.godot`).

Everything visible derives from **one master coordinate `s`** (distance along the tube) plus live dials:

- **`sim/path.gd`** — `path(s) -> {pos, tangent, normal, binormal, aperture}`, a pure seeded function:
  - **Position:** layered sines per axis (amplitude/frequency/phase from `rng.stream("path")`).
  - **Frame — authored roll, NOT parallel transport.** Parallel transport is sequential accumulation (not pure in `s`, and any live or profile change would invalidate every downstream frame). Instead: tangent `T(s)` = analytic derivative of the position curve; reference normal = project a global up onto the plane ⊥ `T`, blending between two reference axes (world up / world side) weighted by tangent elevation so near-vertical segments can't flip the frame; bank = explicit seeded roll function `θ(s)` (layered sines) rotated about `T`. No integration, no flips by construction.
  - **Arc profiles in `u = s / s_arc`:** twist/bank amplitudes and aperture ramp along structural landmark params (`twist_ramp_u0/u1`, `aperture_full_u`, `frenzy_peak_u`), with seeded texture riding the ramp envelopes. Aperture morphs halfpipe (~200°) → full tube (360°).
- **`sim/patterns.gd`** — pure seeded placement functions of `s`: ring formations (rows across the tube, arcs, spirals — classic special-stage shapes) chosen per `phrase_len` (~40 m) phrase from `rng.stream("rings")`; sparse bombs from `rng.stream("bombs")` with a guaranteed clear lane **at max hazard**. Each ring/bomb carries a seeded threshold `u_i ∈ [0,1]`; it exists iff `u_i < ` the live density param — densities ramp only upward over the arc, so items only ever *appear*, far ahead, masked by depth. Pickup crossings, near-miss crossings, and milestone crossings are all pure functions of `s` (needed by the replay integrator).
- **`sim/runner.gd`** — deterministic steering: the robot's angular lane position on the tube cross-section as a function of `s` — attracted to the next ring cluster's lane, repelled by bombs (swerve), plus a gentle sway LFO. Also picks the sprite animation state (run / roll at high speed / swerve-left / swerve-right / near-miss wobble).
- **`sim/clock`** (inside `main.gd`) — playback: `s += speed * delta`; `speed = f(speed param)`. `_on_scrub(t)` = **event-aware replay integration**: build a scratch ModStack from `modulators_cfg`, integrate `s` over `[0, t]` in fixed ~50 ms steps, and at each step evaluate `patterns`/`runner` at the new `s` — when a pickup/near-miss/milestone crossing occurs, `scratch.emit(kind)`. Because tweens/LFOs are pure in `t` and events are pure in `s`, this reproduces continuous playback to within epsilon **even if an envelope targets `pace`/`speed`** — no restriction on envelope targets is needed. (Visual envelope instances in the *live* ModStack are still not replayed — character-at-t, as everywhere.) The replayed `ring` crossing count is also the HUD counter value.
- **`view/tube_view.gd`** — procedural tube chunks: `ArrayMesh` segments (~40 m each, ~24 radial × ~16 longitudinal quads), ring buffer of ~12 chunks generated ahead of the camera and recycled behind. Each chunk is built **once** from the structural `path(s)` when it enters the window — never rebuilt. Cross-section = arc from `-aperture(s)` to `+aperture(s)`; UVs are (path-length, angle) so the checker shader is stable across chunk seams.
- **`view/tube.gdshader`** — `render_mode unshaded`; procedural checkers + lane stripes + rail/edge banding in bold flat colors from a palette function (base palette enum + continuous hue drift over the run); `fwidth()` anti-aliasing on all pattern edges; darkening by tube depth for fake occlusion; subtle emissive scanline shimmer optional.
- **`view/sky.gdshader`** — background sky: starfield + horizontal cloud-band gradient, visible through the open half of the pipe (it wheels overhead during corkscrews — the camera rolls with the tube); star density and palette follow the tube palette.
- **`view/ring_view.gd`** — MultiMesh of **unshaded billboard quads with a ring shader** (spin faked via highlight/UV rotation — from the trailing chase cam it reads identically to a torus at a fraction of the cost). Per-instance visibility computed from `s` each frame (collected iff its pickup crossing is behind the runner). Pickup = sparkle burst (one reusable **GPUParticles** system, unshaded additive gold quads — no flipbook assets) + HUD increment + `emit_event("ring")`.
- **`view/bomb_view.gd`** — MultiMesh spiky spheres (icosphere + spike cones, unshaded dark + red glints). Near-miss (runner passes within threshold) fires `emit_event("near_miss")` + wobble animation state. No collisions, no fail states — the steering repulsion guarantees avoidance.
- **`view/robot_view.gd`** — a `QuadMesh` billboard textured from `assets/robot_sheet.png`, frame-indexed by animation state + phase; positioned on the tube surface at the runner's lane angle, leaning into swerves; drop shadow blob beneath.
- **`view/hud.gd`** — `CanvasLayer` overlay drawing with a **code-drawn 5×7 bitmap pixel font** (no font asset): `RINGS <n>` counter top-left (count from the replayed crossing tally — pure in `s`) with the chunky bordered-panel look, occasional flashing center banner (`SPEED UP!`) at structural `milestone_us` crossings (`emit_event("milestone")`).
- **`main.gd`** — orchestrator: builds world + camera, evaluates path/patterns/runner per frame, feeds views, emits events.
  - **Camera:** chase cam at a **fixed reference lane** (trailing behind, slightly above the frame's "floor") — the robot swings across the frame as it changes lanes (the Sonic 2 composition; lane-tracking would hide the dodges). **Full path-frame roll** (camera up = frame normal — the horizon follows the tube; horizon-lock at frenzy amplitudes is nauseating and exposes the authored roll). Transient feel layers (no determinism impact): bank smoothing toward `θ(s)` over ~150 ms, a soft dead-zone yaw easing a few degrees toward the robot's lane so wall-rides don't hit the frame edge, centerline pull-in at high curvature so closed-tube walls don't clip the near plane, FOV widening with speed.

### Schema

Macros (5):
- `escalation` — **live master**; maps to `speed`, `rings_per_phrase`, `bomb_rate`, `hue_drift`. The `velocity` tween target.
- `twist`, `tube_morph` — **structural** macros (metro's `sprawl` pattern): map to `live: false` params (profile amplitudes, aperture range); presets set them at load, designer changes restart.
- `ring_density`, `hazard` — independent live threshold dials.

(`pace` from the original sketch is deleted — redundant with `escalation`; base speed lives in `speed`'s default and macro range.)

Structural params (`live: false`): `s_arc` (design length of the piece, ~12–18 km), `tube_radius`, `phrase_len`, `sprite_scale`, path personality (sine amplitude/frequency ranges), profile landmarks (`twist_ramp_u0`, `twist_ramp_u1`, `aperture_full_u`, `frenzy_peak_u`), `aperture_start`, `aperture_end`, `milestone_us` (e.g. `[0.3, 0.6, 0.85]`).

Live params: `speed` (macro `escalation`), `rings_per_phrase` (macro `escalation`/`ring_density`), `bomb_rate` (macro `escalation`/`hazard`), `palette` (enum: `arcade`, `midnight`, `bubblegum`), `hue_drift` (macro `escalation`), `glow`, `star_density`, `checker_scale` (pure shader uniform), `cam_dist`, `cam_fov`, `sway`.

Events: `ring`, `near_miss`, `milestone`.

### Character pipeline (the one user gate)

1. Generate 2–3 original little-robot pixel-art reference designs with the local ComfyUI (MCP server `comfy-mcp`; `run_workflow`/`image_download`). Style target: 90s 16-bit mascot, ~48–64 px tall, bold 3–4 color palette, big readable silhouette.
2. **Pause and ask the user to pick one** (this is the only mid-implementation gate).
3. Generate/derive the frame set from the chosen ref: run cycle (4–6), ball-roll (2–4), swerve L/R (2 each), wobble (2). Consistency matters more than frame count — if ComfyUI consistency across frames is poor, generate the key poses and produce tweens by pixel-editing programmatically (palette-locked transforms), or reduce to fewer, punchier frames (Genesis games used very few).
4. Pack into `ring_rush/assets/robot_sheet.png` (+ a small JSON/GDScript frame map). Import with filtering **off** (nearest-neighbor) for crisp pixels.

### Presets

- `default.json` — mid-escalation, mid-density, `overrides: {}` (convention #1).
- Variants: `midnight.json` (dark palette, high stars, high glow), `bubblegum.json` (candy palette, low hazard, dense rings) — variants may use overrides.
- **`velocity.json`** — the 300 s long-form piece: tween `escalation` 0.05→1.0 over ~280 s (`smooth`), plus a late ease-out tween pulling it back down (the cooldown = slow cruise through peak-frenzy geometry; the geometry itself does not de-escalate); slow LFO on camera sway; envelopes: `ring` → small glow pip, `near_miss` → brief shake/FOV kick, `milestone` → banner + glow surge. The twist/aperture arc is structural (rides `u` automatically). **Calibrate `speed`'s escalation lo/hi so the tween integrates to `s(280) ≈ s_arc`** (verified by test). The ÷5 compressed proof is *more* faithful under this design: compressing the speed tween 5× traverses the same structural u-arc in the same order. Add `ring_rush:velocity` to `scripts/render-batch.sh` SET when it grades well.

### Tests (`ring_rush/tests/run_tests.gd`)

- `path(s)` determinism (same seed ⇒ identical frames at sampled `s`) and frame continuity across the whole `u` range at max twist (no roll flips, including across landmark transitions and the aperture full-close).
- Pattern placement determinism; rings and bombs never coincide; a clear lane always exists at max hazard.
- Runner steering stays on the tube surface (angle within `aperture(s)`) for the full run at max hazard.
- Scrub consistency: `s(t)` after `_on_scrub(t)` matches continuous playback within epsilon — **including a test preset with an envelope bound to `speed`**, proving event-aware replay makes the no-target-restriction claim true.
- HUD count equals emitted `ring` events (both from the replay tally).
- Arc calibration: with `velocity`'s modulators, integrated `s(280)` ≈ `s_arc` within tolerance.
- Schema sanity (all macro targets exist; default preset has empty overrides).
- Plus the shared core suite stays green.

### Definition of done

1. All model tests + shared core tests pass.
2. `scripts/render.sh ring_rush default 10` produces frames that look right (checkers crisp, no shimmer, robot readable, HUD correct).
3. Compressed ÷5 proof of `velocity` reviewed frame-by-frame for arc structure; then the full 300 s render.
4. `ring_rush/README.md` + root `README.md` updated; `render-batch.sh` SET updated.
5. Human reviews the render (aesthetics are their call — see convention #7).
