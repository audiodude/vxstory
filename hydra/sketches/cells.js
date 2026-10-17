// cells — voronoi tiles XORed against rotating bands, kaleidoscoped, smeared by feedback.
// Arc: five sections set by at(). Kaleid sides (integer) step up each section and drop
// back for the coda; cell density, warp, band speed and the feedback blend build into
// the peak and ease down over the cooldown.
const h = rand()
const k = 4 + Math.floor(rand() * 5) // opening kaleid sides, 4..8
const kStep = 1 + Math.floor(rand() * 2) // sides added per section, 1..2
const cells = 3.5 + rand() * 2.5 // opening voronoi density
const bandFreq = 12 + rand() * 12 // colour band frequency
const spin = rand() < 0.5 ? -1 : 1 // band rotation direction
const fbSpin = rand() < 0.5 ? -1 : 1 // feedback swirl direction

// Section boundaries (fractions of dur), seeded jitter.
const T = [
  0,
  dur * (0.16 + rand() * 0.05),
  dur * (0.36 + rand() * 0.06),
  dur * (0.58 + rand() * 0.04),
  dur * (0.79 + rand() * 0.03),
]
const sides = [k, k + kStep, k + 2 * kStep, k + 3 * kStep, k]
let sec = 0
for (let i = 1; i < T.length; i++) at(T[i], () => { sec = i })

// Continuous values move toward each section's target: builds over ~10% of dur,
// the cooldown eases over most of the last section.
const width = (i) => (i === T.length - 1 ? (dur - T[i]) * 0.85 : dur * 0.1)
const track = (vals) => () => {
  let v = vals[0]
  for (let i = 1; i < vals.length; i++) v += ramp(T[i], T[i] + width(i), 0, vals[i] - vals[i - 1])
  return v
}
// Integral of track(): an angle whose rate follows the section targets (linear ramps).
const integ = (vals) => ({ time }) => {
  let a = vals[0] * time
  for (let i = 1; i < vals.length; i++) {
    const d = vals[i] - vals[i - 1]
    const w = width(i)
    const u = time - T[i]
    if (u <= 0) continue
    a += u < w ? (d * u * u) / (2 * w) : d * (u - w / 2)
  }
  return a
}

const density = track([cells, cells * 1.35, cells * 1.8, cells * 2.5, cells * 1.1])
const cellSpeed = track([0.15, 0.25, 0.4, 0.6, 0.18])
const warp = track([0.07, 0.13, 0.2, 0.3, 0.08])
const fb = track([0.3, 0.4, 0.5, 0.62, 0.34])
const punch = track([1.15, 1.3, 1.4, 1.5, 1.2])
const bandAngle = integ([0.02 * spin, 0.035 * spin, 0.05 * spin, 0.08 * spin, 0.025 * spin])

voronoi(density, cellSpeed, 0.1)
  .color(0.9, 0.3, 1.2)
  .diff(osc(bandFreq, 0.06, 1.3).rotate(bandAngle))
  .modulate(noise(2.5, 0.08), warp)
  .kaleid(() => sides[sec])
  .hue(() => h + prog() * 0.2)
  .contrast(punch)
  .blend(src(o0).scale(1.008).rotate(0.003 * fbSpin), fb)
  .out(o0)
