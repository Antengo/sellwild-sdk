// scripts/add-code.mjs: the only way to change failure-codes.json. It refuses
// bad entries, keeps the registry sorted, records new codes in
// failure-codes.sources.json, regenerates the mirrors, and serializes
// concurrent runs with contracts/.lock. Every run here works on a copy of the
// registry and mirrors under contracts/out (git-ignored).

import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { spawn, spawnSync } from 'node:child_process'
import { CONTRACTS_DIR, REGISTRY_PATH, SDK_ROOT } from '../scripts/lib/paths.mjs'
import { addCode, parseArgs, today } from '../scripts/add-code.mjs'
import { MIRRORS, staleMirrors } from '../scripts/gen-codes.mjs'
import {
  AREAS,
  CLIENTS,
  COMPONENTS,
  LOCK_DEFAULTS,
  LOCK_OPS,
  REASONS,
  SEVERITIES,
  applyChange,
  breakIfStale,
  formatJson,
  normalizeEntry,
  releaseLock,
  tryLock,
  validateEntry,
  validateRegistry,
  withLock,
  writeFileAtomic,
} from '../scripts/lib/registry.mjs'
import { loadSchemas } from '../scripts/lib/schemas.mjs'

const ADD = path.join(CONTRACTS_DIR, 'scripts', 'add-code.mjs')
const SOURCES_PATH = path.join(CONTRACTS_DIR, 'failure-codes.sources.json')
const registryText = fs.readFileSync(REGISTRY_PATH, 'utf8')
const registry = JSON.parse(registryText)

// The committed text format, written out here instead of calling formatJson,
// so a change to formatJson cannot also change what the tests expect.
const jsonText = (value) => `${JSON.stringify(value, null, 2)}\n`

// The local calendar date, built here independently of add-code's today().
const localDate = (d) => [d.getFullYear(), d.getMonth() + 1, d.getDate()].map((n) => String(n).padStart(2, '0')).join('-')

// The `.lock*` entries in a contracts dir, sorted.
const lockEntries = (dir) => fs.readdirSync(dir).filter((f) => f.startsWith('.lock')).sort()

function makeTree() {
  const base = path.join(CONTRACTS_DIR, 'out')
  fs.mkdirSync(base, { recursive: true })
  const root = fs.mkdtempSync(path.join(base, '.add-code-'))
  const contracts = path.join(root, 'contracts')
  fs.mkdirSync(contracts)
  for (const f of ['failure-codes.json', 'failure-codes.sources.json']) fs.copyFileSync(path.join(CONTRACTS_DIR, f), path.join(contracts, f))
  for (const m of MIRRORS) {
    fs.mkdirSync(path.dirname(path.join(root, m.path)), { recursive: true })
    fs.copyFileSync(path.join(SDK_ROOT, m.path), path.join(root, m.path))
  }
  const read = (f) => JSON.parse(fs.readFileSync(path.join(contracts, f), 'utf8'))
  const text = (f) => fs.readFileSync(path.join(contracts, f), 'utf8')
  const snapshot = () => [path.join(contracts, 'failure-codes.json'), path.join(contracts, 'failure-codes.sources.json'), ...MIRRORS.map((m) => path.join(root, m.path))].map((f) => fs.readFileSync(f, 'utf8'))
  return {
    root,
    contracts,
    registry: () => read('failure-codes.json'),
    sources: () => read('failure-codes.sources.json'),
    registryText: () => text('failure-codes.json'),
    sourcesText: () => text('failure-codes.sources.json'),
    snapshot,
    cleanup: () => fs.rmSync(root, { recursive: true, force: true }),
  }
}

// Every run is killed after 15 s (a normal run takes well under 1 s), so a run
// that ignores a short SELLWILD_LOCK_TIMEOUT_MS fails fast instead of waiting 60 s.
function runAdd(tree, args, env = {}, options = {}) {
  return spawnSync(process.execPath, [ADD, ...args, '--contracts-dir', tree.contracts], { encoding: 'utf8', env: { ...process.env, ...env }, timeout: 15_000, ...options })
}

function runAddAsync(tree, args, env = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [ADD, ...args, '--contracts-dir', tree.contracts], { env: { ...process.env, ...env } })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (d) => { stdout += d })
    child.stderr.on('data', (d) => { stderr += d })
    child.on('close', (status) => resolve({ status, stdout, stderr }))
  })
}

const good = {
  code: 'listings.probe.invalid',
  component: 'listings',
  severity: 'warn',
  clients: ['android', 'core'],
  description: 'A probe entry used only by the add-code tests.',
}

// ── Entry checks ─────────────────────────────────────────────────────────────

