// node --test tools/coverage-gate.test.mjs
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { after, describe, it } from 'node:test'
import { checkDir, checkSummary, main } from './coverage-gate.mjs'

const pct = (value) => ({ covered: value, total: 100, pct: value })
const gate = (over = {}) => ({ gate: { lines: pct(100), branches: pct(99), regions: null, functions: pct(98), unmeasured: [], ...over } })

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'coverage-gate-'))
after(() => fs.rmSync(tmp, { recursive: true, force: true }))

function dirWith (files) {
  const dir = fs.mkdtempSync(path.join(tmp, 'd-'))
  for (const [name, body] of Object.entries(files)) {
    fs.writeFileSync(path.join(dir, `${name}.json`), typeof body === 'string' ? body : JSON.stringify(body))
  }
  return dir
}

function run (argv) {
  let text = ''
  const code = main(argv, { root: tmp, out: { write: (s) => { text += s } } })
  return { code, text }
}

describe('checkSummary', () => {
  it('passes a gate at or over the target', () => {
    assert.deepEqual(checkSummary(gate({ lines: pct(95) })), [])
  })

  it('names each metric under the target', () => {
    assert.deepEqual(checkSummary(gate({ lines: pct(94.99), functions: pct(90) })), [
      'lines 94.99% is under 95%',
      'functions 90% is under 95%',
    ])
  })

  it('uses regions when a platform has no branch count (Swift)', () => {
    assert.deepEqual(checkSummary(gate({ branches: null, regions: pct(96) })), [])
    assert.deepEqual(checkSummary(gate({ branches: null, regions: pct(80) })), ['regions 80% is under 95%'])
  })

  it('fails a metric that was not measured', () => {
    assert.deepEqual(checkSummary(gate({ branches: null })), ['branches not measured'])
    assert.deepEqual(checkSummary(gate({ lines: { covered: 1, total: 2, pct: null } })), ['lines not measured'])
  })

  it('fails a gate that lists unmeasured files', () => {
    assert.deepEqual(checkSummary(gate({ unmeasured: ['lib/a.dart'] })), ['unmeasured: lib/a.dart'])
  })

  it('fails a summary with no gate block', () => {
    assert.deepEqual(checkSummary({}), ['no gate block'])
    assert.deepEqual(checkSummary(null), ['no gate block'])
  })

  it('takes another target', () => {
    assert.deepEqual(checkSummary(gate(), 99.5), ['branches 99% is under 99.5%', 'functions 98% is under 99.5%'])
  })
})

describe('checkDir', () => {
  it('reports a missing expected summary and an unreadable one', () => {
    const dir = dirWith({ core: gate(), ios: '{ not json' })
    const rows = checkDir(dir, { expect: ['core', 'android'] })
    assert.deepEqual(rows.map((r) => [r.name, r.problems.length > 0]), [['android', true], ['core', false], ['ios', true]])
    assert.deepEqual(rows[0].problems, ['missing'])
    assert.match(rows[2].problems[0], /^unreadable: /)
  })

  it('fails an empty or absent directory', () => {
    assert.deepEqual(checkDir(path.join(tmp, 'nope'))[0].problems, ['no coverage summaries'])
  })
})

describe('main', () => {
  it('exits 0 and prints one line per summary when all pass', () => {
    const dir = dirWith({ core: gate(), ios: gate({ branches: null, regions: pct(99.5) }) })
    const { code, text } = run(['--dir', dir, '--expect', 'core,ios'])
    assert.equal(code, 0)
    assert.match(text, /^core {2}lines 100% {2}branches 99% {2}functions 98% {2}pass$/m)
    assert.match(text, /^ios {3}lines 100% {2}regions 99.5% {2}functions 98% {2}pass$/m)
    assert.match(text, /all 2 at 95% or more/)
  })

  it('exits 1 when any summary fails', () => {
    const dir = dirWith({ core: gate({ lines: pct(50) }), android: gate() })
    const { code, text } = run(['--dir', dir, '--target', '90'])
    assert.equal(code, 1)
    assert.match(text, /^core .*FAIL: lines 50% is under 90%$/m)
    assert.match(text, /1 of 2 under 90%/)
  })

  it('exits 2 on a usage error', () => {
    assert.equal(run(['--bogus']).code, 2)
    assert.equal(run(['--target', 'high']).code, 2)
    assert.equal(run(['--dir']).code, 2)
  })
})
