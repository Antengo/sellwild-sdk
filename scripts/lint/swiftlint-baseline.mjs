#!/usr/bin/env node
// The SwiftLint gate and its baseline (scripts/lint/swiftlint.baseline.json).
//
//   node scripts/lint/swiftlint-baseline.mjs                      check: exit 1 on any finding the baseline does not cover
//   node scripts/lint/swiftlint-baseline.mjs --update             rewrite the baseline after fixing findings;
//                                                                 refuses any increase
//   node scripts/lint/swiftlint-baseline.mjs --update --allow-increase
//                                                                 rewrite anyway (needs a reviewer)
//   --findings <file>   read SwiftLint JSON (`swiftlint lint --reporter json`) from a file
//                       instead of running SwiftLint (tests)
//   --root <dir>        lint that copy of the repo instead of this checkout, with its
//                       .swiftlint.yml (mutation checks on an exported tree)
//   --baseline <file>   another baseline file (tests)
//
// Why not SwiftLint's own --baseline: it matches a finding by file, rule,
// severity, reason and the text of its line. The size rules put the measured
// number in the reason ("currently contains 804"), so one line added to or
// removed from a long file or function breaks the match, and editing a
// baselined line does too.
//
// How findings match here:
// 1. A finding's key is its file, its rule and its reason with every number
//    replaced by #. Line numbers and line text are not part of it, so moving
//    code or editing a baselined line changes nothing.
// 2. The baseline counts the findings under each key. More findings under a
//    key than it counts, or a key it does not have, fails.
// 3. The size rules (SIZE_RULES) also keep each finding's measured number,
//    the one after "currently". Under one key the numbers are paired largest
//    first with the baselined ones, and none may be larger than its pair: a
//    long file, type or function may shrink or stay, never grow. Pairing by
//    size means two long functions in one file can trade lines unseen.
// 4. Fewer findings than the baseline holds passes. Shrink the baseline in
//    the same change with --update.

import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
export const BASELINE = path.join(ROOT, 'scripts/lint/swiftlint.baseline.json')
const SWIFTLINT = path.join(ROOT, 'tools/bin/swiftlint')

/** Rules whose reason carries a measured size ("currently spans 59 lines"). */
export const SIZE_RULES = new Set([
  'file_length',
  'type_body_length',
  'function_body_length',
  'closure_body_length',
  'cyclomatic_complexity',
  'function_parameter_count',
  'line_length',
])

const DESCRIPTION = 'SwiftLint findings that existed when the gate started (scripts/lint/swiftlint-baseline.mjs). Per file: "<rule>: <reason, numbers as #>" -> a count, or for a size rule the measured sizes, largest first. A new finding, a higher count or a larger size fails. Shrink it after fixing findings: bash scripts/lint/swiftlint.sh --update.'

/** The key part of a reason: every number replaced by #. */
export const reasonKey = (reason) => reason.replace(/\d+/g, '#')

/** The measured number of a size rule's reason (after "currently"), else null. */
export function measured(rule, reason) {
  if (!SIZE_RULES.has(rule)) return null
  const m = /\bcurrently\b\D*(\d+)/.exec(reason)
  return m ? Number(m[1]) : null
}

/** Repo-relative path of a SwiftLint file path (it drops /private from /private/tmp paths). */
export function relativeFile(file, root = ROOT) {
  const real = (p) => { try { return fs.realpathSync(p) } catch { return p } }
  return path.relative(real(root), real(file)).split(path.sep).join('/')
}

/**
 * SwiftLint JSON findings as { file, rule, key, size, line, character, reason }.
 * `key` is `<rule>: <reason with numbers as #>`; `size` is null outside SIZE_RULES.
 */
export function toFindings(items, root = ROOT) {
  return items.map((v) => ({
    file: relativeFile(v.file, root),
    rule: v.rule_id,
    key: `${v.rule_id}: ${reasonKey(v.reason)}`,
    size: measured(v.rule_id, v.reason),
    line: v.line ?? 0,
    character: v.character ?? 0,
    reason: v.reason,
  }))
}

/** { file: { key: count | sizes (largest first) } }, files and keys sorted. */
export function buildBaseline(findings) {
  const files = {}
  for (const f of findings) {
    const byKey = (files[f.file] ??= {})
    if (f.size === null) byKey[f.key] = (typeof byKey[f.key] === 'number' ? byKey[f.key] : 0) + 1
    else (byKey[f.key] = Array.isArray(byKey[f.key]) ? byKey[f.key] : []).push(f.size)
  }
  const sorted = {}
  for (const file of Object.keys(files).sort()) {
    sorted[file] = {}
    for (const key of Object.keys(files[file]).sort()) {
      const value = files[file][key]
      sorted[file][key] = Array.isArray(value) ? [...value].sort((a, b) => b - a) : value
    }
  }
  return { description: DESCRIPTION, files: sorted }
}

/** How many findings a baseline value allows. */
const allowed = (value) => (Array.isArray(value) ? value.length : typeof value === 'number' ? value : 0)

/**
 * Findings against a baseline. Returns
 *   failures: [{ file, key, why, findings }] (what fails the gate), and
 *   fixed:    how many baselined findings are gone or smaller (shrink with --update).
 */