const BAD = [
  ['a code that fails the format', { code: 'Listings.probe.invalid' }, /does not match <area>\.<operation>\.<reason>/],
  ['a code with two parts', { code: 'listings.probe' }, /does not match/],
  ['a code of 65 characters', { code: `listings.${'a'.repeat(48)}.invalid` }, /longer than 64/],
  ['an unknown area', { code: 'payments.probe.invalid' }, /area must be one of/],
  ['an unknown reason', { code: 'listings.probe.broken' }, /reason must be one of/],
  ['area "client" on another code', { code: 'client.probe.invalid' }, /area "client" is reserved/],
  ['a no-fill code', { code: 'ad.no_fill.missing' }, /never logged/],
  ['a no-bid code', { code: 'ad.no_bid.missing' }, /never logged/],
  ['a nobid code', { code: 'ad.nobid.missing' }, /never logged/],
  ['a no-bids code', { code: 'ad.no_bids.missing' }, /never logged/],
  ['an events-transport code', { code: 'events.flush.network' }, /never logged/],
  ['an area that is not the code\'s', { area: 'feed' }, /area "feed" is not the code's area "listings"/],
  ['an operation that is not the code\'s', { operation: 'other' }, /operation "other" is not the code's operation/],
  ['an unknown component', { component: 'payments' }, /component must be one of/],
  ['component "unknown"', { component: 'unknown' }, /component "unknown" is reserved/],
  ['an unknown severity', { severity: 'info' }, /severity must be one of/],
  ['no clients', { clients: [] }, /clients must be a non-empty list/],
  ['clients as text', { clients: 'core' }, /clients must be a non-empty list/],
  ['an unknown client', { clients: ['core', 'web'] }, /unknown client "web"/],
  ['a duplicate client', { clients: ['core', 'core'] }, /duplicate/],
  ['a short description', { description: 'Too short' }, /shorter than 10/],
  ['a description of 9 characters', { description: 'Probe no.' }, /shorter than 10/],
  ['a description without a period', { description: 'The probe failed and nothing was shown' }, /end with a period/],
  ['a two-line description', { description: 'The probe failed.\nNothing was shown.' }, /one line/],
  ['a description with double spaces', { description: 'The probe  failed.' }, /extra spaces/],
  ['a description that ends a doc comment', { description: 'The probe failed */ badly.' }, /\*\//],
  ['a description that opens a nested Kotlin comment', { description: 'The cache/*.json listing file failed to parse.' }, /"\/\*" \(it would open a nested comment/],
  ['an unknown field', { owner: 'me' }, /unknown field "owner"/],
  ['a missing description', { description: undefined }, /missing field "description"/],
  ['a code that is not text', { code: 42 }, /code must be text/],
  ['a description that is not text', { description: 5 }, /description must be text/],
  ['an operation that fails the pattern', { code: 'listings.probe.invalid', operation: 'Probe' }, /operation must match/],
]

for (const [name, change, message] of BAD) {
  test(`validateEntry refuses ${name}`, () => {
    const entry = normalizeEntry({ ...good, ...change })
    for (const [k, v] of Object.entries(change)) if (v === undefined) delete entry[k]
    const errors = validateEntry(entry)
    assert.ok(errors.some((e) => message.test(e)), `${JSON.stringify(entry)} gave ${JSON.stringify(errors)}`)
  })
}

test('validateEntry accepts a good entry and every committed one', () => {
  assert.deepEqual(validateEntry(normalizeEntry(good)), [])
  assert.deepEqual(validateRegistry(registry), [])
  assert.deepEqual(validateEntry('text'), ['the entry must be a JSON object'])
})

test('validateRegistry reports a bad list without throwing', () => {
  assert.deepEqual(validateRegistry([]), ['the registry must be a non-empty JSON array'])
  assert.deepEqual(validateRegistry({ code: 'a.b.c' }), ['the registry must be a non-empty JSON array'])
  const [first, second] = registry
  // A null or non-object entry (a hand edit) is reported, not a TypeError.
  assert.deepEqual(validateRegistry([first, null]), ['[1] ?: the entry must be a JSON object'])
  assert.deepEqual(validateRegistry([null, first]), ['[0] ?: the entry must be a JSON object'])
  assert.deepEqual(validateRegistry([first, 5, second]), ['[1] ?: the entry must be a JSON object'])
  assert.deepEqual(validateRegistry([first, first]), [`[1] duplicate code ${first.code}`, `[1] ${first.code} is out of order (after ${first.code})`])
  assert.deepEqual(validateRegistry([second, first]), [`[1] ${first.code} is out of order (after ${second.code})`])
})

test('whatever the schema refuses, validateEntry refuses too', () => {
  const { validators } = loadSchemas()
  const schemaCheck = validators['failure-codes']
  for (const [name, change] of BAD) {
    const entry = normalizeEntry({ ...good, ...change })
    for (const [k, v] of Object.entries(change)) if (v === undefined) delete entry[k]
    if (!schemaCheck([entry])) assert.notDeepEqual(validateEntry(entry), [], name)
  }
  assert.ok(schemaCheck([normalizeEntry(good)]))
})

test('validateEntry and the schema draw the length limits in the same place', () => {
  const { validators } = loadSchemas()
  const schemaCheck = validators['failure-codes']
  const LIMITS = [
    ['a code of 64 characters', { code: `listings.${'a'.repeat(47)}.invalid` }, 64, true],
    ['a code of 65 characters', { code: `listings.${'a'.repeat(48)}.invalid` }, 65, false],
    ['a description of 10 characters', { description: 'Probe ran.' }, 10, true],
    ['a description of 9 characters', { description: 'Probe no.' }, 9, false],
  ]
  for (const [name, change, length, ok] of LIMITS) {
    assert.equal(Object.values(change)[0].length, length, name)
    const entry = normalizeEntry({ ...good, ...change })
    assert.equal(schemaCheck([entry]), ok, `the schema on ${name}`)
    assert.deepEqual(validateEntry(entry).length === 0, ok, `validateEntry on ${name}: ${JSON.stringify(validateEntry(entry))}`)
  }
})

test('whatever the schema accepts, validateEntry accepts too (every enum value, every committed entry)', () => {
  const { validators } = loadSchemas()
  const schemaCheck = validators['failure-codes']
  const entries = [
    // area `client` and component `unknown` are reserved for client.code.invalid (refused above, accepted in the registry).
    ...AREAS.filter((a) => a !== 'client').map((area) => ({ ...good, code: `${area}.probe.invalid` })),
    ...REASONS.map((reason) => ({ ...good, code: `listings.probe.${reason}` })),
    ...COMPONENTS.filter((c) => c !== 'unknown').map((component) => ({ ...good, component })),
    ...SEVERITIES.map((severity) => ({ ...good, severity })),
    ...CLIENTS.map((client) => ({ ...good, clients: [client] })),
    { ...good, clients: [...CLIENTS] },
    ...registry,
  ].map(normalizeEntry)
  for (const entry of entries) {
    assert.ok(schemaCheck([entry]), `the schema refused ${JSON.stringify(entry)}`)
    assert.deepEqual(validateEntry(entry), [], JSON.stringify(entry))
  }
})

test('formatJson writes the committed format: 2-space JSON, literal UTF-8, a final newline', () => {
  assert.equal(formatJson({ a: [1, 'é'], b: {} }), '{\n  "a": [\n    1,\n    "é"\n  ],\n  "b": {}\n}\n')
  assert.equal(formatJson(registry), registryText)
  const sourcesText = fs.readFileSync(SOURCES_PATH, 'utf8')
  assert.equal(formatJson(JSON.parse(sourcesText)), sourcesText)
})

test('normalizeEntry fills area, operation and reason from the code and orders fields and clients', () => {
  assert.deepEqual(normalizeEntry(good), {
    code: 'listings.probe.invalid',
    area: 'listings',
    operation: 'probe',
    reason: 'invalid',
    component: 'listings',
    severity: 'warn',
    clients: ['core', 'android'],
    description: 'A probe entry used only by the add-code tests.',
  })
})

test('applyChange: add, re-add, conflict, merge-clients and replace', () => {
  const list = registry.slice(0, 10)
  const added = applyChange(list, good)
  assert.equal(added.action, 'added')
  assert.deepEqual(validateRegistry(added.list), [])
  assert.equal(applyChange(added.list, good).action, 'unchanged')
  assert.throws(() => applyChange(added.list, { ...good, severity: 'error' }), /already in the registry with other values/)
  const merged = applyChange(added.list, { code: good.code, clients: ['ios'] }, 'merge-clients')
  assert.deepEqual(merged.list.find((e) => e.code === good.code).clients, ['core', 'ios', 'android'])
  assert.throws(() => applyChange(added.list, { code: good.code, clients: ['ios'], severity: 'fatal' }, 'merge-clients'), /only adds clients/)
  assert.throws(() => applyChange(list, { code: good.code, clients: ['ios'] }, 'merge-clients'), /not in the registry/)
  const replaced = applyChange(merged.list, { ...good, clients: ['ios'] }, 'replace')
  assert.equal(replaced.action, 'updated')
  assert.deepEqual(replaced.list.find((e) => e.code === good.code).clients, ['ios'])
  assert.throws(() => applyChange(list, good, 'replace'), /not in the registry/)
  assert.throws(() => applyChange(list, good, 'upsert'), /unknown mode/)
  const stored = registry[3]
  assert.equal(applyChange(registry, { ...stored }, 'replace').action, 'unchanged', 'replacing with the stored entry changes nothing')
  assert.equal(applyChange(registry, { code: stored.code, clients: [stored.clients[0]] }, 'merge-clients').action, 'unchanged')
  assert.throws(() => applyChange(list, { component: 'listings' }), /^Error: entry: /, 'an entry with no code is named "entry"')
  assert.equal(normalizeEntry('text'), 'text', 'a non-object is left for validateEntry to refuse')
})

test('a new code sorts into place at the start, the middle and the end', () => {
  const probe = (op) => normalizeEntry({ ...good, code: `listings.${op}.invalid` })
  const list = [probe('bb'), probe('dd'), probe('ff')]
  for (const [code, at] of [['listings.aa.invalid', 0], ['listings.cc.invalid', 1], ['listings.ee.invalid', 2], ['listings.gg.invalid', 3]]) {
    const next = applyChange(list, { ...good, code }).list
    assert.equal(next.findIndex((e) => e.code === code), at, code)
    assert.deepEqual(validateRegistry(next), [], code)
  }
})

test('parseArgs takes a JSON entry, flags, or both (flags win)', () => {
  const parsed = parseArgs([JSON.stringify(good), '--severity', 'error', '--clients=ios, android', '--note', 'why'])
  assert.deepEqual(parsed.entry, { ...good, severity: 'error', clients: ['ios', 'android'] })
  assert.equal(parsed.mode, 'add')
  assert.equal(parsed.note, 'why')
  assert.equal(parsed.contractsDir, CONTRACTS_DIR)
  assert.equal(parseArgs(['--code', 'a.b.c', '--replace']).mode, 'replace')
  assert.equal(parseArgs(['--code', 'a.b.c', '--merge-clients']).mode, 'merge-clients')
  assert.throws(() => parseArgs(['--code', 'a.b.c', '--replace', '--merge-clients']), /cannot be combined/)
  assert.throws(() => parseArgs(['--colour', 'red']), /unknown flag --colour/)
  assert.throws(() => parseArgs(['--code']), /--code needs a value/)
  assert.throws(() => parseArgs(['{nope']), /not valid JSON/)
  assert.throws(() => parseArgs(['[1]']), /must be a JSON object/)
  assert.throws(() => parseArgs(['{}', '{}']), /one JSON entry at most/)
  assert.throws(() => parseArgs(['--severity', 'warn']), /no code given/)
})

// ── The command ──────────────────────────────────────────────────────────────

test('bad entries are refused and nothing is written', () => {
  const tree = makeTree()
  try {
    const before = tree.snapshot()
    for (const args of [
      [JSON.stringify({ ...good, code: 'listings.probe' })],
      [JSON.stringify({ ...good, clients: ['web'] })],
      [JSON.stringify({ ...good, component: 'payments' })],
      [JSON.stringify({ ...good, severity: 'info' })],
      [JSON.stringify({ ...good, area: 'feed' })],
      ['--code', 'config.fetch.http', '--component', 'listings', '--severity', 'error', '--clients', 'core', '--description', 'Clashes with the stored entry.'],
      ['--replace', '--code', 'listings.probe.invalid', '--component', 'listings', '--severity', 'warn', '--clients', 'core', '--description', 'Not in the registry yet.'],
    ]) {
      const r = runAdd(tree, args)
      assert.equal(r.status, 1, `${args.join(' ')}\n${r.stdout}`)
      assert.match(r.stderr, /^add-code: /)
      assert.deepEqual(tree.snapshot(), before, args.join(' '))
      assert.equal(fs.existsSync(path.join(tree.contracts, '.lock')), false)
    }
  } finally {
    tree.cleanup()
  }
})

test('a new code lands in order, is recorded in sources, and reaches only its mirrors', () => {
  const tree = makeTree()
  try {
    const [, , , iosBefore] = tree.snapshot()
    const sourcesBefore = tree.sources()
    const dayBefore = localDate(new Date())
    const r = runAdd(tree, [JSON.stringify(good), '--note', 'Probe for the add-code test.'])
    const dayAfter = localDate(new Date())
    assert.equal(r.status, 0, r.stderr)
    assert.match(r.stdout, /listings\.probe\.invalid: added; regenerated core\/src\/failures\/codes\.ts, android\//)

    const codes = tree.registry().map((e) => e.code)
    assert.ok(codes.includes(good.code))
    assert.deepEqual(codes, [...codes].sort())
    assert.deepEqual(validateRegistry(tree.registry()), [])
    const record = tree.sources().added.at(-1)
    assert.equal(record.code, good.code)
    assert.equal(record.note, 'Probe for the add-code test.')
    assert.ok([dayBefore, dayAfter].includes(record.date), `${record.date} is today's local date`)

    // Both files are written in the committed format, with only the new code added.
    const expectedList = [...registry, normalizeEntry(good)].sort((a, b) => (a.code < b.code ? -1 : 1))
    assert.equal(tree.registryText(), jsonText(expectedList))
    assert.equal(tree.sourcesText(), jsonText({ ...sourcesBefore, added: [...sourcesBefore.added, record] }))

    const [, , , iosAfter] = tree.snapshot()
    assert.ok(iosAfter === iosBefore, 'ios is not a client, so its mirror is untouched')
    assert.match(fs.readFileSync(path.join(tree.root, MIRRORS[0].path), 'utf8'), /'listings\.probe\.invalid',/)
    assert.match(fs.readFileSync(path.join(tree.root, MIRRORS[2].path), 'utf8'), /LISTINGS_PROBE_INVALID = "listings\.probe\.invalid"/)
    assert.deepEqual(staleMirrors(tree.registry(), tree.root), [])

    const again = runAdd(tree, [JSON.stringify(good)])
    assert.equal(again.status, 0, again.stderr)
    assert.equal(again.stdout, 'listings.probe.invalid: unchanged\n')
    assert.equal(tree.sources().added.filter((a) => a.code === good.code).length, 1)
  } finally {
    tree.cleanup()
  }
})

test('--merge-clients adds a client and --replace drops one, regenerating the mirrors', () => {
  const tree = makeTree()
  try {
    const sourcesText = tree.sourcesText()
    const merge = runAdd(tree, ['--merge-clients', '--code', 'config.url.invalid', '--clients', 'android'])
    assert.equal(merge.status, 0, merge.stderr)
    assert.equal(merge.stdout, 'config.url.invalid: updated; regenerated android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailureCode.kt\n')
    assert.deepEqual(tree.registry().find((e) => e.code === 'config.url.invalid').clients, ['ios', 'android'])
    assert.match(fs.readFileSync(path.join(tree.root, MIRRORS[2].path), 'utf8'), /CONFIG_URL_INVALID/)
    assert.equal(tree.sourcesText(), sourcesText, 'a merge is not a new code: sources.json is untouched')

    const entry = registry.find((e) => e.code === 'config.url.invalid')
    const replace = runAdd(tree, ['--replace', JSON.stringify({ ...entry, clients: ['ios'] })])
    assert.equal(replace.status, 0, replace.stderr)
    assert.equal(tree.sourcesText(), sourcesText, 'a replace is not a new code: sources.json is untouched')
    assert.equal(tree.registryText(), registryText, 'back to the committed registry, byte for byte')
    assert.doesNotMatch(fs.readFileSync(path.join(tree.root, MIRRORS[2].path), 'utf8'), /CONFIG_URL_INVALID/)
    assert.deepEqual(staleMirrors(tree.registry(), tree.root), [])
  } finally {
    tree.cleanup()
  }
})

test('concurrent runs all land: the lock serializes them', async () => {
  const tree = makeTree()
  try {
    const probes = ['alpha', 'bravo', 'charlie', 'delta'].map((op) => ({ ...good, code: `listings.probe_${op}.invalid` }))
    // Each run keeps the lock 300 ms after writing, so the others must wait.
    const results = await Promise.all(probes.map((p) => runAddAsync(tree, [JSON.stringify(p)], { SELLWILD_ADD_CODE_HOLD_MS: '300' })))
    for (const r of results) assert.equal(r.status, 0, r.stderr)

    const codes = tree.registry().map((e) => e.code)
    for (const p of probes) assert.ok(codes.includes(p.code), `${p.code} was lost`)
    assert.equal(codes.length, registry.length + probes.length)
    assert.deepEqual(validateRegistry(tree.registry()), [])
    assert.deepEqual(tree.sources().added.slice(-4).map((a) => a.code).sort(), probes.map((p) => p.code).sort())
    assert.deepEqual(staleMirrors(tree.registry(), tree.root), [])
    assert.equal(fs.existsSync(path.join(tree.contracts, '.lock')), false)
  } finally {
    tree.cleanup()
  }
})

test('a lock older than the stale limit is broken', () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    fs.mkdirSync(lock)
    fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({ token: 'dead', pid: 999999, startedAt: '2026-01-01T00:00:00.000Z' }))
    const old = new Date(Date.now() - 10 * 60_000)
    fs.utimesSync(lock, old, old)

    const r = runAdd(tree, [JSON.stringify(good)])
    assert.equal(r.status, 0, r.stderr)
    assert.ok(tree.registry().some((e) => e.code === good.code))
    assert.equal(fs.existsSync(lock), false)
    assert.deepEqual(fs.readdirSync(tree.contracts).filter((f) => f.startsWith('.lock')), [])
  } finally {
    tree.cleanup()
  }
})

test('a live lock that is never released times out and nothing is written', () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    fs.mkdirSync(lock)
    fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({ token: 'live', pid: 4242, startedAt: new Date().toISOString() }))
    const before = tree.snapshot()

    // The kill at 10 s ends a run that ignores the 400 ms timeout (the 60 s default).
    const started = Date.now()
    const r = runAdd(tree, [JSON.stringify(good)], { SELLWILD_LOCK_TIMEOUT_MS: '400' }, { timeout: 10_000 })
    const elapsed = Date.now() - started
    assert.equal(r.status, 1, r.stderr)
    assert.match(r.stderr, /could not take .*\.lock within 400 ms \(held by pid 4242/)
    // At least the timeout; the upper bound only leaves room for node start-up
    // on a busy machine. The fake-clock tests below pin the wait exactly.
    assert.ok(elapsed >= 400 && elapsed < 10_000, `waited ${elapsed} ms for a 400 ms timeout`)
    assert.deepEqual(tree.snapshot(), before)
    assert.equal(fs.existsSync(lock), true, "another run's lock is left alone")
  } finally {
    tree.cleanup()
  }
})

