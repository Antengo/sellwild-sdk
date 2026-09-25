// node --test for core/eslint.config.mjs and react-native/eslint.config.mjs:
// which house failure rules (contracts/FAILURES.md 1, 2, 8.4, 9) apply where,
// with which options, and which catch sites are exempt. The rules themselves
// are tested in contracts/test/lint-rules.test.mjs; this file fails when a
// config turns one off, weakens its options or exempts a whole file.
//
//   node --test scripts/lint/eslint-config.test.mjs
//
// Each config is imported here and handed to ESLint as an object
// (overrideConfigFile: true), the same way sellwild-widget's
// test/tooling/eslint-config.node.test.ts loads its own.

import assert from 'node:assert/strict'
import fs from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import { describe, it } from 'node:test'
import { fileURLToPath } from 'node:url'

import plugin from '../../contracts/lint/eslint-plugin-sellwild.mjs'
import { PRINT_EXEMPT } from '../../contracts/scripts/print-gate.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const CODES = JSON.parse(fs.readFileSync(path.join(ROOT, 'contracts/failure-codes.json'), 'utf8')).map((entry) => entry.code)

/** The rules every src file gets, and the catch options. */
const SRC_RULES = ['no-console', 'sellwild/no-global-console', 'sellwild/no-silent-catch', 'sellwild/catch-reports-failure', 'sellwild/disable-reason']

/**
 * Every sellwild/* exception in src, per file: the sites FAILURES.md exempts,
 * each on its own catch. A new one needs a reason citing FAILURES.md (the
 * disable-reason rule) and an entry here, so a reviewer sees it.
 */
const EXEMPT_SITES = {
  core: {
    // 8.4: transport never reports itself (EventQueue.flush's .catch, the uid guard).
    'src/event-queue.ts': ['sellwild/catch-reports-failure', 'sellwild/catch-reports-failure'],
  },
  'react-native': {
    // 9.2: log once (core's fetchListings already logged it).
    'src/useSellwildListings.ts': ['sellwild/catch-reports-failure'],
  },
}

const PACKAGES = [
  { name: 'core', shell: 'src/failures/index.ts', exts: ['.ts'] },
  { name: 'react-native', shell: null, exts: ['.ts', '.tsx'] },
]

function filesUnder (dir, exts) {
  const out = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push(...filesUnder(abs, exts))
    else if (exts.includes(path.extname(entry.name)) && !entry.name.endsWith('.d.ts')) out.push(abs)
  }
  return out
}

/** A rule's severity: 0 off, 1 warn, 2 error. */
function level (entry) {
  const value = Array.isArray(entry) ? entry[0] : entry
  if (value === undefined || value === 'off' || value === 0) return 0
  return value === 'error' || value === 2 ? 2 : 1
}

for (const pkg of PACKAGES) {
  describe(`${pkg.name}/eslint.config.mjs`, async () => {
    const dir = path.join(ROOT, pkg.name)
    const { ESLint } = createRequire(path.join(dir, 'package.json'))('eslint')
    const { default: config } = await import(path.join(dir, 'eslint.config.mjs'))
    const eslint = new ESLint({ cwd: dir, overrideConfigFile: true, overrideConfig: config })
    const rulesFor = async (file) => (await eslint.calculateConfigForFile(file)).rules ?? {}
    const exemptHere = PRINT_EXEMPT.filter((file) => file.startsWith(`${pkg.name}/`)).map((file) => file.slice(pkg.name.length + 1))
    const srcFiles = filesUnder(path.join(dir, 'src'), pkg.exts).map((file) => path.relative(dir, file).split(path.sep).join('/'))

    it('uses this repo\'s plugin and reports unused disable directives', async () => {
      const resolved = await eslint.calculateConfigForFile(srcFiles[0])
      assert.equal(resolved.plugins.sellwild, plugin, 'the sellwild plugin is contracts/lint/eslint-plugin-sellwild.mjs')
      assert.equal(level(resolved.linterOptions.reportUnusedDisableDirectives), 2)
    })

    it('every src file: no console, no silent catch, every catch reports with logFailure and a registry code', async () => {
      assert.ok(srcFiles.length > 5)
      for (const file of srcFiles) {
        const rules = await rulesFor(file)
        const printExempt = exemptHere.includes(file)
        for (const rule of SRC_RULES) {
          if (printExempt && (rule === 'no-console' || rule === 'sellwild/no-global-console')) continue
          if (file === pkg.shell && rule === 'sellwild/catch-reports-failure') continue
          assert.equal(level(rules[rule]), 2, `${file}: ${rule}`)
        }
        if (file === pkg.shell) continue
        const options = rules['sellwild/catch-reports-failure'][1]
        assert.deepEqual(Object.keys(options).sort(), ['codes', 'reporters'], `${file}: catch options`)
        assert.deepEqual(options.reporters, ['logFailure'], `${file}: the reporter is logFailure itself`)
        assert.deepEqual([...options.codes].sort(), [...CODES].sort(), `${file}: the codes are the registry's`)
      }
    })

    it('the A2 modules may print; only the logFailure shell\'s own catch may not report', async () => {
      for (const file of exemptHere) {
        const rules = await rulesFor(file)
        assert.equal(level(rules['no-console']), 0, file)
        assert.equal(level(rules['sellwild/no-global-console']), 0, file)
        assert.equal(level(rules['sellwild/no-silent-catch']), 2, file)
      }
      if (pkg.shell) assert.equal(level((await rulesFor(pkg.shell))['sellwild/catch-reports-failure']), 0)
    })

    it('tests may catch to assert and may print, but may not swallow', async () => {
      const tests = filesUnder(path.join(dir, 'test'), pkg.exts).map((file) => path.relative(dir, file))
      assert.ok(tests.length > 0)
      for (const file of tests.slice(0, 5)) {
        const rules = await rulesFor(file)
        assert.equal(level(rules['sellwild/no-silent-catch']), 2, file)
        assert.equal(level(rules['sellwild/disable-reason']), 2, file)
        assert.equal(level(rules['sellwild/catch-reports-failure']), 0, file)
      }
    })

    it('the only sellwild/* exceptions in src are the reviewed catch sites, and nothing turns every rule off', () => {
      const found = {}
      for (const file of [...srcFiles, ...filesUnder(path.join(dir, 'test'), pkg.exts).map((f) => path.relative(dir, f))]) {
        const text = fs.readFileSync(path.join(dir, file), 'utf8')
        // A blanket disable turns sellwild/disable-reason off as well, so the rule cannot see it.
        const blanket = [...text.matchAll(/eslint-disable(?:-line|-next-line)?[ \t]*(?:\*\/|--|$)/gm)]
        assert.deepEqual(blanket.map((m) => m[0]), [], `${file}: an eslint-disable must name its rules`)
        for (const m of text.matchAll(/eslint-disable(?:-line|-next-line)?\s+([^\n*]*?)(?:\s-{2,}\s|\*\/|$)/gm)) {
          for (const rule of m[1].split(',').map((r) => r.trim()).filter((r) => r.startsWith('sellwild/'))) {
            if (file.startsWith('src/')) (found[file] ??= []).push(rule)
          }
        }
      }
      assert.deepEqual(found, EXEMPT_SITES[pkg.name])
    })
  })
}
