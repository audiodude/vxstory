// Offline audio analysis for audio-reactive sketches (Node only; ffmpeg on PATH).
// One feature row per video frame at time k/60: four bands, level, beat. Bands and level are
// normalized per song in dB space (gain-invariant); beat is an onset pulse. See
// docs/superpowers/specs/2026-10-17-hydra-audio-design.md.
import { spawn } from 'node:child_process'

export const SAMPLE_RATE = 44100
export const FPS = 60
export const FEATURES = ['fft0', 'fft1', 'fft2', 'fft3', 'level', 'beat']
const BANDS = [[20, 150], [150, 600], [600, 2500], [2500, 11000]]
const BAND_N = 2048 // band/level window (21.5 Hz bins)
const ONSET_N = 1024 // onset window
const ONSET_HOP = 256 // ~5.8 ms onset grid
const ATTACK = 0.02, RELEASE = 0.15, BEAT_TAU = 0.12 // seconds
const SILENCE_DB = 60 // frames this far below the loudest are left out of the percentiles
// Onset picking, tuned on library tracks to ~120-250 onsets/min (roughly the eighth-note
// pulse of a busy track, fewer on sparse ones).
const FLUX_MAX_HZ = 4000 // onsets come from kicks/snares/stabs, not hi-hat shimmer
const MEAN_SEC = 0.3 // adaptive threshold window, each side
const MEAN_MUL = 1.4
const DELTA_FRAC = 0.1 // of the song's 99th-percentile flux
const MIN_GAP = 0.18 // seconds between onsets

function run(args) {
  return new Promise((resolve, reject) => {
    const p = spawn('ffmpeg', ['-hide_banner', '-nostdin', ...args], { stdio: ['ignore', 'pipe', 'pipe'] })
    const out = [], err = []
    p.stdout.on('data', (d) => out.push(d))
    p.stderr.on('data', (d) => err.push(d))
    p.on('error', reject)
    p.on('close', (code) => {
      const stderr = Buffer.concat(err).toString()
      code === 0 ? resolve({ stdout: Buffer.concat(out), stderr }) : reject(new Error(`ffmpeg exited ${code}: ${stderr.trim().slice(-500)}`))
    })
  })
}

// Mono float PCM at 44.1 kHz: the rate radio's assemble.py decodes the aired audio at.
export async function decodeAudio(path) {
  const { stdout } = await run(['-v', 'error', '-i', path, '-vn', '-ac', '1', '-ar', String(SAMPLE_RATE), '-f', 'f32le', '-'])
  const pcm = new Float32Array(stdout.buffer, stdout.byteOffset, stdout.length / 4)
  if (!pcm.length) throw new Error(`no audio decoded from ${path}`)
  return Float32Array.from(pcm) // own, aligned copy
}

// Integrated loudness (EBU R128) in LUFS.
export async function integratedLoudness(path) {
  const { stderr } = await run(['-v', 'info', '-nostats', '-i', path, '-vn', '-af', 'ebur128=framelog=quiet', '-f', 'null', '-'])
  const m = /Integrated loudness:\s*I:\s*(-?[\d.]+|-inf)\s*LUFS/.exec(stderr)
  if (!m) throw new Error(`no loudness reading for ${path}`)
  return m[1] === '-inf' ? -70 : Number(m[1])
}

// In-place radix-2 FFT on (re, im).
function makeFFT(n) {
  const levels = Math.log2(n)
  const rev = new Uint32Array(n)
  for (let i = 0; i < n; i++) {
    let r = 0
    for (let b = 0; b < levels; b++) r = (r << 1) | ((i >>> b) & 1)
    rev[i] = r
  }
  const cos = new Float64Array(n / 2), sin = new Float64Array(n / 2)
  for (let i = 0; i < n / 2; i++) { cos[i] = Math.cos((2 * Math.PI * i) / n); sin[i] = Math.sin((2 * Math.PI * i) / n) }
  const hann = new Float64Array(n)
  for (let i = 0; i < n; i++) hann[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / n)
  const re = new Float64Array(n), im = new Float64Array(n)
  // Power spectrum (bins 0..n/2) of the Hann-windowed window centred on sample `center`.
  function power(pcm, center, out) {
    const start = center - n / 2
    for (let i = 0; i < n; i++) {
      const j = start + i
      re[rev[i]] = j >= 0 && j < pcm.length ? pcm[j] * hann[i] : 0
      im[rev[i]] = 0
    }
    for (let size = 2; size <= n; size *= 2) {
      const half = size / 2, step = n / size
      for (let s = 0; s < n; s += size) {
        for (let k = 0; k < half; k++) {
          const c = cos[k * step], si = -sin[k * step]
          const a = s + k, b = a + half
          const tr = re[b] * c - im[b] * si, ti = re[b] * si + im[b] * c
          re[b] = re[a] - tr; im[b] = im[a] - ti
          re[a] += tr; im[a] += ti
        }
      }
    }
    for (let k = 0; k <= n / 2; k++) out[k] = re[k] * re[k] + im[k] * im[k]
    return out
  }
  return power
}

// The floor only guards log(0): a larger one would make near-empty bands gain-dependent.
const dB = (p) => 10 * Math.log10(p + 1e-30)

function percentile(sorted, q) {
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.round(q * (sorted.length - 1))))]
}

