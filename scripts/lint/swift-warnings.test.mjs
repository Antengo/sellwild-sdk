// node --test scripts/lint/swift-warnings.test.mjs
//
// fixtures/swift-warnings/Sample.dia was written by
//   swiftc -frontend -typecheck -primary-file ios/Sources/SellwildSDK/Sample.swift -serialize-diagnostics-path Sample.dia
// on this source (Swift 6.3.2, Xcode 26.5):
//   1 func sample(_ a: Int?) -> String {
//   2     var unused = 1
//   3     return "\(a)"
//   4 }
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import {
  buildBaseline, cleanMessage, diaWarnings, entryOf, newestInput, newWarnings, ourFile, parseLog, readDia, unique,
} from './swift-warnings.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const FIX = path.join(HERE, 'fixtures/swift-warnings')
const SCRIPT = path.join(HERE, 'swift-warnings.mjs')
const LOG = fs.readFileSync(path.join(FIX, 'ios-test.log'), 'utf8')
const DIA = fs.readFileSync(path.join(FIX, 'Sample.dia'))
const SAMPLE_MSG = {
  interp: 'string interpolation produces a debug description for an optional value; did you mean to make this explicit?',
  unused: "initialization of variable 'unused' was never used; consider replacing with assignment to '_' or removing it",
}

test('parseLog keeps only warnings in ios/Sources and ios/Tests', () => {
  const r = parseLog(LOG, '/ROOT')
  assert.equal(r.derivedData, '/ROOT/.coverage-tmp/ios-dd')
  assert.equal(r.buildFailed, false)
  assert.deepEqual(r.warnings, [
    { file: 'ios/Sources/SellwildSDK/SellwildAdStack.swift', line: 42, column: 13, message: "variable 'x' was never mutated; consider changing to 'let' constant" },
    { file: 'ios/Tests/SellwildSDKTests/Logic/AdStackTests.swift', line: 10, column: 5, message: "'foo()' is deprecated: use bar()" },
    { file: 'ios/Sources/SellwildSDK/SellwildAdStack.swift', line: 42, column: 13, message: "variable 'x' was never mutated; consider changing to 'let' constant" },
  ])
})

test('parseLog spots a failed build', () => {
  assert.equal(parseLog('x\n** BUILD FAILED **\n', '/ROOT').buildFailed, true)
  assert.equal(parseLog('x\n** TEST BUILD FAILED **\n', '/ROOT').buildFailed, true)
  assert.equal(parseLog('Testing cancelled because the build failed.\n** TEST FAILED **\n', '/ROOT').buildFailed, true)
  assert.equal(parseLog('** TEST FAILED **\n', '/ROOT').buildFailed, false)
  assert.equal(parseLog('no command line here', '/ROOT').derivedData, null)
})

test('cleanMessage drops the diagnostic group suffix only', () => {
  assert.equal(cleanMessage("variable 'x' was never used [#no-usage]"), "variable 'x' was never used")
  assert.equal(cleanMessage('uses [brackets] inside'), 'uses [brackets] inside')
})

test('ourFile takes absolute or root-relative paths', () => {
  assert.equal(ourFile('/ROOT/ios/Sources/A.swift', '/ROOT'), 'ios/Sources/A.swift')
  assert.equal(ourFile('ios/Tests/B.swift', '/ROOT'), 'ios/Tests/B.swift')
  assert.equal(ourFile('/ROOT/samples/ios/C.swift', '/ROOT'), null)
  assert.equal(ourFile('/elsewhere/ios/Sources/D.swift', '/ROOT'), null)
  assert.equal(ourFile('/ROOT/ios/SourcesX/E.swift', '/ROOT'), null)
})

test('readDia reads warnings and their nested notes', () => {
  const diags = readDia(DIA)
  const file = 'ios/Sources/SellwildSDK/Sample.swift'
  assert.deepEqual(diags.filter((d) => d.severity === 'warning'), [
    { severity: 'warning', file, line: 3, column: 15, message: SAMPLE_MSG.interp },
    { severity: 'warning', file, line: 2, column: 9, message: SAMPLE_MSG.unused },
  ])
  assert.equal(diags.filter((d) => d.severity === 'note').length, 3)
})

test('readDia rejects other files and truncated ones', () => {
  assert.throws(() => readDia(Buffer.from('nope')), /not a serialized diagnostics file/)
  assert.throws(() => readDia(DIA.subarray(0, 200)), /bitstream/)
})

function tempTree() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'swift-warnings-'))
  const put = (rel, body) => {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true })
    fs.writeFileSync(path.join(root, rel), body)
    return path.join(root, rel)
  }
  return { root, put, done: () => fs.rmSync(root, { recursive: true, force: true }) }
}

