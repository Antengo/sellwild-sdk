#!/usr/bin/env node
// Coverage threshold check: the last step of `bash scripts/gate.sh --full`,
// and the step that fails each platform's CI job (.github/workflows/ci.yml).
// The `gate` block of every coverage-summary/*.json must reach its thresholds
// on lines, on branches (regions where a platform measures regions instead, as
// Swift does) and on functions, and must list no unmeasured file.
// The same file is in sellwild-sdk and sellwild-widget.
//
// Thresholds come from tools/coverage-thresholds.json (per platform, per
// metric) when it exists; a platform it does not list, or any platform when
// the file is absent or --target is given, uses one number for all metrics
// (95 by default).
//
//   node tools/coverage-gate.mjs                        <repo>/coverage-summary, tools/coverage-thresholds.json
//   node tools/coverage-gate.mjs --expect core,ios      also fail when a listed summary is missing
//   node tools/coverage-gate.mjs --only ios             check only these summaries (each must exist)
//   node tools/coverage-gate.mjs --dir <dir> --target <n> | --thresholds <file>
//
// Prints one line per summary. Exit 1 when a summary misses a threshold, lacks
// a metric, lists unmeasured files or cannot be read, or an expected summary
// is missing. Exit 2 on a usage error or an unreadable thresholds file.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const TARGET = 95
export const THRESHOLDS_FILE = 'tools/coverage-thresholds.json'

/**
 * The minimum for one metric. `target` is one number for every metric, or a
 * per-metric object; regions fall back to branches, anything missing to 95.
 * @param {number | Record<string, number>} target
 * @param {string} name lines, branches, regions or functions
 * @returns {number}
 */
export function minimumFor (target, name) {
  if (typeof target === 'number') return target
  const value = target?.[name] ?? (name === 'regions' ? target?.branches : undefined)
  return typeof value === 'number' ? value : TARGET
}

/**
 * The three A10 metrics of one gate block, as [name, metric] pairs. The middle
 * one is branches, or regions when the gate has regions and no branches.
 * @param {Record<string, any>} gate
 * @returns {Array<[string, { pct?: unknown } | null]>}
 */
export function metrics (gate) {
  const middle = gate.branches == null && gate.regions != null ? ['regions', gate.regions] : ['branches', gate.branches ?? null]
  return [['lines', gate.lines ?? null], /** @type {[string, any]} */ (middle), ['functions', gate.functions ?? null]]
}

/**
 * What is wrong with one summary, as text. Empty means it passes.
 * @param {unknown} summary a parsed coverage-summary/*.json
 * @param {number | Record<string, number>} [target] one number, or per metric
 * @returns {string[]}
 */
export function checkSummary (summary, target = TARGET) {
  const gate = summary && typeof summary === 'object' ? /** @type {Record<string, any>} */ (summary).gate : null
  if (!gate || typeof gate !== 'object') return ['no gate block']
  const problems = []
  for (const [name, metric] of metrics(gate)) {
    const min = minimumFor(target, name)
    if (typeof metric?.pct !== 'number') problems.push(`${name} not measured`)
    else if (metric.pct < min) problems.push(`${name} ${metric.pct}% is under ${min}%`)
  }
  if (Array.isArray(gate.unmeasured) && gate.unmeasured.length > 0) {
    problems.push(`unmeasured: ${gate.unmeasured.join(', ')}`)
  }
  return problems
}

/**
 * One row per summary in `dir`, plus one per expected name with no file.
 * `thresholds[name]` overrides `target` for that summary. With `only`, just
 * those summaries are read, and each one must exist.
 * @param {string} dir
 * @param {{ target?: number, thresholds?: Record<string, Record<string, number>>, expect?: string[], only?: string[] }} [options]
 * @returns {Array<{ name: string, line: string, problems: string[] }>}
 */
