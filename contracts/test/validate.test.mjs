import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { runValidation, renderTable, undocumentedProperties, hasSyntheticMarker } from '../scripts/validate.mjs'
import { CONTRACTS_DIR } from '../scripts/lib/paths.mjs'

const VALIDATE = path.join(CONTRACTS_DIR, 'scripts', 'validate.mjs')

function tempOutRoot() {
  const base = path.join(CONTRACTS_DIR, 'out')
  fs.mkdirSync(base, { recursive: true })
  return fs.mkdtempSync(path.join(base, '.test-'))
}

test('every schema, sample, fixture, golden vector and the registry pass', () => {
  const rows = runValidation({ env: { SELLWILD_CONTRACT_OUT: path.join(CONTRACTS_DIR, 'out', '.none') } })
  const failed = rows.filter((r) => !r.ok)
  assert.deepEqual(failed, [], renderTable(failed))
  const checks = new Set(rows.map((r) => r.check))
  for (const c of ['schema', 'sample', 'fixture', 'golden', 'registry']) assert.ok(checks.has(c), c)
})

test('every real JSON sample is checked against its schema', () => {
  const rows = runValidation({ env: { SELLWILD_CONTRACT_OUT: path.join(CONTRACTS_DIR, 'out', '.none') } })
  const sampleRows = rows.filter((r) => r.check === 'sample').map((r) => r.file)
  for (const f of ['samples/app-config/weatherbug_weatherbug-weatherbug.json', 'samples/listings-response/bargainhunter.json', 'samples/localized-listings-response/sports-img-data-sm-webp-al.json']) {
    assert.ok(sampleRows.includes(f), f)
  }
})

test('--out validates only that platform and names the failing file', () => {
  const root = tempOutRoot()
  try {
    fs.mkdirSync(path.join(root, 'ios'))
    fs.mkdirSync(path.join(root, 'android'))
    const good = JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, 'fixtures/client-failure-event/valid/listings-http.json'), 'utf8'))
    delete good._synthetic
    fs.writeFileSync(path.join(root, 'ios', 'client-failure-event.default.json'), JSON.stringify(good))
    fs.writeFileSync(path.join(root, 'android', 'client-failure-event.bad.json'), JSON.stringify({ ...good, amount: 1 }))

    const ios = runValidation({ only: 'ios', env: { SELLWILD_CONTRACT_OUT: root } })
    assert.equal(ios.length, 1)
    assert.equal(ios[0].ok, true)

    const android = runValidation({ only: 'android', env: { SELLWILD_CONTRACT_OUT: root } })
    assert.equal(android.length, 1)
    assert.equal(android[0].ok, false)
    assert.match(android[0].file, /android\/client-failure-event\.bad\.json$/)

    const cli = spawnSync(process.execPath, [VALIDATE, '--out', 'android'], { env: { ...process.env, SELLWILD_CONTRACT_OUT: root }, encoding: 'utf8' })
    assert.equal(cli.status, 1)
    assert.match(cli.stdout, /FAIL/)
    const ok = spawnSync(process.execPath, [VALIDATE, '--out', 'ios'], { env: { ...process.env, SELLWILD_CONTRACT_OUT: root }, encoding: 'utf8' })
    assert.equal(ok.status, 0, ok.stdout)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('--out fails on a missing platform dir, an unknown schema name, or broken JSON', () => {
  const root = tempOutRoot()
  try {
    const none = runValidation({ only: 'flutter', env: { SELLWILD_CONTRACT_OUT: root } })
    assert.equal(none.length, 1)
    assert.equal(none[0].ok, false)
    assert.equal(none[0].detail, 'no emitted files')

    fs.mkdirSync(path.join(root, 'flutter'))
    fs.writeFileSync(path.join(root, 'flutter', 'no-such-schema.default.json'), '{}')
    fs.writeFileSync(path.join(root, 'flutter', 'listing.broken.json'), '{')
    const rows = runValidation({ only: 'flutter', env: { SELLWILD_CONTRACT_OUT: root } })
    assert.equal(rows.length, 2)
    assert.ok(rows.every((r) => !r.ok))
    assert.ok(rows.some((r) => /unknown schema 'no-such-schema'/.test(r.detail)))
    assert.ok(rows.some((r) => /not JSON/.test(r.detail)))
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('a full run also checks files already emitted under out/', () => {
  const root = tempOutRoot()
  try {
    fs.mkdirSync(path.join(root, 'core'))
    fs.writeFileSync(path.join(root, 'core', 'listing.bad.json'), JSON.stringify({ id: 1 }))
    const rows = runValidation({ env: { SELLWILD_CONTRACT_OUT: root } })
    const out = rows.filter((r) => r.check === 'out')
    assert.equal(out.length, 1)
    assert.equal(out[0].ok, false)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('undocumentedProperties finds properties without a description', () => {
  const schema = { properties: { a: { type: 'string', description: 'A.' }, b: { type: 'string' } }, $defs: { x: { properties: { c: { description: ' ' } } } } }
  assert.deepEqual(undocumentedProperties(schema), ['#/properties/b', '#/$defs/x/properties/c'])
})

test('hasSyntheticMarker applies to objects and to the first array element', () => {
  assert.equal(hasSyntheticMarker({ _synthetic: true }), true)
  assert.equal(hasSyntheticMarker({ a: 1 }), false)
  assert.equal(hasSyntheticMarker([{ _synthetic: true }, { a: 1 }]), true)
  assert.equal(hasSyntheticMarker([{ a: 1 }]), false)
  assert.equal(hasSyntheticMarker([]), true)
  assert.equal(hasSyntheticMarker('text'), true)
})
