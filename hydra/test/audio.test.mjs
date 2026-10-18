// lib/audio.mjs analysis on synthetic PCM: no ffmpeg, no browser.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { analyze, FEATURES, SAMPLE_RATE as SR } from '../lib/audio.mjs'

const col = (f, name) => {
  const c = FEATURES.indexOf(name)
  return Array.from({ length: f.rows }, (_, k) => f.data[k * f.stride + c])
}
const pcm = (sec, fn) => Float32Array.from({ length: Math.round(sec * SR) }, (_, i) => fn(i / SR, i))
const sine = (hz, amp = 0.5) => (t) => amp * Math.sin(2 * Math.PI * hz * t)

test('row k is time k/60: floor(duration × 60) + 1 rows', () => {
  assert.equal(analyze(pcm(2, () => 0)).rows, 121)
  assert.equal(analyze(pcm(1.01, () => 0)).rows, 61)
})

test('silence gives all zeros, never NaN', () => {
  const f = analyze(pcm(1, () => 0))
  assert.ok(f.data.every((v) => v === 0))
})

test('a tone in each band drives that band above the others', () => {
  // Tone switches each second between the four band centres; compare mid-second frames.
  const hz = [70, 300, 1200, 6000]
  const f = analyze(pcm(4, (t) => sine(hz[Math.min(3, Math.floor(t))])(t)))
  const bands = [0, 1, 2, 3].map((i) => col(f, `fft${i}`))
  for (let s = 0; s < 4; s++) {
    const k = s * 60 + 45
    const loudest = bands.map((b) => b[k]).indexOf(Math.max(...bands.map((b) => b[k])))
    assert.equal(loudest, s, `second ${s} (${hz[s]} Hz): ${bands.map((b) => b[k].toFixed(2))}`)
  }
})

test('beat fires within one frame of each click, and nowhere else', () => {
  // Clicks at 0.25, 0.75, ... s over quiet noise (frames 15, 45, 75, 105, 135, 165).
  let seed = 7
  const noise = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31 - 0.5) * 0.01
  const f = analyze(pcm(3, (t) => (((t + 0.25) % 0.5) < 0.002 ? 0.9 : noise())))
  const beat = col(f, 'beat')
  const hits = beat.flatMap((v, k) => (v === 1 ? [k] : []))
  const want = [15, 45, 75, 105, 135, 165]
  assert.equal(hits.length, want.length, `beat frames ${hits}`)
  hits.forEach((k, i) => assert.ok(Math.abs(k - want[i]) <= 1, `click ${i}: frame ${k}, want ${want[i]}`))
})

test('normalization is gain-invariant: the same song 20 dB quieter gives the same features', () => {
  const song = (t) => sine(80, 0.4)(t) * (0.5 + 0.5 * Math.sin(2 * Math.PI * 0.7 * t)) + sine(2000, 0.1)(t) * (t % 0.5 < 0.05 ? 1 : 0.1)
  const loud = analyze(pcm(3, song))
  const quiet = analyze(pcm(3, (t) => 0.1 * song(t)))
  let worst = 0
  for (let i = 0; i < loud.data.length; i++) worst = Math.max(worst, Math.abs(loud.data[i] - quiet.data[i]))
  assert.ok(worst < 1e-4, `max difference ${worst}`)
  assert.ok(loud.data.some((v) => v > 0.5), 'features are not trivially zero')
})
