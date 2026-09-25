// The failure-code registry (FAILURES.md 4.2): reading, checking and writing
// failure-codes.json and failure-codes.sources.json, and the lock that lets
// several add-code runs happen at once. Shared by scripts/add-code.mjs,
// scripts/gen-codes.mjs and the tests. No dependencies: it runs before
// `npm install`.
//
// The enums come from schemas/failure-codes.schema.json, so the schema stays
// the one place they are defined. test/add-code.test.mjs checks that ajv and
// validateEntry agree on every case.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { CONTRACTS_DIR } from './paths.mjs'

const schema = JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, 'schemas', 'failure-codes.schema.json'), 'utf8'))
const props = schema.items.properties

export const FIELDS = Object.freeze([...schema.items.required])
export const AREAS = Object.freeze([...props.area.enum])
export const REASONS = Object.freeze([...props.reason.enum])
export const COMPONENTS = Object.freeze([...props.component.enum])
export const SEVERITIES = Object.freeze([...props.severity.enum])
export const CLIENTS = Object.freeze([...props.clients.items.enum])
export const CODE_MAX = props.code.maxLength
export const DESCRIPTION_MIN = props.description.minLength
const CODE_RE = new RegExp(props.code.pattern)
const OPERATION_RE = new RegExp(props.operation.pattern)

/** The one code that may use area `client` and component `unknown`. */
export const INVALID_CODE = 'client.code.invalid'

// FAILURES.md 4.3: no-fill, no-bid and the events transport are never failures.
const NEVER_LOGGED_RE = /no_?fill|no_?bids?|^events?\./

export const REGISTRY_FILE = 'failure-codes.json'
export const SOURCES_FILE = 'failure-codes.sources.json'

// ── Checking ─────────────────────────────────────────────────────────────────

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v)

/**
 * Every problem with one registry entry, as short text. Empty means valid.
 * Checks the schema rules plus what the schema cannot say: the code's three
 * parts equal area/operation/reason, `client` and `unknown` belong to
 * client.code.invalid only, and the description is one clean sentence that
 * cannot break a generated doc comment.
 */
export function validateEntry(entry) {
  if (!isObject(entry)) return ['the entry must be a JSON object']
  const errors = []
  for (const key of Object.keys(entry)) {
    if (!FIELDS.includes(key)) errors.push(`unknown field "${key}"`)
  }
  for (const key of FIELDS) {
    if (!(key in entry)) errors.push(`missing field "${key}"`)
  }
  const { code, area, operation, reason, component, severity, clients, description } = entry

  if (typeof code !== 'string') {
    if ('code' in entry) errors.push('code must be text')
  } else {
    if (code.length > CODE_MAX) errors.push(`code is longer than ${CODE_MAX} characters`)
    if (!CODE_RE.test(code)) errors.push(`code "${code}" does not match <area>.<operation>.<reason> (${props.code.pattern})`)
    if (NEVER_LOGGED_RE.test(code)) errors.push(`code "${code}" names a no-fill or events-transport failure, which is never logged (FAILURES.md 4.3)`)
    const parts = code.split('.')
    if (parts.length === 3) {
      for (const [name, value, part] of [['area', area, parts[0]], ['operation', operation, parts[1]], ['reason', reason, parts[2]]]) {
        if (typeof value === 'string' && value !== part) errors.push(`${name} "${value}" is not the code's ${name} "${part}"`)
      }
    }
  }
  if ('area' in entry && !AREAS.includes(area)) errors.push(`area must be one of ${AREAS.join(', ')}`)
  if (area === 'client' && code !== INVALID_CODE) errors.push(`area "client" is reserved for ${INVALID_CODE}`)
  if ('operation' in entry && (typeof operation !== 'string' || !OPERATION_RE.test(operation))) errors.push(`operation must match ${props.operation.pattern}`)
  if ('reason' in entry && !REASONS.includes(reason)) errors.push(`reason must be one of ${REASONS.join(', ')}`)
  if ('component' in entry && !COMPONENTS.includes(component)) errors.push(`component must be one of ${COMPONENTS.join(', ')}`)
  if (component === 'unknown' && code !== INVALID_CODE) errors.push(`component "unknown" is reserved for ${INVALID_CODE}`)
  if ('severity' in entry && !SEVERITIES.includes(severity)) errors.push(`severity must be one of ${SEVERITIES.join(', ')}`)

  if ('clients' in entry) {
    if (!Array.isArray(clients) || clients.length === 0) {
      errors.push(`clients must be a non-empty list of ${CLIENTS.join(', ')}`)
    } else {
      for (const c of clients) if (!CLIENTS.includes(c)) errors.push(`unknown client "${c}" (one of ${CLIENTS.join(', ')})`)
      if (new Set(clients).size !== clients.length) errors.push('clients has a duplicate')
    }
  }

  if ('description' in entry) {
    if (typeof description !== 'string') {
      errors.push('description must be text')
    } else {
      if (description.length < DESCRIPTION_MIN) errors.push(`description is shorter than ${DESCRIPTION_MIN} characters`)
      if (/[\u0000-\u001f\u007f]/.test(description)) errors.push('description must be one line with no control characters')
      if (description !== description.trim() || / {2}/.test(description)) errors.push('description has extra spaces')
      if (!description.endsWith('.')) errors.push('description must end with a period')
      if (description.includes('*/')) errors.push('description must not contain "*/" (it would end a generated doc comment)')
      // Kotlin block comments nest: "/*" inside the generated KDoc opens a
      // comment that swallows the rest of SellwildFailureCode.kt.
      if (description.includes('/*')) errors.push('description must not contain "/*" (it would open a nested comment in the Kotlin mirror)')
    }
  }
  return errors
}

