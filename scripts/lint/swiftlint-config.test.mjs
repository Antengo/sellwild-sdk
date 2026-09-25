// node --test scripts/lint/swiftlint-config.test.mjs
//
// Checks the house-rule part of .swiftlint.yml: runs the pinned SwiftLint on
// fixtures/swiftlint (a copy laid out like the repo) and compares each hit
// with the "expect: <rule>" markers there, and that SwiftLint has no warning
// about the config itself. Also checks that the rules' print exemptions match
// PRINT_EXEMPT in contracts/scripts/print-gate.mjs. The baseline matching is
// swiftlint-baseline.test.mjs's.
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { PRINT_EXEMPT } from '../../contracts/scripts/print-gate.mjs'
import { configWarnings } from './swiftlint-baseline.mjs'

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
    // A misspelled option is only a warning to SwiftLint; the gate fails on it.
    assert.deepEqual(configWarnings(r.stderr), [], 'SwiftLint warned about .swiftlint.yml')
    const actual = JSON.parse(r.stdout)
      .filter((v) => HOUSE_RULES.has(v.rule_id))
      .map((v) => `${path.relative(fs.realpathSync(dir), fs.realpathSync(v.file))}:${v.line} ${v.rule_id}`)
    assert.deepEqual(actual.sort(), expected.sort())
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