test('withLock releases the lock when the work throws', async () => {
  const tree = makeTree()
  try {
    await assert.rejects(withLock(tree.contracts, () => { throw new Error('boom') }), /boom/)
    assert.equal(fs.existsSync(path.join(tree.contracts, '.lock')), false)
    assert.equal(await withLock(tree.contracts, () => 7), 7)
  } finally {
    tree.cleanup()
  }
})

test('withLock passes on errors other than a held lock', async () => {
  const tree = makeTree()
  try {
    // A contracts dir that does not exist: mkdir fails with ENOENT, not EEXIST.
    await assert.rejects(withLock(path.join(tree.root, 'missing', 'contracts'), () => 1, { timeoutMs: 100 }), /ENOENT/)
  } finally {
    tree.cleanup()
  }
})

// The constants only; the fake-clock tests below check that withLock obeys them.
test('LOCK_DEFAULTS is frozen at a 60 s wait, a 120 s stale limit and a 50 ms retry', () => {
  assert.deepEqual({ ...LOCK_DEFAULTS }, { timeoutMs: 60_000, staleMs: 120_000, retryMs: 50 })
  assert.ok(Object.isFrozen(LOCK_DEFAULTS))
})

test('a bad entry is refused at once, without waiting for a held lock', () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    fs.mkdirSync(lock)
    fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({ token: 'live', pid: 4242, startedAt: new Date().toISOString() }))
    const started = Date.now()
    // Were the entry checked only under the lock, this run would wait the
    // whole 30 s and then fail on the lock; the kill at 10 s ends it first.
    const r = spawnSync(process.execPath, [ADD, JSON.stringify({ ...good, severity: 'info' }), '--contracts-dir', tree.contracts], {
      encoding: 'utf8',
      env: { ...process.env, SELLWILD_LOCK_TIMEOUT_MS: '30000' },
      timeout: 10_000,
    })
    assert.equal(r.status, 1, r.stderr)
    assert.match(r.stderr, /^add-code: listings\.probe\.invalid: severity must be one of/)
    assert.doesNotMatch(r.stderr, /could not take/)
    assert.ok(Date.now() - started < 10_000)
    assert.equal(fs.existsSync(lock), true, "another run's lock is left alone")
  } finally {
    tree.cleanup()
  }
})

