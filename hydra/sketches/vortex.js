// vortex — a wide ring of color spun inward through feedback: a whirlpool swallowing its trails.
const h = rand()
const dir = rand() < 0.5 ? -1 : 1
shape(96, 0.75, 0.04).diff(shape(96, 0.7, 0.04))
  .mult(osc(10, 0.15, 1.5).hue(h).rotate(({ time }) => dir * time * 0.4))
  .add(src(o0).scale(0.975).rotate(dir * 0.03).modulate(noise(3, 0.1), 0.008), 0.95)
  .out(o0)
