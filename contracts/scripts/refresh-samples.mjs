#!/usr/bin/env node
// Re-captures the real samples listed in scripts/lib/samples.mjs.
//
//   CONTRACTS_LIVE=1 node scripts/refresh-samples.mjs
//
// GET only, and only to allowlisted hosts. events.sellwild.com and every
// other method are refused before any request is made. Redirects are not
// followed. Never run from the unit suite: the tests cover the guard only.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { SAMPLE_SPECS, prepareSample, sourcesDocument } from './lib/samples.mjs'
import { SAMPLES_DIR } from './lib/paths.mjs'

export const ALLOWED = [
  { host: 'widget.sellwild.com', pathPrefix: '/app/' },
  { host: 'cache.sellwild.com', pathPrefix: '/' },
  { host: 'sellwild-sports-cache.s3.us-east-1.amazonaws.com', pathPrefix: '/' },
]
export const BLOCKED_HOSTS = ['events.sellwild.com']

/** Throws unless (url, method) is a GET to an allowlisted https URL. Returns the parsed URL. */
export function assertAllowedRequest(url, method = 'GET') {
  if (method !== 'GET') throw new Error(`refused: only GET is allowed (got ${method})`)
  let u
  try {
    u = new URL(url)
  } catch {
    throw new Error(`refused: not a URL: ${url}`)
  }
  const host = u.hostname.toLowerCase()
  if (BLOCKED_HOSTS.some((b) => host === b || host.endsWith(`.${b}`))) throw new Error(`refused: ${host} is never contacted`)
  if (u.protocol !== 'https:') throw new Error(`refused: https only (got ${u.protocol})`)
  if (u.username || u.password) throw new Error('refused: credentials in URL')
  if (u.port !== '') throw new Error(`refused: explicit port ${u.port}`)
  const rule = ALLOWED.find((a) => a.host === host)
  if (!rule) throw new Error(`refused: host ${host} is not on the allowlist`)
  if (!u.pathname.startsWith(rule.pathPrefix)) throw new Error(`refused: ${host}${u.pathname} is outside ${rule.pathPrefix}`)
  return u
}

/** One guarded GET. Redirects are returned as errors, never followed. */
export async function guardedGet(url, fetchImpl) {
  assertAllowedRequest(url, 'GET')
  const res = await fetchImpl(url, { method: 'GET', redirect: 'manual' })
  if (res.status >= 300 && res.status < 400) throw new Error(`refused: redirect from ${url} is not followed`)
  return res
}

function headerBlock(res) {
  const lines = [`HTTP/1.1 ${res.status}`]
  for (const [k, v] of res.headers) lines.push(`${k}: ${v}`)
  return lines.join('\n') + '\n'
}

/**
 * Fetch every refreshable sample. Returns the new SOURCES entries, the files
 * whose original bytes changed, and the files whose HTTP status changed (those
 * are not overwritten). `write: false` keeps the disk untouched (tests).
 */
export async function refresh({ fetchImpl = globalThis.fetch, env = process.env, write = true, dir = SAMPLES_DIR, today = new Date().toISOString().slice(0, 10) } = {}) {
  if (env.CONTRACTS_LIVE !== '1') throw new Error('refused: set CONTRACTS_LIVE=1 to hit the network')
  const previous = fs.existsSync(path.join(dir, 'SOURCES.json'))
    ? Object.fromEntries(JSON.parse(fs.readFileSync(path.join(dir, 'SOURCES.json'), 'utf8')).samples.map((s) => [s.file, s]))
    : {}
  const entries = []
  const changed = []
  const statusChanged = []
  const responses = new Map()
  for (const spec of SAMPLE_SPECS) {
    if (spec.refreshable === false) {
      if (previous[spec.file]) entries.push(previous[spec.file])
      continue
    }
    let res = responses.get(spec.url)
    if (!res) {
      const r = await guardedGet(spec.url, fetchImpl)
      res = { status: r.status, headers: r.headers, bytes: Buffer.from(await r.arrayBuffer()) }
      responses.set(spec.url, res)
    }
    if (res.status !== spec.status) {
      // A 200 turning into 403 (or back) is drift for a person to look at, not a file to overwrite.
      statusChanged.push({ file: spec.file, expected: spec.status, got: res.status })
      if (previous[spec.file]) entries.push(previous[spec.file])
      continue
    }
    const body = spec.kind === 'headers' ? Buffer.from(headerBlock(res)) : res.bytes
    const { bytes, entry } = prepareSample({ ...spec, status: res.status }, body, today)
    if (previous[spec.file]?.sha256 !== entry.sha256) changed.push(spec.file)
    entries.push(entry)
    if (write) {
      fs.mkdirSync(path.dirname(path.join(dir, spec.file)), { recursive: true })
      fs.writeFileSync(path.join(dir, spec.file), bytes)
    }
  }
  if (write) fs.writeFileSync(path.join(dir, 'SOURCES.json'), JSON.stringify(sourcesDocument(entries), null, 2) + '\n')
  return { entries, changed, statusChanged }
}

async function main() {
  try {
    const { changed, statusChanged } = await refresh()
    process.stdout.write(changed.length ? `changed:\n${changed.map((f) => `  ${f}`).join('\n')}\n` : 'no sample changed\n')
    for (const x of statusChanged) process.stdout.write(`status changed (not written): ${x.file} ${x.expected} -> ${x.got}\n`)
    if (statusChanged.length) process.exitCode = 1
  } catch (e) {
    process.stderr.write(`${e.message}\n`)
    process.exitCode = 1
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main()
