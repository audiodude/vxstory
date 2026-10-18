# hydra

Original [Hydra](https://hydra.ojack.xyz/) sketches, rendered offline to the same 1080p60 mp4 as the Godot models. This is a Node project, not a Godot one: the real `hydra-synth` runs in headless Chromium, stepped exactly 1/60 s per frame, and the frames stream into ffmpeg. Sketches can also react to a song (see [Audio](#audio)). Design: `docs/superpowers/specs/2026-10-17-hydra-model-design.md` and `…-hydra-audio-design.md`.

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
npm run preview -- --audio-dir ~/music   # adds a song picker
```

Pick a sketch and seed (🎲 for a random one), a speed (1×/2×/5×/10×: a 300 s arc fits in a minute at 5×) and a start time. Keys: space pauses, `h` hides the controls, `r` reloads (it picks up sketch edits). The bar and clock show where you are in the arc. Sketch errors show in red, and a contract break stops playback.

The preview steps the same way as the renderer, and seeking fast-forwards frame by frame, so a frame at any time matches the render on the same machine. The URL holds the view: `?sketch=cells&seed=42&speed=5&t=120`. Add `&paused=1` to stop right after seeking, for inspecting frames or scripting screenshots.

With `--audio-dir`, pick a song (`&audio=<file name>`): the song plays, the sketch's clock follows the audio clock in exact 1/60 s steps, and the piece lasts as long as the song. Speed sets the playback rate. If the browser blocks autoplay, the status line says "click to play".

## Render

```
node render.mjs --preset presets/cells.json --out cells.mp4 [--duration 60]
node render.mjs --preset presets/cells.json --audio song.mp3 --out cells_song.mp4
scripts/render.sh hydra cells 60          # from the repo root: renders/hydra_cells.mp4
```

| Option | Meaning |
|---|---|
| `--preset P` | Preset JSON (required). |
| `--out F` | `.mp4` (libx264 CRF 18) or `.avi` (MJPEG intermediate, used by radio). |
| `--audio A` | React to this song. The piece becomes the song: `dur` and the default length are the song's. An `.mp4` also carries the song; an `.avi` stays silent. |
| `--duration S` | Render only the first S seconds. `dur` doesn't change, so a 60 s proof is exactly the first minute of the full piece. |
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
| `dur` | The preset's `duration_sec`, or the song's length when rendering with audio. |
| `prog()` | `time / dur`, clamped 0..1. |
| `ramp(t0, t1, a, b, curve='smooth')` | `a` → `b` over seconds `t0..t1`, holding at both ends. Curves: `linear`, `ease_in`, `ease_out`, `smooth`. |
| `lfo(period_sec, phase_deg=0)` | Sine wave, -1..1. |
| `at(t_sec, fn)` | Runs `fn` once, just before the first frame at or after `t_sec` (e.g. to re-patch the `.out()` chain). |

Pass helpers as functions so Hydra re-evaluates them every frame: `osc(() => ramp(0, dur * 0.4, 4, 40))`. Write times as fractions of `dur`. Frame k renders at `time = k/60`.

Rules:
- Don't set `speed` or `fps`. The render clock is fixed at 1/60 s per frame, and the runtime throws if either changes.
- Don't read the wall clock (`Date`, `performance.now`). Use `a` for audio, not the microphone.
- Use `rand()` for at least one structural value (a count, frequency, layout or timing), not just the hue.
- Integer-valued inputs (kaleid sides, repeat counts, pixelate cells) look broken when fractional: step them with `at()` or `Math.round`.

Hydra hides most mistakes: a parameter function that throws silently falls back to a default, and a GLSL error draws black. The shared runtime (`lib/runtime.js`) turns all of these into errors, which show in red in the preview and fail a render.

## Audio

Hydra's own `a` listens to a live microphone in real time, which can't line up with an offline render. Instead `lib/audio.mjs` analyses the song once with ffmpeg (44.1 kHz, the rate radio airs it at) into one row of features per frame, and the runtime installs its own `a`:

| Global | Meaning |
|---|---|
| `a.fft[0..3]` | Band energy, 0..1: bass 20–150 Hz, low-mid 150–600 Hz, high-mid 600–2500 Hz, treble 2.5–11 kHz. |
| `a.level` | Overall loudness, 0..1. |
| `a.beat` | 1 on an onset frame (kicks, snares, stabs; ~120–250/min on busy tracks), decaying with τ = 0.12 s. |
| `a.loudness` | The song's integrated loudness in LUFS (−70 without audio). |
| `a.active` | `true` when rendering with a song. |

- Read features inside parameter functions so they update every frame: `osc(() => 10 + 30 * a.fft[0])`.
- Bands and level are normalized per song: its own 5th–95th percentile (in dB) maps to 0..1, so every song uses the full range whatever its mastering. That also makes them immune to upstream volume changes. Read `a.loudness` if a quiet song should look calmer.
- Analysis windows are centred on each frame, so visuals don't lag the sound; onsets land within one frame of the transient.
- Without a song every feature reads 0, so an audio-aware sketch must still look complete at 0. That keeps it usable as a silent catalog piece.
- Hydra's live-audio controls (`a.setBins`, `a.setSmooth`, `a.show`, …) throw: bands and smoothing are fixed offline.

`cells` is the demo: bass swells cell density and the feedback smear, the beat kicks contrast and jolts the bands, and treble lifts the warp. Its silent render is unchanged.

## Tests

```
npm test        # ~20 s; needs the GPU and ffmpeg
```

Covers the arc helpers and `at()` timing, audio analysis (bands, onsets, gain invariance, silence), beat-synced renders against a click track, determinism across seeds, `--duration` not stretching the arc, frame counts, orientation, every fail-loud path, and SIGTERM cleanup.

## License

`hydra-synth` is AGPL-3.0. It is installed from npm into `node_modules/` (gitignored) and is never committed or bundled here. The code in this directory is MIT, like the rest of vxstory.
