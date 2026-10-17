// lib/runtime.js in a bare VM context with a stand-in for Hydra's clock: no browser needed.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const SRC = readFileSync(new URL('../lib/runtime.js', import.meta.url), 'utf8')
const DT = 1 / 60

function load() {
  const page = vm.createContext({ speed: 1 }) // Hydra puts speed=1 on window at construction
  page.window = page
  vm.runInContext(SRC, page)
  const hydra = { synth: { time: 0 }, tick(ms) { this.synth.time += ms / 1000 } }
  return { page, hydra, rt: page.createRuntime({ hydra, seed: 1, dur: 300 }) }
}

test('ramp holds at both ends and hits each curve midpoint', () => {
  const { page, hydra } = load()
  const ramp = (t, curve) => {
    hydra.synth.time = t
    return page.ramp(10, 20, 2, 4, curve)
  }
  for (const [curve, mid] of [['linear', 3], ['ease_in', 2.5], ['ease_out', 3.5], ['smooth', 3]]) {
    assert.equal(ramp(0, curve), 2, `${curve} before t0`)
    assert.equal(ramp(10, curve), 2, `${curve} at t0`)
    assert.equal(ramp(15, curve), mid, `${curve} midpoint`)
    assert.equal(ramp(20, curve), 4, `${curve} at t1`)
    assert.equal(ramp(99, curve), 4, `${curve} after t1`)
  }
  assert.equal(ramp(12.5), ramp(12.5, 'smooth'), 'default curve is smooth')
})

test('helpers reject arguments that would feed Hydra garbage', () => {
  const { page } = load()
  assert.throws(() => page.ramp(0, 10, 0, 1, 'smoth'), /unknown curve 'smoth'/)
  assert.throws(() => page.ramp(10, 10, 0, 1), /t1 > t0/)
  assert.throws(() => page.ramp(0, 10, 0, NaN), /finite/)
  assert.throws(() => page.lfo(0), /period must be > 0/)
  assert.throws(() => page.at(NaN, () => {}), /finite time/)
})

test('at(t) fires once, just before the first frame whose time reaches t', () => {
  const { page, rt } = load()
  let frame = 0
  const fired = []
  page.at(0, () => fired.push([0, frame]))
  // Tenths of a second land exactly on frame 6n; several (8.3 s, 16.1 s, ...) trip Math.ceil(t * 60).
  for (let n = 1; n <= 600; n++) page.at(n / 10, () => fired.push([n, frame]))
  for (frame = 1; frame <= 3700; frame++) rt.step(DT)
  assert.equal(fired.length, 601)
  for (const [n, f] of fired) assert.equal(f, n === 0 ? 1 : 6 * n, `at(${n / 10})`)
})

test('an at() registered for a time already passed fires in the same step', () => {
  const { page, rt } = load()
  const log = []
  page.at(1, () => {
    log.push('outer')
    page.at(0.5, () => log.push('inner'))
  })
  for (let k = 0; k < 60; k++) rt.step(DT)
  assert.deepEqual(log, ['outer', 'inner'])
})

test('step refuses to render once a sketch sets speed or fps', () => {
  for (const [key, value] of [['speed', 2], ['fps', 30]]) {
    const { page, hydra, rt } = load()
    page[key] = value
    assert.throws(() => rt.step(DT), /must not set speed or fps/, key)
    assert.equal(hydra.synth.time, 0, `${key}: no frame rendered`)
  }
})
