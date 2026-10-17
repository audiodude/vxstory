# hydra

Original [Hydra](https://hydra.ojack.xyz/) sketches, rendered offline to the same 1080p60 mp4 as the Godot models. This is a Node project, not a Godot one: the real `hydra-synth` runs in headless Chromium, stepped exactly 1/60 s per frame, and the frames stream into ffmpeg. Design: `docs/superpowers/specs/2026-10-17-hydra-model-design.md`.

## Setup

```
cd hydra
npm ci
npx playwright install chromium-headless-shell
```

Needs Node ≥ 24 (asdf), ffmpeg on `PATH`, and a GPU. No display or xvfb needed.

## Preview

```
npm run preview          # or: node preview.mjs [port]; then open http://127.0.0.1:8642/
```

Pick a sketch and seed (🎲 for a random one), a speed (1×/2×/5×/10×: a 300 s arc fits in a minute at 5×) and a start time. Keys: space pauses, `h` hides the controls, `r` reloads (it picks up sketch edits). The bar and clock show where you are in the arc. Sketch errors show in red, and a contract break stops playback.

The preview steps the same way as the renderer, and seeking fast-forwards frame by frame, so a frame at any time matches the render on the same machine. The URL holds the view: `?sketch=cells&seed=42&speed=5&t=120`. Add `&paused=1` to stop right after seeking, for inspecting frames or scripting screenshots.

## Render

```
node render.mjs --preset presets/cells.json --out cells.mp4 [--duration 60]
scripts/render.sh hydra cells 60          # from the repo root: renders/hydra_cells.mp4
```

| Option | Meaning |
|---|---|
| `--preset P` | Preset JSON (required). |
| `--out F` | `.mp4` (libx264 CRF 18) or `.avi` (MJPEG intermediate, used by radio). |
| `--duration S` | Render only the first S seconds. The sketch's `dur` stays the preset's, so a 60 s proof is exactly the first minute of the full piece. |
| `--res WxH` | Default `1920x1080`. |
| `--sketch-dir D` | Load sketches from D instead of `sketches/`. |
| `--stall-sec N` | Abort if no frame arrives for N seconds (default 60). |
| `--allow-software` | Accept a software WebGL renderer (SwiftShader/llvmpipe): ~100× slower, and its output differs. |

Throughput is ~11 fps at 1080p on a 3080 Ti, so a 300 s piece takes ~27 min, about the same as a Godot render. The output is written to `<out>.tmp` and renamed into place only on success. Any sketch error (including ones Hydra itself swallows), a lost GPU context, a stall, ffmpeg failing or SIGINT/SIGTERM stops the render with a non-zero exit and no output file.

Renders are repeatable on the same GPU, driver and Playwright version. Feedback sketches amplify tiny float differences, so another machine or browser may drift.

## Sketches

Each sketch is a 300 s arc: opening, escalation, peak, cooldown. Its preset (`presets/<name>.json`) names it and sets the default seed. Another seed gives the same piece with different colours and structure.

| Sketch | Look | Arc | Seeded structure |
|---|---|---|---|
| `cells` | Saturated kaleidoscope: voronoi tiles XORed with rotating colour bands, smeared by feedback. | Kaleidoscope sides step up through four sections while cell density, warp, band spin and feedback build to a peak; it drops back to the opening sides for a slow coda. | Sides and step size, cell density, band frequency, spin directions, section times. |
| `weave` | Op-art rainbow threads crossed with a slow wave lattice. | Few-hued, sparse threads; thread density and lattice warp climb while colour opens to the full rainbow at the peak; then it relaxes and narrows again. | Thread angle and density, lattice frequency, warp direction, peak time. |
| `glass` | Neon tiled shapes refracted through pixelated noise, on black. | A sparse grid gains tiles, refraction and trail length into a held peak, then thins and clears. | Shape sides, grid size and growth, brick or straight layout, pebble size, drift. |
| `marble` | Stripe islands advected through a feedback field: ink marbling. | A combed bath starts drifting; advection and ink drops build, and a counter-rotating second ink joins for the peak; the cooldown stills the bath and drains it dark. | Stripe frequencies, bath comb, drop size and amount, flow direction, layout, second-ink timing. |
| `chrome` | Black-and-mint liquid-metal ribbons folded through themselves. | Wide, shallow folds deepen and tighten to a dense peak with a brief colour bloom, then relax and dim. | Ribbon frequency and drift, fold field and axis swing, symmetry count, bloom time. |
| `fold` | Fat posterized colour bands torn by a pixelated noise field: a datamoshed sunset. | Lightly torn bands; tearing and pixelation grow to a full mosaic, ease back, then snap to clean bands. | Band frequency, tilt and levels, tear axis, tear-block grid, snap time. |

## Presets

```json
{"model": "hydra", "sketch": "cells", "seed": 1137, "duration_sec": 300.0}
```

`sketch` is required: radio renders from a seed-substituted temp copy of the preset, so the file name can't identify the sketch. Convention: one preset per sketch, named after it.

## Writing a sketch

A sketch is plain Hydra code in `sketches/<name>.js`, run once at startup. On top of Hydra's globals it gets:

| Global | Meaning |
|---|---|
| `seed`, `rand()` | The preset seed and a PRNG seeded from it. `Math.random` is replaced by the same PRNG. |
| `dur` | The preset's `duration_sec`. |
| `prog()` | `time / dur`, clamped 0..1. |
| `ramp(t0, t1, a, b, curve='smooth')` | `a` → `b` over seconds `t0..t1`, holding at both ends. Curves: `linear`, `ease_in`, `ease_out`, `smooth`. |
| `lfo(period_sec, phase_deg=0)` | Sine wave, -1..1. |
| `at(t_sec, fn)` | Runs `fn` once, just before the first frame at or after `t_sec` (e.g. to re-patch the `.out()` chain). |

Pass helpers as functions so Hydra re-evaluates them every frame: `osc(() => ramp(0, dur * 0.4, 4, 40))`. Write times as fractions of `dur`. Frame k renders at `time = k/60`.

Rules:
- Don't set `speed` or `fps`. The render clock is fixed at 1/60 s per frame, and the runtime throws if either changes.
- Don't read the wall clock (`Date`, `performance.now`) or use audio (`a.fft`).
- Use `rand()` for at least one structural value (a count, frequency, layout or timing), not just the hue.
- Integer-valued inputs (kaleid sides, repeat counts, pixelate cells) look broken when fractional: step them with `at()` or `Math.round`.

Hydra hides most mistakes: a parameter function that throws silently falls back to a default, and a GLSL error draws black. The shared runtime (`lib/runtime.js`) turns all of these into errors, which show in red in the preview and fail a render.

## Tests

```
npm test        # ~15 s; needs the GPU and ffmpeg
```

Covers the arc helpers and `at()` timing, determinism across seeds, `--duration` not stretching the arc, frame counts, orientation, every fail-loud path, and SIGTERM cleanup.

## License

`hydra-synth` is AGPL-3.0. It is installed from npm into `node_modules/` (gitignored) and is never committed or bundled here. The code in this directory is MIT, like the rest of vxstory.
