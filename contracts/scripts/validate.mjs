#!/usr/bin/env node
// Validates every contract file against contracts/schemas and prints a table.
//
//   node scripts/validate.mjs               all checks
//   node scripts/validate.mjs --out ios     only contracts/out/ios/*.json (emitted by platform tests)
//
// Emitted files are named <schema>.<variant>.json and must pass <schema>. The
// emit root is $SELLWILD_CONTRACT_OUT when set, else contracts/out. Exit code
// is 1 when any row fails.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadSchemas, formatErrors } from './lib/schemas.mjs'
import { sha256, BASE64_STUB_CHARS } from './lib/samples.mjs'
import { CONTRACTS_DIR, SAMPLES_DIR, FIXTURES_DIR, GOLDEN_DIR, REGISTRY_PATH, outDir } from './lib/paths.mjs'

const rel = (p) => path.relative(CONTRACTS_DIR, p) || '.'
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'))
const listJson = (dir) => (fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.json') && !f.startsWith('_')).sort() : [])

/** Every `properties` entry of a schema must carry a description. */
export function undocumentedProperties(schema) {
  const missing = []
  const walk = (node, at) => {
    if (Array.isArray(node)) return node.forEach((n, i) => walk(n, `${at}/${i}`))
    if (!node || typeof node !== 'object') return
    if (node.properties && typeof node.properties === 'object') {
      for (const [k, v] of Object.entries(node.properties)) {
        if (!v || typeof v.description !== 'string' || v.description.trim() === '') missing.push(`${at}/properties/${k}`)
      }
    }
    for (const [k, v] of Object.entries(node)) walk(v, `${at}/${k}`)
  }
  walk(schema, '#')
  return missing
}

/** A fixture carries `_synthetic: true` at the top, or on its first element when it is an array. */
export function hasSyntheticMarker(value) {
  if (Array.isArray(value)) {
    if (value.length === 0 || !value[0] || typeof value[0] !== 'object' || Array.isArray(value[0])) return true
    return value[0]._synthetic === true
  }
  if (value && typeof value === 'object') return value._synthetic === true
  return true
}

function errorMatches(errors, want) {
  return (errors ?? []).some((e) => e.instancePath === want.instancePath && (want.keyword === undefined || e.keyword === want.keyword))
}

export function runValidation({ only = null, env = process.env } = {}) {
  const rows = []
  const add = (check, file, ok, detail = '') => rows.push({ check, file, ok, detail })
  const { validators, errors: compileErrors, docs } = loadSchemas()

  for (const [name, err] of Object.entries(compileErrors)) add('schema', `schemas/${name}.schema.json`, false, err)

  const validate = (schema, value) => {
    const v = validators[schema]
    if (!v) return { ok: false, errors: [], detail: `unknown schema '${schema}'` }
    const ok = v(value)
    return { ok, errors: v.errors ?? [], detail: ok ? '' : formatErrors(v.errors) }
  }

  const checkOut = (platform) => {
    const dir = path.join(outDir(env), platform)
    const files = listJson(dir)
    if (only && files.length === 0) add('out', rel(dir), false, 'no emitted files')
    for (const f of files) {
      const schema = f.split('.')[0]
      let value
      try {
        value = readJson(path.join(dir, f))
      } catch (e) {
        add('out', rel(path.join(dir, f)), false, `not JSON: ${e.message}`)
        continue
      }
      const r = validate(schema, value)
      add('out', path.join(path.relative(CONTRACTS_DIR, dir), f), r.ok, r.detail)
    }
  }

  if (only) {
    checkOut(only)
    return rows
  }

  // Schemas: compile (above) and document every property.
  for (const [name, doc] of Object.entries(docs)) {
    if (compileErrors[name]) continue
    const missing = undocumentedProperties(doc)
    add('schema', `schemas/${name}.schema.json`, missing.length === 0, missing.length ? `no description: ${missing.slice(0, 3).join(', ')}` : '')
  }

  // Samples: listed in SOURCES.json, integrity, and schema.
  const sources = readJson(path.join(SAMPLES_DIR, 'SOURCES.json')).samples
  const listed = new Set(sources.map((s) => s.file))
  for (const shape of fs.readdirSync(SAMPLES_DIR, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).sort()) {
    for (const f of fs.readdirSync(path.join(SAMPLES_DIR, shape)).sort()) {
      if (!listed.has(`${shape}/${f}`)) add('sample', `samples/${shape}/${f}`, false, 'not listed in SOURCES.json')
    }
  }
  for (const s of sources) {
    const p = path.join(SAMPLES_DIR, s.file)
    if (!fs.existsSync(p)) {
      add('sample', `samples/${s.file}`, false, 'listed in SOURCES.json but missing')
      continue
    }
    const bytes = fs.readFileSync(p)
    if (!s.truncated && sha256(bytes) !== s.sha256) {
      add('sample', `samples/${s.file}`, false, 'sha256 differs from SOURCES.json')
      continue
    }
    if (s.status === 403) {
      const ok = /<Code>AccessDenied<\/Code>/.test(bytes.toString('utf8'))
      add('sample', `samples/${s.file}`, ok, ok ? '403 AccessDenied body' : 'expected an S3 AccessDenied XML body')
      continue
    }
    if (s.kind === 'headers') {
      const ok = /^HTTP\/[0-9.]+ 200/.test(bytes.toString('utf8'))
      add('sample', `samples/${s.file}`, ok, ok ? 'response headers' : 'expected an HTTP 200 header block')
      continue
    }
    const value = JSON.parse(bytes.toString('utf8'))
    const schema = s.file.split('/')[0]
    const r = validate(schema, value)
    let detail = r.detail
    let ok = r.ok
    if (ok && s.truncated) {
      const long = bytes.toString('utf8').match(new RegExp(`data:image/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=]{${BASE64_STUB_CHARS + 1},}`))
      if (long) {
        ok = false
        detail = 'truncated sample still holds full base64 data'
      }
    }
    add('sample', `samples/${s.file}`, ok, detail)
  }

  // Fixtures: valid pass, invalid fail for the declared reason, all marked synthetic.
  for (const shape of fs.readdirSync(FIXTURES_DIR, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).sort()) {
    if (!validators[shape]) {
      add('fixture', `fixtures/${shape}`, false, `no schema named ${shape}`)
      continue
    }
    const validDir = path.join(FIXTURES_DIR, shape, 'valid')
    for (const f of listJson(validDir)) {
      const value = readJson(path.join(validDir, f))
      const r = validate(shape, value)
      const marked = hasSyntheticMarker(value)
      add('fixture', `fixtures/${shape}/valid/${f}`, r.ok && marked, marked ? r.detail : 'missing _synthetic: true')
    }
    const invalidDir = path.join(FIXTURES_DIR, shape, 'invalid')
    const expectedPath = path.join(invalidDir, '_expected-errors.json')
    const expected = fs.existsSync(expectedPath) ? readJson(expectedPath).errors : {}
    const invalidFiles = listJson(invalidDir)
    for (const f of invalidFiles) {
      const value = readJson(path.join(invalidDir, f))
      const r = validate(shape, value)
      const want = expected[f]
      let ok = !r.ok && hasSyntheticMarker(value)
      let detail = r.ok ? 'passed but must fail' : ''
      if (!want) {
        ok = false
        detail = 'no entry in _expected-errors.json'
      } else if (!r.ok && !errorMatches(r.errors, want)) {
        ok = false
        detail = `failed for another reason (want ${want.instancePath || '/'} ${want.keyword ?? ''}): ${formatErrors(r.errors)}`
      }
      add('fixture', `fixtures/${shape}/invalid/${f}`, ok, detail)
    }
    for (const f of Object.keys(expected)) {
      if (!invalidFiles.includes(f)) add('fixture', `fixtures/${shape}/invalid/_expected-errors.json`, false, `entry for missing file ${f}`)
    }
  }

  // Golden vectors: every emitted event is a valid clientFailure event.
  for (const f of listJson(GOLDEN_DIR)) {
    const doc = readJson(path.join(GOLDEN_DIR, f))
    const bad = []
    let events = 0
    for (const v of doc.vectors) {
      if (!v.expected.event) continue
      events++
      const r = validate('client-failure-event', v.expected.event)
      if (!r.ok) bad.push(`${v.name}: ${r.detail}`)
    }
    add('golden', `golden/${f}`, bad.length === 0, bad.length ? bad.slice(0, 2).join(' | ') : `${events} events valid`)
  }

  // Failure-code registry.
  const reg = validate('failure-codes', readJson(REGISTRY_PATH))
  add('registry', rel(REGISTRY_PATH), reg.ok, reg.detail)

  // Everything platform tests have emitted so far.
  const root = outDir(env)
  if (fs.existsSync(root)) {
    for (const d of fs.readdirSync(root, { withFileTypes: true }).filter((x) => x.isDirectory() && !x.name.startsWith('.'))) checkOut(d.name)
  }
  return rows
}

export function renderTable(rows) {
  const w = [8, Math.max(4, ...rows.map((r) => r.file.length)), 6]
  const line = (a, b, c, d) => `${a.padEnd(w[0])}  ${b.padEnd(w[1])}  ${c.padEnd(w[2])}  ${d}`.trimEnd()
  const out = [line('CHECK', 'FILE', 'RESULT', 'DETAIL'), line('-'.repeat(w[0]), '-'.repeat(w[1]), '-'.repeat(w[2]), '------')]
  for (const r of rows) out.push(line(r.check, r.file, r.ok ? 'PASS' : 'FAIL', r.detail))
  const failed = rows.filter((r) => !r.ok).length
  out.push('', `${rows.length - failed} passed, ${failed} failed`)
  return out.join('\n')
}

function main(argv) {
  const i = argv.indexOf('--out')
  const only = i >= 0 ? argv[i + 1] : null
  if (i >= 0 && !only) {
    process.stderr.write('usage: node scripts/validate.mjs [--out <platform>]\n')
    process.exitCode = 2
    return
  }
  const rows = runValidation({ only })
  process.stdout.write(renderTable(rows) + '\n')
  process.exitCode = rows.every((r) => r.ok) ? 0 : 1
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2))
