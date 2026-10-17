# hydra — design spec

**Date:** 2026-10-17 · **Status:** implemented (revised after adversarial review, 2026-10-17); sketches await your aesthetic grading · **Branch:** `hydra-model`

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
- **Frame stepping works.** Construct with `autoLoop: false, detectAudio: false, enableStreamCapture: false, precision: 'highp'`, then call `h.tick(1000/60)` once per frame. `tick` advances `time += dt/1000 * speed`, so time is exact and unaffected by wall-clock time, as long as `speed` stays 1 (the runtime enforces that; see below). 18,000 ticks drift by 5.6e-11 s.
- **Repeatable, not portable.** The same sketch rendered twice gives the same SHA-256 over all 120 raw frames, across two different transfer paths (base64 over CDP, and WebSocket). That holds for the same GPU, driver and Chromium build. Feedback sketches amplify tiny floating-point differences, so another GPU, driver, ANGLE backend or browser (including a desktop browser running the preview) can drift.
- **Readback.** hydra-synth creates regl without `preserveDrawingBuffer`, so an `await` between `tick()` and `readPixels()` could read a buffer that has already been presented and cleared. The shared boot code creates the canvas's WebGL context first, with `preserveDrawingBuffer: true`, and regl reuses it. The frame loop still ticks and reads back in the same task.
- **Throughput depends on how frames leave the page.**

  | Transfer | 1080p | 720p |
  |---|---|---|
  | base64 string via `page.evaluate` | 4.8 fps | — |
  | `fetch` POST per frame | 2.8 fps | 6.3 fps |
  | **binary WebSocket, 3 frames in flight** | **11.0 fps** | **24.2 fps** |

  In-page, the GPU renders and reads back at ~346 fps at 1080p, so moving frames out of the page is the bottleneck, not rendering. Using the WebSocket path, a 300 s piece at 1080p takes ~27 min (~5.5× realtime). Godot is about the same: back-to-back 300 s pieces in radio's `catalog_v2/catalog.json` finish ~29 min apart, encode included (radio's README says "~3× realtime", which is stale). If speed later matters, the next step is converting RGBA to I420 on the GPU before readback (2.7× fewer bytes). That is not part of this work.

## Layout

