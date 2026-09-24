// The expectation files cover every app-config and listings input, and every
// knownDrift entry names a real platform and a declared field.

import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { CONTRACTS_DIR } from '../scripts/lib/paths.mjs'

const PLATFORMS = ['core', 'react-native', 'ios', 'android', 'flutter', 'widget']
const read = (p) => JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, p), 'utf8'))
const jsonIn = (dir) => fs.readdirSync(path.join(CONTRACTS_DIR, dir)).filter((f) => f.endsWith('.json') && !f.startsWith('_')).map((f) => `${dir}/${f}`)

for (const [file, inputs] of [
  ['expectations/app-config.expected.json', [...jsonIn('samples/app-config'), ...jsonIn('fixtures/app-config/valid')]],
  ['expectations/listings-response.expected.json', [...jsonIn('samples/listings-response'), ...jsonIn('fixtures/listings-response/valid')]],
]) {
  const doc = read(file)

  test(`${file}: one case per sample and valid fixture`, () => {
    assert.deepEqual(doc.cases.map((c) => c.file).sort(), inputs.sort())
  })

  test(`${file}: every expected value is a declared field`, () => {
    for (const c of doc.cases) {
      assert.deepEqual(Object.keys(c.expected).sort(), Object.keys(doc.fields).sort(), c.file)
    }
    for (const [name, f] of Object.entries(doc.fields)) {
      assert.ok(f.meaning.length > 10, name)
      for (const p of f.platforms) assert.ok(PLATFORMS.includes(p), `${name}: ${p}`)
    }
  })

  test(`${file}: knownDrift names a platform held to a field it mentions`, () => {
    for (const c of doc.cases) {
      for (const [platform, text] of Object.entries(c.knownDrift)) {
        assert.ok(PLATFORMS.includes(platform), `${c.file}: ${platform}`)
        const named = Object.keys(doc.fields).filter((f) => text.includes(`${f}:`) || text.startsWith(f))
        const s2s = file.includes('app-config') && text.includes('S2S_CONFIG:')
        assert.ok(named.length > 0 || s2s, `${c.file} ${platform}: drift text names no field: ${text}`)
      }
    }
  })
}

test('app-config expectations pin the verified weatherbug drift', () => {
  const doc = read('expectations/app-config.expected.json')
  const wb = doc.cases.find((c) => c.file === 'samples/app-config/weatherbug_weatherbug-weatherbug.json')
  assert.deepEqual(wb.expected.iabCats, ['IAB15'])
  assert.deepEqual(wb.expected.mobileZids, { shared: ['weatherbug-mobile-300x250'], ios: ['weatherbug-mobile-ios'], android: ['weatherbug-mobile-android'] })
  assert.equal(wb.expected.adRefreshIntervalMs, 30000)
  assert.deepEqual(wb.expected.adStack.resolved, { 43: 'prebidOnly', 280: 'prebidOnly', 999: 'prebidOnly' })
  assert.equal(wb.expected.eventsEnabled, true)
  assert.equal(wb.expected.failuresSampleRate, 1)
  for (const p of ['ios', 'android', 'flutter']) assert.match(wb.knownDrift[p], /iabCats:/)
  assert.match(wb.knownDrift.flutter, /mobileZids:/)
  assert.match(wb.knownDrift.android, /"LAYOUT"/)
})

test('listings expectations pin the Flutter strict-cast drift on real caches', () => {
  const doc = read('expectations/listings-response.expected.json')
  const bh = doc.cases.find((c) => c.file === 'samples/listings-response/bargainhunter.json')
  assert.equal(bh.expected.items, 10)
  assert.match(bh.knownDrift.flutter, /throws/)
  const loc = doc.cases.find((c) => c.file === 'fixtures/listings-response/valid/rpc-envelope.json')
  assert.deepEqual(loc.knownDrift, {})
})
