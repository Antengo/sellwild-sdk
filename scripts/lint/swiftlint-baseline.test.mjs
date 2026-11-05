// node --test for swiftlint-baseline.mjs: the keys, the per-key counts, the
// size rules (a long file may shrink, not grow), --update refusing any
// increase, and the checked-in baseline's shape. SwiftLint findings are
// inline JSON, so no SwiftLint run is needed.
//
//   node --test scripts/lint/swiftlint-baseline.test.mjs

import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { after, test } from 'node:test'
import { fileURLToPath } from 'node:url'

import {
  BASELINE,
  SIZE_RULES,
  buildBaseline,
  compare,
  configWarnings,
  measured,
  reasonKey,
  toFindings,
} from './swiftlint-baseline.mjs'

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'swiftlint-baseline.mjs')
const ROOT = '/repo'
const FILE = 'ios/Sources/SellwildSDK/SellwildAdView.swift'

/** One SwiftLint JSON finding. */
const v = (rule, reason, { file = FILE, line = 1, character = 1 } = {}) => ({ file: `${ROOT}/${file}`, line, character, rule_id: rule, reason, severity: 'Warning', type: rule })
const fileLength = (n) => v('file_length', `File should contain 400 lines or less excluding comments and whitespaces: currently contains ${n}`, { line: n })
const functionBody = (n, line = 10) => v('function_body_length', `Function body should span 50 lines or less excluding comments and whitespace: currently spans ${n} lines`, { line })
const longLine = (n, line) => v('line_length', `Line should be 120 characters or less; currently it has ${n} characters`, { line })
const comma = (line) => v('trailing_comma', 'Collection literals should not have trailing commas', { line })

const findings = (...items) => toFindings(items, ROOT)
const baseline = (...items) => buildBaseline(findings(...items))
const check = (base, ...now) => compare(findings(...now), base)

test('a key is file, rule and reason with every number as #', () => {
  const [f] = findings(fileLength(804))
  assert.equal(f.file, FILE)
  assert.equal(f.key, 'file_length: File should contain # lines or less excluding comments and whitespaces: currently contains #')
  assert.equal(f.size, 804)
  assert.equal(reasonKey("Type name 'Docs_b03_L36' should be 3 long"), "Type name 'Docs_b#_L#' should be # long")
})

test('the size rules measure the number after "currently"; other rules measure nothing', () => {
  assert.equal(measured('cyclomatic_complexity', 'Function should have complexity 10 or less; currently complexity is 26'), 26)
  assert.equal(measured('type_body_length', 'Class body should span 350 lines or less excluding comments and whitespace: currently spans 446 lines'), 446)
  assert.equal(measured('function_parameter_count', 'Function should have 5 parameters or less: it currently has 6'), 6)
  assert.equal(measured('line_length', 'Line should be 120 characters or less; currently it has 124 characters'), 124)
  assert.equal(measured('large_tuple', 'Tuples should have at most 2 members'), null)
  assert.equal(measured('trailing_comma', 'currently 3'), null)
  for (const rule of ['file_length', 'type_body_length', 'function_body_length', 'cyclomatic_complexity']) assert.ok(SIZE_RULES.has(rule), rule)
})

test('the baseline counts plain findings and keeps sizes largest first', () => {
  const b = baseline(comma(3), comma(9), longLine(124, 5), longLine(130, 7))
  assert.deepEqual(b.files[FILE], {
    'line_length: Line should be # characters or less; currently it has # characters': [130, 124],
    'trailing_comma: Collection literals should not have trailing commas': 2,
  })
})

test('moving or editing a baselined finding passes; one more under a key fails', () => {
  const b = baseline(comma(3), comma(9))
  assert.deepEqual(check(b, comma(40), comma(41)).failures, [])
  const { failures } = check(b, comma(3), comma(9), comma(12))
  assert.equal(failures.length, 1)
  assert.equal(failures[0].why, '3 found, the baseline allows 2')
})

test('a finding under a key the baseline lacks fails, even in a baselined file', () => {
  const b = baseline(comma(3))
  const { failures } = check(b, comma(3), v('force_try', 'Force tries should be avoided', { line: 8 }))
  assert.equal(failures.length, 1)
  assert.equal(failures[0].why, 'new finding')
  assert.equal(check(b, v('trailing_comma', 'Collection literals should not have trailing commas', { file: 'ios/Sources/Other.swift' })).failures.length, 1)
})

test('SW12/SW13: a long file that stays or shrinks passes; one that grows fails', () => {
  const b = baseline(fileLength(613))
  assert.deepEqual(check(b, fileLength(613)).failures, [])
  const shrunk = check(b, fileLength(612))
  assert.deepEqual(shrunk.failures, [])
  assert.equal(shrunk.fixed, 1)
  const grew = check(b, fileLength(614)).failures
  assert.equal(grew.length, 1)
  assert.match(grew[0].why, /^grew: 614 \(baseline 613\)$/)
})

test('SW11: a baselined long function may not grow; sizes pair largest first', () => {
  const b = baseline(functionBody(70, 10), functionBody(59, 200))
  assert.deepEqual(check(b, functionBody(70, 12), functionBody(59, 205)).failures, [], 'moved')
  assert.deepEqual(check(b, functionBody(69, 10), functionBody(58, 200)).failures, [], 'both shrank')
  assert.equal(check(b, functionBody(70, 10), functionBody(60, 200)).failures.length, 1, 'the shorter one grew')
  assert.equal(check(b, functionBody(71, 10)).failures.length, 1, 'the longer one grew, the other is fixed')
  assert.deepEqual(check(b, functionBody(65, 10)).failures, [], 'one fixed, the other shrank')
  assert.equal(check(b, functionBody(70), functionBody(59), functionBody(51)).failures[0].why, '3 found, the baseline allows 2')
})