```
hydra/
  package.json        # exact deps: hydra-synth, playwright, ws; engines: node >= 24; scripts: "preview", "test": "node --test"
  package-lock.json   # committed
  render.mjs          # CLI: render a preset to a video file
  render.html         # render page: boots the sketch, streams frames back over a WebSocket
  preview.mjs         # live preview server (ships)
  preview.html        # preview UI: sketch/seed/speed/start-at controls (ships)
  lib/runtime.js      # in-page: startSketch() boot and error capture, seeded rand, arc helpers, at(); shared by preview and render
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

The preset needs a top-level `seed` because radio's `render_piece.sh` replaces it with `jq '.seed = $seed'`. `sketch` is required for the same reason: radio hands `render.mjs` a seed-substituted temp copy (`mktemp /tmp/preset_XXXXXX.json`), so the file name can't name the sketch. Convention: one preset per sketch, named after it. The preview reads a sketch's default seed and duration from `presets/<sketch>.json`. `render.mjs` rejects a preset whose `model` isn't `hydra`, whose `seed` isn't an integer, whose `duration_sec` isn't positive, or whose sketch file doesn't exist.

## Sketch runtime (`lib/runtime.js`)

A sketch is plain Hydra code that runs once at startup, with these globals available in addition to Hydra's:

| Global | Meaning |
|---|---|
| `seed` | The preset seed. |
| `rand()` | Seeded PRNG (mulberry32 of `seed`). `Math.random` is replaced with it before the sketch runs. hydra-synth itself never calls `Math.random`; the replacement makes any stray `Math.random` in sketch code seeded too. |
| `dur` | The preset's `duration_sec`. `--duration` never changes it (see Renderer). |
| `prog()` | `time / dur`, clamped 0..1. |
| `ramp(t0, t1, a, b, curve='smooth')` | Value from `a` to `b` over seconds `t0..t1`, holding at each end. Curves match vxstory's: `linear`, `ease_in`, `ease_out`, `smooth`. Throws on an unknown curve, `t1 <= t0`, or a non-finite `a`/`b`. |
| `lfo(period_sec, phase_deg=0)` | Sine wave, -1..1. Throws if `period_sec <= 0`. |
| `at(t_sec, fn)` | Calls `fn` once, just before the first frame whose time reaches `t_sec`. Used for section changes (re-patching `.out()` chains). |

All helpers are pure functions of `time`, apart from `at`. Sketches pass helpers into Hydra as function arguments, e.g. `osc(() => ramp(0, dur * 0.4, 4, 40))`. Write arc timing as fractions of `dur`, so an arc scales with the preset's length.

**Time.** Frame k (k = 1, 2, …) renders at `time = k/60`, so the first frame shows t = 1/60, not 0. `at(t)` fires before frame k for the smallest k with `k/60 ≥ t − 1e-9`, and `at(0)` fires before frame 1. A callback that registers another `at()` whose time has already passed fires it in the same step. The tolerance avoids float traps: `Math.ceil(8.3 * 60)` is 499, but 8.3 s is frame 498.

**Contract, enforced.** On every tick, Hydra copies the page globals `speed`, `fps`, `bpm`, `update` and `afterUpdate` into its state. A sketch that sets `speed` desyncs `time` from the frame count (with `speed = 2`, `prog()` reaches 1 at 150 s). One that sets `fps` makes Hydra skip draws, so readback returns repeated frames. `runtime.step` throws if `speed !== 1` or `fps` is set. It checks every frame, after `at()` callbacks and before `tick`. `bpm`, `update` and `afterUpdate` are allowed, since they run off the fixed `dt`. Sketches must not read the wall clock (`Date`, `performance.now`) or use audio (`a.fft`). That rule is not enforced. The output is silent, like every other model.

**Error capture (`startSketch`).** Hydra swallows most failures and keeps drawing:

| Failure | What Hydra does |
|---|---|
| Parameter function throws | `console.warn('ERROR', e)`, then uses the input's default value |
| Parameter function returns a non-number | `console.warn('function does not return a number', …)` |
| `update` / `afterUpdate` throws | `console.log(e)` |
| Anything else inside `tick` | `console.warn('Error during tick():', e)` |
| GLSL compile or link failure | Nothing. The regl bundled in hydra-synth never checks compile status, so the output draws black and only the browser logs `WebGL: INVALID_OPERATION: useProgram: program not valid` (found while building the fail-loud test). |

`startSketch` reports all of these through one `onError` callback. It reports every `console.warn` and `console.error` call, any `console.log` with an `Error` argument, uncaught errors and unhandled rejections, a throwing sketch body, and `webglcontextlost`. It also wraps the context's `compileShader` and `linkProgram` to check their status and report the GLSL info log. The renderer treats any report as fatal. The preview shows it in red. A NaN from a sketch's own arithmetic still passes silently (`typeof NaN === 'number'`); the helpers' argument checks cover the helper cases.

**Seeds make variation.** Each sketch derives palette offsets, symmetry counts and so on from `rand()`. Two seeds of the same preset should look like the same piece in different colors and arrangements. Radio relies on this when it renders one preset under several seeds. Acceptance: every sketch draws at least one structural value (a count, frequency, layout or section timing) from `rand()`, not just a hue offset. The implementer checks this with a two-seed contact sheet (the same times under two seeds).

## Renderer (`render.mjs`)

```
node hydra/render.mjs --preset <path.json> --out <file.mp4|file.avi> [--duration S] [--res 1920x1080]
                      [--sketch-dir DIR] [--stall-sec 60] [--allow-software]
