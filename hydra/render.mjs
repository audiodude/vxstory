#!/usr/bin/env node
// Render a hydra preset to video. Headless Chromium steps the sketch exactly 1/60 s per
// frame (render.html + lib/runtime.js) and streams raw RGBA over a WebSocket into ffmpeg.
// Any sketch error, stall or signal aborts the render and leaves no output file.
import http from 'node:http'
import { spawn } from 'node:child_process'
import { readFile, rename, rm } from 'node:fs/promises'
import { dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'
import { chromium } from 'playwright'
import { WebSocketServer } from 'ws'

const ROOT = dirname(fileURLToPath(import.meta.url))
const USAGE = 'usage: node render.mjs --preset <path.json> --out <file.mp4|file.avi> [--duration S] [--res 1920x1080]\n' +
  '                        [--sketch-dir DIR] [--stall-sec 60] [--allow-software]'
const GPU_ARGS = ['--use-angle=vulkan', '--enable-gpu', '--ignore-gpu-blocklist', '--enable-features=Vulkan']
// The output goes to <out>.tmp first, so the muxer must be named explicitly.
const CODECS = {
  '.mp4': ['-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p', '-f', 'mp4'],
  '.avi': ['-c:v', 'mjpeg', '-q:v', '2', '-pix_fmt', 'yuvj420p', '-f', 'avi'], // radio's intermediate
}
const STATIC = {
  '/': ['render.html', 'text/html'],
  '/hydra-synth.js': ['node_modules/hydra-synth/dist/hydra-synth.js', 'text/javascript'],
  '/lib/runtime.js': ['lib/runtime.js', 'text/javascript'],
}

const die = (msg) => {
  console.error(`render: ${msg}`)
  process.exit(1)
}

// ---- arguments and preset (nothing to clean up yet) ----
let opts
try {
  opts = parseArgs({ options: {
    preset: { type: 'string' },
    out: { type: 'string' },
    duration: { type: 'string' },
    res: { type: 'string', default: '1920x1080' },
    'sketch-dir': { type: 'string', default: join(ROOT, 'sketches') },
    'stall-sec': { type: 'string', default: '60' },
    'allow-software': { type: 'boolean', default: false },
  } }).values
} catch (e) {
  die(`${e.message}\n${USAGE}`)
}
if (!opts.preset || !opts.out) die(USAGE)
const codec = CODECS[extname(opts.out).toLowerCase()]
if (!codec) die(`--out must end in .mp4 or .avi: ${opts.out}`)
const res = /^(\d+)x(\d+)$/.exec(opts.res)
const [width, height] = res ? [Number(res[1]), Number(res[2])] : []
if (!res || width % 2 || height % 2 || !width || !height) die(`--res must be WxH with even sizes: ${opts.res}`)
const stallSec = Number(opts['stall-sec'])
if (!(stallSec > 0)) die(`--stall-sec must be > 0: ${opts['stall-sec']}`)

let preset
try {
  preset = JSON.parse(await readFile(opts.preset, 'utf8'))
} catch (e) {
  die(`can't read preset ${opts.preset}: ${e.message}`)
}
if (preset.model !== 'hydra') die(`preset model is ${JSON.stringify(preset.model)}, not "hydra"`)
if (!/^[a-z0-9_]+$/.test(preset.sketch ?? '')) die(`preset needs a "sketch" name: ${opts.preset}`)
if (!Number.isInteger(preset.seed)) die(`preset seed must be an integer: ${preset.seed}`)
if (!(preset.duration_sec > 0)) die(`preset duration_sec must be > 0: ${preset.duration_sec}`)
// --duration sets the frame count only; the sketch's `dur` stays the preset's, so a short
// proof render is exactly the opening of the full piece.
const duration = opts.duration === undefined ? preset.duration_sec : Number(opts.duration)
if (!(duration > 0)) die(`--duration must be > 0: ${opts.duration}`)
const frames = Math.round(duration * 60)
const sketchPath = join(resolve(opts['sketch-dir']), `${preset.sketch}.js`)
const sketchCode = await readFile(sketchPath, 'utf8').catch(() => die(`sketch not found: ${sketchPath}`))

// ---- render ----
const out = resolve(opts.out)
const tmp = `${out}.tmp`
let ffmpeg, browser, server
let ending = false // set once by fail() or by finish(); stops every other path
let received = 0
let lastFrameAt = Date.now()
const started = Date.now()

async function cleanup() {
  clearInterval(watchdog)
  if (ffmpeg && ffmpeg.exitCode === null && ffmpeg.signalCode === null) {
    ffmpeg.kill('SIGKILL')
    await ffmpegExit
  }
  await rm(tmp, { force: true })
  await Promise.race([browser?.close(), new Promise((r) => setTimeout(r, 5000))])
  server?.closeAllConnections()
  server?.close()
}

async function fail(msg, code = 1) {
  if (ending) return
  ending = true
  console.error(`render: FAILED: ${msg}`)
  await cleanup()
  process.exit(code)
}

async function finish() {
  if (ending) return
  if (received !== frames) return fail(`page delivered ${received} frames, expected ${frames}`)
  ending = true
  clearInterval(watchdog)
  ffmpeg.stdin.end()
  const { code } = await ffmpegExit
  if (code !== 0) {
    ending = false
    return fail(`ffmpeg exited ${code}: ${ffmpegErr.trim()}`)
  }
  await rename(tmp, out)
  await browser.close()
  server.closeAllConnections()
  server.close()
  console.log(`render: wrote ${out} (${frames} frames in ${((Date.now() - started) / 1000).toFixed(1)} s)`)
  process.exit(0)
}

process.on('SIGINT', () => fail('interrupted (SIGINT)', 130))
process.on('SIGTERM', () => fail('terminated (SIGTERM)', 143))

const watchdog = setInterval(() => {
  if (Date.now() - lastFrameAt > stallSec * 1000) fail(`no frame for ${stallSec} s (hung sketch or GPU?)`)
}, 250)

let lastLog = Date.now()
function progress() {
  const now = Date.now()
  if (now - lastLog < 10_000) return
  lastLog = now
  const fps = received / ((now - started) / 1000)
  const eta = Math.round((frames - received) / fps)
  console.log(`render: frame ${received}/${frames} · ${fps.toFixed(1)} fps · eta ${Math.floor(eta / 60)}m${String(eta % 60).padStart(2, '0')}s`)
}

ffmpeg = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y',
  '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', `${width}x${height}`, '-framerate', '60', '-i', 'pipe:0',
  '-vf', 'vflip', '-an', ...codec, tmp], { stdio: ['pipe', 'ignore', 'pipe'] })
