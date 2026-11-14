// hex_tunnel — a rainbow hexagon keyed over its own zooming past.
// Ported from psychadelic-carousel's 03-hex-tunnel.
// Arc: a small hexagon drifting over short, slow trails opens the piece; the hexagon grows
// and turns faster, its stripes tighten and the fall speeds up into long rainbow tunnels at a
// held peak; then it slows back to a gentle drift.
// Audio: the kick pumps both the hexagon and the speed of the fall.
// Seeded: stripe count inside the hexagon, spin direction, peak time.
const rings = 3 + Math.floor(rand() * 3) // 3..5 at the opening
const dir = rand() < 0.5 ? -1 : 1
const peak = dur * (0.55 + rand() * 0.1)
const hold = dur * 0.8

// Envelope: rise from 10% to the seeded peak, hold to 80%, ease to the ending value.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.1, peak, a, b) : ramp(hold, dur, b, c)
const fall = env(1.012, 1.045, 1.02)
const size = env(0.2, 0.34, 0.25)
const freq = env(rings, rings * 2.5, rings * 1.5)
const twist = env(0.15, 0.6, 0.25)
const fade = env(-0.02, -0.006, -0.012) // less fade = longer trails

let kick = 0, turn = 0
update = (dt) => {
  kick = Math.max(a.fft[0], kick * 0.92)
  turn += dt * 0.001 * twist() * dir
}

src(o0)
  .scale(() => fall() + 0.04 * kick)
  .hue(0.01)
  .brightness(() => fade())
  .layer(
    osc(() => 2 * Math.PI * freq(), 0.1, 1.5)
      .hue(() => time * 0.03)
      .mask(
        shape(6, () => size() + 0.15 * kick, 0.01)
          .diff(shape(6, () => size() * 0.8 + 0.12 * kick, 0.01))
          .rotate(() => turn)
          .scale(1, height / width),
      ),
  )
  .out()
