// marble — stripe islands layered into a self-advecting feedback field: liquid ink marbling.
const h = rand()
src(o0)
  .modulate(noise(2.2, 0.04).add(solid(-0.5, -0.5), 1), 0.008)
  .modulateRotate(noise(1.3, 0.02), 0.03)
  .scale(1.002)
  .layer(
    osc(40, 0.05, 1.6).hue(({ time }) => h + time * 0.01).rotate(({ time }) => time * 0.05)
      .mask(noise(1.4, 0.15).thresh(0.7, 0.04))
  )
  .out(o0)