test('diaWarnings skips a .dia whose source is gone', () => {
  const t = tempTree()
  try {
    t.put('dd/Build/Intermediates.noindex/SellwildSDK.build/Debug/SellwildSDK.build/Objects-normal/arm64/Sample.dia', DIA)
    t.put('dd/Build/Intermediates.noindex/Other.build/Objects-normal/arm64/Other.dia', 'not even parsed')
    const all = diaWarnings(path.join(t.root, 'dd'), t.root, () => true)
    assert.equal(all.files, 1)
    assert.deepEqual(all.warnings.map((w) => `${w.file}:${w.line}`), ['ios/Sources/SellwildSDK/Sample.swift:3', 'ios/Sources/SellwildSDK/Sample.swift:2'])
    assert.equal(diaWarnings(path.join(t.root, 'dd'), t.root, () => false).warnings.length, 0)
  } finally {
    t.done()
  }
})

test('unique merges the log and .dia copies even when columns differ', () => {
  const a = { file: 'ios/Sources/A.swift', line: 2, column: 9, message: 'm' }
  assert.deepEqual(unique([a, { ...a, column: 10 }, { ...a, line: 3 }]).map((w) => w.line), [2, 3])
})

test('newWarnings counts copies against the baseline', () => {
  const w = (file, message, line = 1) => ({ file, line, column: 1, message })
  const baseline = buildBaseline([w('ios/Sources/A.swift', 'old')])
  assert.equal(baseline.count, 1)
  assert.deepEqual(baseline.warnings, ['ios/Sources/A.swift: old'])
  const found = [w('ios/Sources/A.swift', 'old', 5), w('ios/Sources/A.swift', 'old', 9), w('ios/Tests/B.swift', 'new')]
  assert.deepEqual(newWarnings(found, baseline).map(entryOf), ['ios/Sources/A.swift: old', 'ios/Tests/B.swift: new'])
})

test('newestInput finds the newest file and skips dot folders', () => {
  const t = tempTree()
  try {
    const old = t.put('ios/Sources/Old.swift', '')
    const young = t.put('ios/Tests/Young.swift', '')
    const hidden = t.put('ios/Sources/.build/Hidden.swift', '')
    fs.utimesSync(old, 1000, 1000)
    fs.utimesSync(young, 2000, 2000)
    fs.utimesSync(hidden, 3000, 3000)
    assert.deepEqual(newestInput(t.root), { file: 'ios/Tests/Young.swift', mtimeMs: 2_000_000 })
  } finally {
    t.done()
  }
})

function run(root, ...args) {
  const r = spawnSync(process.execPath, [SCRIPT, '--root', root, '--baseline', path.join(root, 'baseline.json'), ...args], { encoding: 'utf8' })
  return { status: r.status, out: r.stdout + r.stderr }
}

test('CLI: refuses a stale log, then ratchets on the merged count', () => {
  const t = tempTree()
  try {
    const src = t.put('ios/Sources/SellwildSDK/Sample.swift', 'func sample(_ a: Int?) -> String {\n    var unused = 1\n    return "\\(a)"\n}\n')
    t.put('.coverage-tmp/ios-dd/Build/Intermediates.noindex/SellwildSDK.build/Objects-normal/arm64/Sample.dia', DIA)
    const log = t.put('.coverage-tmp/ios-test.log', LOG.replaceAll('/ROOT', t.root))

    fs.utimesSync(log, 1000, 1000)
    fs.utimesSync(src, 2000, 2000)
    let r = run(t.root)
    assert.equal(r.status, 2)
    assert.match(r.out, /stale log: ios\/Sources\/SellwildSDK\/Sample\.swift changed/)

    fs.utimesSync(log, 3000, 3000)
    fs.writeFileSync(path.join(t.root, 'baseline.json'), JSON.stringify({ count: 3, warnings: [] }))
    r = run(t.root)
    // 2 unique in the log + 2 in the .dia.
    assert.equal(r.status, 1, r.out)
    assert.match(r.out, /FAIL: 4 warning\(s\), baseline allows 3/)
    assert.match(r.out, /ios\/Sources\/SellwildSDK\/Sample\.swift:2:9: warning: initialization of variable 'unused'/)

    r = run(t.root, '--update')
    assert.equal(r.status, 1)
    assert.match(r.out, /refusing to raise the baseline 3 -> 4/)

    r = run(t.root, '--update', '--allow-increase')
    assert.equal(r.status, 0, r.out)
    assert.equal(JSON.parse(fs.readFileSync(path.join(t.root, 'baseline.json'), 'utf8')).count, 4)
    assert.equal(run(t.root).status, 0)

    fs.writeFileSync(log, '** TEST BUILD FAILED **\n')
    r = run(t.root)
    assert.equal(r.status, 2)
    assert.match(r.out, /failed build/)
  } finally {
    t.done()
  }
})

test('CLI: refuses when no .dia files exist', () => {
  const t = tempTree()
  try {
    t.put('ios/Sources/A.swift', '')
    t.put('.coverage-tmp/ios-test.log', 'no build here\n')
    fs.utimesSync(path.join(t.root, 'ios/Sources/A.swift'), 1000, 1000)
    const r = run(t.root)
    assert.equal(r.status, 2)
    assert.match(r.out, /no \.dia files under \.coverage-tmp\/ios-dd/)
  } finally {
    t.done()
  }
})
