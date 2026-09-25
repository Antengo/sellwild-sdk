#!/usr/bin/env node
// Summarizes .timings/suites.jsonl: runs, median, p90, last, and phase medians
// per suite. A run whose starting load was over 2x the CPU count is counted
// separately as "loaded", since those numbers mostly measure the machine.
//
//   node tools/timings-report.mjs [--since 2026-09-24T12:00] [--suite ios]
import { readFileSync, existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const FILE = process.env.TIMINGS_FILE || path.join(ROOT, '.timings', 'suites.jsonl')
const argv = process.argv.slice(2)
const opt = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : null }
const since = opt('--since')
const only = opt('--suite')

if (!existsSync(FILE)) {
  console.log(`no timings yet (${path.relative(process.cwd(), FILE)})`)
  process.exit(0)
}
const rows = readFileSync(FILE, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l))
  .filter((r) => (!since || r.startedAt >= since) && (!only || r.suite.includes(only)))

const q = (sorted, p) => sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))] : null
const fmt = (s) => s == null ? '-' : s >= 60 ? `${(s / 60).toFixed(1)}m` : `${s.toFixed(1)}s`

const bySuite = new Map()
for (const r of rows) {
  if (!bySuite.has(r.suite)) bySuite.set(r.suite, [])
  bySuite.get(r.suite).push(r)
}
console.log(`${'suite'.padEnd(28)} ${'runs'.padStart(4)} ${'quiet'.padStart(5)} ${'median'.padStart(7)} ${'p90'.padStart(7)} ${'last'.padStart(7)} ${'fail'.padStart(4)}  phases (median, quiet runs)`)
for (const [suite, list] of [...bySuite].sort()) {
  const quiet = list.filter((r) => r.load1 == null || r.load1 <= 2 * (r.cpus || 8))
  const pool = quiet.length ? quiet : list
  const secs = pool.map((r) => r.seconds).filter((s) => s != null).sort((a, b) => a - b)
  const phaseNames = [...new Set(pool.flatMap((r) => Object.keys(r.phases || {})))]
  const phases = phaseNames.map((n) => {
    const v = pool.map((r) => r.phases?.[n]).filter((s) => s != null).sort((a, b) => a - b)
    return `${n} ${fmt(q(v, 0.5))}`
  }).join(', ')
  const last = list[list.length - 1]
  const fails = list.filter((r) => r.exit !== 0).length
  console.log(`${suite.padEnd(28)} ${String(list.length).padStart(4)} ${String(quiet.length).padStart(5)} ${fmt(q(secs, 0.5)).padStart(7)} ${fmt(q(secs, 0.9)).padStart(7)} ${fmt(last.seconds).padStart(7)} ${String(fails).padStart(4)}  ${phases}`)
}
