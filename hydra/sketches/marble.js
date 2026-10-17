// marble — stripe islands layered into a self-advecting feedback field: liquid ink marbling.
// Arc: a combed stripe bath laid on frame 1 starts to drift; sparse ink drops in; advection
// and injection climb to a peak where a second, counter-rotating ink joins; the cooldown
// stills the bath and drains it toward a dark tone (8-bit feedback stops the drain short of it).
const D = dur

// Seeded structure.
const h = rand()                                 // palette offset
const freqA = 26 + Math.round(rand() * 30)       // stripe frequency inside the islands
const freqB = 14 + Math.round(rand() * 20)       // stripe frequency of the second ink
const bathFreq = 5 + Math.round(rand() * 9)      // stripe count of the opening bath
const bathAngle = rand() * Math.PI               // bath comb direction
const isle = 0.9 + rand() * 1.1                  // island noise scale: fewer/bigger vs more/smaller
const thr = 0.64 + rand() * 0.08                 // island threshold: how much ink
const flow = rand() * Math.PI * 2                // advection drift direction
const fx = Math.cos(flow) * Math.SQRT2
const fy = Math.sin(flow) * Math.SQRT2
const curl = 1.6 + rand() * 1.4                  // advection noise scale: tight vs broad swirls
const spin = rand() < 0.5 ? -1 : 1               // stripe rotation direction
const off = () => [rand() * 20, rand() * 20]     // noise layout offsets
const [ax, ay] = off(), [bx, by] = off(), [ix, iy] = off(), [jx, jy] = off()
const tJoin = D * (0.22 + rand() * 0.12)         // second ink joins during the escalation
const tLeave = D * (0.78 + rand() * 0.05)        // and leaves as the cooldown starts

// Opening value a, peak value c (reached at 0.62 dur), end value d.
const arc = (a, c, d) => () => ramp(D * 0.04, D * 0.62, a, c) + ramp(D * 0.8, D * 0.97, 0, d - c)
const adv = arc(0.0035, 0.013, 0.0025) // floor: sub-pixel drift stair-steps the still field
const rot = arc(0.012, 0.05, 0.008)
const zoom = arc(1.0006, 1.0022, 1.0)
const inkA = arc(thr + 0.1, thr - 0.05, thr + 0.14)
const inkB = arc(thr + 0.1, thr - 0.02, thr + 0.2)
const drain = () => ramp(D * 0.8, D, 0, 0.012)
// Deep seeded bath colour the cooldown drains toward (saturated, not grey).
const tone = [0, 1, 2].map((k) => 0.17 + 0.14 * Math.cos(2 * Math.PI * (h + 0.4 + k / 3)))

const at0 = (n, x, y) => n.modulate(solid(x, y), 1) // shift a noise layout without fract seams

const islandsA = () =>
  osc(freqA, 0.05, 1.6).hue(({ time }) => h + time * 0.01).rotate(({ time }) => spin * time * 0.05)
    .mask(at0(noise(isle, 0.15), ix, iy).thresh(inkA, 0.04))
const islandsB = () =>
  osc(freqB, -0.04, 1.6).hue(({ time }) => h + 0.5 + time * 0.013).rotate(({ time }) => -spin * time * 0.04)
    .mask(at0(noise(isle * 1.7, 0.11), jx, jy).thresh(inkB, 0.04))

function patch(two) {
  let field = src(o0)
    .modulate(at0(noise(curl, 0.04), ax, ay).add(solid(-0.5, -0.5), 1).color(fx, fy, 0),
      () => adv() * (1 + 0.25 * lfo(17)))
    .modulateRotate(at0(noise(curl * 0.6, 0.02), bx, by), rot)
    .scale(zoom)
    .blend(solid(tone[0], tone[1], tone[2]), drain)
    .layer(islandsA())
  if (two) field = field.layer(islandsB())
  field.out(o0)
}

// Frame 1: lay a combed stripe bath, then hand the buffer to the feedback field.
osc(bathFreq, 0, 1.6).hue(h).rotate(bathAngle).modulate(at0(noise(1.2, 0), ix, iy), 0.15)
  .color(0.75, 0.75, 0.75).out(o0)
at(1.5 / 60, () => patch(false))
at(tJoin, () => patch(true))
at(tLeave, () => patch(false))
