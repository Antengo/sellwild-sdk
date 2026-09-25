// node --test for kotlin-warnings.mjs: the Gradle log parser (Kotlin 2.x and
// 1.x warning lines, javac lines, lines outside the compile tasks), the
// freshness check that refuses an up-to-date compile, the per-file compare,
// and the CLI on saved logs (--log, no Gradle). Fixtures are inline logs.
//
//   node --test scripts/lint/kotlin-warnings.test.mjs

import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { after, test } from 'node:test'
import { fileURLToPath } from 'node:url'

import {
  BASELINE_PATH,
  NO_FILE,
  SDK_ROOT,
  TASKS,
  buildBaseline,
  compare,
  countByFile,
  freshnessProblems,
  parseWarnings,
} from './kotlin-warnings.mjs'

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'kotlin-warnings.mjs')
const ROOT = '/repo'
const MAIN = `${ROOT}/android/src/main/kotlin/com/sellwild/sdk`
const TEST = `${ROOT}/android/src/test/kotlin/com/sellwild/sdk`

// A fresh compile as `gradlew --console=plain` prints it, with the noise that
// must not count: a configuration-time "w:" line, AGP's WARNING line, a
// "w:"-looking line under another task, and javac's Note lines.
const FRESH = `
> Configure project :
w: ⚠️ Deprecated Kotlin Gradle Plugin property
WARNING: We recommend using a newer Android Gradle plugin to use compileSdk = 36

> Task :preBuild UP-TO-DATE
> Task :compileDebugLibraryResources UP-TO-DATE
> Task :compileDebugKotlin
w: file://${MAIN}/SellwildHouseAdView.kt:110:47 Parameter 'config' is never used
w: file://${MAIN}/core/WidgetPage.kt:141:30 'ix: IxConfig?' is deprecated.
w: file://${MAIN}/core/WidgetPage.kt:148:33 'openx: OpenxConfig?' is deprecated.
w: Language version 1.9 is deprecated and its support will be removed in a future version of Kotlin

> Task :compileDebugJavaWithJavac NO-SOURCE
> Task :lintSomething
w: not a compiler warning, another task
> Task :compileDebugUnitTestKotlin
w: ${TEST}/docs/Docs Test.kt: (31, 13): Variable '_displayPrice' is never used
w: file://${TEST.replace('/sdk', '/s%20dk')}/Encoded.kt:1:1 Encoded path

> Task :compileDebugUnitTestJavaWithJavac
${ROOT}/android/src/test/java/com/sellwild/sdk/JavaCallersTest.java:12: warning: [deprecation] old() in Api has been deprecated
warning: [options] source value 8 is obsolete
Note: Some input files use unchecked or unsafe operations.

BUILD SUCCESSFUL in 12s
`

test('parseWarnings reads Kotlin 2.x, Kotlin 1.x and javac lines under the compile tasks only', () => {
  const w = parseWarnings(FRESH, { root: ROOT })
  assert.deepEqual(
    w.map((x) => [x.task, x.file, x.line, x.col]),
    [
      ['compileDebugKotlin', 'android/src/main/kotlin/com/sellwild/sdk/SellwildHouseAdView.kt', 110, 47],
      ['compileDebugKotlin', 'android/src/main/kotlin/com/sellwild/sdk/core/WidgetPage.kt', 141, 30],
      ['compileDebugKotlin', 'android/src/main/kotlin/com/sellwild/sdk/core/WidgetPage.kt', 148, 33],
      ['compileDebugKotlin', NO_FILE, 0, 0],
      ['compileDebugUnitTestKotlin', 'android/src/test/kotlin/com/sellwild/sdk/docs/Docs Test.kt', 31, 13],
      ['compileDebugUnitTestKotlin', 'android/src/test/kotlin/com/sellwild/s dk/Encoded.kt', 1, 1],
      ['compileDebugUnitTestJavaWithJavac', 'android/src/test/java/com/sellwild/sdk/JavaCallersTest.java', 12, 0],
      ['compileDebugUnitTestJavaWithJavac', NO_FILE, 0, 0],
    ],
  )
  assert.equal(w[0].message, "Parameter 'config' is never used")
  assert.equal(w[6].message, '[deprecation] old() in Api has been deprecated')
})

test('parseWarnings with tasks: null counts every warning line, wherever it is', () => {
  const w = parseWarnings(FRESH, { root: ROOT, tasks: null })
  assert.equal(w.length, 10) // + the configuration-time line and the one under :lintSomething
})

test('parseWarnings keeps a path outside the root absolute', () => {
  const w = parseWarnings('> Task :compileDebugKotlin\nw: file:///elsewhere/A.kt:1:2 msg\n', { root: ROOT })
  assert.equal(w[0].file, '/elsewhere/A.kt')
})

test('parseWarnings attributes grouped output to the repeated task header', () => {
  const log = [
    '> Task :compileDebugKotlin',
    '> Task :javaPreCompileDebugUnitTest',
    '> Task :compileDebugKotlin',
    `w: file://${MAIN}/A.kt:1:1 late output of the Kotlin task`,
  ].join('\n')
  assert.equal(parseWarnings(log, { root: ROOT }).length, 1)
})

test('freshnessProblems accepts a log where every compile task ran', () => {
  assert.deepEqual(freshnessProblems(FRESH), [])
})

