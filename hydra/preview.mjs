#!/usr/bin/env node
// Live sketch preview: `node preview.mjs [port]`, then open http://127.0.0.1:<port>/
import http from 'node:http'
import { readFile, readdir } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(fileURLToPath(import.meta.url))
const PORT = Number(process.argv[2] || 8642)
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

const routes = {
  '/': 'preview.html',
  '/hydra-synth.js': 'node_modules/hydra-synth/dist/hydra-synth.js',
  '/lib/runtime.js': 'lib/runtime.js',
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x').pathname
  try {
    if (url === '/api/sketches') {
      res.setHeader('content-type', types['.json'])
      return res.end(JSON.stringify(await sketches()))
    }
    const m = url.match(/^\/sketches\/([a-z0-9_]+)\.js$/)
    const file = routes[url] ?? (m && `sketches/${m[1]}.js`)
    if (!file) throw Object.assign(new Error('not found'), { code: 'ENOENT' })
    res.setHeader('content-type', types[file.slice(file.lastIndexOf('.'))])
    res.setHeader('cache-control', 'no-store') // edit a sketch, reload the page
    res.end(await readFile(join(ROOT, file)))
  } catch (e) {
    res.statusCode = e.code === 'ENOENT' ? 404 : 500
    res.end(String(e.message))
  }
}).listen(PORT, '127.0.0.1', () => console.log(`hydra preview: http://127.0.0.1:${PORT}/`))
