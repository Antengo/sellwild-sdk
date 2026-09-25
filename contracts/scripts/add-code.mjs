#!/usr/bin/env node
// Adds one failure code to failure-codes.json (FAILURES.md 4.4), or changes
// the clients of one, and regenerates the four platform mirrors. The only way
// to change the registry: never edit failure-codes.json or a mirror by hand.
//
//   node scripts/add-code.mjs '<json entry>'
//   node scripts/add-code.mjs --code widget.webview_load.http --component webview \
//     --severity error --clients react-native,ios,android,widget \
//     --description "The widget WebView got an HTTP error status for its page."
//
// area, operation and reason may be left out: they come from the code. Flags
// and a JSON entry may be combined; flags win.
//
//   --merge-clients    the code exists: add the given clients to it
//   --replace          the code exists: replace the whole entry (e.g. drop a client)
//   --note <text>      why a new code exists; kept in failure-codes.sources.json
//   --contracts-dir    another contracts tree (tests); the SDK root is its parent
//
// It checks the entry (format, enums, clients, severity, description), takes
// contracts/.lock (an atomic rename of a directory that already holds the
// owner file; waits up to 60 s; a lock older than 120 s is broken), re-reads
// the registry under the lock, inserts the entry in code order, records a new
// code (only a new one) in failure-codes.sources.json `added`, writes the
// changed files, runs gen-codes and releases the lock. Adding an identical entry again
// changes nothing and exits 0, so concurrent runs are safe.
//
// Exit codes: 0 done, 1 refused or failed (nothing written).

import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { CONTRACTS_DIR } from './lib/paths.mjs'
import {
  FIELDS,
  REGISTRY_FILE,
  SOURCES_FILE,
  applyChange,
  formatJson,
  readJson,
  validateRegistry,
  withLock,
  writeFileAtomic,
} from './lib/registry.mjs'
import { writeMirrors } from './gen-codes.mjs'

const USAGE = 'usage: node scripts/add-code.mjs [\'<json entry>\'] [--code c] [--component c] [--severity s] [--clients a,b] [--description d] [--area a --operation o --reason r] [--merge-clients | --replace] [--note text] [--contracts-dir dir]'

const VALUE_FLAGS = new Set(['code', 'area', 'operation', 'reason', 'component', 'severity', 'clients', 'description', 'note', 'contracts-dir'])

/** Parses the command line into { entry, mode, note, contractsDir }. Throws on bad usage. */
export function parseArgs(argv) {
  let entry = {}
  const flags = {}
  let mode = 'add'
  let sawJson = false
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--merge-clients' || arg === '--replace') {
      const next = arg.slice(2)
      if (mode !== 'add' && mode !== next) throw new Error('--merge-clients and --replace cannot be combined')
      mode = next
    } else if (arg.startsWith('--')) {
      const eq = arg.indexOf('=')
      const name = eq > 0 ? arg.slice(2, eq) : arg.slice(2)
      if (!VALUE_FLAGS.has(name)) throw new Error(`unknown flag --${name}`)
      const value = eq > 0 ? arg.slice(eq + 1) : argv[++i]
      if (value === undefined) throw new Error(`--${name} needs a value`)
      flags[name] = value
    } else {
      if (sawJson) throw new Error('give one JSON entry at most')
      sawJson = true
      try {
        entry = JSON.parse(arg)
      } catch (error) {
        throw new Error(`the entry is not valid JSON: ${error.message}`)
      }
      if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) throw new Error('the entry must be a JSON object')
    }
  }
  for (const key of FIELDS) {
    if (flags[key] === undefined) continue
    entry[key] = key === 'clients' ? flags[key].split(',').map((c) => c.trim()).filter(Boolean) : flags[key]
  }
  if (entry.code === undefined) throw new Error(`no code given\n${USAGE}`)
  return {
    entry,
    mode,
    note: flags.note,
    contractsDir: flags['contracts-dir'] ? path.resolve(flags['contracts-dir']) : CONTRACTS_DIR,
  }
}

/** The local calendar date, YYYY-MM-DD: the `date` of an `added` record. */
export function today(now = new Date()) {
  const pad = (n) => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
}

/**
 * Applies one change under the lock and regenerates the mirrors. Returns
 * { action, code, mirrors }. Throws (and writes nothing) when refused.
 * `now` is the clock for the `added` date; `holdMs` keeps the lock that much
 * longer after writing (both for tests).
 */
export async function addCode({ entry, mode = 'add', note, contractsDir = CONTRACTS_DIR, lock = {}, holdMs = 0, now = () => new Date() }) {
  const registryPath = path.join(contractsDir, REGISTRY_FILE)
  const sourcesPath = path.join(contractsDir, SOURCES_FILE)
  const sdkRoot = path.dirname(contractsDir)
  // A bad entry fails at once, before any wait for the lock.
  if (mode !== 'merge-clients') applyChange([], entry, 'add')
  return withLock(contractsDir, async () => {
    const registry = readJson(registryPath)
    const errors = validateRegistry(registry)
    if (errors.length) throw new Error(`failure-codes.json is already invalid, fix it first:\n  ${errors.join('\n  ')}`)
    const result = applyChange(registry, entry, mode)
    if (result.changed) {
      if (result.action === 'added') {
        const sources = readJson(sourcesPath)
        const added = (sources.added ?? []).filter((a) => a.code !== result.entry.code)
        sources.added = [...added, { code: result.entry.code, date: today(now()), note: note ?? 'Added with scripts/add-code.mjs.' }]
        writeFileAtomic(sourcesPath, formatJson(sources))
      }
      writeFileAtomic(registryPath, formatJson(result.list))
    }
    const mirrors = writeMirrors(result.list, sdkRoot, contractsDir)
    if (holdMs > 0) await new Promise((resolve) => setTimeout(resolve, holdMs))
    return { action: result.action, code: result.entry.code, mirrors }
  }, lock)
}

// Test hooks, read from the environment so the lock tests run in seconds:
// SELLWILD_LOCK_TIMEOUT_MS, SELLWILD_LOCK_STALE_MS and SELLWILD_ADD_CODE_HOLD_MS.
function testHooks(env) {
  const lock = {}
  if (env.SELLWILD_LOCK_TIMEOUT_MS) lock.timeoutMs = Number(env.SELLWILD_LOCK_TIMEOUT_MS)
  if (env.SELLWILD_LOCK_STALE_MS) lock.staleMs = Number(env.SELLWILD_LOCK_STALE_MS)
  return { lock, holdMs: Number(env.SELLWILD_ADD_CODE_HOLD_MS ?? 0) }
}

export async function main(argv = process.argv.slice(2), env = process.env) {
  const { action, code, mirrors } = await addCode({ ...parseArgs(argv), ...testHooks(env) })
  process.stdout.write(`${code}: ${action}${mirrors.length ? `; regenerated ${mirrors.join(', ')}` : ''}\n`)
  return 0
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().then(
    (code) => { process.exitCode = code },
    (error) => {
      process.stderr.write(`add-code: ${error.message}\n`)
      process.exitCode = 1
    },
  )
}