test('freshnessProblems refuses an up-to-date, cached, skipped or missing compile', () => {
  const stale = FRESH
    .replace('> Task :compileDebugKotlin\n', '> Task :compileDebugKotlin UP-TO-DATE\n')
    .replace('> Task :compileDebugUnitTestKotlin\n', '> Task :compileDebugUnitTestKotlin FROM-CACHE\n')
    .replace('> Task :compileDebugUnitTestJavaWithJavac\n', '')
  assert.deepEqual(freshnessProblems(stale), [
    'compileDebugKotlin was UP-TO-DATE, not compiled',
    'compileDebugUnitTestKotlin was FROM-CACHE, not compiled',
    'compileDebugUnitTestJavaWithJavac did not run (no "> Task :compileDebugUnitTestJavaWithJavac" line)',
  ])
  assert.deepEqual(freshnessProblems('> Task :x:compileDebugKotlin NO-SOURCE', ['compileDebugKotlin']), [
    'compileDebugKotlin was NO-SOURCE, not compiled',
  ])
  assert.equal(freshnessProblems('BUILD SUCCESSFUL').length, TASKS.length)
})

test('countByFile totals and sorts per file', () => {
  const c = countByFile(parseWarnings(FRESH, { root: ROOT }))
  assert.equal(c.total, 8)
  assert.deepEqual(Object.keys(c.files), [...Object.keys(c.files)].sort())
  assert.equal(c.files['android/src/main/kotlin/com/sellwild/sdk/core/WidgetPage.kt'], 2)
  assert.equal(c.files[NO_FILE], 2)
})

test('compare: a file may only go down', () => {
  const baseline = { files: { 'a.kt': 2, 'b.kt': 1, 'gone.kt': 3 } }
  const { increases, decreases } = compare({ total: 4, files: { 'a.kt': 3, 'b.kt': 0, 'new.kt': 1 } }, baseline)
  assert.deepEqual(increases, [
    { file: 'a.kt', allowed: 2, found: 3 },
    { file: 'new.kt', allowed: 0, found: 1 },
  ])
  assert.deepEqual(decreases, [
    { file: 'b.kt', allowed: 1, found: 0 },
    { file: 'gone.kt', allowed: 3, found: 0 },
  ])
  // Moving a warning from one file to another is an increase, even at the same total.
  assert.equal(compare({ total: 1, files: { 'b.kt': 1 } }, { files: { 'a.kt': 1 } }).increases.length, 1)
  assert.deepEqual(compare({ total: 0, files: {} }, { files: {} }), { increases: [], decreases: [] })
})

test('buildBaseline records the tasks, total and per-file counts', () => {
  const b = buildBaseline({ total: 3, files: { 'a.kt': 3 } })
  assert.deepEqual(b.tasks, TASKS)
  assert.equal(b.total, 3)
  assert.deepEqual(b.files, { 'a.kt': 3 })
})

test('the checked-in baseline is consistent: total = sum of files, only repo paths', () => {
  const b = JSON.parse(fs.readFileSync(BASELINE_PATH, 'utf8'))
  assert.deepEqual(b.tasks, TASKS)
  assert.equal(b.total, Object.values(b.files).reduce((a, n) => a + n, 0))
  for (const f of Object.keys(b.files)) assert.ok(f === NO_FILE || f.startsWith('android/src/'), f)
})

// ── CLI on saved logs (no Gradle) ─────────────────────────────────────────────

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'kotlin-warnings-'))
after(() => fs.rmSync(tmp, { recursive: true, force: true }))

/** A fresh-compile log that reproduces the checked-in baseline exactly, plus `extra` lines. */
function logMatchingBaseline(extra = []) {
  const b = JSON.parse(fs.readFileSync(BASELINE_PATH, 'utf8'))
  const lines = ['> Task :compileDebugKotlin']
  for (const [file, n] of Object.entries(b.files)) {
    for (let i = 0; i < n; i++) lines.push(file === NO_FILE ? 'w: global' : `w: file://${path.join(SDK_ROOT, file)}:${i + 1}:1 baseline warning`)
  }
  lines.push(...extra, '> Task :compileDebugUnitTestKotlin', '> Task :compileDebugUnitTestJavaWithJavac', 'BUILD SUCCESSFUL')
  const p = path.join(tmp, `log-${Math.random().toString(36).slice(2)}.txt`)
  fs.writeFileSync(p, lines.join('\n'))
  return p
}

const run = (...args) => spawnSync(process.execPath, [SCRIPT, ...args], { encoding: 'utf8' })

test('CLI passes on a log that matches the baseline', () => {
  const r = run('--log', logMatchingBaseline())
  assert.equal(r.status, 0, r.stdout + r.stderr)
})

test('CLI fails on one new warning and names the file and line', () => {
  const file = path.join(SDK_ROOT, 'android/src/main/kotlin/com/sellwild/sdk/Brand.kt')
  const r = run('--log', logMatchingBaseline([`w: file://${file}:7:3 'x' is deprecated.`]))
  assert.equal(r.status, 1)
  assert.match(r.stdout, /FAIL android\/src\/main\/kotlin\/com\/sellwild\/sdk\/Brand\.kt: allowed 0, found 1/)
  assert.match(r.stdout, /line 7: 'x' is deprecated\./)
})

test('CLI fails on a stale log instead of counting zero warnings', () => {
  const p = path.join(tmp, 'stale.txt')
  fs.writeFileSync(p, TASKS.map((t) => `> Task :${t} UP-TO-DATE`).join('\n'))
  const r = run('--log', p)
  assert.equal(r.status, 1)
  assert.match(r.stderr, /not a fresh compile/)
})