test('an already invalid registry is refused under the lock, and nothing is written', () => {
  const tree = makeTree()
  try {
    const file = path.join(tree.contracts, 'failure-codes.json')
    fs.writeFileSync(file, JSON.stringify([registry[1], registry[0], ...registry.slice(2)]))
    const before = tree.snapshot()
    const r = runAdd(tree, [JSON.stringify(good)])
    assert.equal(r.status, 1)
    assert.match(r.stderr, /failure-codes\.json is already invalid, fix it first:\n {2}\[1\] .* is out of order/)
    assert.deepEqual(tree.snapshot(), before)
    assert.equal(fs.existsSync(path.join(tree.contracts, '.lock')), false)
  } finally {
    tree.cleanup()
  }
})

test('a sources file with no added list gets one', () => {
  const tree = makeTree()
  try {
    const file = path.join(tree.contracts, 'failure-codes.sources.json')
    const { added, ...rest } = tree.sources()
    assert.ok(Array.isArray(added))
    fs.writeFileSync(file, JSON.stringify(rest))
    const r = runAdd(tree, [JSON.stringify(good)])
    assert.equal(r.status, 0, r.stderr)
    assert.deepEqual(tree.sources().added.map((a) => [a.code, a.note]), [[good.code, 'Added with scripts/add-code.mjs.']])
  } finally {
    tree.cleanup()
  }
})

