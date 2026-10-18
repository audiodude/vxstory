#!/usr/bin/env node
// Live sketch preview: `node preview.mjs [port] [--audio-dir DIR]`, then open http://127.0.0.1:<port>/
// With --audio-dir, songs in DIR can drive audio-reactive sketches (features from lib/audio.mjs).
import http from 'node:http'
import { createReadStream } from 'node:fs'
import { readFile, readdir, stat } from 'node:fs/promises'
import { basename, dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'
import { audioFeatures } from './lib/audio.mjs'

const ROOT = dirname(fileURLToPath(import.meta.url))
const { values, positionals } = parseArgs({ allowPositionals: true, options: { 'audio-dir': { type: 'string' } } })
const PORT = Number(positionals[0] || 8642)
const AUDIO_DIR = values['audio-dir'] ? resolve(values['audio-dir']) : null
const AUDIO_TYPES = { '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.flac': 'audio/flac', '.ogg': 'audio/ogg', '.m4a': 'audio/mp4' }
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' }

async function sketches() {
  const names = (await readdir(join(ROOT, 'sketches'))).filter((f) => f.endsWith('.js')).map((f) => f.slice(0, -3))
  return Promise.all(names.sort().map(async (name) => {
    try {
      const p = JSON.parse(await readFile(join(ROOT, 'presets', `${name}.json`), 'utf8'))
      return { name, seed: p.seed, duration_sec: p.duration_sec }
    } catch {
      return { name, seed: 1, duration_sec: 300 }
    }
  }))
}

async function songs() {
  if (!AUDIO_DIR) return []
  return (await readdir(AUDIO_DIR)).filter((f) => AUDIO_TYPES[extname(f).toLowerCase()]).sort()
}

// A song name from the URL, confined to AUDIO_DIR.
function songPath(name) {
  if (!AUDIO_DIR || name !== basename(name) || !AUDIO_TYPES[extname(name).toLowerCase()]) {
    throw Object.assign(new Error('no such song'), { code: 'ENOENT' })
  }
  return join(AUDIO_DIR, name)
}

const featureCache = new Map() // path -> {mtime, promise}
async function features(path) {
  const { mtimeMs } = await stat(path)
  const hit = featureCache.get(path)
  if (hit?.mtime === mtimeMs) return hit.promise
  const promise = audioFeatures(path).then((f) => JSON.stringify(f))
  featureCache.set(path, { mtime: mtimeMs, promise })
  promise.catch(() => featureCache.delete(path))
  return promise
}

// Range support so the page's <audio> element can seek.
async function sendAudio(req, res, path) {
  const { size } = await stat(path)
  res.setHeader('content-type', AUDIO_TYPES[extname(path).toLowerCase()])
  res.setHeader('accept-ranges', 'bytes')
  const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? '')
  if (!m || (!m[1] && !m[2])) {
    res.setHeader('content-length', size)
    return createReadStream(path).pipe(res)
  }
  const start = m[1] ? Number(m[1]) : size - Number(m[2])
  const end = m[1] && m[2] ? Math.min(Number(m[2]), size - 1) : size - 1
  if (start > end || start >= size) {
    res.statusCode = 416
    res.setHeader('content-range', `bytes */${size}`)
    return res.end()
  }
  res.statusCode = 206
  res.setHeader('content-range', `bytes ${start}-${end}/${size}`)
  res.setHeader('content-length', end - start + 1)
  createReadStream(path, { start, end }).pipe(res)
}

const routes = {
  '/': 'preview.html',
  '/hydra-synth.js': 'node_modules/hydra-synth/dist/hydra-synth.js',
  '/lib/runtime.js': 'lib/runtime.js',
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x')
  const path = url.pathname
  try {
    if (path === '/api/sketches' || path === '/api/songs') {
      res.setHeader('content-type', types['.json'])
      return res.end(JSON.stringify(path === '/api/songs' ? await songs() : await sketches()))
    }
    if (path === '/api/features') {
      res.setHeader('content-type', types['.json'])
      return res.end(await features(songPath(url.searchParams.get('song') ?? '')))
    }
    if (path === '/audio') return await sendAudio(req, res, songPath(url.searchParams.get('song') ?? ''))
    const m = path.match(/^\/sketches\/([a-z0-9_]+)\.js$/)
    const file = routes[path] ?? (m && `sketches/${m[1]}.js`)
    if (!file) throw Object.assign(new Error('not found'), { code: 'ENOENT' })
    res.setHeader('content-type', types[file.slice(file.lastIndexOf('.'))])
    res.setHeader('cache-control', 'no-store') // edit a sketch, reload the page
    res.end(await readFile(join(ROOT, file)))
  } catch (e) {
    res.statusCode = e.code === 'ENOENT' ? 404 : 500
    res.end(String(e.message))
  }
}).listen(PORT, '127.0.0.1', () => console.log(`hydra preview: http://127.0.0.1:${PORT}/` + (AUDIO_DIR ? ` · songs from ${AUDIO_DIR}` : '')))
