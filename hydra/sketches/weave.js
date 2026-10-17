// weave — fine threads crossed with a slow wave lattice; shimmering textile.
// Arc: sparse, few-hued threads → denser threads and a harder-warped lattice, colour opening
// to the full rainbow at the peak → threads relax and the palette narrows again.
const h = rand() // hue offset
const ang = 0.1 + rand() * 1.4 // thread angle (rad)
const dir = rand() < 0.5 ? -1 : 1 // lattice warp / drift direction
const latF = 7 + rand() * 8 // lattice frequency
const tf = 0.8 + rand() * 0.45 // thread density scale
const pk = 0.6 + rand() * 0.12 // when the build tops out (fraction of dur)

const D = dur
// Envelope: a at t=0, b at the end of the opening, c from the peak to 0.8 dur, d at the end.
const env = (a, b, c, d) => () =>
  a +
  ramp(0, D * 0.2, 0, b - a) +
  ramp(D * 0.2, D * pk, 0, c - b, 'ease_in') +
  ramp(D * 0.8, D, 0, d - c)

const threadFreq = env(60, 72, 150, 78)
const latAmt = env(0.35, 0.5, 1.5, 0.4) // how hard the lattice bends the threads
const noiseAmt = env(0.03, 0.05, 0.16, 0.04)
const spread = env(0.45, 0.6, 2.1, 0.45) // osc channel offset: few hues → full rainbow
const sat = env(1.15, 1.25, 1.7, 1.15)
// The warm tint that defines the few-hue ends relaxes toward neutral at the peak, so the
// rainbow is not filtered back down to one or two colours.
const tintR = env(2.2, 2.2, 1.35, 2.2)
const tintB = env(0.5, 0.5, 1.1, 0.5)

osc(() => threadFreq() * tf, env(0.008, 0.012, 0.04, 0.01), spread)
  .rotate(({ time }) => ang + dir * time * 0.006 + 0.08 * lfo(53))
  .mult(
    osc(() => latF * ramp(D * 0.2, D * pk, 1, 1.6, 'ease_in') * ramp(D * 0.8, D, 1, 0.85), 0.06, 0.4)
      .modulate(osc(latF * 0.75, -0.04 * dir).rotate(({ time }) => -dir * time * 0.015), latAmt),
  )
  .modulate(noise(1.5, 0.05), noiseAmt)
  .color(tintR, 1, tintB)
  .hue(h)
  .saturate(sat)
  .contrast(1.4)
  .out(o0)