```

- A local HTTP server on 127.0.0.1 (ephemeral port) serves `render.html`, the hydra-synth dist file, `lib/runtime.js` and the sketch. Frames come back over a binary WebSocket on the same port, with at most 3 frames in flight. `render.mjs` acks a frame once ffmpeg's stdin has taken it, so ffmpeg backpressure reaches the page.
- Frames = `round(duration × 60)`, where duration is `--duration` if given, else `duration_sec`. `dur` stays the preset's `duration_sec`, so a 60 s proof render is exactly the first 60 s of the full piece. Default resolution is 1920×1080, matching the Godot models and the preview.
- ffmpeg reads raw RGBA and applies `vflip` (`readPixels` returns rows bottom-up). It writes to `<out>.tmp`, so the muxer is named explicitly (`-f mp4` / `-f avi`). ffmpeg can't infer it from `.tmp`. The `--out` extension picks the codec, and any other extension is rejected:
  - `.mp4`: libx264 CRF 18, yuv420p, for `renders/`.
  - `.avi`: MJPEG `-q:v 2`, yuvj420p, the same kind of intermediate Godot Movie Maker writes, so radio's existing encode step consumes it unchanged. Radio downscales to 720p 4:2:0, so 4:2:0 chroma at 1080p loses nothing.
- `<out>.tmp` is renamed into place only when the render succeeds. On any failure, and on SIGINT/SIGTERM, `render.mjs` kills ffmpeg and Chromium and deletes `<out>.tmp`. Radio's cleanup trap only removes `$TMP_AVI`, not `$TMP_AVI.tmp`.
- **Fails loudly.** It exits non-zero and leaves no output if:
  - `startSketch` reports anything (see Error capture), or the page throws or crashes. Hydra otherwise keeps rendering default-valued, stale or black frames.
  - the browser logs a console error, or a warning starting with `WebGL:` (GL errors the page's hooks can't see). Other browser warnings are driver chatter: ANGLE logs `GPU stall due to ReadPixels` on every render.
  - `runtime.step` throws: a contract break, or a throwing `at()` callback.
  - the WebGL renderer string is SwiftShader or llvmpipe. That would be silently ~100× slower and give different output. `--allow-software` opts in.
  - no frame arrives for `--stall-sec` seconds (default 60), counting from launch. That catches hangs, such as an infinite loop in a sketch or a wedged GPU process.
  - the page delivers a frame count other than the one requested, or ffmpeg exits non-zero.
- It prints the WebGL renderer at start and a progress line (frame, fps, ETA) about every 10 s.
- `--sketch-dir` loads sketches from another directory (the tests' fixtures use it). The default is `hydra/sketches/`.

## Preview (`preview.mjs`, `preview.html`) — a shipped deliverable

```
cd hydra && npm run preview        # or: node preview.mjs [port]; default http://127.0.0.1:8642/
```

The live preview is part of the final output, not throwaway scaffolding. It is how sketches get written and graded, the Hydra equivalent of the Godot models' tweak panel and Designer. It stays in the repo, is documented, and is kept working as the renderer and runtime change.

- **Server:** a dependency-free Node HTTP server, bound to 127.0.0.1. It serves the page, the hydra-synth dist file, `lib/runtime.js` and `sketches/<name>.js`, with `no-store` caching, so editing a sketch and pressing `r` picks up the change. `/api/sketches` lists the sketches with their preset seed and duration.
- **UI:** pick sketch and seed, speed 1×/2×/5×/10× so a whole 300 s arc fits in a minute, and start-at seconds. 🎲 picks a random seed from `crypto.getRandomValues`, because once a sketch loads, `Math.random` is the seeded PRNG and would walk the same seeds every time. Keys: space pauses, `h` hides the controls, `r` restarts. A progress bar and clock show where you are in the arc. Everything `startSketch` reports (see Error capture) appears in red on the page, deduplicated. A contract break stops playback.
- **Fidelity:** it boots through the same `startSketch` as the renderer (same context, constructor flags and error capture) and uses the same frame stepping (exact 1/60 s steps through `runtime.step`). Start-at fast-forwards frame by frame, so feedback state at any time matches the render on the same GPU, driver and browser build (see Feasibility). Faster speeds take more steps per animation frame and never larger ones.
- **URL state:** `?sketch=&seed=&speed=&t=` makes a view shareable and reloadable. `&paused=1` starts paused after seeking (space resumes), for frame inspection or scripted contact sheets. It raises no error.
- **README:** the per-model `hydra/README.md` and the root README's Hydra section both document `npm run preview` and the controls.
- **Tests:** none of its own. It shares `lib/runtime.js` with the renderer, and that file's behaviour is tested there.

## Integration

**vxstory**
- `scripts/render.sh`: if `$ROOT/$MODEL/render.mjs` exists, run `node "$ROOT/$MODEL/render.mjs" --preset … --out renders/<model>_<preset>.mp4 [--duration]` instead of Godot. The output name and location are unchanged.
- `scripts/render-batch.sh`: add one Hydra long-form preset (`hydra:cells`) to `SET`.
- Root `README.md`: add a model table row, a short "Hydra" section (setup: `cd hydra && npm ci && npx playwright install chromium-headless-shell`, Node ≥ 24 via asdf) and the AGPL note. Change "Seven … models in Godot 4.6" to say what's actually true. Node 20 reached end of life in April 2026, so `package.json` declares `engines: {node: ">=24"}`.

**radio.dangerthirdrail.com** (separate commit in that repo)
- `scripts/render/render_piece.sh`: if `$MODEL_DIR/render.mjs` exists, replace the `xvfb-run godot … --write-movie "$TMP_AVI"` call with `node "$MODEL_DIR/render.mjs" --preset "$TMP_PRESET" --duration "$DURATION" --out "$TMP_AVI"`. The 720p lanczos encode, sidecar, manifest and upload steps stay the same, and the sidecar's `model` is `hydra`.
- README "Video catalog" section: mention Hydra presets and the Node setup, and correct "~3× realtime" to the observed ~6× (about 29 min per 300 s piece).
- Adding Hydra pieces to a catalog spec (`scripts/render/specs/*.json`) and uploading them are separate decisions, made after you approve the renders.

## Sketches (originals, 300 s long-form each)

Five sketches. You picked six from a live-preview round on 2026-10-17. A first batch of four quieter sketches (`tunnel`, `moire`, `bloom`, `signal`) was rejected as boring. Drafts of all six existed in `hydra/sketches/` and showed the look only. Each still needed a 300 s arc (an opening, an escalation, a peak, a cooldown) built from `ramp`/`lfo`/`at`, which must not dull the look you picked. Each also needed structural seed variation (see Seeds make variation): four of the drafts only seeded a hue offset.

| Sketch | Look (draft) | Arc lever |
|---|---|---|
| `cells` | Saturated kaleidoscope: voronoi tiles XORed with rotating colour bands, smeared by feedback. | Kaleidoscope segment count and cell density step up through `at()` sections; feedback blend grows into the peak. |
| `weave` | Op-art rainbow threads crossed with a slow wave lattice. | Thread frequency and lattice warp; colour narrows to a few hues at the start and end. |
| `glass` | Neon tiled shapes refracted through pixelated noise, on black. | Refraction strength and tile count; trails lengthen into the peak. |
| `chrome` | Black-and-mint liquid-metal ribbons folded through themselves. | Fold depth (`modulateRotate`) and ribbon frequency; a brief colour bloom at the peak. |
| `fold` | Fat posterized colour bands torn by a pixelated noise field: a datamoshed sunset. | Tear amount and pixelation; snaps clean at the end. |

Dropped from the second batch: `plasma`, `vortex`. Dropped after its arc was built: `marble` (stripe islands in a feedback field, ink marbling), which you judged too rough.

One preset per sketch, named after it (drafts exist with placeholder seeds). The implementer checks structure (tests, extracted frames, the two-seed contact sheet). Aesthetic grading is yours, done in the live preview and then from 60 s proof renders and full 300 s renders, per house convention 7 in the ring_rush spec.

## Tests (`hydra/test/`, `npm test`)

Tests that would catch real bugs:
- **Runtime** (Node `vm`, no browser): `ramp` holds at both ends, hits its midpoint correctly for each curve, and rejects bad arguments. `at(n/10)` fires before frame 6n for n = 1..600, which covers float traps like 8.3 s, and fires only once. `at(0)` fires before frame 1. `step` throws when `speed` or `fps` is set.
- **Determinism:** a fixture sketch rendered for 30 frames at 320×180 to `.avi` twice with the same seed gives identical decoded-frame hashes (`ffmpeg -f framemd5`). MJPEG is intra-only, so each frame's bytes depend only on that frame. A different seed gives different hashes.
- **Duration doesn't stretch the arc:** with a fixture whose look depends on `prog()` and a preset `duration_sec` of 4, the first 60 frames of a `--duration 1` render equal those of a `--duration 2` render.
- **Fail-loud:** each of these makes `render.mjs` exit non-zero and leaves neither the output nor `<out>.tmp`: a GLSL compile error (`setFunction`), a throwing sketch body, a throwing parameter function, helper misuse (unknown `ramp` curve), a throwing `update`, `speed = 2`, `fps = 30`, a lost context (`WEBGL_lose_context`), and a hang (`--stall-sec 2`).
- **Interrupt:** SIGTERM mid-render exits non-zero and leaves neither the output nor `<out>.tmp`.
- **Frame count:** a `--duration 2` render has exactly 120 frames (`ffprobe -count_frames`), for both `.mp4` and `.avi`.
- **Orientation:** a fixture that is red on the bottom half on screen comes out red on the bottom half of the video (guards the `vflip`).

## Out of scope

- Audio-reactive sketches (`a.fft`) and syncing to the station's music.
- Community or gallery sketches.
- GPU-side I420 packing and other speed work beyond the WebSocket path.
- Hydra's interactive code editor, and integration with the Godot tweak panel or Designer. The `hydra/` live preview is the tuning tool here.
- Adding Hydra pieces to the live radio catalog.
