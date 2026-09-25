// The expectation files cover every app-config and listings input, and every
// drift entry (expectations/drift/<platform>.json) names a real case and a
// field that platform is held to.

import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { CONTRACTS_DIR } from '../scripts/lib/paths.mjs'

const PLATFORMS = ['core', 'react-native', 'ios', 'android', 'flutter', 'widget']
// The widget keeps its drift in sellwild-widget/contracts.
const DRIFT_PLATFORMS = ['android', 'core', 'flutter', 'ios', 'react-native']
const read = (p) => JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, p), 'utf8'))
const jsonIn = (dir) => fs.readdirSync(path.join(CONTRACTS_DIR, dir)).filter((f) => f.endsWith('.json') && !f.startsWith('_')).map((f) => `${dir}/${f}`)

const DOCS = {
  'app-config': [...jsonIn('samples/app-config'), ...jsonIn('fixtures/app-config/valid')],
  'listings-response': [...jsonIn('samples/listings-response'), ...jsonIn('fixtures/listings-response/valid')],
}
const drift = Object.fromEntries(DRIFT_PLATFORMS.map((p) => [p, read(`expectations/drift/${p}.json`)]))

// Fields a drift text names: "field:" anywhere, or the text starts with it.
const namedFields = (doc, text) => Object.keys(doc.fields).filter((f) => text.includes(`${f}:`) || text.startsWith(f))

for (const [name, inputs] of Object.entries(DOCS)) {
  const file = `expectations/${name}.expected.json`
  const doc = read(file)

  test(`${file}: one case per sample and valid fixture`, () => {
    assert.deepEqual(doc.cases.map((c) => c.file).sort(), [...inputs].sort())
  })

  test(`${file}: every expected value is a declared field, and drift lives in drift/`, () => {
    for (const c of doc.cases) {
      assert.deepEqual(Object.keys(c).sort(), ['expected', 'file'], c.file)
      assert.deepEqual(Object.keys(c.expected).sort(), Object.keys(doc.fields).sort(), c.file)
    }
    assert.deepEqual(Object.keys(doc).filter((k) => /drift/i.test(k)), [])
    for (const [field, f] of Object.entries(doc.fields)) {
      assert.ok(f.meaning.length > 10, field)
      for (const p of f.platforms) assert.ok(PLATFORMS.includes(p), `${field}: ${p}`)
    }
  })

  test(`${file}: each drift entry names a case and fields its platform is held to`, () => {
    const cases = new Set(doc.cases.map((c) => c.file))
    for (const [platform, d] of Object.entries(drift)) {
      for (const [caseFile, text] of Object.entries(d.expectations[name])) {
        assert.ok(cases.has(caseFile), `drift/${platform}.json: no ${name} case ${caseFile}`)
        const named = namedFields(doc, text)
        // S2S_CONFIG text is only held on core (s2sConfigText); native drift names the key.
        const s2s = name === 'app-config' && text.includes('S2S_CONFIG:')
        assert.ok(named.length > 0 || s2s, `drift/${platform}.json ${caseFile}: names no field: ${text}`)
        for (const f of named) assert.ok(doc.fields[f].platforms.includes(platform), `drift/${platform}.json ${caseFile}: ${platform} is not held to ${f}`)
      }
    }
  })
}

test('there is one drift file per SDK platform, in one shape', () => {
  const files = fs.readdirSync(path.join(CONTRACTS_DIR, 'expectations', 'drift')).sort()
  assert.deepEqual(files, DRIFT_PLATFORMS.map((p) => `${p}.json`))
  for (const [platform, d] of Object.entries(drift)) {
    assert.deepEqual(Object.keys(d), ['platform', 'description', 'expectations', 'other'], platform)
    assert.equal(d.platform, platform)
    assert.match(d.description, new RegExp(`Only the ${platform} unit edits this file`))
    assert.deepEqual(Object.keys(d.expectations).sort(), Object.keys(DOCS).sort(), platform)
    for (const [key, text] of Object.entries(d.other)) {
      assert.match(key, /^[a-z][A-Za-z]*(\.[a-z][A-Za-z]*)*$/, `${platform} other key ${key}`)
      assert.ok(typeof text === 'string' && text.length > 20, `${platform} other.${key}`)
    }
  }
})

test('app-config drift pins the verified weatherbug differences', () => {
  const doc = read('expectations/app-config.expected.json')
  const wbFile = 'samples/app-config/weatherbug_weatherbug-weatherbug.json'
  const wb = doc.cases.find((c) => c.file === wbFile)
  assert.deepEqual(wb.expected.iabCats, ['IAB15'])
  assert.deepEqual(wb.expected.mobileZids, { shared: ['weatherbug-mobile-300x250'], ios: ['weatherbug-mobile-ios'], android: ['weatherbug-mobile-android'] })
  assert.equal(wb.expected.adRefreshIntervalMs, 30000)
  assert.deepEqual(wb.expected.adStack.resolved, { 43: 'prebidOnly', 280: 'prebidOnly', 999: 'prebidOnly' })
  assert.equal(wb.expected.eventsEnabled, true)
  assert.equal(wb.expected.failuresSampleRate, 1)
  for (const p of ['ios', 'android', 'flutter']) assert.match(drift[p].expectations['app-config'][wbFile], /iabCats:/)
  assert.match(drift.flutter.expectations['app-config'][wbFile], /mobileZids:/)
  assert.match(drift.android.expectations['app-config'][wbFile], /"LAYOUT"/)
  assert.match(drift['react-native'].other['bridge.android'], /toHashMap/)
  assert.match(drift['react-native'].other['bridge.ios'], /as\? String/)
})

test('drift that phase 2 fixed is gone, and core has none', () => {
  const texts = (p, name) => Object.values(drift[p].expectations[name])
  // Flutter: fromJson no longer throws on real caches, and EVENTS_ENABLED is mapped.
  for (const t of texts('flutter', 'listings-response')) assert.doesNotMatch(t, /^items:|throws/)
  for (const t of texts('flutter', 'app-config')) assert.doesNotMatch(t, /eventsEnabled:/)
  // Android: a JSON-null remote_url is no longer the text "null".
  for (const t of texts('android', 'listings-response')) assert.doesNotMatch(t, /nullRemoteUrlIds:/)
  assert.deepEqual(drift.core.expectations, { 'app-config': {}, 'listings-response': {} })
  const listings = read('expectations/listings-response.expected.json')
  const bh = listings.cases.find((c) => c.file === 'samples/listings-response/bargainhunter.json')
  assert.equal(bh.expected.items, 10)
})