test('the added date is the local calendar date of the clock', async () => {
  const tree = makeTree()
  try {
    const second = { ...good, code: 'listings.probe_two.invalid' }
    const first = await addCode({ entry: good, contractsDir: tree.contracts, now: () => new Date(2026, 0, 5, 23, 59, 59) })
    assert.equal(first.action, 'added')
    await addCode({ entry: second, contractsDir: tree.contracts, now: () => new Date(2026, 11, 31, 0, 0, 1) })
    assert.deepEqual(tree.sources().added.slice(-2).map((a) => [a.code, a.date]), [[good.code, '2026-01-05'], [second.code, '2026-12-31']])
    assert.equal(today(new Date(2027, 8, 9, 12)), '2027-09-09')
    assert.equal(today(), localDate(new Date()))
  } finally {
    tree.cleanup()
  }
})

test('a leftover added record for the new code (a run that died after writing sources) is replaced, not kept', () => {
  const tree = makeTree()
  try {
    const file = path.join(tree.contracts, 'failure-codes.sources.json')
    const sources = tree.sources()
    const leftover = { code: good.code, date: '2020-01-01', note: 'Left by a run that died.' }
    fs.writeFileSync(file, jsonText({ ...sources, added: [leftover, ...sources.added] }))
    const r = runAdd(tree, [JSON.stringify(good), '--note', 'The real record.'])
    assert.equal(r.status, 0, r.stderr)
    const records = tree.sources().added.filter((a) => a.code === good.code)
    assert.deepEqual(records.map((a) => a.note), ['The real record.'])
    assert.deepEqual(tree.sources().added.slice(0, -1), sources.added, 'the other records are kept, in order')
  } finally {
    tree.cleanup()
  }
})

test('SELLWILD_LOCK_STALE_MS sets the stale limit', () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    fs.mkdirSync(lock)
    fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({ token: 'dead', pid: 999999, startedAt: new Date().toISOString() }))
    const old = new Date(Date.now() - 5_000)
    fs.utimesSync(lock, old, old)
    // 5 s old: live under the 120 s default, stale under a 1 s limit.
    const waited = runAdd(tree, [JSON.stringify(good)], { SELLWILD_LOCK_TIMEOUT_MS: '200' })
    assert.equal(waited.status, 1)
    assert.match(waited.stderr, /could not take/)
    const broke = runAdd(tree, [JSON.stringify(good)], { SELLWILD_LOCK_TIMEOUT_MS: '200', SELLWILD_LOCK_STALE_MS: '1000' })
    assert.equal(broke.status, 0, broke.stderr)
    assert.equal(fs.existsSync(lock), false)
  } finally {
    tree.cleanup()
  }
})

test('breakIfStale on disk: a stale lock with no owner file is moved aside and removed', () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    fs.mkdirSync(lock)
    const old = new Date(Date.now() - 10_000)
    fs.utimesSync(lock, old, old)
    assert.equal(breakIfStale(lock, 60_000), 'fresh')
    assert.equal(breakIfStale(lock, 1_000), 'broken')
    assert.deepEqual(fs.readdirSync(tree.contracts).filter((f) => f.startsWith('.lock')), [])
    assert.equal(breakIfStale(lock, 1_000), 'gone')
  } finally {
    tree.cleanup()
  }
})

