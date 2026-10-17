// Sketch runtime, shared by preview and render.
//   startSketch() boots Hydra the one way both pages agree on and reports every failure
//   Hydra would otherwise swallow. createRuntime() installs the sketch globals (seed,
//   rand, dur, prog, ramp, lfo, at) and steps the clock exactly one frame at a time.
// Time: frame k renders at time k/60. Helpers are pure functions of Hydra's `time`,
// except at(), which fires just before the first frame whose time reaches t.
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
    Math.random = rand // hydra-synth never calls it; this seeds any stray use in sketch code
    const pending = []
    Object.assign(window, {
      seed,
      dur,
      rand,
      prog: () => clamp01(now() / dur),
      ramp: (t0, t1, a, b, curve = 'smooth') => {
        const f = curves[curve]
        if (!f) throw new Error(`ramp: unknown curve '${curve}'`)
        if (!(t1 > t0)) throw new Error(`ramp: needs t1 > t0, got ${t0}..${t1}`)
        if (!Number.isFinite(a) || !Number.isFinite(b)) throw new Error(`ramp: a and b must be finite, got ${a}, ${b}`)
        return a + (b - a) * f(clamp01((now() - t0) / (t1 - t0)))
      },
      lfo: (period, phaseDeg = 0) => {
        if (!(period > 0)) throw new Error(`lfo: period must be > 0, got ${period}`)
        return Math.sin(2 * Math.PI * (now() / period + phaseDeg / 360))
      },
      at: (t, fn) => {
        if (!Number.isFinite(t) || typeof fn !== 'function') throw new Error('at: needs a finite time and a function')
        pending.push({ t, fn })
        pending.sort((a, b) => a.t - b.t) // stable: equal times fire in registration order
      },
    })
    return {
      now,
      // Advance exactly one frame: fire at() callbacks due by the new time, then render.
      step(dtSec) {
        const next = now() + dtSec
        while (pending.length && pending[0].t <= next + 1e-9) pending.shift().fn()
        // Hydra copies these globals into its clock on every tick: speed would desync time
        // from the frame count, fps would make it skip draws.
        if (window.speed !== 1 || window.fps) {
          throw new Error(`sketches must not set speed or fps (speed=${window.speed}, fps=${window.fps})`)
        }
        hydra.tick(dtSec * 1000)
      },
    }
  }

  // Boot a sketch on `canvas`. Every failure goes to onError(message): Hydra turns most of
  // them into console noise and keeps drawing default-valued, stale or black frames.
  window.startSketch = function ({ canvas, width, height, seed, dur, name, code, onError }) {
    const text = (x) => (x instanceof Error ? x.stack || String(x) : String(x))
    const report = (...args) => onError(args.map(text).join(' '))
    for (const level of ['warn', 'error']) {
      const orig = console[level].bind(console)
      console[level] = (...a) => { orig(...a); report(...a) }
    }
    const log = console.log.bind(console)
    console.log = (...a) => { log(...a); if (a.some((x) => x instanceof Error)) report(...a) }
    addEventListener('error', (e) => report(e.error ?? e.message))
    addEventListener('unhandledrejection', (e) => report('unhandled rejection:', e.reason))
    canvas.addEventListener('webglcontextlost', () => report('WebGL context lost'))

    // Hydra takes its size from the canvas. Creating the context first keeps each frame
    // readable after presentation; regl reuses the existing context.
    canvas.width = width
    canvas.height = height
    const gl = canvas.getContext('webgl', { preserveDrawingBuffer: true })
    // The regl bundled in hydra-synth never checks compile status: a broken shader just draws
    // nothing, and only the browser logs a warning. Check every shader and program here.
    const compile = gl.compileShader.bind(gl)
    gl.compileShader = (s) => {
      compile(s)
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) report('shader compile failed:', gl.getShaderInfoLog(s))
    }
    const link = gl.linkProgram.bind(gl)
    gl.linkProgram = (p) => {
      link(p)
      if (!gl.getProgramParameter(p, gl.LINK_STATUS)) report('shader link failed:', gl.getProgramInfoLog(p))
    }
    const hydra = new Hydra({ canvas, autoLoop: false, detectAudio: false, enableStreamCapture: false, precision: 'highp' })
    const rt = createRuntime({ hydra, seed, dur })
    try {
      new Function(`${code}\n//# sourceURL=sketches/${name}.js`)()
    } catch (e) {
      report(e)
    }
    return rt
  }
})()
