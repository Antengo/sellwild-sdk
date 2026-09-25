#!/usr/bin/env node
// Coverage threshold check, the last step of `bash scripts/gate.sh --full`.
// The `gate` block of every coverage-summary/*.json must reach the target on
// lines, on branches (regions where a platform measures regions instead, as
// Swift does) and on functions, and must list no unmeasured file.
// The same file is in sellwild-sdk and sellwild-widget.
//
//   node tools/coverage-gate.mjs                        <repo>/coverage-summary, 95%
//   node tools/coverage-gate.mjs --expect core,ios      also fail when a listed summary is missing
//   node tools/coverage-gate.mjs --dir <dir> --target <n>
//
// Prints one line per summary. Exit 1 when a summary misses the target, lacks
// a metric, lists unmeasured files or cannot be read, or an expected summary
// is missing. Exit 2 on a usage error.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const TARGET = 95

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
 * @param {number} [target]
 * @returns {string[]}
 */
export function checkSummary (summary, target = TARGET) {
  const gate = summary && typeof summary === 'object' ? /** @type {Record<string, any>} */ (summary).gate : null
  if (!gate || typeof gate !== 'object') return ['no gate block']
  const problems = []
  for (const [name, metric] of metrics(gate)) {
    if (typeof metric?.pct !== 'number') problems.push(`${name} not measured`)
    else if (metric.pct < target) problems.push(`${name} ${metric.pct}% is under ${target}%`)
  }
  if (Array.isArray(gate.unmeasured) && gate.unmeasured.length > 0) {
    problems.push(`unmeasured: ${gate.unmeasured.join(', ')}`)
  }
  return problems
}

/**
 * One row per summary in `dir`, plus one per expected name with no file.
 * @param {string} dir
 * @param {{ target?: number, expect?: string[] }} [options]
 * @returns {Array<{ name: string, line: string, problems: string[] }>}
 */
export function checkDir (dir, { target = TARGET, expect = [] } = {}) {
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort() : []
  const rows = []
  for (const name of expect) {
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
    rows.push({ name, line, problems: checkSummary(summary, target) })
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
  let expect = /** @type {string[]} */ ([])
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i]
    const value = argv[i + 1]
    if (flag === '--dir' && value) dir = path.resolve(root, value)
    else if (flag === '--target' && value && Number.isFinite(Number(value))) target = Number(value)
    else if (flag === '--expect' && value) expect = value.split(',').filter(Boolean)
    else {
      out.write('usage: node tools/coverage-gate.mjs [--dir <dir>] [--target <pct>] [--expect a,b]\n')
      return 2
    }
    i++
  }
  const rows = checkDir(dir, { target, expect })
  const width = Math.max(...rows.map((row) => row.name.length))
  for (const row of rows) {
    const verdict = row.problems.length ? `FAIL: ${row.problems.join('; ')}` : 'pass'
    out.write(`${row.name.padEnd(width)}  ${row.line ? `${row.line}  ` : ''}${verdict}\n`)
  }
  const failed = rows.filter((row) => row.problems.length).length
  out.write(failed ? `coverage gate: ${failed} of ${rows.length} under ${target}% or incomplete\n` : `coverage gate: all ${rows.length} at ${target}% or more\n`)
  return failed ? 1 : 0
}

const entry = process.argv[1]
if (entry && fs.existsSync(entry) && fs.realpathSync(entry) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  process.exitCode = main(process.argv.slice(2))
}
