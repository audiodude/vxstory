// glass — a tiled grid of shapes refracted through moving noise, like looking through pebbled glass.
// Arc: a sparse, gently bent grid opens; tiles multiply, the glass refracts harder and the
// trails lengthen into the peak; then the grid thins, the glass clears and the shapes shrink.
const h = rand()
const n = 3 + Math.floor(rand() * 4) // shape sides
const cols = 3 + Math.floor(rand() * 3) // opening grid columns
const rows = 2 + Math.floor(rand() * 2) // opening grid rows
const addCols = 2 + Math.floor(rand() * 3) // extra columns at the peak
const addRows = 1 + Math.floor(rand() * 2) // extra rows at the peak
const brick = rand() < 0.5 ? 0.5 : 0 // brick-offset rows or a straight grid
const cells = 24 + Math.floor(rand() * 5) * 8 // pixel size of the glass pebbles
const pebble = 2.5 + rand() * 2 // noise scale of the glass
const drift = (rand() < 0.5 ? 1 : -1) * (0.006 + rand() * 0.008)

// Envelope: rise over 15-65%, hold the peak to 80%, ease off to the end.
const env = (a, b, c) => () =>
  prog() < 0.8 ? ramp(dur * 0.15, dur * 0.65, a, b) : ramp(dur * 0.8, dur, b, c)
const tilesX = env(cols, cols + addCols, cols + 1)
const tilesY = env(rows, rows + addRows, rows)
const refract = env(0.08, 0.2, 0.06)
const bend = env(0.09, 0.19, 0.06)
const trail = env(0.4, 0.66, 0.42)
const size = env(0.3, 0.38, 0.26)

shape(n, size, 0.25)
  .repeat(() => Math.round(tilesX()), () => Math.round(tilesY()), brick, 0)
  .scrollX(({ time }) => time * drift)
  .mult(osc(10, 0.08, 1.4).hue(h))
  .modulate(noise(pebble, 0.08).pixelate(cells, cells), refract)
  .modulate(osc(6, 0.02).rotate(() => time * 0.01), bend)
  .add(src(o0).scale(1.01).modulate(noise(2, 0.05), 0.01), trail)
  .out(o0)
