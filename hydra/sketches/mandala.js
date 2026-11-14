// mandala — folded stripes breathing on the bass, the wedge count stepping every two seconds.
// Ported from psychedelic-carousel's 02-mandala.
// Arc: a calm, sparse mandala opens the piece; stripes multiply, the wedge counts double,
// the petals fold deeper and the colour bands tighten into a held peak; then it eases back
// to a calmer bloom.
// Audio: bass zooms and swells the petals, low-mids spin them, high-mids band the colour,
// the beat flashes.
// Seeded: stripe count, spin direction, peak time.
const stripes = 4 + Math.floor(rand() * 3) // 4..6 at the opening
const dir = rand() < 0.5 ? -1 : 1
const peak = dur * (0.55 + rand() * 0.1)
const hold = dur * 0.8

// Envelope: rise from 10% to the seeded peak, hold to 80%, ease to the ending value.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.1, peak, a, b) : ramp(hold, dur, b, c)
const freq = env(stripes, stripes * 2, stripes * 1.3)
const wedgeMul = env(1, 2, 1.5)
const fold = env(0.05, 0.4, 0.15)
const band = env(0.03, 0.15, 0.06)
const pace = env(0.06, 0.3, 0.12)

const wedges = [6, 8, 6, 12]
let angle = 0
update = (dt) => { angle += dt * 0.001 * (pace() + 0.8 * a.fft[1]) * dir }
const bass = () => a.fft[0]

osc(() => 2 * Math.PI * freq(), 0.04, 1.3)
  .kaleid(() => Math.round(wedges[Math.floor(time * 0.5) % 4] * wedgeMul()))
  .rotate(() => angle)
  .modulateScale(osc(2 * Math.PI * 2, 0.1).kaleid(4), () => fold() + 0.3 * bass(), 1)
  .scale(() => 1 + 0.2 * bass(), height / width)
  .colorama(() => band() + 0.1 * a.fft[2])
  .brightness(() => 0.2 * a.beat)
  .out()
