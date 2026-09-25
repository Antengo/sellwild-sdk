#!/usr/bin/env node
// Compiler-warnings ratchet for the Android SDK (android/): compiles the main
// and unit-test sources from scratch, counts the Kotlin (and javac) warnings
// per file, and compares them with kotlin-warnings.baseline.json next to this
// script. A file may only go down, like contracts/scripts/print-gate.mjs.
//
//   node scripts/lint/kotlin-warnings.mjs            fresh compile, exit 1 on any increase
//   node scripts/lint/kotlin-warnings.mjs --update   rewrite the baseline with today's counts
//                                                    (refuses increases unless --allow-increase)
//   node scripts/lint/kotlin-warnings.mjs --log <f>  read a saved `gradlew --console=plain` log
//                                                    instead of compiling (same freshness check)
//
// Fresh means every compile task below ran. The script passes --rerun to each,
// and fails when a task line says UP-TO-DATE, FROM-CACHE, NO-SOURCE or SKIPPED
// or is missing: an up-to-date compile prints no warnings, which would look
// like zero. (Kotlin's incremental compiler treats a --rerun as a full build.)
//
// Env: JAVA_HOME (a JDK 17; found like scripts/coverage/android.sh when unset),
// GRADLE_OPTS (defaults to -Dorg.gradle.workers.max=2).
// The full Gradle log goes to android/build/reports/kotlin-warnings/gradle.log.