test('a long line may not get longer', () => {
  const b = baseline(longLine(124, 5), longLine(122, 9))
  assert.deepEqual(check(b, longLine(122, 6), longLine(121, 30)).failures, [])
  assert.equal(check(b, longLine(124, 5), longLine(123, 9)).failures.length, 1)
})

test('a size finding against a hand-written count fails: the baseline allows no size', () => {
  const b = { files: { [FILE]: { 'file_length: File should contain # lines or less excluding comments and whitespaces: currently contains #': 1 } } }
  assert.equal(check(b, fileLength(401)).failures.length, 1)
})

test('findings gone from the baseline count as fixed', () => {
  const b = baseline(comma(3), longLine(130, 4), v('force_try', 'Force tries should be avoided', { file: 'ios/Sources/Gone.swift' }))
  const { failures, fixed } = check(b, longLine(125, 4))
  assert.deepEqual(failures, [])
  assert.equal(fixed, 3)
})

test('paths are made repo-relative through realpath (SwiftLint drops /private from /private/tmp)', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'swiftlint-baseline-'))
  try {
    fs.mkdirSync(path.join(dir, 'ios'))
    fs.writeFileSync(path.join(dir, 'ios/A.swift'), '')
    const real = fs.realpathSync(dir)
    const shown = real.replace(/^\/private\//, '/')
    assert.equal(toFindings([{ ...comma(1), file: `${shown}/ios/A.swift` }], dir)[0].file, 'ios/A.swift')
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

test('configWarnings finds SwiftLint\'s own warnings on stderr', () => {
  assert.deepEqual(configWarnings("warning: Configuration for 'file_length' rule contains the invalid key(s) 'x'.\nLinting done\n"), ["warning: Configuration for 'file_length' rule contains the invalid key(s) 'x'."])
  assert.deepEqual(configWarnings(''), [])
})

// ── CLI on saved findings (--findings, --baseline, --root) ───────────────────

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'swiftlint-baseline-cli-'))
after(() => fs.rmSync(tmp, { recursive: true, force: true }))

function cli (name, items, ...args) {
  const file = path.join(tmp, `${name}.json`)
  fs.writeFileSync(file, JSON.stringify(items))
  return spawnSync(process.execPath, [SCRIPT, '--findings', file, '--root', ROOT, '--baseline', path.join(tmp, 'baseline.json'), ...args], { encoding: 'utf8' })
}

test('CLI: --update writes the baseline, check passes on it and fails on growth', () => {
  // With no baseline file every finding is new: creating one needs --allow-increase too.
  let r = cli('first', [fileLength(613), comma(3)], '--update')
  assert.equal(r.status, 1)
  r = cli('first', [fileLength(613), comma(3)], '--update', '--allow-increase')
  assert.equal(r.status, 0, r.stderr)
  assert.equal(cli('same', [fileLength(600), comma(90)]).status, 0)
  r = cli('grew', [fileLength(614), comma(3)])
  assert.equal(r.status, 1)
  assert.match(r.stdout, /SellwildAdView\.swift: file_length: grew: 614 \(baseline 613\)/)
  assert.match(r.stdout, /SellwildAdView\.swift:614:1: File should contain/)
})

test('CLI: --update refuses any increase (a longer file too) unless --allow-increase', () => {
  assert.equal(cli('base', [fileLength(613)], '--update', '--allow-increase').status, 0)
  let r = cli('longer', [fileLength(620)], '--update')
  assert.equal(r.status, 1)
  assert.match(r.stderr, /refusing to add 1 finding group/)
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(tmp, 'baseline.json'), 'utf8')).files[FILE], { [findings(fileLength(1))[0].key]: [613] })
  r = cli('more', [fileLength(613), comma(1)], '--update')
  assert.equal(r.status, 1)
  r = cli('longer', [fileLength(620)], '--update', '--allow-increase')
  assert.equal(r.status, 0, r.stderr)
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(tmp, 'baseline.json'), 'utf8')).files[FILE], { [findings(fileLength(1))[0].key]: [620] })
})

test('CLI: --update shrinks the baseline without --allow-increase', () => {
  assert.equal(cli('base2', [fileLength(613), comma(3), comma(4)], '--update', '--allow-increase').status, 0)
  const r = cli('shrunk', [fileLength(500), comma(3)], '--update')
  assert.equal(r.status, 0, r.stderr)
  assert.match(r.stdout, /3 -> 2 finding/)
})

test('the checked-in baseline has the shape the gate reads', () => {
  const b = JSON.parse(fs.readFileSync(BASELINE, 'utf8'))
  assert.equal(typeof b.description, 'string')
  const files = Object.keys(b.files)
  assert.ok(files.length > 10)
  assert.deepEqual(files, [...files].sort())
  for (const [file, byKey] of Object.entries(b.files)) {
    assert.ok(!path.isAbsolute(file) && !file.startsWith('..'), file)
    for (const [key, value] of Object.entries(byKey)) {
      const rule = key.slice(0, key.indexOf(':'))
      assert.doesNotMatch(key, /\d/, `${file} ${key}: numbers are #`)
      if (Array.isArray(value)) {
        assert.ok(SIZE_RULES.has(rule), `${file} ${key}: only size rules keep sizes`)
        assert.deepEqual(value, [...value].sort((a, b) => b - a), `${file} ${key}: largest first`)
      } else {
        assert.ok(Number.isInteger(value) && value > 0, `${file} ${key}`)
      }
    }
  }
})
