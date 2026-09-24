import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { CONTRACTS_DIR, REGISTRY_PATH } from '../scripts/lib/paths.mjs'
import { normalizeCode, COMPONENTS, CLIENTS } from '../reference/log-failure.mjs'

const registry = JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8'))
const sources = JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, 'failure-codes.sources.json'), 'utf8'))
const codes = new Set(registry.map((e) => e.code))

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
    'config.fetch.network': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
    'config.fetch.timeout': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
    'config.fetch.http': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
    'config.fetch.parse': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
    'listings.fetch.network': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
    'listings.fetch.timeout': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
    'listings.fetch.http': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
    'listings.fetch.parse': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
    'localized.fetch.network': ['ios', 'android', 'widget'],
    'localized.fetch.timeout': ['ios', 'android', 'widget'],
    'localized.fetch.http': ['ios', 'android', 'widget'],
    'localized.fetch.parse': ['ios', 'android', 'widget'],
    'widget.webview_load.network': ['react-native', 'ios', 'android', 'flutter'],
    'bridge.script.exception': ['react-native', 'ios', 'android', 'flutter'],
    'bridge.message.parse': ['react-native', 'ios', 'android', 'flutter'],
    'widget.element.exception': ['widget'],
    'widget.customelements.unsupported': ['widget'],
    'growthcode.sync.network': ['ios', 'android'],
    'growthcode.sync.http': ['ios', 'android'],
    'growthcode.sync.parse': ['ios', 'android'],
    'client.code.invalid': ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'],
  }
  for (const [code, clients] of Object.entries(need)) {
    const e = registry.find((x) => x.code === code)
    assert.ok(e, `missing ${code}`)
    for (const c of clients) assert.ok(e.clients.includes(c), `${code} lacks client ${c}`)
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

test('every registry code has a source point or is a required addition', () => {
  const added = new Set(['client.code.invalid', 'listings.fetch.timeout', 'localized.fetch.timeout', 'widget.webview_process.exception', 'growthcode.sync.timeout'])
  const used = new Set(sources.points.filter((p) => p.code).map((p) => p.code))
  for (const e of registry) assert.ok(used.has(e.code) || added.has(e.code), `${e.code} has no source`)
})
