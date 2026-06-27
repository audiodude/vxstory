# Scene authoring — Phase 2 (the Designer app) — design

**Date:** 2026-06-19

## Goal

Build the **Designer**: a separate Godot app where you compose a render's
modulation program **visually** — graphical ADSR/LFO/tween editors and
Ableton-style rotary knobs — and which writes `scene.json`. It is the *only*
thing that edits the scene; you never hand-edit JSON (that's the `0.754` grind
Phase 1 left in place). It runs alongside the Phase 1 preview: Designer writes
`scene.json` → preview hot-reloads → you watch/scrub.

Guiding principle (unchanged): **a value is shown as what it does.** A tween is
its curve, an LFO its waveform, an envelope its shape, a scalar a knob with an
arc — never a bare number.

## Architecture

- **Separate Godot project** at `designer/` (`project.godot`, `main.gd`,
  `main.tscn`), with `core -> ../common/core` symlinked exactly like the models.
  It reuses the framework directly:
  - `param_schema.gd` — destination types + ranges.
  - `mod_sources.gd` — **draws the editor previews from the same functions the
    engine runs**, so the curve you shape is exactly the curve you get (zero
    drift — the reason both halves are Godot).
  - `preset_io.gd` — load/save the scene file.
- **Two inputs:** the **scene file** (a model preset, e.g.
  `radial_burst/presets/pulsar.json`) and the model's **schema** (its params +
  macros, so the Designer knows the legal modulation destinations and their
  `[min,max]` ranges).
- **One output:** it writes the scene file (via `preset_io.save_preset`), which
  the Phase 1 preview hot-reloads. The file is the bus; the two processes stay
  decoupled — no IPC.

### Schema access (open decision — leaning A)

The Designer needs the target model's schema. Options:
- **A (recommended): export to JSON.** A helper `common/core/export_schema.gd`
  run as `godot --headless --path <model> --script res://core/export_schema.gd --
  <out>` instantiates the model script, calls `get_schema()`, and writes it to
  `<model>/schema.json`. The Designer reads that. Keeps the Designer a clean
  consumer of two JSON files — fully decoupled from model code, trivially
  testable. Cost: re-run the one-line export when a model's schema changes.
- **B: instantiate the model script in-Designer.** Requires the model scripts to
  live in the Designer's `res://` tree (symlinks); cross-project script loading
  is fragile. Rejected unless review prefers it.

## Core UX components (reusable `Control` widgets under `designer/widgets/`)

1. **Knob** — Ableton-style rotary: vertical-drag to change, value arc + label,
   value shown on grab, fine-control on `Shift`, double-click resets to default.
   Maps a scalar within `[min,max]`. The atomic control (replaces every slider).
2. **CurveEditor** (tween) — a live curve drawn via `mod_sources.tween` over the
   duration; a curve-type picker (`linear|ease_in|ease_out|smooth`) and knobs for
   `secs`, `from`, `to`. (v1: pick + knobs with a live preview; dragging the curve
   handles directly is 2c.)
3. **LFOEditor** — a shape picker (`sine|triangle|drift`), a `rate` knob, and a
   live waveform preview via `mod_sources.lfo`.
4. **EnvEditor** — `attack`/`decay`/`peak` knobs and a live shape preview via
   `mod_sources.envelope`, plus the trigger-event picker (e.g. `burst`).
5. **SourceCard** — wraps one source: its type editor + a **routing list** (each
   routing = a destination dropdown over the schema's macros+params, an amount
   knob, and a remove button) + an add-routing button + a remove-source button.
6. **BasesPanel** — knobs for the superparam (macro) bases and the key param
   overrides (palette/source_count/etc.), read from the schema.

Every edit mutates the in-memory scene and writes `scene.json` (debounced ~150ms),
so the preview hot-reloads continuously.

## Layout (sketch — open to your mockups)

```
┌─ DESIGNER · radial_burst · pulsar.json ──────────── seed 204 · 300s · ●writes ─┐
│ BASES   (energy) (density) (symmetry) (grit) (coupling)   [param overrides…]    │
├─ SOURCES ─────────────────────────────────────────  [+ LFO] [+ Tween] [+ Env] ─┤
│ ┌ TWEEN "build" ──────────────┐ ┌ LFO "grit_wobble" ─┐ ┌ ENV "flash" ────────┐ │
│ │  ╱──  curve: linear ▾       │ │  ∿∿  shape: drift ▾ │ │  ◢╲  on: burst ▾    │ │
│ │ (secs)(from)(to)            │ │ (rate)              │ │ (atk)(dec)(peak)    │ │
│ │ → energy      (amt) ✕       │ │ → grit   (amt) ✕    │ │ → glow   (amt) ✕    │ │
│ │ → density     (amt) ✕       │ │ [+ route]           │ │ [+ route]           │ │
│ │ → loop_period (amt) ✕  [+]  │ └─────────────────────┘ └─────────────────────┘ │
│ └─────────────────────────────┘                                                 │
└─────────────────────────────────────────────────────────────────────────────── ┘
```

`( )` = a knob. The render itself + scrub timeline live in the Phase 1 preview
window running beside the Designer; the Designer shows each source's *shape*.

## Decomposition (sub-phases — each its own plan)

Phase 2 is large, so build it in cycles, each independently useful:

- **2a — Widgets + edit an existing scene** *(first cycle, specced in detail
  here).* The Knob, CurveEditor, LFOEditor, EnvEditor widgets; load a
  scene + schema; edit the **existing** sources' params, the bases, and routing
  **amounts**; write `scene.json` on change. No add/remove of sources/routings
  yet; no drag-handle curve editing. This alone ends hand-editing JSON to tune
  pulsar.
- **2b — Compose scenes.** Add/remove sources; add/remove routings; destination
  dropdowns over the full schema; new-scene / save-as / scene picker.
- **2c — Direct manipulation + MIDI.** Drag curve/envelope handles directly;
  **MIDI CC** input mapping hardware knobs to scene params.

## Verification

- The pure math in each widget is unit-tested (knob value↔angle mapping; the
  preview samplers reuse the already-tested `mod_sources`).
- Scene round-trip is tested via `preset_io` (load → mutate → save → reload equals).
- The schema export helper is tested (run on radial_burst → JSON has the expected
  params/macros).
- The GUI itself is verified by running the Designer (xvfb screenshot + your
  review), and by the integration loop: Designer writes `scene.json` → the Phase 1
  preview hot-reloads (manual).
- This is a GUI tool — like the rest of vxstory, look/feel is your visual review;
  automated checks cover the logic and the file contract.

## Open questions for your review

1. **Schema access:** JSON-export helper (A, recommended) vs instantiate-in-Designer (B)?
2. **2a scope:** edit-existing-scene only (no add/remove sources yet) as the first
   cycle — acceptable, or do you want add/remove in the first cut?
3. **Designer shows source *shapes* only**, with the render+scrub staying in the
   Phase 1 preview window — or should the Designer also embed a live render/scrub?
4. **Knob conventions:** vertical-drag + Shift-fine + double-click-reset — match
   your Ableton muscle memory, or different?
5. **Layout:** want me to mock the layout up visually (browser companion) before
   we lock it, or is the sketch enough to plan from?

## Out of scope (Phase 2)

- The Phase 1 preview (done).
- Anything in 2b/2c until those cycles (add/remove, drag-handles, MIDI).
- Multi-model scene composition in one window (Designer targets one model+scene at
  a time).
