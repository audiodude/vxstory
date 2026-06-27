# Scene authoring (designer + live preview) — design

**Date:** 2026-06-19

## Vision

Make vxstory a place where you **program a whole render as a scene**, not where you
fiddle individual parameters. A scene is the modulation *program* for one model
(the instrument): superparam bases + sources (LFOs / tweens / envelopes) + their
routings + the run's duration. The guiding principle, in the user's words:
**a value is only meaningful as what it does** — `energy = 0.754` is noise; the
*curve* energy traces and the blooms it produces are the signal. Every value is
presented as its behavior (a curve, a motion, a result), never as a bare number.

Two processes, connected by one file:

- **Designer** (a second Godot app) — the authoring surface: graphical ADSR/LFO
  editors and Ableton-style rotary knobs. It is the *only* thing that edits the
  scene file; you never hand-edit JSON (that would be back to `0.754`).
- **Preview** (the existing Godot model app) — read/scrub only. Watches the scene
  file, hot-reloads on change, and draws the render plus a scrubbable timeline.
- **`scene.json`** (the existing preset format: model, seed, duration, macros,
  overrides, jitter, modulators) — the one-way contract: designer writes, preview
  reads. The file is the bus; the two processes stay decoupled.

Both are Godot so the designer reuses `get_schema()`, `mod_sources.gd` (its curves
are *exactly* what the engine produces — zero drift), and `preset_io.gd`.

## Decomposition

- **Phase 1 — Preview upgrade** (this spec): hot-reload + a read-only scrub
  timeline + a wipe indicator. Small; the foundation the designer targets;
  de-risks the scrub mechanics.
- **Phase 2 — Designer app** (separate spec, next): the graphical authoring. All
  visual UX — gets its own brainstorm with layout mockups.

### Deferred / TODO (captured, not built)

- **Preview playback controls:** Space = play/pause; ←/→ = skip ∓30s; loop
  markers. (Phase 1 builds the playhead/scrub; these transport niceties come
  after.)
- **Designer MIDI CC input:** map hardware controller knobs to scene params.
- **Designer grab-and-reshape on a timeline:** direct curve-handle dragging that
  writes back to the scene (the preview stays read-only regardless).

---

## Phase 1 — Preview upgrade

Applies to a model running in preview (non-movie) mode with a `--preset` scene
that has modulators. Non-modulator presets keep today's behavior (the timeline
simply has nothing to draw).

### Hot-reload

The preview remembers the scene file path it was launched with and polls the
file's modification time (a few times a second). On change it reloads the preset
(`PresetIO.load_preset`), re-adopts it, and re-resolves/restarts — so saving in
the designer updates the running render with no manual restart. A malformed save
(load error) is ignored with a warning, leaving the last good state running
(don't crash the preview mid-session).

### Scrub timeline

A read-only strip along the bottom of the preview (its own `Control`), shown when
the scene has modulators:

- **Time axis** 0 → `duration_sec`.
- **Sources drawn as what they do over time:**
  - **Tweens** — the actual curve across the duration (this is how you *see* the
    build's shape; reshaping it is how the opening/plateau get fixed).
  - **LFOs** — the waveform at its rate.
  - **Envelopes** — event-triggered, so their firings aren't known ahead of time;
    they appear live as spikes on a lane as events fire (plus a static lane label
    so you know the routing exists).
- **Playhead** at the current modulation time, **draggable** (read-only otherwise).
- **Live composed values shown visually** — for the destinations a scene drives,
  a moving indicator (a dot/bar positioned within the param's range), updated each
  frame. Never a numeric readout.

### Scrub semantics (character-at-`t`, not frame-exact)

The render's on-screen state is path-dependent (accumulated trails, in-flight
particles, ring positions), so it can't be reconstructed from `t` alone. Dragging
the playhead therefore: sets the modulation clock and the model's `sim_t` to `t`,
**clears the canvas**, and plays forward from there at `t`'s settings. Within a
second or two you see the *character* the program dictates at that point (density,
coupling, burst size, color) — which is what you tune against. Frame-exact
accumulation at `t` is explicitly out of scope.

### Wipe indicator

Because a scrub clears the canvas, a brief visual cue marks the reset so it reads
as intentional, not a glitch: a quick sweep/flash across the frame (and/or a
short-lived `⟲ m:ss` overlay at the new time) that fades within ~0.3 s. Fires on
any scrub-driven clear.

### Components / files

- `common/core/scene_watcher.gd` (new) — polls the scene-file mtime; calls back
  into the model to reload on change.
- `common/core/timeline.gd` (new) — the scrub-timeline `Control`: draws tween/LFO
  curves (via `mod_sources.gd`) + envelope-firing lanes + playhead + live-value
  indicators; handles playhead drag → `scrub_to(t)`.
- `common/core/sim_model.gd` — store the launched preset path; add
  `reload_from_file()` and `scrub_to(t)` (set clocks to `t`, restart visuals, fire
  the wipe indicator); attach the watcher + timeline in preview mode.
- Wipe indicator — a small overlay effect triggered by `scrub_to` (in `timeline.gd`
  or a tiny dedicated node).

The existing tweak panel stays as-is (Tab-toggle); the timeline is additive. The
designer (Phase 2) is what removes hand-tuning — Phase 1 doesn't touch the panel.

### Verification

- Pure logic (mtime-change detection, time→x mapping, value→indicator mapping) is
  unit-testable where it can be factored out; the timeline/scrub is verified by
  running the preview (manual: edit scene → see hot-reload; drag playhead → see
  jump + wipe).
- Existing suite stays green; the panel smoke (`test_tweak_panel_builds_rows`)
  still passes.
- Determinism unaffected (scrub only changes which `t` you view from).

## Out of scope (Phase 1)

- The designer app (Phase 2).
- The deferred TODOs above (playback transport, MIDI, grab-reshape).
- Frame-exact scrub / re-simulation.
- Removing or replacing the tweak panel.
