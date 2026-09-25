// scripts/gen-codes.mjs: the four platform mirrors are exactly what the
// registry generates, so a hand edit to a mirror (or a registry change without
// regenerating) fails here.

import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { CONTRACTS_DIR, REGISTRY_PATH, SDK_ROOT } from '../scripts/lib/paths.mjs'
import { GENERATED_NOTE, MIRRORS, camelName, constName, entriesFor, main, renderMirrors, staleMirrors, wrap, writeMirrors } from '../scripts/gen-codes.mjs'

const GEN = path.join(CONTRACTS_DIR, 'scripts', 'gen-codes.mjs')
const registry = JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8'))

// A copy of the registry and the four mirrors, laid out like the repo, under
// contracts/out (git-ignored).
function makeTree() {
  const base = path.join(CONTRACTS_DIR, 'out')
  fs.mkdirSync(base, { recursive: true })
  const root = fs.mkdtempSync(path.join(base, '.gen-codes-'))
  const contracts = path.join(root, 'contracts')
  fs.mkdirSync(contracts)
  for (const f of ['failure-codes.json', 'failure-codes.sources.json']) fs.copyFileSync(path.join(CONTRACTS_DIR, f), path.join(contracts, f))
  for (const m of MIRRORS) {
    fs.mkdirSync(path.dirname(path.join(root, m.path)), { recursive: true })
    fs.copyFileSync(path.join(SDK_ROOT, m.path), path.join(root, m.path))
  }
  return { root, contracts, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) }
}

const run = (args) => spawnSync(process.execPath, [GEN, ...args], { encoding: 'utf8' })

test('every committed mirror equals the generator output', () => {
  assert.deepEqual(staleMirrors(registry, SDK_ROOT), [], 'run: node contracts/scripts/gen-codes.mjs')
  const r = run(['--check'])
  assert.equal(r.status, 0, r.stderr)
})

