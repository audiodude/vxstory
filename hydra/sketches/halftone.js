// halftone — a screen of dark dots on coloured ink, growing to print a drifting, pulsing black sun.
// Ported from psychedelic-carousel's 11-halftone.
// Arc: a coarse screen prints a small, faint sun; the screen gets finer, the sun grows and
// wanders wider, the ink cycles faster into a held peak; then the screen coarsens and the
// sun shrinks back.
// Audio: bass swells the sun, low-mids slide the dot screen, treble pushes the ink colour,
// the beat inverts the print.
// Seeded: opening dot screen size, peak time.
const cols0 = 20 + 4 * Math.floor(rand() * 3) // 20..28 at the opening
const peak = dur * (0.55 + rand() * 0.1)
const hold = dur * 0.8

// Envelope: rise from 10% to the seeded peak, hold to 80%, ease to the ending value.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.1, peak, a, b) : ramp(hold, dur, b, c)
const screen = env(cols0, cols0 * 2.2, cols0 * 1.3)
const cols = () => Math.round(screen()) // repeat counts must be whole
const rows = () => Math.round(screen() * 0.55)
const sun = env(0.15, 0.35, 0.2)
const wander = env(0.1, 0.3, 0.15)
const ink = env(0.003, 0.03, 0.008)
const pace = env(0.01, 0.06, 0.02)

let slide = 0, tint = 0
update = (dt) => {
  slide += dt * 0.001 * (pace() + 0.15 * a.fft[1])
  tint += dt * 0.001 * ink()
}
const bass = () => a.fft[0]

// the picture being printed: a sun wandering over slow noise, 0..1
const picture = shape(64, () => sun() + 0.2 * bass(), 0.6)
  .scroll(() => wander() * Math.sin(time * 0.3), () => 0.75 * wander() * Math.cos(time * 0.23))
  .add(noise(2, 0.1).mult(solid(0.3, 0.3, 0.3)).add(solid(0.2, 0.2, 0.2)))
  .scale(1, height / width)

// each cell is a radial ramp; adding the picture and thresholding gives dots sized by brightness
shape(64, 0.5, 1)
  .repeat(cols, rows)
  .scroll(() => slide, 0)
  .add(picture.luma(0, 0).r())
  .thresh(0.9, 0.05)
  .invert(() => a.beat > 0.5 ? 1 : 0)
  .color(-0.95, -0.9, -0.8)
  .mult(solid(1, () => 0.2 + 0.3 * a.fft[3], 0.55).hue(() => tint))
  .add(solid(0.12, 0.08, 0.06))
  .out()