/**
 * Problems with the whole registry: each entry, duplicate codes, and the order
 * (sorted by code, plain code-unit order). Empty means valid. Never throws: an
 * entry that is not an object is reported and left out of the order check.
 */
export function validateRegistry(list) {
  if (!Array.isArray(list) || list.length === 0) return ['the registry must be a non-empty JSON array']
  const errors = []
  const seen = new Set()
  let previous = null
  list.forEach((entry, i) => {
    const code = isObject(entry) ? entry.code : undefined
    for (const e of validateEntry(entry)) errors.push(`[${i}] ${code ?? '?'}: ${e}`)
    if (typeof code !== 'string') return
    if (seen.has(code)) errors.push(`[${i}] duplicate code ${code}`)
    seen.add(code)
    if (previous !== null && !(previous < code)) errors.push(`[${i}] ${code} is out of order (after ${previous})`)
    previous = code
  })
  return errors
}

/**
 * The entry as it is stored: fields in registry order, area/operation/reason
 * filled in from the code when left out, clients in canonical order.
 */
export function normalizeEntry(input) {
  if (!isObject(input)) return input
  const parts = typeof input.code === 'string' ? input.code.split('.') : []
  const out = {}
  for (const key of FIELDS) {
    let value = input[key]
    if (value === undefined && parts.length === 3) {
      if (key === 'area') value = parts[0]
      if (key === 'operation') value = parts[1]
      if (key === 'reason') value = parts[2]
    }
    if (key === 'clients' && Array.isArray(value) && value.every((c) => CLIENTS.includes(c))) {
      value = [...value].sort((a, b) => CLIENTS.indexOf(a) - CLIENTS.indexOf(b))
    }
    if (value !== undefined) out[key] = value
  }
  for (const key of Object.keys(input)) if (!(key in out)) out[key] = input[key]
  return out
}

// ── Changing ─────────────────────────────────────────────────────────────────

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)

/**
 * Applies one change to a registry list and returns { list, changed, action }.
 * Throws with a readable message when the change is not allowed.
 *
 * mode `add`: a new code. Adding an identical entry again is a no-op, so two
 *   runs that add the same code both succeed. A different entry under an
 *   existing code is refused.
 * mode `merge-clients`: the code exists; its clients become the union with
 *   the given ones. Any other field given must equal the stored one.
 * mode `replace`: the code exists; the whole entry is replaced (for example to
 *   remove a client).
 */
