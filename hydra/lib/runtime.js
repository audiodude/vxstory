// Sketch runtime: seeded RNG and arc helpers over Hydra's frame-stepped clock.
// Every helper is a pure function of Hydra's `time`, except at(), which fires
// on the first frame whose time reaches t. Shared by preview and render.
(function () {
  function mulberry32(a) {
    return function () {
      a = (a + 0x6D2B79F5) | 0
      let t = Math.imul(a ^ (a >>> 15), 1 | a)
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }
  const curves = {
    linear: (u) => u,
    ease_in: (u) => u * u,
    ease_out: (u) => 1 - (1 - u) * (1 - u),
    smooth: (u) => u * u * (3 - 2 * u),
  }
  const clamp01 = (x) => Math.min(1, Math.max(0, x))

  window.createRuntime = function ({ hydra, seed, dur }) {
    const now = () => hydra.synth.time
    const rand = mulberry32(seed)
    Math.random = rand // Hydra internals and sketch code both draw from the seed
    const pending = []
    Object.assign(window, {
      seed,
      dur,
      rand,
      prog: () => clamp01(now() / dur),
      ramp: (t0, t1, a, b, curve = 'smooth') =>
        a + (b - a) * curves[curve](clamp01((now() - t0) / (t1 - t0))),
      lfo: (period, phaseDeg = 0) => Math.sin(2 * Math.PI * (now() / period + phaseDeg / 360)),
      at: (t, fn) => {
        pending.push({ t, fn })
        pending.sort((a, b) => a.t - b.t)
      },
    })
    return {
      now,
      // Advance exactly one frame: fire at() callbacks due by the new time, then render.
      step(dtSec) {
        const next = now() + dtSec
        while (pending.length && pending[0].t <= next + 1e-9) pending.shift().fn()
        hydra.tick(dtSec * 1000)
      },
    }
  }
})()
