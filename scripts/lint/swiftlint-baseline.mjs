#!/usr/bin/env node
// Rewrites .swiftlint.baseline.json from a fresh SwiftLint run: sorted, one
// finding per line, so a diff shows exactly what changed. Like the print gate,
// a baseline may only go down: it refuses to add a finding unless
// --allow-increase is passed (that needs a reviewer).
//
//   node scripts/lint/swiftlint-baseline.mjs                    rewrite, refuse new findings
//   node scripts/lint/swiftlint-baseline.mjs --allow-increase   rewrite anyway
//
// The file stays in SwiftLint's own baseline format (a JSON array), so
// `swiftlint lint --baseline .swiftlint.baseline.json` reads it as is.

import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
export const BASELINE = path.join(ROOT, '.swiftlint.baseline.json')
const SWIFTLINT = path.join(ROOT, 'tools/bin/swiftlint')

/** SwiftLint matches a baselined finding by file, rule and line text, not line number. */
const keyOf = (v) => `${v.violation.location.file}\0${v.violation.ruleIdentifier}\0${v.text}`

/** JSON with object keys sorted (SwiftLint writes them in random order). */
function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((k) => `${JSON.stringify(k)}:${stable(value[k])}`).join(',')}}`
  }
  return JSON.stringify(value)
}

/** Sorted by file, line, column, rule; one finding per line, keys sorted. */
export function normalize(items) {
  const loc = (v) => v.violation.location
  const sorted = [...items].sort((a, b) =>
    loc(a).file.localeCompare(loc(b).file) ||
    (loc(a).line ?? 0) - (loc(b).line ?? 0) ||
    (loc(a).character ?? 0) - (loc(b).character ?? 0) ||
    a.violation.ruleIdentifier.localeCompare(b.violation.ruleIdentifier) ||
    a.text.localeCompare(b.text))
  return sorted.length ? `[\n${sorted.map(stable).join(',\n')}\n]\n` : '[]\n'
}

/** Findings in `next` that `prev` does not cover (counted per file + rule + text). */
export function added(prev, next) {
  const left = new Map()
  for (const v of prev) left.set(keyOf(v), (left.get(keyOf(v)) ?? 0) + 1)
  const out = []
  for (const v of next) {
    const n = left.get(keyOf(v)) ?? 0
    if (n > 0) left.set(keyOf(v), n - 1)
    else out.push(v)
  }
  return out
}

function main(argv) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'swiftlint-baseline-'))
  const out = path.join(tmp, 'baseline.json')
  try {
    // Exits non-zero whenever there are findings; the file is what matters.
    const r = spawnSync(SWIFTLINT, ['lint', '--quiet', '--write-baseline', out], { cwd: ROOT, stdio: ['ignore', 'ignore', 'inherit'] })
    if (r.error || !fs.existsSync(out)) {
      process.stderr.write(`swiftlint-baseline: SwiftLint did not write a baseline (${r.error?.message ?? `exit ${r.status}`}). Run bash scripts/lint/install-swiftlint.sh first.\n`)
      return 1
    }
    const next = JSON.parse(fs.readFileSync(out, 'utf8'))
    const prev = fs.existsSync(BASELINE) ? JSON.parse(fs.readFileSync(BASELINE, 'utf8')) : []
    const grew = added(prev, next)
    if (grew.length && !argv.includes('--allow-increase')) {
      for (const v of grew) {
        const { file, line } = v.violation.location
        process.stderr.write(`refusing to baseline ${file}:${line} ${v.violation.ruleIdentifier}: ${v.violation.reason}\n`)
      }
      process.stderr.write(`swiftlint-baseline: ${grew.length} new finding(s). Fix them, or pass --allow-increase (needs a reviewer).\n`)
      return 1
    }
    fs.writeFileSync(BASELINE, normalize(next))
    process.stdout.write(`swiftlint-baseline: ${prev.length} -> ${next.length} finding(s) in ${path.relative(process.cwd(), BASELINE)}\n`)
    return 0
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2))
