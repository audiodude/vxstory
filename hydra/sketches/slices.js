// slices — blue kaleidoscoped oscillator slices masked by spinning triangles, layered over
// pixelated purple noise.
// Arc: broad slices behind one large star open the piece; the oscillator tightens, kaleid
// sides and mask tiles step up, the star widens and the noise blocks shrink into the peak;
// after a hold everything eases back toward the opening. The slices spin one way at a
// steady speed and snap ahead the moment the peak lands.
// Audio (when rendered with a song): bass swells the star, the beat kicks contrast, treble
// lifts the slices' saturation. With no song the chain is unchanged (see README: Audio).
const sides = 3 + Math.floor(rand() * 2) // opening kaleid sides, 3..4
const addSides = 2 + Math.floor(rand() * 3) // extra sides at the peak, 2..4
const maskSides = 5 + Math.floor(rand() * 3) // star points, 5..7
const spin = rand() < 0.5 ? -1 : 1 // slice rotation direction (the star turns the other way)
const peak = dur * (0.55 + rand() * 0.1)
const hold = dur * 0.8

// Envelope: rise from 10% to the seeded peak, hold to 80%, ease to the ending value.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.1, peak, a, b) : ramp(hold, dur, b, c)
const freq = env(6, 18, 8)
const kSides = env(sides, sides + addSides, sides)
const tiles = env(1, 3, 2)
const radius = env(0.5, 0.7, 0.55)
const pix = env(8, 32, 12)
// The slices spin steadily, then snap ahead by half a kaleid sector the moment the peak
// lands (half a sector is the largest visible jump; a whole one looks identical).
const snap = Math.PI / (sides + addSides)

osc(freq, 0.1, 1.2)
  .rotate(() => (time * 0.1 + (time >= peak ? snap : 0)) * spin)
  .kaleid(() => Math.round(kSides()))
  .saturate(a.active ? () => 2 + 1.5 * a.fft[3] : 2) // literal when silent: a uniform drifts some frames
  .color(0, 0, 1)
  .blend(osc(freq, 0.1, 1.2 + Math.PI).color(0, 0, 1))
  .mask(
    shape(3, () => radius() + 0.15 * a.fft[0], 0.2)
      .repeat(() => Math.round(tiles()), () => Math.round(tiles()))
      .luma(0.1)
      .rotate(() => time * -0.4 * spin)
      .kaleid(maskSides),
  )
  .out(o3)

const bg = solid(0.4, 0.2, 0.6)
  .add(noise(-1))
  .pixelate(() => Math.round(pix()), () => Math.round(pix() * 2))
  .layer(o3)
;(a.active ? bg.contrast(() => 1 + 0.4 * a.beat) : bg).out(o2)

render(o2)