export function applyChange(list, input, mode = 'add') {
  const index = list.findIndex((e) => e.code === input?.code)
  const existing = index >= 0 ? list[index] : null
  let entry
  if (mode === 'merge-clients') {
    if (!existing) throw new Error(`${input?.code}: not in the registry; add it without --merge-clients`)
    for (const key of FIELDS) {
      if (key === 'clients' || input[key] === undefined) continue
      if (!same(input[key], existing[key])) throw new Error(`${input.code}: --merge-clients only adds clients, but ${key} differs from the registry`)
    }
    entry = normalizeEntry({ ...existing, clients: [...new Set([...existing.clients, ...(input.clients ?? [])])] })
  } else {
    entry = normalizeEntry(input)
  }
  const errors = validateEntry(entry)
  if (errors.length) throw new Error(`${input?.code ?? 'entry'}: ${errors.join('; ')}`)

  if (mode === 'add' && existing) {
    if (same(existing, entry)) return { list, changed: false, action: 'unchanged', entry }
    throw new Error(`${entry.code}: already in the registry with other values; use --merge-clients to add clients or --replace to change it`)
  }
  if (mode === 'replace' && !existing) throw new Error(`${entry.code}: not in the registry; add it without --replace`)
  if (!['add', 'merge-clients', 'replace'].includes(mode)) throw new Error(`unknown mode ${mode}`)

  if (existing && same(existing, entry)) return { list, changed: false, action: 'unchanged', entry }
  const next = list.filter((e) => e.code !== entry.code)
  next.push(entry)
  // Plain code-unit order: -1, 0 or 1 with no branch left to chance.
  next.sort((a, b) => (a.code > b.code) - (a.code < b.code))
  return { list: next, changed: true, action: existing ? 'updated' : 'added', entry }
}

// ── Files ────────────────────────────────────────────────────────────────────

export function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