test('a holder whose lock was stranded aside removes only its own moved lock on release', async () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    const theirs = path.join(tree.contracts, '.lock.stale-1-1')
    fs.mkdirSync(theirs)
    fs.writeFileSync(path.join(theirs, 'owner.json'), JSON.stringify({ token: 'someone-else' }))
    const result = await withLock(tree.contracts, () => {
      // A breaker moved this lock aside and a third run took the name.
      fs.renameSync(lock, path.join(tree.contracts, '.lock.stale-2-2'))
      fs.mkdirSync(lock)
      fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({ token: 'third-run' }))
      return 'done'
    })
    assert.equal(result, 'done')
    assert.deepEqual(fs.readdirSync(tree.contracts).filter((f) => f.startsWith('.lock')).sort(), ['.lock', '.lock.stale-1-1'])
    assert.equal(JSON.parse(fs.readFileSync(path.join(lock, 'owner.json'), 'utf8')).token, 'third-run', "the third run's lock is left alone")
  } finally {
    tree.cleanup()
  }
})

test('a lock with an unreadable owner file is waited for, then reported as held by an unknown run', () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    fs.mkdirSync(lock)
    fs.writeFileSync(path.join(lock, 'owner.json'), 'not json')
    const r = runAdd(tree, [JSON.stringify(good)], { SELLWILD_LOCK_TIMEOUT_MS: '200' })
    assert.equal(r.status, 1)
    assert.match(r.stderr, /held by an unknown run/)
    assert.equal(fs.readFileSync(path.join(lock, 'owner.json'), 'utf8'), 'not json', 'the fresh lock is left alone')
  } finally {
    tree.cleanup()
  }
})

test('an empty .lock directory is not a lock (no run leaves one): the run takes it', () => {
  const tree = makeTree()
  try {
    fs.mkdirSync(path.join(tree.contracts, '.lock'))
    const r = runAdd(tree, [JSON.stringify(good)], { SELLWILD_LOCK_TIMEOUT_MS: '200' })
    assert.equal(r.status, 0, r.stderr)
    assert.ok(tree.registry().some((e) => e.code === good.code))
    assert.deepEqual(lockEntries(tree.contracts), [])
  } finally {
    tree.cleanup()
  }
})

// ── tryLock and releaseLock ──────────────────────────────────────────────────

const errno = (code) => Object.assign(new Error(code), { code })

test('tryLock: the lock appears with its owner file already in it', () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    const seen = []
    const ops = {
      ...LOCK_OPS,
      rename: (from, to) => {
        seen.push(JSON.parse(fs.readFileSync(path.join(from, 'owner.json'), 'utf8')).token)
        LOCK_OPS.rename(from, to)
      },
    }
    assert.equal(tryLock(lock, 'mine', ops), true)
    assert.deepEqual(seen, ['mine'], 'the owner file was in place before the rename made the lock')
    assert.equal(JSON.parse(fs.readFileSync(path.join(lock, 'owner.json'), 'utf8')).pid, process.pid)
    assert.deepEqual(lockEntries(tree.contracts), ['.lock'], 'no temp directory is left')

    // Held: false, the holder's lock untouched, the temp directory removed.
    assert.equal(tryLock(lock, 'other'), false)
    assert.equal(LOCK_OPS.owner(lock), 'mine')
    assert.deepEqual(lockEntries(tree.contracts), ['.lock'])

    assert.equal(releaseLock(lock, 'mine'), 'released')
    assert.deepEqual(lockEntries(tree.contracts), [])
  } finally {
    tree.cleanup()
  }
})

test('tryLock: a failed owner write leaves no lock and no temp directory behind', async () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    const ops = { ...LOCK_OPS, write: () => { throw errno('ENOSPC') } }
    assert.throws(() => tryLock(lock, 'mine', ops), /ENOSPC/)
    assert.deepEqual(lockEntries(tree.contracts), [])
    let ran = false
    await assert.rejects(withLock(tree.contracts, () => { ran = true }, { ops }), /ENOSPC/)
    assert.equal(ran, false)
    assert.deepEqual(lockEntries(tree.contracts), [], 'nothing blocks the next run')
    assert.equal(await withLock(tree.contracts, () => 'next'), 'next')
  } finally {
    tree.cleanup()
  }
})

test('tryLock: a rename error other than a held lock is thrown, and the temp directory removed', () => {
  const tree = makeTree()
  try {
    const lock = path.join(tree.contracts, '.lock')
    fs.writeFileSync(lock, 'a file, not a lock directory')
    assert.throws(() => tryLock(lock, 'mine'), (e) => e.code === 'ENOTDIR')
    assert.deepEqual(lockEntries(tree.contracts), ['.lock'])
    // EEXIST (Linux) counts as held, like ENOTEMPTY (macOS).
    assert.equal(tryLock(lock, 'mine', { ...LOCK_OPS, rename: () => { throw errno('EEXIST') } }), false)
    assert.deepEqual(lockEntries(tree.contracts), ['.lock'])
  } finally {
    tree.cleanup()
  }
})

