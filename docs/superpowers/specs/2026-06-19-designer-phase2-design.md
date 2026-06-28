# Scene authoring — Phase 2 (the Designer) — design

**Date:** 2026-06-19 (revised after layout brainstorm)

## Goal

Build the **Designer**: compose a render's modulation program **visually** —
graphical oscillator/tween/envelope editors and Ableton-style rotary knobs — and
write `scene.json`. It is the *only* thing that edits the scene; never hand-edit
JSON. It runs beside the Phase 1 preview: Designer writes `scene.json` → preview
hot-reloads → you watch/scrub. Principle: **a value is shown as what it does** —
a curve, a waveform, an envelope, or a knob whose ring moves; never a bare number.

## Architecture — Designer as a *mode inside the model's project*

Launch `godot --path <model> -- --designer [--scene presets/<name>.json]`.
`SimModel._ready` sees `--designer` and, instead of building the sim, attaches the
Designer UI to the (un-built) model instance. Because it's the model's own
project, the Designer reads the schema directly from `self.get_schema()` — **no
JSON export, no cross-project loading.** Still two processes/windows as intended
(Designer + preview), both the model project in different modes; you pick the
model via `--path` (one model per Designer window).

- Designer code lives in `common/core/designer/` (symlinked into each model as
  `core/designer`, like `core`), reusing `param_schema.gd`, `mod_sources.gd`,
  `modulation.gd`, `preset_io.gd`.
- **Input:** the model (schema via `get_schema()`) + a scene file (`--scene`).
- **Output:** writes the scene file via `preset_io.save_preset` on every change
  (debounced ~150 ms) → the Phase 1 preview hot-reloads.

## Live knobs via the Designer's own clock

The Designer holds the scene in memory and, to **animate the knobs Ableton-style**,
runs its *own* modulation clock with a small **transport** (play / pause / scrub /
loop). Each frame it composes values through the modulation engine
(`ModStack`/`mod_sources`) at the current `t` and shows, per knob: the **pointer =
the set base value**, a **colored ring = the live modulated value**. So you watch
the build sweep, the LFO wobble, the envelope flash — on the knobs themselves. No
sim render in the Designer; the render + its scrub stay in the preview window.

## UX components (`common/core/designer/widgets/`)

1. **Knob** — Ableton rotary: vertical-drag to change, Shift = fine, double-click =
   reset to default; pointer = base, animated ring = live modulated value.
2. **LFO card / OscillatorEditor** — an LFO is a **stack of oscillators**; each
   oscillator has shape (`sine|triangle|saw|square`), `period_sec`, `phase_deg`,
   `amount`, with its own mini-wave; plus a **summed-output** preview (the actual
   signal). (`[+ oscillator]` to add is 2b.) Matches the engine, which already
   models LFOs this way (`mod_sources.osc` + `lfo_value`).
3. **CurveEditor (tween)** — curve-type picker (`linear|ease_in|ease_out|smooth`) +
   `secs`/`from`/`to` knobs + a live curve preview (`mod_sources.tween`).
4. **EnvEditor** — `attack`/`decay`/`peak` knobs + a live shape preview
   (`mod_sources.envelope`) + the trigger-event picker.
5. **SourceCard** — header + **preview-on-top** + the type editor + **source-centric
   routing** rows (destination + amount knob + remove).
6. **BasesPanel** — superparam knobs + a **"Show all basic params (A–Z)" zippy**:
   collapsed by default; expands to every basic param as knobs, sorted
   alphabetically.

All previews are drawn from the same `mod_sources` the engine runs — zero drift.

## Layout (settled — see the approved v4 mock)

A compact **~700 px panel, centered** (a tool panel, not full-bleed):

