#!/usr/bin/env node
// Summarizes the TypeScript packages' vitest v8 coverage into
// coverage-summary/core.json and coverage-summary/react-native.json
// (contract amendment A10).
//
// Each package makes two coverage runs:
//   vitest run --coverage               the gate: exclusions applied, 95%
//                                       thresholds, output in coverage/
//   vitest run --coverage --mode whole  every source file, no thresholds,
//                                       output in coverage/whole/
// `gate` comes from the first, so it is the number the thresholds checked.
// `whole` and `perFile` come from the second.
//
// Gate include globs, exclusions (with reasons) and thresholds are read from
// each package's vitest.config.ts, which Node loads with its built-in type
// stripping (Node 22.18 or later).
//
// Honesty checks, reported in the JSON and on stderr:
//   - source files under the include globs that are missing from the whole
//     run ("unmeasured").
//   - every v8/c8/istanbul ignore comment under the include globs, with its
//     reason text. An ignore without a reason is flagged.
//
// Usage:
//   node scripts/coverage/ts.mjs [--run]
// --run deletes each package's coverage/ and makes both coverage runs first,
// so the summary can only come from this run. `runs` records both exit codes.
// Without --run the script reads the output already on disk and `runs` is
// null. Summaries are written even when a gate is under 95%.
//
// Exit code 1 means a test run failed, the gate run failed for a reason other
// than its thresholds, the gate's exit code disagrees with its numbers, or
// coverage output is missing or older than the run. A gate under 95% alone
// exits 0; `gate.thresholdsMet` says whether it passed.

import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const OUT_DIR = path.join(REPO, 'coverage-summary')
const TARGET_PCT = 95
const SOURCE_FILE = /\.(?:ts|tsx|js|jsx|mjs|cjs)$/
const IGNORE_HINT = /(?:\/\/|\/\*)\s*(?:v8|c8|istanbul)\s+ignore\s+([a-z]+)(?:\s+\d+)?\s*(.*?)\s*(?:\*\/|$)/

const PACKAGES = [
  {
    platform: 'core',
    dir: 'core',
    notes: [],
  },
  {
    platform: 'react-native',
    dir: 'react-native',
    notes: [
      'react-native is a test stub (react-native/test/stubs). Native view behavior is not measured here.',
      '@sellwild/sdk-core is aliased to core/src in tests. Its files count in core.json, not here.',
    ],
  },
]

const COMMON_NOTES = [
  'regions is null: V8 coverage of TypeScript has lines, branches, functions and statements, not regions.',
  'Counts use vitest experimentalAstAwareRemapping: lines and branches come from the source AST, so comments and type-only lines are not counted, and branches in functions that never ran still count as missed.',
  'gate comes from `vitest run --coverage`, the run that enforces the 95% thresholds. whole and perFile come from `vitest run --coverage --mode whole`, which applies no exclusions.',
]

const RUNS = [
  { args: ['run', '--coverage'], summary: 'coverage/coverage-summary.json' },
  { args: ['run', '--coverage', '--mode', 'whole'], summary: 'coverage/whole/coverage-summary.json' },
]

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

function metric(m) {
  return { covered: m.covered, total: m.total, pct: m.pct }
}

function totals(summary) {
  const t = summary.total
  return { lines: metric(t.lines), branches: metric(t.branches), regions: null, functions: metric(t.functions) }
}

function walk(dir) {
  if (!fs.existsSync(dir)) return []
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name)
    return entry.isDirectory() ? walk(full) : [full]
  })
}

function matchesAny(file, globs) {
  return globs.some((glob) => path.matchesGlob(file, glob))
}