/** Same text format as the committed files: 2-space JSON, literal UTF-8, final newline. */
export function formatJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`
}

/**
 * Writes through a temp file and a rename, so a reader never sees half a file.
 * The temp file goes in `tmpDir` (the contracts dir for the mirrors), where
 * contracts/.gitignore ignores `*.tmp-*`, so a run that dies between the write
 * and the rename leaves nothing in an SDK source folder. `tmpDir` must be on
 * the same volume as `file`. A failed rename removes the temp file.
 */
export function writeFileAtomic(file, text, tmpDir = path.dirname(file)) {
  const tmp = path.join(tmpDir, `.${path.basename(file)}.tmp-${process.pid}-${Date.now()}`)
  fs.writeFileSync(tmp, text)
  try {
    fs.renameSync(tmp, file)
  } catch (error) {
    fs.rmSync(tmp, { force: true })
    throw error
  }
}

// ── Lock ─────────────────────────────────────────────────────────────────────

export const LOCK_DIR = '.lock'
export const LOCK_DEFAULTS = Object.freeze({ timeoutMs: 60_000, staleMs: 120_000, retryMs: 50 })

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

function readOwner(dir) {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, 'owner.json'), 'utf8'))
  } catch {
    // Gone, or not a lock this code made (a hand-made directory, a corrupt
    // file): the directory's own age decides staleness.
    return null
  }
}

function ageMs(dir) {
  return Date.now() - fs.statSync(dir).mtimeMs
}

/**
 * The operations the lock uses (files, the clock and the wait between tries);
 * tests pass fakes to play out races and failures and to time the wait.
 */
export const LOCK_OPS = Object.freeze({
  now: () => Date.now(),
  sleep,
  age: ageMs,
  owner: (dir) => readOwner(dir)?.token ?? null,
  mkdtemp: (prefix) => fs.mkdtempSync(prefix),
  write: (file, text) => fs.writeFileSync(file, text),
  rename: (from, to) => fs.renameSync(from, to),
  remove: (dir) => fs.rmSync(dir, { recursive: true, force: true }),
  list: (dir) => fs.readdirSync(dir),
})

// What rename() gives when the target is a directory with something in it.
const HELD = new Set(['ENOTEMPTY', 'EEXIST'])

/**
 * One try at the lock. The owner file is written into a fresh temp directory,
 * which is then renamed to `.lock`. So a lock never exists without its owner
 * file: no run can find a live lock ownerless and break it, and a failed write
 * leaves no lock behind. Returns true when taken and false when another run
 * holds the lock. Any other error is thrown, after the temp directory is
 * removed.
 *
 * rename() also replaces an EMPTY directory. No run leaves `.lock` empty:
 * release and breakIfStale move the lock away before removing it. So an empty
 * `.lock` is not a lock, and taking it is right.
 */
export function tryLock(lock, token, ops = LOCK_OPS) {
  const tmp = ops.mkdtemp(`${lock}.new-`)
  try {
    ops.write(path.join(tmp, 'owner.json'), `${JSON.stringify({ token, pid: process.pid, startedAt: new Date().toISOString() })}\n`)
    ops.rename(tmp, lock)
    return true
  } catch (error) {
    ops.remove(tmp)
    if (HELD.has(error?.code)) return false
    throw error
  }
}

/**
 * Runs `fn` while holding `<contractsDir>/.lock` (see tryLock). Waits up to
 * `timeoutMs` (default 60 s), retrying every `retryMs`. A lock older than
 * `staleMs` (default 120 s) is from a run that died: it is moved aside and
 * removed, and the next try follows at once. The lock is always released, also when `fn`
 * throws; an error from the release itself reaches the caller.
 */
export async function withLock(contractsDir, fn, options = {}) {
  const { timeoutMs, staleMs, retryMs, ops } = { ...LOCK_DEFAULTS, ops: LOCK_OPS, ...options }
  const lock = path.join(contractsDir, LOCK_DIR)
  const token = `${os.hostname()}:${process.pid}:${Date.now()}:${Math.random().toString(36).slice(2)}`
  const deadline = ops.now() + timeoutMs
  while (!tryLock(lock, token, ops)) {
    // A stale lock just broken is free: try again at once, even at the deadline.
    if (breakIfStale(lock, staleMs, ops) === 'broken') continue
    if (ops.now() >= deadline) {
      const owner = readOwner(lock)
      throw new Error(`could not take ${lock} within ${timeoutMs} ms (held by ${owner ? `pid ${owner.pid} since ${owner.startedAt}` : 'an unknown run'}); if no add-code or gen-codes run is active, delete it`)
    }
    await ops.sleep(retryMs)
  }
  try {
    return await fn()
  } finally {
    releaseLock(lock, token, ops)
  }
}

/**
 * Releases our lock: moves it aside, then removes it, so `.lock` never sits
 * empty while it is deleted (a waiting run's rename would take an empty
 * directory, and the delete would then remove that run's lock). Removes only
 * what holds our token. Returns what happened:
 *
 * - `released`: the usual case.
 * - `moved`: a stale-lock breaker had moved ours aside (breakIfStale
 *   `stranded`); that moved copy is removed and nothing else is.
 * - `restored`: between our check and our move, a breaker moved ours aside and
 *   a third run took the name; the lock we moved is that run's, so it goes
 *   back (and ours, found aside, is removed).
 * - `stranded`: as `restored`, but a fourth run took the name first; the moved
 *   lock stays aside for its holder, whose release finds it.
 * - `lost`: nothing of ours was found.
 */
export function releaseLock(lock, token, ops = LOCK_OPS) {
  let result = 'lost'
  if (ops.owner(lock) === token) {
    const free = `${lock}.free-${process.pid}-${Date.now()}`
    let moved = true
    try {
      ops.rename(lock, free)
    } catch {
      moved = false // a breaker moved ours between the check and the move; the scan below finds it
    }
    if (moved && ops.owner(free) === token) {
      ops.remove(free)
      return 'released'
    }
    if (moved) {
      try {
        ops.rename(free, lock)
        result = 'restored'
      } catch {
        result = 'stranded'
      }
    }
  }
  const dir = path.dirname(lock)
  const base = path.basename(lock)
  for (const name of ops.list(dir)) {
    if (!name.startsWith(`${base}.stale-`) && !name.startsWith(`${base}.free-`)) continue
    const aside = path.join(dir, name)
    if (ops.owner(aside) !== token) continue
    ops.remove(aside)
    if (result === 'lost') result = 'moved'
  }
  return result
}

/**
 * Moves a lock older than `staleMs` aside and removes it, then checks it moved
 * the lock it judged stale: if another run replaced it in between, the fresh
 * lock is put back. Returns what happened: `fresh`, `gone` (released
 * meanwhile), `raced` (another run moved it first), `restored`, `stranded`
 * (a fresh lock was moved and a third run took the name before it could go
 * back: the moved lock is left for its holder, which removes it on release)
 * or `broken`.
 *
 * The check compares owner tokens. Every lock tryLock makes has its owner file
 * from the start, so a replacement always has a token that differs from the
 * stale one (or from `null`, when the stale lock had no readable owner file).
 */
export function breakIfStale(lock, staleMs, ops = LOCK_OPS) {
  let before
  try {
    if (ops.age(lock) <= staleMs) return 'fresh'
    before = ops.owner(lock)
  } catch {
    return 'gone'
  }
  const aside = `${lock}.stale-${process.pid}-${Date.now()}`
  try {
    ops.rename(lock, aside)
  } catch {
    return 'raced'
  }
  if (ops.owner(aside) !== before) {
    try {
      ops.rename(aside, lock)
      return 'restored'
    } catch {
      // A third run took the name meanwhile. The moved lock is a live run's,
      // so it is not removed here; its holder removes it on release.
      return 'stranded'
    }
  }
  ops.remove(aside)
  return 'broken'
}