test('each mirror holds exactly the codes of its clients, in registry order, under the generated header', () => {
  const clientsOf = { core: ['core', 'react-native'], ios: ['ios'], android: ['android'], flutter: ['flutter'] }
  for (const { mirror, text } of renderMirrors(registry, SDK_ROOT)) {
    const expected = registry.filter((e) => e.clients.some((c) => clientsOf[mirror.platform].includes(c))).map((e) => e.code)
    assert.deepEqual(entriesFor(mirror, registry).map((e) => e.code), expected, mirror.platform)
    assert.ok(text.split('\n', 1)[0].endsWith(GENERATED_NOTE), `${mirror.platform}: first line is the generated note`)
    const quoted = [...text.matchAll(/['"]([a-z][a-z0-9]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*)['"]/g)].map((m) => m[1])
    assert.deepEqual(quoted, expected, `${mirror.platform}: codes in the file`)
  }
})

test('the mirrors keep the names the call sites use', () => {
  const [ts, swift, kotlin, dart] = renderMirrors(registry, SDK_ROOT).map((m) => m.text)
  assert.match(ts, /^export const FAILURE_CODES = \[$/m)
  assert.match(ts, /^export type FailureCode = \(typeof FAILURE_CODES\)\[number\]$/m)
  assert.match(swift, /^public enum SellwildFailureCode: String, CaseIterable \{$/m)
  assert.match(swift, /^ {4}case configFetchHttp = "config\.fetch\.http"$/m)
  assert.match(kotlin, /^object SellwildFailureCode \{$/m)
  assert.match(kotlin, /^ {4}const val CONFIG_FETCH_HTTP = "config\.fetch\.http"$/m)
  assert.match(kotlin, /^ {4}val ALL: List<String> = listOf\($/m)
  assert.match(kotlin, /^object SellwildFailureComponent \{$/m)
  assert.match(kotlin, /^object SellwildFailureSeverity \{$/m)
  assert.match(dart, /^abstract final class SellwildFailureCode \{$/m)
  assert.match(dart, /^ {2}static const String configFetchHttp = 'config\.fetch\.http';$/m)
  assert.match(dart, /^ {2}static const List<String> all = \[$/m)
  assert.match(dart, /^abstract final class SellwildFailureComponent \{$/m)
  assert.match(dart, /^\/\/ coverage:ignore-file /m)
})

test('a hand edit to a mirror is caught, and regenerating repairs it', () => {
  const tree = makeTree()
  try {
    const kt = path.join(tree.root, MIRRORS[2].path)
    fs.writeFileSync(kt, fs.readFileSync(kt, 'utf8').replace('    const val CONFIG_FETCH_HTTP', '    const val HAND_ADDED = "config.hand.added"\n    const val CONFIG_FETCH_HTTP'))
    fs.rmSync(path.join(tree.root, MIRRORS[3].path))

    const stale = staleMirrors(registry, tree.root)
    assert.deepEqual(stale, [
      { path: MIRRORS[2].path, reason: 'differs from the generated text' },
      { path: MIRRORS[3].path, reason: 'missing' },
    ])
    const check = run(['--check', '--contracts-dir', tree.contracts])
    assert.equal(check.status, 1)
    assert.match(check.stderr, /stale mirror: android\/.*SellwildFailureCode\.kt/)

    const write = run(['--contracts-dir', tree.contracts])
    assert.equal(write.status, 0, write.stderr)
    assert.match(write.stdout, /wrote .*SellwildFailureCode\.kt/)
    assert.equal(run(['--check', '--contracts-dir', tree.contracts]).status, 0)
    assert.equal(fs.readFileSync(kt, 'utf8'), fs.readFileSync(path.join(SDK_ROOT, MIRRORS[2].path), 'utf8'))
    assert.equal(fs.existsSync(path.join(tree.contracts, '.lock')), false, 'the lock is released')

    const again = run(['--contracts-dir', tree.contracts])
    assert.equal(again.stdout, 'mirrors are up to date\n')
  } finally {
    tree.cleanup()
  }
})

test('a whitespace-only hand edit is caught too: the check is byte for byte', () => {
  const tree = makeTree()
  try {
    const swift = path.join(tree.root, MIRRORS[1].path)
    const text = fs.readFileSync(swift, 'utf8')
    for (const edited of [`${text}\n`, `${text.trimEnd()}`, text.replace('\n', ' \n'), text.replace(/\n/g, '\r\n')]) {
      fs.writeFileSync(swift, edited)
      assert.deepEqual(staleMirrors(registry, tree.root), [{ path: MIRRORS[1].path, reason: 'differs from the generated text' }])
      assert.equal(run(['--check', '--contracts-dir', tree.contracts]).status, 1)
    }
  } finally {
    tree.cleanup()
  }
})

test('an invalid registry generates nothing', () => {
  const unsorted = [registry[1], registry[0], ...registry.slice(2)]
  assert.throws(() => renderMirrors(unsorted, SDK_ROOT), /out of order/)
  const tree = makeTree()
  try {
    fs.writeFileSync(path.join(tree.contracts, 'failure-codes.json'), JSON.stringify(unsorted))
    const before = fs.readFileSync(path.join(tree.root, MIRRORS[0].path), 'utf8')
    const r = run(['--contracts-dir', tree.contracts])
    assert.equal(r.status, 1)
    assert.match(r.stderr, /failure-codes\.json is invalid/)
    assert.equal(fs.readFileSync(path.join(tree.root, MIRRORS[0].path), 'utf8'), before)
  } finally {
    tree.cleanup()
  }
})

test('names and wrapping', () => {
  assert.equal(camelName('ad.audio_guard.exception'), 'adAudioGuardException')
  assert.equal(camelName('config.refresh_interval.invalid'), 'configRefreshIntervalInvalid')
  assert.equal(constName('widget.webview_load.http'), 'WIDGET_WEBVIEW_LOAD_HTTP')
  assert.deepEqual(wrap('aa bb cc', '// ', 8), ['// aa bb', '// cc'])
  assert.deepEqual(wrap('averyveryverylongword x', '// ', 8), ['// averyveryverylongword', '// x'], 'a long word gets its own line')
  assert.deepEqual(wrap('', '// ', 8), [])
})

test('unknown arguments and a --contracts-dir with no value are refused', () => {
  const r = run(['--nope'])
  assert.equal(r.status, 1)
  assert.match(r.stderr, /unknown argument --nope/)
  const bare = run(['--check', '--contracts-dir'])
  assert.equal(bare.status, 1)
  assert.equal(bare.stderr, 'gen-codes: --contracts-dir needs a value\n')
})

test('a Dart declaration of up to 80 characters stays on one line; a longer one wraps', () => {
  const dart = MIRRORS.find((m) => m.platform === 'flutter')
  const entry = (code) => ({ code, component: 'listings', severity: 'warn', clients: ['flutter'], description: 'A probe entry for the wrap test.' })
  const at80 = entry('listings.abcdefghij.invalid')
  const at81 = entry('listings.abcde_fghij.invalid')
  const oneLine = (e) => `  static const String ${camelName(e.code)} = '${e.code}';`
  assert.equal(oneLine(at80).length, 80)
  assert.equal(oneLine(at81).length, 81)

  const lines = dart.render([at80, at81]).split('\n')
  assert.ok(lines.includes(oneLine(at80)), 'exactly 80 characters: one line')
  assert.ok(!lines.includes(oneLine(at81)), '81 characters: not one line')
  const at = lines.indexOf(`  static const String ${camelName(at81.code)} =`)
  assert.ok(at > 0, '81 characters: the name ends the first line')
  assert.equal(lines[at + 1], `      '${at81.code}';`)
})

test('writeMirrors keeps its temp files in the contracts dir, and refuses to run without one', (t) => {
  const tree = makeTree()
  try {
    const ts = path.join(tree.root, MIRRORS[0].path)
    fs.writeFileSync(ts, 'hand edit\n')
    assert.throws(() => writeMirrors(registry, tree.root), /writeMirrors needs the contracts dir/)
    assert.equal(fs.readFileSync(ts, 'utf8'), 'hand edit\n', 'nothing written')

    const rename = t.mock.method(fs, 'renameSync')
    assert.deepEqual(writeMirrors(registry, tree.root, tree.contracts), [MIRRORS[0].path])
    assert.equal(rename.mock.callCount(), 1)
    const [from, to] = rename.mock.calls[0].arguments
    assert.equal(to, ts)
    assert.equal(path.dirname(from), tree.contracts, 'not core/src/failures/')
    assert.deepEqual(staleMirrors(registry, tree.root), [])
    assert.deepEqual(fs.readdirSync(path.dirname(ts)).filter((f) => f.includes('.tmp-')), [])
  } finally {
    tree.cleanup()
  }
})

test('the gen-codes CLI writes its temp files in the --contracts-dir it was given', async (t) => {
  const tree = makeTree()
  try {
    const kt = path.join(tree.root, MIRRORS[2].path)
    fs.writeFileSync(kt, 'hand edit\n')
    const out = t.mock.method(process.stdout, 'write', () => true)
    const rename = t.mock.method(fs, 'renameSync')
    assert.equal(await main(['--contracts-dir', tree.contracts]), 0)
    assert.equal(out.mock.calls[0].arguments[0], `wrote ${MIRRORS[2].path}\n`)
    const temps = rename.mock.calls.map((c) => c.arguments).filter(([from]) => from.includes('.tmp-'))
    assert.deepEqual(temps.map(([, to]) => to), [kt])
    assert.equal(path.dirname(temps[0][0]), tree.contracts)
    assert.deepEqual(staleMirrors(registry, tree.root), [])
  } finally {
    tree.cleanup()
  }
})