test('releaseLock plays out every race and removes only what holds its token', () => {
  // Our own move-aside name ends in our pid and the time; it reads as `.lock.free` here.
  const short = (p) => path.basename(p).replace(new RegExp(`^(\\.lock\\.free)-${process.pid}-\\d+$`), '$1')
  const fake = ({ owners, list = [], failRenames = [] }) => {
    const calls = []
    let renames = 0
    return {
      calls,
      ops: {
        owner: (dir) => owners[short(dir)] ?? null,
        rename: (a, b) => {
          renames += 1
          if (failRenames.includes(renames)) throw errno('ENOENT')
          calls.push(`rename ${short(a)} -> ${short(b)}`)
        },
        remove: (d) => calls.push(`remove ${short(d)}`),
        list: () => list,
      },
    }
  }
  const lock = '/x/.lock'

  let f = fake({ owners: { '.lock': 'me', '.lock.free': 'me' } })
  assert.equal(releaseLock(lock, 'me', f.ops), 'released')
  assert.deepEqual(f.calls, ['rename .lock -> .lock.free', 'remove .lock.free'], 'moved aside first, so .lock never sits empty')

  // A breaker had moved ours aside (stranded) and a third run holds .lock.
  f = fake({ owners: { '.lock': 'third', '.lock.stale-1-1': 'me', '.lock.stale-2-2': 'else' }, list: ['.lock', '.lock.new-abc', '.lock.stale-1-1', '.lock.stale-2-2', 'other'] })
  assert.equal(releaseLock(lock, 'me', f.ops), 'moved')
  assert.deepEqual(f.calls, ['remove .lock.stale-1-1'])

  // Between our check and our move, a breaker moved ours and a third run took the name: put its lock back.
  f = fake({ owners: { '.lock': 'me', '.lock.free': 'third', '.lock.stale-1-1': 'me' }, list: ['.lock', '.lock.stale-1-1'] })
  assert.equal(releaseLock(lock, 'me', f.ops), 'restored')
  assert.deepEqual(f.calls, ['rename .lock -> .lock.free', 'rename .lock.free -> .lock', 'remove .lock.stale-1-1'])

  // ...and a fourth run took the name before it could go back: it stays aside for its holder.
  f = fake({ owners: { '.lock': 'me', '.lock.free': 'third', '.lock.stale-1-1': 'me' }, list: ['.lock', '.lock.free-0-9', '.lock.stale-1-1'], failRenames: [2] })
  assert.equal(releaseLock(lock, 'me', f.ops), 'stranded')
  assert.deepEqual(f.calls, ['rename .lock -> .lock.free', 'remove .lock.stale-1-1'])

  // A breaker moved ours between the check and the move: the scan finds it.
  f = fake({ owners: { '.lock': 'me', '.lock.stale-1-1': 'me' }, list: ['.lock.stale-1-1'], failRenames: [1] })
  assert.equal(releaseLock(lock, 'me', f.ops), 'moved')
  assert.deepEqual(f.calls, ['remove .lock.stale-1-1'])

  // A lock stranded by another run's release (.free-) is found by its holder.
  f = fake({ owners: { '.lock': 'else', '.lock.free-0-3': 'me' }, list: ['.lock', '.lock.free-0-3'] })
  assert.equal(releaseLock(lock, 'me', f.ops), 'moved')
  assert.deepEqual(f.calls, ['remove .lock.free-0-3'])

  f = fake({ owners: { '.lock': 'else' }, list: ['.lock'] })
  assert.equal(releaseLock(lock, 'me', f.ops), 'lost')
  assert.deepEqual(f.calls, [])
})

test('breakIfStale plays out every race without taking a live lock', () => {
  const calls = []
  const short = (p) => path.basename(p).replace(/-\d+-\d+$/, '')
  const ops = (over) => ({
    age: () => 999_999,
    owner: () => 'dead',
    rename: (a, b) => calls.push(`rename ${short(a)} -> ${short(b)}`),
    remove: (d) => calls.push(`remove ${short(d)}`),
    ...over,
  })
  const lock = '/x/.lock'
  assert.equal(breakIfStale(lock, 1000, ops({ age: () => 10 })), 'fresh')
  assert.equal(breakIfStale(lock, 1000, ops({ age: () => { throw new Error('ENOENT') } })), 'gone')
  assert.equal(breakIfStale(lock, 1000, ops({ rename: () => { throw new Error('ENOENT') } })), 'raced')

  calls.length = 0
  assert.equal(breakIfStale(lock, 1000, ops()), 'broken')
  assert.deepEqual(calls, ['rename .lock -> .lock.stale', 'remove .lock.stale'])

  // Another run replaced the stale lock between the check and the move: put its lock back.
  calls.length = 0
  assert.equal(breakIfStale(lock, 1000, ops({ owner: (dir) => (dir.includes('.stale-') ? 'fresh-run' : 'dead') })), 'restored')
  assert.deepEqual(calls, ['rename .lock -> .lock.stale', 'rename .lock.stale -> .lock'])

  // ...and a third run took the name before it could be put back.
  calls.length = 0
  let renames = 0
  const third = ops({
    owner: (dir) => (dir.includes('.stale-') ? 'fresh-run' : 'dead'),
    rename: (a, b) => {
      renames += 1
      if (renames === 2) throw new Error('ENOTEMPTY')
      calls.push(`rename ${short(a)} -> ${short(b)}`)
    },
  })
  // The moved lock belongs to a live run: it is left for that run to remove.
  assert.equal(breakIfStale(lock, 1000, third), 'stranded')
  assert.deepEqual(calls, ['rename .lock -> .lock.stale'])
})

// ── The wait, on a fake clock ────────────────────────────────────────────────

// A contracts dir that does not exist: every lock operation below is a fake.
const FAKE_DIR = path.join(CONTRACTS_DIR, 'out', '.no-such-dir', 'contracts')

// Lock ops where another run holds `.lock` until a stale-lock breaker moves it
// aside. The clock is fake: only the wait between tries moves it. `age` is the
// held lock's age in ms.
function heldLock({ age = 0 } = {}) {
  const start = 1_700_000_000_000
  const state = { t: start, tries: 0, sleeps: [], broken: 0, held: true }
  const ops = {
    now: () => state.t,
    sleep: async (ms) => {
      state.sleeps.push(ms)
      state.t += ms
    },
    age: () => age,
    owner: () => 'other-run',
    mkdtemp: (prefix) => `${prefix}fake`,
    write: () => {},
    rename: (from, to) => {
      if (path.basename(from).startsWith('.lock.new-')) {
        state.tries += 1
        // A wait that never ends on the fake clock fails the test, not hangs it.
        if (state.tries > 10_000) throw new Error('runaway: the fake clock never reached the deadline')
        if (state.held) throw errno('ENOTEMPTY')
        state.held = true
      } else if (path.basename(to).startsWith('.lock.stale-')) {
        state.broken += 1
        state.held = false
      }
    },
    remove: () => {},
    list: () => [],
  }
  return { state, ops, elapsed: () => state.t - start }
}

test('withLock tries every retryMs and gives up exactly when timeoutMs has passed', async () => {
  const h = heldLock()
  let ran = false
  await assert.rejects(withLock(FAKE_DIR, () => { ran = true }, { ops: h.ops, timeoutMs: 1000, retryMs: 50 }), /could not take .*\.lock within 1000 ms \(held by an unknown run\)/)
  assert.equal(ran, false)
  assert.equal(h.elapsed(), 1000, 'gave up at the deadline, not before it and not after it')
  assert.equal(h.state.tries, 21, 'one try at each of 0, 50, ..., 1000 ms')
  assert.deepEqual(h.state.sleeps, Array(20).fill(50), 'waits retryMs between tries')

  const other = heldLock()
  await assert.rejects(withLock(FAKE_DIR, () => 'never', { ops: other.ops, timeoutMs: 120, retryMs: 40 }), /within 120 ms/)
  assert.equal(other.elapsed(), 120)
  assert.deepEqual(other.state.sleeps, [40, 40, 40])

  const none = heldLock()
  await assert.rejects(withLock(FAKE_DIR, () => 'never', { ops: none.ops, timeoutMs: 0 }), /within 0 ms/)
  assert.equal(none.state.tries, 1, 'a timeout of 0 tries once and does not wait')
  assert.deepEqual(none.state.sleeps, [])
})

