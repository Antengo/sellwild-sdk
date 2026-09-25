import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { CONTRACTS_DIR, REGISTRY_PATH } from '../scripts/lib/paths.mjs'
import { normalizeCode, COMPONENTS, CLIENTS } from '../reference/log-failure.mjs'
import { validateRegistry } from '../scripts/lib/registry.mjs'
import { loadSchemas, formatErrors } from '../scripts/lib/schemas.mjs'

const registry = JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8'))
const sources = JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, 'failure-codes.sources.json'), 'utf8'))
const codes = new Set(registry.map((e) => e.code))

test('the registry passes its schema and every add-code check', () => {
  const { validators } = loadSchemas()
  const ok = validators['failure-codes'](registry)
  assert.ok(ok, formatErrors(validators['failure-codes'].errors, 10))
  assert.deepEqual(validateRegistry(registry), [])
})

test('codes are unique, sorted and in the dotted format', () => {
  assert.equal(codes.size, registry.length)
  assert.deepEqual(registry.map((e) => e.code), [...registry.map((e) => e.code)].sort())
  for (const e of registry) {
    assert.equal(normalizeCode(e.code), e.code, e.code)
    assert.equal(`${e.area}.${e.operation}.${e.reason}`, e.code)
    assert.ok(COMPONENTS.includes(e.component) || (e.code === 'client.code.invalid' && e.component === 'unknown'), e.code)
    for (const c of e.clients) assert.ok(CLIENTS.includes(c), `${e.code}: ${c}`)
  }
})

test('the codes every lane depends on exist for the right clients', () => {
  const need = {
    'config.fetch.network': ['core', 'react-native', 'ios', 'android', 'widget'],
    'config.fetch.timeout': ['core', 'react-native', 'ios', 'android', 'widget'],
    'config.fetch.http': ['core', 'react-native', 'ios', 'android', 'widget'],
    'config.fetch.parse': ['core', 'react-native', 'ios', 'android', 'widget'],
    'listings.fetch.network': ['core', 'react-native', 'ios', 'android', 'widget'],
    'listings.fetch.timeout': ['core', 'react-native', 'ios', 'android', 'widget'],
    'listings.fetch.http': ['core', 'react-native', 'ios', 'android', 'widget'],
    'listings.fetch.parse': ['core', 'react-native', 'ios', 'android', 'widget'],
    'localized.fetch.network': ['ios', 'android', 'widget'],
    'localized.fetch.timeout': ['ios', 'android', 'widget'],
    'localized.fetch.http': ['ios', 'android', 'widget'],
    'localized.fetch.parse': ['ios', 'android', 'widget'],
    'widget.webview_load.http': ['widget'],
    'widget.element.exception': ['widget'],
    'widget.customelements.unsupported': ['widget'],
    'growthcode.sync.network': ['ios', 'android'],
    'growthcode.sync.http': ['ios', 'android'],
    'growthcode.sync.parse': ['ios', 'android'],
    'client.code.invalid': ['core', 'react-native', 'ios', 'android', 'widget'],
  }
  for (const [code, clients] of Object.entries(need)) {
    const e = registry.find((x) => x.code === code)
    assert.ok(e, `missing ${code}`)
    for (const c of clients) assert.ok(e.clients.includes(c), `${code} lacks client ${c}`)
  }
  // Clients no code may list: the platform is gone from this repo. origin
  // removed the Flutter SDK (df551f7) and the SDK's WebView widget and banner
  // paths (9ff579f), so no SDK client emits a bridge message or WebView code.
  for (const e of registry) assert.ok(!e.clients.includes('flutter'), `${e.code} must not list flutter`)
  const webViewOnly = registry.filter((e) => /^bridge\.(message|script)\.|^widget\.webview_/.test(e.code))
  for (const e of webViewOnly) {
    for (const c of ['core', 'react-native', 'ios', 'android']) assert.ok(!e.clients.includes(c), `${e.code} must not list ${c}`)
  }
})

test('no registry code names a no-fill or an events-transport failure', () => {
  for (const e of registry) {
    assert.doesNotMatch(e.code, /no_?fill|no_?bids|^events?\./, e.code)
  }
})

test('every phase-1 failure point maps to a registry code or a defined exclusion', () => {
  assert.equal(sources.points.length, 641)
  for (const p of sources.points) {
    const has = (p.code !== undefined) !== (p.excluded !== undefined)
    assert.ok(has, `${p.file}:${p.line} needs exactly one of code/excluded`)
    if (p.code) assert.ok(codes.has(p.code), `${p.file}:${p.line} -> unknown code ${p.code}`)
    else assert.ok(sources.exclusions[p.excluded], `${p.file}:${p.line} -> undefined exclusion ${p.excluded}`)
  }
})

test('every registry code has a source point or an `added` record', () => {
  const added = new Map(sources.added.map((a) => [a.code, a]))
  assert.equal(added.size, sources.added.length, 'a code is recorded twice in added')
  for (const a of sources.added) {
    assert.ok(codes.has(a.code), `added ${a.code} is not in the registry`)
    assert.match(a.date, /^\d{4}-\d{2}-\d{2}$/, a.code)
    assert.ok(typeof a.note === 'string' && a.note.length > 10, `${a.code} needs a note`)
  }
  const used = new Set(sources.points.filter((p) => p.code).map((p) => p.code))
  for (const e of registry) assert.ok(used.has(e.code) || added.has(e.code), `${e.code} has no source`)
})

// The platform a phase-1 point's file belongs to (the RN native bridges are
// iOS and Android code).
function platformOf(point) {
  const file = point.file.replace(/^sellwild-sdk\//, '')
  if (point.unit.startsWith('widget-')) return 'widget'
  if (file.startsWith('react-native/ios/')) return 'ios'
  if (file.startsWith('react-native/android/')) return 'android'
  if (file.startsWith('react-native/')) return 'react-native'
  for (const p of ['core', 'ios', 'android', 'flutter']) if (file.startsWith(`${p}/`)) return p
  return null
}

test('a point mapped to a code comes from a platform that emits it', () => {
  const byCode = new Map(registry.map((e) => [e.code, e]))
  const wrong = []
  for (const p of sources.points.filter((x) => x.code)) {
    const platform = platformOf(p)
    assert.ok(platform, `${p.file}: no platform`)
    // core points also run inside react-native, and the other way round.
    const ok = platform === 'core' || platform === 'react-native'
      ? byCode.get(p.code).clients.some((c) => c === 'core' || c === 'react-native')
      : byCode.get(p.code).clients.includes(platform)
    if (!ok) wrong.push(`${p.file}:${p.line} ${p.code} (${platform} is not a client)`)
  }
  assert.deepEqual(wrong, [])
})