let ffmpegErr = ''
ffmpeg.stderr.on('data', (d) => (ffmpegErr += d))
const ffmpegExit = new Promise((r) => ffmpeg.on('exit', (code, signal) => r({ code, signal })))
ffmpeg.on('error', (e) => fail(`can't run ffmpeg: ${e.message}`))
ffmpeg.stdin.on('error', (e) => fail(`ffmpeg input: ${e.message} ${ffmpegErr.trim()}`))
ffmpegExit.then(({ code }) => fail(`ffmpeg exited early (${code}): ${ffmpegErr.trim()}`))

server = http.createServer(async (req, res) => {
  const path = new URL(req.url, 'http://x').pathname
  if (path === '/sketch.js') {
    res.setHeader('content-type', 'text/javascript')
    return res.end(sketchCode)
  }
  const route = STATIC[path]
  if (!route) {
    res.statusCode = 404
    return res.end()
  }
  res.setHeader('content-type', route[1])
  res.end(await readFile(join(ROOT, route[0])))
})
new WebSocketServer({ server }).on('connection', (ws) => {
  ws.on('message', (data, isBinary) => {
    if (ending) return
    if (!isBinary) {
      const msg = JSON.parse(data)
      return msg.error ? fail(`sketch error: ${msg.error}`) : finish()
    }
    if (data.length !== width * height * 4) return fail(`frame of ${data.length} bytes, expected ${width * height * 4}`)
    received++
    lastFrameAt = Date.now()
    ffmpeg.stdin.write(data, (err) => err || ws.send('ack'))
    progress()
  })
})
await new Promise((r) => server.listen(0, '127.0.0.1', r))

browser = await chromium.launch({ headless: true, args: GPU_ARGS, handleSIGINT: false, handleSIGTERM: false, handleSIGHUP: false })
browser.on('disconnected', () => fail('Chromium exited'))
const page = await browser.newPage()
page.on('pageerror', (e) => fail(`page error: ${e.stack || e}`))
page.on('crash', () => fail('page crashed'))
// Browser-side GL errors ("WebGL: INVALID_OPERATION: …") never reach the page's console hooks.
// Other warnings are driver chatter, e.g. "GPU stall due to ReadPixels" on every readback.
page.on('console', (m) => {
  if (m.type() === 'error' || (m.type() === 'warning' && m.text().startsWith('WebGL:'))) fail(`console ${m.type()}: ${m.text()}`)
})

const renderer = await page.evaluate(() => {
  const gl = document.createElement('canvas').getContext('webgl')
  if (!gl) return null
  const info = gl.getExtension('WEBGL_debug_renderer_info')
  return gl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : gl.RENDERER)
})
if (!renderer) await fail('no WebGL in Chromium')
if (/swiftshader|llvmpipe|softpipe/i.test(renderer) && !opts['allow-software']) {
  await fail(`software WebGL renderer (${renderer}): ~100x slower and different output; pass --allow-software to accept`)
}
console.log(`render: ${preset.sketch} seed ${preset.seed} · ${frames} frames at ${width}x${height} · ${renderer} → ${out}`)
const query = new URLSearchParams({ sketch: preset.sketch, seed: preset.seed, dur: preset.duration_sec, frames, w: width, h: height })
await page.goto(`http://127.0.0.1:${server.address().port}/?${query}`, { waitUntil: 'commit' })