export function compare(findings, baseline) {
  const groups = new Map()
  for (const f of findings) {
    const id = `${f.file}\0${f.key}`
    if (!groups.has(id)) groups.set(id, { file: f.file, key: f.key, list: [] })
    groups.get(id).list.push(f)
  }
  const failures = []
  let fixed = 0
  const seen = new Set()
  for (const [id, { file, key, list }] of groups) {
    seen.add(id)
    const base = baseline.files?.[file]?.[key]
    const cap = allowed(base)
    const byLine = [...list].sort((a, b) => a.line - b.line || a.character - b.character)
    if (list.length > cap) {
      const why = cap === 0 ? 'new finding' : `${list.length} found, the baseline allows ${cap}`
      failures.push({ file, key, why, findings: byLine })
      continue
    }
    fixed += cap - list.length
    const sizes = list.filter((f) => f.size !== null)
    if (!sizes.length) continue
    // Largest first on both sides. A baseline count with no sizes (hand-written) allows no size.
    const limits = Array.isArray(base) ? [...base].sort((a, b) => b - a) : []
    const ordered = [...sizes].sort((a, b) => b.size - a.size)
    const grew = ordered.filter((f, i) => f.size > (limits[i] ?? -Infinity))
    if (grew.length) {
      const pairs = ordered.map((f, i) => `${f.size} (baseline ${limits[i] ?? 'none'})`).join(', ')
      failures.push({ file, key, why: `grew: ${pairs}`, findings: grew.sort((a, b) => a.line - b.line) })
    } else {
      fixed += ordered.filter((f, i) => limits[i] !== undefined && f.size < limits[i]).length
    }
  }
  for (const [file, byKey] of Object.entries(baseline.files ?? {})) {
    for (const [key, value] of Object.entries(byKey)) {
      if (!seen.has(`${file}\0${key}`)) fixed += allowed(value)
    }
  }
  return { failures, fixed }
}

/** The report of compare()'s failures, one finding per line. */
export function render(failures) {
  const out = []
  for (const { file, key, why, findings } of failures) {
    out.push(`${file}: ${key.slice(0, key.indexOf(':'))}: ${why}`)
    for (const f of findings) out.push(`  ${file}:${f.line}:${f.character}: ${f.reason} (${f.rule})`)
  }
  return out.join('\n')
}

/** SwiftLint's own warnings and errors on stderr (a bad option, a rule that does not exist). */
export const configWarnings = (stderr) => stderr.split('\n').filter((line) => /^(warning|error):/.test(line.trim()))

/** Runs the pinned SwiftLint (JSON reporter) in `root`, with the .swiftlint.yml there. */
function runSwiftLint(root) {
  const r = spawnSync(SWIFTLINT, ['lint', '--quiet', '--reporter', 'json'], { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
  // SwiftLint exits non-zero whenever it finds anything; the JSON is what matters.
  const text = r.stdout?.trim() ?? ''
  if (r.error || !text.startsWith('[')) {
    throw new Error(`SwiftLint gave no JSON (${r.error?.message ?? `exit ${r.status}`}):\n${r.stderr ?? ''}Run bash scripts/lint/install-swiftlint.sh first.`)
  }
  // With --quiet, stderr holds only SwiftLint's own warnings, such as a
  // misspelled option in .swiftlint.yml, which it skips and carries on.
  const warnings = configWarnings(r.stderr ?? '')
  if (warnings.length) throw new Error(`SwiftLint warned about its setup; fix .swiftlint.yml:\n${warnings.join('\n')}`)
  return JSON.parse(text)
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

/** The value after `flag` in argv, else `fallback`. */
const option = (argv, flag, fallback) => (argv.includes(flag) ? argv[argv.indexOf(flag) + 1] : fallback)

export function main(argv, { stdout = process.stdout, stderr = process.stderr } = {}) {
  const root = path.resolve(option(argv, '--root', ROOT))
  const baselinePath = path.resolve(option(argv, '--baseline', BASELINE))
  const fromFile = option(argv, '--findings', null)
  let items
  try {
    items = fromFile ? readJson(fromFile) : runSwiftLint(root)
  } catch (error) {
    stderr.write(`swiftlint-baseline: ${error.message}\n`)
    return 2
  }
  const findings = toFindings(items, root)
  const prev = fs.existsSync(baselinePath) ? readJson(baselinePath) : { files: {} }
  const { failures, fixed } = compare(findings, prev)

  if (argv.includes('--update')) {
    if (failures.length && !argv.includes('--allow-increase')) {
      stderr.write(`${render(failures)}\n`)
      stderr.write(`swiftlint-baseline: refusing to add ${failures.length} finding group(s) to the baseline. Fix them, or pass --allow-increase (needs a reviewer).\n`)
      return 1
    }
    fs.writeFileSync(baselinePath, `${JSON.stringify(buildBaseline(findings), null, 2)}\n`)
    const before = Object.values(prev.files ?? {}).flatMap(Object.values).reduce((n, v) => n + allowed(v), 0)
    stdout.write(`swiftlint-baseline: ${before} -> ${findings.length} finding(s) in ${path.relative(process.cwd(), baselinePath)}\n`)
    return 0
  }

  if (failures.length) {
    stdout.write(`${render(failures)}\n`)
    stdout.write(`swiftlint: ${failures.length} finding group(s) not in the baseline (${path.relative(ROOT, baselinePath)}). Fix them; never re-baseline to get green.\n`)
    return 1
  }
  stdout.write(`swiftlint: ${findings.length} finding(s), all in the baseline`)
  stdout.write(fixed ? `; ${fixed} baselined finding(s) fixed or smaller: run bash scripts/lint/swiftlint.sh --update\n` : '\n')
  return 0
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2))
