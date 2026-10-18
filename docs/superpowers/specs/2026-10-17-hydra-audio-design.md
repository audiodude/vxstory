# hydra audio reactivity — design spec

**Date:** 2026-10-17 · **Status:** approved (build without further checkpoints) · **Branch:** `hydra-audio` · **Builds on:** `2026-10-17-hydra-model-design.md`

## Goal

Let hydra sketches react to a song, rendered offline and deterministically, so a later radio change can render one video per song and line it up with that song on air. This work covers the engine (analysis, sketch API, renderer, preview) and one demo sketch (`cells`). The other four sketches stay silent-only for now. Per-song rendering in radio (render cache, `plan.py` changes) is a separate piece of work.

## Why not Hydra's own audio

Hydra's `a` object (`a.fft`, `a.setBins`, …) listens to a live microphone through Meyda, in wall-clock time. An offline render steps time exactly 1/60 s per frame, much faster or slower than real time, so live analysis can't line up with it. Instead the song is analysed once in Node before rendering, into one feature row per video frame, and the page reads row k on frame k. Hydra is still constructed with `detectAudio: false`; the runtime installs its own `a`.

## Decode

`lib/audio.mjs` decodes with ffmpeg to 44.1 kHz stereo float PCM, the same rate and channel layout `radio/scripts/bake/assemble.py` uses for the aired audio, then mixes down to mono for analysis. The song's duration is its decoded sample count / 44100.

## Features (one row per frame, at time k/60)

| Feature | Meaning |
|---|---|
| `a.fft[0..3]` | Band energy, 0..1: bass 20–150 Hz, low-mid 150–600 Hz, high-mid 600–2500 Hz, treble 2.5–11 kHz. |
| `a.level` | Overall loudness (window RMS), 0..1. |
| `a.beat` | Onset pulse: 1 on the frame of a detected onset, decaying exponentially (τ = 0.12 s). |
| `a.loudness` | The song's integrated loudness in LUFS (ffmpeg `ebur128`), one number for the whole song. |
| `a.active` | `true` when rendering with audio. |

- **Analysis windows** are centred on the frame time, so the visuals don't lag the sound. Bands and level use a 2048-sample Hann window (21.5 Hz bins). Onsets use spectral flux on a finer grid (1024-sample window, 256-sample hop, ~5.8 ms), then snap to the nearest frame, so an onset lands within one frame of the transient.
- **Per-song normalization in feature space, not audio:** each band and the level are measured in dB, then mapped so the song's own 5th–95th percentiles become 0..1 (clamped). Frames more than 60 dB below the song's loudest frame (silence, padding) are left out of the percentiles. Every song then uses the full visual range regardless of mastering or tonal balance. Because a constant gain only shifts dB values, a gain-only loudness normalization upstream (radio's sync, done separately) doesn't change any per-frame feature, only `a.loudness`. Sketches that want quiet songs to look calmer read `a.loudness`.
- **Smoothing:** after normalization, bands and level go through a one-pole follower with a fast attack (τ = 20 ms) and slower release (τ = 150 ms), like Hydra's own `a.setSmooth`, but deterministic.
- **Silence** (or a constant signal) yields zeros, never NaN.
- Analysis is pure arithmetic on the decoded samples, so features are bit-identical across runs on any machine. Rendering keeps the determinism the base spec describes.

## Sketch API

- `a.fft`, `a.level`, `a.beat`, `a.loudness`, `a.active` are globals. Read them inside parameter functions, e.g. `osc(() => 10 + 30 * a.fft[0])`, so they update every frame.
- Without audio (catalog pieces, preview with no song) every feature reads 0 and `a.active` is `false`, so an audio-aware sketch still renders as a silent piece. Sketches should look complete with the features at 0.
- Hydra's live-audio controls (`a.setBins`, `a.setSmooth`, `a.setCutoff`, `a.setScale`, `a.show`, `a.hide`) throw a clear error: the band layout and smoothing are fixed offline.
- Past the end of the song (`--duration` longer than the song), features read 0, like silence.

## Renderer

```
node render.mjs --preset P --out F [--audio song.mp3] [--duration S] …
```

- With `--audio`, the piece is the song: `dur` becomes the song's duration (arcs written as fractions of `dur` stretch to fit), and the frame count defaults to `round(song duration × 60)`. `--duration` still only shortens the render for proofs, without changing `dur`.
- Features are computed before Chromium starts and served to the render page as JSON (rounded to 5 decimals).
- `.mp4` output with `--audio` muxes the song (AAC 192k), padded or trimmed to the video length, for grading. `.avi` (radio's intermediate) stays video-only; radio muxes its own normalized audio.
- Decode or analysis failure exits non-zero before rendering, with no output.

## Preview

- `node preview.mjs [port] [--audio-dir DIR]` (`npm run preview -- --audio-dir DIR`). The UI gets a song picker listing the dir's audio files, plus `?audio=<file name>` in the URL.
- With a song, `dur` is the song's duration, the page plays the song through an `<audio>` element, and the frame clock follows the audio clock: each animation frame steps exact 1/60 s frames until the sketch time reaches `audio.currentTime`. Seeking (`t=`) fast-forwards frames as before, then seeks the audio. Speed sets `playbackRate`. Space pauses both. If the browser blocks autoplay, the page shows "click to play".
- The server computes features with the same `lib/audio.mjs`, caches them per file and mtime, and serves the audio with HTTP range support so seeking works.

## Demo sketch

`cells` reacts while keeping its arc: bass swells cell density and the feedback smear, the beat kicks contrast and band rotation, and treble lifts the warp. With no audio it renders exactly as before (its 300 s silent arc is unchanged at features = 0).

## Tests

- **Analysis (pure, synthetic PCM, no ffmpeg):** a sine in each band drives that band highest; a click track yields `beat = 1` within one frame of each click and nowhere else; the same signal at −20 dB produces identical features (normalization is gain-invariant); silence gives all zeros with no NaN; row count is `floor(duration × 60) + 1`.
- **Render (GPU):** a click-track WAV through a sketch that paints `a.beat` red flashes on the expected frames (±1); `--audio` without `--duration` renders exactly the song's length; `.mp4` with `--audio` has an audio stream as long as the video; a sketch reading `a.fft` renders without `--audio`; calling `a.setBins` fails the render.

## Out of scope

- Radio per-song rendering: render cache, manifest, `plan.py`/`assemble.py` changes.
- Audio reactivity for `weave`, `glass`, `chrome`, `fold`.
- Beat tracking / tempo (`a.beat` is onsets, not a metrical grid), stems, pitch/chroma.
- Loudness normalization of the station's audio (a separate radio change, in progress).
