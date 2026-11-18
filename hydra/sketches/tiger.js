// tiger — orange and cream stripes folded into a kaleidoscope, torn by counter-scrolling
// stripes cut along a stretching square seam, the whole frame turning.
// Arc: soft, wide stripes and a gentle tear open the piece; the stripes tighten, the
// kaleidoscope gains sectors, the tear deepens and the turn quickens into a held peak; then
// it eases back to a calmer pelt.
// Audio: bass pulls the two tear layers' stripes apart, high-mids deepen the tear, treble
// swells the seam.
// Seeded: palette offset, triangle sides, opening kaleid sides, spin direction, peak time.
const hueOff = 1 + rand() * 0.4 // osc offset: 1.2 is the original orange
const tri = 3 + Math.floor(rand() * 2) // 3..4
const sides = 4 + Math.floor(rand() * 2) // opening kaleid sides, 4..5
const dir = rand() < 0.5 ? -1 : 1
const peak = dur * (0.55 + rand() * 0.1)
const hold = dur * 0.8

// Envelope: rise from 10% to the seeded peak, hold to 80%, ease to the ending value.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.1, peak, a, b) : ramp(hold, dur, b, c)
const freq = env(3, 7, 4)
const tearFreq = env(6, 11, 7)
const kSides = env(sides, sides + 2, sides)
const tear = env(0.08, 0.3, 0.12)
const pace = env(0.8, 2, 1.1)

let angle = 0
update = (dt) => { angle += dt * 0.001 * pace() * dir }

// The seam: a stretching square, scrolled half a screen so it splits across the edges.
shape(4, () => 0.4 + 0.3 * a.fft[3], 0.2).scale(1, 1, [0.02, 2].smooth()).scrollX(0.5).out(o3)

const inner = osc(() => tearFreq() + 1 - 2 * a.fft[0], -2).rotate(Math.PI / 2).mask(src(o3).invert())
const outer = osc(() => tearFreq() + 2 * a.fft[0], 2).rotate(Math.PI / 2).mask(src(o3))

osc(freq, 0.1, hueOff)
  .mask(shape(tri, 0.6))
  .add(osc(() => freq() * 1.5, -0.05, 0.4).color(0.867, 0.831, 0.804).mask(shape(tri, 0.6).invert()))
  .modulateScale(osc().rotate(0, 1))
  .kaleid(() => Math.round(kSides()))
  .out(o2)

src(o2)
  .modulate(inner.layer(outer), () => tear() + 0.3 * a.fft[2])
  .rotate(() => angle)
  .out(o0)

render(o0)
