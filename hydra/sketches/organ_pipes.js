// organ_pipes — a rank of brass pipes whose heights roll in a wave, over a dark violet wall.
// Ported from psychadelic-carousel's 04-organ-pipes.
// Arc: a short rank of low pipes in a gentle swell opens the piece; pipes are added, the wave
// rises taller, rolls faster and folds into more crests while the wall warms, into a held
// peak; then the rank thins and settles.
// Audio: bass lifts the wave, low-mids set its pace, treble warms the brass, the beat flashes.
// Seeded: opening pipe count, wave length, peak time.
const pipesN = [12, 16, 20][Math.floor(rand() * 3)]
const cycles = [1, 1.5, 2][Math.floor(rand() * 3)]
const peak = dur * (0.55 + rand() * 0.1)
const hold = dur * 0.8

// Envelope: rise from 10% to the seeded peak, hold to 80%, ease to the ending value.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.1, peak, a, b) : ramp(hold, dur, b, c)
const count = env(pipesN, pipesN * 2, pipesN * 1.25)
const n = () => Math.round(count()) // pixelate cells must be whole
const crests = env(cycles, cycles * 2, cycles)
const lift = env(0.15, 0.45, 0.25)
const pace = env(0.08, 0.35, 0.12)
const wall = env(0, 0.12, 0.04)

let phase = 0
update = (dt) => { phase += dt * 0.001 * (pace() + 0.5 * a.fft[1]) }
const bass = () => a.fft[0]

// one height per pipe: a sine across x, quantised into one column per pipe
const heights = osc(() => 2 * Math.PI * crests(), 0).scroll(() => phase, 0).pixelate(n, 1)
const pipes = gradient(0).g()
  .modulateScrollY(heights, () => lift() + 0.3 * bass())
  .thresh(0.5, 0.01)
  .mult(osc(() => 2 * Math.PI * n(), 0).thresh(0.3, 0.01))

solid(() => 0.12 + wall(), 0.02, () => 0.2 + 0.5 * wall())
  .layer(
    osc(() => 2 * Math.PI * n(), 0, 0.8)
      .color(1, () => 0.6 + 0.2 * a.fft[3], 0.25)
      .hue(() => 0.1 * Math.sin(time * 0.05))
      .brightness(() => 0.3 * a.beat)
      .mask(pipes)
  )
  .out()
