// babylon_tile — yellow and blue moiré stripes cut through a photo of a glazed tile,
// folded into a kaleidoscope while the photo breathes in and out.
// Arc: a few broad stripes through a sparse mask open the piece; the stripes tighten, the
// mask fills in, the breathing deepens and the kaleidoscope gains sectors and starts to turn
// into a held peak; then it eases back toward a calmer six-fold tile.
// Audio: bass zooms the tile in, low-mids turn the kaleidoscope, treble speeds the stripes,
// the beat flashes.
// Seeded: peak stripe frequency, peak sector count, spin direction, breathing rate, peak time.
s0.initImage('/images/babylon_tile.jpg') // hydra/images/, served by render and preview

const peakFreq = 26 + Math.floor(rand() * 10) // 26..35
const peakSides = 8 + 2 * Math.floor(rand() * 3) // 8, 10, 12
const dir = rand() < 0.5 ? -1 : 1
const rate = 0.7 + rand() * 0.6 // breathing, rad/s (the original sin(time) is 1)
const peak = dur * (0.55 + rand() * 0.1)
const hold = dur * 0.8

// Envelope: rise from 10% to the seeded peak, hold to 80%, ease to the ending value.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.1, peak, a, b) : ramp(hold, dur, b, c)
const freq = env(10, peakFreq, 18)
const sides = env(4, peakSides, 6)
const lumaCut = env(0.35, 0.01, 0.12) // lower = more of the photo opens the mask
const swing = env(0.25, 1, 0.4)
const turn = env(0, 0.12, 0.04)

let spin = 0
update = (dt) => { spin += dt * 0.001 * (turn() + 0.5 * a.fft[1]) * dir }
const sync = () => 1 + 2 * a.fft[3]

osc(freq, sync).color(0.945, 0.937, 0).luma(0.5)
  .add(osc(() => freq() + 1, sync).invert().luma(0.5).color(0, 0.447, 0.976))
  .out(o3)

src(s0)
  .luma(lumaCut)
  .scale(() => 2.1 + swing() * Math.sin(time * rate) - 0.5 * a.fft[0])
  .out(o2)

src(o3)
  .mask(o2)
  .kaleid(() => Math.round(sides()))
  .rotate(() => spin)
  .brightness(() => 0.25 * a.beat)
  .out(o0)
