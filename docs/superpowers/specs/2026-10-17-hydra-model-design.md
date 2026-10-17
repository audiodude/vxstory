# hydra — design spec

**Date:** 2026-10-17 · **Status:** draft, awaiting approval · **Branch:** `hydra-model`

## Goal

Add [Hydra](https://hydra.ojack.xyz/) as a vxstory model. The sketches run on the real `hydra-synth` library and are written from scratch for this project. Rendering is deterministic and offline. Each render produces a 1080p60 mp4, which the radio catalog pipeline (`../radio.dangerthirdrail.com/scripts/render/`) uses just like a Godot piece.

Decisions already made:

| Question | Decision |
|---|---|
| Engine | Real `hydra-synth` (npm) in headless Chromium via Playwright, stepping one frame at a time. Not ported to Godot. |
| Sketches | Written from scratch. No community sketches, so there are no third-party licenses to check. |
| License | `hydra-synth` is AGPL-3.0. It is an npm dependency only and is never committed (no `node_modules/`, no bundled copy). The README says so. vxstory's own code stays MIT. |

## Feasibility (spike, 2026-10-17, this machine)

These numbers come from throwaway scripts in `/tmp/hydra-spike`, using hydra-synth 1.4.0, Playwright 1.64.1 and chrome-headless-shell 156:

- **GPU works headless.** No xvfb needed. Chromium flags `--use-angle=vulkan --enable-gpu --ignore-gpu-blocklist --enable-features=Vulkan`. The renderer reports `ANGLE (NVIDIA, Vulkan … RTX 3080 Ti)`.
- **Frame stepping works.** Construct with `autoLoop: false, detectAudio: false, enableStreamCapture: false, precision: 'highp'`, then call `h.tick(1000/60)` once per frame. `tick` advances `time += dt/1000 * speed`, so time is exact and unaffected by wall-clock time.
- **Deterministic.** The same sketch rendered twice gives the same SHA-256 over all 120 raw frames. The hash also matched across two different transfer paths (base64 over CDP, and WebSocket).
- **Readback must happen in the same task as `tick`.** hydra-synth creates regl without `preserveDrawingBuffer`, so any `await` between `tick()` and `readPixels()` risks reading a frame that has already been presented. Frame loop: wait for backpressure, then `tick`, then `readPixels` synchronously, then send.
- **Throughput depends on how frames leave the page.**

  | Transfer | 1080p | 720p |
  |---|---|---|
  | base64 string via `page.evaluate` | 4.8 fps | — |
  | `fetch` POST per frame | 2.8 fps | 6.3 fps |
  | **binary WebSocket, 3 frames in flight** | **11.0 fps** | **24.2 fps** |

  In-page, the GPU renders and reads back at ~346 fps at 1080p, so moving frames out of the page is the bottleneck, not rendering. Using the WebSocket path, a 300 s piece at 1080p takes ~27 min (~5.5× realtime). Godot renders run ~3× realtime per the radio README. This spec accepts that cost. If it later matters, the next step is converting RGBA to I420 on the GPU before readback (2.7× fewer bytes). That is not part of this work.

## Layout

```
hydra/
  package.json        # deps: hydra-synth, playwright, ws; "test": "node --test"
  package-lock.json   # committed
  render.mjs          # CLI: render a preset to a video file (built)
  preview.mjs         # live preview server (exists)
  preview.html        # preview UI: sketch/seed/speed/start-at controls (exists)
  lib/runtime.js      # in-page: seeded rand, arc helpers, at() (exists); shared by preview and render
  sketches/<name>.js  # Hydra code: one original sketch per file
  presets/<name>.json # {model, sketch, seed, duration_sec}
  test/*.test.mjs
  README.md           # per-model doc: sketches, presets, helpers, setup, AGPL note
```

`hydra/node_modules/` goes in `.gitignore`. `hydra/` is not a Godot project and does not symlink `common/core/`. Godot's SimModel, ModStack and Designer do not apply here.

## Preset format

```json
{"model": "hydra", "sketch": "tunnel", "seed": 4242, "duration_sec": 300.0}
```

The preset needs a top-level `seed` because radio's `render_piece.sh` replaces it with `jq '.seed = $seed'`. `sketch` names a file in `sketches/`. That lets a later variation preset reuse a sketch without changing code.

## Sketch runtime (`lib/runtime.js`)

A sketch is plain Hydra code that runs once at startup, with these globals available in addition to Hydra's:

| Global | Meaning |
|---|---|
| `seed` | The preset seed. |
| `rand()` | Seeded PRNG (mulberry32 of `seed`). `Math.random` is replaced with it before the sketch runs, so Hydra internals and sketch code both draw from the seed. |
| `dur` | `duration_sec`. |
| `prog()` | `time / dur`, clamped 0..1. |
| `ramp(t0, t1, a, b, curve='smooth')` | Value from `a` to `b` over seconds `t0..t1`, holding at each end. Curves match vxstory's: `linear`, `ease_in`, `ease_out`, `smooth`. |
| `lfo(period_sec, phase_deg=0)` | Sine wave, -1..1. |
| `at(t_sec, fn)` | Calls `fn` on the first frame where `time >= t_sec`. Used for section changes (re-patching `.out()` chains). |

All helpers are pure functions of `time`, apart from `at`, which fires on an exact frame. Sketches pass helpers into Hydra as function arguments, e.g. `osc(() => ramp(0, 120, 4, 40))`. Sketches must not read the wall clock (`Date`, `performance.now`) or use audio (`a.fft`). The output is silent, like every other model.

Seeds make variation: each sketch derives its palette offsets, symmetry counts and so on from `rand()`. Two seeds of the same preset should look like the same piece in different colors and arrangements. Radio relies on this when it renders one preset under several seeds.

## Renderer (`render.mjs`)

```
node hydra/render.mjs --preset <path.json> --out <file.mp4|file.avi> [--duration S] [--res 1920x1080]
node hydra/preview.mjs [port]   # already built: http://127.0.0.1:8642/
```

- A local HTTP server serves a render page (sharing `lib/runtime.js` with the preview), the hydra-synth dist file and the sketch. Frames come back over a binary WebSocket with a 3-frame in-flight window. The page waits for acks, so ffmpeg backpressure reaches the page.
- `--duration` overrides `duration_sec`, so frames = `round(duration × 60)`. Default resolution is 1920×1080, matching the Godot models.
- ffmpeg reads raw RGBA and applies `vflip` (`readPixels` returns rows bottom-up). The file extension picks the codec:
  - `.mp4`: libx264 CRF 18, yuv420p, for `renders/`.
  - `.avi`: MJPEG at high quality, the same intermediate Godot Movie Maker writes, so radio's existing encode step consumes it unchanged.
- Writes go to `<out>.tmp` and are renamed into place only when the render succeeds.
- **Fails loudly.** It exits non-zero if:
  - the page logs any error, or Hydra's `Error during tick()` / shader-compile warnings appear. Hydra otherwise keeps rendering black frames.
  - the WebGL renderer string is SwiftShader or llvmpipe. That would be silently ~100× slower and give different output. `--allow-software` opts in.
  - ffmpeg exits non-zero.
- The page `render.mjs` serves loads the same `lib/runtime.js` as the preview, so a sketch looks the same in both. Preview fast-forwards in exact 1/60 s steps, so "start at" matches the render frame-for-frame.

## Integration

**vxstory**
- `scripts/render.sh`: if `$ROOT/$MODEL/render.mjs` exists, run `node "$ROOT/$MODEL/render.mjs" --preset … --out renders/<model>_<preset>.mp4 [--duration]` instead of Godot. The output name and location are unchanged.
- `scripts/render-batch.sh`: add one Hydra long-form preset (e.g. `hydra:tunnel`) to `SET`.
- Root `README.md`: add a model table row, a short "Hydra" section (setup: `cd hydra && npm ci && npx playwright install chromium-headless-shell`, Node ≥ 20 via asdf) and the AGPL note. Change "Seven … models in Godot 4.6" to say what's actually true.

**radio.dangerthirdrail.com** (separate commit in that repo)
- `scripts/render/render_piece.sh`: if `$MODEL_DIR/render.mjs` exists, replace the `xvfb-run godot … --write-movie "$TMP_AVI"` call with `node "$MODEL_DIR/render.mjs" --preset "$TMP_PRESET" --duration "$DURATION" --out "$TMP_AVI"`. The 720p lanczos encode, sidecar, manifest and upload steps stay the same, and the sidecar's `model` is `hydra`.
- README "Video catalog" section: mention Hydra presets and the Node setup.
- Adding Hydra pieces to a catalog spec (`scripts/render/specs/*.json`) and uploading them are separate decisions, made after you approve the renders.

## Sketches (originals, 300 s long-form each)

Six sketches, picked by you from a live-preview round on 2026-10-17. A first batch of four quieter sketches (`tunnel`, `moire`, `bloom`, `signal`) was rejected as boring. Drafts of all six exist in `hydra/sketches/` and show the look only. Each still needs a 300 s arc (an opening, an escalation, a peak, a cooldown) built from `ramp`/`lfo`/`at`, which must not dull the look you picked.

| Sketch | Look (draft) | Arc lever |
|---|---|---|
| `cells` | Saturated kaleidoscope: voronoi tiles XORed with rotating colour bands, smeared by feedback. | Kaleidoscope segment count and cell density step up through `at()` sections; feedback blend grows into the peak. |
| `weave` | Op-art rainbow threads crossed with a slow wave lattice. | Thread frequency and lattice warp; colour narrows to a few hues at the start and end. |
| `glass` | Neon tiled shapes refracted through pixelated noise, on black. | Refraction strength and tile count; trails lengthen into the peak. |
| `marble` | Stripe islands advected through a feedback field: ink marbling. | Advection speed and how much new ink is injected; the cooldown lets the field still and drain. |
| `chrome` | Black-and-mint liquid-metal ribbons folded through themselves. | Fold depth (`modulateRotate`) and ribbon frequency; a brief colour bloom at the peak. |
| `fold` | Fat posterized colour bands torn by a pixelated noise field: a datamoshed sunset. | Tear amount and pixelation; snaps clean at the end. |

Dropped from the second batch: `plasma`, `vortex`.

One preset per sketch, named after it (drafts exist with placeholder seeds). The implementer checks structure (tests, extracted frames). Aesthetic grading is yours, done in the live preview and then from 60 s proof renders and full 300 s renders, per house convention 7 in the ring_rush spec.

## Tests (`hydra/test/`, `npm test`)

Tests that would catch real bugs:
- **Determinism:** rendering a fixture sketch for 30 frames at 320×180 twice with the same seed gives identical raw-frame hashes. A different seed gives a different hash.
- **Fail-loud:** a sketch with a GLSL error, or one that throws, makes `render.mjs` exit non-zero and leaves no output file.
- **Arc helpers:** `ramp` holds at both ends and hits its midpoint correctly for each curve. `at()` fires exactly on frame `ceil(t × 60)` and only once.
- **Frame count:** a `--duration 2` render has exactly 120 frames (ffprobe).

## Out of scope

- Audio-reactive sketches (`a.fft`) and syncing to the station's music.
- Community or gallery sketches.
- GPU-side I420 packing and other speed work beyond the WebSocket path.
- Hydra's interactive editor and tweak-panel/Designer integration (Godot only).
- Adding Hydra pieces to the live radio catalog.
