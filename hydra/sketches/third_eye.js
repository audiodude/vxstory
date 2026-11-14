// third_eye — a ringed iris over a field of turning rays; the pupil dilates on the bass.
// Ported from psychadelic-carousel's 15-third-eye.
// Arc: the eye opens almost shut in a dim field of few rays; rays multiply and brighten, the
// iris widens and its rings tighten, the pupil opens into a held peak; then the field dims
// and the eye half-closes.
// Audio: the kick dilates the pupil, low-mids turn the rays, the beat flashes them.
// Seeded: opening ray and iris segment counts, peak time.
const rays = [12, 16, 20][Math.floor(rand() * 3)]
const iris = [18, 24, 30][Math.floor(rand() * 3)]
const peak = dur * (0.55 + rand() * 0.1)
const hold = dur * 0.8

// Envelope: rise from 10% to the seeded peak, hold to 80%, ease to the ending value.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.1, peak, a, b) : ramp(hold, dur, b, c)
const rayN = env(rays, rays * 2, rays * 1.5)
const irisN = env(iris, iris * 1.5, iris)
const irisR = env(0.2, 0.42, 0.3)
const rings = env(6, 16, 9)
const pupil = env(0.04, 0.12, 0.07)
const dim = env(-0.4, -0.1, -0.3)
const pace = env(0.03, 0.15, 0.06)

let spin = 0, kick = 0
update = (dt) => {
  spin += dt * 0.001 * (pace() + 0.5 * a.fft[1])
  kick = Math.max(a.fft[0], kick * 0.93)
}

osc(2 * Math.PI * 2, 0.02, 2)
  .rotate(Math.PI / 2)
  .kaleid(() => Math.round(rayN()))
  .rotate(() => spin)
  .brightness(() => dim() + 0.3 * a.beat)
  .layer(
    osc(() => 2 * Math.PI * rings(), -0.1, 1.2)
      .kaleid(() => Math.round(irisN()))
      .mask(shape(64, irisR, 0.08))
  )
  .mult(shape(64, () => pupil() + 0.12 * kick, 0.04).invert())
  .scale(1, height / width)
  .out()