// The directory part of a glob before its first wildcard: 'src/**' -> 'src'.
function globRoot(glob) {
  const parts = glob.split('/')
  const firstWild = parts.findIndex((part) => /[*?[{]/.test(part))
  return parts.slice(0, firstWild === -1 ? parts.length - 1 : firstWild).join('/')
}

// Source files on disk under the include globs, package-relative.
function sourceFiles(pkgDir, include) {
  const roots = [...new Set(include.map(globRoot))]
  const files = roots.flatMap((root) => walk(path.join(pkgDir, root)))
  return [...new Set(files.map((file) => path.relative(pkgDir, file)))]
    .filter((file) => SOURCE_FILE.test(file) && !file.endsWith('.d.ts'))
    .filter((file) => matchesAny(file, include))
    .sort()
}

function ignoreHints(pkgDir, files) {
  const hints = []
  for (const file of files) {
    const lines = fs.readFileSync(path.join(pkgDir, file), 'utf8').split('\n')
    lines.forEach((text, index) => {
      const m = IGNORE_HINT.exec(text)
      if (!m) return
      const reason = m[2].replace(/^(?:--|:)\s*/, '').replace(/@preserve/g, '').trim()
      hints.push({ path: file, line: index + 1, directive: m[1], reason: reason || null })
    })
  }
  return hints
}

// Line numbers with no executed statement, as istanbul counts lines: a line
// is covered when any statement that starts on it ran.
function missedLines(fileCoverage) {
  const hits = new Map()
  for (const [id, loc] of Object.entries(fileCoverage.statementMap)) {
    const line = loc.start.line
    hits.set(line, Math.max(hits.get(line) ?? 0, fileCoverage.s[id]))
  }
  const missed = [...hits].filter(([, count]) => count === 0).map(([line]) => line).sort((a, b) => a - b)
  const ranges = []
  for (const line of missed) {
    const last = ranges[ranges.length - 1]
    if (last && line === last[1] + 1) last[1] = line
    else ranges.push([line, line])
  }
  return ranges.map(([a, b]) => (a === b ? `${a}` : `${a}-${b}`)).join(',')
}

async function summarize(pkg, run) {
  const pkgDir = path.join(REPO, pkg.dir)
  const vitestBin = path.join(pkgDir, 'node_modules', '.bin', 'vitest')
  // fatal: no trustworthy summary (tests failed, output missing).
  // warnings: honesty checks that are reported but do not fail the script.
  const fatal = []
  const warnings = []
  const commands = RUNS.map((r) => `cd ${pkgDir} && node_modules/.bin/vitest ${r.args.join(' ')}`)

  let tests = null
  let runs = null
  const startedMs = Date.now()
  if (run) {
    if (!fs.existsSync(vitestBin)) {
      return { fatal: [`${pkg.dir}: vitest is not installed. Run npm install in ${pkgDir}.`], warnings }
    }
    // Output left by an earlier run must not pass for this one's.
    fs.rmSync(path.join(pkgDir, 'coverage'), { recursive: true, force: true })
    const [gateRun, wholeRun] = RUNS.map((r) => spawnSync(vitestBin, r.args, { cwd: pkgDir, stdio: 'inherit' }))
    console.log(`${pkg.dir}: gate run exit ${gateRun.status}, whole run exit ${wholeRun.status}`)
    runs = {
      gate: { exitCode: gateRun.status, signal: gateRun.signal, error: gateRun.error?.message ?? null },
      whole: { exitCode: wholeRun.status, signal: wholeRun.signal, error: wholeRun.error?.message ?? null },
    }
    // The whole run has no thresholds, so its exit code is the tests' result.
    tests = { exitCode: wholeRun.status, passed: wholeRun.status === 0 }
    if (!tests.passed) fatal.push(`${pkg.dir}: tests failed (whole run exit ${wholeRun.status}, signal ${wholeRun.signal})`)
    if (gateRun.status === null) {
      fatal.push(`${pkg.dir}: gate run did not finish (signal ${gateRun.signal}, ${gateRun.error?.message ?? 'no error'})`)
    }
  }

  const [gateFile, wholeFile] = RUNS.map((r) => path.join(pkgDir, r.summary))
  const wholeFinalFile = path.join(pkgDir, 'coverage/whole/coverage-final.json')
  const outputs = [gateFile, wholeFile, wholeFinalFile]
  const missing = outputs.filter((file) => !fs.existsSync(file))
  for (const file of missing) fatal.push(`${pkg.dir}: missing ${path.relative(REPO, file)}`)
  if (missing.length) return { fatal, warnings }
  if (run) {
    const stale = outputs.filter((file) => fs.statSync(file).mtimeMs < startedMs)
    for (const file of stale) fatal.push(`${pkg.dir}: ${path.relative(REPO, file)} is older than this run`)
    if (stale.length) return { fatal, warnings }
  }

  const config = await import(pathToFileURL(path.join(pkgDir, 'vitest.config.ts')).href)
  const include = config.coverageInclude
  const excluded = config.coverageExclusions
  for (const e of excluded) {
    if (!e.reason) warnings.push(`${pkg.dir}: exclusion ${e.path} has no reason`)
  }
  // The thresholds `vitest run --coverage` enforces (mode 'test' is its default).
  const userConfig = typeof config.default === 'function' ? await config.default({ mode: 'test', command: 'serve' }) : config.default
  const thresholds = userConfig?.test?.coverage?.thresholds ?? null
  if (!thresholds) fatal.push(`${pkg.dir}: vitest.config.ts sets no coverage thresholds for the gate run`)

  const gateSummary = readJson(gateFile)
  const under = Object.entries(thresholds ?? {})
    .filter(([key, min]) => typeof min === 'number' && gateSummary.total[key].pct < min)
    .map(([key]) => key)
  const thresholdsMet = thresholds ? under.length === 0 : null
  if (runs && runs.gate.exitCode !== null && tests.passed) {
    // With the tests passing, the gate run fails exactly when a threshold does.
    if (runs.gate.exitCode !== 0 && thresholdsMet) {
      fatal.push(`${pkg.dir}: gate run exit ${runs.gate.exitCode} with every threshold met`)
    }
    if (runs.gate.exitCode === 0 && thresholdsMet === false) {
      fatal.push(`${pkg.dir}: gate run exit 0 but under its thresholds: ${under.join(', ')}`)
    }
  }
  const wholeSummary = readJson(wholeFile)
  const wholeFinal = readJson(wholeFinalFile)
  const rel = (abs) => path.relative(pkgDir, abs)
  const gateFiles = new Set(Object.keys(gateSummary).filter((k) => k !== 'total').map(rel))

  const onDisk = sourceFiles(pkgDir, include)
  const measured = new Set(Object.keys(wholeSummary).filter((k) => k !== 'total').map(rel))
  const unmeasured = onDisk.filter((file) => !measured.has(file))
  const isExcluded = (file) => matchesAny(file, excluded.map((e) => e.path))
  const gateUnmeasured = unmeasured.filter((file) => !isExcluded(file))
  for (const file of unmeasured) warnings.push(`${pkg.dir}: not in coverage output: ${file}`)

  const ignoredLines = ignoreHints(pkgDir, onDisk)
  for (const hint of ignoredLines) {
    if (!hint.reason && hint.directive !== 'stop') {
      warnings.push(`${pkg.dir}: ignore comment without a reason: ${hint.path}:${hint.line}`)
    }
  }

  const perFile = Object.entries(wholeSummary)
    .filter(([key]) => key !== 'total')
    .map(([abs, m]) => ({
      path: rel(abs),
      lines: m.lines.pct,
      branches: m.branches.pct,
      functions: m.functions.pct,
      inGate: gateFiles.has(rel(abs)),
      linesCovered: m.lines.covered,
      linesTotal: m.lines.total,
      missedLines: wholeFinal[abs] ? missedLines(wholeFinal[abs]) : null,
    }))
    .sort((a, b) => a.path.localeCompare(b.path))

  const vitestVersion = readJson(path.join(pkgDir, 'node_modules/vitest/package.json')).version
  const v8Version = readJson(path.join(pkgDir, 'node_modules/@vitest/coverage-v8/package.json')).version
  const summary = {
    platform: pkg.platform,
    generatedAt: new Date().toISOString(),
    tool: `vitest ${vitestVersion} + @vitest/coverage-v8 ${v8Version} (experimentalAstAwareRemapping)`,
    commands,
    gate: { include, ...totals(gateSummary), unmeasured: gateUnmeasured, thresholds, thresholdsMet, under },
    whole: { include, ...totals(wholeSummary), unmeasured },
    excluded,
    ignoredLines,
    perFile,
    tests,
    runs,
    notes: [...COMMON_NOTES, ...pkg.notes],
  }

  fs.mkdirSync(OUT_DIR, { recursive: true })
  const outFile = path.join(OUT_DIR, `${pkg.platform}.json`)
  fs.writeFileSync(outFile, JSON.stringify(summary, null, 2) + '\n')

  const g = summary.gate
  const underTarget = ['lines', 'branches', 'functions'].filter((k) => g[k].pct < TARGET_PCT)
  console.log(
    `${path.relative(REPO, outFile)}: gate lines ${g.lines.pct}%, branches ${g.branches.pct}%, functions ${g.functions.pct}%` +
      (underTarget.length ? ` (under ${TARGET_PCT}%: ${underTarget.join(', ')})` : ` (meets ${TARGET_PCT}%)`),
  )
  return { fatal, warnings }
}

const run = process.argv.includes('--run')
let failed = false
for (const pkg of PACKAGES) {
  const { fatal, warnings } = await summarize(pkg, run)
  for (const message of [...fatal, ...warnings]) console.error(message)
  if (fatal.length) failed = true
}
process.exitCode = failed ? 1 : 0