import { execFileSync, spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
export const SDK_ROOT = path.resolve(HERE, '../..')
export const ANDROID_DIR = path.join(SDK_ROOT, 'android')
export const BASELINE_PATH = path.join(HERE, 'kotlin-warnings.baseline.json')
const LOG_PATH = path.join(ANDROID_DIR, 'build/reports/kotlin-warnings/gradle.log')
const DEFAULT_JDK17 = '/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home'

/** The compile tasks of main + unit-test sources. Main has no Java, so no javac task for it. */
export const TASKS = ['compileDebugKotlin', 'compileDebugUnitTestKotlin', 'compileDebugUnitTestJavaWithJavac']

/** Key for a warning that names no file (compiler option warnings and the like). */
export const NO_FILE = '(no file)'

// Kotlin 2.x: "w: file:///abs/File.kt:12:5 message"
const KOTLIN_URI = /^w: (file:\/\/\S+?\.kts?):(\d+):(\d+) (.*)$/
// Kotlin 1.x: "w: /abs/File.kt: (12, 5): message"
const KOTLIN_PATH = /^w: (\/.+?\.kts?): \((\d+), (\d+)\): (.*)$/
// Kotlin, no file: "w: message"
const KOTLIN_GLOBAL = /^w: (.*)$/
// javac: "/abs/File.java:12: warning: [deprecation] message"
const JAVAC = /^(\/.+?\.java):(\d+): warning: (.*)$/
// javac, no file: "warning: [options] message"
const JAVAC_GLOBAL = /^warning: (.*)$/
// "> Task :compileDebugKotlin" or "> Task :compileDebugKotlin UP-TO-DATE"
const TASK_LINE = /^> Task (:\S+)(?: (.+))?$/

function relative(abs, root) {
  const rel = path.relative(root, abs)
  return rel.startsWith('..') || path.isAbsolute(rel) ? abs : rel.split(path.sep).join('/')
}

const taskName = (taskPath) => taskPath.replace(/^.*:/, '')

/**
 * Warnings in a Gradle log: [{ file, line, col, message, task }]. `file` is
 * relative to `root` (or NO_FILE); `task` is the name from the last
 * "> Task :name" line above it. Only lines under one of `tasks` count (null:
 * every line), so a configuration-time "w:" from the Kotlin Gradle plugin or
 * a "warning:" from another tool is not a compiler warning. Plain console
 * output is grouped: Gradle repeats the task header when output switches task.
 */
export function parseWarnings(log, { root = SDK_ROOT, tasks = TASKS } = {}) {
  const out = []
  let task = null
  for (const raw of log.split(/\r?\n/)) {
    const lineText = raw.trimEnd()
    const t = TASK_LINE.exec(lineText)
    if (t) { task = taskName(t[1]); continue }
    if (tasks && !tasks.includes(task)) continue
    let m
    if ((m = KOTLIN_URI.exec(lineText))) {
      out.push({ file: relative(fileURLToPath(m[1]), root), line: +m[2], col: +m[3], message: m[4], task })
    } else if ((m = KOTLIN_PATH.exec(lineText))) {
      out.push({ file: relative(m[1], root), line: +m[2], col: +m[3], message: m[4], task })
    } else if ((m = KOTLIN_GLOBAL.exec(lineText))) {
      out.push({ file: NO_FILE, line: 0, col: 0, message: m[1], task })
    } else if ((m = JAVAC.exec(lineText))) {
      out.push({ file: relative(m[1], root), line: +m[2], col: 0, message: m[3], task })
    } else if ((m = JAVAC_GLOBAL.exec(lineText))) {
      out.push({ file: NO_FILE, line: 0, col: 0, message: m[1], task })
    }
  }
  return out
}

/**
 * Problems that make the log unfit to count from: a task that did not run
 * (UP-TO-DATE, FROM-CACHE, NO-SOURCE, SKIPPED, ...) or never appeared.
 */
export function freshnessProblems(log, tasks = TASKS) {
  const outcome = new Map()
  for (const raw of log.split(/\r?\n/)) {
    const t = TASK_LINE.exec(raw.trimEnd())
    if (t) outcome.set(taskName(t[1]), t[2] ?? null)
  }
  const problems = []
  for (const name of tasks) {
    if (!outcome.has(name)) problems.push(`${name} did not run (no "> Task :${name}" line)`)
    else if (outcome.get(name) !== null) problems.push(`${name} was ${outcome.get(name)}, not compiled`)
  }
  return problems
}

/** { total, files: { file: count } } with files sorted. */
export function countByFile(warnings) {
  const files = {}
  for (const w of warnings) files[w.file] = (files[w.file] ?? 0) + 1
  const sorted = {}
  for (const k of Object.keys(files).sort()) sorted[k] = files[k]
  return { total: warnings.length, files: sorted }
}

/** Compare counts with a baseline. Returns { increases, decreases }. */
export function compare(counts, baseline) {
  const increases = []
  const decreases = []
  const base = baseline.files ?? {}
  for (const [file, found] of Object.entries(counts.files)) {
    const allowed = base[file] ?? 0
    if (found > allowed) increases.push({ file, allowed, found })
    else if (found < allowed) decreases.push({ file, allowed, found })
  }
  for (const [file, allowed] of Object.entries(base)) {
    if (!(file in counts.files) && allowed > 0) decreases.push({ file, allowed, found: 0 })
  }
  return { increases, decreases }
}

export function buildBaseline(counts) {
  return {
    description: 'Compiler warnings per file from a fresh compile of android/ main + unit-test sources (scripts/lint/kotlin-warnings.mjs). The gate fails when a count goes up or a file not listed here has a warning. Lower a count in the same change that removes a warning: node scripts/lint/kotlin-warnings.mjs --update.',
    tasks: TASKS,
    total: counts.total,
    files: counts.files,
  }
}

function isJdk17(home) {
  if (!home) return false
  try {
    const out = spawnSync(path.join(home, 'bin/java'), ['-version'], { encoding: 'utf8' })
    return /version "17/.test(`${out.stderr}${out.stdout}`)
  } catch {
    return false
  }
}

function findJdk17() {
  if (isJdk17(process.env.JAVA_HOME)) return process.env.JAVA_HOME
  try {
    const home = execFileSync('/usr/libexec/java_home', ['-v', '17'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
    if (isJdk17(home)) return home
  } catch {
    // No java_home helper (not macOS) or no JDK 17 registered: try the default path.
  }
  return isJdk17(DEFAULT_JDK17) ? DEFAULT_JDK17 : null
}

/** Runs the fresh compile. Returns { status, log }. */
function compile() {
  const javaHome = findJdk17()
  if (!javaHome) {
    process.stderr.write('kotlin-warnings: no JDK 17 found. Set JAVA_HOME to a JDK 17.\n')
    return { status: 127, log: '' }
  }
  const env = { ...process.env, JAVA_HOME: javaHome }
  if (env.GRADLE_OPTS === undefined) env.GRADLE_OPTS = '-Dorg.gradle.workers.max=2'
  const args = ['-p', ANDROID_DIR, '--console=plain', ...TASKS.flatMap((t) => [t, '--rerun'])]
  const r = spawnSync(path.join(ANDROID_DIR, 'gradlew'), args, { env, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 })
  const log = `${r.stdout ?? ''}${r.stderr ?? ''}`
  fs.mkdirSync(path.dirname(LOG_PATH), { recursive: true })
  fs.writeFileSync(LOG_PATH, log)
  return { status: r.status ?? 1, log }
}

function main(argv) {
  const logArg = argv.indexOf('--log')
  let log
  if (logArg >= 0) {
    log = fs.readFileSync(argv[logArg + 1], 'utf8')
  } else {
    const r = compile()
    log = r.log
    if (r.status !== 0) {
      process.stdout.write(log.split('\n').slice(-40).join('\n') + '\n')
      process.stderr.write(`kotlin-warnings: Gradle failed (exit ${r.status}); full log: ${path.relative(process.cwd(), LOG_PATH)}\n`)
      process.exitCode = r.status
      return
    }
  }
  const stale = freshnessProblems(log)
  if (stale.length) {
    for (const p of stale) process.stderr.write(`kotlin-warnings: ${p}\n`)
    process.stderr.write('kotlin-warnings: not a fresh compile, so the count would be wrong.\n')
    process.exitCode = 1
    return
  }
  const warnings = parseWarnings(log)
  const counts = countByFile(warnings)
  process.stdout.write(`kotlin-warnings: ${counts.total} warning(s) in ${Object.keys(counts.files).length} file(s)\n`)

  if (argv.includes('--update')) {
    if (fs.existsSync(BASELINE_PATH) && !argv.includes('--allow-increase')) {
      const { increases } = compare(counts, JSON.parse(fs.readFileSync(BASELINE_PATH, 'utf8')))
      if (increases.length) {
        for (const x of increases) process.stderr.write(`refusing to raise ${x.file}: ${x.allowed} -> ${x.found}\n`)
        process.exitCode = 1
        return
      }
    }
    fs.writeFileSync(BASELINE_PATH, JSON.stringify(buildBaseline(counts), null, 2) + '\n')
    process.stdout.write(`wrote ${path.relative(process.cwd(), BASELINE_PATH)}\n`)
    return
  }

  const baseline = JSON.parse(fs.readFileSync(BASELINE_PATH, 'utf8'))
  const { increases, decreases } = compare(counts, baseline)
  for (const x of increases) {
    process.stdout.write(`FAIL ${x.file}: allowed ${x.allowed}, found ${x.found}\n`)
    for (const w of warnings.filter((w) => w.file === x.file)) {
      process.stdout.write(`     ${w.line ? `line ${w.line}: ` : ''}${w.message}\n`)
    }
  }
  if (decreases.length) process.stdout.write(`${decreases.length} count(s) went down; run --update to lock them in\n`)
  process.exitCode = increases.length ? 1 : 0
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2))