export function checkDir (dir, { target = TARGET, thresholds = {}, expect = [], only = [] } = {}) {
  let files = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort() : []
  if (only.length) files = files.filter((f) => only.includes(f.replace(/\.json$/, '')))
  const rows = []
  for (const name of [...new Set([...expect, ...only])]) {
    if (!files.includes(`${name}.json`)) rows.push({ name, line: '', problems: ['missing'] })
  }
  for (const file of files) {
    const name = file.replace(/\.json$/, '')
    let summary
    try {
      summary = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'))
    } catch (error) {
      rows.push({ name, line: '', problems: [`unreadable: ${error instanceof Error ? error.message : String(error)}`] })
      continue
    }
    const gate = summary && typeof summary === 'object' && summary.gate && typeof summary.gate === 'object' ? summary.gate : null
    const line = gate
      ? metrics(gate).map(([metric, value]) => `${metric} ${typeof value?.pct === 'number' ? `${value.pct}%` : '-'}`).join('  ')
      : ''
    rows.push({ name, line, problems: checkSummary(summary, thresholds[name] ?? target) })
  }
  if (rows.length === 0) rows.push({ name: path.basename(dir), line: '', problems: ['no coverage summaries'] })
  return rows
}

/**
 * @param {string[]} argv
 * @param {{ root?: string, out?: { write: (s: string) => unknown } }} [deps]
 * @returns {number} exit code
 */
export function main (argv, { root = ROOT, out = process.stdout } = {}) {
  let dir = path.join(root, 'coverage-summary')
  let target = TARGET
  let targetGiven = false
  let thresholdsFile = path.join(root, THRESHOLDS_FILE)
  let thresholdsGiven = false
  let expect = /** @type {string[]} */ ([])
  let only = /** @type {string[]} */ ([])
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i]
    const value = argv[i + 1]
    if (flag === '--dir' && value) dir = path.resolve(root, value)
    else if (flag === '--target' && value && Number.isFinite(Number(value))) { target = Number(value); targetGiven = true }
    else if (flag === '--thresholds' && value) { thresholdsFile = path.resolve(root, value); thresholdsGiven = true }
    else if (flag === '--expect' && value) expect = value.split(',').filter(Boolean)
    else if (flag === '--only' && value) only = value.split(',').filter(Boolean)
    else {
      out.write('usage: node tools/coverage-gate.mjs [--dir <dir>] [--target <pct> | --thresholds <file>] [--expect a,b] [--only a,b]\n')
      return 2
    }
    i++
  }
  if (targetGiven && thresholdsGiven) {
    out.write('coverage gate: --target and --thresholds cannot be combined\n')
    return 2
  }
  /** @type {Record<string, Record<string, number>>} */
  let thresholds = {}
  if (!targetGiven && (thresholdsGiven || fs.existsSync(thresholdsFile))) {
    try {
      thresholds = readThresholds(thresholdsFile)
    } catch (error) {
      out.write(`coverage gate: ${path.relative(root, thresholdsFile)}: ${error instanceof Error ? error.message : String(error)}\n`)
      return 2
    }
  }
  const rows = checkDir(dir, { target, thresholds, expect, only })
  const width = Math.max(...rows.map((row) => row.name.length))
  for (const row of rows) {
    const verdict = row.problems.length ? `FAIL: ${row.problems.join('; ')}` : 'pass'
    out.write(`${row.name.padEnd(width)}  ${row.line ? `${row.line}  ` : ''}${verdict}\n`)
  }
  const failed = rows.filter((row) => row.problems.length).length
  const what = Object.keys(thresholds).length ? 'their thresholds' : `${target}%`
  out.write(failed ? `coverage gate: ${failed} of ${rows.length} under ${what} or incomplete\n` : `coverage gate: all ${rows.length} at ${what} or more\n`)
  return failed ? 1 : 0
}

/**
 * Reads a thresholds file: { "<platform>": { "lines": n, "branches" | "regions": n, "functions": n } }.
 * Keys starting with `_` are comments. Throws on a malformed file.
 * @param {string} file
 * @returns {Record<string, Record<string, number>>}
 */
export function readThresholds (file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'))
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('not an object')
  /** @type {Record<string, Record<string, number>>} */
  const result = {}
  for (const [name, value] of Object.entries(raw)) {
    if (name.startsWith('_')) continue
    if (!value || typeof value !== 'object') throw new Error(`${name}: not an object`)
    for (const metric of ['lines', 'functions']) {
      if (typeof value[metric] !== 'number') throw new Error(`${name}: ${metric} is not a number`)
    }
    if (typeof value.branches !== 'number' && typeof value.regions !== 'number') throw new Error(`${name}: needs branches or regions`)
    result[name] = value
  }
  return result
}

const entry = process.argv[1]
if (entry && fs.existsSync(entry) && fs.realpathSync(entry) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  process.exitCode = main(process.argv.slice(2))
}
