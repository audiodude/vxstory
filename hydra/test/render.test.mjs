// End-to-end: render.mjs drives GPU Chromium and ffmpeg on fixture sketches at 320x180.
import { after, test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync, spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { once } from 'node:events'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { setTimeout as sleep } from 'node:timers/promises'

const RENDER = new URL('../render.mjs', import.meta.url).pathname
const work = mkdtempSync(join(tmpdir(), 'hydra-test-'))
const SKETCHES = join(work, 'sketches')
after(() => rmSync(work, { recursive: true, force: true }))

const loseContext = "document.getElementById('c').getContext('webgl').getExtension('WEBGL_lose_context').loseContext()"
const FIXTURES = {
  moving: 'osc(10 + rand() * 40, 0.1, 1.2).rotate(() => time * 0.3).out()',
  arc: 'osc(() => 4 + 40 * prog(), 0.1, 1).out()',
  halves: "setFunction({ name: 'halves', type: 'src', inputs: [], glsl: 'return vec4(step(0.5, _st.y), 0.0, 0.0, 1.0);' })\nhalves().out()",
  glsl: "setFunction({ name: 'broken', type: 'src', inputs: [], glsl: 'return vec4(nope);' })\nbroken().out()",
  body: "throw new Error('sketch body blew up')",
  param: "osc(() => { throw new Error('param blew up') }).out()",
  curve: "osc(() => ramp(0, 1, 10, 20, 'smoth')).out()",
  update: "osc(10).out()\nupdate = () => { throw new Error('update blew up') }",
  speed: 'speed = 2\nosc(10).out()',
  fps: 'fps = 30\nosc(10).out()',
  lost: `osc(10).out()\nat(0.1, () => ${loseContext})`,
  hang: 'osc(10).out()\nat(0.1, () => { for (;;) {} })',
}
mkdirSync(SKETCHES)
for (const [name, code] of Object.entries(FIXTURES)) writeFileSync(join(SKETCHES, `${name}.js`), code)

function preset(sketch, seed, duration_sec) {
  const path = join(work, `${sketch}-${seed}-${duration_sec}.json`)
  writeFileSync(path, JSON.stringify({ model: 'hydra', sketch, seed, duration_sec }))
  return path
}

function args(sketch, file, { seed = 7, duration_sec = 0.5, extra = [] } = {}) {
  return [RENDER, '--preset', preset(sketch, seed, duration_sec), '--out', file,
          '--res', '320x180', '--sketch-dir', SKETCHES, ...extra]
}

function render(sketch, out, opts) {
  const file = join(work, out)
  const r = spawnSync(process.execPath, args(sketch, file, opts), { encoding: 'utf8', timeout: 60_000 })
  return { status: r.status, stderr: r.stderr, file }
}

// Decoded-frame hashes. Hash tests use .avi: MJPEG is intra-only, so a frame's bytes depend on that frame alone.
const frameHashes = (file) =>
  execFileSync('ffmpeg', ['-v', 'error', '-i', file, '-f', 'framemd5', '-'], { encoding: 'utf8' })
    .split('\n').filter((l) => l && !l.startsWith('#')).map((l) => l.split(',').pop().trim())

const noOutput = (file) => !existsSync(file) && !existsSync(`${file}.tmp`)

test('the same seed renders identical frames; another seed renders different ones', () => {
  const a = render('moving', 'seed-a.avi')
  const b = render('moving', 'seed-b.avi')
  const c = render('moving', 'seed-c.avi', { seed: 8 })
  for (const r of [a, b, c]) assert.equal(r.status, 0, r.stderr)
  const [ha, hb, hc] = [a, b, c].map((r) => frameHashes(r.file))
  assert.equal(ha.length, 30)
  assert.deepEqual(hb, ha)
  assert.ok(hc.every((h, i) => h !== ha[i]), 'seed 8 differs from seed 7 on every frame')
})

test('--duration sets the frame count without stretching the arc', () => {
  const short = render('arc', 'arc-1s.avi', { duration_sec: 4, extra: ['--duration', '1'] })
  const long = render('arc', 'arc-2s.avi', { duration_sec: 4, extra: ['--duration', '2'] })
  for (const r of [short, long]) assert.equal(r.status, 0, r.stderr)
  const hs = frameHashes(short.file)
  assert.equal(hs.length, 60)
  assert.deepEqual(frameHashes(long.file).slice(0, 60), hs)
})

for (const ext of ['mp4', 'avi']) {
  test(`a --duration 2 render has exactly 120 frames (.${ext})`, () => {
    const r = render('moving', `count.${ext}`, { extra: ['--duration', '2'] })
    assert.equal(r.status, 0, r.stderr)
    const n = execFileSync('ffprobe', ['-v', 'error', '-count_frames', '-select_streams', 'v:0',
      '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', r.file], { encoding: 'utf8' })
    assert.equal(Number(n), 120)
  })
}

test('frames come out right side up', () => {
  // Hydra's _st.y grows downward: the browser shows step(0.5, _st.y) red on the bottom half.
  const r = render('halves', 'halves.avi')
  assert.equal(r.status, 0, r.stderr)
  const px = execFileSync('ffmpeg', ['-v', 'error', '-i', r.file, '-frames:v', '1',
    '-vf', 'scale=1:2:flags=area', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'])
  assert.ok(px[0] < 40 && px[3] > 200, `top rgb ${[...px.subarray(0, 3)]}, bottom rgb ${[...px.subarray(3)]}`)
})

const BROKEN = [
  ['glsl', 'a GLSL compile error', /shader compile failed/],
  ['body', 'a throwing sketch body', /sketch body blew up/],
  ['param', 'a throwing parameter function', /param blew up/],
  ['curve', 'helper misuse', /unknown curve 'smoth'/],
  ['update', 'a throwing update()', /update blew up/],
  ['speed', 'speed = 2', /must not set speed or fps/],
  ['fps', 'fps = 30', /must not set speed or fps/],
  ['lost', 'a lost WebGL context', /context lost/i],
  ['hang', 'a hung page', /no frame for 2 s/, ['--stall-sec', '2']],
]
for (const [sketch, what, cause, extra] of BROKEN) {
  test(`fails loudly on ${what}, leaving no output`, () => {
    const r = render(sketch, `${sketch}.avi`, { extra })
    assert.notEqual(r.status, 0)
    assert.match(r.stderr, cause)
    assert.ok(noOutput(r.file), 'no output or .tmp left behind')
  })
}

test('SIGTERM mid-render exits non-zero and leaves no output', async () => {
  const file = join(work, 'term.avi')
  const child = spawn(process.execPath, args('moving', file, { duration_sec: 600 }), { stdio: 'ignore' })
  const exited = once(child, 'exit')
  for (let i = 0; i < 300 && !(existsSync(`${file}.tmp`) && statSync(`${file}.tmp`).size > 0); i++) await sleep(50)
  assert.ok(existsSync(`${file}.tmp`), 'frames were flowing before the signal')
  child.kill('SIGTERM')
  const [code] = await exited
  assert.equal(code, 143)
  assert.ok(noOutput(file), 'no output or .tmp left behind')
})