// Map each value so the song's 5th..95th percentile (over non-silent frames) becomes 0..1.
function normalize(values, keep) {
  const pool = values.filter((_, i) => keep[i]).sort((x, y) => x - y)
  const lo = percentile(pool, 0.05), hi = percentile(pool, 0.95)
  const range = hi - lo
  return values.map((v) => (range > 1e-6 ? Math.min(1, Math.max(0, (v - lo) / range)) : 0))
}

function follow(values) {
  const dt = 1 / FPS
  const up = 1 - Math.exp(-dt / ATTACK), down = 1 - Math.exp(-dt / RELEASE)
  let y = 0
  return values.map((x) => (y += (x > y ? up : down) * (x - y)))
}

// Onset frames from spectral flux on a fine grid, snapped to the nearest video frame.
function onsetFrames(pcm, sr) {
  const power = makeFFT(ONSET_N)
  const bins = ONSET_N / 2 + 1
  const hops = Math.floor(pcm.length / ONSET_HOP) + 1
  const mags = new Float64Array(hops * bins)
  const p = new Float64Array(bins)
  let maxMag = 0
  for (let h = 0; h < hops; h++) {
    power(pcm, h * ONSET_HOP, p)
    for (let k = 0; k < bins; k++) {
      const m = Math.sqrt(p[k])
      mags[h * bins + k] = m
      if (m > maxMag) maxMag = m
    }
  }
  if (maxMag === 0) return []
  // Log compression relative to the song's peak keeps flux gain-invariant.
  const flux = new Float64Array(hops)
  const fluxBins = Math.min(bins, Math.floor((FLUX_MAX_HZ * ONSET_N) / sr) + 1)
  for (let h = 1; h < hops; h++) {
    let f = 0
    for (let k = 1; k < fluxBins; k++) {
      const d = Math.log1p((1000 * mags[h * bins + k]) / maxMag) - Math.log1p((1000 * mags[(h - 1) * bins + k]) / maxMag)
      if (d > 0) f += d
    }
    flux[h] = f
  }
  const delta = DELTA_FRAC * percentile(Array.from(flux).sort((x, y) => x - y), 0.99) + 1e-6
  const hopSec = ONSET_HOP / sr
  const W = 3, M = Math.round(MEAN_SEC / hopSec)
  // Prefix sums for the moving mean.
  const pre = new Float64Array(hops + 1)
  for (let h = 0; h < hops; h++) pre[h + 1] = pre[h] + flux[h]
  const frames = []
  let last = -Infinity
  for (let h = 1; h < hops; h++) {
    let isMax = true
    for (let j = Math.max(1, h - W); j <= Math.min(hops - 1, h + W); j++) if (flux[j] > flux[h]) { isMax = false; break }
    if (!isMax) continue
    const a = Math.max(1, h - M), b = Math.min(hops - 1, h + M)
    const mean = (pre[b + 1] - pre[a]) / (b - a + 1)
    const t = h * hopSec
    if (flux[h] > MEAN_MUL * mean + delta && t - last >= MIN_GAP) {
      frames.push(Math.round(t * FPS))
      last = t
    }
  }
  return frames
}

// Pure analysis: mono PCM -> {rows, data} with FEATURES.length values per row; row k is time k/60.
export function analyze(pcm, sr = SAMPLE_RATE) {
  const rows = Math.floor((pcm.length / sr) * FPS) + 1
  const power = makeFFT(BAND_N)
  const binHz = sr / BAND_N
  const ranges = BANDS.map(([lo, hi]) => [Math.max(1, Math.ceil(lo / binHz)), Math.min(BAND_N / 2, Math.floor(hi / binHz))])
  const bands = BANDS.map(() => new Array(rows))
  const level = new Array(rows)
  const p = new Float64Array(BAND_N / 2 + 1)
  for (let k = 0; k < rows; k++) {
    const center = Math.round((k * sr) / FPS)
    power(pcm, center, p)
    ranges.forEach(([a, b], i) => {
      let s = 0
      for (let j = a; j <= b; j++) s += p[j]
      bands[i][k] = dB(s)
    })
    let e = 0
    for (let j = center - BAND_N / 2; j < center + BAND_N / 2; j++) if (j >= 0 && j < pcm.length) e += pcm[j] * pcm[j]
    level[k] = dB(e / BAND_N)
  }
  const loudest = level.reduce((m, v) => Math.max(m, v), -Infinity)
  const keep = level.map((v) => v > loudest - SILENCE_DB)
  const cols = [...bands.map((b) => follow(normalize(b, keep))), follow(normalize(level, keep))]

  const onsets = new Set(onsetFrames(pcm, sr))
  const decay = Math.exp(-1 / FPS / BEAT_TAU)
  const beat = new Array(rows)
  let b = 0
  for (let k = 0; k < rows; k++) beat[k] = b = onsets.has(k) ? 1 : b * decay
  cols.push(beat)

  const stride = cols.length
  const data = new Float32Array(rows * stride)
  for (let k = 0; k < rows; k++) for (let c = 0; c < stride; c++) data[k * stride + c] = cols[c][k]
  return { rows, stride, data }
}

// Everything a sketch needs, JSON-ready (values rounded to 5 decimals).
export async function audioFeatures(path) {
  const [pcm, loudness] = await Promise.all([decodeAudio(path), integratedLoudness(path)])
  const { rows, stride, data } = analyze(pcm)
  return {
    dur: pcm.length / SAMPLE_RATE,
    loudness,
    names: FEATURES,
    rows,
    stride,
    data: Array.from(data, (v) => Math.round(v * 1e5) / 1e5),
  }
}
