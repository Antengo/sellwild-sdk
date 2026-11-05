#!/usr/bin/env node
// Regenerates golden/log-failure.vectors.json (and the UTF-16-only companion)
// from reference/vector-cases.mjs through reference/log-failure.mjs.
//
//   node scripts/generate-vectors.mjs          write both files
//   node scripts/generate-vectors.mjs --check  exit 1 if either file is stale

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import * as L from '../reference/log-failure.mjs'
import { buildCases, UNIT_INPUTS, UTF16_ONLY_CASES, UTF16_ONLY_UNITS } from '../reference/vector-cases.mjs'
import * as T from '../reference/sdk-timing.mjs'
import { buildTimingCases, TIMING_UNITS } from '../reference/timing-cases.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
export const VECTORS_PATH = path.join(here, '..', 'golden', 'log-failure.vectors.json')
export const UTF16_VECTORS_PATH = path.join(here, '..', 'golden', 'log-failure.utf16.vectors.json')
export const TIMING_VECTORS_PATH = path.join(here, '..', 'golden', 'sdk-timing.vectors.json')

function runTimingCase(c) {
  const cs = roundTrip(c)
  const r = T.decideTiming(cs.stateBefore, cs.input, cs.context, cs.context.uid, cs.context.now)
  return { name: cs.name, input: cs.input, context: cs.context, stateBefore: cs.stateBefore,
    expected: { event: r.event, reason: r.reason, stateAfter: r.state } }
}

function runTimingUnits() {
  const rows = (list, fn) => roundTrip(list).map((args) => ({ input: args, expected: Array.isArray(args) ? fn(...args) : fn(args) }))
  return {
    budgetFor: rows(TIMING_UNITS.budgetFor, T.budgetFor),
    isSlow: rows(TIMING_UNITS.isSlow, T.isSlow),
    timingRate: roundTrip(TIMING_UNITS.timingRate).map((v) => ({ input: v, expected: T.timingRate(v) })),
  }
}

const roundTrip = (v) => JSON.parse(JSON.stringify(v))

function runCase(c) {
  const cs = roundTrip(c)
  const r = L.decideFailure(cs.stateBefore, cs.input, cs.context, cs.context.uid, cs.context.now)
  return {
    name: cs.name,
    input: cs.input,
    context: cs.context,
    stateBefore: cs.stateBefore,
    expected: { event: r.event, flushNow: r.flushNow, reason: r.reason, stateAfter: r.state },
  }
}

function runUnits(inputs) {
  const out = {}
  const table = (name, fn) => {
    if (!inputs[name]) return
    out[name] = roundTrip(inputs[name]).map((args) => {
      const list = Array.isArray(args) && (name === 'truncateUnicode') ? args : [args]
      return { input: list.length === 1 ? list[0] : list, expected: fn(...list) }
    })
  }
  table('fnv1a32', L.fnv1a32)
  table('truncateUnicode', L.truncateUnicode)
  table('hostOf', L.hostOf)
  table('sanitizeMessage', L.sanitizeMessage)
  table('coerceFlag', (v) => L.coerceFlag(v, true))
  table('coerceRate', L.coerceRate)
  table('normalizeCode', L.normalizeCode)
  table('normalizeHttpStatus', L.normalizeHttpStatus)
  table('normalizeCtxValue', L.normalizeCtxValue)
  return out
}

function assertUniqueNames(vectors) {
  const seen = new Set()
  for (const v of vectors) {
    if (seen.has(v.name)) throw new Error(`duplicate vector name: ${v.name}`)
    seen.add(v.name)
  }
}

const header = (note) => ({
  contract: 'clientFailure',
  fv: L.CONTRACT_VERSION,
  generatedBy: 'contracts/reference/log-failure.mjs via contracts/scripts/generate-vectors.mjs',
  spec: 'contracts/FAILURES.md',
  note,
  limits: L.LIMITS,
})

/** Both documents, built in memory. */
export function generate() {
  const vectors = buildCases().map(runCase)
  assertUniqueNames(vectors)
  const utf16 = UTF16_ONLY_CASES.map(runCase)
  assertUniqueNames([...vectors, ...utf16])
  const timingVectors = buildTimingCases().map(runTimingCase)
  assertUniqueNames(timingVectors)
  return {
    timing: {
      contract: 'sdkTiming',
      tv: T.TIMING_VERSION,
      generatedBy: 'contracts/reference/sdk-timing.mjs via contracts/scripts/generate-vectors.mjs',
      spec: 'contracts/FAILURES.md section 18',
      note: 'Every platform timing core must reproduce every vector (event deep equal or null, reason, stateAfter) and the unit tables.',
      limits: T.TIMING_LIMITS,
      budgets: T.BUDGETS,
      budgetKeys: T.BUDGET_KEYS,
      slowCodes: T.SLOW_CODES,
      steps: T.STEPS,
      vectors: timingVectors,
      units: runTimingUnits(),
    },
    main: {
      ...header('Every platform pure core must reproduce every vector: the same event (deep equal) or null, the same flushNow, the same reason and the same stateAfter. `units` holds single-function tables for porting.'),
      vectors,
      units: runUnits(UNIT_INPUTS),
    },
    utf16: {
      ...header('Inputs with lone UTF-16 surrogates. Only for platforms whose strings can hold them (TS, Kotlin, Dart). Swift strings cannot, so iOS skips this file.'),
      vectors: utf16,
      units: runUnits(UTF16_ONLY_UNITS),
    },
  }
}

export const serialize = (doc) => JSON.stringify(doc, null, 2) + '\n'

function main() {
  const { main: doc, utf16, timing } = generate()
  const files = [[VECTORS_PATH, serialize(doc)], [UTF16_VECTORS_PATH, serialize(utf16)], [TIMING_VECTORS_PATH, serialize(timing)]]
  if (process.argv.includes('--check')) {
    const stale = files.filter(([p, text]) => !fs.existsSync(p) || fs.readFileSync(p, 'utf8') !== text)
    for (const [p] of stale) process.stderr.write(`stale: ${path.relative(process.cwd(), p)}\n`)
    process.exitCode = stale.length === 0 ? 0 : 1
    return
  }
  fs.mkdirSync(path.dirname(VECTORS_PATH), { recursive: true })
  for (const [p, text] of files) fs.writeFileSync(p, text)
  process.stdout.write(`wrote ${doc.vectors.length} vectors + ${utf16.vectors.length} utf16-only vectors + ${timing.vectors.length} timing vectors\n`)
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main()