test('with no options, withLock waits 60 s and breaks only a lock older than 120 s', async () => {
  const live = heldLock({ age: 120_000 })
  await assert.rejects(withLock(FAKE_DIR, () => 'never', { ops: live.ops }), /within 60000 ms/)
  assert.equal(live.elapsed(), 60_000)
  assert.equal(live.state.tries, 1201, 'every 50 ms for 60 s')
  assert.equal(live.state.broken, 0, 'a lock exactly 120 s old is not stale')

  const dead = heldLock({ age: 120_001 })
  assert.equal(await withLock(FAKE_DIR, () => 'ran', { ops: dead.ops }), 'ran')
  assert.equal(dead.state.broken, 1, 'a lock 1 ms past 120 s is broken')
  assert.equal(dead.state.tries, 2, 'taken on the next try')
  assert.equal(dead.elapsed(), 0, 'the next try follows at once, with no wait')
})

test('a stale lock broken at the deadline is still taken', async () => {
  const dead = heldLock({ age: 10_000 })
  assert.equal(await withLock(FAKE_DIR, () => 'ran', { ops: dead.ops, timeoutMs: 0, staleMs: 1000 }), 'ran')
  assert.deepEqual([dead.state.tries, dead.state.broken, dead.state.sleeps.length], [2, 1, 0])
})

test('breakIfStale: a lock exactly staleMs old is fresh, 1 ms older is broken', () => {
  const ops = (age) => ({ age: () => age, owner: () => 'dead', rename: () => {}, remove: () => {} })
  assert.equal(breakIfStale('/x/.lock', 1000, ops(1000)), 'fresh')
  assert.equal(breakIfStale('/x/.lock', 1000, ops(1001)), 'broken')
  assert.equal(breakIfStale('/x/.lock', 120_000, ops(120_000)), 'fresh')
})

test('withLock: an error while releasing the lock reaches the caller', async () => {
  const tree = makeTree()
  try {
    const ops = {
      ...LOCK_OPS,
      remove: (dir) => {
        if (path.basename(dir).startsWith('.lock.free-')) throw errno('EACCES')
        LOCK_OPS.remove(dir)
      },
    }
    let ran = false
    await assert.rejects(withLock(tree.contracts, () => { ran = true }, { ops }), (e) => e.code === 'EACCES')
    assert.equal(ran, true, 'the work ran; the release failed after it')
  } finally {
    tree.cleanup()
  }
})

// ── Atomic writes ────────────────────────────────────────────────────────────

test('writeFileAtomic writes through a dot temp file in tmpDir that contracts/.gitignore ignores', (t) => {
  const tree = makeTree()
  try {
    const target = path.join(tree.root, 'core', 'src', 'failures', 'codes.ts')
    const rename = t.mock.method(fs, 'renameSync')
    writeFileAtomic(target, 'new text\n', tree.contracts)
    assert.equal(fs.readFileSync(target, 'utf8'), 'new text\n')
    assert.equal(rename.mock.callCount(), 1)
    const [from, to] = rename.mock.calls[0].arguments
    assert.equal(to, target)
    assert.equal(path.dirname(from), tree.contracts, 'the temp file is in tmpDir, not in the SDK source folder')
    assert.match(path.basename(from), new RegExp(`^\\.codes\\.ts\\.tmp-${process.pid}-\\d+$`))
    assert.deepEqual(fs.readdirSync(path.dirname(target)).sort(), ['codes.ts'])
    // The same name in the real contracts/ is git-ignored.
    const ignored = spawnSync('git', ['-C', SDK_ROOT, 'check-ignore', '-q', '--no-index', path.join('contracts', path.basename(from))])
    assert.equal(ignored.status, 0, 'contracts/.gitignore ignores the temp file name')

    // With no tmpDir the temp file sits next to the target (the registry and sources in contracts/).
    rename.mock.resetCalls()
    const registryFile = path.join(tree.contracts, 'failure-codes.json')
    writeFileAtomic(registryFile, tree.registryText())
    assert.equal(path.dirname(rename.mock.calls[0].arguments[0]), tree.contracts)
  } finally {
    tree.cleanup()
  }
})

test('writeFileAtomic removes its temp file when the rename fails', () => {
  const tree = makeTree()
  try {
    const target = path.join(tree.root, 'a-directory')
    fs.mkdirSync(target)
    const before = fs.readdirSync(tree.contracts).sort()
    assert.throws(() => writeFileAtomic(target, 'text', tree.contracts), (e) => ['EISDIR', 'ENOTDIR', 'EPERM', 'EEXIST', 'ENOTEMPTY'].includes(e.code))
    assert.deepEqual(fs.readdirSync(tree.contracts).sort(), before, 'no temp file is left')
    assert.equal(fs.statSync(target).isDirectory(), true)
  } finally {
    tree.cleanup()
  }
})

test('add-code writes every temp file in its contracts dir, never next to a mirror', async (t) => {
  const tree = makeTree()
  try {
    const rename = t.mock.method(fs, 'renameSync')
    const result = await addCode({ entry: { ...good, clients: ['core', 'ios', 'android'] }, contractsDir: tree.contracts })
    assert.equal(result.action, 'added')
    assert.equal(result.mirrors.length, 3)
    const temps = rename.mock.calls.map((c) => c.arguments[0]).filter((from) => /\.tmp-/.test(from))
    assert.equal(temps.length, 5, 'registry, sources and three mirrors')
    for (const from of temps) assert.equal(path.dirname(from), tree.contracts, from)
    for (const m of MIRRORS) {
      const dir = path.dirname(path.join(tree.root, m.path))
      assert.deepEqual(fs.readdirSync(dir).filter((f) => f.includes('.tmp-')), [], dir)
    }
  } finally {
    tree.cleanup()
  }
})
