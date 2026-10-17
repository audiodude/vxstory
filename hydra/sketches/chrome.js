// chrome — an oscillator folded through itself into liquid-metal ribbons.
// Arc: wide slow ribbons with a shallow fold → fold depth and ribbon frequency climb →
// peak with a brief colour bloom (seeded timing) → ribbons relax and dim to an ending.
const h = rand()                                          // palette offset
const f0 = 14 + rand() * 10                               // ribbon frequency at full strength
const dir = rand() < 0.5 ? -1 : 1                         // ribbon drift direction
const foldFreq = 2 + rand() * 2.5                         // fold-field frequency
const foldSpin = (0.05 + rand() * 0.06) * (rand() < 0.5 ? -1 : 1) // fold-axis swing rate
const foldPhase = rand() * 2 * Math.PI                    // fold-axis starting angle
const sides = 2 + Math.floor(rand() * 4)                  // scale-fold symmetry, 2..5
const tBloom = dur * (0.63 + rand() * 0.09)               // colour-bloom centre
const bloomLen = dur * 0.035

// Fold depth: shallow opening, long build, held peak, release.
const depth = () =>
  ramp(0, dur * 0.2, 1.1, 1.9) +
  ramp(dur * 0.2, dur * 0.62, 0, 2.7) +
  ramp(dur * 0.62, dur * 0.8, 0, 0.6) +
  0.35 * lfo(23) * ramp(dur * 0.3, dur * 0.75, 0, 1) -
  ramp(dur * 0.8, dur, 0, 3.4)
// Ribbon frequency as a multiple of f0.
const freqMul = () =>
  ramp(0, dur * 0.2, 0.5, 0.75) +
  ramp(dur * 0.2, dur * 0.65, 0, 1.0) -
  ramp(dur * 0.8, dur, 0, 1.05)
const bloom = ({ time }) => Math.exp(-(((time - tBloom) / bloomLen) ** 2))
const fade = () => ramp(dur * 0.9, dur, 1, 0.6)

osc(() => f0 * freqMul(), -0.04 * dir, 0.25)
  .modulateRotate(
    osc(foldFreq, 0.03).rotate(({ time }) => Math.sin(time * foldSpin + foldPhase) * 2),
    depth,
  )
  .modulate(noise(1.6, 0.06), () => ramp(0, dur * 0.65, 0.3, 0.55) - ramp(dur * 0.8, dur, 0, 0.2))
  .modulateScale(osc(2, 0.02).kaleid(sides), () => ramp(dur * 0.1, dur * 0.65, 0.25, 0.5) - ramp(dur * 0.8, dur, 0, 0.2))
  .color(0.9, 1, 1.25)
  .hue((p) => h + 0.42 * bloom(p) * (1 + 0.3 * Math.sin(p.time * 0.9)))
  .saturate((p) => 0.7 + 1.5 * bloom(p))
  .contrast(() => ramp(0, dur * 0.2, 1.1, 1.2) + ramp(dur * 0.4, dur * 0.65, 0, 0.15) - ramp(dur * 0.8, dur, 0, 0.15))
  .color(fade, fade, fade)
  .out(o0)
