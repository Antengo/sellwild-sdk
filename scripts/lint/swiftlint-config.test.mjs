// node --test scripts/lint/swiftlint-config.test.mjs
//
// Checks the house-rule part of .swiftlint.yml: runs the pinned SwiftLint on
// fixtures/swiftlint (a copy laid out like the repo) and compares each hit
// with the "expect: <rule>" markers there. Also checks that the rules' print
// exemptions match PRINT_EXEMPT in contracts/scripts/print-gate.mjs.
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { PRINT_EXEMPT } from '../../contracts/scripts/print-gate.mjs'
import { normalize, added } from './swiftlint-baseline.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(HERE, '../..')
const CONFIG = path.join(ROOT, '.swiftlint.yml')
const SWIFTLINT = path.join(ROOT, 'tools/bin/swiftlint')
const FIXTURES = path.join(HERE, 'fixtures/swiftlint')
const HOUSE_RULES = new Set(['no_print', 'no_os_logger', 'empty_catch', 'empty_catch_comment', 'unhandled_throwing_task'])

test('print exemptions in .swiftlint.yml match PRINT_EXEMPT', () => {
  const yml = fs.readFileSync(CONFIG, 'utf8')
  const swiftExempt = PRINT_EXEMPT.filter((f) => f.endsWith('.swift')).sort()
  for (const rule of ['no_print', 'no_os_logger']) {
    const block = yml.split(new RegExp(`^  ${rule}:$`, 'm'))[1]?.split(/^ {2}\w+:$/m)[0]
    assert.ok(block, `${rule} is missing from .swiftlint.yml`)
    const listed = [...block.matchAll(/- '\/(.+?)\\\.swift\$'/g)].map((m) => `${m[1]}.swift`).sort()
    assert.deepEqual(listed, swiftExempt, `${rule} excluded: must list exactly the Swift files in PRINT_EXEMPT`)
  }
})

test('house rules flag exactly the marked lines', { skip: !fs.existsSync(SWIFTLINT) && 'run bash scripts/lint/install-swiftlint.sh first' }, () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'swiftlint-config-'))
  try {
    fs.cpSync(FIXTURES, dir, { recursive: true })
    fs.copyFileSync(CONFIG, path.join(dir, '.swiftlint.yml'))
    const expected = []
    const walk = (d) => {
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name)
        if (e.isDirectory()) walk(p)
        else if (e.name.endsWith('.swift')) {
          fs.readFileSync(p, 'utf8').split('\n').forEach((line, i) => {
            const m = /\/\/ expect: (\w+)\s*$/.exec(line)
            if (m) expected.push(`${path.relative(dir, p)}:${i + 1} ${m[1]}`)
          })
        }
      }
    }
    walk(dir)
    assert.ok(expected.length > 10, 'fixture expect: markers are missing')
    const r = spawnSync(SWIFTLINT, ['lint', '--quiet', '--no-cache', '--reporter', 'json'], { cwd: dir, encoding: 'utf8' })
    assert.ok(r.stdout.trim().startsWith('['), `SwiftLint gave no JSON:\n${r.stderr}`)
    const actual = JSON.parse(r.stdout)
      .filter((v) => HOUSE_RULES.has(v.rule_id))
      .map((v) => `${path.relative(fs.realpathSync(dir), fs.realpathSync(v.file))}:${v.line} ${v.rule_id}`)
    assert.deepEqual(actual.sort(), expected.sort())
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

test('baseline normalize is stable and added() counts copies', () => {
  const v = (file, line, rule, text, extra = {}) => ({ text, violation: { ...extra, ruleIdentifier: rule, location: { file, line, character: 1 } } })
  const a = v('b.swift', 2, 'line_length', 'x', { severity: 'warning' })
  const b = v('a.swift', 9, 'comma', 'y')
  const sameAsA = { violation: { location: { character: 1, line: 2, file: 'b.swift' }, severity: 'warning', ruleIdentifier: 'line_length' }, text: 'x' }
  assert.equal(normalize([a, b]), normalize([b, sameAsA]))
  assert.equal(normalize([a, b]).split('\n')[1].startsWith('{"text":"y"'), true)
  assert.equal(normalize([]), '[]\n')
  assert.deepEqual(added([a], [a, b]), [b])
  assert.deepEqual(added([a], [{ ...a, violation: { ...a.violation, location: { ...a.violation.location, line: 40 } } }]), [])
  assert.equal(added([a], [a, a]).length, 1)
})