```
┌ DESIGNER · radial_burst · pulsar.json        ▶ ▭▭▭|▭ 1:18/5:00 ⟲ ┐
│ BASES — superparams                                               │
│   (energy) (density) (symmetry) (grit) (coupling)   ← animated     │
│   ▸ Show all basic params (A–Z)                                    │
│ SOURCES                              [+ LFO] [+ Tween] [+ Env] (2b)│
│ ┌ TWEEN "build" ─────────────────────────────────────────────────┐│
│ │ [curve preview ───────────────] curve: linear ▾                ││
│ │ (secs)(from)(to)                                               ││
│ │ → energy ◦ 0.45 ✕   → density ◦ 0.40 ✕   → coupling ◦ 0.70 ✕   ││
│ └────────────────────────────────────────────────────────────────┘│
│ ┌ LFO "grit_wobble" ──────────────────────────────────── [+osc] ─┐│
│ │ [summed wave preview ──────────────────────────────]           ││
│ │ ┌ OSC 1: sine (per)(ph)(amt) ┐ ┌ OSC 2: sine (per)(ph)(amt) ┐  ││
│ │ → grit ◦ 0.20 ✕                                                ││
│ └────────────────────────────────────────────────────────────────┘│
│ ┌ ENV "flash" ──────────────────────────────── on: burst ▾ ──────┐│
│ │ [env preview ──] (atk)(dec)(peak)   → glow ◦ 0.35 ✕            ││
│ └────────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────────┘
```

Vertical stack of source cards, each **preview-on-top, controls below**.

## scene.json contract

The preset format (model, seed, duration, macros, overrides, jitter, modulators).
`modulators.lfo[]` uses the oscillator form: `{name, oscillators:[{shape,
period_sec, phase_deg, amount}], targets:[{to, amount}]}`. Designer mutates the
in-memory scene and saves on change; the file is the bus.

## Decomposition (each its own plan)

- **2a — Widgets + edit an existing scene** *(first cycle, the detailed one):* the
  Knob (animated, via the transport clock), CurveEditor, OscillatorEditor/LFO
  card, EnvEditor; load model schema + scene; the Bases panel incl. the
  "Show all basic params (A–Z)" zippy; edit the **existing** sources' params,
  oscillators, bases, and routing **amounts**; the transport (play/pause/scrub);
  write `scene.json` on change. **No add/remove** of sources/routings/oscillators
  yet; no drag-handle curve editing. This alone ends hand-editing JSON.
- **2b — Compose scenes.** `[+ LFO/Tween/Env]`, `[+ oscillator]`, `[+ route]`,
  remove buttons, destination dropdowns over the full schema, scene picker /
  save-as.
- **2c — Direct manipulation + MIDI.** Drag curve/envelope/oscillator handles;
  **MIDI CC** mapping hardware knobs to scene params.

## Verification

- Pure widget math is unit-tested (knob value↔angle; previews reuse the
  already-tested `mod_sources`); scene round-trip via `preset_io`; the `--designer`
  launch path (attaches Designer, reads `get_schema()`, doesn't build the sim) via
  headless smoke.
- The GUI is verified by running it (xvfb screenshot + your review) and the
  integration loop: Designer writes `scene.json` → preview hot-reloads.
- Like the rest of vxstory, look/feel is your visual review; automated checks
  cover the logic and the file contract.

## Decisions locked (former open questions)

- **Schema access:** C — Designer as a mode in the model's project; schema via
  `get_schema()`.
- **2a scope:** edit existing scene only (no add/remove).
- **Designer shows signal shapes + animated knobs**; render/scrub stay in the
  preview window.
- **Knob conventions:** vertical-drag · Shift-fine · double-click-reset; pointer =
  base, ring = live modulated value.
- **Layout:** ~700 px compact centered panel, vertical source stack,
  preview-on-top (v4 mock approved).
- **LFO model:** oscillator stack (engine already shipped — `mod_sources.osc` +
  `lfo_value`, shapes sine/triangle/saw/square).

## Out of scope (Phase 2)

- The Phase 1 preview (done).
- 2b/2c features until those cycles.
- Multi-model composition in one window; frame-exact anything.
